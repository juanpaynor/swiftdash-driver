import 'package:flutter/material.dart';
import '../services/background_location_service.dart';
import '../core/supabase_config.dart';
import 'battery_optimization_screen.dart';

class BackgroundServiceStatusWidget extends StatefulWidget {
  const BackgroundServiceStatusWidget({super.key});

  @override
  State<BackgroundServiceStatusWidget> createState() => _BackgroundServiceStatusWidgetState();
}

class _BackgroundServiceStatusWidgetState extends State<BackgroundServiceStatusWidget> {
  bool _isServiceRunning = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkServiceStatus();
  }

  Future<void> _checkServiceStatus() async {
    try {
      final isRunning = await BackgroundLocationService.isServiceRunning();
      setState(() {
        _isServiceRunning = isRunning;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isServiceRunning = false;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    return Card(
      color: _isServiceRunning ? SwiftDashColors.successGreen.withOpacity(0.1) : SwiftDashColors.warningOrange.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              _isServiceRunning ? Icons.gps_fixed : Icons.gps_off,
              color: _isServiceRunning ? SwiftDashColors.successGreen : SwiftDashColors.warningOrange,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isServiceRunning ? 'Background Tracking Active' : 'Background Tracking Off',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: _isServiceRunning ? SwiftDashColors.successGreen : SwiftDashColors.warningOrange,
                    ),
                  ),
                  Text(
                    _isServiceRunning 
                      ? 'Location updates continue when app is minimized' 
                      : 'Enable for reliable delivery tracking',
                    style: TextStyle(
                      fontSize: 10,
                      color: SwiftDashColors.textGrey,
                    ),
                  ),
                ],
              ),
            ),
            if (!_isServiceRunning)
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const BatteryOptimizationScreen(),
                    ),
                  );
                },
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Setup',
                  style: TextStyle(
                    fontSize: 10,
                    color: SwiftDashColors.warningOrange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}