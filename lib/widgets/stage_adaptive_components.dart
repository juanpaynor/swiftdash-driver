import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/delivery.dart';
import '../services/delivery_stage_manager.dart';

/// Stage-adaptive header component for 3-stage delivery flow
class StageAdaptiveHeader extends StatelessWidget {
  final Delivery delivery;
  final DeliveryStage currentStage;

  const StageAdaptiveHeader({
    Key? key,
    required this.delivery,
    required this.currentStage,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final stageColors = delivery.stageColors;
    final stageDisplayName = delivery.stageDisplayName;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [stageColors.primary, stageColors.accent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Stage indicator and progress
            Row(
              children: [
                Expanded(
                  child: Text(
                    stageDisplayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _buildStageIndicator(context),
              ],
            ),
            const SizedBox(height: 12),
            
            // Stage-specific status information
            _buildStageStatusInfo(context),
            
            const SizedBox(height: 16),
            
            // Progress bar for visual feedback
            _buildProgressBar(context),
          ],
        ),
      ),
    );
  }

  Widget _buildStageIndicator(BuildContext context) {
    return Row(
      children: [
        // Stage 1 indicator
        _buildStageCircle(
          isActive: true,
          isCompleted: currentStage.index >= 0,
          label: '1',
        ),
        const SizedBox(width: 4),
        
        // Stage 1-2 connector
        Container(
          width: 20,
          height: 2,
          color: currentStage.index >= 1 
              ? Colors.white 
              : Colors.white.withOpacity(0.3),
        ),
        const SizedBox(width: 4),
        
        // Stage 2 indicator  
        _buildStageCircle(
          isActive: currentStage == DeliveryStage.headingToDelivery,
          isCompleted: currentStage.index >= 1,
          label: '2',
        ),
        const SizedBox(width: 4),
        
        // Stage 2-3 connector
        Container(
          width: 20,
          height: 2,
          color: currentStage.index >= 2 
              ? Colors.white 
              : Colors.white.withOpacity(0.3),
        ),
        const SizedBox(width: 4),
        
        // Stage 3 indicator
        _buildStageCircle(
          isActive: currentStage == DeliveryStage.deliveryComplete,
          isCompleted: currentStage.index >= 2,
          label: '3',
        ),
      ],
    );
  }

