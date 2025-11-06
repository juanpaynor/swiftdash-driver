import 'cash_remittance.dart';
import 'delivery_stop.dart';

class Delivery {
  final String id;
  final String customerId;
  final String? driverId;
  final String vehicleTypeId;
  final DeliveryStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;
  
  // Multi-stop support
  final bool isMultiStop;
  final int totalStops;
  final int currentStopIndex;
  final List<DeliveryStop>? stops; // Populated separately via service
  
  // Scheduled delivery support
  final bool isScheduled;
  final DateTime? scheduledPickupTime;
  
  // Pickup Information
  final String pickupAddress;
  final double pickupLatitude;
  final double pickupLongitude;
  final String pickupContactName;
  final String pickupContactPhone;
  final String? pickupInstructions;
  
  // Delivery Information
  final String deliveryAddress;
  final double deliveryLatitude;
  final double deliveryLongitude;
  final String deliveryContactName;
  final String deliveryContactPhone;
  final String? deliveryInstructions;
  
  // Package Information
  final String packageDescription;
  final double? packageWeight;
  final double? packageValue;
  
  // Pricing & Distance
  final double? distanceKm;
  final int? estimatedDuration; // in minutes
  final double totalPrice;
  
  // Ratings
  final int? customerRating;
  final int? driverRating;
  
  // Proof of Delivery
  final String? proofPhotoUrl;
  final String? pickupProofPhotoUrl; // NEW: Photo taken at pickup
  final String? recipientName;
  final String? deliveryNotes;
  final String? signatureData;
  
  // Payment Information (existing fields in database)
  final String? paymentBy; // 'sender' or 'recipient'
  final String? paymentMethod; // 'credit_card', 'maya_wallet', 'qr_ph', 'cash'
  final String? paymentStatus; // 'pending', 'paid', 'failed', 'cash_pending'
  final double? deliveryFee;
  final double? tipAmount;
  final double? totalAmount;
  
  // ⭐ Fleet Management Fields (Added Nov 3, 2025)
  final String? businessId;        // Which business created this delivery
  final String? fleetVehicleId;    // Which fleet vehicle (if assigned)
  final String? driverSource;      // 'private_fleet', 'public_fleet', 'independent_driver'
  final String? assignmentType;    // 'auto' or 'manual'
  
  Delivery({
    required this.id,
    required this.customerId,
    this.driverId,
    required this.vehicleTypeId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
    this.isMultiStop = false,
    this.totalStops = 0,
    this.currentStopIndex = 0,
    this.stops,
    this.isScheduled = false,
    this.scheduledPickupTime,
    required this.pickupAddress,
    required this.pickupLatitude,
    required this.pickupLongitude,
    required this.pickupContactName,
    required this.pickupContactPhone,
    this.pickupInstructions,
    required this.deliveryAddress,
    required this.deliveryLatitude,
    required this.deliveryLongitude,
    required this.deliveryContactName,
    required this.deliveryContactPhone,
    this.deliveryInstructions,
    required this.packageDescription,
    this.packageWeight,
    this.packageValue,
    this.distanceKm,
    this.estimatedDuration,
    required this.totalPrice,
    this.customerRating,
    this.driverRating,
    this.proofPhotoUrl,
    this.pickupProofPhotoUrl,
    this.recipientName,
    this.deliveryNotes,
    this.signatureData,
    this.paymentBy,
    this.paymentMethod,
    this.paymentStatus,
    this.deliveryFee,
    this.tipAmount,
    this.totalAmount,
    this.businessId,
    this.fleetVehicleId,
    this.driverSource,
    this.assignmentType,
  });
  
  // DEPRECATED: Hard-coded commission calculation
  // Use CommissionService.calculateCommission() instead for dynamic rates
  /// Driver's earnings after platform commission
  /// @deprecated Use CommissionService for accurate, dynamic commission rates
  @Deprecated('Use CommissionService.calculateCommission() for dynamic rates')
  double get driverEarnings => totalPrice * 0.84; // Fallback: 16% commission
  
  // Map database payment method to app payment method
  PaymentMethod get mappedPaymentMethod {
    switch (paymentMethod) {
      case 'credit_card':
      case 'maya_wallet':
      case 'qr_ph':
        return PaymentMethod.card;
      case 'cash':
        return PaymentMethod.cash;
      default:
        return PaymentMethod.cash; // Default fallback
    }
  }
  
