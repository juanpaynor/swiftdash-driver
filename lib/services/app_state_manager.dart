import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/driver.dart';
import '../models/delivery.dart';
import '../services/auth_service.dart';
import '../services/driver_flow_service.dart';
import '../services/realtime_service.dart';

/// Global app state management using ChangeNotifier
/// This provides centralized state management for the entire app
class AppStateManager extends ChangeNotifier {
  static AppStateManager? _instance;
  static AppStateManager get instance => _instance ??= AppStateManager._();
  AppStateManager._();

  // Core Services
  final AuthService _authService = AuthService();
  final DriverFlowService _driverFlow = DriverFlowService();
  final RealtimeService _realtimeService = RealtimeService();

  // App State
  bool _isInitialized = false;
  bool _isLoading = false;
  String? _error;
  
  // Driver State
  Driver? _currentDriver;
  bool _isOnline = false;
  bool _isLocationTracking = false;
  
  // Delivery State
  List<Delivery> _availableOffers = [];
  List<Delivery> _activeDeliveries = [];
  Delivery? _currentActiveDelivery;
  
  // UI State
  bool _showDeliveryOffers = false;
  bool _showEarningsModal = false;
  
  // Getters
  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  String? get error => _error;
  
  Driver? get currentDriver => _currentDriver;
  bool get isOnline => _isOnline;
  bool get isLocationTracking => _isLocationTracking;
  
  List<Delivery> get availableOffers => List.unmodifiable(_availableOffers);
  List<Delivery> get activeDeliveries => List.unmodifiable(_activeDeliveries);
  Delivery? get currentActiveDelivery => _currentActiveDelivery;
  
  bool get showDeliveryOffers => _showDeliveryOffers;
  bool get showEarningsModal => _showEarningsModal;
  
  bool get hasActiveDelivery => _currentActiveDelivery != null;
  bool get isDriverVerified => _currentDriver?.isVerified ?? false;

  /// Initialize the app state
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _setLoading(true);
      _clearError();
      
      // Initialize driver flow service
      await _driverFlow.initialize();
      
      // Load current driver profile
      await _loadDriverProfile();
      
      // Initialize realtime subscriptions and listen for offers
      if (_currentDriver != null) {
        await _loadActiveDeliveries();
        
        // Set up realtime subscriptions
        try {
          await _realtimeService.initializeRealtimeSubscriptions(_currentDriver!.id);
          print('✅ Realtime subscriptions initialized for driver: ${_currentDriver!.id}');
          
          // Listen for new delivery offers
          _realtimeService.offerModalStream.listen((delivery) {
            print('🚨 NEW OFFER RECEIVED IN APP STATE MANAGER: ${delivery.id}');
            addDeliveryOffer(delivery);
          });
          
          print('✅ Offer modal stream listener set up');
        } catch (e) {
          print('❌ Failed to set up realtime subscriptions: $e');
        }
      }
      
