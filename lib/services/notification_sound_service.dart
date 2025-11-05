import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Service for playing notification sounds
class NotificationSoundService {
  static final NotificationSoundService _instance = NotificationSoundService._internal();
  factory NotificationSoundService() => _instance;
  NotificationSoundService._internal();

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isInitialized = false;

  /// Initialize the audio player
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Set audio mode for notifications (doesn't affect other audio)
      await _audioPlayer.setReleaseMode(ReleaseMode.stop);
      await _audioPlayer.setVolume(1.0);
      _isInitialized = true;
      debugPrint('✅ NotificationSoundService initialized');
    } catch (e) {
      debugPrint('❌ Error initializing NotificationSoundService: $e');
    }
  }

  /// Play the new offer notification sound
  Future<void> playOfferSound() async {
    try {
      if (!_isInitialized) {
        await initialize();
      }

      debugPrint('🔔 Playing offer notification sound...');
      
      // Stop any currently playing sound first
      await _audioPlayer.stop();
      
      // Play the notification sound from assets
      await _audioPlayer.play(
        AssetSource('sound/new-notification-022-370046.mp3'),
        volume: 1.0,
      );
      
      debugPrint('✅ Offer notification sound played');
    } catch (e) {
      debugPrint('❌ Error playing offer sound: $e');
      // Don't throw - sound is not critical to app function
    }
  }

  /// Stop any currently playing sound
  Future<void> stop() async {
    try {
      await _audioPlayer.stop();
    } catch (e) {
      debugPrint('❌ Error stopping sound: $e');
    }
  }

  /// Dispose the audio player
  Future<void> dispose() async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.dispose();
      _isInitialized = false;
      debugPrint('✅ NotificationSoundService disposed');
    } catch (e) {
      debugPrint('❌ Error disposing NotificationSoundService: $e');
    }
  }
}
