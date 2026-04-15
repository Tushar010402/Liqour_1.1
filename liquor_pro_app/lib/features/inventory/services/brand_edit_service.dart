import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../../core/config/api_config.dart';
import '../../../core/services/auth_service.dart';
import '../models/saas_brand.dart';

/// Brand Edit Service - Loads SaaS Admin data for editing brand variants
///
/// This service fetches:
/// - SaaS Brand Categories (not tenant categories)
/// - SaaS Brand Subcategories (filtered by category)
/// - Category Sizes (sizes available for each category)
///
/// Used by EditBrandVariantScreen to match SaaS Admin's brand management UX
class BrandEditService {
  final AuthService _authService;

  BrandEditService({required AuthService authService})
      : _authService = authService;

  /// Get SaaS Brand Categories (created by SaaS Admin)
  /// These are different from tenant categories
  /// Called through inventory service (which proxies to SaaS service)
  Future<List<SaasBrandCategory>> getSaasBrandCategories() async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        throw Exception('No authentication token');
      }

      // Call inventory service endpoint (it proxies to SaaS service internally)
      final url = Uri.parse('${ApiConfig.baseUrl}/api/inventory/brand-categories');
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(ApiConfig.connectionTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Handle multiple response formats - backend may vary
        // Check for success in multiple ways (bool, string, or status code check)
        final isSuccess = data['success'] == true ||
            data['success'] == 'true' ||
            data['status'] == 'success' ||
            response.statusCode == 200;

        // Try multiple possible data keys
        List<dynamic>? categories;
        if (data['data'] != null && data['data'] is List) {
          categories = data['data'] as List<dynamic>;
        } else if (data['categories'] != null && data['categories'] is List) {
          categories = data['categories'] as List<dynamic>;
        } else if (data is List) {
          // Direct array response
          categories = data;
        }

        if (isSuccess && categories != null) {
          return categories
              .map((cat) => SaasBrandCategory.fromJson(cat as Map<String, dynamic>))
              .toList();
        } else {
          // Log the actual response for debugging
          print('⚠️ [BrandEditService] Unexpected response format: $data');
          throw Exception(data['message'] ?? 'Failed to load categories - unexpected format');
        }
      } else if (response.statusCode == 401) {
        throw Exception('Session expired. Please login again');
      } else {
        throw Exception('Failed to load categories: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error loading SaaS brand categories: $e');
    }
  }

  /// Get SaaS Brand Subcategories (optionally filtered by category)
  /// Called through inventory service (which proxies to SaaS service)
  Future<List<SaasBrandSubcategory>> getSaasBrandSubcategories({
    String? categoryId,
  }) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        throw Exception('No authentication token');
      }

      // Call inventory service endpoint (it proxies to SaaS service internally)
      var url = '${ApiConfig.baseUrl}/api/inventory/brand-subcategories';
      if (categoryId != null) {
        url += '?category_id=$categoryId';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(ApiConfig.connectionTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Handle multiple response formats - backend may vary
        final isSuccess = data['success'] == true ||
            data['success'] == 'true' ||
            data['status'] == 'success' ||
            response.statusCode == 200;

        // Try multiple possible data keys
        List<dynamic>? subcategories;
        if (data['data'] != null && data['data'] is List) {
          subcategories = data['data'] as List<dynamic>;
        } else if (data['subcategories'] != null && data['subcategories'] is List) {
          subcategories = data['subcategories'] as List<dynamic>;
        } else if (data is List) {
          subcategories = data;
        }

        if (isSuccess && subcategories != null) {
          return subcategories
              .map((sub) => SaasBrandSubcategory.fromJson(sub as Map<String, dynamic>))
              .toList();
        } else {
          print('⚠️ [BrandEditService] Unexpected subcategories response: $data');
          throw Exception(data['message'] ?? 'Failed to load subcategories - unexpected format');
        }
      } else if (response.statusCode == 401) {
        throw Exception('Session expired. Please login again');
      } else {
        throw Exception('Failed to load subcategories: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error loading SaaS brand subcategories: $e');
    }
  }

  /// Get Category Sizes (sizes defined for a specific category)
  /// Example: Whiskey → [180ml, 375ml, 750ml, 1L]
  ///          Beer → [330ml, 500ml, 650ml]
  /// Called through inventory service (which proxies to SaaS service)
  Future<List<String>> getCategorySizes({required String categoryId}) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        throw Exception('No authentication token');
      }

      // Call inventory service endpoint (it proxies to SaaS service internally)
      final url = Uri.parse(
        '${ApiConfig.baseUrl}/api/inventory/category-sizes?category_id=$categoryId',
      );

      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(ApiConfig.connectionTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final List<dynamic> sizes = data['data'] as List;
          // Extract size names from category size objects
          return sizes
              .map((sizeObj) => sizeObj['size']?.toString() ?? '')
              .where((size) => size.isNotEmpty)
              .toList();
        } else {
          // If no sizes defined, return common defaults
          return _getDefaultSizes(categoryId);
        }
      } else if (response.statusCode == 401) {
        throw Exception('Session expired. Please login again');
      } else {
        // If endpoint fails, return defaults
        return _getDefaultSizes(categoryId);
      }
    } catch (e) {
      print('⚠️ Error loading category sizes: $e');
      // Return defaults on error
      return _getDefaultSizes(categoryId);
    }
  }

  /// Fetch all SaaS category sizes as raw JSON objects.
  /// Returns list of maps with keys: category_id, size_name, display_name, etc.
  /// Used by AI Stock Setup to show predefined sizes when tenant has no products.
  Future<List<Map<String, dynamic>>> getCategorySizesRaw() async {
    try {
      final token = await _authService.getToken();
      if (token == null) return [];

      final url = Uri.parse('${ApiConfig.baseUrl}/api/inventory/category-sizes');
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(ApiConfig.connectionTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return (data['data'] as List).cast<Map<String, dynamic>>();
        }
      }
      return [];
    } catch (e) {
      print('⚠️ Error loading raw category sizes: $e');
      return [];
    }
  }

  /// Get default sizes if API fails or no sizes defined
  List<String> _getDefaultSizes(String categoryId) {
    // Common default sizes
    return [
      '30ml',
      '50ml',
      '60ml',
      '90ml',
      '180ml',
      '330ml',
      '375ml',
      '500ml',
      '650ml',
      '750ml',
      '1L',
      '1.5L',
      '2L',
    ];
  }

  /// Get brand info by ID (for displaying brand name in edit screen)
  Future<SaasBrand?> getBrandById(String brandId) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        throw Exception('No authentication token');
      }

      final url = Uri.parse('${ApiConfig.baseUrl}/api/saas/brands/$brandId');
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(ApiConfig.connectionTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return SaasBrand.fromJson(data['data'] as Map<String, dynamic>);
        }
      }
      return null;
    } catch (e) {
      print('⚠️ Error loading brand: $e');
      return null;
    }
  }

  /// Update brand variant (product)
  Future<bool> updateBrandVariant({
    required String productId,
    required Map<String, dynamic> updateData,
  }) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        print('❌ [BrandEditService] No authentication token');
        throw Exception('No authentication token');
      }

      final url = Uri.parse('${ApiConfig.baseUrl}/api/inventory/products/$productId');
      print('🔄 [BrandEditService] PUT $url');
      print('📦 [BrandEditService] Payload: ${json.encode(updateData)}');

      final response = await http.put(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode(updateData),
      ).timeout(ApiConfig.connectionTimeout);

      print('📥 [BrandEditService] Response status: ${response.statusCode}');
      print('📥 [BrandEditService] Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // API returns updated product directly OR {success: true}
        // Check for 'id' field (product returned) or 'success' field
        final success = data['id'] != null || data['success'] == true;
        print('✅ [BrandEditService] Update success: $success');
        return success;
      } else if (response.statusCode == 401) {
        print('❌ [BrandEditService] 401 Unauthorized');
        throw Exception('Session expired. Please login again');
      } else {
        final data = json.decode(response.body);
        print('❌ [BrandEditService] Error: ${data['message']}');
        throw Exception(data['message'] ?? 'Failed to update brand variant');
      }
    } catch (e) {
      print('❌ [BrandEditService] Exception: $e');
      throw Exception('Error updating brand variant: $e');
    }
  }
}
