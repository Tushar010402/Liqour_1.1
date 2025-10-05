import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../utils/logger.dart';

/// Preferences Service - State Persistence
/// Manages user preferences and app state across sessions
class PreferencesService {
  static PreferencesService? _instance;
  static SharedPreferences? _prefs;

  PreferencesService._();

  /// Singleton instance
  static Future<PreferencesService> getInstance() async {
    if (_instance == null) {
      _instance = PreferencesService._();
      await _instance!._init();
    }
    return _instance!;
  }

  /// Initialize SharedPreferences
  Future<void> _init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      Logger.info('PreferencesService initialized');
    } catch (e) {
      Logger.error('Failed to initialize PreferencesService', e);
      rethrow;
    }
  }

  /// Ensure preferences are initialized
  Future<void> _ensureInitialized() async {
    if (_prefs == null) {
      await _init();
    }
  }

  // ==================== String Operations ====================

  /// Save string value
  Future<bool> setString(String key, String value) async {
    await _ensureInitialized();
    try {
      final result = await _prefs!.setString(key, value);
      Logger.info('Saved string: $key = $value');
      return result;
    } catch (e) {
      Logger.error('Failed to save string: $key', e);
      return false;
    }
  }

  /// Get string value
  String? getString(String key, {String? defaultValue}) {
    return _prefs?.getString(key) ?? defaultValue;
  }

  // ==================== Int Operations ====================

  /// Save int value
  Future<bool> setInt(String key, int value) async {
    await _ensureInitialized();
    try {
      final result = await _prefs!.setInt(key, value);
      Logger.info('Saved int: $key = $value');
      return result;
    } catch (e) {
      Logger.error('Failed to save int: $key', e);
      return false;
    }
  }

  /// Get int value
  int? getInt(String key, {int? defaultValue}) {
    return _prefs?.getInt(key) ?? defaultValue;
  }

  // ==================== Double Operations ====================

  /// Save double value
  Future<bool> setDouble(String key, double value) async {
    await _ensureInitialized();
    try {
      final result = await _prefs!.setDouble(key, value);
      Logger.info('Saved double: $key = $value');
      return result;
    } catch (e) {
      Logger.error('Failed to save double: $key', e);
      return false;
    }
  }

  /// Get double value
  double? getDouble(String key, {double? defaultValue}) {
    return _prefs?.getDouble(key) ?? defaultValue;
  }

  // ==================== Bool Operations ====================

  /// Save bool value
  Future<bool> setBool(String key, bool value) async {
    await _ensureInitialized();
    try {
      final result = await _prefs!.setBool(key, value);
      Logger.info('Saved bool: $key = $value');
      return result;
    } catch (e) {
      Logger.error('Failed to save bool: $key', e);
      return false;
    }
  }

  /// Get bool value
  bool? getBool(String key, {bool? defaultValue}) {
    return _prefs?.getBool(key) ?? defaultValue;
  }

  // ==================== List Operations ====================

  /// Save string list
  Future<bool> setStringList(String key, List<String> value) async {
    await _ensureInitialized();
    try {
      final result = await _prefs!.setStringList(key, value);
      Logger.info('Saved string list: $key (${value.length} items)');
      return result;
    } catch (e) {
      Logger.error('Failed to save string list: $key', e);
      return false;
    }
  }

  /// Get string list
  List<String>? getStringList(String key) {
    return _prefs?.getStringList(key);
  }

  // ==================== JSON Operations ====================

  /// Save JSON object
  Future<bool> setJson(String key, Map<String, dynamic> value) async {
    await _ensureInitialized();
    try {
      final jsonString = json.encode(value);
      final result = await _prefs!.setString(key, jsonString);
      Logger.info('Saved JSON: $key');
      return result;
    } catch (e) {
      Logger.error('Failed to save JSON: $key', e);
      return false;
    }
  }

  /// Get JSON object
  Map<String, dynamic>? getJson(String key) {
    try {
      final jsonString = _prefs?.getString(key);
      if (jsonString == null) return null;
      return json.decode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      Logger.error('Failed to parse JSON: $key', e);
      return null;
    }
  }

  // ==================== Remove & Clear ====================

  /// Remove specific key
  Future<bool> remove(String key) async {
    await _ensureInitialized();
    try {
      final result = await _prefs!.remove(key);
      Logger.info('Removed key: $key');
      return result;
    } catch (e) {
      Logger.error('Failed to remove key: $key', e);
      return false;
    }
  }

  /// Clear all preferences
  Future<bool> clear() async {
    await _ensureInitialized();
    try {
      final result = await _prefs!.clear();
      Logger.warning('Cleared all preferences');
      return result;
    } catch (e) {
      Logger.error('Failed to clear preferences', e);
      return false;
    }
  }

  /// Check if key exists
  bool containsKey(String key) {
    return _prefs?.containsKey(key) ?? false;
  }

  /// Get all keys
  Set<String> getKeys() {
    return _prefs?.getKeys() ?? {};
  }
}

/// Preference Keys - Centralized key management
class PrefKeys {
  PrefKeys._();

  // User Preferences
  static const String selectedShopId = 'selected_shop_id';
  static const String selectedShopName = 'selected_shop_name';
  static const String lastSelectedCategory = 'last_selected_category';
  static const String lastSelectedSubcategory = 'last_selected_subcategory';

  // UI Preferences
  static const String theme = 'theme'; // 'light' or 'dark'
  static const String language = 'language';
  static const String gridView = 'grid_view'; // true for grid, false for list
  static const String showStockInput = 'show_stock_input';

