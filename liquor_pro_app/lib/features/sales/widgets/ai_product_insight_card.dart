import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../models/daily_sales_models.dart';

/// AI Product Insight Card - Shows per-product validation details
/// Displays product name, issues list, suggestions, and auto-fix options
class AIProductInsightCard extends StatefulWidget {
  final ItemInsight insight;
  final VoidCallback? onAutoFix;
  final Function(String productId, String field, String value)? onManualFix;

  const AIProductInsightCard({
    super.key,
    required this.insight,
    this.onAutoFix,
    this.onManualFix,
  });

  @override
  State<AIProductInsightCard> createState() => _AIProductInsightCardState();
}

class _AIProductInsightCardState extends State<AIProductInsightCard> {
  bool _isExpanded = false;

  // Color constants matching iOS design
  static const Color _criticalRed = Color(0xFFFF3B30);
  static const Color _warningOrange = Color(0xFFFF9500);
  static const Color _successGreen = Color(0xFF34C759);
  static const Color _infoBlue = Color(0xFF007AFF);

  Color _statusColor(ColorScheme cs) {
    switch (widget.insight.status) {
      case 'critical':
        return _criticalRed;
      case 'warning':
        return _warningOrange;
      case 'matched':
        return _successGreen;
      default:
        return cs.onSurfaceVariant;
    }
  }

  IconData get _statusIcon {
    switch (widget.insight.status) {
      case 'critical':
        return CupertinoIcons.xmark_circle_fill;
      case 'warning':
        return CupertinoIcons.exclamationmark_triangle_fill;
      case 'matched':
        return CupertinoIcons.checkmark_circle_fill;
      default:
        return CupertinoIcons.circle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final insight = widget.insight;
    final hasIssues = insight.hasIssues;
    final statusColor = _statusColor(cs);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header - Product name with status
          _buildHeader(insight, cs, statusColor),

          // Issues list (expandable)
          if (hasIssues) ...[
            // Divider
            Divider(height: 1, color: cs.outlineVariant),

            // Issues
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 200),
              crossFadeState: _isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: _buildCollapsedIssues(insight, cs),
              secondChild: _buildExpandedIssues(insight, cs),
            ),
          ],

          // Matched indicator for no issues
          if (!hasIssues) _buildMatchedIndicator(),
        ],
      ),
    );
  }

  Widget _buildHeader(ItemInsight insight, ColorScheme cs, Color statusColor) {
    return InkWell(
      onTap: insight.hasIssues
          ? () => setState(() => _isExpanded = !_isExpanded)
          : null,
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(14),
        topRight: Radius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Status icon
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _statusIcon,
                color: statusColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),

            // Product name
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _cleanProductName(insight.productName),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      // Confidence badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${insight.matchConfidence.toStringAsFixed(0)}% match',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (insight.issueCount > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${insight.issueCount} issue${insight.issueCount > 1 ? 's' : ''}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // Expand/collapse indicator
            if (insight.hasIssues)
              AnimatedRotation(
                turns: _isExpanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  CupertinoIcons.chevron_down,
                  color: cs.onSurfaceVariant,
                  size: 18,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCollapsedIssues(ItemInsight insight, ColorScheme cs) {
    // Show preview of first issue
    final firstIssue = insight.issues.isNotEmpty ? insight.issues.first : null;
    if (firstIssue == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      child: Row(
        children: [
          Icon(
            _getIssueIcon(firstIssue.type),
            size: 14,
            color: _getIssueColor(firstIssue.severity, cs),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              firstIssue.message,
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (insight.issues.length > 1) ...[
            const SizedBox(width: 8),
            Text(
              '+${insight.issues.length - 1} more',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExpandedIssues(ItemInsight insight, ColorScheme cs) {
    return Column(
      children: [
        ...insight.issues.map((issue) => _buildIssueItem(issue, cs)),
      ],
    );
  }

  Widget _buildIssueItem(AIIssue issue, ColorScheme cs) {
    final issueColor = _getIssueColor(issue.severity, cs);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Issue header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: issueColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _getIssueIcon(issue.type),
                  size: 14,
                  color: issueColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  issue.message,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface,
                  ),
                ),
              ),
              // Severity badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: issueColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  issue.severity.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: issueColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),

          // Value comparison
          if (issue.enteredValue.isNotEmpty || issue.ocrValue.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  // Entered value
                  Expanded(
                    child: _buildValueChip(
                      label: 'Entered',
                      value: issue.enteredValue.isEmpty
                          ? '-'
                          : issue.enteredValue,
                      isEntered: true,
                      cs: cs,
                    ),
                  ),
                  // Arrow
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Icon(
                      CupertinoIcons.arrow_right,
                      size: 16,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  // OCR value
                  Expanded(
                    child: _buildValueChip(
                      label: 'Receipt',
                      value: issue.ocrValue.isEmpty ? '-' : issue.ocrValue,
                      isEntered: false,
                      cs: cs,
                    ),
                  ),
                ],
              ),
            ),

          // Suggestion
          if (issue.suggestion.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _infoBlue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _infoBlue.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.lightbulb_fill,
                    size: 16,
                    color: _infoBlue,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      issue.suggestion,
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Auto-fix button
          if (issue.autoFixable && widget.onAutoFix != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  color: _successGreen,
                  borderRadius: BorderRadius.circular(10),
                  onPressed: widget.onAutoFix,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        CupertinoIcons.wand_stars,
                        size: 16,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Auto-Fix This Issue',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildValueChip({
    required String label,
    required String value,
    required bool isEntered,
    required ColorScheme cs,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isEntered ? Colors.red.withValues(alpha: 0.08) : _successGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isEntered ? Colors.red.withValues(alpha: 0.2) : _successGreen.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: isEntered ? Colors.red[700] : _successGreen,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildMatchedIndicator() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.checkmark_seal_fill,
            size: 16,
            color: _successGreen,
          ),
          const SizedBox(width: 8),
          Text(
            'All values match receipt data',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: _successGreen,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getIssueIcon(String type) {
    switch (type) {
      case 'quantity':
        return CupertinoIcons.number;
      case 'price':
        return CupertinoIcons.money_dollar;
      case 'brand':
        return CupertinoIcons.tag;
      case 'missing':
        return CupertinoIcons.doc_text;
      default:
        return CupertinoIcons.exclamationmark_circle;
    }
  }

  Color _getIssueColor(String severity, ColorScheme cs) {
    switch (severity) {
      case 'critical':
        return _criticalRed;
      case 'warning':
        return _warningOrange;
      default:
        return cs.onSurfaceVariant;
    }
  }

  String _cleanProductName(String name) {
    // Remove size patterns like "- 330ML", "- 500ml"
    String cleanName = name
        .replaceAll(RegExp(r'\s*-\s*\d+(?:\.\d+)?\s*(?:ml|ML|ltr|LTR|L)\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\d+(?:\.\d+)?\s*(?:ml|ML|ltr|LTR|L)\b', caseSensitive: false), '')
        .trim();

    if (cleanName.endsWith('-')) {
      cleanName = cleanName.substring(0, cleanName.length - 1).trim();
    }

    return cleanName.isNotEmpty ? cleanName : name;
  }
}
