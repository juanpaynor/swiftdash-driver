import 'package:flutter/material.dart';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import '../services/document_upload_service.dart';
import '../services/auth_service.dart';
import '../utils/validation_utils.dart';
import '../models/driver.dart';

class ImprovedEditProfileScreen extends StatefulWidget {
  const ImprovedEditProfileScreen({super.key});

  @override
  State<ImprovedEditProfileScreen> createState() => _ImprovedEditProfileScreenState();
}

class _ImprovedEditProfileScreenState extends State<ImprovedEditProfileScreen> with SingleTickerProviderStateMixin {
  final DocumentUploadService _docService = DocumentUploadService();
  final AuthService _authService = AuthService();
  final _formKey = GlobalKey<FormState>();

  // Tab controller
  late TabController _tabController;

  // Image files
  File? _profileImage;
  File? _vehicleSideImage;
  File? _vehicleBackImage;
  File? _ltfrbImage;

  // Text controllers
  final _ltfrbController = TextEditingController();
  final _plateNumberController = TextEditingController();
  final _vehicleModelController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _invitationCodeController = TextEditingController();

  // State
  bool _isSaving = false;
  bool _isLoading = true;
  bool _isValidatingCode = false;
  Driver? _currentDriver;
  
  // Existing image URLs
  String? _existingProfileUrl;
  String? _existingVehicleSideUrl;
  String? _existingVehicleBackUrl;
  String? _existingLtfrbUrl;

