import 'package:flutter/foundation.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../config/environment_config.dart';
import '../utils/logger.dart';
import 'preferences_service.dart';

/// Analytics Service - Event tracking and user behavior analytics
/// Production-ready analytics infrastructure
class AnalyticsService {
  static AnalyticsService? _instance;
  static bool _isEnabled = true;

  AnalyticsService._();

  /// Singleton instance
  static Future<AnalyticsService> getInstance() async {
    if (_instance == null) {
      _instance = AnalyticsService._();
      await _instance!._init();
    }
    return _instance!;
  }

  /// Initialize analytics service
  Future<void> _init() async {
    try {
      final prefs = await PreferencesService.getInstance();
      final userPrefs = UserPreferences(prefs);
      _isEnabled = userPrefs.isAnalyticsEnabled();
      Logger.info('Analytics service initialized (enabled: $_isEnabled)');
    } catch (e) {
      Logger.error('Failed to initialize analytics', e);
    }
  }

  /// Enable analytics
  static Future<void> enable() async {
    _isEnabled = true;
    try {
      final prefs = await PreferencesService.getInstance();
      final userPrefs = UserPreferences(prefs);
      await userPrefs.setAnalytics(true);
    } catch (e) {
      Logger.error('Failed to enable analytics', e);
    }
  }

  /// Disable analytics
  static Future<void> disable() async {
    _isEnabled = false;
    try {
      final prefs = await PreferencesService.getInstance();
      final userPrefs = UserPreferences(prefs);
      await userPrefs.setAnalytics(false);
    } catch (e) {
      Logger.error('Failed to disable analytics', e);
    }
  }

  // ==================== Event Tracking ====================

  /// Track generic event
  /// OPTIMIZED: Disabled in debug mode to reduce overhead
  /// Analytics should only run in production/profile mode
  static void trackEvent(String eventName, {Map<String, dynamic>? parameters}) {
    // BEST PRACTICE: Don't track analytics in debug mode
    // Development should be fast; analytics adds significant overhead
    if (kDebugMode) return;

    if (!_isEnabled) return;
    if (!EnvironmentConfig.enableAnalytics) return;

    try {
      // Sanitize event name: Firebase limits to 40 chars, alphanumeric + underscore
      final safeName = _sanitizeEventName(eventName);

      // Sanitize parameters: name ≤40 chars, value ≤100 chars, only String/int/double/bool
      final sanitized = _sanitizeParameters(parameters);

      FirebaseAnalytics.instance.logEvent(
        name: safeName,
        parameters: sanitized,
      );
    } catch (e) {
      // Only log errors - don't spam logs for successful events
      if (kReleaseMode) {
        Logger.error('Failed to track event: $eventName', e);
      }
    }
  }

  /// Sanitize event name for Firebase (≤40 chars, alphanumeric + underscore, must start with letter)
  static String _sanitizeEventName(String name) {
    final sanitized = name
        .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final trimmed = sanitized.length > 40 ? sanitized.substring(0, 40) : sanitized;
    // Must start with a letter
    if (trimmed.isNotEmpty && !RegExp(r'^[a-zA-Z]').hasMatch(trimmed)) {
      return 'e_$trimmed'.substring(0, trimmed.length > 38 ? 40 : trimmed.length + 2);
    }
    return trimmed;
  }

  /// Sanitize parameters for Firebase (name ≤40 chars, value ≤100 chars)
  static Map<String, Object>? _sanitizeParameters(Map<String, dynamic>? params) {
    if (params == null || params.isEmpty) return null;

    final sanitized = <String, Object>{};
    for (final entry in params.entries) {
      final key = entry.key.length > 40 ? entry.key.substring(0, 40) : entry.key;
      final value = entry.value;

      if (value is String) {
        sanitized[key] = value.length > 100 ? value.substring(0, 100) : value;
      } else if (value is int || value is double || value is bool) {
        sanitized[key] = value;
      } else if (value != null) {
        final str = value.toString();
        sanitized[key] = str.length > 100 ? str.substring(0, 100) : str;
      }
    }
    return sanitized.isEmpty ? null : sanitized;
  }

