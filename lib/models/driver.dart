class Driver {
  final String id;
  final String email;
  final String firstName;
  final String lastName;
  final String phoneNumber;
  final String? profileImageUrl;
  final UserStatus userStatus;
  final String userType;
  
  // Driver-specific fields
  final String? vehicleTypeId;
  final String? licenseNumber;
  final String? vehicleModel;
  final bool isVerified;
  final bool isOnline;
  final double? currentLatitude;
  final double? currentLongitude;
  final double rating;
  final int totalDeliveries;
  final DateTime createdAt;
  final DateTime updatedAt;
  
  const Driver({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.phoneNumber,
    this.profileImageUrl,
    required this.userStatus,
    required this.userType,
    this.vehicleTypeId,
    this.licenseNumber,
    this.vehicleModel,
    required this.isVerified,
    required this.isOnline,
    this.currentLatitude,
    this.currentLongitude,
    required this.rating,
    required this.totalDeliveries,
    required this.createdAt,
    required this.updatedAt,
  });
  
  String get fullName => '$firstName $lastName';
  
  factory Driver.fromJson(Map<String, dynamic> json) {
    return Driver(
      id: json['id'],
      email: json['email'],
      firstName: json['first_name'],
      lastName: json['last_name'],
      phoneNumber: json['phone_number'],
      profileImageUrl: json['profile_image_url'],
      userStatus: UserStatus.values.firstWhere(
        (e) => e.toString().split('.').last == json['status'],
        orElse: () => UserStatus.active,
      ),
      userType: json['user_type'],
      vehicleTypeId: json['vehicle_type_id'],
      licenseNumber: json['license_number'],
      vehicleModel: json['vehicle_model'],
      isVerified: json['is_verified'] ?? false,
      isOnline: json['is_online'] ?? false,
      currentLatitude: json['current_latitude']?.toDouble(),
      currentLongitude: json['current_longitude']?.toDouble(),
      rating: (json['rating'] ?? 0.0).toDouble(),
      totalDeliveries: json['total_deliveries'] ?? 0,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'first_name': firstName,
      'last_name': lastName,
      'phone_number': phoneNumber,
      'profile_image_url': profileImageUrl,
      'status': userStatus.toString().split('.').last,
      'user_type': userType,
      'vehicle_type_id': vehicleTypeId,
      'license_number': licenseNumber,
      'vehicle_model': vehicleModel,
      'is_verified': isVerified,
      'is_online': isOnline,
      'current_latitude': currentLatitude,
      'current_longitude': currentLongitude,
      'rating': rating,
      'total_deliveries': totalDeliveries,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

enum UserStatus {
  active,
  inactive,
  suspended,
}

extension UserStatusExtension on UserStatus {
  String get displayName {
    switch (this) {
      case UserStatus.active:
        return 'Active';
      case UserStatus.inactive:
        return 'Inactive';
      case UserStatus.suspended:
        return 'Suspended';
    }
  }
  
  String get description {
    switch (this) {
      case UserStatus.active:
        return 'Your account is active. Complete verification to start delivering.';
      case UserStatus.inactive:
        return 'Your account is currently inactive. Contact support for assistance.';
      case UserStatus.suspended:
        return 'Your account is suspended. Contact support for more information.';
    }
  }
}

extension DriverStatusExtension on Driver {
  String get verificationStatus {
    if (!isVerified) {
      return 'Pending Verification';
    }
    return userStatus.displayName;
  }
  
  String get statusDescription {
    if (!isVerified) {
      return 'Your profile is being reviewed. This typically takes 1-2 business days.';
    }
    return userStatus.description;
  }
}