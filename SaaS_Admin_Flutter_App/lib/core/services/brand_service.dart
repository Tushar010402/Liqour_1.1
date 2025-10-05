import '../constants/api_endpoints.dart';
import '../models/api_response.dart';
import '../models/brand_model.dart';
import 'api_service.dart';

class BrandService {
  final ApiService _apiService;

  BrandService(this._apiService);

  // Brand Operations
  Future<ApiResponse<List<Brand>>> getAllBrands({
    bool includeVariants = false,
    bool activeOnly = false,
  }) async {
    try {
      final queryParams = <String>[];
      if (includeVariants) queryParams.add('include_variants=true');
      if (activeOnly) queryParams.add('active_only=true');

      final queryString = queryParams.isNotEmpty ? '?${queryParams.join('&')}' : '';
      final response = await _apiService.get(
        '${ApiEndpoints.brands}$queryString',
      );

      if (response.success && response.data != null) {
        final List<dynamic> brandsJson = response.data['data'] ?? [];
        final brands = brandsJson.map((json) => Brand.fromJson(json)).toList();
        return ApiResponse<List<Brand>>.success(brands);
      }

      return ApiResponse<List<Brand>>.error(
          response.message ?? 'Unknown error');
    } catch (e) {
      return ApiResponse<List<Brand>>.error('Failed to load brands: $e');
    }
  }

  Future<ApiResponse<Brand>> getBrandById(String brandId,
      {bool includeVariants = true}) async {
    try {
      final response = await _apiService.get(ApiEndpoints.brandById(brandId));

      if (response.success && response.data != null) {
        final brand = Brand.fromJson(response.data['data']);
        return ApiResponse<Brand>.success(brand);
      }

      return ApiResponse<Brand>.error(response.message ?? 'Unknown error');
    } catch (e) {
      return ApiResponse<Brand>.error('Failed to load brand: $e');
    }
  }

  Future<ApiResponse<Brand>> createBrand(CreateBrandRequest request) async {
    try {
      final response = await _apiService.post(
        ApiEndpoints.brands,
        data: request.toJson(),
      );

      if (response.success && response.data != null) {
        final brand = Brand.fromJson(response.data['data']);
        return ApiResponse<Brand>.success(brand);
      }

      return ApiResponse<Brand>.error(response.message ?? 'Unknown error');
    } catch (e) {
      return ApiResponse<Brand>.error('Failed to create brand: $e');
    }
  }

  Future<ApiResponse<Brand>> updateBrand(
      String brandId, CreateBrandRequest request) async {
    try {
      final response = await _apiService.put(
        ApiEndpoints.brandById(brandId),
        data: request.toJson(),
      );

      if (response.success && response.data != null) {
        final brand = Brand.fromJson(response.data['data']);
        return ApiResponse<Brand>.success(brand);
      }

      return ApiResponse<Brand>.error(response.message ?? 'Unknown error');
    } catch (e) {
      return ApiResponse<Brand>.error('Failed to update brand: $e');
    }
  }

  Future<ApiResponse<void>> deleteBrand(String brandId) async {
    try {
      final response =
          await _apiService.delete(ApiEndpoints.brandById(brandId));

      if (response.success) {
        return ApiResponse<void>.success(null);
      }

      return ApiResponse<void>.error(response.message ?? 'Unknown error');
    } catch (e) {
      return ApiResponse<void>.error('Failed to delete brand: $e');
    }
  }

  // Brand Variant Operations
  Future<ApiResponse<List<BrandVariant>>> getBrandVariants(
      String brandId) async {
    try {
      final response =
          await _apiService.get('${ApiEndpoints.brandById(brandId)}/variants');

      if (response.success && response.data != null) {
        final List<dynamic> variantsJson = response.data['data'] ?? [];
        final variants =
            variantsJson.map((json) => BrandVariant.fromJson(json)).toList();
        return ApiResponse<List<BrandVariant>>.success(variants);
      }

      return ApiResponse<List<BrandVariant>>.error(
          response.message ?? 'Unknown error');
    } catch (e) {
      return ApiResponse<List<BrandVariant>>.error(
          'Failed to load brand variants: $e');
    }
  }

