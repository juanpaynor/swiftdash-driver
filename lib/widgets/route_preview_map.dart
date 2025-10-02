import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import '../services/mapbox_service.dart';
import '../core/supabase_config.dart';

class RoutePreviewMap extends StatefulWidget {
  final double pickupLat;
  final double pickupLng;
  final double deliveryLat;
  final double deliveryLng;
  final RouteData? routeData;
  final double? height; // Optional custom height

  const RoutePreviewMap({
    super.key,
    required this.pickupLat,
    required this.pickupLng,
    required this.deliveryLat,
    required this.deliveryLng,
    this.routeData,
    this.height,
  });

  @override
  State<RoutePreviewMap> createState() => _RoutePreviewMapState();
}

class _RoutePreviewMapState extends State<RoutePreviewMap> {
  MapboxMap? _mapboxMap;

  @override
  Widget build(BuildContext context) {
    // Responsive height calculation
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    
    // Calculate responsive height (25% of screen height, with bounds)
    double mapHeight = widget.height ?? screenHeight * 0.25;
    
    // Apply bounds: minimum 180px, maximum 300px
    mapHeight = mapHeight.clamp(180.0, 300.0);
    
    // Adjust for smaller screens
    if (screenWidth < 360) {
      mapHeight = mapHeight * 0.9; // Slightly smaller for small screens
    }
    
    return Container(
      height: mapHeight,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SwiftDashColors.textGrey.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: MapWidget(
          key: ValueKey('${widget.pickupLat}-${widget.pickupLng}-${widget.deliveryLat}-${widget.deliveryLng}'),
          cameraOptions: CameraOptions(
            center: Point(
              coordinates: Position(
                (widget.pickupLng + widget.deliveryLng) / 2,
                (widget.pickupLat + widget.deliveryLat) / 2,
              ),
            ),
            zoom: 11.0,
          ),
          onMapCreated: (MapboxMap mapboxMap) async {
            _mapboxMap = mapboxMap;
            await _setupMap();
          },
        ),
      ),
    );
  }

  Future<void> _setupMap() async {
    if (_mapboxMap == null) return;

    try {
      // Add pickup marker (green)
      await _addMarker(
        widget.pickupLat,
        widget.pickupLng,
        'pickup',
        SwiftDashColors.successGreen,
        'P',
      );

      // Add delivery marker (red)
      await _addMarker(
        widget.deliveryLat,
        widget.deliveryLng,
        'delivery',
        SwiftDashColors.dangerRed,
        'D',
      );

      // Add route line if available
      if (widget.routeData != null) {
        await _addRouteLine();
      }

      // Fit bounds to show both markers
      await _fitBounds();
    } catch (e) {
      print('Error setting up map: $e');
    }
  }

  Future<void> _addMarker(
    double lat,
    double lng,
    String id,
    Color color,
    String text,
  ) async {
    try {
      await _mapboxMap!.annotations.createPointAnnotationManager().then((manager) async {
        await manager.create(
          PointAnnotationOptions(
            geometry: Point(coordinates: Position(lng, lat)),
            textField: text,
            textSize: 12.0,
            textColor: Colors.white.value,
            iconSize: 1.0,
            iconColor: color.value,
          ),
        );
      });
    } catch (e) {
      print('Error adding marker: $e');
    }
  }

  Future<void> _addRouteLine() async {
    if (widget.routeData?.geometry == null) return;

    try {
      final coordinates = widget.routeData!.geometry['coordinates'] as List;
      final lineCoordinates = coordinates
          .map((coord) => Position(coord[0].toDouble(), coord[1].toDouble()))
          .toList();

      await _mapboxMap!.annotations.createPolylineAnnotationManager().then((manager) async {
        await manager.create(
          PolylineAnnotationOptions(
            geometry: LineString(coordinates: lineCoordinates),
            lineColor: SwiftDashColors.lightBlue.value,
            lineWidth: 3.0,
          ),
        );
      });
    } catch (e) {
      print('Error adding route line: $e');
    }
  }

  Future<void> _fitBounds() async {
    try {
      final bbox = widget.routeData?.bbox;
      if (bbox != null && bbox.length >= 4) {
        await _mapboxMap!.flyTo(
          CameraOptions(
            center: Point(coordinates: Position(
              (bbox[0] + bbox[2]) / 2, // center longitude
              (bbox[1] + bbox[3]) / 2, // center latitude
            )),
            zoom: 11.0,
            padding: MbxEdgeInsets(top: 20, left: 20, bottom: 20, right: 20),
          ),
          MapAnimationOptions(duration: 1000),
        );
      } else {
        // Fallback: center between pickup and delivery
        final centerLng = (widget.pickupLng + widget.deliveryLng) / 2;
        final centerLat = (widget.pickupLat + widget.deliveryLat) / 2;
        
        await _mapboxMap!.flyTo(
          CameraOptions(
            center: Point(coordinates: Position(centerLng, centerLat)),
            zoom: 12.0,
          ),
          MapAnimationOptions(duration: 1000),
        );
      }
    } catch (e) {
      print('Error fitting bounds: $e');
    }
  }
}

// Simplified route preview for when map fails to load
class SimpleRoutePreview extends StatelessWidget {
  final String pickupAddress;
  final String deliveryAddress;
  final RouteData? routeData;
  final double? height;

  const SimpleRoutePreview({
    super.key,
    required this.pickupAddress,
    required this.deliveryAddress,
    this.routeData,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    // Responsive height calculation (same as map)
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    
    double containerHeight = height ?? screenHeight * 0.25;
    containerHeight = containerHeight.clamp(180.0, 300.0);
    
    if (screenWidth < 360) {
      containerHeight = containerHeight * 0.9;
    }
    
    return Container(
      height: containerHeight,
      width: double.infinity,
      padding: EdgeInsets.all(screenWidth < 360 ? 12 : 16),
      decoration: BoxDecoration(
        color: SwiftDashColors.backgroundGrey,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SwiftDashColors.textGrey.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Header with route info
          if (routeData != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: SwiftDashColors.lightBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.route, size: 18, color: SwiftDashColors.lightBlue),
                  const SizedBox(width: 6),
                  Text(
                    '${MapboxService.formatDistance(routeData!.distance)} • ${MapboxService.formatDuration(routeData!.duration)}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: SwiftDashColors.lightBlue,
                    ),
                  ),
                ],
              ),
            ),
          
          const Spacer(),
          
          // Pickup
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: SwiftDashColors.successGreen,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PICKUP',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: SwiftDashColors.successGreen,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      pickupAddress,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          // Arrow with spacing
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                const SizedBox(width: 6),
                Container(
                  width: 2,
                  height: 20,
                  color: SwiftDashColors.textGrey.withOpacity(0.5),
                ),
                const SizedBox(width: 10),
                Icon(
                  Icons.arrow_downward,
                  size: 16,
                  color: SwiftDashColors.textGrey,
                ),
              ],
            ),
          ),
          
          // Delivery
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: SwiftDashColors.dangerRed,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DELIVERY',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: SwiftDashColors.dangerRed,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      deliveryAddress,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const Spacer(),
          
          // Map unavailable notice
          if (routeData == null)
            Center(
              child: Text(
                'Route preview unavailable',
                style: TextStyle(
                  fontSize: 12,
                  color: SwiftDashColors.textGrey,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }
}