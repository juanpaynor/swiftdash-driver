import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/delivery_stop.dart';

/// Service for managing delivery stops in multi-stop deliveries
class DeliveryStopService {
  final SupabaseClient _supabase = Supabase.instance.client;
  
  /// Get all stops for a delivery, ordered by stop number
  Future<List<DeliveryStop>> getDeliveryStops(String deliveryId) async {
    try {
      final response = await _supabase
          .from('delivery_stops')
          .select()
          .eq('delivery_id', deliveryId)
          .order('stop_number');
      
      return (response as List)
          .map((json) => DeliveryStop.fromJson(json))
          .toList();
    } catch (e) {
      throw Exception('Failed to fetch delivery stops: $e');
    }
  }
  
  /// Get the current active stop based on delivery's current_stop_index
  Future<DeliveryStop?> getCurrentStop(String deliveryId) async {
    try {
      // First get the delivery's current stop index
      final deliveryResponse = await _supabase
          .from('deliveries')
          .select('current_stop_index')
          .eq('id', deliveryId)
          .single();
      
      final currentIndex = deliveryResponse['current_stop_index'] as int;
      
      // Get the stop at that index
      final stopResponse = await _supabase
          .from('delivery_stops')
          .select()
          .eq('delivery_id', deliveryId)
          .eq('stop_number', currentIndex)
          .maybeSingle();
      
      return stopResponse != null ? DeliveryStop.fromJson(stopResponse) : null;
    } catch (e) {
      print('Error fetching current stop: $e');
      return null;
    }
  }
  
  /// Get remaining (pending) stops for a delivery
  Future<List<DeliveryStop>> getRemainingStops(String deliveryId) async {
    try {
      final response = await _supabase
          .from('delivery_stops')
          .select()
          .eq('delivery_id', deliveryId)
          .eq('status', 'pending')
          .order('stop_number');
      
      return (response as List)
          .map((json) => DeliveryStop.fromJson(json))
          .toList();
    } catch (e) {
      throw Exception('Failed to fetch remaining stops: $e');
    }
  }
  
  /// Mark driver as arrived at a stop
  Future<void> markStopArrived(String stopId) async {
    try {
      await _supabase
          .from('delivery_stops')
          .update({
            'status': 'in_progress',
            'arrived_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', stopId);
    } catch (e) {
      throw Exception('Failed to mark stop as arrived: $e');
    }
  }
  
  /// Complete a stop with proof of delivery
  Future<void> completeStop({
    required String stopId,
    required String deliveryId,
    String? proofPhotoUrl,
    String? signatureUrl,
    String? completionNotes,
  }) async {
    try {
      // Update the stop status
      await _supabase
          .from('delivery_stops')
          .update({
            'status': 'completed',
            'completed_at': DateTime.now().toIso8601String(),
            'proof_photo_url': proofPhotoUrl,
            'signature_url': signatureUrl,
            'completion_notes': completionNotes,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', stopId);
      
      // Get current stop index and increment it
      final deliveryResponse = await _supabase
          .from('deliveries')
          .select('current_stop_index, total_stops')
          .eq('id', deliveryId)
          .single();
      
      final currentIndex = deliveryResponse['current_stop_index'] as int;
      final totalStops = deliveryResponse['total_stops'] as int;
      final newIndex = currentIndex + 1;
      
      // Update delivery's current_stop_index
      await _supabase
          .from('deliveries')
          .update({
            'current_stop_index': newIndex,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', deliveryId);
      
      // If all stops are completed, mark delivery as completed
      if (newIndex >= totalStops) {
        await _completeDelivery(deliveryId);
      }
    } catch (e) {
      throw Exception('Failed to complete stop: $e');
    }
  }
  
  /// Update stop status
  Future<void> updateStopStatus({
    required String stopId,
    required DeliveryStopStatus status,
    DateTime? arrivedAt,
    DateTime? completedAt,
    String? proofPhotoUrl,
    String? signatureUrl,
    String? completionNotes,
  }) async {
    try {
      final updateData = {
        'status': status.databaseValue,
        'updated_at': DateTime.now().toIso8601String(),
      };
      
      if (arrivedAt != null) {
        updateData['arrived_at'] = arrivedAt.toIso8601String();
      }
      if (completedAt != null) {
        updateData['completed_at'] = completedAt.toIso8601String();
      }
      if (proofPhotoUrl != null) {
        updateData['proof_photo_url'] = proofPhotoUrl;
      }
      if (signatureUrl != null) {
        updateData['signature_url'] = signatureUrl;
      }
      if (completionNotes != null) {
        updateData['completion_notes'] = completionNotes;
      }
      
      await _supabase
          .from('delivery_stops')
          .update(updateData)
          .eq('id', stopId);
    } catch (e) {
      throw Exception('Failed to update stop status: $e');
    }
  }
  
  /// Check if all stops are completed
  Future<bool> areAllStopsCompleted(String deliveryId) async {
    try {
      final stops = await getDeliveryStops(deliveryId);
      return stops.every((stop) => stop.isCompleted);
    } catch (e) {
      print('Error checking if all stops completed: $e');
      return false;
    }
  }
  
  /// Stream delivery stops for real-time updates
  Stream<List<DeliveryStop>> streamDeliveryStops(String deliveryId) {
    return _supabase
        .from('delivery_stops')
        .stream(primaryKey: ['id'])
        .eq('delivery_id', deliveryId)
        .order('stop_number')
        .map((data) => data
            .map((json) => DeliveryStop.fromJson(json))
            .toList());
  }
  
  /// Mark a stop as failed
  Future<void> markStopFailed({
    required String stopId,
    required String reason,
  }) async {
    try {
      await _supabase
          .from('delivery_stops')
          .update({
            'status': 'failed',
            'completion_notes': reason,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', stopId);
    } catch (e) {
      throw Exception('Failed to mark stop as failed: $e');
    }
  }
  
  /// Complete the entire delivery
  Future<void> _completeDelivery(String deliveryId) async {
    try {
      await _supabase
          .from('deliveries')
          .update({
            'status': 'delivered',
            'completed_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', deliveryId);
      
      // Make driver available again
      final user = _supabase.auth.currentUser;
      if (user != null) {
        await _supabase
            .from('driver_profiles')
            .update({'is_available': true})
            .eq('id', user.id);
      }
    } catch (e) {
      throw Exception('Failed to complete delivery: $e');
    }
  }
}
