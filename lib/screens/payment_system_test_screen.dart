// TEST: Payment Method and Earnings System
// Run this in the Driver App to test the new payment-aware earnings system

import 'package:flutter/material.dart';
import '../services/driver_earnings_service.dart';
import '../services/cash_remittance_service.dart';
import '../models/cash_remittance.dart';
import '../core/supabase_config.dart';

class PaymentSystemTestScreen extends StatefulWidget {
  const PaymentSystemTestScreen({super.key});

  @override
  State<PaymentSystemTestScreen> createState() => _PaymentSystemTestScreenState();
}

class _PaymentSystemTestScreenState extends State<PaymentSystemTestScreen> {
  final DriverEarningsService _earningsService = DriverEarningsService();
  final CashRemittanceService _remittanceService = CashRemittanceService();
  
  bool _isLoading = false;
  String _testResults = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment System Test'),
        backgroundColor: SwiftDashColors.darkBlue,
        foregroundColor: SwiftDashColors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Test buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : () => _testCashPayment(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SwiftDashColors.warningOrange,
                      foregroundColor: SwiftDashColors.white,
                    ),
                    child: const Text('Test Cash Payment'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : () => _testCardPayment(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SwiftDashColors.successGreen,
                      foregroundColor: SwiftDashColors.white,
                    ),
                    child: const Text('Test Card Payment'),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Test remittance
            ElevatedButton(
              onPressed: _isLoading ? null : () => _testCashRemittance(),
              style: ElevatedButton.styleFrom(
                backgroundColor: SwiftDashColors.lightBlue,
                foregroundColor: SwiftDashColors.white,
              ),
              child: const Text('Test Cash Remittance System'),
            ),
            
            const SizedBox(height: 16),
            
            // Clear results
            ElevatedButton(
              onPressed: () => setState(() => _testResults = ''),
              child: const Text('Clear Results'),
            ),
            
            const SizedBox(height: 16),
            
            // Results display
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _testResults.isEmpty ? 'Test results will appear here...' : _testResults,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: _testResults.isEmpty ? Colors.grey : Colors.black,
                    ),
                  ),
                ),
              ),
            ),
            
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _testCashPayment() async {
    setState(() => _isLoading = true);
    
    try {
      _addResult('🧪 TESTING CASH PAYMENT (COD)');
      _addResult('================================');
      
      // Mock delivery data
      const driverId = 'test-driver-id';
      final deliveryId = 'test-delivery-cash-${DateTime.now().millisecondsSinceEpoch}';
      const totalPrice = 150.0;
      const tips = 25.0;
      
      _addResult('📦 Mock Delivery:');
      _addResult('   Driver ID: $driverId');
      _addResult('   Delivery ID: $deliveryId');
      _addResult('   Total Price: ₱$totalPrice');
      _addResult('   Tips: ₱$tips');
      _addResult('   Payment Method: Cash (COD)');
      
      // Record earnings
      final success = await _earningsService.recordDeliveryEarnings(
        driverId: driverId,
        deliveryId: deliveryId,
        totalPrice: totalPrice,
        paymentMethod: PaymentMethod.cash,
        tips: tips,
      );
      
      if (success) {
        _addResult('✅ Cash payment earnings recorded successfully!');
        _addResult('💰 Platform Commission (16%): ₱${(totalPrice * 0.16).toStringAsFixed(2)}');
        _addResult('💵 Driver Net Earnings: ₱${(totalPrice * 0.84 + tips).toStringAsFixed(2)}');
        _addResult('⏰ Remittance Required: YES (24 hours)');
        _addResult('🏦 Cash Balance Updated: Driver must remit ₱${(totalPrice * 0.16).toStringAsFixed(2)}');
      } else {
        _addResult('❌ Failed to record cash payment earnings');
      }
      
    } catch (e) {
      _addResult('💥 Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
    
    _addResult('\n');
  }

  Future<void> _testCardPayment() async {
    setState(() => _isLoading = true);
    
    try {
      _addResult('🧪 TESTING CARD PAYMENT (Digital)');
      _addResult('===================================');
      
      // Mock delivery data  
      const driverId = 'test-driver-id';
      final deliveryId = 'test-delivery-card-${DateTime.now().millisecondsSinceEpoch}';
      const totalPrice = 200.0;
      const tips = 30.0;
      
      _addResult('📦 Mock Delivery:');
      _addResult('   Driver ID: $driverId');
      _addResult('   Delivery ID: $deliveryId');
      _addResult('   Total Price: ₱$totalPrice');
      _addResult('   Tips: ₱$tips');
      _addResult('   Payment Method: Card (Digital)');
      
      // Record earnings
      final success = await _earningsService.recordDeliveryEarnings(
        driverId: driverId,
        deliveryId: deliveryId,
        totalPrice: totalPrice,
        paymentMethod: PaymentMethod.card,
        tips: tips,
      );
      
      if (success) {
        _addResult('✅ Card payment earnings recorded successfully!');
        _addResult('💳 Platform Commission (16%): ₱${(totalPrice * 0.16).toStringAsFixed(2)} (Auto-deducted)');
        _addResult('💰 Driver Net Earnings: ₱${(totalPrice * 0.84 + tips).toStringAsFixed(2)} (To PayMaya)');
        _addResult('⏰ Remittance Required: NO (Digital payment)');
        _addResult('🏦 Instant Payout: Funds sent to driver PayMaya wallet');
      } else {
        _addResult('❌ Failed to record card payment earnings');
      }
      
    } catch (e) {
      _addResult('💥 Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
    
    _addResult('\n');
  }

  Future<void> _testCashRemittance() async {
    setState(() => _isLoading = true);
    
    try {
      _addResult('🧪 TESTING CASH REMITTANCE SYSTEM');
      _addResult('==================================');
      
      const driverId = 'test-driver-id';
      
      // Get cash balance
      final balance = await _remittanceService.getCashBalance(driverId);
      
      if (balance != null) {
        _addResult('💵 Current Cash Balance:');
        _addResult('   Total Cash: ₱${balance.currentBalance.toStringAsFixed(2)}');
        _addResult('   Pending Remittance: ₱${balance.pendingRemittance.toStringAsFixed(2)}');
        _addResult('   Hours Until Due: ${balance.hoursUntilDue}');
        _addResult('   Is Overdue: ${balance.isRemittanceOverdue ? "YES ⚠️" : "NO ✅"}');
        
        // Test remittance request
        if (balance.pendingRemittance > 0) {
          _addResult('\n🔄 Testing Remittance Request...');
          final remittanceSuccess = await _remittanceService.requestRemittance(
            driverId, 
            balance.pendingRemittance
          );
          
          if (remittanceSuccess) {
            _addResult('✅ Remittance request submitted successfully!');
            _addResult('📤 Amount: ₱${balance.pendingRemittance.toStringAsFixed(2)}');
            _addResult('🏦 Status: Pending PayMaya transfer');
          } else {
            _addResult('❌ Remittance request failed');
          }
        } else {
          _addResult('ℹ️ No pending remittance required');
        }
      } else {
        _addResult('ℹ️ No cash balance record found (no COD deliveries yet)');
      }
      
    } catch (e) {
      _addResult('💥 Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
    
    _addResult('\n');
  }

  void _addResult(String message) {
    setState(() {
      _testResults += '$message\n';
    });
  }
}