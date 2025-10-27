/// Model for individual delivery stops in multi-stop deliveries
/// Each delivery can have multiple stops (1 pickup + multiple dropoffs)
class DeliveryStop {
  final String id;
  final String deliveryId;
  final int stopNumber; // 0 = pickup, 1+ = dropoffs
  final String stopType; // 'pickup' or 'dropoff'
  final DeliveryStopStatus status;
  
  // Location
  final String address;
  final double latitude;
  final double longitude;
  
  // Contact
  final String contactName;
  final String contactPhone;
  final String? instructions;
  
  // Proof of delivery
  final String? proofPhotoUrl;
  final String? signatureUrl;
  final String? completionNotes;
  
  // Timestamps
  final DateTime? arrivedAt;
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  
  const DeliveryStop({
    required this.id,
    required this.deliveryId,
    required this.stopNumber,
    required this.stopType,
    required this.status,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.contactName,
    required this.contactPhone,
    this.instructions,
    this.proofPhotoUrl,
    this.signatureUrl,
    this.completionNotes,
    this.arrivedAt,
    this.completedAt,
    required this.createdAt,
    required this.updatedAt,
  });
  
  // Convenience getters
  bool get isPickup => stopType == 'pickup';
  bool get isDropoff => stopType == 'dropoff';
  bool get isPending => status == DeliveryStopStatus.pending;
  bool get isInProgress => status == DeliveryStopStatus.inProgress;
  bool get isCompleted => status == DeliveryStopStatus.completed;
  bool get isFailed => status == DeliveryStopStatus.failed;
  
  // Display helpers
  String get stopTypeDisplay => isPickup ? 'Pickup' : 'Drop-off #$stopNumber';
  
  String get statusDisplay {
    switch (status) {
      case DeliveryStopStatus.pending:
        return 'Pending';
      case DeliveryStopStatus.inProgress:
        return 'In Progress';
      case DeliveryStopStatus.completed:
        return 'Completed';
      case DeliveryStopStatus.failed:
        return 'Failed';
    }
  }
  
  // Create from JSON
  factory DeliveryStop.fromJson(Map<String, dynamic> json) {
    return DeliveryStop(
      id: json['id'] as String,
      deliveryId: json['delivery_id'] as String,
      stopNumber: json['stop_number'] as int,
      stopType: json['stop_type'] as String,
      status: _parseStatus(json['status'] as String?),
      address: json['address'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      contactName: json['contact_name'] as String,
      contactPhone: json['contact_phone'] as String,
      instructions: json['instructions'] as String?,
      proofPhotoUrl: json['proof_photo_url'] as String?,
      signatureUrl: json['signature_url'] as String?,
      completionNotes: json['completion_notes'] as String?,
      arrivedAt: json['arrived_at'] != null 
          ? DateTime.parse(json['arrived_at'] as String) 
          : null,
      completedAt: json['completed_at'] != null 
          ? DateTime.parse(json['completed_at'] as String) 
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
  
  // Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'delivery_id': deliveryId,
      'stop_number': stopNumber,
      'stop_type': stopType,
      'status': status.toString().split('.').last,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'contact_name': contactName,
      'contact_phone': contactPhone,
      'instructions': instructions,
      'proof_photo_url': proofPhotoUrl,
      'signature_url': signatureUrl,
      'completion_notes': completionNotes,
      'arrived_at': arrivedAt?.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
  
  // Copy with method for immutable updates
  DeliveryStop copyWith({
    String? id,
    String? deliveryId,
    int? stopNumber,
    String? stopType,
    DeliveryStopStatus? status,
    String? address,
    double? latitude,
    double? longitude,
    String? contactName,
    String? contactPhone,
    String? instructions,
    String? proofPhotoUrl,
    String? signatureUrl,
    String? completionNotes,
    DateTime? arrivedAt,
    DateTime? completedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DeliveryStop(
      id: id ?? this.id,
      deliveryId: deliveryId ?? this.deliveryId,
      stopNumber: stopNumber ?? this.stopNumber,
      stopType: stopType ?? this.stopType,
      status: status ?? this.status,
      address: address ?? this.address,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      contactName: contactName ?? this.contactName,
      contactPhone: contactPhone ?? this.contactPhone,
      instructions: instructions ?? this.instructions,
      proofPhotoUrl: proofPhotoUrl ?? this.proofPhotoUrl,
      signatureUrl: signatureUrl ?? this.signatureUrl,
      completionNotes: completionNotes ?? this.completionNotes,
      arrivedAt: arrivedAt ?? this.arrivedAt,
      completedAt: completedAt ?? this.completedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
  
  // Parse status string to enum
  static DeliveryStopStatus _parseStatus(String? status) {
    if (status == null) return DeliveryStopStatus.pending;
    
    switch (status.toLowerCase()) {
      case 'pending':
        return DeliveryStopStatus.pending;
      case 'in_progress':
      case 'inProgress':
        return DeliveryStopStatus.inProgress;
      case 'completed':
        return DeliveryStopStatus.completed;
      case 'failed':
        return DeliveryStopStatus.failed;
      default:
        return DeliveryStopStatus.pending;
    }
  }
}

/// Status enum for delivery stops
enum DeliveryStopStatus {
  pending,      // Not started yet
  inProgress,   // Driver has arrived at location
  completed,    // Stop completed with proof
  failed,       // Stop failed
}

extension DeliveryStopStatusExtension on DeliveryStopStatus {
  String get databaseValue {
    switch (this) {
      case DeliveryStopStatus.pending:
        return 'pending';
      case DeliveryStopStatus.inProgress:
        return 'in_progress';
      case DeliveryStopStatus.completed:
        return 'completed';
      case DeliveryStopStatus.failed:
        return 'failed';
    }
  }
  
  String get displayName {
    switch (this) {
      case DeliveryStopStatus.pending:
        return 'Pending';
      case DeliveryStopStatus.inProgress:
        return 'In Progress';
      case DeliveryStopStatus.completed:
        return 'Completed';
      case DeliveryStopStatus.failed:
        return 'Failed';
    }
  }
}
