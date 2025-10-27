import 'dart:async';
import 'package:ably_flutter/ably_flutter.dart' as ably;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../models/chat_message.dart';

/// Chat service for real-time driver-customer communication via Ably
class ChatService {
  static final ChatService _instance = ChatService._internal();
  factory ChatService() => _instance;
  ChatService._internal();

  ably.Realtime? _ablyClient;
  final Map<String, ably.RealtimeChannel> _channels = {};
  final Map<String, StreamController<ChatMessage>> _messageControllers = {};
  final Map<String, StreamController<bool>> _typingControllers = {};
  final Map<String, List<ChatMessage>> _messageCache = {};
  
  final SupabaseClient _supabase = Supabase.instance.client;
  final ImagePicker _imagePicker = ImagePicker();

  bool _isInitialized = false;

  /// Initialize Ably client with API key
  Future<void> initialize(String ablyApiKey) async {
    if (_isInitialized) return;

    try {
      _ablyClient = ably.Realtime(
        options: ably.ClientOptions(
          key: ablyApiKey,
          clientId: _supabase.auth.currentUser?.id ?? 'driver-${const Uuid().v4()}',
          logLevel: ably.LogLevel.error,
        ),
      );

      // Monitor connection state
      _ablyClient!.connection.on().listen((connectionStateChange) {
        debugPrint('🔌 Ably connection: ${connectionStateChange.event}');
      });

      _isInitialized = true;
      debugPrint('✅ Chat service initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize chat service: $e');
      rethrow;
    }
  }

  /// Get or create channel for delivery chat
  ably.RealtimeChannel _getChannel(String deliveryId) {
    final channelName = 'delivery:$deliveryId:chat';
    
    if (_channels.containsKey(deliveryId)) {
      return _channels[deliveryId]!;
    }

    final channel = _ablyClient!.channels.get(channelName);
    _channels[deliveryId] = channel;
    
    debugPrint('📡 Created channel: $channelName');
    return channel;
  }

  /// Subscribe to chat for a delivery
  Stream<ChatMessage> subscribeToChat(String deliveryId) {
    if (_messageControllers.containsKey(deliveryId)) {
      return _messageControllers[deliveryId]!.stream;
    }

    final controller = StreamController<ChatMessage>.broadcast();
    _messageControllers[deliveryId] = controller;
    _messageCache[deliveryId] = [];

    final channel = _getChannel(deliveryId);

    // Subscribe to messages
    channel.subscribe(name: 'message').listen((message) {
      try {
        final chatMessage = ChatMessage.fromJson(message.data as Map<String, dynamic>);
        _messageCache[deliveryId]!.add(chatMessage);
        controller.add(chatMessage);
        debugPrint('💬 Received message: ${chatMessage.message}');
      } catch (e) {
        debugPrint('❌ Error parsing message: $e');
      }
    });

    // Subscribe to read receipts
    channel.subscribe(name: 'message:read').listen((message) {
      try {
        final data = message.data as Map<String, dynamic>;
        final messageId = data['messageId'] as String;
        final readBy = data['readBy'] as String;
        
        _updateMessageReadStatus(deliveryId, messageId, readBy);
      } catch (e) {
        debugPrint('❌ Error handling read receipt: $e');
      }
    });

    // Subscribe to reactions
    channel.subscribe(name: 'message:reaction').listen((message) {
      try {
        final data = message.data as Map<String, dynamic>;
        final messageId = data['messageId'] as String;
        final emoji = data['emoji'] as String;
        final userId = data['userId'] as String;
        final action = data['action'] as String;
        
        _updateMessageReaction(deliveryId, messageId, emoji, userId, action);
      } catch (e) {
        debugPrint('❌ Error handling reaction: $e');
      }
    });

    // Load message history
    _loadMessageHistory(deliveryId);

    return controller.stream;
  }

  /// Subscribe to typing indicators
  Stream<bool> subscribeToTyping(String deliveryId, String currentUserId) {
    if (_typingControllers.containsKey(deliveryId)) {
      return _typingControllers[deliveryId]!.stream;
    }

    final controller = StreamController<bool>.broadcast();
    _typingControllers[deliveryId] = controller;

    final channel = _getChannel(deliveryId);
    channel.subscribe(name: 'typing').listen((message) {
      try {
        final data = message.data as Map<String, dynamic>;
        final userId = data['userId'] as String;
        final isTyping = data['typing'] as bool;
        
        // Only show typing indicator if it's not the current user
        if (userId != currentUserId) {
          controller.add(isTyping);
        }
      } catch (e) {
        debugPrint('❌ Error handling typing indicator: $e');
      }
    });

    return controller.stream;
  }

