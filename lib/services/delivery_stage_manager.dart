import 'package:flutter/material.dart';
import '../models/delivery.dart';

/// Represents the three visual stages of delivery flow
enum DeliveryStage {
  headingToPickup,    // Stage 1: Order Accepted → Heading to Pickup
  headingToDelivery,  // Stage 2: Package Collected → Heading to Drop-off  
  deliveryComplete    // Stage 3: Delivery Complete
}

/// Manages the mapping between delivery statuses and visual stages
class DeliveryStageManager {
  /// Map delivery status to appropriate visual stage
  static DeliveryStage getStageFromStatus(DeliveryStatus status) {
    switch (status) {
      // Stage 1: Focus on pickup location and sender details
      case DeliveryStatus.driverAssigned:
      case DeliveryStatus.goingToPickup:
      case DeliveryStatus.pickupArrived:
        return DeliveryStage.headingToPickup;
        
      // Stage 2: Focus on delivery location and recipient details  
      case DeliveryStatus.packageCollected:
      case DeliveryStatus.goingToDestination:
      case DeliveryStatus.atDestination:
        return DeliveryStage.headingToDelivery;
        
      // Stage 3: Show completion summary and earnings
      case DeliveryStatus.delivered:
        return DeliveryStage.deliveryComplete;
        
      default:
        return DeliveryStage.headingToPickup;
    }
  }

  /// Get stage display name for headers
  static String getStageDisplayName(DeliveryStage stage, String orderId) {
    final orderNumber = orderId.substring(0, 8).toUpperCase();
    switch (stage) {
      case DeliveryStage.headingToPickup:
        return 'Order #$orderNumber - To Pickup';
      case DeliveryStage.headingToDelivery:
        return 'Order #$orderNumber - To Deliver';
      case DeliveryStage.deliveryComplete:
        return 'Delivery Complete';
    }
  }

  /// Get slider text for current stage
  static String getSliderText(DeliveryStage stage, DeliveryStatus status) {
    switch (stage) {
      case DeliveryStage.headingToPickup:
        if (status == DeliveryStatus.pickupArrived) {
          return 'Slide After Pickup';
        }
        return 'Use Navigation Button Below';
        
      case DeliveryStage.headingToDelivery:
        if (status == DeliveryStatus.atDestination) {
          return 'Slide After Delivery';
        }
        return 'Use Navigation Button Below';
        
      case DeliveryStage.deliveryComplete:
        return 'Delivery Completed';
    }
  }

  /// Check if slider should be enabled for current status
  static bool isSliderEnabled(DeliveryStage stage, DeliveryStatus status) {
    // FOR TESTING: Always enable slider to test flow from anywhere
    // TODO: Re-enable strict checks for production
    switch (stage) {
      case DeliveryStage.headingToPickup:
        return true; // Production: status == DeliveryStatus.pickupArrived
      case DeliveryStage.headingToDelivery:
        return true; // Production: status == DeliveryStatus.atDestination
      case DeliveryStage.deliveryComplete:
        return false; // No slider in completion stage
    }
  }

  /// Get next status when slider is confirmed
  static DeliveryStatus getNextStatusFromSlider(DeliveryStage stage) {
    switch (stage) {
      case DeliveryStage.headingToPickup:
        return DeliveryStatus.packageCollected;
      case DeliveryStage.headingToDelivery:
        return DeliveryStatus.delivered;
      case DeliveryStage.deliveryComplete:
        throw Exception('No next status from completion stage');
    }
  }

  /// Check if real-time broadcasting should be active
  static bool shouldBroadcastLocation(DeliveryStatus status) {
    return status == DeliveryStatus.goingToPickup || 
           status == DeliveryStatus.goingToDestination;
  }

