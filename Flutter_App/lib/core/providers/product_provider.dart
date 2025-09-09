import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../../data/services/product_service.dart';
import '../../data/models/product_model.dart';
import '../../data/models/api_response_model.dart';
import '../utils/logger.dart';

/// Product service provider
final productServiceProvider = Provider<ProductService>((ref) {
  return ProductService();
});

/// Product list provider with pagination and filtering
final productsProvider = StateNotifierProvider.family.autoDispose<
    ProductsNotifier, 
    AsyncValue<PaginatedResponse<ProductModel>>,
    ProductFilters
>((ref, filters) {
  final service = ref.watch(productServiceProvider);
  return ProductsNotifier(service, filters);
});

/// Single product provider
final productProvider = FutureProvider.family.autoDispose<ProductModel, String>((ref, productId) async {
  final service = ref.watch(productServiceProvider);
  
  try {
    final response = await service.getProduct(productId);
    
    if (response.isSuccessful && response.hasData) {
      return response.data!;
    }
    
    throw Exception(response.message);
  } catch (error) {
    AppLogger.error('Failed to fetch product', error);
    throw error;
  }
});

/// Product categories provider
final categoriesProvider = FutureProvider.autoDispose<List<CategoryModel>>((ref) async {
  final service = ref.watch(productServiceProvider);
  
  try {
    final response = await service.getCategories();
    
    if (response.isSuccessful && response.hasData) {
      return response.data!;
    }
    
    throw Exception(response.message);
  } catch (error) {
    AppLogger.error('Failed to fetch categories', error);
    throw error;
  }
});

/// Featured products provider
final featuredProductsProvider = FutureProvider.autoDispose<List<ProductModel>>((ref) async {
  final service = ref.watch(productServiceProvider);
  
  try {
    final response = await service.getFeaturedProducts();
    
    if (response.isSuccessful && response.hasData) {
      return response.data!;
    }
    
    throw Exception(response.message);
  } catch (error) {
    AppLogger.error('Failed to fetch featured products', error);
    throw error;
  }
});

/// Product search provider
final productSearchProvider = StateNotifierProvider.autoDispose<
    ProductSearchNotifier, 
    AsyncValue<List<ProductModel>>
>((ref) {
  final service = ref.watch(productServiceProvider);
  return ProductSearchNotifier(service);
});

/// Product recommendations provider
final recommendationsProvider = FutureProvider.family.autoDispose<
    List<ProductModel>, 
    String
>((ref, productId) async {
  final service = ref.watch(productServiceProvider);
  
  try {
    final response = await service.getRecommendations(productId: productId);
    
    if (response.isSuccessful && response.hasData) {
      return response.data!;
    }
    
    throw Exception(response.message);
  } catch (error) {
    AppLogger.error('Failed to fetch recommendations', error);
    throw error;
  }
});

/// Product availability provider
final productAvailabilityProvider = FutureProvider.family.autoDispose<
    ProductAvailability, 
    ProductAvailabilityRequest
>((ref, request) async {
  final service = ref.watch(productServiceProvider);
  
  try {
    final response = await service.checkAvailability(
      productId: request.productId,
      quantity: request.quantity,
      location: request.location,
    );
    
    if (response.isSuccessful && response.hasData) {
      return response.data!;
    }
    
    throw Exception(response.message);
  } catch (error) {
    AppLogger.error('Failed to check availability', error);
    throw error;
  }
});

/// Product reviews provider
final productReviewsProvider = StateNotifierProvider.family.autoDispose<
    ProductReviewsNotifier,
    AsyncValue<PaginatedResponse<ProductReview>>,
    String
>((ref, productId) {
  final service = ref.watch(productServiceProvider);
  return ProductReviewsNotifier(service, productId);
});

/// Favorites provider
final favoritesProvider = StateNotifierProvider.autoDispose<
    FavoritesNotifier,
    AsyncValue<List<ProductModel>>
>((ref) {
  final service = ref.watch(productServiceProvider);
  return FavoritesNotifier(service);
});

/// Product price history provider
final priceHistoryProvider = FutureProvider.family.autoDispose<
    List<PriceHistory>,
    String
>((ref, productId) async {
  final service = ref.watch(productServiceProvider);
  
  try {
    final response = await service.getPriceHistory(productId);
    
    if (response.isSuccessful && response.hasData) {
      return response.data!;
    }
    
    throw Exception(response.message);
  } catch (error) {
    AppLogger.error('Failed to fetch price history', error);
    throw error;
  }
});

