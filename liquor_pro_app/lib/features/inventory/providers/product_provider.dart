import 'package:flutter/foundation.dart';
import '../../../core/models/api_response.dart';
import '../services/product_service.dart';
import '../models/product.dart' as models;
import '../models/brand.dart';
import '../../../core/utils/logger.dart';

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

  // Filters
  String? _searchQuery;
  String? _selectedCategoryId;
  String? _selectedBrandId;
  bool? _isActiveFilter;
  String? _stockFilter; // 'all', 'low_stock', 'out_of_stock'

  // Categories and Brands
  List<models.Category> _categories = [];
  List<Brand> _brands = [];
  bool _isCategoriesLoading = false;
  bool _isBrandsLoading = false;

  // Stock levels
  Map<String, models.Stock> _stockByProductId = {};

  // Getters
  List<models.Product> get products => _products;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int get currentPage => _currentPage;
  int get totalPages => _totalPages;
  bool get hasMore => _hasMore;
  String? get searchQuery => _searchQuery;
  String? get selectedCategoryId => _selectedCategoryId;
  String? get selectedBrandId => _selectedBrandId;
  String? get stockFilter => _stockFilter;

  List<models.Category> get categories => _categories;
  List<Brand> get brands => _brands;
  bool get isCategoriesLoading => _isCategoriesLoading;
  bool get isBrandsLoading => _isBrandsLoading;

  Map<String, models.Stock> get stockByProductId => _stockByProductId;

  /// Load products with filters and pagination
  Future<void> loadProducts({
    String? search,
    String? categoryId,
    String? brandId,
    bool? isActive,
    int page = 1,
    bool append = false,
  }) async {
    Logger.debug('\n🔵 ProductProvider.loadProducts() - START');
    Logger.debug('   📌 Parameters:');
    Logger.debug('      - search: $search');
    Logger.debug('      - categoryId: $categoryId');
    Logger.debug('      - brandId: $brandId');
    Logger.debug('      - isActive: $isActive');
    Logger.debug('      - page: $page');
    Logger.debug('      - append: $append');

    if (!append) {
      Logger.debug('   🔄 Setting loading state...');
      _isLoading = true;
      _errorMessage = null;
      _products = [];
    }
    notifyListeners();

    try {
      // Update filters
      Logger.debug('   📝 Updating filters...');
      _searchQuery = search;
      _selectedCategoryId = categoryId;
      _selectedBrandId = brandId;
      _isActiveFilter = isActive;
      _currentPage = page;
      Logger.debug('   ✅ Filters updated');

      Logger.debug('   🌐 Calling ProductService.getProducts()...');
      final response = await _productService.getProducts(
        search: search,
        categoryId: categoryId,
        brandId: brandId,
        isActive: isActive,
        page: page,
        limit: 20,
      );

      Logger.debug('   📦 Response received:');
      Logger.debug('      - success: ${response.success}');
      Logger.debug('      - message: ${response.message}');
      Logger.debug('      - data: ${response.data != null ? "present" : "null"}');

      if (response.success && response.data != null) {
        final productsCount = response.data!.products.length;
        Logger.debug('   ✅ Success! Products loaded: $productsCount');

        if (append) {
          _products.addAll(response.data!.products);
          Logger.debug('   📥 Appended $productsCount products. Total: ${_products.length}');
        } else {
          _products = response.data!.products;
          Logger.debug('   📥 Set ${_products.length} products');
        }

        _totalPages = response.data!.totalPages;
        _hasMore = response.data!.hasMore;
        _errorMessage = null;

        Logger.debug('   📊 Pagination info:');
        Logger.debug('      - totalPages: $_totalPages');
        Logger.debug('      - hasMore: $_hasMore');
        Logger.debug('      - currentPage: $_currentPage');
      } else {
        _errorMessage = response.message ?? 'Failed to load products';
        Logger.debug('   ❌ Failed: $_errorMessage');
        if (!append) {
          _products = [];
        }
      }
    } catch (e, stackTrace) {
      Logger.debug('   ❌ EXCEPTION in loadProducts:');
      Logger.debug('      Error: $e');
      Logger.debug('      StackTrace: $stackTrace');
      _errorMessage = 'Error loading products: $e';
      if (!append) {
        _products = [];
      }
    } finally {
      _isLoading = false;
      notifyListeners();
      Logger.debug('   🏁 loadProducts() completed');
      Logger.debug('   📊 Final state:');
      Logger.debug('      - products count: ${_products.length}');
      Logger.debug('      - isLoading: $_isLoading');
      Logger.debug('      - errorMessage: $_errorMessage');
      Logger.debug('🔵 ProductProvider.loadProducts() - END\n');
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
      );
    }
  }

  /// Refresh products (pull-to-refresh)
  Future<void> refreshProducts() async {
    await loadProducts(
      search: _searchQuery,
      categoryId: _selectedCategoryId,
      brandId: _selectedBrandId,
      isActive: _isActiveFilter,
      page: 1,
    );
  }

  /// Load categories
  Future<void> loadCategories() async {
    Logger.debug('\n🟢 ProductProvider.loadCategories() - START');
    _isCategoriesLoading = true;
    notifyListeners();

    try {
      Logger.debug('   🌐 Calling ProductService.getCategories()...');
      final response = await _productService.getCategories();

      Logger.debug('   📦 Response received:');
      Logger.debug('      - success: ${response.success}');
      Logger.debug('      - message: ${response.message}');
      Logger.debug('      - data: ${response.data != null ? "present" : "null"}');

      if (response.success && response.data != null) {
        _categories = response.data!;
        Logger.debug('   ✅ Categories loaded: ${_categories.length}');
        for (var cat in _categories) {
          Logger.debug('      - ${cat.id}: ${cat.name}');
        }
      } else {
        Logger.debug('   ❌ Failed to load categories: ${response.message}');
        _categories = [];
      }
    } catch (e, stackTrace) {
      Logger.debug('   ❌ EXCEPTION in loadCategories:');
      Logger.debug('      Error: $e');
      Logger.debug('      StackTrace: $stackTrace');
      _categories = [];
    } finally {
      _isCategoriesLoading = false;
      notifyListeners();
      Logger.debug('   🏁 loadCategories() completed - ${_categories.length} categories');
      Logger.debug('🟢 ProductProvider.loadCategories() - END\n');
    }
  }

  /// Load brands
  Future<void> loadBrands() async {
    Logger.debug('\n🟡 ProductProvider.loadBrands() - START');
    _isBrandsLoading = true;
    notifyListeners();

    try {
      Logger.debug('   🌐 Calling ProductService.getBrands()...');
      final response = await _productService.getBrands();

      Logger.debug('   📦 Response received:');
      Logger.debug('      - success: ${response.success}');
      Logger.debug('      - message: ${response.message}');
      Logger.debug('      - data: ${response.data != null ? "present" : "null"}');

      if (response.success && response.data != null) {
        _brands = response.data!;
        Logger.debug('   ✅ Brands loaded: ${_brands.length}');
        for (var brand in _brands) {
          Logger.debug('      - ${brand.id}: ${brand.name}');
        }
      } else {
        Logger.debug('   ❌ Failed to load brands: ${response.message}');
        _brands = [];
      }
    } catch (e, stackTrace) {
      Logger.debug('   ❌ EXCEPTION in loadBrands:');
      Logger.debug('      Error: $e');
      Logger.debug('      StackTrace: $stackTrace');
      _brands = [];
    } finally {
      _isBrandsLoading = false;
      notifyListeners();
      Logger.debug('   🏁 loadBrands() completed - ${_brands.length} brands');
      Logger.debug('🟡 ProductProvider.loadBrands() - END\n');
    }
  }

  /// Load stock levels
  Future<void> loadStock({String? shopId}) async {
    try {
      final response = await _productService.getStock(shopId: shopId);

      if (response.success && response.data != null) {
        _stockByProductId = {
          for (var stock in response.data!) stock.productId: stock
        };
        notifyListeners();
      }
    } catch (e) {
      Logger.debug('❌ ProductProvider: Error loading stock - $e');
    }
  }

  /// Get stock for a product
  models.Stock? getStockForProduct(String productId) {
    return _stockByProductId[productId];
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
      Logger.debug('❌ ProductProvider: Error creating category - $e');
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
      Logger.debug('❌ ProductProvider: Error updating category - $e');
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
      Logger.debug('❌ ProductProvider: Error deleting category - $e');
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
      Logger.debug('❌ ProductProvider: Error creating brand - $e');
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
      Logger.debug('❌ ProductProvider: Error updating brand - $e');
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
      Logger.debug('❌ ProductProvider: Error deleting brand - $e');
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
    required double mrp,
  }) async {
    Logger.debug('\n🟣 ProductProvider.createProduct() - START');
    Logger.debug('   📌 Product data:');
    Logger.debug('      - name: $name');
    Logger.debug('      - categoryId: $categoryId');
    Logger.debug('      - brandId: $brandId');
    Logger.debug('      - size: $size');
    Logger.debug('      - alcoholContent: $alcoholContent');
    Logger.debug('      - barcode: $barcode');
    Logger.debug('      - sku: $sku');
    Logger.debug('      - costPrice: $costPrice');
    Logger.debug('      - sellingPrice: $sellingPrice');
    Logger.debug('      - mrp: $mrp');

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      Logger.debug('   🌐 Calling ProductService.createProduct()...');
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
        mrp: mrp,
      );

      Logger.debug('   📦 Response received:');
      Logger.debug('      - success: ${response.success}');
      Logger.debug('      - message: ${response.message}');
      Logger.debug('      - data: ${response.data != null ? "present" : "null"}');

      if (response.success && response.data != null) {
        Logger.debug('   ✅ Product created successfully: ${response.data!.id}');
        Logger.debug('   🔄 Refreshing product list...');
        await refreshProducts();
        Logger.debug('🟣 ProductProvider.createProduct() - END (SUCCESS)\n');
        return true;
      } else {
        _errorMessage = response.message ?? 'Failed to create product';
        Logger.debug('   ❌ Failed to create product: $_errorMessage');
        Logger.debug('🟣 ProductProvider.createProduct() - END (FAILED)\n');
        return false;
      }
    } catch (e, stackTrace) {
      Logger.debug('   ❌ EXCEPTION in createProduct:');
      Logger.debug('      Error: $e');
      Logger.debug('      StackTrace: $stackTrace');
      _errorMessage = 'Error creating product: $e';
      Logger.debug('🟣 ProductProvider.createProduct() - END (EXCEPTION)\n');
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
    required double mrp,
  }) async {
    Logger.debug('\n🔵 ProductProvider.updateProduct() - START');
    Logger.debug('   📌 Update data:');
    Logger.debug('      - id: $id');
    Logger.debug('      - name: $name');
    Logger.debug('      - categoryId: $categoryId');
    Logger.debug('      - brandId: $brandId');

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      Logger.debug('   🌐 Calling ProductService.updateProduct()...');
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
        mrp: mrp,
      );

      Logger.debug('   📦 Response received:');
      Logger.debug('      - success: ${response.success}');
      Logger.debug('      - message: ${response.message}');

      if (response.success && response.data != null) {
        // Update the product in the list
        final index = _products.indexWhere((p) => p.id == id);
        Logger.debug('   🔍 Finding product in list... index: $index');
        if (index != -1) {
          _products[index] = response.data!;
          Logger.debug('   ✅ Product updated in list at index $index');
          notifyListeners();
        }
        Logger.debug('🔵 ProductProvider.updateProduct() - END (SUCCESS)\n');
        return true;
      } else {
        _errorMessage = response.message ?? 'Failed to update product';
        Logger.debug('   ❌ Failed to update product: $_errorMessage');
        Logger.debug('🔵 ProductProvider.updateProduct() - END (FAILED)\n');
        return false;
      }
    } catch (e, stackTrace) {
      Logger.debug('   ❌ EXCEPTION in updateProduct:');
      Logger.debug('      Error: $e');
      Logger.debug('      StackTrace: $stackTrace');
      _errorMessage = 'Error updating product: $e';
      Logger.debug('🔵 ProductProvider.updateProduct() - END (EXCEPTION)\n');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Delete product
  Future<bool> deleteProduct(String id) async {
    Logger.debug('\n🔴 ProductProvider.deleteProduct() - START');
    Logger.debug('   📌 Deleting product ID: $id');

    try {
      Logger.debug('   🌐 Calling ProductService.deleteProduct()...');
      final response = await _productService.deleteProduct(id);

      Logger.debug('   📦 Response received:');
      Logger.debug('      - success: ${response.success}');
      Logger.debug('      - message: ${response.message}');

      if (response.success) {
        final beforeCount = _products.length;
        _products.removeWhere((p) => p.id == id);
        final afterCount = _products.length;
        Logger.debug('   ✅ Product deleted from list');
        Logger.debug('      - before: $beforeCount products');
        Logger.debug('      - after: $afterCount products');
        notifyListeners();
        Logger.debug('🔴 ProductProvider.deleteProduct() - END (SUCCESS)\n');
        return true;
      }
      Logger.debug('   ❌ Failed to delete product');
      Logger.debug('🔴 ProductProvider.deleteProduct() - END (FAILED)\n');
      return false;
    } catch (e, stackTrace) {
      Logger.debug('   ❌ EXCEPTION in deleteProduct:');
      Logger.debug('      Error: $e');
      Logger.debug('      StackTrace: $stackTrace');
      Logger.debug('🔴 ProductProvider.deleteProduct() - END (EXCEPTION)\n');
      return false;
    }
  }
}
