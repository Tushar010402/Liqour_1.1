import 'dart:convert';
import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';

import 'logger.dart';

/// Premium cache manager with multiple caching strategies
class PremiumCacheManager {
  static const String _cacheBoxName = 'premium_cache';
  static const String _imageBoxName = 'image_cache';
  static const String _apiBoxName = 'api_cache';
  
  static PremiumCacheManager? _instance;
  static PremiumCacheManager get instance => _instance ??= PremiumCacheManager._internal();
  
  PremiumCacheManager._internal();
  
  late Box<dynamic> _cacheBox;
  late Box<dynamic> _imageBox;
  late Box<dynamic> _apiBox;
  
  late DefaultCacheManager _imageCacheManager;
  
  bool _initialized = false;

  /// Initialize cache manager
  Future<void> initialize() async {
    if (_initialized) return;
    
    try {
      AppLogger.info('🗄️ Initializing PremiumCacheManager...');
      
      // Initialize Hive boxes
      _cacheBox = await Hive.openBox(_cacheBoxName);
      _imageBox = await Hive.openBox(_imageBoxName);
      _apiBox = await Hive.openBox(_apiBoxName);
      
      // Initialize image cache manager
      _imageCacheManager = DefaultCacheManager();
      
      _initialized = true;
      
      AppLogger.info('✅ PremiumCacheManager initialized successfully');
      
      // Clean expired cache entries on startup
      await _cleanExpiredEntries();
      
    } catch (error, stackTrace) {
      AppLogger.error('❌ Failed to initialize cache manager', error, stackTrace);
      throw error;
    }
  }

  /// Check if cache is initialized
  bool get isInitialized => _initialized;

  /// Store data in cache with TTL
  Future<void> store({
    required String key,
    required dynamic data,
    Duration? ttl,
    CacheType type = CacheType.general,
  }) async {
    if (!_initialized) {
      AppLogger.warning('Cache manager not initialized');
      return;
    }

    try {
      final box = _getBox(type);
      final cacheEntry = CacheEntry(
        data: data,
        timestamp: DateTime.now(),
        ttl: ttl,
      );

      await box.put(key, cacheEntry.toJson());
      
      AppLogger.debug('📦 Cached data', {
        'key': key,
        'type': type.name,
        'ttl': ttl?.inMinutes,
        'size': _getDataSize(data),
      });

    } catch (error, stackTrace) {
      AppLogger.error('Failed to store cache', error, stackTrace);
    }
  }

  /// Retrieve data from cache
  Future<T?> get<T>({
    required String key,
    CacheType type = CacheType.general,
  }) async {
    if (!_initialized) {
      AppLogger.warning('Cache manager not initialized');
      return null;
    }

    try {
      final box = _getBox(type);
      final rawData = box.get(key);
      
      if (rawData == null) return null;

      final cacheEntry = CacheEntry.fromJson(rawData);

      // Check if cache entry is expired
      if (cacheEntry.isExpired) {
        await box.delete(key);
        AppLogger.debug('🗑️ Removed expired cache entry', {'key': key});
        return null;
      }

      AppLogger.debug('📦 Retrieved cached data', {
        'key': key,
        'type': type.name,
        'age': DateTime.now().difference(cacheEntry.timestamp).inMinutes,
      });

      return cacheEntry.data as T?;

    } catch (error, stackTrace) {
      AppLogger.error('Failed to retrieve cache', error, stackTrace);
      return null;
    }
  }

  /// Check if key exists in cache
  bool has({
    required String key,
    CacheType type = CacheType.general,
  }) {
    if (!_initialized) return false;

    final box = _getBox(type);
    return box.containsKey(key);
  }

  /// Remove specific cache entry
  Future<void> remove({
    required String key,
    CacheType type = CacheType.general,
  }) async {
    if (!_initialized) return;

    try {
      final box = _getBox(type);
      await box.delete(key);
      
      AppLogger.debug('🗑️ Removed cache entry', {'key': key, 'type': type.name});

    } catch (error, stackTrace) {
      AppLogger.error('Failed to remove cache entry', error, stackTrace);
    }
  }

  /// Clear all cache of specific type
  Future<void> clear({CacheType? type}) async {
    if (!_initialized) return;

    try {
      if (type != null) {
        final box = _getBox(type);
        await box.clear();
        AppLogger.info('🧹 Cleared cache', {'type': type.name});
      } else {
        // Clear all caches
        await _cacheBox.clear();
        await _imageBox.clear();
        await _apiBox.clear();
        await _imageCacheManager.emptyCache();
        AppLogger.info('🧹 Cleared all caches');
      }

    } catch (error, stackTrace) {
      AppLogger.error('Failed to clear cache', error, stackTrace);
    }
  }

