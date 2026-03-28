import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'log_database.dart';

/// Session Manager - Tracks user sessions for logging
///
/// Features:
/// - Generates unique session ID per app launch
/// - Captures device info, app version, user context
/// - Tracks screens visited during session
/// - Updates session end time on app close
class SessionManager {
  static final SessionManager _instance = SessionManager._internal();
  factory SessionManager() => _instance;
  SessionManager._internal();

  final _uuid = const Uuid();
  final _db = LogDatabase();

  String? _currentSessionId;
  String? _deviceId;
  String? _deviceModel;
  String? _osVersion;
  String? _appVersion;
  String? _userId;
  String? _tenantId;
  final List<String> _screensVisited = [];
  DateTime? _sessionStartTime;

  /// Get current session ID
  String get currentSessionId => _currentSessionId ?? 'unknown';

  /// Get device ID (persistent across sessions)
  String get deviceId => _deviceId ?? 'unknown';

  /// Get device model
  String get deviceModel => _deviceModel ?? 'unknown';

  /// Get OS version
  String get osVersion => _osVersion ?? 'unknown';

  /// Get app version
  String get appVersion => _appVersion ?? 'unknown';

  /// Check if session is active
  bool get hasActiveSession => _currentSessionId != null;

  /// Initialize session manager and start a new session
  Future<void> initialize() async {
    await _loadDeviceInfo();
    await startNewSession();
  }

  /// Load device information
  Future<void> _loadDeviceInfo() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final packageInfo = await PackageInfo.fromPlatform();

      _appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';

      if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        _deviceId = info.identifierForVendor ?? _uuid.v4();
        _deviceModel = info.model;
        _osVersion = '${info.systemName} ${info.systemVersion}';
      } else if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        _deviceId = info.id;
        _deviceModel = '${info.brand} ${info.model}';
        _osVersion = 'Android ${info.version.release} (SDK ${info.version.sdkInt})';
      } else {
        _deviceId = _uuid.v4();
        _deviceModel = 'Unknown';
        _osVersion = Platform.operatingSystem;
      }

      if (kDebugMode) {
        print('📱 SessionManager: Device loaded - $_deviceModel, $_osVersion');
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ SessionManager: Error loading device info: $e');
      }
      _deviceId = _uuid.v4();
      _deviceModel = 'Unknown';
      _osVersion = Platform.operatingSystem;
      _appVersion = '1.0.0';
    }
  }

  /// Start a new session
  Future<String> startNewSession() async {
    // End previous session if exists
    if (_currentSessionId != null) {
      await endCurrentSession();
    }

    _currentSessionId = _uuid.v4();
    _sessionStartTime = DateTime.now();
    _screensVisited.clear();

    // Save session to database
    await _db.upsertSession({
      'id': _currentSessionId,
      'started_at': _sessionStartTime!.toIso8601String(),
      'ended_at': null,
      'device_id': _deviceId ?? 'unknown',
      'device_model': _deviceModel,
      'os_version': _osVersion,
      'app_version': _appVersion ?? '1.0.0',
      'user_id': _userId,
      'tenant_id': _tenantId,
      'log_count': 0,
      'error_count': 0,
      'screens_visited': '[]',
    });

    if (kDebugMode) {
      print('🆕 SessionManager: New session started - $_currentSessionId');
    }

    return _currentSessionId!;
  }

  /// End current session
  Future<void> endCurrentSession() async {
    if (_currentSessionId == null) return;

    try {
      await _db.updateSessionEnd(_currentSessionId!);

      if (kDebugMode) {
        final duration = DateTime.now().difference(_sessionStartTime!);
        print('🏁 SessionManager: Session ended - $_currentSessionId (${duration.inMinutes} min, ${_screensVisited.length} screens)');
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ SessionManager: Error ending session: $e');
      }
    }

    _currentSessionId = null;
    _sessionStartTime = null;
  }

  /// Set user context (after login)
  Future<void> setUserContext({
    required String userId,
    required String tenantId,
  }) async {
    _userId = userId;
    _tenantId = tenantId;

    // Update current session with user info
    if (_currentSessionId != null) {
      final db = await _db.database;
      await db.update(
        'sessions',
        {
          'user_id': userId,
          'tenant_id': tenantId,
        },
        where: 'id = ?',
        whereArgs: [_currentSessionId],
      );
    }

    if (kDebugMode) {
      print('👤 SessionManager: User context set - $userId');
    }
  }

  /// Clear user context (on logout)
  void clearUserContext() {
    _userId = null;
    _tenantId = null;

    if (kDebugMode) {
      print('👤 SessionManager: User context cleared');
    }
  }

  /// Record screen visit
  Future<void> recordScreenVisit(String screenName) async {
    if (!_screensVisited.contains(screenName)) {
      _screensVisited.add(screenName);

      // Update session with screens visited
      if (_currentSessionId != null) {
        try {
          final db = await _db.database;
          await db.update(
            'sessions',
            {
              'screens_visited': _screensVisited.join(','),
            },
            where: 'id = ?',
            whereArgs: [_currentSessionId],
          );
        } catch (e) {
          // Non-critical, ignore
        }
      }
    }
  }

  /// Get session duration
  Duration get sessionDuration {
    if (_sessionStartTime == null) return Duration.zero;
    return DateTime.now().difference(_sessionStartTime!);
  }

  /// Get screens visited in current session
  List<String> get screensVisited => List.unmodifiable(_screensVisited);

  /// Get session info for sync
  Map<String, dynamic> getSessionInfo() {
    return {
      'id': _currentSessionId,
      'started_at': _sessionStartTime?.toIso8601String(),
      'user_id': _userId,
      'tenant_id': _tenantId,
    };
  }

  /// Get device info for sync
  Map<String, dynamic> getDeviceInfo() {
    return {
      'id': _deviceId,
      'model': _deviceModel,
      'os': _osVersion,
      'app_version': _appVersion,
    };
  }
}
