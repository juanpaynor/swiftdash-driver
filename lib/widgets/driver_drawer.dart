import 'package:flutter/material.dart';
import '../models/driver.dart';
import '../services/auth_service.dart';
import '../core/supabase_config.dart';
import '../screens/edit_profile_screen.dart';

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
                _buildDrawerItem(
                  icon: Icons.person,
                  title: 'Driver Profile',
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const EditProfileScreen(),
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
                  title: 'Settings',
                  onTap: () {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Settings coming soon!')),
                    );
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
}