  // Check if this delivery requires cash remittance
  bool get requiresCashRemittance => mappedPaymentMethod.requiresRemittance;
  
  // Get display name for payment method
  String get paymentMethodDisplayName {
    switch (paymentMethod) {
      case 'credit_card':
        return 'Credit Card';
      case 'maya_wallet':
        return 'Maya Wallet';
      case 'qr_ph':
        return 'QR Ph';
      case 'cash':
        return 'Cash on Delivery';
      default:
        return 'Unknown';
    }
  }
  
  String get formattedDistance {
    if (distanceKm == null) return 'N/A';
    return '${distanceKm!.toStringAsFixed(1)} km';
  }
  
  String get formattedDuration {
    if (estimatedDuration == null) return 'N/A';
    final hours = estimatedDuration! ~/ 60;
    final minutes = estimatedDuration! % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }
  
  static DeliveryStatus _parseDeliveryStatus(String? statusString) {
    if (statusString == null) return DeliveryStatus.pending;
    
    // ✅ CONFIRMED with Customer App Team on Oct 21, 2025
    // See: RESPONSE_TO_DRIVER_APP_TEAM.md for official status values
    // Database uses snake_case: 'at_pickup', 'package_collected', 'in_transit'
    final statusMap = {
      'pending': DeliveryStatus.pending,
      'driver_offered': DeliveryStatus.driverOffered,
      'driverOffered': DeliveryStatus.driverOffered,
      'driver_assigned': DeliveryStatus.driverAssigned,
      'driverAssigned': DeliveryStatus.driverAssigned,
      'going_to_pickup': DeliveryStatus.goingToPickup,
      'goingToPickup': DeliveryStatus.goingToPickup,
      'at_pickup': DeliveryStatus.pickupArrived,       // ✅ CORRECT per customer app (Oct 29, 2025)
      'pickup_arrived': DeliveryStatus.pickupArrived,  // ❌ LEGACY - still supported for backwards compatibility
      'pickupArrived': DeliveryStatus.pickupArrived,
      'atPickup': DeliveryStatus.pickupArrived,
      'package_collected': DeliveryStatus.packageCollected,  // ✅ CORRECT per customer app
      'packageCollected': DeliveryStatus.packageCollected,
      'picked_up': DeliveryStatus.packageCollected,    // ❌ LEGACY - map to correct enum
      'pickedUp': DeliveryStatus.packageCollected,
      'going_to_destination': DeliveryStatus.goingToDestination,
      'goingToDestination': DeliveryStatus.goingToDestination,
      'in_transit': DeliveryStatus.goingToDestination, // ✅ CORRECT per customer app
      'inTransit': DeliveryStatus.goingToDestination,
      'at_destination': DeliveryStatus.atDestination,
      'atDestination': DeliveryStatus.atDestination,
      'delivered': DeliveryStatus.delivered,
      'cancelled': DeliveryStatus.cancelled,
      'failed': DeliveryStatus.failed,
    };
    
    final mappedStatus = statusMap[statusString];
    if (mappedStatus != null) {
      return mappedStatus;
    }
    
    // Fallback to enum name matching
    try {
      return DeliveryStatus.values.firstWhere(
        (e) => e.toString().split('.').last == statusString,
      );
    } catch (e) {
      print('Warning: Unknown delivery status "$statusString", defaulting to pending');
      return DeliveryStatus.pending;
    }
  }

