import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'log_database.dart';
import 'session_manager.dart';
import '../config/api_config.dart';
import '../utils/logger.dart';

/// Sync status for UI display
enum SyncStatus {
  idle,
  syncing,
  success,
  failed,
  offline,
}

/// Log Sync Service - Handles background sync to backend
///
/// Features:
/// - Batch upload of logs to backend
/// - Automatic sync every 5 minutes
/// - Sync on app backgrounding
/// - WiFi-only option
/// - Retry logic with exponential backoff
/// - Deduplication (mark synced logs)
class LogSyncService {
  static final LogSyncService _instance = LogSyncService._internal();
  factory LogSyncService() => _instance;
  LogSyncService._internal();

  final _db = LogDatabase();
  final _sessionManager = SessionManager();

  // Sync configuration
  static const Duration syncInterval = Duration(minutes: 5);
  static const int maxLogsPerBatch = 50;
  static const int syncThreshold = 100; // Auto-sync when buffer reaches this
  static const int maxRetries = 3;
  static const Duration retryDelay = Duration(seconds: 30);

  // State
  Timer? _syncTimer;
  SyncStatus _status = SyncStatus.idle;
  DateTime? _lastSyncTime;
  int _failedAttempts = 0;
  bool _wifiOnlySync = false;
  bool _syncEnabled = true;

  // Stream for UI updates
  final StreamController<SyncStatus> _statusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get statusStream => _statusController.stream;

  SyncStatus get status => _status;
  DateTime? get lastSyncTime => _lastSyncTime;
  bool get wifiOnlySync => _wifiOnlySync;
  bool get syncEnabled => _syncEnabled;

  /// Initialize sync service
  Future<void> initialize() async {
    // Load preferences
    await _loadPreferences();

    // Start periodic sync timer
    _startSyncTimer();

    if (kDebugMode) {
      Logger.info('🔄 LogSyncService: Initialized (interval: ${syncInterval.inMinutes}min, wifiOnly: $_wifiOnlySync)');
    }
  }

