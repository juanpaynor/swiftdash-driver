import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/cash_remittance.dart';
import 'commission_service.dart';

class DriverEarning {
  final String id;
  final String driverId;
  final String deliveryId;
  final double baseEarnings;
  final double distanceEarnings;
  final double surgeEarnings;
  final double tips;
  final double totalEarnings;
  final DateTime earningsDate;
  final DateTime createdAt;
  final PaymentMethod paymentMethod;
  final double platformCommission;
  final double driverNetEarnings;
  final bool isRemittanceRequired;
  final DateTime? remittanceDeadline;
  final String? remittanceId;

  DriverEarning({
    required this.id,
    required this.driverId,
    required this.deliveryId,
    required this.baseEarnings,
    required this.distanceEarnings,
    required this.surgeEarnings,
    required this.tips,
    required this.totalEarnings,
    required this.earningsDate,
    required this.createdAt,
    required this.paymentMethod,
    required this.platformCommission,
    required this.driverNetEarnings,
    required this.isRemittanceRequired,
    this.remittanceDeadline,
    this.remittanceId,
  });

  factory DriverEarning.fromJson(Map<String, dynamic> json) {
    final paymentMethod = PaymentMethod.values.firstWhere(
      (e) => e.toString().split('.').last == (json['payment_method'] ?? 'cash'),
      orElse: () => PaymentMethod.cash,
    );
    
    return DriverEarning(
      id: json['id'] as String,
      driverId: json['driver_id'] as String,
      deliveryId: json['delivery_id'] as String,
      baseEarnings: (json['base_earnings'] as num).toDouble(),
      distanceEarnings: (json['distance_earnings'] as num).toDouble(),
      surgeEarnings: (json['surge_earnings'] as num).toDouble(),
      tips: (json['tips'] as num).toDouble(),
      totalEarnings: (json['total_earnings'] as num).toDouble(),
      earningsDate: DateTime.parse(json['earnings_date'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      paymentMethod: paymentMethod,
      platformCommission: (json['platform_commission'] as num?)?.toDouble() ?? 0.0,
      driverNetEarnings: (json['driver_net_earnings'] as num?)?.toDouble() ?? 0.0,
      isRemittanceRequired: json['is_remittance_required'] as bool? ?? paymentMethod.requiresRemittance,
      remittanceDeadline: json['remittance_deadline'] != null 
          ? DateTime.parse(json['remittance_deadline']) : null,
      remittanceId: json['remittance_id'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'driver_id': driverId,
      'delivery_id': deliveryId,
      'base_earnings': baseEarnings,
      'distance_earnings': distanceEarnings,
      'surge_earnings': surgeEarnings,
      'tips': tips,
      'total_earnings': totalEarnings,
      'earnings_date': earningsDate.toIso8601String().split('T')[0],
      'created_at': createdAt.toIso8601String(),
      'payment_method': paymentMethod.toString().split('.').last,
      'platform_commission': platformCommission,
      'driver_net_earnings': driverNetEarnings,
      'is_remittance_required': isRemittanceRequired,
      'remittance_deadline': remittanceDeadline?.toIso8601String(),
      'remittance_id': remittanceId,
    };
  }
}

class EarningsSummary {
  final double todayEarnings;
  final double weekEarnings;
  final double monthEarnings;
  final int todayDeliveries;
  final int weekDeliveries;
  final int monthDeliveries;
  final double averageEarningsPerDelivery;

  EarningsSummary({
    required this.todayEarnings,
    required this.weekEarnings,
    required this.monthEarnings,
    required this.todayDeliveries,
    required this.weekDeliveries,
    required this.monthDeliveries,
    required this.averageEarningsPerDelivery,
  });
}

class DriverEarningsService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final CommissionService _commissionService = CommissionService();

  // Record earnings for a completed delivery
  Future<bool> recordDeliveryEarnings({
    required String driverId,
    required String deliveryId,
    required double totalPrice,
    required PaymentMethod paymentMethod,
    double surgeEarnings = 0.0,
    double tips = 0.0,
  }) async {
    try {
      final today = DateTime.now();
      
      // Get dynamic commission rate from CommissionService
      final commissionData = await _commissionService.calculateCommission(
        driverId: driverId,
        totalPrice: totalPrice,
        tips: tips,
      );
      
      final platformCommissionRate = commissionData['commission_rate'] as double;
      final platformCommission = commissionData['commission_amount'] as double;
      final driverNetEarnings = commissionData['driver_earnings'] as double;
      final rateSource = commissionData['rate_source'] as String;
      
      // For COD, set remittance deadline to 24 hours from now
      final isRemittanceRequired = paymentMethod.requiresRemittance;
      final remittanceDeadline = isRemittanceRequired 
          ? today.add(const Duration(hours: 24))
          : null;
      
      // Split earnings for display purposes
      final baseEarnings = totalPrice * 0.5; // Base fare
      final distanceEarnings = totalPrice * 0.5; // Distance fare (simplified)
      final totalEarnings = baseEarnings + distanceEarnings + surgeEarnings + tips;
      
      await _supabase.from('driver_earnings').insert({
        'driver_id': driverId,
        'delivery_id': deliveryId,
        'base_earnings': baseEarnings,
        'distance_earnings': distanceEarnings,
        'surge_earnings': surgeEarnings,
        'tips': tips,
        'total_earnings': totalEarnings,
        'earnings_date': today.toIso8601String().split('T')[0],
        'payment_method': paymentMethod.toString().split('.').last,
        'platform_commission': platformCommission,
        'driver_net_earnings': driverNetEarnings,
        'commission_rate_applied': platformCommissionRate, // Track which rate was used
        'is_remittance_required': isRemittanceRequired,
        'remittance_deadline': remittanceDeadline?.toIso8601String(),
      });

      // For cash payments, update cash balance
      if (paymentMethod == PaymentMethod.cash) {
        await _updateCashBalance(driverId, totalPrice, platformCommission);
      }

      print('Recorded earnings: ₱$totalEarnings (${paymentMethod.displayName}) for delivery $deliveryId');
      print('Platform commission: ₱$platformCommission, Driver net: ₱$driverNetEarnings');
      
      return true;
    } catch (e) {
      print('Error recording delivery earnings: $e');
      return false;
    }
  }

  // Update driver's cash balance after COD delivery
  Future<void> _updateCashBalance(String driverId, double totalAmount, double platformCommission) async {
    try {
      // Get current cash balance
      final balanceResponse = await _supabase
          .from('driver_cash_balances')
          .select('*')
          .eq('driver_id', driverId)
          .maybeSingle();

      final now = DateTime.now();
      final nextRemittanceDue = now.add(const Duration(hours: 24));

      if (balanceResponse == null) {
        // Create new cash balance record
        await _supabase.from('driver_cash_balances').insert({
          'driver_id': driverId,
          'current_balance': totalAmount,
          'pending_remittance': platformCommission,
          'last_remittance_date': now.subtract(const Duration(days: 1)).toIso8601String(),
          'next_remittance_due': nextRemittanceDue.toIso8601String(),
        });
      } else {
        // Update existing balance
        final currentBalance = (balanceResponse['current_balance'] as num).toDouble();
        final currentPending = (balanceResponse['pending_remittance'] as num).toDouble();
        
        await _supabase.from('driver_cash_balances').update({
          'current_balance': currentBalance + totalAmount,
          'pending_remittance': currentPending + platformCommission,
          'next_remittance_due': nextRemittanceDue.toIso8601String(),
          'updated_at': now.toIso8601String(),
        }).eq('driver_id', driverId);
      }
      
      print('Updated cash balance for driver $driverId: +₱$totalAmount (pending remittance: +₱$platformCommission)');
    } catch (e) {
      print('Error updating cash balance: $e');
    }
  }

  // Get driver earnings summary
  Future<EarningsSummary> getEarningsSummary(String driverId) async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final weekStart = today.subtract(Duration(days: today.weekday - 1));
      final monthStart = DateTime(now.year, now.month, 1);

      // Get today's earnings
      final todayResponse = await _supabase
          .from('driver_earnings')
          .select('total_earnings')
          .eq('driver_id', driverId)
          .gte('earnings_date', today.toIso8601String().split('T')[0])
          .lt('earnings_date', today.add(const Duration(days: 1)).toIso8601String().split('T')[0]);

      final todayEarnings = (todayResponse as List)
          .fold<double>(0.0, (sum, item) => sum + (item['total_earnings'] as num).toDouble());
      final todayDeliveries = todayResponse.length;

      // Get week's earnings
      final weekResponse = await _supabase
          .from('driver_earnings')
          .select('total_earnings')
          .eq('driver_id', driverId)
          .gte('earnings_date', weekStart.toIso8601String().split('T')[0])
          .lt('earnings_date', today.add(const Duration(days: 1)).toIso8601String().split('T')[0]);

      final weekEarnings = (weekResponse as List)
          .fold<double>(0.0, (sum, item) => sum + (item['total_earnings'] as num).toDouble());
      final weekDeliveries = weekResponse.length;

      // Get month's earnings
      final monthResponse = await _supabase
          .from('driver_earnings')
          .select('total_earnings')
          .eq('driver_id', driverId)
          .gte('earnings_date', monthStart.toIso8601String().split('T')[0])
          .lt('earnings_date', today.add(const Duration(days: 1)).toIso8601String().split('T')[0]);

      final monthEarnings = (monthResponse as List)
          .fold<double>(0.0, (sum, item) => sum + (item['total_earnings'] as num).toDouble());
      final monthDeliveries = monthResponse.length;

      final averageEarningsPerDelivery = monthDeliveries > 0 ? monthEarnings / monthDeliveries : 0.0;

      return EarningsSummary(
        todayEarnings: todayEarnings,
        weekEarnings: weekEarnings,
        monthEarnings: monthEarnings,
        todayDeliveries: todayDeliveries,
        weekDeliveries: weekDeliveries,
        monthDeliveries: monthDeliveries,
        averageEarningsPerDelivery: averageEarningsPerDelivery,
      );
    } catch (e) {
      print('Error getting earnings summary: $e');
      return EarningsSummary(
        todayEarnings: 0.0,
        weekEarnings: 0.0,
        monthEarnings: 0.0,
        todayDeliveries: 0,
        weekDeliveries: 0,
        monthDeliveries: 0,
        averageEarningsPerDelivery: 0.0,
      );
    }
  }

