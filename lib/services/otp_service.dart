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
      // Format phone number to E.164 format
      final formattedPhone = _formatPhoneNumber(phoneNumber);
      
      // Validate E.164 format before sending
      if (!isValidPhoneNumber(phoneNumber)) {
        print('❌ Invalid phone number format: $phoneNumber → $formattedPhone');
        return OTPResult(
          success: false,
          message: 'Invalid phone number format. Must be a valid Philippine mobile number.',
        );
      }
      
      print('📱 Sending OTP to E.164 formatted number: $formattedPhone');
      print('   Original input: $phoneNumber');
      
      // Use Supabase Auth's built-in phone OTP (uses Twilio behind the scenes)
      await _supabase.auth.signInWithOtp(
        phone: formattedPhone,
      );

      print('✅ OTP sent successfully via Supabase Auth');

      return OTPResult(
        success: true,
        message: 'OTP sent successfully to $formattedPhone',
      );
    } catch (e) {
      print('❌ Error sending OTP: $e');
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
      // Format phone number to E.164 format (must match the number OTP was sent to)
      final formattedPhone = _formatPhoneNumber(phoneNumber);
      
      print('🔍 Verifying OTP for E.164 number: $formattedPhone');
      print('   Code: $code');
      
      // Use Supabase Auth's verifyOtp
      final response = await _supabase.auth.verifyOTP(
        phone: formattedPhone,
        token: code,
        type: OtpType.sms,
      );

      print('✅ Verification Response: ${response.session != null ? "Success" : "Failed"}');

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
      print('❌ Error verifying OTP: $e');
      return OTPResult(
        success: false,
        message: 'Error verifying OTP: ${e.toString()}',
      );
    }
  }

  /// Format phone number to E.164 international format for Twilio/Supabase
  /// Ensures proper +63 prefix for Philippines
  /// E.164 format: +[country code][subscriber number] (no spaces, dashes, parentheses)
  String _formatPhoneNumber(String phoneNumber) {
    // Remove ALL non-digit characters except leading +
    String cleaned = phoneNumber.trim();
    
    // Extract only digits
    String digitsOnly = cleaned.replaceAll(RegExp(r'[^\d]'), '');
    
    // Handle different input formats:
    // 09171234567 → +639171234567
    // 9171234567 → +639171234567
    // 639171234567 → +639171234567
    // +639171234567 → +639171234567 (already correct)
    
    if (cleaned.startsWith('+63')) {
      // Already has +63, just clean it
      return '+63${digitsOnly.substring(2)}';
    } else if (digitsOnly.startsWith('63')) {
      // Has 63 but no +
      return '+${digitsOnly}';
    } else if (digitsOnly.startsWith('0')) {
      // Starts with 0 (local format)
      return '+63${digitsOnly.substring(1)}';
    } else {
      // No country code at all
      return '+63${digitsOnly}';
    }
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
