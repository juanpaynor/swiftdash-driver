import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';
import 'dart:async';
import '../models/delivery.dart';
import '../services/mapbox_service.dart';
import '../widgets/route_preview_map.dart';
import '../core/supabase_config.dart';

class DeliveryOfferModal extends StatefulWidget {
  final Delivery delivery;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final int timeoutSeconds;

  const DeliveryOfferModal({
    super.key,
    required this.delivery,
    required this.onAccept,
    required this.onDecline,
    this.timeoutSeconds = 300, // 5 minutes default
  });

  @override
  State<DeliveryOfferModal> createState() => _DeliveryOfferModalState();
}

class _DeliveryOfferModalState extends State<DeliveryOfferModal>
    with TickerProviderStateMixin {
  Timer? _countdownTimer;
  int _remainingSeconds = 0;
  late AnimationController _pulseController;
  late AnimationController _slideController;
  RouteData? _routeData;
  bool _isAccepting = false;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.timeoutSeconds;
    
    // Initialize animations
    _pulseController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat(reverse: true);
    
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    // Start countdown
    _startCountdown();
    
    // Trigger vibration and animations
    _triggerAlerts();
    
    // Load route data
    _loadRouteData();
    
    // Animate in
    _slideController.forward();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pulseController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds <= 0) {
        timer.cancel();
        _autoDecline();
      } else {
        setState(() {
          _remainingSeconds--;
        });
        
        // Vibrate every 30 seconds and in final 10 seconds
        if (_remainingSeconds % 30 == 0 || _remainingSeconds <= 10) {
          _triggerVibration();
        }
      }
    });
  }

  void _triggerAlerts() async {
    // Initial vibration pattern
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(pattern: [0, 500, 200, 500, 200, 500]);
    }
  }

  void _triggerVibration() async {
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: 200);
    }
  }

  void _loadRouteData() async {
    final routeData = await MapboxService.getRoute(
      widget.delivery.pickupLatitude,
      widget.delivery.pickupLongitude,
      widget.delivery.deliveryLatitude,
      widget.delivery.deliveryLongitude,
    );
    
    if (mounted) {
      setState(() {
        _routeData = routeData;
      });
    }
  }

  void _autoDecline() {
    if (mounted) {
      _slideController.reverse().then((_) {
        widget.onDecline();
      });
    }
  }

  void _handleAccept() async {
    if (_isAccepting) return;
    
    setState(() {
      _isAccepting = true;
    });
    
    _countdownTimer?.cancel();
    await _slideController.reverse();
    widget.onAccept();
  }

  void _handleDecline() async {
    _countdownTimer?.cancel();
    await _slideController.reverse();
    widget.onDecline();
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Color _getTimerColor() {
    if (_remainingSeconds <= 30) return SwiftDashColors.dangerRed;
    if (_remainingSeconds <= 60) return SwiftDashColors.warningOrange;
    return SwiftDashColors.successGreen;
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _slideController,
        curve: Curves.easeInOut,
      )),
      child: Material(
        color: Colors.black.withOpacity(0.8),
        child: SafeArea(
          child: Container(
            width: double.infinity,
            height: double.infinity,
            padding: EdgeInsets.all(screenWidth < 360 ? 16 : 20),
            child: Column(
              children: [
                // Header with timer
                _buildHeader(),
                
                const SizedBox(height: 20),
                
                // Main content card
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: SwiftDashColors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Column(
                        children: [
                          // Earnings header
                          _buildEarningsHeader(),
                          
                          // Route preview
                          Expanded(
                            flex: 3,
                            child: _buildRoutePreview(),
                          ),
                          
                          // Delivery details
                          Expanded(
                            flex: 2,
                            child: _buildDeliveryDetails(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // Action buttons
                _buildActionButtons(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(
          Icons.local_shipping,
          color: SwiftDashColors.white,
          size: 28,
        ),
        const SizedBox(width: 12),
        Text(
          'New Delivery Offer',
          style: TextStyle(
            color: SwiftDashColors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: _getTimerColor().withOpacity(0.9),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: _getTimerColor().withOpacity(0.5 + (_pulseController.value * 0.3)),
                    blurRadius: 8 + (_pulseController.value * 4),
                    spreadRadius: 1 + (_pulseController.value * 2),
                  ),
                ],
              ),
              child: Text(
                _formatTime(_remainingSeconds),
                style: const TextStyle(
                  color: SwiftDashColors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildEarningsHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [SwiftDashColors.successGreen, SwiftDashColors.successGreen.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          Text(
            'Estimated Earnings',
            style: TextStyle(
              color: SwiftDashColors.white.withOpacity(0.9),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '₱${widget.delivery.totalPrice.toStringAsFixed(2)}',
            style: const TextStyle(
              color: SwiftDashColors.white,
              fontSize: 36,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (_routeData != null) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.route, size: 16, color: SwiftDashColors.white.withOpacity(0.9)),
                const SizedBox(width: 4),
                Text(
                  '${MapboxService.formatDistance(_routeData!.distance)} • ${MapboxService.formatDuration(_routeData!.duration)}',
                  style: TextStyle(
                    color: SwiftDashColors.white.withOpacity(0.9),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRoutePreview() {
    return Container(
      margin: const EdgeInsets.all(16),
      child: _routeData != null
          ? RoutePreviewMap(
              pickupLat: widget.delivery.pickupLatitude,
              pickupLng: widget.delivery.pickupLongitude,
              deliveryLat: widget.delivery.deliveryLatitude,
              deliveryLng: widget.delivery.deliveryLongitude,
              routeData: _routeData,
            )
          : Container(
              decoration: BoxDecoration(
                color: SwiftDashColors.backgroundGrey,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text(
                      'Loading route preview...',
                      style: TextStyle(
                        color: SwiftDashColors.textGrey,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildDeliveryDetails() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pickup location
          _buildLocationItem(
            Icons.circle,
            SwiftDashColors.successGreen,
            'Pickup',
            widget.delivery.pickupAddress,
            widget.delivery.pickupContactName,
          ),
          
          const SizedBox(height: 16),
          
          // Delivery location
          _buildLocationItem(
            Icons.location_on,
            SwiftDashColors.dangerRed,
            'Delivery',
            widget.delivery.deliveryAddress,
            widget.delivery.deliveryContactName,
          ),
          
          const SizedBox(height: 16),
          
          // Package info
          if (widget.delivery.packageDescription.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: SwiftDashColors.backgroundGrey,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.inventory_2, size: 20, color: SwiftDashColors.darkBlue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.delivery.packageDescription,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLocationItem(IconData icon, Color color, String label, String address, String contact) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 14,
            color: SwiftDashColors.white,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: color,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                address,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                contact,
                style: TextStyle(
                  fontSize: 12,
                  color: SwiftDashColors.textGrey,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        // Decline button
        Expanded(
          child: Container(
            height: 60,
            margin: const EdgeInsets.only(right: 8),
            child: ElevatedButton(
              onPressed: _handleDecline,
              style: ElevatedButton.styleFrom(
                backgroundColor: SwiftDashColors.white,
                side: BorderSide(color: SwiftDashColors.dangerRed, width: 2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                elevation: 4,
              ),
              child: Text(
                'Decline',
                style: TextStyle(
                  color: SwiftDashColors.dangerRed,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
        
        // Accept button
        Expanded(
          flex: 2,
          child: Container(
            height: 60,
            margin: const EdgeInsets.only(left: 8),
            child: ElevatedButton(
              onPressed: _isAccepting ? null : _handleAccept,
              style: ElevatedButton.styleFrom(
                backgroundColor: SwiftDashColors.successGreen,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                elevation: 8,
                shadowColor: SwiftDashColors.successGreen.withOpacity(0.5),
              ),
              child: _isAccepting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: SwiftDashColors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'Accept Delivery',
                      style: TextStyle(
                        color: SwiftDashColors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}