import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class LocationService {
  static LocationService? _instance;
  static LocationService get instance => _instance ??= LocationService._();
  LocationService._();
  
  Position? _currentPosition;
  StreamSubscription<Position>? _positionSubscription;
  
  Position? get currentPosition => _currentPosition;
  
  // Check if location permissions are granted
  Future<bool> hasLocationPermission() async {
    final permission = await Permission.location.status;
    return permission == PermissionStatus.granted;
  }
  
  // Request location permissions
  Future<bool> requestLocationPermission() async {
    final permission = await Permission.location.request();
    return permission == PermissionStatus.granted;
  }
  
  // Check if location services are enabled
  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }
  
  // Show location permission dialog
  Future<bool> showLocationPermissionDialog(BuildContext context) async {
    final hasPermission = await hasLocationPermission();
    if (hasPermission) return true;
    
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Location Permission Required'),
        content: const Text(
          'SwiftDash needs access to your location to:\n\n'
          '• Show your position to customers\n'
          '• Calculate accurate delivery routes\n'
          '• Match you with nearby deliveries\n\n'
          'Location is only used while the app is active.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not Now'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Allow Location'),
          ),
        ],
      ),
    );
    
    if (result == true) {
      return await requestLocationPermission();
    }
    
    return false;
  }
  
  // Get current position
  Future<Position?> getCurrentPosition() async {
    try {
      final hasPermission = await hasLocationPermission();
      if (!hasPermission) return null;
      
      final isEnabled = await isLocationServiceEnabled();
      if (!isEnabled) return null;
      
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      
      _currentPosition = position;
      return position;
    } catch (e) {
      print('Error getting current position: $e');
      return null;
    }
  }
  
  // Start location tracking (15-second intervals)
  Future<void> startLocationTracking({
    required Function(Position) onLocationUpdate,
    Function(String)? onError,
  }) async {
    try {
      final hasPermission = await hasLocationPermission();
      if (!hasPermission) {
        onError?.call('Location permission not granted');
        return;
      }
      
      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Update if moved 10 meters
        timeLimit: Duration(seconds: 15),
      );
      
      try {
        _positionSubscription = Geolocator.getPositionStream(
          locationSettings: locationSettings,
        ).listen(
          (position) {
            _currentPosition = position;
            onLocationUpdate(position);
          },
          onError: (error) {
            print('Location tracking error: $error');
            onError?.call(error.toString());
          },
        );
      } catch (e) {
        print('❌ CRITICAL: Failed to start location stream in LocationService: $e');
        print('🛡️ This may be due to Android system location service failure');
        onError?.call('Location system unavailable: ${e.toString()}');
        return;
      }
      
      // Get initial position
      final initialPosition = await getCurrentPosition();
      if (initialPosition != null) {
        onLocationUpdate(initialPosition);
      }
      
    } catch (e) {
      print('Error starting location tracking: $e');
      onError?.call(e.toString());
    }
  }
  
  // Stop location tracking
  void stopLocationTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }
  
  // Calculate distance between two points
  double calculateDistance(
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
    ) / 1000; // Convert to kilometers
  }
  
  // Show location settings dialog
  Future<void> showLocationSettingsDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Location Services Disabled'),
        content: const Text(
          'Please enable location services in your device settings to use SwiftDash.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              Geolocator.openLocationSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
  
  // Dispose resources
  void dispose() {
    stopLocationTracking();
  }
}