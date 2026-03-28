import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'log_database.dart';
import 'session_manager.dart';
import 'privacy_filter.dart';
import 'log_sync_service.dart';

/// Log levels matching backend expectations
enum LogLevel {
  debug,
  info,
  warning,
  error,
  success,
}

/// Enhanced log entry with metadata and sync status
class LogEntry {
  final String id;
  final DateTime timestamp;
  final LogLevel level;
  final String tag;
  final String message;
  final String? stackTrace;
  final String sessionId;
  final Map<String, dynamic>? metadata;
  final bool isSynced;
  final DateTime? syncedAt;

  LogEntry({
    required this.id,
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    this.stackTrace,
    required this.sessionId,
    this.metadata,
    this.isSynced = false,
    this.syncedAt,
  });

  /// Create from database row
  factory LogEntry.fromMap(Map<String, dynamic> map) {
    return LogEntry(
      id: map['id'] as String,
      timestamp: DateTime.parse(map['timestamp'] as String),
      level: LogLevel.values.firstWhere(
        (l) => l.name == map['level'],
        orElse: () => LogLevel.info,
      ),
      tag: map['tag'] as String,
      message: map['message'] as String,
      stackTrace: map['stack_trace'] as String?,
      sessionId: map['session_id'] as String,
      metadata: map['metadata'] != null
          ? jsonDecode(map['metadata'] as String) as Map<String, dynamic>
          : null,
      isSynced: (map['is_synced'] as int?) == 1,
      syncedAt: map['synced_at'] != null
          ? DateTime.parse(map['synced_at'] as String)
          : null,
    );
  }

  /// Convert to database row
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'level': level.name,
      'tag': tag,
      'message': message,
      'stack_trace': stackTrace,
      'session_id': sessionId,
      'metadata': metadata != null ? jsonEncode(metadata) : null,
      'is_synced': isSynced ? 1 : 0,
      'synced_at': syncedAt?.toIso8601String(),
      'created_at': DateTime.now().toIso8601String(),
    };
  }

  /// Convert to JSON for sync
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'level': level.name,
      'tag': tag,
      'message': message,
      if (stackTrace != null) 'stack_trace': stackTrace,
      if (metadata != null) 'metadata': metadata,
    };
  }

  /// Formatted time for display
  String get formattedTime {
    return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}.${timestamp.millisecond.toString().padLeft(3, '0')}';
  }

  /// Level icon for display
  String get levelIcon {
    switch (level) {
      case LogLevel.debug: return '🔍';
      case LogLevel.info: return 'ℹ️';
      case LogLevel.warning: return '⚠️';
      case LogLevel.error: return '❌';
      case LogLevel.success: return '✅';
    }
  }

  /// Level name for display
  String get levelName {
    switch (level) {
      case LogLevel.debug: return 'DEBUG';
      case LogLevel.info: return 'INFO';
      case LogLevel.warning: return 'WARN';
      case LogLevel.error: return 'ERROR';
      case LogLevel.success: return 'SUCCESS';
    }
  }

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.write('[$formattedTime] $levelIcon [$tag] $message');
    if (stackTrace != null) {
      buffer.write('\n$stackTrace');
    }
    return buffer.toString();
  }
}

/// Industrial-grade Logging Service
///
/// Features:
/// - Persistent storage via SQLite
/// - In-memory buffer for real-time display
/// - Automatic privacy filtering
/// - Session tracking
/// - Background sync to backend
/// - Flutter error handling
class LoggingService {
  static final LoggingService _instance = LoggingService._internal();
  factory LoggingService() => _instance;
  LoggingService._internal();

  /// Singleton instance accessor
  static LoggingService get instance => _instance;

  final _uuid = const Uuid();
  final _db = LogDatabase();
  final _sessionManager = SessionManager();
  late final LogSyncService _syncService;

  /// In-memory buffer for real-time UI display (last 200 entries)
  final List<LogEntry> _memoryBuffer = [];
  static const int _maxMemoryBuffer = 200;

  /// Stream controller for real-time log updates
  final StreamController<LogEntry> _logController = StreamController<LogEntry>.broadcast();

  /// Stream of new log entries
  Stream<LogEntry> get logStream => _logController.stream;

