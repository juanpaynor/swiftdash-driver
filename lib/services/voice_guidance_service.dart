import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:developer' as developer;

/// Service for handling voice-guided turn-by-turn navigation announcements
/// 
/// Features:
/// - Multi-language support (English, Filipino)
/// - Audio session configuration (background audio mixing)
/// - Customizable speech rate and volume
/// - Queue management for announcements
class VoiceGuidanceService {
  static final VoiceGuidanceService _instance = VoiceGuidanceService._internal();
  factory VoiceGuidanceService() => _instance;
  VoiceGuidanceService._internal();

  final FlutterTts _flutterTts = FlutterTts();
  bool _isInitialized = false;
  bool _isEnabled = true;
  String _currentLanguage = 'en-US'; // Default to English
  double _speechRate = 0.5; // Normal speed
  double _volume = 1.0; // Max volume
  bool _isSpeaking = false;

  // Speech settings keys
  static const String _keyVoiceEnabled = 'voice_guidance_enabled';
  static const String _keyLanguage = 'voice_guidance_language';
  static const String _keySpeechRate = 'voice_guidance_speech_rate';

  /// Supported languages for voice guidance
  static const Map<String, String> supportedLanguages = {
    'en-US': 'English (US)',
    'en-GB': 'English (UK)',
    'fil-PH': 'Filipino',
  };

  /// Initialize the TTS engine and load saved preferences
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Load saved preferences
      await _loadPreferences();

      // Configure TTS
      await _configureTts();

      // Set up completion handler
      _flutterTts.setCompletionHandler(() {
        _isSpeaking = false;
        developer.log('Voice guidance completed', name: 'VoiceGuidanceService');
      });

      // Set up error handler
      _flutterTts.setErrorHandler((msg) {
        _isSpeaking = false;
        developer.log('TTS Error: $msg', name: 'VoiceGuidanceService');
      });

      _isInitialized = true;
      developer.log('Voice Guidance Service initialized', name: 'VoiceGuidanceService');
    } catch (e) {
      developer.log('Failed to initialize TTS: $e', name: 'VoiceGuidanceService');
    }
  }

  /// Configure TTS settings
  Future<void> _configureTts() async {
    try {
      // Set language
      await _flutterTts.setLanguage(_currentLanguage);

      // Set speech rate (0.0 to 1.0, where 0.5 is normal)
      await _flutterTts.setSpeechRate(_speechRate);

      // Set volume (0.0 to 1.0)
      await _flutterTts.setVolume(_volume);

      // Set pitch (0.5 to 2.0, where 1.0 is normal)
      await _flutterTts.setPitch(1.0);

      // Configure iOS-specific settings
      await _flutterTts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          IosTextToSpeechAudioCategoryOptions.duckOthers,
        ],
        IosTextToSpeechAudioMode.voicePrompt,
      );

      // Configure Android-specific settings
      await _flutterTts.awaitSpeakCompletion(true);
    } catch (e) {
      developer.log('Error configuring TTS: $e', name: 'VoiceGuidanceService');
    }
  }

  /// Load preferences from SharedPreferences
  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isEnabled = prefs.getBool(_keyVoiceEnabled) ?? true;
      _currentLanguage = prefs.getString(_keyLanguage) ?? 'en-US';
      _speechRate = prefs.getDouble(_keySpeechRate) ?? 0.5;
    } catch (e) {
      developer.log('Error loading preferences: $e', name: 'VoiceGuidanceService');
    }
  }

  /// Speak a navigation instruction
  /// 
  /// [text] - The text to speak
  /// [priority] - If true, interrupts current speech
  Future<void> speak(String text, {bool priority = false}) async {
    if (!_isEnabled) return;
    if (!_isInitialized) await initialize();

    try {
      if (priority && _isSpeaking) {
        await stop();
      }

      if (!_isSpeaking || priority) {
        _isSpeaking = true;
        developer.log('Speaking: $text', name: 'VoiceGuidanceService');
        await _flutterTts.speak(text);
      }
    } catch (e) {
      developer.log('Error speaking: $e', name: 'VoiceGuidanceService');
      _isSpeaking = false;
    }
  }

  /// Stop current speech
  Future<void> stop() async {
    if (_isSpeaking) {
      await _flutterTts.stop();
      _isSpeaking = false;
    }
  }

  /// Enable or disable voice guidance
  Future<void> setEnabled(bool enabled) async {
    _isEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyVoiceEnabled, enabled);

    if (!enabled) {
      await stop();
    }

    developer.log('Voice guidance ${enabled ? "enabled" : "disabled"}', 
      name: 'VoiceGuidanceService');
  }

  /// Set the language for voice guidance
  Future<void> setLanguage(String languageCode) async {
    if (!supportedLanguages.containsKey(languageCode)) {
      developer.log('Unsupported language: $languageCode', 
        name: 'VoiceGuidanceService');
      return;
    }

    _currentLanguage = languageCode;
    await _flutterTts.setLanguage(languageCode);
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLanguage, languageCode);

    developer.log('Language set to: ${supportedLanguages[languageCode]}', 
      name: 'VoiceGuidanceService');
  }

  /// Set the speech rate (0.0 to 1.0, where 0.5 is normal)
  Future<void> setSpeechRate(double rate) async {
    _speechRate = rate.clamp(0.0, 1.0);
    await _flutterTts.setSpeechRate(_speechRate);
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keySpeechRate, _speechRate);

    developer.log('Speech rate set to: $_speechRate', 
      name: 'VoiceGuidanceService');
  }

  /// Test the voice guidance with a sample phrase
  Future<void> testVoice() async {
    const testPhrases = {
      'en-US': 'Navigation ready. Voice guidance is working.',
      'en-GB': 'Navigation ready. Voice guidance is working.',
      'fil-PH': 'Handa na ang navigation. Gumagana ang voice guidance.',
    };

    final testPhrase = testPhrases[_currentLanguage] ?? testPhrases['en-US']!;
    await speak(testPhrase, priority: true);
  }

  // Getters
  bool get isEnabled => _isEnabled;
  bool get isSpeaking => _isSpeaking;
  String get currentLanguage => _currentLanguage;
  double get speechRate => _speechRate;

  /// Dispose resources
  Future<void> dispose() async {
    await stop();
    _isInitialized = false;
  }
}
