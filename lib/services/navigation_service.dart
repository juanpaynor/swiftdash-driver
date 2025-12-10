import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import '../utils/route_snapper.dart';
import '../models/delivery.dart';
import 'navigation_announcement_manager.dart';
import 'navigation_foreground_service.dart';

/// Professional navigation service using MapLibre for turn-by-turn guidance
/// Integrates with existing SwiftDash architecture while providing professional navigation
class NavigationService extends ChangeNotifier {
  static NavigationService? _instance;
  static NavigationService get instance => _instance ??= NavigationService._();
  NavigationService._();

  // Voice guidance manager
  final NavigationAnnouncementManager _announcementManager =
      NavigationAnnouncementManager();

  // Foreground service for background navigation
  final NavigationForegroundService _foregroundService =
      NavigationForegroundService();
  bool _backgroundNavigationEnabled = true;

  // Navigation state
  bool _isNavigating = false;
  bool _isRerouting = false;
  DateTime? _lastRerouteTime;
  NavigationRoute? _currentRoute;
  NavigationInstruction? _currentInstruction;
  List<NavigationInstruction> _instructions = [];
  NavigationCoordinate? _snappedLocation;
  int _currentInstructionIndex = 0;
  double _distanceToNextInstruction = 0;
  double _estimatedTimeToArrival = 0;
  double _distanceRemaining = 0;

  // Stream controllers for real-time updates
  final StreamController<NavigationInstruction> _instructionController =
      StreamController<NavigationInstruction>.broadcast();
  final StreamController<NavigationProgress> _progressController =
      StreamController<NavigationProgress>.broadcast();
  final StreamController<NavigationEvent> _eventController =
      StreamController<NavigationEvent>.broadcast();

  // Getters
  bool get isNavigating => _isNavigating;
  NavigationRoute? get currentRoute => _currentRoute;
  NavigationInstruction? get currentInstruction => _currentInstruction;
  List<NavigationInstruction> get instructions => _instructions;
  double get distanceToNextInstruction => _distanceToNextInstruction;
  double get estimatedTimeToArrival => _estimatedTimeToArrival;
  double get distanceRemaining => _distanceRemaining;
  NavigationCoordinate? get snappedLocation => _snappedLocation;

  // Streams
  Stream<NavigationInstruction> get instructionStream =>
      _instructionController.stream;
  Stream<NavigationProgress> get progressStream => _progressController.stream;
  Stream<NavigationEvent> get eventStream => _eventController.stream;

  /// Start navigation to a delivery location
  /// Compatible with existing delivery workflow
  Future<bool> startNavigationToDelivery({
    required Delivery delivery,
    required Position currentLocation,
    bool isPickupPhase = false,
  }) async {
    try {
      final double targetLat = isPickupPhase
          ? delivery.pickupLatitude
          : delivery.deliveryLatitude;
      final double targetLng = isPickupPhase
          ? delivery.pickupLongitude
          : delivery.deliveryLongitude;

      return await startNavigation(
        startLat: currentLocation.latitude,
        startLng: currentLocation.longitude,
        endLat: targetLat,
        endLng: targetLng,
        context: 'delivery',
        deliveryId: delivery.id,
      );
    } catch (e) {
      debugPrint('❌ Failed to start delivery navigation: $e');
      return false;
    }
  }

