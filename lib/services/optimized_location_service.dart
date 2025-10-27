import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'realtime_service.dart';
import 'background_location_service.dart';

class OptimizedLocationService {
  static final OptimizedLocationService _instance = OptimizedLocationService._internal();
  factory OptimizedLocationService() => _instance;
  OptimizedLocationService._internal();

  final OptimizedRealtimeService _realtimeService = OptimizedRealtimeService();
  
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<Position>? _idleListenerSubscription;
  Timer? _broadcastTimer;
  Timer? _fallbackTimer;
  Timer? _healthCheckTimer;
  
  String? _currentDeliveryId;
  bool _isTracking = false;
  
  Position? _lastPosition;
  DateTime? _lastBroadcastTime;
  
  // Callback for idle location listening
  Function(Position)? _idleLocationCallback;
  
  // Circuit breaker for WebSocket errors
  int _consecutiveWebSocketErrors = 0;
  DateTime? _lastWebSocketErrorTime;
  static const int _maxConsecutiveErrors = 3;
  static const Duration _errorCooldown = Duration(minutes: 2);

  // 🔹 ADAPTIVE LOCATION FREQUENCY SYSTEM

  /// Start adaptive location tracking for a delivery
  Future<void> startDeliveryTracking({
    required String driverId,
    required String deliveryId,
  }) async {
    if (_isTracking) {
      await stopTracking();
    }

    _currentDeliveryId = deliveryId;
    _isTracking = true;

    print('📍 Starting adaptive location tracking for delivery: $deliveryId');

    // Check location permissions
    if (!await _checkLocationPermissions()) {
      throw Exception('Location permissions not granted');
    }

    // Start foreground location stream
    await _startLocationStream();
    
    // ✅ FIX: Don't call startLocationBroadcast() - creates infinite loop
    // Location broadcasting is now handled by DriverLocationService (Ably only)
    // This service is DEPRECATED and should not be used
    print('⚠️ OptimizedLocationService is deprecated - use DriverLocationService instead');

    // 🚫 Background service temporarily disabled due to notification crash issues
    // The background service is causing local notification crashes due to missing icon resources
    // TODO: Fix notification configuration and re-enable
    print('⚠️ Background location service temporarily disabled - using foreground-only tracking');

    // Start WebSocket health check timer
    _startHealthCheck();

    print('✅ Adaptive location tracking started (foreground + background + health check)');
  }

  /// Stop location tracking
  Future<void> stopTracking() async {
    if (!_isTracking) return;

    print('📍 Stopping location tracking');

    await _positionSubscription?.cancel();
    _positionSubscription = null;
    
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    
    // Stop fallback timer if running
    _stopFallbackLocationPolling();

    // Stop background service (with error handling)
    try {
      await BackgroundLocationService.stopLocationTracking();
    } catch (e) {
      print('⚠️ Error stopping background service: $e');
      // Continue anyway
    }

    _fallbackTimer?.cancel();
    _healthCheckTimer?.cancel();
    _isTracking = false;
    _currentDeliveryId = null;
    _lastPosition = null;
    _lastBroadcastTime = null;

    print('✅ Location tracking stopped (foreground + background + health check)');
  }

  /// Start WebSocket health check timer
  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    
    // 🚫 DISABLED: Health check creates infinite loop by calling startLocationBroadcast
    // This service is deprecated - DriverLocationService handles all location tracking
    print('⚠️ Health check disabled - OptimizedLocationService is deprecated');
    
