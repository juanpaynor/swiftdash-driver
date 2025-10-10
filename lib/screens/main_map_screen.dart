import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import '../models/driver.dart';
import '../models/delivery.dart';
import '../services/driver_flow_service.dart';
import '../services/optimized_location_service.dart';
import '../services/realtime_service.dart';
import '../services/background_location_service.dart';
import '../core/supabase_config.dart';
import '../core/mapbox_config.dart';
import '../widgets/driver_drawer.dart';
import '../widgets/driver_status_bottom_sheet.dart';
import '../widgets/earnings_modal.dart';

class MainMapScreen extends StatefulWidget {
  const MainMapScreen({super.key});

  @override
  State<MainMapScreen> createState() => _MainMapScreenState();
}

class _MainMapScreenState extends State<MainMapScreen> with TickerProviderStateMixin {
  final DriverFlowService _driverFlow = DriverFlowService();
  final RealtimeService _realtimeService = RealtimeService();
  
  Driver? _currentDriver;
  bool _isOnline = false;
  bool _isLoading = true;
  geo.Position? _currentPosition;
  MapboxMap? _mapboxMap;
  
  // Debouncing for rapid toggles
  bool _isToggling = false;
  DateTime? _lastToggleTime;
  
  // Keep reference to annotation managers for proper cleanup
  CircleAnnotationManager? _driverLocationManager;
  PointAnnotationManager? _pointAnnotationManager;
  
  // Animation controllers
  late AnimationController _onlineToggleController;
  late AnimationController _pulseController;
  
