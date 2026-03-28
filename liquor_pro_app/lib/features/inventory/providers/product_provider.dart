import 'package:flutter/foundation.dart';
import '../services/product_service.dart';
import '../models/product.dart' as models;
import '../models/product_with_stock.dart';
import '../models/brand.dart';
import '../../../core/utils/logger.dart';

/// Default page size for product pagination
/// Optimized for mobile scroll performance - matches backend pagination
const int kProductPageSize = 30;

/// Product Provider - State management for inventory products
class ProductProvider with ChangeNotifier {
  final ProductService _productService;

  ProductProvider(this._productService);

  // Products state
  List<models.Product> _products = [];
  bool _isLoading = false;
  String? _errorMessage;
  int _currentPage = 1;
  int _totalPages = 1;
  bool _hasMore = false;
  bool _hasInitializedProducts = false; // Track if products have been loaded at least once

  // Filters
  String? _searchQuery;
  String? _selectedCategoryId;
  String? _selectedCategoryName; // Store category name for UI display
  final List<String> _selectedCategoryIds = []; // Multiple category IDs for combined filters (e.g., English)
  String? _selectedBrandId;
  bool? _isActiveFilter;
  String? _stockFilter; // 'all', 'low_stock', 'out_of_stock'
  String? _selectedSize; // Size filter (e.g., "90ML", "180ML", "375ML")

  // Categories and Brands
  List<models.Category> _categories = [];
  List<Brand> _brands = [];
  bool _isCategoriesLoading = false;
  bool _isBrandsLoading = false;

  // Available sizes with product counts (dynamic from backend)
  // Industrial Best Practice: Stores SizeWithCount for displaying count badges on filter chips
  List<models.SizeWithCount> _availableSizesWithCounts = [];
  bool _isSizesLoading = false;

  // Stock levels
  Map<String, models.Stock> _stockByProductId = {};

  // Track last used shopId for refreshing
  String? _lastUsedShopId;

  // Getters
  List<models.Product> get products => _products;
  bool get isLoading => _isLoading;
  bool get hasInitializedProducts => _hasInitializedProducts; // True after first load attempt
  String? get errorMessage => _errorMessage;
  int get currentPage => _currentPage;
  int get totalPages => _totalPages;
  bool get hasMore => _hasMore;
  String? get searchQuery => _searchQuery;
  String? get selectedCategoryId => _selectedCategoryId;
  String? get selectedCategoryName => _selectedCategoryName;
  String? get selectedBrandId => _selectedBrandId;
  String? get stockFilter => _stockFilter;

  List<models.Category> get categories => _categories;
  List<Brand> get brands => _brands;
  bool get isCategoriesLoading => _isCategoriesLoading;
  bool get isBrandsLoading => _isBrandsLoading;

  // Available sizes with counts (dynamic from backend)
  List<models.SizeWithCount> get availableSizesWithCounts => _availableSizesWithCounts;
  // Legacy: Returns just size strings for backward compatibility
  List<String> get availableSizes => _availableSizesWithCounts.map((s) => s.size).toList();
  bool get isSizesLoading => _isSizesLoading;
  String? get selectedSize => _selectedSize;

  Map<String, models.Stock> get stockByProductId => _stockByProductId;

  /// Get products with stock combined
  /// Returns list of ProductWithStock for UI display
  List<ProductWithStock> get productsWithStock {
    return ProductWithStock.combineList(
      products: _products,
      stockMap: _stockByProductId,
    );
  }

