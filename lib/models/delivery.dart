class Delivery {
  final String id;
  final String customerId;
  final String? driverId;
  final String vehicleTypeId;
  final DeliveryStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;
  
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
  final String? recipientName;
  final String? deliveryNotes;
  final String? signatureData;
  
  const Delivery({
    required this.id,
    required this.customerId,
    this.driverId,
    required this.vehicleTypeId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
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
    this.recipientName,
    this.deliveryNotes,
    this.signatureData,
  });
  
  // Calculate driver earnings (you can adjust this percentage)
  double get driverEarnings => totalPrice * 0.75; // 75% to driver, 25% platform fee
  
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
  
  factory Delivery.fromJson(Map<String, dynamic> json) {
    return Delivery(
      id: json['id'],
      customerId: json['customer_id'],
      driverId: json['driver_id'],
      vehicleTypeId: json['vehicle_type_id'],
      status: DeliveryStatus.values.firstWhere(
        (e) => e.toString().split('.').last == json['status'],
      ),
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      completedAt: json['completed_at'] != null ? DateTime.parse(json['completed_at']) : null,
      pickupAddress: json['pickup_address'],
      pickupLatitude: json['pickup_latitude'].toDouble(),
      pickupLongitude: json['pickup_longitude'].toDouble(),
      pickupContactName: json['pickup_contact_name'],
      pickupContactPhone: json['pickup_contact_phone'],
      pickupInstructions: json['pickup_instructions'],
      deliveryAddress: json['delivery_address'],
      deliveryLatitude: json['delivery_latitude'].toDouble(),
      deliveryLongitude: json['delivery_longitude'].toDouble(),
      deliveryContactName: json['delivery_contact_name'],
      deliveryContactPhone: json['delivery_contact_phone'],
      deliveryInstructions: json['delivery_instructions'],
      packageDescription: json['package_description'],
      packageWeight: json['package_weight']?.toDouble(),
      packageValue: json['package_value']?.toDouble(),
      distanceKm: json['distance_km']?.toDouble(),
      estimatedDuration: json['estimated_duration'],
      totalPrice: json['total_price'].toDouble(),
      customerRating: json['customer_rating'],
      driverRating: json['driver_rating'],
      proofPhotoUrl: json['proof_photo_url'],
      recipientName: json['recipient_name'],
      deliveryNotes: json['delivery_notes'],
      signatureData: json['signature_data'],
    );
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
      'recipient_name': recipientName,
      'delivery_notes': deliveryNotes,
      'signature_data': signatureData,
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
      recipientName: recipientName ?? this.recipientName,
      deliveryNotes: deliveryNotes ?? this.deliveryNotes,
      signatureData: signatureData ?? this.signatureData,
    );
  }
}

enum DeliveryStatus {
  pending,           // Waiting for driver assignment
  driverAssigned,    // Driver assigned but hasn't arrived at pickup
  pickupArrived,     // Driver arrived at pickup location
  packageCollected,  // Driver collected the package
  inTransit,         // Driver is en route to delivery location
  delivered,         // Successfully delivered
  cancelled,         // Cancelled by customer or system
  failed,            // Delivery failed
}

extension DeliveryStatusExtension on DeliveryStatus {
  String get displayName {
    switch (this) {
      case DeliveryStatus.pending:
        return 'Pending';
      case DeliveryStatus.driverAssigned:
        return 'Driver Assigned';
      case DeliveryStatus.pickupArrived:
        return 'Arrived at Pickup';
      case DeliveryStatus.packageCollected:
        return 'Package Collected';
      case DeliveryStatus.inTransit:
        return 'In Transit';
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
        return 'Accept Delivery';
      case DeliveryStatus.driverAssigned:
        return 'Navigate to Pickup';
      case DeliveryStatus.pickupArrived:
        return 'Confirm Pickup';
      case DeliveryStatus.packageCollected:
        return 'Navigate to Delivery';
      case DeliveryStatus.inTransit:
        return 'Complete Delivery';
      default:
        return '';
    }
  }
  
  String get description {
    switch (this) {
      case DeliveryStatus.pending:
        return 'Looking for a driver...';
      case DeliveryStatus.driverAssigned:
        return 'Driver is on the way to pickup location';
      case DeliveryStatus.pickupArrived:
        return 'Driver has arrived at pickup location';
      case DeliveryStatus.packageCollected:
        return 'Package collected, heading to delivery location';
      case DeliveryStatus.inTransit:
        return 'Package is on the way to destination';
      case DeliveryStatus.delivered:
        return 'Package delivered successfully';
      case DeliveryStatus.cancelled:
        return 'Delivery was cancelled';
      case DeliveryStatus.failed:
        return 'Delivery could not be completed';
    }
  }
}