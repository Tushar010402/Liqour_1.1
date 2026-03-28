import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/animation_constants.dart';

/// Animated Step Indicator for Workflow Visualization
///
/// Features:
/// - Horizontal step progression
/// - Animated transitions between steps
/// - Icon morphing with status colors
/// - Progress line animation
/// - Tap to view step details
class AnimatedStepIndicator extends StatefulWidget {
  final int currentStep;
  final List<WorkflowStep> steps;
  final bool showLabels;
  final Function(int)? onStepTap;

  const AnimatedStepIndicator({
    super.key,
    required this.currentStep,
    required this.steps,
    this.showLabels = true,
    this.onStepTap,
  });

  @override
  State<AnimatedStepIndicator> createState() => _AnimatedStepIndicatorState();
}

class _AnimatedStepIndicatorState extends State<AnimatedStepIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _progressController;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: AnimationConstants.slow,
    );
  }

  @override
  void didUpdateWidget(AnimatedStepIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentStep != widget.currentStep) {
      _progressController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Steps row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(
              widget.steps.length,
              (index) => Expanded(
                child: _buildStepItem(
                  context,
                  index,
                  widget.steps[index],
                  isFirst: index == 0,
                  isLast: index == widget.steps.length - 1,
                ),
              ),
            ),
          ),

          if (widget.showLabels) ...[
            const SizedBox(height: 16),
            _buildCurrentStepLabel(),
          ],
        ],
      ),
    );
  }

  Widget _buildStepItem(BuildContext context, int index, WorkflowStep step, {required bool isFirst, required bool isLast}) {
    final cs = Theme.of(context).colorScheme;
    final isActive = index == widget.currentStep;
    final isCompleted = index < widget.currentStep;

    Color color;
    IconData icon;

    if (isCompleted) {
      color = AppColors.success;
      icon = Icons.check_circle_rounded;
    } else if (isActive) {
      color = cs.primary;
      icon = step.icon;
    } else {
      color = cs.onSurfaceVariant.withValues(alpha: 0.3);
      icon = step.icon;
    }

    return GestureDetector(
      onTap: () => widget.onStepTap?.call(index),
      child: Row(
        children: [
          // Connection line (left)
          if (!isFirst)
            Expanded(
              child: AnimatedBuilder(
                animation: _progressController,
                builder: (context, child) {
                  final progress = isCompleted ? 1.0 : (isActive ? _progressController.value : 0.0);
                  return CustomPaint(
                    painter: _ConnectorLinePainter(
                      progress: progress,
                      color: isCompleted ? AppColors.success : cs.primary,
                      backgroundColor: cs.outlineVariant,
                    ),
                    size: const Size(double.infinity, 2),
                  );
                },
              ),
            ),

          // Step circle
          _buildStepCircle(icon, color, isActive),

          // Connection line (right)
          if (!isLast)
            Expanded(
              child: AnimatedBuilder(
                animation: _progressController,
                builder: (context, child) {
                  final progress = isCompleted ? 1.0 : 0.0;
                  return CustomPaint(
                    painter: _ConnectorLinePainter(
                      progress: progress,
                      color: AppColors.success,
                      backgroundColor: cs.outlineVariant,
                    ),
                    size: const Size(double.infinity, 2),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStepCircle(IconData icon, Color color, bool isActive) {
    return TweenAnimationBuilder<double>(
      duration: AnimationConstants.moderate,
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0.8, end: isActive ? 1.2 : 1.0),
      builder: (context, scale, child) {
        return Transform.scale(
          scale: scale,
          child: child,
        );
      },
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          shape: BoxShape.circle,
          border: Border.all(
            color: color,
            width: isActive ? 3 : 2,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: isActive
            ? Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
              )
            : Icon(
                icon,
                color: color,
                size: 20,
              ),
      ),
    );
  }

  Widget _buildCurrentStepLabel() {
    final currentStep = widget.steps[widget.currentStep];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            currentStep.icon,
            color: Colors.white,
            size: 18,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              currentStep.label,
              style: AppTextStyles.bodyMedium.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for connector line with progress
class _ConnectorLinePainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color backgroundColor;

  _ConnectorLinePainter({
    required this.progress,
    required this.color,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background line
    final bgPaint = Paint()
      ..color = backgroundColor
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      bgPaint,
    );

    // Progress line
    if (progress > 0) {
      final progressPaint = Paint()
        ..color = color
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width * progress, size.height / 2),
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_ConnectorLinePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/// Vertical Animated Step Indicator (Alternative Layout)
///
/// For screens with more vertical space
class VerticalAnimatedStepIndicator extends StatelessWidget {
  final int currentStep;
  final List<WorkflowStep> steps;
  final Function(int)? onStepTap;

  const VerticalAnimatedStepIndicator({
    super.key,
    required this.currentStep,
    required this.steps,
    this.onStepTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          steps.length,
          (index) => _buildVerticalStepItem(
            context,
            index,
            steps[index],
            isLast: index == steps.length - 1,
          ),
        ),
      ),
    );
  }

  Widget _buildVerticalStepItem(BuildContext context, int index, WorkflowStep step, {required bool isLast}) {
    final cs = Theme.of(context).colorScheme;
    final isActive = index == currentStep;
    final isCompleted = index < currentStep;

    Color color;
    if (isCompleted) {
      color = AppColors.success;
    } else if (isActive) {
      color = cs.primary;
    } else {
      color = cs.onSurfaceVariant.withValues(alpha: 0.3);
    }

    return GestureDetector(
      onTap: () => onStepTap?.call(index),
      child: Column(
        children: [
          Row(
            children: [
              // Step circle
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: isActive ? 3 : 2),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: color.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: isCompleted
                    ? Icon(Icons.check_circle_rounded, color: color, size: 20)
                    : isActive
                        ? Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation<Color>(color),
                              ),
                            ),
                          )
                        : Icon(step.icon, color: color, size: 20),
              ),

              const SizedBox(width: 16),

              // Step label
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.label,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: isActive ? cs.onSurface : cs.onSurfaceVariant,
                        fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    if (step.description != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        step.description!,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          // Connector line
          if (!isLast)
            Container(
              margin: const EdgeInsets.only(left: 20, top: 8, bottom: 8),
              width: 2,
              height: 40,
              color: isCompleted ? AppColors.success : cs.outlineVariant,
            ),
        ],
      ),
    );
  }
}

/// Workflow Step Data Model
class WorkflowStep {
  final String label;
  final IconData icon;
  final String? description;

  const WorkflowStep({
    required this.label,
    required this.icon,
    this.description,
  });
}

/// Predefined workflow steps for OCR process
class OCRWorkflowSteps {
  static const List<WorkflowStep> steps = [
    WorkflowStep(
      label: 'Select',
      icon: Icons.photo_library_rounded,
      description: 'Choose images',
    ),
    WorkflowStep(
      label: 'Enhance',
      icon: Icons.auto_awesome_rounded,
      description: 'Preprocessing',
    ),
    WorkflowStep(
      label: 'Scan',
      icon: Icons.document_scanner_rounded,
      description: 'OCR extraction',
    ),
    WorkflowStep(
      label: 'Match',
      icon: Icons.psychology_rounded,
      description: 'AI matching',
    ),
    WorkflowStep(
      label: 'Review',
      icon: Icons.fact_check_rounded,
      description: 'Verify results',
    ),
  ];
}
