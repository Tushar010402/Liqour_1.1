import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

/// OCR-specific logger with debug mode toggle
///
/// FEATURES:
/// - Production-safe logging (controlled by kDebugMode)
/// - Manual debug toggle via settings
/// - Structured log levels (DEBUG, INFO, WARN, ERROR)
/// - Color-coded console output
/// - Log file export capability
/// - Performance tracking
///
/// USAGE:
/// ```dart
/// // Simple logging
/// OCRLogger.info('OCR processing started');
/// OCRLogger.error('Failed to extract text', error: e);
///
/// // With context
/// OCRLogger.debug('Processing image', context: {'imageId': '123', 'size': '1024x768'});
///
/// // Performance tracking
/// final stopwatch = OCRLogger.startTimer('ocr_processing');
/// // ... do work ...
/// OCRLogger.endTimer(stopwatch, 'ocr_processing');
/// ```
class OCRLogger {
  static bool _debugEnabled = kDebugMode; // Automatically disabled in production
  static bool _verboseEnabled = false; // Extra verbose logs
  static final List<LogEntry> _logHistory = [];
  static const int _maxHistorySize = 1000;

  // ANSI color codes for console
  static const String _reset = '\x1B[0m';
  static const String _red = '\x1B[31m';
  static const String _yellow = '\x1B[33m';
  static const String _green = '\x1B[32m';
  static const String _blue = '\x1B[34m';
  static const String _gray = '\x1B[90m';

  /// Enable/disable debug logging
  static void setDebugEnabled(bool enabled) {
    _debugEnabled = enabled && kDebugMode; // Never enable in release mode
    if (enabled) {
      info('OCR Debug logging enabled');
    }
  }

  /// Enable/disable verbose logging
  static void setVerboseEnabled(bool enabled) {
    _verboseEnabled = enabled && kDebugMode;
    if (enabled) {
      info('OCR Verbose logging enabled');
    }
  }

  /// Check if debug is enabled
  static bool get isDebugEnabled => _debugEnabled;

  /// Check if verbose is enabled
  static bool get isVerboseEnabled => _verboseEnabled;

  /// Log debug message (only in debug mode + if debug enabled)
  static void debug(
    String message, {
    Map<String, dynamic>? context,
    StackTrace? stackTrace,
  }) {
    if (!_debugEnabled) return;

    final entry = LogEntry(
      level: LogLevel.debug,
      message: message,
      context: context,
      stackTrace: stackTrace,
      timestamp: DateTime.now(),
    );

    _addToHistory(entry);
    _printLog(entry, color: _gray, icon: '🐛');
  }

  /// Log info message
  static void info(
    String message, {
    Map<String, dynamic>? context,
  }) {
    if (!_debugEnabled && !kDebugMode) return;

    final entry = LogEntry(
      level: LogLevel.info,
      message: message,
      context: context,
      timestamp: DateTime.now(),
    );

    _addToHistory(entry);
    _printLog(entry, color: _blue, icon: 'ℹ️');
  }

  /// Log warning message
  static void warn(
    String message, {
    Map<String, dynamic>? context,
  }) {
    final entry = LogEntry(
      level: LogLevel.warning,
      message: message,
      context: context,
      timestamp: DateTime.now(),
    );

    _addToHistory(entry);
    _printLog(entry, color: _yellow, icon: '⚠️');
  }

