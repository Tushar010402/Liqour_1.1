import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../models/batch_ocr_models.dart';
import '../models/saas_brand.dart';
import '../providers/batch_ocr_provider.dart';
import 'match_confidence_badge.dart';

/// Card displaying a matched OCR item with auto-filled details
///
/// Shows:
/// - OCR extracted text vs matched brand
/// - Confidence score badge
/// - Auto-filled pricing and category
/// - Duplicate warning if applicable
/// - Acceptance state badge (ACCEPTED/REJECTED/PENDING)
/// - Accept/Edit/Reject actions
class MatchedItemCard extends StatelessWidget {
  final DeduplicatedItem item;
  final SaasBrandVariant? matchedVariant;
  final bool isSelected;
  final ItemAcceptanceState acceptanceState;
  final VoidCallback? onAccept;
  final VoidCallback? onEdit;
  final VoidCallback? onReject;
  final ValueChanged<bool>? onSelectionChanged;
  final bool showCheckbox;

  const MatchedItemCard({
    super.key,
    required this.item,
    this.matchedVariant,
    this.isSelected = false,
    this.acceptanceState = ItemAcceptanceState.pending,
    this.onAccept,
    this.onEdit,
    this.onReject,
    this.onSelectionChanged,
    this.showCheckbox = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasMatch = matchedVariant != null;
    final confidence = item.matchConfidence;
    final isDuplicate = item.isDuplicate;

    // Determine border color based on acceptance state
    Color borderColor = Colors.transparent;
    Color shadowColor = Colors.black.withValues(alpha: 0.05);
    double borderWidth = 1;

    if (isSelected) {
      borderColor = cs.primary;
      shadowColor = cs.primary.withValues(alpha: 0.2);
      borderWidth = 2;
    } else if (acceptanceState == ItemAcceptanceState.accepted) {
      borderColor = AppColors.success.withValues(alpha: 0.4);
      shadowColor = AppColors.success.withValues(alpha: 0.15);
      borderWidth = 2;
    } else if (acceptanceState == ItemAcceptanceState.rejected) {
      borderColor = AppColors.error.withValues(alpha: 0.4);
      shadowColor = AppColors.error.withValues(alpha: 0.15);
      borderWidth = 2;
    } else if (isDuplicate) {
      borderColor = AppColors.error.withValues(alpha: 0.3);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: borderColor,
          width: borderWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: isSelected || acceptanceState != ItemAcceptanceState.pending ? 20 : 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with confidence and selection
          _buildHeader(context, confidence, isDuplicate),

          // Divider
          Divider(color: cs.outlineVariant, height: 1),

          // Body with details
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // OCR vs Matched comparison
                _buildComparisonRow(context, hasMatch),

                if (hasMatch && matchedVariant != null) ...[
                  const SizedBox(height: 16),
                  _buildPricingPreview(context),
                  const SizedBox(height: 16),
                  _buildCategoryPreview(context),
                ],

                const SizedBox(height: 16),
                _buildStockInfo(context),

                if (isDuplicate) ...[
                  const SizedBox(height: 16),
                  _buildDuplicateWarning(),
                ],
              ],
            ),
          ),

