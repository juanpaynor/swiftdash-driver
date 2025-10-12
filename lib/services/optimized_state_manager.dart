import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/driver.dart';
import '../models/delivery.dart';
import '../services/auth_service.dart';
import '../services/driver_flow_service.dart';

/// Optimized driver state manager using ValueNotifier for efficient rebuilds
class DriverStateManager {
  static DriverStateManager? _instance;
  static DriverStateManager get instance => _instance ??= DriverStateManager._();
  DriverStateManager._();

  // Core state notifiers
  final ValueNotifier<Driver?> _driver = ValueNotifier<Driver?>(null);
  final ValueNotifier<bool> _isOnline = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isLoading = ValueNotifier<bool>(false);
  final ValueNotifier<String?> _error = ValueNotifier<String?>(null);
  final ValueNotifier<bool> _isLocationTracking = ValueNotifier<bool>(false);

  // Getters for value notifiers
  ValueNotifier<Driver?> get driverNotifier => _driver;
  ValueNotifier<bool> get isOnlineNotifier => _isOnline;
  ValueNotifier<bool> get isLoadingNotifier => _isLoading;
  ValueNotifier<String?> get errorNotifier => _error;
  ValueNotifier<bool> get isLocationTrackingNotifier => _isLocationTracking;

  // Getters for current values
  Driver? get driver => _driver.value;
  bool get isOnline => _isOnline.value;
  bool get isLoading => _isLoading.value;
  String? get error => _error.value;
  bool get isLocationTracking => _isLocationTracking.value;
  
  bool get hasDriver => _driver.value != null;
  bool get isVerified => _driver.value?.isVerified ?? false;

  // Services
  final AuthService _authService = AuthService();
  final DriverFlowService _driverFlow = DriverFlowService();

  /// Initialize driver state
  Future<void> initialize() async {
    setLoading(true);
    clearError();
    
    try {
      await _loadDriverProfile();
      print('✅ Driver state initialized');
    } catch (e) {
      setError('Failed to initialize driver state: $e');
    } finally {
      setLoading(false);
    }
  }

  /// Load driver profile
  Future<void> _loadDriverProfile() async {
    try {
      final driver = await _authService.getCurrentDriverProfile();
      _driver.value = driver;
      _isOnline.value = driver?.isOnline ?? false;
      print('📱 Driver profile loaded: ${driver?.fullName ?? 'None'}');
    } catch (e) {
      print('⚠️ Failed to load driver profile: $e');
    }
  }

  /// Update driver data
  void updateDriver(Driver driver) {
    _driver.value = driver;
    _isOnline.value = driver.isOnline;
  }

  /// Update online status
  void updateOnlineStatus(bool isOnline) {
    _isOnline.value = isOnline;
    
    // Update driver object if available
    if (_driver.value != null) {
      // Create updated driver with new online status
      // Note: This is a simplified update, in practice you might need
      // a proper copyWith method or state update mechanism
      _isLocationTracking.value = isOnline;
    }
  }

  /// Toggle online status
  Future<bool> toggleOnlineStatus(BuildContext context) async {
    if (_driver.value == null || _isLoading.value) return false;
    
    setLoading(true);
    
    try {
      final newStatus = !_isOnline.value;
      
      if (newStatus) {
        // Going online
        final success = await _driverFlow.goOnline(context);
        if (success) {
          _isOnline.value = true;
          _isLocationTracking.value = true;
          print('✅ Driver is now online');
          return true;
        }
      } else {
        // Going offline
        await _driverFlow.goOffline(context);
        _isOnline.value = false;
        _isLocationTracking.value = false;
        print('📴 Driver is now offline');
        return true;
      }
      
      return false;
      
    } catch (e) {
      setError('Failed to update online status: $e');
      return false;
    } finally {
      setLoading(false);
    }
  }

  /// Refresh driver data
  Future<void> refresh() async {
    if (_isLoading.value) return;
    
    setLoading(true);
    try {
      await _loadDriverProfile();
    } catch (e) {
      setError('Failed to refresh: $e');
    } finally {
      setLoading(false);
    }
  }

  /// Sign out and reset state
  Future<void> signOut() async {
    try {
      await _authService.signOut();
      reset();
      print('👋 Driver signed out, state reset');
    } catch (e) {
      setError('Failed to sign out: $e');
    }
  }