  // Search History
  static const String searchHistory = 'search_history';
  static const String recentSearches = 'recent_searches';

  // Onboarding
  static const String onboardingCompleted = 'onboarding_completed';
  static const String firstLaunch = 'first_launch';

  // Session
  static const String lastLoginTime = 'last_login_time';
  static const String sessionCount = 'session_count';

  // Feature Flags
  static const String enableAnalytics = 'enable_analytics';
  static const String enableNotifications = 'enable_notifications';
  static const String enableHapticFeedback = 'enable_haptic_feedback';

  // Cache
  static const String lastDataSync = 'last_data_sync';
  static const String cacheExpiry = 'cache_expiry';
}

/// User Preferences Manager - High-level preference management
class UserPreferences {
  final PreferencesService _prefs;

  UserPreferences(this._prefs);

  // ==================== Shop Selection ====================

  Future<void> saveSelectedShop(String shopId, String shopName) async {
    await _prefs.setString(PrefKeys.selectedShopId, shopId);
    await _prefs.setString(PrefKeys.selectedShopName, shopName);
  }

  String? getSelectedShopId() {
    return _prefs.getString(PrefKeys.selectedShopId);
  }

  String? getSelectedShopName() {
    return _prefs.getString(PrefKeys.selectedShopName);
  }

  Future<void> clearSelectedShop() async {
    await _prefs.remove(PrefKeys.selectedShopId);
    await _prefs.remove(PrefKeys.selectedShopName);
  }

  // ==================== Category Selection ====================

  Future<void> saveLastCategory(String categoryId) async {
    await _prefs.setString(PrefKeys.lastSelectedCategory, categoryId);
  }

  String? getLastCategory() {
    return _prefs.getString(PrefKeys.lastSelectedCategory);
  }

  Future<void> saveLastSubcategory(String subcategoryId) async {
    await _prefs.setString(PrefKeys.lastSelectedSubcategory, subcategoryId);
  }

  String? getLastSubcategory() {
    return _prefs.getString(PrefKeys.lastSelectedSubcategory);
  }

  // ==================== UI Preferences ====================

  Future<void> setTheme(String theme) async {
    await _prefs.setString(PrefKeys.theme, theme);
  }

  String getTheme() {
    return _prefs.getString(PrefKeys.theme, defaultValue: 'light')!;
  }

  bool isDarkMode() {
    return getTheme() == 'dark';
  }

  Future<void> setGridView(bool isGrid) async {
    await _prefs.setBool(PrefKeys.gridView, isGrid);
  }

  bool isGridView() {
    return _prefs.getBool(PrefKeys.gridView, defaultValue: false)!;
  }

  Future<void> setShowStockInput(bool show) async {
    await _prefs.setBool(PrefKeys.showStockInput, show);
  }

  bool getShowStockInput() {
    return _prefs.getBool(PrefKeys.showStockInput, defaultValue: true)!;
  }

  // ==================== Search History ====================

  Future<void> addSearchQuery(String query) async {
    final history = getSearchHistory();
    if (!history.contains(query)) {
      history.insert(0, query);
      // Keep only last 20 searches
      if (history.length > 20) {
        history.removeLast();
      }
      await _prefs.setStringList(PrefKeys.searchHistory, history);
    }
  }

  List<String> getSearchHistory() {
    return _prefs.getStringList(PrefKeys.searchHistory) ?? [];
  }

  Future<void> clearSearchHistory() async {
    await _prefs.remove(PrefKeys.searchHistory);
  }

  // ==================== Feature Flags ====================

  Future<void> setHapticFeedback(bool enabled) async {
    await _prefs.setBool(PrefKeys.enableHapticFeedback, enabled);
  }

  bool isHapticFeedbackEnabled() {
    return _prefs.getBool(PrefKeys.enableHapticFeedback, defaultValue: true)!;
  }

  Future<void> setAnalytics(bool enabled) async {
    await _prefs.setBool(PrefKeys.enableAnalytics, enabled);
  }

  bool isAnalyticsEnabled() {
    return _prefs.getBool(PrefKeys.enableAnalytics, defaultValue: true)!;
  }

  Future<void> setNotifications(bool enabled) async {
    await _prefs.setBool(PrefKeys.enableNotifications, enabled);
  }

  bool areNotificationsEnabled() {
    return _prefs.getBool(PrefKeys.enableNotifications, defaultValue: true)!;
  }

  // ==================== Session Management ====================

  Future<void> recordLogin() async {
    await _prefs.setString(
      PrefKeys.lastLoginTime,
      DateTime.now().toIso8601String(),
    );
    final count = _prefs.getInt(PrefKeys.sessionCount, defaultValue: 0)!;
    await _prefs.setInt(PrefKeys.sessionCount, count + 1);
  }

  DateTime? getLastLoginTime() {
    final timeString = _prefs.getString(PrefKeys.lastLoginTime);
    if (timeString == null) return null;
    return DateTime.tryParse(timeString);
  }

  int getSessionCount() {
    return _prefs.getInt(PrefKeys.sessionCount, defaultValue: 0)!;
  }

  // ==================== Onboarding ====================

  Future<void> completeOnboarding() async {
    await _prefs.setBool(PrefKeys.onboardingCompleted, true);
  }

  bool isOnboardingCompleted() {
    return _prefs.getBool(PrefKeys.onboardingCompleted, defaultValue: false)!;
  }

  bool isFirstLaunch() {
    final isFirst = _prefs.getBool(PrefKeys.firstLaunch, defaultValue: true)!;
    if (isFirst) {
      _prefs.setBool(PrefKeys.firstLaunch, false);
    }
    return isFirst;
  }
}
