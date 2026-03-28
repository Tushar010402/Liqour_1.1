import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Phase 3.3: Haptic feedback
import 'dart:math' as math;
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/animation_constants.dart';
import '../../../core/services/image_preprocessing_service.dart' show ProcessingStepInfo, ProcessingStepStatus;

/// Real-Time Progress Indicator with Step Breakdown
///
/// Features:
/// - Animated circular progress with gradient ring
/// - Step-by-step progress breakdown
/// - Live percentage display
/// - Estimated time remaining
/// - Color-coded confidence levels
/// - Current item display (Phase 2.1)
/// - Items extracted counter (Phase 2.2)
class RealTimeProgressIndicator extends StatefulWidget {
  final double progress; // 0.0 to 1.0
  final String currentStep;
  final List<ProcessingStepInfo> steps;
  final Duration? estimatedTimeRemaining;
  final bool showSteps;
  // Phase 2.1: Current item being processed
  final String? currentItem;
  // Phase 2.2: Total items extracted so far
  final int? itemsExtracted;
  // Phase 2.4: Current processing stage for icon mapping
  final String? stage;

  const RealTimeProgressIndicator({
    super.key,
    required this.progress,
    required this.currentStep,
    required this.steps,
    this.estimatedTimeRemaining,
    this.showSteps = true,
    this.currentItem,
    this.itemsExtracted,
    this.stage,
  });

  @override
  State<RealTimeProgressIndicator> createState() => _RealTimeProgressIndicatorState();
}

