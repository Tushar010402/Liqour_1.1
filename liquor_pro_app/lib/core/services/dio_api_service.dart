import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:flutter/foundation.dart';
import '../config/api_config.dart';
import '../logging/interceptors/dio_logging_interceptor.dart';
import '../models/api_response.dart' as app_models;
import '../utils/app_logger.dart';
import '../utils/logger.dart';
import '../utils/connectivity_helper.dart';
import 'auth_service.dart';
import 'notification_navigation_service.dart';
import 'offline_queue_service.dart';

/// Industrial-Grade API Service using Dio
/// OPTIMIZED: Added kDebugMode guards to eliminate production logging overhead
/// Features:
/// - HTTP/2 with connection pooling
/// - Request/response interceptors
/// - Automatic retry with exponential backoff
/// - Token refresh on 401
/// - Session expiration detection and auto-logout
/// - Performance monitoring
/// - Request/response caching
class DioApiService {
  late final Dio _dio;
  final AuthService _authService;
  final CacheOptions? _cacheOptions;
  final Function()? _onSessionExpired;
  final OfflineQueueService? _offlineQueue;

  // Token cache
  String? _cachedToken;
  String? _cachedTenantId;
  DateTime? _tokenCacheTime;
  static const Duration _tokenCacheLifetime = Duration(seconds: 30);

  // Session expiration flag to prevent multiple logout calls
  bool _isSessionExpired = false;

  // Public endpoints that don't require auth token and should NOT trigger logout on 401
  static const _authEndpoints = [
    '/api/auth/verify-otp',
    '/api/auth/send-otp',
    '/api/auth/check-user',
    '/api/auth/register',
    '/api/auth/login',
    '/api/auth/force-login-otp',
    '/api/admin/validate/email',
    '/api/admin/validate/phone',
    '/api/admin/validate/tenant',
  ];

  DioApiService({
    required AuthService authService,
    Dio? dio,
    CacheOptions? cacheOptions,
    Function()? onSessionExpired,
    OfflineQueueService? offlineQueue,
  })  : _authService = authService,
        _cacheOptions = cacheOptions,
        _onSessionExpired = onSessionExpired,
        _offlineQueue = offlineQueue {
    _dio = dio ?? Dio(_getBaseOptions());
    _setupInterceptors();
  }

  /// Get base Dio options
  BaseOptions _getBaseOptions() {
    return BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: ApiConfig.connectionTimeout,
      receiveTimeout: ApiConfig.receiveTimeout,
      sendTimeout: ApiConfig.sendTimeout,

      // HTTP/2 support
      // Treat 401 (Unauthorized) as error to trigger error interceptor
      // Allow other status codes to be handled manually
      validateStatus: (status) {
        if (status == null) return false;
        // Treat 401 as error (for session expiration handling)
        if (status == 401) return false;
        // All other codes treated as successful (handled manually)
        return true;
      },

      // Headers
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': ApiConfig.userAgent,
        // Smart caching will be applied per-endpoint
      },