  factory Delivery.fromJson(Map<String, dynamic> json) {
    try {
      return Delivery(
      id: json['id'],
      customerId: json['customer_id'],
      driverId: json['driver_id'],
      vehicleTypeId: json['vehicle_type_id'],
      status: _parseDeliveryStatus(json['status']),
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : DateTime.parse(json['updated_at']), // fallback to updated_at if created_at is missing
      updatedAt: DateTime.parse(json['updated_at']),
      completedAt: json['completed_at'] != null ? DateTime.parse(json['completed_at']) : null,
      isMultiStop: json['is_multi_stop'] ?? false,
      totalStops: json['total_stops'] ?? 0,
      currentStopIndex: json['current_stop_index'] ?? 0,
      stops: null, // Populated separately via DeliveryStopService
      isScheduled: json['is_scheduled'] ?? false,
      scheduledPickupTime: json['scheduled_pickup_time'] != null 
          ? DateTime.parse(json['scheduled_pickup_time']) 
          : null,
      pickupAddress: json['pickup_address'] ?? '',
      pickupLatitude: json['pickup_latitude']?.toDouble() ?? 0.0,
      pickupLongitude: json['pickup_longitude']?.toDouble() ?? 0.0,
      pickupContactName: json['pickup_contact_name'] ?? '',
      pickupContactPhone: json['pickup_contact_phone'] ?? '',
      pickupInstructions: json['pickup_instructions'] ?? '',
      deliveryAddress: json['delivery_address'] ?? '',
      deliveryLatitude: json['delivery_latitude']?.toDouble() ?? 0.0,
      deliveryLongitude: json['delivery_longitude']?.toDouble() ?? 0.0,
      deliveryContactName: json['delivery_contact_name'] ?? '',
      deliveryContactPhone: json['delivery_contact_phone'] ?? '',
      deliveryInstructions: json['delivery_instructions'] ?? '',
      packageDescription: json['package_description'] ?? '',
      packageWeight: json['package_weight']?.toDouble() ?? 0.0,
      packageValue: json['package_value']?.toDouble() ?? 0.0,
      distanceKm: json['distance_km']?.toDouble() ?? 0.0,
      estimatedDuration: json['estimated_duration'] != null ? int.tryParse(json['estimated_duration'].toString()) : null,
      totalPrice: (json['total_amount'] ?? json['total_price'])?.toDouble() ?? 0.0, // ⚠️ Database uses "total_amount" NOT "total_price"!
      customerRating: json['customer_rating'] != null ? int.tryParse(json['customer_rating'].toString()) : null,
      driverRating: json['driver_rating'] != null ? int.tryParse(json['driver_rating'].toString()) : null, 
      proofPhotoUrl: json['proof_photo_url'] ?? '',
      pickupProofPhotoUrl: json['pickup_proof_photo_url'] ?? '',
      recipientName: json['recipient_name'] ?? '',
      deliveryNotes: json['delivery_notes'] ?? '',
      signatureData: json['signature_data'] ?? '',
      paymentBy: json['payment_by'] ?? '',
      paymentMethod: json['payment_method'] ?? '',
      paymentStatus: json['payment_status'] ?? 'pending',
      deliveryFee: json['delivery_fee']?.toDouble() ?? 0.0,
      tipAmount: json['tip_amount']?.toDouble() ?? 0.0,
      totalAmount: json['total_amount']?.toDouble() ?? 0.0,
      businessId: json['business_id'],
      fleetVehicleId: json['fleet_vehicle_id'],
      driverSource: json['driver_source'],
      assignmentType: json['assignment_type'],
    );
    } catch (e, stackTrace) {
      print('❌ Error parsing Delivery JSON: $e');
      print('📄 JSON payload: $json');
      print('📍 Stack trace: $stackTrace');
      rethrow;
    }
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'customer_id': customerId,
      'driver_id': driverId,
      'vehicle_type_id': vehicleTypeId,
      'status': status.toString().split('.').last,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'is_multi_stop': isMultiStop,
      'total_stops': totalStops,
      'current_stop_index': currentStopIndex,
      'is_scheduled': isScheduled,
      'scheduled_pickup_time': scheduledPickupTime?.toIso8601String(),
      'pickup_address': pickupAddress,
      'pickup_latitude': pickupLatitude,
      'pickup_longitude': pickupLongitude,
      'pickup_contact_name': pickupContactName,
      'pickup_contact_phone': pickupContactPhone,
      'pickup_instructions': pickupInstructions,
      'delivery_address': deliveryAddress,
      'delivery_latitude': deliveryLatitude,
      'delivery_longitude': deliveryLongitude,
      'delivery_contact_name': deliveryContactName,
      'delivery_contact_phone': deliveryContactPhone,
      'delivery_instructions': deliveryInstructions,
      'package_description': packageDescription,
      'package_weight': packageWeight,
      'package_value': packageValue,
      'distance_km': distanceKm,
      'estimated_duration': estimatedDuration,
      'total_price': totalPrice,
      'customer_rating': customerRating,
      'driver_rating': driverRating,
      'proof_photo_url': proofPhotoUrl,
      'pickup_proof_photo_url': pickupProofPhotoUrl,
      'recipient_name': recipientName,
      'delivery_notes': deliveryNotes,
      'signature_data': signatureData,
      'payment_by': paymentBy,
      'payment_method': paymentMethod,
      'payment_status': paymentStatus,
      'delivery_fee': deliveryFee,
      'tip_amount': tipAmount,
      'total_amount': totalAmount,
      'business_id': businessId,
      'fleet_vehicle_id': fleetVehicleId,
      'driver_source': driverSource,
      'assignment_type': assignmentType,
    };
  }
  
  // Add copyWith method for immutable updates
  Delivery copyWith({
    String? id,
    String? customerId,
    String? driverId,
    String? vehicleTypeId,
    DeliveryStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? completedAt,
    bool? isMultiStop,
    int? totalStops,
    int? currentStopIndex,
    List<DeliveryStop>? stops,
    bool? isScheduled,
    DateTime? scheduledPickupTime,
    String? pickupAddress,
    double? pickupLatitude,
    double? pickupLongitude,
    String? pickupContactName,
    String? pickupContactPhone,
    String? pickupInstructions,
    String? deliveryAddress,
    double? deliveryLatitude,
    double? deliveryLongitude,
    String? deliveryContactName,
    String? deliveryContactPhone,
    String? deliveryInstructions,
    String? packageDescription,
    double? packageWeight,
    double? packageValue,
    double? distanceKm,
    int? estimatedDuration,
    double? totalPrice,
    int? customerRating,
    int? driverRating,
    String? proofPhotoUrl,
    String? pickupProofPhotoUrl,
    String? recipientName,
    String? deliveryNotes,
    String? signatureData,
  }) {
    return Delivery(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      driverId: driverId ?? this.driverId,
      vehicleTypeId: vehicleTypeId ?? this.vehicleTypeId,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: completedAt ?? this.completedAt,
      isMultiStop: isMultiStop ?? this.isMultiStop,
      totalStops: totalStops ?? this.totalStops,
      currentStopIndex: currentStopIndex ?? this.currentStopIndex,
      stops: stops ?? this.stops,
      isScheduled: isScheduled ?? this.isScheduled,
      scheduledPickupTime: scheduledPickupTime ?? this.scheduledPickupTime,
      pickupAddress: pickupAddress ?? this.pickupAddress,
      pickupLatitude: pickupLatitude ?? this.pickupLatitude,
      pickupLongitude: pickupLongitude ?? this.pickupLongitude,
      pickupContactName: pickupContactName ?? this.pickupContactName,
      pickupContactPhone: pickupContactPhone ?? this.pickupContactPhone,
      pickupInstructions: pickupInstructions ?? this.pickupInstructions,
      deliveryAddress: deliveryAddress ?? this.deliveryAddress,
      deliveryLatitude: deliveryLatitude ?? this.deliveryLatitude,
      deliveryLongitude: deliveryLongitude ?? this.deliveryLongitude,
      deliveryContactName: deliveryContactName ?? this.deliveryContactName,
      deliveryContactPhone: deliveryContactPhone ?? this.deliveryContactPhone,
      deliveryInstructions: deliveryInstructions ?? this.deliveryInstructions,
      packageDescription: packageDescription ?? this.packageDescription,
      packageWeight: packageWeight ?? this.packageWeight,
      packageValue: packageValue ?? this.packageValue,
      distanceKm: distanceKm ?? this.distanceKm,
      estimatedDuration: estimatedDuration ?? this.estimatedDuration,
      totalPrice: totalPrice ?? this.totalPrice,
      customerRating: customerRating ?? this.customerRating,
      driverRating: driverRating ?? this.driverRating,
      proofPhotoUrl: proofPhotoUrl ?? this.proofPhotoUrl,
      pickupProofPhotoUrl: pickupProofPhotoUrl ?? this.pickupProofPhotoUrl,
      recipientName: recipientName ?? this.recipientName,
      deliveryNotes: deliveryNotes ?? this.deliveryNotes,
      signatureData: signatureData ?? this.signatureData,
    );
  }
}

