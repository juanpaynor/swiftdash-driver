import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/supabase_config.dart';
import 'screens/auth_wrapper.dart';
import 'screens/delivery_debug_screen.dart';
import 'screens/debug_vehicle_types_screen.dart';
import 'services/auth_service.dart';
import 'services/realtime_service.dart';
import 'models/driver.dart';
import 'screens/delivery_offers_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    anonKey: SupabaseConfig.supabaseAnonKey,
  );
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
      home: const AuthWrapper(),
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
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDriverProfile();
  }

  Future<void> _loadDriverProfile() async {
    try {
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
    if (currentDriver == null) return;
    
    try {
      final newStatus = !isOnline;
      await _authService.updateOnlineStatus(newStatus);
      setState(() {
        isOnline = newStatus;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update status: $e'),
          backgroundColor: SwiftDashColors.dangerRed,
        ),
      );
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
        body: const Center(
          child: CircularProgressIndicator(),
        ),
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
                // TODO: Navigate to profile
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
                value: 'debug',
                child: Row(
                  children: [
                    Icon(Icons.bug_report, color: SwiftDashColors.lightBlue),
                    SizedBox(width: 8),
                    Text('Debug Delivery'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'debug_vehicles',
                child: Row(
                  children: [
                    Icon(Icons.local_shipping, color: SwiftDashColors.lightBlue),
                    SizedBox(width: 8),
                    Text('Debug Vehicles'),
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
                                colors: [SwiftDashColors.darkBlue, SwiftDashColors.lightBlue],
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
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: SwiftDashColors.darkBlue,
                                  ),
                                ),
                                Text(
                                  currentDriver!.isVerified 
                                    ? 'Verified Driver' 
                                    : 'Pending Verification',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: SwiftDashColors.warningOrange.withOpacity(0.1),
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
                      if (currentDriver!.vehicleModel != null || currentDriver!.vehicleTypeId != null) ...[
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(Icons.directions_car, color: SwiftDashColors.lightBlue, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              currentDriver!.vehicleModel ?? 'Vehicle registered',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
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
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: isOnline ? SwiftDashColors.successGreen : SwiftDashColors.textGrey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isOnline 
                            ? [SwiftDashColors.successGreen, SwiftDashColors.successGreen.withOpacity(0.8)]
                            : [SwiftDashColors.textGrey, SwiftDashColors.textGrey.withOpacity(0.8)],
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
                        trackColor: MaterialStateProperty.all(Colors.transparent),
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
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Delivery Actions
            Row(
              children: [
                Expanded(
                  child: Card(
                    child: InkWell(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const DeliveryOffersScreen(),
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
                                  colors: [SwiftDashColors.lightBlue, SwiftDashColors.darkBlue],
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
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: SwiftDashColors.darkBlue,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'View available deliveries',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: SwiftDashColors.textGrey,
                              ),
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
                                colors: [SwiftDashColors.warningOrange, SwiftDashColors.warningOrange.withOpacity(0.8)],
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
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: SwiftDashColors.darkBlue,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Update location',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: SwiftDashColors.textGrey,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
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
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Icon(Icons.trending_up, color: SwiftDashColors.successGreen),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '₱0.00', // TODO: Replace with real earnings data
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
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
                          Icon(Icons.star, color: SwiftDashColors.warningOrange, size: 24),
                          const SizedBox(height: 8),
                          Text(
                            currentDriver?.rating.toStringAsFixed(1) ?? '0.0',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Rating',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: SwiftDashColors.textGrey,
                            ),
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
                          Icon(Icons.local_shipping, color: SwiftDashColors.lightBlue, size: 24),
                          const SizedBox(height: 8),
                          Text(
                            '${currentDriver?.totalDeliveries ?? 0}',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Deliveries',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: SwiftDashColors.textGrey,
                            ),
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
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: SwiftDashColors.textGrey,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Go online to start receiving delivery requests',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: SwiftDashColors.textGrey,
                              ),
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
