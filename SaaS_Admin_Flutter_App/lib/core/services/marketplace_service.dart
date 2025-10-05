import '../constants/api_endpoints.dart';
import '../models/api_response.dart';
import '../models/brand_package_model.dart';
import '../models/brand_model.dart';
import 'api_service.dart';

class MarketplaceService {
  final ApiService _apiService;

  MarketplaceService(this._apiService);

  // Get predefined brand packages
  Future<ApiResponse<List<BrandPackage>>> getBrandPackages({
    MarketplaceFilter? filter,
  }) async {
    try {
      final queryParams = <String>[];

      if (filter != null) {
        if (filter.categoryId != null) {
          queryParams.add('category_id=${filter.categoryId}');
        }
        if (filter.packageType != null) {
          queryParams.add('package_type=${filter.packageType}');
        }
        if (filter.searchQuery != null && filter.searchQuery!.isNotEmpty) {
          queryParams.add('search=${filter.searchQuery}');
        }
        if (filter.priceRange != null) {
          queryParams.add('min_price=${filter.priceRange!.min}');
          queryParams.add('max_price=${filter.priceRange!.max}');
        }
      }

      final queryString = queryParams.isNotEmpty ? '?${queryParams.join('&')}' : '';

      // For now, return mock data since we don't have the backend endpoint yet
      // In production, this would be: await _apiService.get('${ApiEndpoints.brandPackages}$queryString');
      return _getMockBrandPackages(filter);
    } catch (e) {
      return ApiResponse<List<BrandPackage>>.error('Failed to load brand packages: $e');
    }
  }

  // Get individual brands for custom selection
  Future<ApiResponse<List<Brand>>> getMarketplaceBrands({
    MarketplaceFilter? filter,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final queryParams = <String>[];

      if (filter != null) {
        if (filter.categoryId != null) {
          queryParams.add('category_id=${filter.categoryId}');
        }
        if (filter.searchQuery != null && filter.searchQuery!.isNotEmpty) {
          queryParams.add('search=${filter.searchQuery}');
        }
      }

      queryParams.add('page=$page');
      queryParams.add('limit=$limit');
      queryParams.add('include_variants=true');

      final queryString = queryParams.isNotEmpty ? '?${queryParams.join('&')}' : '';
      final response = await _apiService.get('${ApiEndpoints.publicBrands}$queryString');

      if (response.success && response.data != null) {
        final List<dynamic> brandsJson = response.data['data'] ?? [];
        final brands = brandsJson.map((json) => Brand.fromJson(json)).toList();
        return ApiResponse<List<Brand>>.success(brands);
      }

      return ApiResponse<List<Brand>>.error(response.message ?? 'Unknown error');
    } catch (e) {
      return ApiResponse<List<Brand>>.error('Failed to load marketplace brands: $e');
    }
  }

  // Complete tenant onboarding with selected brands/package
  Future<ApiResponse<void>> completeTenantOnboarding(
      TenantOnboardingRequest request) async {
    try {
      final response = await _apiService.post(
        ApiEndpoints.assignBrandsToTenant,
        data: {
          'tenant_id': request.tenantId,
          'brand_ids': request.selectedBrandIds,
          'variant_ids': request.selectedVariantIds,
        },
      );

      if (response.success) {
        return ApiResponse<void>.success(null);
      }

      return ApiResponse<void>.error(response.message ?? 'Unknown error');
    } catch (e) {
      return ApiResponse<void>.error('Failed to complete onboarding: $e');
    }
  }

  // Mock data for brand packages (replace with real API when available)
  Future<ApiResponse<List<BrandPackage>>> _getMockBrandPackages(MarketplaceFilter? filter) async {
    // Simulate API delay
    await Future.delayed(const Duration(milliseconds: 500));

    final packages = [
      BrandPackage(
        id: 'starter-package',
        name: 'Starter Package',
        description: 'Perfect for small liquor stores getting started',
        type: 'starter',
        price: 4999.0,
        brandCount: 15,
        variantCount: 45,
        features: [
          'Popular local brands',
          'Basic inventory management',
          'Standard pricing',
          'Essential product variants',
          '24/7 phone support',
        ],
        isPopular: false,
        discountPercentage: 10.0,
        brands: [], // Would be populated with actual brand data
      ),
      BrandPackage(
        id: 'premium-package',
        name: 'Premium Package',
        description: 'Comprehensive solution for growing businesses',
        type: 'premium',
        price: 9999.0,
        brandCount: 35,
        variantCount: 120,
        features: [
          'Premium and local brands',
          'Advanced inventory tracking',
          'Competitive pricing',
          'Wide variety of products',
          'Analytics dashboard',
          'Priority support',
        ],
        isPopular: true,
        discountPercentage: 20.0,
        brands: [], // Would be populated with actual brand data
      ),
      BrandPackage(
        id: 'full-package',
        name: 'Complete Package',
        description: 'All brands and features for maximum flexibility',
        type: 'full',
        price: 19999.0,
        brandCount: 75,
        variantCount: 300,
        features: [
          'All available brands',
          'Complete inventory system',
          'Dynamic pricing',
          'Full product catalog',
          'Advanced analytics',
          'Custom reporting',
          'Dedicated account manager',
        ],
        isPopular: false,
        discountPercentage: 25.0,
        brands: [], // Would be populated with actual brand data
      ),
    ];

    // Apply filters
    var filteredPackages = packages;

    if (filter?.packageType != null) {
      filteredPackages = filteredPackages
          .where((p) => p.type == filter!.packageType)
          .toList();
    }

    if (filter?.priceRange != null) {
      filteredPackages = filteredPackages
          .where((p) => p.finalPrice >= filter!.priceRange!.min &&
                      p.finalPrice <= filter!.priceRange!.max)
          .toList();
    }

    if (filter?.searchQuery != null && filter!.searchQuery!.isNotEmpty) {
      final query = filter.searchQuery!.toLowerCase();
      filteredPackages = filteredPackages
          .where((p) => p.name.toLowerCase().contains(query) ||
                      p.description.toLowerCase().contains(query))
          .toList();
    }

    return ApiResponse<List<BrandPackage>>.success(filteredPackages);
  }

  // Get onboarding status for tenant
  Future<ApiResponse<Map<String, dynamic>>> getTenantOnboardingStatus(String tenantId) async {
    try {
      final response = await _apiService.get(ApiEndpoints.tenantBrands(tenantId));

      if (response.success && response.data != null) {
        final brands = response.data['data'] as List? ?? [];
        final isOnboarded = brands.isNotEmpty;

        return ApiResponse<Map<String, dynamic>>.success({
          'is_onboarded': isOnboarded,
          'brand_count': brands.length,
          'last_updated': DateTime.now().toIso8601String(),
        });
      }

      return ApiResponse<Map<String, dynamic>>.error(response.message ?? 'Unknown error');
    } catch (e) {
      return ApiResponse<Map<String, dynamic>>.error('Failed to get onboarding status: $e');
    }
  }
}