class ValidationUtils {
  /// Validates Philippine license plate format
  /// Accepts formats like: ABC-1234, AB-123, ABC 1234, ABC1234
  static bool isValidPlateNumber(String plateNumber) {
    if (plateNumber.isEmpty) return false;
    
    // Remove spaces and convert to uppercase for consistent checking
    final cleaned = plateNumber.toUpperCase().replaceAll(' ', '');
    
    // Philippine license plate patterns:
    // Old format: AAA-#### (3 letters, dash, 4 numbers)
    // New format: AAA #### or AAAA ### 
    // Motorcycle: AA-#### (2 letters, dash, 4 numbers)
    final plateRegex = RegExp(r'^[A-Z]{2,4}[-\s]?[0-9]{3,4}$');
    
    return plateRegex.hasMatch(cleaned.replaceAll(' ', '-'));
  }
  
  /// Validates URL format for profile pictures
  static bool isValidImageUrl(String url) {
    if (url.isEmpty) return true; // Optional field
    
    try {
      final uri = Uri.parse(url);
      return uri.hasScheme && 
             (uri.scheme == 'http' || uri.scheme == 'https') &&
             uri.host.isNotEmpty;
    } catch (e) {
      return false;
    }
  }
  
  /// Formats plate number to standard format (ABC-1234)
  static String formatPlateNumber(String plateNumber) {
    if (plateNumber.isEmpty) return plateNumber;
    
    // Remove spaces and convert to uppercase
    final cleaned = plateNumber.toUpperCase().replaceAll(' ', '').replaceAll('-', '');
    
    // Find where letters end and numbers begin
    final match = RegExp(r'^([A-Z]{2,4})([0-9]{3,4})$').firstMatch(cleaned);
    if (match != null) {
      return '${match.group(1)}-${match.group(2)}';
    }
    
    return plateNumber.toUpperCase();
  }
  
  /// Validates vehicle model (basic validation)
  static bool isValidVehicleModel(String model) {
    if (model.isEmpty) return false;
    
    // Basic validation: must have at least 2 characters and contain letters
    return model.trim().length >= 2 && RegExp(r'[a-zA-Z]').hasMatch(model);
  }
  
  /// Validates Philippine phone number format
  /// Accepts formats like: 09XXXXXXXXX, +639XXXXXXXXX, 639XXXXXXXXX
  static bool isValidPhoneNumber(String phoneNumber) {
    if (phoneNumber.isEmpty) return false;
    
    // Remove spaces and hyphens
    final cleaned = phoneNumber.replaceAll(RegExp(r'[\s\-]'), '');
    
    // Philippine phone number patterns:
    // Mobile: 09XXXXXXXXX (11 digits starting with 09)
    // International: +639XXXXXXXXX or 639XXXXXXXXX
    final phoneRegex = RegExp(r'^(\+?63|0)?9\d{9}$');
    
    return phoneRegex.hasMatch(cleaned);
  }
}