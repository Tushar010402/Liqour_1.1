import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../../core/models/api_response.dart';
import '../../../core/services/dio_api_service.dart';
import '../models/saas_brand.dart';
import '../models/brand.dart';
import '../models/product.dart';
import '../models/brand_metadata.dart';

/// Brand Onboarding Service - API client for SaaS brand onboarding
class BrandOnboardingService {
  final DioApiService _apiService;

  BrandOnboardingService(this._apiService);

  /// Get available SaaS brand templates for onboarding
  Future<ApiResponse<List<SaasBrand>>> getAvailableBrands({String? shopId}) async {
    final response = await _apiService.get<List<SaasBrand>>(
      '/api/inventory/saas-brands/available',
      queryParams: shopId != null ? {'shop_id': shopId} : null,
      fromJson: (data) {
        if (data is List) {
          return data
              .map((json) => SaasBrand.fromJson(json as Map<String, dynamic>))
              .toList();
        }

        // Backend sends: {"message": "...", "data": [...], "count": 8}
        if (data is Map<String, dynamic>) {
          // Try 'data' key first (new backend format)
          if (data['data'] is List) {
            return (data['data'] as List)
                .map((json) => SaasBrand.fromJson(json as Map<String, dynamic>))
                .toList();
          }

          // Fallback to 'brands' key (legacy format)
          if (data['brands'] is List) {
            return (data['brands'] as List)
                .map((json) => SaasBrand.fromJson(json as Map<String, dynamic>))
                .toList();
          }
        }

        return [];
      },
    );

    return response;
  }

  /// Onboard selected brands to tenant inventory with initial stock quantities
  Future<ApiResponse<OnboardingResult>> onboardBrands({
    required List<String> brandIds,
    required List<String> variantIds,
    String? shopId,
    Map<String, int>? variantStockQuantities,
  }) async {
    // Get tenant ID from DioApiService
    final tenantId = await _apiService.getTenantId();

    if (tenantId == null || tenantId.isEmpty) {
      return ApiResponse<OnboardingResult>(
        success: false,
        message: 'Tenant ID is required for onboarding',
      );
    }

    // Build request body
    final requestBody = <String, dynamic>{
      'brand_ids': brandIds,
      'variant_ids': variantIds,
      'tenant_id': tenantId,
    };

    // Add shop_id if provided
    if (shopId != null && shopId.isNotEmpty) {
      requestBody['shop_id'] = shopId;
    }

    // Add brand_variants with stock quantities if provided
    if (variantStockQuantities != null && variantStockQuantities.isNotEmpty) {
      final brandVariants = variantStockQuantities.entries
          .where((e) => e.value > 0) // Only include variants with stock > 0
          .map((e) => {
                'saas_brand_variant_id': e.key,
                'initial_stock': e.value,
              })
          .toList();

      if (brandVariants.isNotEmpty) {
        requestBody['brand_variants'] = brandVariants;
      }
    }

    final response = await _apiService.post<OnboardingResult>(
      '/api/inventory/saas-brands/onboard',
      body: requestBody,
      fromJson: (data) {
        return OnboardingResult.fromJson(data as Map<String, dynamic>);
      },
    );

    return response;
  }

