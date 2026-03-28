import 'package:flutter/material.dart';
import 'dart:async';

/// Modern connection status indicator with smooth animations
/// Shows online/offline status with visual feedback
class ConnectionStatusIndicator extends StatefulWidget {
  final bool isConnected;
  final VoidCallback? onTap;
  final bool showLabel;

  const ConnectionStatusIndicator({
    super.key,
    required this.isConnected,
    this.onTap,
    this.showLabel = true,
  });

  @override
  State<ConnectionStatusIndicator> createState() => _ConnectionStatusIndicatorState();
}

class _ConnectionStatusIndicatorState extends State<ConnectionStatusIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    if (!widget.isConnected) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(ConnectionStatusIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isConnected != oldWidget.isConnected) {
      if (widget.isConnected) {
        _controller.stop();
        _controller.value = 0.0;
      } else {
        _controller.repeat(reverse: true);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isConnected) {
      return const SizedBox.shrink(); // Don't show when connected
    }

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _pulseAnimation.value,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: widget.showLabel ? 12 : 8,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.orange.shade300),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.cloud_off_rounded,
                    size: 16,
                    color: Colors.orange.shade700,
                  ),
                  if (widget.showLabel) ...[
                    const SizedBox(width: 6),
                    Text(
                      'Offline',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Global snackbar for connection status changes
class ConnectionStatusSnackbar {
  static Timer? _dismissTimer;

  static void show(BuildContext context, {required bool isConnected}) {
    // Cancel previous timer
    _dismissTimer?.cancel();

    final scaffoldMessenger = ScaffoldMessenger.of(context);

    // Clear existing snackbars
    scaffoldMessenger.clearSnackBars();

    // Show new snackbar
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isConnected ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isConnected
                    ? 'Back online - All services restored'
                    : 'No internet connection - Working offline',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: isConnected ? Colors.green : Colors.orange.shade700,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: isConnected ? 2 : 5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
