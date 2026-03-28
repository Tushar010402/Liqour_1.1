import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/haptic_feedback.dart';
import '../models/saas_brand.dart';

/// Expandable brand card with iOS-style design
class ExpandableBrandCard extends StatefulWidget {
  final SaasBrand brand;
  final bool isSelected;
  final Set<String> selectedVariantIds;
  final Function(String brandId) onBrandToggle;
  final Function(String brandId, String variantId) onVariantToggle;
  final bool showVariantSelection;

  const ExpandableBrandCard({
    super.key,
    required this.brand,
    required this.isSelected,
    required this.selectedVariantIds,
    required this.onBrandToggle,
    required this.onVariantToggle,
    this.showVariantSelection = true,
  });

  @override
  State<ExpandableBrandCard> createState() => _ExpandableBrandCardState();
}

class _ExpandableBrandCardState extends State<ExpandableBrandCard>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _expandController;
  late Animation<double> _iconTurns;

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    _iconTurns = Tween<double>(begin: 0.0, end: 0.5).animate(
      CurvedAnimation(parent: _expandController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _expandController.dispose();
    super.dispose();
  }

  void _toggleExpand() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _expandController.forward();
      } else {
        _expandController.reverse();
      }
    });
    HapticFeedbackUtil.selection();
  }

  String _getPriceRange() {
    if (widget.brand.variants.isEmpty) return '';

    final prices = widget.brand.variants
        .map((v) => v.sellingPrice)
        .where((p) => p > 0)
        .toList()
      ..sort();

    if (prices.isEmpty) return '';
    if (prices.length == 1) return '\u20B9${prices.first.toStringAsFixed(0)}';

    final min = prices.first.toStringAsFixed(0);
    final max = prices.last.toStringAsFixed(0);
    return '\u20B9$min - \u20B9$max';
  }

  String _getSizesList() {
    if (widget.brand.variants.isEmpty) return '';

    final sizes = widget.brand.variants
        .map((v) => v.size)
        .take(3)
        .join(', ');

    return widget.brand.variants.length > 3 ? '$sizes...' : sizes;
  }

  String _getCategoryIcon() {
    final category = widget.brand.categoryNameFromVariant?.toLowerCase() ?? '';

    switch (category) {
      case 'beer':
        return '🍺';
      case 'whiskey':
      case 'whisky':
        return '🥃';
      case 'wine':
        return '🍷';
      case 'vodka':
        return '🍸';
      case 'rum':
        return '🥃';
      case 'gin':
        return '🍸';
      default:
        return '🍾';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final priceRange = _getPriceRange();
    final sizes = _getSizesList();
    final allVariantsSelected = widget.brand.variants.every(
      (v) => widget.selectedVariantIds.contains(v.id),
    );

    final isOnboarded = widget.brand.isOnboarded == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        // VISUAL DISTINCTION: Onboarded brands get subtle green tint
        color: isOnboarded
            ? AppColors.success.withValues(alpha: 0.06)
            : cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOnboarded
              ? AppColors.success
              : widget.isSelected
                  ? cs.primary
                  : cs.outlineVariant,
          width: isOnboarded || widget.isSelected ? 1.5 : 1,
        ),
        boxShadow: widget.isSelected
            ? [
                BoxShadow(
                  color: cs.primary.withValues(alpha: 0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : isOnboarded
                ? [
                    BoxShadow(
                      color: AppColors.success.withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
              ],
      ),
      child: Column(
        children: [
          // Main Card Content
          InkWell(
            onTap: widget.showVariantSelection ? _toggleExpand : null,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Checkbox - DISABLED for onboarded brands
                  GestureDetector(
                    onTap: isOnboarded ? null : () {
                      HapticFeedbackUtil.selection();
                      widget.onBrandToggle(widget.brand.id);
                    },
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: isOnboarded
                            ? AppColors.success  // Green for onboarded
                            : allVariantsSelected
                                ? cs.primary
                                : cs.surface,
                        border: Border.all(
                          color: isOnboarded
                              ? AppColors.success
                              : allVariantsSelected
                                  ? cs.primary
                                  : cs.outlineVariant,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: (isOnboarded || allVariantsSelected)
                          ? const Icon(
                              Icons.check,
                              size: 16,
                              color: Colors.white,
                            )
                          : null,
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Brand Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Brand Name
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                widget.brand.name,
                                style: AppTextStyles.bodyLarge.copyWith(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 17,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isOnboarded) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.success,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.check_circle,
                                      size: 12,
                                      color: Colors.white,
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      'Added',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),

                        const SizedBox(height: 4),

                        // Category & Variant Count
                        Row(
                          children: [
                            Text(
                              _getCategoryIcon(),
                              style: const TextStyle(fontSize: 14),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              widget.brand.categoryNameFromVariant ?? 'Other',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '\u2022',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: cs.outlineVariant,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${widget.brand.variants.length} variants',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 4),

                        // Price Range & Sizes
                        Row(
                          children: [
                            if (priceRange.isNotEmpty) ...[
                              Text(
                                priceRange,
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: cs.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '\u2022',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: cs.outlineVariant,
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Flexible(
                              child: Text(
                                sizes,
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Expand Arrow
                  if (widget.showVariantSelection)
                    RotationTransition(
                      turns: _iconTurns,
                      child: Icon(
                        CupertinoIcons.chevron_down,
                        color: cs.onSurfaceVariant,
                        size: 20,
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Expanded Variant List
          if (widget.showVariantSelection)
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              child: _isExpanded
                  ? Container(
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(12),
                        ),
                      ),
                      child: Column(
                        children: [
                          const Divider(height: 1, thickness: 1),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Select Variants',
                                  style: AppTextStyles.caption.copyWith(
                                    color: cs.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ...widget.brand.variants.map((variant) {
                                  final isSelected = widget.selectedVariantIds
                                      .contains(variant.id);

                                  return _VariantItem(
                                    variant: variant,
                                    isSelected: isSelected,
                                    onToggle: () {
                                      HapticFeedbackUtil.selection();
                                      widget.onVariantToggle(
                                        widget.brand.id,
                                        variant.id,
                                      );
                                    },
                                  );
                                }),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }
}

/// Individual variant item in the expanded card
class _VariantItem extends StatelessWidget {
  final SaasBrandVariant variant;
  final bool isSelected;
  final VoidCallback onToggle;

  const _VariantItem({
    required this.variant,
    required this.isSelected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isOnboarded = variant.isOnboarded == true;

    return GestureDetector(
      // Disable tap for already onboarded variants
      onTap: isOnboarded ? null : onToggle,
      child: Opacity(
        opacity: isOnboarded ? 0.6 : 1.0,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isOnboarded ? cs.surfaceContainerHighest : cs.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isOnboarded
                  ? AppColors.success.withValues(alpha: 0.5)
                  : isSelected
                      ? cs.primary
                      : cs.outlineVariant,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              // Checkbox - disabled for onboarded items
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: isOnboarded
                      ? AppColors.success  // Green check for onboarded
                      : isSelected
                          ? cs.primary
                          : cs.surface,
                  border: Border.all(
                    color: isOnboarded
                        ? AppColors.success
                        : isSelected
                            ? cs.primary
                            : cs.outlineVariant,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: (isOnboarded || isSelected)
                    ? Icon(
                        isOnboarded ? Icons.check : Icons.check,
                        size: 14,
                        color: Colors.white,
                      )
                    : null,
              ),

              const SizedBox(width: 12),

              // Variant Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      variant.size,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isOnboarded ? cs.onSurfaceVariant : null,
                      ),
                    ),
                    if (variant.sellingPrice > 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        '\u20B9${variant.sellingPrice.toStringAsFixed(0)}',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: isOnboarded ? cs.onSurfaceVariant : cs.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Onboarded Badge
              if (isOnboarded)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 12,
                        color: Colors.white,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Added',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
