import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/driver.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;
  
  // Get current user
  User? get currentUser => _supabase.auth.currentUser;
  
  // Check if user is logged in
  bool get isLoggedIn => currentUser != null;
  
  // Listen to auth state changes
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;
  
  // Sign in with email and password
  Future<AuthResponse> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      
      // After successful login, verify this is a driver account
      if (response.user != null) {
        final isDriver = await _verifyDriverAccount(response.user!.id);
        if (!isDriver) {
          // Sign out the user if they're not a driver
          await _supabase.auth.signOut();
          throw Exception('This account is not registered as a driver. Please use the customer app or contact support.');
        }
      }
      
      return response;
    } catch (e) {
      rethrow;
    }
  }
  
  // Verify if the user is a driver
  Future<bool> _verifyDriverAccount(String userId) async {
    try {
      final response = await _supabase
          .from('user_profiles')
          .select('user_type')
          .eq('id', userId)
          .maybeSingle();
      
      if (response == null) {
        return false;
      }
      
      return response['user_type'] == 'driver';
    } catch (e) {
      return false;
    }
  }
  
  // Sign up new driver
  Future<AuthResponse> signUpDriver({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String phoneNumber,
    String? vehicleTypeId,
    String? licenseNumber,
    String? vehicleModel,
  }) async {
    try {
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'first_name': firstName,
          'last_name': lastName,
          'phone_number': phoneNumber,
          'user_type': 'driver',
        },
      );
      
      // If signup successful, create driver profile
      if (response.user != null) {
        await _createDriverProfile(
          userId: response.user!.id,
          email: email,
          firstName: firstName,
          lastName: lastName,
          phoneNumber: phoneNumber,
          vehicleTypeId: vehicleTypeId,
          licenseNumber: licenseNumber,
          vehicleModel: vehicleModel,
        );
      }
      
      return response;
    } catch (e) {
      rethrow;
    }
  }
  
  // Create driver profile in database
  Future<void> _createDriverProfile({
    required String userId,
    required String email,
    required String firstName,
    required String lastName,
    required String phoneNumber,
    String? vehicleTypeId,
    String? licenseNumber,
    String? vehicleModel,
  }) async {
    try {
      // First create user profile
      print('Creating user profile for: $email');
      await _supabase.from('user_profiles').insert({
        'id': userId,
        'first_name': firstName,
        'last_name': lastName,
        'phone_number': phoneNumber,
        'user_type': 'driver',
        'status': 'active',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
      
      print('User profile created, now creating driver profile');
      
      // Then create driver profile
      final driverProfileData = {
        'id': userId,
        'is_verified': false,
        'is_online': false,
        'rating': 0.00,
        'total_deliveries': 0,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      // Add optional fields if provided
      if (vehicleTypeId != null) {
        driverProfileData['vehicle_type_id'] = vehicleTypeId;
      }
      if (licenseNumber != null) {
        driverProfileData['license_number'] = licenseNumber;
      }
      if (vehicleModel != null) {
        driverProfileData['vehicle_model'] = vehicleModel;
      }

      await _supabase.from('driver_profiles').insert(driverProfileData);
      
      print('Driver profile created successfully');
    } catch (e) {
      print('Error creating driver profile: $e');
      rethrow;
    }
  }
  
  // Check if current user is a driver
  Future<bool> isCurrentUserDriver() async {
    if (!isLoggedIn) return false;
    return await _verifyDriverAccount(currentUser!.id);
  }
  
  // Get current driver profile
  Future<Driver?> getCurrentDriverProfile() async {
    if (!isLoggedIn) return null;
    
    try {
      // Get user profile first
      final userResponse = await _supabase
          .from('user_profiles')
          .select('*')
          .eq('id', currentUser!.id)
          .eq('user_type', 'driver')
          .single();
      
      // Get driver profile separately
      final driverResponse = await _supabase
          .from('driver_profiles')
          .select('*')
          .eq('id', currentUser!.id)
          .single();
      
      // Get the user's email from Supabase Auth
      final email = currentUser!.email ?? '';
      
      // Combine the data from both tables
      final combinedData = Map<String, dynamic>.from({
        'id': userResponse['id'],
        'email': email,
        'first_name': userResponse['first_name'],
        'last_name': userResponse['last_name'],
        'phone_number': userResponse['phone_number'],
        'user_type': userResponse['user_type'],
        'profile_image_url': userResponse['profile_image_url'],
        'status': userResponse['status'],
        'created_at': userResponse['created_at'],
        'updated_at': userResponse['updated_at'],
        'vehicle_type_id': driverResponse['vehicle_type_id'],
        'license_number': driverResponse['license_number'],
        'vehicle_model': driverResponse['vehicle_model'],
        'is_verified': driverResponse['is_verified'],
        'is_online': driverResponse['is_online'],
        'current_latitude': driverResponse['current_latitude'],
        'current_longitude': driverResponse['current_longitude'],
        'rating': driverResponse['rating'],
        'total_deliveries': driverResponse['total_deliveries'],
      });
      
      return Driver.fromJson(combinedData);
    } catch (e) {
      print('Error getting driver profile: $e');
      return null;
    }
  }
  
  // Update driver online status
  Future<void> updateOnlineStatus(bool isOnline) async {
    if (!isLoggedIn) return;
    
    final driverId = currentUser!.id;
    
    try {
      // First verify this is actually a driver account
      final isDriver = await _verifyDriverAccount(driverId);
      if (!isDriver) {
        throw Exception('Cannot update driver status: Current user is not a driver. Please log in with a driver account.');
      }
      
      // Check if driver profile exists
      final driverProfile = await _supabase
          .from('driver_profiles')
          .select('id')
          .eq('id', driverId)
          .maybeSingle();
      
      if (driverProfile == null) {
        throw Exception('Driver profile not found. Please complete driver registration first.');
      }
      
      // Update driver_profiles table
      await _supabase
          .from('driver_profiles')
          .update({
            'is_online': isOnline,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', driverId);
      
      // Also update driver_current_status table for realtime tracking
      await _supabase.from('driver_current_status').upsert({
        'driver_id': driverId,
        'status': isOnline ? 'available' : 'offline',
        'last_updated': DateTime.now().toIso8601String(),
      });
      
      print('📱 Updated driver online status in both tables: $isOnline');
    } catch (e) {
      print('❌ Error updating driver online status: $e');
      rethrow;
    }
  }
  
  // Sign out
  Future<void> signOut() async {
    try {
      // Only try to set offline status if user is actually a driver
      if (isLoggedIn) {
        final isDriver = await _verifyDriverAccount(currentUser!.id);
        if (isDriver) {
          try {
            await updateOnlineStatus(false);
            print('📱 Driver set to offline before sign out');
          } catch (e) {
            print('⚠️ Could not set driver offline (non-critical): $e');
            // Continue with sign out even if this fails
          }
        } else {
          print('📱 Customer user signing out (no driver status to update)');
        }
      }
      
      await _supabase.auth.signOut();
      print('✅ User signed out successfully');
    } catch (e) {
      print('❌ Error during sign out: $e');
      // Force sign out even if there were errors
      try {
        await _supabase.auth.signOut();
      } catch (e2) {
        print('❌ Force sign out also failed: $e2');
      }
    }
  }

  // Force sign out (emergency method - bypasses all checks)
  Future<void> forceSignOut() async {
    try {
      await _supabase.auth.signOut();
      print('✅ Force sign out successful');
    } catch (e) {
      print('❌ Force sign out failed: $e');
      rethrow;
    }
  }
  
  // Reset password
  Future<void> resetPassword(String email) async {
    await _supabase.auth.resetPasswordForEmail(email);
  }
}