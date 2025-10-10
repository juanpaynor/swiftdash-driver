import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import '../core/supabase_config.dart';
import '../models/delivery.dart';
import '../models/cash_remittance.dart';
import 'document_upload_service.dart';
import 'driver_earnings_service.dart';

class ProofOfDeliveryService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final DocumentUploadService _documentService = DocumentUploadService();
  final DriverEarningsService _earningsService = DriverEarningsService();

  // Capture POD photo
  Future<File?> captureProofPhoto() async {
    try {
      return await _documentService.captureImage();
    } catch (e) {
      print('Error capturing proof photo: $e');
      return null;
    }
  }

  // Upload POD photo to Supabase Storage
  Future<String?> uploadProofPhoto(File imageFile, String deliveryId) async {
    try {
      return await _documentService.uploadProofOfDelivery(imageFile, deliveryId);
    } catch (e) {
      print('Error uploading proof photo: $e');
      return null;
    }
  }

  // Complete delivery with POD
  Future<bool> completeDeliveryWithPOD({
    required String deliveryId,
    required String driverId,
    String? proofPhotoUrl,
    String? recipientName,
    String? deliveryNotes,
    bool requireSignature = false,
    String? signatureData,
  }) async {
    try {
      // First, get the delivery details to extract payment info
      final deliveryResponse = await _supabase
          .from('deliveries')
          .select('total_price, payment_method, tip_amount')
          .eq('id', deliveryId)
          .maybeSingle();

      if (deliveryResponse == null) {
        print('Error: Delivery not found: $deliveryId');
        return false;
      }

      // Extract payment information
      final totalPrice = (deliveryResponse['total_price'] as num).toDouble();
      final paymentMethodStr = deliveryResponse['payment_method'] as String?;
      final tipAmount = (deliveryResponse['tip_amount'] as num?)?.toDouble() ?? 0.0;

      // Map payment method to our enum
      final paymentMethod = _mapPaymentMethod(paymentMethodStr);

      final completionData = {
        'status': 'delivered',
        'delivered_at': DateTime.now().toIso8601String(),
        'completed_at': DateTime.now().toIso8601String(),
        'proof_photo_url': proofPhotoUrl,
        'recipient_name': recipientName,
        'delivery_notes': deliveryNotes,
        'updated_at': DateTime.now().toIso8601String(),
      };

      // If signature is required, add signature data
      if (requireSignature && signatureData != null) {
        completionData['signature_data'] = signatureData;
      }

      // Update delivery status with POD
      await _supabase
          .from('deliveries')
          .update(completionData)
          .eq('id', deliveryId);

      // Update driver availability - now available for new deliveries
      await _supabase
          .from('driver_profiles')
          .update({'is_available': true})
          .eq('id', driverId);
      print('📱 Updated driver availability to true (delivery completed)');

      // Record earnings with payment method awareness
      final earningsRecorded = await _earningsService.recordDeliveryEarnings(
        driverId: driverId,
        deliveryId: deliveryId,
        totalPrice: totalPrice,
        paymentMethod: paymentMethod,
        tips: tipAmount,
      );

      if (earningsRecorded) {
        print('✅ Delivery completed with POD and earnings recorded: $deliveryId');
        print('💰 Payment Method: ${paymentMethod.displayName}, Total: ₱$totalPrice, Tips: ₱$tipAmount');
      } else {
        print('⚠️ Delivery completed with POD but earnings recording failed: $deliveryId');
      }

      return true;
    } catch (e) {
      print('Error completing delivery with POD: $e');
      return false;
    }
  }

  // Helper method to map payment method string to enum
  PaymentMethod _mapPaymentMethod(String? paymentMethod) {
    switch (paymentMethod) {
      case 'credit_card':
      case 'maya_wallet':
      case 'qr_ph':
        return PaymentMethod.card;
      case 'cash':
        return PaymentMethod.cash;
      default:
        return PaymentMethod.cash; // Default fallback
    }
  }

  // Get delivery proof details
  Future<Map<String, dynamic>?> getDeliveryProof(String deliveryId) async {
    try {
      final response = await _supabase
          .from('deliveries')
          .select('proof_photo_url, recipient_name, delivery_notes, signature_data, delivered_at')
          .eq('id', deliveryId)
          .maybeSingle();

      return response;
    } catch (e) {
      print('Error getting delivery proof: $e');
      return null;
    }
  }
}

// POD Collection Screen
class ProofOfDeliveryScreen extends StatefulWidget {
  final Delivery delivery;
  final VoidCallback onCompleted;

  const ProofOfDeliveryScreen({
    super.key,
    required this.delivery,
    required this.onCompleted,
  });

