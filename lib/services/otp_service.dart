import 'package:supabase_flutter/supabase_flutter.dart';

/// Service for handling phone number OTP verification using Supabase Auth
/// Uses Supabase's built-in phone OTP - no external service needed!
class OTPService {
  final _supabase = Supabase.instance.client;

  /// Send OTP code to phone number via Supabase Auth
  /// Returns true if OTP was sent successfully
  /// 
  /// Example:
  /// ```dart
  /// final success = await OTPService().sendOTP('+639171234567');
  /// if (success) {
  ///   // Navigate to OTP verification screen
  /// }
  /// ```
  Future<OTPResult> sendOTP({required String phoneNumber}) async {
    try {
      // Format phone number (ensure +63 prefix for Philippines)
      final formattedPhone = _formatPhoneNumber(phoneNumber);
      
      print('Sending OTP to: $formattedPhone');
      
      // Use Supabase Auth's built-in phone OTP
      await _supabase.auth.signInWithOtp(
        phone: formattedPhone,
      );

      print('OTP sent successfully via Supabase Auth');

      return OTPResult(
        success: true,
        message: 'OTP sent successfully to $formattedPhone',
      );
    } catch (e) {
      print('Error sending OTP: $e');
      return OTPResult(
        success: false,
        message: 'Error sending OTP: ${e.toString()}',
      );
    }
  }

  /// Verify OTP code entered by user
  /// Returns OTPResult with session data if successful
  /// 
  /// Example:
  /// ```dart
  /// final result = await OTPService().verifyOTP(
  ///   phoneNumber: '+639171234567',
  ///   code: '123456',
  /// );
  /// if (result.success) {
  ///   // User is now authenticated
  ///   // Proceed with profile creation
  /// }
  /// ```
  Future<OTPResult> verifyOTP({
    required String phoneNumber,
    required String code,
  }) async {
    try {
      // Format phone number
      final formattedPhone = _formatPhoneNumber(phoneNumber);
      
      print('Verifying OTP for: $formattedPhone with code: $code');
      
      // Use Supabase Auth's verifyOtp
      final response = await _supabase.auth.verifyOTP(
        phone: formattedPhone,
        token: code,
        type: OtpType.sms,
      );

      print('Verification Response: ${response.session != null ? "Success" : "Failed"}');

      if (response.session != null) {
        return OTPResult(
          success: true,
          message: 'Phone number verified successfully',
          session: response.session,
        );
      } else {
        return OTPResult(
          success: false,
          message: 'Invalid OTP code',
        );
      }
    } catch (e) {
      print('Error verifying OTP: $e');
      return OTPResult(
        success: false,
        message: 'Error verifying OTP: ${e.toString()}',
      );
    }
  }

  /// Format phone number to international format
  /// Ensures +63 prefix for Philippines
  String _formatPhoneNumber(String phoneNumber) {
    // Remove all whitespace and special characters
    String cleaned = phoneNumber.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    
    // If starts with 0, replace with +63
    if (cleaned.startsWith('0')) {
      cleaned = '+63${cleaned.substring(1)}';
    }
    
    // If doesn't start with +, add +63
    if (!cleaned.startsWith('+')) {
      cleaned = '+63$cleaned';
    }
    
    return cleaned;
  }

  /// Check if phone number format is valid
  /// Must be 10 digits after country code (e.g., +639171234567)
  bool isValidPhoneNumber(String phoneNumber) {
    final formatted = _formatPhoneNumber(phoneNumber);
    // Philippine mobile numbers: +63 followed by 10 digits (9XXXXXXXXX)
    return RegExp(r'^\+639\d{9}$').hasMatch(formatted);
  }
}

/// Result of OTP operation (send or verify)
class OTPResult {
  final bool success;
  final String message;
  final Session? session; // Contains access token and user data after successful verification

  OTPResult({
    required this.success,
    required this.message,
    this.session,
  });
}
