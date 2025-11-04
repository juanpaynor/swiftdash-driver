import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../core/colors.dart';
import '../services/navigation_service.dart';
import 'dart:async';

/// Full-screen custom navigation UI with SwiftDash branding
/// Provides large, easy-to-read turn-by-turn instructions for drivers
class FullScreenNavigationView extends StatefulWidget {
  final VoidCallback? onMinimize;
  final VoidCallback? onEndNavigation;

  const FullScreenNavigationView({
    super.key,
    this.onMinimize,
    this.onEndNavigation,
  });

  @override
  State<FullScreenNavigationView> createState() => _FullScreenNavigationViewState();
}

class _FullScreenNavigationViewState extends State<FullScreenNavigationView> {
  final NavigationService _navService = NavigationService.instance;
  StreamSubscription<NavigationInstruction>? _instructionSubscription;
  StreamSubscription<NavigationProgress>? _progressSubscription;
  StreamSubscription<Position>? _positionSubscription;

  NavigationInstruction? _currentInstruction;
  NavigationProgress? _currentProgress;
  double _currentSpeed = 0.0; // in km/h

  @override
  void initState() {
    super.initState();
    _setupListeners();
    _setupSpeedTracking();
  }

  void _setupListeners() {
    // Listen to instruction updates
    _instructionSubscription = _navService.instructionStream.listen((instruction) {
      if (mounted) {
        setState(() {
          _currentInstruction = instruction;
        });
      }
    });

    // Listen to progress updates
    _progressSubscription = _navService.progressStream.listen((progress) {
      if (mounted) {
        setState(() {
          _currentProgress = progress;
        });
      }
    });

    // Initialize with current state
    setState(() {
      _currentInstruction = _navService.currentInstruction;
      _currentProgress = NavigationProgress(
        distanceToNextInstruction: _navService.distanceToNextInstruction,
        distanceRemaining: _navService.distanceRemaining,
        estimatedTimeToArrival: _navService.estimatedTimeToArrival,
        currentInstruction: _navService.currentInstruction,
        progress: 0.0,
      );
    });
  }