  /// Load message history from Ably
  Future<void> _loadMessageHistory(String deliveryId) async {
    try {
      final channel = _getChannel(deliveryId);
      final history = await channel.history(
        ably.RealtimeHistoryParams(
          limit: 100,
          direction: 'backwards',
        ),
      );

      final messages = <ChatMessage>[];
      for (final item in history.items) {
        if (item.name == 'message' && item.data != null) {
          try {
            final msg = ChatMessage.fromJson(item.data as Map<String, dynamic>);
            messages.add(msg);
          } catch (e) {
            debugPrint('⚠️ Skipping invalid message in history: $e');
          }
        }
      }

      // Sort by timestamp
      messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      
      _messageCache[deliveryId] = messages;
      
      // Emit all historical messages
      final controller = _messageControllers[deliveryId];
      if (controller != null) {
        for (final msg in messages) {
          controller.add(msg);
        }
      }

      debugPrint('📜 Loaded ${messages.length} messages from history');
    } catch (e) {
      debugPrint('❌ Error loading message history: $e');
    }
  }

  /// Send text message
  Future<void> sendTextMessage({
    required String deliveryId,
    required String driverId,
    required String driverName,
    required String text,
  }) async {
    try {
      final message = ChatMessage.text(
        deliveryId: deliveryId,
        senderId: driverId,
        senderName: driverName,
        text: text,
      );

      final channel = _getChannel(deliveryId);
      await channel.publish(name: 'message', data: message.toJson());
      
      debugPrint('✅ Sent text message: $text');
    } catch (e) {
      debugPrint('❌ Failed to send message: $e');
      rethrow;
    }
  }

  /// Send quick reply message
  Future<void> sendQuickReply({
    required String deliveryId,
    required String driverId,
    required String driverName,
    required QuickReply quickReply,
  }) async {
    try {
      final message = ChatMessage.quickReply(
        deliveryId: deliveryId,
        senderId: driverId,
        senderName: driverName,
        quickReplyId: quickReply.id,
        emoji: quickReply.emoji,
        text: quickReply.text,
      );

      final channel = _getChannel(deliveryId);
      await channel.publish(name: 'message', data: message.toJson());
      
      debugPrint('✅ Sent quick reply: ${quickReply.displayText}');
    } catch (e) {
      debugPrint('❌ Failed to send quick reply: $e');
      rethrow;
    }
  }

  /// Pick and send image
  Future<void> sendImageMessage({
    required String deliveryId,
    required String driverId,
    required String driverName,
    ImageSource source = ImageSource.gallery,
  }) async {
    try {
      // Pick image
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 75,
      );

      if (image == null) {
        debugPrint('⚠️ No image selected');
        return;
      }

      // Upload to Supabase Storage
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final uuid = const Uuid().v4();
      final ext = image.path.split('.').last;
      final path = 'deliveries/chat/$deliveryId/${timestamp}_$uuid.$ext';

      debugPrint('📤 Uploading image to: $path');

      final bytes = await image.readAsBytes();
      await _supabase.storage.from('chat-images').uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(
          contentType: 'image/jpeg',
        ),
      );

      // Get public URL
      final imageUrl = _supabase.storage.from('chat-images').getPublicUrl(path);
      debugPrint('✅ Image uploaded: $imageUrl');

      // Send message with image URL
      final message = ChatMessage.image(
        deliveryId: deliveryId,
        senderId: driverId,
        senderName: driverName,
        imageUrl: imageUrl,
        caption: 'Photo',
      );

      final channel = _getChannel(deliveryId);
      await channel.publish(name: 'message', data: message.toJson());
      
