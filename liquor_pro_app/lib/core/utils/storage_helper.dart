import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'app_logger.dart';

/// Storage Helper - Best Practice Local Storage
/// Centralized local storage management using SharedPreferences

class StorageHelper {
  // Private constructor to prevent instantiation
  StorageHelper._();

  static SharedPreferences? _prefs;

  // ==================== Initialization ====================

  /// Initialize storage (call in main.dart)
  static Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      AppLogger.info('Storage initialized successfully');
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Storage Initialization',
      );
      rethrow;
    }
  }

  /// Get SharedPreferences instance
  static SharedPreferences get instance {
    if (_prefs == null) {
      throw Exception('StorageHelper not initialized. Call StorageHelper.init() first.');
    }
    return _prefs!;
  }

  // ==================== String Operations ====================

  /// Save string value
  static Future<bool> setString(String key, String value) async {
    try {
      final result = await instance.setString(key, value);
      AppLogger.debug('Storage: Set string - $key');
      return result;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Storage setString',
        additionalData: {'key': key},
      );
      return false;
    }
  }

  /// Get string value
  static String? getString(String key, {String? defaultValue}) {
    try {
      final value = instance.getString(key) ?? defaultValue;
      AppLogger.debug('Storage: Get string - $key: ${value != null ? "found" : "not found"}');
      return value;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Storage getString',
        additionalData: {'key': key},
      );
      return defaultValue;
    }
  }

  // ==================== Integer Operations ====================

  /// Save integer value
  static Future<bool> setInt(String key, int value) async {
    try {
      final result = await instance.setInt(key, value);
      AppLogger.debug('Storage: Set int - $key = $value');
      return result;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Storage setInt',
        additionalData: {'key': key, 'value': value},
      );
      return false;
    }
  }

  /// Get integer value
  static int? getInt(String key, {int? defaultValue}) {
    try {
      final value = instance.getInt(key) ?? defaultValue;
      AppLogger.debug('Storage: Get int - $key: ${value ?? "not found"}');
      return value;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Storage getInt',
        additionalData: {'key': key},
      );
      return defaultValue;
    }
  }

  // ==================== Double Operations ====================

  /// Save double value
  static Future<bool> setDouble(String key, double value) async {
    try {
      final result = await instance.setDouble(key, value);
      AppLogger.debug('Storage: Set double - $key = $value');
      return result;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Storage setDouble',
        additionalData: {'key': key, 'value': value},
      );
      return false;
    }
  }

  /// Get double value
  static double? getDouble(String key, {double? defaultValue}) {
    try {
      final value = instance.getDouble(key) ?? defaultValue;
      AppLogger.debug('Storage: Get double - $key: ${value ?? "not found"}');
      return value;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Storage getDouble',
        additionalData: {'key': key},
      );
      return defaultValue;
    }
  }

  // ==================== Boolean Operations ====================

  /// Save boolean value
  static Future<bool> setBool(String key, bool value) async {
    try {
      final result = await instance.setBool(key, value);
      AppLogger.debug('Storage: Set bool - $key = $value');
      return result;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Storage setBool',
        additionalData: {'key': key, 'value': value},
      );
      return false;
    }
  }

  /// Get boolean value
  static bool? getBool(String key, {bool? defaultValue}) {
    try {
      final value = instance.getBool(key) ?? defaultValue;
      AppLogger.debug('Storage: Get bool - $key: ${value ?? "not found"}');
      return value;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Storage getBool',
        additionalData: {'key': key},
      );
      return defaultValue;
    }
  }

  // ==================== List Operations ====================

  /// Save string list
  static Future<bool> setStringList(String key, List<String> value) async {
    try {
      final result = await instance.setStringList(key, value);
      AppLogger.debug('Storage: Set string list - $key (${value.length} items)');
      return result;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Storage setStringList',
        additionalData: {'key': key},
      );
      return false;
    }
  }

  /// Get string list
  static List<String>? getStringList(String key, {List<String>? defaultValue}) {
    try {
      final value = instance.getStringList(key) ?? defaultValue;
      AppLogger.debug('Storage: Get string list - $key: ${value != null ? "${value.length} items" : "not found"}');
      return value;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Storage getStringList',
        additionalData: {'key': key},
      );
      return defaultValue;
    }
  }

  // ==================== JSON Operations ====================

  /// Save object as JSON
  static Future<bool> setObject(String key, Map<String, dynamic> value) async {
    try {
      final jsonString = jsonEncode(value);
      final result = await instance.setString(key, jsonString);
      AppLogger.debug('Storage: Set object - $key');
      return result;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Storage setObject',
        additionalData: {'key': key},
      );
      return false;
    }
  }

  /// Get object from JSON
  static Map<String, dynamic>? getObject(String key) {
    try {
      final jsonString = instance.getString(key);
      if (jsonString == null) {
        AppLogger.debug('Storage: Get object - $key: not found');
        return null;
      }
      final value = jsonDecode(jsonString) as Map<String, dynamic>;
      AppLogger.debug('Storage: Get object - $key: found');
      return value;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Storage getObject',
        additionalData: {'key': key},
      );
      return null;
    }
  }

  /// Save list of objects as JSON
  static Future<bool> setObjectList(String key, List<Map<String, dynamic>> value) async {
    try {
      final jsonString = jsonEncode(value);
      final result = await instance.setString(key, jsonString);
      AppLogger.debug('Storage: Set object list - $key (${value.length} items)');
      return result;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Storage setObjectList',
        additionalData: {'key': key},
      );
      return false;
    }
  }

  /// Get list of objects from JSON
  static List<Map<String, dynamic>>? getObjectList(String key) {
    try {
      final jsonString = instance.getString(key);
      if (jsonString == null) {
        AppLogger.debug('Storage: Get object list - $key: not found');
        return null;
      }
      final value = (jsonDecode(jsonString) as List)
          .map((item) => item as Map<String, dynamic>)
          .toList();
      AppLogger.debug('Storage: Get object list - $key: ${value.length} items');
      return value;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Storage getObjectList',
        additionalData: {'key': key},
      );
      return null;
    }
  }

  // ==================== Delete Operations ====================

  /// Remove a key
  static Future<bool> remove(String key) async {
    try {
      final result = await instance.remove(key);
      AppLogger.debug('Storage: Remove - $key');
      return result;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Storage remove',
        additionalData: {'key': key},
      );
      return false;
    }
  }

  /// Clear all data
  static Future<bool> clear() async {
    try {
      final result = await instance.clear();
      AppLogger.warning('Storage: Cleared all data');
      return result;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Storage clear',
      );
      return false;
    }
  }

  // ==================== Utility Operations ====================

  /// Check if key exists
  static bool containsKey(String key) {
    try {
      final exists = instance.containsKey(key);
      AppLogger.debug('Storage: Contains key - $key: $exists');
      return exists;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Storage containsKey',
        additionalData: {'key': key},
      );
      return false;
    }
  }

  /// Get all keys
  static Set<String> getKeys() {
    try {
      final keys = instance.getKeys();
      AppLogger.debug('Storage: Get all keys - ${keys.length} keys');
      return keys;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Storage getKeys',
      );
      return {};
    }
  }

  /// Reload storage (refresh from disk)
  static Future<void> reload() async {
    try {
      await instance.reload();
      AppLogger.debug('Storage: Reloaded');
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Storage reload',
      );
    }
  }

  // ==================== Predefined Keys ====================

  // Auth Keys
  static const String keyAuthToken = 'auth_token';
  static const String keyRefreshToken = 'refresh_token';
  static const String keyUserId = 'user_id';
  static const String keyUserEmail = 'user_email';
  static const String keyUserName = 'user_name';
  static const String keyUserPhone = 'user_phone';
  static const String keyUserRole = 'user_role';
  static const String keyIsLoggedIn = 'is_logged_in';

  // App Settings Keys
  static const String keyThemeMode = 'theme_mode';
  static const String keyLanguage = 'language';
  static const String keyNotificationsEnabled = 'notifications_enabled';
  static const String keyFirstRun = 'first_run';
  static const String keyOnboardingCompleted = 'onboarding_completed';

  // Business Keys
  static const String keyTenantId = 'tenant_id';
  static const String keyShopId = 'shop_id';
  static const String keyShopName = 'shop_name';
  static const String keySelectedBrands = 'selected_brands';
  static const String keyInventoryCache = 'inventory_cache';
  static const String keyCategoryCache = 'category_cache';

  // Cache Keys
  static const String keyCacheTimestamp = 'cache_timestamp_';
  static const String keyCacheData = 'cache_data_';

  // ==================== Auth Helper Methods ====================

  /// Save auth token
  static Future<bool> setAuthToken(String token) async {
    return await setString(keyAuthToken, token);
  }

  /// Get auth token
  static String? getAuthToken() {
    return getString(keyAuthToken);
  }

  /// Check if user is logged in
  static bool isLoggedIn() {
    return getBool(keyIsLoggedIn, defaultValue: false) ?? false;
  }

  /// Set logged in status
  static Future<bool> setLoggedIn(bool status) async {
    return await setBool(keyIsLoggedIn, status);
  }

  /// Clear auth data
  static Future<void> clearAuth() async {
    await remove(keyAuthToken);
    await remove(keyRefreshToken);
    await remove(keyUserId);
    await remove(keyUserEmail);
    await remove(keyUserName);
    await remove(keyUserPhone);
    await remove(keyUserRole);
    await setLoggedIn(false);
    AppLogger.info('Storage: Cleared auth data');
  }

  // ==================== Cache Helper Methods ====================

  /// Set cache with timestamp
  static Future<bool> setCache(String key, Map<String, dynamic> data, {Duration? ttl}) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      await setInt('$keyCacheTimestamp$key', timestamp);
      final result = await setObject('$keyCacheData$key', data);
      AppLogger.debug('Storage: Set cache - $key (TTL: ${ttl?.inMinutes ?? "∞"} min)');
      return result;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Storage setCache',
        additionalData: {'key': key},
      );
      return false;
    }
  }

  /// Get cache if not expired
  static Map<String, dynamic>? getCache(String key, {Duration? ttl}) {
    try {
      final timestamp = getInt('$keyCacheTimestamp$key');
      if (timestamp == null) {
        AppLogger.debug('Storage: Get cache - $key: not found');
        return null;
      }

      if (ttl != null) {
        final cacheAge = DateTime.now().millisecondsSinceEpoch - timestamp;
        if (cacheAge > ttl.inMilliseconds) {
          AppLogger.debug('Storage: Get cache - $key: expired');
          return null;
        }
      }

      final data = getObject('$keyCacheData$key');
      AppLogger.debug('Storage: Get cache - $key: ${data != null ? "found" : "not found"}');
      return data;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Storage getCache',
        additionalData: {'key': key},
      );
      return null;
    }
  }

  /// Clear specific cache
  static Future<void> clearCache(String key) async {
    await remove('$keyCacheTimestamp$key');
    await remove('$keyCacheData$key');
    AppLogger.debug('Storage: Cleared cache - $key');
  }

  /// Clear all caches
  static Future<void> clearAllCaches() async {
    final keys = getKeys();
    for (final key in keys) {
      if (key.startsWith(keyCacheTimestamp) || key.startsWith(keyCacheData)) {
        await remove(key);
      }
    }
    AppLogger.info('Storage: Cleared all caches');
  }

  // ==================== Settings Helper Methods ====================

  /// Get theme mode
  static String getThemeMode({String defaultValue = 'system'}) {
    return getString(keyThemeMode, defaultValue: defaultValue) ?? defaultValue;
  }

  /// Set theme mode
  static Future<bool> setThemeMode(String mode) async {
    return await setString(keyThemeMode, mode);
  }

  /// Check if first run
  static bool isFirstRun() {
    return getBool(keyFirstRun, defaultValue: true) ?? true;
  }

  /// Set first run completed
  static Future<bool> setFirstRunCompleted() async {
    return await setBool(keyFirstRun, false);
  }

  /// Check if onboarding completed
  static bool isOnboardingCompleted() {
    return getBool(keyOnboardingCompleted, defaultValue: false) ?? false;
  }

  /// Set onboarding completed
  static Future<bool> setOnboardingCompleted(bool completed) async {
    return await setBool(keyOnboardingCompleted, completed);
  }
}
