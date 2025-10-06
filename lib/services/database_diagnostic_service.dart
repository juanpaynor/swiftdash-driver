import 'package:supabase_flutter/supabase_flutter.dart';

class DatabaseDiagnosticService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Test database connection and table access
  Future<Map<String, dynamic>> runDatabaseDiagnostics() async {
    final diagnostics = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'connection_status': 'unknown',
      'tables_accessible': {},
      'current_user': null,
      'user_type': 'unknown',
      'driver_profile_status': 'unknown',
      'driver_current_status_exists': false,
      'errors': [],
    };

    try {
      // Check current user
      final user = _supabase.auth.currentUser;
      diagnostics['current_user'] = user?.id;
      
      if (user == null) {
        diagnostics['errors'].add('No authenticated user');
        return diagnostics;
      }

      diagnostics['connection_status'] = 'connected';

      // Check user type in user_profiles
      try {
        final userProfile = await _supabase
            .from('user_profiles')
            .select('user_type, first_name, last_name')
            .eq('id', user.id)
            .maybeSingle();
        
        if (userProfile != null) {
          diagnostics['user_type'] = userProfile['user_type'];
          diagnostics['user_name'] = '${userProfile['first_name']} ${userProfile['last_name']}';
          
          if (userProfile['user_type'] != 'driver') {
            diagnostics['errors'].add('❌ WRONG USER TYPE: You are logged in as a ${userProfile['user_type']}, not a driver!');
          }
        } else {
          diagnostics['user_type'] = 'not_found_in_profiles';
          diagnostics['errors'].add('User profile not found in user_profiles table');
        }
      } catch (e) {
        diagnostics['errors'].add('Error checking user profile: $e');
      }

      // Test driver_profiles table (only if user type is driver)
      try {
        final driverProfile = await _supabase
            .from('driver_profiles')
            .select('id, is_online, current_latitude, current_longitude, updated_at')
            .eq('id', user.id)
            .maybeSingle();
        
        diagnostics['tables_accessible']['driver_profiles'] = true;
        diagnostics['driver_profile_status'] = driverProfile != null ? 'found' : 'not_found';
        
        if (driverProfile != null) {
          diagnostics['driver_profile_data'] = {
            'is_online': driverProfile['is_online'],
            'has_location': driverProfile['current_latitude'] != null,
            'last_updated': driverProfile['updated_at'],
          };
        } else if (diagnostics['user_type'] == 'driver') {
          diagnostics['errors'].add('Driver profile not found but user_type is driver');
        }
      } catch (e) {
        diagnostics['tables_accessible']['driver_profiles'] = false;
        diagnostics['errors'].add('driver_profiles error: $e');
      }

      // Test driver_current_status table
      try {
        final currentStatus = await _supabase
            .from('driver_current_status')
            .select('*')
            .eq('driver_id', user.id)
            .maybeSingle();
        
        diagnostics['tables_accessible']['driver_current_status'] = true;
        diagnostics['driver_current_status_exists'] = currentStatus != null;
        
        if (currentStatus != null) {
          diagnostics['driver_current_status_data'] = {
            'status': currentStatus['status'],
            'has_location': currentStatus['current_latitude'] != null,
            'last_updated': currentStatus['last_updated'],
            'current_delivery_id': currentStatus['current_delivery_id'],
          };
        }
      } catch (e) {
        diagnostics['tables_accessible']['driver_current_status'] = false;
        diagnostics['errors'].add('driver_current_status error: $e');
      }

      // Test deliveries table
      try {
        final deliveries = await _supabase
            .from('deliveries')
            .select('id, status, driver_id')
            .limit(1);
        
        diagnostics['tables_accessible']['deliveries'] = true;
        diagnostics['deliveries_count'] = deliveries.length;
      } catch (e) {
        diagnostics['tables_accessible']['deliveries'] = false;
        diagnostics['errors'].add('deliveries error: $e');
      }

      // Test vehicle_types table
      try {
        final vehicleTypes = await _supabase
            .from('vehicle_types')
            .select('id, type_name')
            .limit(1);
        
        diagnostics['tables_accessible']['vehicle_types'] = true;
        diagnostics['vehicle_types_count'] = vehicleTypes.length;
      } catch (e) {
        diagnostics['tables_accessible']['vehicle_types'] = false;
        diagnostics['errors'].add('vehicle_types error: $e');
      }

    } catch (e) {
      diagnostics['connection_status'] = 'error';
      diagnostics['errors'].add('Connection error: $e');
    }

    return diagnostics;
  }

  /// Test driver status update functionality
  Future<Map<String, dynamic>> testDriverStatusUpdate() async {
    final test = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'test_type': 'driver_status_update',
      'success': false,
      'steps': [],
      'errors': [],
    };

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        test['errors'].add('No authenticated user');
        return test;
      }

      // Step 1: Get current status
      test['steps'].add('Getting current status');
      final beforeProfile = await _supabase
          .from('driver_profiles')
          .select('is_online')
          .eq('id', user.id)
          .single();

      final beforeCurrentStatus = await _supabase
          .from('driver_current_status')
          .select('status')
          .eq('driver_id', user.id)
          .maybeSingle();

      test['before_update'] = {
        'driver_profiles_online': beforeProfile['is_online'],
        'driver_current_status': beforeCurrentStatus?['status'] ?? 'not_found',
      };

      // Step 2: Update to opposite status
      test['steps'].add('Updating status');
      final newOnlineStatus = !(beforeProfile['is_online'] ?? false);
      
      await _supabase
          .from('driver_profiles')
          .update({
            'is_online': newOnlineStatus,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', user.id);

      await _supabase.from('driver_current_status').upsert({
        'driver_id': user.id,
        'status': newOnlineStatus ? 'available' : 'offline',
        'last_updated': DateTime.now().toIso8601String(),
      });

      // Step 3: Verify update
      test['steps'].add('Verifying update');
      final afterProfile = await _supabase
          .from('driver_profiles')
          .select('is_online, updated_at')
          .eq('id', user.id)
          .single();

      final afterCurrentStatus = await _supabase
          .from('driver_current_status')
          .select('status, last_updated')
          .eq('driver_id', user.id)
          .single();

      test['after_update'] = {
        'driver_profiles_online': afterProfile['is_online'],
        'driver_profiles_updated_at': afterProfile['updated_at'],
        'driver_current_status': afterCurrentStatus['status'],
        'driver_current_status_updated_at': afterCurrentStatus['last_updated'],
      };

      test['success'] = true;
      test['steps'].add('Update successful');

    } catch (e) {
      test['errors'].add('Test failed: $e');
    }

    return test;
  }

  /// Test location update functionality
  Future<Map<String, dynamic>> testLocationUpdate() async {
    final test = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'test_type': 'location_update',
      'success': false,
      'steps': [],
      'errors': [],
    };

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        test['errors'].add('No authenticated user');
        return test;
      }

      // Test coordinates (Manila area)
      final testLat = 14.5995 + (DateTime.now().millisecond / 100000);
      final testLng = 121.0381 + (DateTime.now().millisecond / 100000);

      test['test_coordinates'] = {
        'latitude': testLat,
        'longitude': testLng,
      };

      // Step 1: Update location in driver_profiles
      test['steps'].add('Updating location in driver_profiles');
      await _supabase
          .from('driver_profiles')
          .update({
            'current_latitude': testLat,
            'current_longitude': testLng,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', user.id);

      // Step 2: Update location in driver_current_status
      test['steps'].add('Updating location in driver_current_status');
      await _supabase.from('driver_current_status').upsert({
        'driver_id': user.id,
        'current_latitude': testLat,
        'current_longitude': testLng,
        'last_updated': DateTime.now().toIso8601String(),
      });

      // Step 3: Verify updates
      test['steps'].add('Verifying location updates');
      final profileLocation = await _supabase
          .from('driver_profiles')
          .select('current_latitude, current_longitude, updated_at')
          .eq('id', user.id)
          .single();

      final statusLocation = await _supabase
          .from('driver_current_status')
          .select('current_latitude, current_longitude, last_updated')
          .eq('driver_id', user.id)
          .single();

      test['verification'] = {
        'driver_profiles': {
          'latitude': profileLocation['current_latitude'],
          'longitude': profileLocation['current_longitude'],
          'updated_at': profileLocation['updated_at'],
        },
        'driver_current_status': {
          'latitude': statusLocation['current_latitude'],
          'longitude': statusLocation['current_longitude'],
          'last_updated': statusLocation['last_updated'],
        },
      };

      test['success'] = true;
      test['steps'].add('Location update successful');

    } catch (e) {
      test['errors'].add('Location test failed: $e');
    }

    return test;
  }

  /// Create driver_current_status entry if it doesn't exist
  Future<Map<String, dynamic>> initializeDriverCurrentStatus() async {
    final result = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'action': 'initialize_driver_current_status',
      'success': false,
      'errors': [],
    };

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        result['errors'].add('No authenticated user');
        return result;
      }

      // Check if entry exists
      final existing = await _supabase
          .from('driver_current_status')
          .select('driver_id')
          .eq('driver_id', user.id)
          .maybeSingle();

      if (existing != null) {
        result['message'] = 'driver_current_status entry already exists';
        result['success'] = true;
        return result;
      }

      // Create new entry
      await _supabase.from('driver_current_status').insert({
        'driver_id': user.id,
        'status': 'offline',
        'last_updated': DateTime.now().toIso8601String(),
      });

      result['message'] = 'driver_current_status entry created';
      result['success'] = true;

    } catch (e) {
      result['errors'].add('Initialize failed: $e');
    }

    return result;
  }

  /// Get comprehensive driver status
  Future<Map<String, dynamic>> getDriverStatus() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return {'error': 'No authenticated user'};

      final profile = await _supabase
          .from('driver_profiles')
          .select('*')
          .eq('id', user.id)
          .single();

      final currentStatus = await _supabase
          .from('driver_current_status')
          .select('*')
          .eq('driver_id', user.id)
          .maybeSingle();

      return {
        'driver_id': user.id,
        'driver_profiles': profile,
        'driver_current_status': currentStatus,
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      return {'error': 'Failed to get driver status: $e'};
    }
  }

  /// Quick check: What type of user is currently logged in?
  Future<Map<String, dynamic>> checkCurrentUserType() async {
    final result = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'authenticated': false,
      'user_id': null,
      'user_type': 'unknown',
      'is_driver': false,
      'has_driver_profile': false,
      'message': '',
    };

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        result['message'] = '❌ No user is currently logged in';
        return result;
      }

      result['authenticated'] = true;
      result['user_id'] = user.id;

      // Check user_profiles table for user type
      final userProfile = await _supabase
          .from('user_profiles')
          .select('user_type, first_name, last_name')
          .eq('id', user.id)
          .maybeSingle();

      if (userProfile == null) {
        result['message'] = '❌ User profile not found in database';
        return result;
      }

      result['user_type'] = userProfile['user_type'];
      result['user_name'] = '${userProfile['first_name']} ${userProfile['last_name']}';

      if (userProfile['user_type'] == 'driver') {
        result['is_driver'] = true;

        // Check if driver profile exists
        final driverProfile = await _supabase
            .from('driver_profiles')
            .select('id')
            .eq('id', user.id)
            .maybeSingle();

        result['has_driver_profile'] = driverProfile != null;

        if (driverProfile != null) {
          result['message'] = '✅ Valid driver account - Ready to use driver app';
        } else {
          result['message'] = '⚠️ Driver user but no driver profile - Need to complete registration';
        }
      } else if (userProfile['user_type'] == 'customer') {
        result['message'] = '❌ You are logged in as a CUSTOMER - Please use the customer app or log in with a driver account';
      } else {
        result['message'] = '❌ Unknown user type: ${userProfile['user_type']}';
      }

    } catch (e) {
      result['message'] = '❌ Error checking user type: $e';
    }

    return result;
  }
}