      debugPrint('✅ Sent image message');
    } catch (e) {
      debugPrint('❌ Failed to send image: $e');
      rethrow;
    }
  }

  /// Send read receipt
  Future<void> markAsRead({
    required String deliveryId,
    required String messageId,
    required String userId,
  }) async {
    try {
      final channel = _getChannel(deliveryId);
      await channel.publish(
        name: 'message:read',
        data: {
          'messageId': messageId,
          'readBy': userId,
          'readAt': DateTime.now().millisecondsSinceEpoch,
        },
      );
      
      debugPrint('✅ Marked message as read: $messageId');
    } catch (e) {
      debugPrint('❌ Failed to mark as read: $e');
    }
  }

  /// Send typing indicator
  Future<void> sendTypingIndicator({
    required String deliveryId,
    required String userId,
    required String userName,
    required bool isTyping,
  }) async {
    try {
      final channel = _getChannel(deliveryId);
      await channel.publish(
        name: 'typing',
        data: {
          'typing': isTyping,
          'userId': userId,
          'userName': userName,
        },
      );
    } catch (e) {
      debugPrint('❌ Failed to send typing indicator: $e');
    }
  }

  /// Add reaction to message
  Future<void> addReaction({
    required String deliveryId,
    required String messageId,
    required String emoji,
    required String userId,
  }) async {
    try {
      final channel = _getChannel(deliveryId);
      await channel.publish(
        name: 'message:reaction',
        data: {
          'messageId': messageId,
          'emoji': emoji,
          'userId': userId,
          'action': 'add',
        },
      );
      
      debugPrint('✅ Added reaction: $emoji');
    } catch (e) {
      debugPrint('❌ Failed to add reaction: $e');
    }
  }

  /// Remove reaction from message
  Future<void> removeReaction({
    required String deliveryId,
    required String messageId,
    required String emoji,
    required String userId,
  }) async {
    try {
      final channel = _getChannel(deliveryId);
      await channel.publish(
        name: 'message:reaction',
        data: {
          'messageId': messageId,
          'emoji': emoji,
          'userId': userId,
          'action': 'remove',
        },
      );
      
      debugPrint('✅ Removed reaction: $emoji');
    } catch (e) {
      debugPrint('❌ Failed to remove reaction: $e');
    }
  }

  /// Update message read status locally
  void _updateMessageReadStatus(String deliveryId, String messageId, String userId) {
    final messages = _messageCache[deliveryId];
    if (messages == null) return;

    final index = messages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;

    final message = messages[index];
    if (!message.readBy.contains(userId)) {
      final updatedMessage = message.copyWith(
        readBy: [...message.readBy, userId],
      );
      messages[index] = updatedMessage;
      _messageControllers[deliveryId]?.add(updatedMessage);
    }
  }

  /// Update message reaction locally
  void _updateMessageReaction(
    String deliveryId,
    String messageId,
    String emoji,
    String userId,
    String action,
  ) {
    final messages = _messageCache[deliveryId];
    if (messages == null) return;

    final index = messages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;

    final message = messages[index];
    final reactions = Map<String, List<String>>.from(message.reactions);

    if (action == 'add') {
      reactions[emoji] = [...(reactions[emoji] ?? []), userId];
    } else if (action == 'remove') {
      reactions[emoji]?.remove(userId);
      if (reactions[emoji]?.isEmpty ?? false) {
        reactions.remove(emoji);
      }
    }

    final updatedMessage = message.copyWith(reactions: reactions);
    messages[index] = updatedMessage;
    _messageControllers[deliveryId]?.add(updatedMessage);
  }

  /// Get cached messages for delivery
  List<ChatMessage> getCachedMessages(String deliveryId) {
    return _messageCache[deliveryId] ?? [];
  }

  /// Unsubscribe from chat
  void unsubscribeFromChat(String deliveryId) {
    final channel = _channels[deliveryId];
    if (channel != null) {
      channel.detach();
      _channels.remove(deliveryId);
    }

    _messageControllers[deliveryId]?.close();
    _messageControllers.remove(deliveryId);
    
    _typingControllers[deliveryId]?.close();
    _typingControllers.remove(deliveryId);
    
    _messageCache.remove(deliveryId);
    
    debugPrint('🔌 Unsubscribed from chat: $deliveryId');
  }

  /// Dispose all resources
  void dispose() {
    for (final controller in _messageControllers.values) {
      controller.close();
    }
    for (final controller in _typingControllers.values) {
      controller.close();
    }
    _messageControllers.clear();
    _typingControllers.clear();
    _channels.clear();
    _messageCache.clear();
    
    _ablyClient?.close();
    _ablyClient = null;
    _isInitialized = false;
    
    debugPrint('🔌 Chat service disposed');
  }

  /// Check if service is initialized
  bool get isInitialized => _isInitialized;

  /// Get connection state
  ably.ConnectionState? get connectionState => _ablyClient?.connection.state;
}
