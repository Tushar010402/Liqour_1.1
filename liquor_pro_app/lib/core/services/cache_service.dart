import 'dart:async';
import 'package:hive_flutter/hive_flutter.dart';
import '../utils/app_logger.dart';

/// Cache Entry Model
class CacheEntry {
  final dynamic data;
  final DateTime timestamp;
  final Duration ttl;

  CacheEntry({
    required this.data,
    required this.timestamp,
    required this.ttl,
  });

  bool get isExpired => DateTime.now().difference(timestamp) > ttl;

  Map<String, dynamic> toJson() => {
    'data': data,
    'timestamp': timestamp.toIso8601String(),
    'ttl_seconds': ttl.inSeconds,
  };

  factory CacheEntry.fromJson(Map<String, dynamic> json) {
    return CacheEntry(
      data: json['data'],
      timestamp: DateTime.parse(json['timestamp'] as String),
      ttl: Duration(seconds: json['ttl_seconds'] as int),
    );
  }
}

/// Multi-Level Cache Service
///
/// Implements a 3-tier caching strategy:
/// 1. Memory Cache (L1) - Fastest, volatile
/// 2. Disk Cache (L2) - Persistent, slower
/// 3. HTTP Cache - Network layer caching via Dio interceptor
class CacheService {
  static final CacheService _instance = CacheService._internal();
  factory CacheService() => _instance;
  CacheService._internal();

  // Memory cache (L1) - Fast, volatile
  final Map<String, CacheEntry> _memoryCache = {};

  // Disk cache (L2) - Persistent
  Box? _diskCache;
  bool _isInitialized = false;

  // Default TTL values
  static const Duration defaultTTL = Duration(minutes: 5);
  static const Duration shortTTL = Duration(minutes: 1);
  static const Duration mediumTTL = Duration(minutes: 15);
  static const Duration longTTL = Duration(hours: 1);

  /// Initialize cache service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await Hive.initFlutter();
      _diskCache = await Hive.openBox('app_cache');
      _isInitialized = true;
      AppLogger.info('✅ [CacheService] Initialized with multi-level caching');

