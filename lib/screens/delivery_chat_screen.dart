import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/chat_message.dart';
import '../models/delivery.dart';
import '../services/chat_service.dart';
import '../widgets/chat_widgets.dart';
import '../core/supabase_config.dart';

class DeliveryChatScreen extends StatefulWidget {
  final Delivery delivery;
  final String driverId;
  final String driverName;

  const DeliveryChatScreen({
    super.key,
    required this.delivery,
    required this.driverId,
    required this.driverName,
  });

  @override
  State<DeliveryChatScreen> createState() => _DeliveryChatScreenState();
}

class _DeliveryChatScreenState extends State<DeliveryChatScreen> {
  final ChatService _chatService = ChatService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  final List<ChatMessage> _messages = [];
  StreamSubscription<ChatMessage>? _messageSubscription;
  StreamSubscription<bool>? _typingSubscription;
  
  bool _isTyping = false;
  bool _customerIsTyping = false;
  bool _isLoading = true;
  bool _showQuickReplies = true;
  
  Timer? _typingTimer;

  @override
  void initState() {
    super.initState();
    _initializeChat();
    _messageController.addListener(_onMessageChanged);
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _typingSubscription?.cancel();
    _typingTimer?.cancel();
    _messageController.removeListener(_onMessageChanged);
    _messageController.dispose();
    _scrollController.dispose();
    _chatService.unsubscribeFromChat(widget.delivery.id);
    super.dispose();
  }

