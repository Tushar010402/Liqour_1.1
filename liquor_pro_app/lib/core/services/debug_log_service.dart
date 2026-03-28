import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:intl/intl.dart';

/// Log entry with timestamp, level, and message
class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String tag;
  final String message;
  final String? stackTrace;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    this.stackTrace,
  });

  String get formattedTime => DateFormat('HH:mm:ss.SSS').format(timestamp);

  String get levelIcon {
    switch (level) {
      case LogLevel.debug: return '🔍';
      case LogLevel.info: return 'ℹ️';
      case LogLevel.warning: return '⚠️';
      case LogLevel.error: return '❌';
      case LogLevel.success: return '✅';
    }
  }

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

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'level': level.name,
    'tag': tag,
    'message': message,
    'stackTrace': stackTrace,
  };
}

enum LogLevel { debug, info, warning, error, success }

/// Centralized Debug Logging Service
///
/// Features:
/// - In-memory log storage (last 500 entries)
/// - Filter by tag, level, or search text
/// - Export logs as text
/// - Real-time log stream for UI
/// - Device info capture
///
/// Usage:
/// ```dart
/// DebugLogService.log('Scanner', 'Starting scan...', level: LogLevel.info);
/// DebugLogService.error('Scanner', 'Failed to scan', error: e);
/// ```
class DebugLogService {
  static final DebugLogService _instance = DebugLogService._internal();
  factory DebugLogService() => _instance;
  DebugLogService._internal();

  /// Maximum logs to keep in memory
  static const int maxLogs = 500;

  /// In-memory log storage (circular buffer)
  final Queue<LogEntry> _logs = Queue<LogEntry>();

  /// Stream controller for real-time log updates
  final StreamController<LogEntry> _logController = StreamController<LogEntry>.broadcast();

  /// Stream of new log entries
  Stream<LogEntry> get logStream => _logController.stream;

  /// Get all logs
  List<LogEntry> get allLogs => _logs.toList();

  /// Device info (cached)
  String? _deviceInfo;

  /// Get device info string
  Future<String> getDeviceInfo() async {
    if (_deviceInfo != null) return _deviceInfo!;

    try {
      final deviceInfo = DeviceInfoPlugin();
      final buffer = StringBuffer();

      if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        buffer.writeln('📱 iOS Device Info:');
        buffer.writeln('  Model: ${info.model}');
        buffer.writeln('  Name: ${info.name}');
        buffer.writeln('  System: ${info.systemName} ${info.systemVersion}');
        buffer.writeln('  Physical: ${info.isPhysicalDevice}');
      } else if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        buffer.writeln('📱 Android Device Info:');
        buffer.writeln('  Model: ${info.model}');
        buffer.writeln('  Brand: ${info.brand}');
        buffer.writeln('  Android: ${info.version.release} (SDK ${info.version.sdkInt})');
        buffer.writeln('  Physical: ${info.isPhysicalDevice}');
      }