  /// Start navigation between two points
  Future<bool> startNavigation({
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
    String context = 'general',
    String? deliveryId,
  }) async {
    try {
      debugPrint(
        '🧭 Starting navigation from ($startLat, $startLng) to ($endLat, $endLng)',
      );

      // Stop any current navigation
      await stopNavigation();

      // Calculate route with turn-by-turn instructions
      final route = await calculateNavigationRoute(
        startLat: startLat,
        startLng: startLng,
        endLat: endLat,
        endLng: endLng,
      );

      if (route == null) {
        debugPrint('❌ Failed to calculate navigation route');
        return false;
      }

      // Initialize navigation state
      _currentRoute = route;
      _instructions = route.instructions;
      _currentInstructionIndex = 0;
      _currentInstruction = _instructions.isNotEmpty ? _instructions[0] : null;
      _distanceRemaining = route.totalDistance;
      _estimatedTimeToArrival = route.totalDuration;
      _isNavigating = true;

      // Initialize voice guidance
      await _announcementManager.initialize();

      // Start foreground service for background navigation
      if (_backgroundNavigationEnabled) {
        await _foregroundService.startService(
          destinationType: context == 'delivery' ? 'Delivery' : 'Destination',
          address: null, // Could be enhanced with actual address
        );
      }

      // Notify listeners
      notifyListeners();

      // Send initial instruction
      if (_currentInstruction != null) {
        _instructionController.add(_currentInstruction!);
      }

      // Send initial progress
      _progressController.add(_buildProgressUpdate());

      // Fire navigation started event
      _eventController.add(
        NavigationEvent(
          type: NavigationEventType.navigationStarted,
          context: context,
          deliveryId: deliveryId,
        ),
      );

      // Announce navigation start with voice
      await _announcementManager.announceNavigationStart(route.totalDistance);

      debugPrint('✅ Navigation started successfully');
      return true;
    } catch (e) {
      debugPrint('❌ Error starting navigation: $e');
      return false;
    }
  }

  /// Update navigation with new location
  /// Call this from your existing location service
  Future<void> updateLocation(Position location) async {
    if (!_isNavigating || _currentRoute == null) return;

    try {
      // 1. Snap to route
      final rawPoint = mapbox.Point(
        coordinates: mapbox.Position(location.longitude, location.latitude),
      );

      // Extract coordinates safely from GeoJSON
      final List<dynamic> rawCoords = _currentRoute!.geometry['coordinates'];
      final List<List<double>> routeGeometry = rawCoords.map((c) {
        return (c as List).map((e) => (e as num).toDouble()).toList();
      }).toList();

      final snappedPoint = RouteSnapper.snapToRoute(rawPoint, routeGeometry);

      // 2. Check for off-route
      final offRouteDistance = RouteSnapper.calculateDistanceInMeters(
        rawPoint,
        snappedPoint,
      );

      if (offRouteDistance > 30 && !_isRerouting) {
        // Debounce rerouting (e.g., max once every 5 seconds)
        if (_lastRerouteTime == null ||
            DateTime.now().difference(_lastRerouteTime!) >
                const Duration(seconds: 5)) {
          debugPrint(
            '⚠️ Off-route detected (${offRouteDistance.toStringAsFixed(1)}m). Recalculating...',
          );
          _recalculateRoute(location.latitude, location.longitude);
          return; // Stop processing this update until new route arrives
        }
      }

      // Use snapped location for instruction logic
      final effectiveLat = snappedPoint.coordinates.lat.toDouble();
      final effectiveLng = snappedPoint.coordinates.lng.toDouble();

      _snappedLocation = NavigationCoordinate(
        latitude: effectiveLat,
        longitude: effectiveLng,
      );

      // Calculate distance to next instruction
      if (_currentInstruction != null) {
        final distanceToInstruction = Geolocator.distanceBetween(
          effectiveLat,
          effectiveLng,
          _currentInstruction!.coordinate.latitude,
          _currentInstruction!.coordinate.longitude,
        );

        _distanceToNextInstruction = distanceToInstruction;

        // Get next instruction for compound announcements
        NavigationInstruction? nextInstruction;
        if (_currentInstructionIndex < _instructions.length - 1) {
          nextInstruction = _instructions[_currentInstructionIndex + 1];
        }

        // Process voice announcement for current instruction
        await _announcementManager.processInstruction(
          _currentInstruction!,
          distanceToInstruction,
          nextInstruction: nextInstruction,
        );

        // Check if we should advance to next instruction (within 20 meters)
        if (distanceToInstruction < 20 &&
            _currentInstructionIndex < _instructions.length - 1) {
          _advanceToNextInstruction();
        }
      }

      // Calculate remaining distance to destination
      final distanceToDestination = Geolocator.distanceBetween(
        effectiveLat,
        effectiveLng,
        _currentRoute!.endPoint.latitude,
        _currentRoute!.endPoint.longitude,
      );

      _distanceRemaining = distanceToDestination;

      // Estimate time to arrival (assuming 50 km/h average speed)
      _estimatedTimeToArrival =
          (distanceToDestination / 1000) / 50 * 60; // minutes

      // Check if we've arrived (within 30 meters of destination)
      if (distanceToDestination < 30) {
        await _handleArrival();
        return;
      }

      // Send progress update
      _progressController.add(_buildProgressUpdate());

      // Update foreground notification
      if (_backgroundNavigationEnabled && _currentInstruction != null) {
        await _foregroundService.updateNotification(
          instruction: _currentInstruction!.instruction,
          distance: _formatDistance(_distanceToNextInstruction),
          eta: _formatETA(_estimatedTimeToArrival),
        );
      }

      // Notify listeners for UI updates
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error updating navigation location: $e');
    }
  }