/// Product filters model
class ProductFilters {
  final int page;
  final int limit;
  final String? search;
  final String? category;
  final String? subCategory;
  final double? minPrice;
  final double? maxPrice;
  final bool? inStock;
  final String? sortBy;
  final String? sortOrder;
  final List<String>? tags;
  final String? location;

  const ProductFilters({
    this.page = 1,
    this.limit = 20,
    this.search,
    this.category,
    this.subCategory,
    this.minPrice,
    this.maxPrice,
    this.inStock,
    this.sortBy,
    this.sortOrder,
    this.tags,
    this.location,
  });

  ProductFilters copyWith({
    int? page,
    int? limit,
    String? search,
    String? category,
    String? subCategory,
    double? minPrice,
    double? maxPrice,
    bool? inStock,
    String? sortBy,
    String? sortOrder,
    List<String>? tags,
    String? location,
  }) {
    return ProductFilters(
      page: page ?? this.page,
      limit: limit ?? this.limit,
      search: search ?? this.search,
      category: category ?? this.category,
      subCategory: subCategory ?? this.subCategory,
      minPrice: minPrice ?? this.minPrice,
      maxPrice: maxPrice ?? this.maxPrice,
      inStock: inStock ?? this.inStock,
      sortBy: sortBy ?? this.sortBy,
      sortOrder: sortOrder ?? this.sortOrder,
      tags: tags ?? this.tags,
      location: location ?? this.location,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    
    return other is ProductFilters &&
        other.page == page &&
        other.limit == limit &&
        other.search == search &&
        other.category == category &&
        other.subCategory == subCategory &&
        other.minPrice == minPrice &&
        other.maxPrice == maxPrice &&
        other.inStock == inStock &&
        other.sortBy == sortBy &&
        other.sortOrder == sortOrder &&
        other.tags?.join(',') == tags?.join(',') &&
        other.location == location;
  }

  @override
  int get hashCode {
    return Object.hash(
      page,
      limit,
      search,
      category,
      subCategory,
      minPrice,
      maxPrice,
      inStock,
      sortBy,
      sortOrder,
      tags?.join(','),
      location,
    );
  }
}

/// Product availability request model
class ProductAvailabilityRequest {
  final String productId;
  final int quantity;
  final String? location;

  const ProductAvailabilityRequest({
    required this.productId,
    required this.quantity,
    this.location,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    
    return other is ProductAvailabilityRequest &&
        other.productId == productId &&
        other.quantity == quantity &&
        other.location == location;
  }

  @override
  int get hashCode => Object.hash(productId, quantity, location);
}

/// Products state notifier
class ProductsNotifier extends StateNotifier<AsyncValue<PaginatedResponse<ProductModel>>> {
  final ProductService _service;
  final ProductFilters _filters;

  ProductsNotifier(this._service, this._filters) : super(const AsyncValue.loading()) {
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    try {
      final response = await _service.getProducts(
        page: _filters.page,
        limit: _filters.limit,
        search: _filters.search,
        category: _filters.category,
        subCategory: _filters.subCategory,
        minPrice: _filters.minPrice,
        maxPrice: _filters.maxPrice,
        inStock: _filters.inStock,
        sortBy: _filters.sortBy,
        sortOrder: _filters.sortOrder,
        tags: _filters.tags,
        location: _filters.location,
      );

      if (response.isSuccessful && response.hasData) {
        state = AsyncValue.data(response.data!);
      } else {
        state = AsyncValue.error(response.message, StackTrace.current);
      }
    } catch (error, stackTrace) {
      AppLogger.error('Failed to load products', error, stackTrace);
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Refresh products
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    await _loadProducts();
  }

  /// Load more products (pagination)
  Future<void> loadMore() async {
    final currentState = state;
    if (currentState is AsyncData && currentState.hasValue) {
      final currentData = currentState.value!;
      
      // Check if more pages are available
      if (!currentData.hasMorePages) return;

      try {
        final response = await _service.getProducts(
          page: currentData.pagination.currentPage + 1,
          limit: _filters.limit,
          search: _filters.search,
          category: _filters.category,
          subCategory: _filters.subCategory,
          minPrice: _filters.minPrice,
          maxPrice: _filters.maxPrice,
          inStock: _filters.inStock,
          sortBy: _filters.sortBy,
          sortOrder: _filters.sortOrder,
          tags: _filters.tags,
          location: _filters.location,
        );

        if (response.isSuccessful && response.hasData) {
          final newData = response.data!;
          
          // Merge with existing data
          final mergedProducts = [...currentData.data, ...newData.data];
          final updatedData = currentData.copyWith(
            data: mergedProducts,
            pagination: newData.pagination,
          );
          
          state = AsyncValue.data(updatedData);
        }
      } catch (error, stackTrace) {
        AppLogger.error('Failed to load more products', error, stackTrace);
        // Don't update state on error, keep current data
      }
    }
  }
}

/// Product search state notifier
class ProductSearchNotifier extends StateNotifier<AsyncValue<List<ProductModel>>> {
  final ProductService _service;

