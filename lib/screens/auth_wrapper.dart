import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_config.dart';
import '../core/app_assets.dart';
import '../services/auth_service.dart';
import '../services/optimized_state_manager.dart';
import '../services/navigation_manager.dart';
import '../widgets/optimized_state_widgets.dart';
import 'login_screen.dart';
import 'main_map_screen.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final _authService = AuthService();
  final AuthStateManager _authStateManager = AuthStateManager.instance;

  @override
  void initState() {
    super.initState();
    _initializeAuthState();
  }

  void _initializeAuthState() {
    // Listen to auth state changes and update state manager
    _authService.authStateChanges.listen((authState) {
      _authStateManager.updateAuthState(authState);
      _checkDriverVerification(authState);
    });
  }

  Future<void> _checkDriverVerification(AuthState authState) async {
    if (authState.session != null) {
      _authStateManager.setLoading(true);
      try {
        final isDriver = await _authService.isCurrentUserDriver();
        _authStateManager.setDriverVerified(isDriver);
        _authStateManager.clearError();
      } catch (e) {
        _authStateManager.setError('Failed to verify driver status: $e');
      } finally {
        _authStateManager.setLoading(false);
      }
    } else {
      _authStateManager.setDriverVerified(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return NavigationWrapper(
      isMainFlow: false,
      child: MultiValueListenable(
        notifiers: [
          _authStateManager.authStateNotifier,
          _authStateManager.isLoadingNotifier,
          _authStateManager.isDriverVerifiedNotifier,
          _authStateManager.errorNotifier,
        ],
        builder: (context) {
          final authState = _authStateManager.authState;
          final isLoading = _authStateManager.isLoading;
          final isDriverVerified = _authStateManager.isDriverVerified;
          final error = _authStateManager.error;

          // Show loading spinner while checking auth state
          if (isLoading || authState == null) {
            return _buildLoadingScreen();
          }

          // Handle error states
          if (error != null) {
            return _buildErrorScreen(error);
          }

          // Check if user is logged in
          final session = authState.session;
          
          if (session != null) {
            if (isDriverVerified) {
              // User is a verified driver, show main app
              return const MainMapScreen();
            } else {
              // User is not a driver, show error and logout
              return _buildNotDriverScreen();
            }
          } else {
            // User is not logged in, show login screen
            return const LoginScreen();
          }
        },
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return const Scaffold(
      backgroundColor: SwiftDashColors.backgroundGrey,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: SwiftDashColors.darkBlue,
            ),
            SizedBox(height: 16),
            Text(
              'Checking authentication...',
              style: TextStyle(
                color: SwiftDashColors.textGrey,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorScreen(String error) {
    return Scaffold(
      backgroundColor: SwiftDashColors.backgroundGrey,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: SwiftDashColors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: SwiftDashColors.darkBlue.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: SwiftDashColors.dangerRed,
                      size: 64,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Authentication Error',
                      style: TextStyle(
                        color: SwiftDashColors.darkBlue,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      error,
                      style: TextStyle(
                        color: SwiftDashColors.textGrey,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          _authStateManager.clearError();
                          _initializeAuthState();
                        },
                        child: const Text('Retry'),
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
                    // SwiftDash Logo
                    Container(
                      width: 100,
                      height: 100,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: SwiftDashColors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: SwiftDashColors.lightBlue.withOpacity(0.3),
                          width: 2,
                        ),
                      ),
                      child: Image.asset(
                        AppAssets.logo,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [SwiftDashColors.darkBlue, SwiftDashColors.lightBlue],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.local_shipping,
                              color: SwiftDashColors.white,
                              size: 30,
                            ),
                          );
                        },
                      ),
                    ),
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
                        onPressed: _authStateManager.isLoading ? null : () async {
                          _authStateManager.setLoading(true);
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
                            _authStateManager.setError('Sign out failed: $e');
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
                          } finally {
                            _authStateManager.setLoading(false);
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
                        onPressed: _authStateManager.isLoading ? null : () async {
                          _authStateManager.setLoading(true);
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
                            _authStateManager.setError('Force sign out failed: $e');
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('❌ Force sign out failed: $e'),
                                  backgroundColor: Colors.red,
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                            }
                          } finally {
                            _authStateManager.setLoading(false);
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