  /// Get onboarded products (from SaaS templates)
  Future<ApiResponse<List<Product>>> getOnboardedProducts() async {
    final response = await _apiService.get<List<Product>>(
      '/api/inventory/saas-brands/onboarded',
      fromJson: (data) {
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
    final response = await _apiService.get<List<Brand>>(
      '/api/inventory/brands/custom',
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

  /// Get brand packages (Starter, Premium, Full)
  Future<ApiResponse<List<BrandPackage>>> getBrandPackages() async {
    final response = await _apiService.get<List<BrandPackage>>(
      '/api/super-admin/brands/packages',
      fromJson: (data) {
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

  /// Download Excel template for bulk brand import
  Future<ApiResponse<String>> downloadBrandTemplate() async {
    try {
      // Get app's temporary directory
      final tempDir = await getTemporaryDirectory();
      final savePath = '${tempDir.path}/brand_template.xlsx';

      // Delete existing file if it exists
      final file = File(savePath);
      if (await file.exists()) {
        await file.delete();
      }

      final response = await _apiService.downloadFile(
        '/api/super-admin/brands/template/download',
        savePath,
      );

      return response;
    } catch (e) {
      return ApiResponse(
        success: false,
        message: 'Failed to download template: $e',
      );
    }
  }

  /// Upload Excel file for bulk brand import with shop support
  Future<ApiResponse<BrandImportResult>> uploadBrandExcel(
    String filePath, {
    String? shopId,
    String? shopName,
  }) async {
    try {
      // Build additional form data for shop context
      final additionalData = <String, dynamic>{};
      if (shopId != null) {
        additionalData['shop_id'] = shopId;
      }
      if (shopName != null) {
        additionalData['shop_name'] = shopName;
      }

      final response = await _apiService.uploadFile<BrandImportResult>(
        '/api/super-admin/brands/bulk-import',
        filePath,
        fromJson: (data) {
          if (data is Map<String, dynamic>) {
            return BrandImportResult.fromJson(data);
          }
          throw Exception('Invalid response format');
        },
        additionalData: additionalData,
      );

      return response;
    } catch (e) {
      return ApiResponse(
        success: false,
        message: 'Failed to upload Excel file: $e',
      );
    }
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

/// Get brand metadata (categories, subcategories, common sizes) for custom brand creation
Future<ApiResponse<BrandMetadata>> getBrandMetadata(DioApiService apiService) async {
  final response = await apiService.get<BrandMetadata>(
    '/api/inventory/saas-brands/metadata',
    fromJson: (data) {
      if (data is Map<String, dynamic>) {
        // Backend sends: {"message": "...", "data": {...}}
        final metadataJson = data['data'] as Map<String, dynamic>? ?? data;
        return BrandMetadata.fromJson(metadataJson);
      }

      return BrandMetadata(categories: [], subcategories: [], commonSizes: []);
    },
  );

  return response;
}

/// Brand Import Result - Response from bulk brand import
class BrandImportResult {
  final int totalRows;
  final int successCount;
  final int errorCount;
  final List<BrandImportError> errors;
  final List<ImportedBrandData> importedBrands;
  final String message;

  BrandImportResult({
    required this.totalRows,
    required this.successCount,
    required this.errorCount,
    required this.errors,
    required this.importedBrands,
    required this.message,
  });

  factory BrandImportResult.fromJson(Map<String, dynamic> json) {
    return BrandImportResult(
      totalRows: json['total_rows'] ?? 0,
      successCount: json['success_count'] ?? 0,
      errorCount: json['error_count'] ?? 0,
      errors: (json['errors'] as List<dynamic>?)
              ?.map((e) => BrandImportError.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      importedBrands: (json['imported_brands'] as List<dynamic>?)
              ?.map((e) => ImportedBrandData.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      message: json['message'] ?? '',
    );
  }
}

/// Brand Import Error - Individual row error
class BrandImportError {
  final int row;
  final String message;

  BrandImportError({
    required this.row,
    required this.message,
  });

  factory BrandImportError.fromJson(Map<String, dynamic> json) {
    return BrandImportError(
      row: json['row'] ?? 0,
      message: json['message'] ?? '',
    );
  }
}

/// Imported Brand Data - Parsed data from Excel
class ImportedBrandData {
  final String brandName;
  final String description;
  final String category;
  final String subcategory;
  final String size;
  final String alcoholContent;
  final String mrp;
  final String governmentDuty;
  final String buyingPrice;
  final String sellingPrice;
  final String barcode;
  final String originCountry;
  final String notes;

  ImportedBrandData({
    required this.brandName,
    required this.description,
    required this.category,
    required this.subcategory,
    required this.size,
    required this.alcoholContent,
    required this.mrp,
    required this.governmentDuty,
    required this.buyingPrice,
    required this.sellingPrice,
    required this.barcode,
    required this.originCountry,
    required this.notes,
  });

  factory ImportedBrandData.fromJson(Map<String, dynamic> json) {
    return ImportedBrandData(
      brandName: json['brand_name'] ?? '',
      description: json['description'] ?? '',
      category: json['category'] ?? '',
      subcategory: json['subcategory'] ?? '',
      size: json['size'] ?? '',
      alcoholContent: json['alcohol_content'] ?? '',
      mrp: json['mrp'] ?? '',
      governmentDuty: json['government_duty'] ?? '',
      buyingPrice: json['buying_price'] ?? '',
      sellingPrice: json['selling_price'] ?? '',
      barcode: json['barcode'] ?? '',
      originCountry: json['origin_country'] ?? '',
      notes: json['notes'] ?? '',
    );
  }
}
