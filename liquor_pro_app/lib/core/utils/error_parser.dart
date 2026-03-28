import 'dart:convert';

/// Error Parser - Converts backend errors into user-friendly messages
///
/// This utility parses technical error messages from the backend
/// and transforms them into actionable, user-friendly text that helps
/// users understand what went wrong and what they can do about it.
class ErrorParser {
  // Private constructor to prevent instantiation
  ErrorParser._();

  /// Parse any error into a user-friendly ErrorInfo object
  static ErrorInfo parse(dynamic error) {
    final errorString = error.toString();

    // Remove "Exception: " prefix if present
    String cleanError = errorString.replaceFirst('Exception: ', '');
    cleanError = cleanError.replaceFirst('Failed to create cash request: ', '');

    // Check for specific error types
    if (_isInsufficientBalanceError(cleanError)) {
      return _parseInsufficientBalance(cleanError);
    } else if (_isNetworkError(cleanError)) {
      return _parseNetworkError(cleanError);
    } else if (_isValidationError(cleanError)) {
      return _parseValidationError(cleanError);
    } else if (_isUnauthorizedError(cleanError)) {
      return _parseUnauthorizedError(cleanError);
    } else if (_isServerError(cleanError)) {
      return _parseServerError(cleanError);
    }

    // Default fallback for unknown errors
    return ErrorInfo(
      title: 'Oops! Something went wrong',
      message: _sanitizeErrorMessage(cleanError),
      icon: ErrorIcon.error,
      actionText: 'Try Again',
      technicalDetails: errorString,
    );
  }

  /// Check if error is an insufficient balance error
  static bool _isInsufficientBalanceError(String error) {
    return error.toLowerCase().contains('insufficient balance') ||
        error.toLowerCase().contains('not enough balance') ||
        error.toLowerCase().contains('has 0.00');
  }

  /// Check if error is a network error
  static bool _isNetworkError(String error) {
    return error.toLowerCase().contains('network') ||
        error.toLowerCase().contains('connection') ||
        error.toLowerCase().contains('timeout') ||
        error.toLowerCase().contains('no internet');
  }

  /// Check if error is a validation error
  static bool _isValidationError(String error) {
    return error.toLowerCase().contains('validation') ||
        error.toLowerCase().contains('invalid') ||
        error.toLowerCase().contains('required field') ||
        error.toLowerCase().contains('must be');
  }

  /// Check if error is an unauthorized error
  static bool _isUnauthorizedError(String error) {
    return error.toLowerCase().contains('unauthorized') ||
        error.toLowerCase().contains('not authorized') ||
        error.toLowerCase().contains('permission denied') ||
        error.toLowerCase().contains('401');
  }

  /// Check if error is a server error
  static bool _isServerError(String error) {
    return error.toLowerCase().contains('500') ||
        error.toLowerCase().contains('server error') ||
        error.toLowerCase().contains('internal server');
  }

  /// Parse insufficient balance error
  static ErrorInfo _parseInsufficientBalance(String error) {
    // Try to extract amounts from error message
    // Example: "insufficient balance: (salesman) has 0.00, request is for 1000.00"
    double? requestedAmount;
    double? availableAmount;
    String? role;

    // Extract requested amount
    final requestPattern = RegExp(r'request is for ([\d.]+)');
    final requestMatch = requestPattern.firstMatch(error);
    if (requestMatch != null) {
      requestedAmount = double.tryParse(requestMatch.group(1) ?? '');
    }

    // Extract available amount
    final availablePattern = RegExp(r'has ([\d.]+)');
    final availableMatch = availablePattern.firstMatch(error);
    if (availableMatch != null) {
      availableAmount = double.tryParse(availableMatch.group(1) ?? '');
    }

    // Extract role if present
    final rolePattern = RegExp(r'\((\w+)\)');
    final roleMatch = rolePattern.firstMatch(error);
    if (roleMatch != null) {
      role = roleMatch.group(1);
    }

    String message = 'You don\'t have enough cash to complete this request.';

    if (requestedAmount != null && availableAmount != null) {
      message = 'You\'re requesting ₹${_formatCurrency(requestedAmount)} '
          'but only have ₹${_formatCurrency(availableAmount)} available.';
    } else if (availableAmount != null && availableAmount == 0) {
      message = 'You currently have no cash available.';
    }

    return ErrorInfo(
      title: '💰 Insufficient Balance',
      message: message,
      suggestion: requestedAmount != null && requestedAmount > 0
          ? '💡 Try requesting less than ₹${_formatCurrency(availableAmount ?? 0)} or contact your manager to request cash.'
          : '💡 Contact your manager to request cash before trying again.',
      icon: ErrorIcon.balance,
      actionText: 'Got It',
      technicalDetails: error,
      data: {
        'requested': requestedAmount,
        'available': availableAmount,
        'role': role,
      },
    );
  }

