import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/category_service.dart';
import './batch_ocr_provider.dart' as batch_ocr;

// ==========================================
// PROVIDERS
// ==========================================

/// Category service provider
final categoryServiceProvider = Provider<CategoryService>((ref) {
  final apiService = ref.watch(batch_ocr.apiServiceProvider);
  return CategoryService(apiService: apiService);
});

/// Categories provider
final categoriesProvider = FutureProvider<List<CategoryModel>>((ref) async {
  final service = ref.watch(categoryServiceProvider);
  final response = await service.getCategories();

  if (response.success && response.data != null) {
    return response.data!;
  }

  throw Exception(response.message ?? 'Failed to load categories');
});

/// Subcategories provider (family - requires categoryId)
final subcategoriesProvider = FutureProvider.family<List<SubcategoryModel>, String>((ref, categoryId) async {
  final service = ref.watch(categoryServiceProvider);
  final response = await service.getSubcategories(categoryId);

  if (response.success && response.data != null) {
    return response.data!;
  }

  throw Exception(response.message ?? 'Failed to load subcategories');
});

// ==========================================
// STATE NOTIFIER (for UI state management)
// ==========================================

class CategorySelectionState {
  final String? selectedCategoryId;
  final String? selectedSubcategoryId;
  final bool isLoadingCategories;
  final bool isLoadingSubcategories;
  final String? error;

  const CategorySelectionState({
    this.selectedCategoryId,
    this.selectedSubcategoryId,
    this.isLoadingCategories = false,
    this.isLoadingSubcategories = false,
    this.error,
  });

  CategorySelectionState copyWith({
    String? selectedCategoryId,
    String? selectedSubcategoryId,
    bool? isLoadingCategories,
    bool? isLoadingSubcategories,
    String? error,
  }) {
    return CategorySelectionState(
      selectedCategoryId: selectedCategoryId ?? this.selectedCategoryId,
      selectedSubcategoryId: selectedSubcategoryId ?? this.selectedSubcategoryId,
      isLoadingCategories: isLoadingCategories ?? this.isLoadingCategories,
      isLoadingSubcategories: isLoadingSubcategories ?? this.isLoadingSubcategories,
      error: error,
    );
  }

  // Clear subcategory when category changes
  CategorySelectionState copyWithNewCategory(String? categoryId) {
    return CategorySelectionState(
      selectedCategoryId: categoryId,
      selectedSubcategoryId: null, // Reset subcategory
      isLoadingCategories: isLoadingCategories,
      isLoadingSubcategories: false,
      error: null,
    );
  }
}

class CategorySelectionNotifier extends StateNotifier<CategorySelectionState> {
  CategorySelectionNotifier() : super(const CategorySelectionState());

  void selectCategory(String? categoryId) {
    if (kDebugMode) print('📂 Selected category: $categoryId');
    state = state.copyWithNewCategory(categoryId);
  }

  void selectSubcategory(String? subcategoryId) {
    if (kDebugMode) print('📂 Selected subcategory: $subcategoryId');
    state = state.copyWith(selectedSubcategoryId: subcategoryId);
  }

  void reset() {
    state = const CategorySelectionState();
  }
}

/// Category selection state provider
final categorySelectionProvider = StateNotifierProvider<CategorySelectionNotifier, CategorySelectionState>((ref) {
  return CategorySelectionNotifier();
});
