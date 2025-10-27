import 'package:uuid/uuid.dart';

/// Chat message model compatible with customer app
class ChatMessage {
  final String id;
  final String deliveryId;
  final String senderId;
  final String senderType; // 'driver' or 'customer'
  final String senderName;
  final String message;
  final String type; // 'text', 'image', 'quickReply', 'system'
  final int timestamp;
  final String? imageUrl;
  final String? quickReplyType;
  final Map<String, List<String>> reactions;
  final List<String> readBy;

  ChatMessage({
    required this.id,
    required this.deliveryId,
    required this.senderId,
    required this.senderType,
    required this.senderName,
    required this.message,
    required this.type,
    required this.timestamp,
    this.imageUrl,
    this.quickReplyType,
    Map<String, List<String>>? reactions,
    List<String>? readBy,
  })  : reactions = reactions ?? {},
        readBy = readBy ?? [];

  /// Create message from JSON (received from Ably)
  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      deliveryId: json['deliveryId'] as String,
      senderId: json['senderId'] as String,
      senderType: json['senderType'] as String,
      senderName: json['senderName'] as String,
      message: json['message'] as String,
      type: json['type'] as String,
      timestamp: json['timestamp'] as int,
      imageUrl: json['imageUrl'] as String?,
      quickReplyType: json['quickReplyType'] as String?,
      reactions: _parseReactions(json['reactions']),
      readBy: (json['readBy'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }

  /// Convert message to JSON (send to Ably)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'deliveryId': deliveryId,
      'senderId': senderId,
      'senderType': senderType,
      'senderName': senderName,
      'message': message,
      'type': type,
      'timestamp': timestamp,
      'imageUrl': imageUrl,
      'quickReplyType': quickReplyType,
      'reactions': reactions,
      'readBy': readBy,
    };
  }

  static Map<String, List<String>> _parseReactions(dynamic reactionsData) {
    if (reactionsData == null) return {};
    if (reactionsData is Map) {
      return reactionsData.map((key, value) {
        return MapEntry(
          key.toString(),
          (value as List<dynamic>).cast<String>(),
        );
      });
    }
    return {};
  }

  /// Create a text message
  factory ChatMessage.text({
    required String deliveryId,
    required String senderId,
    required String senderName,
    required String text,
  }) {
    return ChatMessage(
      id: const Uuid().v4(),
      deliveryId: deliveryId,
      senderId: senderId,
      senderType: 'driver',
      senderName: senderName,
      message: text,
      type: 'text',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      readBy: [senderId],
    );
  }

  /// Create an image message
  factory ChatMessage.image({
    required String deliveryId,
    required String senderId,
    required String senderName,
    required String imageUrl,
    String caption = 'Photo',
  }) {
    return ChatMessage(
      id: const Uuid().v4(),
      deliveryId: deliveryId,
      senderId: senderId,
      senderType: 'driver',
      senderName: senderName,
      message: caption,
      type: 'image',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      imageUrl: imageUrl,
      readBy: [senderId],
    );
  }

  /// Create a quick reply message
  factory ChatMessage.quickReply({
    required String deliveryId,
    required String senderId,
    required String senderName,
    required String quickReplyId,
    required String emoji,
    required String text,
  }) {
    return ChatMessage(
      id: const Uuid().v4(),
      deliveryId: deliveryId,
      senderId: senderId,
      senderType: 'driver',
      senderName: senderName,
      message: '$emoji $text',
      type: 'quickReply',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      quickReplyType: quickReplyId,
      readBy: [senderId],
    );
  }

  /// Check if message is from driver
  bool get isFromDriver => senderType == 'driver';

  /// Check if message is from customer
  bool get isFromCustomer => senderType == 'customer';

  /// Check if message has been read by specific user
  bool isReadBy(String userId) => readBy.contains(userId);

  /// Copy with method for updating properties
  ChatMessage copyWith({
    Map<String, List<String>>? reactions,
    List<String>? readBy,
  }) {
    return ChatMessage(
      id: id,
      deliveryId: deliveryId,
      senderId: senderId,
      senderType: senderType,
      senderName: senderName,
      message: message,
      type: type,
      timestamp: timestamp,
      imageUrl: imageUrl,
      quickReplyType: quickReplyType,
      reactions: reactions ?? this.reactions,
      readBy: readBy ?? this.readBy,
    );
  }
}

/// Quick reply template
class QuickReply {
  final String id;
  final String emoji;
  final String text;

  const QuickReply({
    required this.id,
    required this.emoji,
    required this.text,
  });

  String get displayText => '$emoji $text';
}

/// Driver quick reply templates (matching customer app)
class DriverQuickReplies {
  static const arrived = QuickReply(
    id: 'driver_arrived',
    emoji: '🚗',
    text: "I'm here",
  );

  static const fiveMin = QuickReply(
    id: 'driver_5min',
    emoji: '⏱️',
    text: '5 min away',
  );

  static const traffic = QuickReply(
    id: 'driver_traffic',
    emoji: '🚦',
    text: 'Traffic delay',
  );

  static const cantFind = QuickReply(
    id: 'driver_cant_find',
    emoji: '📍',
    text: "Can't find location",
  );

  static const callMe = QuickReply(
    id: 'driver_call_me',
    emoji: '📞',
    text: 'Please call me',
  );

  static const delivered = QuickReply(
    id: 'driver_delivered',
    emoji: '✅',
    text: 'Package delivered!',
  );

  static const List<QuickReply> all = [
    arrived,
    fiveMin,
    traffic,
    cantFind,
    callMe,
    delivered,
  ];
}
