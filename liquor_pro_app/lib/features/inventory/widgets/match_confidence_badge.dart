import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

/// Badge showing match confidence level with appropriate styling
///
/// Confidence levels:
/// - High (0.8-1.0): Green with checkmark
/// - Medium (0.5-0.79): Yellow with alert
/// - Low (< 0.5): Red with warning
class MatchConfidenceBadge extends StatelessWidget {
  final double? confidence;
  final bool showPercentage;
  final double size;

  const MatchConfidenceBadge({
    super.key,
    required this.confidence,
    this.showPercentage = true,
    this.size = 16.0,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (confidence == null) {
      return _buildNoMatchBadge(cs);
    }

    final level = _getConfidenceLevel(confidence!);
    final color = _getConfidenceColor(level);
    final icon = _getConfidenceIcon(level);
    final label = _getConfidenceLabel(level);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: size,
            color: color,
          ),
          if (showPercentage) ...[
            const SizedBox(width: 4),
            Text(
              '${(confidence! * 100).toInt()}%',
              style: TextStyle(
                fontSize: size * 0.875,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ] else ...[
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: size * 0.875,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNoMatchBadge(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: cs.onSurfaceVariant.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cs.onSurfaceVariant.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: size,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            'No Match',
            style: TextStyle(
              fontSize: size * 0.875,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  ConfidenceLevel _getConfidenceLevel(double confidence) {
    if (confidence >= 0.8) return ConfidenceLevel.high;
    if (confidence >= 0.5) return ConfidenceLevel.medium;
    return ConfidenceLevel.low;
  }

  Color _getConfidenceColor(ConfidenceLevel level) {
    switch (level) {
      case ConfidenceLevel.high:
        return AppColors.success;
      case ConfidenceLevel.medium:
        return AppColors.warning;
      case ConfidenceLevel.low:
        return AppColors.error;
    }
  }

  IconData _getConfidenceIcon(ConfidenceLevel level) {
    switch (level) {
      case ConfidenceLevel.high:
        return Icons.check_circle_rounded;
      case ConfidenceLevel.medium:
        return Icons.info_rounded;
      case ConfidenceLevel.low:
        return Icons.warning_rounded;
    }
  }

  String _getConfidenceLabel(ConfidenceLevel level) {
    switch (level) {
      case ConfidenceLevel.high:
        return 'High Match';
      case ConfidenceLevel.medium:
        return 'Review';
      case ConfidenceLevel.low:
        return 'Low Match';
    }
  }
}

/// Confidence level enum
enum ConfidenceLevel {
  high,
  medium,
  low,
}

/// Helper extension for confidence display
extension ConfidenceDisplay on double {
  /// Get confidence as percentage string
  String toPercentageString() => '${(this * 100).toInt()}%';

  /// Check if high confidence
  bool get isHighConfidence => this >= 0.8;

  /// Check if medium confidence
  bool get isMediumConfidence => this >= 0.5 && this < 0.8;

  /// Check if low confidence
  bool get isLowConfidence => this < 0.5;
}
