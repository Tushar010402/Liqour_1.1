import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/api_response.dart';
import '../utils/network_retry.dart';
import 'auth_service.dart';
import '../../core/utils/logger.dart';

/// HTTP API Service with interceptors
class ApiService {
  final AuthService _authService;
  final http.Client _client;

  ApiService({
    required AuthService authService,
    http.Client? client,
  })  : _authService = authService,
        _client = client ?? http.Client();

  // Expose AuthService for services that need it
  AuthService get authService => _authService;

  // Get default headers
  Future<Map<String, String>> _getHeaders() async {
    final token = await _authService.getToken();
    final tenantId = await _authService.getTenantId();

    Logger.debug('🔑 Getting headers - Token: ${token?.substring(0, 20)}..., Tenant ID: $tenantId');

    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      // Prevent HTTP caching
      'Cache-Control': 'no-cache, no-store, must-revalidate',
      'Pragma': 'no-cache',
      'Expires': '0',
    };

    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
      Logger.debug('🔑 Authorization header added');
    } else {
      Logger.debug('⚠️ No token available!');
    }

    if (tenantId != null) {
      headers['X-Tenant-ID'] = tenantId.toString();
      Logger.debug('🔑 X-Tenant-ID header added: $tenantId');
    } else {
      Logger.debug('⚠️ No tenant ID available!');
    }

    return headers;
  }

  // Handle response
  ApiResponse<T> _handleResponse<T>(
    http.Response response,
    T Function(dynamic)? fromJson,
  ) {
    final statusCode = response.statusCode;

    // Parse response body
    dynamic parsedBody;
    try {
      if (response.body.isNotEmpty) {
        parsedBody = json.decode(response.body);
      }
    } catch (e) {
      Logger.debug('❌ JSON decode error: $e');
      return ApiResponse<T>(
        success: false,
        message: 'Invalid JSON response',
        statusCode: statusCode,
      );
    }

    // Handle success responses (200-299)
    if (statusCode >= 200 && statusCode < 300) {
      // If response is a List (array), pass it directly to fromJson
      if (parsedBody is List) {
        Logger.debug('📋 Response is a List with ${parsedBody.length} items');
        return ApiResponse<T>(
          success: true,
          data: fromJson != null ? fromJson(parsedBody) : parsedBody as T?,
          statusCode: statusCode,
        );
      }

      // If response is a Map (object)
      if (parsedBody is Map<String, dynamic>) {
        // Check if response has 'data' field, otherwise use the entire body
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

      // Unexpected response type
      Logger.debug('⚠️ Unexpected response type: ${parsedBody.runtimeType}');
      return ApiResponse<T>(
        success: false,
        message: 'Unexpected response format',
        statusCode: statusCode,
      );
    }

    // Handle error responses (parsedBody should be a Map)
    final Map<String, dynamic> errorBody = parsedBody is Map<String, dynamic>
        ? parsedBody
        : {};

    return ApiResponse<T>(
      success: false,
      message: errorBody['message'] as String? ?? 'Request failed',
      errors: errorBody['errors'] as Map<String, dynamic>?,
      statusCode: statusCode,
    );
  }

  // GET request
  Future<ApiResponse<T>> get<T>(
    String endpoint, {
    Map<String, dynamic>? queryParams,
    T Function(dynamic)? fromJson,
  }) async {
    try {
      final headers = await _getHeaders();

      // Build URL with query parameters
      var url = Uri.parse('${ApiConfig.baseUrl}$endpoint');
      if (queryParams != null && queryParams.isNotEmpty) {
        url = url.replace(queryParameters: queryParams.map(
          (key, value) => MapEntry(key, value.toString()),
        ));
      }

      // Debug logging
      Logger.debug('🌐 API GET: $url');

      final response = await NetworkRetry.executeHttp(
        request: () => _client
            .get(url, headers: headers)
            .timeout(ApiConfig.connectionTimeout),
        onRetry: (attempt, error) {
          Logger.debug('🔄 Retrying GET $endpoint (attempt $attempt): $error');
        },
      );

      // Debug logging
      Logger.debug('📥 Response status: ${response.statusCode}');
      Logger.debug('📥 Response body: ${response.body}');

      // Handle 401 Unauthorized
      if (response.statusCode == 401) {
        await _authService.logout();
        return ApiResponse<T>(
          success: false,
          message: 'Session expired. Please login again.',
          statusCode: 401,
        );
      }

      return _handleResponse<T>(response, fromJson);
    } catch (e) {
      return ApiResponse<T>(
        success: false,
        message: 'Network error: ${e.toString()}',
      );
    }
  }

  // POST request
  Future<ApiResponse<T>> post<T>(
    String endpoint, {
    Map<String, dynamic>? body,
    T Function(dynamic)? fromJson,
  }) async {
    try {
      final headers = await _getHeaders();
      final url = Uri.parse('${ApiConfig.baseUrl}$endpoint');

      // Debug logging
      Logger.debug('🌐 API POST: $url');
      Logger.debug('📦 Request body: ${json.encode(body)}');

      final response = await NetworkRetry.executeHttp(
        request: () => _client
            .post(
              url,
              headers: headers,
              body: body != null ? json.encode(body) : null,
            )
            .timeout(ApiConfig.connectionTimeout),
        onRetry: (attempt, error) {
          Logger.debug('🔄 Retrying POST $endpoint (attempt $attempt): $error');
        },
      );

      // Debug logging
      Logger.debug('📥 Response status: ${response.statusCode}');
      Logger.debug('📥 Response body: ${response.body}');

      // Handle 401 Unauthorized
      if (response.statusCode == 401) {
        await _authService.logout();
        return ApiResponse<T>(
          success: false,
          message: 'Session expired. Please login again.',
          statusCode: 401,
        );
      }

      return _handleResponse<T>(response, fromJson);
    } catch (e) {
      return ApiResponse<T>(
        success: false,
        message: 'Network error: ${e.toString()}',
      );
    }
  }

  // PUT request
  Future<ApiResponse<T>> put<T>(
    String endpoint, {
    Map<String, dynamic>? body,
    T Function(dynamic)? fromJson,
  }) async {
    try {
      final headers = await _getHeaders();
      final url = Uri.parse('${ApiConfig.baseUrl}$endpoint');

      final response = await _client
          .put(
            url,
            headers: headers,
            body: body != null ? json.encode(body) : null,
          )
          .timeout(ApiConfig.connectionTimeout);

      // Handle 401 Unauthorized
      if (response.statusCode == 401) {
        await _authService.logout();
        return ApiResponse<T>(
          success: false,
          message: 'Session expired. Please login again.',
          statusCode: 401,
        );
      }

      return _handleResponse<T>(response, fromJson);
    } catch (e) {
      return ApiResponse<T>(
        success: false,
        message: 'Network error: ${e.toString()}',
      );
    }
  }

  // DELETE request
  Future<ApiResponse<T>> delete<T>(
    String endpoint, {
    T Function(dynamic)? fromJson,
  }) async {
    try {
      final headers = await _getHeaders();
      final url = Uri.parse('${ApiConfig.baseUrl}$endpoint');

      final response = await _client
          .delete(url, headers: headers)
          .timeout(ApiConfig.connectionTimeout);

      // Handle 401 Unauthorized
      if (response.statusCode == 401) {
        await _authService.logout();
        return ApiResponse<T>(
          success: false,
          message: 'Session expired. Please login again.',
          statusCode: 401,
        );
      }

      return _handleResponse<T>(response, fromJson);
    } catch (e) {
      return ApiResponse<T>(
        success: false,
        message: 'Network error: ${e.toString()}',
      );
    }
  }

  // Dispose
  void dispose() {
    _client.close();
  }
}
