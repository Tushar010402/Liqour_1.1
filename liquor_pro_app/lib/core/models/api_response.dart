/// Generic API Response wrapper
class ApiResponse<T> {
  final bool success;
  final String? message;
  final T? data;
  final Map<String, dynamic>? errors;
  final int? statusCode;

  ApiResponse({
    required this.success,
    this.message,
    this.data,
    this.errors,
    this.statusCode,
  });

  // Factory constructors for easy creation
  factory ApiResponse.success(T data, {String? message}) {
    return ApiResponse<T>(
      success: true,
      data: data,
      message: message,
      statusCode: 200,
    );
  }

  factory ApiResponse.error({required String error, int? statusCode}) {
    return ApiResponse<T>(
      success: false,
      message: error,
      statusCode: statusCode ?? 400,
    );
  }

  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic)? fromJsonT,
  ) {
    return ApiResponse<T>(
      success: json['success'] ?? false,
      message: json['message'] as String?,
      data: json['data'] != null && fromJsonT != null
          ? fromJsonT(json['data'])
          : json['data'] as T?,
      errors: json['errors'] as Map<String, dynamic>?,
      statusCode: json['statusCode'] as int?,
    );
  }

  Map<String, dynamic> toJson(Object? Function(T?)? toJsonT) {
    return {
      'success': success,
      'message': message,
      'data': toJsonT != null ? toJsonT(data) : data,
      'errors': errors,
      'statusCode': statusCode,
    };
  }

  bool get isSuccess => success && statusCode != null && statusCode! >= 200 && statusCode! < 300;
  bool get isError => !success || (statusCode != null && statusCode! >= 400);
  String? get error => message;
}

/// Paginated Response
class PaginatedResponse<T> {
  final List<T> data;
  final int total;
  final int page;
  final int pageSize;
  final int totalPages;

  PaginatedResponse({
    required this.data,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.totalPages,
  });

  factory PaginatedResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fromJsonT,
  ) {
    final dataList = json['data'] as List<dynamic>? ?? [];
    return PaginatedResponse<T>(
      data: dataList.map((item) => fromJsonT(item as Map<String, dynamic>)).toList(),
      total: json['total'] as int? ?? 0,
      page: json['page'] as int? ?? 1,
      pageSize: json['pageSize'] as int? ?? 10,
      totalPages: json['totalPages'] as int? ?? 1,
    );
  }

  bool get hasMore => page < totalPages;
}

/// API Error
class ApiError {
  final String message;
  final int? statusCode;
  final Map<String, dynamic>? details;

  ApiError({
    required this.message,
    this.statusCode,
    this.details,
  });

  factory ApiError.fromJson(Map<String, dynamic> json) {
    return ApiError(
      message: json['message'] as String? ?? 'An error occurred',
      statusCode: json['statusCode'] as int?,
      details: json['errors'] as Map<String, dynamic>?,
    );
  }

  @override
  String toString() => message;
}