  /// Reset all state
  void reset() {
    _driver.value = null;
    _isOnline.value = false;
    _isLocationTracking.value = false;
    _isLoading.value = false;
    _error.value = null;
  }

  /// Set loading state
  void setLoading(bool loading) {
    _isLoading.value = loading;
  }

  /// Set error state
  void setError(String? error) {
    _error.value = error;
  }

  /// Clear error state
  void clearError() {
    _error.value = null;
  }

  /// Dispose resources
  void dispose() {
    _driver.dispose();
    _isOnline.dispose();
    _isLoading.dispose();
    _error.dispose();
    _isLocationTracking.dispose();
  }
}

/// Delivery state manager using ValueNotifier
class DeliveryStateManager {
  static DeliveryStateManager? _instance;
  static DeliveryStateManager get instance => _instance ??= DeliveryStateManager._();
  DeliveryStateManager._();

  // State notifiers
  final ValueNotifier<List<Delivery>> _availableOffers = ValueNotifier<List<Delivery>>([]);
  final ValueNotifier<List<Delivery>> _activeDeliveries = ValueNotifier<List<Delivery>>([]);
  final ValueNotifier<Delivery?> _currentDelivery = ValueNotifier<Delivery?>(null);
  final ValueNotifier<bool> _isLoading = ValueNotifier<bool>(false);
  final ValueNotifier<String?> _error = ValueNotifier<String?>(null);

  // Getters for value notifiers
  ValueNotifier<List<Delivery>> get availableOffersNotifier => _availableOffers;
  ValueNotifier<List<Delivery>> get activeDeliveriesNotifier => _activeDeliveries;
  ValueNotifier<Delivery?> get currentDeliveryNotifier => _currentDelivery;
  ValueNotifier<bool> get isLoadingNotifier => _isLoading;
  ValueNotifier<String?> get errorNotifier => _error;

  // Getters for current values
  List<Delivery> get availableOffers => List.unmodifiable(_availableOffers.value);
  List<Delivery> get activeDeliveries => List.unmodifiable(_activeDeliveries.value);
  Delivery? get currentDelivery => _currentDelivery.value;
  bool get isLoading => _isLoading.value;
  String? get error => _error.value;
  
  bool get hasActiveDelivery => _currentDelivery.value != null;
  bool get hasOffers => _availableOffers.value.isNotEmpty;
  int get offerCount => _availableOffers.value.length;

  /// Add delivery offer
  void addOffer(Delivery delivery) {
    final currentOffers = List<Delivery>.from(_availableOffers.value);
    if (!currentOffers.any((d) => d.id == delivery.id)) {
      currentOffers.add(delivery);
      _availableOffers.value = currentOffers;
      print('📬 New delivery offer added: ${delivery.id}');
    }
  }

  /// Remove delivery offer
  void removeOffer(String deliveryId) {
    final currentOffers = List<Delivery>.from(_availableOffers.value);
    final initialLength = currentOffers.length;
    currentOffers.removeWhere((d) => d.id == deliveryId);
    
    if (currentOffers.length != initialLength) {
      _availableOffers.value = currentOffers;
      print('📭 Delivery offer removed: $deliveryId');
    }
  }

  /// Clear all offers
  void clearOffers() {
    if (_availableOffers.value.isNotEmpty) {
      _availableOffers.value = [];
      print('🗑️ All delivery offers cleared');
    }
  }

  /// Set active delivery
  void setActiveDelivery(Delivery? delivery) {
    _currentDelivery.value = delivery;
    
    if (delivery != null) {
      // Add to active deliveries if not already there
      final currentActive = List<Delivery>.from(_activeDeliveries.value);
      if (!currentActive.any((d) => d.id == delivery.id)) {
        currentActive.add(delivery);
        _activeDeliveries.value = currentActive;
      }
    }
  }

  /// Update delivery status
  void updateDeliveryStatus(String deliveryId, DeliveryStatus newStatus) {
    // Update in active deliveries
    final currentActive = List<Delivery>.from(_activeDeliveries.value);
    bool updated = false;
    
    for (int i = 0; i < currentActive.length; i++) {
      if (currentActive[i].id == deliveryId) {
        currentActive[i] = currentActive[i].copyWith(status: newStatus);
        updated = true;
        
        // Update current delivery if it matches
        if (_currentDelivery.value?.id == deliveryId) {
          _currentDelivery.value = currentActive[i];
        }
        
        // Remove from active if completed
        if (newStatus == DeliveryStatus.delivered) {
          currentActive.removeAt(i);
          if (_currentDelivery.value?.id == deliveryId) {
            _currentDelivery.value = null;
          }
        }
        break;
      }
    }
    
    if (updated) {
      _activeDeliveries.value = currentActive;
    }
  }

