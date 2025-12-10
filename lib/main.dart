import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'core/supabase_config.dart';
import 'core/mapbox_config.dart';
import 'screens/auth_wrapper.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/main_map_screen.dart';
import 'services/background_location_service.dart';
import 'screens/delivery_debug_screen.dart';
import 'screens/debug_vehicle_types_screen.dart';
import 'services/auth_service.dart';
import 'services/driver_flow_service.dart';
import 'models/driver.dart';
import 'models/delivery.dart';
import 'screens/improved_delivery_offers_screen.dart';
import 'services/optimized_location_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'screens/edit_profile_screen.dart';
import 'widgets/background_service_status_widget.dart';
import 'services/device_compatibility_service.dart';
import 'services/navigation_manager.dart';
import 'services/optimized_state_manager.dart';
import 'services/delivery_offer_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  try {
    await dotenv.load(fileName: ".env");
    print('✅ Environment variables loaded');
  } catch (e) {
    print('⚠️ Failed to load .env file: $e');
    print('⚠️ Ably features will not be available');
  }

  // Initialize Supabase
  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    anonKey: SupabaseConfig.supabaseAnonKey,
  );

  // Initialize Mapbox
  MapboxOptions.setAccessToken(MapboxConfig.accessToken);

  runApp(const MyApp());

  WidgetsBinding.instance.addPostFrameCallback((_) {
    _initializeServicesInBackground();
  });
}

/// Initialize services in background after app UI is ready (non-blocking)
Future<void> _initializeServicesInBackground() async {
  // Initialize Ably (if API key available) - non-blocking
  _initAbly();

  // Initialize state managers - non-blocking
  _initStateManagers();

  // Check device compatibility and initialize background service - non-blocking
  _initBackgroundServices();

  // Initialize delivery offer notification service - non-blocking
  _initDeliveryOfferNotifications();
}

/// Initialize Ably service in background
/// 🔧 PERFORMANCE FIX: Lazy initialization - only connect when driver goes online
void _initAbly() {
  // Don't initialize Ably on startup - it will connect when driver goes online
  // This saves 1-2 seconds of startup time and prevents network blocking
  print('⏭️ Ably initialization deferred until driver goes online');

  // Just validate the API key is available
  final ablyKey = dotenv.env['ABLY_CLIENT_KEY'];
  if (ablyKey == null || ablyKey.isEmpty) {
    print('⚠️ ABLY_CLIENT_KEY not found in .env file');
    print('⚠️ Ably real-time tracking will not be available');
  }
}

/// Initialize state managers in background
void _initStateManagers() {
  Future(() async {
    try {
      print('🚀 Initializing state managers...');
      await DriverStateManager.instance.initialize();
      print('✅ Driver state manager initialized');
    } catch (e) {
      print('⚠️ Driver state manager initialization failed: $e');
    }
  });
}

/// Initialize background location services
void _initBackgroundServices() {
  Future(() async {
    try {
      print('🔍 Checking device compatibility...');
      final deviceCompatibility = DeviceCompatibilityService.instance;
      final isCompatible = await deviceCompatibility.checkDeviceCompatibility();

      if (isCompatible) {
        // ✅ Background service enabled for delivery continuity
        print('✅ Device compatible - initializing background location service');
        try {
          await BackgroundLocationService.initializeService();
          print(
            '✅ Background service initialized - app will run in background',
          );
        } catch (e) {
          print('⚠️ Background service initialization failed: $e');
          print('🔄 Falling back to OptimizedLocationService');
        }
      } else {
        print('⚠️ Device has compatibility issues with background services');
        print('📱 Device info: ${deviceCompatibility.deviceInfo}');
        print(
          '🔄 App will use fallback location strategy: ${deviceCompatibility.getFallbackStrategy()}',
        );
      }
    } catch (e) {
      print('❌ Background service check failed: $e');
      print('🔄 App will continue with OptimizedLocationService');
    }
  });
}

/// Initialize delivery offer notification service
void _initDeliveryOfferNotifications() {
  Future(() async {
    try {
      print('🔔 Initializing delivery offer notifications...');
      await DeliveryOfferNotificationService.initialize();
      print('✅ Delivery offer notifications ready');
    } catch (e) {
      print('⚠️ Failed to initialize delivery offer notifications: $e');
      print('🔄 App will continue without background offer notifications');
    }
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: NavigationManager.navigatorKey,
      title: 'SwiftDash Driver',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: SwiftDashColors.darkBlue,
          brightness: Brightness.light,
          primary: SwiftDashColors.darkBlue,
          secondary: SwiftDashColors.lightBlue,
          surface: SwiftDashColors.white,
          background: SwiftDashColors.backgroundGrey,
        ),
        useMaterial3: true,
        appBarTheme: AppBarTheme(
          backgroundColor: SwiftDashColors.darkBlue,
          foregroundColor: SwiftDashColors.white,
          elevation: 0,
          centerTitle: true,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: SwiftDashColors.darkBlue,
            foregroundColor: SwiftDashColors.white,
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        ),
        cardTheme: const CardThemeData(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
          margin: EdgeInsets.all(8),
        ),
      ),
      home: const AppLifecycleManager(child: AuthWrapper()),
      routes: {
        '/login': (context) => const LoginScreen(),
        '/signup': (context) => const SignupScreen(),
        '/dashboard': (context) => const DriverDashboard(),
        '/map': (context) => const MainMapScreen(),
      },
      debugShowCheckedModeBanner: false,
    );
  }
}

