import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import '../models/delivery.dart';

class RealtimeService {
  final SupabaseClient _supabase = Supabase.instance.client;
  RealtimeChannel? _deliveriesChannel;
  RealtimeChannel? _driverChannel;
  
  // Stream controllers for real-time data
  final _newDeliveriesController = StreamController<Delivery>.broadcast();
  final _deliveryUpdatesController = StreamController<Delivery>.broadcast();
  final _driverStatusController = StreamController<Map<String, dynamic>>.broadcast();
  
  // Public streams
  Stream<Delivery> get newDeliveries => _newDeliveriesController.stream;
  Stream<Delivery> get deliveryUpdates => _deliveryUpdatesController.stream;
  Stream<Map<String, dynamic>> get driverStatusUpdates => _driverStatusController.stream;
  
  // Initialize realtime subscriptions
  Future<void> initializeRealtimeSubscriptions(String driverId) async {
    try {
      print('Initializing realtime subscriptions for driver: $driverId');
      
      // Subscribe to deliveries table for new delivery offers
      await _subscribeToDeliveries(driverId);
      
      // Subscribe to driver profile updates
      await _subscribeToDriverUpdates(driverId);
      
      print('Realtime subscriptions initialized successfully');
    } catch (e) {
      print('Error initializing realtime subscriptions: $e');
      rethrow;
    }
  }
  
  // Subscribe to deliveries table for new offers and updates
  Future<void> _subscribeToDeliveries(String driverId) async {
    _deliveriesChannel = _supabase
        .channel('deliveries-channel')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'deliveries',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'status',
            value: 'pending',
          ),
          callback: (payload) {
            print('New delivery offer received: ${payload.newRecord}');
            try {
              final delivery = Delivery.fromJson(payload.newRecord);
              _newDeliveriesController.add(delivery);
            } catch (e) {
              print('Error parsing new delivery: $e');
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'deliveries',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'driver_id',
            value: driverId,
          ),
          callback: (payload) {
            print('Delivery update received: ${payload.newRecord}');
            try {
              final delivery = Delivery.fromJson(payload.newRecord);
              _deliveryUpdatesController.add(delivery);
            } catch (e) {
              print('Error parsing delivery update: $e');
            }
          },
        );
    
    await _deliveriesChannel!.subscribe();
    print('Subscribed to deliveries channel');
  }
  
  // Subscribe to driver profile updates
  Future<void> _subscribeToDriverUpdates(String driverId) async {
    _driverChannel = _supabase
        .channel('driver-profile-channel')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'driver_profiles',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: driverId,
          ),
          callback: (payload) {
            print('Driver profile update received: ${payload.newRecord}');
            _driverStatusController.add(payload.newRecord);
          },
        );
    
    await _driverChannel!.subscribe();
    print('Subscribed to driver profile channel');
  }
  
  // Accept a delivery offer
  Future<bool> acceptDeliveryOffer(String deliveryId, String driverId) async {
    try {
      print('Accepting delivery offer: $deliveryId');
      
      final response = await _supabase
          .from('deliveries')
          .update({
            'status': 'driver_assigned',
            'driver_id': driverId,
            'assigned_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', deliveryId)
          .eq('status', 'pending') // Only update if still pending
          .select()
          .maybeSingle();
      
      if (response != null) {
        print('Successfully accepted delivery: $deliveryId');
        return true;
      } else {
        print('Failed to accept delivery - may have been taken by another driver');
        return false;
      }
    } catch (e) {
      print('Error accepting delivery offer: $e');
      return false;
    }
  }
  
  // Update delivery status (picked up, in transit, delivered)
  Future<bool> updateDeliveryStatus(String deliveryId, String status) async {
    try {
      print('Updating delivery status: $deliveryId -> $status');
      
      final updateData = {
        'status': status,
        'updated_at': DateTime.now().toIso8601String(),
      };
      
      // Add timestamp fields based on status
      switch (status) {
        case 'package_collected':
          updateData['picked_up_at'] = DateTime.now().toIso8601String();
          break;
        case 'in_transit':
          updateData['in_transit_at'] = DateTime.now().toIso8601String();
          break;
        case 'delivered':
          updateData['delivered_at'] = DateTime.now().toIso8601String();
          updateData['completed_at'] = DateTime.now().toIso8601String();
          break;
      }
      
      await _supabase
          .from('deliveries')
          .update(updateData)
          .eq('id', deliveryId);
      
      print('Successfully updated delivery status');
      return true;
    } catch (e) {
      print('Error updating delivery status: $e');
      return false;
    }
  }
  
  // Update driver location (for future proximity matching)
  Future<void> updateDriverLocation(String driverId, double latitude, double longitude) async {
    try {
      await _supabase
          .from('driver_profiles')
          .update({
            'current_latitude': latitude,
            'current_longitude': longitude,
            'location_updated_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', driverId);
      
      print('Updated driver location: $latitude, $longitude');
    } catch (e) {
      print('Error updating driver location: $e');
    }
  }
  
  // Update driver online status
  Future<void> updateDriverOnlineStatus(String driverId, bool isOnline) async {
    try {
      await _supabase
          .from('driver_profiles')
          .update({
            'is_online': isOnline,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', driverId);
      
      print('Updated driver online status: $isOnline');
    } catch (e) {
      print('Error updating driver online status: $e');
    }
  }
  
  // Get pending deliveries for driver
  Future<List<Delivery>> getPendingDeliveries(String driverId) async {
    try {
      final response = await _supabase
          .from('deliveries')
          .select('*')
          .eq('driver_id', driverId)
          .inFilter('status', ['driver_assigned', 'package_collected', 'in_transit'])
          .order('created_at', ascending: true);
      
      return (response as List)
          .map((data) => Delivery.fromJson(data))
          .toList();
    } catch (e) {
      print('Error fetching pending deliveries: $e');
      return [];
    }
  }
  
  // Get available delivery offers
  Future<List<Delivery>> getAvailableDeliveryOffers() async {
    try {
      final response = await _supabase
          .from('deliveries')
          .select('*')
          .eq('status', 'pending')
          .order('created_at', ascending: true)
          .limit(10); // Limit to recent offers
      
      return (response as List)
          .map((data) => Delivery.fromJson(data))
          .toList();
    } catch (e) {
      print('Error fetching delivery offers: $e');
      return [];
    }
  }
  
  // Clean up subscriptions
  Future<void> dispose() async {
    try {
      if (_deliveriesChannel != null) {
        await _deliveriesChannel!.unsubscribe();
        _deliveriesChannel = null;
      }
      
      if (_driverChannel != null) {
        await _driverChannel!.unsubscribe();
        _driverChannel = null;
      }
      
      await _newDeliveriesController.close();
      await _deliveryUpdatesController.close();
      await _driverStatusController.close();
      
      print('Realtime subscriptions disposed');
    } catch (e) {
      print('Error disposing realtime subscriptions: $e');
    }
  }
}