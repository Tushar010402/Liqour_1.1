import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../logging_service.dart';
import '../privacy_filter.dart';
import '../log_database.dart';

/// Dio Logging Interceptor - Industrial-grade API logging
///
/// BEST PRACTICES IMPLEMENTED:
/// 1. Single log per API call (response only, not request+response)
/// 2. Complete info in one log: method, URL, status, duration
/// 3. Screen name tracking for context
/// 4. Separate network_requests table for detailed inspection
/// 5. Privacy filtering for sensitive data
/// 6. Request ID tracking for correlation
///
/// Log Format: "GET /api/shops → 200 (145ms)"
class DioLoggingInterceptor extends Interceptor {
  final _uuid = const Uuid();
  final _db = LogDatabase();

  // Track request start times for duration calculation
  final Map<String, DateTime> _requestStartTimes = {};

  // Current screen name - set externally by navigation observer
  static String? currentScreenName;

  /// Set the current screen name (called by navigation observer)
  static void setCurrentScreen(String screenName) {
    currentScreenName = screenName;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final requestId = _uuid.v4();
    options.extra['logging_request_id'] = requestId;
    options.extra['logging_start_time'] = DateTime.now().millisecondsSinceEpoch;
    _requestStartTimes[requestId] = DateTime.now();

    // BEST PRACTICE: Don't log request here - wait for response
    // This avoids duplicate logs (request + response)
    // Only log in debug mode for immediate feedback during development
    if (kDebugMode) {
      final url = _getShortUrl(options.uri.toString());
      print('📤 [API] ${options.method} $url');
    }

    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final requestId = response.requestOptions.extra['logging_request_id'] as String?;
    final startTimeMs = response.requestOptions.extra['logging_start_time'] as int?;
    final durationMs = startTimeMs != null
        ? DateTime.now().millisecondsSinceEpoch - startTimeMs
        : null;

    // BEST PRACTICE: Log complete API call info here (single log)
    _logApiCall(response.requestOptions, response, null, requestId, durationMs);

    // Store detailed network request for inspector (separate table)
    _storeNetworkRequest(response.requestOptions, response, null, requestId, durationMs);

    // Cleanup
    if (requestId != null) {
      _requestStartTimes.remove(requestId);
    }

    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final requestId = err.requestOptions.extra['logging_request_id'] as String?;
    final startTimeMs = err.requestOptions.extra['logging_start_time'] as int?;
    final durationMs = startTimeMs != null
        ? DateTime.now().millisecondsSinceEpoch - startTimeMs
        : null;

    // Log the error (single log with all info)
    _logApiCall(err.requestOptions, err.response, err, requestId, durationMs);

    // Store detailed network request for inspector
    _storeNetworkRequest(err.requestOptions, err.response, err, requestId, durationMs);

    // Cleanup
    if (requestId != null) {
      _requestStartTimes.remove(requestId);
    }

    handler.next(err);
  }

  /// Log API call - single comprehensive log entry
  /// Format: "GET /api/shops → 200 (145ms)"
  void _logApiCall(
    RequestOptions options,
    Response? response,
    DioException? error,
    String? requestId,
    int? durationMs,
  ) {
    final method = options.method;
    final url = PrivacyFilter.redactUrl(options.uri.toString());
    final shortUrl = _getShortUrl(url);
    final statusCode = response?.statusCode ?? error?.response?.statusCode ?? 0;
    final isError = statusCode >= 400 || error != null;

    // Build log message: "GET /api/shops → 200 (145ms)"
    String message;
    if (error != null && statusCode == 0) {
      // Network error without status code
      message = '$method $shortUrl → ${error.type.name}';
      if (durationMs != null) message += ' (${durationMs}ms)';
    } else {
      message = '$method $shortUrl → $statusCode';
      if (durationMs != null) message += ' (${durationMs}ms)';
    }

    // Build metadata
    final metadata = <String, dynamic>{
      'method': method,
      'url': url,
      'status_code': statusCode,
      'type': 'api_call',
      if (durationMs != null) 'duration_ms': durationMs,
      if (requestId != null) 'request_id': requestId,
      if (currentScreenName != null) 'screen': currentScreenName,
    };

    // Add error details if present
    if (error != null) {
      metadata['error_type'] = error.type.name;
      metadata['error_message'] = error.message;
      if (error.error != null) {
        metadata['underlying_error'] = error.error.toString();
      }
    }

    // Log based on status
    if (isError) {
      // Don't pass exception/stackTrace for HTTP errors (401, 404, etc.)
      // Stack traces are only useful for unexpected errors, not server responses
      final isHttpError = statusCode > 0;
      LoggingService.instance.error(
        'API',
        message,
        exception: isHttpError ? null : error,
        stackTrace: isHttpError ? null : error?.stackTrace,
        metadata: metadata,
      );
    } else {
      LoggingService.instance.info(
        'API',
        message,
        metadata: metadata,
      );
    }

    // Console output in debug mode
    if (kDebugMode) {
      final emoji = isError ? '❌' : '✅';
      print('$emoji [API] $message');
    }
  }

  /// Get short URL path for cleaner logs
  /// "https://new.v2.floelife.in/api/shops" → "/api/shops"
  String _getShortUrl(String fullUrl) {
    try {
      final uri = Uri.parse(fullUrl);
      String path = uri.path;
      if (uri.query.isNotEmpty) {
        // Include query for important params, but truncate if too long
        final query = uri.query.length > 50
            ? '${uri.query.substring(0, 50)}...'
            : uri.query;
        path = '$path?$query';
      }
      return path.isEmpty ? '/' : path;
    } catch (_) {
      return fullUrl;
    }
  }

  /// Store detailed network request for inspector
  /// This goes to a separate table for detailed analysis
  Future<void> _storeNetworkRequest(
    RequestOptions options,
    Response? response,
    DioException? error,
    String? requestId,
    int? durationMs,
  ) async {
    try {
      await _db.insertNetworkRequest({
        'id': _uuid.v4(),
        'log_entry_id': requestId ?? _uuid.v4(),
        'method': options.method,
        'url': PrivacyFilter.redactUrl(options.uri.toString()),
        'status_code': response?.statusCode ?? error?.response?.statusCode,
        'duration_ms': durationMs,
        'request_headers': _encodeHeaders(options.headers),
        'request_body': _encodeBody(options.data),
        'response_headers': response != null ? _encodeHeaders(response.headers.map) : null,
        'response_body': response != null ? _encodeBody(response.data) : null,
        'error_message': error?.message,
        'timestamp': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      // Non-critical, don't block the request
      if (kDebugMode) {
        print('⚠️ DioLoggingInterceptor: Error storing network request: $e');
      }
    }
  }

  /// Encode headers for storage
  String? _encodeHeaders(Map<String, dynamic> headers) {
    if (headers.isEmpty) return null;
    try {
      final redacted = PrivacyFilter.redactHeaders(headers);
      return jsonEncode(redacted);
    } catch (e) {
      return null;
    }
  }

  /// Encode body for storage (truncated and redacted)
  String? _encodeBody(dynamic body) {
    if (body == null) return null;

    try {
      String bodyStr;
      if (body is String) {
        bodyStr = body;
      } else if (body is Map || body is List) {
        bodyStr = jsonEncode(body);
      } else {
        bodyStr = body.toString();
      }

      // Redact and truncate
      return PrivacyFilter.redactBody(bodyStr, maxLength: 2000);
    } catch (e) {
      return '[Unable to encode body]';
    }
  }
}