  /// Parse network error
  static ErrorInfo _parseNetworkError(String error) {
    return ErrorInfo(
      title: '📡 Network Error',
      message: 'Unable to connect to the server. Please check your internet connection.',
      suggestion: '💡 Make sure you\'re connected to Wi-Fi or mobile data and try again.',
      icon: ErrorIcon.network,
      actionText: 'Retry',
      technicalDetails: error,
    );
  }

  /// Parse validation error
  static ErrorInfo _parseValidationError(String error) {
    return ErrorInfo(
      title: '⚠️ Validation Error',
      message: _sanitizeErrorMessage(error),
      suggestion: '💡 Please check all required fields and try again.',
      icon: ErrorIcon.validation,
      actionText: 'Fix and Retry',
      technicalDetails: error,
    );
  }

  /// Parse unauthorized error
  static ErrorInfo _parseUnauthorizedError(String error) {
    return ErrorInfo(
      title: '🔒 Access Denied',
      message: 'You don\'t have permission to perform this action.',
      suggestion: '💡 Please contact your administrator if you believe this is a mistake.',
      icon: ErrorIcon.unauthorized,
      actionText: 'Go Back',
      technicalDetails: error,
    );
  }

  /// Parse server error
  static ErrorInfo _parseServerError(String error) {
    return ErrorInfo(
      title: '🛠️ Server Error',
      message: 'Our servers are experiencing issues. This has been logged and we\'re working on it.',
      suggestion: '💡 Please try again in a few minutes.',
      icon: ErrorIcon.server,
      actionText: 'Try Again Later',
      technicalDetails: error,
    );
  }

  /// Sanitize error message by removing technical jargon
  static String _sanitizeErrorMessage(String error) {
    String sanitized = error;

    // Remove Go formatting artifacts
    sanitized = sanitized.replaceAll(RegExp(r'%!s\(func\(\) string=0x[a-f0-9]+\)'), '');

    // Remove common prefixes
    sanitized = sanitized.replaceFirst('Exception: ', '');
    sanitized = sanitized.replaceFirst('Error: ', '');

    // Clean up extra whitespace
    sanitized = sanitized.trim();
    sanitized = sanitized.replaceAll(RegExp(r'\s+'), ' ');

    // Capitalize first letter
    if (sanitized.isNotEmpty) {
      sanitized = sanitized[0].toUpperCase() + sanitized.substring(1);
    }

    return sanitized;
  }

  /// Format currency for display
  static String _formatCurrency(double amount) {
    return amount.toStringAsFixed(2);
  }

  /// Extract JSON error if present
  static Map<String, dynamic>? tryParseJson(String error) {
    try {
      return jsonDecode(error) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }
}

/// Error information class containing all parsed error details
class ErrorInfo {
  final String title;
  final String message;
  final String? suggestion;
  final ErrorIcon icon;
  final String actionText;
  final String? technicalDetails;
  final Map<String, dynamic>? data;

  ErrorInfo({
    required this.title,
    required this.message,
    this.suggestion,
    required this.icon,
    required this.actionText,
    this.technicalDetails,
    this.data,
  });

  /// Get user-friendly error text for display
  String get userMessage {
    if (suggestion != null) {
      return '$message\n\n$suggestion';
    }
    return message;
  }

  /// Check if this is a balance-related error
  bool get isBalanceError => icon == ErrorIcon.balance;

  /// Check if this is a network error
  bool get isNetworkError => icon == ErrorIcon.network;

  /// Get available balance if present
  double? get availableBalance => data?['available'] as double?;

  /// Get requested amount if present
  double? get requestedAmount => data?['requested'] as double?;
}

/// Error icon types for different error categories
enum ErrorIcon {
  error,
  balance,
  network,
  validation,
  unauthorized,
  server,
}
