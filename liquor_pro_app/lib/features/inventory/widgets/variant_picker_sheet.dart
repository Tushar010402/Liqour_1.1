import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../models/saas_brand.dart';
import '../providers/brand_selection_provider.dart';

/// Bottom sheet for selecting specific variants of a brand
/// Supports Select All, Clear All, and individual variant selection
class VariantPickerSheet extends StatefulWidget {
  final SaasBrand brand;

  const VariantPickerSheet({
    super.key,
    required this.brand,
  });

  @override
  State<VariantPickerSheet> createState() => _VariantPickerSheetState();
}

class _VariantPickerSheetState extends State<VariantPickerSheet> {
  late Set<String> _localSelection;
  bool _isInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      final provider = context.read<BrandSelectionProvider>();
      _localSelection = Set.from(provider.getSelectedVariantIds(widget.brand.id));
      _isInitialized = true;
    }
  }

  void _toggleVariant(String variantId) {
    setState(() {
      if (_localSelection.contains(variantId)) {
        _localSelection.remove(variantId);
      } else {
        _localSelection.add(variantId);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _localSelection = widget.brand.variants.map((v) => v.id).toSet();
    });
  }

  void _clearAll() {
    setState(() {
      _localSelection.clear();
    });
  }

  void _confirm() {
    final provider = context.read<BrandSelectionProvider>();

    // Clear existing selection for this brand
    if (provider.isBrandSelected(widget.brand.id)) {
      provider.toggleBrand(widget.brand.id, widget.brand.variants);
    }

    // Add selected variants
    for (final variantId in _localSelection) {
      provider.toggleVariant(widget.brand.id, variantId);
    }

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final totalVariants = widget.brand.variants.length;
    final selectedCount = _localSelection.length;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Brand Icon
                        if (widget.brand.picture.isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              widget.brand.picture,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: cs.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Center(
                                    child: Text(
                                      widget.brand.categoryNameFromVariant?.substring(0, 1).toUpperCase() ?? '\uD83C\uDF7E',
                                      style: const TextStyle(fontSize: 24),
                                    ),
                                  ),
                                );
                              },
                            ),
                          )
                        else
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(
                                widget.brand.categoryNameFromVariant?.substring(0, 1).toUpperCase() ?? '\uD83C\uDF7E',
                                style: const TextStyle(fontSize: 24),
                              ),
                            ),
                          ),
                        const SizedBox(width: 12),

                        // Brand Info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.brand.name,
                                style: AppTextStyles.h6,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Select variants to onboard',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Close button
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Selection summary and controls
                    Row(
                      children: [
                        // Selection count
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: selectedCount > 0
                                ? cs.primary.withValues(alpha:0.1)
                                : cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: selectedCount > 0
                                  ? cs.primary
                                  : cs.outlineVariant,
                            ),
                          ),
                          child: Text(
                            '$selectedCount of $totalVariants selected',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: selectedCount > 0
                                  ? cs.primary
                                  : cs.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),

                        const Spacer(),

                        // Select All button
                        TextButton.icon(
                          onPressed: _selectAll,
                          icon: const Icon(Icons.check_circle_outline, size: 18),
                          label: const Text('All'),
                          style: TextButton.styleFrom(
                            foregroundColor: cs.primary,
                          ),
                        ),

                        const SizedBox(width: 8),

                        // Clear All button
                        TextButton.icon(
                          onPressed: _clearAll,
                          icon: const Icon(Icons.remove_circle_outline, size: 18),
                          label: const Text('Clear'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.error,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Variant list
              Expanded(
                child: widget.brand.variants.isEmpty
                    ? Center(
                        child: Text(
                          'No variants available',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: widget.brand.variants.length,
                        separatorBuilder: (context, index) => const Divider(height: 1, indent: 72),
                        itemBuilder: (context, index) {
                          final variant = widget.brand.variants[index];
                          final isSelected = _localSelection.contains(variant.id);

                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => _toggleVariant(variant.id),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                color: isSelected
                                    ? cs.primary.withValues(alpha:0.05)
                                    : Colors.transparent,
                                child: Row(
                                  children: [
                                    // Checkbox
                                    AnimatedContainer(
                                      duration: const Duration(milliseconds: 200),
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        color: isSelected ? cs.primary : Colors.transparent,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: isSelected ? cs.primary : cs.outlineVariant,
                                          width: 2,
                                        ),
                                      ),
                                      child: isSelected
                                          ? const Icon(
                                              Icons.check,
                                              size: 16,
                                              color: Colors.white,
                                            )
                                          : null,
                                    ),

                                    const SizedBox(width: 16),

                                    // Variant info
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            variant.size.isNotEmpty ? variant.size : 'Variant ${index + 1}',
                                            style: AppTextStyles.bodyMedium.copyWith(
                                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.local_offer,
                                                size: 12,
                                                color: cs.onSurfaceVariant,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                '\u20B9${variant.mrp.toStringAsFixed(0)}',
                                                style: AppTextStyles.bodySmall.copyWith(
                                                  color: cs.onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Selection indicator
                                    if (isSelected)
                                      Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: cs.primary.withValues(alpha:0.1),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Icons.check,
                                          size: 16,
                                          color: cs.primary,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),

              // Bottom action bar
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cs.surface,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha:0.1),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: selectedCount > 0 ? _confirm : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cs.primary,
                        foregroundColor: cs.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        disabledBackgroundColor: cs.outlineVariant,
                      ),
                      child: Text(
                        selectedCount > 0
                            ? 'Confirm Selection ($selectedCount)'
                            : 'Select at least one variant',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
