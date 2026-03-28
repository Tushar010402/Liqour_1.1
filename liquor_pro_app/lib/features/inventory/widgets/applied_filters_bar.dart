import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../models/inventory_filters.dart';
import '../models/product.dart';
import '../models/brand.dart';

/// Applied Filters Bar
/// Shows active filters as removable chips
class AppliedFiltersBar extends StatelessWidget {
  final InventoryFilters filters;
  final List<Category> categories;
  final List<Subcategory> subcategories;
  final List<Brand> brands;
  final Function(InventoryFilters) onFiltersChanged;

  const AppliedFiltersBar({
    super.key,
    required this.filters,
    required this.categories,
    required this.subcategories,
    required this.brands,
    required this.onFiltersChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (!filters.hasActiveFilters || filters.activeFilterCount == 0) {
      return const SizedBox.shrink();
    }

    final chips = <Widget>[];

    // Stock Status
    if (filters.stockStatus != StockStatusFilter.all) {
      chips.add(_buildFilterChip(
        context: context,
        label: filters.stockStatus.label,
        icon: filters.stockStatus.emoji,
        onRemove: () {
          onFiltersChanged(filters.removeFilter(FilterType.stockStatus));
        },
      ));
    }

    // Categories
    for (final categoryId in filters.selectedCategoryIds) {
      final category = categories.where((c) => c.id == categoryId).firstOrNull;
      if (category != null) {
        // Get subcategories for this category for smart removal
        final relatedSubcategoryIds = subcategories
            .where((sub) => sub.categoryId == categoryId)
            .map((sub) => sub.id)
            .toList();

        chips.add(_buildFilterChip(
          context: context,
          label: category.name,
          icon: '📂',
          onRemove: () {
            onFiltersChanged(filters.removeFilter(
              FilterType.category,
              value: categoryId,
              relatedSubcategoryIds: relatedSubcategoryIds,
            ));
          },
        ));
      }
    }

    // Subcategories
    for (final subcategoryId in filters.selectedSubcategoryIds) {
      final subcategory = subcategories.where((s) => s.id == subcategoryId).firstOrNull;
      if (subcategory != null) {
        chips.add(_buildFilterChip(
          context: context,
          label: subcategory.name,
          icon: '📁',
          onRemove: () {
            onFiltersChanged(filters.removeFilter(FilterType.subcategory, value: subcategoryId));
          },
        ));
      }
    }

    // Brands
    for (final brandId in filters.selectedBrandIds) {
      final brand = brands.where((b) => b.id == brandId).firstOrNull;
      if (brand != null) {
        chips.add(_buildFilterChip(
          context: context,
          label: brand.name,
          icon: '🏷️',
          onRemove: () {
            onFiltersChanged(filters.removeFilter(FilterType.brand, value: brandId));
          },
        ));
      }
    }

    // Sizes
    for (final size in filters.selectedSizes) {
      chips.add(_buildFilterChip(
        context: context,
        label: size,
        icon: BottleSizes.getEmoji(size),
        onRemove: () {
          onFiltersChanged(filters.removeFilter(FilterType.size, value: size));
        },
      ));
    }

    // Price Range
    if (filters.priceRange != null) {
      chips.add(_buildFilterChip(
        context: context,
        label: filters.priceRange.toString(),
        icon: '💰',
        onRemove: () {
          onFiltersChanged(filters.removeFilter(FilterType.priceRange));
        },
      ));
    }

    // Active Status
    if (filters.isActive != null) {
      chips.add(_buildFilterChip(
        context: context,
        label: filters.isActive! ? 'Active' : 'Inactive',
        icon: filters.isActive! ? '✅' : '❌',
        onRemove: () {
          onFiltersChanged(filters.removeFilter(FilterType.isActive));
        },
      ));
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: cs.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Active Filters',
                style: AppTextStyles.caption.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => onFiltersChanged(filters.clear()),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Clear All',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: chips
                  .map((chip) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: chip,
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required BuildContext context,
    required String label,
    required String icon,
    required VoidCallback onRemove,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: cs.primary.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            icon,
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: cs.primary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: cs.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close,
                size: 12,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
