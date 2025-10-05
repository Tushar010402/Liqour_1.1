import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

/// App Logger - Best Practice Logging
/// Centralized logging utility for debugging and monitoring

class AppLogger {
  // Private constructor to prevent instantiation
  AppLogger._();

  // Logger instance
  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 2, // Number of method calls to be displayed
      errorMethodCount: 8, // Number of method calls if stacktrace is provided
      lineLength: 120, // Width of the output
      colors: true, // Colorful log messages
      printEmojis: true, // Print an emoji for each log message
      printTime: true, // Should each log print contain a timestamp
    ),
  );

  // Alternative simple logger for production
  static final Logger _simpleLogger = Logger(
    printer: SimplePrinter(
      colors: false,
      printTime: true,
    ),
  );

  // Get the appropriate logger based on build mode
  static Logger get _currentLogger {
    return kDebugMode ? _logger : _simpleLogger;
  }

  // ==================== Log Levels ====================

  /// Debug log - For detailed debugging information
  /// Use this for: Trace variable values, function calls, debugging info
  static void debug(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      _currentLogger.d(message, error: error, stackTrace: stackTrace);
    }
  }

  /// Info log - For general informational messages
  /// Use this for: App lifecycle events, user actions, API calls
  static void info(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _currentLogger.i(message, error: error, stackTrace: stackTrace);
  }

  /// Warning log - For potentially harmful situations
  /// Use this for: Deprecated API usage, poor use of API, undesirable things
  static void warning(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _currentLogger.w(message, error: error, stackTrace: stackTrace);
  }

  /// Error log - For error events
  /// Use this for: Exceptions, API errors, validation failures
  static void error(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _currentLogger.e(message, error: error, stackTrace: stackTrace);
  }

  /// Fatal log - For very severe error events
  /// Use this for: Critical failures, app crashes, unrecoverable errors
  static void fatal(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _currentLogger.f(message, error: error, stackTrace: stackTrace);
  }

  // ==================== Specialized Logging Methods ====================

  /// Log API request
  static void apiRequest({
    required String method,
    required String url,
    Map<String, dynamic>? headers,
    dynamic body,
  }) {
    if (kDebugMode) {
      info('API Request: $method $url');
      if (headers != null) debug('Headers: $headers');
      if (body != null) debug('Body: $body');
    }
  }

  /// Log API response
  static void apiResponse({
    required String url,
    required int statusCode,
    dynamic body,
  }) {
    if (kDebugMode) {
      if (statusCode >= 200 && statusCode < 300) {
        info('API Response: $statusCode $url');
      } else {
        error('API Error: $statusCode $url');
      }
      if (body != null) debug('Response Body: $body');
    }
  }

  /// Log navigation
  static void navigation({
    required String from,
    required String to,
    Map<String, dynamic>? arguments,
  }) {
    if (kDebugMode) {
      info('Navigation: $from → $to');
      if (arguments != null && arguments.isNotEmpty) {
        debug('Arguments: $arguments');
      }
    }
  }

  /// Log user action
  static void userAction({
    required String action,
    Map<String, dynamic>? data,
  }) {
    if (kDebugMode) {
      info('User Action: $action');
      if (data != null && data.isNotEmpty) {
        debug('Data: $data');
      }
    }
  }

  /// Log database operation
  static void database({
    required String operation,
    String? table,
    Map<String, dynamic>? data,
  }) {
    if (kDebugMode) {
      info('Database: $operation${table != null ? ' on $table' : ''}');
      if (data != null && data.isNotEmpty) {
        debug('Data: $data');
      }
    }
  }

  /// Log authentication event
  static void auth({
    required String event,
    String? userId,
    Map<String, dynamic>? data,
  }) {
    info('Auth: $event${userId != null ? ' for user $userId' : ''}');
    if (data != null && data.isNotEmpty) {
      debug('Data: $data');
    }
  }

  /// Log business operation
  static void business({
    required String operation,
    Map<String, dynamic>? data,
  }) {
    info('Business: $operation');
    if (data != null && data.isNotEmpty) {
      debug('Data: $data');
    }
  }

  /// Log performance metric
  static void performance({
    required String metric,
    required Duration duration,
    Map<String, dynamic>? data,
  }) {
    if (kDebugMode) {
      info('Performance: $metric took ${duration.inMilliseconds}ms');
      if (data != null && data.isNotEmpty) {
        debug('Data: $data');
      }
    }
  }

  /// Log cache operation
  static void cache({
    required String operation,
    required String key,
    bool? hit,
  }) {
    if (kDebugMode) {
      if (hit != null) {
        debug('Cache: $operation - $key (${hit ? 'HIT' : 'MISS'})');
      } else {
        debug('Cache: $operation - $key');
      }
    }
  }

  // ==================== Conditional Logging ====================

  /// Log only in debug mode
  static void debugOnly(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      debug(message, error, stackTrace);
    }
  }

  /// Log only in release mode
  static void releaseOnly(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    if (kReleaseMode) {
      info(message, error, stackTrace);
    }
  }

  // ==================== Structured Logging ====================

  /// Log with structured data
  static void structured({
    required String message,
    required String level,
    Map<String, dynamic>? data,
    dynamic error,
    StackTrace? stackTrace,
  }) {
    final logMessage = StringBuffer(message);

    if (data != null && data.isNotEmpty) {
      logMessage.write('\n');
      data.forEach((key, value) {
        logMessage.write('  $key: $value\n');
      });
    }

    switch (level.toLowerCase()) {
      case 'debug':
        debug(logMessage.toString(), error, stackTrace);
        break;
      case 'info':
        info(logMessage.toString(), error, stackTrace);
        break;
      case 'warning':
        warning(logMessage.toString(), error, stackTrace);
        break;
      case 'error':
        error(logMessage.toString(), error, stackTrace);
        break;
      case 'fatal':
        fatal(logMessage.toString(), error, stackTrace);
        break;
      default:
        info(logMessage.toString(), error, stackTrace);
    }
  }

  // ==================== JSON Logging ====================

  /// Log JSON data in pretty format
  static void json(Map<String, dynamic> data, {String? label}) {
    if (kDebugMode) {
      final message = label != null ? '$label:\n' : '';
      debug('$message${_prettyJson(data)}');
    }
  }

  /// Pretty print JSON
  static String _prettyJson(Map<String, dynamic> json) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(json);
  }

  // ==================== Exception Logging ====================

  /// Log exception with context
  static void exception({
    required dynamic exception,
    StackTrace? stackTrace,
    String? context,
    Map<String, dynamic>? additionalData,
  }) {
    final message = StringBuffer();

    if (context != null) {
      message.write('Exception in $context\n');
    }

    message.write('Exception: $exception');

    if (additionalData != null && additionalData.isNotEmpty) {
      message.write('\nAdditional Data:\n');
      additionalData.forEach((key, value) {
        message.write('  $key: $value\n');
      });
    }

    error(message.toString(), exception, stackTrace);
  }

  // ==================== Timing Utilities ====================

  /// Start a timer for performance measurement
  static Stopwatch startTimer(String label) {
    if (kDebugMode) {
      debug('⏱️  Starting timer: $label');
    }
    return Stopwatch()..start();
  }

  /// Stop a timer and log the duration
  static void stopTimer(Stopwatch stopwatch, String label) {
    stopwatch.stop();
    if (kDebugMode) {
      performance(
        metric: label,
        duration: stopwatch.elapsed,
      );
    }
  }

  // ==================== Network Logging ====================

  /// Log network error
  static void networkError({
    required String url,
    required dynamic error,
    int? statusCode,
    StackTrace? stackTrace,
  }) {
    final message = StringBuffer('Network Error: $url');

    if (statusCode != null) {
      message.write(' (Status: $statusCode)');
    }

    AppLogger.error(message.toString(), error, stackTrace);
  }

  /// Log network timeout
  static void networkTimeout({
    required String url,
    required Duration timeout,
  }) {
    warning('Network Timeout: $url (${timeout.inSeconds}s)');
  }

  // ==================== Lifecycle Logging ====================

  /// Log app lifecycle events
  static void lifecycle(String event, {Map<String, dynamic>? data}) {
    info('Lifecycle: $event');
    if (data != null && data.isNotEmpty) {
      debug('Data: $data');
    }
  }

  /// Log widget lifecycle
  static void widgetLifecycle(String widgetName, String event) {
    if (kDebugMode) {
      debug('Widget Lifecycle: $widgetName - $event');
    }
  }

  // ==================== Custom Logging ====================

  /// Log with custom emoji
  static void custom({
    required String emoji,
    required String message,
    dynamic error,
    StackTrace? stackTrace,
    String level = 'info',
  }) {
    final logMessage = '$emoji $message';

    switch (level.toLowerCase()) {
      case 'debug':
        debug(logMessage, error, stackTrace);
        break;
      case 'warning':
        warning(logMessage, error, stackTrace);
        break;
      case 'error':
        AppLogger.error(logMessage, error, stackTrace);
        break;
      default:
        info(logMessage, error, stackTrace);
    }
  }

  // ==================== Feature Toggles ====================

  /// Check if logging is enabled
  static bool get isEnabled => kDebugMode;

  /// Check if verbose logging is enabled
  static bool get isVerbose => kDebugMode;
}

/// JSON Encoder for pretty printing
class JsonEncoder {
  final String indent;

  const JsonEncoder.withIndent(this.indent);

  String convert(Map<String, dynamic> object) {
    return _encode(object, 0);
  }

  String _encode(dynamic object, int level) {
    if (object == null) return 'null';

    if (object is Map) {
      final entries = object.entries.map((e) {
        final key = '"${e.key}"';
        final value = _encode(e.value, level + 1);
        return '${indent * (level + 1)}$key: $value';
      }).join(',\n');

      return '{\n$entries\n${indent * level}}';
    }

    if (object is List) {
      final items = object.map((e) {
        return '${indent * (level + 1)}${_encode(e, level + 1)}';
      }).join(',\n');

      return '[\n$items\n${indent * level}]';
    }

    if (object is String) {
      return '"$object"';
    }

    return object.toString();
  }
}
