import 'package:flutter/material.dart';
import '../services/vehicle_type_service.dart';
import '../models/vehicle_type.dart';
import '../core/supabase_config.dart';

class DebugVehicleTypesScreen extends StatefulWidget {
  const DebugVehicleTypesScreen({super.key});

  @override
  State<DebugVehicleTypesScreen> createState() => _DebugVehicleTypesScreenState();
}

class _DebugVehicleTypesScreenState extends State<DebugVehicleTypesScreen> {
  final VehicleTypeService _vehicleTypeService = VehicleTypeService();
  List<VehicleType> _vehicleTypes = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadVehicleTypes();
  }

  Future<void> _loadVehicleTypes() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final types = await _vehicleTypeService.getActiveVehicleTypes();
      setState(() {
        _vehicleTypes = types;
        _isLoading = false;
      });
      print('Successfully loaded ${types.length} vehicle types');
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
      print('Error loading vehicle types: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug Vehicle Types'),
        backgroundColor: SwiftDashColors.darkBlue,
        foregroundColor: SwiftDashColors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadVehicleTypes,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vehicle Types Debug Screen',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: SwiftDashColors.darkBlue,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(),
              )
            else if (_error != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: SwiftDashColors.dangerRed.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: SwiftDashColors.dangerRed),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Error:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: SwiftDashColors.dangerRed,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: const TextStyle(color: SwiftDashColors.dangerRed),
                    ),
                  ],
                ),
              )
            else if (_vehicleTypes.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: SwiftDashColors.warningOrange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: SwiftDashColors.warningOrange),
                ),
                child: const Text(
                  'No vehicle types found. Make sure they exist in the database and are marked as active.',
                  style: TextStyle(color: SwiftDashColors.warningOrange),
                ),
              )
            else
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Found ${_vehicleTypes.length} vehicle types:',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: SwiftDashColors.darkBlue,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    Expanded(
                      child: ListView.builder(
                        itemCount: _vehicleTypes.length,
                        itemBuilder: (context, index) {
                          final vehicleType = _vehicleTypes[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    vehicleType.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: SwiftDashColors.darkBlue,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  
                                  if (vehicleType.description != null) ...[
                                    Text(
                                      vehicleType.description!,
                                      style: const TextStyle(
                                        color: SwiftDashColors.textGrey,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                  
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'ID: ${vehicleType.id}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: SwiftDashColors.textGrey,
                                                fontFamily: 'monospace',
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Max Weight: ${vehicleType.maxWeightKg}kg',
                                              style: const TextStyle(
                                                color: SwiftDashColors.textGrey,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            'Base: ₱${vehicleType.basePrice.toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          Text(
                                            'Per KM: ₱${vehicleType.pricePerKm.toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(
                                        vehicleType.isActive ? Icons.check_circle : Icons.cancel,
                                        color: vehicleType.isActive 
                                          ? SwiftDashColors.successGreen 
                                          : SwiftDashColors.dangerRed,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        vehicleType.isActive ? 'Active' : 'Inactive',
                                        style: TextStyle(
                                          color: vehicleType.isActive 
                                            ? SwiftDashColors.successGreen 
                                            : SwiftDashColors.dangerRed,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}