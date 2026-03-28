import '../../../core/models/api_response.dart';
import '../../../core/services/dio_api_service.dart';

/// Service for saving day-closing reconciliation data
/// (cash denominations, UPI breakdowns, expenses)
class DayClosingService {
  final DioApiService _apiService;

  DayClosingService(this._apiService);

  /// Fetch existing day-closing record for a given date
  /// GET /api/sales/day-closing?shop_id=...&date=...
  Future<ApiResponse<Map<String, dynamic>>> getDayClosing({
    required String shopId,
    required String date,
  }) async {
    return _apiService.get<Map<String, dynamic>>(
      '/api/sales/day-closing',
      queryParams: {'shop_id': shopId, 'date': date},
      fromJson: (data) => data as Map<String, dynamic>,
    );
  }

  /// Save day-closing reconciliation entry
  /// POST /api/sales/day-closing
  Future<ApiResponse<Map<String, dynamic>>> saveDayClosing({
    required String shopId,
    required String date,
    Map<int, int>? cashDenominations,
    double? cashTotal,
    Map<String, double>? upiBreakdown,
    double? upiTotal,
    Map<String, double>? expenses,
    double? expenseTotal,
  }) async {
    final body = <String, dynamic>{
      'shop_id': shopId,
      'date': date,
    };

    if (cashDenominations != null) {
      body['cash_denominations'] = cashDenominations.map((k, v) => MapEntry(k.toString(), v));
      body['cash_total'] = cashTotal ?? 0;
    }

    if (upiBreakdown != null) {
      body['upi_breakdown'] = upiBreakdown;
      body['upi_total'] = upiTotal ?? 0;
    }

    if (expenses != null) {
      body['expenses'] = expenses;
      body['expense_total'] = expenseTotal ?? 0;
    }

    return _apiService.post<Map<String, dynamic>>(
      '/api/sales/day-closing',
      body: body,
      fromJson: (data) => data as Map<String, dynamic>,
    );
  }
}