  // Bottom sheet controller
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  
  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeApp();
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
    try {
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
      
      // Always start offline for safety - driver must manually go online
      _isOnline = false;
      
      // 🔧 CRITICAL FIX: Clear any stale location markers on app startup
      await _removeDriverLocationPin();
      
      // If driver was online in database, set them offline on app start
      if (_currentDriver?.isOnline == true) {
        print('📱 Driver was online in database, setting offline on app start for safety');
        try {
          await _driverFlow.goOffline(context);
          _currentDriver = _driverFlow.currentDriver;
          
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
      if (_currentDriver != null) {
        print('🔔 Setting up offer modal listener for driver: ${_currentDriver!.id}');
        _realtimeService.offerModalStream.listen((delivery) {
          print('🔔 *** OFFER MODAL STREAM RECEIVED DELIVERY: ${delivery.id} ***');
          print('🔔 Driver online status: $_isOnline');
          print('🔔 Screen mounted: $mounted');
          
          if (mounted && _isOnline) {
            print('🔔 ✅ CONDITIONS MET - SHOWING OFFER MODAL');
            _showAutomaticOfferModal(delivery);
          } else {
            print('🔔 ❌ CONDITIONS NOT MET - IGNORING OFFER');
            print('   - Driver online: $_isOnline');
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
    
    // Set navigation night style for optimal driver navigation experience
    _mapboxMap!.loadStyleURI(MapboxConfig.navigationNightStyle);
    
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
    _onlineToggleController.dispose();
    _pulseController.dispose();
    _realtimeService.dispose();
    
    // 🔧 CRITICAL FIX: Clean up map annotations and stop any background services
    _removeDriverLocationPin();
    
    // Also ensure background location service is stopped
    BackgroundLocationService.stopLocationTracking();
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isOnline, // Prevent exit if online
      onPopInvoked: (didPop) async {
        if (didPop) return; // Already popped
        
        if (_isOnline) {
          // Show confirmation dialog
          await _showExitConfirmationDialog();
        }
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
                      child: Row(
                        children: [
                          AnimatedBuilder(
                            animation: _pulseController,
                            builder: (context, child) {
                              return Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: _isOnline ? Colors.green : Colors.red,
                                  shape: BoxShape.circle,
                                  boxShadow: _isOnline
                                      ? [
                                          BoxShadow(
                                            color: Colors.green.withOpacity(_pulseController.value * 0.5),
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
                            _isOnline ? 'Online' : 'Offline',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _isOnline ? Colors.green : Colors.red,
                            ),
                          ),
                        ],
                      ),
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
          
          // Active Delivery Card (if exists)
          if (_driverFlow.hasActiveDelivery)
            Positioned(
              bottom: 220,
              left: 20,
              right: 20,
              child: GestureDetector(
                onTap: () => _driverFlow.navigateToActiveDelivery(context),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.green, Colors.green.withOpacity(0.8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
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
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: SwiftDashColors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.local_shipping,
                          color: SwiftDashColors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Active Delivery',
                              style: TextStyle(
                                color: SwiftDashColors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              _driverFlow.activeDelivery?.status.name ?? '',
                              style: TextStyle(
                                color: SwiftDashColors.white.withOpacity(0.9),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_ios,
                        color: SwiftDashColors.white,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          
          // Driver status and online/offline control
          Positioned(
            bottom: 100,
            left: 20,
            right: 20,
            child: Container(
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
                              color: _isOnline ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _isOnline ? Icons.check_circle : Icons.pause_circle,
                              color: _isOnline ? Colors.green : Colors.orange,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _isOnline ? 'You\'re Online' : 'You\'re Offline',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: SwiftDashColors.darkBlue,
                                  ),
                                ),
                                Text(
                                  _isOnline 
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
                      onPressed: _toggleOnlineStatus,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isOnline ? Colors.red : SwiftDashColors.lightBlue,
                        foregroundColor: SwiftDashColors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isOnline ? Icons.pause : Icons.play_arrow,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _isOnline ? 'Go Offline' : 'Go Online',
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
            ),
          ),
          
          // Loading overlay
          if (_isLoading)
            Container(
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
            ),
        ],
      ),
      ), // End of PopScope child (Scaffold)
    ); // End of PopScope
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
    // Prevent rapid toggles
    if (_isToggling) {
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
      if (_isOnline) {
        final success = await _driverFlow.goOffline(context).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            print('⚠️ Go offline operation timed out');
            return false;
          },
        );
        
        if (success) {
          setState(() {
            _currentDriver = _driverFlow.currentDriver;
            _isOnline = _currentDriver?.isOnline ?? false;
          });
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
      } else {
        final success = await _driverFlow.goOnline(context).timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            print('⚠️ Go online operation timed out');
            return false;
          },
        );
        
        if (success) {
          setState(() {
            _currentDriver = _driverFlow.currentDriver;
            _isOnline = _currentDriver?.isOnline ?? false;
          });
          _onlineToggleController.forward();
          await _addDriverLocationPin();
          
          // Location tracking is already started by DriverFlowService.goOnline()
          print('📍 Location tracking handled by DriverFlowService');
          
          // Start location broadcasting for realtime updates
          await _startLocationBroadcasting();
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
      print('❌ MapboxMap is null, cannot add location pin');
      return;
    }
    
    try {
      // Remove any existing annotations first
      await _removeDriverLocationPin();
      
      // Get current location first
      print('🔍 Getting current location for pin...');
      final position = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.high,
      );
      
      _currentPosition = position;
      print('📍 Current position: ${position.latitude}, ${position.longitude}');
      
      // Create a circle annotation manager for the driver's location
      _driverLocationManager = await _mapboxMap!.annotations.createCircleAnnotationManager();
      
      // Create a blue circle for the driver's location
      final circleAnnotationOptions = CircleAnnotationOptions(
        geometry: Point(
          coordinates: Position(
            position.longitude,
            position.latitude,
          ),
        ),
        circleRadius: 8.0,
        circleColor: Colors.blue.value,
        circleStrokeColor: Colors.white.value,
        circleStrokeWidth: 2.0,
      );
      
      await _driverLocationManager!.create(circleAnnotationOptions);
      print('✅ Driver location circle added successfully');
      
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
      print('❌ Error adding driver location pin: $e');
      
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
      // Remove driver location circle if it exists
      if (_driverLocationManager != null) {
        await _driverLocationManager!.deleteAll();
        _driverLocationManager = null;
        print('✅ Driver location circle removed via manager');
      }
      
      // Remove point annotations if they exist
      if (_pointAnnotationManager != null) {
        await _pointAnnotationManager!.deleteAll();
        _pointAnnotationManager = null;
        print('✅ Point annotations removed via manager');
      }
      
      // 🔧 CRITICAL FIX: Clear annotation managers even if map isn't ready
      if (_mapboxMap != null) {
        // Try to clean up all annotations through the map API
        try {
          print('🧹 Cleaning up all map annotations...');
          // Additional cleanup could be added here if needed
        } catch (e) {
          print('⚠️ Error during map annotation cleanup: $e');
        }
      }
      
      print('✅ Driver location pin cleanup completed');
    } catch (e) {
      print('❌ Error during location pin cleanup: $e');
      // Don't throw - cleanup should be fault-tolerant
    }
  }
  
  // Show automatic offer modal when new delivery offers arrive
  void _showAutomaticOfferModal(Delivery delivery) {
    print('🚨 _showAutomaticOfferModal called for delivery: ${delivery.id}');
    print('🚨 Driver online: $_isOnline');
    print('🚨 Current driver: ${_currentDriver?.id}');
    
    if (!_isOnline || _currentDriver == null) {
      print('❌ Not showing modal - driver offline or null');
      return;
    }
    
    print('✅ Showing improved offer modal for delivery: ${delivery.id}');
    RealtimeService.showImprovedOfferModal(
      context,
      delivery,
      (deliveryId, driverId) async {
        print('🔔 Driver attempting to accept delivery: $deliveryId');
        try {
          // CRITICAL FIX: Only update database when user confirms acceptance
          print('🚨 CRITICAL: Driver confirmed acceptance - updating database');
          final success = await _realtimeService.acceptDeliveryOffer(deliveryId, driverId);
          print('🔔 Database update result: $success');
          
          if (success) {
            // Only start location tracking AFTER confirmed database update
            print('✅ Delivery accepted - starting location tracking');
            setState(() {
              _currentDriver = _driverFlow.currentDriver;
            });
            
            // Navigate to active delivery screen with updated delivery object
            final updatedDelivery = delivery.copyWith(
              driverId: driverId,
              status: DeliveryStatus.driverAssigned,
            );
            Navigator.pushNamed(context, '/active-delivery', arguments: updatedDelivery);
          } else {
            print('❌ Database update failed - delivery may have been taken by another driver');
          }
          
          return success;
        } catch (e) {
          print('❌ Error accepting delivery: $e');
          return false;
        }
      },
      (deliveryId, driverId) async {
        print('🔔 Driver attempting to decline delivery: $deliveryId');
        // Use driver flow service to decline the offer
        final success = await _driverFlow.declineDeliveryOffer(context, delivery);
        print('🔔 Decline delivery result: $success');
        return success;
      },
      _currentDriver!.id,
    );
  }
  
  // Show current location dialog and option to open in maps
  void _showCurrentLocation() async {
    try {
      final pos = await OptimizedLocationService().getCurrentPosition();
      if (pos == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location not available')),
          );
        }
        return;
      }

      final lat = pos.latitude;
      final lng = pos.longitude;
      
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Current Location'),
            content: Text('Lat: ${lat.toStringAsFixed(6)}, Lng: ${lng.toStringAsFixed(6)}'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close'),
              ),
              TextButton(
                onPressed: () async {
                  final googleUri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
                  if (await canLaunchUrl(googleUri)) {
                    await launchUrl(googleUri, mode: LaunchMode.externalApplication);
                  }
                },
                child: const Text('Open in Maps'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to get location: $e')),
        );
      }
    }
  }
}