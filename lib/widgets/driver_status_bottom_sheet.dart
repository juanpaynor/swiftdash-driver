import 'package:flutter/material.dart';
import '../models/driver.dart';
import '../services/driver_flow_service.dart';
import '../core/supabase_config.dart';

class DriverStatusBottomSheet extends StatefulWidget {
  final DriverFlowService driverFlowService;
  
  const DriverStatusBottomSheet({
    super.key,
    required this.driverFlowService,
  });

  @override
  State<DriverStatusBottomSheet> createState() => _DriverStatusBottomSheetState();
}

class _DriverStatusBottomSheetState extends State<DriverStatusBottomSheet>
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
            height: MediaQuery.of(context).size.height * 0.35,
            decoration: const BoxDecoration(
              color: SwiftDashColors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: FutureBuilder<void>(
              future: widget.driverFlowService.initialize(),
              builder: (context, snapshot) {
                final driver = widget.driverFlowService.currentDriver;
                final isOnline = driver?.isOnline == true;
                
                return Column(
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
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: isOnline ? Colors.green : Colors.red,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            isOnline ? 'You\'re Online' : 'You\'re Offline',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: SwiftDashColors.darkBlue,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // Status Content
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          children: [
                            if (isOnline) ...[
                              _buildOnlineContent(driver!),
                            ] else ...[
                              _buildOfflineContent(),
                            ],
                            
                            const Spacer(),
                            
                            // Action Button
                            SizedBox(
                              width: double.infinity,
                              height: 56,
                              child: ElevatedButton(
                                onPressed: () {
                                  _toggleStatus();
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isOnline 
                                      ? Colors.red 
                                      : SwiftDashColors.lightBlue,
                                  foregroundColor: SwiftDashColors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  isOnline ? 'Go Offline' : 'Go Online',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildOnlineContent(Driver driver) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(
                Icons.check_circle,
                color: Colors.green,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ready for deliveries',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: SwiftDashColors.darkBlue,
                      ),
                    ),
                    Text(
                      'You\'ll receive delivery offers nearby',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Today's Stats
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'Deliveries',
                '${driver.totalDeliveries}',
                Icons.local_shipping,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                'Earnings',
                '\$${(driver.rating * 10).toStringAsFixed(2)}',
                Icons.attach_money,
              ),
            ),
          ],
        ),
      ],
    );
  }
  
  Widget _buildOfflineContent() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(
                Icons.pause_circle,
                color: Colors.orange,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'You\'re offline',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: SwiftDashColors.darkBlue,
                      ),
                    ),
                    Text(
                      'Go online to start receiving delivery offers',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 16),
        
        Text(
          'When you\'re online, you\'ll see delivery opportunities on the map',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 14,
          ),
        ),
      ],
    );
  }
  
  Widget _buildStatCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SwiftDashColors.lightBlue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: SwiftDashColors.lightBlue,
            size: 20,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: SwiftDashColors.darkBlue,
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
  
  void _toggleStatus() async {
    try {
      final currentDriver = widget.driverFlowService.currentDriver;
      if (currentDriver?.isOnline == true) {
        await widget.driverFlowService.goOffline(context);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You\'re now offline'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        final success = await widget.driverFlowService.goOnline(context);
        if (mounted) {
          if (success) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('You\'re now online and ready for deliveries!'),
                backgroundColor: Colors.green,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Failed to go online. Please check your location permissions.'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}