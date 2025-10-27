import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:async';
import '../models/delivery.dart';
import '../services/document_upload_service.dart';
import 'signature_capture_dialog.dart';

/// Dialog for capturing proof of delivery (photo + signature + details)
class ProofOfDeliveryDialog extends StatefulWidget {
  final Delivery delivery;
  
  const ProofOfDeliveryDialog({
    super.key,
    required this.delivery,
  });

  @override
  State<ProofOfDeliveryDialog> createState() => _ProofOfDeliveryDialogState();
}

class _ProofOfDeliveryDialogState extends State<ProofOfDeliveryDialog> {
  File? _deliveryPhoto;
  String? _signatureData;
  bool _isUploading = false;
  String? _errorMessage;
  
  final TextEditingController _recipientNameController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final DocumentUploadService _uploadService = DocumentUploadService();
  
  @override
  void dispose() {
    _recipientNameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _captureDeliveryPhoto() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      
      if (photo != null) {
        setState(() {
          _deliveryPhoto = File(photo.path);
          _errorMessage = null;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to capture photo: $e';
      });
    }
  }
  
  Future<void> _captureSignature() async {
    final signature = await showDialog<String?>(
      context: context,
      builder: (context) => const SignatureCaptureDialog(),
    );
    
    if (signature != null) {
      setState(() {
        _signatureData = signature;
      });
    }
  }

  Future<void> _submitProofOfDelivery() async {
    // Validate that photo is captured
    if (_deliveryPhoto == null) {
      setState(() {
        _errorMessage = 'Please capture a delivery photo';
      });
      return;
    }
    
    setState(() {
      _isUploading = true;
      _errorMessage = null;
    });
    
    try {
      print('📤 Uploading proof of delivery photo...');
      
      // Upload photo to Supabase with timeout
      final photoUrl = await _uploadService.uploadProofOfDelivery(
        _deliveryPhoto!,
        widget.delivery.id,
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Upload timed out. Please check your internet connection.');
        },
      );
      
      if (photoUrl == null) {
        throw Exception('Failed to upload photo - no URL returned');
      }
      
      print('✅ Photo uploaded successfully: $photoUrl');
      
      // Return POD data
      if (mounted) {
        Navigator.of(context).pop({
          'photoUrl': photoUrl,
          'signatureUrl': _signatureData,
          'recipientName': _recipientNameController.text.trim(),
          'notes': _notesController.text.trim(),
        });
      }
    } catch (e) {
      print('❌ Error uploading POD: $e');
      if (mounted) {
        setState(() {
          _isUploading = false;
          _errorMessage = 'Failed to upload photo: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.camera_alt,
                      color: Colors.blue.shade700,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Proof of Delivery',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Capture delivery confirmation',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 24),
              
              // Delivery Info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoRow('Order ID', widget.delivery.id.substring(0, 8)),
                    const SizedBox(height: 8),
                    _buildInfoRow('Delivery Address', widget.delivery.deliveryAddress),
                    const SizedBox(height: 8),
                    _buildInfoRow('Package', widget.delivery.packageDescription),
                  ],
                ),
              ),
              
              const SizedBox(height: 20),
              
              // Photo Section
              if (_deliveryPhoto != null) ...[
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.green,
                      width: 2,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(
                      _deliveryPhoto!,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              
              // Capture Photo Button
              OutlinedButton.icon(
                onPressed: _isUploading ? null : _captureDeliveryPhoto,
                icon: Icon(
                  _deliveryPhoto != null ? Icons.refresh : Icons.camera_alt,
                  size: 20,
                ),
                label: Text(
                  _deliveryPhoto != null ? 'Retake Photo' : 'Capture Photo',
                  style: const TextStyle(fontSize: 16),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.blue.shade800,
                  side: BorderSide(
                    color: Colors.blue.shade800,
                    width: 2,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Signature Section
              OutlinedButton.icon(
                onPressed: _isUploading ? null : _captureSignature,
                icon: Icon(
                  _signatureData != null ? Icons.check_circle : Icons.draw,
                  size: 20,
                  color: _signatureData != null ? Colors.green : null,
                ),
                label: Text(
                  _signatureData != null ? 'Signature Captured ✓' : 'Capture Signature (Optional)',
                  style: const TextStyle(fontSize: 16),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _signatureData != null ? Colors.green : Colors.grey.shade700,
                  side: BorderSide(
                    color: _signatureData != null ? Colors.green : Colors.grey.shade400,
                    width: 2,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Recipient Name
              TextField(
                controller: _recipientNameController,
                enabled: !_isUploading,
                decoration: InputDecoration(
                  labelText: 'Recipient Name (Optional)',
                  hintText: 'Who received the package?',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.person),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Notes
              TextField(
                controller: _notesController,
                enabled: !_isUploading,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Delivery Notes (Optional)',
                  hintText: 'Any additional notes...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.note),
                ),
              ),
              
              // Error Message
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              
              const SizedBox(height: 20),
              
              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isUploading ? null : () => Navigator.of(context).pop(null),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: Colors.grey.shade400),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: (_isUploading || _deliveryPhoto == null)
                          ? null
                          : _submitProofOfDelivery,
                      icon: _isUploading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.check_circle),
                      label: Text(
                        _isUploading ? 'Uploading...' : 'Confirm Delivery',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