          // Actions
          if (onAccept != null || onEdit != null || onReject != null) ...[
            Divider(color: cs.outlineVariant, height: 1),
            _buildActions(context),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, double? confidence, bool isDuplicate) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDuplicate
            ? AppColors.error.withValues(alpha: 0.05)
            : cs.surfaceContainerHighest,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Row(
        children: [
          if (showCheckbox) ...[
            Checkbox(
              value: isSelected,
              onChanged: (value) => onSelectionChanged?.call(value ?? false),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(width: 8),
          ],
          MatchConfidenceBadge(
            confidence: confidence,
            showPercentage: true,
          ),
          const Spacer(),
          // Acceptance State Badge
          if (acceptanceState != ItemAcceptanceState.pending) ...[
            _buildAcceptanceStateBadge(),
            if (isDuplicate) const SizedBox(width: 8),
          ],
          // Duplicate Badge
          if (isDuplicate)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.error.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.warning_rounded,
                    size: 16,
                    color: AppColors.error,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Duplicate',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.error,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Build acceptance state badge
  Widget _buildAcceptanceStateBadge() {
    final bool isAccepted = acceptanceState == ItemAcceptanceState.accepted;
    final bool isRejected = acceptanceState == ItemAcceptanceState.rejected;

    if (!isAccepted && !isRejected) return const SizedBox.shrink();

    final Color semanticColor = isAccepted ? AppColors.success : AppColors.error;
    final Color bgColor = semanticColor.withValues(alpha: 0.1);
    final Color borderColor = semanticColor.withValues(alpha: 0.3);
    final IconData icon = isAccepted
        ? Icons.check_circle_rounded
        : Icons.cancel_rounded;
    final String label = isAccepted ? 'ACCEPTED' : 'REJECTED';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: borderColor,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: semanticColor,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: semanticColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonRow(BuildContext context, bool hasMatch) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // OCR Extracted
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'OCR Extracted',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${item.brandText} ${item.sizeText}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
        ),

        if (hasMatch) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Icon(
              Icons.arrow_forward_rounded,
              size: 20,
              color: cs.outlineVariant,
            ),
          ),

          // Matched Brand
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Matched',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.success,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 14,
                      color: AppColors.success.withValues(alpha: 0.7),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  matchedVariant?.size ?? 'Unknown',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPricingPreview(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (matchedVariant == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.success.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.price_check_rounded,
                size: 16,
                color: AppColors.success,
              ),
              const SizedBox(width: 6),
              Text(
                'Auto-filled Pricing',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildPriceItem('Cost', matchedVariant!.buyingPrice, cs),
              ),
              Expanded(
                child: _buildPriceItem('Selling', matchedVariant!.sellingPrice, cs),
              ),
              Expanded(
                child: _buildPriceItem('MRP', matchedVariant!.mrp, cs),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPriceItem(String label, double price, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '\u20b9${price.toStringAsFixed(0)}',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryPreview(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (matchedVariant == null) return const SizedBox.shrink();

    final categoryName = matchedVariant!.category?.name ?? 'Unknown';
    final subcategoryName = matchedVariant!.subcategory?.name;

    return Row(
      children: [
        Icon(
          Icons.category_rounded,
          size: 16,
          color: cs.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Text(
          categoryName,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
        if (subcategoryName != null) ...[
          const SizedBox(width: 4),
          Icon(
            Icons.chevron_right_rounded,
            size: 16,
            color: cs.outlineVariant,
          ),
          const SizedBox(width: 4),
          Text(
            subcategoryName,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStockInfo(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(
          Icons.inventory_2_rounded,
          size: 16,
          color: cs.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Text(
          '${item.totalStock} units',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
        if (item.sourceSessionIds.length > 1) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'From ${item.sourceSessionIds.length} images',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.info.withValues(alpha: 0.8),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDuplicateWarning() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.error.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: AppColors.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'This item already exists in your inventory. Consider skipping or adjusting quantities.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.error,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bool isAccepted = acceptanceState == ItemAcceptanceState.accepted;
    final bool isRejected = acceptanceState == ItemAcceptanceState.rejected;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // Reject Button
          if (onReject != null)
            Expanded(
              child: _buildActionButton(
                label: isRejected ? 'Rejected \u2717' : 'Reject',
                icon: isRejected ? Icons.cancel_rounded : Icons.close_rounded,
                color: cs.onSurfaceVariant,
                onTap: isRejected ? null : onReject!,
                isDisabled: isRejected,
                cs: cs,
              ),
            ),
          // Edit Button
          if (onEdit != null) ...[
            if (onReject != null) const SizedBox(width: 12),
            Expanded(
              child: _buildActionButton(
                label: 'Edit',
                icon: Icons.edit_rounded,
                color: cs.primary,
                onTap: onEdit!,
                cs: cs,
              ),
            ),
          ],
          // Accept Button
          if (onAccept != null) ...[
            if (onEdit != null || onReject != null) const SizedBox(width: 12),
            Expanded(
              child: _buildActionButton(
                label: isAccepted ? 'Accepted \u2713' : 'Accept',
                icon: isAccepted ? Icons.check_circle_rounded : Icons.check_rounded,
                color: AppColors.success,
                isPrimary: !isAccepted,
                onTap: isAccepted ? null : onAccept!,
                isDisabled: isAccepted,
                cs: cs,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
    required ColorScheme cs,
    bool isPrimary = false,
    bool isDisabled = false,
  }) {
    final bool disabled = isDisabled || onTap == null;
    final Color effectiveColor = disabled ? cs.outlineVariant : color;
    final Color effectiveTextColor = disabled
        ? cs.onSurfaceVariant
        : (isPrimary ? Colors.white : color);

    return Material(
      color: disabled
          ? cs.surfaceContainerHighest
          : (isPrimary ? effectiveColor : effectiveColor.withValues(alpha: 0.1)),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: effectiveTextColor,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: effectiveTextColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
