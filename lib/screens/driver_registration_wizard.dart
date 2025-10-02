import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_config.dart';
import '../services/auth_service.dart';
import '../models/vehicle_type.dart';
import '../services/vehicle_type_service.dart';
import '../services/document_upload_service.dart';

class DriverRegistrationWizard extends StatefulWidget {
  const DriverRegistrationWizard({super.key});

  @override
  State<DriverRegistrationWizard> createState() => _DriverRegistrationWizardState();
}

class _DriverRegistrationWizardState extends State<DriverRegistrationWizard> {
  final PageController _pageController = PageController();
  final AuthService _authService = AuthService();
  final VehicleTypeService _vehicleTypeService = VehicleTypeService();
  final DocumentUploadService _documentService = DocumentUploadService();
  
  int _currentPage = 0;
  bool _isLoading = false;
  
  // Form controllers
  final _personalFormKey = GlobalKey<FormState>();
  final _vehicleFormKey = GlobalKey<FormState>();
  final _documentsFormKey = GlobalKey<FormState>();
  
  // Personal info
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _licenseNumberController = TextEditingController();
  final _ltfrbNumberController = TextEditingController();
  
  // Vehicle info
  final _vehicleModelController = TextEditingController();
  VehicleType? _selectedVehicleType;
  List<VehicleType> _vehicleTypes = [];
  bool _loadingVehicleTypes = false;
  
  // Images
  File? _profileImage;
  File? _vehicleImage;