      // Response type
      responseType: ResponseType.json,
    );
  }

  /// Setup interceptors
  void _setupInterceptors() {
    // 0. Auth guard - blocks requests when no token (MUST be first to prevent unnecessary logging/network)
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Add auth token
          await _addAuthHeaders(options);

          // Block non-auth requests when token is missing to prevent 401 floods
          final requestPath = options.path;
          final isAuthEndpoint = _authEndpoints.any((ep) => requestPath.contains(ep));
          if (!isAuthEndpoint && (_cachedToken == null || _cachedToken!.isEmpty)) {
            if (kDebugMode) {
              Logger.warning('[DioAPI] Blocked request (no token): ${options.method} $requestPath');
            }
            return handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.cancel,
                message: 'Request blocked: no auth token',
              ),
            );
          }

          handler.next(options);
        },
      ),
    );

    // 1. Logging interceptor - only sees requests that pass auth guard
    _dio.interceptors.add(DioLoggingInterceptor());

    // 2. Request/Response/Error interceptor
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          handler.next(options);
        },

        onResponse: (response, handler) {
          handler.next(response);
        },

        onError: (error, handler) async {
          // Handle 401 - Unauthorized / Session Expired
          if (error.response?.statusCode == 401) {
            final requestPath = error.requestOptions.path;

            // For auth endpoints, 401 means invalid credentials/OTP - NOT session expiration
            final isAuthEndpoint = _authEndpoints.any((ep) => requestPath.contains(ep));
            if (isAuthEndpoint) {
              return handler.next(error);
            }

            final responseData = error.response?.data;

            // Check if this is a session expiration error
            bool isSessionExpired = false;
            String? errorMessage;

            if (responseData is Map<String, dynamic>) {
              errorMessage = responseData['error'] as String? ??
                            responseData['message'] as String?;

              if (errorMessage != null) {
                final lowerError = errorMessage.toLowerCase();
                isSessionExpired = lowerError.contains('session expired') ||
                                  lowerError.contains('token expired') ||
                                  lowerError.contains('invalid token') ||
                                  lowerError.contains('jwt expired') ||
                                  lowerError.contains('token is invalid') ||
                                  lowerError.contains('authorization header required');
              }
            }

            // Check if we have a token at all
            final currentToken = await _authService.getToken();
            final hasNoToken = currentToken == null || currentToken.isEmpty;

            // If no token or session expired, logout (only once)
            if ((hasNoToken || isSessionExpired) && !_isSessionExpired) {
              _isSessionExpired = true;

              await _authService.logout();
              _cachedToken = null;
              _cachedTenantId = null;
              _tokenCacheTime = null;

              _onSessionExpired?.call();
              return handler.reject(error);
            }

            // Try to refresh token if it might be stale
            if (!isSessionExpired && !hasNoToken) {
              await _refreshTokenCache(force: true);

              final refreshedToken = await _authService.getToken();
              if (refreshedToken == null || refreshedToken.isEmpty) {
                await _authService.logout();
                _onSessionExpired?.call();
                return handler.reject(error);
              }

              // Retry with fresh token
              try {
                final options = error.requestOptions;
                await _addAuthHeaders(options);
                final response = await _dio.fetch(options);

                if (response.statusCode == 401) {
                  await _authService.logout();
                  _onSessionExpired?.call();
                  return handler.reject(error);
                }

                return handler.resolve(response);
              } catch (e) {
                return handler.reject(error);
              }
            }
          }

          handler.next(error);
        },
      ),
    );

    // 2. Cache interceptor - HTTP response caching
    if (_cacheOptions != null) {
      _dio.interceptors.add(DioCacheInterceptor(options: _cacheOptions));
      // OPTIMIZED: Logging removed for performance
    }

    // 3. Retry interceptor - Exponential backoff
    _dio.interceptors.add(
      RetryInterceptor(
        dio: _dio,
        maxRetries: 3,
        retryDelays: const [
          Duration(seconds: 1),
          Duration(seconds: 2),
          Duration(seconds: 4),
        ],
      ),
    );
  }

  /// Add authentication headers to request
  Future<void> _addAuthHeaders(RequestOptions options) async {
    // Refresh token cache if needed
    if (_cachedToken == null ||
        _tokenCacheTime == null ||
        DateTime.now().difference(_tokenCacheTime!) > _tokenCacheLifetime) {
      await _refreshTokenCache();
    }

    // Add token
    if (_cachedToken != null && _cachedToken!.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $_cachedToken';
    }

    // Add tenant ID
    if (_cachedTenantId != null) {
      options.headers['X-Tenant-ID'] = _cachedTenantId!;
    }

    // Add start time for performance tracking
    options.extra['start_time'] = DateTime.now().millisecondsSinceEpoch;
  }

  /// Reset session expired flag - call this after successful login
  /// This allows new API calls to work again
  void resetSessionExpired() {
    _isSessionExpired = false;
    _cachedToken = null;
    _cachedTenantId = null;
    _tokenCacheTime = null;
  }

  /// Refresh token cache
  Future<void> _refreshTokenCache({bool force = false}) async {
    if (force || _cachedToken == null) {
      _cachedToken = await _authService.getToken();
      _cachedTenantId = await _authService.getTenantId();
      _tokenCacheTime = DateTime.now();
    }
  }

  /// Handle 403 Forbidden responses with user-friendly messages
  /// Parses the backend error format and provides actionable feedback
  app_models.ApiResponse<T> _handle403Response<T>(dynamic data, int statusCode) {
    final Map<String, dynamic> errorBody = data is Map<String, dynamic> ? data : {};

    // Extract error message from backend
    String rawError = errorBody['error'] as String? ??
        errorBody['message'] as String? ??
        'Permission denied';

    // Parse structured 403 response if available
    // Backend format: {"error": "permission denied: <reason>", "required_role": "admin", "user_role": "manager"}
    String? requiredRole = errorBody['required_role'] as String?;
    String? userRole = errorBody['user_role'] as String?;
    String? action = errorBody['action'] as String?;

    // Generate user-friendly message based on error type
    String friendlyMessage = _get403FriendlyMessage(
      rawError: rawError,
      requiredRole: requiredRole,
      userRole: userRole,
      action: action,
    );

    if (kDebugMode) {
      Logger.error('[DioAPI] 403 Forbidden:');
      Logger.debug('   Raw Error: $rawError');
      Logger.debug('   Required Role: $requiredRole');
      Logger.debug('   User Role: $userRole');
      Logger.debug('   Friendly Message: $friendlyMessage');
    }

    return app_models.ApiResponse<T>(
      success: false,
      message: friendlyMessage,
      statusCode: statusCode,
      errors: {
        'permission_denied': true,
        if (requiredRole != null) 'required_role': requiredRole,
        if (userRole != null) 'user_role': userRole,
        if (action != null) 'action': action,
        'raw_error': rawError,
      },
    );
  }

  /// Generate user-friendly 403 error messages
  String _get403FriendlyMessage({
    required String rawError,
    String? requiredRole,
    String? userRole,
    String? action,
  }) {
    final lowerError = rawError.toLowerCase();

    // User management specific errors
    if (lowerError.contains('manage user') || lowerError.contains('edit user')) {
      if (requiredRole != null && userRole != null) {
        return 'You cannot manage ${requiredRole}s as a ${_formatRole(userRole)}. '
               'You can only manage users with lower permission levels.';
      }
      return 'You don\'t have permission to manage this user. '
             'Users can only manage those with lower permission levels.';
    }

    if (lowerError.contains('delete user')) {
      if (requiredRole != null) {
        return 'You cannot delete ${requiredRole}s. Only administrators can delete users.';
      }
      return 'You don\'t have permission to delete users.';
    }

    if (lowerError.contains('create user')) {
      if (requiredRole != null) {
        return 'You cannot create users with the ${_formatRole(requiredRole)} role. '
               'You can only assign roles below your own level.';
      }
      return 'You don\'t have permission to create users with this role.';
    }

    // Tenant management errors
    if (lowerError.contains('tenant') || lowerError.contains('saas')) {
      return 'Tenant management is restricted to SaaS administrators only.';
    }

    // Shop management errors
    if (lowerError.contains('shop')) {
      return 'You need administrator access to manage shops.';
    }

    // Finance errors
    if (lowerError.contains('finance') || lowerError.contains('expense')) {
      return 'Financial operations require Assistant Manager level or above.';
    }

    // Generic permission errors
    if (requiredRole != null && userRole != null) {
      return 'This action requires ${_formatRole(requiredRole)} access. '
             'You are currently logged in as ${_formatRole(userRole)}.';
    }

    if (requiredRole != null) {
      return 'This action requires ${_formatRole(requiredRole)} access or higher.';
    }

    // Fallback
    return 'You don\'t have permission to perform this action. '
           'Please contact your administrator if you believe this is an error.';
  }

  /// Format role name for display
  String _formatRole(String role) {
    return role
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word.isEmpty ? '' : '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }

  /// Queue failed request for offline processing (Best Practice)
  /// Only queues write operations (POST, PUT, DELETE) when offline
  Future<void> _queueFailedRequest(
    String method,
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? queryParams,
    RequestType priority = RequestType.normal,
  }) async {
    if (_offlineQueue == null) return;

    // Best Practice: Only queue write operations
    // GET requests should not be queued (use cache instead)
    if (method.toUpperCase() == 'GET') {
      if (kDebugMode) {
        AppLogger.debug('[OfflineQueue] Skipping GET request - not queueable');
      }
      return;
    }

    try {
      final requestId = await _offlineQueue.queueRequest(
        method: method,
        endpoint: endpoint,
        body: body,
        queryParams: queryParams,
        type: priority,
      );

      if (kDebugMode) {
        AppLogger.debug(
          '[OfflineQueue] Queued $method $endpoint (${requestId.substring(0, 8)})'
        );
      }
    } catch (e) {
      AppLogger.error('[OfflineQueue] Failed to queue request: $e');
    }
  }

  /// Convert Dio response to ApiResponse
  app_models.ApiResponse<T> _handleResponse<T>(
    Response response,
    T Function(dynamic)? fromJson,
  ) {
    final statusCode = response.statusCode ?? 0;
    final data = response.data;

    // Handle 403 Forbidden - Permission denied
    if (statusCode == 403) {
      return _handle403Response<T>(data, statusCode);
    }

    // Handle 409 Conflict - Device Limit Reached
    // Special case: 409 response contains important data (active_sessions)
    // that needs to be passed back to the caller for device selection UI
    if (statusCode == 409) {
      final Map<String, dynamic> errorBody = data is Map<String, dynamic> ? data : {};
      if (kDebugMode) {
        Logger.warning('[DioAPI] 409 Conflict - Device Limit');
        Logger.debug('   Full error body: $errorBody');
      }
      return app_models.ApiResponse<T>(
        success: false,
        message: errorBody['message'] as String? ?? 'Conflict',
        data: fromJson != null ? fromJson(errorBody) : errorBody as T?,
        statusCode: statusCode,
      );
    }

    // Handle success responses (200-299)
    if (statusCode >= 200 && statusCode < 300) {
      // Handle 204 No Content - successful operation with no response body
      // Standard for DELETE operations per REST conventions
      if (statusCode == 204 || data == null || (data is String && data.isEmpty)) {
        return app_models.ApiResponse<T>(
          success: true,
          message: 'Request completed successfully',
          statusCode: statusCode,
        );
      }

      // If response is a List
      if (data is List) {
        return app_models.ApiResponse<T>(
          success: true,
          data: fromJson != null ? fromJson(data) : data as T?,
          statusCode: statusCode,
        );
      }

      // If response is a Map
      if (data is Map<String, dynamic>) {
        final responseData = data.containsKey('data') ? data['data'] : data;

        return app_models.ApiResponse<T>(
          success: true,
          message: data['message'] as String?,
          data: fromJson != null && responseData != null
              ? fromJson(responseData)
              : responseData as T?,
          statusCode: statusCode,
        );
      }

      // Unexpected response type
      return app_models.ApiResponse<T>(
        success: false,
        message: 'Unexpected response format',
        statusCode: statusCode,
      );
    }

    // Handle error responses
    final Map<String, dynamic> errorBody = data is Map<String, dynamic> ? data : {};

    // Parse error message
    String errorMessage = errorBody['error'] as String? ??
        errorBody['message'] as String? ??
        'Request failed with status $statusCode';

    // Parse errors - handle both array and map formats
    Map<String, dynamic>? parsedErrors;

    if (errorBody['errors'] != null) {
      // Check if errors is a List (array format from backend)
      if (errorBody['errors'] is List) {
        final errorsList = errorBody['errors'] as List;
        parsedErrors = {};

        // Convert array format [{field: "email", message: "is required"}]
        // to map format {email: "is required"}
        for (var error in errorsList) {
          if (error is Map<String, dynamic>) {
            final field = error['field'] as String?;
            final message = error['message'] as String?;
            if (field != null && message != null) {
              parsedErrors[field] = message;

              // Also append to main error message for better visibility
              errorMessage = '$errorMessage\n$field: $message';
            }
          }
        }
      }
      // Check if errors is already a Map
      else if (errorBody['errors'] is Map<String, dynamic>) {
        parsedErrors = errorBody['errors'] as Map<String, dynamic>;
      }
    }

    return app_models.ApiResponse<T>(
      success: false,
      message: errorMessage.trim(),
      errors: parsedErrors,
      statusCode: statusCode,
    );
  }

  /// Handle Dio errors
  app_models.ApiResponse<T> _handleError<T>(DioException error) {
    String message;

    // Log the underlying error for debugging
    if (kDebugMode) {
      Logger.debug('[DioAPI] Error Details:');
      Logger.debug('   Type: ${error.type}');
      Logger.debug('   Message: ${error.message}');
      Logger.debug('   Underlying Error: ${error.error}');
      Logger.debug('   Error Type: ${error.error?.runtimeType}');
    }

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        message = 'Connection timeout. Please check your internet connection.';
        break;
      case DioExceptionType.badResponse:
        message = error.response?.data?['message'] ??
                 error.response?.data?['error'] ??
                 'Server error: ${error.response?.statusCode}';
        break;
      case DioExceptionType.connectionError:
        message = 'Could not connect to server. Please check your internet connection.';
        break;
      case DioExceptionType.cancel:
        message = 'Request was cancelled';
        break;
      default:
        // Include underlying error for unknown types
        final underlyingError = error.error?.toString() ?? '';
        message = 'Network error: ${error.message ?? underlyingError}';
    }

    return app_models.ApiResponse<T>(
      success: false,
      message: message,
      statusCode: error.response?.statusCode,
    );
  }

  /// GET request
  Future<app_models.ApiResponse<T>> get<T>(
    String endpoint, {
    Map<String, dynamic>? queryParams,
    T Function(dynamic)? fromJson,
    Options? options,
  }) async {
    try {
      final response = await _dio.get(
        endpoint,
        queryParameters: queryParams,
        options: options,
      );

      return _handleResponse<T>(response, fromJson);
    } on DioException catch (e) {
      if (kDebugMode) {
        Logger.error('[DioAPI] DioException in GET $endpoint: ${e.response?.statusCode}');
      }
      return _handleError<T>(e);
    } catch (e) {
      // Errors are always logged (important for crash reporting)
      AppLogger.error('[Dio] GET $endpoint - Unexpected: $e');
      return app_models.ApiResponse<T>(
        success: false,
        message: 'Unexpected error: $e',
      );
    }
  }

  /// POST request with automatic offline queueing
  Future<app_models.ApiResponse<T>> post<T>(
    String endpoint, {
    dynamic body, // Changed from Map<String, dynamic>? to dynamic to support FormData
    T Function(dynamic)? fromJson,
    Options? options,
    RequestType priority = RequestType.normal,
    bool queueIfOffline = true,
  }) async {
    try {
      final response = await _dio.post(
        endpoint,
        data: body,
        options: options,
      );

      return _handleResponse<T>(response, fromJson);
    } on DioException catch (e) {
      if (kDebugMode) {
        Logger.error('[DioAPI] DioException in POST $endpoint: ${e.response?.statusCode}');
      }

      // Best Practice: Queue request if offline (connectivity error)
      if (queueIfOffline && e.type == DioExceptionType.connectionError) {
        // Check if offline
        final hasConnection = await ConnectivityHelper.hasConnection();
        if (!hasConnection && body is Map<String, dynamic>) {
          await _queueFailedRequest(
            'POST',
            endpoint,
            body: body,
            priority: priority,
          );

          // Return friendly error message indicating queued
          return app_models.ApiResponse<T>(
            success: false,
            message: 'No connection. Request queued for automatic retry.',
            statusCode: null,
          );
        }
      }

      return _handleError<T>(e);
    } catch (e) {
      AppLogger.error('[Dio] POST $endpoint - Unexpected: $e');
      return app_models.ApiResponse<T>(
        success: false,
        message: 'Unexpected error: $e',
      );
    }
  }

  /// PUT request with automatic offline queueing
  Future<app_models.ApiResponse<T>> put<T>(
    String endpoint, {
    Map<String, dynamic>? body,
    T Function(dynamic)? fromJson,
    Options? options,
    RequestType priority = RequestType.normal,
    bool queueIfOffline = true,
  }) async {
    try {
      final response = await _dio.put(
        endpoint,
        data: body,
        options: options,
      );

      return _handleResponse<T>(response, fromJson);
    } on DioException catch (e) {
      // Best Practice: Queue request if offline (connectivity error)
      if (queueIfOffline && e.type == DioExceptionType.connectionError) {
        // Check if offline
        final hasConnection = await ConnectivityHelper.hasConnection();
        if (!hasConnection) {
          await _queueFailedRequest(
            'PUT',
            endpoint,
            body: body,
            priority: priority,
          );

          // Return friendly error message indicating queued
          return app_models.ApiResponse<T>(
            success: false,
            message: 'No connection. Request queued for automatic retry.',
            statusCode: null,
          );
        }
      }

      return _handleError<T>(e);
    } catch (e) {
      AppLogger.error('[Dio] PUT $endpoint - Unexpected: $e');
      return app_models.ApiResponse<T>(
        success: false,
        message: 'Unexpected error: $e',
      );
    }
  }

  /// PATCH request with automatic offline queueing
  Future<app_models.ApiResponse<T>> patch<T>(
    String endpoint, {
    Map<String, dynamic>? body,
    T Function(dynamic)? fromJson,
    Options? options,
    RequestType priority = RequestType.normal,
    bool queueIfOffline = true,
  }) async {
    try {
      final response = await _dio.patch(
        endpoint,
        data: body,
        options: options,
      );

      return _handleResponse<T>(response, fromJson);
    } on DioException catch (e) {
      // Best Practice: Queue request if offline (connectivity error)
      if (queueIfOffline && e.type == DioExceptionType.connectionError) {
        // Check if offline
        final hasConnection = await ConnectivityHelper.hasConnection();
        if (!hasConnection) {
          await _queueFailedRequest(
            'PATCH',
            endpoint,
            body: body,
            priority: priority,
          );

          // Return friendly error message indicating queued
          return app_models.ApiResponse<T>(
            success: false,
            message: 'No connection. Request queued for automatic retry.',
            statusCode: null,
          );
        }
      }

      return _handleError<T>(e);
    } catch (e) {
      AppLogger.error('[Dio] PATCH $endpoint - Unexpected: $e');
      return app_models.ApiResponse<T>(
        success: false,
        message: 'Unexpected error: $e',
      );
    }
  }

  /// DELETE request with automatic offline queueing
  Future<app_models.ApiResponse<T>> delete<T>(
    String endpoint, {
    Map<String, dynamic>? body,
    T Function(dynamic)? fromJson,
    Options? options,
    RequestType priority = RequestType.normal,
    bool queueIfOffline = true,
  }) async {
    try {
      final response = await _dio.delete(
        endpoint,
        data: body,
        options: options,
      );

      return _handleResponse<T>(response, fromJson);
    } on DioException catch (e) {
      // Best Practice: Queue request if offline (connectivity error)
      if (queueIfOffline && e.type == DioExceptionType.connectionError) {
        // Check if offline
        final hasConnection = await ConnectivityHelper.hasConnection();
        if (!hasConnection) {
          await _queueFailedRequest(
            'DELETE',
            endpoint,
            priority: priority,
          );

          // Return friendly error message indicating queued
          return app_models.ApiResponse<T>(
            success: false,
            message: 'No connection. Request queued for automatic retry.',
            statusCode: null,
          );
        }
      }

      return _handleError<T>(e);
    } catch (e) {
      AppLogger.error('[Dio] DELETE $endpoint - Unexpected: $e');
      return app_models.ApiResponse<T>(
        success: false,
        message: 'Unexpected error: $e',
      );
    }
  }

  /// Upload file (multipart)
  Future<app_models.ApiResponse<T>> uploadFile<T>(
    String endpoint,
    String filePath, {
    T Function(dynamic)? fromJson,
    String fileFieldName = 'file',
    Map<String, dynamic>? additionalData,
    ProgressCallback? onProgress,
  }) async {
    try {
      final formData = FormData.fromMap({
        fileFieldName: await MultipartFile.fromFile(filePath),
        ...?additionalData,
      });

      final response = await _dio.post(
        endpoint,
        data: formData,
        onSendProgress: onProgress,
      );

      return _handleResponse<T>(response, fromJson);
    } on DioException catch (e) {
      return _handleError<T>(e);
    } catch (e) {
      AppLogger.error('[Dio] Upload $endpoint - Error: $e');
      return app_models.ApiResponse<T>(
        success: false,
        message: 'Upload error: $e',
      );
    }
  }

  /// Download file
  Future<app_models.ApiResponse<String>> downloadFile(
    String endpoint,
    String savePath, {
    ProgressCallback? onProgress,
  }) async {
    try {
      await _dio.download(
        endpoint,
        savePath,
        onReceiveProgress: onProgress,
      );

      return app_models.ApiResponse<String>(
        success: true,
        data: savePath,
        message: 'File downloaded successfully',
        statusCode: 200,
      );
    } on DioException catch (e) {
      return _handleError<String>(e);
    } catch (e) {
      AppLogger.error('[Dio] Download $endpoint - Error: $e');
      return app_models.ApiResponse<String>(
        success: false,
        message: 'Download error: $e',
      );
    }
  }

  /// Truncate data for logging
  String _truncateData(dynamic data) {
    final str = data.toString();
    return str.length > 500 ? '${str.substring(0, 500)}...' : str;
  }

  /// Get tenant ID from auth service
  Future<String?> getTenantId() async {
    return await _authService.getTenantId();
  }

  /// Get token from auth service
  Future<String?> getToken() async {
    return await _authService.getToken();
  }

  /// Force refresh token cache - call this after login/registration to invalidate old cached token
  /// Also resets session expired flag to allow new API calls
  Future<void> forceRefreshToken() async {
    // Reset session expired flag first
    _isSessionExpired = false;
    // Then refresh token cache
    await _refreshTokenCache(force: true);
    // Reset navigation service flag
    NotificationNavigationService.resetSessionExpirationFlag();
    Logger.info('[DioAPI] Token cache forcefully refreshed and session reset');
  }

  /// Close Dio client
  void dispose() {
    _dio.close();
  }
}

