import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/animation_constants.dart';

/// Live Accuracy Meter Widget
///
/// Features:
/// - Large animated circular meter
/// - Real-time accuracy percentage (90-95% target)
/// - Color-coded confidence levels
/// - Breakdown by confidence category
/// - Smooth gradient animations
class AccuracyMeterWidget extends StatefulWidget {
  final double accuracy; // 0.0 to 1.0 (0% to 100%)
  final int highConfidenceCount;
  final int mediumConfidenceCount;
  final int lowConfidenceCount;
  final bool showBreakdown;
  final VoidCallback? onTap;

  const AccuracyMeterWidget({
    super.key,
    required this.accuracy,
    this.highConfidenceCount = 0,
    this.mediumConfidenceCount = 0,
    this.lowConfidenceCount = 0,
    this.showBreakdown = true,
    this.onTap,
  });

  @override
  State<AccuracyMeterWidget> createState() => _AccuracyMeterWidgetState();
}

class _AccuracyMeterWidgetState extends State<AccuracyMeterWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _shimmerController;
  late Animation<double> _shimmerAnimation;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: AnimationConstants.shimmer,
    )..repeat();

    _shimmerAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.linear),
    );
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  Color _getAccuracyColor(double accuracy) {
    if (accuracy >= 0.9) return AppColors.success; // 90%+: Excellent
    if (accuracy >= 0.8) return AppColors.info; // 80-90%: Good
    if (accuracy >= 0.7) return AppColors.warning; // 70-80%: Fair
    return AppColors.error; // <70%: Poor
  }

  String _getAccuracyLabel(double accuracy) {
    if (accuracy >= 0.95) return 'Excellent';
    if (accuracy >= 0.9) return 'Very Good';
    if (accuracy >= 0.8) return 'Good';
    if (accuracy >= 0.7) return 'Fair';
    return 'Needs Review';
  }

  IconData _getAccuracyIcon(double accuracy) {
    if (accuracy >= 0.9) return Icons.verified_rounded;
    if (accuracy >= 0.8) return Icons.check_circle_rounded;
    if (accuracy >= 0.7) return Icons.info_rounded;
    return Icons.warning_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final accuracyColor = _getAccuracyColor(widget.accuracy);

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              accuracyColor.withOpacity(0.1),
              accuracyColor.withOpacity(0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: accuracyColor.withOpacity(0.3),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: accuracyColor.withOpacity(0.2),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Accuracy Meter
            _buildAccuracyMeter(accuracyColor),

            if (widget.showBreakdown) ...[
              const SizedBox(height: 24),
              _buildConfidenceBreakdown(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAccuracyMeter(Color color) {
    final percentage = (widget.accuracy * 100).toInt();

    return Stack(
      alignment: Alignment.center,
      children: [
        // Animated shimmer background
        AnimatedBuilder(
          animation: _shimmerAnimation,
          builder: (context, child) {
            return CustomPaint(
              size: const Size(200, 200),
              painter: _ShimmerRingPainter(
                color: color.withOpacity(0.1),
                shimmerProgress: _shimmerAnimation.value,
              ),
            );
          },
        ),

        // Main progress ring
        SizedBox(
          width: 200,
          height: 200,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Background ring
              CustomPaint(
                size: const Size(200, 200),
                painter: _AccuracyRingPainter(
                  progress: 1.0,
                  color: Theme.of(context).colorScheme.outline,
                  strokeWidth: 16,
                ),
              ),

              // Progress ring with gradient
              TweenAnimationBuilder<double>(
                duration: AnimationConstants.slow,
                curve: Curves.easeOutCubic,
                tween: Tween(begin: 0.0, end: widget.accuracy),
                builder: (context, value, child) {
                  return CustomPaint(
                    size: const Size(200, 200),
                    painter: _AccuracyRingPainter(
                      progress: value,
                      color: color,
                      strokeWidth: 16,
                      useGradient: true,
                    ),
                  );
                },
              ),

              // Center content
              _buildCenterContent(percentage, color),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCenterContent(int percentage, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Icon
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            _getAccuracyIcon(widget.accuracy),
            color: color,
            size: 32,
          ),
        ),

        const SizedBox(height: 12),

        // Percentage
        TweenAnimationBuilder<int>(
          duration: AnimationConstants.slow,
          curve: Curves.easeOutCubic,
          tween: IntTween(begin: 0, end: percentage),
          builder: (context, value, child) {
            return Text(
              '$value%',
              style: AppTextStyles.h1.copyWith(
                fontSize: 56,
                fontWeight: FontWeight.w900,
                color: color,
                height: 1.0,
                letterSpacing: -2,
              ),
            );
          },
        ),

        const SizedBox(height: 4),

        // Label
        Text(
          _getAccuracyLabel(widget.accuracy),
          style: AppTextStyles.bodyMedium.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildConfidenceBreakdown() {
    final total = widget.highConfidenceCount +
        widget.mediumConfidenceCount +
        widget.lowConfidenceCount;

    if (total == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        children: [
          _buildBreakdownItem(
            icon: Icons.verified_rounded,
            label: 'High Confidence',
            count: widget.highConfidenceCount,
            color: AppColors.success,
          ),
          if (widget.mediumConfidenceCount > 0) ...[
            const SizedBox(height: 12),
            _buildBreakdownItem(
              icon: Icons.info_rounded,
              label: 'Medium',
              count: widget.mediumConfidenceCount,
              color: AppColors.warning,
            ),
          ],
          if (widget.lowConfidenceCount > 0) ...[
            const SizedBox(height: 12),
            _buildBreakdownItem(
              icon: Icons.help_outline_rounded,
              label: 'Low / New',
              count: widget.lowConfidenceCount,
              color: AppColors.error,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBreakdownItem({
    required IconData icon,
    required String label,
    required int count,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.bodyMedium.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Text(
            count.toString(),
            style: AppTextStyles.bodyMedium.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

/// Custom painter for accuracy ring
class _AccuracyRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;
  final bool useGradient;

  _AccuracyRingPainter({
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

    if (useGradient) {
      final rect = Rect.fromCircle(center: center, radius: radius);
      paint.shader = SweepGradient(
        colors: [
          color,
          color.withOpacity(0.5),
          color.withOpacity(0.3),
          color,
        ],
        stops: const [0.0, 0.3, 0.7, 1.0],
        startAngle: startAngle,
        endAngle: startAngle + 2 * math.pi,
      ).createShader(rect);
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
  bool shouldRepaint(_AccuracyRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

/// Custom painter for shimmer effect
class _ShimmerRingPainter extends CustomPainter {
  final Color color;
  final double shimmerProgress;

  _ShimmerRingPainter({
    required this.color,
    required this.shimmerProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final startAngle = -math.pi / 2 + (2 * math.pi * shimmerProgress);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 20
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromCircle(center: center, radius: radius);
    paint.shader = SweepGradient(
      colors: [
        Colors.transparent,
        color,
        Colors.transparent,
      ],
      stops: const [0.0, 0.5, 1.0],
      startAngle: startAngle,
      endAngle: startAngle + math.pi / 2,
    ).createShader(rect);

    canvas.drawArc(
      rect,
      startAngle,
      math.pi / 2,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_ShimmerRingPainter oldDelegate) {
    return oldDelegate.shimmerProgress != shimmerProgress;
  }
}
