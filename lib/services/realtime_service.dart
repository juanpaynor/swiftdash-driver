import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import '../models/delivery.dart';
import '../widgets/improved_delivery_offer_modal.dart';

class OptimizedRealtimeService {
  final SupabaseClient _supabase = Supabase.instance.client;
  
  // Channel management
  final Map<String, RealtimeChannel> _activeChannels = {};
  
  // Stream controllers for real-time data
  final _newDeliveriesController = StreamController<Delivery>.broadcast();
  final _deliveryUpdatesController = StreamController<Delivery>.broadcast();
  final _driverStatusController = StreamController<Map<String, dynamic>>.broadcast();
  final _offerModalController = StreamController<Delivery>.broadcast();
  final _locationUpdatesController = StreamController<Map<String, dynamic>>.broadcast();
  
  // Public streams
  Stream<Delivery> get newDeliveries => _newDeliveriesController.stream;
  Stream<Delivery> get deliveryUpdates => _deliveryUpdatesController.stream;
  Stream<Map<String, dynamic>> get driverStatusUpdates => _driverStatusController.stream;
  Stream<Delivery> get offerModalStream => _offerModalController.stream;
  Stream<Map<String, dynamic>> get locationUpdates => _locationUpdatesController.stream;
  
  // Active offer tracking
  Delivery? _currentOffer;
  Timer? _offerTimeoutTimer;
  
  String? _currentDriverId;
  String? _currentDeliveryId;

  // Helper to read authenticated user id from Supabase client
  String? get _authUserId => _supabase.auth.currentUser?.id;

  // 🔹 1. GRANULAR CHANNEL SUBSCRIPTIONS
  
