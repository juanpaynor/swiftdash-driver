import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/delivery.dart';
import '../models/driver.dart';
import '../services/realtime_service.dart';
import '../services/auth_service.dart';
import '../services/driver_location_service.dart';
import '../services/ably_service.dart';
import '../services/chat_service.dart';
import '../services/idle_location_update_service.dart';
import '../services/background_location_service.dart';
import '../services/delivery_offer_notification_service.dart';
import '../helpers/battery_optimization_helper.dart';
import '../core/supabase_config.dart';

/// Service to manage the complete driver delivery flow and state transitions
class DriverFlowService {
  static final DriverFlowService _instance = DriverFlowService._internal();
  factory DriverFlowService() => _instance;
  DriverFlowService._internal();

  final RealtimeService _realtimeService = RealtimeService();
  final AuthService _authService = AuthService();
  final IdleLocationUpdateService _idleLocationService = IdleLocationUpdateService();

  Driver? _currentDriver;
  Delivery? _activeDelivery;
  bool _isLocationTrackingActive = false;

  // Getters
  Driver? get currentDriver => _currentDriver;
  Delivery? get activeDelivery => _activeDelivery;
  bool get isLocationTrackingActive => _isLocationTrackingActive;
  bool get hasActiveDelivery => _activeDelivery != null;

  /// Initialize driver flow service
  Future<void> initialize() async {
    try {
      _currentDriver = await _authService.getCurrentDriverProfile();
      if (_currentDriver != null) {
        await _loadActiveDelivery();
        await _initializeRealtimeSubscriptions();
      }
    } catch (e) {
      print('❌ Error initializing driver flow service: $e');
    }
  }

  /// Load any active delivery for this driver
  Future<void> _loadActiveDelivery() async {
    if (_currentDriver == null) return;

    try {
      final activeDeliveries = await _realtimeService.getPendingDeliveries(_currentDriver!.id);
      if (activeDeliveries.isNotEmpty) {
        _activeDelivery = activeDeliveries.first;
        
        // ✅ Business Dispatch Detection (Nov 9, 2025)
        // Check if this is a new business dispatch assignment
        if (_activeDelivery!.isNewBusinessAssignment) {
          print('🏢 *** BUSINESS DISPATCH DETECTED ON APP STARTUP ***');
          print('🏢 Business ID: ${_activeDelivery!.businessId}');
          print('🏢 Driver Source: ${_activeDelivery!.driverSource}');
          print('🏢 Assignment Type: ${_activeDelivery!.assignmentType}');
          print('🏢 Delivery instructions: ${_activeDelivery!.deliveryInstructions ?? "none"}');
          print('🏢 Pickup instructions: ${_activeDelivery!.pickupInstructions ?? "none"}');
        }
        
        // Resume location tracking if delivery is in progress
        // ✅ FIX: Include all active statuses including pickup_arrived and at_destination
        // 🔒 CRITICAL: Only start if NOT already tracking to prevent infinite restart loop
        if (!_isLocationTrackingActive &&
            (_activeDelivery!.status == DeliveryStatus.driverAssigned ||
             _activeDelivery!.status == DeliveryStatus.goingToPickup ||
             _activeDelivery!.status == DeliveryStatus.pickupArrived ||
             _activeDelivery!.status == DeliveryStatus.packageCollected ||
             _activeDelivery!.status == DeliveryStatus.goingToDestination ||
             _activeDelivery!.status == DeliveryStatus.atDestination)) {
          print('🔄 Resuming location tracking for active delivery: ${_activeDelivery!.id}');
          await _startLocationTracking();
        } else if (_isLocationTrackingActive) {
          print('✅ Location tracking already active - skipping restart');
        }
      } else {
        // No active delivery found - clear the state
        _activeDelivery = null;
        // Stop tracking if still active
        if (_isLocationTrackingActive) {
          await _stopLocationTracking();
        }
      }
    } catch (e) {
      print('❌ Error loading active delivery: $e');
    }
  }
  
  /// Refresh active delivery (public method for manual refresh after accepting)
  Future<void> refreshActiveDelivery() async {
    print('🔄 Manually refreshing active delivery...');
    await _loadActiveDelivery();
    print('🔄 Active delivery refreshed: ${_activeDelivery?.id ?? "none"}');
  }