  /// Get stage-specific progress data for WebSocket broadcasting
  static Map<String, dynamic> getStageProgressData({
    required DeliveryStage stage,
    required DeliveryStatus status,
    required double distanceToTarget,
    required int etaMinutes,
  }) {
    switch (stage) {
      case DeliveryStage.headingToPickup:
        return {
          "route_progress": {
            "distance_to_pickup_km": distanceToTarget,
            "eta_minutes": etaMinutes,
            "traffic_status": "moderate"
          }
        };
        
      case DeliveryStage.headingToDelivery:
        // Calculate completion percentage (rough estimate)
        final completionPercentage = _calculateCompletionPercentage(distanceToTarget);
        return {
          "delivery_progress": {
            "distance_to_destination_km": distanceToTarget,
            "eta_minutes": etaMinutes,
            "completion_percentage": completionPercentage,
            "traffic_conditions": "light"
          }
        };
        
      case DeliveryStage.deliveryComplete:
        return {}; // No progress data for completed deliveries
    }
  }

  /// Calculate rough completion percentage based on distance
  static int _calculateCompletionPercentage(double distanceRemaining) {
    // Simple heuristic: assume average delivery is 5km total
    const averageTotalDistance = 5.0;
    final progressDistance = averageTotalDistance - distanceRemaining;
    final percentage = (progressDistance / averageTotalDistance * 100).clamp(0, 100);
    return percentage.round();
  }

  /// Get primary action button text for current stage/status
  static String getPrimaryActionText(DeliveryStatus status) {
    switch (status) {
      case DeliveryStatus.driverAssigned:
        return 'Navigate to Pickup';
      case DeliveryStatus.goingToPickup:
        return 'Arrived at Pickup';
      case DeliveryStatus.pickupArrived:
        return 'Slide After Pickup →';
      case DeliveryStatus.packageCollected:
        return 'Navigate to Destination';
      case DeliveryStatus.goingToDestination:
        return 'Arrived at Destination';
      case DeliveryStatus.atDestination:
        return 'Slide After Delivery →';
      case DeliveryStatus.delivered:
        return 'Find New Orders';
      default:
        return 'Continue';
    }
  }

  /// Get stage-specific color scheme
  static DeliveryStageColors getStageColors(DeliveryStage stage) {
    switch (stage) {
      case DeliveryStage.headingToPickup:
        return DeliveryStageColors(
          primary: const Color(0xFF2196F3), // Blue
          accent: const Color(0xFF1976D2),
          background: const Color(0xFFE3F2FD),
        );
      case DeliveryStage.headingToDelivery:
        return DeliveryStageColors(
          primary: const Color(0xFF9C27B0), // Purple
          accent: const Color(0xFF7B1FA2),
          background: const Color(0xFFF3E5F5),
        );
      case DeliveryStage.deliveryComplete:
        return DeliveryStageColors(
          primary: const Color(0xFF4CAF50), // Green
          accent: const Color(0xFF388E3C),
          background: const Color(0xFFE8F5E8),
        );
    }
  }

  /// Get icon for delivery stage
  static IconData getStageIcon(DeliveryStage stage) {
    switch (stage) {
      case DeliveryStage.headingToPickup:
        return Icons.store;
      case DeliveryStage.headingToDelivery:
        return Icons.local_shipping;
      case DeliveryStage.deliveryComplete:
        return Icons.check_circle;
    }
  }

  /// Get short label for delivery stage
  static String getStageLabel(DeliveryStage stage) {
    switch (stage) {
      case DeliveryStage.headingToPickup:
        return 'Heading to Pickup';
      case DeliveryStage.headingToDelivery:
        return 'Delivering to Customer';
      case DeliveryStage.deliveryComplete:
        return 'Complete';
    }
  }
}

/// Color scheme for delivery stages
class DeliveryStageColors {
  final Color primary;
  final Color accent;
  final Color background;

  const DeliveryStageColors({
    required this.primary,
    required this.accent,
    required this.background,
  });
}

/// Extensions for delivery stage functionality
extension DeliveryExtensions on Delivery {
  /// Get current visual stage for this delivery
  DeliveryStage get currentStage => DeliveryStageManager.getStageFromStatus(status);
  
  /// Check if real-time broadcasting should be active
  bool get shouldBroadcast => DeliveryStageManager.shouldBroadcastLocation(status);
  
  /// Get stage display name
  String get stageDisplayName => DeliveryStageManager.getStageDisplayName(currentStage, id);
  
  /// Get stage colors
  DeliveryStageColors get stageColors => DeliveryStageManager.getStageColors(currentStage);
}