enum DeliveryStatus {
  pending,              // Waiting for driver assignment
  driverOffered,        // Delivery offered to driver (requires acceptance)
  driverAssigned,       // Driver assigned (ASSIGNED)
  goingToPickup,        // Driver navigating to pickup (GOING_TO_PICKUP) - NEW
  pickupArrived,        // Driver arrived at pickup location (AT_PICKUP)
  packageCollected,     // Driver collected the package (PICKED_UP)
  goingToDestination,   // Driver navigating to destination (GOING_TO_DESTINATION) - NEW  
  atDestination,        // Driver arrived at destination (AT_DESTINATION) - NEW
  delivered,            // Successfully delivered with POD (DELIVERED)
  cancelled,            // Cancelled by customer or system
  failed,               // Delivery failed
}

extension DeliveryStatusExtension on DeliveryStatus {
  /// Get database-compatible snake_case value for status updates
  /// ✅ CONFIRMED with Customer App Team on Oct 21, 2025
  /// See: RESPONSE_TO_DRIVER_APP_TEAM.md
  String get databaseValue {
    switch (this) {
      case DeliveryStatus.pending:
        return 'pending';
      case DeliveryStatus.driverOffered:
        return 'driver_offered';
      case DeliveryStatus.driverAssigned:
        return 'driver_assigned';
      case DeliveryStatus.goingToPickup:
        return 'going_to_pickup';  // Optional status
      case DeliveryStatus.pickupArrived:
        return 'at_pickup';  // ✅ FIXED: Changed from 'pickup_arrived' to match customer app
      case DeliveryStatus.packageCollected:
        return 'package_collected';  // ✅ CORRECT per customer app (NOT 'picked_up')
      case DeliveryStatus.goingToDestination:
        return 'in_transit';  // ✅ CORRECT per customer app
      case DeliveryStatus.atDestination:
        return 'at_destination';  // ✅ Customer app expects this value
      case DeliveryStatus.delivered:
        return 'delivered';
      case DeliveryStatus.cancelled:
        return 'cancelled';
      case DeliveryStatus.failed:
        return 'failed';
    }
  }
  
