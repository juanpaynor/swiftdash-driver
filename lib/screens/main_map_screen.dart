import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import '../services/ably_service.dart';
import '../services/navigation_service.dart'; // NEW: Professional navigation
import '../core/supabase_config.dart';
import '../core/mapbox_config.dart';
import '../widgets/driver_drawer.dart';
import '../widgets/driver_status_bottom_sheet.dart';
import '../widgets/earnings_modal.dart';
import '../widgets/draggable_delivery_panel.dart';
import '../widgets/navigation_instruction_panel.dart'; // NEW: Navigation UI
import '../services/navigation_manager.dart';
import '../services/optimized_state_manager.dart';
import '../widgets/optimized_state_widgets.dart';
import '../services/delivery_stage_manager.dart';
import '../services/notification_sound_service.dart';
import 'delivery_completion_screen.dart';

class MainMapScreen extends StatefulWidget {
  const MainMapScreen({super.key});

  @override
  State<MainMapScreen> createState() => _MainMapScreenState();
}

class _MainMapScreenState extends State<MainMapScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final DriverFlowService _driverFlow = DriverFlowService();
  final RealtimeService _realtimeService = RealtimeService();

  Driver? _currentDriver;
  bool _isOnline = false;
  bool _isLoading = true;
  geo.Position? _currentPosition;
  MapboxMap? _mapboxMap;

  // 🔧 PERFORMANCE FIX: Track stream subscriptions for proper cleanup
  StreamSubscription<Delivery>? _offerStreamSubscription;
  StreamSubscription<geo.Position>?
  _navigationLocationSubscription; // 🆕 Track navigation location stream

  // Debouncing for rapid toggles
  bool _isToggling = false;
  DateTime? _lastToggleTime;

  // Keep reference to annotation managers for proper cleanup
  CircleAnnotationManager? _driverLocationManager;
  PointAnnotationManager? _pointAnnotationManager;
  PolylineAnnotationManager? _routePolylineManager;
  PointAnnotationManager?
  _pickupMarkerManager; // 🔄 Changed from Circle to Point
  PointAnnotationManager?
  _dropoffMarkerManager; // 🔄 Changed from Circle to Point
  PointAnnotationManager?
  _multiStopNumberedMarkers; // 🚦 For numbered multi-stop markers

  // 🧭 NEW: Professional navigation service
  final NavigationService _navigationService = NavigationService.instance;
  final NotificationSoundService _soundService = NotificationSoundService();
  bool _isNavigating = false;
  bool _isNavigationCameraLocked =
      true; // Camera auto-follow toggle during navigation

  // 🗺️ Map style URLs
  static const String _defaultMapStyle =
      MapboxConfig.streetStyle; // Default style (idle)
  static const String _navigationMapStyle =
      'mapbox://styles/swiftdash/cmgtdgxbe000e01st0atdhrex'; // Navigation style

  // Route data for active delivery (old mapbox service)
  mapbox_svc.RouteData? _routeData;
  List<Position>?
  _originalRouteCoordinates; // 🆕 Store original route for trimming
  PolylineAnnotation?
  _currentRouteAnnotation; // 🆕 Store current polyline annotation
  int?
  _lastClosestIndex; // 🆕 Track last closest index for smooth polyline updates
  Delivery?
  _pendingDeliveryForRoute; // 🏢 Store business dispatch to show route after map loads

  // Route preview for incoming offers - simplified tracking
  Delivery? _currentOffer;
  mapbox_svc.RouteData?
  _offerRouteData; // ✅ Store route data for offer preview (mapbox format for panel)

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

  // Flag to prevent camera listener from unlocking during programmatic camera updates
  bool _isProgrammaticCameraUpdate = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeAnimations();
    _initializeApp();
    _listenForDeliveryCancellation();

    // Initialize notification sound service
    _soundService.initialize();
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
          throw TimeoutException(
            'Driver initialization timed out',
            const Duration(seconds: 15),
          );
        },
      );

      _currentDriver = _driverFlow.currentDriver;

      // Check if current user is actually a driver
      if (_currentDriver == null) {
        // Show error and navigate back to login
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '❌ You are not logged in as a driver. Please use a driver account.',
              ),
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

      // ✅ FIX: DON'T set offline if driver has active delivery!
      // If driver was online in database, set them offline ONLY IF no active delivery
      if (_currentDriver?.isOnline == true && !_driverFlow.hasActiveDelivery) {
        print(
          '📱 Driver was online in database (no active delivery), setting offline on app start for safety',
        );
        try {
          await _driverFlow.goOffline(context);
          _currentDriver = _driverFlow.currentDriver;
          driverState.updateDriver(_currentDriver!);

          // Show user-friendly message
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  '🛡️ Set to offline for safety. Tap "Go Online" when ready for deliveries.',
                ),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 4),
              ),
            );
          }
        } catch (e) {
          print('⚠️ Failed to set driver offline on startup: $e');
        }
      } else if (_currentDriver?.isOnline == true &&
          _driverFlow.hasActiveDelivery) {
        print('✅ Driver was online with active delivery - staying online!');
        // Keep driver online since they have an active delivery
        _isOnline = true;
        driverState.updateOnlineStatus(true);
      }

      // 🚨 CRITICAL FIX: Set up offer modal listener with debugging
      // 🔧 PERFORMANCE FIX: Cancel existing subscription before creating new one
      if (_currentDriver != null) {
        print(
          '🔔 Setting up offer modal listener for driver: ${_currentDriver!.id}',
        );

        // Cancel any existing subscription to prevent memory leaks
        await _offerStreamSubscription?.cancel();

        _offerStreamSubscription = _realtimeService.offerModalStream.listen((
          delivery,
        ) {
          print(
            '🔔 *** OFFER MODAL STREAM RECEIVED DELIVERY: ${delivery.id} ***',
          );
          print('🔔 Driver online status: ${driverState.isOnline}');
          print('🔔 Screen mounted: $mounted');

          // Add delivery to available offers
          deliveryState.addOffer(delivery);

          if (mounted && driverState.isOnline) {
            print('🔔 ✅ CONDITIONS MET - PROCESSING OFFER');

            // 🔔 Play notification sound
            _soundService.playOfferSound();

            // 🏢 Check if this is a business dispatch delivery
            print('🔍 Checking delivery type:');
            print('   - Driver Source: ${delivery.driverSource}');
            print('   - Business ID: ${delivery.businessId}');
            print('   - Status: ${delivery.status}');
            print('   - Assignment Type: ${delivery.assignmentType}');
            print('   - isBusinessDispatch: ${delivery.isBusinessDispatch}');

            // Check multiple conditions for business dispatch:
            // 1. Primary: driver_source == 'business_dispatch'
            // 2. Fallback: status == 'driver_assigned' AND business_id != null
            //    (for testing if web team hasn't set driver_source yet)
            final isBusinessDispatch =
                delivery.isBusinessDispatch ||
                (delivery.status == DeliveryStatus.driverAssigned &&
                    delivery.businessId != null);

            if (isBusinessDispatch) {
              print('🏢 *** BUSINESS DISPATCH DETECTED - AUTO-ACCEPTING ***');
              print('🏢 Delivery ID: ${delivery.id}');
              print('🏢 Driver Source: ${delivery.driverSource}');
              print('🏢 Business ID: ${delivery.businessId}');
              print(
                '🏢 Detection method: ${delivery.isBusinessDispatch ? "driver_source" : "fallback (status + business_id)"}',
              );
              _handleBusinessDispatchAutoAccept(delivery);
            } else {
              print('👤 B2C delivery - showing offer modal');
              print(
                '   (Not business dispatch: driverSource=${delivery.driverSource}, businessId=${delivery.businessId}, status=${delivery.status})',
              );
              _showAutomaticOfferModal(delivery);
            }
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
              coordinates: Position(
                _currentPosition!.longitude,
                _currentPosition!.latitude,
              ),
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
            coordinates: Position(
              _currentPosition!.longitude,
              _currentPosition!.latitude,
            ),
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

    // 🏢 Show pending business dispatch route if map wasn't ready earlier
    if (_pendingDeliveryForRoute != null) {
      print('🗺️ Map now ready - showing pending business dispatch route...');
      _showDeliveryRoute(_pendingDeliveryForRoute!)
          .then((_) {
            print('✅ Pending route shown on map');
            _pendingDeliveryForRoute = null;
          })
          .catchError((e) {
            print('❌ Error showing pending route: $e');
          });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    // 🔧 PERFORMANCE FIX: Cancel stream subscriptions FIRST
    _offerStreamSubscription?.cancel();
    _offerStreamSubscription = null;
    _navigationLocationSubscription
        ?.cancel(); // 🆕 Cancel navigation location stream
    _navigationLocationSubscription = null;

    // Dispose sound service
    _soundService.dispose();

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

      print(
        '🔄 Active delivery state refreshed: hasActiveDelivery=${_driverFlow.hasActiveDelivery}',
      );

      // Show notification if there's an active delivery
      // But only if we haven't shown it for this delivery yet
      if (_driverFlow.hasActiveDelivery && _driverFlow.activeDelivery != null) {
        final currentDeliveryId = _driverFlow.activeDelivery!.id;

        // 🗺️ Show route on map (especially for business dispatch)
        if (_lastActiveDeliveryNotificationId != currentDeliveryId) {
          print('🗺️ New active delivery detected - showing route on map');
          await _showDeliveryRoute(_driverFlow.activeDelivery!);
        }

        // Only show snackbar if we haven't shown it for this delivery
        if (_lastActiveDeliveryNotificationId != currentDeliveryId) {
          _lastActiveDeliveryNotificationId = currentDeliveryId;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(
                    Icons.local_shipping,
                    color: SwiftDashColors.white,
                  ),
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
          print(
            '⚠️ Skipping active delivery notification - already shown for this delivery',
          );
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
                styleUri: MapboxConfig
                    .navigationNightStyle, // Using navigation night theme for drivers
                onMapCreated: _onMapCreated,
                onCameraChangeListener: _isNavigating
                    ? _onCameraChange
                    : null, // Detect manual camera movement during navigation
              ),

              // Top bar with menu and online status
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
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
                            backgroundColor: SwiftDashColors.lightBlue
                                .withOpacity(0.1),
                            foregroundColor: SwiftDashColors.darkBlue,
                          ),
                        ),

                        const SizedBox(width: 16),

                        // Online status indicator
                        Expanded(
                          child: ValueListenableContainer<bool>(
                            notifier:
                                DriverStateManager.instance.isOnlineNotifier,
                            builder: (context, isOnline, child) {
                              return Row(
                                children: [
                                  // 🔧 PERFORMANCE FIX: Only animate pulse when online to save CPU
                                  AnimatedBuilder(
                                    animation: _pulseController,
                                    builder: (context, child) {
                                      // Don't animate if offline (saves 60% CPU on animation)
                                      final pulseOpacity = isOnline
                                          ? (_pulseController.value * 0.5)
                                          : 0.0;

                                      return Container(
                                        width: 12,
                                        height: 12,
                                        decoration: BoxDecoration(
                                          color: isOnline
                                              ? Colors.green
                                              : Colors.red,
                                          shape: BoxShape.circle,
                                          boxShadow: isOnline
                                              ? [
                                                  BoxShadow(
                                                    color: Colors.green
                                                        .withOpacity(
                                                          pulseOpacity,
                                                        ),
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
                                      color: isOnline
                                          ? Colors.green
                                          : Colors.red,
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
                              onPressed: () =>
                                  _driverFlow.navigateToActiveDelivery(context),
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
                            backgroundColor: SwiftDashColors.lightBlue
                                .withOpacity(0.1),
                            foregroundColor: SwiftDashColors.darkBlue,
                          ),
                          tooltip: 'Refresh',
                        ),

                        // Location button (subtle)
                        IconButton(
                          onPressed: _showCurrentLocation,
                          icon: const Icon(Icons.my_location),
                          style: IconButton.styleFrom(
                            backgroundColor: SwiftDashColors.lightBlue
                                .withOpacity(0.1),
                            foregroundColor: SwiftDashColors.darkBlue,
                          ),
                        ),

                        // Earnings button
                        IconButton(
                          onPressed: _showEarningsModal,
                          icon: const Icon(Icons.account_balance_wallet),
                          style: IconButton.styleFrom(
                            backgroundColor: SwiftDashColors.lightBlue
                                .withOpacity(0.1),
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
                  routeData:
                      _offerRouteData, // ✅ Pass route data for distance/duration display
                  mode: PanelMode.offerPreview,
                  onAcceptOffer: () => _handleAcceptOffer(_currentOffer!),
                  onDeclineOffer: () => _handleDeclineOffer(_currentOffer!),
                ),

              // Show active delivery panel when delivery is in progress
              if (_driverFlow.hasActiveDelivery &&
                  _driverFlow.activeDelivery != null)
                DraggableDeliveryPanel(
                  delivery: _driverFlow.activeDelivery!,
                  routeData: _routeData,
                  mode: PanelMode.activeDelivery,
                  onCallCustomer: () =>
                      _callCustomer(_driverFlow.activeDelivery!),
                  onNavigate: () =>
                      _showNavigationOptions(_driverFlow.activeDelivery!),
                  onStatusChange: (newStage) =>
                      _handleDeliveryStatusChange(newStage),
                ),

              // 🚨 CRITICAL: Floating "Go Online" button when offline with active delivery
              if (_driverFlow.hasActiveDelivery)
                ValueListenableBuilder<bool>(
                  valueListenable: DriverStateManager.instance.isOnlineNotifier,
                  builder: (context, isOnline, child) {
                    // Only show when offline
                    if (isOnline) return const SizedBox.shrink();

                    return Positioned(
                      top: 120,
                      left: 20,
                      right: 20,
                      child: Material(
                        elevation: 8,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.orange, Colors.deepOrange],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.warning_amber_rounded,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'You\'re Offline!',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          'Go online to transmit location and complete delivery',
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(
                                              0.9,
                                            ),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _toggleOnlineStatus,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.deepOrange,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.wifi, size: 20),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Go Online Now',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),

              // 🧭 NEW: Professional Navigation Instructions Panel
              if (_isNavigating)
                NavigationInstructionPanel(
                  navigationService: _navigationService,
                  onCloseNavigation: () async {
                    await _navigationService.stopNavigation();
                    setState(() {
                      _isNavigating = false;
                    });
                    // 🎥 Exit navigation camera mode when user closes
                    await _disableNavigationCameraMode();
                    // 🗺️ Switch back to default map style
                    await _switchToDefaultMapStyle();
                  },
                  showCompactMode: _driverFlow
                      .hasActiveDelivery, // Compact when delivery panel is shown
                ),

              // 🎯 NEW: Re-center button (appears when camera is unlocked during navigation)
              if (_isNavigating && !_isNavigationCameraLocked)
                Positioned(
                  bottom: _driverFlow.hasActiveDelivery ? 420 : 120,
                  right: 20,
                  child: FloatingActionButton(
                    onPressed: _recenterNavigationCamera,
                    backgroundColor: Colors.blue,
                    tooltip: 'Re-center on your location',
                    child: const Icon(Icons.my_location, color: Colors.white),
                  ),
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
                                        color: driverState.isOnline
                                            ? Colors.green.withOpacity(0.2)
                                            : Colors.orange.withOpacity(0.2),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        driverState.isOnline
                                            ? Icons.check_circle
                                            : Icons.pause_circle,
                                        color: driverState.isOnline
                                            ? Colors.green
                                            : Colors.orange,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            driverState.isOnline
                                                ? 'You\'re Online'
                                                : 'You\'re Offline',
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
                                onPressed: driverState.isLoading
                                    ? null
                                    : _toggleOnlineStatus,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: driverState.isOnline
                                      ? Colors.red
                                      : SwiftDashColors.lightBlue,
                                  foregroundColor: SwiftDashColors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
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
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Colors.white,
                                              ),
                                        ),
                                      )
                                    : Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            driverState.isOnline
                                                ? Icons.pause
                                                : Icons.play_arrow,
                                            size: 16,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            driverState.isOnline
                                                ? 'Go Offline'
                                                : 'Go Online',
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
                            valueColor: AlwaysStoppedAnimation<Color>(
                              SwiftDashColors.lightBlue,
                            ),
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
    if (_lastToggleTime != null &&
        now.difference(_lastToggleTime!) < const Duration(seconds: 3)) {
      print('⚠️ Debouncing rapid status toggle');
      return;
    }

    _isToggling = true;
    _lastToggleTime = now;

    try {
      // 🚨 CRITICAL: If offline with active delivery, force go online (don't toggle)
      bool success;
      if (!driverState.isOnline && _driverFlow.hasActiveDelivery) {
        print('🔄 Going online with active delivery - forcing goOnline()');
        success = await _driverFlow.goOnline(context);
        if (success) {
          driverState.updateOnlineStatus(true);
        }
      } else {
        success = await driverState.toggleOnlineStatus(context);
      }

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
      print(
        '📡 Driver location broadcasting started for: $driverId (optimized - no DB writes)',
      );
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
      builder: (context) =>
          DriverStatusBottomSheet(driverFlowService: _driverFlow),
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

    final lat = isGoingToPickup
        ? delivery.pickupLatitude
        : delivery.deliveryLatitude;
    final lng = isGoingToPickup
        ? delivery.pickupLongitude
        : delivery.deliveryLongitude;
    final address = isGoingToPickup
        ? delivery.pickupAddress
        : delivery.deliveryAddress;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: SwiftDashColors.lightBlue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.navigation,
                        color: SwiftDashColors.lightBlue,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Choose Navigation',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Select your preferred navigation',
                            style: TextStyle(fontSize: 13, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Destination Address
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        color: Colors.grey[700],
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          address,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // 🚀 SwiftDash Professional Navigation (Primary Option)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _startProfessionalNavigation(lat, lng, delivery);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SwiftDashColors.lightBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                      shadowColor: SwiftDashColors.lightBlue.withOpacity(0.4),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.navigation, size: 24),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Start SwiftDash Navigation',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Recommended for best experience',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withOpacity(0.9),
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // External Navigation Options
                const Text(
                  'Or use external app',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                ),

                const SizedBox(height: 12),

                // Navigation Options
                Row(
                  children: [
                    Expanded(
                      child: _buildExternalNavButton(
                        'Google Maps',
                        Icons.map,
                        Colors.green,
                        () {
                          Navigator.pop(context);
                          _launchNavigation('google', lat, lng);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildExternalNavButton(
                        'Waze',
                        Icons.directions_car,
                        Colors.blue,
                        () {
                          Navigator.pop(context);
                          _launchNavigation('waze', lat, lng);
                        },
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Cancel Button
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontSize: 15, color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Build external navigation button (compact style)
  Widget _buildExternalNavButton(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Launch navigation app with proper deeplink handling
  Future<void> _launchNavigation(String app, double lat, double lng) async {
    try {
      bool launched = false;

      if (app == 'google') {
        // ✅ FIX: Try multiple Google Maps URL schemes for better compatibility

        // Option 1: Try native app deeplink first (comgooglemaps://)
        final nativeUri = Uri.parse(
          'comgooglemaps://?daddr=$lat,$lng&directionsmode=driving',
        );
        if (await canLaunchUrl(nativeUri)) {
          await launchUrl(nativeUri, mode: LaunchMode.externalApplication);
          launched = true;
          print('🗺️ Launched Google Maps via native deeplink');
        } else {
          // Option 2: Fallback to universal HTTPS link (works on all platforms)
          final webUri = Uri.parse(
            'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
          );
          if (await canLaunchUrl(webUri)) {
            await launchUrl(webUri, mode: LaunchMode.externalApplication);
            launched = true;
            print('🗺️ Launched Google Maps via HTTPS link');
          }
        }
      } else if (app == 'waze') {
        // ✅ FIX: Proper Waze deeplink with fallback

        // Option 1: Try native Waze deeplink first
        final wazeUri = Uri.parse('waze://?ll=$lat,$lng&navigate=yes');
        if (await canLaunchUrl(wazeUri)) {
          await launchUrl(wazeUri, mode: LaunchMode.externalApplication);
          launched = true;
          print('🗺️ Launched Waze via native deeplink');
        } else {
          // Option 2: Fallback to Waze web URL (redirects to app or shows install page)
          final wazeWebUri = Uri.parse(
            'https://waze.com/ul?ll=$lat,$lng&navigate=yes',
          );
          if (await canLaunchUrl(wazeWebUri)) {
            await launchUrl(wazeWebUri, mode: LaunchMode.externalApplication);
            launched = true;
            print('🗺️ Launched Waze via web URL');
          }
        }

        // Show helpful message if Waze not available
        if (!launched && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Waze is not installed. Please install Waze or use Google Maps.',
              ),
              backgroundColor: SwiftDashColors.warningOrange,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }

      // ✅ Send 'in_transit' status via Ably when driver starts navigation to destination
      if (launched &&
          _driverFlow.hasActiveDelivery &&
          _driverFlow.activeDelivery != null) {
        final delivery = _driverFlow.activeDelivery!;
        final currentStage = delivery.currentStage;

        // Only send in_transit when heading to destination (after package collection)
        if (currentStage == DeliveryStage.headingToDelivery) {
          debugPrint('📢 Sending in_transit status via Ably');
          await AblyService().publishStatusUpdate(
            deliveryId: delivery.id,
            status: 'in_transit',
            driverLocation: _currentPosition != null
                ? {
                    'latitude': _currentPosition!.latitude,
                    'longitude': _currentPosition!.longitude,
                  }
                : null,
          );
        }
      }

      if (!launched) {
        print('⚠️ $app navigation could not be launched');
      }
    } catch (e) {
      print('❌ Error launching $app navigation: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Unable to open $app. Please try again or use another navigation app.',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// 🎯 Show beta warning modal before starting navigation (with "don't show again" option)
  Future<void> _showBetaWarningIfNeeded(
    double lat,
    double lng,
    Delivery delivery,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final dontShowAgain =
        prefs.getBool('navigation_beta_warning_dismissed') ?? false;

    if (dontShowAgain) {
      // User chose to not see the warning again, proceed directly
      await _startProfessionalNavigation(lat, lng, delivery);
      return;
    }

    // Show beta warning modal
    bool checkboxValue = false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.science,
                      color: Colors.orange,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Beta Feature',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SwiftDash Navigation is currently in beta testing.',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Please be aware that you may encounter bugs or unexpected behavior during navigation. We appreciate your patience as we continue to improve this feature.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.withOpacity(0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'You can always use Google Maps or Waze as an alternative.',
                            style: TextStyle(fontSize: 13, color: Colors.blue),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () {
                      setState(() {
                        checkboxValue = !checkboxValue;
                      });
                    },
                    child: Row(
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Checkbox(
                            value: checkboxValue,
                            onChanged: (value) {
                              setState(() {
                                checkboxValue = value ?? false;
                              });
                            },
                            activeColor: SwiftDashColors.darkBlue,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Don\'t show this again',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(false);
                  },
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (checkboxValue) {
                      await prefs.setBool(
                        'navigation_beta_warning_dismissed',
                        true,
                      );
                    }
                    Navigator.of(context).pop(true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SwiftDashColors.darkBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Continue',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    // If user clicked "Continue", start navigation
    if (result == true) {
      await _startProfessionalNavigation(lat, lng, delivery);
    }
  }

  /// 🧭 NEW: Start professional in-app navigation using NavigationService
  Future<void> _startProfessionalNavigation(
    double lat,
    double lng,
    Delivery delivery,
  ) async {
    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Current location not available. Please try again.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      // Determine if this is pickup or delivery phase
      final isPickupPhase =
          delivery.status == DeliveryStatus.driverAssigned ||
          delivery.status == DeliveryStatus.pickupArrived;

      // Start professional navigation
      final success = await _navigationService.startNavigationToDelivery(
        delivery: delivery,
        currentLocation: _currentPosition!,
        isPickupPhase: isPickupPhase,
      );

      if (success) {
        setState(() {
          _isNavigating = true;
          _lastClosestIndex = null; // 🆕 Reset for smooth polyline tracking
        });

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.navigation, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  isPickupPhase
                      ? 'Navigation to pickup started'
                      : 'Navigation to delivery started',
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );

        // 🔄 Send appropriate status via Ably when navigation starts
        if (_driverFlow.hasActiveDelivery &&
            _driverFlow.activeDelivery != null) {
          final activeDelivery = _driverFlow.activeDelivery!;
          final currentStage = activeDelivery.currentStage;

          // Send status update based on navigation phase
          if (currentStage == DeliveryStage.headingToDelivery) {
            debugPrint(
              '📢 Sending in_transit status via Ably (SwiftDash Navigation)',
            );
            await AblyService().publishStatusUpdate(
              deliveryId: activeDelivery.id,
              status: 'in_transit',
              driverLocation: {
                'latitude': _currentPosition!.latitude,
                'longitude': _currentPosition!.longitude,
              },
            );
          }
        }

        // 🔍 Route should already be drawn by startNavigationToDelivery via RoutePreviewService
        // The NavigationService gets its route from the same source
        final navigationRoute = _navigationService.currentRoute;
        if (navigationRoute != null) {
          debugPrint('📍 Navigation route available:');
          debugPrint('   Distance: ${navigationRoute.totalDistance}m');
          debugPrint('   Duration: ${navigationRoute.totalDuration} mins');
          debugPrint('   Instructions: ${navigationRoute.instructions.length}');
        } else {
          debugPrint('⚠️ No route data available from navigation service');
        }

        // 🗺️ Switch to premium navigation map style FIRST
        await _switchToNavigationMapStyle();

        // 🎥 Enable professional navigation camera mode
        await _enableNavigationCameraMode();

        // Setup location tracking for navigation (start AFTER camera is set)
        _setupNavigationLocationTracking();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Failed to start navigation. Please try external navigation.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error starting professional navigation: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Navigation error. Please try external navigation.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Setup location tracking for navigation updates
  void _setupNavigationLocationTracking() {
    // ✅ FIX: Start continuous location stream to update _currentPosition
    final locationStream = geo.Geolocator.getPositionStream(
      locationSettings: const geo.LocationSettings(
        accuracy: geo.LocationAccuracy.high,
        distanceFilter: 5, // Update every 5 meters
      ),
    );

    // Cancel any existing subscription
    _navigationLocationSubscription?.cancel();

    // Listen to location updates and update current position
    _navigationLocationSubscription = locationStream.listen((position) {
      if (!_isNavigating) return;

      // Update current position
      _currentPosition = position;
      debugPrint(
        '📍 Location updated: ${position.latitude}, ${position.longitude}, heading: ${position.heading}',
      );

      // Update navigation service
      _navigationService.updateLocation(position);

      // Use snapped location for visualization if available
      geo.Position effectivePosition = position;
      if (_navigationService.snappedLocation != null) {
        effectivePosition = geo.Position(
          latitude: _navigationService.snappedLocation!.latitude,
          longitude: _navigationService.snappedLocation!.longitude,
          timestamp: position.timestamp,
          accuracy: position.accuracy,
          altitude: position.altitude,
          heading: position.heading,
          speed: position.speed,
          speedAccuracy: position.speedAccuracy,
          altitudeAccuracy: position.altitudeAccuracy,
          headingAccuracy: position.headingAccuracy,
          floor: position.floor,
          isMocked: position.isMocked,
        );
      }

      // 🎥 Update camera to follow driver during navigation (only if locked)
      if (_isNavigationCameraLocked) {
        _updateNavigationCamera(effectivePosition);
      }

      // ✅ Update dual polylines with smooth transitions (traveled gray + remaining blue)
      _updateDualPolylinesSmooth(effectivePosition);
    });

    // OLD Timer-based approach (REMOVED - was not getting fresh location)
    // Timer.periodic(const Duration(seconds: 2), (timer) { ... });

    // Listen to navigation events
    _navigationService.eventStream.listen((event) {
      if (event.type == NavigationEventType.arrivedAtDestination) {
        setState(() {
          _isNavigating = false;
        });

        // 🎥 Exit navigation camera mode
        _disableNavigationCameraMode();

        // 🗺️ Switch back to default map style
        _switchToDefaultMapStyle();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎯 You have arrived at your destination!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    });
  }

  /// Enable professional navigation camera mode (3D tilt, heading-up)
  Future<void> _enableNavigationCameraMode() async {
    if (_mapboxMap == null) {
      debugPrint('❌ Cannot enable navigation camera: MapboxMap is null');
      return;
    }
    if (_currentPosition == null) {
      debugPrint('❌ Cannot enable navigation camera: Current position is null');
      return;
    }

    try {
      debugPrint('🎥 Enabling navigation camera mode');
      debugPrint(
        '   - Position: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}',
      );
      debugPrint('   - Heading: ${_currentPosition!.heading}');

      // ✅ Enable camera lock for auto-follow
      setState(() {
        _isNavigationCameraLocked = true;
      });

      // Mark as programmatic update
      _isProgrammaticCameraUpdate = true;

      // Calculate padding to offset puck to bottom of screen (Waze-style)
      // Adding top padding pushes the center point (the car) down
      final screenHeight = MediaQuery.of(context).size.height;
      final topPadding = screenHeight * 0.35; // Push down to bottom 1/3
      debugPrint('   - Screen height: $screenHeight, Top padding: $topPadding');

      // Set initial camera position with 3D tilt for navigation - following from behind
      await _mapboxMap!.flyTo(
        CameraOptions(
          center: Point(
            coordinates: Position(
              _currentPosition!.longitude,
              _currentPosition!.latitude,
            ),
          ),
          zoom: 18.0, // Start zoomed in
          bearing: _currentPosition!.heading, // Heading-up mode
          pitch: 60.0, // High tilt for 3D view
          padding: MbxEdgeInsets(top: topPadding, left: 0, bottom: 0, right: 0),
        ),
        MapAnimationOptions(duration: 1000, startDelay: 0),
      );

      // Reset flag after animation
      await Future.delayed(const Duration(milliseconds: 1100));
      _isProgrammaticCameraUpdate = false;

      debugPrint(
        '✅ Navigation camera mode enabled with auto-follow (Waze-style)',
      );
    } catch (e) {
      debugPrint('❌ Error enabling navigation camera: $e');
      _isProgrammaticCameraUpdate = false;
    }
  }

  /// Update camera to follow driver during navigation
  Future<void> _updateNavigationCamera(geo.Position location) async {
    if (_mapboxMap == null || !_isNavigating || !_isNavigationCameraLocked)
      return;

    try {
      // Mark as programmatic update to prevent listener from unlocking camera
      _isProgrammaticCameraUpdate = true;

      // Calculate dynamic camera properties based on speed (Waze-like feel)
      // Speed is in m/s, convert to km/h
      final speedKmh = (location.speed * 3.6).clamp(0.0, 100.0);

      // Dynamic Zoom & Pitch Logic:
      // 0 km/h: Zoom 18.0, Pitch 60 (Close up, high tilt)
      // 100 km/h: Zoom 15.0, Pitch 45 (Far out, lower tilt to see ahead)
      final t = speedKmh / 100.0; // 0.0 to 1.0

      final targetZoom = 18.0 - (3.0 * t); // Interpolate 18 -> 15
      final targetPitch = 60.0 - (15.0 * t); // Interpolate 60 -> 45

      // Offset the puck to the bottom of the screen
      final screenHeight = MediaQuery.of(context).size.height;
      final topPadding = screenHeight * 0.35; // Push down to bottom 1/3

      // Smoothly animate camera to follow driver
      await _mapboxMap!.easeTo(
        CameraOptions(
          center: Point(
            coordinates: Position(location.longitude, location.latitude),
          ),
          zoom: targetZoom,
          bearing: location.heading,
          pitch: targetPitch,
          padding: MbxEdgeInsets(top: topPadding, left: 0, bottom: 0, right: 0),
        ),
        MapAnimationOptions(
          duration: 900,
          startDelay: 0,
        ), // 900ms for smooth transition between 1s updates
      );

      // Reset flag after a short delay
      await Future.delayed(const Duration(milliseconds: 950));
      _isProgrammaticCameraUpdate = false;
    } catch (e) {
      debugPrint('❌ Error updating navigation camera: $e');
      _isProgrammaticCameraUpdate = false; // Reset on error
    }
  }

  /// Disable navigation camera mode and return to normal view
  Future<void> _disableNavigationCameraMode() async {
    if (_mapboxMap == null) return;

    try {
      debugPrint('🎥 Disabling navigation camera mode');

      // ✅ Disable camera lock (stop auto-follow)
      _isNavigationCameraLocked = false;

      // Return to normal top-down view
      await _mapboxMap!.flyTo(
        CameraOptions(
          center: _currentPosition != null
              ? Point(
                  coordinates: Position(
                    _currentPosition!.longitude,
                    _currentPosition!.latitude,
                  ),
                )
              : null,
          zoom: 15.0, // Standard zoom level
          bearing: 0.0, // North-up
          pitch: 0.0, // Flat view
        ),
        MapAnimationOptions(duration: 1000, startDelay: 0),
      );

      debugPrint('✅ Navigation camera mode disabled');
    } catch (e) {
      debugPrint('❌ Error disabling navigation camera: $e');
    }
  }

  /// 🗺️ Switch to navigation map style (custom premium style)
  Future<void> _switchToNavigationMapStyle() async {
    if (_mapboxMap == null) return;

    try {
      debugPrint('🗺️ Switching to navigation map style: $_navigationMapStyle');
      await _mapboxMap!.loadStyleURI(_navigationMapStyle);

      // Re-enable location puck after style change
      await Future.delayed(const Duration(milliseconds: 500));

      // Re-create modern driver puck
      final driverPuckImage = await _createDriverPuckImage();
      await _mapboxMap!.location.updateSettings(
        LocationComponentSettings(
          enabled: true,
          puckBearingEnabled: true,
          pulsingEnabled: true,
          pulsingColor: const Color(0xFF0EA5E9).value, // Cyan-blue pulse
          pulsingMaxRadius: 25.0,
          locationPuck: LocationPuck(
            locationPuck2D: LocationPuck2D(
              topImage: driverPuckImage,
              bearingImage: driverPuckImage,
              shadowImage: null,
            ),
          ),
        ),
      );

      // 🆕 ISSUE FIX #5: Redraw route polyline after style change
      if (_routeData != null) {
        debugPrint('🗺️ Redrawing route polyline after style change...');
        await _drawRouteOnMap(_routeData!);

        // Also redraw delivery pins
        if (_driverFlow.activeDelivery != null) {
          await _addDeliveryPins(_driverFlow.activeDelivery!);
        }
      }

      debugPrint('✅ Navigation map style loaded with route');
    } catch (e) {
      debugPrint('❌ Error loading navigation map style: $e');
    }
  }

  /// 🗺️ Switch back to default map style
  Future<void> _switchToDefaultMapStyle() async {
    if (_mapboxMap == null) return;

    try {
      debugPrint('🗺️ Switching to default map style: $_defaultMapStyle');
      await _mapboxMap!.loadStyleURI(_defaultMapStyle);

      // Re-enable location puck after style change
      await Future.delayed(const Duration(milliseconds: 500));

      // Re-create modern driver puck (orange pulse for idle mode)
      final driverPuckImage = await _createDriverPuckImage();
      await _mapboxMap!.location.updateSettings(
        LocationComponentSettings(
          enabled: true,
          puckBearingEnabled: true,
          pulsingEnabled: true,
          pulsingColor: const Color(0xFFFF6B35).value, // Orange pulse for idle
          pulsingMaxRadius: 25.0,
          locationPuck: LocationPuck(
            locationPuck2D: LocationPuck2D(
              topImage: driverPuckImage,
              bearingImage: driverPuckImage,
              shadowImage: null,
            ),
          ),
        ),
      );

      debugPrint('✅ Default map style loaded');
    } catch (e) {
      debugPrint('❌ Error loading default map style: $e');
    }
  }

  /// Re-center camera on driver position during navigation
  Future<void> _recenterNavigationCamera() async {
    if (_mapboxMap == null || _currentPosition == null || !_isNavigating)
      return;

    try {
      debugPrint('🎯 Re-centering navigation camera');

      // Mark as programmatic update
      _isProgrammaticCameraUpdate = true;

      // Lock camera back to auto-follow
      setState(() {
        _isNavigationCameraLocked = true;
      });

      // Animate back to navigation view
      await _mapboxMap!.flyTo(
        CameraOptions(
          center: Point(
            coordinates: Position(
              _currentPosition!.longitude,
              _currentPosition!.latitude,
            ),
          ),
          zoom: 17.0,
          bearing: _currentPosition!.heading,
          pitch: 55.0,
        ),
        MapAnimationOptions(duration: 800, startDelay: 0),
      );

      // Reset flag after animation
      await Future.delayed(const Duration(milliseconds: 900));
      _isProgrammaticCameraUpdate = false;

      debugPrint('✅ Navigation camera re-centered');
    } catch (e) {
      debugPrint('❌ Error re-centering camera: $e');
      _isProgrammaticCameraUpdate = false;
    }
  }

  /// Detect when user manually moves camera during navigation
  void _onCameraChange(CameraChangedEventData data) {
    // Ignore programmatic camera updates (auto-follow)
    if (_isProgrammaticCameraUpdate) {
      return;
    }

    // Only unlock if we're in navigation and camera is currently locked
    if (_isNavigating && _isNavigationCameraLocked) {
      // User is manually controlling camera - unlock auto-follow
      setState(() {
        _isNavigationCameraLocked = false;
      });
      debugPrint('🔓 Camera unlocked - user is manually controlling view');
    }
  }

  /// Handle delivery status change from draggable panel
  Future<void> _handleDeliveryStatusChange(DeliveryStage newStage) async {
    print('🔄 Delivery status changing to: ${newStage.name}');
    print(
      '🔄 Current delivery status before refresh: ${_driverFlow.activeDelivery?.status}',
    );

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
      print(
        '🔄 Delivery status after refresh: ${_driverFlow.activeDelivery?.status}',
      );

      // Get the updated delivery
      final updatedDelivery = _driverFlow.activeDelivery;

      // ✅ FIX: Update route when status changes (especially after package collection)
      if (updatedDelivery != null) {
        print(
          '🗺️ Updating route for new stage: ${updatedDelivery.currentStage.name}',
        );

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

    // 🗺️ ISSUE FIX #1: Switch back to default map style after delivery completion
    await _switchToDefaultMapStyle();

    // 🧭 ISSUE FIX: Stop navigation and reset camera
    if (_isNavigating) {
      await _navigationService.stopNavigation();
      setState(() {
        _isNavigating = false;
        _lastClosestIndex = null; // 🆕 Reset polyline tracking
      });
      _navigationLocationSubscription?.cancel(); // 🆕 Cancel subscription
      await _disableNavigationCameraMode();
    }

    // ✅ Clear ALL route polylines and markers (including traveled path)
    print('🧹 Clearing all polylines and markers after delivery completion');
    try {
      if (_routePolylineManager != null) {
        await _routePolylineManager!.deleteAll();
        _routePolylineManager = null;
        _currentRouteAnnotation = null;
      }
      if (_traveledRouteManager != null) {
        await _traveledRouteManager!.deleteAll();
        _traveledRouteManager = null;
        _traveledRouteAnnotation = null;
      }
      if (_pickupMarkerManager != null) {
        await _pickupMarkerManager!.deleteAll();
        _pickupMarkerManager = null;
      }
      if (_dropoffMarkerManager != null) {
        await _dropoffMarkerManager!.deleteAll();
        _dropoffMarkerManager = null;
      }

      // Clear route coordinates
      _originalRouteCoordinates = null;
      _routeData = null;

      print('✅ All polylines and markers cleared after delivery completion');
    } catch (e) {
      print('⚠️ Error clearing map resources: $e');
    }

    // Force UI update after clearing map resources
    if (mounted) {
      setState(() {
        // UI will rebuild without polylines/markers
      });
    }

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
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
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
      builder: (context) => EarningsModal(driverFlowService: _driverFlow),
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

      // 🎯 USE MAPBOX LOCATION PUCK with Maki car icon (modern, built-in)
      // Create a simple blue circle with white car icon overlay
      final driverPuckImage = await _createDriverPuckImage();

      await _mapboxMap!.location.updateSettings(
        LocationComponentSettings(
          enabled: true,
          puckBearingEnabled: true, // Show bearing/direction for navigation
          pulsingEnabled: true, // Pulsing animation
          pulsingColor: const Color(0xFF0EA5E9).value, // Cyan-blue pulse
          pulsingMaxRadius: 25.0,
          locationPuck: LocationPuck(
            locationPuck2D: LocationPuck2D(
              topImage: driverPuckImage,
              bearingImage: driverPuckImage,
              shadowImage: null,
            ),
          ),
        ),
      );

      print('✅ Mapbox navigation puck enabled successfully');

      // Center the map on the driver's location
      await _mapboxMap!.flyTo(
        CameraOptions(
          center: Point(
            coordinates: Position(position.longitude, position.latitude),
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
        await _mapboxMap!.location.updateSettings(
          LocationComponentSettings(enabled: false),
        );
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

  /// 🏢 Auto-accept business dispatch deliveries without showing modal
  /// Business dispatchers manually assign specific drivers, so no acceptance needed
  /// Note: Business deliveries arrive with status='driver_assigned' already set
  Future<void> _handleBusinessDispatchAutoAccept(Delivery delivery) async {
    print('🏢 *** AUTO-ACCEPTING BUSINESS DISPATCH DELIVERY ***');
    print('🏢 Delivery ID: ${delivery.id}');
    print('🏢 Business ID: ${delivery.businessId}');
    print('🏢 Driver: ${_currentDriver?.fullName}');
    print('🏢 Status: ${delivery.status}');

    if (_currentDriver == null) {
      print('❌ Cannot auto-accept: No current driver');
      return;
    }

    try {
      // Show loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                const Text('📦 Loading business delivery...'),
              ],
            ),
            backgroundColor: SwiftDashColors.darkBlue,
            duration: const Duration(seconds: 2),
          ),
        );
      }

      // 🏢 CRITICAL: Business deliveries are already assigned (status='driver_assigned')
      // We don't need to call acceptDeliveryOffer - just refresh and show the delivery
      print(
        '🏢 Delivery already assigned by dispatcher - skipping acceptance workflow',
      );

      // Refresh driver flow to load the active delivery
      print('🔄 Refreshing driver flow to load business delivery...');
      await _driverFlow.refreshActiveDelivery();

      // Wait for realtime update to propagate
      await Future.delayed(const Duration(milliseconds: 500));

      print('🔍 After refresh:');
      print('   - hasActiveDelivery: ${_driverFlow.hasActiveDelivery}');
      print('   - activeDelivery: ${_driverFlow.activeDelivery?.id}');
      print(
        '   - activeDelivery status: ${_driverFlow.activeDelivery?.status}',
      );

      // Check if delivery was actually loaded
      if (!_driverFlow.hasActiveDelivery) {
        print('⚠️ WARNING: Driver flow did not load active delivery');
        print(
          '⚠️ This might be because the delivery has not been committed to DB yet',
        );
        print('⚠️ Trying one more time after longer delay...');
        await Future.delayed(const Duration(seconds: 1));
        await _driverFlow.refreshActiveDelivery();
        print(
          '🔍 After second attempt: hasActiveDelivery=${_driverFlow.hasActiveDelivery}',
        );
      }

      // Update state to trigger rebuild and show panel
      setState(() {
        _currentDriver = _driverFlow.currentDriver;
        _currentOffer = null;
        _offerRouteData = null;
        // Force rebuild to show DraggableDeliveryPanel
      });

      // Clear any offer visualization
      await _clearOfferVisualization();

      // Show delivery route on map
      if (_driverFlow.hasActiveDelivery && _driverFlow.activeDelivery != null) {
        print('🗺️ Attempting to show delivery route...');
        print('🗺️ Map ready: ${_mapboxMap != null}');
        print('🗺️ Delivery ID: ${_driverFlow.activeDelivery!.id}');
        print(
          '🗺️ Pickup: (${_driverFlow.activeDelivery!.pickupLatitude}, ${_driverFlow.activeDelivery!.pickupLongitude})',
        );
        print(
          '🗺️ Delivery: (${_driverFlow.activeDelivery!.deliveryLatitude}, ${_driverFlow.activeDelivery!.deliveryLongitude})',
        );

        if (_mapboxMap != null) {
          await _showDeliveryRoute(_driverFlow.activeDelivery!);
          print('✅ Delivery route shown on map');
        } else {
          print('⚠️ Map not ready yet - will retry when map loads');
          // Store delivery to show route after map loads
          _pendingDeliveryForRoute = _driverFlow.activeDelivery;
        }
      } else {
        print('⚠️ Cannot show route: no active delivery after refresh');
      }

      print('🏢 ✅ Business dispatch delivery loaded successfully');
      print('📊 Active delivery: ${_driverFlow.activeDelivery?.id}');
      print(
        '📊 Panel should now be visible: hasActiveDelivery=${_driverFlow.hasActiveDelivery}',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.business, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '✅ Business delivery assigned! Pickup: ${delivery.pickupAddress}',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: SwiftDashColors.successGreen,
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'Navigate',
              textColor: Colors.white,
              onPressed: () {
                // Trigger navigation to pickup
                if (_driverFlow.activeDelivery != null) {
                  _showNavigationOptions(_driverFlow.activeDelivery!);
                }
              },
            ),
          ),
        );
      }
    } catch (e) {
      print('🏢 ❌ Error in business dispatch auto-accept: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error loading business delivery: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  /// Generate numbered marker image for multi-stop pins
  /// Returns Uint8List of PNG image with number overlay
  Future<Uint8List> _createNumberedMarkerImage(
    int number,
    Color backgroundColor,
  ) async {
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

      if (delivery.isMultiStop &&
          delivery.stops != null &&
          delivery.stops!.isNotEmpty) {
        // Multi-stop delivery: Build waypoints from stops
        print('�️ Multi-stop delivery with ${delivery.stops!.length} stops');
        final waypoints = delivery.stops!
            .map((stop) => Position(stop.longitude, stop.latitude))
            .toList();

        routeData = await routeService.fetchRoute(waypoints: waypoints);
      } else {
        // Single-stop delivery: Pickup → Delivery
        print('🗺️ Single-stop delivery');
        final start = Position(
          delivery.pickupLongitude,
          delivery.pickupLatitude,
        );
        final end = Position(
          delivery.deliveryLongitude,
          delivery.deliveryLatitude,
        );

        routeData = await routeService.fetchRoute(start: start, end: end);
      }

      if (routeData == null) {
        print('❌ Failed to fetch route preview');
        return;
      }

      print(
        '✅ Route preview fetched: ${routeData.formattedDistance}, ${routeData.formattedDuration}',
      );
      print(
        '   Waypoints: ${routeData.waypointCount}, Multi-stop: ${routeData.isMultiStop}',
      );

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
      _routePolylineManager = await _mapboxMap!.annotations
          .createPolylineAnnotationManager();

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
        _multiStopNumberedMarkers = await _mapboxMap!.annotations
            .createPointAnnotationManager();

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
          final position = Point(
            coordinates: Position(stop.longitude, stop.latitude),
          );
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
        // SINGLE-STOP: Add pickup and delivery pins with Maki icons
        print('🗺️ Adding pickup and delivery pins');

        // Create Point annotation managers
        _pickupMarkerManager = await _mapboxMap!.annotations
            .createPointAnnotationManager();
        _dropoffMarkerManager = await _mapboxMap!.annotations
            .createPointAnnotationManager();

        // 📍 Pickup marker (green circle - Maki icon)
        final pickupPosition = Point(
          coordinates: Position(
            delivery.pickupLongitude,
            delivery.pickupLatitude,
          ),
        );
        final pickupOptions = PointAnnotationOptions(
          geometry: pickupPosition,
          iconImage: 'circle-15', // Maki icon: green circle
          iconSize: 1.5,
          iconColor: 0xFF22C55E, // Green color (ARGB)
          iconHaloColor: 0xFFFFFFFF, // White halo/border (ARGB)
          iconHaloWidth: 2.0,
        );
        await _pickupMarkerManager!.create(pickupOptions);

        // 🎯 Delivery marker (red location pin - Maki icon)
        final deliveryPosition = Point(
          coordinates: Position(
            delivery.deliveryLongitude,
            delivery.deliveryLatitude,
          ),
        );
        final deliveryOptions = PointAnnotationOptions(
          geometry: deliveryPosition,
          iconImage: 'marker-15', // Maki icon: classic map pin
          iconSize: 2.0, // Larger for destination
          iconColor: 0xFFEF4444, // Red color (ARGB)
          iconHaloColor: 0xFFFFFFFF, // White halo/border (ARGB)
          iconHaloWidth: 2.0,
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

      print(
        '✅ Camera fitted to offer route - zoom: $zoom, bounds: [$minLat, $minLng] to [$maxLat, $maxLng]',
      );
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

        print(
          '📱 Staying on main map - DraggableDeliveryPanel will show active delivery',
        );
        print('📊 Active delivery: ${_driverFlow.activeDelivery?.id}');

        return true;
      } else {
        print(
          '❌ Database update failed - delivery may have been taken by another driver',
        );

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

      if (existingDelivery == null ||
          existingDelivery['status'] == 'cancelled') {
        print(
          '⚠️ Delivery no longer exists or already cancelled - just close modal',
        );
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
            center: Point(coordinates: Position(pos.longitude, pos.latitude)),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to get location: $e')));
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

      print(
        '✅ Route loaded: ${routeData.distance.toStringAsFixed(2)} km, ETA: ${routeData.duration} min',
      );
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

      _routePolylineManager = await _mapboxMap!.annotations
          .createPolylineAnnotationManager();

      // 🆕 Store original route coordinates for trimming later
      final lineString = LineString.fromJson(routeData.geometry);
      _originalRouteCoordinates = lineString.coordinates.toList();

      // Create polyline from route geometry (bright color for dark mode visibility)
      final polylineOptions = PolylineAnnotationOptions(
        geometry: lineString,
        lineColor: const Color(
          0xFF00D9FF,
        ).value, // ✅ Bright cyan - highly visible on dark maps
        lineWidth:
            8.0, // ✅ Increased width for better visibility during navigation
        lineOpacity: 1.0, // Full opacity
        lineJoin: LineJoin.ROUND, // Smooth corners
      );

      _currentRouteAnnotation = await _routePolylineManager!.create(
        polylineOptions,
      );

      // 🌟 Set emissive strength for dark mode visibility (makes polyline glow)
      await _routePolylineManager!.setLineEmissiveStrength(1.5);

      // Set line cap separately as it's not in options constructor
      await _routePolylineManager!.setLineCap(LineCap.ROUND);

      print(
        '✅ Route polyline drawn on map (${_originalRouteCoordinates?.length} points)',
      );
    } catch (e) {
      print('❌ Error drawing route: $e');
    }
  }

  /// 🆕 OPTION 1: Update route polyline to remove traveled segments (shrinking effect)
  /// ⚠️ DISABLED by default - uncomment in _setupNavigationLocationTracking() to enable
  Future<void> _updateRoutePolyline(geo.Position driverLocation) async {
    if (_routePolylineManager == null ||
        _currentRouteAnnotation == null ||
        _originalRouteCoordinates == null ||
        _originalRouteCoordinates!.isEmpty) {
      return;
    }

    try {
      // Find the closest point on the route to the driver's current location
      int closestIndex = _findClosestPointIndex(
        driverLocation.latitude,
        driverLocation.longitude,
        _originalRouteCoordinates!,
      );

      // If we're past the first few points, trim the route
      if (closestIndex > 2) {
        // Keep at least 2 points behind for smooth visuals (reduced from 5)
        // Get remaining coordinates (from closest point to end)
        final remainingCoordinates = _originalRouteCoordinates!.sublist(
          closestIndex,
        );

        // Update the polyline with trimmed route
        if (remainingCoordinates.length > 1) {
          await _routePolylineManager!.delete(_currentRouteAnnotation!);

          final updatedPolylineOptions = PolylineAnnotationOptions(
            geometry: LineString(coordinates: remainingCoordinates),
            lineColor: SwiftDashColors.lightBlue.value,
            lineWidth: 5.0,
            lineOpacity: 0.8,
          );

          _currentRouteAnnotation = await _routePolylineManager!.create(
            updatedPolylineOptions,
          );
          // 🌟 Set emissive strength for dark mode visibility
          await _routePolylineManager!.setLineEmissiveStrength(1.5);

          // Update the original coordinates to the new trimmed version
          _originalRouteCoordinates = remainingCoordinates;
        }
      }
    } catch (e) {
      debugPrint('❌ Error updating route polyline: $e');
    }
  }

  /// 🆕 OPTION 2: Dual polylines - traveled (gray) + remaining (blue)
  /// Shows progress visually without losing route visibility
  PolylineAnnotationManager? _traveledRouteManager;
  PolylineAnnotation? _traveledRouteAnnotation;

  /// 🎨 Option 4: Update dual polylines with smooth transitions
  /// Shows traveled path (gray) and remaining path (blue) with smooth updates
  Future<void> _updateDualPolylinesSmooth(geo.Position driverLocation) async {
    if (_routePolylineManager == null) {
      debugPrint('⚠️ Polyline update skipped: _routePolylineManager is null');
      return;
    }

    if (_originalRouteCoordinates == null ||
        _originalRouteCoordinates!.isEmpty) {
      debugPrint(
        '⚠️ Polyline update skipped: _originalRouteCoordinates is null or empty',
      );
      return;
    }

    try {
      // Initialize traveled route manager if needed
      if (_traveledRouteManager == null && _mapboxMap != null) {
        _traveledRouteManager = await _mapboxMap!.annotations
            .createPolylineAnnotationManager();
        debugPrint('✅ Traveled route manager created');
      }

      // Find the closest point on the route
      int closestIndex = _findClosestPointIndex(
        driverLocation.latitude,
        driverLocation.longitude,
        _originalRouteCoordinates!,
      );

      // Only update if driver has progressed significantly (prevents jittery updates)
      if (closestIndex > 0 && closestIndex > (_lastClosestIndex ?? 0)) {
        _lastClosestIndex = closestIndex;

        // Traveled path (gray/dimmed) - from start to current position
        final traveledCoordinates = _originalRouteCoordinates!.sublist(
          0,
          closestIndex + 1,
        );

        // Remaining path (bright blue) - from current position to destination
        final remainingCoordinates = _originalRouteCoordinates!.sublist(
          closestIndex,
        );

        // 🎨 Smooth transition: Update traveled polyline
        if (_traveledRouteAnnotation != null && _traveledRouteManager != null) {
          await _traveledRouteManager!.delete(_traveledRouteAnnotation!);
        }

        if (traveledCoordinates.length > 1 && _traveledRouteManager != null) {
          final traveledOptions = PolylineAnnotationOptions(
            geometry: LineString(coordinates: traveledCoordinates),
            lineColor: Colors.grey.withOpacity(0.4).value, // Subtle gray
            lineWidth: 6.0, // ✅ Increased width for traveled path
            lineOpacity: 0.5,
            lineJoin: LineJoin.ROUND,
          );
          _traveledRouteAnnotation = await _traveledRouteManager!.create(
            traveledOptions,
          );
          // 🌟 Set subtle glow for traveled path (dark mode visibility)
          await _traveledRouteManager!.setLineEmissiveStrength(0.5);
          await _traveledRouteManager!.setLineCap(LineCap.ROUND);
        }

        // 🎨 Smooth transition: Update remaining polyline
        if (_currentRouteAnnotation != null && _routePolylineManager != null) {
          await _routePolylineManager!.delete(_currentRouteAnnotation!);
        }

        if (remainingCoordinates.length > 1) {
          final remainingOptions = PolylineAnnotationOptions(
            geometry: LineString(coordinates: remainingCoordinates),
            lineColor: const Color(0xFF0EA5E9).value, // Vibrant cyan-blue
            lineWidth: 8.0, // ✅ Increased width for remaining route
            lineOpacity: 1.0,
            lineJoin: LineJoin.ROUND,
          );
          _currentRouteAnnotation = await _routePolylineManager!.create(
            remainingOptions,
          );
          // 🌟 Set strong glow for remaining route (dark mode visibility)
          await _routePolylineManager!.setLineEmissiveStrength(1.5);
          await _routePolylineManager!.setLineCap(LineCap.ROUND);
        }

        debugPrint(
          '✅ Smooth polyline update: traveled=${traveledCoordinates.length} pts, remaining=${remainingCoordinates.length} pts',
        );
      }
    } catch (e) {
      debugPrint('❌ Error updating dual polylines smoothly: $e');
    }
  }

  /// Old method kept for reference - not used
  Future<void> _updateDualPolylines(geo.Position driverLocation) async {
    if (_routePolylineManager == null ||
        _originalRouteCoordinates == null ||
        _originalRouteCoordinates!.isEmpty) {
      return;
    }

    try {
      // Initialize traveled route manager if needed
      if (_traveledRouteManager == null && _mapboxMap != null) {
        _traveledRouteManager = await _mapboxMap!.annotations
            .createPolylineAnnotationManager();
      }

      // Find the closest point on the route
      int closestIndex = _findClosestPointIndex(
        driverLocation.latitude,
        driverLocation.longitude,
        _originalRouteCoordinates!,
      );

      if (closestIndex > 0) {
        // Traveled path (gray/dimmed)
        final traveledCoordinates = _originalRouteCoordinates!.sublist(
          0,
          closestIndex + 1,
        );

        // Remaining path (bright blue)
        final remainingCoordinates = _originalRouteCoordinates!.sublist(
          closestIndex,
        );

        // Update traveled polyline
        if (_traveledRouteAnnotation != null && _traveledRouteManager != null) {
          await _traveledRouteManager!.delete(_traveledRouteAnnotation!);
        }

        if (traveledCoordinates.length > 1 && _traveledRouteManager != null) {
          final traveledOptions = PolylineAnnotationOptions(
            geometry: LineString(coordinates: traveledCoordinates),
            lineColor: Colors.grey.withOpacity(0.5).value, // Dimmed gray
            lineWidth: 4.0,
            lineOpacity: 0.6,
          );
          _traveledRouteAnnotation = await _traveledRouteManager!.create(
            traveledOptions,
          );
        }

        // Update remaining polyline
        if (_currentRouteAnnotation != null && _routePolylineManager != null) {
          await _routePolylineManager!.delete(_currentRouteAnnotation!);
        }

        if (remainingCoordinates.length > 1) {
          final remainingOptions = PolylineAnnotationOptions(
            geometry: LineString(coordinates: remainingCoordinates),
            lineColor: SwiftDashColors.lightBlue.value, // Bright blue
            lineWidth: 5.0,
            lineOpacity: 0.9,
          );
          _currentRouteAnnotation = await _routePolylineManager!.create(
            remainingOptions,
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Error updating dual polylines: $e');
    }
  }

  /// 🆕 Find the index of the closest point on the route to the driver's location
  int _findClosestPointIndex(
    double lat,
    double lon,
    List<Position> coordinates,
  ) {
    double minDistance = double.infinity;
    int closestIndex = 0;

    for (int i = 0; i < coordinates.length; i++) {
      final point = coordinates[i];
      final distance = _calculateDistance(
        lat,
        lon,
        point.lat.toDouble(),
        point.lng.toDouble(),
      );

      if (distance < minDistance) {
        minDistance = distance;
        closestIndex = i;
      }
    }

    return closestIndex;
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

      // 🎯 Create Point annotation managers for pickup and delivery icons
      _pickupMarkerManager = await _mapboxMap!.annotations
          .createPointAnnotationManager();
      _dropoffMarkerManager = await _mapboxMap!.annotations
          .createPointAnnotationManager();

      // Create custom marker images
      final pickupMarkerImage = await _createPickupMarkerImage();
      final dropoffMarkerImage = await _createDropoffMarkerImage();

      // 📍 Pickup marker (green circle with "P")
      final pickupOptions = PointAnnotationOptions(
        geometry: Point(
          coordinates: Position(
            delivery.pickupLongitude,
            delivery.pickupLatitude,
          ),
        ),
        image: pickupMarkerImage,
        iconSize: 1.5, // Larger size for better visibility
      );

      // 🎯 Delivery marker (red pin with "D")
      final deliveryOptions = PointAnnotationOptions(
        geometry: Point(
          coordinates: Position(
            delivery.deliveryLongitude,
            delivery.deliveryLatitude,
          ),
        ),
        image: dropoffMarkerImage,
        iconSize: 1.5, // Larger size for better visibility
      );

      await _pickupMarkerManager!.create(pickupOptions);
      await _dropoffMarkerManager!.create(deliveryOptions);

      print('✅ Pickup (green circle) and delivery (red pin) markers added');
    } catch (e) {
      print('❌ Error adding delivery pins: $e');
    }
  }

  /// Fit map to show entire delivery route
  Future<void> _fitMapToDeliveryRoute(Delivery delivery) async {
    if (_mapboxMap == null) return;

    try {
      // Calculate center point between pickup and delivery
      final centerLat =
          (delivery.pickupLatitude + delivery.deliveryLatitude) / 2;
      final centerLng =
          (delivery.pickupLongitude + delivery.deliveryLongitude) / 2;

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
  double _calculateDistance(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const double earthRadius = 6371; // Earth radius in km

    final dLat = _degreesToRadians(lat2 - lat1);
    final dLng = _degreesToRadians(lng2 - lng1);

    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(lat1)) *
            math.cos(_degreesToRadians(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);

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
    final channelName =
        'delivery-cancellations-${DateTime.now().millisecondsSinceEpoch}';

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
        .subscribe(); // ✅ Returns RealtimeChannel, not StreamSubscription

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
      // 🧭 CRITICAL: Stop navigation if active
      if (_isNavigating) {
        await _navigationService.stopNavigation();
        setState(() {
          _isNavigating = false;
          _lastClosestIndex = null; // Reset polyline tracking
        });
        _navigationLocationSubscription?.cancel(); // 🆕 Cancel subscription
        await _disableNavigationCameraMode();
        print('🧭 Navigation stopped due to cancellation');
      }

      // 🚨 CRITICAL: If this is the current offer, close the offer modal
      if (_currentOffer?.id == delivery.id) {
        print(
          '🚨 Cancelled delivery matches current offer - closing offer modal',
        );
        setState(() {
          _currentOffer = null;
          _offerRouteData = null;
        });
        await _clearOfferVisualization();
      }

      // ✅ Clear ALL map visualization (polylines, markers, INCLUDING traveled route)
      print('🧹 Clearing all polylines and markers after cancellation');
      await _clearDeliveryRoute();

      // Clear traveled route polyline (for dual polyline navigation)
      if (_traveledRouteManager != null) {
        await _traveledRouteManager!.deleteAll();
        _traveledRouteManager = null;
        _traveledRouteAnnotation = null;
      }

      // Clear route coordinates
      _originalRouteCoordinates = null;
      _routeData = null;

      print('✅ All polylines and markers cleared after cancellation');

      // 🗺️ Switch back to default map style
      await _switchToDefaultMapStyle();

      // 🎯 DISABLE LOCATION PUCK when delivery is cancelled
      if (_mapboxMap != null) {
        await _mapboxMap!.location.updateSettings(
          LocationComponentSettings(enabled: false),
        );
        print('✅ Location puck disabled after cancellation');
      }

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

      print(
        '✅ Delivery cancellation handled - panel, puck, and routes cleared',
      );
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

  /// Create a modern driver puck image with directional arrow
  /// This replaces the old custom chevron with a cleaner, more professional look
  Future<Uint8List> _createDriverPuckImage() async {
    const size =
        140.0; // ✅ FIX: Increased from 100 to 140 for better visibility
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));
    final centerX = size / 2;
    final centerY = size / 2;

    // Draw outer circle (white border)
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(centerX, centerY),
      32,
      borderPaint,
    ); // Increased from 22

    // Draw inner circle (blue background)
    final circlePaint = Paint()
      ..color =
          const Color(0xFF0EA5E9) // Cyan-blue
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(centerX, centerY),
      28,
      circlePaint,
    ); // Increased from 18

    // Draw directional arrow (white, pointing up - bearing will rotate)
    final arrowPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final arrowPath = Path();
    // Sharp arrow pointing upward (scaled up)
    arrowPath.moveTo(centerX, centerY - 18); // Top point (was -12)
    arrowPath.lineTo(centerX + 12, centerY - 3); // Right upper (was +8, -2)
    arrowPath.lineTo(centerX + 6, centerY - 3); // Right inner (was +4, -2)
    arrowPath.lineTo(centerX + 6, centerY + 15); // Right bottom (was +4, +10)
    arrowPath.lineTo(centerX - 6, centerY + 15); // Left bottom (was -4, +10)
    arrowPath.lineTo(centerX - 6, centerY - 3); // Left inner (was -4, -2)
    arrowPath.lineTo(centerX - 12, centerY - 3); // Left upper (was -8, -2)
    arrowPath.close();

    canvas.drawPath(arrowPath, arrowPaint);

    // Convert to image
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    return byteData!.buffer.asUint8List();
  }

  /// Create pickup marker image (green circle with "P")
  Future<Uint8List> _createPickupMarkerImage() async {
    const size = 80.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));
    final centerX = size / 2;
    final centerY = size / 2;

    // Draw shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(Offset(centerX + 2, centerY + 2), 25, shadowPaint);

    // Draw white border
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(centerX, centerY), 25, borderPaint);

    // Draw green circle
    final circlePaint = Paint()
      ..color =
          const Color(0xFF22C55E) // Green
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(centerX, centerY), 22, circlePaint);

    // Draw "P" letter in white
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'P',
        style: TextStyle(
          color: Colors.white,
          fontSize: 32,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(centerX - textPainter.width / 2, centerY - textPainter.height / 2),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    return byteData!.buffer.asUint8List();
  }

  /// Create dropoff marker image (red map pin with "D")
  Future<Uint8List> _createDropoffMarkerImage() async {
    const size = 100.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));
    final centerX = size / 2;
    final centerY = size / 2;

    // Draw shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(Offset(centerX + 2, centerY + 2), 20, shadowPaint);

    // Draw pin shape path
    final pinPath = Path();
    pinPath.addOval(
      Rect.fromCircle(center: Offset(centerX, centerY - 10), radius: 20),
    );
    pinPath.moveTo(centerX, centerY + 10);
    pinPath.lineTo(centerX - 12, centerY - 5);
    pinPath.lineTo(centerX + 12, centerY - 5);
    pinPath.close();

    // Draw white border for pin
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawPath(pinPath, borderPaint);

    // Draw red pin fill
    final pinPaint = Paint()
      ..color =
          const Color(0xFFEF4444) // Red
      ..style = PaintingStyle.fill;
    canvas.drawPath(pinPath, pinPaint);

    // Draw "D" letter in white
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'D',
        style: TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        centerX - textPainter.width / 2,
        centerY - 10 - textPainter.height / 2,
      ),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    return byteData!.buffer.asUint8List();
  }
}
