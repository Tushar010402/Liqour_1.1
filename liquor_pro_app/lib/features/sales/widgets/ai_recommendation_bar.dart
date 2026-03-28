import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import '../models/daily_sales_models.dart';

/// AI Recommendation Bar - Bottom action bar with AI-powered decision suggestions
/// Shows recommended action (approve/review/reject) with quick action buttons
class AIRecommendationBar extends StatelessWidget {
  final AIValidationResult validationResult;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final VoidCallback? onViewDetails;
  final bool isLoading;

  const AIRecommendationBar({
    super.key,
    required this.validationResult,
    this.onApprove,
    this.onReject,
    this.onViewDetails,
    this.isLoading = false,
  });

  // Color constants
  static const Color _criticalRed = Color(0xFFFF3B30);
  static const Color _warningOrange = Color(0xFFFF9500);
  static const Color _successGreen = Color(0xFF34C759);
  static const Color _infoBlue = Color(0xFF007AFF);

  String get _recommendedAction =>
      validationResult.aiSummary?.recommendedAction ?? 'review';

  Color get _primaryColor {
    switch (_recommendedAction) {
      case 'approve':
        return _successGreen;
      case 'reject':
        return _criticalRed;
      default:
        return _warningOrange;
    }
  }

  IconData get _actionIcon {
    switch (_recommendedAction) {
      case 'approve':
        return CupertinoIcons.checkmark_seal_fill;
      case 'reject':
        return CupertinoIcons.xmark_seal_fill;
      default:
        return CupertinoIcons.eye_fill;
    }
  }

  String get _actionLabel {
    switch (_recommendedAction) {
      case 'approve':
        return 'AI Recommends: Approve';
      case 'reject':
        return 'AI Recommends: Reject';
      default:
        return 'AI Recommends: Review Required';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 16,
      ),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // AI Recommendation header
          _buildRecommendationHeader(cs),

          const SizedBox(height: 16),

          // Quick stats
          _buildQuickStats(),

          const SizedBox(height: 16),

          // Action buttons
          _buildActionButtons(context, cs),
        ],
      ),
    );
  }

  Widget _buildRecommendationHeader(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _primaryColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _primaryColor.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          // AI icon
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _primaryColor,
                  _primaryColor.withOpacity(0.8),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _actionIcon,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),

          // Recommendation text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      CupertinoIcons.sparkles,
                      size: 14,
                      color: Colors.amber,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'AI ANALYSIS',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurfaceVariant,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _actionLabel,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _primaryColor,
                  ),
                ),
              ],
            ),
          ),

          // Accuracy score
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _primaryColor.withOpacity(0.3),
              ),
            ),
            child: Column(
              children: [
                Text(
                  '${validationResult.overallAccuracy.toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _primaryColor,
                  ),
                ),
                Text(
                  'accuracy',
                  style: TextStyle(
                    fontSize: 10,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStats() {
    final critical = validationResult.criticalCount;
    final warnings = validationResult.warningCount;
    final matched = validationResult.aiSummary?.matchedCount ??
        validationResult.matchedCount;

    return Row(
      children: [
        Expanded(
          child: _buildStatChip(
            icon: CupertinoIcons.xmark_circle_fill,
            label: '$critical Critical',
            color: _criticalRed,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatChip(
            icon: CupertinoIcons.exclamationmark_triangle_fill,
            label: '$warnings Warnings',
            color: _warningOrange,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatChip(
            icon: CupertinoIcons.checkmark_circle_fill,
            label: '$matched Matched',
            color: _successGreen,
          ),
        ),
      ],
    );
  }

  Widget _buildStatChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, ColorScheme cs) {
    return Row(
      children: [
        // View Details button
        if (onViewDetails != null)
          Expanded(
            child: _ActionButton(
              label: 'View Details',
              icon: CupertinoIcons.list_bullet_below_rectangle,
              color: cs.onSurface,
              backgroundColor: cs.surfaceContainerHighest,
              onTap: isLoading ? null : onViewDetails,
              isLoading: false,
            ),
          ),

        if (onViewDetails != null) const SizedBox(width: 10),

        // Reject button
        if (onReject != null)
          Expanded(
            child: _ActionButton(
              label: 'Reject',
              icon: CupertinoIcons.xmark,
              color: _criticalRed,
              backgroundColor: _criticalRed.withOpacity(0.1),
              onTap: isLoading ? null : onReject,
              isLoading: false,
            ),
          ),

        if (onReject != null) const SizedBox(width: 10),

        // Approve button
        if (onApprove != null)
          Expanded(
            flex: 2,
            child: _ActionButton(
              label: _recommendedAction == 'approve'
                  ? 'Approve (Recommended)'
                  : 'Approve',
              icon: CupertinoIcons.checkmark,
              color: Colors.white,
              backgroundColor: _recommendedAction == 'approve'
                  ? _successGreen
                  : _infoBlue,
              onTap: isLoading ? null : onApprove,
              isLoading: isLoading,
              isPrimary: true,
            ),
          ),
      ],
    );
  }
}

/// Individual action button
class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final Color backgroundColor;
  final VoidCallback? onTap;
  final bool isLoading;
  final bool isPrimary;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.backgroundColor,
    this.onTap,
    this.isLoading = false,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (onTap != null) {
            HapticFeedback.mediumImpact();
            onTap!();
          }
        },
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(14),
            boxShadow: isPrimary
                ? [
                    BoxShadow(
                      color: backgroundColor.withOpacity(0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: isLoading
                ? Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 16, color: color),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: color,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
