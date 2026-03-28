import 'package:flutter/foundation.dart';
import '../models/saas_brand.dart';

/// Provider for managing brand and variant selection state during onboarding
/// Implements a shopping cart-like pattern for selecting brands
class BrandSelectionProvider extends ChangeNotifier {
  // Map<brandId, Set<variantIds>>
  final Map<String, Set<String>> _selectedVariants = {};

  // Cache of all available brands (loaded once)
  List<SaasBrand> _allBrands = [];

  // Filter state
  String? _selectedCategoryId;
  String _searchQuery = '';

  /// Get all available brands
  List<SaasBrand> get allBrands => _allBrands;

  /// Set all available brands (from API)
  void setAllBrands(List<SaasBrand> brands) {
    _allBrands = brands;
    notifyListeners();
  }

  /// Get selected category ID
  String? get selectedCategoryId => _selectedCategoryId;

  /// Set selected category for filtering
  void setCategory(String? categoryId) {
    _selectedCategoryId = categoryId;
    notifyListeners();
  }

  /// Get search query
  String get searchQuery => _searchQuery;

  /// Set search query for filtering
  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  /// Get filtered brands based on category and search
  List<SaasBrand> getFilteredBrands() {
    List<SaasBrand> filtered = _allBrands;

    // Filter by category
    if (_selectedCategoryId != null) {
      filtered = filtered.where((brand) => brand.categoryNameFromVariant == _selectedCategoryId).toList();
    }

    // Filter by search query
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((brand) {
        return brand.name.toLowerCase().contains(query) ||
               brand.description.toLowerCase().contains(query);
      }).toList();
    }