  /// Load products with filters and pagination
  /// [limit] - Optional custom limit. For Daily Sales Entry, use higher limit (500) to get all products with stock
  /// [size] - Optional size filter (e.g., "90ML", "180ML") - passed to backend for server-side filtering
  /// [categoryIds] - Optional list of category IDs for combined filtering (e.g., English = Whisky + Rum + Vodka)
  Future<void> loadProducts({
    String? search,
    String? categoryId,
    List<String>? categoryIds, // NEW: Support multiple category IDs
    String? brandId,
    bool? isActive,
    int page = 1,
    bool append = false,
    String? shopId,
    int? limit,
    String? size,
  }) async {
    // Use stored filters if not explicitly passed (allows preserving filters across calls)
    // Priority: categoryIds > categoryId > stored
    final effectiveCategoryId = categoryIds != null && categoryIds.isNotEmpty
        ? null // Don't use single categoryId when multiple are provided
        : (categoryId ?? _selectedCategoryId);
    final effectiveCategoryIds = categoryIds ?? _selectedCategoryIds;
    final effectiveSize = size ?? _selectedSize;
    final effectiveSearch = search ?? _searchQuery;
    final effectiveBrandId = brandId ?? _selectedBrandId;

    Logger.debug('🛒 [ProductProvider] loadProducts called with shopId: $shopId, categoryId: $effectiveCategoryId, categoryIds: $effectiveCategoryIds, size: $effectiveSize');

    // ═══════════════════════════════════════════════════════════════════════════
    // CRITICAL FIX: Clear stock cache when shop changes to prevent stale data
    // Stock is SHOP-SPECIFIC - we must clear old shop's stock before loading new
    // ═══════════════════════════════════════════════════════════════════════════
    if (shopId != null && _lastUsedShopId != null && shopId != _lastUsedShopId) {
      Logger.info('🔄 [ProductProvider] Shop changed from $_lastUsedShopId to $shopId - CLEARING STOCK CACHE');
      _stockByProductId.clear();
      // Products are tenant-wide (shared) so we don't clear them
      // But we do clear the initialized flag to force fresh stock load
    }

    // Store shopId for later refresh calls
    if (shopId != null) {
      _lastUsedShopId = shopId;
    }

    // Update stored filters with effective values
    _selectedSize = effectiveSize;
    _selectedCategoryId = effectiveCategoryId;
    _searchQuery = effectiveSearch;
    _selectedBrandId = effectiveBrandId;
    if (isActive != null) _isActiveFilter = isActive;

    if (!append) {
      _isLoading = true;
      _errorMessage = null;
      _products = [];
    }
    notifyListeners();

    try {
      _currentPage = page;

      // Use custom limit if provided (for Daily Sales Entry), otherwise use default page size
      final effectiveLimit = limit ?? kProductPageSize;

      final response = await _productService.getProducts(
        search: effectiveSearch,
        categoryId: effectiveCategoryId,
        categoryIds: effectiveCategoryIds.isNotEmpty ? effectiveCategoryIds : null,
        brandId: effectiveBrandId,
        isActive: isActive,
        page: page,
        limit: effectiveLimit,
        shopId: shopId,
        size: effectiveSize,
      );

      if (response.success && response.data != null) {
        final newProducts = response.data!.products;

        if (append) {
          // Deduplicate: only add products not already in the list
          final existingIds = _products.map((p) => p.id).toSet();
          final uniqueNew = newProducts.where((p) => !existingIds.contains(p.id)).toList();
          _products.addAll(uniqueNew);
          if (uniqueNew.length < newProducts.length) {
            Logger.debug('🛒 [ProductProvider] Deduplicated: ${newProducts.length - uniqueNew.length} duplicates skipped');
          }
        } else {
          _products = newProducts;
        }

        Logger.info('🛒 [ProductProvider] Loaded ${_products.length} products');
        Logger.debug('🛒 [ProductProvider] Pagination: total=${response.data!.total}, page=${response.data!.page}, limit=${response.data!.limit}');

        _totalPages = response.data!.totalPages;

        // CRITICAL: hasMore is true ONLY if this page returned a full page of items
        // If we got less than limit items (including 0), there are no more pages
        final returnedCount = newProducts.length;
        final limit = response.data!.limit;
        _hasMore = returnedCount >= limit;

        Logger.info('🛒 [ProductProvider] hasMore=$_hasMore (returned $returnedCount, limit $limit)');
        _errorMessage = null;

        // Load stock data for all products
        Logger.debug('🛒 [ProductProvider] Now loading stock for shopId: $shopId');
        await loadStock(shopId: shopId);
      } else {
        _errorMessage = response.message ?? 'Failed to load products';
        if (!append) {
          _products = [];
        }
      }
    } catch (e) {
      _errorMessage = 'Error loading products: $e';
      if (!append) {
        _products = [];
      }
    } finally {
      _isLoading = false;
      _hasInitializedProducts = true; // Mark as initialized after first load attempt
      notifyListeners();
    }
  }