  /// Subscribe to deliveries assigned specifically to this driver
  Future<void> subscribeToDriverDeliveries(String driverId) async {
  _currentDriverId = driverId;
    final channelName = 'driver-deliveries-$driverId';
    
    // Clean up existing subscription
    await _unsubscribeFromChannel(channelName);
    
    final channel = _supabase.channel(channelName);
    
    // Listen for deliveries assigned to this driver
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'deliveries',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'driver_id',
        value: driverId,
      ),
      callback: (payload) => _handleDriverDeliveryUpdate(payload),
    );
    
    // Listen for new pending deliveries (potential offers)
    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'deliveries',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'status',
        value: 'pending',
      ),
      callback: (payload) => _handleNewDeliveryOffer(payload),
    );
    
    await channel.subscribe();
    _activeChannels[channelName] = channel;
    
    print('🔥 Subscribed to driver deliveries: $channelName');
  }

  /// Subscribe to specific delivery updates (for active delivery tracking)
  Future<void> subscribeToSpecificDelivery(String deliveryId) async {
    _currentDeliveryId = deliveryId;
    final channelName = 'delivery-$deliveryId';
    
    // Clean up existing subscription
    await _unsubscribeFromChannel(channelName);
    
    final channel = _supabase.channel(channelName);
    
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'deliveries',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id',
        value: deliveryId,
      ),
      callback: (payload) => _handleSpecificDeliveryUpdate(payload),
    );
    
    await channel.subscribe();
    _activeChannels[channelName] = channel;
    
    print('🔥 Subscribed to specific delivery: $channelName');
  }

  // 🔹 2. GPS LOCATION BROADCASTING (NON-PERSISTENT)
  
  /// Start broadcasting driver location (does NOT store in database)
  void startLocationBroadcast(String deliveryId) {
    final channelName = 'driver-location-$deliveryId';
    
    if (_activeChannels.containsKey(channelName)) {
      print('📍 Location broadcast already active for delivery: $deliveryId');
      return;
    }
    
    final channel = _supabase.channel(channelName);
    channel.subscribe();
    _activeChannels[channelName] = channel;
    
    print('📍 Started location broadcast for delivery: $deliveryId');
  }
  
  /// Broadcast current location (temporary, not stored in DB)
  Future<void> broadcastLocation({
    required String deliveryId,
    required double latitude,
    required double longitude,
    required double speedKmH,
    double? heading,
    double? accuracy,
  }) async {
    final channelName = 'driver-location-$deliveryId';
    final channel = _activeChannels[channelName];
    
    if (channel == null) {
      print('⚠️ No location broadcast channel for delivery: $deliveryId');
      return;
    }
    
    final locationData = {
      'driver_id': _currentDriverId,
      'delivery_id': deliveryId,
      'latitude': latitude,
      'longitude': longitude,
      'speed_kmh': speedKmH,
      'heading': heading,
      'accuracy': accuracy,
      'timestamp': DateTime.now().toIso8601String(),
    };
    
    // 🔥 BROADCAST VIA WEBSOCKET - This is the key optimization!
    try {
      await channel.sendBroadcastMessage(
        event: 'location_update',
        payload: locationData,
      );
      print('📡 Location broadcasted via websocket for delivery: $deliveryId');
    } catch (e) {
      print('❌ Failed to broadcast location: $e');
    }
    
    // Emit locally so app components can react immediately
    _locationUpdatesController.add(locationData);

    // Optional: Update driver current status table (lightweight)
    await _updateDriverCurrentStatus(latitude, longitude, speedKmH);
  }

  /// Subscribe to driver location broadcasts (for customers)
  Future<void> subscribeToDriverLocation(String deliveryId) async {
    final channelName = 'driver-location-$deliveryId';
    
    if (_activeChannels.containsKey(channelName)) {
      print('📍 Already subscribed to location for delivery: $deliveryId');
      return;
    }
    
    final channel = _supabase.channel(channelName);
    
    // Listen for location broadcasts
    channel.onBroadcast(
      event: 'location_update',
      callback: (payload) {
        print('📍 Received driver location update: $payload');
        _locationUpdatesController.add(payload);
      },
    );
    
    await channel.subscribe();
    _activeChannels[channelName] = channel;
    
    print('📍 Subscribed to driver location broadcasts for delivery: $deliveryId');
  }

  /// Store location only for important events (pickup, delivery, etc.)
  Future<void> storeLocationForCriticalEvent({
    required String eventType,
    required String deliveryId,
    required double latitude,
    required double longitude,
  }) async {
    try {
      final driverId = _currentDriverId ?? _authUserId;
      if (driverId == null) {
        print('❌ Cannot store critical location: driver id unknown (not authenticated)');
        return;
      }

      await _supabase.from('driver_location_history').insert({
        'driver_id': driverId,
        'delivery_id': deliveryId,
        'latitude': latitude,
        'longitude': longitude,
        'event_type': eventType,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      print('📍 Stored critical location event: $eventType');
    } catch (e) {
      print('❌ Error storing critical location: $e');
    }
  }

  // 🔹 3. OPTIMIZED EVENT HANDLERS
  
  void _handleDriverDeliveryUpdate(PostgresChangePayload payload) {
    try {
      final delivery = Delivery.fromJson(payload.newRecord);
      print('🚛 Driver delivery update: ${delivery.id} -> ${delivery.status}');
      
      _deliveryUpdatesController.add(delivery);
      
      // Handle status-specific actions
      switch (delivery.status) {
        case DeliveryStatus.pending:
          // No immediate action for pending here
          break;
        case DeliveryStatus.driverAssigned:
          // Start tracking this specific delivery
          subscribeToSpecificDelivery(delivery.id);
          startLocationBroadcast(delivery.id);
          break;
        case DeliveryStatus.delivered:
          // Stop location broadcast for completed delivery
          _stopLocationBroadcast(delivery.id);
          break;
        default:
          // Other statuses handled elsewhere
          break;
      }
    } catch (e) {
      print('❌ Error handling driver delivery update: $e');
    }
  }
  
  void _handleNewDeliveryOffer(PostgresChangePayload payload) {
    try {
      final delivery = Delivery.fromJson(payload.newRecord);
      
      // Only show offers that are truly pending and not assigned yet
      if (delivery.status == DeliveryStatus.pending && delivery.driverId == null) {
        print('💰 New delivery offer available: ${delivery.id}');
        _handleNewOffer(delivery);
      }
    } catch (e) {
      print('❌ Error handling new delivery offer: $e');
    }
  }
  
  void _handleSpecificDeliveryUpdate(PostgresChangePayload payload) {
    try {
      final delivery = Delivery.fromJson(payload.newRecord);
      print('📦 Specific delivery update: ${delivery.id} -> ${delivery.status}');
      
      _deliveryUpdatesController.add(delivery);
      
      // Handle critical status changes
      if (delivery.status == DeliveryStatus.cancelled) {
        _stopLocationBroadcast(delivery.id);
        _unsubscribeFromChannel('delivery-${delivery.id}');
      }
    } catch (e) {
      print('❌ Error handling specific delivery update: $e');
    }
  }

  // 🔹 4. CRITICAL REALTIME EVENTS
  
  /// Handle new offer with modal trigger
  void _handleNewOffer(Delivery delivery) {
    // Cancel any existing offer
    if (_currentOffer != null) {
      _cancelCurrentOffer();
    }
    
    _currentOffer = delivery;
    _offerModalController.add(delivery);
    
    // Set timeout timer (5 minutes)
    _offerTimeoutTimer = Timer(const Duration(minutes: 5), () {
      _cancelCurrentOffer();
    });
    
    print('🔔 New offer modal triggered for delivery: ${delivery.id}');
  }

  /// Cancel current offer
  void _cancelCurrentOffer() {
    _offerTimeoutTimer?.cancel();
    _offerTimeoutTimer = null;
    _currentOffer = null;
  }
  
  /// Accept delivery offer (critical event - immediate DB update)
  Future<bool> acceptDeliveryOffer(String deliveryId, String driverId) async {
    try {
      print('✅ Accepting delivery offer: $deliveryId');
      
      // Critical event - immediate database update
      Map<String, dynamic> payload = {
        'status': 'driver_assigned',
        'driver_id': driverId,
        'assigned_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      try {
        await _supabase
            .from('deliveries')
            .update(payload)
            .eq('id', deliveryId)
            .eq('status', 'pending') // Only update if still pending
            .select()
            .maybeSingle();
      } catch (e) {
        // If the database doesn't have the assigned_at column (older schema), retry without it
        final errMsg = e.toString();
        print('⚠️ Accept attempt failed, will retry without assigned_at: $errMsg');
        if (errMsg.contains("assigned_at") || errMsg.contains("Could not find the 'assigned_at'")) {
          payload.remove('assigned_at');
          try {
            await _supabase
                .from('deliveries')
                .update(payload)
                .eq('id', deliveryId)
                .eq('status', 'pending')
                .select()
                .maybeSingle();
          } catch (e2) {
            print('❌ Retry accept without assigned_at also failed: $e2');
          }
        } else {
          // unknown error, rethrow to outer catch
          rethrow;
        }
      }

      // Read back the current delivery row to confirm the result
      try {
        final current = await _supabase
            .from('deliveries')
            .select('id,driver_id,status')
            .eq('id', deliveryId)
            .maybeSingle();

        print('🔎 Post-accept delivery state: $current');

        if (current != null && current['driver_id'] == driverId && (current['status'] == 'driver_assigned' || current['status'] == 'package_collected' || current['status'] == 'in_transit')) {
          print('✅ Successfully accepted delivery (confirmed by DB): $deliveryId');
          _cancelCurrentOffer();
          await subscribeToSpecificDelivery(deliveryId);
          startLocationBroadcast(deliveryId);
          return true;
        } else {
          print('⚠️ Delivery not assigned to this driver (DB shows ${current?['driver_id']} / status ${current?['status']})');
          return false;
        }
      } catch (e) {
        print('❌ Failed to verify delivery after accept attempt: $e');
        return false;
      }
    } catch (e) {
      print('❌ Error accepting delivery offer: $e');
      return false;
    }
  }
  
  /// Update delivery status (critical event - immediate DB update + location storage)
  Future<bool> updateDeliveryStatus(String deliveryId, String status, {
    double? latitude,
    double? longitude,
  }) async {
    try {
      print('📋 Updating delivery status: $deliveryId -> $status');
      
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
      
      // Critical database update
      await _supabase
          .from('deliveries')
          .update(updateData)
          .eq('id', deliveryId);
      
      // Store location for critical events
      if (latitude != null && longitude != null) {
        await storeLocationForCriticalEvent(
          eventType: status,
          deliveryId: deliveryId,
          latitude: latitude,
          longitude: longitude,
        );
      }
      
      print('✅ Successfully updated delivery status');
      return true;
    } catch (e) {
      print('❌ Error updating delivery status: $e');
      return false;
    }
  }

  // 🔹 5. LIGHTWEIGHT STATUS UPDATES
  
  /// Update driver current status (lightweight table, not full profile)
  Future<void> _updateDriverCurrentStatus(double latitude, double longitude, double speedKmH) async {
    try {
      final status = _determineDriverStatus(speedKmH);
      final driverId = _currentDriverId ?? _authUserId;
      if (driverId == null) {
        print('❌ Cannot update driver status: driver id unknown (not authenticated)');
        return;
      }

      await _supabase.from('driver_current_status').upsert({
        'driver_id': driverId,
        'current_latitude': latitude,
        'current_longitude': longitude,
        'status': status,
        'last_updated': DateTime.now().toIso8601String(),
        'current_delivery_id': _currentDeliveryId,
      });
    } catch (e) {
      print('❌ Error updating driver current status: $e');
    }
  }
  
  String _determineDriverStatus(double speedKmH) {
    if (_currentDeliveryId != null) {
      return 'delivering';
    } else if (speedKmH > 5) {
      return 'available';
    } else {
      return 'break';
    }
  }

  // 🔹 6. CHANNEL MANAGEMENT
  
  Future<void> _unsubscribeFromChannel(String channelName) async {
    final channel = _activeChannels[channelName];
    if (channel != null) {
      await channel.unsubscribe();
      _activeChannels.remove(channelName);
      print('🔌 Unsubscribed from channel: $channelName');
    }
  }
  
  void _stopLocationBroadcast(String deliveryId) {
    final channelName = 'driver-location-$deliveryId';
    _unsubscribeFromChannel(channelName);
    print('📍 Stopped location broadcast for delivery: $deliveryId');
  }

  // 🔹 7. LEGACY METHODS (Updated)
  
  /// Initialize realtime subscriptions (optimized)
  Future<void> initializeRealtimeSubscriptions(String driverId) async {
    try {
      print('🚀 Initializing optimized realtime subscriptions for driver: $driverId');
      
      // Subscribe to driver-specific deliveries only
      await subscribeToDriverDeliveries(driverId);
      
      print('✅ Optimized realtime subscriptions initialized successfully');
    } catch (e) {
      print('❌ Error initializing realtime subscriptions: $e');
      rethrow;
    }
  }
  
  /// Update driver online status (critical event)
  Future<void> updateDriverOnlineStatus(String driverId, bool isOnline) async {
    try {
      // Update in driver profiles (for admin queries)
      await _supabase
          .from('driver_profiles')
          .update({
            'is_online': isOnline,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', driverId);
      
      // Update in current status table
      await _supabase.from('driver_current_status').upsert({
        'driver_id': driverId,
        'status': isOnline ? 'available' : 'offline',
        'last_updated': DateTime.now().toIso8601String(),
      });
      
      print('📱 Updated driver online status: $isOnline');
    } catch (e) {
      print('❌ Error updating driver online status: $e');
    }
  }
  
  /// Get pending deliveries for driver
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
      print('❌ Error fetching pending deliveries: $e');
      return [];
    }
  }
  
  /// Get available delivery offers (limited scope)
  Future<List<Delivery>> getAvailableDeliveryOffers() async {
    try {
      final response = await _supabase
          .from('deliveries')
          .select('*')
          .eq('status', 'pending')
          .filter('driver_id', 'is', null) // Not assigned yet
          .order('created_at', ascending: true)
          .limit(5); // Limit to recent offers only
      
      return (response as List)
          .map((data) => Delivery.fromJson(data))
          .toList();
    } catch (e) {
      print('❌ Error fetching delivery offers: $e');
      return [];
    }
  }
  
  /// Show improved delivery offer modal
  static void showImprovedOfferModal(
    BuildContext context,
    Delivery delivery,
    Future<bool> Function(String deliveryId, String driverId) onAccept,
    String driverId,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      useSafeArea: false,
      builder: (context) => ImprovedDeliveryOfferModal(
        delivery: delivery,
        onAccept: () async {
          // call parent accept callback which returns true on success
          final ok = await onAccept(delivery.id, driverId);
          if (ok) {
            // close the modal when accept succeeded
            if (Navigator.of(context).canPop()) Navigator.of(context).pop();
          }
          return ok;
        },
        onDecline: () {
          Navigator.of(context).pop();
        },
      ),
    );
  }

  // 🔹 8. CLEANUP & DISPOSAL
  
  /// Clean up all subscriptions and resources
  Future<void> dispose() async {
    try {
      // Unsubscribe from all channels
      for (final channelName in _activeChannels.keys.toList()) {
        await _unsubscribeFromChannel(channelName);
      }
      
      // Cancel any active offer timer
      _offerTimeoutTimer?.cancel();
      
      // Close stream controllers
      await _newDeliveriesController.close();
      await _deliveryUpdatesController.close();
      await _driverStatusController.close();
      await _offerModalController.close();
      await _locationUpdatesController.close();
      
      print('🧹 Optimized realtime service disposed');
    } catch (e) {
      print('❌ Error disposing realtime service: $e');
    }
  }
}

// Backward compatibility
typedef RealtimeService = OptimizedRealtimeService;