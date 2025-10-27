import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:flutter/material.dart';
import '../core/mapbox_config.dart';

/// Service for fetching and rendering route previews on Mapbox map
/// Used for showing delivery routes before driver accepts offer
class RoutePreviewService {
  static final RoutePreviewService _instance = RoutePreviewService._internal();
  factory RoutePreviewService() => _instance;
  RoutePreviewService._internal();

  /// Fetch route from Mapbox Directions API
  /// Supports both single-stop and multi-stop deliveries
  /// 
  /// For single-stop: Pass start and end only
  /// For multi-stop: Pass waypoints list with [pickup, stop1, stop2, ..., final]
  /// 
  /// Returns route geometry, distance, and duration
  Future<RouteData?> fetchRoute({
    Position? start,
    Position? end,
    List<Position>? waypoints,
    bool alternatives = false,
  }) async {
    try {
      // Build coordinates list
      List<Position> coordinates;
      
      if (waypoints != null && waypoints.isNotEmpty) {
        // Multi-stop mode: Use waypoints list
        coordinates = waypoints;
        
        if (coordinates.length < 2) {
          print('❌ Multi-stop route needs at least 2 waypoints');
          return null;
        }
        
        if (coordinates.length > 25) {
          print('❌ Mapbox supports maximum 25 waypoints, got ${coordinates.length}');
          return null;
        }
      } else if (start != null && end != null) {
        // Single-stop mode: Use start and end
        coordinates = [start, end];
      } else {
        print('❌ Must provide either waypoints list OR start+end positions');
        return null;
      }
      
      // Build coordinate string: lng1,lat1;lng2,lat2;lng3,lat3
      final coordinateString = coordinates
          .map((pos) => '${pos.lng},${pos.lat}')
          .join(';');
      
      // Build Mapbox Directions API URL
      final url = Uri.parse(
        'https://api.mapbox.com/directions/v5/mapbox/driving/'
        '$coordinateString'
        '?geometries=geojson'
        '&overview=full'
        '&steps=false'
        '&alternatives=$alternatives'
        '&access_token=${MapboxConfig.accessToken}',
      );

      print('🗺️ Fetching route from Mapbox (${coordinates.length} waypoints)...');
      
      final response = await http.get(url);

      if (response.statusCode != 200) {
        print('❌ Mapbox API error: ${response.statusCode}');
        return null;
      }

      final data = json.decode(response.body);

      if (data['routes'] == null || (data['routes'] as List).isEmpty) {
        print('❌ No routes found');
        return null;
      }

      final route = data['routes'][0];
      final geometry = route['geometry'];
      final distance = route['distance'] as num; // meters
      final duration = route['duration'] as num; // seconds

      print('✅ Route fetched: ${(distance / 1000).toStringAsFixed(1)} km, '
          '${(duration / 60).toStringAsFixed(0)} min');

      return RouteData(
        geometry: geometry,
        distanceMeters: distance.toDouble(),
        durationSeconds: duration.toDouble(),
        waypointCount: coordinates.length,
      );
    } catch (e) {
      print('❌ Failed to fetch route: $e');
      return null;
    }
  }

  /// Draw route polyline on map from GeoJSON geometry
  Future<void> drawRoutePolyline({
    required PolylineAnnotationManager polylineManager,
    required Map<String, dynamic> geometry,
    Color color = Colors.blue,
    double width = 4.0,
  }) async {
    try {
      // Parse GeoJSON coordinates
      final coordinates = geometry['coordinates'] as List;
      
      // Convert to Position list
      final positions = coordinates.map((coord) {
        return Position(coord[0] as double, coord[1] as double);
      }).toList();

      // Create polyline annotation
      await polylineManager.create(
        PolylineAnnotationOptions(
          geometry: LineString(coordinates: positions),
          lineColor: color.value,
          lineWidth: width,
          lineJoin: LineJoin.ROUND,
        ),
      );

      print('✅ Route polyline drawn with ${positions.length} points');
    } catch (e) {
      print('❌ Failed to draw route polyline: $e');
    }
  }