  /// Log error message
  static void error(
    String message, {
    dynamic error,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) {
    final entry = LogEntry(
      level: LogLevel.error,
      message: message,
      error: error,
      stackTrace: stackTrace,
      context: context,
      timestamp: DateTime.now(),
    );

    _addToHistory(entry);
    _printLog(entry, color: _red, icon: '❌');

    // Also log to developer console for visibility
    if (error != null) {
      developer.log(
        message,
        error: error,
        stackTrace: stackTrace,
        level: 1000, // Error level
      );
    }
  }

  /// Log verbose message (only if verbose enabled)
  static void verbose(
    String message, {
    Map<String, dynamic>? context,
  }) {
    if (!_verboseEnabled) return;

    final entry = LogEntry(
      level: LogLevel.verbose,
      message: message,
      context: context,
      timestamp: DateTime.now(),
    );

    _addToHistory(entry);
    _printLog(entry, color: _gray, icon: '🔍');
  }

  /// Start performance timer
  static Stopwatch startTimer(String operation) {
    if (_debugEnabled) {
      debug('⏱️  Starting: $operation');
    }
    return Stopwatch()..start();
  }

  /// End performance timer and log duration
  static void endTimer(Stopwatch stopwatch, String operation) {
    stopwatch.stop();
    final duration = stopwatch.elapsedMilliseconds;

    if (_debugEnabled) {
      final color = duration < 100
          ? _green
          : duration < 500
              ? _yellow
              : _red;

      final message = '⏱️  Completed: $operation in ${duration}ms';

      if (kDebugMode) {
        print('$color$message$_reset');
      }
    }
  }

  /// Log box-style message (for important info)
  static void box(String message, {String? title}) {
    if (!_debugEnabled && !kDebugMode) return;

    final lines = message.split('\n');
    final maxLength = lines.map((l) => l.length).reduce((a, b) => a > b ? a : b);
    final border = '═' * (maxLength + 4);

    if (kDebugMode) {
      print('$_blue╔$border╗$_reset');
      if (title != null) {
        print('$_blue║  ${title.padRight(maxLength)}  ║$_reset');
        print('$_blue╠$border╣$_reset');
      }
      for (final line in lines) {
        print('$_blue║  ${line.padRight(maxLength)}  ║$_reset');
      }
      print('$_blue╚$border╝$_reset');
    }
  }

  /// Print log entry to console
  static void _printLog(
    LogEntry entry, {
    required String color,
    required String icon,
  }) {
    if (!kDebugMode) return;

    final timestamp = '${entry.timestamp.hour.toString().padLeft(2, '0')}:'
        '${entry.timestamp.minute.toString().padLeft(2, '0')}:'
        '${entry.timestamp.second.toString().padLeft(2, '0')}';

    final prefix = '[$timestamp] $icon [${entry.level.name.toUpperCase()}]';

    print('$color$prefix ${entry.message}$_reset');

    if (entry.context != null && entry.context!.isNotEmpty) {
      print('$_gray   Context: ${entry.context}$_reset');
    }

    if (entry.error != null) {
      print('$_red   Error: ${entry.error}$_reset');
    }

    if (entry.stackTrace != null) {
      print('$_gray   ${entry.stackTrace}$_reset');
    }
  }

  /// Add entry to history
  static void _addToHistory(LogEntry entry) {
    _logHistory.add(entry);

    // Trim history if too large
    if (_logHistory.length > _maxHistorySize) {
      _logHistory.removeRange(0, _logHistory.length - _maxHistorySize);
    }
  }

  /// Get log history
  static List<LogEntry> getHistory({
    LogLevel? level,
    DateTime? since,
  }) {
    var filtered = _logHistory;

    if (level != null) {
      filtered = filtered.where((e) => e.level == level).toList();
    }

    if (since != null) {
      filtered = filtered.where((e) => e.timestamp.isAfter(since)).toList();
    }

    return filtered;
  }

  /// Export logs to string (for file export)
  static String exportLogs({
    LogLevel? level,
    DateTime? since,
  }) {
    final logs = getHistory(level: level, since: since);
    final buffer = StringBuffer();

    buffer.writeln('OCR Logs Export');
    buffer.writeln('Generated: ${DateTime.now()}');
    buffer.writeln('Total entries: ${logs.length}');
    buffer.writeln('=' * 80);
    buffer.writeln('');

    for (final entry in logs) {
      buffer.writeln('[${entry.timestamp}] [${entry.level.name.toUpperCase()}] ${entry.message}');

      if (entry.context != null) {
        buffer.writeln('  Context: ${entry.context}');
      }

      if (entry.error != null) {
        buffer.writeln('  Error: ${entry.error}');
      }

      if (entry.stackTrace != null) {
        buffer.writeln('  Stack Trace:');
        buffer.writeln('${entry.stackTrace}'.split('\n').map((line) => '    $line').join('\n'));
      }

      buffer.writeln('');
    }

    return buffer.toString();
  }

  /// Clear log history
  static void clearHistory() {
    _logHistory.clear();
    info('Log history cleared');
  }

  /// Get statistics about logs
  static LogStatistics getStatistics({DateTime? since}) {
    final logs = getHistory(since: since);

    return LogStatistics(
      total: logs.length,
      debug: logs.where((e) => e.level == LogLevel.debug).length,
      info: logs.where((e) => e.level == LogLevel.info).length,
      warning: logs.where((e) => e.level == LogLevel.warning).length,
      error: logs.where((e) => e.level == LogLevel.error).length,
      verbose: logs.where((e) => e.level == LogLevel.verbose).length,
    );
  }
}

/// Log levels
enum LogLevel {
  verbose,
  debug,
  info,
  warning,
  error,
}

/// Log entry model
class LogEntry {
  final LogLevel level;
  final String message;
  final dynamic error;
  final StackTrace? stackTrace;
  final Map<String, dynamic>? context;
  final DateTime timestamp;

  LogEntry({
    required this.level,
    required this.message,
    this.error,
    this.stackTrace,
    this.context,
    required this.timestamp,
  });

  @override
  String toString() {
    return '[${timestamp.toIso8601String()}] [${level.name}] $message';
  }
}

/// Log statistics
class LogStatistics {
  final int total;
  final int debug;
  final int info;
  final int warning;
  final int error;
  final int verbose;

  LogStatistics({
    required this.total,
    required this.debug,
    required this.info,
    required this.warning,
    required this.error,
    required this.verbose,
  });

  @override
  String toString() {
    return '''
Log Statistics:
  Total: $total
  Debug: $debug
  Info: $info
  Warning: $warning
  Error: $error
  Verbose: $verbose
''';
  }
}
