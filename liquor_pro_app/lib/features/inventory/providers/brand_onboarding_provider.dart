import 'package:flutter/foundation.dart';
import '../../../core/models/api_response.dart';
import '../services/brand_onboarding_service.dart';
import '../services/product_service.dart';
import '../models/saas_brand.dart';
import '../models/product.dart' as product_models;
import '../widgets/brand_category_tabs.dart';

/// Brand Onboarding Provider - State management for brand onboarding
class BrandOnboardingProvider with ChangeNotifier {
  final BrandOnboardingService _brandOnboardingService;
  final ProductService _productService;

  BrandOnboardingProvider(this._brandOnboardingService, this._productService);

  // Available SaaS brands
  List<SaasBrand> _availableBrands = [];
  bool _isLoadingBrands = false;
  String? _errorMessage;

  // Categories and Subcategories
  List<product_models.Category> _categories = [];
  List<product_models.Subcategory> _subcategories = [];
  bool _isLoadingCategories = false;
  bool _isLoadingSubcategories = false;

  // Selected brands/variants for onboarding
  final Set<String> _selectedBrandIds = {};
  final Set<String> _selectedVariantIds = {};

  // Brand packages
  List<BrandPackage> _packages = [];
  bool _isLoadingPackages = false;

  // Onboarding state
  bool _isOnboarding = false;
  OnboardingResult? _lastOnboardingResult;

  // Filters
  String? _categoryFilter;
  String? _subcategoryFilter;
  String? _searchQuery;
  bool _hideOnboarded = false; // Show all brands by default (including already onboarded)

  // Stock quantities per variant (for inline stock entry)
  final Map<String, int> _variantStockQuantities = {};

  // Getters
  List<SaasBrand> get availableBrands => _availableBrands;
  bool get isLoadingBrands => _isLoadingBrands;
  bool get isLoading => _isLoadingBrands || _isLoadingCategories;
  String? get errorMessage => _errorMessage;
  List<product_models.Category> get categories => _categories;
  List<product_models.Subcategory> get subcategories => _subcategories;
  bool get isLoadingCategories => _isLoadingCategories;
  bool get isLoadingSubcategories => _isLoadingSubcategories;
  Set<String> get selectedBrandIds => _selectedBrandIds;
  Set<String> get selectedVariantIds => _selectedVariantIds;
  List<BrandPackage> get packages => _packages;
  bool get isLoadingPackages => _isLoadingPackages;
  bool get isOnboarding => _isOnboarding;
  OnboardingResult? get lastOnboardingResult => _lastOnboardingResult;
  String? get categoryFilter => _categoryFilter;
  String? get subcategoryFilter => _subcategoryFilter;
  String? get searchQuery => _searchQuery;
  bool get hideOnboarded => _hideOnboarded;
  Map<String, int> get variantStockQuantities => _variantStockQuantities;

