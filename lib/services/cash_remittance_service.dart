import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/cash_balance.dart';
import '../models/cash_remittance.dart';

class CashRemittanceService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Get driver's current cash balance
  Future<CashBalance?> getCashBalance(String driverId) async {
    try {
      final response = await _supabase
          .from('driver_cash_balances')
          .select('*')
          .eq('driver_id', driverId)
          .maybeSingle();

      if (response != null) {
        return CashBalance.fromJson(response);
      }
      return null;
    } catch (e) {
      print('Error getting cash balance: $e');
      return null;
    }
  }

  // Get pending remittances for driver
  Future<List<CashRemittance>> getPendingRemittances(String driverId) async {
    try {
      final response = await _supabase
          .from('cash_remittances')
          .select('*')
          .eq('driver_id', driverId)
          .inFilter('status', ['pending', 'processing'])
          .order('created_at', ascending: false);

      return (response as List)
          .map((data) => CashRemittance.fromJson(data))
          .toList();
    } catch (e) {
      print('Error getting pending remittances: $e');
      return [];
    }
  }

  // Get all remittances for driver (history)
  Future<List<CashRemittance>> getRemittanceHistory(String driverId, {int limit = 50}) async {
    try {
      final response = await _supabase
          .from('cash_remittances')
          .select('*')
          .eq('driver_id', driverId)
          .order('created_at', ascending: false)
          .limit(limit);

      return (response as List)
          .map((data) => CashRemittance.fromJson(data))
          .toList();
    } catch (e) {
      print('Error getting remittance history: $e');
      return [];
    }
  }

  // Request cash remittance (mock for now - will integrate with PayMaya later)
  Future<bool> requestRemittance(String driverId, double amount) async {
    try {
      // Get cash balance to validate
      final balance = await getCashBalance(driverId);
      if (balance == null || balance.pendingRemittance < amount) {
        print('Insufficient pending remittance balance');
        return false;
      }

      // Get all earnings that require remittance
      final earningsResponse = await _supabase
          .from('driver_earnings')
          .select('id')
          .eq('driver_id', driverId)
          .eq('is_remittance_required', true)
          .isFilter('remittance_id', null); // Only unprocessed earnings

      final earningsIds = (earningsResponse as List)
          .map((e) => e['id'] as String)
          .toList();

      // Create remittance record
      final remittanceResponse = await _supabase
          .from('cash_remittances')
          .insert({
            'driver_id': driverId,
            'amount': amount,
            'status': 'pending',
            'earnings_ids': earningsIds,
          })
          .select()
          .single();

      final remittanceId = remittanceResponse['id'] as String;

      // Update earnings records to link to this remittance
      await _supabase
          .from('driver_earnings')
          .update({'remittance_id': remittanceId})
          .inFilter('id', earningsIds);

      // Update cash balance
      await _supabase
          .from('driver_cash_balances')
          .update({
            'pending_remittance': balance.pendingRemittance - amount,
            'last_remittance_date': DateTime.now().toIso8601String(),
            'next_remittance_due': DateTime.now().add(const Duration(hours: 24)).toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('driver_id', driverId);

      print('Remittance requested: ₱$amount for driver $driverId (ID: $remittanceId)');
      return true;
    } catch (e) {
      print('Error requesting remittance: $e');
      return false;
    }
  }

  // Check for overdue remittances
  Future<List<CashRemittance>> getOverdueRemittances(String driverId) async {
    try {
      final response = await _supabase
          .from('cash_remittances')
          .select('*')
          .eq('driver_id', driverId)
          .eq('status', 'pending')
          .lt('created_at', DateTime.now().subtract(const Duration(hours: 24)).toIso8601String());

      return (response as List)
          .map((data) => CashRemittance.fromJson(data))
          .toList();
    } catch (e) {
      print('Error getting overdue remittances: $e');
      return [];
    }
  }

  // Check if driver has overdue cash remittances
  Future<bool> hasOverdueRemittances(String driverId) async {
    final balance = await getCashBalance(driverId);
    if (balance == null) return false;
    
    return balance.isRemittanceOverdue && balance.pendingRemittance > 0;
  }

  // Get total pending remittance amount
  Future<double> getTotalPendingRemittance(String driverId) async {
    final balance = await getCashBalance(driverId);
    return balance?.pendingRemittance ?? 0.0;
  }

  // Mock PayMaya integration - will implement later
  Future<bool> processRemittancePayment(String remittanceId) async {
    try {
      // TODO: Integrate with PayMaya API
      
      // For now, just update status to processing
      await _supabase
          .from('cash_remittances')
          .update({
            'status': 'processing',
            'processed_at': DateTime.now().toIso8601String(),
          })
          .eq('id', remittanceId);

      // Simulate processing delay (remove in production)
      await Future.delayed(const Duration(seconds: 2));

      // Mark as completed (mock success)
      await _supabase
          .from('cash_remittances')
          .update({
            'status': 'completed',
            'completed_at': DateTime.now().toIso8601String(),
            'paymaya_transaction_id': 'MOCK_${DateTime.now().millisecondsSinceEpoch}',
          })
          .eq('id', remittanceId);

      print('Mock remittance processed successfully: $remittanceId');
      return true;
    } catch (e) {
      print('Error processing remittance: $e');
      
      // Mark as failed
      await _supabase
          .from('cash_remittances')
          .update({
            'status': 'failed',
            'failure_reason': 'Payment processing failed: $e',
          })
          .eq('id', remittanceId);
      
      return false;
    }
  }
}