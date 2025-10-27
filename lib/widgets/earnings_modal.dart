import 'package:flutter/material.dart';
import '../services/driver_flow_service.dart';
import '../core/supabase_config.dart';

class EarningsModal extends StatefulWidget {
  final DriverFlowService driverFlowService;

  const EarningsModal({
    super.key,
    required this.driverFlowService,
  });

  @override
  State<EarningsModal> createState() => _EarningsModalState();
}

class _EarningsModalState extends State<EarningsModal>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _slideAnimation,
      builder: (context, child) {
        return FractionalTranslation(
          translation: Offset(0, 1 - _slideAnimation.value),
          child: Container(
            height: MediaQuery.of(context).size.height * 0.75,
            decoration: const BoxDecoration(
              color: SwiftDashColors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Column(
              children: [
                // Handle
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                
                // Header
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      const Text(
                        'Earnings',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: SwiftDashColors.darkBlue,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                        color: Colors.grey[600],
                      ),
                    ],
                  ),
                ),
                
                // Content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: FutureBuilder<void>(
                      future: widget.driverFlowService.initialize(),
                      builder: (context, snapshot) {
                        final driver = widget.driverFlowService.currentDriver;
                        
                        if (driver == null) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Today's earnings card
                            _buildEarningsCard(
                              'Today\'s Earnings',
                              '₱${(driver.rating * 15.5).toStringAsFixed(2)}', // Mock today's earnings
                              '${driver.totalDeliveries > 10 ? 5 : driver.totalDeliveries % 3} deliveries completed',
                              SwiftDashColors.lightBlue,
                              Icons.today,
                            ),
                            
                            const SizedBox(height: 16),
                            
                            // This week's earnings
                            _buildEarningsCard(
                              'This Week',
                              '₱${(driver.rating * 85.75).toStringAsFixed(2)}', // Mock week earnings
                              '${driver.totalDeliveries > 20 ? 23 : driver.totalDeliveries + 8} total deliveries',
                              Colors.green,
                              Icons.calendar_view_week,
                            ),
                            
                            const SizedBox(height: 16),
                            
                            // Total earnings
                            _buildEarningsCard(
                              'Total Earnings',
                              '₱${(driver.totalDeliveries * 12.5 + driver.rating * 45).toStringAsFixed(2)}',
                              '${driver.totalDeliveries} lifetime deliveries',
                              SwiftDashColors.darkBlue,
                              Icons.account_balance_wallet,
                            ),
                            
                            const SizedBox(height: 24),
                            
                            // Performance metrics
                            const Text(
                              'Performance',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: SwiftDashColors.darkBlue,
                              ),
                            ),
                            const SizedBox(height: 12),
                            
                            Row(
                              children: [
                                Expanded(
                                  child: _buildMetricCard(
                                    'Rating',
                                    '${driver.rating.toStringAsFixed(1)}',
                                    Icons.star,
                                    Colors.amber,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildMetricCard(
                                    'Acceptance',
                                    '${(driver.rating * 20).toInt()}%', // Mock acceptance rate
                                    Icons.check_circle,
                                    Colors.green,
                                  ),
                                ),
                              ],
                            ),
                            
                            const SizedBox(height: 12),
                            
                            Row(
                              children: [
                                Expanded(
                                  child: _buildMetricCard(
                                    'Completion',
                                    '${(95 + driver.rating).toInt()}%', // Mock completion rate
                                    Icons.done_all,
                                    SwiftDashColors.lightBlue,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildMetricCard(
                                    'On Time',
                                    '${(88 + driver.rating * 2).toInt()}%', // Mock on-time rate
                                    Icons.schedule,
                                    Colors.orange,
                                  ),
                                ),
                              ],
                            ),
                            
                            const SizedBox(height: 24),
                            
                            // Payout information
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey[200]!),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.info_outline,
                                        color: SwiftDashColors.lightBlue,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      const Text(
                                        'Payout Information',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: SwiftDashColors.darkBlue,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Earnings are paid out weekly on Fridays. You can update your payout method in the driver profile settings.',
                                    style: TextStyle(
                                      color: Colors.grey[700],
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            
                            const SizedBox(height: 24),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildEarningsCard(
    String title,
    String amount,
    String subtitle,
    Color color,
    IconData icon,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withOpacity(0.1),
            color.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: color,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  amount,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildMetricCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: color,
            size: 24,
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}