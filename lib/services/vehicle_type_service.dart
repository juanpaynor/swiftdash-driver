import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/vehicle_type.dart';

class VehicleTypeService {
  final SupabaseClient _supabase = Supabase.instance.client;
  
  // Get all active vehicle types
  Future<List<VehicleType>> getActiveVehicleTypes() async {
    try {
      print('VehicleTypeService: Fetching active vehicle types...');
      final response = await _supabase
          .from('vehicle_types')
          .select('*')
          .eq('is_active', true)
          .order('max_weight_kg'); // Order by weight capacity
      
      print('VehicleTypeService: Raw response: $response');
      
      final vehicleTypes = (response as List)
          .map((data) => VehicleType.fromJson(data))
          .toList();
          
      print('VehicleTypeService: Parsed ${vehicleTypes.length} vehicle types');
      return vehicleTypes;
    } catch (e) {
      print('VehicleTypeService: Error fetching vehicle types: $e');
      throw Exception('Failed to load vehicle types');
    }
  }
  
  // Get specific vehicle type by ID
  Future<VehicleType?> getVehicleTypeById(String id) async {
    try {
      final response = await _supabase
          .from('vehicle_types')
          .select('*')
          .eq('id', id)
          .single();
      
      return VehicleType.fromJson(response);
    } catch (e) {
      print('Error fetching vehicle type: $e');
      return null;
    }
  }
  
  // Calculate delivery price estimate
  Future<Map<String, double>> calculateDeliveryPrice({
    required String vehicleTypeId,
    required double distanceKm,
    int stops = 0,
  }) async {
    try {
      final vehicleType = await getVehicleTypeById(vehicleTypeId);
      if (vehicleType == null) {
        throw Exception('Vehicle type not found');
      }
      
      // Calculate base cost
      double subtotal = vehicleType.basePrice + (distanceKm * vehicleType.pricePerKm);
      
      // Add stop fees (varies by vehicle type - using a simple calculation)
      double stopFee = 0;
      if (stops > 0) {
        // Simple stop fee calculation - you can customize this based on vehicle type
        if (vehicleType.name.toLowerCase().contains('motorcycle')) {
          stopFee = stops * 40;
        } else if (vehicleType.name.toLowerCase().contains('sedan') || 
                   vehicleType.name.toLowerCase().contains('suv')) {
          stopFee = stops * 45;
        } else if (vehicleType.name.toLowerCase().contains('pickup') || 
                   vehicleType.name.toLowerCase().contains('van')) {
          stopFee = stops * 50;
        } else if (vehicleType.name.toLowerCase().contains('truck')) {
          stopFee = stops * 255;
        }
      }
      
      subtotal += stopFee;
      
      // Calculate service fee (example: 10%)
      double serviceFee = subtotal * 0.10;
      
      // Calculate total
      double total = subtotal + serviceFee;
      
      return {
        'basePrice': vehicleType.basePrice,
        'distanceFee': distanceKm * vehicleType.pricePerKm,
        'stopFee': stopFee,
        'subtotal': subtotal,
        'serviceFee': serviceFee,
        'total': total,
      };
    } catch (e) {
      print('Error calculating delivery price: $e');
      throw Exception('Failed to calculate delivery price');
    }
  }
  
  // Get vehicle types suitable for a specific weight
  Future<List<VehicleType>> getVehicleTypesForWeight(double weightKg) async {
    try {
      final response = await _supabase
          .from('vehicle_types')
          .select('*')
          .gte('max_weight_kg', weightKg)
          .eq('is_active', true)
          .order('max_weight_kg');
      
      return (response as List)
          .map((data) => VehicleType.fromJson(data))
          .toList();
    } catch (e) {
      print('Error fetching suitable vehicle types: $e');
      throw Exception('Failed to load suitable vehicle types');
    }
  }
}