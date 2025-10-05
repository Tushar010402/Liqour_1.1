import 'package:flutter/foundation.dart';
import '../../../core/models/api_response.dart';
import '../services/brand_onboarding_service.dart';
import '../models/saas_brand.dart';
import '../widgets/brand_category_tabs.dart';
import '../../../core/utils/logger.dart';

/// Brand Onboarding Provider - State management for brand onboarding
class BrandOnboardingProvider with ChangeNotifier {
  final BrandOnboardingService _brandOnboardingService;

  BrandOnboardingProvider(this._brandOnboardingService);

  // Available SaaS brands
  List<SaasBrand> _availableBrands = [];
  bool _isLoadingBrands = false;
  String? _errorMessage;

  // Selected brands/variants for onboarding
  Set<String> _selectedBrandIds = {};
  Set<String> _selectedVariantIds = {};

  // Brand packages
  List<BrandPackage> _packages = [];
  bool _isLoadingPackages = false;

  // Onboarding state
  bool _isOnboarding = false;
  OnboardingResult? _lastOnboardingResult;

  // Shop selection for multi-shop tenants
  String? _selectedShopId;

  // Filters
  String? _categoryFilter;
  String? _subcategoryFilter;
  String? _searchQuery;

  // Stock quantities per variant (for inline stock entry)
  Map<String, int> _variantStockQuantities = {};

  // Getters
  List<SaasBrand> get availableBrands => _availableBrands;
  bool get isLoadingBrands => _isLoadingBrands;
  String? get errorMessage => _errorMessage;
  Set<String> get selectedBrandIds => _selectedBrandIds;
  Set<String> get selectedVariantIds => _selectedVariantIds;
  List<BrandPackage> get packages => _packages;
  bool get isLoadingPackages => _isLoadingPackages;
  bool get isOnboarding => _isOnboarding;
  OnboardingResult? get lastOnboardingResult => _lastOnboardingResult;
  String? get categoryFilter => _categoryFilter;
  String? get subcategoryFilter => _subcategoryFilter;
  String? get searchQuery => _searchQuery;
  String? get selectedShopId => _selectedShopId;
  Map<String, int> get variantStockQuantities => _variantStockQuantities;

  /// Filtered brands based on search, category, and subcategory
  List<SaasBrand> get filteredBrands {
    var brands = _availableBrands;

    // Apply category filter
    if (_categoryFilter != null && _categoryFilter!.isNotEmpty) {
      brands = brands
          .where((b) =>
              b.categoryName?.toLowerCase() == _categoryFilter!.toLowerCase())
          .toList();
    }

    // Apply subcategory filter
    if (_subcategoryFilter != null && _subcategoryFilter!.isNotEmpty) {
      brands = brands
          .where((b) =>
              b.subcategoryName?.toLowerCase() ==
              _subcategoryFilter!.toLowerCase())
          .toList();
    }

    // Apply search filter
    if (_searchQuery != null && _searchQuery!.isNotEmpty) {
      final query = _searchQuery!.toLowerCase();
      brands = brands
          .where((b) =>
              b.name.toLowerCase().contains(query) ||
              b.description.toLowerCase().contains(query))
          .toList();
    }

    return brands;
  }

  /// Get unique categories from available brands
  List<String> get availableCategories {
    final categories = _availableBrands
        .where((b) => b.categoryName != null)
        .map((b) => b.categoryName!)
        .toSet()
        .toList();
    categories.sort();
    return categories;
  }

  /// Total selected variants count
  int get selectedVariantsCount => _selectedVariantIds.length;

  /// Check if brand is selected (all variants selected)
  bool isBrandSelected(String brandId) {
    final brand = _availableBrands.firstWhere((b) => b.id == brandId);
    return brand.variants.every((v) => _selectedVariantIds.contains(v.id));
  }

  /// Check if variant is selected
  bool isVariantSelected(String variantId) {
    return _selectedVariantIds.contains(variantId);
  }

