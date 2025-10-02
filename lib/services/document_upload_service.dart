import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';

class DocumentUploadService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();

  // Upload driver profile picture
  Future<String?> uploadDriverProfilePicture(File imageFile, String driverId) async {
    return await _uploadToStorage(
      imageFile: imageFile,
      bucket: 'driver_profile_pictures',
      fileName: '${driverId}_profile.jpg',
    );
  }

  // Upload vehicle picture
  Future<String?> uploadVehiclePicture(File imageFile, String driverId) async {
    return await _uploadToStorage(
      imageFile: imageFile,
      bucket: 'driver_profile_pictures',
      fileName: '${driverId}_vehicle.jpg',
    );
  }

  // Upload license picture
  Future<String?> uploadLicensePicture(File imageFile, String driverId) async {
    return await _uploadToStorage(
      imageFile: imageFile,
      bucket: 'License_pictures',
      fileName: '${driverId}_license.jpg',
    );
  }

  // Upload LTFRB picture
  Future<String?> uploadLTFRBPicture(File imageFile, String driverId) async {
    return await _uploadToStorage(
      imageFile: imageFile,
      bucket: 'LTFRB_pictures',
      fileName: '${driverId}_ltfrb.jpg',
    );
  }

  // Upload proof of delivery
  Future<String?> uploadProofOfDelivery(File imageFile, String deliveryId) async {
    final fileName = '${deliveryId}_pod_${DateTime.now().millisecondsSinceEpoch}.jpg';
    return await _uploadToStorage(
      imageFile: imageFile,
      bucket: 'Proof_of_delivery',
      fileName: fileName,
    );
  }

  // Generic upload method
  Future<String?> _uploadToStorage({
    required File imageFile,
    required String bucket,
    required String fileName,
  }) async {
    try {
      final bytes = await imageFile.readAsBytes();
      
      await _supabase.storage
          .from(bucket)
          .uploadBinary(fileName, bytes);
      
      final url = _supabase.storage
          .from(bucket)
          .getPublicUrl(fileName);
      
      print('Uploaded to $bucket: $fileName');
      return url;
    } catch (e) {
      print('Error uploading to $bucket: $e');
      return null;
    }
  }

  // Capture image from camera
  Future<File?> captureImage({
    ImageSource source = ImageSource.camera,
    CameraDevice camera = CameraDevice.rear,
  }) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
        preferredCameraDevice: camera,
      );
      
      if (image != null) {
        return File(image.path);
      }
      return null;
    } catch (e) {
      print('Error capturing image: $e');
      return null;
    }
  }

  // Pick image from gallery
  Future<File?> pickImageFromGallery() async {
    return await captureImage(source: ImageSource.gallery);
  }

  // Show image source selection dialog
  Future<File?> showImageSourceDialog(BuildContext context) async {
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Image Source'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source != null) {
      return await captureImage(source: source);
    }
    return null;
  }

  // Delete file from storage
  Future<bool> deleteFile(String bucket, String fileName) async {
    try {
      await _supabase.storage
          .from(bucket)
          .remove([fileName]);
      
      print('Deleted from $bucket: $fileName');
      return true;
    } catch (e) {
      print('Error deleting from $bucket: $e');
      return false;
    }
  }

  // Get file URL
  String getFileUrl(String bucket, String fileName) {
    return _supabase.storage
        .from(bucket)
        .getPublicUrl(fileName);
  }
}