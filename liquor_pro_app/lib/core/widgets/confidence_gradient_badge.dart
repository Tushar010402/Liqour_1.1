import 'package:flutter/material.dart';

/// Confidence badge with gradient color based on confidence level
/// Features:
/// - Green gradient for high confidence (>80%)
/// - Yellow gradient for medium confidence (50-80%)
/// - Red gradient for low confidence (<50%)
/// - Animated transitions
/// - Optional percentage display
class ConfidenceGradientBadge extends StatelessWidget {
  final double confidence; // 0.0 to 1.0 or 0 to 100
  final bool showPercentage;
  final double size;
  final bool compact;
  final EdgeInsets? padding;

  const ConfidenceGradientBadge({
    super.key,
    required this.confidence,
    this.showPercentage = true,
    this.size = 24,
    this.compact = false,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    // Normalize confidence to 0-1 range
    final normalizedConfidence = confidence > 1.0 ? confidence / 100.0 : confidence;
    final percentage = (normalizedConfidence * 100).round();

    // Determine confidence level
    final level = _getConfidenceLevel(normalizedConfidence);
    final colors = _getGradientColors(level);
    final icon = _getConfidenceIcon(level);
    final label = _getConfidenceLabel(level);

    if (compact) {
      return _buildCompactBadge(
        context,
        level,
        colors,
        icon,
        percentage,
      );
    }

    return Container(
      padding: padding ??
          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: colors.first.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: size,
            color: Colors.white,
          ),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showPercentage)
                Text(
                  '$percentage%',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompactBadge(
    BuildContext context,
    ConfidenceLevel level,
    List<Color> colors,
    IconData icon,
    int percentage,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: Colors.white,
          ),
          if (showPercentage) ...[
            const SizedBox(width: 4),
            Text(
              '$percentage%',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }

  ConfidenceLevel _getConfidenceLevel(double normalizedConfidence) {
    if (normalizedConfidence >= 0.8) {
      return ConfidenceLevel.high;
    } else if (normalizedConfidence >= 0.5) {
      return ConfidenceLevel.medium;
    } else {
      return ConfidenceLevel.low;
    }
  }

  List<Color> _getGradientColors(ConfidenceLevel level) {
    switch (level) {
      case ConfidenceLevel.high:
        return [const Color(0xFF34C759), const Color(0xFF30D158)];
      case ConfidenceLevel.medium:
        return [const Color(0xFFFFCC00), const Color(0xFFFFB800)];
      case ConfidenceLevel.low:
        return [const Color(0xFFFF3B30), const Color(0xFFFF453A)];
    }
  }

  IconData _getConfidenceIcon(ConfidenceLevel level) {
    switch (level) {
      case ConfidenceLevel.high:
        return Icons.check_circle_rounded;
      case ConfidenceLevel.medium:
        return Icons.warning_rounded;
      case ConfidenceLevel.low:
        return Icons.error_rounded;
    }
  }

  String _getConfidenceLabel(ConfidenceLevel level) {
    switch (level) {
      case ConfidenceLevel.high:
        return 'High Confidence';
      case ConfidenceLevel.medium:
        return 'Medium';
      case ConfidenceLevel.low:
        return 'Low Confidence';
    }
  }
}

/// Confidence level enumeration
enum ConfidenceLevel {
  high,
  medium,
  low,
}

/// Extension for confidence level utilities
extension ConfidenceLevelExtension on ConfidenceLevel {
  Color get color {
    switch (this) {
      case ConfidenceLevel.high:
        return const Color(0xFF34C759);
      case ConfidenceLevel.medium:
        return const Color(0xFFFFCC00);
      case ConfidenceLevel.low:
        return const Color(0xFFFF3B30);
    }
  }

  String get label {
    switch (this) {
      case ConfidenceLevel.high:
        return 'High Confidence';
      case ConfidenceLevel.medium:
        return 'Medium Confidence';
      case ConfidenceLevel.low:
        return 'Low Confidence';
    }
  }

  IconData get icon {
    switch (this) {
      case ConfidenceLevel.high:
        return Icons.check_circle_rounded;
      case ConfidenceLevel.medium:
        return Icons.warning_rounded;
      case ConfidenceLevel.low:
        return Icons.error_rounded;
    }
  }
}

/// Helper to get confidence level from value
ConfidenceLevel getConfidenceLevel(double confidence) {
  final normalized = confidence > 1.0 ? confidence / 100.0 : confidence;
  if (normalized >= 0.8) {
    return ConfidenceLevel.high;
  } else if (normalized >= 0.5) {
    return ConfidenceLevel.medium;
  } else {
    return ConfidenceLevel.low;
  }
}
