import 'dart:async';
import 'package:flutter/foundation.dart';
import '../config/debug_performance_config.dart';

/// Industrial-Grade Request Deduplication Service
/// Best Practices:
/// - Prevents duplicate API calls within a time window
/// - Caches pending requests and returns the same Future
/// - Automatic cleanup of stale entries
/// - Thread-safe implementation
///
/// Usage:
/// ```dart
/// final result = await RequestDeduplicationService.dedupe(
///   key: 'getDashboard_$tenantId',
///   request: () => apiService.get('/api/dashboard'),
///   ttl: Duration(seconds: 5),
/// );
/// ```
class RequestDeduplicationService {
  // Singleton pattern
  static final RequestDeduplicationService _instance =
      RequestDeduplicationService._internal();
  factory RequestDeduplicationService() => _instance;
  RequestDeduplicationService._internal() {
    // Start cleanup timer
    _startCleanupTimer();
  }

  // Cache of pending requests
  // Key: unique request identifier
  // Value: Future<T> of the pending request
  final Map<String, _CachedRequest> _pendingRequests = {};

  // Cleanup timer
  Timer? _cleanupTimer;
  static final Duration _cleanupInterval = DebugPerformanceConfig.deduplicationCleanupInterval;

  /// Deduplicate a request
  /// If a request with the same key is already pending, returns the same Future
  /// Otherwise, executes the request and caches it
  static Future<T> dedupe<T>({
    required String key,
    required Future<T> Function() request,
    Duration ttl = const Duration(seconds: 5),
  }) {
    return _instance._dedupe<T>(key: key, request: request, ttl: ttl);
  }

  Future<T> _dedupe<T>({
    required String key,
    required Future<T> Function() request,
    required Duration ttl,
  }) async {
    final now = DateTime.now();

    // Check if we have a cached request that's still valid
    if (_pendingRequests.containsKey(key)) {
      final cached = _pendingRequests[key]!;

      // Check if the cached request is still valid (not expired)
      if (now.difference(cached.timestamp) < ttl) {
        if (kDebugMode) {
          debugPrint('🔄 [Dedupe] Returning cached request for: $key');
        }
        return cached.future as Future<T>;
      } else {
        // Cached request expired, remove it
        _pendingRequests.remove(key);
      }
    }

    // Execute the new request
    if (kDebugMode) {
      debugPrint('🆕 [Dedupe] Executing new request for: $key');
    }

    // Create a completer to cache the Future
    final completer = Completer<T>();

    // Store the pending request
    _pendingRequests[key] = _CachedRequest(
      future: completer.future,
      timestamp: now,
    );

    // Execute the request
    try {
      final result = await request();
      completer.complete(result);

      // Remove from cache after completion (allow new requests)
      // Keep it cached for a short time to handle rapid duplicate calls
      Future.delayed(const Duration(milliseconds: 100), () {
        _pendingRequests.remove(key);
      });

      return result;
    } catch (e) {
      // Remove from cache on error
      _pendingRequests.remove(key);
      completer.completeError(e);
      rethrow;
    }
  }

  /// Invalidate a cached request
  /// Call this when you know the data has changed
  static void invalidate(String key) {
    _instance._pendingRequests.remove(key);
    if (kDebugMode) {
      debugPrint('🗑️ [Dedupe] Invalidated: $key');
    }
  }

  /// Invalidate all cached requests matching a pattern
  static void invalidateMatching(String pattern) {
    final keysToRemove = _instance._pendingRequests.keys
        .where((key) => key.contains(pattern))
        .toList();

    for (final key in keysToRemove) {
      _instance._pendingRequests.remove(key);
    }

    if (kDebugMode && keysToRemove.isNotEmpty) {
      debugPrint('🗑️ [Dedupe] Invalidated ${keysToRemove.length} matching: $pattern');
    }
  }

  /// Clear all cached requests
  static void clearAll() {
    _instance._pendingRequests.clear();
    if (kDebugMode) {
      debugPrint('🗑️ [Dedupe] Cleared all cached requests');
    }
  }

  /// Get number of pending requests (for debugging)
  static int get pendingCount => _instance._pendingRequests.length;

  /// Start the cleanup timer
  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(_cleanupInterval, (_) {
      _cleanupStaleEntries();
    });
  }

  /// Clean up stale entries
  void _cleanupStaleEntries() {
    final now = DateTime.now();
    final staleKeys = <String>[];

    _pendingRequests.forEach((key, cached) {
      // Remove entries older than 1 minute
      if (now.difference(cached.timestamp) > const Duration(minutes: 1)) {
        staleKeys.add(key);
      }
    });

    for (final key in staleKeys) {
      _pendingRequests.remove(key);
    }

    if (kDebugMode && staleKeys.isNotEmpty) {
      debugPrint('🧹 [Dedupe] Cleaned up ${staleKeys.length} stale entries');
    }
  }

  /// Dispose the service
  void dispose() {
    _cleanupTimer?.cancel();
    _pendingRequests.clear();
  }
}

/// Internal class to store cached requests with timestamp
class _CachedRequest {
  final Future<dynamic> future;
  final DateTime timestamp;

  _CachedRequest({
    required this.future,
    required this.timestamp,
  });
}

/// Extension for easy deduplication on API calls
extension DeduplicationExtension<T> on Future<T> Function() {
  /// Wrap this function with deduplication
  Future<T> dedupe(String key, {Duration ttl = const Duration(seconds: 5)}) {
    return RequestDeduplicationService.dedupe(
      key: key,
      request: this,
      ttl: ttl,
    );
  }
}

/// Mixin for providers to easily dedupe API calls
mixin RequestDeduplicationMixin {
  /// Deduplicate an API call
  Future<T> dedupeRequest<T>({
    required String key,
    required Future<T> Function() request,
    Duration ttl = const Duration(seconds: 5),
  }) {
    return RequestDeduplicationService.dedupe(
      key: key,
      request: request,
      ttl: ttl,
    );
  }

  /// Invalidate a specific cache key
  void invalidateCache(String key) {
    RequestDeduplicationService.invalidate(key);
  }

  /// Invalidate all caches matching a pattern
  void invalidateCacheMatching(String pattern) {
    RequestDeduplicationService.invalidateMatching(pattern);
  }
}