  /// Load next page of products
  Future<void> loadMoreProducts() async {
    if (_hasMore && !_isLoading) {
      await loadProducts(
        search: _searchQuery,
        categoryId: _selectedCategoryId,
        brandId: _selectedBrandId,
        isActive: _isActiveFilter,
        page: _currentPage + 1,
        append: true,
        shopId: _lastUsedShopId,
        size: _selectedSize,
      );
    }
  }

  /// Refresh products (pull-to-refresh)
  /// Now properly maintains shop context and size filter for correct loading
  Future<void> refreshProducts({String? shopId, String? size}) async {
    final effectiveShopId = shopId ?? _lastUsedShopId;
    final effectiveSize = size ?? _selectedSize;
    Logger.debug('🔄 [ProductProvider] refreshProducts with shopId: $effectiveShopId, size: $effectiveSize');

    await loadProducts(
      search: _searchQuery,
      categoryId: _selectedCategoryId,
      brandId: _selectedBrandId,
      isActive: _isActiveFilter,
      page: 1,
      shopId: effectiveShopId,
      size: effectiveSize,
    );
  }

  /// Load categories - filtered by shop_id for accuracy (Industrial Best Practice)
  /// Only returns categories that have products with stock in the specified shop
  Future<void> loadCategories({String? shopId}) async {
    _isCategoriesLoading = true;
    notifyListeners();

    try {
      // Use provided shopId or fall back to last used shopId
      final effectiveShopId = shopId ?? _lastUsedShopId;
      final response = await _productService.getCategories(shopId: effectiveShopId);

      if (response.success && response.data != null) {
        _categories = response.data!;
      } else {
        _categories = [];
      }
    } catch (e) {
      _categories = [];
    } finally {
      _isCategoriesLoading = false;
      notifyListeners();
    }
  }

  /// Load brands
  Future<void> loadBrands() async {
    _isBrandsLoading = true;
    notifyListeners();

    try {
      final response = await _productService.getBrands();

      if (response.success && response.data != null) {
        _brands = response.data!;
      } else {
        _brands = [];
      }
    } catch (e) {
      _brands = [];
    } finally {
      _isBrandsLoading = false;
      notifyListeners();
    }
  }

  /// Load available sizes with counts for filtering (dynamic from backend)
  /// Returns distinct sizes with product counts for a given category and/or shop
  /// Industrial Best Practice: Stores SizeWithCount for showing count badges on filter chips
  /// [categoryIds] - List of category IDs for combined filtering (e.g., English = Whisky + Rum + Vodka)
  Future<void> loadAvailableSizes({String? categoryId, List<String>? categoryIds, String? shopId}) async {
    _isSizesLoading = true;
    notifyListeners();

    try {
      final effectiveShopId = shopId ?? _lastUsedShopId;
      Logger.debug('📏 [ProductProvider] Loading available sizes with counts for category: $categoryId, categoryIds: $categoryIds, shop: $effectiveShopId');

      final response = await _productService.getAvailableSizesWithCounts(
        categoryId: categoryId,
        categoryIds: categoryIds,
        shopId: effectiveShopId,
      );

      if (response.success && response.data != null) {
        _availableSizesWithCounts = response.data!;
        Logger.debug('📏 [ProductProvider] Loaded ${_availableSizesWithCounts.length} sizes with counts:');
        for (final sizeWithCount in _availableSizesWithCounts) {
          Logger.debug('   📏 ${sizeWithCount.displayLabel}');
        }
      } else {
        Logger.warning('⚠️ [ProductProvider] Failed to load sizes: ${response.message}');
        _availableSizesWithCounts = [];
      }
    } catch (e) {
      Logger.error('❌ [ProductProvider] Error loading sizes: $e');
      _availableSizesWithCounts = [];
    } finally {
      _isSizesLoading = false;
      notifyListeners();
    }
  }

