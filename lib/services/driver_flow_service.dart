import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/delivery.dart';
import '../models/driver.dart';
import '../services/realtime_service.dart';
import '../services/optimized_location_service.dart';
import '../services/auth_service.dart';
import '../screens/active_delivery_screen.dart';
import '../core/supabase_config.dart';

/// Service to manage the complete driver delivery flow and state transitions
class DriverFlowService {
  static final DriverFlowService _instance = DriverFlowService._internal();
  factory DriverFlowService() => _instance;
  DriverFlowService._internal();

  final RealtimeService _realtimeService = RealtimeService();
  final OptimizedLocationService _locationService = OptimizedLocationService();
  final AuthService _authService = AuthService();

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
        
        // Resume location tracking if delivery is in progress
        if (_activeDelivery!.status == DeliveryStatus.driverAssigned ||
            _activeDelivery!.status == DeliveryStatus.packageCollected ||
            _activeDelivery!.status == DeliveryStatus.inTransit) {
          await _startLocationTracking();
        }
      }
    } catch (e) {
      print('❌ Error loading active delivery: $e');
    }
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

      // Update driver online status in both tables
      await _authService.updateOnlineStatus(true);
      // Reload driver profile to get updated status
      _currentDriver = await _authService.getCurrentDriverProfile();

      // Start location tracking for online availability
      try {
        await _locationService.startDeliveryTracking(
          driverId: _currentDriver!.id,
          deliveryId: 'available_${_currentDriver!.id}', // Special ID for availability tracking
        );
        print('📍 Started location tracking for driver availability');
      } catch (e) {
        print('⚠️ Could not start location tracking: $e');
        // Don't fail the online process if location tracking fails
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
      // Stop location tracking first
      await _locationService.stopTracking();
      print('📍 Stopped location tracking');

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

  /// Accept a delivery offer
  Future<bool> acceptDeliveryOffer(BuildContext context, Delivery delivery) async {
    if (_currentDriver == null) return false;

    try {
      // Ensure location tracking is ready
      final hasPermission = await _requestLocationPermission(context);
      if (!hasPermission) {
        _showError(context, 'Location permission is required to accept deliveries');
        return false;
      }

      // Accept the delivery
      final success = await _realtimeService.acceptDeliveryOffer(delivery.id, _currentDriver!.id);
      
      if (success) {
        _activeDelivery = delivery.copyWith(
          driverId: _currentDriver!.id,
          status: DeliveryStatus.driverAssigned,
        );

        // Start location tracking
        await _startLocationTracking();

        // Show success and navigation options
        _showDeliveryAcceptedDialog(context, delivery);
        
        return true;
      } else {
        _showError(context, 'Delivery was already taken by another driver');
        return false;
      }
    } catch (e) {
      _showError(context, 'Failed to accept delivery: $e');
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
        currentPosition = await _locationService.getCurrentPosition();
      } catch (e) {
        print('⚠️ Could not get current position: $e');
      }

      // Update status in database
      final success = await _realtimeService.updateDeliveryStatus(
        _activeDelivery!.id,
        newStatus.name,
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
  void navigateToActiveDelivery(BuildContext context) {
    if (_activeDelivery == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ActiveDeliveryScreen(delivery: _activeDelivery!),
      ),
    );
  }

  /// Start location tracking
  Future<void> _startLocationTracking() async {
    if (_activeDelivery == null || _currentDriver == null || _isLocationTrackingActive) return;

    try {
      await _locationService.startDeliveryTracking(
        driverId: _currentDriver!.id,
        deliveryId: _activeDelivery!.id,
      );
      _isLocationTrackingActive = true;
      print('✅ Location tracking started for delivery: ${_activeDelivery!.id}');
    } catch (e) {
      print('❌ Failed to start location tracking: $e');
    }
  }

  /// Stop location tracking
  Future<void> _stopLocationTracking() async {
    if (!_isLocationTrackingActive) return;

    try {
      await _locationService.stopTracking();
      _isLocationTrackingActive = false;
      print('✅ Location tracking stopped');
    } catch (e) {
      print('❌ Failed to stop location tracking: $e');
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
      case DeliveryStatus.inTransit:
        _showSuccess(context, 'En route to delivery location.');
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
    
    _showSuccess(context, 'Delivery completed successfully! 🎉');
    
    // Navigate back to offers screen
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// Validate status transitions
  bool _isValidStatusTransition(DeliveryStatus current, DeliveryStatus next) {
    switch (current) {
      case DeliveryStatus.driverAssigned:
        return next == DeliveryStatus.pickupArrived;
      case DeliveryStatus.pickupArrived:
        return next == DeliveryStatus.packageCollected;
      case DeliveryStatus.packageCollected:
        return next == DeliveryStatus.inTransit;
      case DeliveryStatus.inTransit:
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

  /// Open maps navigation
  void _openMapsNavigation(double lat, double lng) async {
    final url = 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng';
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      print('❌ Could not open maps: $e');
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

  /// Dispose resources
  void dispose() {
    _stopLocationTracking();
  }
}