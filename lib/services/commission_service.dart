import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Model for commission rate details
class CommissionDetails {
  final double commissionRate;
  final String rateSource; // 'default' or 'custom'
  final String? rateType; // 'top_performer', 'negotiated', etc.
  final DateTime? effectiveFrom;
  final DateTime? effectiveUntil;

  CommissionDetails({
    required this.commissionRate,
    required this.rateSource,
    this.rateType,
    this.effectiveFrom,
    this.effectiveUntil,
  });

  factory CommissionDetails.fromJson(Map<String, dynamic> json) {
    return CommissionDetails(
      commissionRate: (json['commission_rate'] as num).toDouble(),
      rateSource: json['rate_source'] as String,
      rateType: json['rate_type'] as String?,
      effectiveFrom: json['effective_from'] != null
          ? DateTime.parse(json['effective_from'])
          : null,
      effectiveUntil: json['effective_until'] != null
          ? DateTime.parse(json['effective_until'])
          : null,
    );
  }

  /// Calculate driver earnings from total price
  double calculateDriverEarnings(double totalPrice) {
    final commission = totalPrice * commissionRate;
    return totalPrice - commission;
  }

  /// Calculate platform commission from total price
  double calculateCommission(double totalPrice) {
    return totalPrice * commissionRate;
  }

  /// Convert commission rate to percentage (0.16 -> 16%)
  double get ratePercentage => commissionRate * 100;
}

/// Service for managing driver commission rates
class CommissionService {
  static const String _cacheKeyPrefix = 'commission_rate_';
  static const String _cacheTimestampPrefix = 'commission_timestamp_';
  static const Duration _cacheDuration = Duration(hours: 24);
  static const double _defaultCommissionRate = 0.16; // 16% default

  final SupabaseClient _supabase = Supabase.instance.client;
  
  // Polling for commission rate changes (more cost-effective than realtime subscriptions)
  Timer? _pollingTimer;
  String? _subscribedDriverId;
  CommissionDetails? _lastKnownRate;
  
  // Callback for when commission rate changes
  Function(CommissionDetails)? _onRateChanged;
  
  // Polling interval (check every 5 minutes)
  static const Duration _pollingInterval = Duration(minutes: 5);

  /// Get commission rate for a driver
  /// 
  /// First checks cache, then fetches from database if cache is expired
  /// Falls back to default 16% if no custom rate found
  Future<CommissionDetails> getCommissionRate(String driverId) async {
    try {
      // Check cache first
      final cachedRate = await _getCachedRate(driverId);
      if (cachedRate != null) {
        debugPrint('[CommissionService] Using cached commission rate for driver $driverId: ${cachedRate.ratePercentage}%');
        return cachedRate;
      }

      // Fetch from database
      debugPrint('[CommissionService] Fetching commission rate from database for driver $driverId');
      final details = await _fetchRateFromDatabase(driverId);

      // Cache the result
      await _cacheRate(driverId, details);

      return details;
    } catch (e) {
      debugPrint('[CommissionService] ERROR: Error fetching commission rate - $e');
      // Fallback to default rate
      return CommissionDetails(
        commissionRate: _defaultCommissionRate,
        rateSource: 'default',
      );
    }
  }

  /// Fetch commission rate from database
  Future<CommissionDetails> _fetchRateFromDatabase(String driverId) async {
    try {
      // Try to get custom rate for this driver
      final customRate = await _supabase
          .from('driver_commission_rates')
          .select('commission_rate, rate_type, effective_from, effective_until')
          .eq('driver_id', driverId)
          .eq('is_active', true)
          .maybeSingle();

      if (customRate != null) {
        // Check if rate is currently effective
        final now = DateTime.now();
        final effectiveFrom = customRate['effective_from'] != null
            ? DateTime.parse(customRate['effective_from'])
            : null;
        final effectiveUntil = customRate['effective_until'] != null
            ? DateTime.parse(customRate['effective_until'])
            : null;

        // Check if rate is within effective date range
        final isEffective = (effectiveFrom == null || now.isAfter(effectiveFrom)) &&
            (effectiveUntil == null || now.isBefore(effectiveUntil));

        if (isEffective) {
          debugPrint('[CommissionService] Found custom commission rate for driver $driverId: ${(customRate['commission_rate'] as num) * 100}%');
          return CommissionDetails(
            commissionRate: (customRate['commission_rate'] as num).toDouble(),
            rateSource: 'custom',
            rateType: customRate['rate_type'] as String?,
            effectiveFrom: effectiveFrom,
            effectiveUntil: effectiveUntil,
          );
        } else {
          debugPrint('[CommissionService] WARNING: Custom rate exists but not currently effective for driver $driverId');
        }
      }

      // No custom rate or not effective, get default rate
      final defaultRate = await _getDefaultRate();
      debugPrint('[CommissionService] Using default commission rate for driver $driverId: ${defaultRate * 100}%');

      return CommissionDetails(
        commissionRate: defaultRate,
        rateSource: 'default',
      );
    } catch (e) {
      debugPrint('[CommissionService] ERROR: Error fetching rate from database - $e');
      rethrow;
    }
  }

