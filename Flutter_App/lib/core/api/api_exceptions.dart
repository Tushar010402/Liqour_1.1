import 'package:dio/dio.dart';

/// Base API exception class
abstract class ApiException extends DioException {
  final String userMessage;
  final String? errorCode;
  final Map<String, dynamic>? errorData;
  
  ApiException(
    this.userMessage, {
    this.errorCode,
    this.errorData,
    required RequestOptions requestOptions,
    String? message,
  }) : super(
          requestOptions: requestOptions,
          message: message ?? userMessage,
        );
  
  @override
  String toString() {
    return 'ApiException: $userMessage (Code: $errorCode)';
  }
}

/// Network connection exception
class NetworkException extends ApiException {
  NetworkException(String message, {String? errorCode, Map<String, dynamic>? errorData})
      : super(
          message,
          errorCode: errorCode,
          errorData: errorData,
          requestOptions: RequestOptions(path: ''),
        );
}

/// Request timeout exception
class TimeoutException extends ApiException {
  TimeoutException(String message, {String? errorCode, Map<String, dynamic>? errorData})
      : super(
          message,
          errorCode: errorCode,
          errorData: errorData,
          requestOptions: RequestOptions(path: ''),
        );
}

/// Unauthorized access exception (401)
class UnauthorizedException extends ApiException {
  UnauthorizedException(String message, {String? errorCode, Map<String, dynamic>? errorData})
      : super(
          message,
          errorCode: errorCode,
          errorData: errorData,
          requestOptions: RequestOptions(path: ''),
        );
}

/// Forbidden access exception (403)
class ForbiddenException extends ApiException {
  ForbiddenException(String message, {String? errorCode, Map<String, dynamic>? errorData})
      : super(
          message,
          errorCode: errorCode,
          errorData: errorData,
          requestOptions: RequestOptions(path: ''),
        );
}

/// Resource not found exception (404)
class NotFoundException extends ApiException {
  NotFoundException(String message, {String? errorCode, Map<String, dynamic>? errorData})
      : super(
          message,
          errorCode: errorCode,
          errorData: errorData,
          requestOptions: RequestOptions(path: ''),
        );
}

/// Bad request exception (400)
class BadRequestException extends ApiException {
  BadRequestException(String message, {String? errorCode, Map<String, dynamic>? errorData})
      : super(
          message,
          errorCode: errorCode,
          errorData: errorData,
          requestOptions: RequestOptions(path: ''),
        );
}

/// Validation exception (422)
class ValidationException extends ApiException {
  final Map<String, dynamic>? validationErrors;
  
  ValidationException(
    String message,
    this.validationErrors, {
    String? errorCode,
    Map<String, dynamic>? errorData,
  }) : super(
          message,
          errorCode: errorCode,
          errorData: errorData,
          requestOptions: RequestOptions(path: ''),
        );
  
  /// Get field-specific validation errors
  List<String> getFieldErrors(String fieldName) {
    if (validationErrors == null) return [];
    
    final fieldErrors = validationErrors![fieldName];
    if (fieldErrors is List) {
      return fieldErrors.cast<String>();
    } else if (fieldErrors is String) {
      return [fieldErrors];
    }
    
    return [];
  }
  
  /// Get all validation errors as a flat list
  List<String> getAllErrors() {
    if (validationErrors == null) return [userMessage];
    
    final allErrors = <String>[];
    
    validationErrors!.forEach((field, errors) {
      if (errors is List) {
        allErrors.addAll(errors.cast<String>());
      } else if (errors is String) {
        allErrors.add(errors);
      }
    });
    
    return allErrors.isEmpty ? [userMessage] : allErrors;
  }
  
  @override
  String toString() {
    final errors = getAllErrors();
    return 'ValidationException: ${errors.join(', ')}';
  }
}

/// Rate limit exceeded exception (429)
class RateLimitException extends ApiException {
  final int? retryAfter;
  
  RateLimitException(
    String message, {
    this.retryAfter,
    String? errorCode,
    Map<String, dynamic>? errorData,
  }) : super(
          message,
          errorCode: errorCode,
          errorData: errorData,
          requestOptions: RequestOptions(path: ''),
        );
}

/// Server error exception (5xx)
class ServerException extends ApiException {
  final int? statusCode;
  
