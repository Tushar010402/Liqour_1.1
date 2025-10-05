import '../../../core/models/api_response.dart';
import '../../../core/services/api_service.dart';
import '../models/dashboard_summary.dart';
import '../../../core/utils/logger.dart';

/// Dashboard Service - API client for dashboard operations
class DashboardService {
  final ApiService _apiService;

  DashboardService(this._apiService);

  /// Get dashboard summary
  /// Optional shopId to filter by specific shop
  Future<ApiResponse<DashboardSummary>> getDashboardSummary({
    String? shopId,
  }) async {
    Logger.debug('📊 DashboardService.getDashboardSummary() called');

    // Build query parameters
    final Map<String, dynamic>? queryParams =
        shopId != null ? {'shop_id': shopId} : null;

    final response = await _apiService.get<DashboardSummary>(
      '/api/sales/dashboard/summary',
      queryParams: queryParams,
      fromJson: (data) {
        Logger.debug('📊 Parsing dashboard response: ${data.runtimeType}');
        return DashboardSummary.fromJson(data as Map<String, dynamic>);
      },
    );

    Logger.debug(
        '📊 DashboardService: Response received - success: ${response.success}');
    return response;
  }
}