  /// Get default commission rate from platform settings
  Future<double> _getDefaultRate() async {
    try {
      final setting = await _supabase
          .from('platform_settings')
          .select('setting_value')
          .eq('setting_key', 'default_commission_rate')
          .maybeSingle();

      if (setting != null) {
        final value = setting['setting_value'] as Map<String, dynamic>;
        return (value['rate'] as num).toDouble();
      }
    } catch (e) {
      debugPrint('[CommissionService] ERROR: Error fetching default rate from platform_settings - $e');
    }

    // Fallback to hard-coded default
    return _defaultCommissionRate;
  }

  /// Calculate commission for a delivery
  Future<Map<String, dynamic>> calculateCommission({
    required String driverId,
    required double totalPrice,
    double tips = 0,
  }) async {
    final details = await getCommissionRate(driverId);
    
    final commissionAmount = details.calculateCommission(totalPrice);
    final driverEarnings = details.calculateDriverEarnings(totalPrice) + tips;

    return {
      'commission_rate': details.commissionRate,
      'commission_rate_percentage': details.ratePercentage,
      'commission_amount': commissionAmount,
      'driver_earnings': driverEarnings,
      'rate_source': details.rateSource,
      'rate_type': details.rateType,
    };
  }

  /// Cache commission rate locally
  Future<void> _cacheRate(String driverId, CommissionDetails details) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '$_cacheKeyPrefix$driverId';
      final timestampKey = '$_cacheTimestampPrefix$driverId';

      // Store rate and metadata as JSON string
      final cacheData = {
        'commission_rate': details.commissionRate,
        'rate_source': details.rateSource,
        'rate_type': details.rateType,
        'effective_from': details.effectiveFrom?.toIso8601String(),
        'effective_until': details.effectiveUntil?.toIso8601String(),
      };

      await prefs.setString(cacheKey, cacheData.toString());
      await prefs.setInt(timestampKey, DateTime.now().millisecondsSinceEpoch);

