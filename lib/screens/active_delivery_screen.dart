import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
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
          status = DeliveryStatus.inTransit;
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
      case DeliveryStatus.pickupArrived:
        return SwiftDashColors.warningOrange;
      case DeliveryStatus.packageCollected:
        return SwiftDashColors.lightBlue;
      case DeliveryStatus.inTransit:
        return SwiftDashColors.darkBlue;
      case DeliveryStatus.delivered:
        return SwiftDashColors.successGreen;
      default:
        return SwiftDashColors.textGrey;
    }
  }
  
  Widget _getNextActionButton() {
    switch (_currentDelivery?.status) {
      case DeliveryStatus.driverAssigned:
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
        return _buildActionButton(
          'Start Delivery',
          Icons.local_shipping,
          () => _updateDeliveryStatus('in_transit'),
          SwiftDashColors.darkBlue,
        );
      case DeliveryStatus.inTransit:
        return _buildActionButton(
          'Mark as Delivered',
          Icons.check_circle,
          () => _updateDeliveryStatus('delivered'),
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
    String destination;
    
    // Determine destination based on current status
    if (delivery.status == DeliveryStatus.driverAssigned ||
        delivery.status == DeliveryStatus.pickupArrived) {
      destination = '${delivery.pickupLatitude},${delivery.pickupLongitude}';
    } else {
      destination = '${delivery.deliveryLatitude},${delivery.deliveryLongitude}';
    }
    
    final Uri googleMapsUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$destination&travelmode=driving'
    );
    
    if (await canLaunchUrl(googleMapsUri)) {
      await launchUrl(googleMapsUri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open maps'),
          backgroundColor: SwiftDashColors.dangerRed,
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
}