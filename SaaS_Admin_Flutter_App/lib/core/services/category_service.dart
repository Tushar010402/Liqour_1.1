import 'dart:async';
import 'package:flutter/foundation.dart' hide Category;
import '../constants/api_endpoints.dart';
import '../models/category_model.dart';
import '../models/api_response.dart';
import 'api_service.dart';

class CategoryService {
  final ApiService _apiService;

  CategoryService(this._apiService);

  // Categories CRUD Operations

  /// Get all categories with their subcategories
  Future<ApiResponse<List<Category>>> getCategories({
    String? searchTerm,
    bool? isActive,
    String sortBy = 'name',
    bool sortAscending = true,
  }) async {
    try {
      final queryParams = <String, dynamic>{};

      if (searchTerm != null && searchTerm.isNotEmpty) {
        queryParams['search'] = searchTerm;
      }
      if (isActive != null) {
        queryParams['is_active'] = isActive.toString();
      }
      queryParams['sort_by'] = sortBy;
      queryParams['sort_order'] = sortAscending ? 'asc' : 'desc';

      final response = await _apiService.get<List<Category>>(
        ApiEndpoints.brandCategories,
        queryParameters: queryParams,
        fromJson: (data) {
          if (data is List) {
            return data
                .map((item) => Category.fromJson(item as Map<String, dynamic>))
                .toList();
          }
          return [];
        },
      );

      return response;
    } catch (e) {
      debugPrint('CategoryService.getCategories error: $e');
      return ApiResponse<List<Category>>.error(
          'Failed to load categories: ${e.toString()}');
    }
  }

  /// Get a specific category by ID
  Future<ApiResponse<Category>> getCategoryById(String categoryId) async {
    try {
      final response = await _apiService.get<Category>(
        ApiEndpoints.brandCategoryById(categoryId),
        fromJson: (data) => Category.fromJson(data as Map<String, dynamic>),
      );

      return response;
    } catch (e) {
      debugPrint('CategoryService.getCategoryById error: $e');
      return ApiResponse<Category>.error(
          'Failed to load category: ${e.toString()}');
    }
  }

  /// Create a new category
  Future<ApiResponse<Category>> createCategory(
      CreateCategoryRequest request) async {
    try {
      final response = await _apiService.post<Category>(
        ApiEndpoints.brandCategories,
        data: request.toJson(),
        fromJson: (data) => Category.fromJson(data as Map<String, dynamic>),
      );

      return response;
    } catch (e) {
      debugPrint('CategoryService.createCategory error: $e');
      return ApiResponse<Category>.error(
          'Failed to create category: ${e.toString()}');
    }
  }

  /// Update an existing category
  Future<ApiResponse<Category>> updateCategory(
      String categoryId, CreateCategoryRequest request) async {
    try {
      final response = await _apiService.put<Category>(
        ApiEndpoints.brandCategoryById(categoryId),
        data: request.toJson(),
        fromJson: (data) => Category.fromJson(data as Map<String, dynamic>),
      );

      return response;
    } catch (e) {
      debugPrint('CategoryService.updateCategory error: $e');
      return ApiResponse<Category>.error(
          'Failed to update category: ${e.toString()}');
    }
  }

  /// Delete a category
  Future<ApiResponse<bool>> deleteCategory(String categoryId) async {
    try {
      print(
          'DEBUG: CategoryService.deleteCategory called with ID: $categoryId');
      final endpoint = ApiEndpoints.brandCategoryById(categoryId);
      print('DEBUG: Delete endpoint: $endpoint');

      final response = await _apiService.delete<bool>(
        endpoint,
        fromJson: (data) {
          // Backend DELETE returns {"message": "success"} on success
          return true;
        },
      );

      print(
          'DEBUG: CategoryService delete response success: ${response.isSuccess}');
      print('DEBUG: CategoryService delete response error: ${response.error}');
      return response;
    } catch (e) {
      print('DEBUG: CategoryService.deleteCategory threw exception: $e');
      debugPrint('CategoryService.deleteCategory error: $e');
      return ApiResponse<bool>.error(
          'Failed to delete category: ${e.toString()}');
    }
  }

  // Subcategories CRUD Operations

  /// Get all subcategories for a specific category
  Future<ApiResponse<List<Subcategory>>> getSubcategories({
    String? categoryId,
    String? searchTerm,
    bool? isActive,
    String sortBy = 'name',
    bool sortAscending = true,
  }) async {
    try {
      final queryParams = <String, dynamic>{};

      if (categoryId != null) {
        queryParams['category_id'] = categoryId;
      }
      if (searchTerm != null && searchTerm.isNotEmpty) {
        queryParams['search'] = searchTerm;
      }
      if (isActive != null) {
        queryParams['is_active'] = isActive.toString();
      }
      queryParams['sort_by'] = sortBy;
      queryParams['sort_order'] = sortAscending ? 'asc' : 'desc';

      final response = await _apiService.get<List<Subcategory>>(
        ApiEndpoints.brandSubcategories,
        queryParameters: queryParams,
        fromJson: (data) {
          if (data is List) {
            return data
                .map((item) =>
                    Subcategory.fromJson(item as Map<String, dynamic>))
                .toList();
          }
          return [];
        },
      );

      return response;
    } catch (e) {
      debugPrint('CategoryService.getSubcategories error: $e');
      return ApiResponse<List<Subcategory>>.error(
          'Failed to load subcategories: ${e.toString()}');
    }
  }

