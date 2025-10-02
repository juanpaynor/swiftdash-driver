import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:typed_data';

class StorageTestService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Test storage access
  Future<bool> testStorageAccess() async {
    try {
      // Create a simple test file
      final testData = Uint8List.fromList('test'.codeUnits);
      final testFileName = 'test_${DateTime.now().millisecondsSinceEpoch}.txt';
      
      // Try to upload to driver_profile_pictures bucket
      await _supabase.storage
          .from('driver_profile_pictures')
          .uploadBinary(testFileName, testData);
      
      print('✅ Storage upload successful');
      
      // Try to get the file URL
      final url = _supabase.storage
          .from('driver_profile_pictures')
          .getPublicUrl(testFileName);
      
      print('✅ Storage URL generated: $url');
      
      // Clean up test file
      await _supabase.storage
          .from('driver_profile_pictures')
          .remove([testFileName]);
      
      print('✅ Storage test complete - All operations successful');
      return true;
      
    } catch (e) {
      print('❌ Storage test failed: $e');
      
      // Check common issues
      if (e.toString().contains('Invalid API key')) {
        print('💡 Issue: API Key problem');
      } else if (e.toString().contains('not allowed')) {
        print('💡 Issue: Storage policy/permission problem');
      } else if (e.toString().contains('Bucket not found')) {
        print('💡 Issue: Bucket does not exist');
      }
      
      return false;
    }
  }

  // Test all buckets
  Future<Map<String, bool>> testAllBuckets() async {
    final buckets = [
      'driver_profile_pictures',
      'License_pictures',
      'LTFRB_pictures', 
      'Proof_of_delivery',
      'user_profile_pictures',
    ];
    
    final results = <String, bool>{};
    
    for (final bucket in buckets) {
      try {
        final testData = Uint8List.fromList('test'.codeUnits);
        final testFileName = 'test_${DateTime.now().millisecondsSinceEpoch}.txt';
        
        await _supabase.storage
            .from(bucket)
            .uploadBinary(testFileName, testData);
        
        await _supabase.storage
            .from(bucket)
            .remove([testFileName]);
        
        results[bucket] = true;
        print('✅ $bucket - OK');
        
      } catch (e) {
        results[bucket] = false;
        print('❌ $bucket - Failed: $e');
      }
    }
    
    return results;
  }
}