import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:audioplayers/audioplayers.dart';

/// Service that listens for delivery offers and shows notifications with sound
/// Works even when app is in background or killed
@pragma('vm:entry-point')
class DeliveryOfferNotificationService {
  static const String _notificationChannelId = 'swiftdash_delivery_offers';
  static const String _locationChannelId = 'swiftdash_driver_location';
  static const int _offerNotificationId = 999;
  static const int _foregroundNotificationId = 888;
  
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  
  static StreamSubscription? _offerSubscription;
  static bool _isInitialized = false;

  /// Initialize the notification service
  static Future<void> initialize() async {
    if (_isInitialized) {
      debugPrint('✅ DeliveryOfferNotificationService already initialized');
      return;
    }

    try {
      debugPrint('🔧 Initializing DeliveryOfferNotificationService...');
      
      // Create notification channels
      await _createNotificationChannels();
      
      // Initialize local notifications
      const initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const initializationSettingsIOS = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsIOS,
      );

      await _notificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );
      
      // Initialize background service
      await _initializeBackgroundService();
      
      _isInitialized = true;
      debugPrint('✅ DeliveryOfferNotificationService initialized successfully');
    } catch (e) {
      debugPrint('❌ Error initializing DeliveryOfferNotificationService: $e');
      rethrow;
    }
  }

  /// Create notification channels for Android
  static Future<void> _createNotificationChannels() async {
    // Channel for delivery offers (high priority with sound)
    const offerChannel = AndroidNotificationChannel(
      _notificationChannelId,
      'Delivery Offers',
      description: 'Notifications for new delivery offers',
      importance: Importance.max,
      enableLights: true,
      enableVibration: true,
      playSound: true,
      showBadge: true,
      sound: RawResourceAndroidNotificationSound('notification_sound'),
    );

    // Channel for location tracking (low priority, silent)
    const locationChannel = AndroidNotificationChannel(
      _locationChannelId,
      'Location Tracking',
      description: 'Background location tracking for active deliveries',
      importance: Importance.low,
      enableLights: false,
      enableVibration: false,
      playSound: false,
      showBadge: false,
    );

    final androidImpl = _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    await androidImpl?.createNotificationChannel(offerChannel);
    await androidImpl?.createNotificationChannel(locationChannel);
    
    debugPrint('✅ Notification channels created');
  }

  /// Initialize background service
  static Future<void> _initializeBackgroundService() async {
    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onBackgroundStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: _locationChannelId,
        initialNotificationTitle: 'SwiftDash Driver',
        initialNotificationContent: 'Listening for delivery offers...',
        foregroundServiceNotificationId: _foregroundNotificationId,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _onBackgroundStart,
        onBackground: _onIosBackground,
      ),
    );
    
    debugPrint('✅ Background service configured');
  }

  /// Start listening for delivery offers
  /// CRITICAL: This keeps the app alive in background even when killed
  static Future<void> startListening(String driverId) async {
    try {
      if (!_isInitialized) {
        await initialize();
      }
      
      // Start background service with foreground notification
      // This is CRITICAL - without foreground service, Android will kill the app
      final service = FlutterBackgroundService();
      final isRunning = await service.isRunning();
      
      if (!isRunning) {
        await service.startService();
        debugPrint('🚀 Background service started (FOREGROUND MODE - KEEPS APP ALIVE)');
      }
      
      // Send command to start listening
      service.invoke('start_offer_listening', {
        'driver_id': driverId,
      });
      
      // Show persistent notification that keeps service alive
      await updateForegroundNotification(
        title: 'SwiftDash Driver - Online',
        body: 'Listening for delivery offers... (Tap to open app)',
      );
      
      debugPrint('👂 Started listening for delivery offers for driver: $driverId');
      debugPrint('🔔 Persistent notification shown - service will stay alive');
    } catch (e) {
      debugPrint('❌ Error starting offer listener: $e');
    }
  }

  /// Stop listening for delivery offers
  static Future<void> stopListening() async {
    try {
      final service = FlutterBackgroundService();
      service.invoke('stop_offer_listening');
      
      _offerSubscription?.cancel();
      _offerSubscription = null;
      
      debugPrint('🛑 Stopped listening for delivery offers');
    } catch (e) {
      debugPrint('❌ Error stopping offer listener: $e');
    }
  }

  /// Show delivery offer notification with sound
  static Future<void> showOfferNotification({
    required String deliveryId,
    required String customerName,
    required double totalPrice,
    required double driverEarnings,
    required double distance,
    required String pickupAddress,
    required String deliveryAddress,
  }) async {
    try {
      // Play sound
      await _playNotificationSound();
      
      // Show notification
      await _notificationsPlugin.show(
        _offerNotificationId,
        '🚚 New Delivery Offer - ₱${driverEarnings.toStringAsFixed(2)}',
        'From: ${_truncateAddress(pickupAddress)}\nTo: ${_truncateAddress(deliveryAddress)}\nDistance: ${distance.toStringAsFixed(1)} km',
        NotificationDetails(
          android: AndroidNotificationDetails(
            _notificationChannelId,
            'Delivery Offers',
            channelDescription: 'Notifications for new delivery offers',
            importance: Importance.max,
            priority: Priority.high,
            enableLights: true,
            enableVibration: true,
            playSound: true,
            sound: const RawResourceAndroidNotificationSound('notification_sound'),
            ongoing: false,
            autoCancel: true,
            showWhen: true,
            color: const Color(0xFF3B82F6), // SwiftDash blue
            icon: '@mipmap/ic_launcher',
            styleInformation: BigTextStyleInformation(
              '💰 You earn: ₱${driverEarnings.toStringAsFixed(2)}\n'
              '📦 Total: ₱${totalPrice.toStringAsFixed(2)}\n'
              '📍 Distance: ${distance.toStringAsFixed(1)} km\n\n'
              '🏪 Pickup: $pickupAddress\n'
              '📍 Delivery: $deliveryAddress',
              contentTitle: '🚚 New Delivery Offer',
              summaryText: 'Tap to accept',
            ),
            actions: [
              const AndroidNotificationAction(
                'accept',
                'Accept Offer',
                showsUserInterface: true,
              ),
              const AndroidNotificationAction(
                'decline',
                'Decline',
                showsUserInterface: false,
              ),
            ],
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            sound: 'notification_sound.wav',
            subtitle: '₱${driverEarnings.toStringAsFixed(2)} earnings',
            interruptionLevel: InterruptionLevel.timeSensitive,
          ),
        ),
        payload: deliveryId,
      );
      
      debugPrint('🔔 Delivery offer notification shown for: $deliveryId');
    } catch (e) {
      debugPrint('❌ Error showing offer notification: $e');
    }
  }

  /// Play notification sound
  static Future<void> _playNotificationSound() async {
    try {
      final player = AudioPlayer();
      await player.setSource(AssetSource('sound/new-notification-022-370046.mp3'));
      await player.resume();
      
      // Stop after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        player.stop();
        player.dispose();
      });
    } catch (e) {
      debugPrint('⚠️ Could not play notification sound: $e');
    }
  }

  /// Handle notification tap
  static void _onNotificationTapped(NotificationResponse response) {
    debugPrint('🔔 Notification tapped: ${response.payload}');
    
    if (response.actionId == 'accept') {
      debugPrint('✅ User accepted offer from notification');
      // TODO: Implement direct accept from notification
    } else if (response.actionId == 'decline') {
      debugPrint('❌ User declined offer from notification');
      // TODO: Implement direct decline from notification
    }
  }

  /// Background service entry point
  @pragma('vm:entry-point')
  static void _onBackgroundStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();
    
    debugPrint('🚀 Background service started for offer listening');
    
    String? driverId;
    RealtimeChannel? realtimeChannel;

    // Listen for start command
    service.on('start_offer_listening').listen((event) async {
      debugPrint('👂 Received start_offer_listening command: $event');
      
      driverId = event!['driver_id'] as String;
      
      // Cancel existing subscription
      await realtimeChannel?.unsubscribe();
      
      // Subscribe to Supabase realtime for delivery offers
      try {
        if (!Supabase.instance.isInitialized) {
          debugPrint('⚠️ Supabase not initialized in background');
          return;
        }
        
        final supabase = Supabase.instance.client;
        
        // Listen to deliveries table for offers assigned to this driver
        final channel = supabase
            .channel('driver-offers-$driverId')
            .onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'deliveries',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'driver_id',
                value: driverId,
              ),
              callback: (payload) async {
                debugPrint('🔔 New delivery offer received: ${payload.newRecord}');
                
                // Extract delivery details
                final record = payload.newRecord;
                final status = record['status'] as String?;
                
                // Only show notification for offers (not assigned/accepted deliveries)
                if (status == 'pending' || status == 'offering') {
                  await _showOfferNotificationFromBackground(record);
                }
              },
            );
        
        await channel.subscribe();
        realtimeChannel = channel;
        debugPrint('📡 Subscribed to delivery offers channel');
        
        // Update foreground notification
        await _notificationsPlugin.show(
          _foregroundNotificationId,
          'SwiftDash Driver - Online',
          'Listening for delivery offers...',
          const NotificationDetails(
            android: AndroidNotificationDetails(
              _locationChannelId,
              'Location Tracking',
              importance: Importance.low,
              priority: Priority.low,
              ongoing: true,
              autoCancel: false,
              icon: '@mipmap/ic_launcher',
            ),
          ),
        );
        
        debugPrint('✅ Subscribed to delivery offers in background');
      } catch (e) {
        debugPrint('❌ Error subscribing to offers in background: $e');
      }
    });

    // Listen for stop command
    service.on('stop_offer_listening').listen((event) async {
      debugPrint('🛑 Received stop_offer_listening command');
      await realtimeChannel?.unsubscribe();
      realtimeChannel = null;
      driverId = null;
    });

    // Auto-stop service
    service.on('stop_service').listen((event) async {
      await realtimeChannel?.unsubscribe();
      realtimeChannel = null;
      service.stopSelf();
    });
  }

  /// iOS background handler
  @pragma('vm:entry-point')
  static Future<bool> _onIosBackground(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();
    return true;
  }

  /// Show offer notification from background service
  @pragma('vm:entry-point')
  static Future<void> _showOfferNotificationFromBackground(
    Map<String, dynamic> deliveryRecord,
  ) async {
    try {
      final deliveryId = deliveryRecord['id'] as String;
      final totalPrice = (deliveryRecord['total_price'] as num).toDouble();
      final pickupAddress = deliveryRecord['pickup_address'] as String? ?? 'Unknown';
      final deliveryAddress = deliveryRecord['delivery_address'] as String? ?? 'Unknown';
      final distance = (deliveryRecord['distance'] as num?)?.toDouble() ?? 0.0;
      
      // Calculate driver earnings (84% of total)
      final driverEarnings = totalPrice * 0.84;
      
      // Play sound
      await _playNotificationSound();
      
      // Show notification
      await _notificationsPlugin.show(
        _offerNotificationId,
        '🚚 New Delivery Offer - ₱${driverEarnings.toStringAsFixed(2)}',
        'Tap to view details and accept',
        NotificationDetails(
          android: AndroidNotificationDetails(
            _notificationChannelId,
            'Delivery Offers',
            importance: Importance.max,
            priority: Priority.high,
            enableLights: true,
            enableVibration: true,
            playSound: true,
            sound: const RawResourceAndroidNotificationSound('notification_sound'),
            ongoing: false,
            autoCancel: true,
            showWhen: true,
            color: const Color(0xFF3B82F6),
            icon: '@mipmap/ic_launcher',
            styleInformation: BigTextStyleInformation(
              '💰 You earn: ₱${driverEarnings.toStringAsFixed(2)}\n'
              '📦 Total: ₱${totalPrice.toStringAsFixed(2)}\n'
              '📍 Distance: ${distance.toStringAsFixed(1)} km\n\n'
              '🏪 Pickup: $pickupAddress\n'
              '📍 Delivery: $deliveryAddress',
              contentTitle: '🚚 New Delivery Offer',
              summaryText: 'Tap to accept',
            ),
          ),
        ),
        payload: deliveryId,
      );
      
      debugPrint('🔔 Background offer notification shown');
    } catch (e) {
      debugPrint('❌ Error showing background notification: $e');
    }
  }

  /// Truncate address for notification
  static String _truncateAddress(String address, {int maxLength = 40}) {
    if (address.length <= maxLength) return address;
    return '${address.substring(0, maxLength)}...';
  }

  /// Update foreground notification status
  static Future<void> updateForegroundNotification({
    required String title,
    required String body,
  }) async {
    try {
      await _notificationsPlugin.show(
        _foregroundNotificationId,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _locationChannelId,
            'Location Tracking',
            importance: Importance.low,
            priority: Priority.low,
            ongoing: true,
            autoCancel: false,
            icon: '@mipmap/ic_launcher',
          ),
        ),
      );
    } catch (e) {
      debugPrint('❌ Error updating foreground notification: $e');
    }
  }
}
