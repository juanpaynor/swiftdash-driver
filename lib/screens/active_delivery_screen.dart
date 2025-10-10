import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/delivery.dart';
import '../core/supabase_config.dart';
import '../services/driver_flow_service.dart';
import '../services/location_service.dart';
import '../widgets/route_preview_map.dart';

class ActiveDeliveryScreen extends StatefulWidget {
  final Delivery delivery;

  const ActiveDeliveryScreen({
    super.key,
    required this.delivery,
  });

  @override
  State<ActiveDeliveryScreen> createState() => _ActiveDeliveryScreenState();
}

class _ActiveDeliveryScreenState extends State<ActiveDeliveryScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  
  final DriverFlowService _driverFlow = DriverFlowService();
  final LocationService _locationService = LocationService.instance;
  
  Delivery? _currentDelivery;
  bool _isUpdatingStatus = false;
  
  @override
  void initState() {
    super.initState();
    _currentDelivery = widget.delivery;
    _initializeAnimations();
    _startLocationTracking();
  }
  
  void _initializeAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
  }
  
  void _startLocationTracking() {
    // Location tracking is now handled by the DriverFlowService
    // when delivery is accepted. This method is kept for compatibility
    // but the actual tracking is managed centrally.
    print('Location tracking is managed by DriverFlowService');
  }
  
  Future<void> _updateDeliveryStatus(String newStatus) async {
    if (_isUpdatingStatus) return;
    
    setState(() => _isUpdatingStatus = true);
    
    try {
      DeliveryStatus status;
      switch (newStatus) {
        case 'pickup_arrived':
          status = DeliveryStatus.pickupArrived;
          break;
        case 'package_collected':
          status = DeliveryStatus.packageCollected;
          break;
        case 'in_transit':
          status = DeliveryStatus.goingToDestination;
          break;
        case 'going_to_destination':
          status = DeliveryStatus.goingToDestination;
          break;
        case 'delivered':
          status = DeliveryStatus.delivered;
          break;
        default:
          throw Exception('Invalid status: $newStatus');
      }

      final success = await _driverFlow.updateDeliveryStatus(context, status);

      if (success) {
        setState(() {
          _currentDelivery = _currentDelivery!.copyWith(status: status);
        });
        
        if (status == DeliveryStatus.delivered) {
          // Navigate back to dashboard after completion
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update status: $e'),
          backgroundColor: SwiftDashColors.dangerRed,
        ),
      );
    } finally {
      setState(() => _isUpdatingStatus = false);
    }
  }
  
  String _getStatusDisplayName(String status) {
    switch (status) {
      case 'pickup_arrived': return 'Arrived at Pickup';
      case 'package_collected': return 'Package Collected';
      case 'in_transit': return 'In Transit';
      case 'delivered': return 'Delivered';
      default: return status;
    }
  }
  
  Color _getStatusColor() {
    switch (_currentDelivery?.status) {
      case DeliveryStatus.driverAssigned:
        return SwiftDashColors.lightBlue;
      case DeliveryStatus.goingToPickup:
        return SwiftDashColors.darkBlue;
      case DeliveryStatus.pickupArrived:
        return SwiftDashColors.warningOrange;
      case DeliveryStatus.packageCollected:
        return SwiftDashColors.lightBlue;
      case DeliveryStatus.goingToDestination:
        return SwiftDashColors.darkBlue;
      case DeliveryStatus.atDestination:
        return SwiftDashColors.warningOrange;
      case DeliveryStatus.delivered:
        return SwiftDashColors.successGreen;
      default:
        return SwiftDashColors.textGrey;
    }
  }
  
  Widget _getNextActionButton() {
    switch (_currentDelivery?.status) {
      case DeliveryStatus.driverAssigned:
        return _buildNavigationButton(
          'Navigate to Pickup',
          Icons.navigation,
          () => _startNavigation(isPickup: true),
          SwiftDashColors.lightBlue,
        );
      case DeliveryStatus.goingToPickup:
        return _buildActionButton(
          'Arrived at Pickup',
          Icons.my_location,
          () => _updateDeliveryStatus('pickup_arrived'),
          SwiftDashColors.warningOrange,
        );
      case DeliveryStatus.pickupArrived:
        return _buildActionButton(
          'Package Collected',
          Icons.inventory_2,
          () => _updateDeliveryStatus('package_collected'),
          SwiftDashColors.lightBlue,
        );
      case DeliveryStatus.packageCollected:
        return _buildNavigationButton(
          'Navigate to Destination',
          Icons.navigation,
          () => _startNavigation(isPickup: false),
          SwiftDashColors.darkBlue,
        );
      case DeliveryStatus.goingToDestination:
        return _buildActionButton(
          'Arrived at Destination',
          Icons.location_on,
          () => _updateDeliveryStatus('at_destination'),
          SwiftDashColors.warningOrange,
        );
      case DeliveryStatus.atDestination:
        return _buildActionButton(
          'Complete Delivery',
          Icons.photo_camera,
          () => _showProofOfDeliveryDialog(),
          SwiftDashColors.successGreen,
        );
      case DeliveryStatus.delivered:
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: SwiftDashColors.successGreen,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.check_circle,
                color: SwiftDashColors.white,
              ),
              const SizedBox(width: 8),
              const Text(
                'Delivery Completed',
                style: TextStyle(
                  color: SwiftDashColors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }
  
  Widget _buildActionButton(
    String text,
    IconData icon,
    VoidCallback onTap,
    Color color,
  ) {
    return GestureDetector(
      onTap: _isUpdatingStatus ? null : onTap,
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _pulseAnimation.value,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isUpdatingStatus)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(SwiftDashColors.white),
                      ),
                    )
                  else
                    Icon(icon, color: SwiftDashColors.white),
                  const SizedBox(width: 8),
                  Text(
                    text,
                    style: const TextStyle(
                      color: SwiftDashColors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
  
  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri launchUri = Uri(
      scheme: 'tel',
      path: phoneNumber,
    );
    
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not launch phone dialer'),
          backgroundColor: SwiftDashColors.dangerRed,
        ),
      );
    }
  }
  
  Future<void> _openMaps() async {
    final delivery = _currentDelivery!;
    
    // Determine destination based on current status
    final bool isPickupPhase = delivery.status == DeliveryStatus.driverAssigned ||
                               delivery.status == DeliveryStatus.pickupArrived;
    
    final double lat = isPickupPhase ? delivery.pickupLatitude : delivery.deliveryLatitude;
    final double lng = isPickupPhase ? delivery.pickupLongitude : delivery.deliveryLongitude;
    final String address = isPickupPhase ? delivery.pickupAddress : delivery.deliveryAddress;
    final String destination = '$lat,$lng';
    
    // Show navigation options dialog
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.navigation,
                  color: SwiftDashColors.darkBlue,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Navigate to ${isPickupPhase ? "Pickup" : "Delivery"}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: SwiftDashColors.darkBlue,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        address,
                        style: TextStyle(
                          fontSize: 14,
                          color: SwiftDashColors.textGrey,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // Google Maps option
            _buildNavigationOption(
              'Google Maps',
              Icons.map,
              SwiftDashColors.successGreen,
              () async {
                final Uri googleMapsUri = Uri.parse(
                  'https://www.google.com/maps/dir/?api=1&destination=$destination&travelmode=driving'
                );
                await _launchNavigationApp(googleMapsUri, 'Google Maps');
              },
            ),
            
            const SizedBox(height: 12),
            
            // Waze option
            _buildNavigationOption(
              'Waze',
              Icons.alt_route,
              SwiftDashColors.warningOrange,
              () async {
                final Uri wazeUri = Uri.parse(
                  'https://waze.com/ul?ll=$lat,$lng&navigate=yes'
                );
                await _launchNavigationApp(wazeUri, 'Waze');
              },
            ),
            
            const SizedBox(height: 12),
            
            // Apple Maps option (iOS)
            _buildNavigationOption(
              'Apple Maps',
              Icons.location_on,
              SwiftDashColors.lightBlue,
              () async {
                final Uri appleMapsUri = Uri.parse(
                  'https://maps.apple.com/?daddr=$lat,$lng&dirflg=d'
                );
                await _launchNavigationApp(appleMapsUri, 'Apple Maps');
              },
            ),
            
            const SizedBox(height: 20),
            
            // Cancel button
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: SwiftDashColors.textGrey),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildNavigationOption(
    String name,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: color.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: SwiftDashColors.darkBlue,
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: SwiftDashColors.textGrey,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
  
  Future<void> _launchNavigationApp(Uri uri, String appName) async {
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        
        // Show success feedback
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Opening $appName...'),
            backgroundColor: SwiftDashColors.successGreen,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        throw Exception('Could not launch $appName');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$appName is not installed on this device'),
          backgroundColor: SwiftDashColors.dangerRed,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
  
  @override
  void dispose() {
    _pulseController.dispose();
    _locationService.stopLocationTracking();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    if (_currentDelivery == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    
    final delivery = _currentDelivery!;
    final isPickupPhase = delivery.status == DeliveryStatus.driverAssigned ||
                         delivery.status == DeliveryStatus.pickupArrived;
    
    return Scaffold(
      backgroundColor: SwiftDashColors.backgroundGrey,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _getStatusColor(),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _getStatusDisplayName(delivery.status.toString().split('.').last),
                style: const TextStyle(
                  color: SwiftDashColors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Order #${delivery.id.substring(0, 8).toUpperCase()}',
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.navigation),
            onPressed: _openMaps,
            tooltip: 'Open in Maps',
          ),
        ],
      ),
      body: Column(
        children: [
          // Route preview map
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.3,
            child: RoutePreviewMap(
              pickupLat: delivery.pickupLatitude,
              pickupLng: delivery.pickupLongitude,
              deliveryLat: delivery.deliveryLatitude,
              deliveryLng: delivery.deliveryLongitude,
            ),
          ),
          
          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Current destination card
                  Card(
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
                                  color: isPickupPhase 
                                    ? SwiftDashColors.successGreen.withOpacity(0.1)
                                    : SwiftDashColors.dangerRed.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isPickupPhase ? Icons.radio_button_checked : Icons.location_on,
                                  color: isPickupPhase 
                                    ? SwiftDashColors.successGreen 
                                    : SwiftDashColors.dangerRed,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isPickupPhase ? 'Pickup Location' : 'Delivery Location',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: SwiftDashColors.textGrey,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      isPickupPhase ? delivery.pickupAddress : delivery.deliveryAddress,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: SwiftDashColors.darkBlue,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          
                          const SizedBox(height: 16),
                          
                          // Contact information
                          Row(
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.person_outline,
                                      size: 16,
                                      color: SwiftDashColors.textGrey,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      isPickupPhase 
                                        ? delivery.pickupContactName 
                                        : delivery.deliveryContactName,
                                      style: TextStyle(
                                        color: SwiftDashColors.textGrey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              GestureDetector(
                                onTap: () => _makePhoneCall(
                                  isPickupPhase 
                                    ? delivery.pickupContactPhone 
                                    : delivery.deliveryContactPhone,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: SwiftDashColors.lightBlue,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.phone,
                                        color: SwiftDashColors.white,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Call ${isPickupPhase ? "Sender" : "Recipient"}',
                                        style: const TextStyle(
                                          color: SwiftDashColors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          
                          const SizedBox(height: 16),
                          
                          // Navigation button
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _openMaps,
                              icon: const Icon(Icons.navigation, size: 20),
                              label: Text(
                                'Navigate to ${isPickupPhase ? "Pickup" : "Delivery"}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: SwiftDashColors.darkBlue,
                                foregroundColor: SwiftDashColors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Package details
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.inventory_2_outlined,
                                color: SwiftDashColors.darkBlue,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Package Details',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: SwiftDashColors.darkBlue,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            delivery.packageDescription,
                            style: TextStyle(
                              color: SwiftDashColors.textGrey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Delivery info
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Order ID',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: SwiftDashColors.textGrey,
                                      ),
                                    ),
                                    Text(
                                      '#${delivery.id.substring(0, 8).toUpperCase()}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: SwiftDashColors.darkBlue,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      'Total Fare',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: SwiftDashColors.textGrey,
                                      ),
                                    ),
                                    Text(
                                      '₱${delivery.totalPrice.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                        color: SwiftDashColors.darkBlue,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          
          // Action button
          Container(
            padding: const EdgeInsets.all(16),
            color: SwiftDashColors.white,
            child: SafeArea(
              child: _getNextActionButton(),
            ),
          ),
        ],
      ),
    );
  }

  // Navigation button widget (different from action button)
  Widget _buildNavigationButton(
    String text,
    IconData icon,
    VoidCallback onTap,
    Color color,
  ) {
    return GestureDetector(
      onTap: _isUpdatingStatus ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: SwiftDashColors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              text,
              style: const TextStyle(
                color: SwiftDashColors.white,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Start navigation to pickup or destination
  Future<void> _startNavigation({required bool isPickup}) async {
    try {
      final delivery = _currentDelivery!;
      final lat = isPickup ? delivery.pickupLatitude : delivery.deliveryLatitude;
      final lng = isPickup ? delivery.pickupLongitude : delivery.deliveryLongitude;
      final address = isPickup ? delivery.pickupAddress : delivery.deliveryAddress;

      // Show navigation options dialog
      await showModalBottomSheet(
        context: context,
        builder: (context) => Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Navigate to ${isPickup ? "Pickup" : "Destination"}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                address,
                style: TextStyle(color: SwiftDashColors.textGrey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _buildNavOption(
                      'Google Maps',
                      Icons.map,
                      () => _launchNavigation('google', lat, lng),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildNavOption(
                      'Waze',
                      Icons.navigation,
                      () => _launchNavigation('waze', lat, lng),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      // Update status to indicate navigation started
      final newStatus = isPickup ? 'going_to_pickup' : 'going_to_destination';
      await _updateDeliveryStatus(newStatus);

    } catch (e) {
      print('Error starting navigation: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start navigation: $e')),
      );
    }
  }

  Widget _buildNavOption(String title, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: SwiftDashColors.lightBlue,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: SwiftDashColors.white, size: 24),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                color: SwiftDashColors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launchNavigation(String app, double lat, double lng) async {
    try {
      String url;
      if (app == 'google') {
        url = 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng';
      } else {
        url = 'https://waze.com/ul?ll=$lat,$lng&navigate=yes';
      }

      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        Navigator.pop(context); // Close the navigation options modal
      } else {
        throw 'Could not launch $app';
      }
    } catch (e) {
      print('Error launching navigation: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $app')),
      );
    }
  }

  // Show proof of delivery dialog
  Future<void> _showProofOfDeliveryDialog() async {
    String recipientName = '';
    String notes = '';

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Complete Delivery'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Confirm delivery completion:'),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Recipient Name',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => recipientName = value,
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Delivery Notes (Optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
              onChanged: (value) => notes = value,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _completeDeliveryWithProof(null, recipientName, notes);
            },
            child: const Text('Complete Delivery'),
          ),
        ],
      ),
    );
  }

  // Complete delivery with proof of delivery
  Future<void> _completeDeliveryWithProof(
    String? photoUrl,
    String recipientName,
    String notes,
  ) async {
    setState(() => _isUpdatingStatus = true);

    try {
      final supabase = Supabase.instance.client;
      
      // Update delivery with POD data as specified by customer app AI
      await supabase.from('deliveries').update({
        'status': 'delivered',
        'proof_photo_url': photoUrl,
        'recipient_name': recipientName,
        'delivery_notes': notes,
        'completed_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', _currentDelivery!.id);

      // Update local state
      setState(() {
        _currentDelivery = _currentDelivery!.copyWith(
          status: DeliveryStatus.delivered,
          proofPhotoUrl: photoUrl,
          recipientName: recipientName,
          deliveryNotes: notes,
          completedAt: DateTime.now(),
        );
      });

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Delivery completed successfully!'),
          backgroundColor: SwiftDashColors.successGreen,
        ),
      );

      // Navigate back to main screen after a short delay
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }

    } catch (e) {
      print('Error completing delivery: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to complete delivery: $e'),
          backgroundColor: SwiftDashColors.dangerRed,
        ),
      );
    } finally {
      setState(() => _isUpdatingStatus = false);
    }
  }
}