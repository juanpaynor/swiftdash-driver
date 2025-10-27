import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';

/// Diagnostic service to test WebSocket location broadcasting
/// This is specifically to fix the customer app coordination issue
class LocationBroadcastDiagnostic {
  static const String testDeliveryId = 'd43a25b7-4724-407b-b096-30409a03d517';
  static const String testDriverId = '3d778cea-7f1e-40cd-b1f3-3f25bfb72bf9';
  
  final SupabaseClient _supabase = Supabase.instance.client;
  RealtimeChannel? _testChannel;
  Timer? _broadcastTimer;
  bool _isActive = false;

  /// Start diagnostic broadcasting (for testing with customer app)
  Future<void> startDiagnosticBroadcast() async {
    if (_isActive) {
      print('🧪 Diagnostic broadcast already running');
      return;
    }

    // Check if Supabase is initialized
    if (!Supabase.instance.isInitialized) {
      print('❌ DIAGNOSTIC ERROR: Supabase not initialized. Cannot start broadcasting.');
      return;
    }

    print('🧪 DIAGNOSTIC: Starting WebSocket location broadcast test');
    print('🧪 Using customer app test IDs:');
    print('🧪 Delivery ID: $testDeliveryId');
    print('🧪 Driver ID: $testDriverId');
    print('🧪 Channel: driver-location-$testDeliveryId');

    // 1. Setup WebSocket channel (exactly like customer app expects)
    final channelName = 'driver-location-$testDeliveryId';
    print('🧪 Channel name: $channelName');

    _testChannel = _supabase.channel(channelName);
    
    // 2. Subscribe to channel
    try {
      await _testChannel!.subscribe();
      print('✅ WebSocket channel subscribed successfully');
    } catch (e) {
      print('❌ Failed to subscribe to WebSocket channel: $e');
      return;
    }

    _isActive = true;

    // 3. Start broadcasting location every 15 seconds
    _broadcastTimer = Timer.periodic(Duration(seconds: 15), (timer) async {
      if (!_isActive) {
        timer.cancel();
        return;
      }

      await _broadcastTestLocation();
    });

    print('🧪 Diagnostic broadcast started - will send location updates every 15 seconds');
    print('🧪 Customer app should now see driver location updates!');
  }

  /// Broadcast a test location update
  Future<void> _broadcastTestLocation() async {
    if (_testChannel == null || !_isActive) return;

    try {
      // Get real GPS location
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        ).timeout(Duration(seconds: 10));
      } catch (e) {
        print('⚠️ Failed to get GPS location, using test coordinates: $e');
        // Use test coordinates in Manila area - create a mock position
        position = null; // We'll handle this case below
      }

      // Create payload exactly as customer app expects
      final locationPayload = {
        'driver_id': testDriverId,
        'delivery_id': testDeliveryId,
        'latitude': position?.latitude ?? 14.5995, // Manila test coordinates
        'longitude': position?.longitude ?? 120.9842,
        'speed_kmh': position?.speed != null ? (position!.speed * 3.6) : 15.0, // Convert m/s to km/h
        'heading': position?.heading ?? 45.0,
        'battery_level': 85.0, // Mock battery level
        'timestamp': DateTime.now().toIso8601String(),
      };

      // 🚨 THE KEY FIX - Use sendBroadcastMessage (not channel.on)
      await _testChannel!.sendBroadcastMessage(
        event: 'location_update',
        payload: locationPayload,
      );

      print('📡 DIAGNOSTIC BROADCAST SENT:');
      print('   📍 Lat: ${position?.latitude ?? 14.5995}, Lng: ${position?.longitude ?? 120.9842}');
      print('   🏎️ Speed: ${position?.speed != null ? (position!.speed * 3.6).toStringAsFixed(1) : "15.0"} km/h');
      print('   📊 Payload: $locationPayload');
      print('   🎯 Customer app should receive this update now!');

    } catch (e) {
      print('❌ DIAGNOSTIC BROADCAST FAILED: $e');
    }
  }

  /// Stop diagnostic broadcasting
  Future<void> stopDiagnosticBroadcast() async {
    if (!_isActive) return;

    print('🛑 Stopping diagnostic broadcast');
    
    _isActive = false;
    _broadcastTimer?.cancel();
    _broadcastTimer = null;

    if (_testChannel != null) {
      await _testChannel!.unsubscribe();
      _testChannel = null;
    }

    print('✅ Diagnostic broadcast stopped');
  }

  /// Test WebSocket connection and GPS permissions
  Future<void> runFullDiagnostic() async {
    print('🧪 RUNNING FULL DIAGNOSTIC...\n');

    // 1. Test Supabase connection
    print('1️⃣ Testing Supabase connection...');
    try {
      final user = _supabase.auth.currentUser;
      if (user != null) {
        print('✅ Supabase connected - User ID: ${user.id}');
      } else {
        print('❌ Not authenticated with Supabase');
        return;
      }
    } catch (e) {
      print('❌ Supabase connection failed: $e');
      return;
    }

    // 2. Test GPS permissions
    print('\n2️⃣ Testing GPS permissions...');
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      
      if (permission == LocationPermission.whileInUse || 
          permission == LocationPermission.always) {
        print('✅ GPS permissions granted');
        
        // Test GPS location
        print('📍 Getting current GPS location...');
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        ).timeout(Duration(seconds: 15));
        
        print('✅ GPS working - Lat: ${position.latitude}, Lng: ${position.longitude}');
        
      } else {
        print('❌ GPS permissions not granted: $permission');
        return;
      }
    } catch (e) {
      print('❌ GPS test failed: $e');
    }

    // 3. Test WebSocket channel creation
    print('\n3️⃣ Testing WebSocket channel...');
    try {
      final testChannel = _supabase.channel('test-diagnostic-${DateTime.now().millisecondsSinceEpoch}');
      await testChannel.subscribe();
      print('✅ WebSocket channel creation successful');
      await testChannel.unsubscribe();
    } catch (e) {
      print('❌ WebSocket channel test failed: $e');
      return;
    }

    print('\n🎉 ALL DIAGNOSTICS PASSED!');
    print('🚀 Ready to start location broadcasting');
    print('\n🧪 Run startDiagnosticBroadcast() to test with customer app');
  }
}