  /// Get cache statistics
  Map<String, dynamic> getStatistics() {
    if (!_initialized) return {};

    try {
      final generalCount = _cacheBox.length;
      final imageCount = _imageBox.length;
      final apiCount = _apiBox.length;

      return {
        'general_cache_count': generalCount,
        'image_cache_count': imageCount,
        'api_cache_count': apiCount,
        'total_entries': generalCount + imageCount + apiCount,
        'initialized': _initialized,
      };

    } catch (error) {
      AppLogger.error('Failed to get cache statistics', error);
      return {};
    }
  }

  /// Cache API response
  Future<void> cacheApiResponse({
    required String endpoint,
    required Map<String, dynamic>? queryParams,
    required dynamic response,
    Duration ttl = const Duration(minutes: 5),
  }) async {
    final cacheKey = _generateApiCacheKey(endpoint, queryParams);
    
    await store(
      key: cacheKey,
      data: response,
      ttl: ttl,
      type: CacheType.api,
    );
  }

  /// Get cached API response
  Future<T?> getCachedApiResponse<T>({
    required String endpoint,
    required Map<String, dynamic>? queryParams,
  }) async {
    final cacheKey = _generateApiCacheKey(endpoint, queryParams);
    
    return await get<T>(
      key: cacheKey,
      type: CacheType.api,
    );
  }

  /// Cache image with URL
  Future<void> cacheImage({
    required String url,
    Duration maxAge = const Duration(days: 7),
  }) async {
    try {
      await _imageCacheManager.downloadFile(
        url,
        key: _generateImageCacheKey(url),
      );
      
      // Store metadata
      await store(
        key: 'image_meta_${_generateImageCacheKey(url)}',
        data: {
          'url': url,
          'cached_at': DateTime.now().toIso8601String(),
        },
        ttl: maxAge,
        type: CacheType.image,
      );

    } catch (error, stackTrace) {
      AppLogger.error('Failed to cache image', error, stackTrace);
    }
  }

  /// Get cached image file
  Future<File?> getCachedImageFile(String url) async {
    try {
      final cacheKey = _generateImageCacheKey(url);
      final fileInfo = await _imageCacheManager.getFileFromCache(cacheKey);
      
      return fileInfo?.file;

    } catch (error) {
      AppLogger.error('Failed to get cached image', error);
      return null;
    }
  }

  /// Preload images for better performance
  Future<void> preloadImages(List<String> urls) async {
    AppLogger.info('🖼️ Preloading images', {'count': urls.length});

    for (final url in urls) {
      try {
        await cacheImage(url: url);
      } catch (error) {
        AppLogger.warning('Failed to preload image: $url', error);
      }
    }

    AppLogger.info('✅ Image preloading completed');
  }

  /// Cache search results
  Future<void> cacheSearchResults({
    required String query,
    required List<dynamic> results,
    Duration ttl = const Duration(minutes: 10),
  }) async {
    final cacheKey = 'search_${_hashString(query)}';
    
    await store(
      key: cacheKey,
      data: {
        'query': query,
        'results': results,
        'result_count': results.length,
      },
      ttl: ttl,
      type: CacheType.api,
    );
  }

  /// Get cached search results
  Future<List<T>?> getCachedSearchResults<T>(String query) async {
    final cacheKey = 'search_${_hashString(query)}';
    
    final cached = await get<Map<String, dynamic>>(
      key: cacheKey,
      type: CacheType.api,
    );

    if (cached != null && cached['results'] is List) {
      return (cached['results'] as List).cast<T>();
    }

    return null;
  }

  /// Cache user preferences
  Future<void> cacheUserPreferences(Map<String, dynamic> preferences) async {
    await store(
      key: 'user_preferences',
      data: preferences,
      type: CacheType.general,
    );
  }

  /// Get cached user preferences
  Future<Map<String, dynamic>?> getCachedUserPreferences() async {
    return await get<Map<String, dynamic>>(
      key: 'user_preferences',
      type: CacheType.general,
    );
  }

  /// Cache app configuration
  Future<void> cacheAppConfig(Map<String, dynamic> config) async {
    await store(
      key: 'app_config',
      data: config,
      ttl: const Duration(hours: 1),
      type: CacheType.general,
    );
  }

  /// Get cached app configuration
  Future<Map<String, dynamic>?> getCachedAppConfig() async {
    return await get<Map<String, dynamic>>(
      key: 'app_config',
      type: CacheType.general,
    );
  }

  /// Clean expired cache entries
  Future<void> _cleanExpiredEntries() async {
    AppLogger.info('🧹 Cleaning expired cache entries...');
    
    int cleanedCount = 0;

    try {
      // Clean general cache
      cleanedCount += await _cleanBoxExpiredEntries(_cacheBox);
      
      // Clean image cache metadata
      cleanedCount += await _cleanBoxExpiredEntries(_imageBox);
      
      // Clean API cache
      cleanedCount += await _cleanBoxExpiredEntries(_apiBox);

      AppLogger.info('✅ Cache cleanup completed', {'cleaned_entries': cleanedCount});

    } catch (error, stackTrace) {
      AppLogger.error('Failed to clean expired cache entries', error, stackTrace);
    }
  }