  Widget _buildStageCircle({
    required bool isActive,
    required bool isCompleted,
    required String label,
  }) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isCompleted 
            ? Colors.white
            : isActive 
                ? Colors.white.withOpacity(0.8)
                : Colors.white.withOpacity(0.3),
        border: Border.all(
          color: Colors.white,
          width: 2,
        ),
      ),
      child: Center(
        child: isCompleted && !isActive
            ? const Icon(Icons.check, size: 14, color: Colors.green)
            : Text(
                label,
                style: TextStyle(
                  color: isCompleted || isActive ? Colors.black : Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  Widget _buildStageStatusInfo(BuildContext context) {
    switch (currentStage) {
      case DeliveryStage.headingToPickup:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Show scheduled pickup time if applicable
            if (delivery.isScheduled && delivery.scheduledPickupTime != null) ...[
              Row(
                children: [
                  Icon(Icons.schedule, color: Colors.amber.shade200, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'Pickup at ${DateFormat('h:mm a').format(delivery.scheduledPickupTime!)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Time countdown
                  _buildTimeCountdown(),
                ],
              ),
              const SizedBox(height: 8),
            ],
            Text(
              'Navigate to: ${delivery.pickupAddress}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Contact: ${delivery.pickupContactName} - ${delivery.pickupContactPhone}',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 13,
              ),
            ),
          ],
        );
        
      case DeliveryStage.headingToDelivery:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Deliver to: ${delivery.deliveryAddress}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Contact: ${delivery.deliveryContactName} - ${delivery.deliveryContactPhone}',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 13,
              ),
            ),
          ],
        );
        
      case DeliveryStage.deliveryComplete:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🎉 Successfully Delivered!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Earnings: ₱${delivery.driverEarnings.toStringAsFixed(2)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );
    }
  }

  Widget _buildProgressBar(BuildContext context) {
    // Calculate overall progress percentage
    double progressPercentage;
    switch (currentStage) {
      case DeliveryStage.headingToPickup:
        // Stage 1 progress based on status
        switch (delivery.status) {
          case DeliveryStatus.driverAssigned:
            progressPercentage = 0.1;
            break;
          case DeliveryStatus.goingToPickup:
            progressPercentage = 0.25;
            break;
          case DeliveryStatus.pickupArrived:
            progressPercentage = 0.33;
            break;
          default:
            progressPercentage = 0.1;
        }
        break;
        
      case DeliveryStage.headingToDelivery:
        // Stage 2 progress (33% to 90%)
        switch (delivery.status) {
          case DeliveryStatus.packageCollected:
            progressPercentage = 0.4;
            break;
          case DeliveryStatus.goingToDestination:
            progressPercentage = 0.7;
            break;
          case DeliveryStatus.atDestination:
            progressPercentage = 0.9;
            break;
          default:
            progressPercentage = 0.4;
        }
        break;
        
      case DeliveryStage.deliveryComplete:
        progressPercentage = 1.0;
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Delivery Progress',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 12,
              ),
            ),
            Text(
              '${(progressPercentage * 100).round()}%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progressPercentage,
            backgroundColor: Colors.white.withOpacity(0.3),
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            minHeight: 6,
          ),
        ),
      ],
    );
  }
  
  Widget _buildTimeCountdown() {
    if (!delivery.isScheduled || delivery.scheduledPickupTime == null) {
      return const SizedBox.shrink();
    }
    
    final now = DateTime.now();
    final minutesUntil = delivery.scheduledPickupTime!.difference(now).inMinutes;
    
    Color bgColor;
    String text;
    
    if (minutesUntil < 0) {
      bgColor = Colors.red.shade700;
      text = '${-minutesUntil}m LATE';
    } else if (minutesUntil <= 5) {
      bgColor = Colors.red.shade600;
      text = '${minutesUntil}m';
    } else if (minutesUntil <= 10) {
      bgColor = Colors.orange.shade600;
      text = '${minutesUntil}m';
    } else {
      return const SizedBox.shrink(); // Don't show if more than 10 min
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Priority information card that adapts based on delivery stage
class PriorityInfoCard extends StatelessWidget {
  final Delivery delivery;
  final DeliveryStage currentStage;

  const PriorityInfoCard({
    Key? key,
    required this.delivery,
    required this.currentStage,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPriorityHeader(context),
            const SizedBox(height: 12),
            _buildPriorityContent(context),
          ],
        ),
      ),
    );
  }

  Widget _buildPriorityHeader(BuildContext context) {
    IconData icon;
    String title;
    Color iconColor;
    
    switch (currentStage) {
      case DeliveryStage.headingToPickup:
        icon = Icons.person_pin_circle;
        title = 'Pickup Details';
        iconColor = Colors.blue;
        break;
      case DeliveryStage.headingToDelivery:
        icon = Icons.location_on;
        title = 'Delivery Details';
        iconColor = Colors.purple;
        break;
      case DeliveryStage.deliveryComplete:
        icon = Icons.check_circle;
        title = 'Completion Summary';
        iconColor = Colors.green;
        break;
    }

    return Row(
      children: [
        Icon(icon, color: iconColor, size: 24),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (currentStage != DeliveryStage.deliveryComplete)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Priority',
              style: TextStyle(
                color: iconColor,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPriorityContent(BuildContext context) {
    switch (currentStage) {
      case DeliveryStage.headingToPickup:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Address', delivery.pickupAddress),
            _buildInfoRow('Contact', '${delivery.pickupContactName}\n${delivery.pickupContactPhone}'),
            if (delivery.pickupInstructions?.isNotEmpty == true)
              _buildInfoRow('Instructions', delivery.pickupInstructions!),
            _buildInfoRow('Package', delivery.packageDescription),
            if (delivery.packageWeight != null)
              _buildInfoRow('Weight', '${delivery.packageWeight!.toStringAsFixed(1)} kg'),
            _buildInfoRow('Payment', '${delivery.paymentMethodDisplayName} by ${delivery.paymentBy?.toUpperCase()}'),
          ],
        );
        
      case DeliveryStage.headingToDelivery:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Address', delivery.deliveryAddress),
            _buildInfoRow('Contact', '${delivery.deliveryContactName}\n${delivery.deliveryContactPhone}'),
            if (delivery.deliveryInstructions?.isNotEmpty == true)
              _buildInfoRow('Instructions', delivery.deliveryInstructions!),
            _buildInfoRow('Package', delivery.packageDescription),
            if (delivery.packageValue != null && delivery.packageValue! > 0)
              _buildInfoRow('Value', '\$${delivery.packageValue!.toStringAsFixed(2)}'),
            _buildInfoRow('Payment', delivery.paymentMethodDisplayName),
            if (delivery.requiresCashRemittance)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.orange, size: 16),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Collect cash payment and provide receipt',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
        
      case DeliveryStage.deliveryComplete:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Order ID', delivery.id.substring(0, 8).toUpperCase()),
            _buildInfoRow('Completed At', _formatDateTime(DateTime.now())),
            _buildInfoRow('Total Distance', delivery.formattedDistance),
            _buildInfoRow('Duration', delivery.formattedDuration),
            const Divider(height: 24),
            _buildEarningsRow('Total Amount', '₱${delivery.totalAmount?.toStringAsFixed(2) ?? delivery.totalPrice.toStringAsFixed(2)}'),
            _buildEarningsRow('Your Earnings', '₱${delivery.driverEarnings.toStringAsFixed(2)}', isEarnings: true),
            if (delivery.tipAmount != null && delivery.tipAmount! > 0)
              _buildEarningsRow('Tip', '+₱${delivery.tipAmount!.toStringAsFixed(2)}', isBonus: true),
          ],
        );
    }
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEarningsRow(String label, String amount, {bool isEarnings = false, bool isBonus = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isEarnings ? 16 : 14,
              fontWeight: isEarnings ? FontWeight.bold : FontWeight.w500,
              color: isEarnings ? Colors.green[700] : Colors.black87,
            ),
          ),
          Text(
            amount,
            style: TextStyle(
              fontSize: isEarnings ? 18 : 14,
              fontWeight: FontWeight.bold,
              color: isEarnings 
                  ? Colors.green[700] 
                  : isBonus 
                      ? Colors.blue[600]
                      : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} at ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}