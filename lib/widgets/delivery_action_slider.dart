import 'package:flutter/material.dart';
import '../models/delivery.dart';
import '../services/delivery_stage_manager.dart';

/// Custom slider component with slide-to-confirm UX and photo/signature integration
class DeliveryActionSlider extends StatefulWidget {
  final Delivery delivery;
  final DeliveryStage currentStage;
  final VoidCallback? onSlideComplete;
  final VoidCallback? onPhotoCapture;
  final VoidCallback? onSignatureCapture;

  const DeliveryActionSlider({
    Key? key,
    required this.delivery,
    required this.currentStage,
    this.onSlideComplete,
    this.onPhotoCapture,
    this.onSignatureCapture,
  }) : super(key: key);

  @override
  State<DeliveryActionSlider> createState() => _DeliveryActionSliderState();
}

class _DeliveryActionSliderState extends State<DeliveryActionSlider>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;
  
  double _sliderPosition = 0.0;
  bool _isSliding = false;
  bool _isCompleted = false;
  
  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSliderEnabled = DeliveryStageManager.isSliderEnabled(
      widget.currentStage, 
      widget.delivery.status,
    );
    final sliderText = DeliveryStageManager.getSliderText(
      widget.currentStage, 
      widget.delivery.status,
    );
    


    return Column(
      children: [
        // Photo/Signature action buttons (shown when slider is enabled)
        if (isSliderEnabled && widget.currentStage == DeliveryStage.headingToDelivery)
          _buildProofOfDeliveryActions(context),
        
        const SizedBox(height: 16),
        
        // Main slider component
        Container(
          height: 70,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(35),
            color: isSliderEnabled 
                ? widget.delivery.stageColors.background
                : Colors.grey[200],
            border: Border.all(
              color: isSliderEnabled 
                  ? widget.delivery.stageColors.primary.withOpacity(0.3)
                  : Colors.grey[300]!,
              width: 2,
            ),
          ),
          child: Stack(
            children: [
              // Background text
              Center(
                child: AnimatedBuilder(
                  animation: _animation,
                  builder: (context, child) {
                    return Opacity(
                      opacity: 1 - (_sliderPosition / 0.8),
                      child: Text(
                        sliderText,
                        style: TextStyle(
                          color: isSliderEnabled 
                              ? widget.delivery.stageColors.primary
                              : Colors.grey[500],
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  },
                ),
              ),
              
              // Sliding circle
              if (isSliderEnabled)
                Positioned(
                  left: _sliderPosition * (MediaQuery.of(context).size.width - 32 - 70 - 70), // Account for margins and circle size
                  top: 4,
                  child: GestureDetector(
                    onPanStart: (_) {
                      if (!_isCompleted) {
                        setState(() {
                          _isSliding = true;
                        });
                      }
                    },
                    onPanUpdate: (details) {
                      if (!_isCompleted && _isSliding) {
                        final maxWidth = MediaQuery.of(context).size.width - 32 - 70 - 70;
                        final newPosition = (_sliderPosition * maxWidth + details.delta.dx) / maxWidth;
                        setState(() {
                          _sliderPosition = newPosition.clamp(0.0, 1.0);
                        });
                        
                        // Trigger completion at 80% slide
                        if (_sliderPosition >= 0.8 && !_isCompleted) {
                          _completeSlide();
                        }
                      }
                    },
                    onPanEnd: (_) {
                      if (!_isCompleted && _sliderPosition < 0.8) {
                        // Animate back to start if not completed
                        _animateToPosition(0.0);
                      }
                      setState(() {
                        _isSliding = false;
                      });
                    },
                    child: AnimatedContainer(
                      duration: _isSliding ? Duration.zero : const Duration(milliseconds: 300),
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isCompleted 
                            ? Colors.green
                            : widget.delivery.stageColors.primary,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            offset: const Offset(0, 2),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: Icon(
                        _isCompleted ? Icons.check : Icons.arrow_forward_ios,
                        color: Colors.white,
                        size: _isCompleted ? 32 : 24,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        
        // Helper text
        if (isSliderEnabled && !_isCompleted)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              widget.currentStage == DeliveryStage.headingToPickup
                  ? 'Slide to confirm package pickup'
                  : 'Slide to confirm delivery completion',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildProofOfDeliveryActions(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.camera_alt, color: Colors.orange, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Proof of Delivery Required',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: widget.onPhotoCapture,
                  icon: const Icon(Icons.photo_camera, size: 18),
                  label: const Text('Take Photo'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.delivery.stageColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: widget.onSignatureCapture,
                  icon: const Icon(Icons.draw, size: 18),
                  label: const Text('Signature'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: widget.delivery.stageColors.primary,
                    side: BorderSide(color: widget.delivery.stageColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _completeSlide() {
    if (_isCompleted) return;
    
    setState(() {
      _isCompleted = true;
      _sliderPosition = 1.0;
    });
    
    // Animate to final position and trigger callback
    _animateToPosition(1.0).then((_) {
      if (widget.onSlideComplete != null) {
        widget.onSlideComplete!();
      }
    });
  }

  Future<void> _animateToPosition(double position) async {
    _animationController.reset();
    await _animationController.forward();
    
    setState(() {
      _sliderPosition = position;
    });
  }
}

/// Navigation button for stage-specific actions
class StageNavigationButton extends StatelessWidget {
  final Delivery delivery;
  final DeliveryStage currentStage;
  final VoidCallback? onPressed;

  const StageNavigationButton({
    Key? key,
    required this.delivery,
    required this.currentStage,
    this.onPressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final buttonText = DeliveryStageManager.getPrimaryActionText(delivery.status);
    final isEnabled = _isButtonEnabled();
    

    
    return Container(
      margin: const EdgeInsets.all(16),
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isEnabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: isEnabled 
              ? delivery.stageColors.primary 
              : Colors.grey[300],
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: isEnabled ? 4 : 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_getButtonIcon()),
            const SizedBox(width: 8),
            Text(
              buttonText,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isButtonEnabled() {
    // Debug: Print current status to understand the issue
    print('🔍 StageNavigationButton - Current Status: ${delivery.status}');
    print('🔍 StageNavigationButton - Current Stage: ${currentStage}');
    
    switch (delivery.status) {
      case DeliveryStatus.driverAssigned:
        return true; // START: Navigate to pickup - SHOULD BE ENABLED
      case DeliveryStatus.goingToPickup:
        return true; // Confirm arrival at pickup
      case DeliveryStatus.pickupArrived:
        return false; // Use slider to confirm pickup
      case DeliveryStatus.packageCollected:
        return true; // Navigate to delivery
      case DeliveryStatus.goingToDestination:
        return true; // Confirm arrival at destination
      case DeliveryStatus.atDestination:
        return false; // Use slider to confirm delivery
      case DeliveryStatus.delivered:
        return true; // Find new orders
      default:
        // Fallback: if unsure, enable the button
        print('⚠️ Unknown status, enabling button as fallback');
        return true;
    }
  }

  IconData _getButtonIcon() {
    switch (delivery.status) {
      case DeliveryStatus.driverAssigned:
      case DeliveryStatus.packageCollected:
        return Icons.navigation;
      case DeliveryStatus.goingToPickup:
      case DeliveryStatus.goingToDestination:
        return Icons.location_on;
      case DeliveryStatus.delivered:
        return Icons.search;
      default:
        return Icons.arrow_forward;
    }
  }
}