      debugPrint('[CommissionService] Cached commission rate for driver $driverId');
    } catch (e) {
      debugPrint('[CommissionService] ERROR: Error caching commission rate - $e');
    }
  }

  /// Get cached commission rate if not expired
  Future<CommissionDetails?> _getCachedRate(String driverId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '$_cacheKeyPrefix$driverId';
      final timestampKey = '$_cacheTimestampPrefix$driverId';

      final cachedData = prefs.getString(cacheKey);
      final timestamp = prefs.getInt(timestampKey);

      if (cachedData == null || timestamp == null) {
        return null;
      }

      // Check if cache is expired
      final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final now = DateTime.now();
      if (now.difference(cacheTime) > _cacheDuration) {
        debugPrint('[CommissionService] Cached commission rate expired for driver $driverId');
        return null;
      }

      // Parse cached data (simplified - in production use proper JSON parsing)
      // For now, we'll refetch instead of complex parsing
      return null;
    } catch (e) {
      debugPrint('[CommissionService] ERROR: Error reading cached commission rate - $e');
      return null;
    }
  }

  /// Clear cached commission rate for a driver
  Future<void> clearCache(String driverId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_cacheKeyPrefix$driverId');
      await prefs.remove('$_cacheTimestampPrefix$driverId');
      debugPrint('[CommissionService] Cleared cached commission rate for driver $driverId');
    } catch (e) {
      debugPrint('[CommissionService] ERROR: Error clearing commission cache - $e');
    }
  }

  /// Force refresh commission rate (bypasses cache)
  /// 
  /// Use this when driver manually refreshes or when you need immediate update
  /// This will also trigger the rate change callback if rate has changed
  Future<CommissionDetails> refreshCommissionRate(String driverId) async {
    await clearCache(driverId);
    final newRate = await getCommissionRate(driverId);
    
    // If polling is active and rate changed, notify listener
    if (_subscribedDriverId == driverId && _lastKnownRate != null) {
      final hasChanged = newRate.commissionRate != _lastKnownRate!.commissionRate ||
                        newRate.rateSource != _lastKnownRate!.rateSource;
      
      if (hasChanged && _onRateChanged != null) {
        _lastKnownRate = newRate;
        _onRateChanged!(newRate);
      }
    }
    
    return newRate;
  }

  /// Clear all cached commission rates
  Future<void> clearAllCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      
      for (final key in keys) {
        if (key.startsWith(_cacheKeyPrefix) || key.startsWith(_cacheTimestampPrefix)) {
          await prefs.remove(key);
        }
      }
      
      debugPrint('[CommissionService] Cleared all cached commission rates');
    } catch (e) {
      debugPrint('[CommissionService] ERROR: Error clearing all commission cache - $e');
    }
  }

  /// Start polling for commission rate changes
  /// 
  /// Checks every 5 minutes for rate updates - more cost-effective than realtime subscriptions
  /// Still provides near-real-time updates without consuming concurrent connections
  Future<void> startPollingForRateChanges(
    String driverId, 
    Function(CommissionDetails) onRateChanged,
  ) async {
    try {
      // Stop any existing polling
      stopPollingForRateChanges();

      debugPrint('[CommissionService] Starting to poll commission rate changes for driver $driverId (every ${_pollingInterval.inMinutes} minutes)');

      _subscribedDriverId = driverId;
      _onRateChanged = onRateChanged;

      // Get initial rate
      _lastKnownRate = await getCommissionRate(driverId);

      // Start periodic polling
      _pollingTimer = Timer.periodic(_pollingInterval, (timer) async {
        await _checkForRateChanges(driverId);
      });

      debugPrint('[CommissionService] Successfully started polling for commission rate changes');
    } catch (e) {
      debugPrint('[CommissionService] ERROR: Error starting polling for commission rate changes - $e');
    }
  }

  /// Check if commission rate has changed
  Future<void> _checkForRateChanges(String driverId) async {
    try {
      debugPrint('[CommissionService] Checking for commission rate changes for driver $driverId');

      // Fetch fresh rate from database (bypass cache)
      final currentRate = await _fetchRateFromDatabase(driverId);

      // Compare with last known rate
      if (_lastKnownRate != null) {
        final hasChanged = currentRate.commissionRate != _lastKnownRate!.commissionRate ||
                          currentRate.rateSource != _lastKnownRate!.rateSource;

        if (hasChanged) {
          debugPrint('[CommissionService] Commission rate changed: ${_lastKnownRate!.ratePercentage}% → ${currentRate.ratePercentage}%');

          // Clear cache
          await clearCache(driverId);

          // Update cache with new rate
          await _cacheRate(driverId, currentRate);

          // Update last known rate
          _lastKnownRate = currentRate;

          // Notify listeners
          if (_onRateChanged != null) {
            _onRateChanged!(currentRate);
          }
        }
      } else {
        // First check, just store the rate
        _lastKnownRate = currentRate;
      }
    } catch (e) {
      debugPrint('[CommissionService] ERROR: Error checking for commission rate changes - $e');
    }
  }

  /// Stop polling for commission rate changes
  void stopPollingForRateChanges() {
    if (_pollingTimer != null) {
      _pollingTimer!.cancel();
      debugPrint('[CommissionService] Stopped polling for commission rate changes');
      
      _pollingTimer = null;
      _subscribedDriverId = null;
      _lastKnownRate = null;
      _onRateChanged = null;
    }
  }

  /// Dispose resources (call when service is no longer needed)
  Future<void> dispose() async {
    stopPollingForRateChanges();
  }
}