  /// Initialize realtime subscriptions
  Future<void> _initializeRealtimeSubscriptions() async {
    if (_currentDriver == null) return;

    try {
      await _realtimeService.initializeRealtimeSubscriptions(_currentDriver!.id);
    } catch (e) {
      print('❌ Error initializing realtime subscriptions: $e');
    }
  }

  /// Handle driver going online
  Future<bool> goOnline(BuildContext context) async {
    if (_currentDriver == null) return false;

    try {
      // Request location permissions first
      final hasPermission = await _requestLocationPermission(context);
      if (!hasPermission) {
        _showError(context, 'Location permission is required to accept deliveries');
        return false;
      }

      // Update driver online status in both tables (includes location update)
      await _authService.updateOnlineStatus(true);
      
      // 🔧 PERFORMANCE FIX: Initialize Ably in background (non-blocking)
      // Don't await - let it connect in background while driver sees online status
      _initializeAblyInBackground();
      
      // ✅ FIX: DON'T broadcast location when idle (no active delivery)
      // Location will be broadcast ONLY when driver has an active delivery
      // Customer app doesn't need constant location updates for available drivers
      print('📍 Location broadcasting will start when delivery is accepted');

      // ✅ START: Idle location updates for accurate pairing
      // This updates driver_profiles table periodically (5 min) and when driver moves (>100m)
      await _idleLocationService.startIdleLocationUpdates(_currentDriver!.id);
      print('📍 Started idle location updates for driver pairing accuracy');

      // 🚨 START: Foreground service to keep app alive when online
      try {
        await BackgroundLocationService.startOnlineStatusService(
          driverId: _currentDriver!.id,
        );
        print('✅ Foreground service started - app will stay online in background');
      } catch (e) {
        print('⚠️ Failed to start foreground service: $e');
        // Continue without foreground service - app may be killed in background
      }

      // Reload driver profile to get updated status with location
      _currentDriver = await _authService.getCurrentDriverProfile();

      // 🔋 CRITICAL: Check battery optimization before going online
      // Only show warning once per session to avoid being annoying
      try {
        final hasExemption = await BatteryOptimizationHelper.checkAndRequestOnGoingOnline(context);
        if (!hasExemption) {
          print('⚠️ Battery optimization not disabled');
          // Show subtle warning instead of blocking dialog
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  '⚠️ Battery optimization enabled - you may miss delivery offers when idle',
                  style: TextStyle(fontSize: 13),
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 5),
                action: SnackBarAction(
                  label: 'Fix',
                  textColor: Colors.white,
                  onPressed: () {
                    BatteryOptimizationHelper.requestBatteryOptimizationExemption(context);
                  },
                ),
              ),
            );
          }
        } else {
          print('✅ Battery optimization disabled - background notifications will work reliably');
        }
      } catch (e) {
        print('⚠️ Failed to check battery optimization: $e');
        // Continue anyway
      }

      // �🚨 CRITICAL FIX: Initialize realtime subscriptions to receive delivery offers
      try {
        await _initializeRealtimeSubscriptions();
        print('🚨 ✅ CRITICAL: Realtime subscriptions initialized - driver can now receive delivery offers!');
      } catch (e) {
        print('🚨 ❌ CRITICAL ERROR: Failed to initialize realtime subscriptions - driver will NOT receive offers: $e');
        _showError(context, 'Warning: You may not receive delivery offers. Please try going offline and online again.');
      }

      // 🔔 Start listening for delivery offers with background notifications
      try {
        await DeliveryOfferNotificationService.startListening(_currentDriver!.id);
        print('🔔 ✅ Started listening for delivery offers with notifications');
      } catch (e) {
        print('⚠️ Failed to start delivery offer notifications: $e');
        // Continue without background notifications - foreground still works
      }

      _showSuccess(context, 'You are now online and available for deliveries');
      return true;
    } catch (e) {
      _showError(context, 'Failed to go online: $e');
      return false;
    }
  }

  /// Handle driver going offline
  Future<bool> goOffline(BuildContext context) async {
    if (_currentDriver == null) return false;

    // Check if driver has active delivery
    if (hasActiveDelivery) {
      final confirmed = await _showConfirmDialog(
        context,
        'Active Delivery',
        'You have an active delivery. Going offline will not cancel it, but you won\'t receive new offers. Continue?',
      );
      if (!confirmed) return false;
    }

    try {
      // Stop Ably location tracking first
      DriverLocationService().stopTracking();
      print('📍 Stopped Ably location tracking');

      // Stop idle location updates
      _idleLocationService.stopIdleLocationUpdates();
      print('📍 Stopped idle location updates');

      // 🔔 Stop listening for delivery offers
      try {
        await DeliveryOfferNotificationService.stopListening();
        print('🔔 Stopped listening for delivery offers');
      } catch (e) {
        print('⚠️ Failed to stop delivery offer notifications: $e');
      }

      // 🚨 STOP: Foreground service when going offline
      try {
        await BackgroundLocationService.stopOnlineStatusService();
        print('✅ Foreground service stopped');
      } catch (e) {
        print('⚠️ Failed to stop foreground service: $e');
      }

      // Update driver offline status in both tables
      await _authService.updateOnlineStatus(false);
      // Reload driver profile to get updated status
      _currentDriver = await _authService.getCurrentDriverProfile();

      _showSuccess(context, 'You are now offline');
      return true;
    } catch (e) {
      _showError(context, 'Failed to go offline: $e');
      return false;
    }
  }

  /// Accept a delivery offer (NEW WORKFLOW)
  Future<bool> acceptDeliveryOffer(BuildContext context, Delivery delivery) async {
    if (_currentDriver == null) return false;

    try {
      // Ensure location tracking is ready
      final hasPermission = await _requestLocationPermission(context);
      if (!hasPermission) {
        _showError(context, 'Location permission is required to accept deliveries');
        return false;
      }

      // Accept the delivery offer (NEW WORKFLOW)
      final success = await _realtimeService.acceptDeliveryOfferNew(delivery.id, _currentDriver!.id);
      
      if (success) {
        _activeDelivery = delivery.copyWith(
          driverId: _currentDriver!.id,
          status: DeliveryStatus.driverAssigned,
        );

        // Start location tracking
        await _startLocationTracking();

        // 🚀 AUTOMATIC STATUS UPDATE: Send "going_to_pickup" to customer app
        // Per STATUS_UPDATE_FLOW_EXPLANATION.md - customer sees "Driver heading to pickup"
        print('📢 Auto-sending going_to_pickup status to customer...');
        await updateDeliveryStatus(context, DeliveryStatus.goingToPickup);

        // Show success and navigation options
        _showDeliveryAcceptedDialog(context, delivery);
        
        return true;
      } else {
        _showError(context, 'Delivery offer expired or was taken by another driver');
        return false;
      }
    } catch (e) {
      _showError(context, 'Failed to accept delivery offer: $e');
      return false;
    }
  }

  /// Decline a delivery offer (NEW WORKFLOW)
  Future<bool> declineDeliveryOffer(BuildContext context, Delivery delivery) async {
    if (_currentDriver == null) return false;

    try {
      // Decline the delivery offer
      final success = await _realtimeService.declineDeliveryOfferNew(delivery.id, _currentDriver!.id);
      
      if (success) {
        _showSuccess(context, 'Delivery offer declined. Waiting for next offer...');
        return true;
      } else {
        _showError(context, 'Failed to decline delivery offer - it may have expired');
        return false;
      }
    } catch (e) {
      _showError(context, 'Failed to decline delivery offer: $e');
      return false;
    }
  }

  /// Update delivery status with proper flow validation
  Future<bool> updateDeliveryStatus(BuildContext context, DeliveryStatus newStatus) async {
    if (_activeDelivery == null || _currentDriver == null) return false;

    // Validate status transition
    if (!_isValidStatusTransition(_activeDelivery!.status, newStatus)) {
      _showError(context, 'Invalid status transition');
      return false;
    }

    try {
      // Get current location for status update
      Position? currentPosition;
      try {
        currentPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
      } catch (e) {
        print('⚠️ Could not get current position: $e');
      }

      // Update status in database
      final success = await _realtimeService.updateDeliveryStatus(
        _activeDelivery!.id,
        newStatus.databaseValue,  // ✅ Use snake_case for database/customer app
        latitude: currentPosition?.latitude,
        longitude: currentPosition?.longitude,
      );

      if (success) {
        _activeDelivery = _activeDelivery!.copyWith(status: newStatus);
        
        // Handle status-specific actions
        await _handleStatusUpdate(context, newStatus);
        
        return true;
      } else {
        _showError(context, 'Failed to update delivery status');
        return false;
      }
    } catch (e) {
      _showError(context, 'Error updating status: $e');
      return false;
    }
  }

  /// Navigate to active delivery screen
  /// DEPRECATED: This method is no longer used - deliveries now shown on main map screen
  @Deprecated('Use main_map_screen with DraggableDeliveryPanel instead')
  void navigateToActiveDelivery(BuildContext context) {
    if (_activeDelivery == null) return;

    // Navigation removed - delivery now shown on main map screen
    print('⚠️ navigateToActiveDelivery called but deprecated - use main_map_screen instead');
  }

  /// Start location tracking with Ably
  Future<void> _startLocationTracking() async {
    if (_activeDelivery == null || _currentDriver == null) {
      print('⚠️ Cannot start location tracking - missing delivery or driver');
      return;
    }
    
    if (_isLocationTrackingActive) {
      print('⚠️ Location tracking already active - skipping duplicate start for delivery: ${_activeDelivery!.id}');
      return;
    }

    try {
      // Stop idle location updates - we're now actively tracking
      _idleLocationService.stopIdleLocationUpdates();
      print('📍 Stopped idle location updates (starting active tracking)');

      // Use DriverLocationService for Ably-based location broadcasting
      DriverLocationService().startTracking(_activeDelivery!.id);
      _isLocationTrackingActive = true;
      print('✅ Ably location tracking started for delivery: ${_activeDelivery!.id}');
    } catch (e) {
      print('❌ Failed to start Ably location tracking: $e');
    }
  }

  /// Stop Ably location tracking
  Future<void> _stopLocationTracking() async {
    if (!_isLocationTrackingActive) return;

    try {
      DriverLocationService().stopTracking();
      _isLocationTrackingActive = false;
      print('✅ Ably location tracking stopped');
    } catch (e) {
      print('❌ Failed to stop Ably location tracking: $e');
    }
  }

  /// Handle status updates with specific actions
  Future<void> _handleStatusUpdate(BuildContext context, DeliveryStatus status) async {
    switch (status) {
      case DeliveryStatus.pickupArrived:
        _showSuccess(context, 'Arrival confirmed. Collect the package when ready.');
        break;
      case DeliveryStatus.packageCollected:
        _showSuccess(context, 'Package collected. Navigate to delivery location.');
        break;
      case DeliveryStatus.goingToDestination:
        _showSuccess(context, 'En route to delivery location.');
        break;
      case DeliveryStatus.atDestination:
        _showSuccess(context, 'Arrived at destination. Complete the delivery.');
        break;
      case DeliveryStatus.delivered:
        await _handleDeliveryCompletion(context);
        break;
      default:
        break;
    }
  }

  /// Handle delivery completion
  Future<void> _handleDeliveryCompletion(BuildContext context) async {
    await _stopLocationTracking();
    _activeDelivery = null;
    
    // Restart idle location updates for driver pairing
    if (_currentDriver != null) {
      await _idleLocationService.startIdleLocationUpdates(_currentDriver!.id);
      print('📍 Restarted idle location updates after delivery completion');
    }
    
    _showSuccess(context, 'Delivery completed successfully! 🎉');
    
    // Navigate back to offers screen
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// Validate status transitions
  bool _isValidStatusTransition(DeliveryStatus current, DeliveryStatus next) {
    switch (current) {
      case DeliveryStatus.driverAssigned:
        return next == DeliveryStatus.goingToPickup || next == DeliveryStatus.pickupArrived;
      case DeliveryStatus.goingToPickup:
        return next == DeliveryStatus.pickupArrived;
      case DeliveryStatus.pickupArrived:
        return next == DeliveryStatus.packageCollected;
      case DeliveryStatus.packageCollected:
        return next == DeliveryStatus.goingToDestination;
      case DeliveryStatus.goingToDestination:
        return next == DeliveryStatus.atDestination;
      case DeliveryStatus.atDestination:
        return next == DeliveryStatus.delivered;
      default:
        return false;
    }
  }

  /// Request location permission with user-friendly dialog
  Future<bool> _requestLocationPermission(BuildContext context) async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      
      if (permission == LocationPermission.denied) {
        // Show explanation dialog first
        final shouldRequest = await _showConfirmDialog(
          context,
          'Location Permission Required',
          'SwiftDash needs your location to:\n\n• Match you with nearby deliveries\n• Provide real-time tracking to customers\n• Navigate to pickup and delivery locations\n\nGrant location permission?',
        );
        
        if (!shouldRequest) return false;
        
        permission = await Geolocator.requestPermission();
      }
      
      if (permission == LocationPermission.deniedForever) {
        _showLocationPermissionDeniedDialog(context);
        return false;
      }
      
      return permission == LocationPermission.whileInUse || permission == LocationPermission.always;
    } catch (e) {
      print('❌ Error requesting location permission: $e');
      return false;
    }
  }

  /// Show location permission denied dialog
  void _showLocationPermissionDeniedDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Location Permission Required'),
        content: const Text(
          'Location permission is permanently denied. Please enable it in Settings to accept deliveries.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Geolocator.openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  /// Show delivery accepted dialog with navigation options
  void _showDeliveryAcceptedDialog(BuildContext context, Delivery delivery) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Delivery Accepted! 🎉'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Navigate to pickup location:'),
            const SizedBox(height: 8),
            Text(
              delivery.pickupAddress,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              navigateToActiveDelivery(context);
            },
            child: const Text('View Details'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _openMapsNavigation(delivery.pickupLatitude, delivery.pickupLongitude);
            },
            child: const Text('Navigate'),
          ),
        ],
      ),
    );
  }

  /// Open maps navigation with proper deeplink handling
  void _openMapsNavigation(double lat, double lng) async {
    try {
      // ✅ FIX: Try native Google Maps deeplink first, fallback to HTTPS
      final nativeUri = Uri.parse('comgooglemaps://?daddr=$lat,$lng&directionsmode=driving');
      
      if (await canLaunchUrl(nativeUri)) {
        await launchUrl(nativeUri, mode: LaunchMode.externalApplication);
        print('🗺️ Opened Google Maps via native deeplink');
      } else {
        // Fallback to HTTPS URL (works on all platforms)
        final webUri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
        print('🗺️ Opened Google Maps via HTTPS link');
      }
    } catch (e) {
      print('❌ Could not open Google Maps: $e');
    }
  }

  /// Show confirmation dialog
  Future<bool> _showConfirmDialog(BuildContext context, String title, String content) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Show error message
  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: SwiftDashColors.dangerRed,
      ),
    );
  }

  /// Show success message
  void _showSuccess(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: SwiftDashColors.successGreen,
      ),
    );
  }

  /// 🔧 PERFORMANCE FIX: Initialize Ably in background (non-blocking)
  void _initializeAblyInBackground() {
    if (_currentDriver == null) return;
    
    // Run in background without blocking UI
    Future(() async {
      try {
        final ablyKey = dotenv.env['ABLY_CLIENT_KEY'];
        if (ablyKey != null && ablyKey.isNotEmpty) {
          print('🔌 Initializing Ably in background...');
          await AblyService().initialize(ablyKey, clientId: _currentDriver!.id);
          print('✅ Ably initialized with driver clientId: ${_currentDriver!.id}');
          
          // Initialize Chat service with same key
          await ChatService().initialize(ablyKey);
          print('✅ Chat service initialized');
          
          // Ensure Ably is connected
          await AblyService().reconnect();
          
          // Verify connection state
          final isConnected = AblyService().isConnected;
          print('🔌 Ably connection state: ${AblyService().connectionState}');
          
          if (!isConnected) {
            print('⚠️ WARNING: Ably not connected - will retry automatically');
          } else {
            print('✅ Ably and Chat services ready for real-time updates');
          }
        }
      } catch (e) {
        print('⚠️ Background Ably initialization failed: $e');
        print('⚠️ Will retry on next connection attempt');
      }
    });
  }

  /// Dispose resources
  void dispose() {
    _stopLocationTracking();
  }
}