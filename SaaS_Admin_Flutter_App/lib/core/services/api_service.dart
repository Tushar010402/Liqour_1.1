import 'dart:io';
import 'package:dio/dio.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import '../constants/api_endpoints.dart';
import '../models/api_response.dart';
import 'auth_service.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  late Dio _dio;
  final AuthService _authService = AuthService();

  void initialize() {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiEndpoints.baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    // Add interceptors
    _dio.interceptors.add(_authInterceptor());
    _dio.interceptors.add(PrettyDioLogger(
      requestHeader: true,
      requestBody: true,
      responseBody: true,
      responseHeader: false,
      error: true,
      compact: true,
    ));
  }

  // Auth interceptor to add JWT token
  Interceptor _authInterceptor() {
    return InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _authService.getToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          // Token expired, logout user
          await _authService.logout();
        }
        handler.next(error);
      },
    );
  }

  // Generic GET request
  Future<ApiResponse<T>> get<T>(
    String endpoint, {
    Map<String, dynamic>? queryParameters,
    T Function(dynamic)? fromJson,
  }) async {
    try {
      final response = await _dio.get(
        endpoint,
        queryParameters: queryParameters,
      );
      return _handleResponse<T>(response, fromJson);
    } catch (e) {
      return _handleError<T>(e);
    }
  }

  // Generic POST request
  Future<ApiResponse<T>> post<T>(
    String endpoint, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    T Function(dynamic)? fromJson,
  }) async {
    try {
      final response = await _dio.post(
        endpoint,
        data: data,
        queryParameters: queryParameters,
      );
      return _handleResponse<T>(response, fromJson);
    } catch (e) {
      return _handleError<T>(e);
    }
  }

  // Generic PUT request
  Future<ApiResponse<T>> put<T>(
    String endpoint, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    T Function(dynamic)? fromJson,
  }) async {
    try {
      final response = await _dio.put(
        endpoint,
        data: data,
        queryParameters: queryParameters,
      );
      return _handleResponse<T>(response, fromJson);
    } catch (e) {
      return _handleError<T>(e);
    }
  }

  // Generic DELETE request
  Future<ApiResponse<T>> delete<T>(
    String endpoint, {
    Map<String, dynamic>? queryParameters,
    T Function(dynamic)? fromJson,
  }) async {
    try {
      final response = await _dio.delete(
        endpoint,
        queryParameters: queryParameters,
      );
      return _handleResponse<T>(response, fromJson);
    } catch (e) {
      return _handleError<T>(e);
    }
  }

  // Handle successful response
  ApiResponse<T> _handleResponse<T>(
    Response response,
    T Function(dynamic)? fromJson,
  ) {
    final statusCode = response.statusCode ?? 500;
    print(
        'DEBUG: ApiService._handleResponse - Status: $statusCode, Data: ${response.data}');

    if (statusCode >= 200 && statusCode < 300) {
      final responseData = response.data;

      if (responseData is Map<String, dynamic>) {
        // Check for error field first (your backend error format)
        if (responseData.containsKey('error')) {
          final errorMsg =
              responseData['error']?.toString() ?? 'Request failed';
          final details = responseData['details']?.toString();
          final fullError = details != null ? '$errorMsg: $details' : errorMsg;
          print('DEBUG: API Error response - $fullError');
          return ApiResponse<T>.error(fullError, statusCode: statusCode);
        }

        // Check if response has explicit success field
        if (responseData.containsKey('success')) {
          final success = responseData['success'] as bool? ?? false;
          if (!success) {
            return ApiResponse<T>.error(
              responseData['error']?.toString() ?? 'Request failed',
              statusCode: statusCode,
            );
          }
        }

        // Extract data (your backend uses "data" field for both lists and single items)
        T? data;
        if (fromJson != null) {
          // Check if response has a "data" field (for both lists and objects)
          final dataField = responseData.containsKey('data')
              ? responseData['data']
              : responseData;
          print('DEBUG: Parsing data field: $dataField');
          data = fromJson(dataField);
        } else {
          data = responseData as T?;
        }

        final message = responseData['message']?.toString();
        print('DEBUG: API Success response - Message: $message, Data: $data');

        return ApiResponse<T>(
          success: true,
          data: data,
          message: message,
          statusCode: statusCode,
        );
      } else {
        // Direct response data
        T? data;
        if (fromJson != null) {
          data = fromJson(responseData);
        } else {
          data = responseData as T?;
        }

        return ApiResponse<T>(
          success: true,
          data: data,
          statusCode: statusCode,
        );
      }
    } else {
      return ApiResponse<T>.error(
        'HTTP Error: $statusCode',
        statusCode: statusCode,
      );
    }
  }

  // Handle errors
  ApiResponse<T> _handleError<T>(dynamic error) {
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return ApiResponse<T>.error(
            'Connection timeout. Please check your internet connection.',
            statusCode: 408,
          );

        case DioExceptionType.connectionError:
          return ApiResponse<T>.error(
            'Network connection error. Please check your internet connection.',
            statusCode: 0,
          );

        case DioExceptionType.badResponse:
          final response = error.response;
          if (response != null) {
            final statusCode = response.statusCode ?? 500;
            String message = 'Server error occurred';

            try {
              final responseData = response.data;
              if (responseData is Map<String, dynamic>) {
                message = responseData['error']?.toString() ??
                    responseData['message']?.toString() ??
                    'Server error occurred';
              } else if (responseData is String) {
                message = responseData;
              }
            } catch (_) {
              // Use default message
            }

            return ApiResponse<T>.error(message, statusCode: statusCode);
          }
          return ApiResponse<T>.error('Unknown server error');

        case DioExceptionType.cancel:
          return ApiResponse<T>.error('Request was cancelled');

        case DioExceptionType.unknown:
          if (error.error is SocketException) {
            return ApiResponse<T>.error(
              'Network connection error. Please check your internet connection.',
              statusCode: 0,
            );
          }
          return ApiResponse<T>.error(
            error.message ?? 'An unknown error occurred',
          );

        default:
          return ApiResponse<T>.error(
            error.message ?? 'An unknown error occurred',
          );
      }
    } else {
      return ApiResponse<T>.error(
        error.toString(),
      );
    }
  }

  // Upload file
  Future<ApiResponse<T>> uploadFile<T>(
    String endpoint,
    String filePath, {
    String fieldName = 'file',
    Map<String, dynamic>? additionalData,
    T Function(dynamic)? fromJson,
    ProgressCallback? onSendProgress,
  }) async {
    try {
      final formData = FormData.fromMap({
        fieldName: await MultipartFile.fromFile(filePath),
        ...?additionalData,
      });

      final response = await _dio.post(
        endpoint,
        data: formData,
        onSendProgress: onSendProgress,
      );

      return _handleResponse<T>(response, fromJson);
    } catch (e) {
      return _handleError<T>(e);
    }
  }

  // Download file
  Future<ApiResponse<String>> downloadFile(
    String endpoint,
    String savePath, {
    ProgressCallback? onReceiveProgress,
  }) async {
    try {
      await _dio.download(
        endpoint,
        savePath,
        onReceiveProgress: onReceiveProgress,
      );
      return ApiResponse<String>.success(savePath);
    } catch (e) {
      return _handleError<String>(e);
    }
  }

  // Cancel all requests
  void cancelRequests() {
    _dio.close(force: true);
  }
}