  Future<void> _recalculateRoute(double currentLat, double currentLng) async {
    if (_isRerouting || _currentRoute == null) return;

    _isRerouting = true;
    _lastRerouteTime = DateTime.now();

    // Notify UI that we are rerouting
    _eventController.add(
      NavigationEvent(
        type: NavigationEventType.routeRecalculated,
        context: 'Rerouting...',
      ),
    );

    try {
      final endLat = _currentRoute!.endPoint.latitude;
      final endLng = _currentRoute!.endPoint.longitude;

      final newRoute = await calculateNavigationRoute(
        startLat: currentLat,
        startLng: currentLng,
        endLat: endLat,
        endLng: endLng,
      );

      if (newRoute != null) {
        debugPrint('✅ Route recalculated successfully');
        _currentRoute = newRoute;
        _instructions = newRoute.instructions;
        _currentInstructionIndex = 0;
        _currentInstruction = _instructions.isNotEmpty
            ? _instructions[0]
            : null;
        _distanceRemaining = newRoute.totalDistance;
        _estimatedTimeToArrival = newRoute.totalDuration;

        // Send new instruction immediately
        if (_currentInstruction != null) {
          _instructionController.add(_currentInstruction!);

          // Announce new route
          _announcementManager.speak(
            'Rerouting. ${_currentInstruction!.instruction}',
          );
        }

        notifyListeners();
      }
    } catch (e) {
      debugPrint('❌ Error recalculating route: $e');
    } finally {
      _isRerouting = false;
    }
  }

  /// Stop current navigation
  Future<void> stopNavigation() async {
    if (!_isNavigating) return;

    try {
      _isNavigating = false;
      _currentRoute = null;
      _currentInstruction = null;
      _instructions = [];
      _currentInstructionIndex = 0;
      _distanceToNextInstruction = 0;
      _estimatedTimeToArrival = 0;
      _distanceRemaining = 0;

      // Reset voice guidance
      await _announcementManager.reset();

      // Stop foreground service
      await _foregroundService.stopService();

      // Fire navigation stopped event
      _eventController.add(
        NavigationEvent(type: NavigationEventType.navigationStopped),
      );

      notifyListeners();
      debugPrint('🛑 Navigation stopped');
    } catch (e) {
      debugPrint('❌ Error stopping navigation: $e');
    }
  }

  /// Calculate navigation route with turn-by-turn instructions
  /// Uses open routing services or can be adapted for MapLibre routing
  Future<NavigationRoute?> calculateNavigationRoute({
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
  }) async {
    try {
      // For Phase 1, we'll use Enhanced Mapbox API (uses your existing token)
      // This provides professional turn-by-turn instructions without additional API keys
      final route = await _getEnhancedMapboxDirections(
        startLat: startLat,
        startLng: startLng,
        endLat: endLat,
        endLng: endLng,
      );

      return route;
    } catch (e) {
      debugPrint('❌ Error calculating navigation route: $e');
      return null;
    }
  }