  @override
  void initState() {
    super.initState();
    _loadVehicleTypes();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _licenseNumberController.dispose();
    _ltfrbNumberController.dispose();
    _vehicleModelController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadVehicleTypes() async {
    setState(() {
      _loadingVehicleTypes = true;
    });
    
    try {
      print('Loading vehicle types...');
      final types = await _vehicleTypeService.getActiveVehicleTypes();
      print('Loaded ${types.length} vehicle types');
      for (final type in types) {
        print('- ${type.name} (${type.id})');
      }
      setState(() {
        _vehicleTypes = types;
        _loadingVehicleTypes = false;
      });
    } catch (e) {
      print('Error loading vehicle types: $e');
      setState(() {
        _loadingVehicleTypes = false;
      });
      _showError('Failed to load vehicle types: $e');
    }
  }

  Future<void> _pickImage(bool isProfile) async {
    try {
      final File? image = await _documentService.showImageSourceDialog(context);
      
      if (image != null) {
        setState(() {
          if (isProfile) {
            _profileImage = image;
          } else {
            _vehicleImage = image;
          }
        });
      }
    } catch (e) {
      _showError('Failed to pick image: $e');
    }
  }

  Future<void> _completeRegistration() async {
    if (!_documentsFormKey.currentState!.validate()) return;
    
    setState(() => _isLoading = true);
    
    try {
      final user = _authService.currentUser;
      if (user == null) throw Exception('No authenticated user');
      
      String? profileImageUrl;
      String? vehicleImageUrl;
      
      // Upload images using document service
      if (_profileImage != null) {
        profileImageUrl = await _documentService.uploadDriverProfilePicture(
          _profileImage!,
          user.id,
        );
      }
      
      if (_vehicleImage != null) {
        vehicleImageUrl = await _documentService.uploadVehiclePicture(
          _vehicleImage!,
          user.id,
        );
      }
      
      // Create user profile
      await Supabase.instance.client.from('user_profiles').upsert({
        'id': user.id,
        'phone_number': _phoneController.text.trim(),
        'first_name': _firstNameController.text.trim(),
        'last_name': _lastNameController.text.trim(),
        'user_type': 'driver',
        'profile_image_url': profileImageUrl,
        'status': 'active',
      });
      
      // Create driver profile
      await Supabase.instance.client.from('driver_profiles').upsert({
        'id': user.id,
        'vehicle_type_id': _selectedVehicleType?.id,
        'license_number': _licenseNumberController.text.trim(),
        'ltfrb_number': _ltfrbNumberController.text.trim(),
        'vehicle_model': _vehicleModelController.text.trim(),
        'profile_picture_url': profileImageUrl,
        'vehicle_picture_url': vehicleImageUrl,
        'is_verified': false, // Admin verification required
        'is_online': false,
        'is_available': false,
        'rating': 0.0,
        'total_deliveries': 0,
      });
      
      // Show success and navigate
      _showSuccess('Registration completed! Your account is pending admin verification.');
      
      // Navigate back to auth wrapper
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/');
      }
      
    } catch (e) {
      _showError('Registration failed: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _nextPage() {
    if (_currentPage < 2) {
      // Validate current page
      bool isValid = false;
      switch (_currentPage) {
        case 0:
          isValid = _personalFormKey.currentState?.validate() ?? false;
          break;
        case 1:
          isValid = _vehicleFormKey.currentState?.validate() ?? false;
          isValid = isValid && _selectedVehicleType != null;
          break;
      }
      
      if (isValid) {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: SwiftDashColors.dangerRed,
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: SwiftDashColors.successGreen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SwiftDashColors.backgroundGrey,
      appBar: AppBar(
        title: const Text('Driver Registration'),
        backgroundColor: SwiftDashColors.darkBlue,
        foregroundColor: SwiftDashColors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Progress indicator
          Container(
            padding: const EdgeInsets.all(16),
            color: SwiftDashColors.white,
            child: Row(
              children: [
                for (int i = 0; i < 3; i++) ...[
                  Expanded(
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: i <= _currentPage 
                          ? SwiftDashColors.lightBlue 
                          : SwiftDashColors.textGrey.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  if (i < 2) const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          
          // Page content
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: (page) => setState(() => _currentPage = page),
              children: [
                _buildPersonalInfoPage(),
                _buildVehicleInfoPage(),
                _buildDocumentsPage(),
              ],
            ),
          ),
          
          // Navigation buttons
          Container(
            padding: const EdgeInsets.all(16),
            color: SwiftDashColors.white,
            child: Row(
              children: [
                if (_currentPage > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _previousPage,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: SwiftDashColors.darkBlue,
                        side: BorderSide(color: SwiftDashColors.darkBlue),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Previous'),
                    ),
                  ),
                if (_currentPage > 0) const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : (_currentPage == 2 ? _completeRegistration : _nextPage),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SwiftDashColors.darkBlue,
                      foregroundColor: SwiftDashColors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(SwiftDashColors.white),
                          ),
                        )
                      : Text(_currentPage == 2 ? 'Complete Registration' : 'Next'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalInfoPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _personalFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Personal Information',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: SwiftDashColors.darkBlue,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please provide your personal details',
              style: TextStyle(color: SwiftDashColors.textGrey),
            ),
            const SizedBox(height: 32),
            
            // Profile image
            Center(
              child: GestureDetector(
                onTap: () => _pickImage(true),
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: SwiftDashColors.backgroundGrey,
                    border: Border.all(color: SwiftDashColors.lightBlue, width: 3),
                  ),
                  child: _profileImage != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(60),
                        child: Image.file(
                          _profileImage!,
                          width: 120,
                          height: 120,
                          fit: BoxFit.cover,
                        ),
                      )
                    : const Icon(
                        Icons.camera_alt,
                        size: 40,
                        color: SwiftDashColors.lightBlue,
                      ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Center(
              child: Text(
                'Tap to add profile photo',
                style: TextStyle(
                  color: SwiftDashColors.textGrey,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 32),
            
            TextFormField(
              controller: _firstNameController,
              decoration: const InputDecoration(
                labelText: 'First Name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
              validator: (value) {
                if (value?.isEmpty ?? true) {
                  return 'First name is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            TextFormField(
              controller: _lastNameController,
              decoration: const InputDecoration(
                labelText: 'Last Name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (value) {
                if (value?.isEmpty ?? true) {
                  return 'Last name is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            TextFormField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: 'Phone Number',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone),
                hintText: '+639123456789',
              ),
              keyboardType: TextInputType.phone,
              validator: (value) {
                if (value?.isEmpty ?? true) {
                  return 'Phone number is required';
                }
                if (!RegExp(r'^\+639\d{9}$').hasMatch(value!)) {
                  return 'Enter valid Philippine phone number (+639XXXXXXXXX)';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            TextFormField(
              controller: _licenseNumberController,
              decoration: const InputDecoration(
                labelText: 'Driver License Number',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.badge),
              ),
              validator: (value) {
                if (value?.isEmpty ?? true) {
                  return 'License number is required';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVehicleInfoPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _vehicleFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Vehicle Information',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: SwiftDashColors.darkBlue,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tell us about your vehicle',
              style: TextStyle(color: SwiftDashColors.textGrey),
            ),
            const SizedBox(height: 32),
            
            // Vehicle image
            Center(
              child: GestureDetector(
                onTap: () => _pickImage(false),
                child: Container(
                  width: 200,
                  height: 120,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: SwiftDashColors.backgroundGrey,
                    border: Border.all(color: SwiftDashColors.lightBlue, width: 2),
                  ),
                  child: _vehicleImage != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          _vehicleImage!,
                          width: 200,
                          height: 120,
                          fit: BoxFit.cover,
                        ),
                      )
                    : const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.directions_car,
                            size: 40,
                            color: SwiftDashColors.lightBlue,
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Add Vehicle Photo',
                            style: TextStyle(
                              color: SwiftDashColors.textGrey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            
            DropdownButtonFormField<VehicleType>(
              value: _selectedVehicleType,
              decoration: InputDecoration(
                labelText: 'Vehicle Type',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.local_shipping),
                suffixIcon: _loadingVehicleTypes 
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              ),
              items: _loadingVehicleTypes 
                ? []
                : _vehicleTypes.map((type) {
                    return DropdownMenuItem(
                      value: type,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              type.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Max: ${type.maxWeightKg.toStringAsFixed(0)}kg • Base: ₱${type.basePrice.toStringAsFixed(0)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: SwiftDashColors.textGrey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
              hint: _loadingVehicleTypes 
                ? const Text('Loading vehicle types...')
                : _vehicleTypes.isEmpty 
                  ? const Text('No vehicle types available')
                  : const Text('Select your vehicle type'),
              onChanged: _loadingVehicleTypes ? null : (value) {
                setState(() {
                  _selectedVehicleType = value;
                });
              },
              validator: (value) {
                if (value == null) {
                  return 'Please select a vehicle type';
                }
                return null;
              },
            ),
            
            // Show error and retry button if vehicle types failed to load
            if (!_loadingVehicleTypes && _vehicleTypes.isEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: SwiftDashColors.warningOrange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: SwiftDashColors.warningOrange.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber,
                      color: SwiftDashColors.warningOrange,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Unable to load vehicle types',
                        style: TextStyle(
                          color: SwiftDashColors.warningOrange,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _loadVehicleTypes,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ],
            
            const SizedBox(height: 16),
            
            TextFormField(
              controller: _vehicleModelController,
              decoration: const InputDecoration(
                labelText: 'Vehicle Model',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.directions_car),
                hintText: 'e.g., Honda Click 150i',
              ),
              validator: (value) {
                if (value?.isEmpty ?? true) {
                  return 'Vehicle model is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            TextFormField(
              controller: _ltfrbNumberController,
              decoration: const InputDecoration(
                labelText: 'LTFRB Number',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.assignment),
                hintText: 'LTFRB registration number',
              ),
              validator: (value) {
                if (value?.isEmpty ?? true) {
                  return 'LTFRB number is required';
                }
                return null;
              },
            ),
            
            if (_selectedVehicleType != null) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: SwiftDashColors.lightBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: SwiftDashColors.lightBlue.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Vehicle Type: ${_selectedVehicleType!.name}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: SwiftDashColors.darkBlue,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Max Weight: ${_selectedVehicleType!.maxWeightKg}kg',
                      style: const TextStyle(color: SwiftDashColors.textGrey),
                    ),
                    Text(
                      'Base Rate: ₱${_selectedVehicleType!.basePrice.toStringAsFixed(2)}',
                      style: const TextStyle(color: SwiftDashColors.textGrey),
                    ),
                    Text(
                      'Per KM: ₱${_selectedVehicleType!.pricePerKm.toStringAsFixed(2)}',
                      style: const TextStyle(color: SwiftDashColors.textGrey),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentsPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _documentsFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Review & Submit',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: SwiftDashColors.darkBlue,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please review your information before submitting',
              style: TextStyle(color: SwiftDashColors.textGrey),
            ),
            const SizedBox(height: 32),
            
            // Summary card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Personal Information',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: SwiftDashColors.darkBlue,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildSummaryRow('Name', '${_firstNameController.text} ${_lastNameController.text}'),
                    _buildSummaryRow('Phone', _phoneController.text),
                    _buildSummaryRow('License', _licenseNumberController.text),
                    _buildSummaryRow('LTFRB', _ltfrbNumberController.text),
                    
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 16),
                    
                    const Text(
                      'Vehicle Information',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: SwiftDashColors.darkBlue,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildSummaryRow('Type', _selectedVehicleType?.name ?? 'Not selected'),
                    _buildSummaryRow('Model', _vehicleModelController.text),
                    _buildSummaryRow('Profile Photo', _profileImage != null ? 'Added' : 'Not added'),
                    _buildSummaryRow('Vehicle Photo', _vehicleImage != null ? 'Added' : 'Not added'),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Terms and verification notice
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: SwiftDashColors.warningOrange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: SwiftDashColors.warningOrange.withOpacity(0.3)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Verification Process',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: SwiftDashColors.warningOrange,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '• Your account will be pending admin verification\n'
                    '• You can use the app normally during review\n'
                    '• Verification typically takes 1-2 business days\n'
                    '• You\'ll be notified once approved',
                    style: TextStyle(
                      color: SwiftDashColors.textGrey,
                      fontSize: 14,
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

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: SwiftDashColors.textGrey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? 'Not provided' : value,
              style: const TextStyle(
                color: SwiftDashColors.darkBlue,
              ),
            ),
          ),
        ],
      ),
    );
  }
}