  /// Load saved preferences
  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _wifiOnlySync = prefs.getBool('log_sync_wifi_only') ?? false;
      _syncEnabled = prefs.getBool('log_sync_enabled') ?? true;
      final lastSyncStr = prefs.getString('log_last_sync');
      if (lastSyncStr != null) {
        _lastSyncTime = DateTime.parse(lastSyncStr);
      }
    } catch (e) {
      if (kDebugMode) {
        Logger.error('⚠️ LogSyncService: Error loading preferences: $e');
      }
    }
  }

  /// Save preferences
  Future<void> _savePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('log_sync_wifi_only', _wifiOnlySync);
      await prefs.setBool('log_sync_enabled', _syncEnabled);
      if (_lastSyncTime != null) {
        await prefs.setString('log_last_sync', _lastSyncTime!.toIso8601String());
      }
    } catch (e) {
      if (kDebugMode) {
        Logger.error('⚠️ LogSyncService: Error saving preferences: $e');
      }
    }
  }

  /// Start periodic sync timer
  void _startSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(syncInterval, (_) => _periodicSync());
  }

  /// Periodic sync callback
  Future<void> _periodicSync() async {
    if (!_syncEnabled) return;
    await _performSync();
  }

  /// Check if sync threshold is reached and sync if needed
  Future<void> checkAndSync() async {
    if (!_syncEnabled) return;

    final unsyncedCount = await _db.getUnsyncedLogCount();
    if (unsyncedCount >= syncThreshold) {
      if (kDebugMode) {
        Logger.debug('🔄 LogSyncService: Threshold reached ($unsyncedCount logs), triggering sync');
      }
      await _performSync();
    }
  }

  /// Manual sync trigger
  Future<void> syncNow() async {
    await _performSync();
  }

  /// Perform sync operation
  Future<bool> _performSync() async {
    // Check if already syncing
    if (_status == SyncStatus.syncing) {
      if (kDebugMode) {
        Logger.debug('⏳ LogSyncService: Sync already in progress');
      }
      return false;
    }

    // Check connectivity
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) {
      _setStatus(SyncStatus.offline);
      return false;
    }

    // Check WiFi-only preference
    if (_wifiOnlySync && !connectivity.contains(ConnectivityResult.wifi)) {
      if (kDebugMode) {
        Logger.warning('📵 LogSyncService: Skipping sync (WiFi-only mode, not on WiFi)');
      }
      return false;
    }

    _setStatus(SyncStatus.syncing);

    try {
      // Get unsynced logs
      final unsyncedLogs = await _db.getUnsyncedLogs(limit: maxLogsPerBatch);

      if (unsyncedLogs.isEmpty) {
        if (kDebugMode) {
          Logger.debug('✅ LogSyncService: No logs to sync');
        }
        _setStatus(SyncStatus.success);
        _lastSyncTime = DateTime.now();
        await _savePreferences();
        return true;
      }

      if (kDebugMode) {
        Logger.debug('📤 LogSyncService: Syncing ${unsyncedLogs.length} logs...');
      }

      // Build sync payload
      final payload = _buildSyncPayload(unsyncedLogs);

      // Send to backend
      final success = await _sendToBackend(payload);

      if (success) {
        // Mark logs as synced
        final ids = unsyncedLogs.map((l) => l['id'] as String).toList();
        await _db.markLogsSynced(ids);

        _failedAttempts = 0;
        _lastSyncTime = DateTime.now();
        await _savePreferences();
        _setStatus(SyncStatus.success);

        if (kDebugMode) {
          Logger.info('✅ LogSyncService: Synced ${unsyncedLogs.length} logs successfully');
        }

        // Check if more logs need syncing
        final remaining = await _db.getUnsyncedLogCount();
        if (remaining > 0) {
          // Schedule another sync soon
          Future.delayed(const Duration(seconds: 5), _performSync);
        }

        return true;
      } else {
        throw Exception('Backend returned failure');
      }
    } catch (e) {
      _failedAttempts++;
      _setStatus(SyncStatus.failed);

      if (kDebugMode) {
        Logger.error('❌ LogSyncService: Sync failed (attempt $_failedAttempts): $e');
      }

      // Schedule retry with exponential backoff
      if (_failedAttempts < maxRetries) {
        final delay = retryDelay * _failedAttempts;
        if (kDebugMode) {
          Logger.info('🔄 LogSyncService: Retrying in ${delay.inSeconds}s...');
        }
        Future.delayed(delay, _performSync);
      }

      return false;
    }
  }

  /// Build sync payload - formatted to match VPS backend LogBatchRequest
  /// API Contract: POST /api/logs/batch
  Map<String, dynamic> _buildSyncPayload(List<Map<String, dynamic>> logs) {
    final deviceInfo = _sessionManager.getDeviceInfo();
    final sessionInfo = _sessionManager.getSessionInfo();

    // OS info already includes version from SessionManager (e.g., "iOS 17.2" or "Android 14")
    final osVersion = deviceInfo['os'] as String? ?? 'unknown';

    return {
      'batch_id': 'batch-${DateTime.now().millisecondsSinceEpoch}',
      'device': {
        'id': deviceInfo['id'] ?? 'unknown',
        'model': deviceInfo['model'] ?? 'unknown',
        'os': osVersion,  // Full OS string including version
        'app_version': deviceInfo['app_version'] ?? '1.0.0',
      },
      'session': {
        'id': sessionInfo['id'] ?? 'unknown',
        'started_at': sessionInfo['started_at'] ?? DateTime.now().toUtc().toIso8601String(),
        'user_id': sessionInfo['user_id'],  // Include user_id
        'tenant_id': sessionInfo['tenant_id'],  // Include tenant_id
      },
      'logs': logs.map((log) {
        final entry = <String, dynamic>{
          'id': log['id'],  // Use 'id' not 'client_log_id'
          'timestamp': log['timestamp'],
          'level': log['level']?.toLowerCase() ?? 'info',
          'tag': log['tag'] ?? 'General',
          'message': log['message'] ?? '',
        };

        // Add optional stack_trace
        if (log['stack_trace'] != null) {
          entry['stack_trace'] = log['stack_trace'];
        }

        // Parse metadata and extract screen_name if available
        if (log['metadata'] != null) {
          try {
            final metadata = jsonDecode(log['metadata'] as String) as Map<String, dynamic>;
            // Extract screen_name from metadata if present
            if (metadata['screen'] != null) {
              entry['screen_name'] = metadata['screen'];
            } else if (metadata['screen_name'] != null) {
              entry['screen_name'] = metadata['screen_name'];
            }
            entry['metadata'] = metadata;
          } catch (_) {
            entry['metadata'] = {'raw': log['metadata']};
          }
        }

        return entry;
      }).toList(),
    };
  }

  /// Send payload to backend
  /// POST /api/logs/batch with JWT auth and X-Tenant-ID header
  Future<bool> _sendToBackend(Map<String, dynamic> payload) async {
    try {
      // Get auth token and tenant ID from secure storage and prefs
      final secureStorage = const FlutterSecureStorage();
      final prefs = await SharedPreferences.getInstance();

      // Read token from secure storage
      String? token;
      try {
        if (Platform.isIOS) {
          token = await secureStorage.read(
            key: 'auth_token',
            iOptions: const IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
              accountName: 'com.liquorproapp.store',
            ),
          );
        } else {
          token = await secureStorage.read(
            key: 'auth_token',
            aOptions: const AndroidOptions(encryptedSharedPreferences: true),
          );
        }
      } catch (e) {
        if (kDebugMode) {
          Logger.error('⚠️ LogSyncService: Error reading token: $e');
        }
      }

      // Get tenant ID from shared preferences
      final tenantId = prefs.getString('tenant_id');

      if (token == null) {
        if (kDebugMode) {
          Logger.warning('⚠️ LogSyncService: No auth token available, skipping sync');
        }
        return false;
      }

      // Build request URL
      final url = Uri.parse('${ApiConfig.baseUrl}/api/logs/batch');

      // Build headers
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      };

      // Add tenant ID if available
      if (tenantId != null && tenantId.isNotEmpty) {
        headers['X-Tenant-ID'] = tenantId;
      }

      // Send request
      final body = jsonEncode(payload);
      final logCount = (payload['logs'] as List).length;

      if (kDebugMode) {
        Logger.debug('📤 LogSyncService: Sending $logCount logs to backend...');
        Logger.debug('   URL: $url');
        Logger.debug('   Payload size: ${body.length} bytes');
      }

      final response = await http
          .post(url, headers: headers, body: body)
          .timeout(const Duration(seconds: 30));

      if (kDebugMode) {
        Logger.debug('📥 LogSyncService: Response status: ${response.statusCode}');
      }

      // Check for success
      if (response.statusCode >= 200 && response.statusCode < 300) {
        try {
          final responseData = jsonDecode(response.body);
          if (kDebugMode) {
            Logger.info('✅ LogSyncService: Logs synced successfully');
            Logger.debug('   Received: ${responseData['received'] ?? logCount}');
            Logger.debug('   Session ID: ${responseData['session_id'] ?? 'N/A'}');
            Logger.debug('   Batch ID: ${responseData['batch_id'] ?? payload['batch_id']}');
          }
        } catch (_) {
          // Response parsing failed but request succeeded
          if (kDebugMode) {
            Logger.info('✅ LogSyncService: Logs synced (response parsing skipped)');
          }
        }
        return true;
      } else {
        if (kDebugMode) {
          Logger.error('❌ LogSyncService: Backend returned error ${response.statusCode}');
          Logger.error('   Body: ${response.body}');
        }
        return false;
      }
    } on SocketException catch (e) {
      if (kDebugMode) {
        Logger.error('❌ LogSyncService: Network error - ${e.message}');
      }
      return false;
    } on http.ClientException catch (e) {
      if (kDebugMode) {
        Logger.error('❌ LogSyncService: HTTP error - ${e.message}');
      }
      return false;
    } on TimeoutException {
      if (kDebugMode) {
        Logger.error('❌ LogSyncService: Request timeout');
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        Logger.error('❌ LogSyncService: Unexpected error - $e');
      }
      return false;
    }
  }

  /// Set sync status and notify listeners
  void _setStatus(SyncStatus status) {
    _status = status;
    _statusController.add(status);
  }

  // ==================== SETTINGS ====================

  /// Enable/disable sync
  Future<void> setSyncEnabled(bool enabled) async {
    _syncEnabled = enabled;
    await _savePreferences();

    if (enabled) {
      _startSyncTimer();
    } else {
      _syncTimer?.cancel();
    }

    if (kDebugMode) {
      Logger.info('⚙️ LogSyncService: Sync ${enabled ? 'enabled' : 'disabled'}');
    }
  }

  /// Set WiFi-only sync preference
  Future<void> setWifiOnlySync(bool wifiOnly) async {
    _wifiOnlySync = wifiOnly;
    await _savePreferences();

    if (kDebugMode) {
      Logger.debug('⚙️ LogSyncService: WiFi-only sync ${wifiOnly ? 'enabled' : 'disabled'}');
    }
  }

  // ==================== STATS ====================

  /// Get sync statistics
  Future<Map<String, dynamic>> getSyncStats() async {
    final total = await _db.getTotalLogCount();
    final unsynced = await _db.getUnsyncedLogCount();

    return {
      'total_logs': total,
      'unsynced_logs': unsynced,
      'synced_logs': total - unsynced,
      'last_sync': _lastSyncTime?.toIso8601String(),
      'status': _status.name,
      'failed_attempts': _failedAttempts,
      'wifi_only': _wifiOnlySync,
      'enabled': _syncEnabled,
    };
  }

  // ==================== LIFECYCLE ====================

  /// Called when app goes to background
  Future<void> onAppBackground() async {
    if (_syncEnabled) {
      if (kDebugMode) {
        Logger.debug('📤 LogSyncService: App backgrounding, triggering sync');
      }
      await _performSync();
    }
  }

  /// Shutdown service
  Future<void> shutdown() async {
    _syncTimer?.cancel();
    _statusController.close();

    // Final sync before shutdown
    if (_syncEnabled) {
      await _performSync();
    }

    if (kDebugMode) {
      Logger.info('🛑 LogSyncService: Shutdown complete');
    }
  }
}
