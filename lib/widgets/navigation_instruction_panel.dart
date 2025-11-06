import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/navigation_service.dart';
import '../core/colors.dart';

/// Professional navigation instruction widget that displays turn-by-turn guidance
/// Integrates seamlessly with existing SwiftDash UI
class NavigationInstructionPanel extends StatefulWidget {
  final NavigationService navigationService;
  final VoidCallback? onCloseNavigation;
  final bool showCompactMode;

  const NavigationInstructionPanel({
    super.key,
    required this.navigationService,
    this.onCloseNavigation,
    this.showCompactMode = false,
  });

  @override
  State<NavigationInstructionPanel> createState() => _NavigationInstructionPanelState();
}

class _NavigationInstructionPanelState extends State<NavigationInstructionPanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _slideAnimation;
  NavigationInstruction? _currentInstruction;
  NavigationProgress? _currentProgress;

  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _slideAnimation = Tween<double>(
      begin: -1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    
    // Listen to navigation updates
    _listenToNavigation();
    
    // Start animation
    _animationController.forward();
  }

  void _listenToNavigation() {
    // Listen to instruction changes
    widget.navigationService.instructionStream.listen((instruction) {
      if (mounted) {
        setState(() {
          _currentInstruction = instruction;
        });
        
        // Haptic feedback for new instruction
        HapticFeedback.lightImpact();
      }
    });
    
    // Listen to progress updates
    widget.navigationService.progressStream.listen((progress) {
      if (mounted) {
        setState(() {
          _currentProgress = progress;
        });
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.navigationService.isNavigating) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: _slideAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _slideAnimation.value * MediaQuery.of(context).size.height * 0.2),
          child: child,
        );
      },
      child: widget.showCompactMode ? _buildCompactPanel() : _buildFullPanel(),
    );
  }

  Widget _buildFullPanel() {
    // 🆕 ISSUE FIX #4: Add proper top margin to avoid overlapping with app bar
    final topPadding = MediaQuery.of(context).padding.top;
    final appBarHeight = kToolbarHeight;
    final totalTopSpace = topPadding + appBarHeight + 16; // Safe area + AppBar + spacing
    
    return Container(
      margin: EdgeInsets.fromLTRB(16, totalTopSpace, 16, 0),
      decoration: BoxDecoration(
        color: SwiftDashColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: SwiftDashColors.darkBlue.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with close button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: SwiftDashColors.lightBlue.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.navigation,
                  color: SwiftDashColors.lightBlue,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Navigation Active',
                  style: TextStyle(
                    color: SwiftDashColors.lightBlue,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                if (widget.onCloseNavigation != null)
                  GestureDetector(
                    onTap: () {
                      _animationController.reverse().then((_) {
                        widget.onCloseNavigation?.call();
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: SwiftDashColors.lightBlue.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(
                        Icons.close,
                        color: SwiftDashColors.lightBlue,
                        size: 16,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          
          // Main instruction content
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Current instruction
                if (_currentInstruction != null) ...[
                  Row(
                    children: [
                      _buildInstructionIcon(_currentInstruction!.type),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _currentInstruction!.instruction,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: SwiftDashColors.darkBlue,
                              ),
                            ),
                            if (_currentProgress != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                _formatDistance(_currentProgress!.distanceToNextInstruction),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: SwiftDashColors.darkBlue.withOpacity(0.7),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Progress information
                  if (_currentProgress != null) ...[
                    Row(
                      children: [
                        Expanded(
                          child: _buildProgressInfo(
                            'Remaining',
                            _formatDistance(_currentProgress!.distanceRemaining),
                            Icons.straighten,
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 40,
                          color: SwiftDashColors.lightGray,
                        ),
                        Expanded(
                          child: _buildProgressInfo(
                            'ETA',
                            _formatDuration(_currentProgress!.estimatedTimeToArrival),
                            Icons.access_time,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactPanel() {
    if (_currentInstruction == null) return const SizedBox.shrink();
    
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SwiftDashColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: SwiftDashColors.darkBlue.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildInstructionIcon(_currentInstruction!.type),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _currentInstruction!.instruction,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: SwiftDashColors.darkBlue,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (_currentProgress != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${_formatDistance(_currentProgress!.distanceToNextInstruction)} • ${_formatDuration(_currentProgress!.estimatedTimeToArrival)} remaining',
                    style: TextStyle(
                      fontSize: 12,
                      color: SwiftDashColors.darkBlue.withOpacity(0.7),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (widget.onCloseNavigation != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: widget.onCloseNavigation,
              child: Icon(
                Icons.close,
                color: SwiftDashColors.lightGray,
                size: 18,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInstructionIcon(NavigationInstructionType type) {
    IconData iconData;
    Color iconColor = SwiftDashColors.lightBlue;
    
    switch (type) {
      case NavigationInstructionType.start:
        iconData = Icons.play_arrow;
        iconColor = SwiftDashColors.successGreen;
        break;
      case NavigationInstructionType.straight:
        iconData = Icons.straight;
        break;
      case NavigationInstructionType.turnLeft:
        iconData = Icons.turn_left;
        break;
      case NavigationInstructionType.turnRight:
        iconData = Icons.turn_right;
        break;
      case NavigationInstructionType.slightLeft:
        iconData = Icons.turn_slight_left;
        break;
      case NavigationInstructionType.slightRight:
        iconData = Icons.turn_slight_right;
        break;
      case NavigationInstructionType.sharpLeft:
        iconData = Icons.turn_sharp_left;
        break;
      case NavigationInstructionType.sharpRight:
        iconData = Icons.turn_sharp_right;
        break;
      case NavigationInstructionType.roundabout:
        iconData = Icons.roundabout_left;
        break;
      case NavigationInstructionType.arrive:
        iconData = Icons.flag;
        iconColor = SwiftDashColors.successGreen;
        break;
    }
    
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: iconColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        iconData,
        color: iconColor,
        size: 24,
      ),
    );
  }

  Widget _buildProgressInfo(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(
          icon,
          color: SwiftDashColors.lightBlue,
          size: 18,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: SwiftDashColors.darkBlue.withOpacity(0.7),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: SwiftDashColors.darkBlue,
          ),
        ),
      ],
    );
  }

  String _formatDistance(double distanceMeters) {
    if (distanceMeters < 1000) {
      return '${distanceMeters.round()} m';
    } else {
      return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
    }
  }

  String _formatDuration(double durationMinutes) {
    if (durationMinutes < 60) {
      return '${durationMinutes.round()} min';
    } else {
      final hours = durationMinutes ~/ 60;
      final minutes = (durationMinutes % 60).round();
      return '${hours}h ${minutes}m';
    }
  }
}

/// Simple navigation start button that integrates with existing UI
class NavigationStartButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String label;
  final bool isLoading;
  final IconData icon;

  const NavigationStartButton({
    super.key,
    required this.onPressed,
    this.label = 'Start Navigation',
    this.isLoading = false,
    this.icon = Icons.navigation,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 48,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ElevatedButton.icon(
        onPressed: isLoading ? null : onPressed,
        icon: isLoading 
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(SwiftDashColors.white),
                ),
              )
            : Icon(icon, size: 18),
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: SwiftDashColors.lightBlue,
          foregroundColor: SwiftDashColors.white,
          elevation: 2,
          shadowColor: SwiftDashColors.lightBlue.withOpacity(0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

/// Navigation progress bar that shows route completion
class NavigationProgressBar extends StatelessWidget {
  final NavigationService navigationService;

  const NavigationProgressBar({
    super.key,
    required this.navigationService,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<NavigationProgress>(
      stream: navigationService.progressStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData || !navigationService.isNavigating) {
          return const SizedBox.shrink();
        }
        
        final progress = snapshot.data!;
        
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Route Progress',
                    style: TextStyle(
                      fontSize: 12,
                      color: SwiftDashColors.darkBlue.withOpacity(0.7),
                    ),
                  ),
                  Text(
                    '${(progress.progress * 100).round()}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: SwiftDashColors.lightBlue,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: progress.progress.clamp(0.0, 1.0),
                backgroundColor: SwiftDashColors.lightGray.withOpacity(0.3),
                valueColor: AlwaysStoppedAnimation<Color>(SwiftDashColors.lightBlue),
                minHeight: 4,
              ),
            ],
          ),
        );
      },
    );
  }
}