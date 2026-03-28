import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../models/batch_ocr_models.dart';
import 'quantity_editor.dart';

/// Modern table view for OCR review with spreadsheet-like layout
///
/// Features:
/// - Fixed column headers (sticky)
/// - Editable cells (brand name, quantity, price)
/// - Selection checkboxes
/// - Row number display
/// - Match status indicators
/// - Accept/Reject states
/// - Horizontal and vertical scrolling
class OCRReviewTable extends StatelessWidget {
  final List<DeduplicatedItem> items;
  final Set<String> selectedItemIds;
  final Map<String, int> editedQuantities;
  final Map<String, String> editedBrandNames;
  final Map<String, double> editedPrices;
  final Map<String, bool> acceptanceStates;
  final Map<String, bool> rejectionStates;
  final ValueChanged<String> onItemSelected;
  final Function(String itemId, int quantity) onQuantityChanged;
  final Function(String itemId) onBrandNameTap;
  final Function(String itemId) onSellingPriceTap;

  const OCRReviewTable({
    super.key,
    required this.items,
    required this.selectedItemIds,
    required this.editedQuantities,
    required this.editedBrandNames,
    required this.editedPrices,
    required this.acceptanceStates,
    required this.rejectionStates,
    required this.onItemSelected,
    required this.onQuantityChanged,
    required this.onBrandNameTap,
    required this.onSellingPriceTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        // Table Header (Fixed)
        _buildTableHeader(cs),

        // Divider
        Container(
          height: 2,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                cs.primary.withValues(alpha: 0.3),
                cs.primary.withValues(alpha: 0.1),
              ],
            ),
          ),
        ),

        // Table Body (Scrollable)
        Expanded(
          child: _buildTableBody(),
        ),
      ],
    );
  }

  Widget _buildTableHeader(ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.05),
        border: Border(
          bottom: BorderSide(
            color: cs.primary.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Select Column
            _buildHeaderCell('', width: 50, icon: Icons.check_box_outline_blank, cs: cs),

            // Row Number Column
            _buildHeaderCell('#', width: 60, icon: Icons.numbers, cs: cs),

            // Brand Name Column
            _buildHeaderCell('Brand Name', width: 180, icon: Icons.local_drink, cs: cs),

            // Size Column
            _buildHeaderCell('Size', width: 100, icon: Icons.straighten, cs: cs),

            // Quantity Column
            _buildHeaderCell('Qty', width: 120, icon: Icons.inventory_2, cs: cs),

            // Price Column
            _buildHeaderCell('Price', width: 100, icon: Icons.currency_rupee, cs: cs),

            // Status Column
            _buildHeaderCell('Status', width: 100, icon: Icons.info_outline, cs: cs),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCell(String title, {required double width, IconData? icon, required ColorScheme cs}) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 16,
              color: cs.primary,
            ),
            const SizedBox(width: 6),
          ],
          if (title.isNotEmpty)
            Flexible(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                  letterSpacing: 0.3,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTableBody() {
    if (items.isEmpty) {
      return Builder(builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.inbox_outlined,
                size: 64,
                color: cs.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),
              Text(
                'No items to display',
                style: TextStyle(
                  fontSize: 16,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      });
    }

    return ListView.builder(
      itemCount: items.length,
      padding: const EdgeInsets.only(bottom: 80),
      itemBuilder: (context, index) {
        final item = items[index];
        final itemId = item.sourceItemIds.isNotEmpty ? item.sourceItemIds.first : '';

        return _buildTableRow(context, item, itemId, index);
      },
    );
  }

  Widget _buildTableRow(BuildContext context, DeduplicatedItem item, String itemId, int index) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = selectedItemIds.contains(itemId);
    final isAccepted = acceptanceStates[itemId] ?? false;
    final isRejected = rejectionStates[itemId] ?? false;

    final brandName = editedBrandNames[itemId] ?? item.brandText;
    final quantity = editedQuantities[itemId] ?? item.totalStock;
    final price = editedPrices[itemId] ?? item.sellingPrice;

    final rowColor = _getRowColor(isSelected, isAccepted, isRejected, item.matchConfidence, cs: cs);
    final borderColor = _getBorderColor(isSelected, isAccepted, isRejected, item.matchConfidence, cs: cs);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: rowColor,
        border: Border.all(
          color: borderColor,
          width: isSelected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onItemSelected(itemId),
          borderRadius: BorderRadius.circular(8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Select Checkbox
                _buildCheckboxCell(isSelected, () => onItemSelected(itemId)),

                // Row Number
                _buildRowNumberCell(context, item.rowNumber),

                // Brand Name (Editable)
                _buildBrandNameCell(brandName, !isRejected, () => onBrandNameTap(itemId)),

                // Size
                _buildSizeCell(context, item.sizeText),

                // Quantity (Editable)
                _buildQuantityCell(context, quantity, !isRejected, (newQty) => onQuantityChanged(itemId, newQty)),

                // Price (Editable)
                _buildPriceCell(price, !isRejected, () => onSellingPriceTap(itemId)),

                // Status
                _buildStatusCell(isAccepted, isRejected, item.matchedBrandId != null, item.matchConfidence),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCheckboxCell(bool isSelected, VoidCallback onTap) {
    return Builder(builder: (context) {
      final cs = Theme.of(context).colorScheme;
      return Container(
      width: 50,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: isSelected ? cs.primary : cs.surface,
              border: Border.all(
                color: isSelected ? cs.primary : cs.onSurfaceVariant.withValues(alpha: 0.3),
                width: 2,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: isSelected
                ? const Icon(
                    Icons.check,
                    size: 16,
                    color: Colors.white,
                  )
                : null,
          ),
        ),
      ),
    );
    });
  }

  Widget _buildRowNumberCell(BuildContext context, int? rowNumber) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 60,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      child: Center(
        child: Container(
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
              rowNumber != null ? '#$rowNumber' : '-',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: cs.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrandNameCell(String brandName, bool isEditable, VoidCallback onTap) {
    return Builder(builder: (context) {
      final cs = Theme.of(context).colorScheme;
      return Container(
      width: 180,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: GestureDetector(
        onTap: isEditable
            ? () {
                HapticFeedback.lightImpact();
                onTap();
              }
            : null,
        child: Row(
          children: [
            Expanded(
              child: Text(
                brandName,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isEditable) ...[
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
    );
    });
  }

  Widget _buildSizeCell(BuildContext context, String size) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 100,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: Row(
        children: [
          Icon(
            Icons.local_drink,
            size: 14,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              size,
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuantityCell(BuildContext context, int quantity, bool isEditable, ValueChanged<int> onChanged) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 120,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Center(
        child: isEditable
            ? QuantityEditor(
                initialQuantity: quantity,
                onChanged: onChanged,
                compact: true,
                min: 0,
                max: 9999,
              )
            : Text(
                quantity.toString(),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
              ),
      ),
    );
  }

  Widget _buildPriceCell(double? price, bool isEditable, VoidCallback onTap) {
    return Builder(builder: (context) {
      final cs = Theme.of(context).colorScheme;
      if (price == null) {
        return Container(
          width: 100,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          child: Center(
            child: Text(
              '-',
              style: TextStyle(
                fontSize: 14,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        );
      }

      return Container(
        width: 100,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        child: GestureDetector(
          onTap: isEditable
              ? () {
                  HapticFeedback.lightImpact();
                  onTap();
                }
              : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: AppColors.success.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '\u20B9${price.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.success,
                  ),
                ),
                if (isEditable) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.edit,
                    size: 11,
                    color: AppColors.success.withValues(alpha: 0.7),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _buildStatusCell(bool isAccepted, bool isRejected, bool isMatched, double confidence) {
    String statusText;
    Color statusColor;
    IconData statusIcon;

    if (isRejected) {
      statusText = 'Rejected';
      statusColor = AppColors.error;
      statusIcon = Icons.cancel;
    } else if (isAccepted) {
      statusText = 'Accepted';
      statusColor = AppColors.success;
      statusIcon = Icons.check_circle;
    } else if (isMatched) {
      statusText = 'Matched';
      statusColor = AppColors.info;
      statusIcon = Icons.link;
    } else {
      statusText = 'Pending';
      statusColor = AppColors.warning;
      statusIcon = Icons.pending;
    }

    return Container(
      width: 100,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: statusColor.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              statusIcon,
              size: 12,
              color: statusColor,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                statusText,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: statusColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getRowColor(bool isSelected, bool isAccepted, bool isRejected, double confidence, {ColorScheme? cs}) {
    if (isRejected) {
      return AppColors.error.withValues(alpha: 0.08);
    }
    if (isAccepted) {
      return AppColors.success.withValues(alpha: 0.08);
    }
    if (isSelected) {
      return cs!.primary.withValues(alpha: 0.08);
    }

    // Confidence-based coloring
    if (confidence >= 0.8) {
      return AppColors.success.withValues(alpha: 0.05);
    } else if (confidence >= 0.5) {
      return AppColors.warning.withValues(alpha: 0.05);
    } else {
      return AppColors.error.withValues(alpha: 0.05);
    }
  }

  Color _getBorderColor(bool isSelected, bool isAccepted, bool isRejected, double confidence, {ColorScheme? cs}) {
    if (isRejected) {
      return AppColors.error.withValues(alpha: 0.3);
    }
    if (isAccepted) {
      return AppColors.success.withValues(alpha: 0.3);
    }
    if (isSelected) {
      return cs!.primary;
    }

    // Confidence-based border coloring
    if (confidence >= 0.8) {
      return AppColors.success.withValues(alpha: 0.2);
    } else if (confidence >= 0.5) {
      return AppColors.warning.withValues(alpha: 0.2);
    } else {
      return AppColors.error.withValues(alpha: 0.2);
    }
  }
}
