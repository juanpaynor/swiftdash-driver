import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/delivery.dart';
import '../services/realtime_service.dart';
import '../services/auth_service.dart';
import '../services/driver_flow_service.dart';
import '../core/supabase_config.dart';
import '../screens/active_delivery_screen.dart';

class ImprovedDeliveryOffersScreen extends StatefulWidget {
  const ImprovedDeliveryOffersScreen({super.key});

  @override
  State<ImprovedDeliveryOffersScreen> createState() => _ImprovedDeliveryOffersScreenState();
}

class _ImprovedDeliveryOffersScreenState extends State<ImprovedDeliveryOffersScreen> {
  final RealtimeService _realtimeService = RealtimeService();
  final AuthService _authService = AuthService();
  final DriverFlowService _driverFlow = DriverFlowService();
  
  List<Delivery> _availableOffers = [];
  List<Delivery> _activeDeliveries = [];
  bool _isLoading = true;
  String? _driverId;
  
  @override
  void initState() {
    super.initState();
    _initializeScreen();
  }
  
  Future<void> _initializeScreen() async {
    try {
      final driver = await _authService.getCurrentDriverProfile();
      if (driver == null) {
        _showError('Driver profile not found');
        return;
      }
      
      setState(() {
        _driverId = driver.id;
      });
      
      // Initialize realtime subscriptions
      await _realtimeService.initializeRealtimeSubscriptions(driver.id);
      
      // Listen to new offers
      _realtimeService.offerModalStream.listen((delivery) {
        if (mounted) {
          _showOfferModal(delivery);
        }
      });
      
      // Listen to delivery updates
      _realtimeService.deliveryUpdates.listen((delivery) {
        if (mounted) {
          _updateActiveDelivery(delivery);
        }
      });
      
      // Load initial data
      await _loadData();
      
    } catch (e) {
      _showError('Failed to initialize: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }
  
  Future<void> _loadData() async {
    try {
      if (_driverId == null) return;
      
      // Load available offers and active deliveries
      final offers = await _realtimeService.getAvailableDeliveryOffers();
      final active = await _realtimeService.getPendingDeliveries(_driverId!);
      
      setState(() {
        _availableOffers = offers;
        _activeDeliveries = active;
      });
    } catch (e) {
      _showError('Failed to load data: $e');
    }
  }
  
  void _showOfferModal(Delivery delivery) {
    RealtimeService.showImprovedOfferModal(
      context,
      delivery,
      _acceptDeliveryOffer,
      _declineDeliveryOffer,
      _driverId!,
    );
  }
  
  Future<bool> _acceptDeliveryOffer(String deliveryId, String driverId) async {
    try {
      // Find the delivery object
      Delivery? delivery;
      try {
        delivery = _availableOffers.firstWhere((d) => d.id == deliveryId);
      } catch (_) {
        try {
          delivery = _activeDeliveries.firstWhere((d) => d.id == deliveryId);
        } catch (_) {
          delivery = null;
        }
      }

      if (delivery == null) {
        _showError('Delivery not found');
        return false;
      }

      // Use driver flow service for proper accept handling
      final success = await _driverFlow.acceptDeliveryOffer(context, delivery);

      if (success) {
        // Refresh data
        await _loadData();
      }

      return success;
    } catch (e) {
      _showError('Failed to accept delivery: $e');
      return false;
    }
  }

  Future<bool> _declineDeliveryOffer(String deliveryId, String driverId) async {
    try {
      // Find the delivery object
      Delivery? delivery;
      try {
        delivery = _availableOffers.firstWhere((d) => d.id == deliveryId);
      } catch (_) {
        try {
          delivery = _activeDeliveries.firstWhere((d) => d.id == deliveryId);
        } catch (_) {
          delivery = null;
        }
      }

      if (delivery == null) {
        _showError('Delivery not found');
        return false;
      }

      // Use driver flow service for proper decline handling
      final success = await _driverFlow.declineDeliveryOffer(context, delivery);

      if (success) {
        // Refresh data to remove the declined offer
        await _loadData();
      }

      return success;
    } catch (e) {
      _showError('Failed to decline delivery: $e');
      return false;
    }
  }
  
  void _updateActiveDelivery(Delivery delivery) {
    setState(() {
      final index = _activeDeliveries.indexWhere((d) => d.id == delivery.id);
      if (index != -1) {
        _activeDeliveries[index] = delivery;
      } else {
        _activeDeliveries.add(delivery);
      }
    });
  }
  
  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: SwiftDashColors.dangerRed,
        ),
      );
    }
  }

  @override
  void dispose() {
    _realtimeService.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: SwiftDashColors.backgroundGrey,
        appBar: AppBar(
          title: const Text('Delivery Offers'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    
    return Scaffold(
      backgroundColor: SwiftDashColors.backgroundGrey,
      appBar: AppBar(
        title: const Text('Delivery Offers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: CustomScrollView(
          slivers: [
            // Active Deliveries Section
            if (_activeDeliveries.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Active Deliveries',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: SwiftDashColors.darkBlue,
                    ),
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final delivery = _activeDeliveries[index];
                    return _buildActiveDeliveryCard(delivery);
                  },
                  childCount: _activeDeliveries.length,
                ),
              ),
              const SliverToBoxAdapter(
                child: SizedBox(height: 16),
              ),
            ],
            
            // Available Offers Section
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Available Offers',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: SwiftDashColors.darkBlue,
                  ),
                ),
              ),
            ),
            
            if (_availableOffers.isEmpty)
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: SwiftDashColors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.local_shipping_outlined,
                        size: 64,
                        color: SwiftDashColors.textGrey.withOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No delivery offers available',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: SwiftDashColors.textGrey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'New delivery requests will appear here automatically',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: SwiftDashColors.textGrey,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final delivery = _availableOffers[index];
                    return _buildOfferCard(delivery);
                  },
                  childCount: _availableOffers.length,
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildActiveDeliveryCard(Delivery delivery) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        elevation: 4,
        child: InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => ActiveDeliveryScreen(delivery: delivery),
              ),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status badge and order ID
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _getStatusColor(delivery.status),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        delivery.status.displayName,
                        style: const TextStyle(
                          color: SwiftDashColors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '#${delivery.id.substring(0, 8).toUpperCase()}',
                      style: TextStyle(
                        color: SwiftDashColors.textGrey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                // Route info
                Row(
                  children: [
                    // Pickup
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: SwiftDashColors.successGreen,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Pickup',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: SwiftDashColors.textGrey,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Padding(
                            padding: const EdgeInsets.only(left: 16),
                            child: Text(
                              delivery.pickupAddress,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 14,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      child: Icon(
                        Icons.arrow_forward,
                        color: SwiftDashColors.textGrey,
                        size: 20,
                      ),
                    ),
                    
                    // Delivery
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: SwiftDashColors.dangerRed,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Delivery',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: SwiftDashColors.textGrey,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Padding(
                            padding: const EdgeInsets.only(left: 16),
                            child: Text(
                              delivery.deliveryAddress,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 14,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                // Bottom info
                Row(
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 16,
                      color: SwiftDashColors.textGrey,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        delivery.packageDescription,
                        style: TextStyle(
                          color: SwiftDashColors.textGrey,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '₱${delivery.totalPrice.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: SwiftDashColors.darkBlue,
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
  
  Widget _buildOfferCard(Delivery delivery) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        elevation: 2,
        child: InkWell(
          onTap: () => _showOfferModal(delivery),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Distance and price header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: SwiftDashColors.lightBlue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        delivery.formattedDistance,
                        style: TextStyle(
                          color: SwiftDashColors.lightBlue,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const Spacer(),
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
                
                const SizedBox(height: 12),
                
                // Addresses
                Row(
                  children: [
                    Icon(
                      Icons.radio_button_checked,
                      color: SwiftDashColors.successGreen,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        delivery.pickupAddress,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 8),
                
                Row(
                  children: [
                    Icon(
                      Icons.location_on,
                      color: SwiftDashColors.dangerRed,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        delivery.deliveryAddress,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 12),
                
                // Package info
                Text(
                  delivery.packageDescription,
                  style: TextStyle(
                    color: SwiftDashColors.textGrey,
                    fontSize: 14,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                
                const SizedBox(height: 16),
                
                // Quick navigation button
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _quickNavigate(delivery),
                        icon: const Icon(Icons.navigation, size: 16),
                        label: Text(
                          _getNavigationLabel(delivery),
                          style: const TextStyle(fontSize: 13),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: SwiftDashColors.darkBlue,
                          side: BorderSide(color: SwiftDashColors.darkBlue.withOpacity(0.3)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => ActiveDeliveryScreen(delivery: delivery),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: SwiftDashColors.darkBlue,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        child: const Text(
                          'View Details',
                          style: TextStyle(fontSize: 13),
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
  
  String _getNavigationLabel(Delivery delivery) {
    final bool isPickupPhase = delivery.status == DeliveryStatus.driverAssigned ||
                               delivery.status == DeliveryStatus.pickupArrived;
    return isPickupPhase ? 'Navigate to Pickup' : 'Navigate to Delivery';
  }
  
  Future<void> _quickNavigate(Delivery delivery) async {
    final bool isPickupPhase = delivery.status == DeliveryStatus.driverAssigned ||
                               delivery.status == DeliveryStatus.pickupArrived;
    
    final double lat = isPickupPhase ? delivery.pickupLatitude : delivery.deliveryLatitude;
    final double lng = isPickupPhase ? delivery.pickupLongitude : delivery.deliveryLongitude;
    final String destination = '$lat,$lng';
    
    // Quick launch Google Maps (most common)
    final Uri googleMapsUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$destination&travelmode=driving'
    );
    
    try {
      if (await canLaunchUrl(googleMapsUri)) {
        await launchUrl(googleMapsUri, mode: LaunchMode.externalApplication);
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Opening Google Maps...'),
            backgroundColor: SwiftDashColors.successGreen,
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        throw Exception('Could not launch Google Maps');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please install a navigation app (Google Maps, Waze, etc.)'),
          backgroundColor: SwiftDashColors.dangerRed,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Color _getStatusColor(DeliveryStatus status) {
    switch (status) {
      case DeliveryStatus.driverAssigned:
        return SwiftDashColors.lightBlue;
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
}