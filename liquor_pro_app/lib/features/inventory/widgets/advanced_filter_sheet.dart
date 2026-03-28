import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/haptic_feedback.dart';

/// Filter configuration for brand catalog
class BrandFilterConfig {
  Set<String> selectedCategoryIds;
  Set<String> selectedSubcategoryIds;
  Set<String> selectedSizes;
  double? minPrice;
  double? maxPrice;
  String sortBy; // 'name_asc', 'name_desc', 'price_asc', 'price_desc'
  bool showOnboarded;

  BrandFilterConfig({
    Set<String>? selectedCategoryIds,
    Set<String>? selectedSubcategoryIds,
    Set<String>? selectedSizes,
    this.minPrice,
    this.maxPrice,
    this.sortBy = 'name_asc',
    this.showOnboarded = true,
  })  : selectedCategoryIds = selectedCategoryIds ?? {},
        selectedSubcategoryIds = selectedSubcategoryIds ?? {},
        selectedSizes = selectedSizes ?? {};

  BrandFilterConfig copyWith({
    Set<String>? selectedCategoryIds,
    Set<String>? selectedSubcategoryIds,
    Set<String>? selectedSizes,
    double? minPrice,
    double? maxPrice,
    String? sortBy,
    bool? showOnboarded,
  }) {
    return BrandFilterConfig(
      selectedCategoryIds: selectedCategoryIds ?? this.selectedCategoryIds,
      selectedSubcategoryIds:
          selectedSubcategoryIds ?? this.selectedSubcategoryIds,
      selectedSizes: selectedSizes ?? this.selectedSizes,
      minPrice: minPrice ?? this.minPrice,
      maxPrice: maxPrice ?? this.maxPrice,
      sortBy: sortBy ?? this.sortBy,
      showOnboarded: showOnboarded ?? this.showOnboarded,
    );
  }

  bool get hasActiveFilters {
    return selectedCategoryIds.isNotEmpty ||
        selectedSubcategoryIds.isNotEmpty ||
        selectedSizes.isNotEmpty ||
        minPrice != null ||
        maxPrice != null ||
        sortBy != 'name_asc';
  }

  int get activeFilterCount {
    int count = 0;
    if (selectedCategoryIds.isNotEmpty) count++;
    if (selectedSubcategoryIds.isNotEmpty) count++;
    if (selectedSizes.isNotEmpty) count++;
    if (minPrice != null || maxPrice != null) count++;
    if (sortBy != 'name_asc') count++;
    return count;
  }
}

/// Advanced filter bottom sheet with iOS design
class AdvancedFilterSheet extends StatefulWidget {
  final BrandFilterConfig initialConfig;
  final List<FilterOption> categories;
  final List<FilterOption> subcategories;
  final List<String> availableSizes;
  final double minPriceLimit;
  final double maxPriceLimit;

  const AdvancedFilterSheet({
    super.key,
    required this.initialConfig,
    required this.categories,
    required this.subcategories,
    required this.availableSizes,
    this.minPriceLimit = 0,
    this.maxPriceLimit = 10000,
  });

  @override
  State<AdvancedFilterSheet> createState() => _AdvancedFilterSheetState();

  static Future<BrandFilterConfig?> show(
    BuildContext context, {
    required BrandFilterConfig initialConfig,
    required List<FilterOption> categories,
    required List<FilterOption> subcategories,
    required List<String> availableSizes,
    double minPriceLimit = 0,
    double maxPriceLimit = 10000,
  }) {
    return showModalBottomSheet<BrandFilterConfig>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AdvancedFilterSheet(
        initialConfig: initialConfig,
        categories: categories,
        subcategories: subcategories,
        availableSizes: availableSizes,
        minPriceLimit: minPriceLimit,
        maxPriceLimit: maxPriceLimit,
      ),
    );
  }
}

class _AdvancedFilterSheetState extends State<AdvancedFilterSheet> {
  late BrandFilterConfig _config;

  @override
  void initState() {
    super.initState();
    _config = BrandFilterConfig(
      selectedCategoryIds: Set.from(widget.initialConfig.selectedCategoryIds),
      selectedSubcategoryIds:
          Set.from(widget.initialConfig.selectedSubcategoryIds),
      selectedSizes: Set.from(widget.initialConfig.selectedSizes),
      minPrice: widget.initialConfig.minPrice,
      maxPrice: widget.initialConfig.maxPrice,
      sortBy: widget.initialConfig.sortBy,
      showOnboarded: widget.initialConfig.showOnboarded,
    );
  }

  void _toggleCategory(String id) {
    setState(() {
      if (_config.selectedCategoryIds.contains(id)) {
        _config.selectedCategoryIds.remove(id);
      } else {
        _config.selectedCategoryIds.add(id);
      }
    });
    HapticFeedbackUtil.selection();
  }

  void _toggleSubcategory(String id) {
    setState(() {
      if (_config.selectedSubcategoryIds.contains(id)) {
        _config.selectedSubcategoryIds.remove(id);
      } else {
        _config.selectedSubcategoryIds.add(id);
      }
    });
    HapticFeedbackUtil.selection();
  }

  void _toggleSize(String size) {
    setState(() {
      if (_config.selectedSizes.contains(size)) {
        _config.selectedSizes.remove(size);
      } else {
        _config.selectedSizes.add(size);
      }
    });
    HapticFeedbackUtil.selection();
  }

