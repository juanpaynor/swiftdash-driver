import 'dart:async';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@pragma('vm:entry-point')
class BackgroundLocationService {
  static const String _notificationChannelId = 'swiftdash_driver_location';
  static const int _notificationId = 888;
  
  // Add state tracking to prevent rapid starts/stops
  static bool _isStarting = false;
  static bool _isStopping = false;
  static String? _currentTrackingId;
  static DateTime? _lastStartTime;

  /// Initialize background service
  static Future<void> initializeService() async {
    try {
      final service = FlutterBackgroundService();
      
      /// Create notification channel for Android
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        _notificationChannelId,
        'SwiftDash Driver Location',
        description: 'Tracks driver location for active deliveries',
        importance: Importance.low,
        enableLights: false,
        enableVibration: false,
        playSound: false,
      );

      final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
          FlutterLocalNotificationsPlugin();

      // Initialize notifications with error handling
      try {
        await flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(channel);
        print('✅ Notification channel created');
      } catch (e) {
        print('⚠️ Failed to create notification channel: $e');
        // Continue without notification channel - service can still work
      }

      // Configure service with error handling
      await service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: onStart,
          autoStart: false,
          isForegroundMode: true,
          notificationChannelId: _notificationChannelId,
          initialNotificationTitle: 'SwiftDash Driver',
          initialNotificationContent: 'Ready for deliveries',
          foregroundServiceNotificationId: _notificationId,
          // Use a simple built-in icon to avoid resource issues
        ),
        iosConfiguration: IosConfiguration(
          autoStart: false,
          onForeground: onStart,
          onBackground: onIosBackground,
        ),
      );

      print('✅ Background service initialized');
    } catch (e) {
      print('❌ Failed to initialize background service: $e');
      // Re-throw the error so main.dart can handle it gracefully
      throw Exception('Background service initialization failed: $e');
    }
  }

  /// Start background location tracking
  static Future<void> startLocationTracking({
    required String driverId,
    required String deliveryId,
  }) async {
    // Prevent rapid restarts
    if (_isStarting) {
      print('⚠️ Location tracking already starting, skipping...');
      return;
    }
    
    // Check if already tracking the same delivery
    if (_currentTrackingId == deliveryId) {
      print('📍 Location broadcast already active for delivery: $deliveryId');
      return;
    }
    
    // Debounce rapid starts (minimum 2 seconds between starts)
    final now = DateTime.now();
    if (_lastStartTime != null && now.difference(_lastStartTime!) < const Duration(seconds: 2)) {
      print('⚠️ Debouncing rapid location service start');
      return;
    }
    
    _isStarting = true;
    _lastStartTime = now;
    
    try {
      final service = FlutterBackgroundService();
      
      // Check if service is available and configured
      final isRunning = await service.isRunning();
      print('📍 Background service status: ${isRunning ? 'running' : 'stopped'}');
      
      await service.startService();
      
      // Small delay to ensure service is ready
      await Future.delayed(const Duration(milliseconds: 300));
      
      service.invoke('start_location_tracking', {
        'driver_id': driverId,
        'delivery_id': deliveryId,
      });

      _currentTrackingId = deliveryId;
      print('🚀 Background location tracking started for delivery: $deliveryId');
    } catch (e) {
      print('❌ Error starting background service: $e');
      
      // Check if it's a specific error we can handle gracefully
      if (e.toString().contains('Service not available') || 
          e.toString().contains('Permission denied') ||
          e.toString().contains('Battery optimization') ||
          e.toString().contains('Background execution not allowed')) {
        print('⚠️ Background service not available due to device restrictions');
        print('🔄 Continuing with foreground-only location tracking');
      } else {
        print('❌ Unexpected background service error: $e');
        print('🔄 App will continue without background service');
      }
      // Don't rethrow to prevent app crash - let foreground service continue
    } finally {
      _isStarting = false;
    }
  }

  /// Stop background location tracking
  static Future<void> stopLocationTracking() async {
    // Prevent concurrent stops
    if (_isStopping) {
      print('⚠️ Location tracking already stopping, skipping...');
      return;
    }
    
    _isStopping = true;
    
    final service = FlutterBackgroundService();
    
    try {
      service.invoke('stop_location_tracking');
      _currentTrackingId = null;
      print('🛑 Background location tracking stopped');
    } catch (e) {
      print('❌ Error stopping background service: $e');
    } finally {
      _isStopping = false;
    }
  }

  /// Check if background service is running
  static Future<bool> isServiceRunning() async {
    final service = FlutterBackgroundService();
    return await service.isRunning();
  }

  /// Start foreground service when driver goes online (keeps app alive in background)
  static Future<void> startOnlineStatusService({
    required String driverId,
  }) async {
    try {
      final service = FlutterBackgroundService();
      
      // Check if service is already running
      final isRunning = await service.isRunning();
      
      if (!isRunning) {
        await service.startService();
        print('🚀 Foreground service started - driver online');
      } else {
        print('✅ Foreground service already running');
      }
      
      // Send online status command to update notification
      service.invoke('set_online_status', {
        'driver_id': driverId,
        'is_online': true,
      });
      
    } catch (e) {
      print('❌ Error starting online status service: $e');
      throw Exception('Failed to start foreground service: $e');
    }
  }

  /// Stop foreground service when driver goes offline
  static Future<void> stopOnlineStatusService() async {
    try {
      final service = FlutterBackgroundService();
      
      // Only stop if no active delivery tracking
      if (_currentTrackingId == null) {
        service.invoke('stop_service');
        print('🛑 Foreground service stopped - driver offline');
      } else {
        // Update notification but keep service running for active delivery
        service.invoke('set_online_status', {
          'is_online': false,
        });
        print('📍 Driver offline but keeping service for active delivery');
      }
      
    } catch (e) {
      print('❌ Error stopping online status service: $e');
    }
  }

  /// Background service entry point
  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    // Ensure Flutter bindings are initialized
    DartPluginRegistrant.ensureInitialized();
    
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    String? currentDriverId;
    String? currentDeliveryId;
    Timer? locationTimer;
    bool isOnline = false;

    print('🚀 Background service started');

    // Listen for online status updates
    service.on('set_online_status').listen((event) async {
      print('📱 Received online status update: $event');
      
      if (event != null && event['driver_id'] != null) {
        currentDriverId = event['driver_id'];
      }
      
      isOnline = event?['is_online'] ?? false;
      
      // Update notification based on status
      final title = isOnline ? 'SwiftDash Driver - Online' : 'SwiftDash Driver - Offline';
      final content = isOnline 
          ? 'You are online and available for deliveries' 
          : 'You are offline';
      
      await flutterLocalNotificationsPlugin.show(
        _notificationId,
        title,
        content,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _notificationChannelId,
            'SwiftDash Driver Location',
            importance: Importance.low,
            priority: Priority.low,
            ongoing: true,
            autoCancel: false,
            showWhen: false,
          ),
        ),
      );
    });

    // Listen for start tracking command
    service.on('start_location_tracking').listen((event) async {
      print('📍 Received start tracking command: $event');
      
      currentDriverId = event!['driver_id'];
      currentDeliveryId = event['delivery_id'];
      
      // Cancel existing timer if any
      locationTimer?.cancel();
      
      // Start location tracking timer (3 seconds for smooth customer tracking)
      locationTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
        await _updateLocation(
          service: service,
          flutterLocalNotificationsPlugin: flutterLocalNotificationsPlugin,
          driverId: currentDriverId!,
          deliveryId: currentDeliveryId!,
        );
      });

      // Get initial location immediately
      await _updateLocation(
        service: service,
        flutterLocalNotificationsPlugin: flutterLocalNotificationsPlugin,
        driverId: currentDriverId!,
        deliveryId: currentDeliveryId!,
      );
    });

    // Listen for stop tracking command
    service.on('stop_location_tracking').listen((event) {
      print('🛑 Received stop tracking command');
      locationTimer?.cancel();
      locationTimer = null;
      currentDriverId = null;
      currentDeliveryId = null;
      service.stopSelf();
    });

    // Auto-stop service if no commands received
    service.on('stop_service').listen((event) {
      locationTimer?.cancel();
      service.stopSelf();
    });
  }

  /// iOS background handler
  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    print('📱 iOS background handler called');
    DartPluginRegistrant.ensureInitialized();
    return true;
  }

  /// Update location and broadcast to customers
  @pragma('vm:entry-point')
  static Future<void> _updateLocation({
    required ServiceInstance service,
    required FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin,
    required String driverId,
    required String deliveryId,
  }) async {
    try {
      // Check location permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        print('❌ Location permission denied in background');
        return;
      }

      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('❌ Location services disabled');
        return;
      }

      // Get current position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      final speedKmH = (position.speed * 3.6).clamp(0.0, 200.0); // Convert m/s to km/h

      // Broadcast location via Supabase realtime
      await _broadcastLocationViaWebSocket(
        deliveryId: deliveryId,
        driverId: driverId,
        latitude: position.latitude,
        longitude: position.longitude,
        speedKmH: speedKmH,
        heading: position.heading,
        accuracy: position.accuracy,
      );

      // Update persistent notification
      await flutterLocalNotificationsPlugin.show(
        _notificationId,
        'SwiftDash Driver - Active Delivery',
        'Location tracking active • Speed: ${speedKmH.toStringAsFixed(0)} km/h',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _notificationChannelId,
            'SwiftDash Driver Location',
            channelDescription: 'Tracks driver location for active deliveries',
            ongoing: true,
            autoCancel: false,
            importance: Importance.low,
            priority: Priority.low,
            enableLights: false,
            enableVibration: false,
            playSound: false,
            icon: '@mipmap/ic_launcher', // Use app launcher icon
          ),
        ),
      );

      print('📍 Background location updated: ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)} • ${speedKmH.toStringAsFixed(1)} km/h');
      
    } catch (e) {
      print('❌ Background location error: $e');
      
      // Show error notification
      await flutterLocalNotificationsPlugin.show(
        _notificationId,
        'SwiftDash Driver - Location Error',
        'Unable to get location. Please check GPS settings.',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _notificationChannelId,
            'SwiftDash Driver Location',
            importance: Importance.low,
            priority: Priority.low,
            ongoing: true,
            icon: '@mipmap/ic_launcher', // Use app launcher icon
          ),
        ),
      );
    }
  }

  /// Broadcast location via WebSocket (NO database pollution)
  @pragma('vm:entry-point')
  static Future<void> _broadcastLocationViaWebSocket({
    required String driverId,
    required String deliveryId,
    required double latitude,
    required double longitude,
    required double speedKmH,
    required double heading,
    required double accuracy,
  }) async {
    try {
      // Check if Supabase is initialized in background service context
      if (!Supabase.instance.isInitialized) {
        print('⚠️ Supabase not initialized in background service - skipping WebSocket broadcast');
        return;
      }
      
      final supabaseClient = Supabase.instance.client;
      
      // Create temporary WebSocket channel for this delivery
      final channelName = 'driver-location-$deliveryId';
      final channel = supabaseClient.channel(channelName);
      
      // Subscribe and broadcast via WebSocket ONLY (no DB writes)
      await channel.subscribe();
      
      channel.sendBroadcastMessage(
        event: 'location_update',
        payload: {
          'driver_id': driverId,
          'delivery_id': deliveryId,
          'latitude': latitude,
          'longitude': longitude,
          'speed_kmh': speedKmH,
          'heading': heading,
          'battery_level': 100.0, // TODO: Get actual battery level
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      print('📡 Location broadcasted via WebSocket ONLY (no database pollution)');
      
    } catch (e) {
      print('❌ Error broadcasting location via WebSocket: $e');
    }
  }
  
  /// Update the foreground notification with delivery status info
  /// This allows updating notification from the main app when status changes
  static Future<void> updateNotification({
    required String title,
    required String body,
  }) async {
    try {
      final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
          FlutterLocalNotificationsPlugin();
      
      await flutterLocalNotificationsPlugin.show(
        _notificationId,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _notificationChannelId,
            'SwiftDash Driver Location',
            channelDescription: 'Tracks driver location for active deliveries',
            ongoing: true,
            autoCancel: false,
            importance: Importance.low,
            priority: Priority.low,
            enableLights: false,
            enableVibration: false,
            playSound: false,
            icon: '@mipmap/ic_launcher',
          ),
        ),
      );
      
      print('🔔 Background notification updated: $title - $body');
    } catch (e) {
      print('❌ Error updating notification: $e');
    }
  }
  
  /// Show a foreground service notification (called when starting tracking)
  static Future<void> showForegroundNotification({
    required String deliveryId,
    String? customerName,
  }) async {
    try {
      final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
          FlutterLocalNotificationsPlugin();
      
      final title = 'SwiftDash Driver - Active Delivery';
      final body = customerName != null 
          ? 'Delivering to $customerName'
          : 'Location tracking active';
      
      await flutterLocalNotificationsPlugin.show(
        _notificationId,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _notificationChannelId,
            'SwiftDash Driver Location',
            channelDescription: 'Tracks driver location for active deliveries',
            ongoing: true,
            autoCancel: false,
            importance: Importance.low,
            priority: Priority.low,
            enableLights: false,
            enableVibration: false,
            playSound: false,
            icon: '@mipmap/ic_launcher',
          ),
        ),
        payload: deliveryId,
      );
      
      print('🔔 Foreground notification shown for delivery: $deliveryId');
    } catch (e) {
      print('❌ Error showing foreground notification: $e');
    }
  }
}