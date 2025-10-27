import 'package:flutter/material.dart';
import '../models/delivery_stop.dart';
import '../core/supabase_config.dart';

/// Multi-Stop Badge - Shows number of stops
class MultiStopBadge extends StatelessWidget {
  final int totalStops;
  final Color? backgroundColor;
  final Color? textColor;

  const MultiStopBadge({
    super.key,
    required this.totalStops,
    this.backgroundColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            backgroundColor ?? SwiftDashColors.lightBlue,
            (backgroundColor ?? SwiftDashColors.lightBlue).withOpacity(0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: (backgroundColor ?? SwiftDashColors.lightBlue).withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.route,
            size: 14,
            color: textColor ?? Colors.white,
          ),
          const SizedBox(width: 4),
          Text(
            '$totalStops STOPS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: textColor ?? Colors.white,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Progress Indicator - Shows completion progress
class StopProgressIndicator extends StatelessWidget {
  final List<DeliveryStop> stops;
  final bool showPercentage;

  const StopProgressIndicator({
    super.key,
    required this.stops,
    this.showPercentage = true,
  });

  @override
  Widget build(BuildContext context) {
    final completedCount = stops.where((s) => s.status == DeliveryStopStatus.completed).length;
    final totalCount = stops.length;
    final progress = totalCount > 0 ? completedCount / totalCount : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation<Color>(
                    progress == 1.0 ? SwiftDashColors.successGreen : SwiftDashColors.lightBlue,
                  ),
                  minHeight: 8,
                ),
              ),
            ),
            if (showPercentage) ...[
              const SizedBox(width: 12),
              Text(
                '$completedCount of $totalCount',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ],
        ),
        if (!showPercentage) ...[
          const SizedBox(height: 4),
          Text(
            '$completedCount of $totalCount stops completed',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ],
    );
  }
}

/// Stop List Item - Individual stop display
class StopListItem extends StatelessWidget {
  final DeliveryStop stop;
  final bool isCurrent;
  final VoidCallback? onNavigate;
  final VoidCallback? onArrived;
  final VoidCallback? onComplete;
  final VoidCallback? onCustomerNotAvailable;

  const StopListItem({
    super.key,
    required this.stop,
    this.isCurrent = false,
    this.onNavigate,
    this.onArrived,
    this.onComplete,
    this.onCustomerNotAvailable,
  });

  IconData get _statusIcon {
    switch (stop.status) {
      case DeliveryStopStatus.completed:
        return Icons.check_circle;
      case DeliveryStopStatus.inProgress:
        return Icons.navigation;
      case DeliveryStopStatus.failed:
        return Icons.cancel;
      default:
        return Icons.radio_button_unchecked;
    }
  }

  Color get _statusColor {
    switch (stop.status) {
      case DeliveryStopStatus.completed:
        return SwiftDashColors.successGreen;
      case DeliveryStopStatus.inProgress:
        return SwiftDashColors.lightBlue;
      case DeliveryStopStatus.failed:
        return SwiftDashColors.dangerRed;
      default:
        return Colors.grey[400]!;
    }
  }

