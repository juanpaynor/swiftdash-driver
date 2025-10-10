/// SwiftDash App Assets
/// Centralized management of all app assets including logos, icons, and images
class AppAssets {
  // Private constructor to prevent instantiation
  AppAssets._();
  
  // Base paths
  static const String _imagesPath = 'assets/images';
  static const String _logosPath = '$_imagesPath/logos';
  static const String _iconsPath = '$_imagesPath/icons';
  
  // === LOGOS ===
  /// Main SwiftDash Driver logo
  static const String logo = '$_logosPath/Swiftdash_Driver.png';
  
  /// White version of logo (for dark backgrounds)
  static const String logoWhite = '$_logosPath/swiftdash_logo_white.png';
  
  /// Logo with text (full branding)
  static const String logoWithText = '$_logosPath/swiftdash_logo_with_text.png';
  
  /// Small logo for app bar/navigation
  static const String logoSmall = '$_logosPath/swiftdash_logo_small.png';
  
  // === ICONS ===
  /// Driver avatar placeholder
  static const String driverAvatar = '$_iconsPath/driver_avatar.png';
  
  /// Delivery box icon
  static const String deliveryBox = '$_iconsPath/delivery_box.png';
  
  /// Vehicle icons
  static const String carIcon = '$_iconsPath/car.png';
  static const String bikeIcon = '$_iconsPath/bike.png';
  static const String truckIcon = '$_iconsPath/truck.png';
  
  /// Status icons
  static const String onlineIcon = '$_iconsPath/online.png';
  static const String offlineIcon = '$_iconsPath/offline.png';
  static const String deliveryIcon = '$_iconsPath/delivery.png';
  
  // === ILLUSTRATIONS ===
  /// Empty state illustrations
  static const String noDeliveries = '$_imagesPath/no_deliveries.png';
  static const String locationPermission = '$_imagesPath/location_permission.png';
  static const String networkError = '$_imagesPath/network_error.png';
  
  /// Onboarding illustrations
  static const String onboardingStep1 = '$_imagesPath/onboarding_1.png';
  static const String onboardingStep2 = '$_imagesPath/onboarding_2.png';
  static const String onboardingStep3 = '$_imagesPath/onboarding_3.png';
  
  // === UTILITY METHODS ===
  
  /// Get logo based on theme (light/dark)
  static String getLogoForTheme({bool isDark = false}) {
    return isDark ? logoWhite : logo;
  }
  
  /// Get vehicle icon by type
  static String getVehicleIcon(String vehicleType) {
    switch (vehicleType.toLowerCase()) {
      case 'car':
      case 'sedan':
      case 'hatchback':
        return carIcon;
      case 'bike':
      case 'motorcycle':
      case 'scooter':
        return bikeIcon;
      case 'truck':
      case 'van':
      case 'pickup':
        return truckIcon;
      default:
        return carIcon; // Default fallback
    }
  }
  
  /// Get status icon by driver status
  static String getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'online':
      case 'available':
        return onlineIcon;
      case 'offline':
      case 'unavailable':
        return offlineIcon;
      case 'delivering':
      case 'busy':
        return deliveryIcon;
      default:
        return offlineIcon; // Default fallback
    }
  }
}