  /// Filtered brands based on search, category, subcategory, and onboarded status
  List<SaasBrand> get filteredBrands {
    var brands = _availableBrands;

    // Apply "hide onboarded" filter
    if (_hideOnboarded) {
      brands = brands.where((b) => b.isOnboarded != true).toList();
    }

    // Apply category filter
    if (_categoryFilter != null && _categoryFilter!.isNotEmpty) {
      brands = brands
          .where((b) =>
              b.categoryNameFromVariant?.toLowerCase() == _categoryFilter!.toLowerCase())
          .toList();
    }

    // Apply subcategory filter
    if (_subcategoryFilter != null && _subcategoryFilter!.isNotEmpty) {
      brands = brands
          .where((b) =>
              b.subcategoryNameFromVariant?.toLowerCase() ==
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

  /// Get count of onboarded brands
  int get onboardedBrandsCount {
    return _availableBrands.where((b) => b.isOnboarded == true).length;
  }

  /// Get count of available (not onboarded) brands
  int get availableBrandsCount {
    return _availableBrands.where((b) => b.isOnboarded != true).length;
  }

  /// Get unique categories from available brands
  List<String> get availableCategories {
    final categories = _availableBrands
        .where((b) => b.categoryNameFromVariant != null)
        .map((b) => b.categoryNameFromVariant!)
        .toSet()
        .toList();
    categories.sort();
    return categories;
  }

  /// Total selected variants count
  int get selectedVariantsCount => _selectedVariantIds.length;

  /// Get list of unique brand names that have selected variants
  List<String> get selectedBrandNames {
    final brandNames = <String>[];
    for (var brandId in _selectedBrandIds) {
      final brand = _availableBrands.where((b) => b.id == brandId).firstOrNull;
      if (brand != null) {
        brandNames.add(brand.name);
      }
    }
    return brandNames;
  }

  /// Get count of unique brands with selected variants
  int get selectedBrandsCount => _selectedBrandIds.length;

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

        // Clear old selections when loading new brands
        // This prevents stale variant IDs from previous sessions
        _selectedVariantIds.clear();
        _selectedBrandIds.clear();

        // AUTO-SELECT: Pre-select already onboarded brands
        // This helps users see which brands they've already imported
        for (var brand in _availableBrands) {
          if (brand.isOnboarded == true) {
            // Select the brand
            _selectedBrandIds.add(brand.id);

            // Select all variants of this brand
            for (var variant in brand.variants) {
              _selectedVariantIds.add(variant.id);
            }
          }
        }
      } else {
        _errorMessage = response.message ?? 'Failed to load brands';
        _availableBrands = [];
      }
    } catch (e) {
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
        _packages = [];
      }
    } catch (e) {
      _packages = [];
    } finally {
      _isLoadingPackages = false;
      notifyListeners();
    }
  }

  /// Load categories from product service
  Future<void> loadCategories() async {
    _isLoadingCategories = true;
    notifyListeners();

    try {
      final response = await _productService.getCategories();

      if (response.success && response.data != null) {
        _categories = response.data!;
      } else {
        _categories = [];
      }
    } catch (e) {
      _categories = [];
    } finally {
      _isLoadingCategories = false;
      notifyListeners();
    }
  }

  /// Load subcategories for a specific category
  Future<void> loadSubcategories(String categoryId) async {
    _isLoadingSubcategories = true;
    notifyListeners();

    try {
      final response = await _productService.getSubcategories(categoryId);

      if (response.success && response.data != null) {
        _subcategories = response.data!;
      } else {
        _subcategories = [];
      }
    } catch (e) {
      _subcategories = [];
    } finally {
      _isLoadingSubcategories = false;
      notifyListeners();
    }
  }

  /// Toggle brand selection (select/deselect all variants)
  /// IMPORTANT: Skips already onboarded brands - they cannot be toggled
  void toggleBrand(String brandId) {
    final brand = _availableBrands.firstWhere((b) => b.id == brandId);

    // BLOCK: Already onboarded brands cannot be toggled
    if (brand.isOnboarded == true) {
      return; // Do nothing for onboarded brands
    }

    // Only consider non-onboarded variants for selection
    final nonOnboardedVariants = brand.variants.where((v) => v.isOnboarded != true).toList();
    if (nonOnboardedVariants.isEmpty) {
      return; // All variants are already onboarded
    }

    final allSelected = nonOnboardedVariants.every((v) => _selectedVariantIds.contains(v.id));

    if (allSelected) {
      // Deselect all non-onboarded variants
      for (var variant in nonOnboardedVariants) {
        _selectedVariantIds.remove(variant.id);
      }
      _selectedBrandIds.remove(brandId);
    } else {
      // Select all non-onboarded variants
      for (var variant in nonOnboardedVariants) {
        _selectedVariantIds.add(variant.id);
      }
      _selectedBrandIds.add(brandId);
    }

    notifyListeners();
  }

  /// Alias for toggleBrand - for brand-level selection UI
  void toggleBrandSelection(String brandId) {
    toggleBrand(brandId);
  }

  /// Toggle variant selection
  /// IMPORTANT: Skips already onboarded variants - they cannot be toggled
  void toggleVariant(String brandId, String variantId) {
    // Find the variant and check if it's already onboarded
    final brand = _availableBrands.firstWhere((b) => b.id == brandId);
    final variant = brand.variants.firstWhere((v) => v.id == variantId);

    // BLOCK: Already onboarded variants cannot be toggled
    if (variant.isOnboarded == true) {
      return; // Do nothing for onboarded variants
    }

    if (_selectedVariantIds.contains(variantId)) {
      _selectedVariantIds.remove(variantId);
    } else {
      _selectedVariantIds.add(variantId);
      _selectedBrandIds.add(brandId);
    }

    // Update brand selection status (only consider non-onboarded variants)
    final nonOnboardedVariants = brand.variants.where((v) => v.isOnboarded != true).toList();
    final allSelected = nonOnboardedVariants.isNotEmpty &&
        nonOnboardedVariants.every((v) => _selectedVariantIds.contains(v.id));

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

  /// Toggle hide onboarded brands filter
  void toggleHideOnboarded() {
    _hideOnboarded = !_hideOnboarded;
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
      final categoryName = brand.categoryNameFromVariant ?? 'Uncategorized';
      final subcategoryName = brand.subcategoryNameFromVariant ?? '';

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

  /// Onboard selected brands to tenant with initial stock quantities
  Future<bool> onboardSelectedBrands({String? shopId}) async {
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
        shopId: shopId,
        variantStockQuantities: _variantStockQuantities.isNotEmpty
            ? Map<String, int>.from(_variantStockQuantities)
            : null,
      );

      if (response.success && response.data != null) {
        _lastOnboardingResult = response.data;

        // 🔍 CHECK FOR ACTUAL SUCCESS: Backend may return 206 with errors
        final result = response.data!;
        final hasErrors = result.errors != null && result.errors!.isNotEmpty;
        final noProductsCreated = result.productsCreated == 0;

        // If no products were created OR errors exist, treat as failure
        if (noProductsCreated || hasErrors) {
          print('⚠️ [BrandOnboarding] Partial/failed onboarding detected:');
          print('   Products created: ${result.productsCreated}');
          print('   Brands onboarded: ${result.brandsOnboarded}');
          print('   Has errors: $hasErrors');
          if (hasErrors) {
            print('   Errors: ${result.errors}');
          }

          // Build detailed error message
          final errorMessages = <String>[];
          if (noProductsCreated) {
            errorMessages.add('No products were created from the selected brands.');
          }
          if (hasErrors) {
            errorMessages.addAll(result.errors!);
          }

          _errorMessage = errorMessages.join('\n\n');
          return false;
        }

        // Actual success - products were created
        print('✅ [BrandOnboarding] Success:');
        print('   Products created: ${result.productsCreated}');
        print('   Brands onboarded: ${result.brandsOnboarded}');

        _errorMessage = null;

        // Clear selection and stock quantities after successful onboarding
        clearSelection();
        _variantStockQuantities.clear();

        return true;
      } else {
        _errorMessage = response.message ?? 'Failed to onboard brands';
        return false;
      }
    } catch (e) {
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

  /// Download brand template Excel file
  Future<ApiResponse<String>> downloadBrandTemplate() async {
    return await _brandOnboardingService.downloadBrandTemplate();
  }

  /// Upload brand Excel file for bulk import with shop-specific stock
  Future<ApiResponse<BrandImportResult>> uploadBrandExcel(
    String filePath, {
    String? shopId,
    String? shopName,
  }) async {
    return await _brandOnboardingService.uploadBrandExcel(
      filePath,
      shopId: shopId,
      shopName: shopName,
    );
  }

  /// Reset all state — called on logout to prevent stale data
  void reset() {
    _availableBrands = [];
    _isLoadingBrands = false;
    _errorMessage = null;
    _categories = [];
    _subcategories = [];
    _isLoadingCategories = false;
    _isLoadingSubcategories = false;
    _selectedBrandIds.clear();
    _selectedVariantIds.clear();
    _packages = [];
    _isLoadingPackages = false;
    _isOnboarding = false;
    _lastOnboardingResult = null;
    _categoryFilter = null;
    _subcategoryFilter = null;
    _searchQuery = null;
    _hideOnboarded = false;
    _variantStockQuantities.clear();
    notifyListeners();
  }
}