  /// Track screen view
  static void trackScreenView(String screenName, {String? screenClass}) {
    trackEvent('screen_view', parameters: {
      'screen_name': screenName,
      'screen_class': screenClass ?? screenName,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  // ==================== User Actions ====================

  /// Track login
  static void trackLogin({String? method}) {
    trackEvent('login', parameters: {
      'method': method ?? 'email',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Track logout
  static void trackLogout() {
    trackEvent('logout', parameters: {
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Track sign up
  static void trackSignUp({String? method}) {
    trackEvent('sign_up', parameters: {
      'method': method ?? 'email',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  // ==================== Product Actions ====================

  /// Track product view
  static void trackProductView(String productId, String productName) {
    trackEvent('product_view', parameters: {
      'product_id': productId,
      'product_name': productName,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Track product search
  static void trackProductSearch(String query, {int? resultCount}) {
    trackEvent('product_search', parameters: {
      'search_query': query,
      'result_count': resultCount,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Track product onboarding
  static void trackProductOnboarding({
    required int productCount,
    required bool withStock,
    String? category,
  }) {
    trackEvent('product_onboarding', parameters: {
      'product_count': productCount,
      'with_stock': withStock,
      'category': category,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  // ==================== Brand Actions ====================

  /// Track brand catalog view
  static void trackBrandCatalogView({String? category, String? subcategory}) {
    trackEvent('brand_catalog_view', parameters: {
      'category': category,
      'subcategory': subcategory,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Track brand selection
  static void trackBrandSelection(String brandId, String brandName) {
    trackEvent('brand_selection', parameters: {
      'brand_id': brandId,
      'brand_name': brandName,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  // ==================== Inventory Actions ====================

  /// Track stock adjustment
  static void trackStockAdjustment({
    required String productId,
    required int quantity,
    required String type,
  }) {
    trackEvent('stock_adjustment', parameters: {
      'product_id': productId,
      'quantity': quantity,
      'adjustment_type': type,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Track inventory sync
  static void trackInventorySync({int? itemCount}) {
    trackEvent('inventory_sync', parameters: {
      'item_count': itemCount,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  // ==================== Sales Actions ====================

  /// Track sale
  static void trackSale({
    required String saleId,
    required double amount,
    required int itemCount,
  }) {
    trackEvent('sale', parameters: {
      'sale_id': saleId,
      'amount': amount,
      'item_count': itemCount,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Track sale return
  static void trackSaleReturn({
    required String returnId,
    required double amount,
  }) {
    trackEvent('sale_return', parameters: {
      'return_id': returnId,
      'amount': amount,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  // ==================== UI Interactions ====================

  /// Track button click
  static void trackButtonClick(String buttonName, {String? screen}) {
    trackEvent('button_click', parameters: {
      'button_name': buttonName,
      'screen': screen,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Track filter applied
  static void trackFilterApplied({
    required String filterType,
    required String filterValue,
    String? screen,
  }) {
    trackEvent('filter_applied', parameters: {
      'filter_type': filterType,
      'filter_value': filterValue,
      'screen': screen,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Track toggle changed
  static void trackToggleChanged({
    required String toggleName,
    required bool value,
    String? screen,
  }) {
    trackEvent('toggle_changed', parameters: {
      'toggle_name': toggleName,
      'value': value,
      'screen': screen,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  // ==================== Performance Tracking ====================

  /// Track performance metric
  static void trackPerformance({
    required String metricName,
    required int durationMs,
    String? category,
  }) {
    trackEvent('performance', parameters: {
      'metric_name': metricName,
      'duration_ms': durationMs,
      'category': category,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Track API call performance
  static void trackApiCall({
    required String endpoint,
    required int durationMs,
    required int statusCode,
    bool? success,
  }) {
    trackEvent('api_call', parameters: {
      'endpoint': endpoint,
      'duration_ms': durationMs,
      'status_code': statusCode,
      'success': success ?? (statusCode >= 200 && statusCode < 300),
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  // ==================== Error Tracking ====================

  /// Track error
  static void trackError({
    required String errorType,
    required String errorMessage,
    String? screen,
    StackTrace? stackTrace,
  }) {
    trackEvent('error', parameters: {
      'error_type': errorType,
      'error_message': errorMessage,
      'screen': screen,
      'stack_trace': stackTrace?.toString(),
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Track crash
  static void trackCrash({
    required String crashMessage,
    StackTrace? stackTrace,
  }) {
    trackEvent('crash', parameters: {
      'crash_message': crashMessage,
      'stack_trace': stackTrace?.toString(),
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  // ==================== User Properties ====================

  /// Set user ID
  /// OPTIMIZED: Disabled in debug mode
  static void setUserId(String userId) {
    if (kDebugMode) return; // Skip in debug mode
    if (!_isEnabled) return;
    try {
      FirebaseAnalytics.instance.setUserId(id: userId);
      if (EnvironmentConfig.enableCrashReporting) {
        FirebaseCrashlytics.instance.setUserIdentifier(userId);
      }
    } catch (e) {
      Logger.error('Failed to set user ID', e);
    }
  }

  /// Set user property
  /// OPTIMIZED: Disabled in debug mode
  static void setUserProperty(String name, String value) {
    if (kDebugMode) return; // Skip in debug mode
    if (!_isEnabled) return;
    try {
      final safeName = name.length > 24 ? name.substring(0, 24) : name;
      final safeValue = value.length > 36 ? value.substring(0, 36) : value;
      FirebaseAnalytics.instance.setUserProperty(name: safeName, value: safeValue);
    } catch (e) {
      Logger.error('Failed to set user property: $name', e);
    }
  }

  /// Set user properties
  static void setUserProperties(Map<String, String> properties) {
    if (!_isEnabled) return;
    for (final entry in properties.entries) {
      setUserProperty(entry.key, entry.value);
    }
  }
}

/// Analytics extension for easy tracking
extension AnalyticsContext on Object {
  /// Track event from any context
  void track(String eventName, {Map<String, dynamic>? parameters}) {
    AnalyticsService.trackEvent(eventName, parameters: parameters);
  }
}

/// Performance timer for tracking operation duration
class PerformanceTimer {
  final String metricName;
  final String? category;
  final DateTime _startTime;

  PerformanceTimer(this.metricName, {this.category}) : _startTime = DateTime.now();

  /// Stop timer and track performance
  void stop() {
    final duration = DateTime.now().difference(_startTime);
    AnalyticsService.trackPerformance(
      metricName: metricName,
      durationMs: duration.inMilliseconds,
      category: category,
    );
  }
}

/// Timed operation wrapper
Future<T> trackPerformance<T>({
  required String metricName,
  required Future<T> Function() operation,
  String? category,
}) async {
  final timer = PerformanceTimer(metricName, category: category);
  try {
    return await operation();
  } finally {
    timer.stop();
  }
}
