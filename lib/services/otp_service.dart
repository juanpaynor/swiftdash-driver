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
      
      // Provide specific error messages based on error type
      String errorMessage = 'Failed to send OTP';
      
      if (e is AuthException) {
        if (e.message.contains('Phone provider is disabled') || 
            e.message.contains('not enabled')) {
          errorMessage = 'Phone authentication is not configured. Please contact support.';
          print('🚨 CRITICAL: Phone provider not enabled in Supabase dashboard!');
          print('   Go to: https://supabase.com/dashboard → Auth → Providers → Enable Phone');
        } else if (e.message.contains('Invalid phone number')) {
          errorMessage = 'Invalid phone number format. Use format: 09171234567';
        } else if (e.message.contains('Twilio')) {
          errorMessage = 'SMS service configuration error. Please contact support.';
          print('🚨 CRITICAL: Twilio credentials not configured in Supabase!');
        } else {
          errorMessage = e.message;
        }
      } else if (e.toString().contains('NetworkException')) {
        errorMessage = 'Network error. Please check your internet connection.';
      }
      
      return OTPResult(
        success: false,
        message: errorMessage,
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
      
      // Provide specific error messages
      String errorMessage = 'Failed to verify OTP';
      
      if (e is AuthException) {
        if (e.message.contains('Invalid token') || 
            e.message.contains('invalid') || 
            e.message.contains('expired')) {
          errorMessage = 'Invalid or expired OTP code. Please try again.';
        } else if (e.message.contains('Token has expired')) {
          errorMessage = 'OTP code has expired. Please request a new code.';
        } else {
          errorMessage = e.message;
        }
      } else if (e.toString().contains('NetworkException')) {
        errorMessage = 'Network error. Please check your internet connection.';
      }
      
      return OTPResult(
        success: false,
        message: errorMessage,
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
    
    // Philippine mobile numbers: +63 followed by 10 digits starting with 9
    // Examples: +639171234567, +639281234567, +639051234567
    final isMobile = RegExp(r'^\+639\d{9}$').hasMatch(formatted);
    
    // Philippine landlines: +63 2 followed by 7-8 digits (Metro Manila)
    // or +63 followed by area code and local number
    final isLandline = RegExp(r'^\+632\d{7,8}$').hasMatch(formatted);
    
    return isMobile || isLandline;
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
