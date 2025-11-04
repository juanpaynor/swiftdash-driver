import 'package:ably_flutter/ably_flutter.dart' as ably;
import 'package:flutter/foundation.dart';

class AblyService {
  static final AblyService _instance = AblyService._internal();
  factory AblyService() => _instance;
  AblyService._internal();

  ably.Realtime? _realtime;
  final Map<String, ably.RealtimeChannel> _channels = {};
  String? _clientId;  // Store client ID for presence features

  Future<void> initialize(String clientKey, {String? clientId}) async {
    // 🚨 FIX: If already initialized but with different clientId, reinitialize
    if (_realtime != null) {
      if (clientId != null && _clientId != clientId) {
        debugPrint('🔄 Ably clientId changed from $_clientId to $clientId - reinitializing...');
        await dispose();
      } else {
        debugPrint('⚠️ Ably already initialized with same clientId');
        return;
      }
    }

    try {
      _clientId = clientId;  // Store for future reference
      
      final clientOptions = ably.ClientOptions(
        key: clientKey,
        clientId: clientId,  // ✅ FIX: Set clientId for presence features
        logLevel: kDebugMode ? ably.LogLevel.error : ably.LogLevel.error,
        autoConnect: true,
      );

      _realtime = ably.Realtime(options: clientOptions);
      
      _realtime!.connection.on().listen((ably.ConnectionStateChange stateChange) {
        debugPrint('🔌 Ably connection: ${stateChange.current}');
        
        // 🚨 AUTO-RECONNECT on disconnection
        if (stateChange.current == ably.ConnectionState.disconnected ||
            stateChange.current == ably.ConnectionState.suspended ||
            stateChange.current == ably.ConnectionState.failed) {
          debugPrint('⚠️ Ably connection lost: ${stateChange.current} - waiting for auto-reconnect');
        }
        
        if (stateChange.current == ably.ConnectionState.connected) {
          debugPrint('✅ Ably connection restored/established');
        }
      });

      debugPrint('✅ Ably service initialized with clientId: $clientId');
    } catch (e) {
      debugPrint('❌ Failed to initialize Ably: $e');
      rethrow;
    }
  }

  ably.RealtimeChannel getChannel(String channelName) {
    if (_realtime == null) {
      throw Exception('Ably not initialized. Call initialize() first.');
    }

    // Return existing channel if already created
    if (_channels.containsKey(channelName)) {
      return _channels[channelName]!;
    }

    // Create new channel (lazy initialization)
    final channel = _realtime!.channels.get(channelName);
    _channels[channelName] = channel;
    debugPrint('📡 Created channel: $channelName (total: ${_channels.length})');
    
    // 🧹 Auto-cleanup: Keep max 5 active channels to prevent memory leaks
    // Old channels are automatically detached when limit exceeded
    if (_channels.length > 5) {
      final oldestKey = _channels.keys.first;
      debugPrint('🧹 Auto-cleanup: Detaching old channel: $oldestKey');
      _channels[oldestKey]?.detach();
      _channels.remove(oldestKey);
    }
    
    return channel;
  }

  /// Manually cleanup a specific channel when delivery is complete
  Future<void> cleanupChannel(String channelName) async {
    if (_channels.containsKey(channelName)) {
      try {
        await _channels[channelName]!.detach();
        _channels.remove(channelName);
        debugPrint('🧹 Cleaned up channel: $channelName');
      } catch (e) {
        debugPrint('⚠️ Error cleaning up channel $channelName: $e');
      }
    }
  }

  Future<void> publishLocation(String deliveryId, Map<String, dynamic> location) async {
    try {
      final channelName = 'tracking:$deliveryId';
      final channel = getChannel(channelName);
      
      await channel.publish(
        name: 'location-update',  // ✅ CRITICAL FIX: Changed from 'location_update' to match customer app
        data: location,
      );
      
      debugPrint('📍 Published location to $channelName with event: location-update');
    } catch (e) {
      debugPrint('❌ Failed to publish location: $e');
    }
  }

