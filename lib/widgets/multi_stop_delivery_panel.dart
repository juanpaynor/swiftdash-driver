import 'package:flutter/material.dart';
import '../models/delivery.dart';
import '../models/delivery_stop.dart';
import '../services/delivery_stop_service.dart';
import '../services/document_upload_service.dart';
import 'signature_capture_dialog.dart';
import 'package:url_launcher/url_launcher.dart';

/// Widget for displaying and managing multi-stop deliveries
class MultiStopDeliveryPanel extends StatefulWidget {
  final Delivery delivery;
  final VoidCallback onStopCompleted;
  
  const MultiStopDeliveryPanel({
    super.key,
    required this.delivery,
    required this.onStopCompleted,
  });
  
  @override
  State<MultiStopDeliveryPanel> createState() => _MultiStopDeliveryPanelState();
}

class _MultiStopDeliveryPanelState extends State<MultiStopDeliveryPanel> {
  final DeliveryStopService _stopService = DeliveryStopService();
  final DocumentUploadService _uploadService = DocumentUploadService();
  
  List<DeliveryStop> _stops = [];
  DeliveryStop? _currentStop;
  bool _isLoading = false;
  bool _isCompletingStop = false;
  
  @override
  void initState() {
    super.initState();
    _loadStops();
  }
  
  Future<void> _loadStops() async {
    setState(() => _isLoading = true);
    
    try {
      final stops = await _stopService.getDeliveryStops(widget.delivery.id);
      final currentStop = await _stopService.getCurrentStop(widget.delivery.id);
      
      setState(() {
        _stops = stops;
        _currentStop = currentStop;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading stops: $e')),
        );
      }
    }
  }
  
  Future<void> _completeCurrentStop() async {
    if (_currentStop == null) return;
    
    setState(() => _isCompletingStop = true);
    
    try {
      // Capture proof photo
      final imageFile = await _uploadService.captureImage();
      if (imageFile == null) {
        throw Exception('Proof photo is required');
      }
      
      // Upload proof photo
      final proofPhotoUrl = await _uploadService.uploadProofOfDelivery(
        imageFile,
        '${widget.delivery.id}_stop_${_currentStop!.stopNumber}_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      
      String? signatureUrl;
      
      // Get signature for dropoffs
      if (_currentStop!.isDropoff && mounted) {
        signatureUrl = await _showSignatureDialog();
      }
      
      // Get completion notes
      String? notes;
      if (mounted) {
        notes = await _showNotesDialog();
      }
      
      // Complete the stop
      await _stopService.completeStop(
        stopId: _currentStop!.id,
        deliveryId: widget.delivery.id,
        proofPhotoUrl: proofPhotoUrl,
        signatureUrl: signatureUrl,
        completionNotes: notes,
      );
      
      // Reload stops
      await _loadStops();
      
      // Notify parent
      widget.onStopCompleted();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _currentStop!.isPickup 
                  ? 'Package collected successfully!' 
                  : 'Delivery completed successfully!'
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error completing stop: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isCompletingStop = false);
    }
  }
  
  Future<String?> _showSignatureDialog() async {
    return await showDialog<String>(
      context: context,
      builder: (context) => const SignatureCaptureDialog(),
    );
  }
  
