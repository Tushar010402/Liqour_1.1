import 'package:flutter/foundation.dart';
import '../../../core/services/dio_api_service.dart';
import '../../../core/models/api_response.dart';
import '../models/finance_matrix_models.dart';

/// Finance Matrix Service - AI-Powered Unified Financial Dashboard
/// Fetches combined Sales + Cash + Inventory + Expenses data
class FinanceMatrixService {
  final DioApiService _apiService;

  FinanceMatrixService(this._apiService);

  // =========================================================================
  // MAIN DASHBOARD
  // =========================================================================

  /// Get complete finance matrix dashboard
  Future<ApiResponse<FinanceMatrixDashboard>> getDashboard(MatrixQuery query) async {
    try {
      if (kDebugMode) {
        debugPrint('📊 FinanceMatrixService: Fetching dashboard');
        debugPrint('   - Period: ${query.period.displayName}');
        debugPrint('   - Shop: ${query.shopId ?? "all"}');
      }

      final response = await _apiService.get(
        '/api/finance/matrix',
        queryParams: query.toQueryParams(),
      );

      if (response.success && response.data != null) {
        final dashboard = FinanceMatrixDashboard.fromJson(
          response.data as Map<String, dynamic>,
        );
        if (kDebugMode) {
          debugPrint('✅ FinanceMatrixService: Dashboard loaded');
          debugPrint('   - Health Score: ${dashboard.healthScore.toStringAsFixed(1)}');
          debugPrint('   - Insights: ${dashboard.insights.length}');
        }
        return ApiResponse<FinanceMatrixDashboard>(
          success: true,
          data: dashboard,
        );
      }

      return ApiResponse<FinanceMatrixDashboard>(
        success: false,
        message: response.message ?? 'Failed to fetch dashboard',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ FinanceMatrixService: Error fetching dashboard - $e');
      return ApiResponse<FinanceMatrixDashboard>(
        success: false,
        message: 'Error fetching finance matrix: $e',
      );
    }
  }

  // =========================================================================
  // INDIVIDUAL SUMMARIES
  // =========================================================================

  /// Get sales summary only
  Future<ApiResponse<SalesSummary>> getSalesSummary(MatrixQuery query) async {
    try {
      if (kDebugMode) debugPrint('📊 FinanceMatrixService: Fetching sales summary');

      final response = await _apiService.get(
        '/api/finance/matrix/sales',
        queryParams: query.toQueryParams(),
      );

      if (response.success && response.data != null) {
        final summary = SalesSummary.fromJson(
          response.data as Map<String, dynamic>,
        );
        if (kDebugMode) {
          debugPrint('✅ FinanceMatrixService: Sales = ₹${summary.totalAmount}');
        }
        return ApiResponse<SalesSummary>(
          success: true,
          data: summary,
        );
      }

      return ApiResponse<SalesSummary>(
        success: false,
        message: response.message ?? 'Failed to fetch sales summary',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ FinanceMatrixService: Error - $e');
      return ApiResponse<SalesSummary>(
        success: false,
        message: 'Error fetching sales summary: $e',
      );
    }
  }

  /// Get cash summary only
  Future<ApiResponse<CashSummary>> getCashSummary(MatrixQuery query) async {
    try {
      if (kDebugMode) debugPrint('📊 FinanceMatrixService: Fetching cash summary');

      final response = await _apiService.get(
        '/api/finance/matrix/cash',
        queryParams: query.toQueryParams(),
      );

      if (response.success && response.data != null) {
        final summary = CashSummary.fromJson(
          response.data as Map<String, dynamic>,
        );
        if (kDebugMode) {
          debugPrint('✅ FinanceMatrixService: Cash = ₹${summary.actualBalance}');
        }
        return ApiResponse<CashSummary>(
          success: true,
          data: summary,
        );
      }

      return ApiResponse<CashSummary>(
        success: false,
        message: response.message ?? 'Failed to fetch cash summary',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ FinanceMatrixService: Error - $e');
      return ApiResponse<CashSummary>(
        success: false,
        message: 'Error fetching cash summary: $e',
      );
    }
  }

  /// Get inventory summary only
  Future<ApiResponse<InventorySummary>> getInventorySummary(MatrixQuery query) async {
    try {
      if (kDebugMode) debugPrint('📊 FinanceMatrixService: Fetching inventory summary');

      final response = await _apiService.get(
        '/api/finance/matrix/inventory',
        queryParams: query.toQueryParams(),
      );

      if (response.success && response.data != null) {
        final summary = InventorySummary.fromJson(
          response.data as Map<String, dynamic>,
        );
        if (kDebugMode) {
          debugPrint('✅ FinanceMatrixService: Items = ${summary.totalItems}');
        }
        return ApiResponse<InventorySummary>(
          success: true,
          data: summary,
        );
      }

      return ApiResponse<InventorySummary>(
        success: false,
        message: response.message ?? 'Failed to fetch inventory summary',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ FinanceMatrixService: Error - $e');
      return ApiResponse<InventorySummary>(
        success: false,
        message: 'Error fetching inventory summary: $e',
      );
    }
  }

  /// Get expenses summary only
  Future<ApiResponse<ExpensesSummary>> getExpensesSummary(MatrixQuery query) async {
    try {
      if (kDebugMode) debugPrint('📊 FinanceMatrixService: Fetching expenses summary');

      final response = await _apiService.get(
        '/api/finance/matrix/expenses',
        queryParams: query.toQueryParams(),
      );

      if (response.success && response.data != null) {
        final summary = ExpensesSummary.fromJson(
          response.data as Map<String, dynamic>,
        );
        if (kDebugMode) {
          debugPrint('✅ FinanceMatrixService: Expenses = ₹${summary.totalSpent}');
        }
        return ApiResponse<ExpensesSummary>(
          success: true,
          data: summary,
        );
      }

      return ApiResponse<ExpensesSummary>(
        success: false,
        message: response.message ?? 'Failed to fetch expenses summary',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ FinanceMatrixService: Error - $e');
      return ApiResponse<ExpensesSummary>(
        success: false,
        message: 'Error fetching expenses summary: $e',
      );
    }
  }

  // =========================================================================
  // INSIGHTS
  // =========================================================================

  /// Get AI-generated insights
  Future<ApiResponse<List<MatrixInsight>>> getInsights(MatrixQuery query) async {
    try {
      if (kDebugMode) debugPrint('📊 FinanceMatrixService: Fetching insights');

      final response = await _apiService.get(
        '/api/finance/matrix/insights',
        queryParams: query.toQueryParams(),
      );

      if (response.success && response.data != null) {
        final insightsData = response.data as List;
        final insights = insightsData
            .map((e) => MatrixInsight.fromJson(e as Map<String, dynamic>))
            .toList();
        if (kDebugMode) {
          debugPrint('✅ FinanceMatrixService: ${insights.length} insights');
        }
        return ApiResponse<List<MatrixInsight>>(
          success: true,
          data: insights,
        );
      }

      return ApiResponse<List<MatrixInsight>>(
        success: false,
        message: response.message ?? 'Failed to fetch insights',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ FinanceMatrixService: Error - $e');
      return ApiResponse<List<MatrixInsight>>(
        success: false,
        message: 'Error fetching insights: $e',
      );
    }
  }

  /// Dismiss an insight
  Future<ApiResponse<void>> dismissInsight(String insightId) async {
    try {
      if (kDebugMode) debugPrint('📊 FinanceMatrixService: Dismissing insight');

      final response = await _apiService.post(
        '/api/finance/matrix/insights/$insightId/dismiss',
        body: {},
      );

      if (response.success) {
        if (kDebugMode) debugPrint('✅ FinanceMatrixService: Insight dismissed');
        return ApiResponse<void>(success: true);
      }

      return ApiResponse<void>(
        success: false,
        message: response.message ?? 'Failed to dismiss insight',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ FinanceMatrixService: Error - $e');
      return ApiResponse<void>(
        success: false,
        message: 'Error dismissing insight: $e',
      );
    }
  }

  // =========================================================================
  // TRENDS
  // =========================================================================

  /// Get sales trend data
  Future<ApiResponse<TrendData>> getSalesTrend({
    required String trendPeriod, // 'daily', 'weekly', 'monthly'
    String? shopId,
    int days = 30,
  }) async {
    try {
      if (kDebugMode) debugPrint('📊 FinanceMatrixService: Fetching sales trend');

      final response = await _apiService.get(
        '/api/finance/matrix/trends/sales',
        queryParams: {
          'trend_period': trendPeriod,
          'days': days.toString(),
          if (shopId != null) 'shop_id': shopId,
        },
      );

      if (response.success && response.data != null) {
        final trend = TrendData.fromJson(
          response.data as Map<String, dynamic>,
        );
        if (kDebugMode) {
          debugPrint('✅ FinanceMatrixService: ${trend.points.length} trend points');
        }
        return ApiResponse<TrendData>(
          success: true,
          data: trend,
        );
      }

      return ApiResponse<TrendData>(
        success: false,
        message: response.message ?? 'Failed to fetch trend',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ FinanceMatrixService: Error - $e');
      return ApiResponse<TrendData>(
        success: false,
        message: 'Error fetching trend: $e',
      );
    }
  }

  /// Get cash flow trend
  Future<ApiResponse<TrendData>> getCashFlowTrend({
    required String trendPeriod,
    String? shopId,
    int days = 30,
  }) async {
    try {
      if (kDebugMode) debugPrint('📊 FinanceMatrixService: Fetching cash flow trend');

      final response = await _apiService.get(
        '/api/finance/matrix/trends/cash',
        queryParams: {
          'trend_period': trendPeriod,
          'days': days.toString(),
          if (shopId != null) 'shop_id': shopId,
        },
      );

      if (response.success && response.data != null) {
        final trend = TrendData.fromJson(
          response.data as Map<String, dynamic>,
        );
        return ApiResponse<TrendData>(
          success: true,
          data: trend,
        );
      }

      return ApiResponse<TrendData>(
        success: false,
        message: response.message ?? 'Failed to fetch trend',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ FinanceMatrixService: Error - $e');
      return ApiResponse<TrendData>(
        success: false,
        message: 'Error fetching trend: $e',
      );
    }
  }

  // =========================================================================
  // COMPARISONS
  // =========================================================================

  /// Compare two periods
  Future<ApiResponse<Map<String, dynamic>>> comparePeriods({
    required MatrixPeriod period1,
    required MatrixPeriod period2,
    String? shopId,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('📊 FinanceMatrixService: Comparing periods');
        debugPrint('   - ${period1.displayName} vs ${period2.displayName}');
      }

      final response = await _apiService.get(
        '/api/finance/matrix/compare',
        queryParams: {
          'period1': period1.apiValue,
          'period2': period2.apiValue,
          if (shopId != null) 'shop_id': shopId,
        },
      );

      if (response.success && response.data != null) {
        if (kDebugMode) debugPrint('✅ FinanceMatrixService: Comparison loaded');
        return ApiResponse<Map<String, dynamic>>(
          success: true,
          data: response.data as Map<String, dynamic>,
        );
      }

      return ApiResponse<Map<String, dynamic>>(
        success: false,
        message: response.message ?? 'Failed to compare periods',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ FinanceMatrixService: Error - $e');
      return ApiResponse<Map<String, dynamic>>(
        success: false,
        message: 'Error comparing periods: $e',
      );
    }
  }

  // =========================================================================
  // EXPORT
  // =========================================================================

  /// Export matrix report
  Future<ApiResponse<String>> exportReport({
    required MatrixQuery query,
    required String format, // 'pdf', 'excel', 'csv'
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('📊 FinanceMatrixService: Exporting report as $format');
      }

      final params = query.toQueryParams();
      params['format'] = format;

      final response = await _apiService.get(
        '/api/finance/matrix/export',
        queryParams: params,
      );

      if (response.success && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        final downloadUrl = data['download_url'] as String?;
        if (downloadUrl != null) {
          if (kDebugMode) debugPrint('✅ FinanceMatrixService: Export ready');
          return ApiResponse<String>(
            success: true,
            data: downloadUrl,
          );
        }
      }

      return ApiResponse<String>(
        success: false,
        message: response.message ?? 'Failed to export report',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ FinanceMatrixService: Error - $e');
      return ApiResponse<String>(
        success: false,
        message: 'Error exporting report: $e',
      );
    }
  }

  // =========================================================================
  // SETTINGS
  // =========================================================================

  /// Get matrix settings (targets, budgets)
  Future<ApiResponse<Map<String, dynamic>>> getSettings() async {
    try {
      if (kDebugMode) debugPrint('📊 FinanceMatrixService: Fetching settings');

      final response = await _apiService.get('/api/finance/matrix/settings');

      if (response.success && response.data != null) {
        if (kDebugMode) debugPrint('✅ FinanceMatrixService: Settings loaded');
        return ApiResponse<Map<String, dynamic>>(
          success: true,
          data: response.data as Map<String, dynamic>,
        );
      }

      return ApiResponse<Map<String, dynamic>>(
        success: false,
        message: response.message ?? 'Failed to fetch settings',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ FinanceMatrixService: Error - $e');
      return ApiResponse<Map<String, dynamic>>(
        success: false,
        message: 'Error fetching settings: $e',
      );
    }
  }

  /// Update matrix settings
  Future<ApiResponse<void>> updateSettings(Map<String, dynamic> settings) async {
    try {
      if (kDebugMode) debugPrint('📊 FinanceMatrixService: Updating settings');

      final response = await _apiService.put(
        '/api/finance/matrix/settings',
        body: settings,
      );

      if (response.success) {
        if (kDebugMode) debugPrint('✅ FinanceMatrixService: Settings updated');
        return ApiResponse<void>(success: true);
      }

      return ApiResponse<void>(
        success: false,
        message: response.message ?? 'Failed to update settings',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ FinanceMatrixService: Error - $e');
      return ApiResponse<void>(
        success: false,
        message: 'Error updating settings: $e',
      );
    }
  }
}
