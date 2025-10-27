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
    try {
      print('📸 Preparing POD photo for upload...');
      final fileName = '${deliveryId}_pod_${DateTime.now().millisecondsSinceEpoch}.jpg';
      
      // Read and upload
      final bytes = await imageFile.readAsBytes();
      print('📦 Image size: ${(bytes.length / 1024).toStringAsFixed(2)} KB');
      
      final url = await _uploadToStorage(
        imageFile: imageFile,
        bucket: 'Proof_of_delivery',
        fileName: fileName,
      );
      
      print('✅ POD photo uploaded successfully');
      return url;
    } catch (e) {
      print('❌ Error in uploadProofOfDelivery: $e');
      rethrow;
    }
  }

  // Upload pickup proof photo
  Future<String?> uploadPickupProof(File imageFile, String deliveryId) async {
    try {
      print('📸 Preparing pickup photo for upload...');
      final fileName = '${deliveryId}_pickup_${DateTime.now().millisecondsSinceEpoch}.jpg';
      
      // Read and upload in chunks to prevent freezing
      final bytes = await imageFile.readAsBytes();
      print('📦 Image size: ${(bytes.length / 1024).toStringAsFixed(2)} KB');
      
      final url = await _uploadToStorage(
        imageFile: imageFile,
        bucket: 'pickup_photo',
        fileName: fileName,
      );
      
      print('✅ Pickup photo uploaded successfully');
      return url;
    } catch (e) {
      print('❌ Error in uploadPickupProof: $e');
      rethrow;
    }
  }

  // Generic upload method
  Future<String?> _uploadToStorage({
    required File imageFile,
    required String bucket,
    required String fileName,
  }) async {
    try {
      print('⏳ Reading image file...');
      final bytes = await imageFile.readAsBytes();
      print('✅ File read complete: ${bytes.length} bytes');
      
      print('⏳ Uploading to bucket: $bucket...');
      // Use upsert to overwrite existing file
      await _supabase.storage
          .from(bucket)
          .uploadBinary(
            fileName, 
            bytes,
            fileOptions: const FileOptions(
              cacheControl: '3600',
              upsert: true,  // Overwrite if exists
            ),
          );
      
      print('✅ Upload to Supabase complete');
      
      // Get public URL with cache-busting
      final baseUrl = _supabase.storage
          .from(bucket)
          .getPublicUrl(fileName);
      
      // Add cache-busting query parameter
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final url = '$baseUrl?t=$timestamp';
      
      print('✅ Public URL generated: $url');
      return url;
    } catch (e, stackTrace) {
      print('❌ Error uploading to $bucket: $e');
      print('Stack trace: $stackTrace');
      return null;
    }
  }

  // Capture image from camera
  Future<File?> captureImage({
    ImageSource source = ImageSource.camera,
    CameraDevice camera = CameraDevice.rear,
  }) async {
    try {
      print('📸 Opening camera/gallery...');
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1024,  // Reduced from higher resolution
        maxHeight: 1024,
        imageQuality: 75,  // Reduced from 85 to prevent large files
        preferredCameraDevice: camera,
      );
      
      if (image != null) {
        final file = File(image.path);
        final fileSize = await file.length();
        print('✅ Image captured: ${(fileSize / 1024).toStringAsFixed(2)} KB');
        return file;
      }
      print('❌ No image selected');
      return null;
    } catch (e) {
      print('❌ Error capturing image: $e');
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