import 'dart:developer' as developer;
import 'navigation_service.dart';
import 'voice_guidance_service.dart';

/// Manages when and what navigation announcements should be spoken
/// 
/// Features:
/// - Distance-based announcement thresholds
/// - Prevents duplicate announcements
/// - Formats instructions into natural speech
/// - Handles multi-language announcement formatting
class NavigationAnnouncementManager {
  final VoiceGuidanceService _voiceService = VoiceGuidanceService();
  
  // Track announced instructions to prevent duplicates
  final Set<String> _announcedInstructions = {};
  
  // Distance thresholds for announcements (in meters)
  static const List<double> distanceThresholds = [
    1000.0, // 1 km
    500.0,  // 500 m
    200.0,  // 200 m
    100.0,  // 100 m
    50.0,   // 50 m
    20.0,   // 20 m - Final warning
  ];

  /// Initialize the announcement manager
  Future<void> initialize() async {
    await _voiceService.initialize();
  }

  /// Process a navigation instruction and determine if it should be announced
  /// 
  /// [instruction] - The current navigation instruction
  /// [distanceToStep] - Distance remaining to this step in meters
  Future<void> processInstruction(
    NavigationInstruction instruction,
    double distanceToStep,
  ) async {
    // Find the appropriate threshold for this distance
    final threshold = _getAnnouncementThreshold(distanceToStep);
    
    if (threshold == null) return; // Too far or too close
    
    // Create unique key for this instruction at this threshold
    final key = '${instruction.instruction}_$threshold';
    
    // Check if we've already announced this
    if (_announcedInstructions.contains(key)) return;
    
    // Mark as announced
    _announcedInstructions.add(key);
    
    // Format and speak the announcement
    final announcement = _formatAnnouncement(
      instruction,
      distanceToStep,
      threshold,
    );
    
    await _voiceService.speak(announcement);
    
    developer.log(
      'Announced: $announcement (distance: ${distanceToStep.toStringAsFixed(0)}m)',
      name: 'NavigationAnnouncementManager',
    );
  }

  /// Get the appropriate announcement threshold for a given distance
  /// Returns null if no announcement should be made at this distance
  double? _getAnnouncementThreshold(double distance) {
    for (final threshold in distanceThresholds) {
      // Allow 10% margin below threshold to catch the announcement
      if (distance <= threshold && distance >= threshold * 0.9) {
        return threshold;
      }
    }
    return null;
  }

  /// Format an instruction into natural speech
  String _formatAnnouncement(
    NavigationInstruction instruction,
    double distance,
    double threshold,
  ) {
    final language = _voiceService.currentLanguage;
    
    // Format distance
    final distanceText = _formatDistance(distance, language);
    
    // Get the instruction text
    final instructionText = instruction.instruction;
    
    // Combine into announcement
    if (language.startsWith('fil')) {
      // Filipino
      return _formatFilipinoAnnouncement(distanceText, instructionText, distance);
    } else {
      // English (default)
      return _formatEnglishAnnouncement(distanceText, instructionText, distance);
    }
  }

  /// Format announcement in English
  String _formatEnglishAnnouncement(
    String distanceText,
    String instruction,
    double distance,
  ) {
    if (distance <= 50) {
      // Immediate instruction
      return instruction;
    } else {
      // Distance-based instruction
      return 'In $distanceText, $instruction';
    }
  }

  /// Format announcement in Filipino
  String _formatFilipinoAnnouncement(
    String distanceText,
    String instruction,
    double distance,
  ) {
    if (distance <= 50) {
      // Immediate instruction
      return instruction;
    } else {
      // Distance-based instruction
      return 'Sa loob ng $distanceText, $instruction';
    }
  }

  /// Format distance into readable text
  String _formatDistance(double meters, String language) {
    if (language.startsWith('fil')) {
      // Filipino
      if (meters >= 1000) {
        final km = (meters / 1000).toStringAsFixed(1);
        return '$km kilometro';
      } else {
        return '${meters.round()} metro';
      }
    } else {
      // English
      if (meters >= 1000) {
        final km = (meters / 1000).toStringAsFixed(1);
        return '$km kilometers';
      } else if (meters >= 100) {
        return '${meters.round()} meters';
      } else {
        return '${meters.round()} meters';
      }
    }
  }

  /// Announce arrival at destination
  Future<void> announceArrival() async {
    _clearAnnouncements(); // Clear old announcements
    
    final language = _voiceService.currentLanguage;
    final announcement = language.startsWith('fil')
        ? 'Nandito na kayo sa inyong destinasyon'
        : 'You have arrived at your destination';
    
    await _voiceService.speak(announcement, priority: true);
  }

  /// Announce navigation start
  Future<void> announceNavigationStart(double totalDistance) async {
    final language = _voiceService.currentLanguage;
    final distanceText = _formatDistance(totalDistance, language);
    
    final announcement = language.startsWith('fil')
        ? 'Nagsisimula ang navigation. Kabuuang distansya: $distanceText'
        : 'Navigation started. Total distance: $distanceText';
    
    await _voiceService.speak(announcement, priority: true);
  }

  /// Announce recalculating route
  Future<void> announceRecalculating() async {
    final language = _voiceService.currentLanguage;
    final announcement = language.startsWith('fil')
        ? 'Muling kinakalkula ang ruta'
        : 'Recalculating route';
    
    await _voiceService.speak(announcement, priority: true);
  }

  /// Clear all announcement history (useful when starting new navigation)
  void _clearAnnouncements() {
    _announcedInstructions.clear();
    developer.log('Cleared announcement history', 
      name: 'NavigationAnnouncementManager');
  }

  /// Reset the announcement manager (e.g., when navigation ends)
  Future<void> reset() async {
    _clearAnnouncements();
    await _voiceService.stop();
  }

  /// Enable/disable voice guidance
  Future<void> setEnabled(bool enabled) async {
    await _voiceService.setEnabled(enabled);
  }

  /// Set language
  Future<void> setLanguage(String languageCode) async {
    await _voiceService.setLanguage(languageCode);
    _clearAnnouncements(); // Clear history when language changes
  }

  /// Test voice guidance
  Future<void> testVoice() async {
    await _voiceService.testVoice();
  }

  // Getters
  bool get isEnabled => _voiceService.isEnabled;
  String get currentLanguage => _voiceService.currentLanguage;
}
