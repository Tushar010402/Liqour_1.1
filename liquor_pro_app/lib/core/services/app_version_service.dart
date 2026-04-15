import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/api_config.dart';
import '../models/app_version_config.dart';
import 'dio_api_service.dart';
import 'notification_navigation_service.dart';

/// Singleton orchestrator for app version checks and force update gating.
/// Pattern matches LoggingService.instance.
class AppVersionService {
  AppVersionService._();
  static final AppVersionService instance = AppVersionService._();

  DioApiService? _apiService;
  SharedPreferences? _prefs;
  PackageInfo? _packageInfo;
  SemanticVersion? _currentVersion;
  AppVersionConfig? _cachedConfig;
  Timer? _periodicTimer;
  bool _isShowingForceUpdate = false;
  bool _initialized = false;

  // SharedPreferences keys
  static const _keyCachedConfig = 'app_version_cached_config';
  static const _keyLastCheck = 'app_version_last_check';
  static const _keySkippedSoftPrefix = 'app_version_skipped_soft_';

  /// Initialize service — call once after DioApiService and SharedPreferences are ready
  Future<void> initialize(DioApiService apiService, SharedPreferences prefs) async {
    if (_initialized) return;
    _apiService = apiService;
    _prefs = prefs;

    try {
      _packageInfo = await PackageInfo.fromPlatform();
      _currentVersion = SemanticVersion.parse(_packageInfo!.version);
      if (kDebugMode) {
        debugPrint('[AppVersion] Initialized — current: $_currentVersion');
      }
    } catch (e) {
      _currentVersion = const SemanticVersion(0, 0, 0);
      if (kDebugMode) {
        debugPrint('[AppVersion] Failed to get package info: $e');
      }
    }

    // Restore cached config
    final cachedJson = _prefs?.getString(_keyCachedConfig);
    if (cachedJson != null) {
      try {
        _cachedConfig = AppVersionConfig.fromJson(
          json.decode(cachedJson) as Map<String, dynamic>,
        );
      } catch (_) {}
    }

    _initialized = true;
  }

  /// Current app version string
  String get currentVersionString => _packageInfo?.version ?? '0.0.0';

  /// Cached config for UI access
  AppVersionConfig? get cachedConfig => _cachedConfig;

  /// Check version against backend
  Future<VersionCheckResult> checkVersion({bool silent = false}) async {
    if (!_initialized || _apiService == null) return VersionCheckResult.checkFailed;

    try {
      final platform = Platform.isIOS ? 'ios' : 'android';
      final response = await _apiService!.get<Map<String, dynamic>>(
        ApiConfig.appVersionCheck,
        queryParams: {
          'platform': platform,
          'current_version': currentVersionString,
        },
      );

      if (!response.success || response.data == null) {
        if (kDebugMode && !silent) {
          debugPrint('[AppVersion] Check failed: ${response.message}');
        }
        return VersionCheckResult.checkFailed;
      }

      final config = AppVersionConfig.fromJson(
        response.data is Map<String, dynamic>
            ? response.data as Map<String, dynamic>
            : {},
      );
      _cachedConfig = config;

      // Persist to prefs
      _prefs?.setString(_keyCachedConfig, json.encode(config.toJson()));
      _prefs?.setString(_keyLastCheck, DateTime.now().toIso8601String());

      return _evaluateConfig(config);
    } catch (e) {
      if (kDebugMode && !silent) {
        debugPrint('[AppVersion] Check error: $e');
      }
      // Never block user on network issues
      return VersionCheckResult.checkFailed;
    }
  }

  /// Evaluate config and determine result
  VersionCheckResult _evaluateConfig(AppVersionConfig config) {
    // Maintenance mode takes priority
    if (config.maintenanceMode) return VersionCheckResult.maintenanceMode;

    // Server says force update, or client-side defense
    if (config.forceUpdate) return VersionCheckResult.forceUpdateRequired;

    // Client-side defense: compare current < minVersion
    final current = _currentVersion ?? const SemanticVersion(0, 0, 0);
    final minVersion = SemanticVersion.parse(config.minVersion);
    if (current < minVersion) return VersionCheckResult.forceUpdateRequired;

    // Soft update
    if (config.updateAvailable) {
      final latestVersion = SemanticVersion.parse(config.latestVersion);
      if (current < latestVersion) return VersionCheckResult.softUpdateAvailable;
    }

    return VersionCheckResult.upToDate;
  }

