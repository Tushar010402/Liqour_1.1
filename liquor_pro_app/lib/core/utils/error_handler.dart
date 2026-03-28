import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'app_logger.dart';
import 'snackbar_helper.dart';

/// Centralized Error Handler for Modern UX
/// Provides user-friendly error messages, automatic retry, and proper logging
class ErrorHandler {
  /// Handle API errors with user-friendly messages and optional retry
  static Future<T?> handleApiError<T>({
    required BuildContext context,
    required Exception error,
    String? customMessage,
    Future<T> Function()? retryCallback,
    bool showSnackbar = true,
  }) async {
    final errorInfo = _parseError(error);
    final userMessage = customMessage ?? errorInfo.userMessage;

    AppLogger.error('ErrorHandler: ${errorInfo.technicalMessage}');

    if (showSnackbar && context.mounted) {
      if (errorInfo.isRetryable && retryCallback != null) {
        // Show error with retry option
        _showErrorWithRetry(
          context,
          userMessage,
          retryCallback,
        );
      } else {
        // Show simple error message
        SnackbarHelper.showError(context, userMessage);
      }
    }

    return null;
  }

  /// Parse error into user-friendly and technical messages
  static ErrorInfo _parseError(Exception error) {
    if (error is DioException) {
      return _parseDioError(error);
    }

    // Generic error
    return ErrorInfo(
      userMessage: 'Something went wrong. Please try again.',
      technicalMessage: error.toString(),
      isRetryable: true,
    );
  }

  /// Parse Dio errors specifically
  static ErrorInfo _parseDioError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ErrorInfo(
          userMessage: 'Connection timed out. Please check your internet and try again.',
          technicalMessage: 'Timeout: ${error.message}',
          isRetryable: true,
        );

      case DioExceptionType.badResponse:
        final statusCode = error.response?.statusCode;
        return _parseHttpError(statusCode, error);

      case DioExceptionType.connectionError:
        return ErrorInfo(
          userMessage: 'No internet connection. Please check your network.',
          technicalMessage: 'Connection error: ${error.message}',
          isRetryable: true,
        );

      case DioExceptionType.cancel:
        return ErrorInfo(
          userMessage: 'Request was cancelled',
          technicalMessage: 'Request cancelled',
          isRetryable: false,
        );

      default:
        return ErrorInfo(
          userMessage: 'Network error occurred. Please try again.',
          technicalMessage: 'Dio error: ${error.message}',
          isRetryable: true,
        );
    }
  }

  /// Parse HTTP status code errors
  static ErrorInfo _parseHttpError(int? statusCode, DioException error) {
    // Try to extract error message from response
    String? serverMessage;
    try {
      final data = error.response?.data;
      if (data is Map) {
        serverMessage = data['message'] ?? data['error'];
      }
    } catch (_) {}

    switch (statusCode) {
      case 400:
        return ErrorInfo(
          userMessage: serverMessage ?? 'Invalid request. Please check your input.',
          technicalMessage: 'Bad Request (400): ${error.message}',
          isRetryable: false,
        );

      case 401:
        return ErrorInfo(
          userMessage: 'Session expired. Please log in again.',
          technicalMessage: 'Unauthorized (401): ${error.message}',
          isRetryable: false,
        );

      case 403:
        return ErrorInfo(
          userMessage: 'You don\'t have permission to perform this action.',
          technicalMessage: 'Forbidden (403): ${error.message}',
          isRetryable: false,
        );

      case 404:
        return ErrorInfo(
          userMessage: serverMessage ?? 'Resource not found.',
          technicalMessage: 'Not Found (404): ${error.message}',
          isRetryable: false,
        );

      case 409:
        return ErrorInfo(
          userMessage: serverMessage ?? 'This action conflicts with existing data.',
          technicalMessage: 'Conflict (409): ${error.message}',
          isRetryable: false,
        );

      case 422:
        return ErrorInfo(
          userMessage: serverMessage ?? 'Validation failed. Please check your input.',
          technicalMessage: 'Unprocessable Entity (422): ${error.message}',
          isRetryable: false,
        );

      case 429:
        return ErrorInfo(
          userMessage: 'Too many requests. Please wait a moment and try again.',
          technicalMessage: 'Rate Limited (429): ${error.message}',
          isRetryable: true,
        );

      case 500:
      case 502:
      case 503:
      case 504:
        return ErrorInfo(
          userMessage: 'Server error. Please try again in a moment.',
          technicalMessage: 'Server Error ($statusCode): ${error.message}',
          isRetryable: true,
        );

      default:
        return ErrorInfo(
          userMessage: serverMessage ?? 'Something went wrong. Please try again.',
          technicalMessage: 'HTTP Error ($statusCode): ${error.message}',
          isRetryable: true,
        );
    }
  }

  /// Show error message with retry button
  static void _showErrorWithRetry<T>(
    BuildContext context,
    String message,
    Future<T> Function() retryCallback,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'RETRY',
          textColor: Colors.white,
          onPressed: () async {
            try {
              await retryCallback();
              if (context.mounted) {
                SnackbarHelper.showSuccess(context, 'Operation completed successfully');
              }
            } catch (e) {
              if (context.mounted) {
                handleApiError(
                  context: context,
                  error: e as Exception,
                  retryCallback: retryCallback,
                );
              }
            }
          },
        ),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  /// Retry logic with exponential backoff
  static Future<T> retryWithBackoff<T>({
    required Future<T> Function() operation,
    int maxAttempts = 3,
    Duration initialDelay = const Duration(seconds: 1),
  }) async {
    int attempt = 0;
    Duration delay = initialDelay;

    while (true) {
      try {
        return await operation();
      } catch (e) {
        attempt++;

        if (attempt >= maxAttempts) {
          rethrow;
        }

        // Exponential backoff: 1s, 2s, 4s
        AppLogger.info('Retry attempt $attempt/$maxAttempts after ${delay.inSeconds}s delay');
        await Future.delayed(delay);
        delay *= 2;
      }
    }
  }

  /// Handle errors with dialog (for critical errors)
  static Future<void> showErrorDialog(
    BuildContext context, {
    required String title,
    required String message,
    String? buttonText,
    VoidCallback? onDismiss,
  }) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade600),
            const SizedBox(width: 12),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              onDismiss?.call();
            },
            child: Text(buttonText ?? 'OK'),
          ),
        ],
      ),
    );
  }
}

/// Error information model
class ErrorInfo {
  final String userMessage;
  final String technicalMessage;
  final bool isRetryable;

  ErrorInfo({
    required this.userMessage,
    required this.technicalMessage,
    required this.isRetryable,
  });
}