  /// Publish status update to Ably for real-time customer notifications
  /// NOTE: Only send intermediate statuses via Ably (going_to_pickup, at_pickup, etc.)
  /// Don't send: pending, driver_offered, driver_assigned (database only)
  Future<void> publishStatusUpdate({
    required String deliveryId,
    required String status,
    Map<String, dynamic>? driverLocation,
    String? notes,
  }) async {
    try {
      final channelName = 'tracking:$deliveryId';
      final channel = getChannel(channelName);
      
      final payload = {
        'delivery_id': deliveryId,
        'status': status,
        'timestamp': DateTime.now().toIso8601String(),
        if (driverLocation != null) 'driver_location': driverLocation,
        if (notes != null) 'notes': notes,
      };
      
      await channel.publish(
        name: 'status-update',  // ✅ Match customer app event name
        data: payload,
      );
      
      debugPrint('📢 Published status-update to $channelName: $status');
    } catch (e) {
      debugPrint('❌ Failed to publish status update: $e');
      // Don't rethrow - status updates are non-critical, driver can continue
    }
  }

  /// Publish stop update event to Ably for multi-stop deliveries
  /// Used to notify customer app when driver arrives/completes each stop
  Future<void> publishStopUpdate({
    required String deliveryId,
    required String stopId,
    required int stopNumber,
    required String stopType, // 'pickup' or 'dropoff'
    required String status,   // 'pending', 'in_progress', 'completed', 'failed'
    Map<String, dynamic>? driverLocation,
    String? proofPhotoUrl,
    String? completionNotes,
  }) async {
    try {
      final channelName = 'tracking:$deliveryId';
      final channel = getChannel(channelName);
      
      final payload = {
        'delivery_id': deliveryId,
        'stop_id': stopId,
        'stop_number': stopNumber,
        'stop_type': stopType,
        'status': status,
        'timestamp': DateTime.now().toIso8601String(),
        if (driverLocation != null) 'driver_location': driverLocation,
        if (proofPhotoUrl != null) 'proof_photo_url': proofPhotoUrl,
        if (completionNotes != null) 'completion_notes': completionNotes,
      };
      
      await channel.publish(
        name: 'stop-update',  // Match customer app event name
        data: payload,
      );
      
      debugPrint('📦 Published stop-update to $channelName: Stop #$stopNumber ($stopType) - $status');
    } catch (e) {
      debugPrint('❌ Failed to publish stop update: $e');
      // Don't rethrow - stop updates are non-critical for database operations
    }
  }

  Future<void> enterPresence(String deliveryId) async {
    try {
      final channelName = 'tracking:$deliveryId';
      final channel = getChannel(channelName);
      
      await channel.presence.enter();
      debugPrint('👋 Entered presence: $channelName');
    } catch (e) {
      debugPrint('❌ Failed to enter presence: $e');
    }
  }

  Future<void> leavePresence(String deliveryId) async {
    try {
      final channelName = 'tracking:$deliveryId';
      final channel = getChannel(channelName);
      
      await channel.presence.leave();
      debugPrint('👋 Left presence: $channelName');
    } catch (e) {
      debugPrint('❌ Failed to leave presence: $e');
    }
  }

  /// Get connection state
  ably.ConnectionState? get connectionState => _realtime?.connection.state;
  
  /// Check if connected
  bool get isConnected => _realtime?.connection.state == ably.ConnectionState.connected;
  
  /// Force reconnect if disconnected
  Future<void> reconnect() async {
    if (_realtime == null) {
      debugPrint('⚠️ Ably not initialized, cannot reconnect');
      return;
    }
    
    try {
      final currentState = _realtime!.connection.state;
      debugPrint('🔄 Current Ably state: $currentState');
      
      if (currentState == ably.ConnectionState.disconnected ||
          currentState == ably.ConnectionState.suspended ||
          currentState == ably.ConnectionState.failed) {
        debugPrint('🔄 Forcing Ably reconnection...');
        await _realtime!.connection.connect();
      } else if (currentState == ably.ConnectionState.connected) {
        debugPrint('✅ Ably already connected');
      } else {
        debugPrint('⏳ Ably connecting... state: $currentState');
      }
    } catch (e) {
      debugPrint('❌ Failed to reconnect Ably: $e');
    }
  }

  Future<void> dispose() async {
    // 🚨 FIX: Properly detach and clean up channels
    for (var entry in _channels.entries) {
      try {
        debugPrint('📡 Detaching channel: ${entry.key}');
        await entry.value.detach();
      } catch (e) {
        debugPrint('⚠️ Error detaching channel ${entry.key}: $e');
      }
    }
    _channels.clear();
    
    // Close connection
    try {
      await _realtime?.close();
    } catch (e) {
      debugPrint('⚠️ Error closing Ably: $e');
    }
    
    _realtime = null;
    _clientId = null;
    debugPrint('🔌 Ably service disposed');
  }
}
