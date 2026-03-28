import 'package:intl/intl.dart';

import '../../../core/models/api_response.dart';
import '../../../core/services/dio_api_service.dart';
import '../models/dashboard_metrics.dart';
import '../models/dashboard_summary.dart';

/// Dashboard Service - API client for dashboard operations
class DashboardService {
  final DioApiService _apiService;

  DashboardService(this._apiService);

  /// Get dashboard summary (original endpoint for sales data)
  /// Optional shopId to filter by specific shop
  /// Optional dateFilter: today, yesterday, last_7_days, last_30_days, this_month
  Future<ApiResponse<DashboardSummary>> getDashboardSummary({
    String? shopId,
    String dateFilter = 'yesterday',
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final queryParams = <String, dynamic>{
      'date_filter': dateFilter,
    };
    if (dateFilter == 'custom' && startDate != null && endDate != null) {
      queryParams['start_date'] = DateFormat('yyyy-MM-dd').format(startDate);
      queryParams['end_date'] = DateFormat('yyyy-MM-dd').format(endDate);
    }
    if (shopId != null) {
      queryParams['shop_id'] = shopId;
    }

    final response = await _apiService.get<DashboardSummary>(
      '/api/sales/dashboard/summary',
      queryParams: queryParams,
      fromJson: (data) {
        return DashboardSummary.fromJson(data as Map<String, dynamic>);
      },
    );

    return response;
  }

  /// Get dashboard metrics for manager/admin summary view
  /// API: GET /api/sales/dashboard/summary
  ///
  /// [dateFilter] - One of: today, yesterday, last_7_days, last_30_days, this_month, custom
  /// [startDate] - Required when dateFilter is 'custom'
  /// [endDate] - Required when dateFilter is 'custom'
  /// [shopId] - Optional shop filter (null = all shops)
  Future<ApiResponse<DashboardMetrics>> getDashboardMetrics({
    String dateFilter = 'yesterday',
    DateTime? startDate,
    DateTime? endDate,
    String? shopId,
  }) async {
    final queryParams = <String, dynamic>{
      'date_filter': dateFilter,
    };

    if (dateFilter == 'custom' && startDate != null && endDate != null) {
      queryParams['start_date'] = DateFormat('yyyy-MM-dd').format(startDate);
      queryParams['end_date'] = DateFormat('yyyy-MM-dd').format(endDate);
    }

    if (shopId != null && shopId.isNotEmpty) {
      queryParams['shop_id'] = shopId;
    }

    final response = await _apiService.get<DashboardMetrics>(
      '/api/sales/dashboard/summary',
      queryParams: queryParams,
      fromJson: (data) {
        return DashboardMetrics.fromJson(data as Map<String, dynamic>);
      },
    );

    return response;
  }
}
