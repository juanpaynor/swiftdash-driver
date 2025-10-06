import 'package:flutter/material.dart';
import '../models/delivery.dart';
import '../services/driver_flow_service.dart';
import '../core/supabase_config.dart';

class OfferModal extends StatefulWidget {
  final Delivery delivery;
  final DriverFlowService driverFlowService;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const OfferModal({
    super.key,
    required this.delivery,
    required this.driverFlowService,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  State<OfferModal> createState() => _OfferModalState();
}

class _OfferModalState extends State<OfferModal>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  int _countdown = 30; // 30 seconds to accept
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    
    _scaleAnimation = Tween<double>(
      begin: 0.7,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    ));
    
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    ));

    _animationController.forward();
    _startCountdown();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _startCountdown() {
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _countdown > 0) {
        setState(() {
          _countdown--;
        });
        if (_countdown > 0) {
          _startCountdown();
        } else {
          _autoDecline();
        }
      }
    });
  }

  void _autoDecline() {
    if (!_isProcessing) {
      widget.onDecline();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: SwiftDashColors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header with countdown
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            SwiftDashColors.lightBlue,
                            SwiftDashColors.darkBlue,
                          ],
                        ),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(20),
                          topRight: Radius.circular(20),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'New Delivery Offer',
                                  style: TextStyle(
                                    color: SwiftDashColors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'Tap to accept in $_countdown seconds',
                                  style: TextStyle(
                                    color: SwiftDashColors.white.withOpacity(0.8),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: SwiftDashColors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Stack(
                              children: [
                                Center(
                                  child: Text(
                                    '$_countdown',
                                    style: const TextStyle(
                                      color: SwiftDashColors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                CircularProgressIndicator(
                                  value: _countdown / 30,
                                  strokeWidth: 3,
                                  backgroundColor: SwiftDashColors.white.withOpacity(0.3),
                                  valueColor: const AlwaysStoppedAnimation<Color>(
                                    SwiftDashColors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // Delivery details
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          // Payment and distance
                          Row(
                            children: [
                              Expanded(
                                child: _buildInfoCard(
                                  'Payment',
                                  '\$${widget.delivery.totalPrice.toStringAsFixed(2)}',
                                  Icons.attach_money,
                                  Colors.green,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildInfoCard(
                                  'Distance',
                                  '${widget.delivery.distanceKm?.toStringAsFixed(1) ?? 'N/A'} km',
                                  Icons.route,
                                  SwiftDashColors.lightBlue,
                                ),
                              ),
                            ],
                          ),
                          
                          const SizedBox(height: 16),
                          
                          // Pickup location
                          _buildLocationCard(
                            'Pickup',
                            widget.delivery.pickupAddress,
                            Icons.store,
                            Colors.orange,
                          ),
                          
                          const SizedBox(height: 12),
                          
                          // Delivery location
                          _buildLocationCard(
                            'Delivery',
                            widget.delivery.deliveryAddress,
                            Icons.home,
                            Colors.blue,
                          ),
                          
                          const SizedBox(height: 16),
                          
                          // Delivery notes if any
                          if (widget.delivery.deliveryNotes?.isNotEmpty == true) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Special Instructions:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: SwiftDashColors.darkBlue,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.delivery.deliveryNotes!,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          
                          // Action buttons
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _isProcessing ? null : () {
                                    setState(() {
                                      _isProcessing = true;
                                    });
                                    widget.onDecline();
                                  },
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    side: const BorderSide(color: Colors.red),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text(
                                    'Decline',
                                    style: TextStyle(
                                      color: Colors.red,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 2,
                                child: ElevatedButton(
                                  onPressed: _isProcessing ? null : () async {
                                    setState(() {
                                      _isProcessing = true;
                                    });
                                    
                                    final success = await widget.driverFlowService
                                        .acceptDeliveryOffer(context, widget.delivery);
                                    
                                    if (success) {
                                      widget.onAccept();
                                    } else {
                                      setState(() {
                                        _isProcessing = false;
                                      });
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: SwiftDashColors.lightBlue,
                                    foregroundColor: SwiftDashColors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: _isProcessing
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation<Color>(
                                              SwiftDashColors.white,
                                            ),
                                          ),
                                        )
                                      : const Text(
                                          'Accept',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildInfoCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
              fontSize: 16,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildLocationCard(String label, String address, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  address,
                  style: const TextStyle(
                    fontSize: 14,
                    color: SwiftDashColors.darkBlue,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}