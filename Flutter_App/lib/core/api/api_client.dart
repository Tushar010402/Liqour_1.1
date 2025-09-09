import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

import '../constants/app_constants.dart';
import '../utils/logger.dart';
import 'api_exceptions.dart';

/// Premium API client with advanced features
class ApiClient {
  late final Dio _dio;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  
  // Singleton instance
  static ApiClient? _instance;
  static ApiClient get instance => _instance ??= ApiClient._internal();
  
  ApiClient._internal() {
    _dio = Dio();
    _initializeInterceptors();
  }
  
  /// Initialize API client with configuration
  void _initializeInterceptors() {
    // Base options
    _dio.options = BaseOptions(
      baseUrl: AppConstants.baseUrl,
      connectTimeout: AppConstants.apiTimeout,
      receiveTimeout: AppConstants.apiTimeout,
      sendTimeout: AppConstants.apiTimeout,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-API-Version': AppConstants.apiVersion,
      },
    );
    
    // Request interceptor for authentication and logging
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: _onRequest,
        onResponse: _onResponse,
        onError: _onError,
      ),
    );
    
    // Pretty logger for development
    if (kDebugMode && AppConstants.enableNetworkLogging) {
      _dio.interceptors.add(
        PrettyDioLogger(
          requestHeader: true,
          requestBody: true,
          responseBody: true,
          responseHeader: false,
          error: true,
          compact: true,
          maxWidth: 90,
        ),
      );
    }
    
    // Retry interceptor
    _dio.interceptors.add(_RetryInterceptor());
  }
  
  /// Request interceptor
  Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      // Add authentication token
      final token = await _secureStorage.read(key: AppConstants.authTokenKey);
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      
      // Add tenant context
      final tenantId = await _secureStorage.read(key: AppConstants.tenantDataKey);
      if (tenantId != null) {
        options.headers['X-Tenant-ID'] = tenantId;
      }
      
      // Add request ID for tracking
      options.headers['X-Request-ID'] = _generateRequestId();
      
      // Log request
      AppLogger.networkRequest(
        options.method,
        options.uri.toString(),
        options.data,
      );
      
      handler.next(options);
    } catch (error) {
      AppLogger.error('Request interceptor error', error);
      handler.reject(DioException(requestOptions: options, error: error));
    }
  }
  
  /// Response interceptor
  Future<void> _onResponse(
    Response response,
    ResponseInterceptorHandler handler,
  ) async {
    try {
      // Log response
      AppLogger.networkResponse(
        response.requestOptions.method,
        response.requestOptions.uri.toString(),
        response.statusCode ?? 0,
        response.data,
      );
      
      handler.next(response);
    } catch (error) {
      AppLogger.error('Response interceptor error', error);
      handler.next(response);
    }
  }
  
  /// Error interceptor with automatic token refresh
  Future<void> _onError(
    DioException error,
    ErrorInterceptorHandler handler,
  ) async {
    try {
      AppLogger.error(
        'API Error: ${error.requestOptions.method} ${error.requestOptions.uri}',
        error.message,
      );
      
      // Handle token expiry
      if (error.response?.statusCode == 401) {
        AppLogger.info('Token expired, attempting refresh...');
        
        final refreshed = await _refreshToken();
        if (refreshed) {
          // Retry the original request
          final response = await _dio.request(
            error.requestOptions.path,
            data: error.requestOptions.data,
            queryParameters: error.requestOptions.queryParameters,
            options: Options(
              method: error.requestOptions.method,
              headers: error.requestOptions.headers,
            ),
          );
          
          AppLogger.info('Request retried successfully after token refresh');
          handler.resolve(response);
          return;
        } else {
          // Refresh failed, redirect to login
          AppLogger.warning('Token refresh failed, user needs to re-authenticate');
          await _clearAuthData();
          handler.reject(UnauthorizedException('Authentication expired'));
          return;
        }
      }
      
      // Convert DioException to custom exception
      final customException = _handleDioException(error);
      handler.reject(customException);
      
    } catch (handlerError) {
      AppLogger.error('Error interceptor failed', handlerError);
      handler.reject(error);
    }
  }
  
  /// Refresh authentication token
  Future<bool> _refreshToken() async {
    try {
      final refreshToken = await _secureStorage.read(key: AppConstants.refreshTokenKey);
      if (refreshToken == null) {
        AppLogger.warning('No refresh token available');
        return false;
      }
      
      final response = await _dio.post(
        '/api/auth/refresh',
        data: {'refresh_token': refreshToken},
        options: Options(
          headers: {'Authorization': null}, // Don't send expired token
        ),
      );
      
      if (response.statusCode == 200) {
        final data = response.data;
        await _secureStorage.write(key: AppConstants.authTokenKey, value: data['token']);
        await _secureStorage.write(key: AppConstants.refreshTokenKey, value: data['refresh_token']);
        
        AppLogger.info('Token refreshed successfully');
        return true;
      }
      
      return false;
    } catch (error) {
      AppLogger.error('Token refresh failed', error);
      return false;
    }
  }
  
  /// Clear authentication data
  Future<void> _clearAuthData() async {
    await Future.wait([
      _secureStorage.delete(key: AppConstants.authTokenKey),
      _secureStorage.delete(key: AppConstants.refreshTokenKey),
      _secureStorage.delete(key: AppConstants.userDataKey),
      _secureStorage.delete(key: AppConstants.tenantDataKey),
    ]);
  }
  
  /// Generate unique request ID
  String _generateRequestId() {
    return '${DateTime.now().millisecondsSinceEpoch}_${_generateRandomString(6)}';
  }
  
  /// Generate random string
  String _generateRandomString(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(length, (index) => chars[DateTime.now().microsecond % chars.length]).join();
  }
  
  /// Convert DioException to custom exception
  DioException _handleDioException(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return TimeoutException('Request timeout');
        
      case DioExceptionType.connectionError:
        return NetworkException('Network connection failed');
        
      case DioExceptionType.badResponse:
        final statusCode = error.response?.statusCode ?? 0;
        final message = error.response?.data?['message'] ?? error.message;
        
        switch (statusCode) {
          case 400:
            return BadRequestException(message ?? 'Bad request');
          case 401:
            return UnauthorizedException(message ?? 'Unauthorized');
          case 403:
            return ForbiddenException(message ?? 'Forbidden');
          case 404:
            return NotFoundException(message ?? 'Resource not found');
          case 422:
            return ValidationException(
              message ?? 'Validation failed',
              error.response?.data?['errors'],
            );
          case 429:
            return RateLimitException('Too many requests');
          case 500:
            return ServerException(message ?? 'Internal server error');
          case 502:
            return ServerException('Bad gateway');
          case 503:
            return ServerException('Service unavailable');
          default:
            return ServerException(message ?? 'Server error');
        }
        
      case DioExceptionType.cancel:
        return RequestCancelledException('Request was cancelled');
        
      default:
        return UnknownException(error.message ?? 'Unknown error occurred');
    }
  }
  
  // HTTP Methods
  
  /// GET request
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    try {
      return await _dio.get<T>(
        path,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );
    } catch (error) {
      rethrow;
    }
  }
  
  /// POST request
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    try {
      return await _dio.post<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );
    } catch (error) {
      rethrow;
    }
  }
  
  /// PUT request
  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    try {
      return await _dio.put<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );
    } catch (error) {
      rethrow;
    }
  }
  
  /// PATCH request
  Future<Response<T>> patch<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    try {
      return await _dio.patch<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );
    } catch (error) {
      rethrow;
    }
  }
  
  /// DELETE request
  Future<Response<T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    try {
      return await _dio.delete<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );
    } catch (error) {
      rethrow;
    }
  }
  
  /// Upload file
  Future<Response<T>> upload<T>(
    String path,
    FormData formData, {
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
  }) async {
    try {
      return await _dio.post<T>(
        path,
        data: formData,
        options: options,
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
      );
    } catch (error) {
      rethrow;
    }
  }
  
  /// Download file
  Future<Response> download(
    String urlPath,
    dynamic savePath, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    bool deleteOnError = true,
    String lengthHeader = Headers.contentLengthHeader,
    Options? options,
    void Function(int, int)? onReceiveProgress,
  }) async {
    try {
      return await _dio.download(
        urlPath,
        savePath,
        queryParameters: queryParameters,
        cancelToken: cancelToken,
        deleteOnError: deleteOnError,
        lengthHeader: lengthHeader,
        options: options,
        onReceiveProgress: onReceiveProgress,
      );
    } catch (error) {
      rethrow;
    }
  }
}

/// Retry interceptor for failed requests
class _RetryInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (_shouldRetry(err)) {
      AppLogger.info('Retrying request: ${err.requestOptions.uri}');
      
      try {
        final response = await Dio().request(
          err.requestOptions.path,
          data: err.requestOptions.data,
          queryParameters: err.requestOptions.queryParameters,
          options: Options(
            method: err.requestOptions.method,
            headers: err.requestOptions.headers,
          ),
        );
        
        handler.resolve(response);
        return;
      } catch (retryError) {
        AppLogger.warning('Retry failed', retryError);
      }
    }
    
    handler.next(err);
  }
  
  bool _shouldRetry(DioException error) {
    // Only retry on network errors or 5xx server errors
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout) {
      return true;
    }
    
    final statusCode = error.response?.statusCode;
    if (statusCode != null && statusCode >= 500 && statusCode < 600) {
      return true;
    }
    
    return false;
  }
}