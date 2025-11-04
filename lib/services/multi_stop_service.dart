import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/delivery_stop.dart';
import '../core/mapbox_config.dart';
import 'ably_service.dart';

class MultiStopService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final AblyService _ablyService = AblyService();

  /// Optimize route for multiple stops using Mapbox Optimization API
  /// Returns optimized stop order and route geometry
  Future<Map<String, dynamic>> optimizeRoute({
    required double pickupLat,
    required double pickupLng,
    required List<Map<String, double>> dropoffLocations,
  }) async {
    try {
      // Build coordinates string: pickup first, then all dropoffs
      final coordinates = <String>[];
      coordinates.add('$pickupLng,$pickupLat'); // Mapbox uses lng,lat order
      
      for (final location in dropoffLocations) {
        coordinates.add('${location['lng']},${location['lat']}');
      }
      
      final coordinatesStr = coordinates.join(';');
      
      // Call Mapbox Optimization API
      final url = Uri.parse(
        'https://api.mapbox.com/optimized-trips/v1/mapbox/driving/$coordinatesStr'
        '?access_token=${MapboxConfig.accessToken}'
        '&source=first' // Pickup is always first
        '&destination=any' // Any dropoff can be last
        '&roundtrip=false' // One-way trip
        '&geometries=geojson'
        '&overview=full',
      );
      
      final response = await http.get(url);
      
      print('🗺️ MAPBOX OPTIMIZATION API CALL:');
      print('  URL: $url');
      print('  Status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        print('  Response code: ${data['code']}');
        print('  Raw response: ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}...');
        
        if (data['code'] == 'Ok' && data['trips'] != null && data['trips'].isNotEmpty) {
          final trip = data['trips'][0];
          
          print('  Trip distance (raw): ${trip['distance']}');
          print('  Trip distance type: ${trip['distance']?.runtimeType}');
          print('  Trip duration: ${trip['duration']}');
          print('  Number of waypoints: ${(data['waypoints'] as List).length}');
          
          // Extract waypoint order (excludes pickup which is always first)
          final waypoints = data['waypoints'] as List;
          final optimizedOrder = <int>[];
          
          // Skip first waypoint (pickup) and get optimized order for dropoffs
          for (int i = 1; i < waypoints.length; i++) {
            final waypointIndex = waypoints[i]['waypoint_index'] as int;
            // Adjust index to match dropoff list (subtract 1 because pickup is index 0)
            optimizedOrder.add(waypointIndex - 1);
          }
          
          return {
            'success': true,
            'optimizedOrder': optimizedOrder, // Order of dropoff indices
            'distance': trip['distance'], // meters
            'duration': trip['duration'], // seconds
            'geometry': trip['geometry'], // GeoJSON LineString
          };
        } else {
          throw Exception('Mapbox Optimization failed: ${data['code']}');
        }
      } else {
        throw Exception('Mapbox API error: ${response.statusCode}');
      }
    } catch (e) {
      print('Error optimizing route: $e');
      // Return original order if optimization fails
      return {
        'success': false,
        'optimizedOrder': List.generate(dropoffLocations.length, (i) => i),
        'error': e.toString(),
      };
    }
  }

  /// Calculate total price for multi-stop delivery
  /// Uses base price + (distance × rate per km) + (additional stops × additional_stop_charge)
  Future<Map<String, dynamic>> calculateMultiStopPrice({
    required String vehicleTypeId,
    required double distanceKm,
    required int numberOfDropoffs,
  }) async {
    try {
      // Fetch vehicle type to get pricing info
      final response = await _supabase
          .from('vehicle_types')
          .select('base_price, price_per_km, additional_stop_charge')
          .eq('id', vehicleTypeId)
          .single();
      
      final basePrice = (response['base_price'] as num).toDouble();
      final pricePerKm = (response['price_per_km'] as num).toDouble();
      final additionalStopCharge = (response['additional_stop_charge'] as num?)?.toDouble() ?? 0.0;
      
      // Calculate components
      final distancePrice = distanceKm * pricePerKm;
      // First dropoff is included in base price, charge for additional dropoffs
      final additionalStopsCount = numberOfDropoffs > 1 ? numberOfDropoffs - 1 : 0;
      final additionalStopsPrice = additionalStopsCount * additionalStopCharge;
      
      final totalPrice = basePrice + distancePrice + additionalStopsPrice;
      
      print('💵 MULTI-STOP PRICE CALCULATION:');
      print('  Vehicle Type ID: $vehicleTypeId');
      print('  Distance: $distanceKm km');
      print('  Number of dropoffs: $numberOfDropoffs');
      print('  ───────────────────────────');
      print('  Base Price: ₱$basePrice');
      print('  Price per KM: ₱$pricePerKm');
      print('  Distance Price: $distanceKm × ₱$pricePerKm = ₱$distancePrice');
      print('  ───────────────────────────');
      print('  Additional Stops: $additionalStopsCount');
      print('  Additional Stop Charge: ₱$additionalStopCharge');
      print('  Additional Stops Price: $additionalStopsCount × ₱$additionalStopCharge = ₱$additionalStopsPrice');
      print('  ───────────────────────────');
      print('  TOTAL (no VAT): ₱$totalPrice');
      print('  ═══════════════════════════');
      
      return {
        'success': true,
        'basePrice': basePrice,
        'distancePrice': distancePrice,
        'additionalStopsPrice': additionalStopsPrice,
        'totalPrice': totalPrice,
        'breakdown': {
          'base': basePrice,
          'distance': distancePrice,
          'distanceKm': distanceKm,
          'pricePerKm': pricePerKm,
          'additionalStops': additionalStopsCount,
          'additionalStopCharge': additionalStopCharge,
          'additionalStopsTotal': additionalStopsPrice,
        },
      };
    } catch (e) {
      print('Error calculating multi-stop price: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Create stops for a multi-stop delivery
  Future<List<DeliveryStop>> createStops({
    required String deliveryId,
    required Map<String, dynamic> pickupData,
    required List<Map<String, dynamic>> dropoffData,
    List<int>? optimizedOrder,
  }) async {
    try {
      final stops = <Map<String, dynamic>>[];
      
      // Create pickup stop (always stop number 1)
      stops.add({
        'delivery_id': deliveryId,
        'stop_number': 1,
        'stop_type': 'pickup',
        'address': pickupData['address'],
        'latitude': pickupData['latitude'],
        'longitude': pickupData['longitude'],
        'house_number': pickupData['houseNumber'],
        'street': pickupData['street'],
        'barangay': pickupData['barangay'],
        'city': pickupData['city'],
        'province': pickupData['province'],
        'recipient_name': pickupData['contactName'],
        'recipient_phone': pickupData['contactPhone'],
        'delivery_notes': pickupData['instructions'],
        'status': 'pending',
      });
      
      // Create dropoff stops in optimized order (or original order if no optimization)
      final orderedDropoffs = optimizedOrder != null
          ? optimizedOrder.map((i) => dropoffData[i]).toList()
          : dropoffData;
      
      int stopNumber = 2; // Start from 2 (pickup is 1)
      for (final dropoff in orderedDropoffs) {
        stops.add({
          'delivery_id': deliveryId,
          'stop_number': stopNumber,
          'stop_type': 'dropoff',
          'address': dropoff['address'],
          'latitude': dropoff['latitude'],
          'longitude': dropoff['longitude'],
          'house_number': dropoff['houseNumber'],
          'street': dropoff['street'],
          'barangay': dropoff['barangay'],
          'city': dropoff['city'],
          'province': dropoff['province'],
          'recipient_name': dropoff['contactName'],
          'recipient_phone': dropoff['contactPhone'],
          'delivery_notes': dropoff['instructions'],
          'status': 'pending',
        });
        stopNumber++;
      }
      
      // Insert all stops in a batch
      final response = await _supabase
          .from('delivery_stops')
          .insert(stops)
          .select();
      
      return response.map((json) => DeliveryStop.fromJson(json)).toList();
    } catch (e) {
      print('Error creating stops: $e');
      rethrow;
    }
  }

  /// Get all stops for a delivery
  Future<List<DeliveryStop>> getStops(String deliveryId) async {
    try {
      final response = await _supabase
          .from('delivery_stops')
          .select()
          .eq('delivery_id', deliveryId)
          .order('stop_number', ascending: true);
      
      return response.map((json) => DeliveryStop.fromJson(json)).toList();
    } catch (e) {
      print('Error fetching stops: $e');
      rethrow;
    }
  }

  /// Update stop status
  Future<DeliveryStop> updateStopStatus({
    required String stopId,
    required String status,
    DateTime? arrivedAt,
    DateTime? completedAt,
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
      
      final updateData = <String, dynamic>{
        'status': status,
        'updated_at': DateTime.now().toIso8601String(),
      };
      
      if (arrivedAt != null) updateData['arrived_at'] = arrivedAt.toIso8601String();
      if (completedAt != null) updateData['completed_at'] = completedAt.toIso8601String();
      if (proofPhotoUrl != null) updateData['proof_photo_url'] = proofPhotoUrl;
      if (signatureUrl != null) updateData['signature_url'] = signatureUrl;
      if (completionNotes != null) updateData['completion_notes'] = completionNotes;
      
      // Update database
      final response = await _supabase
          .from('delivery_stops')
          .update(updateData)
          .eq('id', stopId)
          .select()
          .single();
      
      // Publish to Ably for customer app
      await _ablyService.publishStopUpdate(
        deliveryId: stopBefore['delivery_id'],
        stopId: stopId,
        stopNumber: stopBefore['stop_number'],
        stopType: stopBefore['stop_type'],
        status: status,
        proofPhotoUrl: proofPhotoUrl,
        completionNotes: completionNotes,
      );
      
      return DeliveryStop.fromJson(response);
    } catch (e) {
      print('Error updating stop status: $e');
      rethrow;
    }
  }

  /// Reorder stops (before delivery starts)
  Future<List<DeliveryStop>> reorderStops({
    required String deliveryId,
    required List<String> stopIds, // New order of stop IDs
  }) async {
    try {
      // Update stop_number for each stop
      final updates = <Future>[];
      for (int i = 0; i < stopIds.length; i++) {
        updates.add(
          _supabase
              .from('delivery_stops')
              .update({
                'stop_number': i + 1,
                'updated_at': DateTime.now().toIso8601String(),
              })
              .eq('id', stopIds[i])
        );
      }
      
      await Future.wait(updates);
      
      // Fetch updated stops
      return getStops(deliveryId);
    } catch (e) {
      print('Error reordering stops: $e');
      rethrow;
    }
  }

  /// Delete a stop (before delivery starts)
  Future<void> deleteStop(String stopId) async {
    try {
      await _supabase
          .from('delivery_stops')
          .delete()
          .eq('id', stopId);
    } catch (e) {
      print('Error deleting stop: $e');
      rethrow;
    }
  }

  /// Get current active stop (first pending or in_progress stop)
  DeliveryStop? getCurrentStop(List<DeliveryStop> stops) {
    return stops.firstWhere(
      (stop) => stop.status == 'in_progress' || stop.status == 'pending',
      orElse: () => stops.last, // Return last stop if all completed
    );
  }

  /// Check if all stops are completed
  bool areAllStopsCompleted(List<DeliveryStop> stops) {
    return stops.every((stop) => stop.status == 'completed');
  }

  /// Get next pending stop
  DeliveryStop? getNextPendingStop(List<DeliveryStop> stops) {
    try {
      return stops.firstWhere((stop) => stop.status == 'pending');
    } catch (e) {
      return null; // No pending stops
    }
  }

  /// Calculate progress percentage
  double calculateProgress(List<DeliveryStop> stops) {
    if (stops.isEmpty) return 0.0;
    
    final completedCount = stops.where((s) => s.status == 'completed').length;
    return (completedCount / stops.length) * 100;
  }
}
