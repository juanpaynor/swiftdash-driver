import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import '../services/background_location_service.dart';
import '../core/supabase_config.dart';

class BatteryOptimizationScreen extends StatefulWidget {
  const BatteryOptimizationScreen({super.key});

  @override
  State<BatteryOptimizationScreen> createState() => _BatteryOptimizationScreenState();
}

class _BatteryOptimizationScreenState extends State<BatteryOptimizationScreen> {
  String _deviceBrand = '';
  bool _isLoading = true;
  bool _isServiceRunning = false;

  @override
  void initState() {
    super.initState();
    _initializeScreen();
  }

  Future<void> _initializeScreen() async {
    await _getDeviceInfo();
    await _checkServiceStatus();
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _getDeviceInfo() async {
    try {
      if (Platform.isAndroid) {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        setState(() {
          _deviceBrand = androidInfo.brand.toLowerCase();
        });
      }
    } catch (e) {
      print('Error getting device info: $e');
      setState(() {
        _deviceBrand = 'android';
      });
    }
  }

  Future<void> _checkServiceStatus() async {
    try {
      final isRunning = await BackgroundLocationService.isServiceRunning();
      setState(() {
        _isServiceRunning = isRunning;
      });
    } catch (e) {
      setState(() {
        _isServiceRunning = false;
      });
    }
  }

  Future<void> _initializeBackgroundService() async {
    try {
      await BackgroundLocationService.initializeService();
      await _checkServiceStatus();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Background service initialized successfully! It will start automatically when you go online.'),
            backgroundColor: SwiftDashColors.successGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to initialize background service: $e'),
            backgroundColor: SwiftDashColors.dangerRed,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Background Tracking Setup'),
          backgroundColor: SwiftDashColors.darkBlue,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Background Tracking Setup'),
        backgroundColor: SwiftDashColors.darkBlue,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Service Status Card
            _buildServiceStatusCard(),
            const SizedBox(height: 20),
            
            // Why This Matters Section
            _buildImportanceSection(),
            const SizedBox(height: 20),
            
            // Device-Specific Instructions
            _buildDeviceInstructions(),
            const SizedBox(height: 20),
            
            // General Android Instructions
            _buildGeneralInstructions(),
            const SizedBox(height: 20),
            
            // Action Buttons
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceStatusCard() {
    return Card(
      color: _isServiceRunning 
        ? SwiftDashColors.successGreen.withOpacity(0.1)
        : SwiftDashColors.warningOrange.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              _isServiceRunning ? Icons.check_circle : Icons.warning,
              color: _isServiceRunning 
                ? SwiftDashColors.successGreen 
                : SwiftDashColors.warningOrange,
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isServiceRunning 
                      ? 'Background Service Active ✅'
                      : 'Background Service Inactive ⚠️',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _isServiceRunning 
                        ? SwiftDashColors.successGreen 
                        : SwiftDashColors.warningOrange,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isServiceRunning
                      ? 'Your location will be tracked reliably during deliveries'
                      : 'Enable background tracking for reliable delivery service',
                    style: TextStyle(
                      fontSize: 14,
                      color: SwiftDashColors.textGrey,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImportanceSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info, color: SwiftDashColors.lightBlue),
                const SizedBox(width: 8),
                const Text(
                  'Why Background Tracking Matters',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildBulletPoint('📍', 'Customers can track your real-time location'),
            _buildBulletPoint('🚗', 'Delivery tracking continues when phone is locked'),
            _buildBulletPoint('⚡', 'Prevents app from being killed by battery optimization'),
            _buildBulletPoint('💼', 'Essential for professional delivery service'),
            _buildBulletPoint('⭐', 'Improves customer satisfaction and ratings'),
          ],
        ),
      ),
    );
  }

  Widget _buildBulletPoint(String emoji, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: SwiftDashColors.textGrey,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceInstructions() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.phone_android, color: SwiftDashColors.lightBlue),
                const SizedBox(width: 8),
                Text(
                  '${_deviceBrand.toUpperCase()} Device Instructions',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._getDeviceSpecificInstructions(),
          ],
        ),
      ),
    );
  }

  List<Widget> _getDeviceSpecificInstructions() {
    switch (_deviceBrand) {
      case 'samsung':
        return [
          _buildInstructionStep('1', 'Go to Settings > Apps > SwiftDash Driver'),
          _buildInstructionStep('2', 'Tap "Battery" > "Allow background activity"'),
          _buildInstructionStep('3', 'Enable "Auto-start" if available'),
          _buildInstructionStep('4', 'Go to Settings > Device care > Battery'),
          _buildInstructionStep('5', 'Tap "App power management" > "Apps that won\'t be put to sleep"'),
          _buildInstructionStep('6', 'Add "SwiftDash Driver" to the list'),
        ];
      case 'huawei':
      case 'honor':
        return [
          _buildInstructionStep('1', 'Go to Settings > Apps > SwiftDash Driver'),
          _buildInstructionStep('2', 'Enable "Auto-launch" and "Secondary launch"'),
          _buildInstructionStep('3', 'Go to Settings > Battery > App launch'),
          _buildInstructionStep('4', 'Find SwiftDash Driver and set to "Manual"'),
          _buildInstructionStep('5', 'Enable "Auto-launch", "Secondary launch", "Run in background"'),
        ];
      case 'xiaomi':
      case 'redmi':
        return [
          _buildInstructionStep('1', 'Go to Settings > Apps > Manage apps > SwiftDash Driver'),
          _buildInstructionStep('2', 'Enable "Autostart"'),
          _buildInstructionStep('3', 'Go to Settings > Battery & performance > App battery saver'),
          _buildInstructionStep('4', 'Find SwiftDash Driver and set to "No restrictions"'),
          _buildInstructionStep('5', 'Lock the app in recent apps (tap the lock icon)'),
        ];
      case 'oppo':
      case 'oneplus':
        return [
          _buildInstructionStep('1', 'Go to Settings > Apps & notifications > SwiftDash Driver'),
          _buildInstructionStep('2', 'Enable "Allow background activity"'),
          _buildInstructionStep('3', 'Go to Settings > Battery > Battery optimization'),
          _buildInstructionStep('4', 'Find SwiftDash Driver and select "Don\'t optimize"'),
          _buildInstructionStep('5', 'Enable "Auto-start" in startup manager'),
        ];
      case 'vivo':
        return [
          _buildInstructionStep('1', 'Go to Settings > Apps & permissions > SwiftDash Driver'),
          _buildInstructionStep('2', 'Enable "Auto-start" and "Background app refresh"'),
          _buildInstructionStep('3', 'Go to Settings > Battery > Background app management'),
          _buildInstructionStep('4', 'Set SwiftDash Driver to "Allow high consumption"'),
        ];
      default:
        return [
          _buildInstructionStep('1', 'Go to Settings > Apps > SwiftDash Driver'),
          _buildInstructionStep('2', 'Look for "Battery" or "Battery optimization"'),
          _buildInstructionStep('3', 'Set to "Don\'t optimize" or "Allow background activity"'),
          _buildInstructionStep('4', 'Enable "Auto-start" or "Allow in background" if available'),
        ];
    }
  }

  Widget _buildInstructionStep(String number, String instruction) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: SwiftDashColors.lightBlue,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              instruction,
              style: TextStyle(
                fontSize: 14,
                color: SwiftDashColors.textGrey,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGeneralInstructions() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.settings, color: SwiftDashColors.lightBlue),
                const SizedBox(width: 8),
                const Text(
                  'General Android Settings',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInstructionStep('1', 'Keep SwiftDash Driver in recent apps (don\'t swipe it away)'),
            _buildInstructionStep('2', 'Ensure Location Services are enabled'),
            _buildInstructionStep('3', 'Allow "All the time" location permission when prompted'),
            _buildInstructionStep('4', 'Disable any task killer or cleaner apps'),
            _buildInstructionStep('5', 'Keep your phone charged during long shifts'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: SwiftDashColors.warningOrange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: SwiftDashColors.warningOrange.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning, color: SwiftDashColors.warningOrange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Important: Each phone manufacturer has different settings. If you can\'t find these options, search for "battery optimization" or "background apps" in your Settings.',
                      style: TextStyle(
                        fontSize: 12,
                        color: SwiftDashColors.textGrey,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        // Start Service Button
        if (!_isServiceRunning) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _initializeBackgroundService,
              style: ElevatedButton.styleFrom(
                backgroundColor: SwiftDashColors.successGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Initialize Background Service',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        
        // Open Device Settings Button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _openDeviceSettings,
            style: OutlinedButton.styleFrom(
              foregroundColor: SwiftDashColors.lightBlue,
              side: BorderSide(color: SwiftDashColors.lightBlue),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Open Device Settings',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        
        // Refresh Status Button
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: () async {
              setState(() {
                _isLoading = true;
              });
              await _checkServiceStatus();
              setState(() {
                _isLoading = false;
              });
            },
            child: Text(
              'Refresh Status',
              style: TextStyle(
                fontSize: 14,
                color: SwiftDashColors.textGrey,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openDeviceSettings() async {
    try {
      if (Platform.isAndroid) {
        // Try to open app-specific settings
        const url = 'android-settings:application-details-settings';
        if (await canLaunchUrl(Uri.parse(url))) {
          await launchUrl(Uri.parse(url));
        } else {
          // Fallback to general settings
          const fallbackUrl = 'android-settings:';
          if (await canLaunchUrl(Uri.parse(fallbackUrl))) {
            await launchUrl(Uri.parse(fallbackUrl));
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open settings: $e'),
            backgroundColor: SwiftDashColors.warningOrange,
          ),
        );
      }
    }
  }
}