  Future<void> _initializeChat() async {
    try {
      setState(() => _isLoading = true);

      // Subscribe to messages
      _messageSubscription = _chatService
          .subscribeToChat(widget.delivery.id)
          .listen(_onNewMessage);

      // Subscribe to typing indicators
      _typingSubscription = _chatService
          .subscribeToTyping(widget.delivery.id, widget.driverId)
          .listen((isTyping) {
        setState(() => _customerIsTyping = isTyping);
      });

      // Load existing messages from cache
      _messages.addAll(_chatService.getCachedMessages(widget.delivery.id));

      setState(() => _isLoading = false);
      _scrollToBottom();

      // Mark all customer messages as read
      _markCustomerMessagesAsRead();
    } catch (e) {
      debugPrint('❌ Error initializing chat: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load chat: $e'),
            backgroundColor: SwiftDashColors.dangerRed,
          ),
        );
      }
    }
  }

  void _onNewMessage(ChatMessage message) {
    setState(() {
      // Update existing message or add new one
      final index = _messages.indexWhere((m) => m.id == message.id);
      if (index != -1) {
        _messages[index] = message;
      } else {
        _messages.add(message);
        _scrollToBottom();
      }
    });

    // Mark customer messages as read
    if (message.isFromCustomer && !message.isReadBy(widget.driverId)) {
      _chatService.markAsRead(
        deliveryId: widget.delivery.id,
        messageId: message.id,
        userId: widget.driverId,
      );
    }
  }

  void _onMessageChanged() {
    final text = _messageController.text.trim();
    final shouldBeTyping = text.isNotEmpty;

    if (_isTyping != shouldBeTyping) {
      setState(() => _isTyping = shouldBeTyping);
      _chatService.sendTypingIndicator(
        deliveryId: widget.delivery.id,
        userId: widget.driverId,
        userName: widget.driverName,
        isTyping: shouldBeTyping,
      );

      // Auto-stop typing after 3 seconds
      _typingTimer?.cancel();
      if (shouldBeTyping) {
        _typingTimer = Timer(const Duration(seconds: 3), () {
          setState(() => _isTyping = false);
          _chatService.sendTypingIndicator(
            deliveryId: widget.delivery.id,
            userId: widget.driverId,
            userName: widget.driverName,
            isTyping: false,
          );
        });
      }
    }
  }

  void _markCustomerMessagesAsRead() {
    for (final message in _messages) {
      if (message.isFromCustomer && !message.isReadBy(widget.driverId)) {
        _chatService.markAsRead(
          deliveryId: widget.delivery.id,
          messageId: message.id,
          userId: widget.driverId,
        );
      }
    }
  }

  Future<void> _sendTextMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();
    setState(() {
      _isTyping = false;
      _showQuickReplies = false;
    });

    try {
      await _chatService.sendTextMessage(
        deliveryId: widget.delivery.id,
        driverId: widget.driverId,
        driverName: widget.driverName,
        text: text,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send message: $e'),
            backgroundColor: SwiftDashColors.dangerRed,
          ),
        );
      }
    }
  }

  Future<void> _sendQuickReply(QuickReply quickReply) async {
    setState(() => _showQuickReplies = false);
    
    try {
      await _chatService.sendQuickReply(
        deliveryId: widget.delivery.id,
        driverId: widget.driverId,
        driverName: widget.driverName,
        quickReply: quickReply,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send quick reply: $e'),
            backgroundColor: SwiftDashColors.dangerRed,
          ),
        );
      }
    }
  }

  Future<void> _sendImage(ImageSource source) async {
    try {
      await _chatService.sendImageMessage(
        deliveryId: widget.delivery.id,
        driverId: widget.driverId,
        driverName: widget.driverName,
        source: source,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send image: $e'),
            backgroundColor: SwiftDashColors.dangerRed,
          ),
        );
      }
    }
  }

  void _handleReaction(ChatMessage message, String emoji) {
    final hasReacted = message.reactions[emoji]?.contains(widget.driverId) ?? false;
    
    if (hasReacted) {
      _chatService.removeReaction(
        deliveryId: widget.delivery.id,
        messageId: message.id,
        emoji: emoji,
        userId: widget.driverId,
      );
    } else {
      _chatService.addReaction(
        deliveryId: widget.delivery.id,
        messageId: message.id,
        emoji: emoji,
        userId: widget.driverId,
      );
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showImagePicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(context);
                _sendImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _sendImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: SwiftDashColors.darkBlue,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.delivery.deliveryContactName,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            if (_customerIsTyping)
              const Text(
                'typing...',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white70,
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.phone, color: Colors.white),
            onPressed: () {
              // Call customer (implement phone call logic)
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No messages yet',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Start a conversation with the customer',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        itemCount: _messages.length + (_customerIsTyping ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (_customerIsTyping && index == _messages.length) {
                            return TypingIndicator(
                              userName: widget.delivery.deliveryContactName,
                            );
                          }
                          
                          final message = _messages[index];
                          return MessageBubble(
                            message: message,
                            isFromCurrentUser: message.isFromDriver,
                            onReactionTap: (emoji) => _handleReaction(message, emoji),
                          );
                        },
                      ),
          ),

          // Quick replies (show at the start or when toggled)
          if (_showQuickReplies && _messages.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                border: Border(
                  top: BorderSide(color: Colors.grey[300]!),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Quick Replies',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => setState(() => _showQuickReplies = false),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: DriverQuickReplies.all.map((quickReply) {
                      return QuickReplyButton(
                        quickReply: quickReply,
                        onTap: () => _sendQuickReply(quickReply),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

          // Message input
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.2),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                // Image picker button
                IconButton(
                  icon: Icon(Icons.photo, color: SwiftDashColors.lightBlue),
                  onPressed: _showImagePicker,
                ),
                
                // Quick reply toggle
                if (!_showQuickReplies)
                  IconButton(
                    icon: Icon(Icons.flash_on, color: SwiftDashColors.lightBlue),
                    onPressed: () => setState(() => _showQuickReplies = true),
                  ),
                
                // Message input field
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: TextField(
                      controller: _messageController,
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                  ),
                ),
                
                const SizedBox(width: 8),
                
                // Send button
                CircleAvatar(
                  backgroundColor: SwiftDashColors.lightBlue,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 20),
                    onPressed: _sendTextMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