  // Business/Fleet information
  String? _currentBusinessId;
  String? _currentBusinessName;
  String? _validatedBusinessName; // After code validation

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadCurrentProfile();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _ltfrbController.dispose();
    _plateNumberController.dispose();
    _vehicleModelController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _invitationCodeController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentProfile() async {
    try {
      final user = _authService.currentUser;
      if (user == null) return;

      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('driver_profiles')
          .select('*, business:businesses!managed_by_business_id(name)')
          .eq('user_id', user.id)
          .single();

      setState(() {
        _currentDriver = Driver.fromJson(response);
        _firstNameController.text = response['first_name'] ?? '';
        _lastNameController.text = response['last_name'] ?? '';
        _phoneController.text = response['phone_number'] ?? '';
        _vehicleModelController.text = response['vehicle_model'] ?? '';
        _plateNumberController.text = response['plate_number'] ?? '';
        _ltfrbController.text = response['ltfrb_number'] ?? '';
        
        _existingProfileUrl = response['profile_picture_url'];
        _existingVehicleSideUrl = response['vehicle_side_image_url'];
        _existingVehicleBackUrl = response['vehicle_back_image_url'];
        _existingLtfrbUrl = response['ltfrb_image_url'];

        _currentBusinessId = response['managed_by_business_id'];
        // Try to get business name from the join
        if (response['business'] != null) {
          _currentBusinessName = response['business']['name'];
        }

        _isLoading = false;
      });
    } catch (e) {
      print('Error loading profile: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading profile: $e')),
        );
      }
    }
  }

  Future<void> _validateInvitationCode() async {
    final code = _invitationCodeController.text.trim();
    if (code.isEmpty) {
      setState(() {
        _validatedBusinessName = null;
      });
      return;
    }

    setState(() => _isValidatingCode = true);

    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('businesses')
          .select('id, name')
          .eq('invitation_code', code)
          .maybeSingle();

      setState(() {
        _isValidatingCode = false;
        if (response != null) {
          _validatedBusinessName = response['name'];
        } else {
          _validatedBusinessName = null;
        }
      });
    } catch (e) {
      setState(() {
        _isValidatingCode = false;
        _validatedBusinessName = null;
      });
    }
  }

  Future<void> _pick(String type) async {
    final File? pickedFile = await _docService.captureImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    // Check file size (5MB limit)
    final bytes = await pickedFile.length();
    if (bytes > 5 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Image size must be less than 5MB'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() {
      switch (type) {
        case 'profile':
          _profileImage = pickedFile;
          break;
        case 'vehicle_side':
          _vehicleSideImage = pickedFile;
          break;
        case 'vehicle_back':
          _vehicleBackImage = pickedFile;
          break;
        case 'ltfrb':
          _ltfrbImage = pickedFile;
          break;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // Validate invitation code if provided
    if (_invitationCodeController.text.trim().isNotEmpty && _validatedBusinessName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please validate the invitation code first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final user = _authService.currentUser;
      if (user == null) throw Exception('Not authenticated');

      final supabase = Supabase.instance.client;

      // Upload images
      String? profileUrl = _existingProfileUrl;
      String? vehicleSideUrl = _existingVehicleSideUrl;
      String? vehicleBackUrl = _existingVehicleBackUrl;
      String? ltfrbUrl = _existingLtfrbUrl;

      if (_profileImage != null) {
        profileUrl = await _docService.uploadDriverProfilePicture(
          _profileImage!,
          user.id,
        );
      }

      if (_vehicleSideImage != null) {
        vehicleSideUrl = await _docService.uploadToStorage(
          imageFile: _vehicleSideImage!,
          bucket: 'driver_profile_pictures',
          fileName: '${user.id}_vehicle_side.jpg',
        );
      }

      if (_vehicleBackImage != null) {
        vehicleBackUrl = await _docService.uploadToStorage(
          imageFile: _vehicleBackImage!,
          bucket: 'driver_profile_pictures',
          fileName: '${user.id}_vehicle_back.jpg',
        );
      }

      if (_ltfrbImage != null) {
        ltfrbUrl = await _docService.uploadLTFRBPicture(
          _ltfrbImage!,
          user.id,
        );
      }

      // Prepare update data
      final updateData = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };

      // Only update fields that have changed
      if (_firstNameController.text != _currentDriver?.firstName) {
        updateData['first_name'] = _firstNameController.text.trim();
      }
      if (_lastNameController.text != _currentDriver?.lastName) {
        updateData['last_name'] = _lastNameController.text.trim();
      }
      if (_phoneController.text != _currentDriver?.phoneNumber) {
        updateData['phone_number'] = _phoneController.text.trim();
      }
      if (_vehicleModelController.text.trim() != (_currentDriver?.vehicleModel ?? '')) {
        updateData['vehicle_model'] = _vehicleModelController.text.trim();
      }
      if (_plateNumberController.text.trim() != (_currentDriver?.plateNumber ?? '')) {
        updateData['plate_number'] = _plateNumberController.text.trim();
      }
      if (_ltfrbController.text.trim() != (_currentDriver?.licenseNumber ?? '')) {
        updateData['ltfrb_number'] = _ltfrbController.text.trim();
      }

      // Update image URLs if changed
      if (profileUrl != _existingProfileUrl) {
        updateData['profile_picture_url'] = profileUrl;
      }
      if (vehicleSideUrl != _existingVehicleSideUrl) {
        updateData['vehicle_side_image_url'] = vehicleSideUrl;
      }
      if (vehicleBackUrl != _existingVehicleBackUrl) {
        updateData['vehicle_back_image_url'] = vehicleBackUrl;
      }
      if (ltfrbUrl != _existingLtfrbUrl) {
        updateData['ltfrb_image_url'] = ltfrbUrl;
      }

      // Handle business invitation code
      if (_invitationCodeController.text.trim().isNotEmpty && _validatedBusinessName != null) {
        // Fetch business ID
        final businessResponse = await supabase
            .from('businesses')
            .select('id')
            .eq('invitation_code', _invitationCodeController.text.trim())
            .single();
        
        updateData['managed_by_business_id'] = businessResponse['id'];
        updateData['employment_type'] = 'fleet_driver';
      }

      // Update profile
      await supabase
          .from('driver_profiles')
          .update(updateData)
          .eq('user_id', user.id);

      setState(() => _isSaving = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _imageTile(String label, File? imageFile, String? existingUrl, VoidCallback onTap, {bool isCircle = false}) {
    final hasImage = imageFile != null || (existingUrl != null && existingUrl.isNotEmpty);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: isCircle ? 140 : 160,
        width: isCircle ? 140 : double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: isCircle ? null : BorderRadius.circular(16),
          shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
          border: Border.all(
            color: hasImage ? const Color(0xFFFF6B35) : Colors.grey.shade300,
            width: hasImage ? 3 : 2,
          ),
        ),
        child: hasImage
            ? ClipRRect(
                borderRadius: isCircle ? BorderRadius.circular(70) : BorderRadius.circular(14),
                child: imageFile != null
                    ? Image.file(imageFile, fit: BoxFit.cover)
                    : CachedNetworkImage(
                        imageUrl: existingUrl!,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => const Center(
                          child: CircularProgressIndicator(),
                        ),
                        errorWidget: (context, url, error) => const Icon(Icons.error),
                      ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_photo_alternate,
                    size: 40,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildPersonalInfoTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Profile Photo
          const Text(
            'Profile Photo',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Center(
            child: _imageTile(
              'Tap to upload\nprofile photo',
              _profileImage,
              _existingProfileUrl,
              () => _pick('profile'),
              isCircle: true,
            ),
          ),
          const SizedBox(height: 32),

          // Personal Details
          const Text(
            'Personal Details',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          TextFormField(
            controller: _firstNameController,
            decoration: InputDecoration(
              labelText: 'First Name *',
              prefixIcon: const Icon(Icons.person_outline),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your first name';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          TextFormField(
            controller: _lastNameController,
            decoration: InputDecoration(
              labelText: 'Last Name *',
              prefixIcon: const Icon(Icons.person),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your last name';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          TextFormField(
            controller: _phoneController,
            decoration: InputDecoration(
              labelText: 'Phone Number *',
              prefixIcon: const Icon(Icons.phone),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey.shade50,
              helperText: 'Format: 09XXXXXXXXX',
            ),
            keyboardType: TextInputType.phone,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your phone number';
              }
              if (!ValidationUtils.isValidPhoneNumber(value.trim())) {
                return 'Please enter a valid phone number';
              }
              return null;
            },
          ),
          const SizedBox(height: 32),

          // Driver Stats (Read-only)
          if (_currentDriver != null) ...[
            const Text(
              'Driver Statistics',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF6B35), Color(0xFFFF8C42)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem(
                    Icons.local_shipping,
                    '${_currentDriver!.totalDeliveries}',
                    'Deliveries',
                  ),
                  Container(
                    width: 1,
                    height: 50,
                    color: Colors.white.withOpacity(0.3),
                  ),
                  _buildStatItem(
                    Icons.star,
                    _currentDriver!.rating.toStringAsFixed(1),
                    'Rating',
                  ),
                  Container(
                    width: 1,
                    height: 50,
                    color: Colors.white.withOpacity(0.3),
                  ),
                  _buildStatItem(
                    Icons.verified,
                    _currentDriver!.isVerified ? 'Yes' : 'No',
                    'Verified',
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 28),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildVehicleTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Vehicle Details
          const Text(
            'Vehicle Details',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          TextFormField(
            controller: _vehicleModelController,
            decoration: InputDecoration(
              labelText: 'Vehicle Model *',
              hintText: 'e.g., Honda Click 150i',
              prefixIcon: const Icon(Icons.motorcycle),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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

          // Vehicle Photos
          const Text(
            'Vehicle Photos',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Text(
            'Upload clear photos of your vehicle (side and back view)',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 16),

          Row(
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
        ],
      ),
    );
  }

  Widget _buildDocumentsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // LTFRB Document
          const Text(
            'LTFRB Document',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Text(
            'Upload your LTFRB franchise certificate',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 16),

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
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
          ),
          const SizedBox(height: 32),

          // Fleet/Business Section
          const Text(
            'Fleet Management',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          // Show current business if linked
          if (_currentBusinessId != null && _currentBusinessName != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.business, color: Colors.green.shade700),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Currently managed by:',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _currentBusinessName!,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.verified, color: Colors.green.shade700),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'You are part of a fleet. Contact your fleet manager to make changes.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ] else ...[
            const Text(
              'Join a business or fleet by entering an invitation code',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _invitationCodeController,
              decoration: InputDecoration(
                labelText: 'Invitation Code (optional)',
                hintText: 'Enter code provided by your fleet manager',
                prefixIcon: const Icon(Icons.vpn_key),
                suffixIcon: _isValidatingCode
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : (_validatedBusinessName != null
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : (_invitationCodeController.text.trim().isNotEmpty
                            ? const Icon(Icons.error, color: Colors.red)
                            : null)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
              onChanged: (value) {
                if (value.trim().length >= 6) {
                  _validateInvitationCode();
                } else {
                  setState(() {
                    _validatedBusinessName = null;
                  });
                }
              },
            ),
            const SizedBox(height: 8),

            if (_validatedBusinessName != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Valid code for: $_validatedBusinessName',
                        style: TextStyle(
                          color: Colors.green.shade900,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else if (_invitationCodeController.text.trim().isNotEmpty && !_isValidatingCode)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error, color: Colors.red.shade700, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Invalid invitation code',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Edit Profile'),
          elevation: 0,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFFFF6B35),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFFFF6B35),
          tabs: const [
            Tab(icon: Icon(Icons.person), text: 'Personal'),
            Tab(icon: Icon(Icons.motorcycle), text: 'Vehicle'),
            Tab(icon: Icon(Icons.description), text: 'Documents'),
          ],
        ),
      ),
      body: Form(
        key: _formKey,
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildPersonalInfoTab(),
            _buildVehicleTab(),
            _buildDocumentsTab(),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          child: SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B35),
                disabledBackgroundColor: Colors.grey.shade300,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
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
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
