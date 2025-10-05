import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../models/saas_brand.dart';

/// Brand Variant Card with Inline Stock Input
/// Mobile-optimized card for selecting brands and setting initial stock
class BrandVariantCardWithStock extends StatefulWidget {
  final SaasBrandVariant variant;
  final String brandName;
  final bool isSelected;
  final int stockQuantity;
  final Function(bool selected) onSelectionChanged;
  final Function(int quantity) onStockChanged;
  final bool showStockInput;

  const BrandVariantCardWithStock({
    super.key,
    required this.variant,
    required this.brandName,
    required this.isSelected,
    this.stockQuantity = 0,
    required this.onSelectionChanged,
    required this.onStockChanged,
    this.showStockInput = false,
  });

  @override
  State<BrandVariantCardWithStock> createState() =>
      _BrandVariantCardWithStockState();
}

class _BrandVariantCardWithStockState
    extends State<BrandVariantCardWithStock> {
  late TextEditingController _stockController;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _stockController = TextEditingController(
      text: widget.stockQuantity > 0 ? widget.stockQuantity.toString() : '',
    );
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(BrandVariantCardWithStock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stockQuantity != widget.stockQuantity) {
      _stockController.text =
          widget.stockQuantity > 0 ? widget.stockQuantity.toString() : '';
    }
  }

  @override
  void dispose() {
    _stockController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _adjustStock(int delta) {
    final current = int.tryParse(_stockController.text) ?? 0;
    final newValue = (current + delta).clamp(0, 99999);
    _stockController.text = newValue > 0 ? newValue.toString() : '';
    widget.onStockChanged(newValue);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: widget.isSelected ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: widget.isSelected
              ? AppColors.primary
              : AppColors.border.withOpacity(0.3),
          width: widget.isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: () => widget.onSelectionChanged(!widget.isSelected),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Selection Checkbox
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: widget.isSelected
                          ? AppColors.primary
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: widget.isSelected
                            ? AppColors.primary
                            : AppColors.border,
                        width: 2,
                      ),
                    ),
                    child: widget.isSelected
                        ? const Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 18,
                          )
                        : null,
                  ),

                  const SizedBox(width: 12),

                  // Product Image
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      image: widget.variant.picture.isNotEmpty
                          ? DecorationImage(
                              image: NetworkImage(widget.variant.picture),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: widget.variant.picture.isEmpty
                        ? const Icon(
                            Icons.liquor,
                            color: AppColors.primary,
                            size: 32,
                          )
                        : null,
                  ),

                  const SizedBox(width: 12),

                  // Product Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.brandName} ${widget.variant.size}',
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.success.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '₹${widget.variant.mrp.toStringAsFixed(0)}',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.success,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'ABV ${widget.variant.alcoholContent}%',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Stock Input (shown when selected and showStockInput is true)
              if (widget.isSelected && widget.showStockInput) ...[
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),

                Row(
                  children: [
                    // Stock Input Field
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Initial Stock',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            height: 56,
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _focusNode.hasFocus
                                    ? AppColors.primary
                                    : AppColors.border,
                                width: _focusNode.hasFocus ? 2 : 1,
                              ),
                            ),
                            child: TextField(
                              controller: _stockController,
                              focusNode: _focusNode,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              style: AppTextStyles.h6.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: InputDecoration(
                                hintText: '0',
                                hintStyle: AppTextStyles.h6.copyWith(
                                  color: AppColors.textSecondary.withOpacity(0.5),
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 16,
                                ),
                                suffixText: 'units',
                                suffixStyle: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              onChanged: (value) {
                                widget.onStockChanged(
                                  int.tryParse(value) ?? 0,
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Quick Adjust Buttons
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Quick Add',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _buildQuickButton('+10', 10),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: _buildQuickButton('+50', 50),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: _buildQuickButton('-10', -10),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: _buildQuickButton('Clear', 0, isReset: true),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],

              // Barcode and HSN (if available)
              if (widget.variant.barcode.isNotEmpty ||
                  widget.variant.hsnCode.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (widget.variant.barcode.isNotEmpty) ...[
                      Icon(
                        Icons.qr_code,
                        size: 14,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        widget.variant.barcode,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                    if (widget.variant.barcode.isNotEmpty &&
                        widget.variant.hsnCode.isNotEmpty)
                      const SizedBox(width: 12),
                    if (widget.variant.hsnCode.isNotEmpty) ...[
                      Text(
                        'HSN: ${widget.variant.hsnCode}',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickButton(String label, int delta, {bool isReset = false}) {
    return InkWell(
      onTap: () {
        if (isReset) {
          _stockController.text = '';
          widget.onStockChanged(0);
        } else {
          _adjustStock(delta);
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 28,
        decoration: BoxDecoration(
          color: isReset
              ? AppColors.error.withOpacity(0.1)
              : delta > 0
                  ? AppColors.success.withOpacity(0.1)
                  : AppColors.warning.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isReset
                ? AppColors.error.withOpacity(0.3)
                : delta > 0
                    ? AppColors.success.withOpacity(0.3)
                    : AppColors.warning.withOpacity(0.3),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: isReset
                  ? AppColors.error
                  : delta > 0
                      ? AppColors.success
                      : AppColors.warning,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }
}
