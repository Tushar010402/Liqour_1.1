import '../../../core/services/dio_api_service.dart';
import '../models/category_summary.dart';
import '../models/paginated_brand_response.dart';
import '../models/saas_brand.dart';

/// Service for brand catalog operations with category-first navigation
class BrandCatalogService {
  final DioApiService _apiService;

  BrandCatalogService(this._apiService);

  /// Get all categories with brand counts
  /// NOTE: Backend endpoint not implemented yet - returns empty list
  Future<List<CategorySummary>> getCategories() async {
    try {
      final response = await _apiService.get<List<CategorySummary>>(
        '/api/inventory/saas-brands/categories',
        fromJson: (data) {
          if (data is List) {
            return data.map((json) => CategorySummary.fromJson(json as Map<String, dynamic>)).toList();
          }
          return <CategorySummary>[];
        },
      );

      if (response.success && response.data != null) {
        return response.data!;
      }

      // Backend endpoint not implemented - return empty list gracefully
      return [];
    } catch (e) {
      // Return empty list on error instead of throwing
      return [];
    }
  }

  /// Get brands paginated with optional filtering
  Future<PaginatedBrandResponse> getBrandsPaginated({
    String? categoryId,
    String? search,
    int page = 1,
    int limit = 30,
  }) async {
    try {
      final Map<String, String> queryParams = {
        'page': page.toString(),
        'limit': limit.toString(),
      };

      if (categoryId != null && categoryId.isNotEmpty) {
        queryParams['category_id'] = categoryId;
      }

      if (search != null && search.isNotEmpty) {
        queryParams['search'] = search;
      }

      final response = await _apiService.get<PaginatedBrandResponse>(
        '/api/inventory/saas-brands/paginated',
        queryParams: queryParams,
        fromJson: (data) => PaginatedBrandResponse.fromJson(data as Map<String, dynamic>),
      );

      if (response.success && response.data != null) {
        return response.data!;
      }

      return PaginatedBrandResponse(
        brands: [],
        total: 0,
        page: page,
        limit: limit,
        hasMore: false,
      );
    } catch (e) {
      rethrow;
    }
  }

  /// Get all available brands (legacy endpoint for backward compatibility)
  Future<List<SaasBrand>> getAllBrands() async {
    try {
      final response = await _apiService.get<List<SaasBrand>>(
        '/api/inventory/saas-brands/available',
        fromJson: (data) {
          if (data is List) {
            return data.map((json) => SaasBrand.fromJson(json as Map<String, dynamic>)).toList();
          }
          return <SaasBrand>[];
        },
      );

      if (response.success && response.data != null) {
        return response.data!;
      }

      return [];
    } catch (e) {
      rethrow;
    }
  }

  /// Onboard selected brands and variants to tenant with shop-specific stock
  Future<Map<String, dynamic>> onboardBrands({
    required List<String> brandIds,
    required List<String> variantIds,
    String? shopId,
    Map<String, int>? variantStockQuantities,
  }) async {
    try {
      // Build request body
      final requestBody = <String, dynamic>{
        'brand_ids': brandIds,
        'variant_ids': variantIds,
      };

      // Add shop_id if provided
      if (shopId != null && shopId.isNotEmpty) {
        requestBody['shop_id'] = shopId;
      }

      // Add brand_variants with stock quantities if provided
      if (variantStockQuantities != null && variantStockQuantities.isNotEmpty) {
        final brandVariants = variantStockQuantities.entries
            .where((e) => e.value >= 0) // Include all non-negative quantities
            .map((e) => {
                  'saas_brand_variant_id': e.key,
                  'initial_stock': e.value,
                })
            .toList();

        if (brandVariants.isNotEmpty) {
          requestBody['brand_variants'] = brandVariants;
        }
      }

      // Tenant ID is automatically added by auth middleware in backend
      final response = await _apiService.post<Map<String, dynamic>>(
        '/api/inventory/saas-brands/onboard',
        body: requestBody,
      );

      if (response.success && response.data != null) {
        return response.data!;
      }

      return {};
    } catch (e) {
      rethrow;
    }
  }

  /// Get onboarded brands (products created from SaaS brands)
  Future<List<dynamic>> getOnboardedBrands() async {
    try {
      final response = await _apiService.get<List<dynamic>>(
        '/api/inventory/saas-brands/onboarded',
      );

      if (response.success && response.data != null) {
        return response.data!;
      }

      return [];
    } catch (e) {
      rethrow;
    }
  }

  /// Get custom brands (tenant-created brands)
  Future<List<dynamic>> getCustomBrands() async {
    try {
      final response = await _apiService.get<List<dynamic>>(
        '/api/inventory/brands/custom',
      );

      if (response.success && response.data != null) {
        return response.data!;
      }

      return [];
    } catch (e) {
      rethrow;
    }
  }
}
