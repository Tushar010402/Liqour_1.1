import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

/// Premium logging system for LiquorPro mobile app
class AppLogger {
  static final Logger _logger = Logger(
    printer: kDebugMode ? _DevelopmentPrinter() : _ProductionPrinter(),
    level: kDebugMode ? Level.debug : Level.info,
    output: _FileOutput(),
  );
  
  static final List<LogEntry> _logHistory = [];
  static const int _maxLogHistorySize = 1000;
  
  /// Log debug message
  static void debug(String message, [dynamic error, StackTrace? stackTrace]) {
    _log(Level.debug, message, error, stackTrace);
  }
  
  /// Log info message
  static void info(String message, [dynamic error, StackTrace? stackTrace]) {
    _log(Level.info, message, error, stackTrace);
  }
  
  /// Log warning message
  static void warning(String message, [dynamic error, StackTrace? stackTrace]) {
    _log(Level.warning, message, error, stackTrace);
  }
  
  /// Log error message
  static void error(String message, [dynamic error, StackTrace? stackTrace]) {
    _log(Level.error, message, error, stackTrace);
  }
  
  /// Log fatal error message
  static void fatal(String message, [dynamic error, StackTrace? stackTrace]) {
    _log(Level.fatal, message, error, stackTrace);
  }
  
  /// Internal logging method
  static void _log(Level level, String message, [dynamic error, StackTrace? stackTrace]) {
    final logEntry = LogEntry(
      level: level,
      message: message,
      error: error,
      stackTrace: stackTrace,
      timestamp: DateTime.now(),
    );
    
    // Add to history
    _addToHistory(logEntry);
    
    // Log to console/file
    switch (level) {
      case Level.debug:
        _logger.d(message, error: error, stackTrace: stackTrace);
        break;
      case Level.info:
        _logger.i(message, error: error, stackTrace: stackTrace);
        break;
      case Level.warning:
        _logger.w(message, error: error, stackTrace: stackTrace);
        break;
      case Level.error:
        _logger.e(message, error: error, stackTrace: stackTrace);
        break;
      case Level.fatal:
        _logger.f(message, error: error, stackTrace: stackTrace);
        break;
      default:
        _logger.i(message, error: error, stackTrace: stackTrace);
    }
  }
  
  /// Add log entry to history
  static void _addToHistory(LogEntry entry) {
    _logHistory.add(entry);
    
    // Maintain maximum history size
    if (_logHistory.length > _maxLogHistorySize) {
      _logHistory.removeRange(0, _logHistory.length - _maxLogHistorySize);
    }
  }
  
  /// Get log history
  static List<LogEntry> getLogHistory({
    Level? level,
    DateTime? since,
    int? limit,
  }) {
    var logs = _logHistory.where((entry) {
      if (level != null && entry.level != level) return false;
      if (since != null && entry.timestamp.isBefore(since)) return false;
      return true;
    }).toList();
    
    if (limit != null && logs.length > limit) {
      logs = logs.skip(logs.length - limit).toList();
    }
    
    return logs;
  }
  
  /// Clear log history
  static void clearHistory() {
    _logHistory.clear();
  }
  
  /// Export logs as string
  static String exportLogs({
    Level? level,
    DateTime? since,
    int? limit,
  }) {
    final logs = getLogHistory(level: level, since: since, limit: limit);
    
    return logs.map((entry) {
      final timestamp = entry.timestamp.toIso8601String();
      final levelName = entry.level.name.toUpperCase();
      var logLine = '[$timestamp] [$levelName] ${entry.message}';
      
      if (entry.error != null) {
        logLine += '\nError: ${entry.error}';
      }
      
      if (entry.stackTrace != null) {
        logLine += '\nStack Trace:\n${entry.stackTrace}';
      }
      
      return logLine;
    }).join('\n\n');
  }
  
  /// Log network request
  static void networkRequest(String method, String url, [Map<String, dynamic>? data]) {
    debug('🌐 $method $url', data);
  }
  
  /// Log network response
  static void networkResponse(String method, String url, int statusCode, [dynamic data]) {
    final emoji = statusCode >= 200 && statusCode < 300 ? '✅' : '❌';
    debug('$emoji $method $url [$statusCode]', data);
  }
  
  /// Log user action
  static void userAction(String action, [Map<String, dynamic>? context]) {
    info('👤 User Action: $action', context);
  }
  
  /// Log navigation
  static void navigation(String route, [Map<String, dynamic>? params]) {
    debug('🧭 Navigation: $route', params);
  }
  
  /// Log performance metric
  static void performance(String metric, Duration duration, [Map<String, dynamic>? context]) {
    info('⚡ Performance: $metric took ${duration.inMilliseconds}ms', context);
  }
  
  /// Log business event
  static void business(String event, Map<String, dynamic> data) {
    info('💼 Business Event: $event', data);
  }
  
  /// Log security event
  static void security(String event, [Map<String, dynamic>? context]) {
    warning('🔒 Security Event: $event', context);
  }
}

/// Log entry data class
class LogEntry {
  final Level level;
  final String message;
  final dynamic error;
  final StackTrace? stackTrace;
  final DateTime timestamp;
  
  LogEntry({
    required this.level,
    required this.message,
    this.error,
    this.stackTrace,
    required this.timestamp,
  });
  
  @override
  String toString() {
    return 'LogEntry(level: $level, message: $message, timestamp: $timestamp)';
  }
}

/// Development-friendly log printer
class _DevelopmentPrinter extends LogPrinter {
  static final Map<Level, String> _levelEmojis = {
    Level.debug: '🐛',
    Level.info: 'ℹ️',
    Level.warning: '⚠️',
    Level.error: '❌',
    Level.fatal: '💀',
  };
  
  static final Map<Level, AnsiColor> _levelColors = {
    Level.debug: AnsiColor.fg(243),
    Level.info: AnsiColor.fg(12),
    Level.warning: AnsiColor.fg(208),
    Level.error: AnsiColor.fg(196),
    Level.fatal: AnsiColor.fg(199),
  };
  
  @override
  List<String> log(LogEvent event) {
    final emoji = _levelEmojis[event.level] ?? '';
    final color = _levelColors[event.level] ?? AnsiColor.none();
    final time = DateTime.now().toIso8601String().substring(11, 19);
    
    var message = '$emoji [$time] ${event.message}';
    
    if (event.error != null) {
      message += '\n${event.error}';
    }
    
    if (event.stackTrace != null) {
      message += '\n${event.stackTrace}';
    }
    
    return [color(message)];
  }
}

/// Production-optimized log printer
class _ProductionPrinter extends LogPrinter {
  @override
  List<String> log(LogEvent event) {
    final time = DateTime.now().toIso8601String();
    final level = event.level.name.toUpperCase();
    
    var message = '[$time] [$level] ${event.message}';
    
    if (event.error != null) {
      message += ' | Error: ${event.error}';
    }
    
    return [message];
  }
}

/// File output for logs (can be extended to write to files)
class _FileOutput extends LogOutput {
  @override
  void output(OutputEvent event) {
    // In a real implementation, you might write to a file here
    // For now, we'll just output to console
    for (final line in event.lines) {
      print(line);
    }
  }
}