  /// Clean expired entries from a specific box
  Future<int> _cleanBoxExpiredEntries(Box box) async {
    int cleanedCount = 0;
    final keysToDelete = <String>[];

    for (final key in box.keys) {
      try {
        final rawData = box.get(key);
        if (rawData != null) {
          final cacheEntry = CacheEntry.fromJson(rawData);
          
          if (cacheEntry.isExpired) {
            keysToDelete.add(key.toString());
          }
        }
      } catch (error) {
        // If entry is corrupted, mark for deletion
        keysToDelete.add(key.toString());
      }
    }

    // Delete expired entries
    for (final key in keysToDelete) {
      await box.delete(key);
      cleanedCount++;
    }

    return cleanedCount;
  }

  /// Get appropriate box for cache type
  Box<dynamic> _getBox(CacheType type) {
    switch (type) {
      case CacheType.general:
        return _cacheBox;
      case CacheType.image:
        return _imageBox;
      case CacheType.api:
        return _apiBox;
    }
  }

  /// Generate API cache key
  String _generateApiCacheKey(String endpoint, Map<String, dynamic>? queryParams) {
    final queryString = queryParams?.entries
        .map((e) => '${e.key}=${e.value}')
        .join('&') ?? '';
    
    final fullUrl = queryString.isEmpty ? endpoint : '$endpoint?$queryString';
    return 'api_${_hashString(fullUrl)}';
  }

  /// Generate image cache key
  String _generateImageCacheKey(String url) {
    return _hashString(url);
  }

  /// Generate hash for string
  String _hashString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Get approximate data size
  int _getDataSize(dynamic data) {
    try {
      final jsonString = json.encode(data);
      return jsonString.length;
    } catch (error) {
      return 0;
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    try {
      await _cacheBox.close();
      await _imageBox.close();
      await _apiBox.close();
      
      _initialized = false;
      
      AppLogger.info('🗄️ Cache manager disposed');

    } catch (error, stackTrace) {
      AppLogger.error('Failed to dispose cache manager', error, stackTrace);
    }
  }
}

/// Cache types enumeration
enum CacheType {
  general,
  image,
  api,
}

/// Cache entry model
class CacheEntry {
  final dynamic data;
  final DateTime timestamp;
  final Duration? ttl;

  const CacheEntry({
    required this.data,
    required this.timestamp,
    this.ttl,
  });

  /// Check if cache entry is expired
  bool get isExpired {
    if (ttl == null) return false;
    return DateTime.now().isAfter(timestamp.add(ttl!));
  }

  /// Get age of cache entry
  Duration get age => DateTime.now().difference(timestamp);

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'data': data,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'ttl_seconds': ttl?.inSeconds,
    };
  }

  /// Create from JSON
  factory CacheEntry.fromJson(Map<String, dynamic> json) {
    return CacheEntry(
      data: json['data'],
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp']),
      ttl: json['ttl_seconds'] != null 
          ? Duration(seconds: json['ttl_seconds'])
          : null,
    );
  }
}

/// Cache configuration
class CacheConfig {
  static const Duration defaultApiCacheTtl = Duration(minutes: 5);
  static const Duration defaultImageCacheTtl = Duration(days: 7);
  static const Duration defaultGeneralCacheTtl = Duration(hours: 1);
  static const Duration searchCacheTtl = Duration(minutes: 10);
  static const Duration userPreferencesCacheTtl = Duration(days: 30);
  static const Duration appConfigCacheTtl = Duration(hours: 1);
  
  static const int maxCacheEntries = 1000;
  static const int maxImageCacheSize = 100 * 1024 * 1024; // 100MB
  static const int maxApiCacheSize = 50 * 1024 * 1024; // 50MB
}

/// Cache helper functions
class CacheHelper {
  /// Generate cache key for paginated data
  static String generatePaginatedKey({
    required String baseKey,
    required int page,
    required int limit,
    Map<String, dynamic>? filters,
  }) {
    final filterString = filters?.entries
        .map((e) => '${e.key}:${e.value}')
        .join('|') ?? '';
    
    return '${baseKey}_p${page}_l${limit}_$filterString';
  }

  /// Generate cache key for user-specific data
  static String generateUserKey({
    required String userId,
    required String dataType,
    String? identifier,
  }) {
    final parts = ['user', userId, dataType];
    if (identifier != null) parts.add(identifier);
    return parts.join('_');
  }

  /// Generate cache key for location-based data
  static String generateLocationKey({
    required String baseKey,
    required double latitude,
    required double longitude,
    double precision = 0.01,
  }) {
    final roundedLat = (latitude / precision).round() * precision;
    final roundedLng = (longitude / precision).round() * precision;
    return '${baseKey}_${roundedLat}_$roundedLng';
  }

  /// Check if cache should be bypassed based on connectivity
  static bool shouldBypassCache() {
    // Implementation would check network connectivity and user preferences
    return false;
  }
}