  /// Calculate camera bounds to fit multiple points
  CoordinateBounds calculateBounds(List<Position> points) {
    if (points.isEmpty) {
      throw ArgumentError('Points list cannot be empty');
    }

    double minLat = points.first.lat.toDouble();
    double maxLat = points.first.lat.toDouble();
    double minLng = points.first.lng.toDouble();
    double maxLng = points.first.lng.toDouble();

    for (final point in points) {
      if (point.lat < minLat) minLat = point.lat.toDouble();
      if (point.lat > maxLat) maxLat = point.lat.toDouble();
      if (point.lng < minLng) minLng = point.lng.toDouble();
      if (point.lng > maxLng) maxLng = point.lng.toDouble();
    }

    // Add 20% padding
    final latPadding = (maxLat - minLat) * 0.2;
    final lngPadding = (maxLng - minLng) * 0.2;

    return CoordinateBounds(
      southwest: Point(coordinates: Position(minLng - lngPadding, minLat - latPadding)),
      northeast: Point(coordinates: Position(maxLng + lngPadding, maxLat + latPadding)),
      infiniteBounds: false,
    );
  }

  /// Animate camera to fit bounds with bottom sheet space
  Future<void> fitCameraToBounds({
    required MapboxMap mapboxMap,
    required CoordinateBounds bounds,
    Duration duration = const Duration(milliseconds: 800),
    double bottomPadding = 400.0, // Space for bottom sheet
  }) async {
    try {
      await mapboxMap.setCamera(
        CameraOptions(
          center: Point(coordinates: Position(
            (bounds.southwest.coordinates.lng + bounds.northeast.coordinates.lng) / 2,
            (bounds.southwest.coordinates.lat + bounds.northeast.coordinates.lat) / 2,
          )),
          padding: MbxEdgeInsets(
            top: 100,
            left: 50,
            bottom: bottomPadding,
            right: 50,
          ),
        ),
      );

      print('✅ Camera animated to bounds');
    } catch (e) {
      print('❌ Failed to animate camera: $e');
    }
  }

  /// Center camera on specific position with zoom
  Future<void> centerCamera({
    required MapboxMap mapboxMap,
    required Position position,
    double zoom = 15.0,
    Duration duration = const Duration(milliseconds: 500),
  }) async {
    try {
      await mapboxMap.flyTo(
        CameraOptions(
          center: Point(coordinates: position),
          zoom: zoom,
        ),
        MapAnimationOptions(
          duration: duration.inMilliseconds,
          startDelay: 0,
        ),
      );

      print('✅ Camera centered on position');
    } catch (e) {
      print('❌ Failed to center camera: $e');
    }
  }

  /// Format distance for display
  String formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.toStringAsFixed(0)} m';
    } else {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
  }

  /// Format duration for display
  String formatDuration(double seconds) {
    final minutes = (seconds / 60).round();
    if (minutes < 60) {
      return '$minutes min';
    } else {
      final hours = (minutes / 60).floor();
      final remainingMinutes = minutes % 60;
      return '${hours}h ${remainingMinutes}min';
    }
  }

  /// Calculate estimated time of arrival
  DateTime calculateETA(double durationSeconds) {
    return DateTime.now().add(Duration(seconds: durationSeconds.toInt()));
  }

  /// Format ETA for display
  String formatETA(DateTime eta) {
    final now = DateTime.now();
    final difference = eta.difference(now);

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes} min';
    } else {
      final hours = difference.inHours;
      final minutes = difference.inMinutes % 60;
      return '${hours}h ${minutes}min';
    }
  }
}

/// Data class for route information
class RouteData {
  final Map<String, dynamic> geometry; // GeoJSON geometry
  final double distanceMeters;
  final double durationSeconds;
  final int waypointCount; // Number of stops (2 = single-stop, 3+ = multi-stop)

  RouteData({
    required this.geometry,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.waypointCount,
  });

  /// Distance in kilometers
  double get distanceKm => distanceMeters / 1000;

  /// Duration in minutes
  double get durationMinutes => durationSeconds / 60;
  
  /// Check if this is a multi-stop delivery
  bool get isMultiStop => waypointCount > 2;
  
  /// Number of intermediate stops (excludes pickup and final delivery)
  int get intermediateStopCount => isMultiStop ? waypointCount - 2 : 0;

  /// Formatted distance string
  String get formattedDistance => RoutePreviewService().formatDistance(distanceMeters);

  /// Formatted duration string
  String get formattedDuration => RoutePreviewService().formatDuration(durationSeconds);

  /// Estimated time of arrival
  DateTime get eta => RoutePreviewService().calculateETA(durationSeconds);

  /// Formatted ETA string
  String get formattedETA => RoutePreviewService().formatETA(eta);
}