  void _setupSpeedTracking() {
    // Track current speed from GPS
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) {
      if (mounted) {
        setState(() {
          // speed is in m/s, convert to km/h
          _currentSpeed = (position.speed * 3.6).clamp(0, 200);
        });
      }
    });
  }

  @override
  void dispose() {
    _instructionSubscription?.cancel();
    _progressSubscription?.cancel();
    _positionSubscription?.cancel();
    super.dispose();
  }

  String _formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    } else {
      return '${meters.round()} m';
    }
  }

  String _formatETA(double minutes) {
    if (minutes >= 60) {
      final hours = (minutes / 60).floor();
      final mins = (minutes % 60).round();
      return '${hours}h ${mins}m';
    } else {
      return '${minutes.round()} min';
    }
  }

  IconData _getInstructionIcon(NavigationInstructionType type) {
    switch (type) {
      case NavigationInstructionType.turnLeft:
        return Icons.turn_left;
      case NavigationInstructionType.turnRight:
        return Icons.turn_right;
      case NavigationInstructionType.slightLeft:
        return Icons.turn_slight_left;
      case NavigationInstructionType.slightRight:
        return Icons.turn_slight_right;
      case NavigationInstructionType.sharpLeft:
        return Icons.turn_sharp_left;
      case NavigationInstructionType.sharpRight:
        return Icons.turn_sharp_right;
      case NavigationInstructionType.straight:
        return Icons.arrow_upward;
      case NavigationInstructionType.roundabout:
        return Icons.roundabout_left;
      case NavigationInstructionType.arrive:
        return Icons.location_on;
      default:
        return Icons.navigation;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SwiftDashColors.darkBlue,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
            _buildTopBar(),
            
            // Main Navigation Display
            Expanded(
              child: _buildMainNavigationDisplay(),
            ),
            
            // Bottom Stats Bar
            _buildBottomStatsBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: SwiftDashColors.lightBlue,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Minimize Button
          IconButton(
            onPressed: widget.onMinimize,
            icon: const Icon(Icons.keyboard_arrow_down, size: 28),
            color: SwiftDashColors.white,
            tooltip: 'Minimize',
          ),
          
          // SwiftDash Logo/Title
          const Text(
            'SwiftDash Navigation',
            style: TextStyle(
              color: SwiftDashColors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          
          // End Navigation Button
          IconButton(
            onPressed: _showEndNavigationDialog,
            icon: const Icon(Icons.close, size: 28),
            color: SwiftDashColors.white,
            tooltip: 'End Navigation',
          ),
        ],
      ),
    );
  }

  Widget _buildMainNavigationDisplay() {
    if (_currentInstruction == null) {
      return const Center(
        child: CircularProgressIndicator(
          color: SwiftDashColors.white,
        ),
      );
    }

    final distanceToInstruction = _currentProgress?.distanceToNextInstruction ?? 0;
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Large Turn Icon
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: SwiftDashColors.lightBlue,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: SwiftDashColors.lightBlue.withOpacity(0.3),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Icon(
              _getInstructionIcon(_currentInstruction!.type),
              size: 80,
              color: SwiftDashColors.white,
            ),
          ),
          
          const SizedBox(height: 40),
          
          // Distance to Next Turn
          Text(
            _formatDistance(distanceToInstruction),
            style: const TextStyle(
              color: SwiftDashColors.white,
              fontSize: 72,
              fontWeight: FontWeight.w700,
              height: 1.0,
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Instruction Text
          Text(
            _currentInstruction!.instruction,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: SwiftDashColors.white,
              fontSize: 28,
              fontWeight: FontWeight.w500,
              height: 1.3,
            ),
          ),
          
          const SizedBox(height: 40),
          
          // Progress Bar
          if (_currentProgress != null)
            _buildProgressBar(),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    final progress = _currentProgress!.progress.clamp(0.0, 1.0);
    
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: SwiftDashColors.white.withOpacity(0.2),
            valueColor: const AlwaysStoppedAnimation<Color>(SwiftDashColors.successGreen),
            minHeight: 10,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '${(progress * 100).round()}% to destination',
          style: TextStyle(
            color: SwiftDashColors.white.withOpacity(0.8),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomStatsBar() {
    final distanceRemaining = _currentProgress?.distanceRemaining ?? 0;
    final eta = _currentProgress?.estimatedTimeToArrival ?? 0;
    
    return Container(
      decoration: BoxDecoration(
        color: SwiftDashColors.lightBlue,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Current Speed
          Expanded(
            child: _buildStatTile(
              icon: Icons.speed,
              label: 'Speed',
              value: '${_currentSpeed.round()}',
              unit: 'km/h',
            ),
          ),
          
          Container(
            width: 1,
            height: 60,
            color: SwiftDashColors.white.withOpacity(0.3),
          ),
          
          // Distance Remaining
          Expanded(
            child: _buildStatTile(
              icon: Icons.straighten,
              label: 'Distance',
              value: _formatDistance(distanceRemaining),
              unit: '',
            ),
          ),
          
          Container(
            width: 1,
            height: 60,
            color: SwiftDashColors.white.withOpacity(0.3),
          ),
          
          // ETA
          Expanded(
            child: _buildStatTile(
              icon: Icons.access_time,
              label: 'ETA',
              value: _formatETA(eta),
              unit: '',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatTile({
    required IconData icon,
    required String label,
    required String value,
    required String unit,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: SwiftDashColors.white,
            size: 24,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: SwiftDashColors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: TextStyle(
                    color: SwiftDashColors.white.withOpacity(0.8),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: SwiftDashColors.white.withOpacity(0.7),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _showEndNavigationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End Navigation'),
        content: const Text('Are you sure you want to stop navigation?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onEndNavigation?.call();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: SwiftDashColors.errorRed,
              foregroundColor: SwiftDashColors.white,
            ),
            child: const Text('End'),
          ),
        ],
      ),
    );
  }
}