    return filtered;
  }

  /// Check if a brand is selected (all variants or some variants)
  bool isBrandSelected(String brandId) {
    return _selectedVariants.containsKey(brandId) &&
           _selectedVariants[brandId]!.isNotEmpty;
  }

  /// Check if a specific variant is selected
  bool isVariantSelected(String brandId, String variantId) {
    return _selectedVariants.containsKey(brandId) &&
           _selectedVariants[brandId]!.contains(variantId);
  }

  /// Get selected variants for a brand
  Set<String> getSelectedVariants(String brandId) {
    return _selectedVariants[brandId] ?? {};
  }

  /// Get count of selected variants for a brand
  int getSelectedVariantCount(String brandId) {
    return _selectedVariants[brandId]?.length ?? 0;
  }

  /// Get selected variant IDs for a brand
  Set<String> getSelectedVariantIds(String brandId) {
    return _selectedVariants[brandId] ?? {};
  }

  /// Toggle entire brand (all variants)
  void toggleBrand(String brandId, List<SaasBrandVariant> allVariants) {
    if (isBrandSelected(brandId)) {
      // Deselect all variants
      _selectedVariants.remove(brandId);
    } else {
      // Select all variants
      _selectedVariants[brandId] = allVariants.map((v) => v.id).toSet();
    }
    notifyListeners();
  }

  /// Toggle a single variant
  void toggleVariant(String brandId, String variantId) {
    if (!_selectedVariants.containsKey(brandId)) {
      _selectedVariants[brandId] = {};
    }

    if (_selectedVariants[brandId]!.contains(variantId)) {
      _selectedVariants[brandId]!.remove(variantId);

      // Remove brand if no variants selected
      if (_selectedVariants[brandId]!.isEmpty) {
        _selectedVariants.remove(brandId);
      }
    } else {
      _selectedVariants[brandId]!.add(variantId);
    }

    notifyListeners();
  }

  /// Set specific variants for a brand (replaces existing selection)
  void setVariantsForBrand(String brandId, Set<String> variantIds) {
    if (variantIds.isEmpty) {
      _selectedVariants.remove(brandId);
    } else {
      _selectedVariants[brandId] = Set.from(variantIds);
    }
    notifyListeners();
  }

  /// Get total count of selected variants across all brands
  int get totalSelectedCount {
    return _selectedVariants.values.fold(0, (sum, variants) => sum + variants.length);
  }

  /// Get count of selected brands
  int get selectedBrandCount {
    return _selectedVariants.keys.length;
  }

  /// Get all selected variant IDs (flattened list)
  List<String> getAllSelectedVariantIds() {
    List<String> allIds = [];
    _selectedVariants.forEach((brandId, variantIds) {
      allIds.addAll(variantIds);
    });
    return allIds;
  }

  /// Get brands grouped by category for cart display
  Map<String, List<SaasBrand>> getGroupedByCategory() {
    Map<String, List<SaasBrand>> grouped = {};

    _selectedVariants.forEach((brandId, variantIds) {
      // Find brand
      final brand = _allBrands.firstWhere(
        (b) => b.id == brandId,
        orElse: () => SaasBrand(
          id: brandId,
          name: 'Unknown Brand',
          description: '',
          picture: '',
          isActive: true,
          sortOrder: 0,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          variants: [],
        ),
      );

      final categoryName = brand.categoryNameFromVariant ?? 'Other';
      if (!grouped.containsKey(categoryName)) {
        grouped[categoryName] = [];
      }
      if (!grouped[categoryName]!.any((b) => b.id == brand.id)) {
        grouped[categoryName]!.add(brand);
      }
    });

    return grouped;
  }

  /// Get breakdown by category
  Map<String, int> getBreakdownByCategory() {
    Map<String, int> breakdown = {};

    _selectedVariants.forEach((brandId, variantIds) {
      // Find brand
      final brand = _allBrands.firstWhere(
        (b) => b.id == brandId,
        orElse: () => SaasBrand(
          id: brandId,
          name: '',
          description: '',
          picture: '',
          isActive: true,
          sortOrder: 0,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          variants: [],
        ),
      );

      final categoryName = brand.categoryNameFromVariant ?? 'Other';
      breakdown[categoryName] = (breakdown[categoryName] ?? 0) + variantIds.length;
    });

    return breakdown;
  }

  /// Get selected products for cart display
  List<SelectedProduct> getSelectedProducts() {
    List<SelectedProduct> products = [];

    _selectedVariants.forEach((brandId, variantIds) {
      // Find brand
      final brand = _allBrands.firstWhere(
        (b) => b.id == brandId,
        orElse: () => SaasBrand(
          id: brandId,
          name: 'Unknown Brand',
          description: '',
          picture: '',
          isActive: true,
          sortOrder: 0,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          variants: [],
        ),
      );

      // Add each selected variant as a product
      for (final variantId in variantIds) {
        final variant = brand.variants.firstWhere(
          (v) => v.id == variantId,
          orElse: () => SaasBrandVariant(
            id: variantId,
            brandId: brandId,
            categoryId: '',
            size: '',
            alcoholContent: 0,
            governmentDuty: 0,
            buyingPrice: 0,
            sellingPrice: 0,
            mrp: 0,
            picture: '',
            barcode: '',
            hsnCode: '',
            isActive: true,
            sortOrder: 0,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );

        products.add(SelectedProduct(
          brandId: brandId,
          brandName: brand.name,
          variantId: variantId,
          variant: variant,
          categoryName: brand.categoryNameFromVariant ?? 'Other',
        ));
      }
    });

    return products;
  }

  /// Remove a specific product from selection
  void removeProduct(String brandId, String variantId) {
    toggleVariant(brandId, variantId);
  }

  /// Clear all selections
  void clearAll() {
    _selectedVariants.clear();
    notifyListeners();
  }

  /// Clear selections for a specific category
  void clearCategory(String categoryName) {
    List<String> brandsToRemove = [];

    _selectedVariants.forEach((brandId, variantIds) {
      final brand = _allBrands.firstWhere(
        (b) => b.id == brandId,
        orElse: () => SaasBrand(
          id: brandId,
          name: '',
          description: '',
          picture: '',
          isActive: true,
          sortOrder: 0,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          variants: [],
        ),
      );

      if (brand.categoryNameFromVariant == categoryName) {
        brandsToRemove.add(brandId);
      }
    });

    for (final brandId in brandsToRemove) {
      _selectedVariants.remove(brandId);
    }

    notifyListeners();
  }

  /// Get request payload for onboarding API
  Map<String, dynamic> getOnboardingPayload() {
    List<String> brandIds = _selectedVariants.keys.toList();
    List<String> variantIds = getAllSelectedVariantIds();

    return {
      'brand_ids': brandIds,
      'variant_ids': variantIds,
    };
  }
}

/// Represents a selected product for display in cart
class SelectedProduct {
  final String brandId;
  final String brandName;
  final String variantId;
  final SaasBrandVariant variant;
  final String categoryName;

  SelectedProduct({
    required this.brandId,
    required this.brandName,
    required this.variantId,
    required this.variant,
    required this.categoryName,
  });

  String get displayName => '$brandName ${variant.size}';
  double get mrp => variant.mrp;
  double get sellingPrice => variant.sellingPrice;
  String get size => variant.size;
}
