import 'package:flutter/foundation.dart';
import '../../../core/models/api_response.dart';
import '../../../core/services/dio_api_service.dart';
import '../models/saas_brand.dart'; // Import full SaasBrand models for pricing data

/// Service for SaaS brand catalog operations
class SaaSBrandService {
  final DioApiService _apiService;

  SaaSBrandService({required DioApiService apiService}) : _apiService = apiService;

  /// Get available SaaS brands
  Future<ApiResponse<List<SaaSBrandModel>>> getAvailableBrands({
    String? categoryId,
    String? subcategoryId,
    String? searchQuery,
  }) async {
    try {
      if (kDebugMode) print('🏷️ SaaSBrandService: Fetching available brands');

      // Build query parameters
      final queryParams = <String, dynamic>{};
      if (categoryId != null) queryParams['category_id'] = categoryId;
      if (subcategoryId != null) queryParams['subcategory_id'] = subcategoryId;
      if (searchQuery != null && searchQuery.isNotEmpty) {
        queryParams['search'] = searchQuery;
      }

      final response = await _apiService.get<List<SaaSBrandModel>>(
        '/api/saas/brands/public',
        queryParams: queryParams,
        fromJson: (json) {
          if (json is List) {
            return json
                .map((item) => SaaSBrandModel.fromJson(item as Map<String, dynamic>))
                .toList();
          }
          return <SaaSBrandModel>[];
        },
      );

      if (kDebugMode && response.success) {
        print('✅ SaaSBrandService: Fetched ${response.data?.length ?? 0} brands');
      }

      return response;
    } catch (e) {
      if (kDebugMode) print('❌ SaaSBrandService: Error fetching brands - $e');
      return ApiResponse<List<SaaSBrandModel>>(
        success: false,
        message: 'Failed to fetch brands: ${e.toString()}',
      );
    }
  }

  /// Get brand variants
  Future<ApiResponse<List<BrandVariantModel>>> getBrandVariants(String brandId) async {
    try {
      if (kDebugMode) print('🏷️ SaaSBrandService: Fetching variants for brand $brandId');

      final response = await _apiService.get<List<BrandVariantModel>>(
        '/api/saas/brands/$brandId/variants',
        fromJson: (json) {
          if (json is List) {
            return json
                .map((item) => BrandVariantModel.fromJson(item as Map<String, dynamic>))
                .toList();
          }
          return <BrandVariantModel>[];
        },
      );

      if (kDebugMode && response.success) {
        print('✅ SaaSBrandService: Fetched ${response.data?.length ?? 0} variants');
      }

      return response;
    } catch (e) {
      if (kDebugMode) print('❌ SaaSBrandService: Error fetching variants - $e');
      return ApiResponse<List<BrandVariantModel>>(
        success: false,
        message: 'Failed to fetch variants: ${e.toString()}',
      );
    }
  }

  /// Get variant by ID with full pricing data
  ///
  /// This fetches complete variant information including:
  /// - Pricing: buyingPrice, sellingPrice, mrp
  /// - Category and subcategory IDs
  /// - Product details: size, alcoholContent, hsnCode
  /// - Government duty information
  ///
  /// Used by Smart Matching Review to auto-fill pricing from matched variants.
  Future<ApiResponse<SaasBrandVariant>> getVariantById(String variantId) async {
    try {
      if (kDebugMode) print('🔍 SaaSBrandService: Fetching variant details - $variantId');

      final response = await _apiService.get<SaasBrandVariant>(
        '/api/saas/brand-variants/$variantId',
        fromJson: (json) => SaasBrandVariant.fromJson(json as Map<String, dynamic>),
      );

      if (kDebugMode && response.success && response.data != null) {
        final variant = response.data!;
        print('✅ SaaSBrandService: Variant fetched - ${variant.size}');
        print('   Pricing: Cost ₹${variant.buyingPrice}, Selling ₹${variant.sellingPrice}, MRP ₹${variant.mrp}');
      }

      return response;
    } catch (e) {
      if (kDebugMode) print('❌ SaaSBrandService: Error fetching variant - $e');
      return ApiResponse<SaasBrandVariant>(
        success: false,
        message: 'Failed to fetch variant details: ${e.toString()}',
      );
    }
  }
}

/// SaaS Brand model
class SaaSBrandModel {
  final String id;
  final String name;
  final String categoryId;
  final String? categoryName;
  final String? subcategoryId;
  final String? subcategoryName;
  final String? imageUrl;
  final bool isActive;

  SaaSBrandModel({
    required this.id,
    required this.name,
    required this.categoryId,
    this.categoryName,
    this.subcategoryId,
    this.subcategoryName,
    this.imageUrl,
    this.isActive = true,
  });

  factory SaaSBrandModel.fromJson(Map<String, dynamic> json) {
    return SaaSBrandModel(
      id: json['id'] as String,
      name: json['name'] as String,
      categoryId: json['category_id'] as String,
      categoryName: json['category_name'] as String?,
      subcategoryId: json['subcategory_id'] as String?,
      subcategoryName: json['subcategory_name'] as String?,
      imageUrl: json['image_url'] as String?,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'category_id': categoryId,
      'category_name': categoryName,
      'subcategory_id': subcategoryId,
      'subcategory_name': subcategoryName,
      'image_url': imageUrl,
      'is_active': isActive,
    };
  }
}

/// Brand Variant model
class BrandVariantModel {
  final String id;
  final String brandId;
  final String size;
  final String? sizeUnit;
  final double? alcoholContent;
  final String? packagingType;

  BrandVariantModel({
    required this.id,
    required this.brandId,
    required this.size,
    this.sizeUnit,
    this.alcoholContent,
    this.packagingType,
  });

  factory BrandVariantModel.fromJson(Map<String, dynamic> json) {
    return BrandVariantModel(
      id: json['id'] as String,
      brandId: json['brand_id'] as String,
      size: json['size'] as String,
      sizeUnit: json['size_unit'] as String?,
      alcoholContent: json['alcohol_content'] != null
          ? (json['alcohol_content'] as num).toDouble()
          : null,
      packagingType: json['packaging_type'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'brand_id': brandId,
      'size': size,
      'size_unit': sizeUnit,
      'alcohol_content': alcoholContent,
      'packaging_type': packagingType,
    };
  }
}
