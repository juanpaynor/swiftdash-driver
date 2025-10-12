import 'package:flutter/material.dart';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/document_upload_service.dart';
import '../services/auth_service.dart';
import '../utils/validation_utils.dart';

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
  final _formKey = GlobalKey<FormState>();

  bool _isSaving = false;

  @override
  void dispose() {
    _ltfrbController.dispose();
    _plateNumberController.dispose();
    _vehicleModelController.dispose();
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

      if (_profileImage != null) {
        profileUrl = await _docService.uploadDriverProfilePicture(_profileImage!, user.id);
      }
      if (_vehicleSideImage != null) {
        vehicleSideUrl = await _docService.uploadVehiclePicture(_vehicleSideImage!, user.id);
      }
      if (_vehicleBackImage != null) {
        // store back image under vehicle picture (use different name internally)
        vehicleBackUrl = await _docService.uploadVehiclePicture(_vehicleBackImage!, user.id);
      }
      if (_ltfrbImage != null) {
        ltfrbUrl = await _docService.uploadLTFRBPicture(_ltfrbImage!, user.id);
      }

      // Update driver_profiles
      final updateData = <String, dynamic>{
        'id': user.id,
      };
      if (profileUrl != null) updateData['profile_picture_url'] = profileUrl;
      if (vehicleSideUrl != null) updateData['vehicle_picture_url'] = vehicleSideUrl;
      if (vehicleBackUrl != null) updateData['vehicle_back_picture_url'] = vehicleBackUrl;
      if (ltfrbUrl != null) updateData['ltfrb_picture_url'] = ltfrbUrl;
      if (_ltfrbController.text.trim().isNotEmpty) updateData['ltfrb_number'] = _ltfrbController.text.trim();
      if (_vehicleModelController.text.trim().isNotEmpty) updateData['vehicle_model'] = _vehicleModelController.text.trim();
      if (_plateNumberController.text.trim().isNotEmpty) {
        updateData['plate_number'] = ValidationUtils.formatPlateNumber(_plateNumberController.text.trim());
      }

      await Supabase.instance.client.from('driver_profiles').upsert(updateData);

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated'), backgroundColor: Colors.green));
      Navigator.of(context).pop();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save profile: $e')));
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Widget _imageTile(String label, File? file, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.grey.shade100,
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: file != null
            ? ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(file, fit: BoxFit.cover))
            : Center(child: Text(label, textAlign: TextAlign.center)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Profile Photo', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _imageTile('Tap to upload\nProfile', _profileImage, () => _pick('profile')),
            const SizedBox(height: 16),

            const Text('Vehicle Photos (Side & Back)', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                _imageTile('Vehicle Side', _vehicleSideImage, () => _pick('vehicle_side')),
                const SizedBox(width: 12),
                _imageTile('Vehicle Back', _vehicleBackImage, () => _pick('vehicle_back')),
              ],
            ),
            const SizedBox(height: 16),

            const Text('LTFRB Document', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _imageTile('LTFRB Photo', _ltfrbImage, () => _pick('ltfrb')),
            const SizedBox(height: 12),
            TextField(
              controller: _ltfrbController,
              decoration: const InputDecoration(labelText: 'LTFRB Number (optional)'),
            ),
            const SizedBox(height: 16),

            const Text('Vehicle Details', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _vehicleModelController,
              decoration: const InputDecoration(
                labelText: 'Vehicle Model',
                hintText: 'e.g., Honda Click 150i',
              ),
              validator: (value) {
                if (value != null && value.trim().isNotEmpty && !ValidationUtils.isValidVehicleModel(value.trim())) {
                  return 'Please enter a valid vehicle model';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _plateNumberController,
              decoration: const InputDecoration(
                labelText: 'License Plate Number',
                hintText: 'e.g., ABC-1234',
              ),
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
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save Profile'),
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}
