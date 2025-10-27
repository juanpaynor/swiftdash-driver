import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import '../services/delivery_stage_manager.dart';

/// Service for managing persistent delivery notifications with action buttons
/// Provides quick access to status updates without opening the app
class DeliveryNotificationService {
  static const String _channelId = 'delivery_actions';
  static const String _channelName = 'Delivery Actions';
  static const String _channelDescription = 'Quick actions for active deliveries';
  static const int _notificationId = 1000;
  
  static final FlutterLocalNotificationsPlugin _notifications = 
      FlutterLocalNotificationsPlugin();
  
  static bool _isInitialized = false;
  
  /// Initialize the notification service
  static Future<void> initialize() async {
    if (_isInitialized) {
      print('✅ Delivery notification service already initialized');
      return;
    }
    
    try {
      // Android initialization settings
      const AndroidInitializationSettings androidSettings = 
          AndroidInitializationSettings('@mipmap/ic_launcher');
      
      // iOS initialization settings
      const DarwinInitializationSettings iosSettings = 
          DarwinInitializationSettings(
            requestAlertPermission: true,
            requestBadgePermission: true,
            requestSoundPermission: false,
          );
      
      const InitializationSettings initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );
      
      // Initialize with callback for handling action button taps
      await _notifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );
      
      // Create notification channel for Android
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.high,
        playSound: false,
        enableVibration: false,
        showBadge: true,
      );
      
      await _notifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
      
      _isInitialized = true;
      print('✅ Delivery notification service initialized');
    } catch (e) {
      print('❌ Error initializing delivery notifications: $e');
      rethrow;
    }
  }
  
  /// Show persistent notification with action buttons based on delivery stage
  static Future<void> showDeliveryNotification({
    required String deliveryId,
    required DeliveryStage stage,
    required String customerName,
    String? address,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }
    
    try {
      final title = _getNotificationTitle(stage, customerName);
      final body = _getNotificationBody(stage, address);
      final actions = _getActionsForStage(stage);
      
      final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.low,  // Changed from high - less intrusive
        priority: Priority.low,      // Changed from high
        ongoing: false,              // Changed from true - can be swiped away
        autoCancel: true,            // Changed from false - dismisses on tap
        icon: '@mipmap/ic_launcher',
        largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
        actions: actions,
        styleInformation: const BigTextStyleInformation(''),
        color: const Color(0xFF2E4A9B),  // SwiftDash blue
        playSound: false,            // Don't play sound
        enableVibration: false,      // Don't vibrate
      );
      
      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: false,
      );
      
      final NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );
      
      await _notifications.show(
        _notificationId,
        title,
        body,
        details,
        payload: deliveryId,
      );
      
      print('🔔 Delivery notification shown: $title');
    } catch (e) {
      print('❌ Error showing delivery notification: $e');
    }
  }
  
  /// Update existing notification (e.g., when stage changes)
  static Future<void> updateNotification({
    required String deliveryId,
    required DeliveryStage stage,
    required String customerName,
    String? address,
  }) async {
    // Just show a new notification with same ID - it will replace the old one
    await showDeliveryNotification(
      deliveryId: deliveryId,
      stage: stage,
      customerName: customerName,
      address: address,
    );
  }
  
  /// Cancel the persistent delivery notification
  static Future<void> cancelNotification() async {
    try {
      await _notifications.cancel(_notificationId);
      print('🔕 Delivery notification cancelled');
    } catch (e) {
      print('❌ Error cancelling notification: $e');
    }
  }
  
  /// Get notification title based on stage
  static String _getNotificationTitle(DeliveryStage stage, String customerName) {
    switch (stage) {
      case DeliveryStage.headingToPickup:
        return '🚗 Active Delivery - Heading to Pickup';
      case DeliveryStage.headingToDelivery:
        return '📦 Active Delivery - Delivering to $customerName';
      case DeliveryStage.deliveryComplete:
        return '✅ Delivery Complete';
    }
  }
  
  /// Get notification body based on stage
  static String _getNotificationBody(DeliveryStage stage, String? address) {
    switch (stage) {
      case DeliveryStage.headingToPickup:
        return address != null 
            ? 'Pickup location: $address'
            : 'En route to pickup location';
      case DeliveryStage.headingToDelivery:
        return address != null
            ? 'Delivery address: $address'
            : 'En route to delivery location';
      case DeliveryStage.deliveryComplete:
        return 'Thank you for completing this delivery!';
    }
  }
  
  /// Get action buttons based on current stage
  static List<AndroidNotificationAction> _getActionsForStage(DeliveryStage stage) {
    switch (stage) {
      case DeliveryStage.headingToPickup:
        return [
          const AndroidNotificationAction(
            'arrived_pickup',
            '🎯 Arrived at Pickup',
            showsUserInterface: false,  // Don't open app, just trigger action
            cancelNotification: false,  // Keep notification visible
          ),
          const AndroidNotificationAction(
            'open_app',
            '📱 Open App',
            showsUserInterface: true,
          ),
        ];
        
      case DeliveryStage.headingToDelivery:
        return [
          const AndroidNotificationAction(
            'arrived_delivery',
            '🎯 Arrived at Delivery',
            showsUserInterface: false,
            cancelNotification: false,
          ),
          const AndroidNotificationAction(
            'open_app',
            '📱 Open App',
            showsUserInterface: true,
          ),
        ];
        
      case DeliveryStage.deliveryComplete:
        return [
          const AndroidNotificationAction(
            'open_app',
            '📱 View Summary',
            showsUserInterface: true,
          ),
        ];
    }
  }
  
  /// Handle notification and action button taps
  static void _onNotificationTapped(NotificationResponse response) {
    final String? payload = response.payload;
    final String? actionId = response.actionId;
    
    print('🔔 Notification tapped: action=$actionId, deliveryId=$payload');
    
    if (actionId == null) {
      // User tapped notification body - open app
      print('📱 Opening app from notification body tap');
      // The app will open automatically
      return;
    }
    
    // Handle action button taps
    _handleNotificationAction(actionId, payload);
  }
  
  /// Handle specific notification action
  static void _handleNotificationAction(String actionId, String? deliveryId) {
    print('⚡ Handling notification action: $actionId for delivery: $deliveryId');
    
    // Store the action to be processed when app resumes
    // This will be picked up by the delivery screen or main map screen
    _pendingAction = NotificationAction(
      actionId: actionId,
      deliveryId: deliveryId,
      timestamp: DateTime.now(),
    );
    
    switch (actionId) {
      case 'arrived_pickup':
        print('🎯 Driver marked: Arrived at Pickup (from notification)');
        // The actual status update will be handled by the active screen
        break;
        
      case 'arrived_delivery':
        print('🎯 Driver marked: Arrived at Delivery (from notification)');
        // The actual status update will be handled by the active screen
        break;
        
      case 'open_app':
        print('📱 Opening app (from notification button)');
        // App opens automatically
        break;
        
      default:
        print('⚠️ Unknown notification action: $actionId');
    }
  }
  
  /// Pending notification action (to be processed by active screen)
  static NotificationAction? _pendingAction;
  
  /// Get and clear pending notification action
  static NotificationAction? consumePendingAction() {
    final action = _pendingAction;
    _pendingAction = null;
    return action;
  }
  
  /// Check if there's a pending action
  static bool hasPendingAction() => _pendingAction != null;
}

/// Represents an action triggered from a notification
class NotificationAction {
  final String actionId;
  final String? deliveryId;
  final DateTime timestamp;
  
  NotificationAction({
    required this.actionId,
    required this.deliveryId,
    required this.timestamp,
  });
  
  bool get isArrivedAtPickup => actionId == 'arrived_pickup';
  bool get isArrivedAtDelivery => actionId == 'arrived_delivery';
  bool get isOpenApp => actionId == 'open_app';
  
  @override
  String toString() => 'NotificationAction(actionId: $actionId, deliveryId: $deliveryId)';
}