  /// Get in-memory logs
  List<LogEntry> get recentLogs => List.unmodifiable(_memoryBuffer);

  /// Check if initialized
  bool _initialized = false;
  bool get isInitialized => _initialized;

  /// Initialize the logging service
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Initialize database
      await _db.database;

      // Initialize session manager
      await _sessionManager.initialize();

      // Initialize sync service
      _syncService = LogSyncService();
      await _syncService.initialize();

      _initialized = true;

      // Log initialization
      info('LoggingService', 'Logging service initialized');
      info('LoggingService', 'Session: ${_sessionManager.currentSessionId}');
      info('LoggingService', 'Device: ${_sessionManager.deviceModel}');

      if (kDebugMode) {
        print('✅ LoggingService: Initialized successfully');
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('❌ LoggingService: Initialization failed: $e');
        print(stackTrace);
      }
    }
  }

  // ==================== LOGGING METHODS ====================

  /// Log a message
  Future<void> log(
    LogLevel level,
    String tag,
    String message, {
    String? stackTrace,
    Map<String, dynamic>? metadata,
  }) async {
    if (!_initialized) {
      // Fallback to debug print if not initialized
      if (kDebugMode) {
        print('[$tag] $message');
      }
      return;
    }

    // Apply privacy filter
    final sanitizedMessage = PrivacyFilter.sanitizeMessage(message);
    final sanitizedMetadata = metadata != null ? PrivacyFilter.redactMap(metadata) : null;

    final entry = LogEntry(
      id: _uuid.v4(),
      timestamp: DateTime.now(),
      level: level,
      tag: tag,
      message: sanitizedMessage,
      stackTrace: stackTrace,
      sessionId: _sessionManager.currentSessionId,
      metadata: sanitizedMetadata,
    );

    // Add to memory buffer
    _addToMemoryBuffer(entry);

    // Persist to database
    await _db.insertLog(entry.toMap());

    // Notify listeners
    _logController.add(entry);

    // Console output in debug mode
    if (kDebugMode) {
      debugPrint(entry.toString());
    }

    // Check if sync is needed
    _checkSyncThreshold();
  }

  /// Add to memory buffer with size limit
  void _addToMemoryBuffer(LogEntry entry) {
    _memoryBuffer.add(entry);
    while (_memoryBuffer.length > _maxMemoryBuffer) {
      _memoryBuffer.removeAt(0);
    }
  }

  /// Check if sync threshold is reached
  void _checkSyncThreshold() {
    // Trigger sync if buffer has 100+ unsynced logs
    _syncService.checkAndSync();
  }

  // ==================== CONVENIENCE METHODS ====================

  /// Log debug message
  Future<void> debug(String tag, String message, {Map<String, dynamic>? metadata}) async {
    await log(LogLevel.debug, tag, message, metadata: metadata);
  }

  /// Log info message
  Future<void> info(String tag, String message, {Map<String, dynamic>? metadata}) async {
    await log(LogLevel.info, tag, message, metadata: metadata);
  }

  /// Log warning message
  Future<void> warning(String tag, String message, {Map<String, dynamic>? metadata}) async {
    await log(LogLevel.warning, tag, message, metadata: metadata);
  }

  /// Log success message
  Future<void> success(String tag, String message, {Map<String, dynamic>? metadata}) async {
    await log(LogLevel.success, tag, message, metadata: metadata);
  }

  /// Log error message
  Future<void> error(
    String tag,
    String message, {
    dynamic exception,
    StackTrace? stackTrace,
    Map<String, dynamic>? metadata,
  }) async {
    final errorMessage = exception != null ? '$message: $exception' : message;
    await log(
      LogLevel.error,
      tag,
      errorMessage,
      stackTrace: stackTrace?.toString(),
      metadata: metadata,
    );
  }

  // ==================== SPECIALIZED LOGGING ====================

  /// Log API request
  Future<void> logApiRequest({
    required String method,
    required String url,
    Map<String, dynamic>? headers,
    dynamic body,
    String? requestId,
  }) async {
    final sanitizedUrl = PrivacyFilter.redactUrl(url);
    final sanitizedHeaders = headers != null ? PrivacyFilter.redactHeaders(headers) : null;

    await info('API', '$method $sanitizedUrl', metadata: {
      'type': 'request',
      'method': method,
      'url': sanitizedUrl,
      if (sanitizedHeaders != null) 'headers': sanitizedHeaders,
      if (requestId != null) 'request_id': requestId,
    });
  }

  /// Log API response
  Future<void> logApiResponse({
    required String method,
    required String url,
    required int statusCode,
    int? durationMs,
    dynamic body,
    String? requestId,
  }) async {
    final sanitizedUrl = PrivacyFilter.redactUrl(url);
    final isError = statusCode >= 400;

    final level = isError ? LogLevel.error : LogLevel.info;
    final message = '$method $sanitizedUrl → $statusCode${durationMs != null ? ' (${durationMs}ms)' : ''}';

    await log(level, 'API', message, metadata: {
      'type': 'response',
      'method': method,
      'url': sanitizedUrl,
      'status_code': statusCode,
      if (durationMs != null) 'duration_ms': durationMs,
      if (requestId != null) 'request_id': requestId,
    });
  }

  /// Log navigation event
  Future<void> logNavigation({
    required String from,
    required String to,
    Map<String, dynamic>? arguments,
  }) async {
    await info('Navigation', '$from → $to', metadata: {
      'from': from,
      'to': to,
      if (arguments != null) 'arguments': PrivacyFilter.redactMap(arguments),
    });

    // Record screen visit
    _sessionManager.recordScreenVisit(to);
  }

  /// Log user action
  Future<void> logUserAction({
    required String action,
    String? screen,
    Map<String, dynamic>? data,
  }) async {
    await info('UserAction', action, metadata: {
      'action': action,
      if (screen != null) 'screen': screen,
      if (data != null) 'data': PrivacyFilter.redactMap(data),
    });
  }

  /// Log Flutter error
  void logFlutterError(FlutterErrorDetails details) {
    error(
      'Flutter',
      details.exceptionAsString(),
      stackTrace: details.stack,
      metadata: {
        'context': details.context?.toString(),
        'library': details.library,
      },
    );
  }

  /// Log unhandled error (from error zone)
  void logUnhandledError(Object error, StackTrace stackTrace) {
    this.error(
      'Unhandled',
      error.toString(),
      exception: error,
      stackTrace: stackTrace,
      metadata: {
        'type': 'unhandled_exception',
      },
    );
  }

  // ==================== QUERY METHODS ====================

  /// Get filtered logs from memory buffer (synchronous for UI)
  List<LogEntry> getFilteredLogs({
    LogLevel? level,
    String? tag,
    String? search,
  }) {
    return _memoryBuffer.where((entry) {
      if (level != null && entry.level != level) return false;
      if (tag != null && entry.tag != tag) return false;
      if (search != null && search.isNotEmpty) {
        final query = search.toLowerCase();
        if (!entry.message.toLowerCase().contains(query) &&
            !entry.tag.toLowerCase().contains(query)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  /// Get log count by level (synchronous for UI)
  Map<LogLevel, int> get logCountByLevel {
    final counts = <LogLevel, int>{};
    for (final level in LogLevel.values) {
      counts[level] = 0;
    }
    for (final entry in _memoryBuffer) {
      counts[entry.level] = (counts[entry.level] ?? 0) + 1;
    }
    return counts;
  }

  /// Get unique tags from memory buffer (synchronous for UI)
  List<String> get uniqueTags {
    return _memoryBuffer.map((e) => e.tag).toSet().toList()..sort();
  }

  /// Export logs as text
  Future<String> exportLogs({
    LogLevel? level,
    String? tag,
  }) async {
    final buffer = StringBuffer();
    buffer.writeln('=== LiquorPro Log Export ===');
    buffer.writeln('Exported: ${DateTime.now().toIso8601String()}');
    buffer.writeln('Session: ${_sessionManager.currentSessionId}');
    buffer.writeln('Device: ${_sessionManager.deviceModel}');
    buffer.writeln('');
    buffer.writeln('=== Logs ===');
    buffer.writeln('');

    final filtered = getFilteredLogs(level: level, tag: tag);
    for (final entry in filtered) {
      buffer.writeln(entry.toString());
      buffer.writeln('');
    }

    return buffer.toString();
  }

  /// Get logs from database with filters
  Future<List<LogEntry>> getLogs({
    LogLevel? level,
    String? tag,
    String? search,
    DateTime? after,
    DateTime? before,
    int? limit,
    int? offset,
  }) async {
    final maps = await _db.getLogs(
      level: level?.name,
      tag: tag,
      search: search,
      after: after,
      before: before,
      limit: limit,
      offset: offset,
    );
    return maps.map((m) => LogEntry.fromMap(m)).toList();
  }

  /// Get log count by level
  Future<Map<LogLevel, int>> getLogCountByLevel() async {
    final counts = await _db.getLogCountByLevel();
    return counts.map((key, value) {
      final level = LogLevel.values.firstWhere(
        (l) => l.name == key,
        orElse: () => LogLevel.info,
      );
      return MapEntry(level, value);
    });
  }

  /// Get unique tags
  Future<List<String>> getUniqueTags() async {
    return await _db.getUniqueTags();
  }

  /// Get total log count
  Future<int> getTotalLogCount() async {
    return await _db.getTotalLogCount();
  }

  /// Get unsynced log count
  Future<int> getUnsyncedLogCount() async {
    return await _db.getUnsyncedLogCount();
  }

  // ==================== SESSION MANAGEMENT ====================

  /// Get session manager
  SessionManager get sessionManager => _sessionManager;

  /// Set user context (call after login)
  Future<void> setUserContext({
    required String userId,
    required String tenantId,
  }) async {
    await _sessionManager.setUserContext(userId: userId, tenantId: tenantId);
    await info('Auth', 'User logged in', metadata: {
      'user_id': userId,
      'tenant_id': tenantId,
    });
  }

  /// Clear user context (call on logout)
  Future<void> clearUserContext() async {
    await info('Auth', 'User logged out');
    _sessionManager.clearUserContext();
  }

  // ==================== SYNC MANAGEMENT ====================

  /// Get sync service
  LogSyncService get syncService => _syncService;

  /// Trigger manual sync
  Future<void> syncNow() async {
    await _syncService.syncNow();
  }

  // ==================== CLEANUP ====================

  /// Clear all logs
  Future<void> clearAllLogs() async {
    await _db.clearAllLogs();
    _memoryBuffer.clear();
    await info('LoggingService', 'All logs cleared');
  }

  /// Shutdown service (call on app close)
  Future<void> shutdown() async {
    await _sessionManager.endCurrentSession();
    await _syncService.shutdown();
    await _db.close();
    _logController.close();
    _initialized = false;

    if (kDebugMode) {
      print('🛑 LoggingService: Shutdown complete');
    }
  }
}

/// Static convenience methods for easy logging
class Log {
  Log._();

  static LoggingService get _service => LoggingService.instance;

  static Future<void> debug(String tag, String message, {Map<String, dynamic>? metadata}) =>
      _service.debug(tag, message, metadata: metadata);

  static Future<void> info(String tag, String message, {Map<String, dynamic>? metadata}) =>
      _service.info(tag, message, metadata: metadata);

  static Future<void> warning(String tag, String message, {Map<String, dynamic>? metadata}) =>
      _service.warning(tag, message, metadata: metadata);

  static Future<void> success(String tag, String message, {Map<String, dynamic>? metadata}) =>
      _service.success(tag, message, metadata: metadata);

  static Future<void> error(String tag, String message, {dynamic exception, StackTrace? stackTrace, Map<String, dynamic>? metadata}) =>
      _service.error(tag, message, exception: exception, stackTrace: stackTrace, metadata: metadata);

  static Future<void> api({required String method, required String url, int? statusCode, int? durationMs}) async {
    if (statusCode != null) {
      await _service.logApiResponse(method: method, url: url, statusCode: statusCode, durationMs: durationMs);
    } else {
      await _service.logApiRequest(method: method, url: url);
    }
  }

  static Future<void> navigation({required String from, required String to}) =>
      _service.logNavigation(from: from, to: to);

  static Future<void> action(String action, {String? screen, Map<String, dynamic>? data}) =>
      _service.logUserAction(action: action, screen: screen, data: data);
}
