import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/saas_brand_service.dart';
import './batch_ocr_provider.dart' as batch_ocr;

// ==========================================
// PROVIDERS
// ==========================================

/// SaaS Brand service provider
final saasBrandServiceProvider = Provider<SaaSBrandService>((ref) {
  final apiService = ref.watch(batch_ocr.apiServiceProvider);
  return SaaSBrandService(apiService: apiService);
});

/// Available brands provider (filtered by category/subcategory)
final availableBrandsProvider = FutureProvider.family<List<SaaSBrandModel>, BrandFilterParams>((ref, params) async {
  final service = ref.watch(saasBrandServiceProvider);
  final response = await service.getAvailableBrands(
    categoryId: params.categoryId,
    subcategoryId: params.subcategoryId,
    searchQuery: params.searchQuery,
  );

  if (response.success && response.data != null) {
    return response.data!;
  }

  throw Exception(response.message ?? 'Failed to load brands');
});

/// Brand variants provider
final brandVariantsProvider = FutureProvider.family<List<BrandVariantModel>, String>((ref, brandId) async {
  final service = ref.watch(saasBrandServiceProvider);
  final response = await service.getBrandVariants(brandId);

  if (response.success && response.data != null) {
    return response.data!;
  }

  throw Exception(response.message ?? 'Failed to load variants');
});

// ==========================================
// HELPER CLASSES
// ==========================================

/// Parameters for filtering brands
class BrandFilterParams {
  final String? categoryId;
  final String? subcategoryId;
  final String? searchQuery;

  const BrandFilterParams({
    this.categoryId,
    this.subcategoryId,
    this.searchQuery,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BrandFilterParams &&
        other.categoryId == categoryId &&
        other.subcategoryId == subcategoryId &&
        other.searchQuery == searchQuery;
  }

  @override
  int get hashCode => Object.hash(categoryId, subcategoryId, searchQuery);
}

// ==========================================
// STATE NOTIFIER
// ==========================================

class BrandSelectionState {
  final String? selectedBrandId;
  final String? searchQuery;
  final bool isLoading;
  final String? error;

  const BrandSelectionState({
    this.selectedBrandId,
    this.searchQuery,
    this.isLoading = false,
    this.error,
  });

  BrandSelectionState copyWith({
    String? selectedBrandId,
    String? searchQuery,
    bool? isLoading,
    String? error,
  }) {
    return BrandSelectionState(
      selectedBrandId: selectedBrandId ?? this.selectedBrandId,
      searchQuery: searchQuery ?? this.searchQuery,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class BrandSelectionNotifier extends StateNotifier<BrandSelectionState> {
  BrandSelectionNotifier() : super(const BrandSelectionState());

  void selectBrand(String? brandId) {
    if (kDebugMode) print('🏷️ Selected brand: $brandId');
    state = state.copyWith(selectedBrandId: brandId);
  }

  void setSearchQuery(String? query) {
    if (kDebugMode) print('🔍 Search query: $query');
    state = state.copyWith(searchQuery: query);
  }

  void reset() {
    state = const BrandSelectionState();
  }
}

/// Brand selection state provider
final brandSelectionProvider = StateNotifierProvider<BrandSelectionNotifier, BrandSelectionState>((ref) {
  return BrandSelectionNotifier();
});