  ServerException(
    String message, {
    this.statusCode,
    String? errorCode,
    Map<String, dynamic>? errorData,
  }) : super(
          message,
          errorCode: errorCode,
          errorData: errorData,
          requestOptions: RequestOptions(path: ''),
        );
}

/// Request cancelled exception
class RequestCancelledException extends ApiException {
  RequestCancelledException(String message, {String? errorCode, Map<String, dynamic>? errorData})
      : super(
          message,
          errorCode: errorCode,
          errorData: errorData,
          requestOptions: RequestOptions(path: ''),
        );
}

/// Unknown exception for unhandled errors
class UnknownException extends ApiException {
  UnknownException(String message, {String? errorCode, Map<String, dynamic>? errorData})
      : super(
          message,
          errorCode: errorCode,
          errorData: errorData,
          requestOptions: RequestOptions(path: ''),
        );
}

/// Business logic exception for app-specific errors
class BusinessException extends ApiException {
  final String businessCode;
  
  BusinessException(
    String message,
    this.businessCode, {
    String? errorCode,
    Map<String, dynamic>? errorData,
  }) : super(
          message,
          errorCode: errorCode,
          errorData: errorData,
          requestOptions: RequestOptions(path: ''),
        );
}

/// Authentication exception for auth-related errors
class AuthenticationException extends ApiException {
  final AuthErrorType errorType;
  
  AuthenticationException(
    String message,
    this.errorType, {
    String? errorCode,
    Map<String, dynamic>? errorData,
  }) : super(
          message,
          errorCode: errorCode,
          errorData: errorData,
          requestOptions: RequestOptions(path: ''),
        );
}

/// Authentication error types
enum AuthErrorType {
  invalidCredentials,
  accountLocked,
  accountDisabled,
  tokenExpired,
  tokenInvalid,
  biometricNotAvailable,
  biometricNotEnrolled,
  biometricAuthFailed,
  multiFactorRequired,
  passwordExpired,
}

/// Exception handler utility
class ApiExceptionHandler {
  /// Get user-friendly message from exception
  static String getUserMessage(Object exception) {
    if (exception is ApiException) {
      return exception.userMessage;
    } else if (exception is DioException) {
      switch (exception.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return 'Request timeout. Please check your connection and try again.';
        case DioExceptionType.connectionError:
          return 'Unable to connect to server. Please check your internet connection.';
        case DioExceptionType.badResponse:
          final statusCode = exception.response?.statusCode;
          switch (statusCode) {
            case 400:
              return 'Invalid request. Please check your input and try again.';
            case 401:
              return 'Authentication required. Please login and try again.';
            case 403:
              return 'Access denied. You don\'t have permission to perform this action.';
            case 404:
              return 'The requested resource was not found.';
            case 429:
              return 'Too many requests. Please wait a moment and try again.';
            case 500:
              return 'Server error. Please try again later.';
            case 502:
              return 'Service temporarily unavailable. Please try again later.';
            case 503:
              return 'Service is currently under maintenance. Please try again later.';
            default:
              return 'Something went wrong. Please try again.';
          }
        case DioExceptionType.cancel:
          return 'Request was cancelled.';
        default:
          return 'An unexpected error occurred. Please try again.';
      }
    }
    
    return 'An unexpected error occurred. Please try again.';
  }
  
  /// Check if error is retryable
  static bool isRetryable(Object exception) {
    if (exception is TimeoutException ||
        exception is NetworkException ||
        exception is ServerException) {
      return true;
    }
    
    if (exception is DioException) {
      switch (exception.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.connectionError:
          return true;
        case DioExceptionType.badResponse:
          final statusCode = exception.response?.statusCode;
          return statusCode != null && statusCode >= 500;
        default:
          return false;
      }
    }
    
    return false;
  }
  
  /// Check if error requires authentication
  static bool requiresAuthentication(Object exception) {
    return exception is UnauthorizedException ||
        exception is AuthenticationException ||
        (exception is DioException && exception.response?.statusCode == 401);
  }
  
  /// Extract error code from exception
  static String? getErrorCode(Object exception) {
    if (exception is ApiException) {
      return exception.errorCode;
    } else if (exception is DioException) {
      return exception.response?.statusCode?.toString();
    }
    
    return null;
  }
  
  /// Extract additional error data from exception
  static Map<String, dynamic>? getErrorData(Object exception) {
    if (exception is ApiException) {
      return exception.errorData;
    } else if (exception is DioException) {
      return exception.response?.data;
    }
    
    return null;
  }
}