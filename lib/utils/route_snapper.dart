import 'dart:math' as math;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// Utility class to snap a raw GPS coordinate to the nearest point on a route polyline.
class RouteSnapper {
  /// Snaps a [point] to the nearest segment on the [routeGeometry].
  /// Returns the snapped coordinate.
  static Point snapToRoute(Point point, List<List<double>> routeGeometry) {
    if (routeGeometry.isEmpty) return point;
    if (routeGeometry.length == 1) {
      return Point(
        coordinates: Position(
          routeGeometry[0][0], // lng
          routeGeometry[0][1], // lat
        ),
      );
    }

    double minDistance = double.infinity;
    Point snappedPoint = point;

    // Iterate through all segments of the polyline
    for (int i = 0; i < routeGeometry.length - 1; i++) {
      final start = routeGeometry[i];
      final end = routeGeometry[i + 1];

      final p = point;
      final a = Point(coordinates: Position(start[0], start[1]));
      final b = Point(coordinates: Position(end[0], end[1]));

      final closestOnSegment = _getClosestPointOnSegment(p, a, b);
      final distance = _calculateDistance(p, closestOnSegment);

      if (distance < minDistance) {
        minDistance = distance;
        snappedPoint = closestOnSegment;
      }
    }

    return snappedPoint;
  }

  /// Calculates the distance between two points in meters (haversine approximation for short distances).
  /// For snapping logic, Euclidean distance on lat/lng is often sufficient for "closest" check,
  /// but for "off-route" threshold, we need meters.
  static double calculateDistanceInMeters(Point p1, Point p2) {
    const R = 6371000.0; // Earth radius in meters
    final lat1 = p1.coordinates.lat.toDouble() * math.pi / 180;
    final lat2 = p2.coordinates.lat.toDouble() * math.pi / 180;
    final dLat =
        (p2.coordinates.lat.toDouble() - p1.coordinates.lat.toDouble()) *
        math.pi /
        180;
    final dLon =
        (p2.coordinates.lng.toDouble() - p1.coordinates.lng.toDouble()) *
        math.pi /
        180;

    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return R * c;
  }

  // --- Private Helpers ---

  static Point _getClosestPointOnSegment(Point p, Point a, Point b) {
    final x = p.coordinates.lng.toDouble();
    final y = p.coordinates.lat.toDouble();
    final x1 = a.coordinates.lng.toDouble();
    final y1 = a.coordinates.lat.toDouble();
    final x2 = b.coordinates.lng.toDouble();
    final y2 = b.coordinates.lat.toDouble();

    final A = x - x1;
    final B = y - y1;
    final C = x2 - x1;
    final D = y2 - y1;

    final dot = A * C + B * D;
    final lenSq = C * C + D * D;

    double param = -1;
    if (lenSq != 0) {
      param = dot / lenSq;
    }

    double xx, yy;

    if (param < 0) {
      xx = x1;
      yy = y1;
    } else if (param > 1) {
      xx = x2;
      yy = y2;
    } else {
      xx = x1 + param * C;
      yy = y1 + param * D;
    }

    return Point(coordinates: Position(xx, yy));
  }

  static double _calculateDistance(Point p1, Point p2) {
    final dx = p1.coordinates.lng.toDouble() - p2.coordinates.lng.toDouble();
    final dy = p1.coordinates.lat.toDouble() - p2.coordinates.lat.toDouble();
    return math.sqrt(dx * dx + dy * dy);
  }
}
