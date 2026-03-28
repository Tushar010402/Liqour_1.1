import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

/// Modern confidence badge widget with color-coded visual feedback
///
/// Color coding:
/// - Green (80%+): High confidence match
/// - Yellow (50-79%): Medium confidence
/// - Red (<50%): Low confidence
/// - Gray: No match
class ConfidenceBadge extends StatelessWidget {
  final double? confidence;
  final bool showPercentage;
  final BadgeSize size;
  final bool showIcon;

  const ConfidenceBadge({
    super.key,
    required this.confidence,
    this.showPercentage = true,
    this.size = BadgeSize.medium,
    this.showIcon = true,
  });

  @override
  Widget build(BuildContext context) {
    if (confidence == null || confidence == 0) {
      return _NoMatchBadge(size: size, showPercentage: showPercentage);
    }

    final conf = confidence!;
    final level = _getConfidenceLevel(conf);
    final color = _getConfidenceColor(level);
    final icon = _getConfidenceIcon(level);
    final label = _getConfidenceLabel(level, conf);

    return Container(
      padding: _getPadding(),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color,
            color.withOpacity(0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(_getBorderRadius()),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showIcon) ...[
            Icon(
              icon,
              color: Colors.white,
              size: _getIconSize(),
            ),
            SizedBox(width: _getIconSpacing()),
          ],
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: _getFontSize(),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  ConfidenceLevel _getConfidenceLevel(double conf) {
    if (conf >= 0.8) return ConfidenceLevel.high;
    if (conf >= 0.5) return ConfidenceLevel.medium;
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
        return Icons.verified_rounded;
      case ConfidenceLevel.medium:
        return Icons.info_rounded;
      case ConfidenceLevel.low:
        return Icons.warning_rounded;
    }
  }

  String _getConfidenceLabel(ConfidenceLevel level, double conf) {
    if (!showPercentage) {
      switch (level) {
        case ConfidenceLevel.high:
          return 'HIGH';
        case ConfidenceLevel.medium:
          return 'MEDIUM';
        case ConfidenceLevel.low:
          return 'LOW';
      }
    }
    return '${(conf * 100).round()}%';
  }

  EdgeInsets _getPadding() {
    switch (size) {
      case BadgeSize.small:
        return const EdgeInsets.symmetric(horizontal: 8, vertical: 4);
      case BadgeSize.medium:
        return const EdgeInsets.symmetric(horizontal: 10, vertical: 6);
      case BadgeSize.large:
        return const EdgeInsets.symmetric(horizontal: 12, vertical: 8);
    }
  }

  double _getBorderRadius() {
    switch (size) {
      case BadgeSize.small:
        return 6;
      case BadgeSize.medium:
        return 8;
      case BadgeSize.large:
        return 10;
    }
  }

  double _getIconSize() {
    switch (size) {
      case BadgeSize.small:
        return 14;
      case BadgeSize.medium:
        return 16;
      case BadgeSize.large:
        return 18;
    }
  }

  double _getIconSpacing() {
    switch (size) {
      case BadgeSize.small:
        return 4;
      case BadgeSize.medium:
        return 6;
      case BadgeSize.large:
        return 8;
    }
  }

  double _getFontSize() {
    switch (size) {
      case BadgeSize.small:
        return 11;
      case BadgeSize.medium:
        return 13;
      case BadgeSize.large:
        return 15;
    }
  }
}

class _NoMatchBadge extends StatelessWidget {
  final BadgeSize size;
  final bool showPercentage;

  const _NoMatchBadge({
    required this.size,
    required this.showPercentage,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: _getPadding(),
      decoration: BoxDecoration(
        color: cs.onSurfaceVariant,
        borderRadius: BorderRadius.circular(_getBorderRadius()),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.help_outline_rounded,
            color: Colors.white,
            size: _getIconSize(),
          ),
          SizedBox(width: _getIconSpacing()),
          Text(
            'NEW',
            style: TextStyle(
              color: Colors.white,
              fontSize: _getFontSize(),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  EdgeInsets _getPadding() {
    switch (size) {
      case BadgeSize.small:
        return const EdgeInsets.symmetric(horizontal: 8, vertical: 4);
      case BadgeSize.medium:
        return const EdgeInsets.symmetric(horizontal: 10, vertical: 6);
      case BadgeSize.large:
        return const EdgeInsets.symmetric(horizontal: 12, vertical: 8);
    }
  }

  double _getBorderRadius() {
    switch (size) {
      case BadgeSize.small:
        return 6;
      case BadgeSize.medium:
        return 8;
      case BadgeSize.large:
        return 10;
    }
  }

  double _getIconSize() {
    switch (size) {
      case BadgeSize.small:
        return 14;
      case BadgeSize.medium:
        return 16;
      case BadgeSize.large:
        return 18;
    }
  }

  double _getIconSpacing() {
    switch (size) {
      case BadgeSize.small:
        return 4;
      case BadgeSize.medium:
        return 6;
      case BadgeSize.large:
        return 8;
    }
  }

  double _getFontSize() {
    switch (size) {
      case BadgeSize.small:
        return 11;
      case BadgeSize.medium:
        return 13;
      case BadgeSize.large:
        return 15;
    }
  }
}

enum ConfidenceLevel {
  high,
  medium,
  low,
}

enum BadgeSize {
  small,
  medium,
  large,
}