  /// Load available SaaS brands
  Future<void> loadAvailableBrands() async {
    _isLoadingBrands = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _brandOnboardingService.getAvailableBrands();

      if (response.success && response.data != null) {
        _availableBrands = response.data!;
        _errorMessage = null;

        // ✅ FIX: Clear old selections when loading new brands
        // This prevents stale variant IDs from previous sessions
        Logger.debug('🧹 Clearing old variant selections on brand reload');
        _selectedVariantIds.clear();
        _selectedBrandIds.clear();
      } else {
        _errorMessage = response.message ?? 'Failed to load brands';
        _availableBrands = [];
      }
    } catch (e) {
      Logger.debug('❌ BrandOnboardingProvider: Error loading brands - $e');
      _errorMessage = 'Error loading brands: $e';
      _availableBrands = [];
    } finally {
      _isLoadingBrands = false;
      notifyListeners();
    }
  }

  /// Load brand packages
  Future<void> loadBrandPackages() async {
    _isLoadingPackages = true;
    notifyListeners();

    try {
      final response = await _brandOnboardingService.getBrandPackages();

      if (response.success && response.data != null) {
        _packages = response.data!;
      } else {
        Logger.debug('❌ Failed to load packages: ${response.message}');
        _packages = [];
      }
    } catch (e) {
      Logger.debug('❌ BrandOnboardingProvider: Error loading packages - $e');
      _packages = [];
    } finally {
      _isLoadingPackages = false;
      notifyListeners();
    }
  }

  /// Toggle brand selection (select/deselect all variants)
  void toggleBrand(String brandId) {
    final brand = _availableBrands.firstWhere((b) => b.id == brandId);
    final allSelected = brand.variants.every((v) => _selectedVariantIds.contains(v.id));

    if (allSelected) {
      // Deselect all variants
      for (var variant in brand.variants) {
        _selectedVariantIds.remove(variant.id);
      }
      _selectedBrandIds.remove(brandId);
    } else {
      // Select all variants
      for (var variant in brand.variants) {
        _selectedVariantIds.add(variant.id);
      }
      _selectedBrandIds.add(brandId);
    }

    notifyListeners();
  }

  /// Toggle variant selection
  void toggleVariant(String brandId, String variantId) {
    if (_selectedVariantIds.contains(variantId)) {
      _selectedVariantIds.remove(variantId);
    } else {
      _selectedVariantIds.add(variantId);
      _selectedBrandIds.add(brandId);
    }

    // Update brand selection status
    final brand = _availableBrands.firstWhere((b) => b.id == brandId);
    final allSelected = brand.variants.every((v) => _selectedVariantIds.contains(v.id));

    if (allSelected) {
      _selectedBrandIds.add(brandId);
    } else {
      _selectedBrandIds.remove(brandId);
    }

    notifyListeners();
  }

  /// Select package (all brands in package)
  void selectPackage(BrandPackage package) {
    for (var brandId in package.brandIds) {
      final brand = _availableBrands.firstWhere(
        (b) => b.id == brandId,
        orElse: () => _availableBrands.first,
      );

      if (brand.id == brandId) {
        _selectedBrandIds.add(brandId);
        for (var variant in brand.variants) {
          _selectedVariantIds.add(variant.id);
        }
      }
    }
    notifyListeners();
  }

  /// Clear selection
  void clearSelection() {
    _selectedBrandIds.clear();
    _selectedVariantIds.clear();
    notifyListeners();
  }

  /// Apply category and subcategory filter
  void applyFilter({String? categoryId, String? subcategoryId}) {
    _categoryFilter = categoryId;
    _subcategoryFilter = subcategoryId;
    notifyListeners();
  }

  /// Apply category filter
  void applyCategoryFilter(String? category) {
    _categoryFilter = category;
    _subcategoryFilter = null; // Reset subcategory when category changes
    notifyListeners();
  }

  /// Apply subcategory filter
  void applySubcategoryFilter(String? subcategory) {
    _subcategoryFilter = subcategory;
    notifyListeners();
  }

  /// Apply search filter
  void applySearch(String query) {
    _searchQuery = query.isEmpty ? null : query;
    notifyListeners();
  }

  /// Set selected shop for onboarding
  void selectShop(String? shopId) {
    _selectedShopId = shopId;
    notifyListeners();
  }

  /// Set stock quantity for a variant
  void setVariantStock(String variantId, int quantity) {
    if (quantity > 0) {
      _variantStockQuantities[variantId] = quantity;
    } else {
      _variantStockQuantities.remove(variantId);
    }
    notifyListeners();
  }

  /// Get stock quantity for a variant
  int getVariantStock(String variantId) {
    return _variantStockQuantities[variantId] ?? 0;
  }

  /// Get category groups for hierarchical navigation
  List<CategoryGroup> getCategoryGroups() {
    final Map<String, Map<String, List<SaasBrand>>> categoryMap = {};

    // Group brands by category and subcategory
    for (var brand in _availableBrands) {
      final categoryName = brand.categoryName ?? 'Uncategorized';
      final subcategoryName = brand.subcategoryName ?? '';

      categoryMap.putIfAbsent(categoryName, () => {});
      categoryMap[categoryName]!.putIfAbsent(subcategoryName, () => []);
      categoryMap[categoryName]![subcategoryName]!.add(brand);
    }

    // Convert to CategoryGroup objects
    final groups = <CategoryGroup>[];
    categoryMap.forEach((categoryName, subcategories) {
      final subcategoryItems = <SubcategoryItem>[];

      subcategories.forEach((subcategoryName, brands) {
        if (subcategoryName.isNotEmpty) {
          subcategoryItems.add(SubcategoryItem(
            id: subcategoryName,
            name: subcategoryName,
            brandCount: brands.length,
          ));
        }
      });

      // Calculate total brand count for category
      final totalBrands =
          subcategories.values.fold(0, (sum, brands) => sum + brands.length);

      groups.add(CategoryGroup(
        id: categoryName,
        name: categoryName,
        subcategories: subcategoryItems,
        brandCount: totalBrands,
      ));
    });

    return groups;
  }

  /// Onboard selected brands
  Future<bool> onboardSelectedBrands({String? shopId}) async {
    // Use provided shopId or fall back to selected shop
    final targetShopId = shopId ?? _selectedShopId;
    if (_selectedVariantIds.isEmpty) {
      _errorMessage = 'Please select at least one product variant';
      notifyListeners();
      return false;
    }

    _isOnboarding = true;
    _errorMessage = null;
    _lastOnboardingResult = null;
    notifyListeners();

    try {
      final response = await _brandOnboardingService.onboardBrands(
        brandIds: _selectedBrandIds.toList(),
        variantIds: _selectedVariantIds.toList(),
        shopId: targetShopId,
      );

      if (response.success && response.data != null) {
        _lastOnboardingResult = response.data;
        _errorMessage = null;

        // Clear selection after successful onboarding
        clearSelection();

        return true;
      } else {
        _errorMessage = response.message ?? 'Failed to onboard brands';
        return false;
      }
    } catch (e) {
      Logger.debug('❌ BrandOnboardingProvider: Error onboarding brands - $e');
      _errorMessage = 'Error onboarding brands: $e';
      return false;
    } finally {
      _isOnboarding = false;
      notifyListeners();
    }
  }

  /// Initialize provider
  Future<void> initialize() async {
    await Future.wait([
      loadAvailableBrands(),
      loadBrandPackages(),
    ]);
  }
}
