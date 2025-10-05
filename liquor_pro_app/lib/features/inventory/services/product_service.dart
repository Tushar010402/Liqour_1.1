import '../../../core/models/api_response.dart';
import '../../../core/services/api_service.dart';
import '../models/product.dart';
import '../models/brand.dart';
import '../../../core/utils/logger.dart';

/// Product Service - API client for product operations
class ProductService {
  final ApiService _apiService;

  ProductService(this._apiService);

  /// Get all products with optional filtering
  /// Supports: search, category_id, brand_id, is_active, page, limit
  Future<ApiResponse<ProductsResponse>> getProducts({
    String? search,
    String? categoryId,
    String? brandId,
    bool? isActive,
    int page = 1,
    int limit = 20,
  }) async {
    Logger.debug('📦 ProductService.getProducts() called');

    // Build query parameters
    final Map<String, dynamic> queryParams = {
      'page': page.toString(),
      'limit': limit.toString(),
    };

    if (search != null && search.isNotEmpty) {
      queryParams['search'] = search;
    }
    if (categoryId != null) {
      queryParams['category_id'] = categoryId;
    }
    if (brandId != null) {
      queryParams['brand_id'] = brandId;
    }
    if (isActive != null) {
      queryParams['is_active'] = isActive.toString();
    }

    final response = await _apiService.get<ProductsResponse>(
      '/api/inventory/products',
      queryParams: queryParams,
      fromJson: (data) {
        Logger.debug('📦 Parsing products response: ${data.runtimeType}');

        // Handle array response
        if (data is List) {
          return ProductsResponse(
            products: data
                .map((json) => Product.fromJson(json as Map<String, dynamic>))
                .toList(),
            total: data.length,
            page: page,
            limit: limit,
          );
        }

        // Handle object response with pagination
        if (data is Map<String, dynamic>) {
          return ProductsResponse(
            products: (data['products'] as List?)
                    ?.map((json) => Product.fromJson(json as Map<String, dynamic>))
                    .toList() ??
                [],
            total: data['total'] ?? 0,
            page: data['page'] ?? page,
            limit: data['limit'] ?? limit,
          );
        }

        return ProductsResponse(products: [], total: 0, page: 1, limit: 20);
      },
    );

    Logger.debug('📦 ProductService: Response received - success: ${response.success}');
    return response;
  }

  /// Get single product by ID
  Future<ApiResponse<Product>> getProduct(String productId) async {
    Logger.debug('📦 ProductService.getProduct($productId) called');

    final response = await _apiService.get<Product>(
      '/api/inventory/products/$productId',
      fromJson: (data) {
        Logger.debug('📦 Parsing product response: ${data.runtimeType}');
        return Product.fromJson(data as Map<String, dynamic>);
      },
    );

    Logger.debug('📦 ProductService: Response received - success: ${response.success}');
    return response;
  }

  /// Get all categories
  Future<ApiResponse<List<Category>>> getCategories() async {
    Logger.debug('📦 ProductService.getCategories() called');

    final response = await _apiService.get<List<Category>>(
      '/api/inventory/categories',
      fromJson: (data) {
        Logger.debug('📦 Parsing categories response: ${data.runtimeType}');

        if (data is List) {
          return data
              .map((json) => Category.fromJson(json as Map<String, dynamic>))
              .toList();
        }

        if (data is Map<String, dynamic> && data['categories'] is List) {
          return (data['categories'] as List)
              .map((json) => Category.fromJson(json as Map<String, dynamic>))
              .toList();
        }

        return [];
      },
    );

    Logger.debug('📦 ProductService: Categories response - success: ${response.success}');
    return response;
  }

  /// Get all brands
  Future<ApiResponse<List<Brand>>> getBrands() async {
    Logger.debug('📦 ProductService.getBrands() called');

    final response = await _apiService.get<List<Brand>>(
      '/api/inventory/brands',
      fromJson: (data) {
        Logger.debug('📦 Parsing brands response: ${data.runtimeType}');

        if (data is List) {
          return data
              .map((json) => Brand.fromJson(json as Map<String, dynamic>))
              .toList();
        }

        if (data is Map<String, dynamic> && data['brands'] is List) {
          return (data['brands'] as List)
              .map((json) => Brand.fromJson(json as Map<String, dynamic>))
              .toList();
        }

        return [];
      },
    );

    Logger.debug('📦 ProductService: Brands response - success: ${response.success}');
    return response;
  }

  /// Get stock levels for products (optional shop filter)
  Future<ApiResponse<List<Stock>>> getStock({String? shopId}) async {
    Logger.debug('📦 ProductService.getStock() called');

    final queryParams = shopId != null ? {'shop_id': shopId} : null;

    final response = await _apiService.get<List<Stock>>(
      '/api/inventory/stock',
      queryParams: queryParams,
      fromJson: (data) {
        Logger.debug('📦 Parsing stock response: ${data.runtimeType}');

        if (data is List) {
          return data
              .map((json) => Stock.fromJson(json as Map<String, dynamic>))
              .toList();
        }

        if (data is Map<String, dynamic> && data['stocks'] is List) {
          return (data['stocks'] as List)
              .map((json) => Stock.fromJson(json as Map<String, dynamic>))
              .toList();
        }

        return [];
      },
    );

    Logger.debug('📦 ProductService: Stock response - success: ${response.success}');
    return response;
  }