  /// Get a specific subcategory by ID
  Future<ApiResponse<Subcategory>> getSubcategoryById(
      String subcategoryId) async {
    try {
      final response = await _apiService.get<Subcategory>(
        ApiEndpoints.brandSubcategoryById(subcategoryId),
        fromJson: (data) => Subcategory.fromJson(data as Map<String, dynamic>),
      );

      return response;
    } catch (e) {
      debugPrint('CategoryService.getSubcategoryById error: $e');
      return ApiResponse<Subcategory>.error(
          'Failed to load subcategory: ${e.toString()}');
    }
  }

  /// Create a new subcategory
  Future<ApiResponse<Subcategory>> createSubcategory(
      CreateSubcategoryRequest request) async {
    try {
      final response = await _apiService.post<Subcategory>(
        ApiEndpoints.brandSubcategories,
        data: request.toJson(),
        fromJson: (data) => Subcategory.fromJson(data as Map<String, dynamic>),
      );

      return response;
    } catch (e) {
      debugPrint('CategoryService.createSubcategory error: $e');
      return ApiResponse<Subcategory>.error(
          'Failed to create subcategory: ${e.toString()}');
    }
  }

  /// Update an existing subcategory
  Future<ApiResponse<Subcategory>> updateSubcategory(
      String subcategoryId, CreateSubcategoryRequest request) async {
    try {
      final response = await _apiService.put<Subcategory>(
        ApiEndpoints.brandSubcategoryById(subcategoryId),
        data: request.toJson(),
        fromJson: (data) => Subcategory.fromJson(data as Map<String, dynamic>),
      );

      return response;
    } catch (e) {
      debugPrint('CategoryService.updateSubcategory error: $e');
      return ApiResponse<Subcategory>.error(
          'Failed to update subcategory: ${e.toString()}');
    }
  }

  /// Delete a subcategory
  Future<ApiResponse<bool>> deleteSubcategory(String subcategoryId) async {
    try {
      print(
          'DEBUG: CategoryService.deleteSubcategory called with ID: $subcategoryId');
      final endpoint = ApiEndpoints.brandSubcategoryById(subcategoryId);
      print('DEBUG: Delete subcategory endpoint: $endpoint');

      final response = await _apiService.delete<bool>(
        endpoint,
        fromJson: (data) {
          // Backend DELETE returns {"message": "success"} on success
          return true;
        },
      );

      print(
          'DEBUG: CategoryService delete subcategory response success: ${response.isSuccess}');
      print(
          'DEBUG: CategoryService delete subcategory response error: ${response.error}');
      return response;
    } catch (e) {
      print('DEBUG: CategoryService.deleteSubcategory threw exception: $e');
      debugPrint('CategoryService.deleteSubcategory error: $e');
      return ApiResponse<bool>.error(
          'Failed to delete subcategory: ${e.toString()}');
    }
  }

  // Bulk operations for categories

  /// Bulk update category status (activate/deactivate)
  Future<ApiResponse<List<Category>>> bulkUpdateCategoryStatus(
    List<String> categoryIds,
    bool isActive,
  ) async {
    try {
      final results = <Category>[];

      for (final categoryId in categoryIds) {
        // Get current category
        final categoryResponse = await getCategoryById(categoryId);
        if (categoryResponse.isSuccess && categoryResponse.data != null) {
          final category = categoryResponse.data!;

          // Update with new status
          final updateRequest = CreateCategoryRequest(
            name: category.name,
            description: category.description,
            picture: category.picture,
            isActive: isActive,
            sortOrder: category.sortOrder,
          );

          final updateResponse =
              await updateCategory(categoryId, updateRequest);
          if (updateResponse.isSuccess && updateResponse.data != null) {
            results.add(updateResponse.data!);
          }
        }
      }

      return ApiResponse<List<Category>>.success(results);
    } catch (e) {
      debugPrint('CategoryService.bulkUpdateCategoryStatus error: $e');
      return ApiResponse<List<Category>>.error(
          'Failed to bulk update categories: ${e.toString()}');
    }
  }

  /// Get category statistics
  Future<ApiResponse<Map<String, dynamic>>> getCategoryStatistics() async {
    try {
      final categoriesResponse = await getCategories();
      final subcategoriesResponse = await getSubcategories();

      if (categoriesResponse.isSuccess && subcategoriesResponse.isSuccess) {
        final categories = categoriesResponse.data ?? [];
        final subcategories = subcategoriesResponse.data ?? [];

        final stats = {
          'total_categories': categories.length,
          'active_categories': categories.where((c) => c.isActive).length,
          'inactive_categories': categories.where((c) => !c.isActive).length,
          'total_subcategories': subcategories.length,
          'active_subcategories': subcategories.where((s) => s.isActive).length,
          'inactive_subcategories':
              subcategories.where((s) => !s.isActive).length,
          'categories_with_subcategories':
              categories.where((c) => c.subcategories.isNotEmpty).length,
          'categories_without_subcategories':
              categories.where((c) => c.subcategories.isEmpty).length,
        };

        return ApiResponse<Map<String, dynamic>>.success(stats);
      } else {
        return ApiResponse<Map<String, dynamic>>.error(
            'Failed to load category data for statistics');
      }
    } catch (e) {
      debugPrint('CategoryService.getCategoryStatistics error: $e');
      return ApiResponse<Map<String, dynamic>>.error(
          'Failed to get statistics: ${e.toString()}');
    }
  }
}