class _RealTimeProgressIndicatorState extends State<RealTimeProgressIndicator>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Phase 3: Polish animations
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;
  late AnimationController _breathingController;
  late Animation<double> _breathingAnimation;

  // Phase 3.3: Track previous values for haptic feedback
  int? _previousItemsExtracted;
  String? _previousStage;

  @override
  void initState() {
    super.initState();

    // Existing pulse animation for progress ring
    _pulseController = AnimationController(
      vsync: this,
      duration: AnimationConstants.shimmer,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Phase 3.5: Scale animation for milestone celebrations
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.2)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.2, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 70,
      ),
    ]).animate(_scaleController);

    // Phase 3.5: Breathing animation for current item card
    _breathingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _breathingAnimation = Tween<double>(begin: 1.0, end: 1.02).animate(
      CurvedAnimation(parent: _breathingController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scaleController.dispose();
    _breathingController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(RealTimeProgressIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Phase 3.3: Detect milestone achievements and trigger haptic feedback
    if (widget.itemsExtracted != null && _previousItemsExtracted != null) {
      final current = widget.itemsExtracted!;
      final previous = _previousItemsExtracted!;

      // Check if we crossed a milestone threshold
      bool crossedMilestone = false;

      if (previous < 10 && current >= 10) {
        crossedMilestone = true;
      } else if (previous < 25 && current >= 25) {
        crossedMilestone = true;
      } else if (previous < 50 && current >= 50) {
        crossedMilestone = true;
      }

      if (crossedMilestone) {
        // Trigger celebration animations
        _scaleController.forward(from: 0);
        // Haptic feedback - medium impact for milestone
        HapticFeedback.mediumImpact();
      }
    }

    // Phase 3.3: Haptic feedback on stage change
    if (widget.stage != null && _previousStage != null && widget.stage != _previousStage) {
      // Light haptic feedback for stage transition
      HapticFeedback.selectionClick();
    }

    // Update previous values
    _previousItemsExtracted = widget.itemsExtracted;
    _previousStage = widget.stage;
  }

  Color _getProgressColor(double progress) {
    if (progress < 0.5) return AppColors.warning;
    if (progress < 0.8) return AppColors.info;
    return AppColors.success;
  }

  /// Phase 2.4: Map processing stage to icon
  /// Returns appropriate icon for each OCR processing stage
  IconData _getStageIcon(String? stage) {
    switch (stage) {
      case 'text_extraction':
        return Icons.document_scanner_rounded;
      case 'brand_matching':
        return Icons.search_rounded;
      case 'validation':
        return Icons.check_circle_outline_rounded;
      case 'stock_calculation':
        return Icons.inventory_rounded;
      default:
        return Icons.cloud_upload_rounded; // Upload/default
    }
  }

  /// Phase 2.4: Get color for stage icon
  /// Color-code icons by processing stage for visual distinction
  Color _getStageIconColor(String? stage, ColorScheme cs) {
    switch (stage) {
      case 'text_extraction':
        return AppColors.info;
      case 'brand_matching':
        return cs.primary;
      case 'validation':
        return AppColors.success;
      case 'stock_calculation':
        return AppColors.warning;
      default:
        return Colors.white70; // Upload/default
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final percentage = (widget.progress * 100).toInt();
    final progressColor = _getProgressColor(widget.progress);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: progressColor.withValues(alpha: 0.1),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Circular Progress Meter
          _buildCircularProgress(cs, percentage, progressColor),

          const SizedBox(height: 24),

          // Current Step
          _buildCurrentStepIndicator(),

          // Phase 2.1: Current Item Display
          if (widget.currentItem != null) ...[
            const SizedBox(height: 16),
            _buildCurrentItemDisplay(cs),
          ],

          // Phase 2.2: Items Extracted Counter
          if (widget.itemsExtracted != null && widget.itemsExtracted! > 0) ...[
            const SizedBox(height: 12),
            _buildItemsExtractedCounter(cs),
          ],

          if (widget.estimatedTimeRemaining != null) ...[
            const SizedBox(height: 12),
            _buildTimeRemaining(cs),
          ],

          if (widget.showSteps) ...[
            const SizedBox(height: 24),
            _buildStepsList(cs),
          ],
        ],
      ),
    );
  }

  Widget _buildCircularProgress(ColorScheme cs, int percentage, Color color) {
    // Phase 3.4: Smooth color transitions
    return TweenAnimationBuilder<Color?>(
      duration: AnimationConstants.moderate,
      tween: ColorTween(begin: color, end: color),
      builder: (context, animatedColor, child) {
        return AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _pulseAnimation.value,
              child: SizedBox(
                width: 180,
                height: 180,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Background circle
                    CustomPaint(
                      size: const Size(180, 180),
                      painter: _ProgressRingPainter(
                    progress: 1.0,
                    color: cs.outlineVariant,
                    strokeWidth: 12,
                  ),
                ),

                // Progress circle with gradient
                TweenAnimationBuilder<double>(
                  duration: AnimationConstants.moderate,
                  curve: Curves.easeOutCubic,
                  tween: Tween(begin: 0.0, end: widget.progress),
                  builder: (context, value, child) {
                    return CustomPaint(
                      size: const Size(180, 180),
                      painter: _ProgressRingPainter(
                        progress: value,
                        color: animatedColor ?? color, // Phase 3.4: Smooth color transition
                        strokeWidth: 12,
                        useGradient: true,
                      ),
                    );
                  },
                ),

                // Percentage Text
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TweenAnimationBuilder<int>(
                      duration: AnimationConstants.moderate,
                      curve: Curves.easeOutCubic,
                      tween: IntTween(begin: 0, end: percentage),
                      builder: (context, value, child) {
                        return Text(
                          '$value%',
                          style: AppTextStyles.h1.copyWith(
                            fontSize: 48,
                            fontWeight: FontWeight.w900,
                            color: animatedColor ?? color, // Phase 3.4: Smooth color transition
                            height: 1.0,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _getStatusText(widget.progress),
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
        ); // Close AnimatedBuilder
      }, // Close TweenAnimationBuilder for color transition
    );
  }

  Widget _buildCurrentStepIndicator() {
    final cs = Theme.of(context).colorScheme;
    // Phase 2.4: Get stage-specific icon and color
    final stageIcon = _getStageIcon(widget.stage);
    final iconColor = _getStageIconColor(widget.stage, cs);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Phase 2.4: Animated stage icon with smooth morphing
          AnimatedSwitcher(
            duration: AnimationConstants.moderate,
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(
                opacity: animation,
                child: RotationTransition(
                  turns: Tween<double>(begin: 0.8, end: 1.0).animate(animation),
                  child: child,
                ),
              );
            },
            child: Icon(
              stageIcon,
              key: ValueKey<String>(widget.stage ?? 'default'),
              size: 22,
              color: iconColor,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              widget.currentStep,
              style: AppTextStyles.bodyMedium.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  /// Phase 2.1: Display current item being processed
  /// Shows what specific item OCR is currently analyzing
  Widget _buildCurrentItemDisplay(ColorScheme cs) {
    return AnimatedSwitcher(
      duration: AnimationConstants.moderate,
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.3),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      // Phase 3.5: Wrap with breathing animation
      child: AnimatedBuilder(
        animation: _breathingAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _breathingAnimation.value,
            child: child,
          );
        },
        child: Container(
          key: ValueKey<String>(widget.currentItem!),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: cs.primary.withValues(alpha: 0.2),
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.inventory_2_rounded,
                size: 18,
                color: cs.primary,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  'Processing: ${widget.currentItem}',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Phase 2.2: Animated counter for items extracted
  /// Shows running count of items found with smooth animation
  Widget _buildItemsExtractedCounter(ColorScheme cs) {
    return TweenAnimationBuilder<int>(
      duration: AnimationConstants.moderate,
      curve: Curves.easeOutCubic,
      tween: IntTween(begin: 0, end: widget.itemsExtracted!),
      builder: (context, value, child) {
        // Celebrate milestones with different colors
        Color iconColor;
        IconData icon;
        if (value >= 50) {
          iconColor = AppColors.success;
          icon = Icons.celebration_rounded;
        } else if (value >= 25) {
          iconColor = AppColors.info;
          icon = Icons.local_fire_department_rounded;
        } else if (value >= 10) {
          iconColor = AppColors.warning;
          icon = Icons.trending_up_rounded;
        } else {
          iconColor = cs.primary;
          icon = Icons.inventory_rounded;
        }

        // Phase 3.5: Wrap with scale animation for milestone celebrations
        return ScaleTransition(
          scale: _scaleAnimation,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  iconColor.withValues(alpha: 0.1),
                  iconColor.withValues(alpha: 0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: iconColor.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: iconColor,
                ),
                const SizedBox(width: 8),
                Text(
                  '$value',
                  style: AppTextStyles.h5.copyWith(
                    color: iconColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  value == 1 ? 'item found' : 'items found',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ), // Close Container
        ); // Close ScaleTransition
      },
    );
  }

  Widget _buildTimeRemaining(ColorScheme cs) {
    final seconds = widget.estimatedTimeRemaining!.inSeconds;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.access_time_rounded,
          size: 16,
          color: cs.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Text(
          seconds < 60
              ? '${seconds}s remaining'
              : '${(seconds / 60).toStringAsFixed(1)}m remaining',
          style: AppTextStyles.bodySmall.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildStepsList(ColorScheme cs) {
    return Column(
      children: widget.steps.asMap().entries.map((entry) {
        final index = entry.key;
        final step = entry.value;

        return TweenAnimationBuilder<double>(
          duration: AnimationConstants.fast,
          curve: Curves.easeOutCubic,
          tween: Tween(begin: 0.0, end: 1.0),
          builder: (context, value, child) {
            return Transform.translate(
              offset: Offset(0, 10 * (1 - value)),
              child: Opacity(
                opacity: value,
                child: child,
              ),
            );
          },
          child: Padding(
            padding: EdgeInsets.only(
              bottom: index < widget.steps.length - 1 ? 12 : 0,
            ),
            child: _buildStepItem(cs, step),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStepItem(ColorScheme cs, ProcessingStepInfo step) {
    IconData icon;
    Color color;

    switch (step.status) {
      case ProcessingStepStatus.completed:
        icon = Icons.check_circle_rounded;
        color = AppColors.success;
        break;
      case ProcessingStepStatus.inProgress:
        icon = Icons.sync_rounded;
        color = cs.primary;
        break;
      case ProcessingStepStatus.pending:
        icon = Icons.radio_button_unchecked_rounded;
        color = cs.onSurfaceVariant;
        break;
      case ProcessingStepStatus.failed:
        icon = Icons.error_rounded;
        color = AppColors.error;
        break;
    }

    return Row(
      children: [
        AnimatedContainer(
          duration: AnimationConstants.fast,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: step.status == ProcessingStepStatus.inProgress
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                )
              : Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step.name,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (step.duration != null) ...[
                const SizedBox(height: 2),
                Text(
                  '${step.duration!.inMilliseconds}ms',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _getStatusText(double progress) {
    if (progress < 0.3) return 'Starting...';
    if (progress < 0.6) return 'Processing...';
    if (progress < 0.9) return 'Almost done';
    if (progress < 1.0) return 'Finishing up';
    return 'Complete!';
  }
}

/// Custom painter for circular progress ring
class _ProgressRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;
  final bool useGradient;

  _ProgressRingPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
    this.useGradient = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    final startAngle = -math.pi / 2;
    final sweepAngle = 2 * math.pi * progress;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Only apply gradient when sweepAngle is meaningful (> 0.001 radians)
    // This prevents SweepGradient assertion failure when startAngle == endAngle
    if (useGradient && sweepAngle > 0.001) {
      paint.shader = SweepGradient(
        colors: [color, color.withValues(alpha: 0.3), color],
        stops: const [0.0, 0.5, 1.0],
        startAngle: startAngle,
        endAngle: startAngle + sweepAngle,
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    } else {
      paint.color = color;
    }

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_ProgressRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
