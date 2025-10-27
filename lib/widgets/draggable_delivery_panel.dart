import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:confetti/confetti.dart';
import 'dart:math' as math;
import '../models/delivery.dart';
import '../models/delivery_stop.dart';
import '../core/supabase_config.dart';
import '../services/delivery_stage_manager.dart';
import '../services/mapbox_service.dart';
import '../services/driver_location_service.dart';
import '../services/multi_stop_service.dart';
import '../widgets/pickup_confirmation_dialog.dart';
import '../widgets/proof_of_delivery_dialog.dart';
import '../widgets/multi_stop_widgets.dart';

/// Panel display mode
enum PanelMode {
  offerPreview,    // Showing delivery offer before acceptance
  activeDelivery,  // Showing active delivery in progress
}

/// Haptic feedback types
enum HapticFeedbackType {
  light,
  medium,
  heavy,
  selection,
}

/// DoorDash-style draggable delivery panel
/// Shows delivery info in a draggable bottom sheet when delivery is active
/// OR shows offer preview with Accept/Decline buttons when offer arrives
class DraggableDeliveryPanel extends StatefulWidget {
  final Delivery delivery;
  final RouteData? routeData;
  final PanelMode mode;
  
  // Active delivery callbacks
  final VoidCallback? onCallCustomer;
  final VoidCallback? onNavigate;
  final Function(DeliveryStage)? onStatusChange;
  
  // Offer preview callbacks
  final Future<bool> Function()? onAcceptOffer;
  final Future<bool> Function()? onDeclineOffer;
  
  const DraggableDeliveryPanel({
    super.key,
    required this.delivery,
    this.routeData,
    this.mode = PanelMode.activeDelivery,
    this.onCallCustomer,
    this.onNavigate,
    this.onStatusChange,
    this.onAcceptOffer,
    this.onDeclineOffer,
  });

  @override
  State<DraggableDeliveryPanel> createState() => _DraggableDeliveryPanelState();
}

class _DraggableDeliveryPanelState extends State<DraggableDeliveryPanel> with TickerProviderStateMixin {
  final DraggableScrollableController _controller = DraggableScrollableController();
  
  // Get Supabase client instance
  final supabase = Supabase.instance.client;
  
  // 🎊 PHASE 3: Confetti controller for celebration
  late ConfettiController _confettiController;
  
  // 💰 PHASE 3: Animated earnings counter
  late AnimationController _earningsAnimationController;
  late Animation<double> _earningsAnimation;
  double _displayedEarnings = 0.0;
  
  // 🚦 MULTI-STOP: Delivery stops management
  final MultiStopService _multiStopService = MultiStopService();
  List<DeliveryStop>? _stops;
  bool _isLoadingStops = false;
  