  /// Set all active deliveries
  void setActiveDeliveries(List<Delivery> deliveries) {
    _activeDeliveries.value = List.from(deliveries);
    
    // Set current delivery to first active one if none set
    if (_currentDelivery.value == null && deliveries.isNotEmpty) {
      _currentDelivery.value = deliveries.first;
    }
  }

  /// Reset all delivery state
  void reset() {
    _availableOffers.value = [];
    _activeDeliveries.value = [];
    _currentDelivery.value = null;
    _isLoading.value = false;
    _error.value = null;
  }

  /// Set loading state
  void setLoading(bool loading) {
    _isLoading.value = loading;
  }

  /// Set error state
  void setError(String? error) {
    _error.value = error;
  }

  /// Dispose resources
  void dispose() {
    _availableOffers.dispose();
    _activeDeliveries.dispose();
    _currentDelivery.dispose();
    _isLoading.dispose();
    _error.dispose();
  }
}

/// UI state manager for screen visibility and interactions
class UIStateManager {
  static UIStateManager? _instance;
  static UIStateManager get instance => _instance ??= UIStateManager._();
  UIStateManager._();

  // State notifiers
  final ValueNotifier<bool> _showDeliveryOffers = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _showEarningsModal = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isMapInitialized = ValueNotifier<bool>(false);
  final ValueNotifier<String> _currentScreen = ValueNotifier<String>('map');

  // Getters for value notifiers
  ValueNotifier<bool> get showDeliveryOffersNotifier => _showDeliveryOffers;
  ValueNotifier<bool> get showEarningsModalNotifier => _showEarningsModal;
  ValueNotifier<bool> get isMapInitializedNotifier => _isMapInitialized;
  ValueNotifier<String> get currentScreenNotifier => _currentScreen;

  // Getters for current values
  bool get showDeliveryOffers => _showDeliveryOffers.value;
  bool get showEarningsModal => _showEarningsModal.value;
  bool get isMapInitialized => _isMapInitialized.value;
  String get currentScreen => _currentScreen.value;

  /// Toggle delivery offers visibility
  void toggleDeliveryOffers() {
    _showDeliveryOffers.value = !_showDeliveryOffers.value;
  }

  /// Set delivery offers visibility
  void setShowDeliveryOffers(bool show) {
    _showDeliveryOffers.value = show;
  }

  /// Toggle earnings modal visibility
  void toggleEarningsModal() {
    _showEarningsModal.value = !_showEarningsModal.value;
  }

  /// Set earnings modal visibility
  void setShowEarningsModal(bool show) {
    _showEarningsModal.value = show;
  }

  /// Set map initialization status
  void setMapInitialized(bool initialized) {
    _isMapInitialized.value = initialized;
  }

  /// Set current screen
  void setCurrentScreen(String screen) {
    _currentScreen.value = screen;
  }

  /// Close all modals
  void closeAllModals() {
    _showDeliveryOffers.value = false;
    _showEarningsModal.value = false;
  }

  /// Reset UI state
  void reset() {
    _showDeliveryOffers.value = false;
    _showEarningsModal.value = false;
    _isMapInitialized.value = false;
    _currentScreen.value = 'map';
  }

  /// Dispose resources
  void dispose() {
    _showDeliveryOffers.dispose();
    _showEarningsModal.dispose();
    _isMapInitialized.dispose();
    _currentScreen.dispose();
  }
}

/// Authentication state manager using ValueNotifier
class AuthStateManager {
  static AuthStateManager? _instance;
  static AuthStateManager get instance => _instance ??= AuthStateManager._();
  AuthStateManager._();

  // State notifiers
  final ValueNotifier<AuthState?> _authState = ValueNotifier<AuthState?>(null);
  final ValueNotifier<bool> _isLoading = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isDriverVerified = ValueNotifier<bool>(false);
  final ValueNotifier<String?> _error = ValueNotifier<String?>(null);

  // Getters for value notifiers
  ValueNotifier<AuthState?> get authStateNotifier => _authState;
  ValueNotifier<bool> get isLoadingNotifier => _isLoading;
  ValueNotifier<bool> get isDriverVerifiedNotifier => _isDriverVerified;
  ValueNotifier<String?> get errorNotifier => _error;

