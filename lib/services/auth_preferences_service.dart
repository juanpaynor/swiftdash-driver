import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthPreferencesService {
  static const String _rememberMeKey = 'remember_me';
  static const String _savedEmailKey = 'saved_email';
  static const String _autoLoginKey = 'auto_login';
  
  // Save login credentials (remember me)
  Future<void> saveLoginPreferences({
    required String email,
    required bool rememberMe,
    bool autoLogin = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    
    await prefs.setBool(_rememberMeKey, rememberMe);
    await prefs.setBool(_autoLoginKey, autoLogin);
    
    if (rememberMe) {
      await prefs.setString(_savedEmailKey, email);
    } else {
      await prefs.remove(_savedEmailKey);
    }
  }
  
  // Get saved login preferences
  Future<Map<String, dynamic>> getLoginPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    
    return {
      'rememberMe': prefs.getBool(_rememberMeKey) ?? false,
      'savedEmail': prefs.getString(_savedEmailKey) ?? '',
      'autoLogin': prefs.getBool(_autoLoginKey) ?? false,
    };
  }
  
  // Clear saved credentials
  Future<void> clearLoginPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    
    await prefs.remove(_rememberMeKey);
    await prefs.remove(_savedEmailKey);
    await prefs.remove(_autoLoginKey);
  }
  
  // Enable auto-login after successful manual login
  Future<void> enableAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoLoginKey, true);
  }
  
  // Disable auto-login (on logout)
  Future<void> disableAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoLoginKey, false);
  }
  
  // Check if should attempt auto-login
  Future<bool> shouldAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final autoLogin = prefs.getBool(_autoLoginKey) ?? false;
    final hasSession = Supabase.instance.client.auth.currentSession != null;
    
    return autoLogin && hasSession;
  }
}