  /// Clear available sizes
  void clearAvailableSizes() {
    _availableSizesWithCounts = [];
    notifyListeners();
  }

  /// Calculate total stock quantity per size from loaded products
  /// This updates the availableSizesWithCounts with actual stock totals
  /// Called after products are loaded to show stock on size filter chips
  void calculateStockTotalsPerSize() {
    if (_availableSizesWithCounts.isEmpty || _products.isEmpty) return;

    // Calculate stock total for each size
    final stockTotalsBySize = <String, int>{};
    for (final product in _products) {
      final size = product.size.toUpperCase();
      final stock = _stockByProductId[product.id];
      final stockQty = stock?.quantity ?? 0;
      stockTotalsBySize[size] = (stockTotalsBySize[size] ?? 0) + stockQty;
    }

    // Update SizeWithCount objects with stock totals
    _availableSizesWithCounts = _availableSizesWithCounts.map((sizeWithCount) {
      final stockTotal = stockTotalsBySize[sizeWithCount.size] ?? 0;
      return sizeWithCount.copyWithStockQuantity(stockTotal);
    }).toList();

    Logger.debug('📊 [ProductProvider] Stock totals per size: ${_availableSizesWithCounts.map((s) => "${s.size}=${s.totalStockQuantity}").join(", ")}');
    notifyListeners();
  }

  /// Get stock total for a specific size (from current products)
  /// Useful for real-time stock display on size filter chips
  int getStockTotalForSize(String size) {
    final normalizedSize = size.toUpperCase();
    int total = 0;
    for (final product in _products) {
      if (product.size.toUpperCase() == normalizedSize) {
        final stock = _stockByProductId[product.id];
        total += stock?.quantity ?? 0;
      }
    }
    return total;
  }

  // ===== Filter State Setters (for UI to update filters without triggering load) =====

  /// Set selected category (for filter persistence across navigation)
  void setSelectedCategory(String? categoryId, String? categoryName) {
    _selectedCategoryId = categoryId;
    _selectedCategoryName = categoryName;
    Logger.info('🏷️ [ProductProvider] Category filter set: $categoryName ($categoryId)');
    notifyListeners();
  }

  /// Set selected size filter (for filter persistence across navigation)
  void setSelectedSize(String? size) {
    _selectedSize = size;
    Logger.debug('📏 [ProductProvider] Size filter set: $size');
    notifyListeners();
  }

  /// Clear all filters (when changing shop or explicitly requested)
  void clearAllFilters() {
    _searchQuery = null;
    _selectedCategoryId = null;
    _selectedCategoryName = null;
    _selectedBrandId = null;
    _isActiveFilter = null;
    _stockFilter = null;
    _selectedSize = null;
    _availableSizesWithCounts = [];
    Logger.info('🧹 [ProductProvider] All filters cleared');
    notifyListeners();
  }

