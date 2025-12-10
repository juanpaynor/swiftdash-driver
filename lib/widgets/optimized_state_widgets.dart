import 'dart:async';
import 'package:flutter/material.dart';
import '../services/optimized_state_manager.dart';

/// A widget that rebuilds when a ValueNotifier changes
/// More efficient than using setState across the entire widget tree
class ValueListenableContainer<T> extends StatelessWidget {
  final ValueNotifier<T> notifier;
  final Widget Function(BuildContext context, T value, Widget? child) builder;
  final Widget? child;

  const ValueListenableContainer({
    super.key,
    required this.notifier,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<T>(
      valueListenable: notifier,
      builder: builder,
      child: child,
    );
  }
}

/// A widget that listens to multiple ValueNotifiers efficiently
class MultiValueListenable extends StatefulWidget {
  final List<ValueNotifier> notifiers;
  final Widget Function(BuildContext context) builder;

  const MultiValueListenable({
    super.key,
    required this.notifiers,
    required this.builder,
  });

  @override
  State<MultiValueListenable> createState() => _MultiValueListenableState();
}

class _MultiValueListenableState extends State<MultiValueListenable> {
  Timer? _debounceTimer;
  static const _debounceDuration = Duration(milliseconds: 50);

  @override
  void initState() {
    super.initState();
    for (final notifier in widget.notifiers) {
      notifier.addListener(_onValueChanged);
    }
  }

  @override
  void didUpdateWidget(MultiValueListenable oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Remove listeners from old notifiers
    for (final notifier in oldWidget.notifiers) {
      notifier.removeListener(_onValueChanged);
    }

    // Add listeners to new notifiers
    for (final notifier in widget.notifiers) {
      notifier.addListener(_onValueChanged);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    for (final notifier in widget.notifiers) {
      notifier.removeListener(_onValueChanged);
    }
    super.dispose();
  }

  void _onValueChanged() {
    // Debounce rapid changes to prevent excessive rebuilds
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () {
      if (mounted) {
        setState(() {
          // Trigger rebuild when any notifier changes
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context);
  }
}

/// Enhanced driver status widget using optimized state management
class OptimizedDriverStatusWidget extends StatelessWidget {
  final bool showOfflineMessage;

  const OptimizedDriverStatusWidget({
    super.key,
    this.showOfflineMessage = true,
  });

  @override
  Widget build(BuildContext context) {
    return MultiValueListenable(
      notifiers: [
        DriverStateManager.instance.isOnlineNotifier,
        DriverStateManager.instance.isLoadingNotifier,
        DriverStateManager.instance.errorNotifier,
      ],
      builder: (context) {
        final driverState = DriverStateManager.instance;

        if (driverState.isLoading) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('Updating status...'),
                ],
              ),
            ),
          );
        }

        if (driverState.error != null) {
          return Card(
            color: Colors.red.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.error, color: Colors.red.shade600),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      driverState.error!,
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Card(
          color: driverState.isOnline
              ? Colors.green.shade50
              : Colors.grey.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: driverState.isOnline ? Colors.green : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        driverState.isOnline
                            ? 'Online - Available for deliveries'
                            : 'Offline',
                        style: TextStyle(
                          color: driverState.isOnline
                              ? Colors.green.shade700
                              : Colors.grey.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (!driverState.isOnline && showOfflineMessage)
                        Text(
                          'Tap toggle to go online',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                if (driverState.isLocationTracking)
                  Icon(
                    Icons.location_on,
                    color: Colors.green.shade600,
                    size: 18,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Delivery offers counter widget
class DeliveryOffersCounter extends StatelessWidget {
  const DeliveryOffersCounter({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableContainer<List<dynamic>>(
      notifier: DeliveryStateManager.instance.availableOffersNotifier,
      builder: (context, offers, child) {
        final count = offers.length;

        if (count == 0) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            count.toString(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      },
    );
  }
}

/// Loading overlay widget using state management
class OptimizedLoadingOverlay extends StatelessWidget {
  final Widget child;

  const OptimizedLoadingOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return MultiValueListenable(
      notifiers: [
        DriverStateManager.instance.isLoadingNotifier,
        DeliveryStateManager.instance.isLoadingNotifier,
      ],
      builder: (context) {
        final isLoading =
            DriverStateManager.instance.isLoading ||
            DeliveryStateManager.instance.isLoading;

        return Stack(
          children: [
            child,
            if (isLoading)
              Container(
                color: Colors.black.withOpacity(0.3),
                child: const Center(
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Please wait...'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
