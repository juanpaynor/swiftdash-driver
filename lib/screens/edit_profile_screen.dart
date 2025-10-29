import 'package:flutter/material.dart';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/document_upload_service.dart';
import '../services/auth_service.dart';
import '../utils/validation_utils.dart';
import '../models/driver.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final DocumentUploadService _docService = DocumentUploadService();
  final AuthService _authService = AuthService();

  File? _profileImage;
  File? _vehicleSideImage;
  File? _vehicleBackImage;
  File? _ltfrbImage;
  final _ltfrbController = TextEditingController();
  final _plateNumberController = TextEditingController();
  final _vehicleModelController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isSaving = false;
  bool _isLoading = true;
  Driver? _currentDriver;
  
  // Existing image URLs from database
  String? _existingProfileUrl;
  String? _existingVehicleSideUrl;
  String? _existingVehicleBackUrl;
  String? _existingLtfrbUrl;

  @override
  void initState() {
    super.initState();
    _loadCurrentProfile();
  }

  Future<void> _loadCurrentProfile() async {
    try {
      final user = _authService.currentUser;
      if (user == null) {
        throw Exception('Not authenticated');
      }

      // Fetch driver profile
      final response = await Supabase.instance.client
          .from('driver_profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (response != null) {
        setState(() {
          _currentDriver = Driver.fromJson(response);
          _firstNameController.text = _currentDriver?.firstName ?? '';
          _lastNameController.text = _currentDriver?.lastName ?? '';
          _phoneController.text = _currentDriver?.phoneNumber ?? '';
          _plateNumberController.text = _currentDriver?.plateNumber ?? '';
          _vehicleModelController.text = _currentDriver?.vehicleModel ?? '';
          
          // Store existing image URLs
          _existingProfileUrl = response['profile_picture_url'];
          _existingVehicleSideUrl = response['vehicle_picture_url'];
          _existingVehicleBackUrl = response['vehicle_back_picture_url'];
          _existingLtfrbUrl = response['ltfrb_picture_url'];
          _ltfrbController.text = response['ltfrb_number'] ?? '';
          
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load profile: $e'), backgroundColor: Colors.red),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _ltfrbController.dispose();
    _plateNumberController.dispose();
    _vehicleModelController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _pick(String type) async {
    final file = await _docService.showImageSourceDialog(context);
    if (file == null) return;

    final sizeMb = await file.length() / (1024 * 1024);
    if (sizeMb > 5) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('File must be ≤ 5MB (selected ${sizeMb.toStringAsFixed(1)}MB)')));
      return;
    }

    setState(() {
      switch (type) {
        case 'profile':
          _profileImage = file;
          break;
        case 'vehicle_side':
          _vehicleSideImage = file;
          break;
        case 'vehicle_back':
          _vehicleBackImage = file;
          break;
        case 'ltfrb':
          _ltfrbImage = file;
          break;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    
    setState(() => _isSaving = true);
    try {
      final user = _authService.currentUser;
      if (user == null) throw Exception('Not authenticated');

      String? profileUrl;
      String? vehicleSideUrl;
      String? vehicleBackUrl;
      String? ltfrbUrl;

      // Upload new images if selected
      if (_profileImage != null) {
        profileUrl = await _docService.uploadDriverProfilePicture(_profileImage!, user.id);
        if (profileUrl == null) throw Exception('Failed to upload profile picture');
      }
      
      if (_vehicleSideImage != null) {
        vehicleSideUrl = await _docService.uploadVehiclePicture(_vehicleSideImage!, user.id);
        if (vehicleSideUrl == null) throw Exception('Failed to upload vehicle side picture');
      }
      
      if (_vehicleBackImage != null) {
        // ✅ FIX: Upload vehicle back image to correct bucket with unique filename
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        vehicleBackUrl = await _docService.uploadToStorage(
          imageFile: _vehicleBackImage!,
          bucket: 'driver_profile_pictures',
          fileName: '${user.id}_vehicle_back_$timestamp.jpg',
        );
        if (vehicleBackUrl == null) throw Exception('Failed to upload vehicle back picture');
      }
      
      if (_ltfrbImage != null) {
        ltfrbUrl = await _docService.uploadLTFRBPicture(_ltfrbImage!, user.id);
        if (ltfrbUrl == null) throw Exception('Failed to upload LTFRB picture');
      }

      // Prepare update data
      final updateData = <String, dynamic>{};
      
      // Only update fields that were changed
      if (profileUrl != null) updateData['profile_picture_url'] = profileUrl;
      if (vehicleSideUrl != null) updateData['vehicle_picture_url'] = vehicleSideUrl;
      if (vehicleBackUrl != null) updateData['vehicle_back_picture_url'] = vehicleBackUrl;
      if (ltfrbUrl != null) updateData['ltfrb_picture_url'] = ltfrbUrl;
      if (_ltfrbController.text.trim().isNotEmpty) {
        updateData['ltfrb_number'] = _ltfrbController.text.trim();
      }
      if (_vehicleModelController.text.trim().isNotEmpty) {
        updateData['vehicle_model'] = _vehicleModelController.text.trim();
      }
      if (_plateNumberController.text.trim().isNotEmpty) {
        updateData['plate_number'] = ValidationUtils.formatPlateNumber(_plateNumberController.text.trim());
      }

      // Only perform update if there are changes
      if (updateData.isNotEmpty) {
        await Supabase.instance.client
            .from('driver_profiles')
            .update(updateData)
            .eq('id', user.id);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Profile updated successfully'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
          Navigator.of(context).pop(true); // Return true to indicate success
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No changes to save'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Error saving profile: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save profile: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Widget _imageTile(String label, File? newFile, String? existingUrl, VoidCallback onTap, {bool isCircle = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: isCircle ? 120 : 140,
        height: 120,
        decoration: BoxDecoration(
          borderRadius: isCircle ? null : BorderRadius.circular(12),
          shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
          color: Colors.grey.shade50,
          border: Border.all(
            color: newFile != null ? Colors.blue : Colors.grey.shade300,
            width: newFile != null ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Image display
            if (newFile != null)
              ClipRRect(
                borderRadius: isCircle ? BorderRadius.circular(60) : BorderRadius.circular(12),
                child: Image.file(newFile, width: double.infinity, height: double.infinity, fit: BoxFit.cover),
              )
            else if (existingUrl != null && existingUrl.isNotEmpty)
              ClipRRect(
                borderRadius: isCircle ? BorderRadius.circular(60) : BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: existingUrl,
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: Colors.grey.shade200,
                    child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: Colors.grey.shade100,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, color: Colors.grey.shade400),
                        const SizedBox(height: 4),
                        Text('Failed', style: TextStyle(color: Colors.grey.shade600, fontSize: 10)),
                      ],
                    ),
                  ),
                ),
              )
            else
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_a_photo, color: Colors.grey.shade400, size: 32),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            
            // Badge indicating new image
            if (newFile != null)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'NEW',
                    style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            
            // Edit overlay icon
            if (newFile != null || (existingUrl != null && existingUrl.isNotEmpty))
              Positioned(
                bottom: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.edit, color: Colors.white, size: 16),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Profile')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Profile Photo Section
              const Text(
                'Profile Photo',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Center(
                child: _imageTile(
                  'Tap to upload\nprofile photo',
                  _profileImage,
                  _existingProfileUrl,
                  () => _pick('profile'),
                  isCircle: true,
                ),
              ),
              const SizedBox(height: 24),

              // Vehicle Photos Section
              const Text(
                'Vehicle Photos',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Text(
                'Upload clear photos of your vehicle (side and back view)',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: _imageTile(
                      'Vehicle\nSide',
                      _vehicleSideImage,
                      _existingVehicleSideUrl,
                      () => _pick('vehicle_side'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _imageTile(
                      'Vehicle\nBack',
                      _vehicleBackImage,
                      _existingVehicleBackUrl,
                      () => _pick('vehicle_back'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // LTFRB Document Section
              const Text(
                'LTFRB Document',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Text(
                'Upload your LTFRB franchise certificate',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              _imageTile(
                'LTFRB\nCertificate',
                _ltfrbImage,
                _existingLtfrbUrl,
                () => _pick('ltfrb'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _ltfrbController,
                decoration: InputDecoration(
                  labelText: 'LTFRB Number (optional)',
                  hintText: 'e.g., 2024-NCR-12345',
                  prefixIcon: const Icon(Icons.badge),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
              ),
              const SizedBox(height: 24),

              // Vehicle Details Section
              const Text(
                'Vehicle Details',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _vehicleModelController,
                decoration: InputDecoration(
                  labelText: 'Vehicle Model *',
                  hintText: 'e.g., Honda Click 150i',
                  prefixIcon: const Icon(Icons.motorcycle),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
                validator: (value) {
                  if (value != null && value.trim().isNotEmpty && !ValidationUtils.isValidVehicleModel(value.trim())) {
                    return 'Please enter a valid vehicle model';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _plateNumberController,
                decoration: InputDecoration(
                  labelText: 'License Plate Number *',
                  hintText: 'e.g., ABC-1234',
                  prefixIcon: const Icon(Icons.pin),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  helperText: 'Format: XXX-#### or XX-####',
                ),
                textCapitalization: TextCapitalization.characters,
                validator: (value) {
                  if (value != null && value.trim().isNotEmpty && !ValidationUtils.isValidPlateNumber(value.trim())) {
                    return 'Please enter a valid license plate format';
                  }
                  return null;
                },
                onChanged: (value) {
                  // Auto-format as user types
                  if (value.isNotEmpty && ValidationUtils.isValidPlateNumber(value)) {
                    final formatted = ValidationUtils.formatPlateNumber(value);
                    if (formatted != value) {
                      _plateNumberController.value = _plateNumberController.value.copyWith(
                        text: formatted,
                        selection: TextSelection.collapsed(offset: formatted.length),
                      );
                    }
                  }
                },
              ),
              const SizedBox(height: 32),

              // Save Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    disabledBackgroundColor: Colors.grey.shade300,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: _isSaving ? 0 : 2,
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Save Changes',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
