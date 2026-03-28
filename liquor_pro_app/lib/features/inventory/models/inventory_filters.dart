/// Inventory Filters Model
/// Comprehensive filter state for inventory screen
class InventoryFilters {
  final String? searchQuery;
  final List<String> selectedCategoryIds;
  final List<String> selectedSubcategoryIds;
  final List<String> selectedBrandIds;
  final List<String> selectedSizes;
  final StockStatusFilter stockStatus;
  final PriceRange? priceRange;
  final bool? isActive;

  const InventoryFilters({
    this.searchQuery,
    this.selectedCategoryIds = const [],
    this.selectedSubcategoryIds = const [],
    this.selectedBrandIds = const [],
    this.selectedSizes = const [],
    this.stockStatus = StockStatusFilter.all,
    this.priceRange,
    this.isActive,
  });

  /// Check if any filters are applied
  bool get hasActiveFilters {
    return searchQuery != null && searchQuery!.isNotEmpty ||
        selectedCategoryIds.isNotEmpty ||
        selectedSubcategoryIds.isNotEmpty ||
        selectedBrandIds.isNotEmpty ||
        selectedSizes.isNotEmpty ||
        stockStatus != StockStatusFilter.all ||
        priceRange != null ||
        isActive != null;
  }

  /// Count of active filters (excluding search)
  int get activeFilterCount {
    int count = 0;
    if (selectedCategoryIds.isNotEmpty) count++;
    if (selectedSubcategoryIds.isNotEmpty) count++;
    if (selectedBrandIds.isNotEmpty) count++;
    if (selectedSizes.isNotEmpty) count++;
    if (stockStatus != StockStatusFilter.all) count++;
    if (priceRange != null) count++;
    if (isActive != null) count++;
    return count;
  }

  /// Clear all filters
  InventoryFilters clear() {
    return const InventoryFilters();
  }

  /// Copy with modifications
  InventoryFilters copyWith({
    String? searchQuery,
    List<String>? selectedCategoryIds,
    List<String>? selectedSubcategoryIds,
    List<String>? selectedBrandIds,
    List<String>? selectedSizes,
    StockStatusFilter? stockStatus,
    PriceRange? priceRange,
    bool? isActive,
    bool clearSearch = false,
    bool clearPriceRange = false,
    bool clearIsActive = false,
  }) {
    return InventoryFilters(
      searchQuery: clearSearch ? null : (searchQuery ?? this.searchQuery),
      selectedCategoryIds: selectedCategoryIds ?? this.selectedCategoryIds,
      selectedSubcategoryIds: selectedSubcategoryIds ?? this.selectedSubcategoryIds,
      selectedBrandIds: selectedBrandIds ?? this.selectedBrandIds,
      selectedSizes: selectedSizes ?? this.selectedSizes,
      stockStatus: stockStatus ?? this.stockStatus,
      priceRange: clearPriceRange ? null : (priceRange ?? this.priceRange),
      isActive: clearIsActive ? null : (isActive ?? this.isActive),
    );
  }

  /// Remove a specific filter
  /// Smart behavior: When removing a category, also removes its subcategories
  InventoryFilters removeFilter(
    FilterType type, {
    String? value,
    List<String>? relatedSubcategoryIds,
  }) {
    switch (type) {
      case FilterType.category:
        // SMART: When removing a category, also remove its subcategories
        final newCategoryIds = selectedCategoryIds.where((id) => id != value).toList();
        var newSubcategoryIds = selectedSubcategoryIds;

        if (relatedSubcategoryIds != null && relatedSubcategoryIds.isNotEmpty) {
          newSubcategoryIds = selectedSubcategoryIds
              .where((subId) => !relatedSubcategoryIds.contains(subId))
              .toList();
        }

        return copyWith(
          selectedCategoryIds: newCategoryIds,
          selectedSubcategoryIds: newSubcategoryIds,
        );
      case FilterType.subcategory:
        return copyWith(
          selectedSubcategoryIds: selectedSubcategoryIds.where((id) => id != value).toList(),
        );
      case FilterType.brand:
        return copyWith(
          selectedBrandIds: selectedBrandIds.where((id) => id != value).toList(),
        );
      case FilterType.size:
        return copyWith(
          selectedSizes: selectedSizes.where((s) => s != value).toList(),
        );
      case FilterType.stockStatus:
        return copyWith(stockStatus: StockStatusFilter.all);
      case FilterType.priceRange:
        return copyWith(clearPriceRange: true);
      case FilterType.isActive:
        return copyWith(clearIsActive: true);
    }
  }
}

/// Stock status filter options
enum StockStatusFilter {
  all,
  healthy,    // > 50 units
  low,        // ≤ 50 units
  critical,   // ≤ 10 units
  outOfStock; // 0 units

  String get label {
    switch (this) {
      case StockStatusFilter.all:
        return 'All Stock';
      case StockStatusFilter.healthy:
        return 'Healthy Stock';
      case StockStatusFilter.low:
        return 'Low Stock';
      case StockStatusFilter.critical:
        return 'Critical Stock';
      case StockStatusFilter.outOfStock:
        return 'Out of Stock';
    }
  }

  String get emoji {
    switch (this) {
      case StockStatusFilter.all:
        return '📦';
      case StockStatusFilter.healthy:
        return '✅';
      case StockStatusFilter.low:
        return '⚠️';
      case StockStatusFilter.critical:
        return '🔴';
      case StockStatusFilter.outOfStock:
        return '❌';
    }
  }
}

/// Price range filter
class PriceRange {
  final double min;
  final double max;

  const PriceRange({
    required this.min,
    required this.max,
  });

  @override
  String toString() => '₹${min.toStringAsFixed(0)} - ₹${max.toStringAsFixed(0)}';

  PriceRange copyWith({
    double? min,
    double? max,
  }) {
    return PriceRange(
      min: min ?? this.min,
      max: max ?? this.max,
    );
  }
}

/// Filter type enum for removal
enum FilterType {
  category,
  subcategory,
  brand,
  size,
  stockStatus,
  priceRange,
  isActive,
}

/// Common bottle sizes for filtering
class BottleSizes {
  static const String size180ml = '180ml';
  static const String size350ml = '350ml';
  static const String size375ml = '375ml';
  static const String size500ml = '500ml';
  static const String size750ml = '750ml';
  static const String size1L = '1L';
  static const String size1000ml = '1000ml';

  static const List<String> all = [
    size180ml,
    size350ml,
    size375ml,
    size500ml,
    size750ml,
    size1L,
  ];

  static String getEmoji(String size) {
    final normalized = size.toLowerCase();
    if (normalized.contains('180')) return '🥃';
    if (normalized.contains('350') || normalized.contains('375')) return '🍺';
    if (normalized.contains('500')) return '🍾';
    if (normalized.contains('750')) return '🍷';
    if (normalized.contains('1l') || normalized.contains('1000')) return '🍶';
    return '📦';
  }
}
