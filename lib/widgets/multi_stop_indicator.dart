import 'package:flutter/material.dart';
import '../models/delivery.dart';

/// Badge to display multi-stop delivery indicator
class MultiStopIndicator extends StatelessWidget {
  final Delivery delivery;
  final double fontSize;
  
  const MultiStopIndicator({
    super.key,
    required this.delivery,
    this.fontSize = 12,
  });
  
  @override
  Widget build(BuildContext context) {
    if (!delivery.isMultiStop || delivery.totalStops <= 1) {
      return const SizedBox.shrink();
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.blue.shade100,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blue.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.location_on,
            color: Colors.blue.shade700,
            size: fontSize + 4,
          ),
          const SizedBox(width: 4),
          Text(
            '${delivery.totalStops} STOPS',
            style: TextStyle(
              color: Colors.blue.shade700,
              fontWeight: FontWeight.bold,
              fontSize: fontSize,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Expanded multi-stop details card
class MultiStopDetailsCard extends StatelessWidget {
  final Delivery delivery;
  
  const MultiStopDetailsCard({
    super.key,
    required this.delivery,
  });
  
  @override
  Widget build(BuildContext context) {
    if (!delivery.isMultiStop) {
      return const SizedBox.shrink();
    }
    
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.route, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Text(
                  'Multi-Stop Delivery',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              icon: Icons.store,
              label: 'Pickup Locations',
              value: '1',
              color: Colors.orange,
            ),
            const SizedBox(height: 8),
            _buildInfoRow(
              icon: Icons.home,
              label: 'Drop-off Locations',
              value: '${delivery.totalStops - 1}',
              color: Colors.green,
            ),
            const SizedBox(height: 8),
            _buildInfoRow(
              icon: Icons.route,
              label: 'Total Distance',
              value: delivery.formattedDistance,
              color: Colors.blue,
            ),
            const Divider(height: 24),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.amber.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Complete each stop sequentially with proof of delivery',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.amber.shade900,
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
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 14)),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
