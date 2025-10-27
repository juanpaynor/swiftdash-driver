import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'optimized_location_service.dart';

/// Service to update driver location in driver_profiles table while idle
/// This keeps the pairing location accurate without continuous broadcasting
class IdleLocationUpdateService {
  static final IdleLocationUpdateService _instance = IdleLocationUpdateService._internal();
  factory IdleLocationUpdateService() => _instance;
  IdleLocationUpdateService._internal();

  final _supabase = Supabase.instance.client;
  final OptimizedLocationService _locationService = OptimizedLocationService();

  Timer? _periodicTimer;
  String? _currentDriverId;
  Position? _lastKnownPosition;
  bool _isRunning = false;

  // Configuration
  static const Duration _updateInterval = Duration(minutes: 5); // Option A: Every 5 minutes
  static const double _significantMoveThreshold = 1000.0; // Option B: 1 kilometer (1000 meters)

  /// Start periodic location updates for idle driver
  Future<void> startIdleLocationUpdates(String driverId) async {
    if (_isRunning) {
      print('⚠️ Idle location updates already running');
      return;
    }

    _currentDriverId = driverId;
    _isRunning = true;

    // Get initial position
    _lastKnownPosition = await _locationService.getCurrentPosition();
    
    print('🟢 Started idle location updates for driver pairing accuracy');
    print('   - Periodic updates: Every ${_updateInterval.inMinutes} minutes');
    print('   - Movement updates: When moved > $_significantMoveThreshold meters');

    // Start periodic timer (Option A)
    _periodicTimer = Timer.periodic(_updateInterval, (_) async {
      if (_isRunning) {
        await _updateDriverProfileLocation('periodic');
      }
    });

    // Start listening to location changes for significant movement (Option B)
    _locationService.startListening(_onLocationChange);
  }

  /// Stop idle location updates
  void stopIdleLocationUpdates() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
    _locationService.stopListening();
    _isRunning = false;
    _currentDriverId = null;
    _lastKnownPosition = null;
    print('🔴 Stopped idle location updates');
  }

  /// Handle location changes for significant movement detection
  Future<void> _onLocationChange(Position position) async {
    if (!_isRunning || _lastKnownPosition == null) return;

    // Calculate distance from last known position
    final distance = Geolocator.distanceBetween(
      _lastKnownPosition!.latitude,
      _lastKnownPosition!.longitude,
      position.latitude,
      position.longitude,
    );

    // Update if moved significantly (Option B)
    if (distance > _significantMoveThreshold) {
      print('📍 Driver moved ${distance.toStringAsFixed(0)}m - updating pairing location');
      await _updateDriverProfileLocation('movement', position: position);
    }
  }

  /// Update driver location in driver_profiles table
  Future<void> _updateDriverProfileLocation(String trigger, {Position? position}) async {
    if (_currentDriverId == null) return;

    try {
      // Get current position if not provided
      position ??= await _locationService.getCurrentPosition();
      if (position == null) {
        print('⚠️ Could not get current position for update');
        return;
      }

      // Update driver_profiles table
      await _supabase
          .from('driver_profiles')
          .update({
            'current_latitude': position.latitude,
            'current_longitude': position.longitude,
            'location_updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', _currentDriverId!);

      // Update last known position
      _lastKnownPosition = position;

      print('📍 Updated driver pairing location ($trigger): ${position.latitude}, ${position.longitude}');
    } catch (e) {
      print('❌ Error updating driver profile location: $e');
    }
  }

  /// Check if service is running
  bool get isRunning => _isRunning;
}