  // Getters for current values
  AuthState? get authState => _authState.value;
  bool get isLoading => _isLoading.value;
  bool get isDriverVerified => _isDriverVerified.value;
  String? get error => _error.value;
  
  bool get isAuthenticated => _authState.value?.session != null;
  User? get user => _authState.value?.session?.user;

  /// Update authentication state
  void updateAuthState(AuthState? state) {
    _authState.value = state;
    if (state?.session == null) {
      _isDriverVerified.value = false;
    }
  }

  /// Set loading state
  void setLoading(bool loading) {
    _isLoading.value = loading;
  }

  /// Set driver verification status
  void setDriverVerified(bool verified) {
    _isDriverVerified.value = verified;
  }

  /// Set error state
  void setError(String? error) {
    _error.value = error;
  }

  /// Clear error state
  void clearError() {
    _error.value = null;
  }

  /// Reset authentication state
  void reset() {
    _authState.value = null;
    _isLoading.value = false;
    _isDriverVerified.value = false;
    _error.value = null;
  }

  /// Dispose resources
  void dispose() {
    _authState.dispose();
    _isLoading.dispose();
    _isDriverVerified.dispose();
    _error.dispose();
  }
}

/// Form state manager for login and signup forms
class FormStateManager {
  static FormStateManager? _instance;
  static FormStateManager get instance => _instance ??= FormStateManager._();
  FormStateManager._();

  // State notifiers
  final ValueNotifier<bool> _isLoading = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _obscurePassword = ValueNotifier<bool>(true);
  final ValueNotifier<bool> _obscureConfirmPassword = ValueNotifier<bool>(true);
  final ValueNotifier<String?> _error = ValueNotifier<String?>(null);
  final ValueNotifier<String?> _successMessage = ValueNotifier<String?>(null);
  final ValueNotifier<Map<String, String>> _fieldErrors = ValueNotifier<Map<String, String>>({});

  // Getters for value notifiers
  ValueNotifier<bool> get isLoadingNotifier => _isLoading;
  ValueNotifier<bool> get obscurePasswordNotifier => _obscurePassword;
  ValueNotifier<bool> get obscureConfirmPasswordNotifier => _obscureConfirmPassword;
  ValueNotifier<String?> get errorNotifier => _error;
  ValueNotifier<String?> get successMessageNotifier => _successMessage;
  ValueNotifier<Map<String, String>> get fieldErrorsNotifier => _fieldErrors;

  // Getters for current values
  bool get isLoading => _isLoading.value;
  bool get obscurePassword => _obscurePassword.value;
  bool get obscureConfirmPassword => _obscureConfirmPassword.value;
  String? get error => _error.value;
  String? get successMessage => _successMessage.value;
  Map<String, String> get fieldErrors => Map.from(_fieldErrors.value);

  /// Set loading state
  void setLoading(bool loading) {
    _isLoading.value = loading;
  }

  /// Toggle password visibility
  void togglePasswordVisibility() {
    _obscurePassword.value = !_obscurePassword.value;
  }

  /// Toggle confirm password visibility
  void toggleConfirmPasswordVisibility() {
    _obscureConfirmPassword.value = !_obscureConfirmPassword.value;
  }

  /// Set error message
  void setError(String? error) {
    _error.value = error;
  }

  /// Set success message
  void setSuccessMessage(String? message) {
    _successMessage.value = message;
  }

  /// Set field error
  void setFieldError(String field, String? error) {
    final errors = Map<String, String>.from(_fieldErrors.value);
    if (error != null) {
      errors[field] = error;
    } else {
      errors.remove(field);
    }
    _fieldErrors.value = errors;
  }

  /// Clear all errors
  void clearErrors() {
    _error.value = null;
    _fieldErrors.value = {};
  }

  /// Clear messages
  void clearMessages() {
    _error.value = null;
    _successMessage.value = null;
  }

  /// Reset form state
  void reset() {
    _isLoading.value = false;
    _obscurePassword.value = true;
    _obscureConfirmPassword.value = true;
    _error.value = null;
    _successMessage.value = null;
    _fieldErrors.value = {};
  }

  /// Dispose resources
  void dispose() {
    _isLoading.dispose();
    _obscurePassword.dispose();
    _obscureConfirmPassword.dispose();
    _error.dispose();
    _successMessage.dispose();
    _fieldErrors.dispose();
  }
}