/// Retry Interceptor with exponential backoff and connectivity awareness
/// Best Practice: Check connectivity before retrying to avoid wasting resources
class RetryInterceptor extends Interceptor {
  final Dio dio;
  final int maxRetries;
  final List<Duration> retryDelays;

  // Connectivity check throttling to prevent spam
  static DateTime? _lastConnectivityCheck;
  static bool? _lastConnectivityStatus;
  static const Duration _connectivityCheckThrottle = Duration(seconds: 5);

  RetryInterceptor({
    required this.dio,
    this.maxRetries = 3,
    this.retryDelays = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
    ],
  });

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final extra = err.requestOptions.extra;
    final retryCount = extra['retry_count'] as int? ?? 0;

    // Check if we should retry based on error type
    if (retryCount < maxRetries && _shouldRetry(err)) {
      // Best Practice: Check connectivity before retrying
      // This prevents wasting resources retrying when offline
      final hasConnection = await _checkConnectivityThrottled();

      if (!hasConnection) {
        // Skip retry if offline - fail fast
        if (kDebugMode) {
          AppLogger.debug('[Retry] Skipping retry - device is offline');
        }
        return super.onError(err, handler);
      }

      // Log retry attempt in debug mode only
      if (kDebugMode) {
        AppLogger.debug(
          '[Retry] Attempt ${retryCount + 1}/$maxRetries for ${err.requestOptions.path}'
        );
      }

      // Wait before retry (exponential backoff)
      if (retryCount < retryDelays.length) {
        await Future.delayed(retryDelays[retryCount]);
      } else {
        await Future.delayed(retryDelays.last);
      }

      // Increment retry count
      err.requestOptions.extra['retry_count'] = retryCount + 1;

      // Retry request
      try {
        final response = await dio.fetch(err.requestOptions);
        if (kDebugMode) {
          AppLogger.debug('[Retry] Succeeded on attempt ${retryCount + 1}');
        }
        return handler.resolve(response);
      } on DioException catch (e) {
        return super.onError(e, handler);
      }
    }

    // Max retries reached or should not retry
    if (retryCount >= maxRetries && kDebugMode) {
      AppLogger.debug('[Retry] Max retries reached for ${err.requestOptions.path}');
    }
    return super.onError(err, handler);
  }

  /// Check connectivity with throttling to prevent spam
  /// Best Practice: Cache connectivity status for 5 seconds to reduce OS calls
  Future<bool> _checkConnectivityThrottled() async {
    final now = DateTime.now();

    // Use cached status if within throttle window
    if (_lastConnectivityCheck != null && _lastConnectivityStatus != null) {
      final timeSinceLastCheck = now.difference(_lastConnectivityCheck!);
      if (timeSinceLastCheck < _connectivityCheckThrottle) {
        return _lastConnectivityStatus!;
      }
    }

    // Check connectivity and cache result
    _lastConnectivityCheck = now;
    _lastConnectivityStatus = await ConnectivityHelper.hasConnection();
    return _lastConnectivityStatus!;
  }

  /// Check if error should be retried
  /// Best Practice: Only retry transient errors, not client errors
  /// OPTIMIZED: Don't retry connection timeouts (indicates server unreachable)
  bool _shouldRetry(DioException err) {
    // DON'T retry connection timeout - server is likely down
    // This prevents blocking the app for 45+ seconds per failed call
    if (err.type == DioExceptionType.connectionTimeout) {
      return false; // Fail fast
    }

    // Retry on send/receive timeouts (might be temporary network glitch)
    if (err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.receiveTimeout) {
      return true;
    }

    // DON'T retry connection errors - usually means no network
    if (err.type == DioExceptionType.connectionError) {
      return false; // Fail fast
    }

    // Retry on 5xx server errors (transient server issues)
    if (err.response?.statusCode != null) {
      final statusCode = err.response!.statusCode!;
      if (statusCode >= 500 && statusCode < 600) {
        return true;
      }
    }

    // Don't retry on client errors (4xx) or cancellation
    // These are permanent errors that won't be fixed by retrying
    return false;
  }
}
