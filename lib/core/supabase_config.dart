import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class SupabaseConfig {
  // 🔒 SECURITY: Read from .env file, never hardcode credentials!
  static String get supabaseUrl {
    final url = dotenv.env['SUPABASE_URL'];
    if (url == null || url.isEmpty) {
      throw Exception('⚠️ SUPABASE_URL not found in .env file');
    }
    return url;
  }
  
  static String get supabaseAnonKey {
    final key = dotenv.env['SUPABASE_ANON_KEY'];
    if (key == null || key.isEmpty) {
      throw Exception('⚠️ SUPABASE_ANON_KEY not found in .env file');
    }
    return key;
  }
}

// SwiftDash Brand Colors
class SwiftDashColors {
  static const Color darkBlue = Color(0xFF2E4A9B);
  static const Color lightBlue = Color(0xFF1DA1F2);
  static const Color white = Color(0xFFFFFFFF);
  static const Color backgroundGrey = Color(0xFFF8F9FA);
  static const Color textGrey = Color(0xFF6C757D);
  static const Color successGreen = Color(0xFF28A745);
  static const Color warningOrange = Color(0xFFFFC107);
  static const Color dangerRed = Color(0xFFDC3545);
}