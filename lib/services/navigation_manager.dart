import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Navigation manager that handles back button behavior and app lifecycle
class NavigationManager {
  static NavigationManager? _instance;
  static NavigationManager get instance => _instance ??= NavigationManager._();
  NavigationManager._();

  /// Global navigation key for app-wide navigation
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  
  /// Current context - updated by root widget
  BuildContext? _currentContext;
  
  /// Flag to track if we're in main screens (map, deliveries, etc)
  bool _isInMainFlow = false;
  
  /// Set current context
  void setCurrentContext(BuildContext context) {
    _currentContext = context;
  }
  
  /// Set main flow status
  void setMainFlow(bool isMain) {
    _isInMainFlow = isMain;
  }
  
  /// Handle system back button
  Future<bool> handleBackButton() async {
    final context = _currentContext ?? navigatorKey.currentContext;
    if (context == null) return false;
    
    // Check if we can pop the current route
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return true;
    }
    
    // If we're in main flow, minimize app instead of closing
    if (_isInMainFlow) {
      return await _minimizeApp();
    }
    
    // Otherwise allow normal back button behavior
    return false;
  }
  
  /// Minimize app to background instead of closing
  Future<bool> _minimizeApp() async {
    try {
      // Move app to background
      await SystemNavigator.pop();
      return true;
    } catch (e) {
      print('Failed to minimize app: $e');
      return false;
    }
  }
  
  /// Navigate to screen and clear back stack
  void navigateAndClearStack(String routeName, {Object? arguments}) {
    final context = _currentContext ?? navigatorKey.currentContext;
    if (context != null) {
      Navigator.of(context).pushNamedAndRemoveUntil(
        routeName, 
        (route) => false,
        arguments: arguments,
      );
    }
  }
  
  /// Navigate to screen
  void navigateTo(String routeName, {Object? arguments}) {
    final context = _currentContext ?? navigatorKey.currentContext;
    if (context != null) {
      Navigator.of(context).pushNamed(routeName, arguments: arguments);
    }
  }
  
  /// Go back
  void goBack() {
    final context = _currentContext ?? navigatorKey.currentContext;
    if (context != null && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }
}

/// Widget that handles back button behavior and provides navigation context
class NavigationWrapper extends StatefulWidget {
  final Widget child;
  final bool isMainFlow;
  
  const NavigationWrapper({
    super.key, 
    required this.child,
    this.isMainFlow = false,
  });

  @override
  State<NavigationWrapper> createState() => _NavigationWrapperState();
}

class _NavigationWrapperState extends State<NavigationWrapper> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NavigationManager.instance.setCurrentContext(context);
    NavigationManager.instance.setMainFlow(widget.isMainFlow);
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  
  @override
  void didUpdateWidget(NavigationWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    NavigationManager.instance.setMainFlow(widget.isMainFlow);
  }
  
  @override
  Widget build(BuildContext context) {
    NavigationManager.instance.setCurrentContext(context);
    
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (!didPop) {
          await NavigationManager.instance.handleBackButton();
        }
      },
      child: widget.child,
    );
  }
}

/// App lifecycle manager
class AppLifecycleManager extends StatefulWidget {
  final Widget child;
  
  const AppLifecycleManager({
    super.key,
    required this.child,
  });

  @override
  State<AppLifecycleManager> createState() => _AppLifecycleManagerState();
}

class _AppLifecycleManagerState extends State<AppLifecycleManager> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.resumed:
        print('🔄 App resumed');
        _handleAppResumed();
        break;
      case AppLifecycleState.paused:
        print('⏸️ App paused');
        _handleAppPaused();
        break;
      case AppLifecycleState.detached:
        print('📱 App detached');
        _handleAppDetached();
        break;
      default:
        break;
    }
  }
  
  void _handleAppResumed() {
    // App came back to foreground
    // Can refresh data, resume location tracking, etc.
  }
  
  void _handleAppPaused() {
    // App went to background
    // Can save state, pause non-critical operations, etc.
  }
  
  void _handleAppDetached() {
    // App is being terminated
    // Save critical state
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}