  ProductSearchNotifier(this._service) : super(const AsyncValue.data([]));

  /// Search products
  Future<void> search(String query, {
    List<String>? categories,
    List<String>? tags,
    double? minPrice,
    double? maxPrice,
    bool? inStock,
    String? sortBy,
    String? sortOrder,
  }) async {
    if (query.trim().isEmpty) {
      state = const AsyncValue.data([]);
      return;
    }

    state = const AsyncValue.loading();

    try {
      final response = await _service.searchProducts(
        query: query,
        categories: categories,
        tags: tags,
        minPrice: minPrice,
        maxPrice: maxPrice,
        inStock: inStock,
        sortBy: sortBy,
        sortOrder: sortOrder,
      );

      if (response.isSuccessful && response.hasData) {
        state = AsyncValue.data(response.data!);
      } else {
        state = AsyncValue.error(response.message, StackTrace.current);
      }
    } catch (error, stackTrace) {
      AppLogger.error('Search failed', error, stackTrace);
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Clear search results
  void clear() {
    state = const AsyncValue.data([]);
  }
}

/// Product reviews state notifier
class ProductReviewsNotifier extends StateNotifier<AsyncValue<PaginatedResponse<ProductReview>>> {
  final ProductService _service;
  final String _productId;

  ProductReviewsNotifier(this._service, this._productId) : super(const AsyncValue.loading()) {
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    try {
      final response = await _service.getReviews(productId: _productId);

      if (response.isSuccessful && response.hasData) {
        state = AsyncValue.data(response.data!);
      } else {
        state = AsyncValue.error(response.message, StackTrace.current);
      }
    } catch (error, stackTrace) {
      AppLogger.error('Failed to load reviews', error, stackTrace);
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Add a new review
  Future<bool> addReview({
    required int rating,
    required String comment,
    List<String>? images,
  }) async {
    try {
      final response = await _service.createReview(
        productId: _productId,
        rating: rating,
        comment: comment,
        images: images,
      );

      if (response.isSuccessful) {
        // Refresh reviews list
        await _loadReviews();
        return true;
      }

      return false;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to add review', error, stackTrace);
      return false;
    }
  }

  /// Refresh reviews
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    await _loadReviews();
  }
}

/// Favorites state notifier
class FavoritesNotifier extends StateNotifier<AsyncValue<List<ProductModel>>> {
  final ProductService _service;

  FavoritesNotifier(this._service) : super(const AsyncValue.loading()) {
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    try {
      final response = await _service.getFavorites();

      if (response.isSuccessful && response.hasData) {
        state = AsyncValue.data(response.data!);
      } else {
        state = AsyncValue.error(response.message, StackTrace.current);
      }
    } catch (error, stackTrace) {
      AppLogger.error('Failed to load favorites', error, stackTrace);
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Add product to favorites
  Future<bool> addToFavorites(String productId) async {
    try {
      final response = await _service.addToFavorites(productId);

      if (response.isSuccessful) {
        // Refresh favorites list
        await _loadFavorites();
        return true;
      }

      return false;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to add to favorites', error, stackTrace);
      return false;
    }
  }

  /// Remove product from favorites
  Future<bool> removeFromFavorites(String productId) async {
    try {
      final response = await _service.removeFromFavorites(productId);

      if (response.isSuccessful) {
        // Update state immediately for better UX
        state.whenData((favorites) {
          final updatedFavorites = favorites.where((p) => p.id != productId).toList();
          state = AsyncValue.data(updatedFavorites);
        });
        return true;
      }

      return false;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to remove from favorites', error, stackTrace);
      return false;
    }
  }

  /// Check if product is in favorites
  bool isFavorite(String productId) {
    return state.whenOrNull(
      data: (favorites) => favorites.any((p) => p.id == productId),
    ) ?? false;
  }

  /// Refresh favorites
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    await _loadFavorites();
  }
}