import '../providers/websocket_provider.dart';
import '../services/websocket_service.dart';
import '../services/cache_service.dart';
import '../utils/app_logger.dart';

/// Cache Invalidation Service
///
/// Listens to WebSocket events and invalidates relevant caches
/// to ensure data consistency across the app
class CacheInvalidationService {
  final CacheService _cacheService;
  final WebSocketProvider _wsProvider;

  CacheInvalidationService({
    required CacheService cacheService,
    required WebSocketProvider wsProvider,
  })  : _cacheService = cacheService,
        _wsProvider = wsProvider {
    _setupInvalidationHandlers();
  }

  /// Setup cache invalidation based on real-time events
  void _setupInvalidationHandlers() {
    AppLogger.info('[CacheInvalidation] Setting up cache invalidation handlers');

    // Inventory updates
    _wsProvider.subscribe(
      WebSocketChannels.inventory,
      onEvent: _handleInventoryEvent,
    );

    // Sales updates
    _wsProvider.subscribe(
      WebSocketChannels.sales,
      onEvent: _handleSalesEvent,
    );

    // Cashflow updates
    _wsProvider.subscribe(
      WebSocketChannels.cashflow,
      onEvent: _handleCashflowEvent,
    );

    // Dashboard updates
    _wsProvider.subscribe(
      WebSocketChannels.dashboard,
      onEvent: _handleDashboardEvent,
    );
  }

  /// Handle inventory events
  void _handleInventoryEvent(Map<String, dynamic> event) {
    final eventType = event['event_type'] as String?;
    final data = event['data'] as Map<String, dynamic>?;

    switch (eventType) {
      case KafkaEventTypes.inventoryUpdated:
        final productId = data?['product_id'] as String?;
        final shopId = data?['shop_id'] as String?;

        if (productId != null) {
          _invalidateProduct(productId);
        }
        if (shopId != null) {
          _invalidateProductsList(shopId);
        }

        // Also invalidate dashboard stats
        _invalidateDashboard(shopId);

        AppLogger.info('[CacheInvalidation] 📦 Invalidated inventory cache');
        break;

      case KafkaEventTypes.stockLow:
        // Invalidate product and dashboard
        final productId = data?['product_id'] as String?;
        if (productId != null) {
          _invalidateProduct(productId);
        }
        _invalidateDashboard(null);

        AppLogger.warning('[CacheInvalidation] ⚠️ Low stock - invalidated cache');
        break;

      default:
        // For unknown events, invalidate all inventory cache
        _cacheService.clearByPrefix(CacheKeys.productsPrefix);
    }
  }

  /// Handle sales events
  void _handleSalesEvent(Map<String, dynamic> event) {
    final eventType = event['event_type'] as String?;
    final data = event['data'] as Map<String, dynamic>?;

    switch (eventType) {
      case KafkaEventTypes.saleCreated:
      case KafkaEventTypes.saleUpdated:
        final saleId = data?['sale_id'] as String?;
        final shopId = data?['shop_id'] as String?;

        if (saleId != null) {
          _invalidateSale(saleId);
        }
        if (shopId != null) {
          _invalidateSalesList(shopId, null);
        }

        // Invalidate dashboard and inventory (stock changed)
        _invalidateDashboard(shopId);
        _invalidateProductsList(shopId);

        AppLogger.info('[CacheInvalidation] 💰 Invalidated sales cache');
        break;

      default:
        _cacheService.clearByPrefix(CacheKeys.salesPrefix);
    }
  }

  /// Handle cashflow events
  void _handleCashflowEvent(Map<String, dynamic> event) {
    final eventType = event['event_type'] as String?;
    final data = event['data'] as Map<String, dynamic>?;

    switch (eventType) {
      case KafkaEventTypes.paymentProcessed:
        final shopId = data?['shop_id'] as String?;

        // Invalidate cash balance and requests
        _invalidateCashBalance(shopId);
        _invalidateCashRequests();

        // Invalidate dashboard
        _invalidateDashboard(shopId);

        AppLogger.info('[CacheInvalidation] 💳 Invalidated cash cache');
        break;

      default:
        _cacheService.clearByPrefix(CacheKeys.cashPrefix);
    }
  }

  /// Handle dashboard events
  void _handleDashboardEvent(Map<String, dynamic> event) {
    final data = event['data'] as Map<String, dynamic>?;
    final shopId = data?['shop_id'] as String?;

    // Invalidate dashboard stats
    _invalidateDashboard(shopId);

    AppLogger.info('[CacheInvalidation] 📊 Invalidated dashboard cache');
  }

  // ========== Specific invalidation methods ==========

  void _invalidateProduct(String productId) {
    _cacheService.remove(CacheKeys.productDetail(productId));
  }

  void _invalidateProductsList(String? shopId) {
    _cacheService.remove(CacheKeys.productsList(shopId));
    _cacheService.remove(CacheKeys.productsList(null)); // Also clear "all shops" list
  }

  void _invalidateBrand(String brandId) {
    _cacheService.remove(CacheKeys.brandDetail(brandId));
    _cacheService.remove(CacheKeys.brandVariants(brandId));
    _cacheService.remove(CacheKeys.brandsList);
  }

  void _invalidateSale(String saleId) {
    _cacheService.remove(CacheKeys.saleDetail(saleId));
  }

  void _invalidateSalesList(String? shopId, String? date) {
    _cacheService.remove(CacheKeys.salesList(shopId, date));
    _cacheService.remove(CacheKeys.salesList(null, date)); // Also clear "all shops" list
  }

  void _invalidateDashboard(String? shopId) {
    _cacheService.remove(CacheKeys.dashboardStats(shopId));
    _cacheService.remove(CacheKeys.dashboardStats(null)); // Also clear "all shops" stats
  }

  void _invalidateCashBalance(String? shopId) {
    _cacheService.remove(CacheKeys.cashBalance(shopId));
    _cacheService.remove(CacheKeys.cashBalance(null)); // Also clear "all shops" balance
  }

  void _invalidateCashRequests() {
    _cacheService.remove(CacheKeys.cashRequests);
  }

  // ========== Public invalidation API ==========

  /// Manually invalidate product cache
  Future<void> invalidateProduct(String productId) async {
    _invalidateProduct(productId);
    _invalidateProductsList(null);
  }

  /// Manually invalidate all products
  Future<void> invalidateAllProducts() async {
    await _cacheService.clearByPrefix(CacheKeys.productsPrefix);
  }

  /// Manually invalidate brand cache
  Future<void> invalidateBrand(String brandId) async {
    _invalidateBrand(brandId);
  }

  /// Manually invalidate all brands
  Future<void> invalidateAllBrands() async {
    await _cacheService.clearByPrefix(CacheKeys.brandsPrefix);
  }

  /// Manually invalidate sales
  Future<void> invalidateAllSales() async {
    await _cacheService.clearByPrefix(CacheKeys.salesPrefix);
  }

  /// Manually invalidate dashboard
  Future<void> invalidateAllDashboard() async {
    await _cacheService.clearByPrefix(CacheKeys.dashboardPrefix);
  }

  /// Manually invalidate all cache
  Future<void> invalidateAll() async {
    await _cacheService.clear();
    AppLogger.info('[CacheInvalidation] 🗑️ Invalidated ALL cache');
  }
}