  /// Load stock levels
  /// CRITICAL: Stock is shop-specific - this replaces all cached stock with new shop's data
  Future<void> loadStock({String? shopId}) async {
    try {
      Logger.debug('🔍 [ProductProvider] Loading stock for shopId: $shopId (current cache: ${_stockByProductId.length} items)');

      // CRITICAL: Clear stock cache before loading new shop's stock
      // This prevents any stale data from previous shop from persisting
      final oldStockCount = _stockByProductId.length;
      _stockByProductId.clear();
      Logger.debug('🧹 [ProductProvider] Cleared $oldStockCount cached stock items before loading new shop');

      final response = await _productService.getStock(shopId: shopId);

      if (response.success && response.data != null) {
        Logger.debug('✅ [ProductProvider] Loaded ${response.data!.length} stock items for shop: $shopId');
        _stockByProductId = {
          for (var stock in response.data!) stock.productId: stock
        };

        // Debug: Log first few stock items to verify shop context
        if (response.data!.isNotEmpty) {
          final firstStock = response.data!.first;
          Logger.debug('   📦 Sample stock - ProductID: ${firstStock.productId}, Quantity: ${firstStock.quantity}, ShopID: ${firstStock.shopId}');
          // Verify shop ID matches
          if (shopId != null && firstStock.shopId != shopId) {
            Logger.warning('   ⚠️ WARNING: Stock shopId (${firstStock.shopId}) does not match requested shopId ($shopId)!');
          }
        }

        // NOTE: Do NOT call calculateStockTotalsPerSize() here!
        // The backend API already returns accurate total_stock in the sizes endpoint.
        // Local calculation would be wrong because products are paginated (only 30 per page).
        // The availableSizesWithCounts already has the correct total_stock from loadAvailableSizes().

        notifyListeners();
      } else {
        Logger.warning('⚠️  [ProductProvider] Failed to load stock: ${response.message}');
      }
    } catch (e) {
      Logger.error('❌ [ProductProvider] Error loading stock: $e');
      // Silent fail - stock loading is optional
    }
  }

  /// Get stock for a product
  models.Stock? getStockForProduct(String productId) {
    return _stockByProductId[productId];
  }

