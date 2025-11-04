import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/delivery_stop.dart';
import '../models/cash_remittance.dart';
import 'driver_earnings_service.dart';
import 'ably_service.dart';

/// Service for managing delivery stops in multi-stop deliveries
class DeliveryStopService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final AblyService _ablyService = AblyService();
  
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
      // Get stop details BEFORE update
      final stopBefore = await _supabase
          .from('delivery_stops')
          .select()
          .eq('id', stopId)
          .single();
      
      // Update database
      await _supabase
          .from('delivery_stops')
          .update({
            'status': 'in_progress',
            'arrived_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', stopId);
      
      // Publish to Ably for customer app
      await _ablyService.publishStopUpdate(
        deliveryId: stopBefore['delivery_id'],
        stopId: stopId,
        stopNumber: stopBefore['stop_number'],
        stopType: stopBefore['stop_type'],
        status: 'in_progress',
      );
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
      // Get stop details BEFORE update
      final stopBefore = await _supabase
          .from('delivery_stops')
          .select()
          .eq('id', stopId)
          .single();
      
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
      
      // Publish to Ably for customer app
      await _ablyService.publishStopUpdate(
        deliveryId: deliveryId,
        stopId: stopId,
        stopNumber: stopBefore['stop_number'],
        stopType: stopBefore['stop_type'],
        status: 'completed',
        proofPhotoUrl: proofPhotoUrl,
        completionNotes: completionNotes,
      );
      
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
      // Get stop details BEFORE update
      final stopBefore = await _supabase
          .from('delivery_stops')
          .select()
          .eq('id', stopId)
          .single();
      
      // Update database
      await _supabase
          .from('delivery_stops')
          .update({
            'status': 'failed',
            'completion_notes': reason,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', stopId);
      
      // Publish to Ably for customer app
      await _ablyService.publishStopUpdate(
        deliveryId: stopBefore['delivery_id'],
        stopId: stopId,
        stopNumber: stopBefore['stop_number'],
        stopType: stopBefore['stop_type'],
        status: 'failed',
        completionNotes: reason,
      );
    } catch (e) {
      throw Exception('Failed to mark stop as failed: $e');
    }
  }
  
  /// Complete the entire delivery
  Future<void> _completeDelivery(String deliveryId) async {
    try {
      // Get delivery details for earnings calculation
      final deliveryResponse = await _supabase
          .from('deliveries')
          .select('driver_id, total_price, payment_method, tip_amount, vehicle_type_id, distance_km')
          .eq('id', deliveryId)
          .single();
      
      final driverId = deliveryResponse['driver_id'] as String;
      final totalPrice = (deliveryResponse['total_price'] as num).toDouble();
      final paymentMethodStr = deliveryResponse['payment_method'] as String?;
      final tipAmount = (deliveryResponse['tip_amount'] as num?)?.toDouble() ?? 0.0;
      
      // Parse payment method
      PaymentMethod paymentMethod;
      try {
        paymentMethod = PaymentMethod.values.firstWhere(
          (e) => e.toString().split('.').last == paymentMethodStr,
          orElse: () => PaymentMethod.cash,
        );
      } catch (e) {
        paymentMethod = PaymentMethod.cash;
      }
      
      // Record earnings BEFORE marking complete
      final earningsService = DriverEarningsService();
      await earningsService.recordDeliveryEarnings(
        driverId: driverId,
        deliveryId: deliveryId,
        totalPrice: totalPrice,
        paymentMethod: paymentMethod,
        tips: tipAmount,
      );
      
      // ⭐ Use fleet-safe helper function (Added Nov 3, 2025)
      // This handles: delivery completion, driver status reset, and fleet vehicle reset
      await _supabase.rpc(
        'complete_delivery_safe',
        params: {
          'p_delivery_id': deliveryId,
          'p_driver_id': driverId,
        },
      );
      
      print('✅ Delivery completed and earnings recorded: ₱$totalPrice');
    } catch (e) {
      print('Error completing delivery: $e');
      throw Exception('Failed to complete delivery: $e');
    }
  }
}
