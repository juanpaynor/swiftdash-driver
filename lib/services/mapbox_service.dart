import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'navigation_service.dart'; // Import new navigation service

class MapboxService {
  // Load token from environment (secure)
  static String get accessToken =>
      dotenv.env['MAPBOX_ACCESS_TOKEN'] ??
      (throw Exception('❌ MAPBOX_ACCESS_TOKEN not found in .env file'));

  // Philippines bounding box and center
  static const String philippinesBbox = '116.9283,4.5693,126.6043,21.1210';
  static const String manilaProximity = '121.0244,14.5995';

  /// Get route data between two points
  /// 🔄 ENHANCED: Now supports both basic routing and professional navigation
  static Future<RouteData?> getRoute(
    double fromLat,
    double fromLng,
    double toLat,
    double toLng, {
    bool useNavigation = false, // NEW: Enable professional navigation
  }) async {
    try {
      // If professional navigation requested, use NavigationService
      if (useNavigation) {
        final navRoute = await NavigationService.instance
            .calculateNavigationRoute(
              startLat: fromLat,
              startLng: fromLng,
              endLat: toLat,
              endLng: toLng,
            );

        if (navRoute != null) {
          // Convert NavigationRoute to RouteData for compatibility
          return RouteData(
            distance: navRoute.totalDistance / 1000, // Convert to km
            duration: navRoute.totalDuration.toInt(), // Already in minutes
            geometry: navRoute.geometry,
            bbox: _calculateBbox(navRoute.geometry),
            navigationRoute: navRoute, // NEW: Include full navigation data
          );
        }
      }

      // Fallback to basic Mapbox routing (existing functionality)
      final url =
          'https://api.mapbox.com/directions/v5/mapbox/driving'
          '/$fromLng,$fromLat;$toLng,$toLat'
          '?access_token=$accessToken'
          '&geometries=geojson'
          '&overview=simplified';

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];

          return RouteData(
            distance: (route['distance'] / 1000).toDouble(), // Convert to km
            duration: (route['duration'] / 60).toInt(), // Convert to minutes
            geometry: route['geometry'],
            bbox: route['bbox'] ?? [],
          );
        }
      }

      print('Mapbox API error: ${response.statusCode} - ${response.body}');
      return null;
    } catch (e) {
      print('Error getting route: $e');
      return null;
    }
  }

  /// Alias method for enhanced active delivery screen
  static Future<RouteData?> getRouteData({
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
  }) async {
    return await getRoute(startLat, startLng, endLat, endLng);
  }

  /// Get a static map image URL centered between two points with pickup/delivery markers and route
  static String getStaticPreviewUrl({
    required double pickupLat,
    required double pickupLng,
    required double deliveryLat,
    required double deliveryLng,
    RouteData? routeData,
    int width = 600,
    int height = 300,
    int zoom = 12,
  }) {
    // Markers: pickup green, delivery red
    final pickupMarker = 'pin-s-a+00cc66($pickupLng,$pickupLat)';
    final deliveryMarker = 'pin-s-b+ff3366($deliveryLng,$deliveryLat)';

    final centerLng = (pickupLng + deliveryLng) / 2;
    final centerLat = (pickupLat + deliveryLat) / 2;

    String overlays = '';

    // Add route polyline if available (must come BEFORE markers so markers appear on top)
    if (routeData != null && routeData.geometry['coordinates'] != null) {
      try {
        final coordinates = routeData.geometry['coordinates'] as List;
        if (coordinates.isNotEmpty) {
          // Create a simplified polyline for the route
          final routePolyline = _createPolylineOverlay(coordinates);
          overlays = routePolyline;
        }
      } catch (e) {
        print('⚠️ Error adding route to static map: $e');
      }
    }

    // Add markers AFTER polyline so they appear on top
    if (overlays.isNotEmpty) {
      overlays = '$overlays,$pickupMarker,$deliveryMarker';
    } else {
      overlays = '$pickupMarker,$deliveryMarker';
    }

    // Use auto-fit if route data available, otherwise manual zoom
    String positioning;
    if (routeData != null &&
        routeData.bbox.isNotEmpty &&
        routeData.bbox.length >= 4) {
      // Auto-fit to route bounds
      positioning = 'auto';
    } else {
      positioning = '$centerLng,$centerLat,$zoom';
    }

    final url =
        'https://api.mapbox.com/styles/v1/mapbox/streets-v11/static/$overlays/$positioning/${width}x${height}@2x?access_token=$accessToken';
    return url;
  }

  /// Create a polyline overlay for the static map
  static String _createPolylineOverlay(List coordinates) {
    // For static maps, we use simplified coordinates to avoid URL length limits
    final simplified = <List<double>>[];

    // Take every 3rd coordinate to simplify the route (avoid URL length issues)
    for (int i = 0; i < coordinates.length; i += 3) {
      final coord = coordinates[i] as List;
      if (coord.length >= 2) {
        simplified.add([coord[0] as double, coord[1] as double]);
      }
    }

    // Ensure we have start and end points
    if (simplified.isNotEmpty && coordinates.isNotEmpty) {
      final first = coordinates.first as List;
      final last = coordinates.last as List;

      if (simplified.first[0] != first[0] || simplified.first[1] != first[1]) {
        simplified.insert(0, [first[0] as double, first[1] as double]);
      }

      if (simplified.last[0] != last[0] || simplified.last[1] != last[1]) {
        simplified.add([last[0] as double, last[1] as double]);
      }
    }

    // Create path string: path-{strokeWidth}+{color}({coordinates})
    final pathCoords = simplified
        .map((coord) => '${coord[0]},${coord[1]}')
        .join(',');
    return 'path-3+3366ff($pathCoords)'; // Blue route line, 3px width
  }

  /// Calculate estimated earnings based on distance
  static double calculateEarnings(double distanceKm) {
    // Base fare + distance rate (adjust these values as needed)
    const double baseFare = 50.0; // ₱50 base fare
    const double perKmRate = 15.0; // ₱15 per km

    return baseFare + (distanceKm * perKmRate);
  }

  /// Format distance for display
  static String formatDistance(double distanceKm) {
    if (distanceKm < 1) {
      return '${(distanceKm * 1000).round()}m';
    } else {
      return '${distanceKm.toStringAsFixed(1)}km';
    }
  }

  /// Format duration for display
  static String formatDuration(int durationMinutes) {
    if (durationMinutes < 60) {
      return '${durationMinutes}min';
    } else {
      final hours = durationMinutes ~/ 60;
      final minutes = durationMinutes % 60;
      return '${hours}h ${minutes}min';
    }
  }

  /// Calculate bounding box from geometry
  static List<double> _calculateBbox(Map<String, dynamic> geometry) {
    try {
      final coordinates = geometry['coordinates'] as List;
      if (coordinates.isEmpty) return [];

      double minLng = double.infinity;
      double maxLng = double.negativeInfinity;
      double minLat = double.infinity;
      double maxLat = double.negativeInfinity;

      for (final coord in coordinates) {
        final lng = (coord[0] as num).toDouble();
        final lat = (coord[1] as num).toDouble();

        minLng = minLng < lng ? minLng : lng;
        maxLng = maxLng > lng ? maxLng : lng;
        minLat = minLat < lat ? minLat : lat;
        maxLat = maxLat > lat ? maxLat : lat;
      }

      return [minLng, minLat, maxLng, maxLat];
    } catch (e) {
      print('Error calculating bbox: $e');
      return [];
    }
  }
}

class RouteData {
  final double distance; // in kilometers
  final int duration; // in minutes
  final Map<String, dynamic> geometry; // GeoJSON geometry
  final List<dynamic> bbox; // Bounding box for the route
  final NavigationRoute? navigationRoute; // NEW: Professional navigation data

  RouteData({
    required this.distance,
    required this.duration,
    required this.geometry,
    required this.bbox,
    this.navigationRoute, // NEW: Optional navigation route
  });

  /// Check if this route has professional navigation capabilities
  bool get hasNavigation => navigationRoute != null;

  /// Get turn-by-turn instructions (empty if basic route)
  List<NavigationInstruction> get instructions =>
      navigationRoute?.instructions ?? [];

  @override
  String toString() {
    final navStatus = hasNavigation ? ' (with navigation)' : ' (basic)';
    return 'RouteData(distance: ${distance}km, duration: ${duration}min$navStatus)';
  }
}
