import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/delivery.dart';

/// Badge to display scheduled delivery indicator
class ScheduledDeliveryIndicator extends StatelessWidget {
  final Delivery delivery;
  final double fontSize;
  
  const ScheduledDeliveryIndicator({
    super.key,
    required this.delivery,
    this.fontSize = 12,
  });
  
  @override
  Widget build(BuildContext context) {
    if (!delivery.isScheduled || delivery.scheduledPickupTime == null) {
      return const SizedBox.shrink();
    }
    
    final pickupTime = delivery.scheduledPickupTime!;
    final formattedTime = DateFormat('h:mm a').format(pickupTime);
    final formattedDate = DateFormat('MMM d').format(pickupTime);
    final isToday = _isToday(pickupTime);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.amber.shade100,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.schedule,
            color: Colors.amber.shade800,
            size: fontSize + 4,
          ),
          const SizedBox(width: 4),
          Text(
            isToday ? 'Today $formattedTime' : '$formattedDate $formattedTime',
            style: TextStyle(
              color: Colors.amber.shade900,
              fontWeight: FontWeight.bold,
              fontSize: fontSize,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
  
  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && 
           date.month == now.month && 
           date.day == now.day;
  }
}

/// Expanded scheduled delivery details card
class ScheduledDeliveryDetailsCard extends StatelessWidget {
  final Delivery delivery;
  
  const ScheduledDeliveryDetailsCard({
    super.key,
    required this.delivery,
  });
  
  @override
  Widget build(BuildContext context) {
    if (!delivery.isScheduled || delivery.scheduledPickupTime == null) {
      return const SizedBox.shrink();
    }
    
    final pickupTime = delivery.scheduledPickupTime!;
    final now = DateTime.now();
    final minutesUntil = pickupTime.difference(now).inMinutes;
    final hoursUntil = pickupTime.difference(now).inHours;
    
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      color: Colors.amber.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.schedule, color: Colors.amber.shade800, size: 24),
                const SizedBox(width: 8),
                Text(
                  'Scheduled Delivery',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber.shade900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              icon: Icons.calendar_today,
              label: 'Date',
              value: DateFormat('EEEE, MMMM d, yyyy').format(pickupTime),
            ),
            const SizedBox(height: 8),
            _buildInfoRow(
              icon: Icons.access_time,
              label: 'Pickup Time',
              value: DateFormat('h:mm a').format(pickupTime),
              valueStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            _buildInfoRow(
              icon: Icons.hourglass_empty,
              label: 'Time Until Pickup',
              value: _formatTimeUntil(hoursUntil, minutesUntil),
              valueColor: _getTimeUntilColor(minutesUntil),
            ),
            const Divider(height: 24),
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
                      '⚠️ Please arrive at pickup location on time',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade900,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    TextStyle? valueStyle,
    Color? valueColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.amber.shade700),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 14, color: Colors.black87),
        ),
        const Spacer(),
        Text(
          value,
          style: valueStyle ?? TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: valueColor ?? Colors.black,
          ),
        ),
      ],
    );
  }
  
  String _formatTimeUntil(int hours, int minutes) {
    if (minutes < 0) {
      return 'OVERDUE!';
    } else if (hours > 24) {
      final days = hours ~/ 24;
      return '$days day${days > 1 ? 's' : ''}';
    } else if (hours > 0) {
      return '$hours hour${hours > 1 ? 's' : ''} ${minutes % 60} min';
    } else {
      return '$minutes minutes';
    }
  }
  
  Color _getTimeUntilColor(int minutes) {
    if (minutes < 0) {
      return Colors.red.shade700; // Overdue
    } else if (minutes <= 10) {
      return Colors.orange.shade700; // Urgent
    } else {
      return Colors.green.shade700; // On time
    }
  }
}

/// Pickup time warning banner
class PickupTimeWarning extends StatelessWidget {
  final Delivery delivery;
  
  const PickupTimeWarning({
    super.key,
    required this.delivery,
  });
  
  @override
  Widget build(BuildContext context) {
    if (!delivery.isScheduled || delivery.scheduledPickupTime == null) {
      return const SizedBox.shrink();
    }
    
    // Don't show warning if already picked up
    if (delivery.status == DeliveryStatus.packageCollected ||
        delivery.status == DeliveryStatus.goingToDestination ||
        delivery.status == DeliveryStatus.atDestination ||
        delivery.status == DeliveryStatus.delivered) {
      return const SizedBox.shrink();
    }
    
    final now = DateTime.now();
    final scheduledTime = delivery.scheduledPickupTime!;
    final minutesUntilPickup = scheduledTime.difference(now).inMinutes;
    
    // Show urgent warning if less than 10 minutes until pickup
    if (minutesUntilPickup > 0 && minutesUntilPickup <= 10) {
      return Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.orange.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.shade300, width: 2),
        ),
        child: Row(
          children: [
            Icon(
              Icons.warning_amber,
              color: Colors.orange.shade800,
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '⚠️ Pickup in $minutesUntilPickup minute${minutesUntilPickup > 1 ? 's' : ''}!',
                    style: TextStyle(
                      color: Colors.orange.shade900,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Please head to pickup location now',
                    style: TextStyle(
                      color: Colors.orange.shade800,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    
    // Show late warning if past scheduled time
    if (minutesUntilPickup < 0) {
      final minutesLate = -minutesUntilPickup;
      return Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.shade300, width: 2),
        ),
        child: Row(
          children: [
            Icon(
              Icons.error,
              color: Colors.red.shade800,
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '🚨 $minutesLate minute${minutesLate > 1 ? 's' : ''} LATE!',
                    style: TextStyle(
                      color: Colors.red.shade900,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Customer is waiting. Please hurry!',
                    style: TextStyle(
                      color: Colors.red.shade800,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    
    return const SizedBox.shrink();
  }
}

/// Compact time countdown widget
class PickupCountdown extends StatefulWidget {
  final Delivery delivery;
  
  const PickupCountdown({
    super.key,
    required this.delivery,
  });
  
  @override
  State<PickupCountdown> createState() => _PickupCountdownState();
}

class _PickupCountdownState extends State<PickupCountdown> {
  @override
  void initState() {
    super.initState();
    // Update every minute
    Future.delayed(const Duration(minutes: 1), () {
      if (mounted) {
        setState(() {});
      }
    });
  }
  
  @override
  Widget build(BuildContext context) {
    if (!widget.delivery.isScheduled || widget.delivery.scheduledPickupTime == null) {
      return const SizedBox.shrink();
    }
    
    final now = DateTime.now();
    final scheduledTime = widget.delivery.scheduledPickupTime!;
    final minutesUntil = scheduledTime.difference(now).inMinutes;
    
    if (minutesUntil < -60) {
      return const SizedBox.shrink(); // Don't show if more than 1 hour late
    }
    
    Color backgroundColor;
    Color textColor;
    IconData icon;
    
    if (minutesUntil < 0) {
      backgroundColor = Colors.red.shade100;
      textColor = Colors.red.shade900;
      icon = Icons.error;
    } else if (minutesUntil <= 10) {
      backgroundColor = Colors.orange.shade100;
      textColor = Colors.orange.shade900;
      icon = Icons.warning_amber;
    } else {
      backgroundColor = Colors.green.shade100;
      textColor = Colors.green.shade900;
      icon = Icons.check_circle;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: textColor, size: 16),
          const SizedBox(width: 6),
          Text(
            minutesUntil < 0 
                ? '${-minutesUntil}m late' 
                : '${minutesUntil}m until pickup',
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
