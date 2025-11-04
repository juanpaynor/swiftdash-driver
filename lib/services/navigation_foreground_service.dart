import 'dart:async';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:developer' as developer;
import 'navigation_service.dart';

/// Foreground service for background navigation
/// Keeps GPS and navigation active when app is minimized
class NavigationForegroundService {
  static final NavigationForegroundService _instance = NavigationForegroundService._internal();
  factory NavigationForegroundService() => _instance;
  NavigationForegroundService._internal();

  bool _isServiceRunning = false;
  StreamSubscription<Position>? _locationSubscription;

  /// Initialize the foreground task service
  static Future<void> initForegroundTask() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'swiftdash_navigation',
        channelName: 'SwiftDash Navigation',
        channelDescription: 'Turn-by-turn navigation in progress',
        channelImportance: NotificationChannelImportance.HIGH,
        priority: NotificationPriority.HIGH,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(2000), // Update every 2 seconds
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  /// Start the foreground service for navigation
  Future<bool> startService({
    required String destinationType, // 'Pickup' or 'Delivery'
    String? address,
  }) async {
    if (_isServiceRunning) {
      developer.log('Foreground service already running', name: 'NavigationForegroundService');
      return true;
    }

    try {
      // Request notification permission
      final permissionStatus = await FlutterForegroundTask.checkNotificationPermission();
      if (permissionStatus != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }

      // Start the foreground service
      await FlutterForegroundTask.startService(
        serviceId: 256,
        notificationTitle: 'Navigating to $destinationType',
        notificationText: address ?? 'Turn-by-turn navigation in progress',
        notificationIcon: null,
        notificationButtons: [],
        callback: startCallback,
      );

      _isServiceRunning = true;
      _startLocationUpdates();
      developer.log('Foreground service started', name: 'NavigationForegroundService');

      return true;
    } catch (e) {
      developer.log('Failed to start foreground service: $e', name: 'NavigationForegroundService');
      return false;
    }
  }

  /// Update the notification with current navigation status
  Future<void> updateNotification({
    String? instruction,
    String? distance,
    String? eta,
  }) async {
    if (!_isServiceRunning) return;

    try {
      String notificationText = '';
      
      if (instruction != null && distance != null) {
        notificationText = '$instruction • $distance';
      } else if (instruction != null) {
        notificationText = instruction;
      } else {
        notificationText = 'Navigation in progress';
      }

      if (eta != null) {
        notificationText += ' • ETA: $eta';
      }

      await FlutterForegroundTask.updateService(
        notificationText: notificationText,
      );
    } catch (e) {
      developer.log('Failed to update notification: $e', name: 'NavigationForegroundService');
    }
  }

  /// Stop the foreground service
  Future<void> stopService() async {
    if (!_isServiceRunning) return;

    try {
      await _locationSubscription?.cancel();
      _locationSubscription = null;

      await FlutterForegroundTask.stopService();
      _isServiceRunning = false;

      developer.log('Foreground service stopped', name: 'NavigationForegroundService');
    } catch (e) {
      developer.log('Failed to stop foreground service: $e', name: 'NavigationForegroundService');
    }
  }

  /// Start continuous location updates
  void _startLocationUpdates() {
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // Update every 10 meters
    );

    _locationSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (Position position) {
        // Update navigation service with new location
        NavigationService.instance.updateLocation(position);
      },
      onError: (error) {
        developer.log('Location stream error: $error', name: 'NavigationForegroundService');
      },
    );
  }

  /// Check if service is running
  bool get isServiceRunning => _isServiceRunning;

  /// Dispose resources
  Future<void> dispose() async {
    await stopService();
  }
}

/// Callback function for foreground task
/// This runs in the background isolate
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(NavigationTaskHandler());
}

/// Task handler for background navigation
class NavigationTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    developer.log('Navigation task started', name: 'NavigationTaskHandler');
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    // This is called every 2 seconds (as configured in eventAction)
    // We don't need to do anything here since location updates
    // are handled by the main isolate
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    developer.log('Navigation task destroyed', name: 'NavigationTaskHandler');
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'stop_navigation') {
      // Stop navigation when user taps the notification button
      FlutterForegroundTask.stopService();
    }
  }

  @override
  void onNotificationPressed() {
    // Bring app to foreground when notification is tapped
    FlutterForegroundTask.launchApp('/');
  }

  @override
  void onNotificationDismissed() {
    // Handle notification dismissal if needed
  }
}
