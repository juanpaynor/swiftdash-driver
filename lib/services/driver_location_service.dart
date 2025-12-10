import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import 'ably_service.dart';

/// Simple location tracking service that publishes to Ably
/// Based on DRIVER_APP_ABLY_GUIDE.md
class DriverLocationService {
  static final DriverLocationService _instance =
      DriverLocationService._internal();
  factory DriverLocationService() => _instance;
  DriverLocationService._internal();

  Timer? _locationTimer;
  String? _activeDeliveryId;
  final Battery _battery = Battery();
  final AblyService _ably = AblyService();

  /// Start tracking location for a delivery
  void startTracking(String deliveryId) async {
    if (_activeDeliveryId != null) {
      debugPrint('⚠️ Already tracking delivery: $_activeDeliveryId');
      return;
    }

    // 🚨 CHECK: Verify Ably is connected before starting
    if (!_ably.isConnected) {
      debugPrint('⚠️ Ably not connected - attempting to reconnect...');
      await _ably.reconnect();

      // Wait a bit for connection
      await Future.delayed(const Duration(seconds: 2));

      if (!_ably.isConnected) {
        debugPrint(
          '❌ ERROR: Ably still not connected - location tracking may fail!',
        );
      }
    }

    _activeDeliveryId = deliveryId;

    // Enter presence to show driver is online
    try {
      await _ably.enterPresence(deliveryId);
      debugPrint('🚀 Started location tracking for delivery: $deliveryId');
    } catch (e) {
      debugPrint('❌ Failed to enter presence: $e');
    }

    // Start publishing location every 3-5 seconds
    _locationTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      await _publishCurrentLocation();
    });
  }

  /// Publish current GPS location to Ably
  Future<void> _publishCurrentLocation() async {
    if (_activeDeliveryId == null) return;

    try {
      // Get current GPS position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Get battery level (optional - may fail on simulators)
      int? batteryLevel;
      try {
        batteryLevel = await _battery.batteryLevel;
      } catch (e) {
        debugPrint('⚠️ Battery info unavailable (simulator?): $e');
        batteryLevel = null; // Battery info not available on iOS simulator
      }

      // Publish to Ably with exact format from guide
      final locationData = {
        'delivery_id': _activeDeliveryId,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'timestamp': DateTime.now().toIso8601String(),
        'bearing': position.heading,
        'speed': position.speed,
        'accuracy': position.accuracy,
      };

      // Only include battery level if available
      if (batteryLevel != null) {
        locationData['battery_level'] = batteryLevel;
      }

      await _ably.publishLocation(_activeDeliveryId!, locationData);

      debugPrint(
        '📍 Location published: ${position.latitude}, ${position.longitude}',
      );
    } catch (e) {
      debugPrint('❌ Failed to publish location: $e');
    }
  }

  /// Stop tracking location
  Future<void> stopTracking() async {
    if (_activeDeliveryId == null) {
      debugPrint('⚠️ No active tracking to stop');
      return;
    }

    final deliveryToStop = _activeDeliveryId!;

    // CRITICAL: Clear active delivery ID FIRST to prevent timer callbacks
    _activeDeliveryId = null;

    // Cancel timer
    _locationTimer?.cancel();
    _locationTimer = null;

    // Leave presence to show driver is offline
    try {
      await _ably.leavePresence(deliveryToStop);
    } catch (e) {
      debugPrint('⚠️ Error leaving presence: $e');
    }

    debugPrint('🛑 Stopped location tracking for delivery: $deliveryToStop');
  }

  /// Get active delivery ID
  String? get activeDeliveryId => _activeDeliveryId;

  /// Check if currently tracking
  bool get isTracking => _activeDeliveryId != null;
}