  Future<ApiResponse<BrandVariant>> createBrandVariant(
      CreateBrandVariantRequest request) async {
    try {
      final response = await _apiService.post(
        ApiEndpoints.brandVariants,
        data: request.toJson(),
      );

      if (response.success && response.data != null) {
        final variant = BrandVariant.fromJson(response.data['data']);
        return ApiResponse<BrandVariant>.success(variant);
      }

      return ApiResponse<BrandVariant>.error(
          response.message ?? 'Unknown error');
    } catch (e) {
      return ApiResponse<BrandVariant>.error(
          'Failed to create brand variant: $e');
    }
  }

  Future<ApiResponse<BrandVariant>> updateBrandVariant(
      String variantId, CreateBrandVariantRequest request) async {
    try {
      final response = await _apiService.put(
        ApiEndpoints.brandVariantById(variantId),
        data: request.toJson(),
      );

      if (response.success && response.data != null) {
        final variant = BrandVariant.fromJson(response.data['data']);
        return ApiResponse<BrandVariant>.success(variant);
      }

      return ApiResponse<BrandVariant>.error(
          response.message ?? 'Unknown error');
    } catch (e) {
      return ApiResponse<BrandVariant>.error(
          'Failed to update brand variant: $e');
    }
  }

  Future<ApiResponse<void>> deleteBrandVariant(String variantId) async {
    try {
      final response = await _apiService.delete(
        ApiEndpoints.brandVariantById(variantId),
      );

      if (response.success) {
        return ApiResponse<void>.success(null);
      }

      return ApiResponse<void>.error(response.message ?? 'Unknown error');
    } catch (e) {
      return ApiResponse<void>.error('Failed to delete brand variant: $e');
    }
  }

  // Brand Category Operations
  Future<ApiResponse<List<BrandCategory>>> getBrandCategories() async {
    try {
      final response = await _apiService.get(ApiEndpoints.brandCategories);

      if (response.success && response.data != null) {
        final List<dynamic> categoriesJson = response.data['data'] ?? [];
        final categories =
            categoriesJson.map((json) => BrandCategory.fromJson(json)).toList();
        return ApiResponse<List<BrandCategory>>.success(categories);
      }

      return ApiResponse<List<BrandCategory>>.error(
          response.message ?? 'Unknown error');
    } catch (e) {
      return ApiResponse<List<BrandCategory>>.error(
          'Failed to load brand categories: $e');
    }
  }

  Future<ApiResponse<BrandCategory>> createBrandCategory(
      CreateBrandCategoryRequest request) async {
    try {
      final response = await _apiService.post(
        ApiEndpoints.brandCategories,
        data: request.toJson(),
      );

      if (response.success && response.data != null) {
        final category = BrandCategory.fromJson(response.data['data']);
        return ApiResponse<BrandCategory>.success(category);
      }

      return ApiResponse<BrandCategory>.error(
          response.message ?? 'Unknown error');
    } catch (e) {
      return ApiResponse<BrandCategory>.error(
          'Failed to create brand category: $e');
    }
  }

  // Brand Subcategory Operations
  Future<ApiResponse<List<BrandSubcategory>>> getBrandSubcategories(
      {String? categoryId}) async {
    try {
      final queryParams = categoryId != null ? '?category_id=$categoryId' : '';
      final response = await _apiService
          .get('${ApiEndpoints.brandSubcategories}$queryParams');

      if (response.success && response.data != null) {
        final List<dynamic> subcategoriesJson = response.data['data'] ?? [];
        final subcategories = subcategoriesJson
            .map((json) => BrandSubcategory.fromJson(json))
            .toList();
        return ApiResponse<List<BrandSubcategory>>.success(subcategories);
      }

      return ApiResponse<List<BrandSubcategory>>.error(
          response.message ?? 'Unknown error');
    } catch (e) {
      return ApiResponse<List<BrandSubcategory>>.error(
          'Failed to load brand subcategories: $e');
    }
  }

  Future<ApiResponse<BrandSubcategory>> createBrandSubcategory(
      CreateBrandSubcategoryRequest request) async {
    try {
      final response = await _apiService.post(
        ApiEndpoints.brandSubcategories,
        data: request.toJson(),
      );

      if (response.success && response.data != null) {
        final subcategory = BrandSubcategory.fromJson(response.data['data']);
        return ApiResponse<BrandSubcategory>.success(subcategory);
      }

      return ApiResponse<BrandSubcategory>.error(
          response.message ?? 'Unknown error');
    } catch (e) {
      return ApiResponse<BrandSubcategory>.error(
          'Failed to create brand subcategory: $e');
    }
  }