  Future<String?> _showNotesDialog() async {
    final controller = TextEditingController();
    
    return await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Completion Notes'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Add any notes (optional)',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Skip'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
  
  Future<void> _navigateToStop(DeliveryStop stop) async {
    try {
      // ✅ FIX: Try native Google Maps deeplink first, fallback to HTTPS
      final nativeUri = Uri.parse('comgooglemaps://?daddr=${stop.latitude},${stop.longitude}&directionsmode=driving');
      
      if (await canLaunchUrl(nativeUri)) {
        await launchUrl(nativeUri, mode: LaunchMode.externalApplication);
        print('🗺️ Navigating to stop via Google Maps native deeplink');
      } else {
        // Fallback to HTTPS URL (works on all platforms)
        final webUri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${stop.latitude},${stop.longitude}&travelmode=driving');
        if (await canLaunchUrl(webUri)) {
          await launchUrl(webUri, mode: LaunchMode.externalApplication);
          print('🗺️ Navigating to stop via Google Maps HTTPS link');
        } else {
          throw Exception('Could not launch Google Maps');
        }
      }
    } catch (e) {
      print('❌ Error navigating to stop: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open navigation app. Please ensure Google Maps is installed.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (_currentStop == null) {
      return const Center(
        child: Text('All stops completed!', style: TextStyle(fontSize: 18)),
      );
    }
    
    final remainingStops = _stops.where((s) => s.isPending && s.stopNumber > _currentStop!.stopNumber).toList();
    final completedStops = _stops.where((s) => s.isCompleted).toList();
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Progress indicator
          _buildProgressIndicator(),
          const SizedBox(height: 24),
          
          // Current stop card
          _buildCurrentStopCard(),
          const SizedBox(height: 16),
          
          // Action button
          _buildActionButton(),
          const SizedBox(height: 24),
          
          // Remaining stops
          if (remainingStops.isNotEmpty) ...[
            const Text(
              'Remaining Stops',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...remainingStops.map((stop) => _buildStopCard(stop, false)),
          ],
          
          // Completed stops
          if (completedStops.isNotEmpty) ...[
            const SizedBox(height: 16),
            ExpansionTile(
              title: Text('Completed Stops (${completedStops.length})'),
              children: completedStops.map((stop) => _buildStopCard(stop, true)).toList(),
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildProgressIndicator() {
    final progress = widget.delivery.currentStopIndex / widget.delivery.totalStops;
    
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Stop ${widget.delivery.currentStopIndex + 1} of ${widget.delivery.totalStops}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue.shade100,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.location_on, color: Colors.blue.shade700, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    '${widget.delivery.totalStops} STOPS',
                    style: TextStyle(
                      color: Colors.blue.shade700,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LinearProgressIndicator(
          value: progress,
          backgroundColor: Colors.grey.shade300,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade600),
          minHeight: 8,
        ),
      ],
    );
  }
  
  Widget _buildCurrentStopCard() {
    if (_currentStop == null) return const SizedBox();
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _currentStop!.isPickup ? Colors.orange.shade100 : Colors.green.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _currentStop!.isPickup ? Icons.store : Icons.home,
                    color: _currentStop!.isPickup ? Colors.orange.shade700 : Colors.green.shade700,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _currentStop!.isPickup ? 'PICKUP' : 'DROP-OFF #${_currentStop!.stopNumber}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _currentStop!.isPickup ? Colors.orange.shade700 : Colors.green.shade700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _currentStop!.address,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                const Icon(Icons.person, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                Text(_currentStop!.contactName),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.phone, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                Text(_currentStop!.contactPhone),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.call, color: Colors.blue),
                  onPressed: () => _makePhoneCall(_currentStop!.contactPhone),
                ),
              ],
            ),
            if (_currentStop!.instructions != null && _currentStop!.instructions!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 18, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _currentStop!.instructions!,
                      style: const TextStyle(fontStyle: FontStyle.italic),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _navigateToStop(_currentStop!),
              icon: const Icon(Icons.navigation),
              label: const Text('Navigate'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildActionButton() {
    if (_currentStop == null) return const SizedBox();
    
    return ElevatedButton(
      onPressed: _isCompletingStop ? null : _completeCurrentStop,
      style: ElevatedButton.styleFrom(
        backgroundColor: _currentStop!.isPickup ? Colors.orange : Colors.green,
        minimumSize: const Size(double.infinity, 56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: _isCompletingStop
          ? const CircularProgressIndicator(color: Colors.white)
          : Text(
              _currentStop!.isPickup ? 'PACKAGE COLLECTED' : 'COMPLETE DELIVERY',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
    );
  }
  
  Widget _buildStopCard(DeliveryStop stop, bool isCompleted) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isCompleted ? Colors.green.shade100 : Colors.grey.shade200,
          child: Icon(
            isCompleted ? Icons.check : (stop.isPickup ? Icons.store : Icons.home),
            color: isCompleted ? Colors.green.shade700 : Colors.grey.shade600,
          ),
        ),
        title: Text(
          stop.stopTypeDisplay,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            decoration: isCompleted ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(stop.address),
            Text(
              '${stop.contactName} • ${stop.contactPhone}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        trailing: isCompleted
            ? const Icon(Icons.check_circle, color: Colors.green)
            : null,
      ),
    );
  }
  
  Future<void> _makePhoneCall(String phoneNumber) async {
    final uri = Uri.parse('tel:$phoneNumber');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}
