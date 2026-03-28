import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../models/batch_ocr_models.dart';
import 'quantity_editor.dart';

/// Compact, performance-optimized item card for OCR review
///
/// Features:
/// - Fixed 80px height for ListView virtualization
/// - Inline quantity editing
/// - Accept/Reject quick actions
/// - Confidence badge
/// - Match status indicator
/// - Selection support
/// - Minimal text, icon-focused design
class CompactEditableItemCard extends StatelessWidget {
  final DeduplicatedItem item;
  final bool isSelected;
  final bool isAccepted;
  final bool isRejected;
  final int currentQuantity;
  final VoidCallback? onTap;
  final ValueChanged<bool?>? onSelected;
  final ValueChanged<int>? onQuantityChanged;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onBrandNameTap;  // Tap to edit brand name
  final VoidCallback? onSellingPriceTap;  // Tap to edit price

  const CompactEditableItemCard({
    super.key,
    required this.item,
    this.isSelected = false,
    this.isAccepted = false,
    this.isRejected = false,
    required this.currentQuantity,
    this.onTap,
    this.onSelected,
    this.onQuantityChanged,
    this.onAccept,
    this.onReject,
    this.onBrandNameTap,
    this.onSellingPriceTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return RepaintBoundary(
      child: Container(
        height: 80,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: _getBackgroundColor(cs),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _getBorderColor(cs),
            width: isSelected ? 2.5 : 1.5,
          ),
          boxShadow: [
            if (!isRejected)
              BoxShadow(
                color: _getBorderColor(cs).withValues(alpha: 0.15),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              // Make entire row selectable
              if (onSelected != null) {
                onSelected!(!isSelected);
              }
            },
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Row Number Badge
                  if (item.rowNumber != null) ...[
                    _buildRowNumberBadge(cs),
                    const SizedBox(width: 12),
                  ],

                  // Brand & Size Info (Expanded)
                  Expanded(
                    child: _buildBrandInfo(cs),
                  ),

                  const SizedBox(width: 12),

                  // Selling Price
                  if (item.sellingPrice != null) ...[
                    _buildSellingPrice(),
                    const SizedBox(width: 12),
                  ],

                  // Quantity Editor (Auto-saves on change)
                  if (onQuantityChanged != null && !isRejected)
                    QuantityEditor(
                      initialQuantity: currentQuantity,
                      onChanged: (newQty) {
                        // Auto-save on quantity change
                        onQuantityChanged!(newQty);
                        // Auto-accept when user edits quantity
                        if (onAccept != null && !isAccepted) {
                          onAccept!();
                        }
                      },
                      compact: true,
                      min: 0,
                      max: 9999,
                    ),

                  if (isRejected)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Rejected',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRowNumberBadge(ColorScheme cs) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.1),
        shape: BoxShape.circle,
        border: Border.all(
          color: cs.primary.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Center(
        child: Text(
          '#${item.rowNumber}',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: cs.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildSellingPrice() {
    return GestureDetector(
      onTap: onSellingPriceTap != null && !isRejected
          ? () {
              HapticFeedback.lightImpact();
              onSellingPriceTap!();
            }
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppColors.success.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '\u20B9${item.sellingPrice!.toStringAsFixed(0)}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: AppColors.success,
                letterSpacing: -0.5,
              ),
            ),
            if (onSellingPriceTap != null && !isRejected) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.edit,
                size: 12,
                color: AppColors.success.withValues(alpha: 0.7),
              ),
            ],
          ],
        ),
      ),
    );
  }


  Widget _buildBrandInfo(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Brand Name (Editable)
        GestureDetector(
          onTap: onBrandNameTap != null && !isRejected
              ? () {
                  HapticFeedback.lightImpact();
                  onBrandNameTap!();
                }
              : null,
          child: Row(
            children: [
              Flexible(
                child: Text(
                  item.brandText,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onBrandNameTap != null && !isRejected) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.edit,
                  size: 14,
                  color: cs.primary.withValues(alpha: 0.6),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 4),

        // Size
        Row(
          children: [
            Icon(
              Icons.local_drink,
              size: 12,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                item.sizeText,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }



  // Helper methods

  Color _getBackgroundColor(ColorScheme cs) {
    // Priority: Rejected > Accepted > Selected > Confidence
    if (isRejected) {
      return AppColors.error.withValues(alpha: 0.08);
    }
    if (isAccepted) {
      return AppColors.success.withValues(alpha: 0.08);
    }
    if (isSelected) {
      return cs.primary.withValues(alpha: 0.08);
    }

    // Apply confidence-based background color
    final confidence = item.matchConfidence;
    if (confidence >= 0.8) {
      return AppColors.success.withValues(alpha: 0.08); // Light green for high confidence
    } else if (confidence >= 0.5) {
      return AppColors.warning.withValues(alpha: 0.08); // Light amber for medium confidence
    } else {
      return AppColors.error.withValues(alpha: 0.08);   // Light red for low confidence
    }
  }

  Color _getBorderColor(ColorScheme cs) {
    // Priority: Rejected > Accepted > Selected > Confidence
    if (isRejected) {
      return AppColors.error.withValues(alpha: 0.2);
    }
    if (isAccepted) {
      return AppColors.success.withValues(alpha: 0.3);
    }
    if (isSelected) {
      return cs.primary;
    }

    // Apply confidence-based border color
    final confidence = item.matchConfidence;
    if (confidence >= 0.8) {
      return AppColors.success.withValues(alpha: 0.2); // Green border for high confidence
    } else if (confidence >= 0.5) {
      return AppColors.warning.withValues(alpha: 0.2); // Amber border for medium confidence
    } else {
      return AppColors.error.withValues(alpha: 0.2);   // Red border for low confidence
    }
  }
}
