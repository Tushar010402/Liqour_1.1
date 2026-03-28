import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../models/ocr_models.dart';

/// Enhanced OCR Item Card widget displaying rate and stock information
class OCRItemCard extends StatelessWidget {
  final OCRExtractedItem item;
  final VoidCallback? onEdit;
  final VoidCallback? onConfirm;
  final VoidCallback? onReject;

  const OCRItemCard({
    super.key,
    required this.item,
    this.onEdit,
    this.onConfirm,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasStockData = item.openingStock != null || item.closingStock != null;
    final hasRateData = item.ratePerUnit != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: _getBorderColor(),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          // Header with row number and confidence
          if (item.rowNumber != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.05),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(11),
                  topRight: Radius.circular(11),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Row #${item.rowNumber}',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  _buildConfidenceBadge(),
                ],
              ),
            ),

          // Main content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Brand and size
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.brandText ?? 'Unknown Brand',
                            style: AppTextStyles.bodyLarge.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (item.sizeText != null)
                            Text(
                              item.sizeText!,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Quantity badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.info.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Qty: ${item.parsedQuantity ?? 0}',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.info,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Rate and Price information
                if (hasRateData) ...[
                  _buildInfoRow(
                    icon: Icons.attach_money,
                    label: 'Rate per Unit',
                    value: '₹${item.ratePerUnit?.toStringAsFixed(2) ?? '0.00'}',
                    color: AppColors.success,
                    context: context,
                  ),
                  const SizedBox(height: 8),
                  if (item.parsedPrice != null)
                    _buildInfoRow(
                      icon: Icons.payments,
                      label: 'Total Price',
                      value: '₹${item.parsedPrice?.toStringAsFixed(2) ?? '0.00'}',
                      color: cs.primary,
                      context: context,
                    ),
                  const SizedBox(height: 12),
                ],

                // Stock information
                if (hasStockData) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.neutral,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.inventory_2,
                              size: 16,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Stock Movement',
                              style: AppTextStyles.bodySmall.copyWith(
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildStockItem(
                              'Opening',
                              item.openingStock?.toString() ?? '-',
                              cs.onSurfaceVariant,
                            ),
                            Icon(
                              Icons.arrow_forward,
                              size: 16,
                              color: cs.onSurfaceVariant,
                            ),
                            _buildStockItem(
                              'Transacted',
                              item.parsedQuantity?.toString() ?? '-',
                              AppColors.info,
                            ),
                            Icon(
                              Icons.arrow_forward,
                              size: 16,
                              color: cs.onSurfaceVariant,
                            ),
                            _buildStockItem(
                              'Closing',
                              item.closingStock?.toString() ?? '-',
                              _getClosingStockColor(context),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Match status
                if (item.matchedProductId != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle,
                          size: 14,
                          color: AppColors.success,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Matched Product',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Action buttons
                if (onEdit != null || onConfirm != null || onReject != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (onReject != null)
                          IconButton(
                            icon: Icon(Icons.close, color: AppColors.error),
                            onPressed: onReject,
                            tooltip: 'Reject',
                          ),
                        if (onEdit != null)
                          IconButton(
                            icon: Icon(Icons.edit, color: AppColors.info),
                            onPressed: onEdit,
                            tooltip: 'Edit',
                          ),
                        if (onConfirm != null)
                          IconButton(
                            icon: Icon(Icons.check, color: AppColors.success),
                            onPressed: onConfirm,
                            tooltip: 'Confirm',
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfidenceBadge() {
    final confidence = item.matchConfidence;
    Color color;
    String label;

    if (confidence >= 0.9) {
      color = AppColors.success;
      label = 'High';
    } else if (confidence >= 0.7) {
      color = AppColors.warning;
      label = 'Medium';
    } else {
      color = AppColors.error;
      label = 'Low';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '${(confidence * 100).toInt()}% $label',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required BuildContext context,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: AppTextStyles.bodyMedium.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildStockItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: AppColors.textHint,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppTextStyles.bodyMedium.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Color _getBorderColor() {
    if (item.isConfirmed) return AppColors.success;
    if (item.isRejected) return AppColors.error;
    if (item.matchConfidence >= 0.9) return AppColors.success.withValues(alpha: 0.3);
    if (item.matchConfidence >= 0.7) return AppColors.warning.withValues(alpha: 0.3);
    return AppColors.neutral;
  }

  Color _getClosingStockColor(BuildContext context) {
    if (item.closingStock == null) return Theme.of(context).colorScheme.onSurfaceVariant;
    if (item.closingStock! <= 0) return AppColors.error;
    if (item.closingStock! < 5) return AppColors.warning;
    return AppColors.success;
  }
}