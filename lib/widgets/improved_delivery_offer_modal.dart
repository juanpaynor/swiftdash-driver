import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/delivery.dart';
import '../core/supabase_config.dart';
import '../widgets/route_preview_map.dart';

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
  
  Map<String, dynamic>? _routeData;
  bool _loadingRoute = false;
  
  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _startCountdown();
    // Comment out route loading for now to avoid errors
    // _loadRoutePreview();
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
  
  
  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }
  
  String _formatDistance() {
    return widget.delivery.formattedDistance;
  }
  
  String _formatDuration() {
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
      return 50.0 + (widget.delivery.distanceKm! * 15.0);
    }
    
    return 50.0; // Minimum fare
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
        setState(() {});
        // show accepting state
        try {
          // indicate accepting
          setState(() => _loadingRoute = true); // reuse loading flag as a lightweight 'busy' indicator
          final accepted = await widget.onAccept();
          if (accepted) {
            // success: modal can close itself by calling onAccept provider (which should return true)
            // parent callback is expected to handle navigation and tracking
            // we simply leave — parent will close the dialog if needed
          } else {
            // failed to accept (taken by another driver) — reset slider
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Delivery was already taken by another driver.'), backgroundColor: SwiftDashColors.warningOrange),
            );
            setState(() {
              _slideProgress = 0.0;
              _isSliding = false;
            });
            _slideController.reverse();
          }
        } catch (e) {
          print('Error during accept flow: $e');
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to accept delivery: $e')));
          setState(() {
            _slideProgress = 0.0;
            _isSliding = false;
          });
          _slideController.reverse();
        } finally {
          setState(() => _loadingRoute = false);
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
      color: Colors.black54,
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
                                'You earn: ₱${(_calculateTotalFare() * 0.8).toStringAsFixed(2)}',
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
                    
                    // Route preview map (simplified)
                    if (!_loadingRoute)
                      SizedBox(
                        height: screenHeight * 0.25,
                        child: RoutePreviewMap(
                          pickupLat: widget.delivery.pickupLatitude,
                          pickupLng: widget.delivery.pickupLongitude,
                          deliveryLat: widget.delivery.deliveryLatitude,
                          deliveryLng: widget.delivery.deliveryLongitude,
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
                            
                            // Delivery location
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
    );
  }
  
  Widget _buildLocationCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String address,
    required String contact,
    required String phone,
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