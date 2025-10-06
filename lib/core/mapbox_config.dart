class MapboxConfig {
  // Using the token from MapboxService
  static const String accessToken = 'pk.eyJ1Ijoic3dpZnRkYXNoIiwiYSI6ImNtZzNiazczczEzZmQycnIwdno1Z2NtYW0ifQ.9zBJVXVCBLU3eN1jZQTJUA';
  
  // Map styles
  static const String streetStyle = 'mapbox://styles/mapbox/streets-v12';
  static const String satelliteStyle = 'mapbox://styles/mapbox/satellite-streets-v12';
  static const String darkStyle = 'mapbox://styles/mapbox/dark-v11';
  static const String navigationDayStyle = 'mapbox://styles/mapbox/navigation-day-v1';
  static const String navigationNightStyle = 'mapbox://styles/mapbox/navigation-night-v1';
  
  // Default map settings for driver app
  static const double defaultZoom = 15.0;
  static const double minZoom = 8.0;
  static const double maxZoom = 20.0;
}