import 'dart:io';
import 'package:dio/dio.dart';
import '../exceptions/app_exception.dart';
import '../utils/app_logger.dart';

/// Exception Handler
///
/// Converts raw exceptions into typed AppExceptions
/// and provides user-friendly error messages
class ExceptionHandler {
  /// Handle any exception and convert to AppException
  static AppException handle(dynamic error, [StackTrace? stackTrace]) {
    AppLogger.error('🔥 [ExceptionHandler] Handling error: ${error.runtimeType}');

    // Already an AppException
    if (error is AppException) {
      return error;
    }

    // Dio exceptions
    if (error is DioException) {
      return _handleDioException(error, stackTrace);
    }

    // Socket exceptions
    if (error is SocketException) {
      return NoInternetException(
        originalError: error,
        stackTrace: stackTrace,
      );
    }

    // Format exceptions (JSON parsing)
    if (error is FormatException) {
      return ParseException(
        message: error.message,
        originalError: error,
        stackTrace: stackTrace,
      );
    }

    // Timeout exceptions
    if (error is TimeoutException) {
      return TimeoutException(
        originalError: error,
        stackTrace: stackTrace,
      );
    }

    // File system exceptions
    if (error is FileSystemException) {
      return FileException(
        message: error.message,
        originalError: error,
        stackTrace: stackTrace,
      );
    }

    // Unknown exception
    return UnknownException(
      message: error.toString(),
      originalError: error,
      stackTrace: stackTrace,
    );
  }

  /// Handle Dio exceptions specifically
  static AppException _handleDioException(DioException error, StackTrace? stackTrace) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return TimeoutException(
          message: error.message ?? 'Request timed out',
          originalError: error,
          stackTrace: stackTrace,
        );

      case DioExceptionType.connectionError:
        return NoInternetException(
          message: error.message ?? 'Connection error',
          originalError: error,
          stackTrace: stackTrace,
        );

      case DioExceptionType.badResponse:
        return _handleBadResponse(error, stackTrace);

      case DioExceptionType.cancel:
        return NetworkException(
          message: 'Request was cancelled',
          originalError: error,
          stackTrace: stackTrace,
        );

      case DioExceptionType.badCertificate:
        return NetworkException(
          message: 'SSL certificate error',
          originalError: error,
          stackTrace: stackTrace,
        );

      case DioExceptionType.unknown:
      default:
        if (error.error is SocketException) {
          return NoInternetException(
            originalError: error,
            stackTrace: stackTrace,
          );
        }
        return NetworkException(
          message: error.message ?? 'Network error',
          originalError: error,
          stackTrace: stackTrace,
        );
    }
  }

  /// Handle bad response (4xx, 5xx status codes)
  static AppException _handleBadResponse(DioException error, StackTrace? stackTrace) {
    final statusCode = error.response?.statusCode;
    final data = error.response?.data;

    // Extract error message from response
    String message = 'Request failed';
    Map<String, String>? fieldErrors;

    if (data is Map) {
      message = data['message'] as String? ??
          data['error'] as String? ??
          data['detail'] as String? ??
          message;

      // Extract field-specific errors
      if (data['errors'] is Map) {
        fieldErrors = (data['errors'] as Map).map(
          (key, value) => MapEntry(
            key.toString(),
            value.toString(),
          ),
        );
      }
    }

    switch (statusCode) {
      case 400:
        if (fieldErrors != null && fieldErrors.isNotEmpty) {
          return ValidationException(
            message: message,
            fieldErrors: fieldErrors,
            code: '400',
            originalError: error,
            stackTrace: stackTrace,
          );
        }
        return BadRequestException(
          message: message,
          code: '400',
          originalError: error,
          stackTrace: stackTrace,
        );

      case 401:
        return UnauthorizedException(
          message: message,
          originalError: error,
          stackTrace: stackTrace,
        );

      case 403:
        return ForbiddenException(
          message: message,
          originalError: error,
          stackTrace: stackTrace,
        );

      case 404:
        return NotFoundException(
          message: message,
          originalError: error,
          stackTrace: stackTrace,
        );

      case 409:
        return DuplicateException(
          message: message,
          originalError: error,
          stackTrace: stackTrace,
        );

      case 422:
        return ValidationException(
          message: message,
          fieldErrors: fieldErrors,
          code: '422',
          originalError: error,
          stackTrace: stackTrace,
        );

      case 500:
      case 502:
      case 503:
      case 504:
        return ServerException(
          message: message,
          statusCode: statusCode,
          code: statusCode.toString(),
          originalError: error,
          stackTrace: stackTrace,
        );

      default:
        return ServerException(
          message: message,
          statusCode: statusCode,
          code: statusCode?.toString(),
          originalError: error,
          stackTrace: stackTrace,
        );
    }
  }

  /// Log exception with full details
  static void logException(AppException exception, {String? context}) {
    final buffer = StringBuffer();
    buffer.writeln('═══════════════════════════════════════════════');
    buffer.writeln('🔥 EXCEPTION CAUGHT');
    if (context != null) buffer.writeln('Context: $context');
    buffer.writeln(exception.technicalDetails);
    buffer.writeln('═══════════════════════════════════════════════');

    AppLogger.error(buffer.toString());
  }

  /// Get user-friendly error message from any error
  static String getUserMessage(dynamic error) {
    if (error is AppException) {
      return error.userMessage;
    }

    final appException = handle(error);
    return appException.userMessage;
  }

  /// Check if error is recoverable (should retry)
  static bool isRecoverable(dynamic error) {
    if (error is NoInternetException ||
        error is TimeoutException ||
        error is NetworkException) {
      return true;
    }

    if (error is ServerException) {
      final statusCode = error.statusCode;
      if (statusCode != null && statusCode >= 500) {
        return true; // Server errors are often temporary
      }
    }

    return false;
  }

  /// Check if error requires user authentication
  static bool requiresAuthentication(dynamic error) {
    return error is UnauthorizedException || error is AuthException;
  }

  /// Check if error is a validation error
  static bool isValidationError(dynamic error) {
    return error is ValidationException;
  }

  /// Get field errors from validation exception
  static Map<String, String>? getFieldErrors(dynamic error) {
    if (error is ValidationException) {
      return error.fieldErrors;
    }
    return null;
  }
}