    // Check WebSocket health every 30 seconds
    // _healthCheckTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
    //   if (_currentDeliveryId != null) {
    //     if (!_realtimeService.isWebSocketHealthy(_currentDeliveryId!)) {
    //       print('🔄 WebSocket unhealthy, attempting recovery...');
    //       _realtimeService.startLocationBroadcast(_currentDeliveryId!).catchError((e) {
    //         print('❌ Failed to recover WebSocket: $e');
    //       });
    //     } else {
    //       print('✅ WebSocket health check: OK');
    //     }
    //   }
    // });
  }

  /// Check and request location permissions
  Future<bool> _checkLocationPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print('❌ Location services are disabled');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        print('❌ Location permissions are denied');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      print('❌ Location permissions are permanently denied');
      return false;
    }

    return true;
  }

  /// Start location stream with adaptive settings
  Future<void> _startLocationStream() async {
    try {
      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // Only update if moved 5 meters
      );

      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        _handleLocationUpdate,
        onError: (error) {
          print('❌ Location stream error: $error');
          // Try to restart stream after error with delay
          if (_isTracking) {
            print('🔄 Restarting location stream in 5 seconds...');
            Timer(Duration(seconds: 5), () {
              if (_isTracking) {
                _startLocationStream();
              }
            });
          }
        },
        onDone: () {
          print('📍 Location stream completed');
          // Restart stream if tracking is still active
          if (_isTracking) {
            print('🔄 Restarting location stream...');
            _startLocationStream();
          }
        },
      );
      
      print('📍 Location stream started successfully');
      
    } catch (e) {
      print('❌ CRITICAL: Failed to start location stream: $e');
      print('🛡️ This may be due to Android system location service failure');
      
      // Try fallback approach - get location periodically instead of stream
      if (_isTracking) {
        print('🔄 Trying fallback location polling...');
        _startFallbackLocationPolling();
      }
    }
  }

  /// Handle location updates with adaptive broadcasting
  void _handleLocationUpdate(Position position) {
    _lastPosition = position;
    
    // Calculate speed in km/h
    final speedKmH = (position.speed * 3.6).clamp(0.0, 200.0);
    
    // Determine if we should broadcast based on adaptive frequency
    final shouldBroadcast = _shouldBroadcastLocation(speedKmH);
    
    if (shouldBroadcast) {
      _broadcastCurrentLocation(position, speedKmH);
    }
  }

  /// Adaptive frequency logic - determines when to broadcast
  bool _shouldBroadcastLocation(double speedKmH) {
    final now = DateTime.now();
    
    // Always broadcast first location
    if (_lastBroadcastTime == null) {
      return true;
    }
    
    final timeSinceLastBroadcast = now.difference(_lastBroadcastTime!);
    final requiredInterval = _getUpdateInterval(speedKmH);
    
    return timeSinceLastBroadcast >= requiredInterval;
  }

  /// Get adaptive update interval based on speed and activity
  Duration _getUpdateInterval(double speedKmH) {
    // During active delivery - REAL-TIME UPDATES for customer tracking
    if (_currentDeliveryId != null) {
      if (speedKmH > 50) {
        return const Duration(seconds: 3);  // Highway speed - frequent updates
      } else if (speedKmH > 20) {
        return const Duration(seconds: 4);  // City driving - frequent updates
      } else if (speedKmH > 5) {
        return const Duration(seconds: 5);  // Slow movement - moderate updates
      } else {
        return const Duration(seconds: 10);  // Stationary - reduced updates
      }
    }
    
    // Available but not delivering
    return const Duration(minutes: 5);
  }

  /// Broadcast location via realtime service with circuit breaker
  void _broadcastCurrentLocation(Position position, double speedKmH) {
    if (_currentDeliveryId == null) return;

    // Circuit breaker: Check if we're in error cooldown
    if (_consecutiveWebSocketErrors >= _maxConsecutiveErrors) {
      if (_lastWebSocketErrorTime != null) {
        final timeSinceLastError = DateTime.now().difference(_lastWebSocketErrorTime!);
        if (timeSinceLastError < _errorCooldown) {
          // Still in cooldown period, skip broadcast
          return;
        } else {
          // Cooldown expired, reset error counter
          print('🔄 WebSocket error cooldown expired, resuming broadcasts');
          _consecutiveWebSocketErrors = 0;
          _lastWebSocketErrorTime = null;
        }
      }
    }

    // Check WebSocket health before broadcasting
    if (!_realtimeService.isWebSocketHealthy(_currentDeliveryId!)) {
      _handleWebSocketError('WebSocket unhealthy');
      return;
    }

    try {
      _realtimeService.broadcastLocation(
        deliveryId: _currentDeliveryId!,
        latitude: position.latitude,
        longitude: position.longitude,
        speedKmH: speedKmH,
        heading: position.heading,
        accuracy: position.accuracy,
      );
      
      // Reset error counter on successful broadcast
      _consecutiveWebSocketErrors = 0;
      
    } catch (e) {
      _handleWebSocketError('Broadcast failed: $e');
    }

    _lastBroadcastTime = DateTime.now();
    
    print('📡 Broadcasted location: ${position.latitude}, ${position.longitude} (${speedKmH.toStringAsFixed(1)} km/h)');
  }

  // 🔹 CRITICAL EVENT LOCATION STORAGE

  /// Store location for critical delivery events (pickup, delivery, etc.)
  Future<void> storeLocationForEvent(String eventType) async {
    if (_lastPosition == null || _currentDeliveryId == null) {
      print('⚠️ Cannot store location - no position or delivery ID');
      return;
    }

    await _realtimeService.storeLocationForCriticalEvent(
      eventType: eventType,
      deliveryId: _currentDeliveryId!,
      latitude: _lastPosition!.latitude,
      longitude: _lastPosition!.longitude,
    );

    print('💾 Stored location for event: $eventType');
  }

  // 🔹 UTILITY METHODS

  /// Get current position immediately
  Future<Position?> getCurrentPosition() async {
    try {
      if (!await _checkLocationPermissions()) {
        return null;
      }

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      print('❌ Error getting current position: $e');
      return null;
    }
  }

  /// Get last known position
  Position? get lastPosition => _lastPosition;

  /// Check if currently tracking
  bool get isTracking => _isTracking;

  /// Get current delivery ID
  String? get currentDeliveryId => _currentDeliveryId;

  /// Calculate distance between two points
  static double calculateDistance(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  ) {
    return Geolocator.distanceBetween(
      startLatitude,
      startLongitude,
      endLatitude,
      endLongitude,
    );
  }

  /// Format coordinates for display
  static String formatCoordinates(double latitude, double longitude) {
    return '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
  }

  // 🔹 BATTERY OPTIMIZATION

  /// Enable battery optimization mode (less frequent updates)
  void enableBatteryOptimization() {
    // Reduce location accuracy to save battery
    _stopLocationStream();
    _startLocationStreamOptimized();
  }

  /// Start battery-optimized location stream
  Future<void> _startLocationStreamOptimized() async {
    try {
      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.medium, // Reduced accuracy for battery saving
        distanceFilter: 10, // Only update if moved 10 meters
      );

      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        _handleLocationUpdate,
        onError: (error) {
          print('❌ Battery-optimized location stream error: $error');
          // Try to restart stream after error
          if (_isTracking) {
            print('🔄 Restarting optimized location stream in 5 seconds...');
            Timer(Duration(seconds: 5), () {
              if (_isTracking) {
                _startLocationStreamOptimized();
              }
            });
          }
        },
      );
      
      print('📍 Battery-optimized location stream started successfully');
      
    } catch (e) {
      print('❌ CRITICAL: Failed to start battery-optimized location stream: $e');
      print('🛡️ This may be due to Android system location service failure');
      
      // Try fallback approach
      if (_isTracking) {
        print('🔄 Trying fallback location polling...');
        _startFallbackLocationPolling();
      }
    }
  }

  /// Disable battery optimization (full accuracy)
  void disableBatteryOptimization() {
    _stopLocationStream();
    _startLocationStream();
  }

  /// Stop location stream
  void _stopLocationStream() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  // 🔹 CLEANUP

  /// Dispose of all resources
  Future<void> dispose() async {
    await stopTracking();
    stopListening();
    print('🧹 OptimizedLocationService disposed');
  }

  // 🔹 IDLE LOCATION LISTENING (for IdleLocationUpdateService)

  /// Start listening to location changes (for idle drivers)
  void startListening(Function(Position) onLocationChange) {
    if (_idleListenerSubscription != null) {
      print('⚠️ Location listener already active');
      return;
    }

    _idleLocationCallback = onLocationChange;

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.medium, // Lower accuracy for battery saving
      distanceFilter: 10, // Only notify if moved 10 meters
    );

    _idleListenerSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (position) {
        _idleLocationCallback?.call(position);
      },
      onError: (error) {
        print('❌ Idle location listener error: $error');
      },
    );

    print('📍 Started idle location listener');
  }

  /// Stop listening to location changes
  void stopListening() {
    _idleListenerSubscription?.cancel();
    _idleListenerSubscription = null;
    _idleLocationCallback = null;
    print('📍 Stopped idle location listener');
  }
}

