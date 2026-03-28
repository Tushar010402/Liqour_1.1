import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../models/daily_sales_models.dart';

/// AI Summary Banner - Top-level validation overview
/// Shows accuracy score, issue counts, and AI recommendation
class AISummaryBanner extends StatelessWidget {
  final AIValidationResult validationResult;
  final VoidCallback? onTapDetails;

  const AISummaryBanner({
    super.key,
    required this.validationResult,
    this.onTapDetails,
  });

  // Color constants matching iOS design
  static const Color _criticalRed = Color(0xFFFF3B30);
  static const Color _warningOrange = Color(0xFFFF9500);
  static const Color _successGreen = Color(0xFF34C759);
  static const Color _lowGray = Color(0xFF8E8E93);

  /// Get color based on accuracy level
  Color get _accuracyColor {
    final accuracy = validationResult.overallAccuracy;
    if (accuracy >= 80) return _successGreen;
    if (accuracy >= 50) return _warningOrange;
    return _criticalRed;
  }

  /// Get icon based on recommendation
  IconData get _recommendationIcon {
    final action = validationResult.aiSummary?.recommendedAction ?? 'review';
    switch (action) {
      case 'approve':
        return CupertinoIcons.checkmark_seal_fill;
      case 'reject':
        return CupertinoIcons.xmark_seal_fill;
      default:
        return CupertinoIcons.eye_fill;
    }
  }

  /// Get color based on recommendation
  Color get _recommendationColor {
    final action = validationResult.aiSummary?.recommendedAction ?? 'review';
    switch (action) {
      case 'approve':
        return _successGreen;
      case 'reject':
        return _criticalRed;
      default:
        return _warningOrange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final summary = validationResult.aiSummary;
    final accuracy = validationResult.overallAccuracy;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header with AI icon and title
          _buildHeader(cs),

          // Accuracy Progress Bar
          _buildAccuracyBar(accuracy, cs),

          // Issue Count Chips
          _buildIssueChips(),

          // AI Recommendation
          if (summary != null && summary.recommendation.isNotEmpty)
            _buildRecommendation(summary, cs),

          // Tap for details
          if (onTapDetails != null) _buildDetailsButton(cs),
        ],
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs) {
    final confidence = validationResult.aiSummary?.confidenceLevel ?? 'low';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.05),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Row(
        children: [
          // AI Icon
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  cs.primary,
                  cs.primary.withValues(alpha: 0.8),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              CupertinoIcons.sparkles,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),

          // Title and subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AI Validation Summary',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A1A),
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      CupertinoIcons.circle_fill,
                      size: 8,
                      color: _getConfidenceColor(confidence),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${_capitalizeFirst(confidence)} confidence',
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Status indicator
          _buildStatusBadge(),
        ],
      ),
    );
  }

  Widget _buildStatusBadge() {
    final status = validationResult.status;
    Color bgColor;
    Color textColor;
    String label;
    IconData icon;

    switch (status) {
      case 'verified':
        bgColor = _successGreen.withValues(alpha: 0.15);
        textColor = _successGreen;
        label = 'Verified';
        icon = CupertinoIcons.checkmark_circle_fill;
        break;
      case 'mismatches_found':
        bgColor = _criticalRed.withValues(alpha: 0.15);
        textColor = _criticalRed;
        label = 'Issues';
        icon = CupertinoIcons.exclamationmark_triangle_fill;
        break;
      case 'processing':
        bgColor = Colors.blue.withValues(alpha: 0.15);
        textColor = Colors.blue;
        label = 'Processing';
        icon = CupertinoIcons.arrow_2_circlepath;
        break;
      default:
        bgColor = _lowGray.withValues(alpha: 0.15);
        textColor = _lowGray;
        label = 'Pending';
        icon = CupertinoIcons.clock_fill;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccuracyBar(double accuracy, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Overall Accuracy',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              Text(
                '${accuracy.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _accuracyColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: accuracy / 100,
              backgroundColor: cs.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(_accuracyColor),
              minHeight: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIssueChips() {
    final criticalCount = validationResult.criticalCount;
    final warningCount = validationResult.warningCount;
    final matchedCount = validationResult.aiSummary?.matchedCount ??
        validationResult.matchedCount;
    final missingCount = validationResult.aiSummary?.missingCount ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (criticalCount > 0)
            _buildChip(
              icon: CupertinoIcons.xmark_circle_fill,
              label: '$criticalCount Critical',
              color: _criticalRed,
            ),
          if (warningCount > 0)
            _buildChip(
              icon: CupertinoIcons.exclamationmark_triangle_fill,
              label: '$warningCount Warnings',
              color: _warningOrange,
            ),
          if (matchedCount > 0)
            _buildChip(
              icon: CupertinoIcons.checkmark_circle_fill,
              label: '$matchedCount Matched',
              color: _successGreen,
            ),
          if (missingCount > 0)
            _buildChip(
              icon: CupertinoIcons.doc_text,
              label: '$missingCount Missing',
              color: _lowGray,
            ),
        ],
      ),
    );
  }

  Widget _buildChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendation(AISummary summary, ColorScheme cs) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _recommendationColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _recommendationColor.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _recommendationColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _recommendationIcon,
              color: _recommendationColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI Recommendation',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _recommendationColor,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  summary.recommendation,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsButton(ColorScheme cs) {
    return InkWell(
      onTap: onTapDetails,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: cs.outlineVariant),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.list_bullet_below_rectangle,
              size: 16,
              color: cs.primary,
            ),
            const SizedBox(width: 8),
            Text(
              'View Detailed Insights',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: cs.primary,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              CupertinoIcons.chevron_right,
              size: 14,
              color: cs.primary,
            ),
          ],
        ),
      ),
    );
  }

  Color _getConfidenceColor(String confidence) {
    switch (confidence.toLowerCase()) {
      case 'high':
        return _successGreen;
      case 'medium':
        return _warningOrange;
      default:
        return _lowGray;
    }
  }

  String _capitalizeFirst(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }
}