  @override
  void initState() {
    super.initState();
    
    // � PHASE 3: Initialize confetti controller
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));
    
    // 💰 PHASE 3: Initialize earnings animation controller
    _earningsAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    
    // Start animating earnings on offer arrival
    _displayedEarnings = 0.0;
    final targetEarnings = widget.delivery.driverEarnings;
    _earningsAnimation = Tween<double>(
      begin: 0.0,
      end: targetEarnings,
    ).animate(CurvedAnimation(
      parent: _earningsAnimationController,
      curve: Curves.easeOutCubic,
    ))..addListener(() {
      setState(() {
        _displayedEarnings = _earningsAnimation.value;
      });
    });
    
    // �🎯 SMART AUTO-EXPANSION: Auto-expand on offer arrival
    if (widget.mode == PanelMode.offerPreview) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _triggerHapticFeedback();
        // Auto-expand to 50% on offer arrival
        if (_controller.isAttached) {
          _controller.animateTo(
            0.50,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
          );
        }
        // 💰 Start earnings count-up animation
        _earningsAnimationController.forward();
      });
    } else {
      // Active delivery mode - show full earnings immediately
      _displayedEarnings = targetEarnings;
    }
    
    // 🚦 MULTI-STOP: Load stops if this is a multi-stop delivery
    if (widget.delivery.isMultiStop) {
      _loadStops();
    }
  }
  
  @override
  void didUpdateWidget(DraggableDeliveryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 🎯 SMART AUTO-EXPANSION: Status changes trigger expansion
    if (widget.mode == PanelMode.activeDelivery) {
      // Expand when status changes to show new action
      if (oldWidget.delivery.status != widget.delivery.status) {
        _triggerHapticFeedback();
        _autoExpandOnStatusChange();
      }
    }
  }
  
  /// Auto-expand panel on important status changes
  void _autoExpandOnStatusChange() {
    if (!_controller.isAttached) return;
    
    final currentSize = _controller.size;
    
    // If panel is collapsed (< 0.30), expand to medium size
    if (currentSize < 0.30) {
      _controller.animateTo(
        0.35,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }
  
  /// Trigger haptic feedback for important interactions
  void _triggerHapticFeedback({HapticFeedbackType type = HapticFeedbackType.light}) {
    switch (type) {
      case HapticFeedbackType.light:
        HapticFeedback.lightImpact();
        break;
      case HapticFeedbackType.medium:
        HapticFeedback.mediumImpact();
        break;
      case HapticFeedbackType.heavy:
        HapticFeedback.heavyImpact();
        break;
      case HapticFeedbackType.selection:
        HapticFeedback.selectionClick();
        break;
    }
  }
  
  /// Load delivery stops for multi-stop deliveries
  Future<void> _loadStops() async {
    if (!widget.delivery.isMultiStop) return;
    
    setState(() {
      _isLoadingStops = true;
    });
    
    try {
      final stops = await _multiStopService.getStops(widget.delivery.id);
      setState(() {
        _stops = stops;
        _isLoadingStops = false;
      });
    } catch (e) {
      print('Error loading stops: $e');
      setState(() {
        _isLoadingStops = false;
      });
    }
  }
  
  /// Progress to next stop and update delivery status
  Future<void> _progressToNextStop() async {
    if (!widget.delivery.isMultiStop || _stops == null || _stops!.isEmpty) return;
    
    try {
      // Check if all stops are completed
      final allStopsCompleted = _multiStopService.areAllStopsCompleted(_stops!);
      
      if (allStopsCompleted) {
        print('🎉 All stops completed! Marking delivery as completed.');
        
        // Update delivery status to 'completed'
        await supabase
            .from('deliveries')
            .update({
              'status': 'completed',
              'completed_at': DateTime.now().toIso8601String(),
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', widget.delivery.id);
        
        print('✅ Multi-stop delivery marked as completed');
        
        // Trigger status change callback if provided
        if (widget.onStatusChange != null) {
          widget.onStatusChange!(DeliveryStage.deliveryComplete);
        }
      } else {
        // Get next pending stop
        final currentStop = _multiStopService.getCurrentStop(_stops!);
        
        if (currentStop != null) {
          // Update delivery's current_stop_index
          final newIndex = currentStop.stopNumber - 1; // stopNumber is 1-based, index is 0-based
          
          await supabase
              .from('deliveries')
              .update({
                'current_stop_index': newIndex,
                'updated_at': DateTime.now().toIso8601String(),
              })
              .eq('id', widget.delivery.id);
          
          print('✅ Advanced to stop ${currentStop.stopNumber} (index $newIndex)');
        }
      }
    } catch (e) {
      print('❌ Error progressing to next stop: $e');
    }
  }
  
  @override
  void dispose() {
    _controller.dispose();
    _confettiController.dispose();
    _earningsAnimationController.dispose();
    super.dispose();
  }
  
  // Track last position to detect snaps
  double _lastSnapPosition = 0.35;
  
  @override
  Widget build(BuildContext context) {
    final mode = widget.mode;
    
    return Stack(
      children: [
        NotificationListener<DraggableScrollableNotification>(
      onNotification: (notification) {
        // Trigger haptic when approaching a snap position
        final currentSize = notification.extent;
        final snapSizes = mode == PanelMode.offerPreview 
            ? [0.50, 0.70]
            : [0.20, 0.35, 0.70];
        
        // Check if we're close to a snap position
        for (final snapSize in snapSizes) {
          if ((currentSize - snapSize).abs() < 0.02 && 
              (_lastSnapPosition - snapSize).abs() > 0.02) {
            _triggerHapticFeedback(type: HapticFeedbackType.selection);
            _lastSnapPosition = currentSize;
            break;
          }
        }
        
        return false;
      },
      child: DraggableScrollableSheet(
        controller: _controller,
        initialChildSize: mode == PanelMode.offerPreview ? 0.50 : 0.35,
        minChildSize: 0.20,
        maxChildSize: 0.70,
        snap: true,
        snapSizes: mode == PanelMode.offerPreview 
            ? const [0.50, 0.70]  // Offer mode: start expanded
            : const [0.20, 0.35, 0.70],  // Active mode: normal behavior
        builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(24),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.zero,
            children: [
              // Drag handle
              _buildDragHandle(),
              
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: mode == PanelMode.offerPreview
                    ? _buildOfferPreviewContent()
                    : _buildActiveDeliveryContent(),
              ),
            ],
          ),
        );
      },
      ),
        ),
        
        // 🎊 PHASE 3: Confetti overlay for celebration
        Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: _confettiController,
            blastDirection: math.pi / 2, // Down
            emissionFrequency: 0.05,
            numberOfParticles: 30,
            gravity: 0.3,
            shouldLoop: false,
            colors: const [
              Color(0xFF1DA1F2), // SwiftDash light blue
              Color(0xFF2E4A9B), // SwiftDash dark blue
              Colors.white,
              Colors.yellow,
              Colors.orange,
            ],
          ),
        ),
      ],
    );
  }
  
  Widget _buildDragHandle() {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        width: 48,
        height: 5,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
  
  /// Build offer preview content with Accept/Decline buttons
  Widget _buildOfferPreviewContent() {
    final delivery = widget.delivery;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 💰 HERO SECTION: Earnings Front and Center
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                SwiftDashColors.lightBlue,
                SwiftDashColors.darkBlue,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: SwiftDashColors.lightBlue.withOpacity(0.3),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              const Text(
                'DELIVERY EARNINGS',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              // 💰 PHASE 3: Animated earnings counter
              Text(
                '₱${_displayedEarnings.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  height: 1.0,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 16),
              
              // Quick stats in one line
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildQuickStat(
                    Icons.straighten,
                    widget.routeData?.distance != null
                        ? '${widget.routeData!.distance.toStringAsFixed(1)} km'
                        : '--',
                  ),
                  Container(
                    width: 1,
                    height: 20,
                    color: Colors.white30,
                  ),
                  _buildQuickStat(
                    Icons.schedule,
                    widget.routeData?.duration != null
                        ? '${widget.routeData!.duration} min'
                        : '--',
                  ),
                  if (delivery.isMultiStop) ...[
                    Container(
                      width: 1,
                      height: 20,
                      color: Colors.white30,
                    ),
                    _buildQuickStat(
                      Icons.multiple_stop,
                      '${delivery.totalStops} stops',
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 20),
        
        // 📍 TIMELINE: Visual Route
        _buildRouteTimeline(delivery),
        
        const SizedBox(height: 24),
        
        // 🎯 SWIPE TO ACCEPT - Big, satisfying gesture
        _buildSwipeToAcceptButton(),
        
        const SizedBox(height: 16),
        
        // Simple decline text button
        TextButton(
          onPressed: _isProcessingOffer ? null : () {
            _triggerHapticFeedback(type: HapticFeedbackType.light);
            _handleDeclineOffer();
          },
          style: TextButton.styleFrom(
            foregroundColor: SwiftDashColors.textGrey,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: _isProcessingOffer
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
                  ),
                )
              : const Text(
                  'Decline Offer',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
        ),
        
        const SizedBox(height: 16),
      ],
    );
  }
  
  /// Build quick stat widget for hero section
  Widget _buildQuickStat(IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white70, size: 16),
        const SizedBox(width: 6),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
  
  /// Build visual route timeline - ENHANCED PHASE 2
  Widget _buildRouteTimeline(Delivery delivery) {
    // 🚦 MULTI-STOP: Show stop list instead of simple timeline
    if (delivery.isMultiStop && _stops != null && _stops!.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Multi-stop badge
          Row(
            children: [
              MultiStopBadge(totalStops: delivery.totalStops),
              const Spacer(),
              if (_isLoadingStops)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Progress indicator
          StopProgressIndicator(stops: _stops!, showPercentage: true),
          const SizedBox(height: 20),
          
          // Stop list (show first 3 stops in offer preview)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: SwiftDashColors.backgroundGrey,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: SwiftDashColors.lightBlue.withOpacity(0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ROUTE OVERVIEW',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 12),
                ...(_stops!.take(3).map((stop) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          // Stop number badge
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: stop.stopType == 'pickup'
                                  ? SwiftDashColors.lightBlue
                                  : SwiftDashColors.darkBlue,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '${stop.stopNumber}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  stop.stopType == 'pickup' ? 'PICKUP' : 'DROP-OFF',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  stop.address,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.black87,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ))),
                if (_stops!.length > 3)
                  Text(
                    '+ ${_stops!.length - 3} more stops',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    }
    
    // SINGLE-STOP: Original timeline UI
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            SwiftDashColors.backgroundGrey,
            Colors.white,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: SwiftDashColors.lightBlue.withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: SwiftDashColors.lightBlue.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Pickup
          Row(
            children: [
              // Animated pulsing circle for pickup
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: SwiftDashColors.lightBlue,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: SwiftDashColors.lightBlue.withOpacity(0.3),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(Icons.store, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'PICKUP',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                        if (widget.routeData != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: SwiftDashColors.lightBlue.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${widget.routeData!.distance.toStringAsFixed(1)} km',
                              style: TextStyle(
                                fontSize: 10,
                                color: SwiftDashColors.lightBlue,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      delivery.pickupAddress,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
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
          
          // Connection line
          Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Container(
              width: 2,
              height: 24,
              color: SwiftDashColors.lightBlue.withOpacity(0.3),
            ),
          ),
          
          // Drop-off
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: SwiftDashColors.darkBlue,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.location_on, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      delivery.isMultiStop ? 'DROP-OFF (${delivery.totalStops - 1} stops)' : 'DROP-OFF',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      delivery.deliveryAddress,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
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
        ],
      ),
    );
  }
  
  /// Build swipe-to-accept button
  Widget _buildSwipeToAcceptButton() {
    return GestureDetector(
      onTap: _isProcessingOffer ? null : () {
        _triggerHapticFeedback(type: HapticFeedbackType.heavy);
        _handleAcceptOffer();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              SwiftDashColors.lightBlue,
              SwiftDashColors.darkBlue,
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: SwiftDashColors.lightBlue.withOpacity(0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: _isProcessingOffer
            ? const Center(
                child: SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.touch_app, color: Colors.white, size: 24),
                  SizedBox(width: 12),
                  Text(
                    'TAP TO ACCEPT DELIVERY',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
  
  /// Build active delivery content - PHASE 1 REDESIGN
  Widget _buildActiveDeliveryContent() {
    final delivery = widget.delivery;
    final currentStage = delivery.currentStage;
    final isGoingToPickup = currentStage == DeliveryStage.headingToPickup;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 📊 PROGRESS BAR - Visual stage indicator
        _buildProgressIndicator(currentStage),
        
        const SizedBox(height: 20),
        
        // 💰 EARNINGS + QUICK INFO
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                SwiftDashColors.lightBlue.withOpacity(0.1),
                SwiftDashColors.darkBlue.withOpacity(0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              // Earnings
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'EARNING',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₱${delivery.totalPrice.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              
              // Distance & ETA
              if (widget.routeData != null) ...[
                Container(
                  width: 1,
                  height: 40,
                  color: Colors.grey[300],
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.straighten, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          '${widget.routeData!.distance.toStringAsFixed(1)} km',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[800],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.schedule, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          '${widget.routeData!.duration} min',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[800],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        
        const SizedBox(height: 20),
        
        // � MULTI-STOP: Show full stop list OR single next destination
        if (delivery.isMultiStop && _stops != null && _stops!.isNotEmpty) ...[
          // Multi-stop list with interactive buttons
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  MultiStopBadge(totalStops: delivery.totalStops),
                  const Spacer(),
                  Text(
                    'Stop ${delivery.currentStopIndex + 1} of ${delivery.totalStops}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              StopProgressIndicator(stops: _stops!, showPercentage: false),
              const SizedBox(height: 16),
              StopListWidget(
                stops: _stops!,
                currentStopIndex: delivery.currentStopIndex,
                onNavigate: (stop) {
                  widget.onNavigate?.call();
                },
                onArrived: (stop) async {
                  // Update stop status to in_progress
                  await _multiStopService.updateStopStatus(
                    stopId: stop.id,
                    status: 'in_progress',
                    arrivedAt: DateTime.now(),
                  );
                  // Reload stops
                  await _loadStops();
                },
                onComplete: (stop) async {
                  // Show POD dialog based on stop type
                  if (stop.stopType == 'pickup') {
                    _handlePickupConfirmation(stop);
                  } else {
                    _handleDropoffPOD(stop);
                  }
                },
                onCustomerNotAvailable: (stop) async {
                  final result = await showCustomerNotAvailableDialog(context);
                  if (result != null) {
                    // Mark stop as failed
                    await _multiStopService.updateStopStatus(
                      stopId: stop.id,
                      status: 'failed',
                      completionNotes: 'Customer not available: ${result['reason']}',
                      completedAt: DateTime.now(),
                    );
                    
                    // 🚦 MULTI-STOP: Progress to next stop even if failed
                    await _progressToNextStop();
                    
                    // Reload stops
                    await _loadStops();
                  }
                },
              ),
            ],
          ),
        ] else ...[
          // Single-stop: Original next destination card
          _buildNextDestination(isGoingToPickup),
        ],
        
        const SizedBox(height: 20),
        
        // 🎯 PRIMARY ACTION BUTTON - Single, clear next action
        _buildPrimaryActionButton(currentStage),
        
        const SizedBox(height: 12),
        
        // ⚡ QUICK ACTIONS BAR
        _buildQuickActionsBar(),
        
        const SizedBox(height: 8),
      ],
    );
  }
  
  /// Build progress indicator showing current stage
  Widget _buildProgressIndicator(DeliveryStage currentStage) {
    final stages = [
      DeliveryStage.headingToPickup,
      DeliveryStage.headingToDelivery,
      DeliveryStage.deliveryComplete,
    ];
    
    final currentIndex = stages.indexOf(currentStage);
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: List.generate(stages.length, (index) {
          final isCompleted = index < currentIndex;
          final isCurrent = index == currentIndex;
          
          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: isCompleted || isCurrent
                          ? SwiftDashColors.lightBlue
                          : Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                if (index < stages.length - 1)
                  Container(
                    width: 8,
                    height: 4,
                    color: Colors.transparent,
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }
  
  /// Build next destination card
  Widget _buildNextDestination(bool isGoingToPickup) {
    final delivery = widget.delivery;
    final address = isGoingToPickup 
        ? delivery.pickupAddress 
        : delivery.deliveryAddress;
    final label = isGoingToPickup ? 'NEXT: PICKUP LOCATION' : 'NEXT: DROP-OFF LOCATION';
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SwiftDashColors.backgroundGrey,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: SwiftDashColors.lightBlue.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: SwiftDashColors.lightBlue.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isGoingToPickup ? Icons.store : Icons.location_on,
              color: SwiftDashColors.lightBlue,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  address,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Colors.black87,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
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
  
  /// Build primary action button - ONE clear next action based on status
  Widget _buildPrimaryActionButton(DeliveryStage stage) {
    final delivery = widget.delivery;
    String buttonText;
    IconData buttonIcon;
    VoidCallback? onPressed;
    
    // Determine button based on actual delivery status (more granular than stage)
    switch (delivery.status) {
      case DeliveryStatus.driverAssigned:
      case DeliveryStatus.goingToPickup:
        buttonText = "I'VE ARRIVED AT PICKUP";
        buttonIcon = Icons.store;
        onPressed = () {
          _triggerHapticFeedback(type: HapticFeedbackType.medium);
          _handleArrivedButton(stage);
        };
        break;
      case DeliveryStatus.pickupArrived:
        buttonText = "I'VE PICKED UP ITEMS";
        buttonIcon = Icons.shopping_bag;
        onPressed = () {
          _triggerHapticFeedback(type: HapticFeedbackType.medium);
          _handlePackageReceived();
        };
        break;
      case DeliveryStatus.packageCollected:
      case DeliveryStatus.goingToDestination:
        buttonText = "I'VE ARRIVED AT DESTINATION";
        buttonIcon = Icons.location_on;
        onPressed = () {
          _triggerHapticFeedback(type: HapticFeedbackType.medium);
          _handleArrivedButton(stage);
        };
        break;
      case DeliveryStatus.atDestination:
        buttonText = "COMPLETE DELIVERY";
        buttonIcon = Icons.check_circle;
        onPressed = () {
          _triggerHapticFeedback(type: HapticFeedbackType.heavy);
          _handleMarkAsDelivered();
        };
        break;
      default:
        buttonText = "CONTINUE";
        buttonIcon = Icons.arrow_forward;
        onPressed = null;
    }
    
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: SwiftDashColors.lightBlue,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        elevation: 0,
        shadowColor: Colors.transparent,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(buttonIcon, size: 22),
          const SizedBox(width: 12),
          Text(
            buttonText,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
  
  /// Build quick actions bar
  Widget _buildQuickActionsBar() {
    return Row(
      children: [
        Expanded(
          child: _buildQuickActionButton(
            icon: Icons.phone,
            label: 'Call',
            onTap: _callCustomer,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildQuickActionButton(
            icon: Icons.navigation,
            label: 'Navigate',
            onTap: () {
              if (widget.onNavigate != null) {
                widget.onNavigate!();
              }
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildQuickActionButton(
            icon: Icons.warning_amber,
            label: 'Issue',
            onTap: () => _showIssueDialog(),
          ),
        ),
      ],
    );
  }
  
  /// Show issue dialog
  Future<void> _showIssueDialog() async {
    // Simple dialog to report issue
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Report Issue'),
        content: const Text('Issue reporting feature coming soon.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
  
  /// Build individual quick action button
  Widget _buildQuickActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: () {
        _triggerHapticFeedback(type: HapticFeedbackType.selection);
        onTap();
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: SwiftDashColors.backgroundGrey,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Colors.grey[300]!,
            width: 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: SwiftDashColors.textGrey, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: SwiftDashColors.textGrey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // State for offer processing
  bool _isProcessingOffer = false;
  
  /// Handle accept offer button press
  /// Handle pickup confirmation for multi-stop delivery
  Future<void> _handlePickupConfirmation(DeliveryStop stop) async {
    final photoUrl = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PickupConfirmationDialog(
        delivery: widget.delivery,
      ),
    );
    
    if (photoUrl != null) {
      try {
        // Update stop with photo
        await _multiStopService.updateStopStatus(
          stopId: stop.id,
          status: 'completed',
          proofPhotoUrl: photoUrl,
          completedAt: DateTime.now(),
        );
        
        // 🚦 MULTI-STOP: Progress to next stop
        await _progressToNextStop();
        
        // Reload stops
        await _loadStops();
        
        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Pickup confirmed!'),
              backgroundColor: SwiftDashColors.successGreen,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        print('Error updating pickup: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to update pickup: $e'),
              backgroundColor: SwiftDashColors.dangerRed,
            ),
          );
        }
      }
    }
  }
  
  /// Handle dropoff POD for multi-stop delivery
  Future<void> _handleDropoffPOD(DeliveryStop stop) async {
    final result = await showDialog<Map<String, String>?>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ProofOfDeliveryDialog(
        delivery: widget.delivery,
      ),
    );
    
    if (result != null) {
      try {
        // Update stop with photo and signature
        await _multiStopService.updateStopStatus(
          stopId: stop.id,
          status: 'completed',
          proofPhotoUrl: result['photoUrl'],
          signatureUrl: result['signatureUrl'],
          completedAt: DateTime.now(),
        );
        
        // 🚦 MULTI-STOP: Progress to next stop
        await _progressToNextStop();
        
        // Reload stops
        await _loadStops();
        
        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Delivery completed!'),
              backgroundColor: SwiftDashColors.successGreen,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        print('Error updating dropoff: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to update delivery: $e'),
              backgroundColor: SwiftDashColors.dangerRed,
            ),
          );
        }
      }
    }
  }
  
  Future<void> _handleAcceptOffer() async {
    if (widget.onAcceptOffer == null) return;
    
    setState(() {
      _isProcessingOffer = true;
    });
    
    try {
      final success = await widget.onAcceptOffer!();
      
      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to accept delivery. It may have been taken by another driver.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('❌ Error accepting offer: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingOffer = false;
        });
      }
    }
  }
  
  /// Handle decline offer button press
  Future<void> _handleDeclineOffer() async {
    if (widget.onDeclineOffer == null) return;
    
    setState(() {
      _isProcessingOffer = true;
    });
    
    try {
      final success = await widget.onDeclineOffer!();
      
      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to decline delivery.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      print('❌ Error declining offer: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingOffer = false;
        });
      }
    }
  }
  
  /// Handle "Package Received" button tap
  Future<void> _handlePackageReceived() async {
    try {
      // Show pickup confirmation dialog with photo capture
      final photoUrl = await showDialog<String?>(
        context: context,
        barrierDismissible: false,
        builder: (context) => PickupConfirmationDialog(
          delivery: widget.delivery,
        ),
      );
      
      // If user cancelled, return early
      if (photoUrl == null) {
        print('📦 Pickup confirmation cancelled by user');
        return;
      }
      
      print('📦 Package received confirmed with photo: $photoUrl');
      
      // 🔒 RACE CONDITION FIX: Check current status before updating
      // Prevents overwriting customer cancellation with driver status update
      final currentDelivery = await supabase
          .from('deliveries')
          .select('status')
          .eq('id', widget.delivery.id)
          .single();
      
      if (currentDelivery['status'] == 'cancelled') {
        print('⚠️ Delivery already cancelled, aborting status update');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🚫 This delivery has been cancelled'),
              backgroundColor: Colors.red,
            ),
          );
        }
        // Trigger refresh to close panel
        widget.onStatusChange?.call(DeliveryStage.headingToPickup);
        return;
      }
      
      // Update status to packageCollected in database
      final response = await supabase.from('deliveries').update({
        'status': DeliveryStatus.packageCollected.databaseValue,
        'pickup_proof_photo_url': photoUrl,
        // Note: picked_up_at column doesn't exist in schema - removed
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', widget.delivery.id).select();
      
      print('✅ Package collected status updated: $response');
      
      // Notify parent to refresh delivery state
      if (widget.onStatusChange != null) {
        widget.onStatusChange!(DeliveryStage.headingToDelivery);
      }
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Package collected successfully'),
            backgroundColor: SwiftDashColors.successGreen,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('❌ Error confirming package received: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to confirm pickup: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  /// Handle "Arrived" button tap
  Future<void> _handleArrivedButton(DeliveryStage stage) async {
    try {
      // Determine the next status
      final nextStatus = stage == DeliveryStage.headingToPickup
          ? DeliveryStatus.pickupArrived
          : DeliveryStatus.atDestination;
      
      print('📍 Driver marking arrived: $nextStatus');
      print('📍 Using database value: ${nextStatus.databaseValue}');
      
      // 🔒 RACE CONDITION FIX: Check current status before updating
      // Prevents overwriting customer cancellation with driver status update
      final currentDelivery = await supabase
          .from('deliveries')
          .select('status')
          .eq('id', widget.delivery.id)
          .single();
      
      if (currentDelivery['status'] == 'cancelled') {
        print('⚠️ Delivery already cancelled, aborting status update');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🚫 This delivery has been cancelled'),
              backgroundColor: Colors.red,
            ),
          );
        }
        // Trigger refresh to close panel
        widget.onStatusChange?.call(stage);
        return;
      }
      
      // Update status in database
      // NOTE: The deliveries table does not have explicit arrival timestamp
      // columns in the current schema. Writing to unknown columns causes
      // PostgREST errors (PGRST204). Set status and updated_at only.
      final response = await supabase.from('deliveries').update({
        'status': nextStatus.databaseValue,  // ✅ Use snake_case for customer app
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', widget.delivery.id).select();
      
      print('✅ Database update response: $response');
      
      // ✅ FIX: Notify parent to refresh delivery state immediately
      // The parent will reload the delivery from database and rebuild the panel
      // with the updated status, which will show the correct button state
      if (widget.onStatusChange != null) {
        // Pass current stage - parent will reload delivery and determine new stage from updated status
        widget.onStatusChange!(stage);
      }
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              stage == DeliveryStage.headingToPickup 
                ? '✅ Marked as arrived at pickup - tap to confirm package collection' 
                : '✅ Marked as arrived at delivery - tap to complete',
            ),
            backgroundColor: SwiftDashColors.successGreen,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      
      print('✅ Status updated to: $nextStatus - parent will refresh delivery');
    } catch (e) {
      print('❌ Error updating arrival status: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Failed to update status'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  Future<void> _callCustomer() async {
    final phone = widget.delivery.deliveryContactPhone;
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ No phone number available'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Could not launch phone app'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  /// Show cancel job confirmation dialog
  Future<void> _showCancelJobDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 12),
            Text('Cancel Job?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Are you sure you want to cancel this delivery?',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This action cannot be undone. The customer will be notified.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep Job'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Cancel Job'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      await _cancelJob();
    }
  }
  
  /// Cancel the current job
  Future<void> _cancelJob() async {
    try {
      print('🚫 Cancelling delivery: ${widget.delivery.id}');
      
      // CRITICAL: Stop Ably location tracking FIRST before updating database
      DriverLocationService().stopTracking();
      print('📍 Stopped Ably location tracking');
      
      // Update delivery status to cancelled
      await supabase.from('deliveries').update({
        'status': DeliveryStatus.cancelled.databaseValue,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', widget.delivery.id);
      
      print('✅ Delivery cancelled successfully');
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🚫 Job cancelled'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
        
        // Trigger parent refresh to clear the delivery
        // This will cause the panel to disappear automatically
        widget.onStatusChange?.call(DeliveryStage.headingToPickup);
        
        // DON'T call Navigator.pop() - the panel will hide when activeDelivery becomes null
        print('✅ Cancellation complete - panel will hide automatically');
      }
    } catch (e) {
      print('❌ Error cancelling job: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to cancel job: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  /// Handle "Mark as Delivered" button tap
  Future<void> _handleMarkAsDelivered() async {
    try {
      // Show POD (Proof of Delivery) dialog
      final podResult = await showDialog<Map<String, dynamic>?>(
        context: context,
        barrierDismissible: false,
        builder: (context) => ProofOfDeliveryDialog(
          delivery: widget.delivery,
        ),
      );
      
      // If user cancelled, return early
      if (podResult == null) {
        print('📦 Delivery confirmation cancelled by driver');
        return;
      }
      
      print('✅ POD captured, updating delivery status...');
      print('📸 Photo URL: ${podResult['photoUrl']}');
      print('✍️ Signature: ${podResult['signatureData'] != null ? 'Yes' : 'No'}');
      
      // 🔒 RACE CONDITION FIX: Check current status before updating
      final currentDelivery = await supabase
          .from('deliveries')
          .select('status')
          .eq('id', widget.delivery.id)
          .single();
      
      if (currentDelivery['status'] == 'cancelled') {
        print('⚠️ Delivery already cancelled, aborting completion');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🚫 This delivery has been cancelled'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      
      // Update delivery status to delivered
      // Note: POD fields (proof_photo_url, signature_data, recipient_name, delivery_notes) 
      // don't exist in current schema - removed to prevent PGRST204 errors
      await supabase.from('deliveries').update({
        'status': DeliveryStatus.delivered.databaseValue,
        'completed_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', widget.delivery.id);
      
      print('✅ Delivery marked as complete');
      
      if (context.mounted) {
        // 🎊 PHASE 3: Trigger confetti celebration!
        _confettiController.play();
        _triggerHapticFeedback(type: HapticFeedbackType.heavy);
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 Delivery completed successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        
        // Notify parent of completion
        widget.onStatusChange!(DeliveryStage.deliveryComplete);
      }
    } catch (e) {
      print('❌ Error marking as delivered: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to complete delivery: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  /// Show report issue dialog
  Future<void> _showReportIssueDialog() async {
    String? selectedIssue;
    final TextEditingController notesController = TextEditingController();
    
    final issues = [
      'Customer Not Available',
      'Wrong Address',
      'Customer Refused Delivery',
      'Damaged Package',
      'Unsafe Location',
      'Other',
    ];
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.report_problem, color: Colors.red, size: 28),
              SizedBox(width: 12),
              Text('Report Issue'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select the issue you encountered:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 16),
                
                // Issue type dropdown
                DropdownButtonFormField<String>(
                  value: selectedIssue,
                  decoration: InputDecoration(
                    labelText: 'Issue Type',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 16,
                    ),
                  ),
                  items: issues.map((issue) {
                    return DropdownMenuItem(
                      value: issue,
                      child: Text(issue),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedIssue = value;
                    });
                  },
                ),
                
                const SizedBox(height: 16),
                
                // Notes text field
                TextField(
                  controller: notesController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Additional Notes (Optional)',
                    hintText: 'Provide more details about the issue...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Warning banner
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.red.shade700, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This will mark the delivery as failed. The customer will be notified.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.red.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: selectedIssue == null
                  ? null
                  : () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Report Issue'),
            ),
          ],
        ),
      ),
    );
    
    if (confirmed == true && selectedIssue != null) {
      await _reportIssue(selectedIssue!, notesController.text);
    }
    
    notesController.dispose();
  }
  
  /// Report delivery issue
  Future<void> _reportIssue(String issueType, String notes) async {
    try {
      print('📝 Reporting issue: $issueType');
      
      // 🔒 RACE CONDITION FIX: Check current status before updating
      final currentDelivery = await supabase
          .from('deliveries')
          .select('status')
          .eq('id', widget.delivery.id)
          .single();
      
      if (currentDelivery['status'] == 'cancelled') {
        print('⚠️ Delivery already cancelled, cannot report issue');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🚫 This delivery has been cancelled'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      
      // Update delivery status to failed with issue details
      // Note: delivery_notes column doesn't exist in schema - removed
      await supabase.from('deliveries').update({
        'status': DeliveryStatus.failed.databaseValue,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', widget.delivery.id);
      
      print('✅ Issue reported successfully');
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📝 Issue reported. Customer will be notified.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
        
        // Close the panel
        Navigator.of(context).pop();
      }
    } catch (e) {
      print('❌ Error reporting issue: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to report issue: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