// 🔹 LOCATION SERVICE EXTENSIONS

extension LocationServiceExtensions on OptimizedLocationService {
  /// Start tracking with automatic event storage
  Future<void> startTrackingWithEvents({
    required String driverId,
    required String deliveryId,
    required String startEvent,
  }) async {
    await startDeliveryTracking(
      driverId: driverId,
      deliveryId: deliveryId,
    );
    
    // Store initial location for start event
    await storeLocationForEvent(startEvent);
  }

  /// Stop tracking with final event storage
  Future<void> stopTrackingWithEvent(String endEvent) async {
    await storeLocationForEvent(endEvent);
    await stopTracking();
  }

  /// Fallback location polling when stream fails (due to Android system issues)
  void _startFallbackLocationPolling() {
    print('📍 Starting fallback location polling (every 10 seconds)');
    
    _fallbackTimer = Timer.periodic(Duration(seconds: 10), (timer) async {
      if (!_isTracking) {
        timer.cancel();
        return;
      }
      
      try {
        final position = await getCurrentPosition();
        if (position != null) {
          _handleLocationUpdate(position);
          print('📍 Fallback location obtained: ${position.latitude}, ${position.longitude}');
        }
      } catch (e) {
        print('❌ Fallback location failed: $e');
      }
    });
  }
  
