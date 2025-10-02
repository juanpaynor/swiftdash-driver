import 'dart:convert';
import 'package:http/http.dart' as http;

class MapboxService {
  // Your Mapbox token
  static const String accessToken = 'pk.eyJ1Ijoic3dpZnRkYXNoIiwiYSI6ImNtZzNiazczczEzZmQycnIwdno1Z2NtYW0ifQ.9zBJVXVCBLU3eN1jZQTJUA';
  
  // Philippines bounding box and center
  static const String philippinesBbox = '116.9283,4.5693,126.6043,21.1210';
  static const String manilaProximity = '121.0244,14.5995';

  /// Get route data between two points
  static Future<RouteData?> getRoute(
    double fromLat, 
    double fromLng, 
    double toLat, 
    double toLng
  ) async {
    try {
      final url = 'https://api.mapbox.com/directions/v5/mapbox/driving'
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
}

class RouteData {
  final double distance; // in kilometers
  final int duration; // in minutes
  final Map<String, dynamic> geometry; // GeoJSON geometry
  final List<dynamic> bbox; // Bounding box for the route

  RouteData({
    required this.distance,
    required this.duration,
    required this.geometry,
    required this.bbox,
  });

  @override
  String toString() {
    return 'RouteData(distance: ${distance}km, duration: ${duration}min)';
  }
}