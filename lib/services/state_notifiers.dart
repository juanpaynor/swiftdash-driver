import 'package:flutter/foundation.dart';
import '../models/driver.dart';
import '../models/delivery.dart';

/// Optimized state notifier for driver data
class DriverStateNotifier extends ChangeNotifier {
  Driver? _driver;
  bool _isOnline = false;
  bool _isLoading = false;
  String? _error;
  
  Driver? get driver => _driver;
  bool get isOnline => _isOnline;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasDriver => _driver != null;
  bool get isVerified => _driver?.isVerified ?? false;
  
  void updateDriver(Driver? driver) {
    if (_driver != driver) {
      _driver = driver;
      _isOnline = driver?.isOnline ?? false;
      notifyListeners();
    }
  }
  
  void updateOnlineStatus(bool isOnline) {
    if (_isOnline != isOnline) {
      _isOnline = isOnline;
      notifyListeners();
    }
  }
  
  void setLoading(bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      notifyListeners();
    }
  }
  
  void setError(String? error) {
    if (_error != error) {
      _error = error;
      notifyListeners();
    }
  }
  
  void clearError() {
    setError(null);
  }
  
  void reset() {
    _driver = null;
    _isOnline = false;
    _isLoading = false;
    _error = null;
    notifyListeners();
  }
}

/// Optimized state notifier for delivery data
class DeliveryStateNotifier extends ChangeNotifier {
  final List<Delivery> _availableOffers = [];
  final List<Delivery> _activeDeliveries = [];
  Delivery? _currentDelivery;
  bool _isLoading = false;
  String? _error;
  
  List<Delivery> get availableOffers => List.unmodifiable(_availableOffers);
  List<Delivery> get activeDeliveries => List.unmodifiable(_activeDeliveries);
  Delivery? get currentDelivery => _currentDelivery;
  bool get isLoading => _isLoading;
  String? get error => _error;
  
  bool get hasActiveDelivery => _currentDelivery != null;
  bool get hasOffers => _availableOffers.isNotEmpty;
  int get offerCount => _availableOffers.length;
  int get activeDeliveryCount => _activeDeliveries.length;
  
  void addOffer(Delivery delivery) {
    final existingIndex = _availableOffers.indexWhere((d) => d.id == delivery.id);
    if (existingIndex == -1) {
      _availableOffers.add(delivery);
      notifyListeners();
    }
  }
  
  void removeOffer(String deliveryId) {
    final initialLength = _availableOffers.length;
    _availableOffers.removeWhere((d) => d.id == deliveryId);
    if (_availableOffers.length != initialLength) {
      notifyListeners();
    }
  }
  
  void clearOffers() {
    if (_availableOffers.isNotEmpty) {
      _availableOffers.clear();
      notifyListeners();
    }
  }
  
  void setActiveDelivery(Delivery? delivery) {
    if (_currentDelivery != delivery) {
      _currentDelivery = delivery;
      
      // Add to active deliveries if not already there
      if (delivery != null && !_activeDeliveries.any((d) => d.id == delivery.id)) {
        _activeDeliveries.add(delivery);
      }
      
      notifyListeners();
    }
  }
  
  void updateDeliveryStatus(String deliveryId, DeliveryStatus newStatus) {
    bool updated = false;
    
    // Update in active deliveries
    final activeIndex = _activeDeliveries.indexWhere((d) => d.id == deliveryId);
    if (activeIndex != -1) {
      final updatedDelivery = _activeDeliveries[activeIndex].copyWith(status: newStatus);
      _activeDeliveries[activeIndex] = updatedDelivery;
      updated = true;
      
      // Update current delivery if it matches
      if (_currentDelivery?.id == deliveryId) {
        _currentDelivery = updatedDelivery;
      }
      
      // Remove from active if completed
      if (newStatus == DeliveryStatus.delivered) {
        _activeDeliveries.removeAt(activeIndex);
        if (_currentDelivery?.id == deliveryId) {
          _currentDelivery = null;
        }
      }
    }
    
    if (updated) {
      notifyListeners();
    }
  }
  
  void setActiveDeliveries(List<Delivery> deliveries) {
    _activeDeliveries.clear();
    _activeDeliveries.addAll(deliveries);
    
    // Set current delivery to first active one if none set
    if (_currentDelivery == null && deliveries.isNotEmpty) {
      _currentDelivery = deliveries.first;
    }
    
    notifyListeners();
  }
  
  void setLoading(bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      notifyListeners();
    }
  }
  
  void setError(String? error) {
    if (_error != error) {
      _error = error;
      notifyListeners();
    }
  }
  
  void clearError() {
    setError(null);
  }
  
  void reset() {
    _availableOffers.clear();
    _activeDeliveries.clear();
    _currentDelivery = null;
    _isLoading = false;
    _error = null;
    notifyListeners();
  }
}

/// UI state notifier for screen visibility and interactions
class UIStateNotifier extends ChangeNotifier {
  bool _showDeliveryOffers = false;
  bool _showEarningsModal = false;
  bool _showDriverDrawer = false;
  bool _isMapInitialized = false;
  String _currentScreen = 'map';
  
  bool get showDeliveryOffers => _showDeliveryOffers;
  bool get showEarningsModal => _showEarningsModal;
  bool get showDriverDrawer => _showDriverDrawer;
  bool get isMapInitialized => _isMapInitialized;
  String get currentScreen => _currentScreen;
  
  void setShowDeliveryOffers(bool show) {
    if (_showDeliveryOffers != show) {
      _showDeliveryOffers = show;
      notifyListeners();
    }
  }
  
  void setShowEarningsModal(bool show) {
    if (_showEarningsModal != show) {
      _showEarningsModal = show;
      notifyListeners();
    }
  }
  
  void setShowDriverDrawer(bool show) {
    if (_showDriverDrawer != show) {
      _showDriverDrawer = show;
      notifyListeners();
    }
  }
  
  void setMapInitialized(bool initialized) {
    if (_isMapInitialized != initialized) {
      _isMapInitialized = initialized;
      notifyListeners();
    }
  }
  
  void setCurrentScreen(String screen) {
    if (_currentScreen != screen) {
      _currentScreen = screen;
      notifyListeners();
    }
  }
  
  void toggleDeliveryOffers() {
    setShowDeliveryOffers(!_showDeliveryOffers);
  }
  
  void toggleEarningsModal() {
    setShowEarningsModal(!_showEarningsModal);
  }
  
  void closeAllModals() {
    bool hasChanges = false;
    
    if (_showDeliveryOffers) {
      _showDeliveryOffers = false;
      hasChanges = true;
    }
    
    if (_showEarningsModal) {
      _showEarningsModal = false;
      hasChanges = true;
    }
    
    if (_showDriverDrawer) {
      _showDriverDrawer = false;
      hasChanges = true;
    }
    
    if (hasChanges) {
      notifyListeners();
    }
  }
  
  void reset() {
    _showDeliveryOffers = false;
    _showEarningsModal = false;
    _showDriverDrawer = false;
    _isMapInitialized = false;
    _currentScreen = 'map';
    notifyListeners();
  }
}