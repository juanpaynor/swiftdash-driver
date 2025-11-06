import 'package:flutter/material.dart';
import '../models/driver.dart';
import '../services/auth_service.dart';
import '../services/driver_flow_service.dart';
import '../services/delivery_offer_notification_service.dart';
import '../core/supabase_config.dart';
import '../screens/improved_edit_profile_screen.dart';
import '../screens/navigation_settings_screen.dart';

class DriverDrawer extends StatelessWidget {
  const DriverDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: SwiftDashColors.darkBlue,
      child: Column(
        children: [
          // Drawer Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 60, 16, 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  SwiftDashColors.darkBlue,
                  SwiftDashColors.lightBlue,
                ],
              ),
            ),
            child: FutureBuilder<Driver?>(
              future: AuthService().getCurrentDriverProfile(),
              builder: (context, snapshot) {
                final driver = snapshot.data;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: SwiftDashColors.white.withOpacity(0.2),
                      child: driver?.profileImageUrl != null
                          ? ClipOval(
                              child: Image.network(
                                driver!.profileImageUrl!,
                                width: 64,
                                height: 64,
                                fit: BoxFit.cover,
                              ),
                            )
                          : Text(
                              driver?.firstName.substring(0, 1).toUpperCase() ?? 'D',
                              style: const TextStyle(
                                color: SwiftDashColors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      driver?.fullName ?? 'Driver',
                      style: const TextStyle(
                        color: SwiftDashColors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.star,
                          color: Colors.amber,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${driver?.rating.toStringAsFixed(1) ?? '0.0'}',
                          style: TextStyle(
                            color: SwiftDashColors.white.withOpacity(0.8),
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${driver?.totalDeliveries ?? 0} deliveries',
                          style: TextStyle(
                            color: SwiftDashColors.white.withOpacity(0.8),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
          
          // Menu Items
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                // Active Delivery Item (conditionally shown)
                FutureBuilder<bool>(
                  future: _checkActiveDelivery(),
                  builder: (context, snapshot) {
                    final hasActiveDelivery = snapshot.data == true;
                    
                    if (!hasActiveDelivery) return const SizedBox.shrink();
                    
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [SwiftDashColors.successGreen, SwiftDashColors.successGreen.withOpacity(0.8)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: SwiftDashColors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.local_shipping,
                            color: SwiftDashColors.white,
                            size: 20,
                          ),
                        ),
                        title: const Text(
                          'Active Delivery',
                          style: TextStyle(
                            color: SwiftDashColors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: const Text(
                          'Continue your delivery',
                          style: TextStyle(
                            color: SwiftDashColors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                        trailing: const Icon(
                          Icons.arrow_forward_ios,
                          color: SwiftDashColors.white,
                          size: 16,
                        ),
                        onTap: () async {
                          Navigator.of(context).pop();
                          await _navigateToActiveDelivery(context);
                        },
                      ),
                    );
                  },
                ),
                
                const Divider(color: SwiftDashColors.lightBlue, thickness: 1),
                
                _buildDrawerItem(
                  icon: Icons.person,
                  title: 'Driver Profile',
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const ImprovedEditProfileScreen(),
                      ),
                    );
                  },
                ),
                _buildDrawerItem(
                  icon: Icons.account_balance_wallet,
                  title: 'Payout Options',
                  onTap: () {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Payout options coming soon!')),
                    );
                  },
                ),
                _buildDrawerItem(
                  icon: Icons.history,
                  title: 'Delivery History',
                  onTap: () {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Delivery history coming soon!')),
                    );
                  },
                ),
                _buildDrawerItem(
                  icon: Icons.help_outline,
                  title: 'Help & Support',
                  onTap: () {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Help & support coming soon!')),
                    );
                  },
                ),
                _buildDrawerItem(
                  icon: Icons.settings,
                  title: 'Navigation Settings',
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const NavigationSettingsScreen(),
                      ),
                    );
                  },
                ),
                _buildDrawerItem(
                  icon: Icons.notification_add,
                  title: '🧪 Test Notification',
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _testNotification(context);
                  },
                ),
                const Divider(color: SwiftDashColors.lightBlue),
                _buildDrawerItem(
                  icon: Icons.logout,
                  title: 'Logout',
                  onTap: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Logout'),
                        content: const Text('Are you sure you want to logout?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text('Logout'),
                          ),
                        ],
                      ),
                    );
                    
                    if (confirmed == true) {
                      await AuthService().signOut();
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: SwiftDashColors.white,
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: SwiftDashColors.white,
          fontSize: 16,
        ),
      ),
      onTap: onTap,
      hoverColor: SwiftDashColors.lightBlue.withOpacity(0.1),
      splashColor: SwiftDashColors.lightBlue.withOpacity(0.2),
    );
  }

  /// Check if driver has an active delivery
  Future<bool> _checkActiveDelivery() async {
    try {
      final driverFlow = DriverFlowService();
      await driverFlow.initialize();
      return driverFlow.hasActiveDelivery;
    } catch (e) {
      print('Error checking active delivery: $e');
      return false;
    }
  }

  /// Navigate to active delivery screen
  Future<void> _navigateToActiveDelivery(BuildContext context) async {
    try {
      // Check if widget is still mounted before any async operations
      if (!context.mounted) return;
      
      final driverFlow = DriverFlowService();
      await driverFlow.initialize();
      
      // Check if widget is still mounted after async operation
      if (!context.mounted) return;
      
      // DEPRECATED: Navigation to EnhancedActiveDeliveryScreen removed
      // Active deliveries now shown on main_map_screen
      final activeDelivery = driverFlow.activeDelivery;
      if (driverFlow.hasActiveDelivery && activeDelivery != null) {
        print('⚠️ Active Delivery navigation tapped but deprecated');
        // Close drawer instead
        if (context.mounted) {
          Navigator.of(context).pop();
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No active delivery found'),
              backgroundColor: SwiftDashColors.warningOrange,
            ),
          );
        }
      }
    } catch (e) {
      print('Error navigating to active delivery: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error accessing active delivery: $e'),
            backgroundColor: SwiftDashColors.dangerRed,
          ),
        );
      }
    }
  }

  /// Test notification functionality
  static Future<void> _testNotification(BuildContext context) async {
    try {
      // Show loading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              SizedBox(width: 12),
              Text('Sending test notification...'),
            ],
          ),
          duration: Duration(seconds: 2),
        ),
      );

      // Send test notification
      await DeliveryOfferNotificationService.showOfferNotification(
        deliveryId: 'TEST-${DateTime.now().millisecondsSinceEpoch}',
        customerName: 'Test Customer',
        totalPrice: 200.00,
        driverEarnings: 125.50,
        distance: 5.2,
        pickupAddress: '123 Test Street, Manila City',
        deliveryAddress: '456 Delivery Avenue, Makati City',
      );

      // Show success message
      await Future.delayed(const Duration(milliseconds: 500));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '✅ Test notification sent! You should see it now (even if you minimize the app)',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to send test notification: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
}