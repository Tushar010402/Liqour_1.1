import 'package:flutter/material.dart';
import '../../../core/constants/app_text_styles.dart';
import '../models/inventory_filters.dart';
import '../models/product.dart';
import '../models/brand.dart';

/// iOS 16-inspired Filter Bottom Sheet
/// Organized sections with clean UI
class FilterBottomSheet extends StatefulWidget {
  final InventoryFilters currentFilters;
  final List<Category> categories;
  final List<Subcategory> subcategories;
  final List<Brand> brands;
  final List<String> availableSizes;
  final double minPrice;
  final double maxPrice;

  const FilterBottomSheet({
    super.key,
    required this.currentFilters,
    required this.categories,
    required this.subcategories,
    required this.brands,
    this.availableSizes = const [],
    this.minPrice = 0,
    this.maxPrice = 10000,
  });

  static Future<InventoryFilters?> show(
    BuildContext context, {
    required InventoryFilters currentFilters,
    required List<Category> categories,
    required List<Subcategory> subcategories,
    required List<Brand> brands,
    List<String> availableSizes = const [],
    double minPrice = 0,
    double maxPrice = 10000,
  }) {
    return showModalBottomSheet<InventoryFilters>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => FilterBottomSheet(
        currentFilters: currentFilters,
        categories: categories,
        subcategories: subcategories,
        brands: brands,
        availableSizes: availableSizes,
        minPrice: minPrice,
        maxPrice: maxPrice,
      ),
    );
  }

  @override
  State<FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<FilterBottomSheet> {
  late InventoryFilters _filters;
  final _brandSearchController = TextEditingController();
  List<Brand> _filteredBrands = [];

  @override
  void initState() {
    super.initState();
    _filters = widget.currentFilters;
    _filteredBrands = widget.brands;
  }

  @override
  void dispose() {
    _brandSearchController.dispose();
    super.dispose();
  }

  void _filterBrands(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredBrands = widget.brands;
      } else {
        _filteredBrands = widget.brands
            .where((b) => b.name.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  children: [
                    // Drag Handle
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: cs.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),

                    // Title & Clear All
                    Row(
                      children: [
                        Text(
                          'Filters',
                          style: AppTextStyles.h4.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (_filters.activeFilterCount > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: cs.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${_filters.activeFilterCount}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                        const Spacer(),
                        if (_filters.hasActiveFilters)
                          TextButton(
                            onPressed: () {
                              setState(() => _filters = _filters.clear());
                            },
                            child: const Text('Clear All'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // Filter Sections
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Stock Status
                    _buildSection(
                      title: 'Stock Status',
                      icon: Icons.inventory_2,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: StockStatusFilter.values.map((status) {
                          final isSelected = _filters.stockStatus == status;
                          return ChoiceChip(
                            label: Text('${status.emoji} ${status.label}'),
                            selected: isSelected,
                            onSelected: (selected) {
                              if (selected) {
                                setState(() {
                                  _filters = _filters.copyWith(stockStatus: status);
                                });
                              }
                            },
                            selectedColor: cs.primary.withOpacity(0.2),
                            labelStyle: TextStyle(
                              color: isSelected ? cs.primary : cs.onSurfaceVariant,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                              fontSize: 13,
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Categories
                    if (widget.categories.isNotEmpty)
                      _buildSection(
                        title: 'Categories',
                        icon: Icons.category,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: widget.categories.map((category) {
                            final isSelected = _filters.selectedCategoryIds.contains(category.id);
                            return FilterChip(
                              label: Text(category.name),
                              selected: isSelected,
                              onSelected: (selected) {
                                setState(() {
                                  final categoryIds = List<String>.from(_filters.selectedCategoryIds);
                                  var subcategoryIds = List<String>.from(_filters.selectedSubcategoryIds);

                                  if (selected) {
                                    categoryIds.add(category.id);
                                  } else {
                                    categoryIds.remove(category.id);
                                    // SMART: Remove all subcategories of this category
                                    if (widget.subcategories.isNotEmpty) {
                                      subcategoryIds.removeWhere((subId) {
                                        final sub = widget.subcategories.firstWhere(
                                          (s) => s.id == subId,
                                          orElse: () => Subcategory(
                                            id: '',
                                            name: '',
                                            categoryId: '',
                                            priceRange: '',
                                            description: '',
                                            sortOrder: 0,
                                            isActive: true,
                                          ),
                                        );
                                        return sub.categoryId == category.id;
                                      });
                                    }
                                  }

                                  _filters = _filters.copyWith(
                                    selectedCategoryIds: categoryIds,
                                    selectedSubcategoryIds: subcategoryIds,
                                  );
                                });
                              },
                              selectedColor: cs.primary.withOpacity(0.2),
                              checkmarkColor: cs.primary,
                              labelStyle: TextStyle(
                                color: isSelected ? cs.primary : cs.onSurfaceVariant,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                              ),
                            );
                          }).toList(),
                        ),
                      ),

                    if (widget.categories.isNotEmpty) const SizedBox(height: 24),

                    // Subcategories (filtered by selected categories)
                    if (_filters.selectedCategoryIds.isNotEmpty) ...[
                      _buildSection(
                        title: 'Subcategories',
                        icon: Icons.subdirectory_arrow_right,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: widget.subcategories
                              .where((sub) => _filters.selectedCategoryIds.contains(sub.categoryId))
                              .map((subcategory) {
                            final isSelected = _filters.selectedSubcategoryIds.contains(subcategory.id);
                            return FilterChip(
                              label: Text(subcategory.name),
                              selected: isSelected,
                              onSelected: (selected) {
                                setState(() {
                                  final ids = List<String>.from(_filters.selectedSubcategoryIds);
                                  if (selected) {
                                    ids.add(subcategory.id);
                                  } else {
                                    ids.remove(subcategory.id);
                                  }
                                  _filters = _filters.copyWith(selectedSubcategoryIds: ids);
                                });
                              },
                              selectedColor: cs.primary.withOpacity(0.2),
                              checkmarkColor: cs.primary,
                              labelStyle: TextStyle(
                                color: isSelected ? cs.primary : cs.onSurfaceVariant,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                fontSize: 13,
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Bottle Sizes (from actual products)
                    if (widget.availableSizes.isNotEmpty)
                      _buildSection(
                        title: 'Bottle Sizes',
                        icon: Icons.local_drink,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: widget.availableSizes.map((size) {
                            final isSelected = _filters.selectedSizes.contains(size);
                            return FilterChip(
                              label: Text('${BottleSizes.getEmoji(size)} $size'),
                              selected: isSelected,
                              onSelected: (selected) {
                                setState(() {
                                  final sizes = List<String>.from(_filters.selectedSizes);
                                  if (selected) {
                                    sizes.add(size);
                                  } else {
                                    sizes.remove(size);
                                  }
                                  _filters = _filters.copyWith(selectedSizes: sizes);
                                });
                              },
                              selectedColor: cs.primary.withOpacity(0.2),
                              checkmarkColor: cs.primary,
                              labelStyle: TextStyle(
                                color: isSelected ? cs.primary : cs.onSurfaceVariant,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                              ),
                            );
                          }).toList(),
                        ),
                      ),

                    const SizedBox(height: 24),

                    // Brands (with search)
                    if (widget.brands.isNotEmpty)
                      _buildSection(
                        title: 'Brands',
                        icon: Icons.business,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Brand search
                            TextField(
                              controller: _brandSearchController,
                              decoration: InputDecoration(
                                hintText: 'Search brands...',
                                prefixIcon: const Icon(Icons.search, size: 20),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                isDense: true,
                              ),
                              onChanged: _filterBrands,
                            ),
                            const SizedBox(height: 12),

                            // Brand chips (max 20 visible)
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _filteredBrands.take(20).map((brand) {
                                final isSelected = _filters.selectedBrandIds.contains(brand.id);
                                return FilterChip(
                                  label: Text(brand.name),
                                  selected: isSelected,
                                  onSelected: (selected) {
                                    setState(() {
                                      final ids = List<String>.from(_filters.selectedBrandIds);
                                      if (selected) {
                                        ids.add(brand.id);
                                      } else {
                                        ids.remove(brand.id);
                                      }
                                      _filters = _filters.copyWith(selectedBrandIds: ids);
                                    });
                                  },
                                  selectedColor: cs.primary.withOpacity(0.2),
                                  checkmarkColor: cs.primary,
                                  labelStyle: TextStyle(
                                    color: isSelected ? cs.primary : cs.onSurfaceVariant,
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                    fontSize: 13,
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),

                    if (widget.brands.isNotEmpty) const SizedBox(height: 24),

                    // Price Range
                    _buildSection(
                      title: 'Price Range',
                      icon: Icons.attach_money,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RangeSlider(
                            values: RangeValues(
                              _filters.priceRange?.min ?? widget.minPrice,
                              _filters.priceRange?.max ?? widget.maxPrice,
                            ),
                            min: widget.minPrice,
                            max: widget.maxPrice,
                            divisions: 100,
                            labels: RangeLabels(
                              '\u20B9${(_filters.priceRange?.min ?? widget.minPrice).toStringAsFixed(0)}',
                              '\u20B9${(_filters.priceRange?.max ?? widget.maxPrice).toStringAsFixed(0)}',
                            ),
                            onChanged: (values) {
                              setState(() {
                                _filters = _filters.copyWith(
                                  priceRange: PriceRange(min: values.start, max: values.end),
                                );
                              });
                            },
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '\u20B9${(_filters.priceRange?.min ?? widget.minPrice).toStringAsFixed(0)}',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              Text(
                                '\u20B9${(_filters.priceRange?.max ?? widget.maxPrice).toStringAsFixed(0)}',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Active Status
                    _buildSection(
                      title: 'Status',
                      icon: Icons.toggle_on,
                      child: Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              label: const Text('All'),
                              selected: _filters.isActive == null,
                              onSelected: (selected) {
                                if (selected) {
                                  setState(() {
                                    _filters = _filters.copyWith(clearIsActive: true);
                                  });
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: const Text('Active'),
                              selected: _filters.isActive == true,
                              onSelected: (selected) {
                                if (selected) {
                                  setState(() {
                                    _filters = _filters.copyWith(isActive: true);
                                  });
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: const Text('Inactive'),
                              selected: _filters.isActive == false,
                              onSelected: (selected) {
                                if (selected) {
                                  setState(() {
                                    _filters = _filters.copyWith(isActive: false);
                                  });
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Apply Button
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.surface,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: SafeArea(
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, _filters),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cs.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Apply Filters',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
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

  Widget _buildSection({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: AppTextStyles.bodyLarge.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
