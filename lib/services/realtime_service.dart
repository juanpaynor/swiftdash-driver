import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import '../models/delivery.dart';
import '../widgets/improved_delivery_offer_modal.dart';
import 'optimized_location_service.dart';
import 'ably_service.dart';

class OptimizedRealtimeService {
  static final OptimizedRealtimeService _instance = OptimizedRealtimeService._internal();
  factory OptimizedRealtimeService() {
    print('🔥 RealtimeService singleton instance requested');
    return _instance;
  }
  OptimizedRealtimeService._internal() {
    print('🔥 RealtimeService singleton instance created');
  }
  
  final SupabaseClient _supabase = Supabase.instance.client;
  
  // Channel management
  final Map<String, RealtimeChannel> _activeChannels = {};
  
  // Stream controllers for real-time data (don't close in singleton!)
  late final _newDeliveriesController = StreamController<Delivery>.broadcast();
  late final _deliveryUpdatesController = StreamController<Delivery>.broadcast();
  late final _driverStatusController = StreamController<Map<String, dynamic>>.broadcast();
  late final _offerModalController = StreamController<Delivery>.broadcast();
  late final _locationUpdatesController = StreamController<Map<String, dynamic>>.broadcast();
  
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
    
    // Listen for delivery offers sent to this driver (using proper status name)
    channel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'deliveries',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'status',
        value: 'driver_offered',
      ),
      callback: (payload) => _handleNewDeliveryOffer(payload),
    );
    
    // ALSO listen for any delivery updates for this driver (broader filter for debugging)
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public', 
      table: 'deliveries',
      callback: (payload) {
        print('🔍 DEBUGGING: Any delivery update received for driver $driverId');
        print('🔍 Event: ${payload.eventType}');
        print('🔍 New record driver_id: ${payload.newRecord['driver_id']}');
        print('🔍 New record status: ${payload.newRecord['status']}');
        if (payload.newRecord['driver_id'] == driverId) {
          print('🎯 This update is for current driver!');
        }
      },
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
  
  /// Start broadcasting driver location (ABLY ONLY - Supabase WebSocket disabled)
  /// ✅ OPTIMIZED: Customer app uses Ably 'tracking:{deliveryId}', not Supabase channels
  Future<void> startLocationBroadcast(String deliveryId) async {
    print('📍 Starting GPS location tracking for delivery: $deliveryId');
    
    // ✅ FIX: Only start Ably location tracking (via DriverLocationService)
    // Supabase WebSocket channels are NOT used by customer app - disabled to save resources
    final driverId = _currentDriverId ?? _authUserId;
    if (driverId != null) {
      try {
        final locationService = OptimizedLocationService();
        await locationService.startDeliveryTracking(
          driverId: driverId,
          deliveryId: deliveryId,
        );
        print('✅ GPS location tracking started (Ably only) for delivery: $deliveryId');
      } catch (e) {
        print('❌ Failed to start GPS tracking: $e');
      }
    } else {
      print('⚠️ Cannot start GPS tracking: driver ID not available');
    }
  }
  
  /// Broadcast current location (DEPRECATED - now handled by Ably only)
  /// ✅ OPTIMIZED: This method kept for backward compatibility but does nothing
  /// Location is now broadcast via DriverLocationService → Ably 'tracking:{deliveryId}'
  Future<void> broadcastLocation({
    required String deliveryId,
    required double latitude,
    required double longitude,
    required double speedKmH,
    double? heading,
    double? accuracy,
    double? batteryLevel,
  }) async {
    // ✅ FIX: Supabase WebSocket broadcasting disabled - customer app uses Ably
    // Location is already being broadcast by OptimizedLocationService → Ably
    // This method is kept for backward compatibility but does nothing
    
    // Optional: Update driver current status table (lightweight)
    await _updateDriverCurrentStatus(latitude, longitude, speedKmH);
  }

  /// Check if WebSocket broadcasting is healthy (DEPRECATED)
  /// ✅ OPTIMIZED: Always returns true since we use Ably now
  bool isWebSocketHealthy(String deliveryId) {
    // Supabase WebSocket no longer used - return true for backward compatibility
    return true;
  }

  /// Subscribe to driver location broadcasts (DEPRECATED - for customers)
  /// ✅ OPTIMIZED: Customer app should use Ably 'tracking:{deliveryId}' instead
  Future<void> subscribeToDriverLocation(String deliveryId) async {
    print('⚠️ subscribeToDriverLocation called but Supabase WebSocket is disabled');
    print('⚠️ Customer app should use Ably channel: tracking:$deliveryId');
    // Do nothing - customer app should use Ably
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
          // ✅ FIX: Don't start location here - DriverFlowService handles it
          // Location tracking started by DriverFlowService.acceptDeliveryOffer()
          print('📍 Skipping location broadcast - handled by DriverFlowService');
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
      print('🚨 *** NEW DELIVERY OFFER PAYLOAD RECEIVED ***');
      print('🚨 Payload event: ${payload.eventType}');
      print('🚨 Payload new record: ${payload.newRecord}');
      
      final delivery = Delivery.fromJson(payload.newRecord);
      
      print('🚨 Parsed delivery: ${delivery.id}');
      print('🚨 Delivery status: ${delivery.status}');
      print('🚨 Delivery status enum: ${delivery.status.toString().split('.').last}');
      print('🚨 Delivery driver ID: ${delivery.driverId}');
      print('🚨 Current driver ID: $_currentDriverId');
      
      // Only show offers that are offered to the current driver
      if (delivery.status == DeliveryStatus.driverOffered && delivery.driverId == _currentDriverId) {
        print('💰 ✅ NEW DELIVERY OFFER FOR CURRENT DRIVER: ${delivery.id}');
        print('💰 Driver ID: ${delivery.driverId} matches current: $_currentDriverId');
        _handleNewOffer(delivery);
      } else {
        print('💰 ❌ DELIVERY OFFER NOT FOR CURRENT DRIVER:');
        print('   - Status: ${delivery.status} (expected: ${DeliveryStatus.driverOffered})');
        print('   - Status matches: ${delivery.status == DeliveryStatus.driverOffered}');
        print('   - Driver ID: ${delivery.driverId} (expected: $_currentDriverId)');
        print('   - Driver ID matches: ${delivery.driverId == _currentDriverId}');
      }
    } catch (e, stackTrace) {
      print('❌ Error handling new delivery offer: $e');
      print('❌ Payload: ${payload.newRecord}');
      print('❌ Stack trace: $stackTrace');
      
      // Try to identify which field is causing the issue
      if (e.toString().contains('Bad state: No element')) {
        print('🔍 Debugging individual fields from payload:');
        final record = payload.newRecord;
        print('  - id: ${record['id']}');
        print('  - status: ${record['status']}');
        print('  - driver_id: ${record['driver_id']}');
        print('  - customer_id: ${record['customer_id']}');
        print('  - pickup_address: ${record['pickup_address']}');
        print('  - delivery_address: ${record['delivery_address']}');
        print('  - package_description: ${record['package_description']}');
        print('  - total_price: ${record['total_price']}');
        print('  - total_amount: ${record['total_amount']}');
        print('  - created_at: ${record['created_at']}');
        print('  - updated_at: ${record['updated_at']}');
      }
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
    print('🚨 *** _handleNewOffer called for delivery: ${delivery.id} ***');
    
    // Cancel any existing offer
    if (_currentOffer != null) {
      print('🔔 Canceling existing offer: ${_currentOffer!.id}');
      _cancelCurrentOffer();
    }
    
    _currentOffer = delivery;
    
    print('🚨 *** ADDING DELIVERY TO OFFER MODAL STREAM ***');
    _offerModalController.add(delivery);
    print('🚨 *** DELIVERY ADDED TO STREAM - LISTENERS SHOULD RECEIVE IT ***');
    
    // Set timeout timer (5 minutes)
    _offerTimeoutTimer = Timer(const Duration(minutes: 5), () {
      print('⏰ Offer timeout for delivery: ${delivery.id}');
      _cancelCurrentOffer();
    });
    
    print('🔔 ✅ New offer modal triggered for delivery: ${delivery.id}');
  }

  /// Cancel current offer
  void _cancelCurrentOffer() {
    _offerTimeoutTimer?.cancel();
    _offerTimeoutTimer = null;
    _currentOffer = null;
  }
  
  /// Accept delivery offer (delegating to new optimized workflow)
  Future<bool> acceptDeliveryOffer(String deliveryId, String driverId) async {
    print('🔄 Delegating to new acceptance workflow for delivery: $deliveryId');
    return await acceptDeliveryOfferNew(deliveryId, driverId);
  }

  /// Decline delivery offer (using Edge Function as per customer app AI spec)
  Future<bool> declineDeliveryOffer(String deliveryId, String driverId) async {
    try {
      print('❌ Declining delivery offer: $deliveryId');
      
      // Use the dedicated accept_delivery Edge Function with accept: false
      final response = await _supabase.functions.invoke(
        'accept_delivery',
        body: {
          'deliveryId': deliveryId,
          'driverId': driverId,
          'accept': false,
        },
      );
      
      if (response.status == 200) {
        final data = response.data as Map<String, dynamic>;
        final success = data['ok'] == true;
        
        if (success) {
          print('✅ Delivery declined successfully: ${data['message']}');
          _cancelCurrentOffer();
          return true;
        } else {
          print('❌ Failed to decline delivery: ${data['message']}');
          return false;
        }
      } else {
        print('❌ Decline delivery API call failed with status: ${response.status}');
        return false;
      }
    } catch (e) {
      print('❌ Error declining delivery offer: $e');
      
      // Fallback - just cancel the current offer locally
      _cancelCurrentOffer();
      return true;
    }
  }
  
  /// Update delivery status following Ably-first architecture
  /// 
  /// **CRITICAL**: Per STATUS_UPDATE_FLOW_EXPLANATION.md:
  /// - ALL status changes publish to Ably (real-time customer updates)
  /// - Database ONLY updated for FINAL states: delivered, cancelled, failed
  /// - Intermediate statuses (going_to_pickup, at_pickup, package_collected, in_transit) are Ably-only
  Future<bool> updateDeliveryStatus(String deliveryId, String status, {
    double? latitude,
    double? longitude,
  }) async {
    try {
      print('📋 Updating delivery status: $deliveryId -> $status');
      
      // 🚀 STEP 1: ALWAYS publish to Ably for real-time customer updates
      final driverLocation = (latitude != null && longitude != null) 
        ? {'latitude': latitude, 'longitude': longitude}
        : null;
      
      await AblyService().publishStatusUpdate(
        deliveryId: deliveryId,
        status: status,
        driverLocation: driverLocation,
      );
      print('✅ Published status to Ably: $status');
      
      // 🗄️ STEP 2: Update database ONLY for final statuses
      final isFinalStatus = ['delivered', 'cancelled', 'failed'].contains(status);
      
      if (isFinalStatus) {
        print('💾 Final status detected - updating database: $status');
        
        final updateData = {
          'status': status,
          'updated_at': DateTime.now().toIso8601String(),
        };
        
        // Add completion timestamps for final statuses
        switch (status) {
          case 'delivered':
            updateData['delivered_at'] = DateTime.now().toIso8601String();
            updateData['completed_at'] = DateTime.now().toIso8601String();
            break;
          case 'cancelled':
            updateData['cancelled_at'] = DateTime.now().toIso8601String();
            break;
          case 'failed':
            updateData['failed_at'] = DateTime.now().toIso8601String();
            break;
        }
        
        // Persist to database
        await _supabase
            .from('deliveries')
            .update(updateData)
            .eq('id', deliveryId);
        
        print('✅ Database updated for final status: $status');
      } else {
        print('⏭️ Intermediate status - skipping database update (Ably-only): $status');
      }
      
      // 📍 Store location ONLY for final statuses (avoid unnecessary DB writes)
      // Intermediate status locations are already broadcasted via Ably real-time
      if (isFinalStatus && latitude != null && longitude != null) {
        await storeLocationForCriticalEvent(
          eventType: status,
          deliveryId: deliveryId,
          latitude: latitude,
          longitude: longitude,
        );
        print('💾 Stored final location for: $status');
      }
      
      print('✅ Successfully processed delivery status update: $status');
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
  
  /// Stop location broadcast (OPTIMIZED - only stops GPS tracking, no WebSocket cleanup needed)
  Future<void> _stopLocationBroadcast(String deliveryId) async {
    // ✅ FIX: No Supabase WebSocket channel to unsubscribe from - only stop GPS tracking
    
    // Stop GPS location tracking
    try {
      final locationService = OptimizedLocationService();
      if (locationService.currentDeliveryId == deliveryId) {
        await locationService.stopTracking();
        print('✅ Stopped GPS location tracking for delivery: $deliveryId');
      }
    } catch (e) {
      print('❌ Failed to stop GPS tracking: $e');
    }
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
      // Update only in driver_profiles table (single source of truth)
      await _supabase
          .from('driver_profiles')
          .update({
            'is_online': isOnline,
            'is_available': isOnline,  // Available when online, unavailable when offline
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', driverId);
      
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
          .inFilter('status', [
            'driver_assigned',
            'pickup_arrived',      // ✅ FIX: Include arrival at pickup
            'package_collected',
            'in_transit',
            'at_destination',      // ✅ FIX: Include arrival at delivery (though customer app uses in_transit)
          ])
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
    Future<bool> Function(String deliveryId, String driverId)? onDecline,
    String driverId,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      useSafeArea: true,  // ✅ FIX: Prevent parent screen widgets from bleeding through
      builder: (context) => ImprovedDeliveryOfferModal(
        delivery: delivery,
        onAccept: () async {
          try {
            print('🎯 Modal onAccept called - starting acceptance flow');
            // call parent accept callback which returns true on success
            final ok = await onAccept(delivery.id, driverId);
            
            if (ok) {
              print('✅ Acceptance successful - closing modal and navigating');
              // close the modal when accept succeeded
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
                
                // Navigate to active delivery screen after a brief delay
                Future.delayed(const Duration(milliseconds: 300), () {
                  if (Navigator.of(context).mounted) {
                    Navigator.of(context).pushReplacementNamed(
                      '/active-delivery',
                      arguments: delivery,
                    );
                  }
                });
              }
            } else {
              print('❌ Acceptance failed - offer may have been taken');
            }
            return ok;
          } catch (e) {
            print('❌ Error in modal onAccept: $e');
            return false;
          }
        },
        onDecline: () async {
          // call parent decline callback if provided
          if (onDecline != null) {
            final ok = await onDecline(delivery.id, driverId);
            print('🚨 Decline delivery result: $ok');
          }
          // Always close the modal after decline
          if (Navigator.of(context).canPop()) Navigator.of(context).pop();
        },
      ),
    );
  }

  // 🔹 8. NEW OFFER/ACCEPTANCE WORKFLOW
  
  // Guard against concurrent accept attempts
  static final Set<String> _processingAccepts = <String>{};

  /// Accept a delivery offer (NEW WORKFLOW)
  Future<bool> acceptDeliveryOfferNew(String deliveryId, String driverId) async {
    // Prevent concurrent accepts for the same delivery
    if (_processingAccepts.contains(deliveryId)) {
      print('⚠️ Already processing accept for delivery: $deliveryId');
      return false;
    }
    
    _processingAccepts.add(deliveryId);
    
    try {
      print('🚨 *** ACCEPTING DELIVERY OFFER (NEW WORKFLOW) ***');
      print('🚨 Delivery ID: $deliveryId');
      print('🚨 Driver ID: $driverId');
      
      // ⭐ Use fleet-safe helper function (Added Nov 3, 2025)
      // This handles: delivery status update, driver availability, and current_status
      final result = await _supabase.rpc(
        'accept_delivery_safe',
        params: {
          'p_delivery_id': deliveryId,
          'p_driver_id': driverId,
        },
      ).timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              print('❌ Accept delivery timeout after 10 seconds');
              throw TimeoutException('Database update timed out', const Duration(seconds: 10));
            },
          );
      
      if (result != null && result['success'] == true) {
        print('🚨 ✅ DELIVERY OFFER ACCEPTED SUCCESSFULLY');
        print('📱 Driver status updated to busy');
        
        // Cancel any current offer modal
        _cancelCurrentOffer();
        
        // Subscribe to specific delivery updates
        await subscribeToSpecificDelivery(deliveryId);
        
        // ✅ FIX: Don't start location here - DriverFlowService handles it
        // Location tracking is started by DriverFlowService.acceptDeliveryOffer()
        // to avoid duplicate location services fighting each other
        print('📍 Location tracking will be started by DriverFlowService');
        
        // ✅ Send 'going_to_pickup' status via Ably automatically (non-blocking)
        // This happens immediately after driver accepts, no need to wait for Navigate button
        AblyService().publishStatusUpdate(
          deliveryId: deliveryId,
          status: 'going_to_pickup',
          notes: 'Driver is heading to pickup location',
        ).catchError((e) => debugPrint('⚠️ Ably publish failed: $e'));
        debugPrint('📢 Sent going_to_pickup status via Ably (non-blocking, automatic after acceptance)');
        
        return true;
      } else {
        print('🚨 ❌ DELIVERY OFFER ACCEPTANCE FAILED - offer may have expired or been taken');
        return false;
      }
    } catch (e) {
      print('🚨 ❌ ERROR ACCEPTING DELIVERY OFFER: $e');
      return false;
    } finally {
      _processingAccepts.remove(deliveryId);
    }
  }
  
  /// Decline a delivery offer (NEW WORKFLOW)
  Future<bool> declineDeliveryOfferNew(String deliveryId, String driverId) async {
    try {
      print('🚨 *** DECLINING DELIVERY OFFER (NEW WORKFLOW) ***');
      print('🚨 Delivery ID: $deliveryId');
      print('🚨 Driver ID: $driverId');
      
      // CRITICAL FIX: Only decline if delivery is still offered to this driver
      final result = await _supabase
          .from('deliveries')
          .update({
            'status': 'pending',
            'driver_id': null,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', deliveryId)
          .eq('driver_id', driverId)
          .eq('status', 'driver_offered') // Only decline if still offered
          .select()
          .maybeSingle()
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              print('⚠️ Decline delivery timeout - delivery may have already changed');
              return null;
            },
          );
      
      if (result != null) {
        print('🚨 ✅ DELIVERY OFFER DECLINED SUCCESSFULLY - back to pending');
        
        // Cancel current offer modal
        _cancelCurrentOffer();
        
        return true;
      } else {
        print('🚨 ❌ DELIVERY OFFER DECLINE FAILED - offer may have expired');
        return false;
      }
    } catch (e) {
      print('🚨 ❌ ERROR DECLINING DELIVERY OFFER: $e');
      return false;
    }
  }

  // 🔹 9. CLEANUP & DISPOSAL
  
  /// Clean up channels for a specific delivery (call when delivery is complete)
  Future<void> cleanupDeliveryChannels(String deliveryId) async {
    try {
      final channelsToRemove = <String>[];
      
      // Find all channels related to this delivery
      for (final channelName in _activeChannels.keys) {
        if (channelName.contains(deliveryId)) {
          channelsToRemove.add(channelName);
        }
      }
      
      // Unsubscribe and remove each channel
      for (final channelName in channelsToRemove) {
        await _unsubscribeFromChannel(channelName);
        debugPrint('🧹 Cleaned up realtime channel: $channelName');
      }
      
      debugPrint('✅ Cleaned up ${channelsToRemove.length} realtime channel(s) for delivery: $deliveryId');
    } catch (e) {
      debugPrint('⚠️ Error cleaning up delivery channels: $e');
    }
  }
  
  /// Clean up all subscriptions and resources
  Future<void> dispose() async {
    try {
      // Unsubscribe from all channels
      for (final channelName in _activeChannels.keys.toList()) {
        await _unsubscribeFromChannel(channelName);
      }
      
      // Cancel any active offer timer
      _offerTimeoutTimer?.cancel();
      
      // 🚨 DON'T CLOSE STREAM CONTROLLERS IN SINGLETON!
      // They need to persist for the lifetime of the app
      // Closing them prevents listeners from receiving future events
      print('🧹 Optimized realtime service channels unsubscribed (stream controllers kept alive)');
    } catch (e) {
      print('❌ Error disposing realtime service: $e');
    }
  }
}

// Backward compatibility
typedef RealtimeService = OptimizedRealtimeService;