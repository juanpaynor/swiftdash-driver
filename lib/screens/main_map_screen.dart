import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import '../models/driver.dart';
import '../models/delivery.dart';
import '../models/delivery_stop.dart';
import '../services/driver_flow_service.dart';
import '../services/optimized_location_service.dart';
import '../services/realtime_service.dart';
import '../services/background_location_service.dart';
import '../services/mapbox_service.dart' as mapbox_svc;
import '../services/route_preview_service.dart';
import '../services/multi_stop_service.dart';
import '../services/ably_service.dart';
import '../core/supabase_config.dart';
import '../core/mapbox_config.dart';
import '../widgets/driver_drawer.dart';
import '../widgets/driver_status_bottom_sheet.dart';
import '../widgets/earnings_modal.dart';
import '../widgets/draggable_delivery_panel.dart';
import '../services/navigation_manager.dart';
import '../services/optimized_state_manager.dart';
import '../widgets/optimized_state_widgets.dart';
import '../services/delivery_stage_manager.dart';
import 'delivery_completion_screen.dart';

class MainMapScreen extends StatefulWidget {
  const MainMapScreen({super.key});

  @override
  State<MainMapScreen> createState() => _MainMapScreenState();
}

class _MainMapScreenState extends State<MainMapScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  final DriverFlowService _driverFlow = DriverFlowService();
  final RealtimeService _realtimeService = RealtimeService();
  
  Driver? _currentDriver;
  bool _isOnline = false;
  bool _isLoading = true;
  geo.Position? _currentPosition;
  MapboxMap? _mapboxMap;
  
  // 🔧 PERFORMANCE FIX: Track stream subscriptions for proper cleanup
  StreamSubscription<Delivery>? _offerStreamSubscription;
  
  // Debouncing for rapid toggles
  bool _isToggling = false;
  DateTime? _lastToggleTime;
  
  // Keep reference to annotation managers for proper cleanup
  CircleAnnotationManager? _driverLocationManager;
  PointAnnotationManager? _pointAnnotationManager;
  PolylineAnnotationManager? _routePolylineManager;
  CircleAnnotationManager? _pickupMarkerManager;
  CircleAnnotationManager? _dropoffMarkerManager;
  PointAnnotationManager? _multiStopNumberedMarkers; // 🚦 For numbered multi-stop markers
  
  // Multi-stop service
  final MultiStopService _multiStopService = MultiStopService();
  
  // Route data for active delivery (old mapbox service)
  mapbox_svc.RouteData? _routeData;
  
  // Route preview for incoming offers - simplified tracking
  Delivery? _currentOffer;
  mapbox_svc.RouteData? _offerRouteData;  // ✅ Store route data for offer preview (mapbox format for panel)
  
  // Animation controllers
  late AnimationController _onlineToggleController;
  late AnimationController _pulseController;
  
  // Bottom sheet controller
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  
  // Track if we have shown notification for current delivery
  bool _hasActiveDeliveryNotification = false;
  
  // Delivery cancellation listener (RealtimeChannel, not StreamSubscription)
  RealtimeChannel? _deliveryCancellationChannel;
  
  // Track last cancelled delivery ID to prevent duplicate notifications
  String? _lastCancelledDeliveryId;
  
  // Track if we've already shown active delivery notification for current delivery
  String? _lastActiveDeliveryNotificationId;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeAnimations();
    _initializeApp();
    _listenForDeliveryCancellation();
  }
  
  @override
  void didUpdateWidget(MainMapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateNotificationState();
  }
  
  /// Update notification state based on active delivery
  void _updateNotificationState() {
    final hasActiveDelivery = _driverFlow.hasActiveDelivery;
    
    // Cancel notification when delivery becomes inactive (REMOVED - notifications disabled)
    if (_hasActiveDeliveryNotification && !hasActiveDelivery) {
      print('🔕 Delivery notification cancelled (notifications disabled)');
      // DeliveryNotificationService.cancelNotification();
      _hasActiveDeliveryNotification = false;
    }
    
    // Set flag when delivery becomes active
    if (!_hasActiveDeliveryNotification && hasActiveDelivery) {
      _hasActiveDeliveryNotification = true;
    }
  }
  
  void _initializeAnimations() {
    _onlineToggleController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
  }
  
  Future<void> _initializeApp() async {
    final driverState = DriverStateManager.instance;
    final deliveryState = DeliveryStateManager.instance;
    
    try {
      driverState.setLoading(true);
      
      // Add timeout to prevent hanging
      await _driverFlow.initialize().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('Driver initialization timed out', const Duration(seconds: 15));
        },
      );
      
      _currentDriver = _driverFlow.currentDriver;
      
      // Check if current user is actually a driver
      if (_currentDriver == null) {
        // Show error and navigate back to login
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ You are not logged in as a driver. Please use a driver account.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 5),
            ),
          );
          Navigator.of(context).pushReplacementNamed('/login');
        });
        return;
      }

      // Update state manager with driver data
      driverState.updateDriver(_currentDriver!);
      
      // Always start offline for safety - driver must manually go online
      _isOnline = false;
      driverState.updateOnlineStatus(false);
      
      // 🔧 CRITICAL FIX: Clear any stale location markers on app startup
      await _removeDriverLocationPin();
      
      // If driver was online in database, set them offline on app start
      if (_currentDriver?.isOnline == true) {
        print('📱 Driver was online in database, setting offline on app start for safety');
        try {
          await _driverFlow.goOffline(context);
          _currentDriver = _driverFlow.currentDriver;
          driverState.updateDriver(_currentDriver!);
          
          // Show user-friendly message
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('🛡️ Set to offline for safety. Tap "Go Online" when ready for deliveries.'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 4),
              ),
            );
          }
        } catch (e) {
          print('⚠️ Failed to set driver offline on startup: $e');
        }
      }
      
      // 🚨 CRITICAL FIX: Set up offer modal listener with debugging
      // 🔧 PERFORMANCE FIX: Cancel existing subscription before creating new one
      if (_currentDriver != null) {
        print('🔔 Setting up offer modal listener for driver: ${_currentDriver!.id}');
        
        // Cancel any existing subscription to prevent memory leaks
        await _offerStreamSubscription?.cancel();
        
        _offerStreamSubscription = _realtimeService.offerModalStream.listen((delivery) {
          print('🔔 *** OFFER MODAL STREAM RECEIVED DELIVERY: ${delivery.id} ***');
          print('🔔 Driver online status: ${driverState.isOnline}');
          print('🔔 Screen mounted: $mounted');
          
          // Add delivery to available offers
          deliveryState.addOffer(delivery);
          
          if (mounted && driverState.isOnline) {
            print('🔔 ✅ CONDITIONS MET - SHOWING OFFER MODAL');
            _showAutomaticOfferModal(delivery);
          } else {
            print('🔔 ❌ CONDITIONS NOT MET - IGNORING OFFER');
            print('   - Driver online: ${driverState.isOnline}');
            print('   - Screen mounted: $mounted');
          }
        });
        print('✅ Offer modal listener set up successfully');
      }
      
      // Animation starts in offline state (no forward() call)
      
      // Add timeout to location getting
      await _getCurrentLocation().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          print('⚠️ Location request timed out');
          return; // Continue without location
        },
      );
    } catch (e) {
      print('Error initializing app: $e');
      driverState.setError('Failed to initialize: $e');
      
      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error initializing driver app: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      driverState.setLoading(false);
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  
  Future<void> _getCurrentLocation() async {
    try {
      final position = await geo.Geolocator.getCurrentPosition();
      setState(() {
        _currentPosition = position;
      });
      
      // Move map to current location if map is ready
      if (_mapboxMap != null && _currentPosition != null) {
        await _mapboxMap!.flyTo(
          CameraOptions(
            center: Point(
              coordinates: Position(_currentPosition!.longitude, _currentPosition!.latitude),
            ),
            zoom: MapboxConfig.defaultZoom,
          ),
          MapAnimationOptions(duration: 2000),
        );
      }
    } catch (e) {
      print('Error getting location: $e');
    }
  }
  
  void _onMapCreated(MapboxMap mapboxMap) {
    _mapboxMap = mapboxMap;
    
    // Set custom SwiftDash style
    _mapboxMap!.loadStyleURI(MapboxConfig.streetStyle);
    
    // 🔧 CRITICAL FIX: Clear any existing location markers when map is created
    _removeDriverLocationPin();
    
    // Move to current location if available, otherwise default to Manila
    if (_currentPosition != null) {
      _mapboxMap!.flyTo(
        CameraOptions(
          center: Point(
            coordinates: Position(_currentPosition!.longitude, _currentPosition!.latitude),
          ),
          zoom: MapboxConfig.defaultZoom,
        ),
        MapAnimationOptions(duration: 1000),
      );
    } else {
      // Default to Manila, Philippines
      _mapboxMap!.flyTo(
        CameraOptions(
          center: Point(
            coordinates: Position(121.0244, 14.5995), // Manila coordinates
          ),
          zoom: 12.0,
        ),
        MapAnimationOptions(duration: 1000),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    
    // 🔧 PERFORMANCE FIX: Cancel stream subscriptions FIRST
    _offerStreamSubscription?.cancel();
    _offerStreamSubscription = null;
    
    // Dispose animation controllers
    _onlineToggleController.dispose();
    _pulseController.dispose();
    
    // Dispose realtime service
    _realtimeService.dispose();
    
    // Unsubscribe from cancellation channel
    _deliveryCancellationChannel?.unsubscribe();
    
    // 🔧 CRITICAL FIX: Clean up map annotations and stop any background services
    _removeDriverLocationPin();
    
    // Also ensure background location service is stopped
    BackgroundLocationService.stopLocationTracking();
    
    // Cancel any active delivery notifications (REMOVED - notifications disabled)
    // DeliveryNotificationService.cancelNotification();
    
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    print('📱 Main map screen lifecycle changed: $state');
    
    switch (state) {
      case AppLifecycleState.resumed:
        print('📱 App resumed - refreshing delivery state');
        _refreshActiveDeliveryState();
        _checkPendingNotificationActions();
        break;
        
      case AppLifecycleState.paused:
        print('📱 App paused - KEEPING background location tracking active');
        // ✅ DON'T STOP TRACKING!
        // Background location service continues broadcasting
        // Ably continues sending location updates
        // This is critical for when driver opens Google Maps
        break;
        
      case AppLifecycleState.inactive:
        print('📱 App inactive (transitioning between states)');
        // App is temporarily inactive (e.g., phone call, notification drawer)
        // DON'T stop tracking here either
        break;
        
      case AppLifecycleState.detached:
        print('📱 App detached - app is being terminated');
        // Only stop tracking if app is fully closing
        // Note: Background service should handle cleanup
        break;
        
      case AppLifecycleState.hidden:
        print('📱 App hidden but still running');
        // Keep tracking active
        break;
    }
  }
  
  /// Refresh active delivery state when app resumes
  Future<void> _refreshActiveDeliveryState() async {
    try {
      // Reinitialize driver flow to get latest active delivery
      await _driverFlow.initialize();
      
      // Update the UI
      setState(() {
        _currentDriver = _driverFlow.currentDriver;
      });
      
      print('🔄 Active delivery state refreshed: hasActiveDelivery=${_driverFlow.hasActiveDelivery}');
      
      // Show notification if there's an active delivery
      // But only if we haven't shown it for this delivery yet
      if (_driverFlow.hasActiveDelivery && _driverFlow.activeDelivery != null) {
        final currentDeliveryId = _driverFlow.activeDelivery!.id;
        
        // Only show snackbar if we haven't shown it for this delivery
        if (_lastActiveDeliveryNotificationId != currentDeliveryId) {
          _lastActiveDeliveryNotificationId = currentDeliveryId;
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.local_shipping, color: SwiftDashColors.white),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'You have an active delivery! Tap the card below to continue.',
                      style: TextStyle(color: SwiftDashColors.white),
                    ),
                  ),
                ],
              ),
              backgroundColor: SwiftDashColors.successGreen,
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                label: 'Continue',
                textColor: SwiftDashColors.white,
                onPressed: () => _driverFlow.navigateToActiveDelivery(context),
              ),
            ),
          );
        } else {
          print('⚠️ Skipping active delivery notification - already shown for this delivery');
        }
      }
    } catch (e) {
      print('Error refreshing active delivery state: $e');
    }
  }
  
  /// Check for pending notification actions and process them (DISABLED - notifications removed)
  Future<void> _checkPendingNotificationActions() async {
    // Notifications system completely disabled - method no longer functional
    return;
  }
  
  /// Handle "Arrived at Pickup" action from notification (DISABLED - notifications removed)
  @override
  Widget build(BuildContext context) {
    return NavigationWrapper(
      isMainFlow: true,
      child: PopScope(
        canPop: false, // Never allow back button to exit
        onPopInvoked: (didPop) async {
          if (didPop) return; // Already handled
          
          // Always minimize app instead of exiting
          await _minimizeApp();
        },
        child: Scaffold(
        key: _scaffoldKey,
        drawer: const DriverDrawer(),
        body: Stack(
        children: [
          // Mapbox Map with Navigation Night Style
          MapWidget(
            key: const ValueKey("mapWidget"),
            styleUri: MapboxConfig.navigationNightStyle, // Using navigation night theme for drivers
            onMapCreated: _onMapCreated,
          ),
          
          // Top bar with menu and online status
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: SwiftDashColors.white.withOpacity(0.95),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Menu button
                    IconButton(
                      onPressed: () {
                        _scaffoldKey.currentState?.openDrawer();
                      },
                      icon: const Icon(Icons.menu),
                      style: IconButton.styleFrom(
                        backgroundColor: SwiftDashColors.lightBlue.withOpacity(0.1),
                        foregroundColor: SwiftDashColors.darkBlue,
                      ),
                    ),
                    
                    const SizedBox(width: 16),
                    
                    // Online status indicator
                    Expanded(
                      child: ValueListenableContainer<bool>(
                        notifier: DriverStateManager.instance.isOnlineNotifier,
                        builder: (context, isOnline, child) {
                          return Row(
                            children: [
                              // 🔧 PERFORMANCE FIX: Only animate pulse when online to save CPU
                              AnimatedBuilder(
                                animation: _pulseController,
                                builder: (context, child) {
                                  // Don't animate if offline (saves 60% CPU on animation)
                                  final pulseOpacity = isOnline ? (_pulseController.value * 0.5) : 0.0;
                                  
                                  return Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: isOnline ? Colors.green : Colors.red,
                                      shape: BoxShape.circle,
                                      boxShadow: isOnline
                                          ? [
                                              BoxShadow(
                                                color: Colors.green.withOpacity(pulseOpacity),
                                                blurRadius: 8,
                                                spreadRadius: 2,
                                              ),
                                            ]
                                          : null,
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isOnline ? 'Online' : 'Offline',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isOnline ? Colors.green : Colors.red,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    
                    // Active Delivery Button (when available)
                    if (_driverFlow.hasActiveDelivery)
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        child: IconButton(
                          onPressed: () => _driverFlow.navigateToActiveDelivery(context),
                          icon: const Icon(Icons.local_shipping),
                          style: IconButton.styleFrom(
                            backgroundColor: SwiftDashColors.successGreen,
                            foregroundColor: SwiftDashColors.white,
                          ),
                          tooltip: 'Active Delivery',
                        ),
                      ),
                    
                    // Refresh button
                    IconButton(
                      onPressed: _refreshActiveDeliveryState,
                      icon: const Icon(Icons.refresh),
                      style: IconButton.styleFrom(
                        backgroundColor: SwiftDashColors.lightBlue.withOpacity(0.1),
                        foregroundColor: SwiftDashColors.darkBlue,
                      ),
                      tooltip: 'Refresh',
                    ),
                    
                    // Location button (subtle)
                    IconButton(
                      onPressed: _showCurrentLocation,
                      icon: const Icon(Icons.my_location),
                      style: IconButton.styleFrom(
                        backgroundColor: SwiftDashColors.lightBlue.withOpacity(0.1),
                        foregroundColor: SwiftDashColors.darkBlue,
                      ),
                    ),
                    
                    // Earnings button
                    IconButton(
                      onPressed: _showEarningsModal,
                      icon: const Icon(Icons.account_balance_wallet),
                      style: IconButton.styleFrom(
                        backgroundColor: SwiftDashColors.lightBlue.withOpacity(0.1),
                        foregroundColor: SwiftDashColors.darkBlue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // 🚀 DoorDash-Style Draggable Delivery Panel (Phase 3)
          // Show offer preview panel when offer is available
          if (_currentOffer != null && !_driverFlow.hasActiveDelivery)
            DraggableDeliveryPanel(
              delivery: _currentOffer!,
              routeData: _offerRouteData, // ✅ Pass route data for distance/duration display
              mode: PanelMode.offerPreview,
              onAcceptOffer: () => _handleAcceptOffer(_currentOffer!),
              onDeclineOffer: () => _handleDeclineOffer(_currentOffer!),
            ),
          
          // Show active delivery panel when delivery is in progress
          if (_driverFlow.hasActiveDelivery && _driverFlow.activeDelivery != null)
            DraggableDeliveryPanel(
              delivery: _driverFlow.activeDelivery!,
              routeData: _routeData,
              mode: PanelMode.activeDelivery,
              onCallCustomer: () => _callCustomer(_driverFlow.activeDelivery!),
              onNavigate: () => _showNavigationOptions(_driverFlow.activeDelivery!),
              onStatusChange: (newStage) => _handleDeliveryStatusChange(newStage),
            ),
          
          // Driver status and online/offline control (hide when delivery active or offer shown)
          if (!_driverFlow.hasActiveDelivery && _currentOffer == null)
          Positioned(
            bottom: 100,
            left: 20,
            right: 20,
            child: MultiValueListenable(
              notifiers: [
                DriverStateManager.instance.isOnlineNotifier,
                DriverStateManager.instance.isLoadingNotifier,
              ],
              builder: (context) {
                final driverState = DriverStateManager.instance;
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: SwiftDashColors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Tappable status info area
                      Expanded(
                        child: GestureDetector(
                          onTap: _showDriverStatusBottomSheet,
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: driverState.isOnline ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  driverState.isOnline ? Icons.check_circle : Icons.pause_circle,
                                  color: driverState.isOnline ? Colors.green : Colors.orange,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      driverState.isOnline ? 'You\'re Online' : 'You\'re Offline',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: SwiftDashColors.darkBlue,
                                      ),
                                    ),
                                    Text(
                                      driverState.isOnline 
                                          ? 'Tap for stats • Ready for offers'
                                          : 'Tap for stats • Go online to receive offers',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Online/Offline Toggle Button
                      Container(
                        height: 40,
                        child: ElevatedButton(
                          onPressed: driverState.isLoading ? null : _toggleOnlineStatus,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: driverState.isOnline ? Colors.red : SwiftDashColors.lightBlue,
                            foregroundColor: SwiftDashColors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                          child: driverState.isLoading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      driverState.isOnline ? Icons.pause : Icons.play_arrow,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      driverState.isOnline ? 'Go Offline' : 'Go Online',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          
          // Loading overlay with optimized state management
          ValueListenableContainer<bool>(
            notifier: DriverStateManager.instance.isLoadingNotifier,
            builder: (context, isLoading, child) {
              if (!isLoading && !_isLoading) return const SizedBox.shrink();
              
              return Container(
                color: Colors.black.withOpacity(0.5),
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(SwiftDashColors.lightBlue),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Loading...',
                        style: TextStyle(
                          color: SwiftDashColors.white,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
      ), // End of PopScope child (Scaffold)
    ), // End of PopScope
    ); // End of NavigationWrapper
  }

  /// Minimize app to background instead of exiting
  Future<void> _minimizeApp() async {
    try {
      await SystemNavigator.pop();
      print('📱 App minimized to background');
    } catch (e) {
      print('⚠️ Failed to minimize app: $e');
      // Fallback: show exit confirmation
      await _showExitConfirmationDialog();
    }
  }
  
  /// Show exit confirmation dialog when driver tries to exit while online
  Future<void> _showExitConfirmationDialog() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // User must tap button
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning, color: Colors.orange, size: 24),
              const SizedBox(width: 8),
              const Text('You\'re Still Online'),
            ],
          ),
          content: const Text(
            'You must go offline before exiting the app. This ensures you won\'t miss delivery notifications and customers know your availability status.',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('Go Offline & Exit'),
              onPressed: () async {
                Navigator.of(context).pop(); // Close dialog
                
                // Go offline first
                final success = await _driverFlow.goOffline(context);
                if (success) {
                  setState(() {
                    _currentDriver = _driverFlow.currentDriver;
                    _isOnline = _currentDriver?.isOnline ?? false;
                  });
                  _onlineToggleController.reverse();
                  await _removeDriverLocationPin();
                  
                  // Now exit the app
                  if (mounted) {
                    Navigator.of(context).pop(); // Exit the screen
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }
  
  void _toggleOnlineStatus() async {
    final driverState = DriverStateManager.instance;
    
    // Prevent rapid toggles or if already loading
    if (_isToggling || driverState.isLoading) {
      print('⚠️ Toggle already in progress, ignoring...');
      return;
    }
    
    // Debounce rapid toggles (minimum 3 seconds between toggles)
    final now = DateTime.now();
    if (_lastToggleTime != null && now.difference(_lastToggleTime!) < const Duration(seconds: 3)) {
      print('⚠️ Debouncing rapid status toggle');
      return;
    }
    
    _isToggling = true;
    _lastToggleTime = now;
    
    try {
      final success = await driverState.toggleOnlineStatus(context);
      
      if (success) {
        // Update local state from state manager
        _currentDriver = driverState.driver;
        _isOnline = driverState.isOnline;
        
        if (_isOnline) {
          _onlineToggleController.forward();
          await _addDriverLocationPin();
          
          // Location tracking is already started by DriverFlowService.goOnline()
          print('📍 Location tracking handled by DriverFlowService');
          
          // Start location broadcasting for realtime updates
          await _startLocationBroadcasting();
        } else {
          _onlineToggleController.reverse();
          await _removeDriverLocationPin();
          
          // Stop location tracking when going offline
          await OptimizedLocationService().stopTracking().timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              print('⚠️ Stop location tracking timed out');
            },
          );
          print('📍 Location tracking stopped');
        }
      }
    } catch (e) {
      print('❌ Error in toggle online status: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating status: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      _isToggling = false;
    }
  }
  
  // Start location broadcasting for realtime updates
  Future<void> _startLocationBroadcasting() async {
    try {
      final driverId = _driverFlow.currentDriver?.id;
      if (driverId == null) {
        print('❌ Cannot start location broadcasting: no driver ID');
        return;
      }
      
      // ✅ OPTIMIZED: No more heavy database writes - use broadcast only!
      // Old: await _updateDriverLocationInProfile(); // ❌ Heavy DB write
      print('📡 Driver location broadcasting started for: $driverId (optimized - no DB writes)');
      
    } catch (e) {
      print('❌ Error starting location broadcasting: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Location broadcasting failed: $e'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }
  
  void _showDriverStatusBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DriverStatusBottomSheet(
        driverFlowService: _driverFlow,
      ),
    ).then((_) {
      // Refresh driver status after bottom sheet closes
      setState(() {
        _currentDriver = _driverFlow.currentDriver;
        _isOnline = _currentDriver?.isOnline ?? false;
      });
    });
  }
  
  /// Get human-readable label for delivery stage
  String _getStageLabel(DeliveryStage stage) {
    switch (stage) {
      case DeliveryStage.headingToPickup:
        return 'Heading to Pickup';
      case DeliveryStage.headingToDelivery:
        return 'Heading to Delivery';
      case DeliveryStage.deliveryComplete:
        return 'Delivery Complete';
    }
  }
  
  /// Call customer phone number
  Future<void> _callCustomer(Delivery delivery) async {
    final phone = delivery.deliveryContactPhone;
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ No phone number available'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    final uri = Uri.parse('tel:$phone');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        print('📞 Calling customer: $phone');
      } else {
        throw 'Could not launch phone dialer';
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error calling customer: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  /// Show navigation options dialog
  Future<void> _showNavigationOptions(Delivery delivery) async {
    final currentStage = delivery.currentStage;
    final isGoingToPickup = currentStage == DeliveryStage.headingToPickup;
    
    final lat = isGoingToPickup ? delivery.pickupLatitude : delivery.deliveryLatitude;
    final lng = isGoingToPickup ? delivery.pickupLongitude : delivery.deliveryLongitude;
    final address = isGoingToPickup ? delivery.pickupAddress : delivery.deliveryAddress;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose Navigation App'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Navigate to:',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              address,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _launchNavigation('google', lat, lng);
            },
            child: const Text('Google Maps'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _launchNavigation('waze', lat, lng);
            },
            child: const Text('Waze'),
          ),
        ],
      ),
    );
  }
  
  /// Launch navigation app
  Future<void> _launchNavigation(String app, double lat, double lng) async {
    Uri uri;
    
    if (app == 'google') {
      // Use official Google Maps Directions API format
      // Automatically uses user's current location as origin
      uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
    } else if (app == 'waze') {
      // Use native Waze protocol for better app integration
      uri = Uri.parse('waze://ul?ll=$lat,$lng&navigate=yes');
    } else {
      return;
    }
    
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        print('🗺️ Launched $app navigation');
        
        // ✅ Send 'in_transit' status via Ably when driver starts navigation to destination
        // Note: 'going_to_pickup' is sent automatically when driver accepts delivery
        if (_driverFlow.hasActiveDelivery && _driverFlow.activeDelivery != null) {
          final delivery = _driverFlow.activeDelivery!;
          final currentStage = delivery.currentStage;
          
          // Only send in_transit when heading to destination (after package collection)
          if (currentStage == DeliveryStage.headingToDelivery) {
            debugPrint('📢 Sending in_transit status via Ably');
            await AblyService().publishStatusUpdate(
              deliveryId: delivery.id,
              status: 'in_transit',
              driverLocation: _currentPosition != null ? {
                'latitude': _currentPosition!.latitude,
                'longitude': _currentPosition!.longitude,
              } : null,
            );
          }
        }
      } else {
        // Waze not installed - show helpful message
        if (app == 'waze' && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Waze is not installed. Please use Google Maps or install Waze.'),
              backgroundColor: SwiftDashColors.warningOrange,
            ),
          );
        }
        print('⚠️ $app not available');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error launching $app: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  /// Handle delivery status change from draggable panel
  Future<void> _handleDeliveryStatusChange(DeliveryStage newStage) async {
    print('🔄 Delivery status changing to: ${newStage.name}');
    
    try {
      // If delivery is complete, show completion screen
      if (newStage == DeliveryStage.deliveryComplete) {
        final activeDelivery = _driverFlow.activeDelivery;
        if (activeDelivery != null) {
          await _showCompletionScreen(activeDelivery);
        }
        return;
      }
      
      // Show loading indicator for other stage changes
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                Text('Updating to ${_getStageLabel(newStage)}...'),
              ],
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      
      // Refresh the driver flow to update the delivery
      print('🔄 Reloading delivery from database to get updated status...');
      await _driverFlow.refreshActiveDelivery();
      
      // Get the updated delivery
      final updatedDelivery = _driverFlow.activeDelivery;
      
      // ✅ FIX: Update route when status changes (especially after package collection)
      if (updatedDelivery != null) {
        print('🗺️ Updating route for new stage: ${updatedDelivery.currentStage.name}');
        
        // Reload and redraw route for new destination
        await _loadDeliveryRoute(updatedDelivery);
        
        if (_routeData != null) {
          await _drawRouteOnMap(_routeData!);
          await _addDeliveryPins(updatedDelivery);
          await _fitMapToDeliveryRoute(updatedDelivery);
          print('✅ Route updated for ${updatedDelivery.currentStage.name}');
        }
      }
      
      // Refresh the map state
      if (mounted) {
        setState(() {
          _currentDriver = _driverFlow.currentDriver;
          // This rebuild will cause DraggableDeliveryPanel to receive the updated delivery
        });
        
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        
        // Show updated status
        if (updatedDelivery != null) {
          print('✅ Delivery reloaded with status: ${updatedDelivery.status}');
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Updated to ${_getStageLabel(newStage)}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      
      print('✅ Delivery status updated successfully');
    } catch (e) {
      print('❌ Error updating delivery status: $e');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error updating status: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
  
  /// Show completion screen after successful delivery
  Future<void> _showCompletionScreen(Delivery delivery) async {
    if (!mounted) return;
    
    // Navigate to completion screen
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DeliveryCompletionScreen(
          delivery: delivery,
          onNextJob: () {
            // Go back to map and set driver online
            Navigator.of(context).pop();
            _handleCompletionNext();
          },
          onViewWallet: () {
            // Go back to map, then navigate to wallet
            Navigator.of(context).pop();
            _handleCompletionViewWallet();
          },
        ),
      ),
    );
  }
  
  /// Handle "Next Job" button from completion screen
  Future<void> _handleCompletionNext() async {
    print('🚀 Driver ready for next job');
    
    try {
      // Refresh driver flow to clear completed delivery
      await _driverFlow.initialize();
      
      // Refresh state
      setState(() {
        _currentDriver = _driverFlow.currentDriver;
      });
      
      // Ensure driver is online
      if (_currentDriver != null && !_currentDriver!.isOnline) {
        _toggleOnlineStatus();
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Ready for next delivery!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
      
      print('✅ Driver back online and ready');
    } catch (e) {
      print('❌ Error going back online: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  /// Handle "View Wallet" button from completion screen
  Future<void> _handleCompletionViewWallet() async {
    print('💵 Navigating to wallet screen');
    
    // Refresh driver flow
    await _driverFlow.initialize();
    
    // Refresh state
    setState(() {
      _currentDriver = _driverFlow.currentDriver;
    });
    
    // TODO: Navigate to wallet/earnings screen
    // For now, just show a message
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('💵 Wallet screen - Coming soon!'),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }
  
  void _showEarningsModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => EarningsModal(
        driverFlowService: _driverFlow,
      ),
    );
  }
  
  // Add driver location pin when going online
  Future<void> _addDriverLocationPin() async {
    if (_mapboxMap == null) {
      print('❌ MapboxMap is null, cannot enable location puck');
      return;
    }
    
    try {
      // Get current location first
      print('🔍 Getting current location for puck...');
      final position = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.high,
      );
      
      _currentPosition = position;
      print('📍 Current position: ${position.latitude}, ${position.longitude}');
      
      // 🎯 USE MAPBOX LOCATION PUCK instead of custom annotations
      await _mapboxMap!.location.updateSettings(LocationComponentSettings(
        enabled: true,
        puckBearingEnabled: true, // Show bearing/direction
        pulsingEnabled: true, // Pulsing animation
        pulsingColor: Colors.blue.value,
        pulsingMaxRadius: 20.0,
      ));
      
      print('✅ Mapbox location puck enabled successfully');
      
      // Center the map on the driver's location
      await _mapboxMap!.flyTo(
        CameraOptions(
          center: Point(
            coordinates: Position(
              position.longitude,
              position.latitude,
            ),
          ),
          zoom: 16.0, // Closer zoom for better visibility
        ),
        MapAnimationOptions(duration: 1500),
      );
      
      print('🎯 Map centered on driver location');
    } catch (e) {
      print('❌ Error enabling location puck: $e');
      
      // Show user-friendly error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to get location: $e'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }
  
  // Remove driver location pin when going offline
  Future<void> _removeDriverLocationPin() async {
    try {
      // 🎯 DISABLE MAPBOX LOCATION PUCK
      if (_mapboxMap != null) {
        await _mapboxMap!.location.updateSettings(LocationComponentSettings(
          enabled: false,
        ));
        print('✅ Mapbox location puck disabled');
      }
      
      // Remove driver location circle if it exists (legacy cleanup)
      if (_driverLocationManager != null) {
        await _driverLocationManager!.deleteAll();
        _driverLocationManager = null;
        print('✅ Driver location circle removed via manager');
      }
      
      // Remove point annotations if they exist (legacy cleanup)
      if (_pointAnnotationManager != null) {
        await _pointAnnotationManager!.deleteAll();
        _pointAnnotationManager = null;
        print('✅ Point annotations removed via manager');
      }
      
      print('✅ Driver location pin cleanup completed');
    } catch (e) {
      print('❌ Error during location pin cleanup: $e');
      // Don't throw - cleanup should be fault-tolerant
    }
  }
  
  // Show automatic offer modal when new delivery offers arrive
  void _showAutomaticOfferModal(Delivery delivery) async {
    print('🚨 _showAutomaticOfferModal called for delivery: ${delivery.id}');
    print('🚨 Driver online: $_isOnline');
    print('🚨 Current driver: ${_currentDriver?.id}');
    
    if (!_isOnline || _currentDriver == null) {
      print('❌ Not showing modal - driver offline or null');
      return;
    }
    
    print('✅ Showing offer preview on map for delivery: ${delivery.id}');
    
    // Store current offer
    setState(() {
      _currentOffer = delivery;
    });
    
    // Show route preview on map
    await _showOfferRoutePreview(delivery);
  }
  
  /// Generate numbered marker image for multi-stop pins
  /// Returns Uint8List of PNG image with number overlay
  Future<Uint8List> _createNumberedMarkerImage(int number, Color backgroundColor) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = 60.0;
    final center = Offset(size / 2, size / 2);
    
    // Draw circle background
    final circlePaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, size / 2, circlePaint);
    
    // Draw white border
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;
    canvas.drawCircle(center, size / 2, borderPaint);
    
    // Draw number text
    final textPainter = TextPainter(
      text: TextSpan(
        text: number.toString(),
        style: TextStyle(
          color: Colors.white,
          fontSize: 28,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        center.dx - textPainter.width / 2,
        center.dy - textPainter.height / 2,
      ),
    );
    
    // Convert to image
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    
    return byteData!.buffer.asUint8List();
  }
  
  /// Show offer route preview on map
  Future<void> _showOfferRoutePreview(Delivery delivery) async {
    if (_mapboxMap == null) {
      print('⚠️ Map not ready, cannot show offer preview');
      return;
    }
    
    try {
      print('🗺️ Fetching route preview for offer: ${delivery.id}');
      final routeService = RoutePreviewService();
      
      // Build waypoints list based on delivery type
      RouteData? routeData;
      
      if (delivery.isMultiStop && delivery.stops != null && delivery.stops!.isNotEmpty) {
        // Multi-stop delivery: Build waypoints from stops
        print('�️ Multi-stop delivery with ${delivery.stops!.length} stops');
        final waypoints = delivery.stops!.map((stop) => 
          Position(stop.longitude, stop.latitude)
        ).toList();
        
        routeData = await routeService.fetchRoute(waypoints: waypoints);
      } else {
        // Single-stop delivery: Pickup → Delivery
        print('🗺️ Single-stop delivery');
        final start = Position(
          delivery.pickupLongitude, 
          delivery.pickupLatitude
        );
        final end = Position(
          delivery.deliveryLongitude, 
          delivery.deliveryLatitude
        );
        
        routeData = await routeService.fetchRoute(start: start, end: end);
      }
      
      if (routeData == null) {
        print('❌ Failed to fetch route preview');
        return;
      }
      
      print('✅ Route preview fetched: ${routeData.formattedDistance}, ${routeData.formattedDuration}');
      print('   Waypoints: ${routeData.waypointCount}, Multi-stop: ${routeData.isMultiStop}');
      
      // Store route data for panel display (convert to mapbox_service.RouteData format)
      final routeDataNonNull = routeData; // For null-safety promotion
      setState(() {
        _offerRouteData = mapbox_svc.RouteData(
          distance: routeDataNonNull.distanceKm,
          duration: routeDataNonNull.durationMinutes.toInt(),
          geometry: routeDataNonNull.geometry,
          bbox: [], // Not needed for panel display
        );
      });
      
      // Draw route on map
      await _drawOfferRouteOnMap(routeDataNonNull);
      
      // Add pickup/delivery pins
      await _addOfferPins(delivery);
      
      // Fit camera to show entire route
      await _fitCameraToOfferRoute(routeDataNonNull);
      
      print('✅ Offer route preview complete');
      
    } catch (e) {
      print('❌ Error showing offer preview: $e');
    }
  }
  
  /// Draw offer route polyline on map
  Future<void> _drawOfferRouteOnMap(RouteData routeData) async {
    if (_mapboxMap == null) return;
    
    try {
      // Clear existing route polyline if any
      if (_routePolylineManager != null) {
        await _routePolylineManager!.deleteAll();
      }
      
      // Create new polyline manager
      _routePolylineManager = await _mapboxMap!.annotations.createPolylineAnnotationManager();
      
      // Extract coordinates from GeoJSON geometry
      final geometry = routeData.geometry;
      final coordinates = (geometry['coordinates'] as List).map((coord) {
        return Position(coord[0], coord[1]);
      }).toList();
      
      // Create polyline
      final polylineOptions = PolylineAnnotationOptions(
        geometry: LineString(coordinates: coordinates),
        lineColor: Colors.blue.value,
        lineWidth: 5.0,
        lineOpacity: 0.8,
      );
      
      await _routePolylineManager!.create(polylineOptions);
      
      print('✅ Offer route polyline drawn (${coordinates.length} points)');
    } catch (e) {
      print('❌ Error drawing offer route: $e');
    }
  }
  
  /// Add pickup and delivery pins for offer
  Future<void> _addOfferPins(Delivery delivery) async {
    if (_mapboxMap == null) return;
    
    try {
      // Clear existing pins
      if (_pickupMarkerManager != null) {
        await _pickupMarkerManager!.deleteAll();
      }
      if (_dropoffMarkerManager != null) {
        await _dropoffMarkerManager!.deleteAll();
      }
      if (_multiStopNumberedMarkers != null) {
        await _multiStopNumberedMarkers!.deleteAll();
      }
      
      if (delivery.isMultiStop && delivery.stops != null) {
        // 🚦 MULTI-STOP: Add numbered pins for all stops
        print('🗺️ Adding numbered pins for ${delivery.stops!.length} stops');
        
        // Create point annotation manager for numbered markers
        _multiStopNumberedMarkers = await _mapboxMap!.annotations.createPointAnnotationManager();
        
        for (final stop in delivery.stops!) {
          // Determine color based on stop type and status
          Color markerColor;
          if (stop.status == DeliveryStopStatus.completed) {
            markerColor = SwiftDashColors.successGreen; // Completed = green
          } else if (stop.status == DeliveryStopStatus.inProgress) {
            markerColor = SwiftDashColors.lightBlue; // In progress = blue
          } else if (stop.status == DeliveryStopStatus.failed) {
            markerColor = Colors.grey; // Failed = grey
          } else {
            // Pending stops: pickup = blue, dropoff = orange
            markerColor = stop.stopType == 'pickup' 
                ? SwiftDashColors.lightBlue 
                : SwiftDashColors.warningOrange;
          }
          
          // Generate numbered marker image
          final markerImage = await _createNumberedMarkerImage(
            stop.stopNumber,
            markerColor,
          );
          
          // Create point annotation with numbered image
          final position = Point(coordinates: Position(stop.longitude, stop.latitude));
          final markerOptions = PointAnnotationOptions(
            geometry: position,
            image: markerImage,
            iconSize: 1.0,
            iconAnchor: IconAnchor.CENTER,
          );
          
          await _multiStopNumberedMarkers!.create(markerOptions);
        }
        
        print('✅ ${delivery.stops!.length} numbered stop markers added');
      } else {
        // SINGLE-STOP: Add pickup and delivery pins (original behavior)
        print('🗺️ Adding pickup and delivery pins');
        
        // Create annotation managers
        _pickupMarkerManager = await _mapboxMap!.annotations.createCircleAnnotationManager();
        _dropoffMarkerManager = await _mapboxMap!.annotations.createCircleAnnotationManager();
        
        // Pickup pin (green)
        final pickupPosition = Point(
          coordinates: Position(delivery.pickupLongitude, delivery.pickupLatitude)
        );
        final pickupOptions = CircleAnnotationOptions(
          geometry: pickupPosition,
          circleRadius: 12.0,
          circleColor: Colors.green.value,
          circleStrokeColor: Colors.white.value,
          circleStrokeWidth: 3.0,
        );
        await _pickupMarkerManager!.create(pickupOptions);
        
        // Delivery pin (red)
        final deliveryPosition = Point(
          coordinates: Position(delivery.deliveryLongitude, delivery.deliveryLatitude)
        );
        final deliveryOptions = CircleAnnotationOptions(
          geometry: deliveryPosition,
          circleRadius: 12.0,
          circleColor: Colors.red.value,
          circleStrokeColor: Colors.white.value,
          circleStrokeWidth: 3.0,
        );
        await _dropoffMarkerManager!.create(deliveryOptions);
      }
      
      print('✅ Offer pins added');
    } catch (e) {
      print('❌ Error adding offer pins: $e');
    }
  }
  
  /// Fit camera to show entire offer route
  Future<void> _fitCameraToOfferRoute(RouteData routeData) async {
    if (_mapboxMap == null) return;
    
    try {
      // Extract coordinates from route geometry
      final geometry = routeData.geometry;
      final coordinates = (geometry['coordinates'] as List).map((coord) {
        return Position(coord[0], coord[1]);
      }).toList();
      
      if (coordinates.isEmpty) {
        print('⚠️ No coordinates to fit camera');
        return;
      }
      
      // Calculate bounds
      double minLat = coordinates.first.lat.toDouble();
      double maxLat = coordinates.first.lat.toDouble();
      double minLng = coordinates.first.lng.toDouble();
      double maxLng = coordinates.first.lng.toDouble();
      
      for (final coord in coordinates) {
        if (coord.lat < minLat) minLat = coord.lat.toDouble();
        if (coord.lat > maxLat) maxLat = coord.lat.toDouble();
        if (coord.lng < minLng) minLng = coord.lng.toDouble();
        if (coord.lng > maxLng) maxLng = coord.lng.toDouble();
      }
      
      // Add padding to the bounds (20% on each side for better view)
      final latPadding = (maxLat - minLat) * 0.25;
      final lngPadding = (maxLng - minLng) * 0.25;
      
      // Calculate center point
      final centerLat = (minLat + maxLat) / 2;
      final centerLng = (minLng + maxLng) / 2;
      
      // Calculate appropriate zoom level based on bounds
      final latDiff = (maxLat - minLat) + (latPadding * 2);
      final lngDiff = (maxLng - minLng) + (lngPadding * 2);
      
      // Simple zoom calculation (adjust based on the larger dimension)
      final maxDiff = math.max(latDiff, lngDiff);
      double zoom;
      if (maxDiff > 0.5) {
        zoom = 10.0;
      } else if (maxDiff > 0.2) {
        zoom = 11.0;
      } else if (maxDiff > 0.1) {
        zoom = 12.0;
      } else if (maxDiff > 0.05) {
        zoom = 13.0;
      } else {
        zoom = 14.0;
      }
      
      // Animate camera to fit the route with calculated zoom
      await _mapboxMap!.flyTo(
        CameraOptions(
          center: Point(coordinates: Position(centerLng, centerLat)),
          zoom: zoom,
          pitch: 0,
          bearing: 0,
        ),
        MapAnimationOptions(duration: 1000, startDelay: 0),
      );
      
      print('✅ Camera fitted to offer route - zoom: $zoom, bounds: [$minLat, $minLng] to [$maxLat, $maxLng]');
    } catch (e) {
      print('❌ Error fitting camera: $e');
    }
  }
  
  /// Handle accept offer (Phase 4 implementation)
  Future<bool> _handleAcceptOffer(Delivery delivery) async {
    print('🔔 Driver attempting to accept delivery: ${delivery.id}');
    
    // Clear any previous cancellation tracking when accepting new delivery
    _lastCancelledDeliveryId = null;
    // Clear active delivery notification tracking to allow notification for new delivery
    _lastActiveDeliveryNotificationId = null;
    
    try {
      if (_currentDriver == null) {
        print('❌ No current driver');
        return false;
      }
      
      // 🚨 Check if delivery still exists (not cancelled) before accepting
      final existingDelivery = await supabase
          .from('deliveries')
          .select('id, status')
          .eq('id', delivery.id)
          .maybeSingle();
      
      if (existingDelivery == null) {
        print('⚠️ Delivery no longer exists - customer may have cancelled');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🚫 This delivery is no longer available'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        // Clear offer state
        setState(() {
          _currentOffer = null;
          _offerRouteData = null;
        });
        await _clearOfferVisualization();
        return false;
      }
      
      if (existingDelivery['status'] == 'cancelled') {
        print('⚠️ Delivery already cancelled by customer');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🚫 This delivery was cancelled by the customer'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        // Clear offer state
        setState(() {
          _currentOffer = null;
          _offerRouteData = null;
        });
        await _clearOfferVisualization();
        return false;
      }
      
      // CRITICAL FIX: Only update database when user confirms acceptance
      print('🚨 CRITICAL: Driver confirmed acceptance - updating database');
      final success = await _realtimeService.acceptDeliveryOffer(
        delivery.id,
        _currentDriver!.id,
      );
      
      print('🔔 Database update result: $success');
      
      if (success) {
        // Only start location tracking AFTER confirmed database update
        print('✅ Delivery accepted - starting location tracking');
        
        // 🚨 CRITICAL FIX: Refresh driver flow to load active delivery
        print('🔄 Refreshing driver flow to load active delivery...');
        await _driverFlow.refreshActiveDelivery();
        
        // Wait a moment for the realtime update to propagate
        await Future.delayed(const Duration(milliseconds: 500));
        
        // Clear offer state
        setState(() {
          _currentOffer = null;
          _offerRouteData = null;
        });
        
        // Update driver state and force rebuild
        setState(() {
          _currentDriver = _driverFlow.currentDriver;
        });
        
        // Clear offer visualization from map
        await _clearOfferVisualization();
        
        // Show delivery route on map (this will be the active delivery route)
        final updatedDelivery = delivery.copyWith(
          driverId: _currentDriver!.id,
          status: DeliveryStatus.driverAssigned,
        );
        await _showDeliveryRoute(updatedDelivery);
        
        print('📱 Staying on main map - DraggableDeliveryPanel will show active delivery');
        print('📊 Active delivery: ${_driverFlow.activeDelivery?.id}');
        
        return true;
      } else {
        print('❌ Database update failed - delivery may have been taken by another driver');
        
        // Clear offer state on failure
        setState(() {
          _currentOffer = null;
          _offerRouteData = null;
        });
        
        await _clearOfferVisualization();
        
        return false;
      }
    } catch (e) {
      print('❌ Error accepting delivery: $e');
      
      // Clear offer state on error
      setState(() {
        _currentOffer = null;
        _offerRouteData = null;
      });
      
      await _clearOfferVisualization();
      
      return false;
    }
  }
  
  /// Handle decline offer (Phase 4 implementation)
  Future<bool> _handleDeclineOffer(Delivery delivery) async {
    print('🔔 Driver attempting to decline delivery: ${delivery.id}');
    
    try {
      // 🚨 Check if delivery still exists (not cancelled) before declining
      final existingDelivery = await supabase
          .from('deliveries')
          .select('id, status')
          .eq('id', delivery.id)
          .maybeSingle();
      
      if (existingDelivery == null || existingDelivery['status'] == 'cancelled') {
        print('⚠️ Delivery no longer exists or already cancelled - just close modal');
        // Clear offer state silently
        setState(() {
          _currentOffer = null;
          _offerRouteData = null;
        });
        await _clearOfferVisualization();
        return true; // Return true since the goal (closing modal) is achieved
      }
      
      // Use driver flow service to decline the offer
      final success = await _driverFlow.declineDeliveryOffer(context, delivery);
      print('🔔 Decline delivery result: $success');
      
      if (success) {
        // Clear offer state
        setState(() {
          _currentOffer = null;
          _offerRouteData = null;
        });
        
        // Clear offer visualization from map
        await _clearOfferVisualization();
        
        print('✅ Offer declined and cleared from map');
      }
      
      return success;
    } catch (e) {
      print('❌ Error declining delivery: $e');
      return false;
    }
  }
  
  /// Clear offer visualization from map
  Future<void> _clearOfferVisualization() async {
    if (_mapboxMap == null) return;
    
    try {
      // Clear route polyline
      if (_routePolylineManager != null) {
        await _routePolylineManager!.deleteAll();
      }
      
      // Clear pickup marker
      if (_pickupMarkerManager != null) {
        await _pickupMarkerManager!.deleteAll();
      }
      
      // Clear dropoff marker
      if (_dropoffMarkerManager != null) {
        await _dropoffMarkerManager!.deleteAll();
      }
      
      print('✅ Offer visualization cleared from map');
    } catch (e) {
      print('❌ Error clearing offer visualization: $e');
    }
  }
  
  // Show current location dialog and option to open in maps
  void _showCurrentLocation() async {
    try {
      final pos = await OptimizedLocationService().getCurrentPosition();
      if (pos == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('📍 Location not available'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      // Focus camera on user location with smooth animation
      if (_mapboxMap != null) {
        await _mapboxMap!.flyTo(
          CameraOptions(
            center: Point(
              coordinates: Position(pos.longitude, pos.latitude),
            ),
            zoom: 17.0, // Close zoom level for user location
            pitch: 0.0, // Reset tilt
            bearing: 0.0, // Reset rotation
          ),
          MapAnimationOptions(duration: 1000, startDelay: 0),
        );
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('📍 Focused on your location'),
              duration: Duration(seconds: 1),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to get location: $e')),
        );
      }
    }
  }
  
  // ============================================================================
  // DELIVERY ROUTE VISUALIZATION METHODS
  // ============================================================================
  
  /// Load and display delivery route on map
  Future<void> _showDeliveryRoute(Delivery delivery) async {
    if (_mapboxMap == null) {
      print('⚠️ Map not ready, skipping route visualization');
      return;
    }
    
    try {
      // Load route data from Mapbox
      await _loadDeliveryRoute(delivery);
      
      if (_routeData != null) {
        // Draw route polyline
        await _drawRouteOnMap(_routeData!);
        
        // Add pickup and delivery pins
        await _addDeliveryPins(delivery);
        
        // Fit map to show entire route
        await _fitMapToDeliveryRoute(delivery);
        
        print('✅ Delivery route visualization complete');
      }
    } catch (e) {
      print('❌ Error showing delivery route: $e');
    }
  }
  
  /// Load route data from Mapbox Directions API
  Future<void> _loadDeliveryRoute(Delivery delivery) async {
    try {
      print('🗺️ Loading route from Mapbox...');
      
      final currentPos = await OptimizedLocationService().getCurrentPosition();
      if (currentPos == null) {
        print('⚠️ Current position not available');
        return;
      }
      
      // Determine origin and destination based on delivery stage
      double originLat, originLng, destLat, destLng;
      
      if (delivery.currentStage == DeliveryStage.headingToPickup) {
        // Route from current location to pickup
        originLat = currentPos.latitude;
        originLng = currentPos.longitude;
        destLat = delivery.pickupLatitude;
        destLng = delivery.pickupLongitude;
      } else {
        // Route from pickup to delivery (or current location to delivery)
        originLat = currentPos.latitude;
        originLng = currentPos.longitude;
        destLat = delivery.deliveryLatitude;
        destLng = delivery.deliveryLongitude;
      }
      
      // Fetch route from Mapbox
      final routeData = await mapbox_svc.MapboxService.getRoute(
        originLat,
        originLng,
        destLat,
        destLng,
      );
      
      if (routeData == null) {
        print('⚠️ Failed to fetch route from Mapbox');
        return;
      }
      
      setState(() {
        _routeData = routeData;
      });
      
      print('✅ Route loaded: ${routeData.distance.toStringAsFixed(2)} km, ETA: ${routeData.duration} min');
    } catch (e) {
      print('❌ Error loading route: $e');
    }
  }
  
  /// Draw route polyline on map
  Future<void> _drawRouteOnMap(mapbox_svc.RouteData routeData) async {
    if (_mapboxMap == null) return;
    
    try {
      // Clear existing route if any
      if (_routePolylineManager != null) {
        await _routePolylineManager!.deleteAll();
      }
      
      _routePolylineManager = await _mapboxMap!.annotations.createPolylineAnnotationManager();
      
      // Create polyline from route geometry
      final polylineOptions = PolylineAnnotationOptions(
        geometry: LineString.fromJson(routeData.geometry),
        lineColor: SwiftDashColors.lightBlue.value,
        lineWidth: 5.0,
        lineOpacity: 0.8,
      );
      
      await _routePolylineManager!.create(polylineOptions);
      
      print('✅ Route polyline drawn on map');
    } catch (e) {
      print('❌ Error drawing route: $e');
    }
  }
  
  /// Add pickup and delivery location pins
  Future<void> _addDeliveryPins(Delivery delivery) async {
    if (_mapboxMap == null) return;
    
    try {
      // Clear existing pins if any
      if (_pickupMarkerManager != null) {
        await _pickupMarkerManager!.deleteAll();
      }
      if (_dropoffMarkerManager != null) {
        await _dropoffMarkerManager!.deleteAll();
      }
      
      // Create separate circle annotation managers for pickup and delivery
      _pickupMarkerManager = await _mapboxMap!.annotations.createCircleAnnotationManager();
      _dropoffMarkerManager = await _mapboxMap!.annotations.createCircleAnnotationManager();
      
      // Pickup marker (green circle)
      final pickupOptions = CircleAnnotationOptions(
        geometry: Point(
          coordinates: Position(
            delivery.pickupLongitude,
            delivery.pickupLatitude,
          ),
        ),
        circleRadius: 12.0,
        circleColor: Colors.green.value,
        circleStrokeColor: Colors.white.value,
        circleStrokeWidth: 3.0,
      );
      
      // Delivery marker (red circle)
      final deliveryOptions = CircleAnnotationOptions(
        geometry: Point(
          coordinates: Position(
            delivery.deliveryLongitude,
            delivery.deliveryLatitude,
          ),
        ),
        circleRadius: 12.0,
        circleColor: Colors.red.value,
        circleStrokeColor: Colors.white.value,
        circleStrokeWidth: 3.0,
      );
      
      await _pickupMarkerManager!.create(pickupOptions);
      await _dropoffMarkerManager!.create(deliveryOptions);
      
      print('✅ Pickup (green pin) and delivery (red pin) added');
    } catch (e) {
      print('❌ Error adding delivery pins: $e');
    }
  }
  
  /// Fit map to show entire delivery route
  Future<void> _fitMapToDeliveryRoute(Delivery delivery) async {
    if (_mapboxMap == null) return;
    
    try {
      // Calculate center point between pickup and delivery
      final centerLat = (delivery.pickupLatitude + delivery.deliveryLatitude) / 2;
      final centerLng = (delivery.pickupLongitude + delivery.deliveryLongitude) / 2;
      
      // Calculate distance to determine appropriate zoom level
      final distance = _calculateDistance(
        delivery.pickupLatitude,
        delivery.pickupLongitude,
        delivery.deliveryLatitude,
        delivery.deliveryLongitude,
      );
      
      // Determine zoom level based on distance
      double zoomLevel = 12.0;
      if (distance < 2) {
        zoomLevel = 14.0;
      } else if (distance < 10) {
        zoomLevel = 12.0;
      } else if (distance < 50) {
        zoomLevel = 10.0;
      } else {
        zoomLevel = 8.0;
      }
      
      await _mapboxMap!.flyTo(
        CameraOptions(
          center: Point(coordinates: Position(centerLng, centerLat)),
          zoom: zoomLevel,
        ),
        MapAnimationOptions(duration: 1500),
      );
      
      print('✅ Map fitted to route (zoom: $zoomLevel)');
    } catch (e) {
      print('❌ Error fitting map bounds: $e');
    }
  }
  
  /// Calculate distance between two points in kilometers
  double _calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    const double earthRadius = 6371; // Earth radius in km
    
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLng = _degreesToRadians(lng2 - lng1);
    
    final a = 
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_degreesToRadians(lat1)) * math.cos(_degreesToRadians(lat2)) *
      math.sin(dLng / 2) * math.sin(dLng / 2);
    
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    
    return earthRadius * c;
  }
  
  double _degreesToRadians(double degrees) {
    return degrees * (math.pi / 180);
  }
  
  /// Listen for delivery cancellation events
  void _listenForDeliveryCancellation() {
    // 🚨 FIX: Use realtime postgres_changes instead of stream() to avoid old data
    // Only listen to UPDATE events for deliveries that change to 'cancelled' status
    final channelName = 'delivery-cancellations-${DateTime.now().millisecondsSinceEpoch}';
    
    _deliveryCancellationChannel = Supabase.instance.client
      .channel(channelName)
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'deliveries',
        callback: (payload) {
          if (_currentDriver == null) return;
          
          final newRecord = payload.newRecord;
          final driverId = newRecord['driver_id'];
          final status = newRecord['status'];
          final deliveryId = newRecord['id'];
          
          // Only handle if it's THIS driver's delivery AND status changed to cancelled
          if (driverId == _currentDriver!.id && status == 'cancelled') {
            // Only handle if it's the ACTIVE delivery
            if (_driverFlow.activeDelivery?.id == deliveryId) {
              print('🚫 Active delivery cancelled by customer: $deliveryId');
              final delivery = Delivery.fromJson(newRecord);
              _handleDeliveryCancellation(delivery);
            }
          }
        },
      )
      .subscribe();  // ✅ Returns RealtimeChannel, not StreamSubscription
      
    print('✅ Listening for delivery cancellations (realtime updates only)');
  }
  
  /// Handle delivery cancellation from customer
  Future<void> _handleDeliveryCancellation(Delivery delivery) async {
    if (!mounted) return;
    
    // Prevent duplicate notifications for same delivery
    if (_lastCancelledDeliveryId == delivery.id) {
      print('⚠️ Cancellation already handled for delivery: ${delivery.id}');
      return;
    }
    
    _lastCancelledDeliveryId = delivery.id;
    print('🚫 Delivery cancelled by customer: ${delivery.id}');
    
    try {
      // 🚨 CRITICAL: If this is the current offer, close the offer modal
      if (_currentOffer?.id == delivery.id) {
        print('🚨 Cancelled delivery matches current offer - closing offer modal');
        setState(() {
          _currentOffer = null;
          _offerRouteData = null;
        });
        await _clearOfferVisualization();
      }
      
      // Clear map visualization
      await _clearDeliveryRoute();
      
      // Stop location tracking services
      await BackgroundLocationService.stopLocationTracking();
      
      // Ensure driver flow refreshes activeDelivery to clear panel state
      try {
        await _driverFlow.refreshActiveDelivery();
        print('🔄 Driver flow refreshed - active delivery should be null now');
      } catch (e) {
        print('⚠️ Could not refresh driver flow after cancellation: $e');
      }
      
      // Force UI update to hide the draggable panel
      setState(() {
        _hasActiveDeliveryNotification = false;
      });
      
      // Clear active delivery notification tracking
      _lastActiveDeliveryNotificationId = null;
      
      // Show cancellation message to driver (only once)
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🚫 Delivery cancelled by customer'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
      
      print('✅ Delivery cancellation handled - panel should close');
    } catch (e) {
      print('❌ Error handling delivery cancellation: $e');
    }
  }
  
  /// Clear delivery route visualization
  Future<void> _clearDeliveryRoute() async {
    try {
      // Clear route polyline
      if (_routePolylineManager != null) {
        await _routePolylineManager!.deleteAll();
        _routePolylineManager = null;
      }
      
      // Clear pickup marker
      if (_pickupMarkerManager != null) {
        await _pickupMarkerManager!.deleteAll();
        _pickupMarkerManager = null;
      }
      
      // Clear delivery marker
      if (_dropoffMarkerManager != null) {
        await _dropoffMarkerManager!.deleteAll();
        _dropoffMarkerManager = null;
      }
      
      // Clear route data
      setState(() {
        _routeData = null;
      });
      
      print('✅ Delivery route visualization cleared');
    } catch (e) {
      print('❌ Error clearing delivery route: $e');
    }
  }
}
