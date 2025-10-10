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
  Timer? _broadcastTimer;
  
  String? _currentDeliveryId;
  bool _isTracking = false;
  
  Position? _lastPosition;
  DateTime? _lastBroadcastTime;

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
    
    // Start location broadcast for this delivery
    _realtimeService.startLocationBroadcast(deliveryId);

    // Start background service for when app is minimized
    await BackgroundLocationService.startLocationTracking(
      driverId: driverId,
      deliveryId: deliveryId,
    );

    print('✅ Adaptive location tracking started (foreground + background)');
  }

  /// Stop location tracking
  Future<void> stopTracking() async {
    if (!_isTracking) return;

    print('📍 Stopping location tracking');

    await _positionSubscription?.cancel();
    _positionSubscription = null;
    
    _broadcastTimer?.cancel();
    _broadcastTimer = null;

    // Stop background service
    await BackgroundLocationService.stopLocationTracking();

    _isTracking = false;
    _currentDeliveryId = null;
    _lastPosition = null;
    _lastBroadcastTime = null;

    print('✅ Location tracking stopped (foreground + background)');
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
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5, // Only update if moved 5 meters
    );

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      _handleLocationUpdate,
      onError: (error) => print('❌ Location stream error: $error'),
    );
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
    // During active delivery
    if (_currentDeliveryId != null) {
      if (speedKmH > 50) {
        return const Duration(seconds: 5);   // Highway speed - frequent updates
      } else if (speedKmH > 20) {
        return const Duration(seconds: 10);  // City driving - normal updates
      } else if (speedKmH > 5) {
        return const Duration(seconds: 20);  // Slow movement - moderate updates
      } else {
        return const Duration(seconds: 60);  // Stationary - minimal updates
      }
    }
    
    // Available but not delivering
    return const Duration(minutes: 5);
  }

  /// Broadcast location via realtime service
  void _broadcastCurrentLocation(Position position, double speedKmH) {
    if (_currentDeliveryId == null) return;

    _realtimeService.broadcastLocation(
      deliveryId: _currentDeliveryId!,
      latitude: position.latitude,
      longitude: position.longitude,
      speedKmH: speedKmH,
      heading: position.heading,
      accuracy: position.accuracy,
    );

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
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.medium, // Reduced accuracy for battery saving
      distanceFilter: 10, // Only update if moved 10 meters
    );

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      _handleLocationUpdate,
      onError: (error) => print('❌ Location stream error: $error'),
    );
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
    print('🧹 OptimizedLocationService disposed');
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