  /// Called by Dio interceptor on every API response to check version headers
  void handleVersionHeaders(String minVersion, String? latestVersion) {
    if (!_initialized || _currentVersion == null) return;

    final min = SemanticVersion.parse(minVersion);
    if (_currentVersion! < min && !_isShowingForceUpdate) {
      // Update cached config with header info
      _cachedConfig = AppVersionConfig(
        minVersion: minVersion,
        latestVersion: latestVersion ?? minVersion,
        forceUpdate: true,
        updateAvailable: true,
        maintenanceMode: false,
        storeUrl: _cachedConfig?.storeUrl ?? '',
      );
      showForceUpdateScreen(null);
    }
  }

  /// Show non-dismissible force update screen.
  /// Uses a builder callback to avoid circular imports — the caller (splash_screen)
  /// provides the widget, or we use the registered builder.
  void showForceUpdateScreen(BuildContext? context, {bool isMaintenance = false}) {
    if (_isShowingForceUpdate) return;
    _isShowingForceUpdate = true;

    final navigator = NotificationNavigationService.navigatorKey.currentState;
    if (navigator == null) {
      _isShowingForceUpdate = false;
      return;
    }

    navigator.push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) {
          // Build inline since ForceUpdateScreen imports this service
          // We pass data through the registered builder
          return _forceUpdateScreenBuilder?.call(
                config: _cachedConfig,
                currentVersion: currentVersionString,
                isMaintenance: isMaintenance,
              ) ??
              const SizedBox.shrink();
        },
      ),
    );
  }

  // Builder registration to avoid circular imports
  static ForceUpdateScreenBuilder? _forceUpdateScreenBuilder;

  /// Register the force update screen builder (called from main.dart)
  static void registerForceUpdateScreenBuilder(ForceUpdateScreenBuilder builder) {
    _forceUpdateScreenBuilder = builder;
  }

  /// Show dismissible soft update dialog
  void showSoftUpdateDialog() {
    if (_cachedConfig == null) return;

    final version = _cachedConfig!.latestVersion;

    // Check if user already skipped this version within 24h
    final skippedKey = '$_keySkippedSoftPrefix$version';
    final skippedTimestamp = _prefs?.getString(skippedKey);
    if (skippedTimestamp != null) {
      final skippedAt = DateTime.tryParse(skippedTimestamp);
      if (skippedAt != null &&
          DateTime.now().difference(skippedAt).inHours < 24) {
        return; // Already dismissed within 24h
      }
    }

    final navContext = NotificationNavigationService.navigatorKey.currentContext;
    if (navContext == null) return;

    _softUpdateDialogBuilder?.call(
      context: navContext,
      config: _cachedConfig!,
      onSkip: () {
        _prefs?.setString(skippedKey, DateTime.now().toIso8601String());
      },
    );
  }

  static SoftUpdateDialogBuilder? _softUpdateDialogBuilder;

  /// Register the soft update dialog builder (called from main.dart)
  static void registerSoftUpdateDialogBuilder(SoftUpdateDialogBuilder builder) {
    _softUpdateDialogBuilder = builder;
  }

  /// Launch the store URL
  Future<void> launchStoreUrl() async {
    final url = _cachedConfig?.storeUrl;
    if (url == null || url.isEmpty) return;
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (kDebugMode) debugPrint('[AppVersion] Failed to launch store URL: $e');
    }
  }

  /// Reset force update flag (e.g. if screen is popped programmatically)
  void resetForceUpdateFlag() {
    _isShowingForceUpdate = false;
  }

  /// Start periodic background check (every 6 hours)
  void startPeriodicCheck() {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(
      const Duration(hours: 6),
      (_) => checkVersion(silent: true).then((result) {
        if (result == VersionCheckResult.forceUpdateRequired) {
          showForceUpdateScreen(null);
        } else if (result == VersionCheckResult.maintenanceMode) {
          showForceUpdateScreen(null, isMaintenance: true);
        }
      }),
    );
  }

  /// Stop periodic check
  void stopPeriodicCheck() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }
}

/// Builder typedef for force update screen
typedef ForceUpdateScreenBuilder = Widget Function({
  AppVersionConfig? config,
  String currentVersion,
  bool isMaintenance,
});

/// Builder typedef for soft update dialog
typedef SoftUpdateDialogBuilder = void Function({
  required BuildContext context,
  required AppVersionConfig config,
  required VoidCallback onSkip,
});