      _isInitialized = true;
      print('✅ App state initialized successfully');
      
    } catch (e) {
      _setError('Failed to initialize app: $e');
      print('❌ App initialization failed: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Load current driver profile
  Future<void> _loadDriverProfile() async {
    try {
      final driver = await _authService.getCurrentDriverProfile();
      _currentDriver = driver;
      _isOnline = driver?.isOnline ?? false;
      notifyListeners();
      
      print('📱 Driver profile loaded: ${driver?.fullName ?? 'None'}');
    } catch (e) {
      print('⚠️ Failed to load driver profile: $e');
    }
  }

  /// Toggle driver online status
  Future<void> toggleOnlineStatus() async {
    if (_currentDriver == null || _isLoading) return;
    
    try {
      _setLoading(true);
      
      final newStatus = !_isOnline;
      
      if (newStatus) {
        // Going online - Initialize realtime subscriptions
        print('🔥 Driver going online - Current driver ID: ${_currentDriver!.id}');
        
        // Re-initialize realtime subscriptions to ensure they're active
        try {
          await _realtimeService.initializeRealtimeSubscriptions(_currentDriver!.id);
          print('✅ Realtime subscriptions re-initialized for driver: ${_currentDriver!.id}');
        } catch (e) {
          print('❌ Failed to initialize realtime subscriptions: $e');
        }
        
        _isOnline = true;
        _isLocationTracking = true;
        await _loadAvailableOffers();
        print('✅ Driver is now online');
      } else {
        // Going offline
        _isOnline = false;
        _isLocationTracking = false;
        _availableOffers.clear();
        _showDeliveryOffers = false;
        print('📴 Driver is now offline');
      }
      
      notifyListeners();
      
    } catch (e) {
      _setError('Failed to update online status: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Load available delivery offers
  Future<void> _loadAvailableOffers() async {
    if (!_isOnline || _currentDriver == null) return;
    
    try {
      // This will be populated by the realtime service
      // For now, we just prepare the state
      _showDeliveryOffers = true;
      notifyListeners();
    } catch (e) {
      print('⚠️ Failed to load offers: $e');
    }
  }

  /// Load active deliveries
  Future<void> _loadActiveDeliveries() async {
    if (_currentDriver == null) return;
    
    try {
      // Use RealtimeService to get pending deliveries instead
      final deliveries = await _realtimeService.getPendingDeliveries(_currentDriver!.id);
      _activeDeliveries = deliveries;
      
      // Set current active delivery (assume only one at a time)
      _currentActiveDelivery = deliveries.isNotEmpty ? deliveries.first : null;
      
      notifyListeners();
      print('📦 Active deliveries loaded: ${deliveries.length}');
      
    } catch (e) {
      print('⚠️ Failed to load active deliveries: $e');
    }
  }

  /// Accept a delivery offer
  Future<bool> acceptDeliveryOffer(Delivery delivery) async {
    if (_isLoading || _currentDriver == null) return false;
    
    try {
      _setLoading(true);
      
      // Use RealtimeService directly since we don't have BuildContext
      final success = await _realtimeService.acceptDeliveryOfferNew(delivery.id, _currentDriver!.id);
      
      if (success) {
        _currentActiveDelivery = delivery;
        _activeDeliveries.add(delivery);
        _availableOffers.removeWhere((d) => d.id == delivery.id);
        _showDeliveryOffers = false;
        
        notifyListeners();
        print('✅ Delivery offer accepted: ${delivery.id}');
        return true;
      }
      
      return false;
      
    } catch (e) {
      _setError('Failed to accept delivery: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Update delivery status
  Future<void> updateDeliveryStatus(String deliveryId, DeliveryStatus newStatus) async {
    try {
      // Update in active deliveries list
      final index = _activeDeliveries.indexWhere((d) => d.id == deliveryId);
      if (index != -1) {
        final updatedDelivery = _activeDeliveries[index].copyWith(status: newStatus);
        _activeDeliveries[index] = updatedDelivery;
        
        // Update current active delivery if it matches
        if (_currentActiveDelivery?.id == deliveryId) {
          _currentActiveDelivery = updatedDelivery;
        }
        
        // If delivery is completed, remove from active list
        if (newStatus == DeliveryStatus.delivered) {
          _activeDeliveries.removeAt(index);
          _currentActiveDelivery = null;
        }
        
        notifyListeners();
      }
    } catch (e) {
      print('⚠️ Failed to update delivery status: $e');
    }
  }

  /// Add new delivery offer
  void addDeliveryOffer(Delivery delivery) {
    if (!_availableOffers.any((d) => d.id == delivery.id)) {
      _availableOffers.add(delivery);
      _showDeliveryOffers = true;
      notifyListeners();
      print('📬 New delivery offer added: ${delivery.id}');
    }
  }

  /// Remove delivery offer
  void removeDeliveryOffer(String deliveryId) {
    _availableOffers.removeWhere((d) => d.id == deliveryId);
    if (_availableOffers.isEmpty) {
      _showDeliveryOffers = false;
    }
    notifyListeners();
    print('📭 Delivery offer removed: $deliveryId');
  }

  /// Show/hide delivery offers screen
  void setShowDeliveryOffers(bool show) {
    _showDeliveryOffers = show;
    notifyListeners();
  }

  /// Show/hide earnings modal
  void setShowEarningsModal(bool show) {
    _showEarningsModal = show;
    notifyListeners();
  }

  /// Refresh app state
  Future<void> refresh() async {
    if (_isLoading) return;
    
    try {
      _setLoading(true);
      await _loadDriverProfile();
      await _loadActiveDeliveries();
      
      if (_isOnline) {
        await _loadAvailableOffers();
      }
      
    } catch (e) {
      _setError('Failed to refresh: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Sign out and reset state
  Future<void> signOut() async {
    try {
      await _authService.signOut();
      _resetState();
      print('👋 User signed out, state reset');
    } catch (e) {
      _setError('Failed to sign out: $e');
    }
  }

  /// Reset all state
  void _resetState() {
    _currentDriver = null;
    _isOnline = false;
    _isLocationTracking = false;
    _availableOffers.clear();
    _activeDeliveries.clear();
    _currentActiveDelivery = null;
    _showDeliveryOffers = false;
    _showEarningsModal = false;
    _isInitialized = false;
    _clearError();
    notifyListeners();
  }

  /// Set loading state
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  /// Set error state
  void _setError(String error) {
    _error = error;
    notifyListeners();
  }

  /// Clear error state
  void _clearError() {
    _error = null;
    notifyListeners();
  }

  /// Debug method to check realtime connection
  Future<void> debugRealtimeConnection() async {
    if (_currentDriver == null) {
      print('❌ No current driver for debugging');
      return;
    }
    
    print('🔍 === DEBUGGING REALTIME CONNECTION ===');
    print('🔍 Current driver ID: ${_currentDriver!.id}');
    print('🔍 Driver online status: $_isOnline');
    print('🔍 Available offers: ${_availableOffers.length}');
    
    try {
      // Re-initialize subscriptions
      await _realtimeService.initializeRealtimeSubscriptions(_currentDriver!.id);
      print('✅ Realtime subscriptions re-initialized');
      
      // Check for pending deliveries
      final pending = await _realtimeService.getPendingDeliveries(_currentDriver!.id);
      print('🔍 Pending deliveries found: ${pending.length}');
      
      // Test direct database query for driver_offered status
      final client = Supabase.instance.client;
      final offered = await client
          .from('deliveries')
          .select()
          .eq('driver_id', _currentDriver!.id)
          .eq('status', 'driver_offered');
      
      print('🔍 Direct database query for driver_offered: ${offered.length} results');
      for (final delivery in offered) {
        print('  - Delivery ${delivery['id']}: ${delivery['status']}');
      }
      
    } catch (e) {
      print('❌ Debug error: $e');
    }
  }

  @override
  void dispose() {
    // Clean up resources
    super.dispose();
  }
}