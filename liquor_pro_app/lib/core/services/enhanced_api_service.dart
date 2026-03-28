import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/api_response.dart';
import '../utils/app_logger.dart';
import '../utils/network_retry.dart';
import 'auth_service.dart';

/// Enhanced API Service with industrial-grade error handling, retry logic, and token management
class EnhancedApiService {
  final AuthService _authService;
  final http.Client _client;

  // Token cache with expiry tracking
  String? _cachedToken;
  String? _cachedTenantId;
  DateTime? _tokenCacheTime;
  static const Duration _tokenCacheLifetime = Duration(seconds: 30);

  EnhancedApiService({
    required AuthService authService,
    http.Client? client,
  })  : _authService = authService,
        _client = client ?? http.Client();

  /// Force refresh cached token from secure storage
  Future<void> refreshTokenCache() async {
    AppLogger.debug('🔄 [EnhancedApiService] Refreshing token cache from secure storage');
    _cachedToken = await _authService.getToken();
    _cachedTenantId = await _authService.getTenantId();
    _tokenCacheTime = DateTime.now();

    AppLogger.debug('✅ [EnhancedApiService] Token cache refreshed - Token: ${_cachedToken?.substring(0, 20)}..., TenantID: $_cachedTenantId');
  }

  /// Get headers with smart token caching
  Future<Map<String, String>> _getHeaders({bool forceRefresh = false}) async {
    // Refresh token cache if needed
    if (forceRefresh ||
        _cachedToken == null ||
        _tokenCacheTime == null ||
        DateTime.now().difference(_tokenCacheTime!) > _tokenCacheLifetime) {
      await refreshTokenCache();
    }

    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Cache-Control': 'no-cache, no-store, must-revalidate',
      'Pragma': 'no-cache',
      'Expires': '0',
    };

    if (_cachedToken != null && _cachedToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_cachedToken';
    }

    if (_cachedTenantId != null) {
      headers['X-Tenant-ID'] = _cachedTenantId!;
    }

