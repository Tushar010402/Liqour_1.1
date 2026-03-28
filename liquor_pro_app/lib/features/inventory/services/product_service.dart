import '../../../core/models/api_response.dart';
import '../../../core/services/dio_api_service.dart';
import '../models/product.dart';
import '../models/brand.dart';
import '../../../core/utils/logger.dart';

/// Default page size for product pagination
/// Optimized for mobile scroll performance - matches backend pagination
const int kProductPageSize = 30;

/// Product Service - API client for product operations
class ProductService {
  final DioApiService _apiService;

  ProductService(this._apiService);

  /// Get all products with optional filtering
  /// Supports: search, category_id, category_ids, brand_id, is_active, page, limit, shop_id, size
  /// [categoryIds] - List of category IDs for combined filtering (e.g., English = Whisky + Rum + Vodka)
  Future<ApiResponse<ProductsResponse>> getProducts({
    String? search,
    String? categoryId,
    List<String>? categoryIds, // NEW: Multiple category IDs for combined filters
    String? brandId,
    bool? isActive,
    int page = 1,
    int limit = kProductPageSize,
    String? shopId,
    String? size, // Size filter parameter (e.g., "90ML", "180ML", "375ML")
  }) async {
    // Build query parameters
    // Backend uses offset/limit (not page/limit)
    final offset = (page - 1) * limit;
    final Map<String, dynamic> queryParams = {
      'offset': offset.toString(),
      'limit': limit.toString(),
    };

    if (search != null && search.isNotEmpty) {
      queryParams['search'] = search;
    }
    // Priority: categoryIds > categoryId
    if (categoryIds != null && categoryIds.isNotEmpty) {
      // Pass as comma-separated list for backend to parse
      queryParams['category_ids'] = categoryIds.join(',');
      Logger.debug('🏷️ [ProductService] Adding category_ids to query: ${categoryIds.join(',')}');
    } else if (categoryId != null) {
      queryParams['category_id'] = categoryId;
    }
    if (brandId != null) {
      queryParams['brand_id'] = brandId;
    }
    if (isActive != null) {
      queryParams['is_active'] = isActive.toString();
    }
    if (shopId != null) {
      queryParams['shop_id'] = shopId;
      Logger.debug('🏪 [ProductService] Adding shop_id to query: $shopId');
    }
    // Add size filter for backend filtering (case-insensitive on backend)
    if (size != null && size.isNotEmpty) {
      queryParams['size'] = size.toUpperCase(); // Normalize to uppercase
      Logger.debug('📏 [ProductService] Adding size filter to query: $size');
    }

    Logger.debug('🌐 [ProductService] Calling GET /api/inventory/products with params: $queryParams');

    final response = await _apiService.get<ProductsResponse>(
      '/api/inventory/products',
      queryParams: queryParams,
      fromJson: (data) {
        Logger.debug('🔍 [ProductService] Parsing response - data type: ${data.runtimeType}');

        // Handle array response
        if (data is List) {
          Logger.debug('✅ [ProductService] Parsed ${data.length} products from List');
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
          final productsList = (data['products'] as List?) ?? [];
          final total = data['total'] ?? productsList.length;
          final respOffset = data['offset'] ?? offset;
          final pageLimit = data['limit'] ?? limit;
          final pageNum = pageLimit > 0 ? (respOffset ~/ pageLimit) + 1 : page;
          Logger.debug('✅ [ProductService] Parsed ${productsList.length} products from Map');
          Logger.debug('✅ [ProductService] Backend pagination: total=$total, offset=$respOffset, limit=$pageLimit, page=$pageNum');
          Logger.debug('✅ [ProductService] Response keys: ${data.keys.toList()}');
          return ProductsResponse(
            products: productsList
                    .map((json) => Product.fromJson(json as Map<String, dynamic>))
                    .toList(),
            total: total,
            page: pageNum,
            limit: pageLimit,
          );
        }

        Logger.warning('⚠️  [ProductService] Could not parse response - returning empty');
        return ProductsResponse(products: [], total: 0, page: 1, limit: kProductPageSize);
      },
    );

    Logger.debug('🔍 [ProductService] Response success: ${response.success}, products: ${response.data?.products.length ?? 0}');
    return response;
  }

