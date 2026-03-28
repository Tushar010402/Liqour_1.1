import 'package:flutter/material.dart';
import 'dart:async';
import '../../../core/constants/app_colors.dart';

/// Modern OCR Progress Widget with Polling Fallback
/// Shows progress even when WebSocket is unavailable
class ModernOCRProgress extends StatefulWidget {
  final String sessionId;
  final Function(String sessionId) onPollProgress;
  final Stream<Map<String, dynamic>>? websocketStream;
  final VoidCallback? onComplete;
  final VoidCallback? onError;

  const ModernOCRProgress({
    super.key,
    required this.sessionId,
    required this.onPollProgress,
    this.websocketStream,
    this.onComplete,
    this.onError,
  });

  @override
  State<ModernOCRProgress> createState() => _ModernOCRProgressState();
}

class _ModernOCRProgressState extends State<ModernOCRProgress>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;
  Timer? _pollTimer;
  StreamSubscription? _wsSubscription;

  double _progress = 0.0;
  String _currentStage = 'Starting...';
  int _processedImages = 0;
  int _totalImages = 0;
  bool _usePolling = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _setupProgressMonitoring();
  }

  void _setupProgressMonitoring() {
    // Try WebSocket first
    if (widget.websocketStream != null) {
      _wsSubscription = widget.websocketStream!.listen(
        (data) {
          _updateProgress(data);
        },
        onError: (_) {
          // WebSocket failed, fall back to polling
          _startPolling();
        },
      );

      // Start polling as backup after 5 seconds if no WebSocket updates
      Future.delayed(const Duration(seconds: 5), () {
        if (_progress == 0 && mounted) {
          _startPolling();
        }
      });
    } else {
      // No WebSocket available, use polling immediately
      _startPolling();
    }
  }

  void _startPolling() {
    if (_usePolling) return; // Already polling

    setState(() {
      _usePolling = true;
      _currentStage = 'Processing (polling for updates)...';
    });

    _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      widget.onPollProgress(widget.sessionId);
    });
  }

  void _updateProgress(Map<String, dynamic> data) {
    if (!mounted) return;

    setState(() {
      _progress = (data['progress'] as num?)?.toDouble() ?? _progress;
      _currentStage = data['stage'] as String? ?? _currentStage;
      _processedImages = data['processed_images'] as int? ?? _processedImages;
      _totalImages = data['total_images'] as int? ?? _totalImages;

      if (_progress >= 100) {
        _controller.stop();
        widget.onComplete?.call();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _pollTimer?.cancel();
    _wsSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Animated progress icon
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseAnimation.value,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        Theme.of(context).primaryColor,
                        Theme.of(context).primaryColor.withValues(alpha: 0.6),
                      ],
                    ),
                  ),
                  child: Icon(
                    _progress >= 100
                        ? Icons.check_circle_rounded
                        : Icons.auto_awesome_rounded,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 24),

          // Stage text
          Text(
            _currentStage,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 16),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _progress / 100,
              minHeight: 8,
              backgroundColor: cs.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).primaryColor,
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Progress text
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_progress.toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).primaryColor,
                ),
              ),
              if (_totalImages > 0)
                Text(
                  '$_processedImages / $_totalImages images',
                  style: TextStyle(
                    fontSize: 14,
                    color: cs.onSurfaceVariant,
                  ),
                ),
            ],
          ),

          // Connection method indicator
          if (_usePolling) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.sync_rounded,
                    size: 16,
                    color: AppColors.info,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Auto-refreshing',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.info,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Public method to update progress from parent (for polling)
  void updateProgressFromPoll(Map<String, dynamic> data) {
    _updateProgress(data);
  }
}