  String get _stopTypeLabel {
    return stop.stopType == 'pickup' ? 'PICKUP' : 'DROP-OFF';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isCurrent ? SwiftDashColors.lightBlue.withOpacity(0.1) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCurrent ? SwiftDashColors.lightBlue : Colors.grey[200]!,
          width: isCurrent ? 2 : 1,
        ),
        boxShadow: isCurrent
            ? [
                BoxShadow(
                  color: SwiftDashColors.lightBlue.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Stop number, type, status
            Row(
              children: [
                // Status icon
                Icon(_statusIcon, color: _statusColor, size: 24),
                const SizedBox(width: 8),
                
                // Stop info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Stop ${stop.stopNumber}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: SwiftDashColors.darkBlue,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: stop.stopType == 'pickup'
                                  ? Colors.green.withOpacity(0.2)
                                  : Colors.orange.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _stopTypeLabel,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: stop.stopType == 'pickup' ? Colors.green[800] : Colors.orange[800],
                              ),
                            ),
                          ),
                          if (isCurrent) ...[
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.arrow_forward,
                              size: 14,
                              color: SwiftDashColors.lightBlue,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        stop.address,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[700],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            // Recipient info (if available)
            if (stop.contactName.isNotEmpty || stop.contactPhone.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.person_outline, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    stop.contactName.isEmpty ? 'No name' : stop.contactName,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  if (stop.contactPhone.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Icon(Icons.phone_outlined, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      stop.contactPhone,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ],
              ),
            ],
            
            // Delivery notes
            if (stop.instructions != null && stop.instructions!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.amber.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 14, color: Colors.amber),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        stop.instructions!,
                        style: const TextStyle(fontSize: 12, color: Colors.black87),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            
            // Action buttons (only for current stop)
            if (isCurrent && stop.status != DeliveryStopStatus.completed && stop.status != DeliveryStopStatus.failed) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  if (stop.status == DeliveryStopStatus.pending) ...[
                    // Navigate button
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onNavigate,
                        icon: const Icon(Icons.navigation, size: 16),
                        label: const Text('Navigate'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: SwiftDashColors.lightBlue,
                          side: const BorderSide(color: SwiftDashColors.lightBlue),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Arrived button
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: onArrived,
                        icon: const Icon(Icons.location_on, size: 16),
                        label: const Text('Arrived'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: SwiftDashColors.lightBlue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ] else if (stop.status == DeliveryStopStatus.inProgress) ...[
                    // Complete button
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: onComplete,
                        icon: const Icon(Icons.check_circle, size: 16),
                        label: Text(
                          stop.stopType == 'pickup' ? 'Package Received' : 'Delivered',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: SwiftDashColors.successGreen,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Customer not available button (dropoffs only)
                    if (stop.stopType == 'dropoff')
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onCustomerNotAvailable,
                          icon: const Icon(Icons.person_off, size: 16),
                          label: const Text('Not Available'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: SwiftDashColors.dangerRed,
                            side: const BorderSide(color: SwiftDashColors.dangerRed),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Complete Stop List Widget
class StopListWidget extends StatelessWidget {
  final List<DeliveryStop> stops;
  final int? currentStopIndex;
  final Function(DeliveryStop)? onNavigate;
  final Function(DeliveryStop)? onArrived;
  final Function(DeliveryStop)? onComplete;
  final Function(DeliveryStop)? onCustomerNotAvailable;

  const StopListWidget({
    super.key,
    required this.stops,
    this.currentStopIndex,
    this.onNavigate,
    this.onArrived,
    this.onComplete,
    this.onCustomerNotAvailable,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: stops.length,
      itemBuilder: (context, index) {
        final stop = stops[index];
        final isCurrent = currentStopIndex != null && stop.stopNumber == currentStopIndex! + 1;
        
        return StopListItem(
          stop: stop,
          isCurrent: isCurrent,
          onNavigate: onNavigate != null ? () => onNavigate!(stop) : null,
          onArrived: onArrived != null ? () => onArrived!(stop) : null,
          onComplete: onComplete != null ? () => onComplete!(stop) : null,
          onCustomerNotAvailable: onCustomerNotAvailable != null ? () => onCustomerNotAvailable!(stop) : null,
        );
      },
    );
  }
}

/// Customer Not Available Dialog
Future<Map<String, dynamic>?> showCustomerNotAvailableDialog(BuildContext context) async {
  String? selectedReason;
  final TextEditingController otherReasonController = TextEditingController();

  final reasons = [
    'Customer not home',
    'Wrong address',
    'Customer refused package',
    'Access denied to building',
    'Other',
  ];

  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.person_off, color: SwiftDashColors.dangerRed),
            SizedBox(width: 8),
            Text('Customer Not Available'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select a reason for not completing this delivery:',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              ...reasons.map((reason) => RadioListTile<String>(
                    value: reason,
                    groupValue: selectedReason,
                    onChanged: (value) {
                      setState(() {
                        selectedReason = value;
                      });
                    },
                    title: Text(reason, style: const TextStyle(fontSize: 14)),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  )),
              if (selectedReason == 'Other') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: otherReasonController,
                  decoration: const InputDecoration(
                    labelText: 'Specify reason',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  maxLines: 2,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: selectedReason == null
                ? null
                : () {
                    final reason = selectedReason == 'Other'
                        ? otherReasonController.text.trim()
                        : selectedReason!;
                    
                    if (selectedReason == 'Other' && reason.isEmpty) {
                      return;
                    }
                    
                    Navigator.of(context).pop({
                      'reason': reason,
                      'timestamp': DateTime.now().toIso8601String(),
                    });
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: SwiftDashColors.dangerRed,
              foregroundColor: Colors.white,
            ),
            child: const Text('Mark as Failed'),
          ),
        ],
      ),
    ),
  );
}
