/// Custom exception for API errors with detailed error information
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final Map<String, dynamic>? fieldErrors;

  ApiException({
    required this.message,
    this.statusCode,
    this.fieldErrors,
  });

  /// Get user-friendly display message
  String get displayMessage {
    // If there are field-level errors, format them nicely
    if (fieldErrors != null && fieldErrors!.isNotEmpty) {
      final errors = fieldErrors!.entries
          .map((e) => '${_formatFieldName(e.key)}: ${e.value}')
          .join('\n');
      return errors;
    }

    // Return the main error message
    return _formatErrorMessage(message);
  }

  /// Get detailed error message for debugging
  String get detailedMessage {
    final buffer = StringBuffer();
    buffer.write(message);

    if (statusCode != null) {
      buffer.write(' (Status: $statusCode)');
    }

    if (fieldErrors != null && fieldErrors!.isNotEmpty) {
      buffer.write('\nField Errors: ');
      buffer.write(fieldErrors!.entries
          .map((e) => '${e.key}: ${e.value}')
          .join(', '));
    }

    return buffer.toString();
  }

  /// Format field name to be user-friendly
  String _formatFieldName(String fieldName) {
    // Convert snake_case to Title Case
    final words = fieldName.split('_');
    return words
        .map((word) => word.isEmpty
            ? ''
            : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}')
        .join(' ');
  }

  /// Format error message to be more user-friendly
  String _formatErrorMessage(String msg) {
    // Common error message mappings
    final errorMappings = {
      'username or email already exists': 'Username or email already exists. Please use a different phone number.',
      'phone number already registered': 'This phone number is already registered.',
      'shop not found or does not belong to your tenant': 'Selected shop is invalid or not accessible.',
      'shop_id is required for salesman role': 'Please select a shop for the salesman.',
      'invalid credentials': 'Invalid username or password.',
      'unauthorized': 'You are not authorized to perform this action.',
      'session expired': 'Your session has expired. Please login again.',
    };

    // Check for exact matches
    final lowerMsg = msg.toLowerCase();
    for (final entry in errorMappings.entries) {
      if (lowerMsg.contains(entry.key.toLowerCase())) {
        return entry.value;
      }
    }

    // Return original message if no mapping found
    return msg;
  }

  /// Check if error is a validation error
  bool get isValidationError =>
      statusCode == 400 && (fieldErrors != null && fieldErrors!.isNotEmpty);

  /// Check if error is an authentication error
  bool get isAuthError =>
      statusCode == 401 || statusCode == 403;

  /// Check if error is a not found error
  bool get isNotFoundError =>
      statusCode == 404;

  /// Check if error is a server error
  bool get isServerError =>
      statusCode != null && statusCode! >= 500;

  @override
  String toString() => displayMessage;

  /// Create ApiException from ApiResponse
  factory ApiException.fromResponse({
    required String message,
    int? statusCode,
    Map<String, dynamic>? errors,
  }) {
    return ApiException(
      message: message,
      statusCode: statusCode,
      fieldErrors: errors,
    );
  }

  /// Create ApiException for network errors
  factory ApiException.network(String message) {
    return ApiException(
      message: 'Network error: $message',
      statusCode: null,
      fieldErrors: null,
    );
  }

  /// Create ApiException for timeout errors
  factory ApiException.timeout() {
    return ApiException(
      message: 'Request timed out. Please check your internet connection and try again.',
      statusCode: 408,
      fieldErrors: null,
    );
  }

  /// Create ApiException for unknown errors
  factory ApiException.unknown() {
    return ApiException(
      message: 'An unexpected error occurred. Please try again.',
      statusCode: null,
      fieldErrors: null,
    );
  }
}