  // Get detailed earnings history
  Future<List<DriverEarning>> getEarningsHistory({
    required String driverId,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 50,
  }) async {
    try {
      var query = _supabase
          .from('driver_earnings')
          .select('*')
          .eq('driver_id', driverId);

      if (startDate != null) {
        query = query.gte('earnings_date', startDate.toIso8601String().split('T')[0]);
      }

      if (endDate != null) {
        query = query.lte('earnings_date', endDate.toIso8601String().split('T')[0]);
      }

      final response = await query
          .order('earnings_date', ascending: false)
          .limit(limit);
      
      return (response as List)
          .map((data) => DriverEarning.fromJson(data))
          .toList();
    } catch (e) {
      print('Error getting earnings history: $e');
      return [];
    }
  }

  // Add tip to existing delivery earnings
  Future<bool> addTipToDelivery({
    required String deliveryId,
    required double tipAmount,
  }) async {
    try {
      // Get existing earnings record
      final existingResponse = await _supabase
          .from('driver_earnings')
          .select('*')
          .eq('delivery_id', deliveryId)
          .maybeSingle();

      if (existingResponse == null) {
        print('No earnings record found for delivery $deliveryId');
        return false;
      }

      final currentTips = (existingResponse['tips'] as num).toDouble();
      final newTips = currentTips + tipAmount;
      final currentTotal = (existingResponse['total_earnings'] as num).toDouble();
      final newTotal = currentTotal + tipAmount;

      // Update earnings record
      await _supabase
          .from('driver_earnings')
          .update({
            'tips': newTips,
            'total_earnings': newTotal,
          })
          .eq('delivery_id', deliveryId);

      print('Added tip: ₱$tipAmount to delivery $deliveryId');
      return true;
    } catch (e) {
      print('Error adding tip: $e');
      return false;
    }
  }