  // Tenant Brand Assignment
  Future<ApiResponse<void>> assignBrandsToTenant(
      TenantBrandAssignmentRequest request) async {
    try {
      final response = await _apiService.post(
        ApiEndpoints.assignBrandsToTenant,
        data: request.toJson(),
      );

      if (response.success) {
        return ApiResponse<void>.success(null);
      }

      return ApiResponse<void>.error(response.message ?? 'Unknown error');
    } catch (e) {
      return ApiResponse<void>.error('Failed to assign brands to tenant: $e');
    }
  }

  Future<ApiResponse<List<Brand>>> getTenantBrands(String tenantId) async {
    try {
      final response =
          await _apiService.get(ApiEndpoints.tenantBrands(tenantId));

      if (response.success && response.data != null) {
        final List<dynamic> brandsJson = response.data['data'] ?? [];
        final brands = brandsJson.map((json) => Brand.fromJson(json)).toList();
        return ApiResponse<List<Brand>>.success(brands);
      }

      return ApiResponse<List<Brand>>.error(
          response.message ?? 'Unknown error');
    } catch (e) {
      return ApiResponse<List<Brand>>.error('Failed to load tenant brands: $e');
    }
  }

  // Public Brands (for tenant selection)
  Future<ApiResponse<List<Brand>>> getPublicBrands({
    bool includeVariants = false,
    String? categoryId,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final queryParams = <String>[];
      if (includeVariants) queryParams.add('include_variants=true');
      if (categoryId != null) queryParams.add('category_id=$categoryId');
      queryParams.add('page=$page');
      queryParams.add('limit=$limit');

      final queryString =
          queryParams.isNotEmpty ? '?${queryParams.join('&')}' : '';
      final response =
          await _apiService.get('${ApiEndpoints.publicBrands}$queryString');

      if (response.success && response.data != null) {
        final List<dynamic> brandsJson = response.data['data'] ?? [];
        final brands = brandsJson.map((json) => Brand.fromJson(json)).toList();
        return ApiResponse<List<Brand>>.success(brands);
      }

      return ApiResponse<List<Brand>>.error(
          response.message ?? 'Unknown error');
    } catch (e) {
      return ApiResponse<List<Brand>>.error('Failed to load public brands: $e');
    }
  }

  // Bulk Operations
  Future<ApiResponse<Map<String, dynamic>>> bulkCreateBrands(
      List<Map<String, dynamic>> bulkRequest) async {
    try {
      final response = await _apiService.post(
        ApiEndpoints.bulkCreateBrands,
        data: bulkRequest,
      );

      if (response.success && response.data != null) {
        return ApiResponse<Map<String, dynamic>>.success(response.data);
      }

      return ApiResponse<Map<String, dynamic>>.error(
          response.message ?? 'Unknown error');
    } catch (e) {
      return ApiResponse<Map<String, dynamic>>.error(
          'Failed to bulk create brands: $e');
    }
  }

  // Search brands
  Future<ApiResponse<List<Brand>>> searchBrands({
    required String query,
    bool includeVariants = false,
    String? categoryId,
  }) async {
    try {
      // For now, we'll get all brands and filter client-side
      // In a production app, you'd want a proper search endpoint
      final response = await getAllBrands(includeVariants: includeVariants);

      if (response.success && response.data != null) {
        final filteredBrands = response.data!.where((brand) {
          final matchesQuery =
              brand.name.toLowerCase().contains(query.toLowerCase()) ||
                  brand.description.toLowerCase().contains(query.toLowerCase());

          if (categoryId != null && brand.brandVariants != null) {
            final matchesCategory = brand.brandVariants!
                .any((variant) => variant.categoryId == categoryId);
            return matchesQuery && matchesCategory;
          }

          return matchesQuery;
        }).toList();

        return ApiResponse<List<Brand>>.success(filteredBrands);
      }

      return ApiResponse<List<Brand>>.error(
          response.message ?? 'Unknown error');
    } catch (e) {
      return ApiResponse<List<Brand>>.error('Failed to search brands: $e');
    }
  }
}