  /// Get single product by ID
  Future<ApiResponse<Product>> getProduct(String productId) async {
    final response = await _apiService.get<Product>(
      '/api/inventory/products/$productId',
      fromJson: (data) {
        return Product.fromJson(data as Map<String, dynamic>);
      },
    );

    return response;
  }

  /// Get multiple products by their IDs in a single API call
  /// More efficient than N individual getProduct calls
  /// Used for stock purchase sheet to fetch all selected products regardless of current filter
  Future<ApiResponse<ProductsResponse>> getProductsByIds({
    required List<String> productIds,
    String? shopId,
  }) async {
    if (productIds.isEmpty) {
      return ApiResponse.success(ProductsResponse(
        products: [],
        total: 0,
        page: 1,
        limit: productIds.length,
      ));
    }

    Logger.debug('🌐 [ProductService] Calling POST /api/inventory/products/by-ids with ${productIds.length} IDs');

    final body = <String, dynamic>{
      'ids': productIds,
    };
    if (shopId != null && shopId.isNotEmpty) {
      body['shop_id'] = shopId;
    }

    final response = await _apiService.post<ProductsResponse>(
      '/api/inventory/products/by-ids',
      body: body,
      fromJson: (data) {
        if (data is Map<String, dynamic>) {
          final productsList = (data['products'] as List?) ?? [];
          final total = data['total'] ?? productsList.length;
          Logger.info('✅ [ProductService] Fetched ${productsList.length} products by IDs');
          return ProductsResponse(
            products: productsList
                .map((json) => Product.fromJson(json as Map<String, dynamic>))
                .toList(),
            total: total,
            page: 1,
            limit: productIds.length,
          );
        }
        Logger.warning('⚠️ [ProductService] Could not parse by-ids response');
        return ProductsResponse(products: [], total: 0, page: 1, limit: productIds.length);
      },
    );

    return response;
  }