  // Get earnings by date range for dashboard charts
  Future<Map<String, double>> getEarningsByDateRange({
    required String driverId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final response = await _supabase
          .from('driver_earnings')
          .select('earnings_date, total_earnings')
          .eq('driver_id', driverId)
          .gte('earnings_date', startDate.toIso8601String().split('T')[0])
          .lte('earnings_date', endDate.toIso8601String().split('T')[0])
          .order('earnings_date', ascending: true);

      final Map<String, double> earningsByDate = {};
      
      for (final item in response as List) {
        final date = item['earnings_date'] as String;
        final earnings = (item['total_earnings'] as num).toDouble();
        
        earningsByDate[date] = (earningsByDate[date] ?? 0.0) + earnings;
      }

      return earningsByDate;
    } catch (e) {
      print('Error getting earnings by date range: $e');
      return {};
    }
  }

  // Calculate estimated earnings for delivery offer
  Future<double> calculateEstimatedEarnings({
    required String vehicleTypeId,
    required double distanceKm,
    double surgMultiplier = 1.0,
  }) async {
    try {
      // Get vehicle type pricing
      final vehicleTypeResponse = await _supabase
          .from('vehicle_types')
          .select('base_price, price_per_km')
          .eq('id', vehicleTypeId)
          .maybeSingle();

      if (vehicleTypeResponse == null) {
        print('Vehicle type not found: $vehicleTypeId');
        return 0.0;
      }

      final basePrice = (vehicleTypeResponse['base_price'] as num).toDouble();
      final pricePerKm = (vehicleTypeResponse['price_per_km'] as num).toDouble();

      final baseEarnings = basePrice * surgMultiplier;
      final distanceEarnings = (distanceKm * pricePerKm) * surgMultiplier;

      return baseEarnings + distanceEarnings;
    } catch (e) {
      print('Error calculating estimated earnings: $e');
      return 0.0;
    }
  }
}