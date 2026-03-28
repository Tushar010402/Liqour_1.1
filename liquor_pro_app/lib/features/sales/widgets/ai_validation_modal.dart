import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../core/utils/formatters.dart';
import '../models/daily_sales_models.dart';
import 'receipt_image_viewer.dart';

/// AI Validation Modal - Clean, Clear Display of AI Validation Results
/// Shows AI summary with critical issues, warnings, and recommendations
class AIValidationModal extends StatelessWidget {
  final DailySalesRecord record;
  final AIValidationResult? validationResult;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final bool showActions;

  const AIValidationModal({
    super.key,
    required this.record,
    this.validationResult,
    this.onApprove,
    this.onReject,
    this.showActions = true,
  });

  // iOS 16 Colors
  static const Color _criticalRed = Color(0xFFFF3B30);
  static const Color _warningOrange = Color(0xFFFF9500);
  static const Color _successGreen = Color(0xFF34C759);
  static const Color _infoBlue = Color(0xFF007AFF);
  static const Color _neutralGray = Color(0xFF8E8E93);

  /// Show the modal as a bottom sheet
  static Future<void> show(
    BuildContext context, {
    required DailySalesRecord record,
    AIValidationResult? validationResult,
    VoidCallback? onApprove,
    VoidCallback? onReject,
    bool showActions = true,
  }) {
    HapticFeedback.mediumImpact();
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => AIValidationModal(
          record: record,
          validationResult: validationResult,
          onApprove: onApprove,
          onReject: onReject,
          showActions: showActions,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final validation = validationResult ?? record.validationResult;
    final summary = validation?.aiSummary;

    // Debug logging
    print('🎨 [AIValidationModal] Building modal');
    print('   - validationResult: ${validationResult != null ? "YES" : "NULL"}');
    print('   - record.validationResult: ${record.validationResult != null ? "YES" : "NULL"}');
    print('   - final validation: ${validation != null ? "YES" : "NULL"}');
    print('   - aiSummary: ${summary != null ? "YES" : "NULL"}');
    if (summary != null) {
      print('   - Accuracy: ${summary.overallAccuracy}%');
      print('   - Critical: ${summary.criticalCount}, Warning: ${summary.warningCount}');
      print('   - Recommendation: ${summary.recommendation}');
      print('   - Action: ${summary.recommendedAction}');
    }
    if (validation != null) {
      print('   - perItemInsights: ${validation.perItemInsights.length}');
      print('   - missingItemsGrouped: ${validation.missingItemsGrouped.length}');
    }

    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // Drag handle
          _buildDragHandle(),

          // Scrollable content
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                // Header with close button
                _buildHeader(context),

                const SizedBox(height: 16),

                // Main AI Summary Card
                if (validation != null && summary != null)
                  _buildAISummaryCard(context, validation, summary)
                else
                  _buildNoValidationState(),

                const SizedBox(height: 16),

                // Issue counts breakdown
                if (validation != null && summary != null)
                  _buildIssueBreakdown(summary),

                const SizedBox(height: 16),

                // Per-item issues list
                if (validation != null && validation.perItemInsights.isNotEmpty)
                  _buildItemIssuesList(validation),

                const SizedBox(height: 16),

                // Missing items section
                if (validation != null && validation.missingItemsGrouped.isNotEmpty)
                  _buildMissingItemsSection(validation),

                const SizedBox(height: 16),

                // Receipt images preview
                if (record.imageUrls.isNotEmpty)
                  _buildReceiptPreview(context),

                // Bottom padding for safe area
                SizedBox(height: MediaQuery.of(context).padding.bottom + 100),
              ],
            ),
          ),

          // Action buttons
          if (showActions && record.status == 'pending')
            _buildActionBar(context, validation),
        ],
      ),
    );
  }

  Widget _buildDragHandle() {
    return Builder(builder: (context) {
      final cs = Theme.of(context).colorScheme;
      return Container(
        margin: const EdgeInsets.only(top: 8, bottom: 4),
        width: 36,
        height: 5,
        decoration: BoxDecoration(
          color: cs.onSurfaceVariant,
          borderRadius: BorderRadius.circular(3),
        ),
      );
    });
  }

  Widget _buildHeader(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 16),
      child: Row(
        children: [
          // AI Icon
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF667EEA).withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              CupertinoIcons.sparkles,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          // Title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI Validation Report',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${record.shopName ?? "Shop"} • ${DateFormat('MMM d, yyyy').format(record.recordDate)}',
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // Close button
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                shape: BoxShape.circle,
              ),
              child: Icon(
                CupertinoIcons.xmark,
                size: 16,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAISummaryCard(BuildContext context, AIValidationResult validation, AISummary summary) {
    final cs = Theme.of(context).colorScheme;
    final accuracy = summary.overallAccuracy;
    final Color accentColor = accuracy >= 80
        ? _successGreen
        : accuracy >= 50
            ? _warningOrange
            : _criticalRed;

    final String statusText = accuracy >= 80
        ? 'Good Match'
        : accuracy >= 50
            ? 'Needs Review'
            : 'Issues Found';

    final IconData statusIcon = accuracy >= 80
        ? CupertinoIcons.checkmark_seal_fill
        : accuracy >= 50
            ? CupertinoIcons.exclamationmark_triangle_fill
            : CupertinoIcons.xmark_circle_fill;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Accuracy Circle
          Row(
            children: [
              // Large accuracy percentage
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accentColor.withOpacity(0.15),
                      accentColor.withOpacity(0.05),
                    ],
                  ),
                  border: Border.all(
                    color: accentColor,
                    width: 4,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${accuracy.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: accentColor,
                        letterSpacing: -1,
                      ),
                    ),
                    Text(
                      'Accuracy',
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              // Status and recommendation
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: accentColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(statusIcon, size: 16, color: accentColor),
                          const SizedBox(width: 6),
                          Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: accentColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // AI Recommendation
                    if (summary.recommendation.isNotEmpty) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            CupertinoIcons.lightbulb_fill,
                            size: 14,
                            color: Colors.amber[700],
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              summary.recommendation,
                              style: TextStyle(
                                fontSize: 13,
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Recommended action
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _getActionColor(summary.recommendedAction).withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _getActionColor(summary.recommendedAction).withOpacity(0.2),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _getActionIcon(summary.recommendedAction),
                  size: 22,
                  color: _getActionColor(summary.recommendedAction),
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
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _getActionText(summary.recommendedAction),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _getActionColor(summary.recommendedAction),
                        ),
                      ),
                    ],
                  ),
                ),
                // Confidence badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Text(
                    '${summary.confidenceLevel.toUpperCase()} confidence',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIssueBreakdown(AISummary summary) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Critical
          Expanded(
            child: _buildIssueCountCard(
              icon: CupertinoIcons.xmark_circle_fill,
              label: 'Critical',
              count: summary.criticalCount,
              color: _criticalRed,
            ),
          ),
          const SizedBox(width: 10),
          // Warnings
          Expanded(
            child: _buildIssueCountCard(
              icon: CupertinoIcons.exclamationmark_triangle_fill,
              label: 'Warnings',
              count: summary.warningCount,
              color: _warningOrange,
            ),
          ),
          const SizedBox(width: 10),
          // Matched
          Expanded(
            child: _buildIssueCountCard(
              icon: CupertinoIcons.checkmark_circle_fill,
              label: 'Matched',
              count: summary.matchedCount,
              color: _successGreen,
            ),
          ),
          const SizedBox(width: 10),
          // Missing
          Expanded(
            child: _buildIssueCountCard(
              icon: CupertinoIcons.doc_text_search,
              label: 'Missing',
              count: summary.missingCount,
              color: _neutralGray,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIssueCountCard({
    required IconData icon,
    required String label,
    required int count,
    required Color color,
  }) {
    return Builder(builder: (context) {
      final cs = Theme.of(context).colorScheme;
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(height: 8),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildItemIssuesList(AIValidationResult validation) {
    final itemsWithIssues = validation.perItemInsights
        .where((item) => item.hasIssues)
        .toList();

    if (itemsWithIssues.isEmpty) return const SizedBox.shrink();

    return Builder(builder: (context) {
      final cs = Theme.of(context).colorScheme;
      return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _warningOrange.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    CupertinoIcons.exclamationmark_triangle_fill,
                    size: 18,
                    color: _warningOrange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Items With Issues',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _warningOrange.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${itemsWithIssues.length}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _warningOrange,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Items list
          ...itemsWithIssues.take(5).map((item) => _buildItemIssueRow(item)),

          // Show more indicator
          if (itemsWithIssues.length > 5)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  '+${itemsWithIssues.length - 5} more items',
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    });
  }

  Widget _buildItemIssueRow(ItemInsight item) {
    final issueColor = item.isCritical ? _criticalRed : _warningOrange;

    return Builder(builder: (context) {
      final cs = Theme.of(context).colorScheme;
      return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: cs.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product name with status
          Row(
            children: [
              Icon(
                item.isCritical
                    ? CupertinoIcons.xmark_circle_fill
                    : CupertinoIcons.exclamationmark_triangle_fill,
                size: 16,
                color: issueColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.productName,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${item.matchConfidence.toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: issueColor,
                ),
              ),
            ],
          ),

          // Issues list
          if (item.issues.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...item.issues.map((issue) => Padding(
              padding: const EdgeInsets.only(left: 24, top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: issue.severity == 'critical' ? _criticalRed : _warningOrange,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          issue.message,
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        if (issue.enteredValue.isNotEmpty || issue.ocrValue.isNotEmpty)
                          Text(
                            'Entered: ${issue.enteredValue} → Receipt: ${issue.ocrValue}',
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            )),
          ],
        ],
      ),
    );
    });
  }

  Widget _buildMissingItemsSection(AIValidationResult validation) {
    final totalMissing = validation.missingItemsGrouped.fold<int>(
      0, (sum, group) => sum + group.count,
    );

    if (totalMissing == 0) return const SizedBox.shrink();

    return Builder(builder: (context) {
      final cs = Theme.of(context).colorScheme;
      return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _criticalRed.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: _criticalRed.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _criticalRed.withOpacity(0.05),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _criticalRed.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    CupertinoIcons.doc_text_search,
                    size: 18,
                    color: _criticalRed,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Missing Items',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      Text(
                        'Found in receipt but not entered',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _criticalRed,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$totalMissing',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Missing items by group
          ...validation.missingItemsGrouped.map((group) => _buildMissingGroup(group)),
        ],
      ),
    );
    });
  }

  Widget _buildMissingGroup(MissingItemGroup group) {
    final color = group.isCritical ? _criticalRed : _warningOrange;

    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      childrenPadding: EdgeInsets.zero,
      leading: Icon(
        group.isCritical
            ? CupertinoIcons.xmark_circle_fill
            : CupertinoIcons.exclamationmark_triangle_fill,
        size: 20,
        color: color,
      ),
      title: Text(
        '${group.severity.toUpperCase()} (${group.count})',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
      children: group.items.take(3).map((item) => Builder(builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.03),
          border: Border(top: BorderSide(color: cs.outlineVariant)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.brand,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${item.size} • ${item.ocrQuantity} qty',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              Formatters.currency(item.ocrPrice),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      );
      })).toList(),
    );
  }

  Widget _buildReceiptPreview(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.photo_fill,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Text(
                  'Receipt Images (${record.imageUrls.length})',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const Spacer(),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () => ReceiptImageViewer.show(
                    context,
                    imageUrls: record.imageUrls,
                    title: 'Receipts',
                  ),
                  child: const Text(
                    'View All',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Image thumbnails
          SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: record.imageUrls.length,
              itemBuilder: (context, index) => GestureDetector(
                onTap: () => ReceiptImageViewer.show(
                  context,
                  imageUrls: record.imageUrls,
                  initialIndex: index,
                  title: 'Receipt ${index + 1}',
                ),
                child: Container(
                  width: 80,
                  margin: EdgeInsets.only(right: index < record.imageUrls.length - 1 ? 10 : 0),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: Image.network(
                      record.imageUrls[index],
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          color: cs.surfaceContainerHighest,
                          child: const Center(
                            child: CupertinoActivityIndicator(radius: 10),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: cs.surfaceContainerHighest,
                        child: Icon(
                          CupertinoIcons.photo,
                          color: cs.onSurfaceVariant,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoValidationState() {
    return Builder(builder: (context) {
      final cs = Theme.of(context).colorScheme;
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(
              CupertinoIcons.sparkles,
              size: 48,
              color: cs.outlineVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No AI Validation Available',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'AI validation requires receipt images',
              style: TextStyle(
                fontSize: 14,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildActionBar(BuildContext context, AIValidationResult? validation) {
    final cs = Theme.of(context).colorScheme;
    final recommendedAction = validation?.aiSummary?.recommendedAction ?? 'review';

    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Row(
        children: [
          // Reject button
          if (onReject != null)
            Expanded(
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 14),
                color: _criticalRed.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  Navigator.pop(context);
                  onReject!();
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      CupertinoIcons.xmark,
                      size: 18,
                      color: _criticalRed,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Reject',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _criticalRed,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          if (onReject != null && onApprove != null)
            const SizedBox(width: 12),

          // Approve button
          if (onApprove != null)
            Expanded(
              flex: 2,
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 14),
                color: recommendedAction == 'approve' ? _successGreen : _infoBlue,
                borderRadius: BorderRadius.circular(14),
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  Navigator.pop(context);
                  onApprove!();
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      CupertinoIcons.checkmark,
                      size: 18,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      recommendedAction == 'approve'
                          ? 'Approve (Recommended)'
                          : 'Approve',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Helper methods
  Color _getActionColor(String action) {
    switch (action) {
      case 'approve': return _successGreen;
      case 'reject': return _criticalRed;
      default: return _warningOrange;
    }
  }

  IconData _getActionIcon(String action) {
    switch (action) {
      case 'approve': return CupertinoIcons.checkmark_seal_fill;
      case 'reject': return CupertinoIcons.xmark_seal_fill;
      default: return CupertinoIcons.eye_fill;
    }
  }

  String _getActionText(String action) {
    switch (action) {
      case 'approve': return 'Approve This Entry';
      case 'reject': return 'Reject This Entry';
      default: return 'Review Before Approving';
    }
  }
}