  /// Get categories - optionally filtered by shop_id for accuracy
  /// When shop_id is provided, only returns categories that have products with stock in that shop
  Future<ApiResponse<List<Category>>> getCategories({String? shopId}) async {
    final queryParams = <String, dynamic>{};
    if (shopId != null && shopId.isNotEmpty) {
      queryParams['shop_id'] = shopId;
    }

    final response = await _apiService.get<List<Category>>(
      '/api/inventory/categories',
      queryParams: queryParams.isNotEmpty ? queryParams : null,
      fromJson: (data) {
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

    return response;
  }

  /// Get all brands
  Future<ApiResponse<List<Brand>>> getBrands() async {
    final response = await _apiService.get<List<Brand>>(
      '/api/inventory/brands',
      fromJson: (data) {
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

    return response;
  }

  /// Get stock levels for products (optional shop filter)
  Future<ApiResponse<List<Stock>>> getStock({String? shopId}) async {
    final queryParams = shopId != null ? {'shop_id': shopId} : null;

    Logger.debug('🌐 [ProductService] Calling /api/inventory/stock with queryParams: $queryParams');

    final response = await _apiService.get<List<Stock>>(
      '/api/inventory/stock',
      queryParams: queryParams,
      fromJson: (data) {
        if (data is List) {
          Logger.debug('🌐 [ProductService] Received ${data.length} stock items (List format)');
          return data
              .map((json) => Stock.fromJson(json as Map<String, dynamic>))
              .toList();
        }

        if (data is Map<String, dynamic> && data['stocks'] is List) {
          final stocksList = data['stocks'] as List;
          Logger.debug('🌐 [ProductService] Received ${stocksList.length} stock items (Map format)');
          return stocksList
              .map((json) => Stock.fromJson(json as Map<String, dynamic>))
              .toList();
        }

        Logger.warning('⚠️  [ProductService] No stock data in response');
        return [];
      },
    );

    Logger.debug('🌐 [ProductService] Response success: ${response.success}, message: ${response.message}');
    return response;
  }

  // ===== Category CRUD Operations =====

  /// Create new category
  Future<ApiResponse<Category>> createCategory({
    required String name,
    String? description,
  }) async {
    final response = await _apiService.post<Category>(
      '/api/inventory/categories',
      body: {
        'name': name,
        if (description != null) 'description': description,
      },
      fromJson: (data) => Category.fromJson(data as Map<String, dynamic>),
    );

    return response;
  }

  /// Update existing category
  Future<ApiResponse<Category>> updateCategory({
    required String id,
    required String name,
    String? description,
  }) async {
    final response = await _apiService.put<Category>(
      '/api/inventory/categories/$id',
      body: {
        'name': name,
        if (description != null) 'description': description,
      },
      fromJson: (data) => Category.fromJson(data as Map<String, dynamic>),
    );

    return response;
  }

  /// Delete category
  Future<ApiResponse<void>> deleteCategory(String id) async {
    final response = await _apiService.delete<void>(
      '/api/inventory/categories/$id',
      fromJson: (_) {},
    );

    return response;
  }

  // ===== Brand CRUD Operations =====

  /// Create new brand
  Future<ApiResponse<Brand>> createBrand({
    required String name,
    String? description,
  }) async {
    final response = await _apiService.post<Brand>(
      '/api/inventory/brands',
      body: {
        'name': name,
        if (description != null) 'description': description,
      },
      fromJson: (data) => Brand.fromJson(data as Map<String, dynamic>),
    );

    return response;
  }

  /// Update existing brand
  Future<ApiResponse<Brand>> updateBrand({
    required String id,
    required String name,
    String? description,
  }) async {
    final response = await _apiService.put<Brand>(
      '/api/inventory/brands/$id',
      body: {
        'name': name,
        if (description != null) 'description': description,
      },
      fromJson: (data) => Brand.fromJson(data as Map<String, dynamic>),
    );

    return response;
  }

  /// Delete brand
  Future<ApiResponse<void>> deleteBrand(String id) async {
    final response = await _apiService.delete<void>(
      '/api/inventory/brands/$id',
      fromJson: (_) {},
    );

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
  }) async {
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
      },
      fromJson: (data) => Product.fromJson(data as Map<String, dynamic>),
    );

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
  }) async {
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
      },
      fromJson: (data) => Product.fromJson(data as Map<String, dynamic>),
    );

    return response;
  }

  /// Delete product
  Future<ApiResponse<void>> deleteProduct(String id) async {
    final response = await _apiService.delete<void>(
      '/api/inventory/products/$id',
      fromJson: (_) {},
    );

    return response;
  }

  /// Adjust stock for a product
  /// [quantity] - Absolute value to add or subtract
  /// [adjustmentType] - 'addition' or 'subtraction'
  Future<ApiResponse<void>> adjustStock({
    required String productId,
    required String shopId,
    required int quantity,
    required String adjustmentType,
    String? reason,
  }) async {
    final response = await _apiService.post<void>(
      '/api/inventory/stocks/adjust',
      body: {
        'product_id': productId,
        'shop_id': shopId,
        'quantity': quantity,
        'adjustment_type': adjustmentType,
        'reason': reason ?? 'Manual adjustment',
      },
      fromJson: (_) {},
    );

    return response;
  }

  /// Get available sizes for filtering (dynamic from backend)
  /// Returns distinct sizes with product counts for a given category and/or shop
  /// Industrial Best Practice: Returns SizeWithCount for showing count badges on filter chips
  /// [categoryIds] - List of category IDs for combined filtering (e.g., English = Whisky + Rum + Vodka)
  Future<ApiResponse<List<SizeWithCount>>> getAvailableSizesWithCounts({
    String? categoryId,
    List<String>? categoryIds, // NEW: Multiple category IDs for combined filters
    String? shopId,
  }) async {
    final queryParams = <String, dynamic>{};
    // Priority: categoryIds > categoryId
    if (categoryIds != null && categoryIds.isNotEmpty) {
      queryParams['category_ids'] = categoryIds.join(',');
      Logger.debug('🏷️ [ProductService] Adding category_ids to sizes query: ${categoryIds.join(',')}');
    } else if (categoryId != null && categoryId.isNotEmpty) {
      queryParams['category_id'] = categoryId;
    }
    if (shopId != null && shopId.isNotEmpty) {
      queryParams['shop_id'] = shopId;
    }

    Logger.debug('📏 [ProductService] Fetching available sizes with counts, params: $queryParams');

    final response = await _apiService.get<List<SizeWithCount>>(
      '/api/inventory/products/sizes',
      queryParams: queryParams.isNotEmpty ? queryParams : null,
      fromJson: (data) {
        List<SizeWithCount> sizesWithCounts = [];

        // Debug: Log the raw response structure
        Logger.debug('📏 [ProductService] Raw sizes response type: ${data.runtimeType}');
        if (data is Map) {
          Logger.debug('📏 [ProductService] Response keys: ${(data).keys.toList()}');
        }

        if (data is List) {
          // Check if it's a list of maps with SIZE/PRODUCT_COUNT format
          if (data.isNotEmpty && data.first is Map) {
            // Backend returns: [{SIZE: 90ML, PRODUCT_COUNT: 2}, ...]
            sizesWithCounts = data
                .whereType<Map>()
                .map((item) => SizeWithCount.fromJson(item as Map<String, dynamic>))
                .toList();
            Logger.debug('📏 [ProductService] Parsed ${sizesWithCounts.length} sizes with counts from list of maps');
          } else {
            // Backend returns simple list of strings: ["90ML", "180ML", ...]
            // Create SizeWithCount with count=0 (unknown)
            sizesWithCounts = data.map((e) => SizeWithCount(
              size: e.toString().toUpperCase(),
              productCount: 0,
            )).toList();
            Logger.debug('📏 [ProductService] Parsed ${sizesWithCounts.length} sizes (no counts) from list');
          }
        } else if (data is Map<String, dynamic>) {
          // Try multiple possible keys for sizes
          List? sizesList;
          if (data['sizes'] is List) {
            sizesList = data['sizes'] as List;
          } else if (data['data'] is List) {
            sizesList = data['data'] as List;
          } else if (data['items'] is List) {
            sizesList = data['items'] as List;
          }

          // Log total for debugging
          final total = data['total'];
          Logger.debug('📏 [ProductService] sizes list length: ${sizesList?.length ?? 0}, total from API: $total');

          if (sizesList != null && sizesList.isNotEmpty) {
            // Check if it's a list of maps with SIZE/PRODUCT_COUNT format
            if (sizesList.first is Map) {
              sizesWithCounts = sizesList
                  .whereType<Map>()
                  .map((item) => SizeWithCount.fromJson(item as Map<String, dynamic>))
                  .toList();
              Logger.debug('📏 [ProductService] Parsed ${sizesWithCounts.length} sizes with counts from map.sizes');
            } else {
              // Simple list of strings - create with count=0
              sizesWithCounts = sizesList.map((e) => SizeWithCount(
                size: e.toString().toUpperCase(),
                productCount: 0,
              )).toList();
              Logger.debug('📏 [ProductService] Parsed ${sizesWithCounts.length} sizes (no counts) from map.sizes');
            }
          } else {
            Logger.warning('⚠️ [ProductService] Backend returned EMPTY sizes array');
            return <SizeWithCount>[];
          }
        } else {
          Logger.warning('⚠️ [ProductService] Could not parse sizes response: ${data.runtimeType}');
          return <SizeWithCount>[];
        }

        // BEST PRACTICE: Deduplicate sizes by normalized key (handles 180ML vs 180ml)
        // Since SizeWithCount.fromJson already calls toUpperCase(), duplicates can occur
        // if backend returns both "180ML" and "180ml" as separate records
        final Map<String, SizeWithCount> deduplicatedSizes = {};
        for (final sizeWithCount in sizesWithCounts) {
          final normalizedSize = sizeWithCount.size.toUpperCase().replaceAll(' ', '');
          if (deduplicatedSizes.containsKey(normalizedSize)) {
            // Merge counts: add productCount and totalStockQuantity
            final existing = deduplicatedSizes[normalizedSize]!;
            deduplicatedSizes[normalizedSize] = SizeWithCount(
              size: normalizedSize,
              productCount: existing.productCount + sizeWithCount.productCount,
              totalStockQuantity: existing.totalStockQuantity + sizeWithCount.totalStockQuantity,
            );
          } else {
            // First occurrence - use normalized size
            deduplicatedSizes[normalizedSize] = SizeWithCount(
              size: normalizedSize,
              productCount: sizeWithCount.productCount,
              totalStockQuantity: sizeWithCount.totalStockQuantity,
            );
          }
        }
        sizesWithCounts = deduplicatedSizes.values.toList();

        // Sort numerically (90ML < 180ML < 375ML < 750ML)
        sizesWithCounts.sort((a, b) {
          final aNum = int.tryParse(a.size.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
          final bNum = int.tryParse(b.size.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
          return aNum.compareTo(bNum);
        });

        Logger.debug('📏 [ProductService] Final sizes with counts and stock (deduplicated):');
        for (final s in sizesWithCounts) {
          Logger.debug('   📏 ${s.size}: ${s.productCount} products, ${s.totalStockQuantity} total stock');
        }
        return sizesWithCounts;
      },
    );

    return response;
  }

  /// Get available sizes for filtering (legacy - returns strings only)
  /// Deprecated: Use getAvailableSizesWithCounts() instead for better UX
  Future<ApiResponse<List<String>>> getAvailableSizes({
    String? categoryId,
    String? shopId,
  }) async {
    final result = await getAvailableSizesWithCounts(
      categoryId: categoryId,
      shopId: shopId,
    );

    if (result.success && result.data != null) {
      return ApiResponse<List<String>>(
        success: true,
        data: result.data!.map((s) => s.size).toList(),
        message: result.message,
      );
    }

    return ApiResponse<List<String>>(
      success: result.success,
      data: [],
      message: result.message,
    );
  }

  /// Get subcategories for a category
  Future<ApiResponse<List<Subcategory>>> getSubcategories(String categoryId) async {
    final response = await _apiService.get<List<Subcategory>>(
      '/api/inventory/catalog/subcategories',
      queryParams: {'category_id': categoryId},
      fromJson: (data) {
        if (data is List) {
          return data
              .map((json) => Subcategory.fromJson(json as Map<String, dynamic>))
              .toList();
        }

        if (data is Map<String, dynamic> && data['subcategories'] is List) {
          return (data['subcategories'] as List)
              .map((json) => Subcategory.fromJson(json as Map<String, dynamic>))
              .toList();
        }

        return [];
      },
    );

    return response;
  }

  /// Create a custom brand with a product variant
  Future<ApiResponse<Map<String, dynamic>>> createCustomBrandWithVariant({
    required String brandName,
    required String description,
    required String categoryId,
    String? subcategoryId,
    required String size,
    required double alcoholContent,
    required double buyingPrice, // Changed from costPrice
    required double sellingPrice,
    required double mrp, // Added MRP parameter
    required String barcode,
  }) async {
    final response = await _apiService.post<Map<String, dynamic>>(
      '/api/inventory/brands/custom',
      body: {
        'brand_name': brandName,
        'description': description,
        'category_id': categoryId,
        if (subcategoryId != null) 'subcategory_id': subcategoryId,
        'size': size,
        'alcohol_content': alcoholContent,
        'buying_price': buyingPrice, // Changed from cost_price
        'selling_price': sellingPrice,
        'mrp': mrp, // Added MRP
        'barcode': barcode,
      },
      fromJson: (data) => (data as Map<String, dynamic>?) ?? {},
    );

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

  /// Check if there are more pages to load
  /// True only if current page returned a full page of items
  /// (meaning there might be more on the next page)
  bool get hasMore => products.length >= limit;

  int get totalPages => (total / limit).ceil();
}
