import 'package:flutter/foundation.dart';
import '../../../core/models/api_response.dart';
import '../../../core/services/dio_api_service.dart';

/// Service for category and subcategory operations
class CategoryService {
  final DioApiService _apiService;

  CategoryService({required DioApiService apiService}) : _apiService = apiService;

  /// Get all categories
  Future<ApiResponse<List<CategoryModel>>> getCategories() async {
    try {
      if (kDebugMode) print('📂 CategoryService: Fetching categories');

      final response = await _apiService.get<List<CategoryModel>>(
        '/api/inventory/categories',
        fromJson: (json) {
          if (json is List) {
            return json
                .map((item) => CategoryModel.fromJson(item as Map<String, dynamic>))
                .toList();
          }
          return <CategoryModel>[];
        },
      );

      if (kDebugMode && response.success) {
        print('✅ CategoryService: Fetched ${response.data?.length ?? 0} categories');
      }

      return response;
    } catch (e) {
      if (kDebugMode) print('❌ CategoryService: Error fetching categories - $e');
      return ApiResponse<List<CategoryModel>>(
        success: false,
        message: 'Failed to fetch categories: ${e.toString()}',
      );
    }
  }

  /// Get subcategories for a category
  Future<ApiResponse<List<SubcategoryModel>>> getSubcategories(String categoryId) async {
    try {
      if (kDebugMode) print('📂 CategoryService: Fetching subcategories for category $categoryId');

      final response = await _apiService.get<List<SubcategoryModel>>(
        '/api/inventory/categories/$categoryId/subcategories',
        fromJson: (json) {
          if (json is List) {
            return json
                .map((item) => SubcategoryModel.fromJson(item as Map<String, dynamic>))
                .toList();
          }
          return <SubcategoryModel>[];
        },
      );

      if (kDebugMode && response.success) {
        print('✅ CategoryService: Fetched ${response.data?.length ?? 0} subcategories');
      }

      return response;
    } catch (e) {
      if (kDebugMode) print('❌ CategoryService: Error fetching subcategories - $e');
      return ApiResponse<List<SubcategoryModel>>(
        success: false,
        message: 'Failed to fetch subcategories: ${e.toString()}',
      );
    }
  }
}

/// Category model
class CategoryModel {
  final String id;
  final String name;
  final String? description;
  final bool isActive;

  CategoryModel({
    required this.id,
    required this.name,
    this.description,
    this.isActive = true,
  });

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'is_active': isActive,
    };
  }
}

/// Subcategory model
class SubcategoryModel {
  final String id;
  final String categoryId;
  final String name;
  final String? description;
  final bool isActive;

  SubcategoryModel({
    required this.id,
    required this.categoryId,
    required this.name,
    this.description,
    this.isActive = true,
  });

  factory SubcategoryModel.fromJson(Map<String, dynamic> json) {
    return SubcategoryModel(
      id: json['id'] as String,
      categoryId: json['category_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'category_id': categoryId,
      'name': name,
      'description': description,
      'is_active': isActive,
    };
  }
}
