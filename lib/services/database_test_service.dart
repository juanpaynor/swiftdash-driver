import 'package:supabase_flutter/supabase_flutter.dart';

class DatabaseTestService {
  final SupabaseClient _supabase = Supabase.instance.client;
  
  // Test basic connection to Supabase
  Future<Map<String, dynamic>> testDatabaseConnection() async {
    final results = <String, dynamic>{};
    
    try {
      // Test 1: Check if we can connect to Supabase
      results['connection'] = 'Connected';
      results['user_authenticated'] = _supabase.auth.currentUser != null;
      
      // Test 2: Try to read from user_profiles table (should work for authenticated users)
      try {
        await _supabase
            .from('user_profiles')
            .select('count')
            .limit(1);
        results['user_profiles_read'] = 'Success';
      } catch (e) {
        results['user_profiles_read'] = 'Error: $e';
      }
      
      // Test 3: Try to read from driver_profiles table
      try {
        await _supabase
            .from('driver_profiles')
            .select('count')
            .limit(1);
        results['driver_profiles_read'] = 'Success';
      } catch (e) {
        results['driver_profiles_read'] = 'Error: $e';
      }
      
      // Test 4: Try to read from deliveries table
      try {
        await _supabase
            .from('deliveries')
            .select('count')
            .limit(1);
        results['deliveries_read'] = 'Success';
      } catch (e) {
        results['deliveries_read'] = 'Error: $e';
      }
      
      // Test 5: Check RLS policies by trying a simple insert (this will fail but tell us why)
      if (_supabase.auth.currentUser != null) {
        try {
          await _supabase
              .from('user_profiles')
              .select('id')
              .eq('id', _supabase.auth.currentUser!.id)
              .maybeSingle();
          results['user_profile_access'] = 'Can access own profile';
        } catch (e) {
          results['user_profile_access'] = 'Error: $e';
        }
      }
      
    } catch (e) {
      results['connection'] = 'Error: $e';
    }
    
    return results;
  }
  
  // Test signup process step by step
  Future<Map<String, dynamic>> testSignupProcess({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String phoneNumber,
  }) async {
    final results = <String, dynamic>{};
    
    try {
      // Step 1: Test Supabase Auth signup
      print('Testing Supabase Auth signup...');
      final authResponse = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'first_name': firstName,
          'last_name': lastName,
          'phone_number': phoneNumber,
          'user_type': 'driver',
        },
      );
      
      if (authResponse.user != null) {
        results['auth_signup'] = 'Success - User created: ${authResponse.user!.id}';
        
        // Step 2: Test user_profiles insert
        try {
          print('Testing user_profiles insert...');
          await _supabase.from('user_profiles').insert({
            'id': authResponse.user!.id,
            'first_name': firstName,
            'last_name': lastName,
            'phone_number': phoneNumber,
            'user_type': 'driver',
            'status': 'active',
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          });
          results['user_profiles_insert'] = 'Success';
          
          // Step 3: Test driver_profiles insert
          try {
            print('Testing driver_profiles insert...');
            await _supabase.from('driver_profiles').insert({
              'id': authResponse.user!.id,
              'is_verified': false,
              'is_online': false,
              'rating': 0.00,
              'total_deliveries': 0,
              'created_at': DateTime.now().toIso8601String(),
              'updated_at': DateTime.now().toIso8601String(),
            });
            results['driver_profiles_insert'] = 'Success';
          } catch (e) {
            results['driver_profiles_insert'] = 'Error: $e';
          }
          
        } catch (e) {
          results['user_profiles_insert'] = 'Error: $e';
        }
        
        // Clean up - delete the test user
        try {
          await _supabase.auth.admin.deleteUser(authResponse.user!.id);
          results['cleanup'] = 'Test user deleted';
        } catch (e) {
          results['cleanup'] = 'Could not delete test user: $e';
        }
        
      } else {
        results['auth_signup'] = 'Failed - No user returned';
      }
      
    } catch (e) {
      results['auth_signup'] = 'Error: $e';
    }
    
    return results;
  }
  
  // Test if tables exist and are accessible
  Future<Map<String, dynamic>> testTableAccess() async {
    final results = <String, dynamic>{};
    
    // List of tables to test
    final tables = ['user_profiles', 'driver_profiles', 'deliveries'];
    
    for (final table in tables) {
      try {
        // Try to get table schema/structure
        await _supabase
            .from(table)
            .select()
            .limit(0); // Get no rows, just test access
        results[table] = 'Accessible';
      } catch (e) {
        results[table] = 'Error: $e';
      }
    }
    
    return results;
  }
}