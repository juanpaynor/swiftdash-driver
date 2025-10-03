import 'vehicle_type_service.dart';

Future<void> testVehicleTypes() async {
  try {
    print('Testing vehicle types service...');
    
    // Initialize Supabase (you might need to call this from main)
    // await Supabase.initialize(url: SupabaseConfig.url, anonKey: SupabaseConfig.anonKey);
    
    final service = VehicleTypeService();
    
    print('Fetching vehicle types...');
    final types = await service.getActiveVehicleTypes();
    
    print('Found ${types.length} vehicle types:');
    for (final type in types) {
      print('- ${type.name} (ID: ${type.id})');
      print('  Base Price: ₱${type.basePrice}');
      print('  Per KM: ₱${type.pricePerKm}');
      print('  Max Weight: ${type.maxWeightKg}kg');
      print('  Active: ${type.isActive}');
      print('');
    }
    
    if (types.isEmpty) {
      print('No vehicle types found! Check if:');
      print('1. Vehicle types exist in the database');
      print('2. They are marked as active (is_active = true)');
      print('3. Database connection is working');
    }
    
  } catch (e) {
    print('Error testing vehicle types: $e');
  }
}