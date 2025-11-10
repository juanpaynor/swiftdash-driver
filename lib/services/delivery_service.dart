import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/delivery.dart';
import 'delivery_stop_service.dart';

class DeliveryService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final DeliveryStopService _stopService = DeliveryStopService();
  
  // Get available deliveries for a driver (pending assignments)
  Future<List<Delivery>> getAvailableDeliveries() async {
    try {
      final response = await _supabase
          .from('deliveries')
          .select()
          .eq('status', 'pending')
          .order('created_at', ascending: true);
      
      return (response as List)
          .map((delivery) => Delivery.fromJson(delivery))
          .toList();
    } catch (e) {
      throw Exception('Failed to fetch available deliveries: $e');
    }
  }
  
  // Get current driver's assigned deliveries
  Future<List<Delivery>> getDriverDeliveries() async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('User not authenticated');
    
    try {
      final response = await _supabase
          .from('deliveries')
          .select()
          .eq('driver_id', user.id)
          .inFilter('status', ['driver_assigned', 'pickup_arrived', 'package_collected', 'in_transit'])
          .order('created_at', ascending: true);
      
      return (response as List)
          .map((delivery) => Delivery.fromJson(delivery))
          .toList();
    } catch (e) {
      throw Exception('Failed to fetch driver deliveries: $e');
    }
  }
  
  // Accept a delivery
  Future<void> acceptDelivery(String deliveryId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('User not authenticated');
    
    try {
      await _supabase
          .from('deliveries')
          .update({
            'driver_id': user.id,
            'status': 'driver_assigned',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', deliveryId)
          .eq('status', 'pending'); // Only update if still pending
    } catch (e) {
      throw Exception('Failed to accept delivery: $e');
    }
  }
  
  // Update delivery status
  Future<void> updateDeliveryStatus(String deliveryId, DeliveryStatus status) async {
    try {
      final updateData = {
        'status': status.databaseValue, // ✅ Use database-compatible value instead of enum name
        'updated_at': DateTime.now().toIso8601String(),
      };
      
      // Add completed_at timestamp for delivered status
      if (status == DeliveryStatus.delivered) {
        updateData['completed_at'] = DateTime.now().toIso8601String();
      }
      
      await _supabase
          .from('deliveries')
          .update(updateData)
          .eq('id', deliveryId);
    } catch (e) {
      throw Exception('Failed to update delivery status: $e');
    }
  }
  
  // Get delivery history for the driver
  Future<List<Delivery>> getDeliveryHistory({int limit = 50}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('User not authenticated');
    
    try {
      final response = await _supabase
          .from('deliveries')
          .select()
          .eq('driver_id', user.id)
          .inFilter('status', ['delivered', 'cancelled', 'failed'])
          .order('completed_at', ascending: false)
          .limit(limit);
      
      return (response as List)
          .map((delivery) => Delivery.fromJson(delivery))
          .toList();
    } catch (e) {
      throw Exception('Failed to fetch delivery history: $e');
    }
  }
  
  // Get today's earnings
  Future<double> getTodayEarnings() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return 0.0;
    
    try {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      
      final response = await _supabase
          .from('deliveries')
          .select('total_price')
          .eq('driver_id', user.id)
          .eq('status', 'delivered')
          .gte('completed_at', startOfDay.toIso8601String())
          .lt('completed_at', endOfDay.toIso8601String());
      
      double totalEarnings = 0.0;
      for (final delivery in response) {
        final price = delivery['total_price'] as num;
        totalEarnings += price.toDouble() * 0.75; // 75% driver commission
      }
      
      return totalEarnings;
    } catch (e) {
      return 0.0;
    }
  }
  
  // Get today's delivery count
  Future<int> getTodayDeliveryCount() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return 0;
    
    try {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      
      final response = await _supabase
          .from('deliveries')
          .select('id')
          .eq('driver_id', user.id)
          .eq('status', 'delivered')
          .gte('completed_at', startOfDay.toIso8601String())
          .lt('completed_at', endOfDay.toIso8601String());
      
      return response.length;
    } catch (e) {
      return 0;
    }
  }
  
  // Submit driver rating for customer
  Future<void> rateCustomer(String deliveryId, int rating) async {
    try {
      await _supabase
          .from('deliveries')
          .update({
            'driver_rating': rating,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', deliveryId);
    } catch (e) {
      throw Exception('Failed to submit rating: $e');
    }
  }
  
  // Listen to delivery updates (for real-time notifications)
  Stream<List<Delivery>> watchAvailableDeliveries() {
    return _supabase
        .from('deliveries')
        .stream(primaryKey: ['id'])
        .eq('status', 'pending')
        .map((data) => data
            .map((delivery) => Delivery.fromJson(delivery))
            .toList());
  }
  
  // Listen to driver's assigned deliveries
  Stream<List<Delivery>> watchDriverDeliveries() {
    final user = _supabase.auth.currentUser;
    if (user == null) return Stream.value([]);
    
    return _supabase
        .from('deliveries')
        .stream(primaryKey: ['id'])
        .eq('driver_id', user.id)
        .map((data) => data
            .map((delivery) => Delivery.fromJson(delivery))
            .toList());
  }
  
  // Get delivery with stops loaded (for multi-stop deliveries)
  Future<Delivery> getDeliveryWithStops(String deliveryId) async {
    try {
      final response = await _supabase
          .from('deliveries')
          .select()
          .eq('id', deliveryId)
          .single();
      
      final delivery = Delivery.fromJson(response);
      
      // If multi-stop, load the stops
      if (delivery.isMultiStop) {
        final stops = await _stopService.getDeliveryStops(deliveryId);
        return delivery.copyWith(stops: stops);
      }
      
      return delivery;
    } catch (e) {
      throw Exception('Failed to fetch delivery with stops: $e');
    }
  }
  
  // Check if delivery is multi-stop
  bool isMultiStopDelivery(Delivery delivery) {
    return delivery.isMultiStop && delivery.totalStops > 1;
  }
}