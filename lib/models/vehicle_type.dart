class VehicleType {
  final String id;
  final String name;
  final String? description;
  final double maxWeightKg;
  final double basePrice;
  final double pricePerKm;
  final String? iconUrl;
  final bool isActive;
  
  const VehicleType({
    required this.id,
    required this.name,
    this.description,
    required this.maxWeightKg,
    required this.basePrice,
    required this.pricePerKm,
    this.iconUrl,
    this.isActive = true,
  });
  
  factory VehicleType.fromJson(Map<String, dynamic> json) {
    return VehicleType(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'],
      maxWeightKg: (json['max_weight_kg'] ?? 0).toDouble(),
      basePrice: (json['base_price'] ?? 0).toDouble(),
      pricePerKm: (json['price_per_km'] ?? 0).toDouble(),
      iconUrl: json['icon_url'],
      isActive: json['is_active'] ?? true,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'max_weight_kg': maxWeightKg,
      'base_price': basePrice,
      'price_per_km': pricePerKm,
      'icon_url': iconUrl,
      'is_active': isActive,
    };
  }

  // Helper methods for formatting display
  String get formattedBasePrice => '₱${basePrice.toStringAsFixed(2)}';
  String get formattedPricePerKm => '₱${pricePerKm.toStringAsFixed(2)}/km';
  String get formattedMaxWeight => '${maxWeightKg.toStringAsFixed(0)}kg';

  @override
  String toString() {
    return 'VehicleType(id: $id, name: $name, maxWeight: $maxWeightKg kg, basePrice: $basePrice, pricePerKm: $pricePerKm)';
  }
}