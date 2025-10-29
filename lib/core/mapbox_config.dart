import 'package:flutter_dotenv/flutter_dotenv.dart';

class MapboxConfig {
  // Load token from environment (secure)
  static String get accessToken => 
    dotenv.env['MAPBOX_ACCESS_TOKEN'] ?? 
    (throw Exception('❌ MAPBOX_ACCESS_TOKEN not found in .env file'));
  
  // Map styles
  static const String streetStyle = 'mapbox://styles/swiftdash/cmh0gjtfm007h01r4ghel4u4m'; // SwiftDash custom style
  static const String satelliteStyle = 'mapbox://styles/mapbox/satellite-streets-v12';
  static const String darkStyle = 'mapbox://styles/mapbox/dark-v11';
  static const String navigationDayStyle = 'mapbox://styles/mapbox/navigation-day-v1';
  static const String navigationNightStyle = 'mapbox://styles/mapbox/navigation-night-v1';
  
  // Default map settings for driver app
  static const double defaultZoom = 15.0;
  static const double minZoom = 8.0;
  static const double maxZoom = 20.0;
}