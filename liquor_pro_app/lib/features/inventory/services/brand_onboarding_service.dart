import '../../../core/models/api_response.dart';
import '../../../core/services/api_service.dart';
import '../models/saas_brand.dart';
import '../models/brand.dart';
import '../models/product.dart';
import '../../../core/utils/logger.dart';

/// Brand Onboarding Service - API client for SaaS brand onboarding
class BrandOnboardingService {
  final ApiService _apiService;

  BrandOnboardingService(this._apiService) {
    Logger.debug('🎯 BrandOnboardingService created');
    Logger.debug('   - ApiService: ${_apiService != null ? "✅" : "❌"}');
    Logger.debug('   - AuthService (from ApiService): ${_apiService.authService != null ? "✅" : "❌"}');
  }

  /// Get available SaaS brand templates for onboarding
  Future<ApiResponse<List<SaasBrand>>> getAvailableBrands() async {
    Logger.debug('🎯 BrandOnboardingService.getAvailableBrands() called');

    final response = await _apiService.get<List<SaasBrand>>(
      '/api/inventory/saas-brands/available',
      fromJson: (data) {
        Logger.debug('🎯 Parsing available brands response: ${data.runtimeType}');

        if (data is List) {
          return data
              .map((json) => SaasBrand.fromJson(json as Map<String, dynamic>))
              .toList();
        }

        // Backend sends: {"message": "...", "data": [...], "count": 8}
        if (data is Map<String, dynamic>) {
          // Try 'data' key first (new backend format)
          if (data['data'] is List) {
            Logger.debug('🎯 Parsing from "data" key (${(data['data'] as List).length} brands)');
            return (data['data'] as List)
                .map((json) => SaasBrand.fromJson(json as Map<String, dynamic>))
                .toList();
          }

          // Fallback to 'brands' key (legacy format)
          if (data['brands'] is List) {
            Logger.debug('🎯 Parsing from "brands" key (${(data['brands'] as List).length} brands)');
            return (data['brands'] as List)
                .map((json) => SaasBrand.fromJson(json as Map<String, dynamic>))
                .toList();
          }
        }

        Logger.debug('⚠️  Unable to parse brands from response');
        return [];
      },
    );

    Logger.debug('🎯 BrandOnboardingService: Response - success: ${response.success}');
    return response;
  }

  /// Onboard selected brands to tenant inventory
  Future<ApiResponse<OnboardingResult>> onboardBrands({
    required List<String> brandIds,
    required List<String> variantIds,
    String? shopId,
  }) async {
    Logger.debug('🎯 BrandOnboardingService.onboardBrands() called');
    Logger.debug('   - Brand IDs: $brandIds');
    Logger.debug('   - Variant IDs: $variantIds');

    // Get tenant ID from ApiService's AuthService
    final tenantId = await _apiService.authService.getTenantId();
    Logger.debug('🎯 Tenant ID retrieved: $tenantId');

    if (tenantId == null || tenantId.isEmpty) {
      Logger.debug('❌ Tenant ID is null or empty!');
      return ApiResponse<OnboardingResult>(
        success: false,
        message: 'Tenant ID is required for onboarding',
      );
    }

    final requestBody = {
      'brand_ids': brandIds,
      'variant_ids': variantIds,
      'tenant_id': tenantId,
      if (shopId != null) 'shop_id': shopId,
    };

    final response = await _apiService.post<OnboardingResult>(
      '/api/inventory/saas-brands/onboard',
      body: requestBody,
      fromJson: (data) {
        Logger.debug('🎯 Parsing onboarding result: ${data.runtimeType}');
        return OnboardingResult.fromJson(data as Map<String, dynamic>);
      },
    );

    Logger.debug('🎯 BrandOnboardingService: Onboarding response - success: ${response.success}');
    return response;
  }

  /// Get onboarded products (from SaaS templates)
  Future<ApiResponse<List<Product>>> getOnboardedProducts() async {
    Logger.debug('🎯 BrandOnboardingService.getOnboardedProducts() called');

    final response = await _apiService.get<List<Product>>(
      '/api/inventory/saas-brands/onboarded',
      fromJson: (data) {
        Logger.debug('🎯 Parsing onboarded products: ${data.runtimeType}');

        if (data is List) {
          return data
              .map((json) => Product.fromJson(json as Map<String, dynamic>))
              .toList();
        }

        if (data is Map<String, dynamic> && data['products'] is List) {
          return (data['products'] as List)
              .map((json) => Product.fromJson(json as Map<String, dynamic>))
              .toList();
        }

        return [];
      },
    );

    return response;
  }

  /// Get custom brands (created by tenant)
  Future<ApiResponse<List<Brand>>> getCustomBrands() async {
    Logger.debug('🎯 BrandOnboardingService.getCustomBrands() called');

    final response = await _apiService.get<List<Brand>>(
      '/api/inventory/brands/custom',
      fromJson: (data) {
        Logger.debug('🎯 Parsing custom brands: ${data.runtimeType}');

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

  /// Get brand packages (Starter, Premium, Full)
  Future<ApiResponse<List<BrandPackage>>> getBrandPackages() async {
    Logger.debug('🎯 BrandOnboardingService.getBrandPackages() called');

    final response = await _apiService.get<List<BrandPackage>>(
      '/api/super-admin/brands/packages',
      fromJson: (data) {
        Logger.debug('🎯 Parsing brand packages: ${data.runtimeType}');

        if (data is List) {
          return data
              .map((json) => BrandPackage.fromJson(json as Map<String, dynamic>))
              .toList();
        }

        if (data is Map<String, dynamic> && data['packages'] is List) {
          return (data['packages'] as List)
              .map((json) => BrandPackage.fromJson(json as Map<String, dynamic>))
              .toList();
        }

        return [];
      },
    );

    return response;
  }
}

/// Onboarding Result - Matches backend OnboardBrandResponse
class OnboardingResult {
  final int brandsOnboarded;
  final int productsCreated;
  final int categoriesCreated;
  final List<String> productIds;
  final String message;
  final List<String>? errors;

  OnboardingResult({
    required this.brandsOnboarded,
    required this.productsCreated,
    required this.categoriesCreated,
    required this.productIds,
    required this.message,
    this.errors,
  });

  factory OnboardingResult.fromJson(Map<String, dynamic> json) {
    // Backend sends: onboarded_brands, onboarded_products, brand_details, errors
    // Map to Flutter expectations
    final brandDetails = json['brand_details'] as List<dynamic>? ?? [];
    final allProductIds = <String>[];

    // Extract product IDs from brand_details
    for (var detail in brandDetails) {
      if (detail is Map<String, dynamic> && detail['product_ids'] is List) {
        allProductIds.addAll(
          (detail['product_ids'] as List).map((id) => id.toString())
        );
      }
    }

    return OnboardingResult(
      brandsOnboarded: json['onboarded_brands'] ?? 0,
      productsCreated: json['onboarded_products'] ?? 0,
      categoriesCreated: json['categories_created'] ?? 0,
      productIds: allProductIds,
      message: json['message'] ?? 'Brands onboarded successfully',
      errors: (json['errors'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
    );
  }
}

/// Brand Package (Starter, Premium, Full)
class BrandPackage {
  final String id;
  final String name;
  final String description;
  final int brandCount;
  final List<String> brandIds;

  BrandPackage({
    required this.id,
    required this.name,
    required this.description,
    required this.brandCount,
    required this.brandIds,
  });

  factory BrandPackage.fromJson(Map<String, dynamic> json) {
    return BrandPackage(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      brandCount: json['brand_count'] ?? 0,
      brandIds: (json['brand_ids'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }
}
