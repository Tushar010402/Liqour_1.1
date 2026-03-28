import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/api_response.dart';
import '../utils/network_retry.dart';
import 'auth_service.dart';

/// HTTP API Service with interceptors
/// OPTIMIZED: Added kDebugMode guards to reduce logging overhead
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
    }

    if (tenantId != null) {
      headers['X-Tenant-ID'] = tenantId.toString();
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
      if (kDebugMode) {
        print('🚨 ApiService: JSON parse error - Status: $statusCode');
        print('🚨 ApiService: Response body: ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}');
        print('🚨 ApiService: Parse error: $e');
      }
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

    // Backend can send error in either 'message' or 'error' key
    // Check 'message' first as per backend convention
    final errorMessage = (errorBody['message'] as String?) ??
                        (errorBody['error'] as String?) ??
                        'Request failed';

    if (kDebugMode) {
      print('🚨 ApiService: Error Response - Status: $statusCode, Message: $errorMessage');
      if (errorBody['errors'] != null) {
        print('🚨 ApiService: Field Errors: ${errorBody['errors']}');
      }
    }

    return ApiResponse<T>(
      success: false,
      message: errorMessage,
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
      var headers = await _getHeaders();

      // Build URL with query parameters
      var url = Uri.parse('${ApiConfig.baseUrl}$endpoint');
      if (queryParams != null && queryParams.isNotEmpty) {
        url = url.replace(queryParameters: queryParams.map(
          (key, value) => MapEntry(key, value.toString()),
        ));
      }

      var response = await NetworkRetry.executeHttp(
        request: () => _client
            .get(url, headers: headers)
            .timeout(ApiConfig.connectionTimeout),
        onRetry: (attempt, error) {},
      );

      // Handle 401 Unauthorized - Retry once with fresh token
      if (response.statusCode == 401) {
        if (kDebugMode) print('⚠️ ApiService: 401 on $endpoint, refreshing token');

        // Get fresh headers (forces re-read from secure storage)
        headers = await _getHeaders();

        // Retry request
        response = await _client
            .get(url, headers: headers)
            .timeout(ApiConfig.connectionTimeout);

        // If still 401, logout
        if (response.statusCode == 401) {
          if (kDebugMode) print('🚫 ApiService: Still 401 after retry - logging out');
          await _authService.logout();
          return ApiResponse<T>(
            success: false,
            message: 'Session expired. Please login again.',
            statusCode: 401,
          );
        }
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
      var headers = await _getHeaders();
      final url = Uri.parse('${ApiConfig.baseUrl}$endpoint');

      if (kDebugMode) print('🌐 ApiService: POST $endpoint');

      var response = await NetworkRetry.executeHttp(
        request: () => _client
            .post(
              url,
              headers: headers,
              body: body != null ? json.encode(body) : null,
            )
            .timeout(ApiConfig.connectionTimeout),
        onRetry: (attempt, error) {},
      );

      if (kDebugMode) print('🌐 ApiService: POST $endpoint - Status: ${response.statusCode}');

      // Handle 401 Unauthorized - Retry once with fresh token
      if (response.statusCode == 401) {
        if (kDebugMode) print('⚠️ ApiService: 401 on $endpoint, refreshing token');

        // Get fresh headers (forces re-read from secure storage)
        headers = await _getHeaders();

        // Retry request
        response = await _client
            .post(
              url,
              headers: headers,
              body: body != null ? json.encode(body) : null,
            )
            .timeout(ApiConfig.connectionTimeout);

        // If still 401, logout
        if (response.statusCode == 401) {
          if (kDebugMode) print('🚫 ApiService: Still 401 after retry - logging out');
          await _authService.logout();
          return ApiResponse<T>(
            success: false,
            message: 'Session expired. Please login again.',
            statusCode: 401,
          );
        }
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
      var headers = await _getHeaders();
      final url = Uri.parse('${ApiConfig.baseUrl}$endpoint');

      var response = await _client
          .put(
            url,
            headers: headers,
            body: body != null ? json.encode(body) : null,
          )
          .timeout(ApiConfig.connectionTimeout);

      // Handle 401 Unauthorized - Retry once with fresh token
      if (response.statusCode == 401) {
        if (kDebugMode) print('⚠️ ApiService: 401 on $endpoint, refreshing token');

        // Get fresh headers (forces re-read from secure storage)
        headers = await _getHeaders();

        // Retry request
        response = await _client
            .put(
              url,
              headers: headers,
              body: body != null ? json.encode(body) : null,
            )
            .timeout(ApiConfig.connectionTimeout);

        // If still 401, logout
        if (response.statusCode == 401) {
          if (kDebugMode) print('🚫 ApiService: Still 401 after retry - logging out');
          await _authService.logout();
          return ApiResponse<T>(
            success: false,
            message: 'Session expired. Please login again.',
            statusCode: 401,
          );
        }
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
      var headers = await _getHeaders();
      final url = Uri.parse('${ApiConfig.baseUrl}$endpoint');

      var response = await _client
          .delete(url, headers: headers)
          .timeout(ApiConfig.connectionTimeout);

      // Handle 401 Unauthorized - Retry once with fresh token
      if (response.statusCode == 401) {
        if (kDebugMode) print('⚠️ ApiService: 401 on $endpoint, refreshing token');

        // Get fresh headers (forces re-read from secure storage)
        headers = await _getHeaders();

        // Retry request
        response = await _client
            .delete(url, headers: headers)
            .timeout(ApiConfig.connectionTimeout);

        // If still 401, logout
        if (response.statusCode == 401) {
          if (kDebugMode) print('🚫 ApiService: Still 401 after retry - logging out');
          await _authService.logout();
          return ApiResponse<T>(
            success: false,
            message: 'Session expired. Please login again.',
            statusCode: 401,
          );
        }
      }

      return _handleResponse<T>(response, fromJson);
    } catch (e) {
      return ApiResponse<T>(
        success: false,
        message: 'Network error: ${e.toString()}',
      );
    }
  }

  // Download file
  Future<ApiResponse<String>> downloadFile(
    String endpoint,
    String savePath,
  ) async {
    try {
      final headers = await _getHeaders();
      final url = Uri.parse('${ApiConfig.baseUrl}$endpoint');

      if (kDebugMode) print('📥 ApiService: Downloading file from $endpoint');

      final response = await _client
          .get(url, headers: headers)
          .timeout(ApiConfig.connectionTimeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        // Write file to disk
        final file = File(savePath);
        await file.writeAsBytes(response.bodyBytes);

        if (kDebugMode) print('✅ ApiService: File downloaded - $savePath');

        return ApiResponse<String>(
          success: true,
          data: savePath,
          message: 'File downloaded successfully',
          statusCode: response.statusCode,
        );
      }

      return ApiResponse<String>(
        success: false,
        message: 'Failed to download file',
        statusCode: response.statusCode,
      );
    } catch (e) {
      if (kDebugMode) print('❌ ApiService: Download error - $e');
      return ApiResponse<String>(
        success: false,
        message: 'Network error: ${e.toString()}',
      );
    }
  }

  // Upload file using multipart/form-data
  Future<ApiResponse<T>> uploadFile<T>(
    String endpoint,
    String filePath, {
    T Function(dynamic)? fromJson,
    String fileFieldName = 'file',
  }) async {
    try {
      final headers = await _getHeaders();
      final url = Uri.parse('${ApiConfig.baseUrl}$endpoint');

      if (kDebugMode) print('📤 ApiService: Uploading file to $endpoint');

      // Create multipart request
      final request = http.MultipartRequest('POST', url);

      // Add headers (but remove Content-Type as multipart will set it)
      headers.forEach((key, value) {
        if (key.toLowerCase() != 'content-type') {
          request.headers[key] = value;
        }
      });

      // Add file
      final file = File(filePath);
      final stream = http.ByteStream(file.openRead());
      final length = await file.length();
      final multipartFile = http.MultipartFile(
        fileFieldName,
        stream,
        length,
        filename: file.path.split('/').last,
      );
      request.files.add(multipartFile);

      if (kDebugMode) print('📤 ApiService: File size - $length bytes');

      // Send request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (kDebugMode) print('📤 ApiService: Upload complete - Status: ${response.statusCode}');

      return _handleResponse<T>(response, fromJson);
    } catch (e) {
      if (kDebugMode) print('❌ ApiService: Upload error - $e');
      return ApiResponse<T>(
        success: false,
        message: 'Upload error: ${e.toString()}',
      );
    }
  }

  // Dispose
  void dispose() {
    _client.close();
  }
}