  /// Get directions from Enhanced Mapbox API (using your existing token)
  Future<NavigationRoute?> _getEnhancedMapboxDirections({
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
  }) async {
    try {
      // Use your existing Mapbox token with enhanced features
      final accessToken =
          dotenv.env['MAPBOX_ACCESS_TOKEN'] ??
          (throw Exception('❌ MAPBOX_ACCESS_TOKEN not found in .env file'));

      // Enhanced Mapbox Directions API with turn-by-turn instructions
      final url =
          'https://api.mapbox.com/directions/v5/mapbox/driving'
          '/$startLng,$startLat;$endLng,$endLat'
          '?access_token=$accessToken'
          '&steps=true' // Turn-by-turn steps
          '&voice_instructions=true' // Voice-ready instructions
          '&banner_instructions=true' // Visual instructions
          '&geometries=geojson'
          '&overview=full';

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return _parseMapboxNavigationResponse(data);
      } else {
        // Fallback to basic routing if enhanced API fails
        debugPrint('⚠️ Enhanced Mapbox failed, using fallback routing');
        return await _calculateBasicRoute(startLat, startLng, endLat, endLng);
      }
    } catch (e) {
      debugPrint('❌ Enhanced Mapbox error: $e, using fallback');
      return await _calculateBasicRoute(startLat, startLng, endLat, endLng);
    }
  }

  /// Parse Enhanced Mapbox response into NavigationRoute
  NavigationRoute? _parseMapboxNavigationResponse(Map<String, dynamic> data) {
    try {
      final routes = data['routes'] as List;
      if (routes.isEmpty) return null;

      final route = routes[0];
      final legs = route['legs'] as List;
      if (legs.isEmpty) return null;

      final leg = legs[0];
      final steps = leg['steps'] as List;
      final geometry = route['geometry'];

      // Extract route info
      final totalDistance = (route['distance'] as num).toDouble();
      final totalDuration =
          (route['duration'] as num).toDouble() / 60; // Convert to minutes

      // Extract turn-by-turn instructions from Mapbox steps
      final instructions = <NavigationInstruction>[];
      for (final step in steps) {
        final instruction = _parseMapboxStep(step);
        if (instruction != null) {
          instructions.add(instruction);
        }
      }

      // Extract start and end coordinates from geometry
      final coordinates = geometry['coordinates'] as List;
      final startCoord = coordinates.first;
      final endCoord = coordinates.last;

      return NavigationRoute(
        startPoint: NavigationCoordinate(
          latitude: (startCoord[1] as num).toDouble(),
          longitude: (startCoord[0] as num).toDouble(),
        ),
        endPoint: NavigationCoordinate(
          latitude: (endCoord[1] as num).toDouble(),
          longitude: (endCoord[0] as num).toDouble(),
        ),
        totalDistance: totalDistance,
        totalDuration: totalDuration,
        instructions: instructions,
        geometry: geometry,
      );
    } catch (e) {
      debugPrint('❌ Error parsing Enhanced Mapbox response: $e');
      return null;
    }
  }

  /// Parse individual Mapbox step into NavigationInstruction
  NavigationInstruction? _parseMapboxStep(Map<String, dynamic> step) {
    try {
      final maneuver = step['maneuver'];
      final instruction = maneuver['instruction'] as String;
      final distance = (step['distance'] as num).toDouble();
      final duration =
          (step['duration'] as num).toDouble() / 60; // Convert to minutes
      final type = _mapboxManeuverToType(
        maneuver['type'] as String,
        maneuver['modifier'],
      );

      // Get coordinate from maneuver location
      final location = maneuver['location'] as List;

      return NavigationInstruction(
        instruction: instruction,
        distance: distance,
        duration: duration,
        type: type,
        coordinate: NavigationCoordinate(
          latitude: (location[1] as num).toDouble(),
          longitude: (location[0] as num).toDouble(),
        ),
      );
    } catch (e) {
      debugPrint('❌ Error parsing Mapbox step: $e');
      return null;
    }
  }

  /// Map Mapbox maneuver types to our navigation instruction types
  NavigationInstructionType _mapboxManeuverToType(
    String type,
    dynamic modifier,
  ) {
    switch (type) {
      case 'depart':
        return NavigationInstructionType.start;
      case 'turn':
        if (modifier == 'left') return NavigationInstructionType.turnLeft;
        if (modifier == 'right') return NavigationInstructionType.turnRight;
        if (modifier == 'sharp left')
          return NavigationInstructionType.sharpLeft;
        if (modifier == 'sharp right')
          return NavigationInstructionType.sharpRight;
        if (modifier == 'slight left')
          return NavigationInstructionType.slightLeft;
        if (modifier == 'slight right')
          return NavigationInstructionType.slightRight;
        return NavigationInstructionType.straight;
      case 'continue':
      case 'merge':
        return NavigationInstructionType.straight;
      case 'roundabout':
      case 'rotary':
        return NavigationInstructionType.roundabout;
      case 'arrive':
        return NavigationInstructionType.arrive;
      default:
        return NavigationInstructionType.straight;
    }
  }

  /// Fallback basic routing using simple calculations
  Future<NavigationRoute?> _calculateBasicRoute(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) async {
    try {
      final distance = Geolocator.distanceBetween(
        startLat,
        startLng,
        endLat,
        endLng,
      );
      final duration =
          (distance / 1000) / 50 * 60; // Assume 50 km/h, convert to minutes

      // Create basic instructions
      final instructions = [
        NavigationInstruction(
          instruction: 'Head towards your destination',
          distance: distance,
          duration: duration,
          type: NavigationInstructionType.start,
          coordinate: NavigationCoordinate(
            latitude: startLat,
            longitude: startLng,
          ),
        ),
        NavigationInstruction(
          instruction: 'You have arrived at your destination',
          distance: 0,
          duration: 0,
          type: NavigationInstructionType.arrive,
          coordinate: NavigationCoordinate(latitude: endLat, longitude: endLng),
        ),
      ];

      return NavigationRoute(
        startPoint: NavigationCoordinate(
          latitude: startLat,
          longitude: startLng,
        ),
        endPoint: NavigationCoordinate(latitude: endLat, longitude: endLng),
        totalDistance: distance,
        totalDuration: duration,
        instructions: instructions,
        geometry: {
          'type': 'LineString',
          'coordinates': [
            [startLng, startLat],
            [endLng, endLat],
          ],
        },
      );
    } catch (e) {
      debugPrint('❌ Error creating basic route: $e');
      return null;
    }
  }

  /// Advance to next instruction
  void _advanceToNextInstruction() {
    if (_currentInstructionIndex < _instructions.length - 1) {
      _currentInstructionIndex++;
      _currentInstruction = _instructions[_currentInstructionIndex];

      // 🆕 ISSUE FIX #2 & #3: Clear announcement history for new instruction
      _announcementManager.clearAnnouncementsForNewInstruction();

      // Send new instruction
      _instructionController.add(_currentInstruction!);

      // Fire instruction changed event
      _eventController.add(
        NavigationEvent(
          type: NavigationEventType.instructionChanged,
          instruction: _currentInstruction,
        ),
      );

      debugPrint(
        '📍 Advanced to instruction: ${_currentInstruction!.instruction}',
      );

      // 🆕 ISSUE FIX #3: Immediately announce new instruction
      if (_currentInstruction != null) {
        _announcementManager.announceImmediateInstruction(_currentInstruction!);
      }
    }
  }

  /// Handle arrival at destination
  Future<void> _handleArrival() async {
    try {
      // Announce arrival with voice
      await _announcementManager.announceArrival();

      // Fire arrival event
      _eventController.add(
        NavigationEvent(type: NavigationEventType.arrivedAtDestination),
      );

      debugPrint('🎯 Arrived at destination!');

      // Stop navigation
      await stopNavigation();
    } catch (e) {
      debugPrint('❌ Error handling arrival: $e');
    }
  }

  /// Build progress update
  NavigationProgress _buildProgressUpdate() {
    return NavigationProgress(
      distanceToNextInstruction: _distanceToNextInstruction,
      distanceRemaining: _distanceRemaining,
      estimatedTimeToArrival: _estimatedTimeToArrival,
      currentInstruction: _currentInstruction,
      progress: _currentRoute != null
          ? 1 - (_distanceRemaining / _currentRoute!.totalDistance)
          : 0,
    );
  }

  /// Format distance for display
  String _formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    } else {
      return '${meters.round()} m';
    }
  }

  /// Format ETA for display
  String _formatETA(double minutes) {
    if (minutes >= 60) {
      final hours = (minutes / 60).floor();
      final mins = (minutes % 60).round();
      return '${hours}h ${mins}m';
    } else {
      return '${minutes.round()} min';
    }
  }

  /// Enable/disable voice guidance
  Future<void> setVoiceGuidanceEnabled(bool enabled) async {
    await _announcementManager.setEnabled(enabled);
  }

  /// Set voice guidance language
  Future<void> setVoiceGuidanceLanguage(String languageCode) async {
    await _announcementManager.setLanguage(languageCode);
  }

  /// Test voice guidance
  Future<void> testVoiceGuidance() async {
    await _announcementManager.testVoice();
  }

  /// Get voice guidance status
  bool get isVoiceGuidanceEnabled => _announcementManager.isEnabled;
  String get voiceGuidanceLanguage => _announcementManager.currentLanguage;

  /// Enable/disable background navigation
  Future<void> setBackgroundNavigationEnabled(bool enabled) async {
    _backgroundNavigationEnabled = enabled;
    if (!enabled && _isNavigating) {
      await _foregroundService.stopService();
    }
  }

  /// Get background navigation status
  bool get isBackgroundNavigationEnabled => _backgroundNavigationEnabled;

  /// Dispose resources
  @override
  void dispose() {
    _instructionController.close();
    _progressController.close();
    _eventController.close();
    _announcementManager.reset();
    super.dispose();
  }

  /// Integration with existing DriverFlowService
  /// This method can be called when delivery status changes
  Future<void> handleDeliveryStatusChange(
    String deliveryId,
    String newStatus,
  ) async {
    if (!_isNavigating) return;

    // Stop navigation if delivery is completed or cancelled
    if (newStatus == 'completed' || newStatus == 'cancelled') {
      await stopNavigation();
    }
  }
}