    return headers;
  }

  /// Handle response with detailed error logging
  ApiResponse<T> _handleResponse<T>(
    http.Response response,
    T Function(dynamic)? fromJson,
    String endpoint,
  ) {
    final statusCode = response.statusCode;

    AppLogger.debug('📥 [EnhancedApiService] Response from $endpoint - Status: $statusCode, Body length: ${response.body.length}');

    // Parse response body
    dynamic parsedBody;
    try {
      if (response.body.isNotEmpty) {
        parsedBody = json.decode(response.body);
      }
    } catch (e) {
      AppLogger.error('🚨 [EnhancedApiService] JSON parse error - Status: $statusCode, Error: $e');
      AppLogger.error('🚨 [EnhancedApiService] Response body: ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}');
      return ApiResponse<T>(
        success: false,
        message: 'Invalid JSON response from server',
        statusCode: statusCode,
      );
    }

    // Handle success responses (200-299)
    if (statusCode >= 200 && statusCode < 300) {
      if (parsedBody is List) {
        return ApiResponse<T>(
          success: true,
          data: fromJson != null ? fromJson(parsedBody) : parsedBody as T?,
          statusCode: statusCode,
        );
      }

      if (parsedBody is Map<String, dynamic>) {
        final dynamic responseData = parsedBody.containsKey('data')
            ? parsedBody['data']
            : parsedBody;

        return ApiResponse<T>(
          success: true,
          message: parsedBody['message'] as String?,
          data: fromJson != null && responseData != null
              ? fromJson(responseData)
              : responseData as T?,
          statusCode: statusCode,
        );
      }

      return ApiResponse<T>(
        success: false,
        message: 'Unexpected response format',
        statusCode: statusCode,
      );
    }

    // Handle error responses
    final Map<String, dynamic> errorBody = parsedBody is Map<String, dynamic>
        ? parsedBody
        : {};

    final errorMessage = errorBody['error'] as String? ??
                         errorBody['message'] as String? ??
                         'Request failed with status $statusCode';

    AppLogger.error('⛔ [EnhancedApiService] API Error - $endpoint: $errorMessage');

    return ApiResponse<T>(
      success: false,
      message: errorMessage,
      errors: errorBody['errors'] as Map<String, dynamic>?,
      statusCode: statusCode,
    );
  }

  /// Execute request with automatic retry on 401
  Future<ApiResponse<T>> _executeWithRetry<T>(
    String method,
    String endpoint,
    Future<http.Response> Function(Map<String, String> headers) request,
    T Function(dynamic)? fromJson,
  ) async {
    try {
      // First attempt with cached token
      var headers = await _getHeaders();

      AppLogger.debug('📤 [EnhancedApiService] $method $endpoint');
      AppLogger.debug('📋 [EnhancedApiService] Headers: ${headers.keys.join(", ")}');

      var response = await NetworkRetry.executeHttp(
        request: () => request(headers).timeout(ApiConfig.connectionTimeout),
        onRetry: (attempt, error) {
          AppLogger.warning('⚠️ [EnhancedApiService] Retry attempt $attempt for $endpoint: $error');
        },
      );

      // If 401, try once more with force-refreshed token
      if (response.statusCode == 401) {
        AppLogger.warning('⚠️ [EnhancedApiService] Got 401, refreshing token and retrying...');

        // Force refresh token cache
        headers = await _getHeaders(forceRefresh: true);

        // Retry request with fresh token
        response = await request(headers).timeout(ApiConfig.connectionTimeout);

        // If still 401, logout user
        if (response.statusCode == 401) {
          AppLogger.error('🚫 [EnhancedApiService] Still 401 after token refresh - logging out user');
          await _authService.logout();
          return ApiResponse<T>(
            success: false,
            message: 'Session expired. Please login again.',
            statusCode: 401,
          );
        }
      }

      return _handleResponse<T>(response, fromJson, endpoint);
    } catch (e) {
      AppLogger.error('💥 [EnhancedApiService] Network error on $endpoint: $e');
      return ApiResponse<T>(
        success: false,
        message: 'Network error: ${e.toString()}',
      );
    }
  }

  /// GET request
  Future<ApiResponse<T>> get<T>(
    String endpoint, {
    Map<String, dynamic>? queryParams,
    T Function(dynamic)? fromJson,
  }) async {
    return _executeWithRetry<T>(
      'GET',
      endpoint,
      (headers) {
        var url = Uri.parse('${ApiConfig.baseUrl}$endpoint');
        if (queryParams != null && queryParams.isNotEmpty) {
          url = url.replace(queryParameters: queryParams.map(
            (key, value) => MapEntry(key, value.toString()),
          ));
        }
        return _client.get(url, headers: headers);
      },
      fromJson,
    );
  }

  /// POST request
  Future<ApiResponse<T>> post<T>(
    String endpoint, {
    Map<String, dynamic>? body,
    T Function(dynamic)? fromJson,
  }) async {
    return _executeWithRetry<T>(
      'POST',
      endpoint,
      (headers) {
        final url = Uri.parse('${ApiConfig.baseUrl}$endpoint');
        if (body != null) {
          AppLogger.debug('📦 [EnhancedApiService] Body: ${json.encode(body)}');
        }
        return _client.post(
          url,
          headers: headers,
          body: body != null ? json.encode(body) : null,
        );
      },
      fromJson,
    );
  }

  /// PUT request
  Future<ApiResponse<T>> put<T>(
    String endpoint, {
    Map<String, dynamic>? body,
    T Function(dynamic)? fromJson,
  }) async {
    return _executeWithRetry<T>(
      'PUT',
      endpoint,
      (headers) {
        final url = Uri.parse('${ApiConfig.baseUrl}$endpoint');
        return _client.put(
          url,
          headers: headers,
          body: body != null ? json.encode(body) : null,
        );
      },
      fromJson,
    );
  }

  /// DELETE request
  Future<ApiResponse<T>> delete<T>(
    String endpoint, {
    T Function(dynamic)? fromJson,
  }) async {
    return _executeWithRetry<T>(
      'DELETE',
      endpoint,
      (headers) {
        final url = Uri.parse('${ApiConfig.baseUrl}$endpoint');
        return _client.delete(url, headers: headers);
      },
      fromJson,
    );
  }

  /// Dispose
  void dispose() {
    _client.close();
  }
}
