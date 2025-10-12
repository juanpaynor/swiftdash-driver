import 'dart:io' show Platform;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class DeviceCompatibilityService {
  static DeviceCompatibilityService? _instance;
  static DeviceCompatibilityService get instance => _instance ??= DeviceCompatibilityService._();
  DeviceCompatibilityService._();
  
  bool _isBackgroundServiceSupported = true;
  String _deviceInfo = '';
  
  bool get isBackgroundServiceSupported => _isBackgroundServiceSupported;
  String get deviceInfo => _deviceInfo;

  /// Check device compatibility for background services
  Future<bool> checkDeviceCompatibility() async {
    try {
      if (!Platform.isAndroid) {
        _isBackgroundServiceSupported = true; // iOS handles differently
        return true;
      }

      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      
      _deviceInfo = '${androidInfo.brand} ${androidInfo.model} (API ${androidInfo.version.sdkInt})';
      print('📱 Device: $_deviceInfo');
      
      // Check Android API level
      final apiLevel = androidInfo.version.sdkInt;
      
      // Android 14+ (API 34+) has stricter background service restrictions
      if (apiLevel >= 34) {
        print('⚠️ Android 14+ detected - stricter background service restrictions');
        return await _checkAndroid14Compatibility();
      }
      
      // Android 12+ (API 31+) has battery optimization restrictions
      if (apiLevel >= 31) {
        print('⚠️ Android 12+ detected - checking battery optimization');
        return await _checkBatteryOptimization();
      }
      
      // Check for known problematic manufacturers
      final brand = androidInfo.brand.toLowerCase();
      if (_isProblematicManufacturer(brand)) {
        print('⚠️ Potentially problematic manufacturer: $brand');
        return await _checkManufacturerSpecificIssues(brand);
      }
      
      _isBackgroundServiceSupported = true;
      return true;
      
    } catch (e) {
      print('❌ Error checking device compatibility: $e');
      _isBackgroundServiceSupported = false;
      return false;
    }
  }
  
  /// Check Android 14+ specific compatibility
  Future<bool> _checkAndroid14Compatibility() async {
    try {
      // Check if we have the required permissions for Android 14+
      final permissions = [
        Permission.location,
        Permission.locationWhenInUse,
        Permission.notification,
      ];
      
      for (final permission in permissions) {
        final status = await permission.status;
        if (status.isDenied) {
          print('⚠️ Missing required permission: $permission');
          _isBackgroundServiceSupported = false;
          return false;
        }
      }
      
      // Android 14+ requires explicit user consent for background location
      final backgroundLocationStatus = await Permission.locationAlways.status;
      if (backgroundLocationStatus.isDenied) {
        print('⚠️ Background location permission required for Android 14+');
      }
      
      _isBackgroundServiceSupported = true;
      return true;
      
    } catch (e) {
      print('❌ Android 14+ compatibility check failed: $e');
      _isBackgroundServiceSupported = false;
      return false;
    }
  }
  
  /// Check battery optimization settings
  Future<bool> _checkBatteryOptimization() async {
    try {
      // We can't directly check battery optimization status without additional plugins
      // But we can assume it might be an issue and provide fallback
      print('⚠️ Battery optimization may affect background services');
      _isBackgroundServiceSupported = true; // Assume it works, fallback if needed
      return true;
      
    } catch (e) {
      print('❌ Battery optimization check failed: $e');
      _isBackgroundServiceSupported = false;
      return false;
    }
  }
  
  /// Check for manufacturer-specific issues
  Future<bool> _checkManufacturerSpecificIssues(String brand) async {
    switch (brand) {
      case 'xiaomi':
      case 'redmi':
        print('⚠️ Xiaomi/Redmi device - may have MIUI restrictions');
        break;
      case 'huawei':
      case 'honor':
        print('⚠️ Huawei/Honor device - may have EMUI restrictions');
        break;
      case 'oppo':
      case 'realme':
        print('⚠️ OPPO/Realme device - may have ColorOS restrictions');
        break;
      case 'vivo':
        print('⚠️ Vivo device - may have FuntouchOS restrictions');
        break;
      case 'samsung':
        print('⚠️ Samsung device - may have battery optimization');
        break;
    }
    
    // For now, assume compatibility but log warnings
    _isBackgroundServiceSupported = true;
    return true;
  }
  
  /// Check if manufacturer is known to have background service issues
  bool _isProblematicManufacturer(String brand) {
    const problematicBrands = [
      'xiaomi', 'redmi', 'huawei', 'honor', 
      'oppo', 'realme', 'vivo', 'samsung'
    ];
    return problematicBrands.contains(brand);
  }
  
  /// Get fallback location strategy for incompatible devices
  String getFallbackStrategy() {
    if (!_isBackgroundServiceSupported) {
      return 'foreground_only';
    }
    return 'background_supported';
  }
  
  /// Show device compatibility warning dialog
  Future<void> showCompatibilityWarning(BuildContext context) async {
    if (_isBackgroundServiceSupported) return;
    
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Device Compatibility Notice'),
        content: Text(
          'Your device ($_deviceInfo) may have restrictions that limit background location tracking. '
          'The app will work but location updates may be less frequent when minimized.\n\n'
          'For best performance:\n'
          '• Keep the app open during deliveries\n'
          '• Disable battery optimization for SwiftDash\n'
          '• Allow all location permissions',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}