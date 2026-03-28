import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../models/daily_sales_models.dart';

/// AI Validation Badge Widget - Enhanced with Critical/Warning counts
/// Shows the validation status on sale cards in the history list
class AIValidationBadge extends StatelessWidget {
  final DailySalesRecord record;
  final bool compact;
  final VoidCallback? onTap;

  const AIValidationBadge({
    super.key,
    required this.record,
    this.compact = false,
    this.onTap,
  });

  // Color constants
  static const Color _criticalRed = Color(0xFFFF3B30);
  static const Color _warningOrange = Color(0xFFFF9500);
  static const Color _successGreen = Color(0xFF34C759);
  static const Color _infoBlue = Color(0xFF007AFF);
  static const Color _neutralGray = Color(0xFF8E8E93);

  @override
  Widget build(BuildContext context) {
    // Don't show badge if no images attached (nothing to validate)
    if (!record.hasImages) {
      return const SizedBox.shrink();
    }

    final validation = record.validationResult;
    final status = record.validationStatus;

    // Get counts from AI summary if available
    final criticalCount = validation?.criticalCount ?? 0;
    final warningCount = validation?.warningCount ?? 0;
    final mismatchCount = validation?.mismatchCount ?? 0;

    // Determine badge style based on validation status
    final (icon, label, color, bgColor) = _getBadgeStyle(
      status,
      mismatchCount,
      criticalCount,
      warningCount,
    );

    if (compact) {
      return _buildCompactBadge(icon, label, color, bgColor, criticalCount, warningCount);
    }

    return _buildFullBadge(icon, label, color, bgColor, criticalCount, warningCount, validation);
  }

  (IconData, String, Color, Color) _getBadgeStyle(
    String? status,
    int mismatchCount,
    int criticalCount,
    int warningCount,
  ) {
    switch (status) {
      case 'verified':
        return (
          CupertinoIcons.checkmark_shield_fill,
          'AI Verified',
          _successGreen,
          _successGreen.withOpacity(0.12),
        );
      case 'mismatches_found':
        // Prioritize critical count in label
        if (criticalCount > 0) {
          return (
            CupertinoIcons.xmark_circle_fill,
            '$criticalCount Critical',
            _criticalRed,
            _criticalRed.withOpacity(0.12),
          );
        } else if (warningCount > 0) {
          return (
            CupertinoIcons.exclamationmark_triangle_fill,
            '$warningCount Warning${warningCount > 1 ? 's' : ''}',
            _warningOrange,
            _warningOrange.withOpacity(0.12),
          );
        } else {
          return (
            CupertinoIcons.exclamationmark_triangle_fill,
            '$mismatchCount Issue${mismatchCount > 1 ? 's' : ''}',
            _warningOrange,
            _warningOrange.withOpacity(0.12),
          );
        }
      case 'processing':
        return (
          CupertinoIcons.sparkles,
          'AI Analyzing...',
          _infoBlue,
          _infoBlue.withOpacity(0.12),
        );
      case 'failed':
        return (
          CupertinoIcons.xmark_circle_fill,
          'Validation Failed',
          _criticalRed,
          _criticalRed.withOpacity(0.12),
        );
      case 'pending':
        return (
          CupertinoIcons.clock_fill,
          'Pending',
          _neutralGray,
          _neutralGray.withOpacity(0.12),
        );
      default:
        // No validation yet - show "AI Review" to encourage tap
        return (
          CupertinoIcons.sparkles,
          'AI Review',
          _infoBlue,
          _infoBlue.withOpacity(0.12),
        );
    }
  }

