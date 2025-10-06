import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_config.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'main_map_screen.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final _authService = AuthService();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: _authService.authStateChanges,
      builder: (context, snapshot) {
        // Show loading spinner while checking auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: SwiftDashColors.backgroundGrey,
            body: Center(
              child: CircularProgressIndicator(
                color: SwiftDashColors.darkBlue,
              ),
            ),
          );
        }

        // Check if user is logged in
        final session = snapshot.hasData ? snapshot.data!.session : null;
        
        if (session != null) {
          // User is logged in, but we need to verify they're a driver
          return FutureBuilder<bool>(
            future: _authService.isCurrentUserDriver(),
            builder: (context, driverSnapshot) {
              if (driverSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  backgroundColor: SwiftDashColors.backgroundGrey,
                  body: Center(
                    child: CircularProgressIndicator(
                      color: SwiftDashColors.darkBlue,
                    ),
                  ),
                );
              }
              
              if (driverSnapshot.data == true) {
                // User is a verified driver, show main app
                return const MainMapScreen();
              } else {
                // User is not a driver, show error and logout
                return _buildNotDriverScreen();
              }
            },
          );
        } else {
          // User is not logged in, show login screen
          return const LoginScreen();
        }
      },
    );
  }
  
  Widget _buildNotDriverScreen() {
    return Scaffold(
      backgroundColor: SwiftDashColors.backgroundGrey,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: SwiftDashColors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: SwiftDashColors.darkBlue.withOpacity(0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: SwiftDashColors.dangerRed.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        Icons.error_outline,
                        color: SwiftDashColors.dangerRed,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Access Denied',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: SwiftDashColors.darkBlue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'This account is not registered as a driver. Please use the customer app or contact support to register as a driver.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: SwiftDashColors.textGrey,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    Container(
                      width: double.infinity,
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [SwiftDashColors.dangerRed, SwiftDashColors.dangerRed.withOpacity(0.8)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ElevatedButton(
                        onPressed: () async {
                          try {
                            // Show loading indicator
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Signing out...'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                            
                            await _authService.signOut();
                            
                            // Show success message
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('✅ Signed out successfully'),
                                  backgroundColor: Colors.green,
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
                          } catch (e) {
                            // Show error message but still try to navigate
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('⚠️ Sign out error: $e'),
                                  backgroundColor: Colors.orange,
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                            }
                            print('Sign out error: $e');
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Sign Out',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: SwiftDashColors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // Force Sign Out Button (Emergency)
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.grey[600]!, Colors.grey[700]!],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ElevatedButton(
                        onPressed: () async {
                          try {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Force signing out...'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                            
                            await _authService.forceSignOut();
                            
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('✅ Force sign out successful'),
                                  backgroundColor: Colors.green,
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('❌ Force sign out failed: $e'),
                                  backgroundColor: Colors.red,
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Force Sign Out',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: SwiftDashColors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}