  // ===== Category CRUD Operations =====

  /// Create new category
  Future<ApiResponse<Category>> createCategory({
    required String name,
    String? description,
  }) async {
    Logger.debug('📦 ProductService.createCategory() called');

    final response = await _apiService.post<Category>(
      '/api/inventory/categories',
      body: {
        'name': name,
        if (description != null) 'description': description,
      },
      fromJson: (data) => Category.fromJson(data as Map<String, dynamic>),
    );

    Logger.debug('📦 ProductService: Category created - success: ${response.success}');
    return response;
  }

  /// Update existing category
  Future<ApiResponse<Category>> updateCategory({
    required String id,
    required String name,
    String? description,
  }) async {
    Logger.debug('📦 ProductService.updateCategory($id) called');

    final response = await _apiService.put<Category>(
      '/api/inventory/categories/$id',
      body: {
        'name': name,
        if (description != null) 'description': description,
      },
      fromJson: (data) => Category.fromJson(data as Map<String, dynamic>),
    );

    Logger.debug('📦 ProductService: Category updated - success: ${response.success}');
    return response;
  }

  /// Delete category
  Future<ApiResponse<void>> deleteCategory(String id) async {
    Logger.debug('📦 ProductService.deleteCategory($id) called');

    final response = await _apiService.delete<void>(
      '/api/inventory/categories/$id',
      fromJson: (_) => null,
    );

    Logger.debug('📦 ProductService: Category deleted - success: ${response.success}');
    return response;
  }

  // ===== Brand CRUD Operations =====

  /// Create new brand
  Future<ApiResponse<Brand>> createBrand({
    required String name,
    String? description,
  }) async {
    Logger.debug('📦 ProductService.createBrand() called');

    final response = await _apiService.post<Brand>(
      '/api/inventory/brands',
      body: {
        'name': name,
        if (description != null) 'description': description,
      },
      fromJson: (data) => Brand.fromJson(data as Map<String, dynamic>),
    );

    Logger.debug('📦 ProductService: Brand created - success: ${response.success}');
    return response;
  }

  /// Update existing brand
  Future<ApiResponse<Brand>> updateBrand({
    required String id,
    required String name,
    String? description,
  }) async {
    Logger.debug('📦 ProductService.updateBrand($id) called');

    final response = await _apiService.put<Brand>(
      '/api/inventory/brands/$id',
      body: {
        'name': name,
        if (description != null) 'description': description,
      },
      fromJson: (data) => Brand.fromJson(data as Map<String, dynamic>),
    );

    Logger.debug('📦 ProductService: Brand updated - success: ${response.success}');
    return response;
  }

  /// Delete brand
  Future<ApiResponse<void>> deleteBrand(String id) async {
    Logger.debug('📦 ProductService.deleteBrand($id) called');

    final response = await _apiService.delete<void>(
      '/api/inventory/brands/$id',
      fromJson: (_) => null,
    );

    Logger.debug('📦 ProductService: Brand deleted - success: ${response.success}');
    return response;
  }

  // ===== Product CRUD Operations =====

  /// Create new product
  Future<ApiResponse<Product>> createProduct({
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
    Logger.debug('📦 ProductService.createProduct() called');

    final response = await _apiService.post<Product>(
      '/api/inventory/products',
      body: {
        'name': name,
        'category_id': categoryId,
        'brand_id': brandId,
        'size': size,
        'alcohol_content': alcoholContent,
        'description': description,
        'barcode': barcode,
        'sku': sku,
        'cost_price': costPrice,
        'selling_price': sellingPrice,
        'mrp': mrp,
      },
      fromJson: (data) => Product.fromJson(data as Map<String, dynamic>),
    );

    Logger.debug('📦 ProductService: Product created - success: ${response.success}');
    return response;
  }

  /// Update existing product
  Future<ApiResponse<Product>> updateProduct({
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
    Logger.debug('📦 ProductService.updateProduct($id) called');

    final response = await _apiService.put<Product>(
      '/api/inventory/products/$id',
      body: {
        'name': name,
        'category_id': categoryId,
        'brand_id': brandId,
        'size': size,
        'alcohol_content': alcoholContent,
        'description': description,
        'barcode': barcode,
        'sku': sku,
        'cost_price': costPrice,
        'selling_price': sellingPrice,
        'mrp': mrp,
      },
      fromJson: (data) => Product.fromJson(data as Map<String, dynamic>),
    );

    Logger.debug('📦 ProductService: Product updated - success: ${response.success}');
    return response;
  }

  /// Delete product
  Future<ApiResponse<void>> deleteProduct(String id) async {
    Logger.debug('📦 ProductService.deleteProduct($id) called');

    final response = await _apiService.delete<void>(
      '/api/inventory/products/$id',
      fromJson: (_) => null,
    );

    Logger.debug('📦 ProductService: Product deleted - success: ${response.success}');
    return response;
  }
}

/// Products Response with Pagination
class ProductsResponse {
  final List<Product> products;
  final int total;
  final int page;
  final int limit;

  ProductsResponse({
    required this.products,
    required this.total,
    required this.page,
    required this.limit,
  });

  bool get hasMore => products.length < total;
  int get totalPages => (total / limit).ceil();
}