  Widget _buildCompactBadge(
    IconData icon,
    String label,
    Color color,
    Color bgColor,
    int criticalCount,
    int warningCount,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            // Show additional count chips if both critical and warning exist
            if (criticalCount > 0 && warningCount > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: _warningOrange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '+$warningCount',
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: _warningOrange,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFullBadge(
    IconData icon,
    String label,
    Color color,
    Color bgColor,
    int criticalCount,
    int warningCount,
    AIValidationResult? validation,
  ) {
    final isVerified = record.validationStatus == 'verified';
    final hasMismatches = record.validationStatus == 'mismatches_found';
    final isProcessing = record.validationStatus == 'processing';
    final accuracy = validation?.overallAccuracy ?? 0.0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: Icon + Label + Accuracy
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // AI icon with animation effect for processing
                if (isProcessing)
                  _buildPulsingIcon(icon, color)
                else
                  Icon(icon, size: 18, color: color),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                if (validation != null && validation.hasAISummary) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${accuracy.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
                ],
                if (hasMismatches) ...[
                  const Spacer(),
                  Icon(
                    CupertinoIcons.chevron_right,
                    size: 14,
                    color: color.withOpacity(0.6),
                  ),
                ],
              ],
            ),

            // Bottom row: Issue counts chips
            if (hasMismatches && (criticalCount > 0 || warningCount > 0)) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (criticalCount > 0)
                    _buildCountChip(
                      CupertinoIcons.xmark_circle_fill,
                      '$criticalCount',
                      'critical',
                      _criticalRed,
                    ),
                  if (criticalCount > 0 && warningCount > 0)
                    const SizedBox(width: 6),
                  if (warningCount > 0)
                    _buildCountChip(
                      CupertinoIcons.exclamationmark_triangle_fill,
                      '$warningCount',
                      'warnings',
                      _warningOrange,
                    ),
                ],
              ),
            ],

            // Subtitle for verified or processing
            if (isVerified) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    CupertinoIcons.checkmark_seal_fill,
                    size: 11,
                    color: color.withOpacity(0.7),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'All items match receipt',
                    style: TextStyle(
                      fontSize: 11,
                      color: color.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ] else if (isProcessing) ...[
              const SizedBox(height: 4),
              Text(
                'AI is comparing entry with receipt...',
                style: TextStyle(
                  fontSize: 11,
                  color: color.withOpacity(0.8),
                ),
              ),
            ] else if (hasMismatches) ...[
              const SizedBox(height: 4),
              Text(
                'Tap to review AI insights',
                style: TextStyle(
                  fontSize: 11,
                  color: color.withOpacity(0.8),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCountChip(IconData icon, String count, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            '$count $label',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPulsingIcon(IconData icon, Color color) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.5, end: 1.0),
      duration: const Duration(milliseconds: 800),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Icon(icon, size: 18, color: color),
        );
      },
      onEnd: () {},
    );
  }
}

/// Small indicator dot for validation status
/// Used in tight spaces where full badge doesn't fit
class AIValidationDot extends StatelessWidget {
  final String? validationStatus;
  final double size;

  const AIValidationDot({
    super.key,
    this.validationStatus,
    this.size = 8,
  });

  @override
  Widget build(BuildContext context) {
    final color = _getStatusColor(validationStatus);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.4),
            blurRadius: 4,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'verified':
        return const Color(0xFF34C759); // iOS green
      case 'mismatches_found':
        return const Color(0xFFFF9500); // iOS orange
      case 'processing':
        return const Color(0xFF007AFF); // iOS blue
      case 'failed':
        return const Color(0xFFFF3B30); // iOS red
      default:
        return const Color(0xFF8E8E93); // iOS gray
    }
  }
}

/// Enhanced AI badge with sparkle animation for promotional use
class AISparklingBadge extends StatefulWidget {
  final String text;
  final VoidCallback? onTap;

  const AISparklingBadge({
    super.key,
    this.text = 'AI Powered',
    this.onTap,
  });

  @override
  State<AISparklingBadge> createState() => _AISparklingBadgeState();
}

class _AISparklingBadgeState extends State<AISparklingBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _sparkleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
    _sparkleAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _sparkleAnimation,
        builder: (context, child) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF667eea).withOpacity(_sparkleAnimation.value),
                  const Color(0xFF764ba2).withOpacity(_sparkleAnimation.value),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF667eea).withOpacity(0.3 * _sparkleAnimation.value),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  CupertinoIcons.sparkles,
                  size: 14,
                  color: Colors.white,
                ),
                const SizedBox(width: 6),
                Text(
                  widget.text,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
