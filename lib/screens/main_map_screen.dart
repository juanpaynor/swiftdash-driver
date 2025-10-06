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
      
      _isOnline = _currentDriver?.isOnline ?? false;
      
      // Listen for automatic offer popups (subscriptions initialized by driver flow service)
      if (_currentDriver != null) {
        // Listen for automatic offer popups
        _realtimeService.offerModalStream.listen((delivery) {
          if (mounted && _isOnline) {
            _showAutomaticOfferModal(delivery);
          }
        });
      }
      
      if (_isOnline) {
        _onlineToggleController.forward();
      }
      
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
    );
  }
  
  void _toggleOnlineStatus() async {
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
          
          // Start continuous location tracking when going online
          if (_currentDriver != null) {
            try {
              await OptimizedLocationService().startDeliveryTracking(
                driverId: _currentDriver!.id,
                deliveryId: 'driver_online_${_currentDriver!.id}', // Unique ID for online tracking
              ).timeout(
                const Duration(seconds: 10),
                onTimeout: () {
                  print('⚠️ Start location tracking timed out');
                },
              );
              print('📍 Continuous location tracking started');
            } catch (e) {
              print('❌ Error starting location tracking: $e');
            }
          }
          
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
      // Get current location first
      print('🔍 Getting current location for pin...');
      final position = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.high,
      );
      
      _currentPosition = position;
      print('📍 Current position: ${position.latitude}, ${position.longitude}');
      
      // Create a circle annotation for the driver's location instead of point
      final circleAnnotationManager = await _mapboxMap!.annotations.createCircleAnnotationManager();
      
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
      
      await circleAnnotationManager.create(circleAnnotationOptions);
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
    if (_mapboxMap == null) {
      print('❌ MapboxMap is null, cannot remove location pin');
      return;
    }
    
    try {
      // Remove all circle annotations (driver location)
      final circleAnnotationManager = await _mapboxMap!.annotations.createCircleAnnotationManager();
      await circleAnnotationManager.deleteAll();
      
      // Also remove any point annotations just in case
      final pointAnnotationManager = await _mapboxMap!.annotations.createPointAnnotationManager();
      await pointAnnotationManager.deleteAll();
      
      print('✅ Driver location pin removed successfully');
    } catch (e) {
      print('❌ Error removing driver location pin: $e');
    }
  }
  
  // Show automatic offer modal when new delivery offers arrive
  void _showAutomaticOfferModal(Delivery delivery) {
    if (!_isOnline || _currentDriver == null) return;
    
    RealtimeService.showImprovedOfferModal(
      context,
      delivery,
      (deliveryId, driverId) async {
        // Use driver flow service to accept the offer
        final success = await _driverFlow.acceptDeliveryOffer(context, delivery);
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