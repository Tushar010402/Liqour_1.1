class ApiResponse<T> {
  final bool success;
  final String? message;
  final T? data;
  final String? error;
  final int? statusCode;

  const ApiResponse({
    this.success = false,
    this.message,
    this.data,
    this.error,
    this.statusCode,
  });

  // Success response
  factory ApiResponse.success(T? data, {String? message}) {
    return ApiResponse<T>(
      success: true,
      data: data,
      message: message,
      statusCode: 200,
    );
  }

  // Error response
  factory ApiResponse.error(String error, {int? statusCode}) {
    return ApiResponse<T>(
      success: false,
      error: error,
      statusCode: statusCode ?? 500,
    );
  }

  // Loading state
  factory ApiResponse.loading() {
    return ApiResponse<T>(
      success: false,
    );
  }

  bool get isSuccess => success && error == null;
  bool get isError => !success || error != null;
  bool get hasData => data != null;
}

class PaginatedResponse<T> {
  final List<T> data;
  final int total;
  final int page;
  final int limit;
  final int totalPages;
  final bool hasNextPage;
  final bool hasPrevPage;

  const PaginatedResponse({
    required this.data,
    required this.total,
    required this.page,
    required this.limit,
    required this.totalPages,
    required this.hasNextPage,
    required this.hasPrevPage,
  });
}
