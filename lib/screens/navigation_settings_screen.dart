import 'package:flutter/material.dart';
import '../core/colors.dart';
import '../services/navigation_service.dart';
import '../services/voice_guidance_service.dart';

/// Navigation settings screen for customizing voice guidance and navigation preferences
class NavigationSettingsScreen extends StatefulWidget {
  const NavigationSettingsScreen({super.key});

  @override
  State<NavigationSettingsScreen> createState() => _NavigationSettingsScreenState();
}

class _NavigationSettingsScreenState extends State<NavigationSettingsScreen> {
  final NavigationService _navService = NavigationService.instance;
  final VoiceGuidanceService _voiceService = VoiceGuidanceService();
  
  bool _isVoiceEnabled = true;
  bool _isBackgroundNavEnabled = true;
  String _selectedLanguage = 'en-US';
  double _speechRate = 0.5;
  bool _isTestingVoice = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    await _voiceService.initialize();
    setState(() {
      _isVoiceEnabled = _navService.isVoiceGuidanceEnabled;
      _isBackgroundNavEnabled = _navService.isBackgroundNavigationEnabled;
      _selectedLanguage = _navService.voiceGuidanceLanguage;
      _speechRate = _voiceService.speechRate;
    });
  }

  Future<void> _toggleVoiceGuidance(bool value) async {
    await _navService.setVoiceGuidanceEnabled(value);
    setState(() {
      _isVoiceEnabled = value;
    });
  }

  Future<void> _toggleBackgroundNavigation(bool value) async {
    await _navService.setBackgroundNavigationEnabled(value);
    setState(() {
      _isBackgroundNavEnabled = value;
    });
  }

  Future<void> _changeLanguage(String? languageCode) async {
    if (languageCode == null) return;
    await _navService.setVoiceGuidanceLanguage(languageCode);
    setState(() {
      _selectedLanguage = languageCode;
    });
  }

  Future<void> _changeSpeechRate(double rate) async {
    await _voiceService.setSpeechRate(rate);
    setState(() {
      _speechRate = rate;
    });
  }

  Future<void> _testVoice() async {
    setState(() {
      _isTestingVoice = true;
    });
    
    await _navService.testVoiceGuidance();
    
    // Wait a bit for the voice to finish
    await Future.delayed(const Duration(seconds: 3));
    
    if (mounted) {
      setState(() {
        _isTestingVoice = false;
      });
    }
  }

  String _getSpeechRateLabel(double rate) {
    if (rate < 0.4) return 'Very Slow';
    if (rate < 0.5) return 'Slow';
    if (rate < 0.6) return 'Normal';
    if (rate < 0.8) return 'Fast';
    return 'Very Fast';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SwiftDashColors.backgroundLight,
      appBar: AppBar(
        title: const Text(
          'Navigation Settings',
          style: TextStyle(
            color: SwiftDashColors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: SwiftDashColors.lightBlue,
        iconTheme: const IconThemeData(color: SwiftDashColors.white),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Voice Guidance Section
          _buildSectionHeader('Voice Guidance'),
          _buildSettingsCard(
            children: [
              SwitchListTile(
                title: const Text(
                  'Voice Instructions',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 16,
                  ),
                ),
                subtitle: const Text(
                  'Turn-by-turn voice announcements',
                  style: TextStyle(color: SwiftDashColors.mediumGray),
                ),
                value: _isVoiceEnabled,
                activeColor: SwiftDashColors.successGreen,
                onChanged: _toggleVoiceGuidance,
              ),
              
              const Divider(height: 1),
              
              // Language Selection
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Language',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: SwiftDashColors.lightGray),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedLanguage,
                          isExpanded: true,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          items: VoiceGuidanceService.supportedLanguages.entries.map((entry) {
                            return DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            );
                          }).toList(),
                          onChanged: _isVoiceEnabled ? _changeLanguage : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              const Divider(height: 1),
              
              // Speech Rate Slider
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Speech Speed',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          _getSpeechRateLabel(_speechRate),
                          style: TextStyle(
                            color: SwiftDashColors.lightBlue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.speed, color: SwiftDashColors.mediumGray, size: 20),
                        Expanded(
                          child: Slider(
                            value: _speechRate,
                            min: 0.3,
                            max: 1.0,
                            divisions: 14,
                            activeColor: SwiftDashColors.lightBlue,
                            inactiveColor: SwiftDashColors.lightGray,
                            onChanged: _isVoiceEnabled ? _changeSpeechRate : null,
                          ),
                        ),
                        const Icon(Icons.speed, color: SwiftDashColors.lightBlue, size: 24),
                      ],
                    ),
                  ],
                ),
              ),
              
              const Divider(height: 1),
              
              // Test Voice Button
              Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton.icon(
                  onPressed: _isVoiceEnabled && !_isTestingVoice ? _testVoice : null,
                  icon: _isTestingVoice
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: SwiftDashColors.white,
                          ),
                        )
                      : const Icon(Icons.volume_up),
                  label: Text(_isTestingVoice ? 'Testing...' : 'Test Voice'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SwiftDashColors.lightBlue,
                    foregroundColor: SwiftDashColors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Background Navigation Section
          _buildSectionHeader('Background Navigation'),
          _buildSettingsCard(
            children: [
              SwitchListTile(
                title: const Text(
                  'Keep Navigation Active',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 16,
                  ),
                ),
                subtitle: const Text(
                  'Continue navigation when app is minimized',
                  style: TextStyle(color: SwiftDashColors.mediumGray),
                ),
                value: _isBackgroundNavEnabled,
                activeColor: SwiftDashColors.successGreen,
                onChanged: _toggleBackgroundNavigation,
              ),
              
              if (_isBackgroundNavEnabled)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: SwiftDashColors.lightBlue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: SwiftDashColors.lightBlue.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: SwiftDashColors.lightBlue,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'GPS and voice guidance will continue in the background. A notification will show navigation progress.',
                            style: TextStyle(
                              color: SwiftDashColors.darkBlue,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Info Section
          _buildSectionHeader('About'),
          _buildSettingsCard(
            children: [
              _buildInfoTile(
                icon: Icons.info_outline,
                title: 'Navigation Data',
                subtitle: 'Powered by Mapbox Directions API',
              ),
              const Divider(height: 1),
              _buildInfoTile(
                icon: Icons.cloud_off_outlined,
                title: 'Offline Voice',
                subtitle: 'Voice guidance works without internet',
              ),
              const Divider(height: 1),
              _buildInfoTile(
                icon: Icons.battery_charging_full_outlined,
                title: 'Battery Efficient',
                subtitle: 'Optimized for minimal battery usage',
              ),
            ],
          ),
          
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: SwiftDashColors.mediumGray,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSettingsCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: SwiftDashColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return ListTile(
      leading: Icon(icon, color: SwiftDashColors.lightBlue),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 15,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          color: SwiftDashColors.mediumGray,
          fontSize: 13,
        ),
      ),
    );
  }
}