  void _updateSortBy(String sortBy) {
    setState(() {
      _config.sortBy = sortBy;
    });
    HapticFeedbackUtil.selection();
  }

  void _resetFilters() {
    setState(() {
      _config = BrandFilterConfig();
    });
    HapticFeedbackUtil.selection();
  }

  void _applyFilters() {
    Navigator.of(context).pop(_config);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle Bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 36,
            height: 5,
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2.5),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Filters',
                  style: AppTextStyles.h2.copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_config.hasActiveFilters)
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: _resetFilters,
                    child: Text(
                      'Reset',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Filter Content
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Categories
                  if (widget.categories.isNotEmpty) ...[
                    _FilterSection(
                      title: 'Categories',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: widget.categories.map((category) {
                          final isSelected =
                              _config.selectedCategoryIds.contains(category.id);
                          return _FilterChip(
                            label: category.label,
                            icon: category.icon,
                            isSelected: isSelected,
                            onTap: () => _toggleCategory(category.id),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Subcategories
                  if (widget.subcategories.isNotEmpty) ...[
                    _FilterSection(
                      title: 'Subcategories',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: widget.subcategories.map((subcategory) {
                          final isSelected = _config.selectedSubcategoryIds
                              .contains(subcategory.id);
                          return _FilterChip(
                            label: subcategory.label,
                            isSelected: isSelected,
                            onTap: () => _toggleSubcategory(subcategory.id),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Sizes
                  if (widget.availableSizes.isNotEmpty) ...[
                    _FilterSection(
                      title: 'Sizes',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: widget.availableSizes.map((size) {
                          final isSelected = _config.selectedSizes.contains(size);
                          return _FilterChip(
                            label: size,
                            isSelected: isSelected,
                            onTap: () => _toggleSize(size),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Price Range
                  _FilterSection(
                    title: 'Price Range',
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '₹${(_config.minPrice ?? widget.minPriceLimit).toStringAsFixed(0)}',
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '₹${(_config.maxPrice ?? widget.maxPriceLimit).toStringAsFixed(0)}',
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        RangeSlider(
                          values: RangeValues(
                            _config.minPrice ?? widget.minPriceLimit,
                            _config.maxPrice ?? widget.maxPriceLimit,
                          ),
                          min: widget.minPriceLimit,
                          max: widget.maxPriceLimit,
                          divisions: 50,
                          activeColor: cs.primary,
                          inactiveColor: cs.outlineVariant,
                          onChanged: (RangeValues values) {
                            setState(() {
                              _config.minPrice = values.start;
                              _config.maxPrice = values.end;
                            });
                          },
                          onChangeEnd: (RangeValues values) {
                            HapticFeedbackUtil.selection();
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Sort By
                  _FilterSection(
                    title: 'Sort By',
                    child: Column(
                      children: [
                        _SortOption(
                          label: 'Name (A-Z)',
                          value: 'name_asc',
                          groupValue: _config.sortBy,
                          onChanged: _updateSortBy,
                        ),
                        _SortOption(
                          label: 'Name (Z-A)',
                          value: 'name_desc',
                          groupValue: _config.sortBy,
                          onChanged: _updateSortBy,
                        ),
                        _SortOption(
                          label: 'Price (Low to High)',
                          value: 'price_asc',
                          groupValue: _config.sortBy,
                          onChanged: _updateSortBy,
                        ),
                        _SortOption(
                          label: 'Price (High to Low)',
                          value: 'price_desc',
                          groupValue: _config.sortBy,
                          onChanged: _updateSortBy,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Show Onboarded Toggle
                  _FilterSection(
                    title: 'Display Options',
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Show Onboarded Brands',
                            style: AppTextStyles.bodyMedium,
                          ),
                          CupertinoSwitch(
                            value: _config.showOnboarded,
                            activeTrackColor: cs.primary,
                            onChanged: (value) {
                              setState(() {
                                _config.showOnboarded = value;
                              });
                              HapticFeedbackUtil.selection();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom Actions
          Container(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: bottomPadding + 16,
            ),
            decoration: BoxDecoration(
              color: cs.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: Row(
              children: [
                // Active Filter Count
                if (_config.hasActiveFilters)
                  Container(
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_config.activeFilterCount} active',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                // Apply Button
                Expanded(
                  child: CupertinoButton(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(12),
                    onPressed: _applyFilters,
                    child: Text(
                      'Apply Filters',
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
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
}

/// Filter section with title
class _FilterSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _FilterSection({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTextStyles.bodyMedium.copyWith(
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

/// Filter chip for multi-select options
class _FilterChip extends StatelessWidget {
  final String label;
  final String? icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? cs.primary : cs.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? cs.primary : cs.outlineVariant,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: cs.primary.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Text(
                icon!,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: AppTextStyles.bodyMedium.copyWith(
                color: isSelected ? Colors.white : cs.onSurface,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sort option radio button
class _SortOption extends StatelessWidget {
  final String label;
  final String value;
  final String groupValue;
  final Function(String) onChanged;

  const _SortOption({
    required this.label,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = value == groupValue;
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => onChanged(value),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? cs.primary : cs.outlineVariant,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? cs.primary : cs.outlineVariant,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: cs.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Filter option data model
class FilterOption {
  final String id;
  final String label;
  final String? icon;

  FilterOption({
    required this.id,
    required this.label,
    this.icon,
  });
}