  String get displayName {
    switch (this) {
      case DeliveryStatus.pending:
        return 'Pending';
      case DeliveryStatus.driverOffered:
        return 'Delivery Offered';
      case DeliveryStatus.driverAssigned:
        return 'Driver Assigned';
      case DeliveryStatus.goingToPickup:
        return 'Going to Pickup';
      case DeliveryStatus.pickupArrived:
        return 'Arrived at Pickup';
      case DeliveryStatus.packageCollected:
        return 'Package Collected';
      case DeliveryStatus.goingToDestination:
        return 'Going to Destination';
      case DeliveryStatus.atDestination:
        return 'Arrived at Destination';
      case DeliveryStatus.delivered:
        return 'Delivered';
      case DeliveryStatus.cancelled:
        return 'Cancelled';
      case DeliveryStatus.failed:
        return 'Failed';
    }
  }
  
  String get driverActionText {
    switch (this) {
      case DeliveryStatus.pending:
        return 'Wait for Offer';
      case DeliveryStatus.driverOffered:
        return 'Accept or Decline';
      case DeliveryStatus.driverAssigned:
        return 'Start Navigation';
      case DeliveryStatus.goingToPickup:
        return 'Navigate to Pickup';
      case DeliveryStatus.pickupArrived:
        return 'Confirm Pickup';
      case DeliveryStatus.packageCollected:
        return 'Start Delivery';
      case DeliveryStatus.goingToDestination:
        return 'Navigate to Destination';
      case DeliveryStatus.atDestination:
        return 'Complete Delivery';
      case DeliveryStatus.delivered:
        return 'Completed';
      default:
        return '';
    }
  }
  
  String get description {
    switch (this) {
      case DeliveryStatus.pending:
        return 'Looking for a driver...';
      case DeliveryStatus.driverOffered:
        return 'Delivery offer sent to driver';
      case DeliveryStatus.driverAssigned:
        return 'Driver accepted order';
      case DeliveryStatus.goingToPickup:
        return 'Driver is on the way to pickup location';
      case DeliveryStatus.pickupArrived:
        return 'Driver has arrived at pickup location';
      case DeliveryStatus.packageCollected:
        return 'Package collected, heading to delivery location';
      case DeliveryStatus.goingToDestination:
        return 'Driver is on the way to destination';
      case DeliveryStatus.atDestination:
        return 'Driver has arrived at destination';
      case DeliveryStatus.delivered:
        return 'Package delivered successfully';
      case DeliveryStatus.cancelled:
        return 'Delivery was cancelled';
      case DeliveryStatus.failed:
        return 'Delivery could not be completed';
    }
  }
}