  void _stopFallbackLocationPolling() {
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
  }

  /// Handle WebSocket errors with circuit breaker logic
  void _handleWebSocketError(String error) {
    _consecutiveWebSocketErrors++;
    _lastWebSocketErrorTime = DateTime.now();
    
    if (_consecutiveWebSocketErrors >= OptimizedLocationService._maxConsecutiveErrors) {
      print('🔴 WebSocket circuit breaker activated after $_consecutiveWebSocketErrors errors');
      print('   Last error: $error');
      print('   Broadcasting paused for ${OptimizedLocationService._errorCooldown.inMinutes} minutes');
    } else {
      print('⚠️ WebSocket error ($_consecutiveWebSocketErrors/${OptimizedLocationService._maxConsecutiveErrors}): $error');
    }
  }
}

// 🔹 LOCATION ANALYTICS

class LocationAnalytics {
  static final Map<String, dynamic> _metrics = {};

  static void trackLocationUpdate({
    required double speedKmH,
    required Duration interval,
    required String updateType,
  }) {
    final key = 'location_update_${DateTime.now().millisecondsSinceEpoch}';
    _metrics[key] = {
      'speed_kmh': speedKmH,
      'interval_seconds': interval.inSeconds,
      'update_type': updateType,
      'timestamp': DateTime.now().toIso8601String(),
    };

    // Keep only last 100 metrics to prevent memory leaks
    if (_metrics.length > 100) {
      final oldestKey = _metrics.keys.first;
      _metrics.remove(oldestKey);
    }
  }

  static Map<String, dynamic> getMetrics() => Map.from(_metrics);
  
  static void clearMetrics() => _metrics.clear();
}