import 'package:flutter/material.dart';
import 'dart:async';
import '../models/delivery.dart';
import '../widgets/route_preview_map.dart';
import '../services/mapbox_service.dart';
import '../core/supabase_config.dart';

class DeliveryOfferModal extends StatefulWidget {
  final Delivery delivery;
  /// onAccept should return true when the accept operation succeeded (assigned)
  final Future<bool> Function() onAccept;
  final VoidCallback onDecline;
  final int timeoutSeconds;

  const DeliveryOfferModal({
    Key? key,
    required this.delivery,
  required this.onAccept,
    required this.onDecline,
    this.timeoutSeconds = 300,
  }) : super(key: key);

  @override
  State<DeliveryOfferModal> createState() => _DeliveryOfferModalState();
}

class _DeliveryOfferModalState extends State<DeliveryOfferModal> {
  Timer? _timer;
  late int _remainingSeconds;
  bool _isAccepting = false;
  RouteData? _routeData;
  bool _routeLoading = false;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.timeoutSeconds;
    _startCountdown();
    _fetchRoute();
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_remainingSeconds <= 0) {
        t.cancel();
        if (mounted) {
          try {
            widget.onDecline();
          } finally {
            Navigator.of(context).pop();
          }
        }
      } else {
        setState(() => _remainingSeconds--);
      }
    });
  }

  Future<void> _fetchRoute() async {
    setState(() {
      _routeLoading = true;
    });
    try {
      final r = await MapboxService.getRoute(
        widget.delivery.pickupLatitude,
        widget.delivery.pickupLongitude,
        widget.delivery.deliveryLatitude,
        widget.delivery.deliveryLongitude,
      );
      if (mounted) setState(() {
        _routeData = r;
      });
    } catch (e) {
      print('⚠️ Failed to fetch route preview: $e');
      // leave _routeData as null to show error placeholder
    } finally {
      if (mounted) setState(() => _routeLoading = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatTime(int s) {
    final m = s ~/ 60;
    final r = s % 60;
    return '${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
  }

  Future<void> _handleAccept() async {
    if (_isAccepting) return;
    setState(() => _isAccepting = true);

    // pause countdown while accepting
    _timer?.cancel();

    try {
      final ok = await widget.onAccept();
      if (ok) {
        // Close modal on success
        if (mounted) Navigator.of(context).pop();
      } else {
        // Accept failed (taken by someone else) — show feedback and resume
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Delivery was already taken by another driver.'), backgroundColor: SwiftDashColors.warningOrange),
          );
          setState(() => _isAccepting = false);
          // resume countdown
          _startCountdown();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to accept delivery: $e')),
        );
        setState(() => _isAccepting = false);
        _startCountdown();
      }
    }
  }

  void _handleDecline() {
    _timer?.cancel();
    try {
      widget.onDecline();
    } finally {
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final delivery = widget.delivery;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.local_shipping, color: SwiftDashColors.darkBlue),
                const SizedBox(width: 8),
                const Text('Delivery Offer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text(_formatTime(_remainingSeconds), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),

            // Earnings header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [SwiftDashColors.darkBlue, SwiftDashColors.lightBlue]),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Earnings', style: TextStyle(color: SwiftDashColors.white.withOpacity(0.9), fontSize: 12)),
                  const SizedBox(height: 6),
                  Text('₱${delivery.driverEarnings.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Route preview
            SizedBox(
              height: 220,
              child: _routeLoading
                  ? const Center(child: CircularProgressIndicator())
                  : (_routeData != null
                      ? RoutePreviewMap(
                          pickupLat: delivery.pickupLatitude,
                          pickupLng: delivery.pickupLongitude,
                          deliveryLat: delivery.deliveryLatitude,
                          deliveryLng: delivery.deliveryLongitude,
                          routeData: _routeData,
                        )
                      : Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.map_outlined, size: 48, color: Colors.grey),
                              const SizedBox(height: 8),
                              const Text('No route preview available', style: TextStyle(color: Colors.grey)),
                              const SizedBox(height: 8),
                              ElevatedButton(
                                onPressed: _fetchRoute,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        )),
            ),

            const SizedBox(height: 12),

            // Pickup / Delivery details
            Text('Pickup: ${delivery.pickupAddress}', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text('Delivery: ${delivery.deliveryAddress}'),

            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: _handleDecline, child: const Text('Decline'))),
                const SizedBox(width: 8),
                Expanded(child: ElevatedButton(onPressed: _isAccepting ? null : _handleAccept, child: _isAccepting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Accept'))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}