import 'package:flutter/material.dart';
import 'dart:async';
import '../core/supabase_config.dart';
import '../services/realtime_service.dart';
import '../services/auth_service.dart';
import '../services/mapbox_service.dart';
import '../models/delivery.dart';
import '../widgets/route_preview_map.dart';
// Legacy modal removed - use improved modal via RealtimeService.showImprovedOfferModal

class DeliveryOffersScreen extends StatefulWidget {
  const DeliveryOffersScreen({super.key});

  @override
  State<DeliveryOffersScreen> createState() => _DeliveryOffersScreenState();
}

class _DeliveryOffersScreenState extends State<DeliveryOffersScreen> {
  final RealtimeService _realtimeService = RealtimeService();
  final AuthService _authService = AuthService();
  
  List<Delivery> _availableOffers = [];
  List<Delivery> _pendingDeliveries = [];
  StreamSubscription? _newOffersSubscription;
  StreamSubscription? _deliveryUpdatesSubscription;
  StreamSubscription? _offerModalSubscription;
  bool _isLoading = true;
  String? _driverId;
  
  // Cache for route data
  final Map<String, RouteData> _routeCache = {};
  final Map<String, Future<RouteData?>> _routeRequests = {};
  
  // Offer modal tracking
  bool _isOfferModalOpen = false;

  @override
  void initState() {
    super.initState();
    _initializeRealtimeService();
  }

  @override
  void dispose() {
    _newOffersSubscription?.cancel();
    _deliveryUpdatesSubscription?.cancel();
    _offerModalSubscription?.cancel();
    _realtimeService.dispose();
    super.dispose();
  }