  /// Adjust stock for a product
  /// [quantity] - Absolute value of adjustment amount
  /// [adjustmentType] - 'addition' or 'subtraction'
  Future<bool> adjustStock({
    required String productId,
    required String shopId,
    required int quantity,
    required String adjustmentType,
    String? reason,
  }) async {
    try {
      final response = await _productService.adjustStock(
        productId: productId,
        shopId: shopId,
        quantity: quantity,
        adjustmentType: adjustmentType,
        reason: reason ?? 'Manual adjustment',
      );

      if (response.success) {
        return true;
      } else {
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  /// Apply search filter
  void applySearch(String query) {
    loadProducts(
      search: query.isEmpty ? null : query,
      categoryId: _selectedCategoryId,
      brandId: _selectedBrandId,
      isActive: _isActiveFilter,
      page: 1,
    );
  }

  /// Apply category filter
  void applyCategory(String? categoryId) {
    loadProducts(
      search: _searchQuery,
      categoryId: categoryId,
      brandId: _selectedBrandId,
      isActive: _isActiveFilter,
      page: 1,
    );
  }

  /// Apply brand filter
  void applyBrand(String? brandId) {
    loadProducts(
      search: _searchQuery,
      categoryId: _selectedCategoryId,
      brandId: brandId,
      isActive: _isActiveFilter,
      page: 1,
    );
  }

  /// Apply stock filter
  void applyStockFilter(String? filter) {
    _stockFilter = filter;
    notifyListeners();
  }

  /// Clear all filters
  void clearFilters() {
    _searchQuery = null;
    _selectedCategoryId = null;
    _selectedBrandId = null;
    _isActiveFilter = null;
    _stockFilter = null;
    loadProducts(page: 1);
  }

  /// Get filtered products based on stock status
  List<models.Product> get filteredProducts {
    if (_stockFilter == null || _stockFilter == 'all') {
      return _products;
    }

    return _products.where((product) {
      final stock = getStockForProduct(product.id);
      if (stock == null) return false;

      if (_stockFilter == 'low_stock') {
        return stock.isLowStock && !stock.isOutOfStock;
      } else if (_stockFilter == 'out_of_stock') {
        return stock.isOutOfStock;
      }

      return true;
    }).toList();
  }

  /// Get count of products by stock status
  int get lowStockCount {
    return _products.where((product) {
      final stock = getStockForProduct(product.id);
      return stock != null && stock.isLowStock && !stock.isOutOfStock;
    }).length;
  }

  int get outOfStockCount {
    return _products.where((product) {
      final stock = getStockForProduct(product.id);
      return stock != null && stock.isOutOfStock;
    }).length;
  }

  int get activeProductsCount {
    return _products.where((product) => product.isActive).length;
  }

  /// Get total inventory value
  double get totalInventoryValue {
    double total = 0;
    for (var product in _products) {
      final stock = getStockForProduct(product.id);
      if (stock != null) {
        total += product.costPrice * stock.quantity;
      }
    }
    return total;
  }

  /// Initialize provider - load essential data
  Future<void> initialize() async {
    await Future.wait([
      loadProducts(),
      loadCategories(),
      loadBrands(),
    ]);
  }

  // ===== Category CRUD Operations =====

  /// Create new category
  Future<bool> createCategory({
    required String name,
    String? description,
  }) async {
    try {
      final response = await _productService.createCategory(
        name: name,
        description: description,
      );

      if (response.success && response.data != null) {
        _categories.add(response.data!);
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Update existing category
  Future<bool> updateCategory({
    required String id,
    required String name,
    String? description,
  }) async {
    try {
      final response = await _productService.updateCategory(
        id: id,
        name: name,
        description: description,
      );

      if (response.success && response.data != null) {
        final index = _categories.indexWhere((c) => c.id == id);
        if (index != -1) {
          _categories[index] = response.data!;
          notifyListeners();
        }
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Delete category
  Future<bool> deleteCategory(String id) async {
    try {
      final response = await _productService.deleteCategory(id);

      if (response.success) {
        _categories.removeWhere((c) => c.id == id);
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  // ===== Brand CRUD Operations =====

  /// Create new brand
  Future<bool> createBrand({
    required String name,
    String? description,
  }) async {
    try {
      final response = await _productService.createBrand(
        name: name,
        description: description,
      );

      if (response.success && response.data != null) {
        _brands.add(response.data!);
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Update existing brand
  Future<bool> updateBrand({
    required String id,
    required String name,
    String? description,
  }) async {
    try {
      final response = await _productService.updateBrand(
        id: id,
        name: name,
        description: description,
      );

      if (response.success && response.data != null) {
        final index = _brands.indexWhere((b) => b.id == id);
        if (index != -1) {
          _brands[index] = response.data!;
          notifyListeners();
        }
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Delete brand
  Future<bool> deleteBrand(String id) async {
    try {
      final response = await _productService.deleteBrand(id);

      if (response.success) {
        _brands.removeWhere((b) => b.id == id);
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  // ===== Product CRUD Operations =====

  /// Create new product
  Future<bool> createProduct({
    required String name,
    required String categoryId,
    required String brandId,
    required String size,
    required double alcoholContent,
    required String description,
    required String barcode,
    required String sku,
    required double costPrice,
    required double sellingPrice,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _productService.createProduct(
        name: name,
        categoryId: categoryId,
        brandId: brandId,
        size: size,
        alcoholContent: alcoholContent,
        description: description,
        barcode: barcode,
        sku: sku,
        costPrice: costPrice,
        sellingPrice: sellingPrice,
      );

      if (response.success && response.data != null) {
        await refreshProducts();
        return true;
      } else {
        _errorMessage = response.message ?? 'Failed to create product';
        return false;
      }
    } catch (e) {
      _errorMessage = 'Error creating product: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Update existing product
  Future<bool> updateProduct({
    required String id,
    required String name,
    required String categoryId,
    required String brandId,
    required String size,
    required double alcoholContent,
    required String description,
    required String barcode,
    required String sku,
    required double costPrice,
    required double sellingPrice,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _productService.updateProduct(
        id: id,
        name: name,
        categoryId: categoryId,
        brandId: brandId,
        size: size,
        alcoholContent: alcoholContent,
        description: description,
        barcode: barcode,
        sku: sku,
        costPrice: costPrice,
        sellingPrice: sellingPrice,
      );

      if (response.success && response.data != null) {
        // Update the product in the list
        final index = _products.indexWhere((p) => p.id == id);
        if (index != -1) {
          _products[index] = response.data!;
          notifyListeners();
        }
        return true;
      } else {
        _errorMessage = response.message ?? 'Failed to update product';
        return false;
      }
    } catch (e) {
      _errorMessage = 'Error updating product: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Delete product
  Future<bool> deleteProduct(String id) async {
    try {
      final response = await _productService.deleteProduct(id);

      if (response.success) {
        _products.removeWhere((p) => p.id == id);
        _stockByProductId.remove(id); // Also remove from stock map
        Logger.debug('🗑️ [ProductProvider] Deleted product $id, remaining: ${_products.length}');
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      Logger.error('❌ [ProductProvider] Error deleting product: $e');
      return false;
    }
  }

  /// Reset provider state (called on logout)
  /// Clears all cached data so new user starts fresh
  void reset() {
    _products = [];
    _isLoading = false;
    _hasInitializedProducts = false; // Reset initialization flag on logout
    _errorMessage = null;
    _currentPage = 1;
    _totalPages = 1;
    _hasMore = false;
    _searchQuery = null;
    _selectedCategoryId = null;
    _selectedCategoryName = null;
    _selectedBrandId = null;
    _isActiveFilter = null;
    _stockFilter = null;
    _selectedSize = null;
    _availableSizesWithCounts = [];
    _categories = [];
    _brands = [];
    _isCategoriesLoading = false;
    _isBrandsLoading = false;
    _stockByProductId = {};
    _lastUsedShopId = null;
    notifyListeners();
    Logger.info('🔄 [ProductProvider] State reset for logout');
  }

  /// Update local stock cache after successful API adjustment
  /// This prevents full page refresh and maintains scroll position
  /// Creates new cache entry if product not in cache (fixes missing stock issue)
  void updateLocalStock({
    required String productId,
    required int newQuantity,
    String? shopId,
  }) {
    final effectiveShopId = shopId ?? _lastUsedShopId ?? '';

    if (_stockByProductId.containsKey(productId)) {
      // Update existing cache entry
      _stockByProductId[productId] = _stockByProductId[productId]!.copyWith(
        quantity: newQuantity,
      );
      Logger.info('✅ [ProductProvider] Local stock updated for $productId: $newQuantity');
    } else {
      // Create new cache entry for this product
      // This fixes the issue where stock adjustment doesn't show because product wasn't in cache
      final now = DateTime.now();
      _stockByProductId[productId] = models.Stock(
        id: '', // ID not needed for display
        shopId: effectiveShopId,
        productId: productId,
        quantity: newQuantity,
        reservedQuantity: 0,
        minimumLevel: 0,
        maximumLevel: 0,
        averageCost: 0,
        lastPurchasePrice: 0,
        createdAt: now,
        updatedAt: now,
      );
      Logger.info('✅ [ProductProvider] Created new stock cache entry for $productId: $newQuantity (shop: $effectiveShopId)');
    }
    notifyListeners();
  }

  /// Update product stock directly (for shop stock review screen)
  Future<bool> updateProductStock({
    required String productId,
    required String shopId,
    required int stock,
  }) async {
    try {
      // Calculate adjustment based on current stock
      final currentStock = _stockByProductId[productId];
      final currentQuantity = currentStock?.quantity ?? 0;
      final difference = stock - currentQuantity;

      if (difference == 0) {
        // No change needed
        return true;
      }

      // Use adjustStock method with appropriate type
      final adjustmentType = difference > 0 ? 'addition' : 'subtraction';
      final quantity = difference.abs();

      final response = await _productService.adjustStock(
        productId: productId,
        shopId: shopId,
        quantity: quantity,
        adjustmentType: adjustmentType,
        reason: 'Stock update from review screen',
      );

      if (response.success) {
        // Update local stock cache
        if (_stockByProductId.containsKey(productId)) {
          _stockByProductId[productId] = _stockByProductId[productId]!.copyWith(
            quantity: stock,
          );
        }
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      Logger.error('❌ [ProductProvider] Error updating product stock: $e');
      return false;
    }
  }
}
