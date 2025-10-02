import 'package:supabase_flutter/supabase_flutter.dart';

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
  });

  factory DriverEarning.fromJson(Map<String, dynamic> json) {
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

  // Record earnings for a completed delivery
  Future<bool> recordDeliveryEarnings({
    required String driverId,
    required String deliveryId,
    required double baseEarnings,
    required double distanceEarnings,
    double surgeEarnings = 0.0,
    double tips = 0.0,
  }) async {
    try {
      final totalEarnings = baseEarnings + distanceEarnings + surgeEarnings + tips;
      final today = DateTime.now();
      
      await _supabase.from('driver_earnings').insert({
        'driver_id': driverId,
        'delivery_id': deliveryId,
        'base_earnings': baseEarnings,
        'distance_earnings': distanceEarnings,
        'surge_earnings': surgeEarnings,
        'tips': tips,
        'total_earnings': totalEarnings,
        'earnings_date': today.toIso8601String().split('T')[0],
      });

      print('Recorded earnings: ₱$totalEarnings for delivery $deliveryId');
      return true;
    } catch (e) {
      print('Error recording delivery earnings: $e');
      return false;
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