class DriverDashboard extends StatefulWidget {
  const DriverDashboard({super.key});

  @override
  State<DriverDashboard> createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard> {
  bool isOnline = false;
  Driver? currentDriver;
  final AuthService _authService = AuthService();
  final DriverFlowService _driverFlow = DriverFlowService();
  bool isLoading = true;
  bool _isUpdatingStatus = false;

  @override
  void initState() {
    super.initState();
    _initializeDashboard();
  }

  Future<void> _initializeDashboard() async {
    try {
      await _driverFlow.initialize();
      final driver = await _authService.getCurrentDriverProfile();
      setState(() {
        currentDriver = driver;
        isOnline = driver?.isOnline ?? false;
        isLoading = false;
      });
    } catch (e) {
      print('Error loading driver profile: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _toggleOnlineStatus() async {
    if (currentDriver == null || _isUpdatingStatus) return;

    setState(() => _isUpdatingStatus = true);

    try {
      final newStatus = !isOnline;

      bool success;
      if (newStatus) {
        success = await _driverFlow.goOnline(context);
      } else {
        success = await _driverFlow.goOffline(context);
      }

      if (success) {
        setState(() {
          isOnline = newStatus;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update status: $e'),
          backgroundColor: SwiftDashColors.dangerRed,
        ),
      );
    } finally {
      setState(() => _isUpdatingStatus = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        backgroundColor: SwiftDashColors.backgroundGrey,
        appBar: AppBar(
          title: Row(
            children: [
              Icon(Icons.local_shipping, color: SwiftDashColors.white),
              const SizedBox(width: 8),
              const Text('SwiftDash Driver'),
            ],
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: SwiftDashColors.backgroundGrey,
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.local_shipping, color: SwiftDashColors.white),
            const SizedBox(width: 8),
            const Text('SwiftDash Driver'),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.person),
            onSelected: (value) async {
              if (value == 'logout') {
                final authService = AuthService();
                await authService.signOut();
                // AuthWrapper will handle navigation automatically
              } else if (value == 'profile') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const EditProfileScreen(),
                  ),
                );
              } else if (value == 'debug') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const DeliveryDebugScreen(),
                  ),
                );
              } else if (value == 'debug_vehicles') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const DebugVehicleTypesScreen(),
                  ),
                );
              }
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem<String>(
                value: 'profile',
                child: Row(
                  children: [
                    Icon(Icons.person, color: SwiftDashColors.darkBlue),
                    SizedBox(width: 8),
                    Text('Profile'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: SwiftDashColors.dangerRed),
                    SizedBox(width: 8),
                    Text('Logout'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Driver Welcome Card
            if (currentDriver != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  SwiftDashColors.darkBlue,
                                  SwiftDashColors.lightBlue,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(25),
                            ),
                            child: Icon(
                              Icons.person,
                              color: SwiftDashColors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Welcome back, ${currentDriver!.firstName}!',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: SwiftDashColors.darkBlue,
                                      ),
                                ),
                                Text(
                                  currentDriver!.isVerified
                                      ? 'Verified Driver'
                                      : 'Pending Verification',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: currentDriver!.isVerified
                                            ? SwiftDashColors.successGreen
                                            : SwiftDashColors.warningOrange,
                                        fontWeight: FontWeight.w500,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          if (!currentDriver!.isVerified)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: SwiftDashColors.warningOrange
                                    .withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Pending',
                                style: TextStyle(
                                  color: SwiftDashColors.warningOrange,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (currentDriver!.vehicleModel != null ||
                          currentDriver!.vehicleTypeId != null) ...[
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(
                              Icons.directions_car,
                              color: SwiftDashColors.lightBlue,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              currentDriver!.vehicleModel ??
                                  'Vehicle registered',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // Online/Offline Toggle Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(
                      isOnline ? 'You\'re Online' : 'You\'re Offline',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: isOnline
                                ? SwiftDashColors.successGreen
                                : SwiftDashColors.textGrey,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isOnline
                              ? [
                                  SwiftDashColors.successGreen,
                                  SwiftDashColors.successGreen.withOpacity(0.8),
                                ]
                              : [
                                  SwiftDashColors.textGrey,
                                  SwiftDashColors.textGrey.withOpacity(0.8),
                                ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: Switch(
                        value: isOnline,
                        onChanged: (value) async {
                          await _toggleOnlineStatus();
                        },
                        activeColor: SwiftDashColors.white,
                        inactiveThumbColor: SwiftDashColors.white,
                        trackColor: MaterialStateProperty.all(
                          Colors.transparent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isOnline
                          ? 'Available for deliveries'
                          : 'Tap to go online and start earning',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: SwiftDashColors.textGrey,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (isOnline) ...[
                      const SizedBox(height: 12),
                      const BackgroundServiceStatusWidget(),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Active Delivery Card (if exists)
            if (_driverFlow.hasActiveDelivery) ...[
              Card(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        SwiftDashColors.successGreen,
                        SwiftDashColors.successGreen.withOpacity(0.8),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: InkWell(
                    onTap: () => _driverFlow.navigateToActiveDelivery(context),
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: SwiftDashColors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.local_shipping,
                                  color: SwiftDashColors.white,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Active Delivery',
                                      style: TextStyle(
                                        color: SwiftDashColors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      _driverFlow
                                              .activeDelivery
                                              ?.status
                                              .displayName ??
                                          '',
                                      style: TextStyle(
                                        color: SwiftDashColors.white
                                            .withOpacity(0.9),
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.arrow_forward_ios,
                                color: SwiftDashColors.white,
                                size: 16,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: SwiftDashColors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'Tap to view details',
                              style: TextStyle(
                                color: SwiftDashColors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Delivery Actions
            Row(
              children: [
                Expanded(
                  child: Card(
                    child: InkWell(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) =>
                                const ImprovedDeliveryOffersScreen(),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    SwiftDashColors.lightBlue,
                                    SwiftDashColors.darkBlue,
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: const Icon(
                                Icons.local_shipping,
                                color: SwiftDashColors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Delivery Offers',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: SwiftDashColors.darkBlue,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'View available deliveries',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: SwiftDashColors.textGrey),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      // Show current position and offer to open in maps
                      try {
                        final pos = await OptimizedLocationService()
                            .getCurrentPosition();
                        if (pos == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Location not available'),
                            ),
                          );
                          return;
                        }

                        final lat = pos.latitude;
                        final lng = pos.longitude;
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Current Location'),
                            content: Text(
                              'Lat: ${lat.toStringAsFixed(6)}, Lng: ${lng.toStringAsFixed(6)}',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(),
                                child: const Text('Close'),
                              ),
                              TextButton(
                                onPressed: () async {
                                  // ✅ FIX: Try native Google Maps deeplink first, fallback to HTTPS
                                  try {
                                    final nativeUri = Uri.parse(
                                      'comgooglemaps://?q=$lat,$lng',
                                    );
                                    if (await canLaunchUrl(nativeUri)) {
                                      await launchUrl(
                                        nativeUri,
                                        mode: LaunchMode.externalApplication,
                                      );
                                    } else {
                                      // Fallback to HTTPS search URL
                                      final webUri = Uri.parse(
                                        'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
                                      );
                                      await launchUrl(
                                        webUri,
                                        mode: LaunchMode.externalApplication,
                                      );
                                    }
                                  } catch (e) {
                                    print('❌ Error opening Google Maps: $e');
                                  }
                                },
                                child: const Text('Open in Maps'),
                              ),
                            ],
                          ),
                        );
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to get location: $e')),
                        );
                      }
                    },
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    SwiftDashColors.warningOrange,
                                    SwiftDashColors.warningOrange.withOpacity(
                                      0.8,
                                    ),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: const Icon(
                                Icons.location_on,
                                color: SwiftDashColors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'My Location',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: SwiftDashColors.darkBlue,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Update location',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: SwiftDashColors.textGrey),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Today's Earnings Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Today\'s Earnings',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Icon(
                          Icons.trending_up,
                          color: SwiftDashColors.successGreen,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '₱0.00', // TODO: Replace with real earnings data
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: SwiftDashColors.darkBlue,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${currentDriver?.totalDeliveries ?? 0} total deliveries completed',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: SwiftDashColors.textGrey,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Quick Stats Row
            Row(
              children: [
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Icon(
                            Icons.star,
                            color: SwiftDashColors.warningOrange,
                            size: 24,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            currentDriver?.rating.toStringAsFixed(1) ?? '0.0',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Rating',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: SwiftDashColors.textGrey),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Icon(
                            Icons.local_shipping,
                            color: SwiftDashColors.lightBlue,
                            size: 24,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${currentDriver?.totalDeliveries ?? 0}',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Deliveries',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: SwiftDashColors.textGrey),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Recent Activity
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recent Activity',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (currentDriver?.totalDeliveries == 0)
                      Center(
                        child: Column(
                          children: [
                            Icon(
                              Icons.delivery_dining,
                              size: 48,
                              color: SwiftDashColors.textGrey.withOpacity(0.5),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No deliveries yet',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: SwiftDashColors.textGrey),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Go online to start receiving delivery requests',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: SwiftDashColors.textGrey),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    else
                      // TODO: Replace with real delivery history
                      Text(
                        'Delivery history will appear here',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: SwiftDashColors.textGrey,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
