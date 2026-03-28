/// Base App Exception
abstract class AppException implements Exception {
  final String message;
  final String? code;
  final dynamic originalError;
  final StackTrace? stackTrace;

  AppException({
    required this.message,
    this.code,
    this.originalError,
    this.stackTrace,
  });

  @override
  String toString() => message;

  /// Get user-friendly message
  String get userMessage => message;

  /// Get technical details for logging
  String get technicalDetails {
    final buffer = StringBuffer();
    buffer.writeln('Exception: $runtimeType');
    buffer.writeln('Message: $message');
    if (code != null) buffer.writeln('Code: $code');
    if (originalError != null) buffer.writeln('Original Error: $originalError');
    if (stackTrace != null) buffer.writeln('Stack Trace: $stackTrace');
    return buffer.toString();
  }
}

/// Network Exceptions
class NetworkException extends AppException {
  NetworkException({
    required super.message,
    super.code,
    super.originalError,
    super.stackTrace,
  });

  @override
  String get userMessage => 'Network error. Please check your connection and try again.';
}

class TimeoutException extends NetworkException {
  TimeoutException({
    super.message = 'Request timed out',
    super.code,
    super.originalError,
    super.stackTrace,
  });

  @override
  String get userMessage => 'Request timed out. Please try again.';
}

class NoInternetException extends NetworkException {
  NoInternetException({
    super.message = 'No internet connection',
    super.code,
    super.originalError,
    super.stackTrace,
  });

  @override
  String get userMessage => 'No internet connection. Please check your network settings.';
}

/// Authentication Exceptions
class AuthException extends AppException {
  AuthException({
    required super.message,
    super.code,
    super.originalError,
    super.stackTrace,
  });

  @override
  String get userMessage => 'Authentication failed. Please login again.';
}

class UnauthorizedException extends AuthException {
  UnauthorizedException({
    super.message = 'Unauthorized access',
    super.code = '401',
    super.originalError,
    super.stackTrace,
  });

  @override
  String get userMessage => 'Session expired. Please login again.';
}

class ForbiddenException extends AuthException {
  ForbiddenException({
    super.message = 'Access forbidden',
    super.code = '403',
    super.originalError,
    super.stackTrace,
  });

  @override
  String get userMessage => 'You don\'t have permission to perform this action.';
}

/// Validation Exceptions
class ValidationException extends AppException {
  final Map<String, String>? fieldErrors;

  ValidationException({
    required super.message,
    this.fieldErrors,
    super.code,
    super.originalError,
    super.stackTrace,
  });

  @override
  String get userMessage {
    if (fieldErrors != null && fieldErrors!.isNotEmpty) {
      return fieldErrors!.values.first;
    }
    return message;
  }
}

/// Server Exceptions
class ServerException extends AppException {
  final int? statusCode;

  ServerException({
    required super.message,
    this.statusCode,
    super.code,
    super.originalError,
    super.stackTrace,
  });

  @override
  String get userMessage {
    if (statusCode != null && statusCode! >= 500) {
      return 'Server error. Please try again later.';
    }
    return message;
  }
}

class BadRequestException extends ServerException {
  BadRequestException({
    super.message = 'Invalid request',
    super.statusCode = 400,
    super.code,
    super.originalError,
    super.stackTrace,
  });

  @override
  String get userMessage => message;
}

class NotFoundException extends ServerException {
  NotFoundException({
    super.message = 'Resource not found',
    super.statusCode = 404,
    super.code,
    super.originalError,
    super.stackTrace,
  });

  @override
  String get userMessage => 'The requested item was not found.';
}

/// Data Exceptions
class DataException extends AppException {
  DataException({
    required super.message,
    super.code,
    super.originalError,
    super.stackTrace,
  });

  @override
  String get userMessage => 'Data error. Please try again.';
}

class CacheException extends DataException {
  CacheException({
    super.message = 'Cache error',
    super.code,
    super.originalError,
    super.stackTrace,
  });

  @override
  String get userMessage => 'Failed to load cached data.';
}

class ParseException extends DataException {
  ParseException({
    super.message = 'Failed to parse data',
    super.code,
    super.originalError,
    super.stackTrace,
  });

  @override
  String get userMessage => 'Received invalid data from server.';
}

/// Business Logic Exceptions
class BusinessException extends AppException {
  BusinessException({
    required super.message,
    super.code,
    super.originalError,
    super.stackTrace,
  });

  @override
  String get userMessage => message;
}

class InsufficientStockException extends BusinessException {
  final int available;
  final int requested;

  InsufficientStockException({
    required this.available,
    required this.requested,
    super.message = 'Insufficient stock',
    super.code,
    super.originalError,
    super.stackTrace,
  });

  @override
  String get userMessage => 'Only $available items available. Cannot process $requested.';
}

class DuplicateException extends BusinessException {
  DuplicateException({
    super.message = 'Duplicate entry',
    super.code,
    super.originalError,
    super.stackTrace,
  });

  @override
  String get userMessage => 'This item already exists.';
}

/// File Exceptions
class FileException extends AppException {
  FileException({
    required super.message,
    super.code,
    super.originalError,
    super.stackTrace,
  });

  @override
  String get userMessage => 'File operation failed.';
}

class FileNotFoundAppException extends FileException {
  FileNotFoundAppException({
    super.message = 'File not found',
    super.code,
    super.originalError,
    super.stackTrace,
  });

  @override
  String get userMessage => 'The requested file was not found.';
}

class FileUploadException extends FileException {
  FileUploadException({
    super.message = 'File upload failed',
    super.code,
    super.originalError,
    super.stackTrace,
  });

  @override
  String get userMessage => 'Failed to upload file. Please try again.';
}

/// Unknown Exception
class UnknownException extends AppException {
  UnknownException({
    super.message = 'An unexpected error occurred',
    super.code,
    super.originalError,
    super.stackTrace,
  });

  @override
  String get userMessage => 'Something went wrong. Please try again.';
}
