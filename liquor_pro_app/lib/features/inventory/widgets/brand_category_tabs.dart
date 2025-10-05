import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';

/// Category & Subcategory Navigation Tabs
/// Provides hierarchical navigation for brand catalog
class BrandCategoryTabs extends StatefulWidget {
  final List<CategoryGroup> categories;
  final String? selectedCategoryId;
  final String? selectedSubcategoryId;
  final Function(String? categoryId, String? subcategoryId) onFilterChanged;

  const BrandCategoryTabs({
    super.key,
    required this.categories,
    this.selectedCategoryId,
    this.selectedSubcategoryId,
    required this.onFilterChanged,
  });

  @override
  State<BrandCategoryTabs> createState() => _BrandCategoryTabsState();
}

class _BrandCategoryTabsState extends State<BrandCategoryTabs>
    with TickerProviderStateMixin {
  late TabController _tabController;
  String? _selectedSubcategoryId;

  @override
  void initState() {
    super.initState();
    final tabLength = widget.categories.length + 1; // +1 for "All" tab
    _tabController = TabController(
      length: tabLength > 0 ? tabLength : 1, // Ensure at least 1 tab
      vsync: this,
    );
    _selectedSubcategoryId = widget.selectedSubcategoryId;
    _tabController.addListener(_onTabChange);
  }

  @override
  void didUpdateWidget(BrandCategoryTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update tab controller if category count changes
    final newLength = widget.categories.length + 1;
    if (oldWidget.categories.length != widget.categories.length &&
        _tabController.length != newLength) {
      // Save current index
      final currentIndex = _tabController.index;

      // Remove old listener and dispose
      _tabController.removeListener(_onTabChange);
      _tabController.dispose();

      // Create new controller
      _tabController = TabController(
        length: newLength > 0 ? newLength : 1,
        vsync: this,
        initialIndex: currentIndex < newLength ? currentIndex : 0,
      );
      _tabController.addListener(_onTabChange);
    }
  }

  void _onTabChange() {
    if (!_tabController.indexIsChanging) {
      _handleCategoryChange(_tabController.index);
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChange);
    _tabController.dispose();
    super.dispose();
  }

  void _handleCategoryChange(int index) {
    if (index == 0) {
      // "All" tab selected
      setState(() {
        _selectedSubcategoryId = null;
      });
      widget.onFilterChanged(null, null);
    } else {
      final category = widget.categories[index - 1];
      setState(() {
        _selectedSubcategoryId = null;
      });
      widget.onFilterChanged(category.id, null);
    }
  }

  void _handleSubcategoryChange(String? subcategoryId) {
    setState(() {
      _selectedSubcategoryId = subcategoryId;
    });

    final currentIndex = _tabController.index;
    if (currentIndex > 0) {
      final category = widget.categories[currentIndex - 1];
      widget.onFilterChanged(category.id, subcategoryId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Category Tabs
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            indicatorColor: AppColors.primary,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            labelStyle: AppTextStyles.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: AppTextStyles.bodyMedium,
            tabs: [
              Tab(
                child: Row(
                  children: [
                    const Icon(Icons.grid_view, size: 18),
                    const SizedBox(width: 8),
                    const Text('All'),
                  ],
                ),
              ),
              ...widget.categories.map((category) {
                return Tab(
                  child: Row(
                    children: [
                      Icon(_getCategoryIcon(category.name), size: 18),
                      const SizedBox(width: 8),
                      Text(category.name),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),

        // Subcategory Chips (shown when category is selected)
        if (_tabController.index > 0)
          Container(
            height: 56,
            color: AppColors.surface,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: _buildSubcategoryChips(),
          ),
      ],
    );
  }

  Widget _buildSubcategoryChips() {
    final currentIndex = _tabController.index;
    if (currentIndex == 0) return const SizedBox.shrink();

    final category = widget.categories[currentIndex - 1];
    if (category.subcategories.isEmpty) {
      return Center(
        child: Text(
          'No subcategories',
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      );
    }

    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        _buildSubcategoryChip(
          'All ${category.name}',
          null,
          _selectedSubcategoryId == null,
        ),
        const SizedBox(width: 8),
        ...category.subcategories.map((subcategory) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _buildSubcategoryChip(
              subcategory.name,
              subcategory.id,
              _selectedSubcategoryId == subcategory.id,
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSubcategoryChip(String label, String? id, bool isSelected) {
    return InkWell(
      onTap: () => _handleSubcategoryChange(id),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: 1.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            color: isSelected ? Colors.white : AppColors.textPrimary,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  IconData _getCategoryIcon(String categoryName) {
    final name = categoryName.toLowerCase();
    if (name.contains('whisky') || name.contains('whiskey')) {
      return Icons.local_bar;
    } else if (name.contains('rum')) {
      return Icons.wine_bar;
    } else if (name.contains('vodka')) {
      return Icons.liquor;
    } else if (name.contains('gin')) {
      return Icons.local_drink;
    } else if (name.contains('beer')) {
      return Icons.sports_bar;
    } else if (name.contains('wine')) {
      return Icons.wine_bar;
    }
    return Icons.category;
  }
}

/// Category data model for tabs
class CategoryGroup {
  final String id;
  final String name;
  final List<SubcategoryItem> subcategories;
  final int brandCount;

  CategoryGroup({
    required this.id,
    required this.name,
    required this.subcategories,
    this.brandCount = 0,
  });
}

/// Subcategory data model for chips
class SubcategoryItem {
  final String id;
  final String name;
  final int brandCount;

  SubcategoryItem({
    required this.id,
    required this.name,
    this.brandCount = 0,
  });
}