// Data Models

class NavigationRoute {
  final NavigationCoordinate startPoint;
  final NavigationCoordinate endPoint;
  final double totalDistance; // in meters
  final double totalDuration; // in minutes
  final List<NavigationInstruction> instructions;
  final Map<String, dynamic> geometry; // GeoJSON geometry

  NavigationRoute({
    required this.startPoint,
    required this.endPoint,
    required this.totalDistance,
    required this.totalDuration,
    required this.instructions,
    required this.geometry,
  });
}

class NavigationInstruction {
  final String instruction;
  final double distance; // in meters
  final double duration; // in minutes
  final NavigationInstructionType type;
  final NavigationCoordinate coordinate;

  NavigationInstruction({
    required this.instruction,
    required this.distance,
    required this.duration,
    required this.type,
    required this.coordinate,
  });
}

class NavigationCoordinate {
  final double latitude;
  final double longitude;

  NavigationCoordinate({required this.latitude, required this.longitude});
}

class NavigationProgress {
  final double distanceToNextInstruction; // in meters
  final double distanceRemaining; // in meters
  final double estimatedTimeToArrival; // in minutes
  final NavigationInstruction? currentInstruction;
  final double progress; // 0.0 to 1.0

  NavigationProgress({
    required this.distanceToNextInstruction,
    required this.distanceRemaining,
    required this.estimatedTimeToArrival,
    required this.currentInstruction,
    required this.progress,
  });
}

class NavigationEvent {
  final NavigationEventType type;
  final String? context;
  final String? deliveryId;
  final NavigationInstruction? instruction;

  NavigationEvent({
    required this.type,
    this.context,
    this.deliveryId,
    this.instruction,
  });
}

enum NavigationInstructionType {
  start,
  straight,
  turnLeft,
  turnRight,
  slightLeft,
  slightRight,
  sharpLeft,
  sharpRight,
  roundabout,
  arrive,
}

enum NavigationEventType {
  navigationStarted,
  navigationStopped,
  instructionChanged,
  arrivedAtDestination,
  routeRecalculated,
}
