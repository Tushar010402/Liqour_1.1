/// BEST PRACTICES PROVIDER EXAMPLE
///
/// This is a comprehensive example showing how to integrate all modern features:
/// - DioApiService for HTTP calls
/// - CacheService for multi-level caching
/// - OfflineQueueService for offline support
/// - WebSocketProvider for real-time updates
/// - ExceptionHandler for error handling
/// - RetryStrategy for resilience
/// - Performance monitoring
library;

import 'package:flutter/foundation.dart';
import '../services/dio_api_service.dart';
import '../services/cache_service.dart';
import '../services/offline_queue_service.dart';
import '../providers/websocket_provider.dart';
import '../config/api_config.dart';
import '../exceptions/app_exception.dart';
import '../utils/exception_handler.dart';
import '../utils/retry_strategy.dart';
import '../utils/realtime_handler.dart';
import '../utils/app_logger.dart';
import '../utils/performance_monitor.dart';

/// Example Product Model
class ExampleProduct {
  final String id;
  final String name;
  final double price;
  final int stock;

  ExampleProduct({
    required this.id,
    required this.name,
    required this.price,
    required this.stock,
  });

  factory ExampleProduct.fromJson(Map<String, dynamic> json) {
    return ExampleProduct(
      id: json['id'] as String,
      name: json['name'] as String,
      price: (json['price'] as num).toDouble(),
      stock: json['stock'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'price': price,
    'stock': stock,
  };
}

/// BEST PRACTICES PROVIDER
///
/// Demonstrates industrial-grade patterns for:
/// - Loading data with cache-first strategy
/// - Handling errors gracefully
/// - Retry logic for network failures
/// - Offline queue for mutations
/// - Real-time updates via WebSocket
/// - Performance monitoring
class BestPracticesProductProvider extends ChangeNotifier {
  final DioApiService _apiService;
  final CacheService _cacheService;
  final OfflineQueueService _offlineQueue;
  final WebSocketProvider? _wsProvider;

  // State
  List<ExampleProduct> _products = [];
  bool _isLoading = false;
  bool _isRefreshing = false;
  AppException? _error;
  DateTime? _lastFetchTime;

  BestPracticesProductProvider({
    required DioApiService apiService,
    required CacheService cacheService,
    required OfflineQueueService offlineQueue,
    WebSocketProvider? wsProvider,
  })  : _apiService = apiService,
        _cacheService = cacheService,
        _offlineQueue = offlineQueue,
        _wsProvider = wsProvider {
    _initializeRealTimeUpdates();
  }

  // Getters
  List<ExampleProduct> get products => _products;
  bool get isLoading => _isLoading;
  bool get isRefreshing => _isRefreshing;
  AppException? get error => _error;
  bool get hasError => _error != null;
  bool get isEmpty => _products.isEmpty && !_isLoading;
  bool get hasData => _products.isNotEmpty;

  // ==================== BEST PRACTICE #1: Cache-First Loading ====================

  /// Load products with cache-first strategy
  Future<void> loadProducts({bool forceRefresh = false}) async {
    final operationId = 'load_products';
    PerformanceMonitor.startOperation(operationId);

    try {
      _setLoading(true);
      _clearError();

      final cacheKey = CacheKeys.productsList(null);

      // Try cache first (unless force refresh)
      if (!forceRefresh) {
        final cached = await _cacheService.get<List<ExampleProduct>>(cacheKey);
        if (cached != null) {
          _products = cached;
          _lastFetchTime = DateTime.now();
          notifyListeners();
          AppLogger.info('[BestPractices] ✅ Products loaded from cache');

          // Fetch fresh data in background
          _fetchProductsInBackground();
          return;
        }
      }

      // Cache miss or force refresh - fetch from API
      await _fetchProducts();

    } catch (e, stackTrace) {
      _handleError(e, stackTrace, 'loadProducts');
    } finally {
      _setLoading(false);
      PerformanceMonitor.endOperation(operationId, category: 'data_load');
    }
  }

  // ==================== BEST PRACTICE #2: Retry Strategy ====================

  /// Fetch products from API with retry logic
  Future<void> _fetchProducts() async {
    try {
      final products = await RetryStrategy.executeWithRetry<List<ExampleProduct>>(
        operation: () => _fetchProductsFromApi(),
        maxAttempts: 3,
        initialDelay: const Duration(seconds: 1),
        onRetry: (attempt, delay, error) {
          AppLogger.warning(
            '[BestPractices] Retry attempt $attempt after ${delay.inSeconds}s',
          );
        },
      );

      _products = products;
      _lastFetchTime = DateTime.now();

      // Cache the result
      await _cacheService.put(
        CacheKeys.productsList(null),
        products,
        ttl: CacheService.defaultTTL,
      );

      AppLogger.info('[BestPractices] ✅ Products fetched and cached');
      notifyListeners();

    } on NoInternetException {
      AppLogger.warning('[BestPractices] No internet - using cached data if available');
      rethrow;
    }
  }

  /// Fetch products from API (raw)
  Future<List<ExampleProduct>> _fetchProductsFromApi() async {
    final response = await _apiService.get<List<dynamic>>(
      ApiConfig.products,
      fromJson: (data) => data as List<dynamic>,
    );

    if (response.isSuccess && response.data != null) {
      return response.data!
          .map((e) => ExampleProduct.fromJson(e as Map<String, dynamic>))
          .toList();
    } else {
      throw BadRequestException(
        message: response.message ?? 'Failed to load products',
      );
    }
  }

  // ==================== BEST PRACTICE #3: Background Refresh ====================

  /// Fetch products in background (no loading state)
  Future<void> _fetchProductsInBackground() async {
    try {
      final products = await _fetchProductsFromApi();
      _products = products;
      _lastFetchTime = DateTime.now();

      // Update cache
      await _cacheService.put(
        CacheKeys.productsList(null),
        products,
        ttl: CacheService.defaultTTL,
      );

      notifyListeners();
      AppLogger.info('[BestPractices] ✅ Background refresh complete');
    } catch (e) {
      // Silent failure for background refresh
      AppLogger.debug('[BestPractices] Background refresh failed: $e');
    }
  }

  // ==================== BEST PRACTICE #4: Pull-to-Refresh ====================

  /// Refresh products (for pull-to-refresh)
  Future<void> refreshProducts() async {
    if (_isRefreshing) return;

    _isRefreshing = true;
    notifyListeners();

    try {
      await _fetchProducts();
    } catch (e, stackTrace) {
      _handleError(e, stackTrace, 'refreshProducts');
    } finally {
      _isRefreshing = false;
      notifyListeners();
    }
  }

  // ==================== BEST PRACTICE #5: Offline Support ====================

  /// Create product with offline queue support
  Future<void> createProduct(ExampleProduct product) async {
    try {
      _setLoading(true);
      _clearError();

      final response = await _apiService.post(
        ApiConfig.products,
        body: product.toJson(),
      );

      if (response.isSuccess) {
        // Success - add to local list
        _products.add(product);

        // Clear cache
        await _cacheService.clearByPrefix(CacheKeys.productsPrefix);

        AppLogger.info('[BestPractices] ✅ Product created successfully');
        notifyListeners();
      } else {
        throw BadRequestException(
          message: response.message ?? 'Failed to create product',
        );
      }

    } on NoInternetException {
      // Queue for later
      await _offlineQueue.queueRequest(
        method: 'POST',
        endpoint: ApiConfig.products,
        body: product.toJson(),
        type: RequestType.important,
        priority: 5,
      );

      // Optimistic update
      _products.add(product);
      notifyListeners();

      AppLogger.info('[BestPractices] 📥 Product queued for sync when online');

      // Re-throw so UI can show appropriate message
      rethrow;

    } catch (e, stackTrace) {
      _handleError(e, stackTrace, 'createProduct');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // ==================== BEST PRACTICE #6: Real-Time Updates ====================

  /// Initialize real-time updates via WebSocket
  void _initializeRealTimeUpdates() {
    if (_wsProvider == null) return;

    // Subscribe to inventory updates
    RealTimeHandler.subscribeToInventoryUpdates(
      _wsProvider,
      () => _handleRealTimeUpdate(),
    );

    AppLogger.info('[BestPractices] ✅ Real-time updates initialized');
  }

  /// Handle real-time inventory updates
  Future<void> _handleRealTimeUpdate() async {
    AppLogger.info('[BestPractices] 📡 Received real-time update - refreshing data');

    // Invalidate cache
    await _cacheService.clearByPrefix(CacheKeys.productsPrefix);

    // Refresh data in background
    await _fetchProductsInBackground();
  }

  // ==================== BEST PRACTICE #7: Error Handling ====================

  /// Handle errors with proper logging and user messaging
  void _handleError(dynamic error, StackTrace stackTrace, String context) {
    final appException = ExceptionHandler.handle(error, stackTrace);

    // Log the error
    ExceptionHandler.logException(appException, context: context);

    // Set error state
    _error = appException;
    notifyListeners();

    // Report to crash analytics (if configured)
    _reportError(appException, stackTrace, context);
  }

  /// Report error to analytics/crash reporting
  void _reportError(AppException exception, StackTrace stackTrace, String context) {
    // TODO: Integrate with Firebase Crashlytics or Sentry
    if (kDebugMode) {
      AppLogger.error('[BestPractices] Error in $context: ${exception.message}');
    }
  }

  // ==================== BEST PRACTICE #8: State Management ====================

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _clearError() {
    _error = null;
  }

  /// Retry after error
  Future<void> retry() async {
    await loadProducts(forceRefresh: true);
  }

  // ==================== BEST PRACTICE #9: Resource Management ====================

  @override
  void dispose() {
    // Clean up resources
    AppLogger.debug('[BestPractices] Disposing provider');
    super.dispose();
  }

  // ==================== BEST PRACTICE #10: Data Freshness ====================

  /// Check if data needs refresh
  bool get needsRefresh {
    if (_lastFetchTime == null) return true;

    final timeSinceLastFetch = DateTime.now().difference(_lastFetchTime!);
    return timeSinceLastFetch > const Duration(minutes: 5);
  }

  /// Auto-refresh if data is stale
  Future<void> autoRefreshIfNeeded() async {
    if (needsRefresh && !_isLoading) {
      await _fetchProductsInBackground();
    }
  }
}
