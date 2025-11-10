import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/delivery.dart';
import '../core/supabase_config.dart';
import '../widgets/route_preview_map.dart';
import '../services/mapbox_service.dart';

class ImprovedDeliveryOfferModal extends StatefulWidget {
  final Delivery delivery;
  final Future<bool> Function() onAccept;
  final VoidCallback onDecline;

  const ImprovedDeliveryOfferModal({
    super.key,
    required this.delivery,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  State<ImprovedDeliveryOfferModal> createState() => _ImprovedDeliveryOfferModalState();
}

class _ImprovedDeliveryOfferModalState extends State<ImprovedDeliveryOfferModal>
    with TickerProviderStateMixin {
  late AnimationController _slideController;
  late AnimationController _countdownController;
  late Animation<double> _pulseAnimation;
  
  int _timeLeft = 300; // 5 minutes in seconds
  bool _isSliding = false;
  double _slideProgress = 0.0;
  final double _slideThreshold = 0.7; // 70% slide to accept
  
  RouteData? _routeData;
  bool _loadingRoute = false;
  
  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _startCountdown();
    _loadRoutePreview();
  }
  
  void _initializeAnimations() {
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _countdownController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat();
    
    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _countdownController,
      curve: Curves.easeInOut,
    ));
  }
  
  void _startCountdown() {
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _timeLeft > 0) {
        setState(() {
          _timeLeft--;
        });
        _startCountdown();
      } else if (_timeLeft <= 0) {
        widget.onDecline();
      }
    });
  }
  
  /// Load route preview data from Mapbox
  void _loadRoutePreview() async {
    if (!mounted) return;
    
    setState(() {
      _loadingRoute = true;
    });
    
    try {
      final routeData = await MapboxService.getRoute(
        widget.delivery.pickupLatitude,
        widget.delivery.pickupLongitude,
        widget.delivery.deliveryLatitude,
        widget.delivery.deliveryLongitude,
      );
      
      if (mounted) {
        setState(() {
          _routeData = routeData;
          _loadingRoute = false;
        });
      }
    } catch (e) {
      print('Error loading route preview: $e');
      if (mounted) {
        setState(() {
          _loadingRoute = false;
        });
      }
    }
  }
  
  
  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }
  
  String _formatDistance() {
    return widget.delivery.formattedDistance;
  }
  
  String _formatDuration() {
    if (_routeData != null) {
      return MapboxService.formatDuration(_routeData!.duration);
    }
    return widget.delivery.formattedDuration;
  }
  
  double _calculateTotalFare() {
    // Use total_amount if available, otherwise calculate based on distance
    if (widget.delivery.totalAmount != null && widget.delivery.totalAmount! > 0) {
      return widget.delivery.totalAmount!;
    }
    
    if (widget.delivery.totalPrice > 0) {
      return widget.delivery.totalPrice;
    }
    
    // Fallback calculation based on distance (₱50 base + ₱15/km)
    if (widget.delivery.distanceKm != null) {
      double basePrice = 50.0;
      double distancePrice = widget.delivery.distanceKm! * 15.0;
      
      // Add multi-stop surcharge if applicable
      if (widget.delivery.isMultiStop && widget.delivery.totalStops > 1) {
        double additionalStopCharge = (widget.delivery.totalStops - 1) * 20.0; // ₱20 per additional stop
        return basePrice + distancePrice + additionalStopCharge;
      }
      
      return basePrice + distancePrice;
    }
    
    return 50.0; // Minimum fare
  }
  
  // ✅ Multi-Stop Pricing Breakdown (Nov 10, 2025)
  Map<String, double> _getMultiStopPricingBreakdown() {
    if (!widget.delivery.isMultiStop) {
      return {};
    }
    
    double basePrice = 50.0;
    double distancePrice = (widget.delivery.distanceKm ?? 0) * 15.0;
    double additionalStops = (widget.delivery.totalStops - 1).toDouble();
    double additionalStopCharge = additionalStops * 20.0;
    
    return {
      'base': basePrice,
      'distance': distancePrice,
      'additionalStops': additionalStops,
      'additionalStopCharge': additionalStopCharge,
      'total': basePrice + distancePrice + additionalStopCharge,
    };
  }
  
  void _onSlideUpdate(double progress) {
    setState(() {
      _slideProgress = progress;
    });
    
    if (progress >= _slideThreshold && !_isSliding) {
      setState(() => _isSliding = true);
      HapticFeedback.mediumImpact();

      // Auto-complete slide animation and await accept result
      _slideController.forward().then((_) async {
        if (!mounted) return;
        
        setState(() {
          _loadingRoute = true; // Show loading state
        });
        
        try {
          print('🎯 Starting delivery acceptance...');
          final accepted = await widget.onAccept();
          
          if (!mounted) return;
          
          if (accepted) {
            print('✅ Delivery accepted - modal will close');
            // Success: The parent callback should handle modal closing and navigation
            // Add a small delay to ensure the UI updates properly
            await Future.delayed(const Duration(milliseconds: 100));
          } else {
            print('❌ Delivery acceptance failed - resetting slider');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Delivery was already taken by another driver.'),
                  backgroundColor: SwiftDashColors.warningOrange,
                ),
              );
              setState(() {
                _slideProgress = 0.0;
                _isSliding = false;
              });
              _slideController.reverse();
            }
          }
        } catch (e) {
          print('❌ Error during accept flow: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to accept delivery: $e')),
            );
            setState(() {
              _slideProgress = 0.0;
              _isSliding = false;
            });
            _slideController.reverse();
          }
        } finally {
          if (mounted) {
            setState(() => _loadingRoute = false);
          }
        }
      });
    } else if (progress < _slideThreshold && _isSliding) {
      setState(() => _isSliding = false);
    }
  }
  
  @override
  void dispose() {
    _slideController.dispose();
    _countdownController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isUrgent = _timeLeft < 60;
    
    return Material(
      type: MaterialType.transparency,
      child: Container(
        color: Colors.black87, // ✅ FIX: Fully opaque to block parent screen content
        child: SafeArea(
          child: Column(
          children: [
            // Top status bar with timer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: isUrgent ? SwiftDashColors.dangerRed : SwiftDashColors.darkBlue,
              child: Row(
                children: [
                  AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: isUrgent ? _pulseAnimation.value : 1.0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: SwiftDashColors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.timer,
                                size: 16,
                                color: isUrgent 
                                  ? SwiftDashColors.dangerRed 
                                  : SwiftDashColors.darkBlue,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _formatTime(_timeLeft),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isUrgent 
                                    ? SwiftDashColors.dangerRed 
                                    : SwiftDashColors.darkBlue,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const Spacer(),
                  Text(
                    'New Delivery Request',
                    style: const TextStyle(
                      color: SwiftDashColors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: widget.onDecline,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Colors.white24,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        color: SwiftDashColors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // ✅ Business Dispatch Badge (Nov 9, 2025)
            if (widget.delivery.isBusinessDelivery) 
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue[700]!, Colors.blue[500]!],
                  ),
                  border: Border(
                    bottom: BorderSide(color: Colors.blue[800]!, width: 2),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.business, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Business Dispatch Assignment',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            
            // ✅ Multi-Stop Indicator Badge (Nov 10, 2025)
            if (widget.delivery.isMultiStop) 
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.orange[700]!, Colors.orange[500]!],
                  ),
                  border: Border(
                    bottom: BorderSide(color: Colors.orange[800]!, width: 2),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.route, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Multi-Stop Delivery (${widget.delivery.totalStops} stops)',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            
            // Main content area
            Expanded(
              child: Container(
                color: SwiftDashColors.white,
                child: Column(
                  children: [
                    // Distance and earnings header
                    Container(
                      padding: const EdgeInsets.all(20),
                      color: SwiftDashColors.backgroundGrey,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: SwiftDashColors.lightBlue,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.navigation,
                                  color: SwiftDashColors.white,
                                  size: 16,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _formatDistance(),
                                  style: const TextStyle(
                                    color: SwiftDashColors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          if (_routeData != null) ...[
                            Text(
                              '• ${_formatDuration()}',
                              style: TextStyle(
                                color: SwiftDashColors.textGrey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                          const Spacer(),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '₱${_calculateTotalFare().toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: SwiftDashColors.darkBlue,
                                ),
                              ),
                              Text(
                                'Total Fare',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: SwiftDashColors.textGrey,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'You earn: ₱${(_calculateTotalFare() * 0.84).toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: SwiftDashColors.successGreen,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    
                    // ✅ Multi-Stop Pricing Breakdown (Nov 10, 2025)
                    if (widget.delivery.isMultiStop)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.orange.withOpacity(0.3),
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.receipt_outlined,
                                  color: Colors.orange,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Multi-Stop Pricing',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: SwiftDashColors.darkBlue,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Builder(builder: (context) {
                              final breakdown = _getMultiStopPricingBreakdown();
                              if (breakdown.isEmpty) return const SizedBox();
                              
                              return Column(
                                children: [
                                  _buildPricingRow('Base fare', breakdown['base']!),
                                  _buildPricingRow('Distance (${_formatDistance()})', breakdown['distance']!),
                                  _buildPricingRow('${breakdown['additionalStops']!.toInt()} extra stops', breakdown['additionalStopCharge']!),
                                  const Divider(height: 16),
                                  _buildPricingRow('Total', breakdown['total']!, isTotal: true),
                                ],
                              );
                            }),
                          ],
                        ),
                      ),
                    
                    // Route preview map with route polygon
                    if (!_loadingRoute)
                      SizedBox(
                        height: screenHeight * 0.25,
                        child: RoutePreviewMap(
                          pickupLat: widget.delivery.pickupLatitude,
                          pickupLng: widget.delivery.pickupLongitude,
                          deliveryLat: widget.delivery.deliveryLatitude,
                          deliveryLng: widget.delivery.deliveryLongitude,
                          routeData: _routeData, // Pass route data for polygon
                        ),
                      )
                    else
                      Container(
                        height: screenHeight * 0.25,
                        color: SwiftDashColors.backgroundGrey,
                        child: const Center(
                          child: CircularProgressIndicator(),
                        ),
                      ),
                    
                    // Order details
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Pickup location
                            _buildLocationCard(
                              icon: Icons.radio_button_checked,
                              iconColor: SwiftDashColors.successGreen,
                              title: 'Pickup',
                              address: widget.delivery.pickupAddress,
                              contact: widget.delivery.pickupContactName,
                              phone: widget.delivery.pickupContactPhone,
                            ),
                            
                            const SizedBox(height: 16),
                            
                            // Delivery location(s)
                            if (widget.delivery.isMultiStop)
                              _buildLocationCard(
                                icon: Icons.route,
                                iconColor: Colors.orange,
                                title: 'Multiple Destinations',
                                address: '${widget.delivery.totalStops - 1} delivery stops',
                                contact: 'Various recipients',
                                phone: '',
                                isMultiStop: true,
                              )
                            else
                              _buildLocationCard(
                                icon: Icons.location_on,
                                iconColor: SwiftDashColors.dangerRed,
                                title: 'Delivery',
                                address: widget.delivery.deliveryAddress,
                                contact: widget.delivery.deliveryContactName,
                                phone: widget.delivery.deliveryContactPhone,
                              ),
                            
                            const SizedBox(height: 20),
                            
                            // Package details
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: SwiftDashColors.backgroundGrey,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.inventory_2_outlined,
                                        color: SwiftDashColors.darkBlue,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Package Details',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: SwiftDashColors.darkBlue,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    widget.delivery.packageDescription,
                                    style: TextStyle(
                                      color: SwiftDashColors.textGrey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            
                            // ✅ Multi-Stop Route Information (Nov 10, 2025)
                            if (widget.delivery.isMultiStop)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.orange.withOpacity(0.3),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.route,
                                            color: Colors.orange,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Multi-Stop Route',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: SwiftDashColors.darkBlue,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      // Route overview
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.radio_button_checked,
                                            color: SwiftDashColors.successGreen,
                                            size: 16,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '1. Pickup: ${widget.delivery.pickupAddress.length > 40 ? widget.delivery.pickupAddress.substring(0, 40) + '...' : widget.delivery.pickupAddress}',
                                            style: TextStyle(
                                              color: SwiftDashColors.textGrey,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.location_on,
                                            color: Colors.orange,
                                            size: 16,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '2-${widget.delivery.totalStops}. ${widget.delivery.totalStops - 1} delivery stops',
                                            style: TextStyle(
                                              color: SwiftDashColors.textGrey,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      // Route optimization notice
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.auto_awesome,
                                              color: Colors.orange,
                                              size: 16,
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                'Route will be optimized for efficiency',
                                                style: TextStyle(
                                                  color: Colors.orange[700],
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            
                            // Sender notes (pickup instructions)
                            if (widget.delivery.pickupInstructions != null && 
                                widget.delivery.pickupInstructions!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: SwiftDashColors.lightBlue.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: SwiftDashColors.lightBlue.withOpacity(0.3),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.notes_outlined,
                                            color: SwiftDashColors.lightBlue,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Sender Notes',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: SwiftDashColors.darkBlue,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        widget.delivery.pickupInstructions!,
                                        style: TextStyle(
                                          color: SwiftDashColors.textGrey,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            
                            // Delivery instructions (if any)
                            if (widget.delivery.deliveryInstructions != null && 
                                widget.delivery.deliveryInstructions!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: SwiftDashColors.dangerRed.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: SwiftDashColors.dangerRed.withOpacity(0.3),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.info_outline,
                                            color: SwiftDashColors.dangerRed,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Delivery Instructions',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: SwiftDashColors.darkBlue,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        widget.delivery.deliveryInstructions!,
                                        style: TextStyle(
                                          color: SwiftDashColors.textGrey,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            
                            const SizedBox(height: 20),
                            
                            // Order info
                            Row(
                              children: [
                                Expanded(
                                  child: _buildInfoCard(
                                    'Order ID',
                                    '#${widget.delivery.id.substring(0, 8).toUpperCase()}',
                                    Icons.receipt_outlined,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildInfoCard(
                                    'Payment',
                                    'Cash on Delivery',
                                    Icons.payments_outlined,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // Slide to accept button
            Container(
              padding: const EdgeInsets.all(20),
              color: SwiftDashColors.white,
              child: _buildSlideToAcceptButton(),
            ),
          ],
        ),
      ),
      ), // Container wrapper
    );
  }
  
  Widget _buildLocationCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String address,
    required String contact,
    required String phone,
    bool isMultiStop = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: SwiftDashColors.backgroundGrey),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: SwiftDashColors.textGrey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  address,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: SwiftDashColors.darkBlue,
                  ),
                ),
                const SizedBox(height: 8),
                // Show contact info for single deliveries, route info for multi-stop
                if (isMultiStop)
                  Row(
                    children: [
                      Icon(
                        Icons.alt_route,
                        size: 16,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Optimized route order',
                        style: TextStyle(
                          color: Colors.orange,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      Icon(
                        Icons.person_outline,
                        size: 16,
                        color: SwiftDashColors.textGrey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        contact,
                        style: TextStyle(
                          color: SwiftDashColors.textGrey,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        Icons.phone_outlined,
                        size: 16,
                        color: SwiftDashColors.textGrey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        phone,
                        style: TextStyle(
                          color: SwiftDashColors.textGrey,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildInfoCard(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SwiftDashColors.backgroundGrey,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: SwiftDashColors.lightBlue,
              ),
              const SizedBox(width: 4),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: SwiftDashColors.textGrey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: SwiftDashColors.darkBlue,
            ),
          ),
        ],
      ),
    );
  }
  
  // ✅ Pricing Row Helper for Multi-Stop Breakdown (Nov 10, 2025)
  Widget _buildPricingRow(String label, double amount, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 14 : 13,
              fontWeight: isTotal ? FontWeight.w600 : FontWeight.normal,
              color: isTotal ? SwiftDashColors.darkBlue : SwiftDashColors.textGrey,
            ),
          ),
          Text(
            '₱${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: isTotal ? 14 : 13,
              fontWeight: isTotal ? FontWeight.w600 : FontWeight.w500,
              color: isTotal ? SwiftDashColors.darkBlue : SwiftDashColors.textGrey,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSlideToAcceptButton() {
    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        if (!_isSliding) {
          final buttonWidth = MediaQuery.of(context).size.width - 40;
          final progress = (details.localPosition.dx / buttonWidth).clamp(0.0, 1.0);
          _onSlideUpdate(progress);
        }
      },
      onHorizontalDragEnd: (details) {
        if (_slideProgress < _slideThreshold) {
          setState(() {
            _slideProgress = 0.0;
            _isSliding = false;
          });
          _slideController.reverse();
        }
      },
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              SwiftDashColors.successGreen,
              SwiftDashColors.successGreen.withOpacity(0.8),
            ],
          ),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Stack(
          children: [
            // Background text
            Center(
              child: Text(
                _slideProgress > 0.5 ? 'Release to Accept Order' : 'Slide to Accept Order',
                style: const TextStyle(
                  color: SwiftDashColors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ),
            
            // Sliding circle
            Positioned(
              left: 4 + (_slideProgress * (MediaQuery.of(context).size.width - 88)),
              top: 4,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: SwiftDashColors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  _slideProgress > 0.5 ? Icons.check : Icons.arrow_forward_ios,
                  color: SwiftDashColors.successGreen,
                  size: 24,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}