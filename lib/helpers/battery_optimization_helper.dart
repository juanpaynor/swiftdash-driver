import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io' show Platform;

/// Helper widget to request battery optimization exemption
/// CRITICAL: Without this, Android will kill the background service after 30-60 minutes
class BatteryOptimizationHelper {
  // Track if we've already shown the dialog this session
  static bool _hasShownDialogThisSession = false;
  
  /// Check if battery optimization is disabled
  static Future<bool> isBatteryOptimizationDisabled() async {
    if (!Platform.isAndroid) return true;
    
    try {
      return await Permission.ignoreBatteryOptimizations.isGranted;
    } catch (e) {
      debugPrint('Error checking battery optimization: $e');
      return false;
    }
  }

  /// Request battery optimization exemption
  static Future<bool> requestBatteryOptimizationExemption(BuildContext context) async {
    if (!Platform.isAndroid) return true;

    try {
      // Check current status
      final status = await Permission.ignoreBatteryOptimizations.status;
      
      if (status.isGranted) {
        debugPrint('✅ Battery optimization already disabled');
        return true;
      }

      // Only show dialog once per session to avoid being annoying
      if (_hasShownDialogThisSession) {
        debugPrint('⏭️ Already shown battery optimization dialog this session - skipping');
        return false;
      }
      _hasShownDialogThisSession = true;

      // Show explanation dialog first
      final shouldRequest = await showDialog<bool>(
        context: context,
        barrierDismissible: true,  // Allow dismissing by tapping outside
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.battery_alert, color: Colors.orange, size: 32),
              SizedBox(width: 12),
              Expanded(child: Text('Battery Optimization')),
            ],
          ),
          content: const SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'To receive delivery offers while your phone is idle, we need to disable battery optimization.',
                  style: TextStyle(fontSize: 16),
                ),
                SizedBox(height: 16),
                Text(
                  '⚠️ Without this:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                SizedBox(height: 8),
                Text('• You won\'t receive offers after 30-60 minutes'),
                Text('• Background service will be killed by Android'),
                Text('• You may miss delivery opportunities'),
                SizedBox(height: 16),
                Text(
                  '✅ With this enabled:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                SizedBox(height: 8),
                Text('• Instant delivery offer notifications 24/7'),
                Text('• Service stays alive even when idle'),
                Text('• You\'ll never miss an opportunity'),
                SizedBox(height: 16),
                Text(
                  'Battery impact: ~2-3% per hour (minimal)',
                  style: TextStyle(fontStyle: FontStyle.italic, fontSize: 14),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Skip for Now'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('Enable'),
            ),
          ],
        ),
      );

      if (shouldRequest != true) {
        debugPrint('⚠️ User skipped battery optimization request');
        return false;
      }

      // Request permission
      final result = await Permission.ignoreBatteryOptimizations.request();
      
      if (result.isGranted) {
        debugPrint('✅ Battery optimization disabled successfully');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Battery optimization disabled - you\'ll receive offers 24/7!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        }
        return true;
      } else {
        debugPrint('❌ Battery optimization request denied');
        if (context.mounted) {
          _showManualInstructions(context);
        }
        return false;
      }
    } catch (e) {
      debugPrint('❌ Error requesting battery optimization exemption: $e');
      return false;
    }
  }

  /// Show manual instructions for manufacturers with custom battery settings
  static void _showManualInstructions(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Manual Setup Required'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your phone manufacturer requires manual setup:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 16),
              Text('📱 Xiaomi/MIUI:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Settings → Apps → SwiftDash Driver → Battery saver → No restrictions'),
              Text('Settings → Apps → SwiftDash Driver → Autostart → Enable'),
              SizedBox(height: 12),
              Text('📱 Oppo/ColorOS:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Settings → Battery → App Battery Management → SwiftDash Driver → Don\'t optimize'),
              SizedBox(height: 12),
              Text('📱 Huawei/EMUI:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Settings → Battery → App launch → SwiftDash Driver → Manage manually (enable all)'),
              SizedBox(height: 12),
              Text('📱 Samsung:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Settings → Apps → SwiftDash Driver → Battery → Allow background activity'),
              SizedBox(height: 16),
              Text(
                '⚠️ Without these settings, you may not receive offers after your phone is idle for 30 minutes.',
                style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('I\'ll Set It Up Later'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Open app settings
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  /// Show warning if battery optimization is still enabled
  static Future<void> showBatteryOptimizationWarning(BuildContext context) async {
    final isDisabled = await isBatteryOptimizationDisabled();
    
    if (!isDisabled) {
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.red, size: 32),
                SizedBox(width: 12),
                Text('Warning'),
              ],
            ),
            content: const Text(
              'Battery optimization is still enabled. You may not receive delivery offers when your phone is idle.\n\n'
              'Please disable battery optimization in Settings to ensure you receive all offers.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Remind Me Later'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  requestBatteryOptimizationExemption(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Fix Now'),
              ),
            ],
          ),
        );
      }
    }
  }

  /// Check and request on driver going online
  static Future<bool> checkAndRequestOnGoingOnline(BuildContext context) async {
    final isDisabled = await isBatteryOptimizationDisabled();
    
    if (!isDisabled) {
      return await requestBatteryOptimizationExemption(context);
    }
    
    return true;
  }
}