  Future<void> _initializeRealtimeService() async {
    try {
      final user = _authService.currentUser;
      if (user == null) return;
      
      _driverId = user.id;
      
      // Initialize realtime subscriptions
      await _realtimeService.initializeRealtimeSubscriptions(_driverId!);
      
      // Listen for new delivery offers
      _newOffersSubscription = _realtimeService.newDeliveries.listen(
        (delivery) {
          setState(() {
            _availableOffers.add(delivery);
          });
          _showNewOfferNotification(delivery);
        },
      );
      
      // Listen for delivery updates
      _deliveryUpdatesSubscription = _realtimeService.deliveryUpdates.listen(
        (delivery) {
          setState(() {
            // Update pending deliveries list
            final index = _pendingDeliveries.indexWhere((d) => d.id == delivery.id);
            if (index != -1) {
              _pendingDeliveries[index] = delivery;
            } else if (delivery.driverId == _driverId) {
              _pendingDeliveries.add(delivery);
            }
            
            // Remove from available offers if accepted
            _availableOffers.removeWhere((d) => d.id == delivery.id);
          });
        },
      );
      
      // Listen for offer modal triggers
      _offerModalSubscription = _realtimeService.offerModalStream.listen(
        (delivery) {
          if (!_isOfferModalOpen && mounted) {
            _showOfferModal(delivery);
          }
        },
      );
      
      // Load initial data
      await _loadInitialData();
      
    } catch (e) {
      print('Error initializing realtime service: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to connect to delivery service: $e'),
            backgroundColor: SwiftDashColors.dangerRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadInitialData() async {
    if (_driverId == null) return;
    
    try {
      // Load available offers and pending deliveries
      final offers = await _realtimeService.getAvailableDeliveryOffers();
      final pending = await _realtimeService.getPendingDeliveries(_driverId!);
      
      setState(() {
        _availableOffers = offers;
        _pendingDeliveries = pending;
      });
    } catch (e) {
      print('Error loading initial data: $e');
    }
  }

  void _showNewOfferNotification(Delivery delivery) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.local_shipping, color: SwiftDashColors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'New delivery offer: ${delivery.pickupAddress}',
                style: const TextStyle(color: SwiftDashColors.white),
              ),
            ),
          ],
        ),
        backgroundColor: SwiftDashColors.lightBlue,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'View',
          textColor: SwiftDashColors.white,
          onPressed: () {
            // Auto-scroll to the new offer or show details
          },
        ),
      ),
    );
  }

  Future<bool> _acceptOffer(Delivery delivery) async {
    if (_driverId == null) return false;

    try {
      final success = await _realtimeService.acceptDeliveryOffer(delivery.id, _driverId!);

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Delivery accepted successfully!'),
            backgroundColor: SwiftDashColors.successGreen,
          ),
        );
        return true;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Delivery was already taken by another driver'),
            backgroundColor: SwiftDashColors.warningOrange,
          ),
        );
        return false;
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to accept delivery: $e'),
          backgroundColor: SwiftDashColors.dangerRed,
        ),
      );
      return false;
    }
  }

  void _showOfferModal(Delivery delivery) {
    if (_isOfferModalOpen) return;
    
    setState(() {
      _isOfferModalOpen = true;
    });
    
    // Use improved offer modal which awaits DB-confirmed accept
    RealtimeService.showImprovedOfferModal(
      context,
      delivery,
      (String deliveryId, String driverId) async {
        // call accept logic and close modal only on success
        final ok = await _acceptOffer(delivery);
        if (ok) {
          // mark modal open flag false — caller will dismiss modal via the improved modal flow
          setState(() => _isOfferModalOpen = false);
        }
        return ok;
      },
      (String deliveryId, String driverId) async {
        // Decline callback - just close the modal
        setState(() => _isOfferModalOpen = false);
        return true;
      },
      _driverId!,
    );
  }

  Future<RouteData?> _getRouteData(Delivery delivery) async {
    final cacheKey = '${delivery.pickupLatitude},${delivery.pickupLongitude}-${delivery.deliveryLatitude},${delivery.deliveryLongitude}';
    
    // Check cache first
    if (_routeCache.containsKey(cacheKey)) {
      return _routeCache[cacheKey];
    }
    
    // Check if request is already in progress
    if (_routeRequests.containsKey(cacheKey)) {
      return await _routeRequests[cacheKey];
    }
    
    // Make new request
    final request = MapboxService.getRoute(
      delivery.pickupLatitude,
      delivery.pickupLongitude,
      delivery.deliveryLatitude,
      delivery.deliveryLongitude,
    );
    
    _routeRequests[cacheKey] = request;
    
    try {
      final routeData = await request;
      if (routeData != null) {
        _routeCache[cacheKey] = routeData;
      }
      return routeData;
    } finally {
      _routeRequests.remove(cacheKey);
    }
  }

  // Test helper removed for production builds

  Widget _buildStatItem(IconData icon, String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: color,
          ),
          textAlign: TextAlign.center,
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: SwiftDashColors.textGrey,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Delivery Offers'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Delivery Offers'),
        backgroundColor: SwiftDashColors.darkBlue,
        actions: [],
      ),
      body: RefreshIndicator(
        onRefresh: _loadInitialData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Current Deliveries Section
              if (_pendingDeliveries.isNotEmpty) ...[
                Text(
                  'Current Deliveries',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: SwiftDashColors.darkBlue,
                  ),
                ),
                const SizedBox(height: 12),
                ..._pendingDeliveries.map((delivery) => _buildCurrentDeliveryCard(delivery)),
                const SizedBox(height: 24),
              ],
              
              // Available Offers Section
              Text(
                'Available Offers',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: SwiftDashColors.darkBlue,
                ),
              ),
              const SizedBox(height: 12),
              
              if (_availableOffers.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(
                          Icons.delivery_dining,
                          size: 48,
                          color: SwiftDashColors.textGrey.withOpacity(0.5),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No delivery offers available',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: SwiftDashColors.textGrey,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'New offers will appear here automatically',
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
                ..._availableOffers.map((delivery) => _buildOfferCard(delivery)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOfferCard(Delivery delivery) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with earnings and status
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: SwiftDashColors.lightBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'NEW OFFER',
                    style: TextStyle(
                      color: SwiftDashColors.lightBlue,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₱${delivery.totalPrice.toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: SwiftDashColors.successGreen,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'estimated',
                      style: TextStyle(
                        fontSize: 10,
                        color: SwiftDashColors.textGrey,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Route preview
            FutureBuilder<RouteData?>(
              future: _getRouteData(delivery),
              builder: (context, snapshot) {
                final routeData = snapshot.data;
                final screenWidth = MediaQuery.of(context).size.width;
                
                return Column(
                  children: [
                    // Route preview map/fallback
                    if (snapshot.connectionState == ConnectionState.waiting)
                      Container(
                        height: MediaQuery.of(context).size.height * 0.25,
                        constraints: const BoxConstraints(
                          minHeight: 180,
                          maxHeight: 300,
                        ),
                        decoration: BoxDecoration(
                          color: SwiftDashColors.backgroundGrey,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: SwiftDashColors.textGrey.withOpacity(0.3)),
                        ),
                        child: const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 8),
                              Text(
                                'Loading route...',
                                style: TextStyle(
                                  color: SwiftDashColors.textGrey,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (routeData != null)
                      RoutePreviewMap(
                        pickupLat: delivery.pickupLatitude,
                        pickupLng: delivery.pickupLongitude,
                        deliveryLat: delivery.deliveryLatitude,
                        deliveryLng: delivery.deliveryLongitude,
                        routeData: routeData,
                      )
                    else
                      SimpleRoutePreview(
                        pickupAddress: delivery.pickupAddress,
                        deliveryAddress: delivery.deliveryAddress,
                        routeData: null,
                      ),
                    
                    const SizedBox(height: 16),
                    
                    // Route stats row
                    if (routeData != null)
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: screenWidth < 360 ? 12 : 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: SwiftDashColors.backgroundGrey,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildStatItem(
                                Icons.straighten,
                                'Distance',
                                MapboxService.formatDistance(routeData.distance),
                                SwiftDashColors.lightBlue,
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 30,
                              color: SwiftDashColors.textGrey.withOpacity(0.3),
                            ),
                            Expanded(
                              child: _buildStatItem(
                                Icons.access_time,
                                'Duration',
                                MapboxService.formatDuration(routeData.duration),
                                SwiftDashColors.warningOrange,
                              ),
                            ),
                            if (delivery.packageDescription.isNotEmpty) ...[
                              Container(
                                width: 1,
                                height: 30,
                                color: SwiftDashColors.textGrey.withOpacity(0.3),
                              ),
                              Expanded(
                                child: _buildStatItem(
                                  Icons.inventory_2,
                                  'Package',
                                  delivery.packageDescription,
                                  SwiftDashColors.darkBlue,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
            
            const SizedBox(height: 12),
            
            // Pickup Location
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: SwiftDashColors.successGreen,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pickup',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: SwiftDashColors.textGrey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        delivery.pickupAddress,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            // Dropoff Location
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: SwiftDashColors.dangerRed,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Dropoff',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: SwiftDashColors.textGrey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        delivery.deliveryAddress,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Action Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                  onPressed: () async {
                    await _acceptOffer(delivery);
                  },
                style: ElevatedButton.styleFrom(
                  backgroundColor: SwiftDashColors.successGreen,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  'Accept Delivery',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: SwiftDashColors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentDeliveryCard(Delivery delivery) {
    Color statusColor;
    String statusText;
    
    switch (delivery.status) {
      case DeliveryStatus.driverAssigned:
        statusColor = SwiftDashColors.lightBlue;
        statusText = 'ASSIGNED';
        break;
      case DeliveryStatus.packageCollected:
        statusColor = SwiftDashColors.warningOrange;
        statusText = 'PICKED UP';
        break;
      case DeliveryStatus.goingToDestination:
        statusColor = SwiftDashColors.warningOrange;
        statusText = 'IN TRANSIT';
        break;
      case DeliveryStatus.atDestination:
        statusColor = SwiftDashColors.darkBlue;
        statusText = 'AT DESTINATION';
        break;
      default:
        statusColor = SwiftDashColors.textGrey;
        statusText = delivery.status.displayName.toUpperCase();
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '₱${delivery.totalPrice.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: SwiftDashColors.darkBlue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${delivery.pickupAddress} → ${delivery.deliveryAddress}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Action buttons based on status
            Row(
              children: [
                if (delivery.status == DeliveryStatus.driverAssigned)
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        await _realtimeService.updateDeliveryStatus(delivery.id, 'package_collected');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: SwiftDashColors.lightBlue,
                      ),
                      child: const Text('Mark as Picked Up'),
                    ),
                  ),
                if (delivery.status == DeliveryStatus.packageCollected)
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        await _realtimeService.updateDeliveryStatus(delivery.id, 'in_transit');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: SwiftDashColors.warningOrange,
                      ),
                      child: const Text('Start Delivery'),
                    ),
                  ),
                if (delivery.status == DeliveryStatus.goingToDestination || delivery.status == DeliveryStatus.atDestination)
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        await _realtimeService.updateDeliveryStatus(delivery.id, 'delivered');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: SwiftDashColors.successGreen,
                      ),
                      child: const Text('Mark as Delivered'),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}