  @override
  State<ProofOfDeliveryScreen> createState() => _ProofOfDeliveryScreenState();
}

class _ProofOfDeliveryScreenState extends State<ProofOfDeliveryScreen> {
  final ProofOfDeliveryService _podService = ProofOfDeliveryService();
  final _recipientNameController = TextEditingController();
  final _notesController = TextEditingController();
  
  File? _proofPhoto;
  bool _isSubmitting = false;
  bool _requireSignature = false;
  String? _signatureData;

  @override
  void dispose() {
    _recipientNameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _captureProofPhoto() async {
    final photo = await _podService.captureProofPhoto();
    if (photo != null) {
      setState(() {
        _proofPhoto = photo;
      });
    }
  }

  Future<void> _submitProofOfDelivery() async {
    if (_proofPhoto == null) {
      _showError('Please capture a proof of delivery photo');
      return;
    }

    if (_recipientNameController.text.trim().isEmpty) {
      _showError('Please enter recipient name');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // Upload proof photo
      final photoUrl = await _podService.uploadProofPhoto(
        _proofPhoto!,
        widget.delivery.id,
      );

      if (photoUrl == null) {
        _showError('Failed to upload proof photo');
        return;
      }

      // Complete delivery with POD
      final success = await _podService.completeDeliveryWithPOD(
        deliveryId: widget.delivery.id,
        driverId: widget.delivery.driverId ?? '',
        proofPhotoUrl: photoUrl,
        recipientName: _recipientNameController.text.trim(),
        deliveryNotes: _notesController.text.trim(),
        requireSignature: _requireSignature,
        signatureData: _signatureData,
      );

      if (success) {
        _showSuccess('Delivery completed successfully!');
        widget.onCompleted();
        if (mounted) {
          Navigator.of(context).pop();
        }
      } else {
        _showError('Failed to complete delivery');
      }
    } catch (e) {
      _showError('Error completing delivery: $e');
    } finally {
      setState(() => _isSubmitting = false);
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
        title: const Text('Proof of Delivery'),
        backgroundColor: SwiftDashColors.darkBlue,
        foregroundColor: SwiftDashColors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Delivery Info Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Delivery Information',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: SwiftDashColors.darkBlue,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildInfoRow('Delivery ID', widget.delivery.id.substring(0, 8).toUpperCase()),
                    _buildInfoRow('Customer', widget.delivery.deliveryContactName),
                    _buildInfoRow('Phone', widget.delivery.deliveryContactPhone),
                    _buildInfoRow('Address', widget.delivery.deliveryAddress),
                    _buildInfoRow('Package', widget.delivery.packageDescription),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),

            // Proof Photo Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Proof of Delivery Photo',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: SwiftDashColors.darkBlue,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Take a photo showing the delivered package at the delivery location',
                      style: TextStyle(color: SwiftDashColors.textGrey),
                    ),
                    const SizedBox(height: 16),
                    
                    if (_proofPhoto != null) ...[
                      Container(
                        width: double.infinity,
                        height: 200,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: SwiftDashColors.successGreen, width: 2),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            _proofPhoto!,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _captureProofPhoto,
                        icon: Icon(
                          _proofPhoto != null ? Icons.refresh : Icons.camera_alt,
                          color: SwiftDashColors.white,
                        ),
                        label: Text(
                          _proofPhoto != null ? 'Retake Photo' : 'Take Photo',
                          style: const TextStyle(color: SwiftDashColors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _proofPhoto != null 
                            ? SwiftDashColors.warningOrange 
                            : SwiftDashColors.darkBlue,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Recipient Information
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recipient Information',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: SwiftDashColors.darkBlue,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    TextFormField(
                      controller: _recipientNameController,
                      decoration: const InputDecoration(
                        labelText: 'Recipient Name *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                        hintText: 'Who received the package?',
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    TextFormField(
                      controller: _notesController,
                      decoration: const InputDecoration(
                        labelText: 'Delivery Notes (Optional)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.note),
                        hintText: 'Any additional notes about the delivery',
                      ),
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Submit Button
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitProofOfDelivery,
                style: ElevatedButton.styleFrom(
                  backgroundColor: SwiftDashColors.successGreen,
                  foregroundColor: SwiftDashColors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(SwiftDashColors.white),
                      ),
                    )
                  : const Text(
                      'Complete Delivery',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
              ),
            ),

            const SizedBox(height: 16),

            // Help Text
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: SwiftDashColors.lightBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: SwiftDashColors.lightBlue.withOpacity(0.3)),
              ),
              child: const Text(
                '📸 Proof of Delivery helps protect both you and the customer. '
                'Make sure the photo clearly shows the package at the delivery location.',
                style: TextStyle(
                  color: SwiftDashColors.textGrey,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
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
              value,
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