      _deviceInfo = buffer.toString();
      return _deviceInfo!;
    } catch (e) {
      return 'Device info unavailable: $e';
    }
  }

  /// Add a log entry
  void _addLog(LogEntry entry) {
    // Add to queue
    _logs.add(entry);

    // Remove old logs if over limit
    while (_logs.length > maxLogs) {
      _logs.removeFirst();
    }

    // Notify listeners
    _logController.add(entry);

    // Also print to console in debug mode
    if (kDebugMode) {
      debugPrint(entry.toString());
    }
  }

  /// Log a message
  static void log(String tag, String message, {LogLevel level = LogLevel.info}) {
    _instance._addLog(LogEntry(
      timestamp: DateTime.now(),
      level: level,
      tag: tag,
      message: message,
    ));
  }

  /// Log debug message
  static void debug(String tag, String message) {
    log(tag, message, level: LogLevel.debug);
  }

  /// Log info message
  static void info(String tag, String message) {
    log(tag, message, level: LogLevel.info);
  }

  /// Log warning message
  static void warning(String tag, String message) {
    log(tag, message, level: LogLevel.warning);
  }

  /// Log success message
  static void success(String tag, String message) {
    log(tag, message, level: LogLevel.success);
  }

  /// Log error with optional exception
  static void error(String tag, String message, {dynamic error, StackTrace? stackTrace}) {
    final errorMessage = error != null ? '$message: $error' : message;
    _instance._addLog(LogEntry(
      timestamp: DateTime.now(),
      level: LogLevel.error,
      tag: tag,
      message: errorMessage,
      stackTrace: stackTrace?.toString(),
    ));
  }

  /// Get logs filtered by tag
  List<LogEntry> getLogsByTag(String tag) {
    return _logs.where((log) => log.tag.toLowerCase().contains(tag.toLowerCase())).toList();
  }

  /// Get logs filtered by level
  List<LogEntry> getLogsByLevel(LogLevel level) {
    return _logs.where((log) => log.level == level).toList();
  }

  /// Get logs filtered by search text
  List<LogEntry> searchLogs(String query) {
    final lowerQuery = query.toLowerCase();
    return _logs.where((log) =>
      log.tag.toLowerCase().contains(lowerQuery) ||
      log.message.toLowerCase().contains(lowerQuery)
    ).toList();
  }

  /// Get logs with multiple filters
  List<LogEntry> filterLogs({
    String? tag,
    LogLevel? level,
    String? search,
    DateTime? after,
    DateTime? before,
  }) {
    return _logs.where((log) {
      if (tag != null && !log.tag.toLowerCase().contains(tag.toLowerCase())) {
        return false;
      }
      if (level != null && log.level != level) {
        return false;
      }
      if (search != null && !log.message.toLowerCase().contains(search.toLowerCase())) {
        return false;
      }
      if (after != null && log.timestamp.isBefore(after)) {
        return false;
      }
      if (before != null && log.timestamp.isAfter(before)) {
        return false;
      }
      return true;
    }).toList();
  }

  /// Export all logs as formatted text
  Future<String> exportLogs({String? tag, LogLevel? level}) async {
    final buffer = StringBuffer();

    // Add header with device info
    buffer.writeln('═══════════════════════════════════════════════════════');
    buffer.writeln('LiquorPro Debug Logs');
    buffer.writeln('Exported: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())}');
    buffer.writeln('═══════════════════════════════════════════════════════');
    buffer.writeln();
    buffer.writeln(await getDeviceInfo());
    buffer.writeln();
    buffer.writeln('═══════════════════════════════════════════════════════');
    buffer.writeln('LOGS (${_logs.length} entries)');
    if (tag != null) buffer.writeln('Filter: Tag = $tag');
    if (level != null) buffer.writeln('Filter: Level = ${level.name}');
    buffer.writeln('═══════════════════════════════════════════════════════');
    buffer.writeln();

    // Filter logs
    var logs = _logs.toList();
    if (tag != null) {
      logs = logs.where((l) => l.tag.toLowerCase().contains(tag.toLowerCase())).toList();
    }
    if (level != null) {
      logs = logs.where((l) => l.level == level).toList();
    }

    // Add logs
    for (final log in logs) {
      buffer.writeln(log.toString());
    }

    return buffer.toString();
  }

  /// Clear all logs
  static void clearLogs() {
    _instance._logs.clear();
    log('System', 'Logs cleared', level: LogLevel.info);
  }

  /// Get unique tags from logs
  List<String> get uniqueTags {
    return _logs.map((l) => l.tag).toSet().toList()..sort();
  }

  /// Get log count by level
  Map<LogLevel, int> get logCountByLevel {
    final counts = <LogLevel, int>{};
    for (final level in LogLevel.values) {
      counts[level] = _logs.where((l) => l.level == level).length;
    }
    return counts;
  }

  void dispose() {
    _logController.close();
  }
}

/// Extension for easy logging from any class
extension DebugLogging on Object {
  void logDebug(String message) => DebugLogService.debug(runtimeType.toString(), message);
  void logInfo(String message) => DebugLogService.info(runtimeType.toString(), message);
  void logWarning(String message) => DebugLogService.warning(runtimeType.toString(), message);
  void logError(String message, {dynamic error}) => DebugLogService.error(runtimeType.toString(), message, error: error);
  void logSuccess(String message) => DebugLogService.success(runtimeType.toString(), message);
}