      // Start cache cleanup timer
      _startCacheCleanup();
    } catch (e) {
      AppLogger.error('[CacheService] Failed to initialize: $e');
      rethrow;
    }
  }

  /// Get from cache (checks L1, then L2)
  Future<T?> get<T>(String key) async {
    _ensureInitialized();

    // Try L1 (Memory) first
    final memoryEntry = _memoryCache[key];
    if (memoryEntry != null && !memoryEntry.isExpired) {
      AppLogger.debug('[CacheService] ✅ L1 HIT: $key');
      return memoryEntry.data as T?;
    } else if (memoryEntry != null && memoryEntry.isExpired) {
      _memoryCache.remove(key);
    }

    // Try L2 (Disk)
    try {
      final diskData = _diskCache?.get(key);
      if (diskData != null) {
        final entry = CacheEntry.fromJson(diskData as Map<String, dynamic>);
        if (!entry.isExpired) {
          AppLogger.debug('[CacheService] ✅ L2 HIT: $key');

          // Promote to L1
          _memoryCache[key] = entry;
          return entry.data as T?;
        } else {
          // Expired, remove from disk
          await _diskCache?.delete(key);
        }
      }
    } catch (e) {
      AppLogger.warning('[CacheService] L2 read error for $key: $e');
    }

    AppLogger.debug('[CacheService] ❌ MISS: $key');
    return null;
  }

  /// Put in cache (writes to both L1 and L2)
  Future<void> put(
    String key,
    dynamic data, {
    Duration ttl = defaultTTL,
    bool memoryOnly = false,
  }) async {
    _ensureInitialized();

    final entry = CacheEntry(
      data: data,
      timestamp: DateTime.now(),
      ttl: ttl,
    );

    // Write to L1 (Memory)
    _memoryCache[key] = entry;

    // Write to L2 (Disk) unless memory-only
    if (!memoryOnly) {
      try {
        await _diskCache?.put(key, entry.toJson());
        AppLogger.debug('[CacheService] ✅ WRITE: $key (L1 + L2)');
      } catch (e) {
        AppLogger.warning('[CacheService] L2 write error for $key: $e');
      }
    } else {
      AppLogger.debug('[CacheService] ✅ WRITE: $key (L1 only)');
    }
  }

  /// Remove from cache
  Future<void> remove(String key) async {
    _ensureInitialized();

    _memoryCache.remove(key);
    await _diskCache?.delete(key);
    AppLogger.debug('[CacheService] 🗑️ REMOVE: $key');
  }

  /// Clear all cache
  Future<void> clear() async {
    _ensureInitialized();

    _memoryCache.clear();
    await _diskCache?.clear();
    AppLogger.info('[CacheService] 🗑️ CLEARED all caches');
  }

  /// Clear cache by prefix (e.g., 'products_', 'sales_')
  Future<void> clearByPrefix(String prefix) async {
    _ensureInitialized();

    // Clear from memory
    _memoryCache.removeWhere((key, _) => key.startsWith(prefix));

    // Clear from disk
    final keysToDelete = <String>[];
    for (final key in _diskCache?.keys ?? <String>[]) {
      if (key.toString().startsWith(prefix)) {
        keysToDelete.add(key as String);
      }
    }

    for (final key in keysToDelete) {
      await _diskCache?.delete(key);
    }

    AppLogger.info('[CacheService] 🗑️ CLEARED cache with prefix: $prefix');
  }

  /// Check if key exists in cache and is not expired
  Future<bool> has(String key) async {
    final data = await get(key);
    return data != null;
  }

  /// Get cache statistics
  Map<String, dynamic> getStats() {
    return {
      'memory_size': _memoryCache.length,
      'disk_size': _diskCache?.length ?? 0,
      'is_initialized': _isInitialized,
      'memory_keys': _memoryCache.keys.toList(),
    };
  }

  /// Start periodic cache cleanup
  void _startCacheCleanup() {
    Timer.periodic(const Duration(minutes: 5), (_) async {
      await _cleanupExpiredEntries();
    });
  }

  /// Clean up expired entries
  Future<void> _cleanupExpiredEntries() async {
    int removedCount = 0;

    // Clean memory cache
    _memoryCache.removeWhere((_, entry) {
      if (entry.isExpired) {
        removedCount++;
        return true;
      }
      return false;
    });

    // Clean disk cache
    final keysToDelete = <String>[];
    for (final key in _diskCache?.keys ?? <String>[]) {
      try {
        final data = _diskCache?.get(key);
        if (data != null) {
          final entry = CacheEntry.fromJson(data as Map<String, dynamic>);
          if (entry.isExpired) {
            keysToDelete.add(key as String);
            removedCount++;
          }
        }
      } catch (e) {
        // If we can't parse it, delete it
        keysToDelete.add(key as String);
      }
    }

    for (final key in keysToDelete) {
      await _diskCache?.delete(key);
    }

    if (removedCount > 0) {
      AppLogger.info('[CacheService] 🧹 Cleaned $removedCount expired entries');
    }
  }

  void _ensureInitialized() {
    if (!_isInitialized) {
      throw Exception('CacheService not initialized. Call initialize() first.');
    }
  }

  /// Close cache (cleanup)
  Future<void> close() async {
    _memoryCache.clear();
    await _diskCache?.close();
    _isInitialized = false;
    AppLogger.info('[CacheService] ♦️ Closed');
  }
}

/// Cache keys for different data types
class CacheKeys {
  // Products
  static const String productsPrefix = 'products_';
  static String productsList(String? shopId) => '${productsPrefix}list_${shopId ?? 'all'}';
  static String productDetail(String id) => '${productsPrefix}detail_$id';

  // Brands
  static const String brandsPrefix = 'brands_';
  static String brandsList = '${brandsPrefix}list';
  static String brandDetail(String id) => '${brandsPrefix}detail_$id';
  static String brandVariants(String id) => '${brandsPrefix}variants_$id';

  // Sales
  static const String salesPrefix = 'sales_';
  static String salesList(String? shopId, String? date) =>
    '${salesPrefix}list_${shopId ?? 'all'}_${date ?? 'today'}';
  static String saleDetail(String id) => '${salesPrefix}detail_$id';

  // Dashboard
  static const String dashboardPrefix = 'dashboard_';
  static String dashboardStats(String? shopId) => '${dashboardPrefix}stats_${shopId ?? 'all'}';

  // Shops
  static const String shopsPrefix = 'shops_';
  static String shopsList = '${shopsPrefix}list';
  static String shopDetail(String id) => '${shopsPrefix}detail_$id';

  // Users
  static const String usersPrefix = 'users_';
  static String usersList = '${usersPrefix}list';
  static String userDetail(String id) => '${usersPrefix}detail_$id';

  // Cash
  static const String cashPrefix = 'cash_';
  static String cashBalance(String? shopId) => '${cashPrefix}balance_${shopId ?? 'all'}';
  static String cashRequests = '${cashPrefix}requests';

  // Categories
  static const String categoriesPrefix = 'categories_';
  static String categoriesList = '${categoriesPrefix}list';
}
