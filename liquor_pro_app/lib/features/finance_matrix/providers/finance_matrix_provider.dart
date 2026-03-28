import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/service_providers.dart';
import '../models/finance_matrix_models.dart';
import '../services/finance_matrix_service.dart';

// ============================================================================
// SERVICE PROVIDER
// ============================================================================

/// Provider for the FinanceMatrixService
final financeMatrixServiceProvider = Provider<FinanceMatrixService>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  return FinanceMatrixService(apiService);
});

// ============================================================================
// QUERY PROVIDERS (UI STATE)
// ============================================================================

/// Selected time period
final matrixPeriodProvider = StateProvider<MatrixPeriod>((ref) => MatrixPeriod.today);

/// Selected shop (null = all shops)
final matrixShopIdProvider = StateProvider<String?>((ref) => null);

/// Custom date range start
final matrixStartDateProvider = StateProvider<DateTime?>((ref) => null);

/// Custom date range end
final matrixEndDateProvider = StateProvider<DateTime?>((ref) => null);

/// Computed query from UI state
final matrixQueryProvider = Provider<MatrixQuery>((ref) {
  final period = ref.watch(matrixPeriodProvider);
  final shopId = ref.watch(matrixShopIdProvider);
  final startDate = ref.watch(matrixStartDateProvider);
  final endDate = ref.watch(matrixEndDateProvider);

  return MatrixQuery(
    period: period,
    shopId: shopId,
    startDate: startDate,
    endDate: endDate,
    includeInsights: true,
  );
});

// ============================================================================
// DATA PROVIDERS
// ============================================================================

/// Main dashboard provider
final financeMatrixDashboardProvider =
    FutureProvider.family<FinanceMatrixDashboard, MatrixQuery>((ref, query) async {
  final service = ref.watch(financeMatrixServiceProvider);
  final response = await service.getDashboard(query);
  if (response.success && response.data != null) {
    return response.data!;
  }
  throw Exception(response.message ?? 'Failed to fetch finance matrix');
});

/// Active dashboard based on current query
final activeFinanceMatrixProvider = FutureProvider<FinanceMatrixDashboard>((ref) async {
  final query = ref.watch(matrixQueryProvider);
  return ref.watch(financeMatrixDashboardProvider(query).future);
});

/// Sales summary only
final salesSummaryProvider =
    FutureProvider.family<SalesSummary, MatrixQuery>((ref, query) async {
  final service = ref.watch(financeMatrixServiceProvider);
  final response = await service.getSalesSummary(query);
  if (response.success && response.data != null) {
    return response.data!;
  }
  throw Exception(response.message ?? 'Failed to fetch sales summary');
});

/// Cash summary only
final cashSummaryProvider =
    FutureProvider.family<CashSummary, MatrixQuery>((ref, query) async {
  final service = ref.watch(financeMatrixServiceProvider);
  final response = await service.getCashSummary(query);
  if (response.success && response.data != null) {
    return response.data!;
  }
  throw Exception(response.message ?? 'Failed to fetch cash summary');
});

/// Inventory summary only
final inventorySummaryProvider =
    FutureProvider.family<InventorySummary, MatrixQuery>((ref, query) async {
  final service = ref.watch(financeMatrixServiceProvider);
  final response = await service.getInventorySummary(query);
  if (response.success && response.data != null) {
    return response.data!;
  }
  throw Exception(response.message ?? 'Failed to fetch inventory summary');
});

/// Expenses summary only
final expensesSummaryProvider =
    FutureProvider.family<ExpensesSummary, MatrixQuery>((ref, query) async {
  final service = ref.watch(financeMatrixServiceProvider);
  final response = await service.getExpensesSummary(query);
  if (response.success && response.data != null) {
    return response.data!;
  }
  throw Exception(response.message ?? 'Failed to fetch expenses summary');
});

/// AI Insights provider
final matrixInsightsProvider =
    FutureProvider.family<List<MatrixInsight>, MatrixQuery>((ref, query) async {
  final service = ref.watch(financeMatrixServiceProvider);
  final response = await service.getInsights(query);
  if (response.success && response.data != null) {
    return response.data!;
  }
  return [];
});

/// Active insights based on current query
final activeInsightsProvider = FutureProvider<List<MatrixInsight>>((ref) async {
  final query = ref.watch(matrixQueryProvider);
  return ref.watch(matrixInsightsProvider(query).future);
});

// ============================================================================
// TREND PROVIDERS
// ============================================================================

/// Sales trend query
class TrendQuery {
  final String trendPeriod;
  final String? shopId;
  final int days;

  const TrendQuery({
    this.trendPeriod = 'daily',
    this.shopId,
    this.days = 30,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrendQuery &&
          runtimeType == other.runtimeType &&
          trendPeriod == other.trendPeriod &&
          shopId == other.shopId &&
          days == other.days;

  @override
  int get hashCode => trendPeriod.hashCode ^ shopId.hashCode ^ days.hashCode;
}

/// Sales trend data
final salesTrendProvider =
    FutureProvider.family<TrendData, TrendQuery>((ref, query) async {
  final service = ref.watch(financeMatrixServiceProvider);
  final response = await service.getSalesTrend(
    trendPeriod: query.trendPeriod,
    shopId: query.shopId,
    days: query.days,
  );
  if (response.success && response.data != null) {
    return response.data!;
  }
  throw Exception(response.message ?? 'Failed to fetch trend');
});

/// Cash flow trend data
final cashFlowTrendProvider =
    FutureProvider.family<TrendData, TrendQuery>((ref, query) async {
  final service = ref.watch(financeMatrixServiceProvider);
  final response = await service.getCashFlowTrend(
    trendPeriod: query.trendPeriod,
    shopId: query.shopId,
    days: query.days,
  );
  if (response.success && response.data != null) {
    return response.data!;
  }
  throw Exception(response.message ?? 'Failed to fetch trend');
});

// ============================================================================
// MATRIX NOTIFIER (MUTATIONS)
// ============================================================================

/// StateNotifier for matrix mutations
class FinanceMatrixNotifier extends StateNotifier<AsyncValue<void>> {
  final FinanceMatrixService _service;
  final Ref _ref;

  FinanceMatrixNotifier(this._service, this._ref) : super(const AsyncValue.data(null));

  /// Dismiss an insight
  Future<bool> dismissInsight(String insightId) async {
    state = const AsyncValue.loading();
    try {
      final response = await _service.dismissInsight(insightId);
      if (response.success) {
        _ref.invalidate(activeInsightsProvider);
        _ref.invalidate(activeFinanceMatrixProvider);
        state = const AsyncValue.data(null);
        return true;
      }
      state = AsyncValue.error(response.message ?? 'Failed', StackTrace.current);
      return false;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// Export report
  Future<String?> exportReport({
    required MatrixQuery query,
    required String format,
  }) async {
    state = const AsyncValue.loading();
    try {
      final response = await _service.exportReport(
        query: query,
        format: format,
      );
      state = const AsyncValue.data(null);
      if (response.success && response.data != null) {
        return response.data;
      }
      return null;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return null;
    }
  }

  /// Update settings
  Future<bool> updateSettings(Map<String, dynamic> settings) async {
    state = const AsyncValue.loading();
    try {
      final response = await _service.updateSettings(settings);
      if (response.success) {
        _ref.invalidate(matrixSettingsProvider);
        state = const AsyncValue.data(null);
        return true;
      }
      state = AsyncValue.error(response.message ?? 'Failed', StackTrace.current);
      return false;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// Refresh all data
  void refresh() {
    _ref.invalidate(activeFinanceMatrixProvider);
    _ref.invalidate(activeInsightsProvider);
  }

  /// Change period
  void setPeriod(MatrixPeriod period) {
    _ref.read(matrixPeriodProvider.notifier).state = period;
  }

  /// Change shop filter
  void setShopId(String? shopId) {
    _ref.read(matrixShopIdProvider.notifier).state = shopId;
  }

  /// Set custom date range
  void setDateRange(DateTime start, DateTime end) {
    _ref.read(matrixPeriodProvider.notifier).state = MatrixPeriod.custom;
    _ref.read(matrixStartDateProvider.notifier).state = start;
    _ref.read(matrixEndDateProvider.notifier).state = end;
  }
}

/// Provider for matrix mutations
final financeMatrixNotifierProvider =
    StateNotifierProvider<FinanceMatrixNotifier, AsyncValue<void>>((ref) {
  final service = ref.watch(financeMatrixServiceProvider);
  return FinanceMatrixNotifier(service, ref);
});

// ============================================================================
// SETTINGS PROVIDER
// ============================================================================

/// Matrix settings (targets, budgets, etc.)
final matrixSettingsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final service = ref.watch(financeMatrixServiceProvider);
  final response = await service.getSettings();
  if (response.success && response.data != null) {
    return response.data!;
  }
  return {};
});

// ============================================================================
// COMPARISON PROVIDER
// ============================================================================

/// Comparison query
class ComparisonQuery {
  final MatrixPeriod period1;
  final MatrixPeriod period2;
  final String? shopId;

  const ComparisonQuery({
    required this.period1,
    required this.period2,
    this.shopId,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ComparisonQuery &&
          runtimeType == other.runtimeType &&
          period1 == other.period1 &&
          period2 == other.period2 &&
          shopId == other.shopId;

  @override
  int get hashCode => period1.hashCode ^ period2.hashCode ^ shopId.hashCode;
}

/// Period comparison provider
final periodComparisonProvider =
    FutureProvider.family<Map<String, dynamic>, ComparisonQuery>((ref, query) async {
  final service = ref.watch(financeMatrixServiceProvider);
  final response = await service.comparePeriods(
    period1: query.period1,
    period2: query.period2,
    shopId: query.shopId,
  );
  if (response.success && response.data != null) {
    return response.data!;
  }
  throw Exception(response.message ?? 'Failed to compare periods');
});

// ============================================================================
// HELPER EXTENSIONS
// ============================================================================

extension FinanceMatrixDashboardX on FinanceMatrixDashboard {
  /// Get health status text
  String get healthStatus {
    if (healthScore >= 90) return 'Excellent';
    if (healthScore >= 75) return 'Good';
    if (healthScore >= 60) return 'Fair';
    if (healthScore >= 40) return 'Needs Attention';
    return 'Critical';
  }

  /// Get health color value (for UI)
  int get healthColorValue {
    if (healthScore >= 90) return 0xFF10B981; // Green
    if (healthScore >= 75) return 0xFF22C55E; // Light Green
    if (healthScore >= 60) return 0xFFF59E0B; // Yellow
    if (healthScore >= 40) return 0xFFF97316; // Orange
    return 0xFFEF4444; // Red
  }

  /// Get critical insights
  List<MatrixInsight> get criticalInsights =>
      insights.where((i) => i.severity == 'critical').toList();

  /// Get warning insights
  List<MatrixInsight> get warningInsights =>
      insights.where((i) => i.severity == 'warning').toList();

  /// Get info insights
  List<MatrixInsight> get infoInsights =>
      insights.where((i) => i.severity == 'info').toList();

  /// Get success insights
  List<MatrixInsight> get successInsights =>
      insights.where((i) => i.severity == 'success').toList();
}

extension SalesSummaryX on SalesSummary {
  /// Format for display
  String get formattedTotal => '₹${_formatNumber(totalAmount)}';

  /// Is above target
  bool get isAboveTarget => target > 0 && totalAmount >= target;

  /// Growth indicator text
  String get growthText {
    if (growthPercent > 0) return '+${growthPercent.toStringAsFixed(1)}%';
    if (growthPercent < 0) return '${growthPercent.toStringAsFixed(1)}%';
    return '0%';
  }
}

extension CashSummaryX on CashSummary {
  /// Format variance for display
  String get formattedVariance {
    if (variance.abs() < 0.01) return '₹0';
    final sign = variance > 0 ? '+' : '';
    return '$sign₹${_formatNumber(variance)}';
  }

  /// Get variance status
  String get varianceStatus {
    if (variance.abs() < 0.01) return 'balanced';
    if (variance > 0) return 'over';
    return 'short';
  }
}

extension InventorySummaryX on InventorySummary {
  /// Get health status
  String get healthStatus {
    if (outOfStockCount > 0) return 'critical';
    if (lowStockCount > 5) return 'warning';
    return 'healthy';
  }

  /// Format value for display
  String get formattedValue => '₹${_formatNumber(totalValue)}';
}

extension ExpensesSummaryX on ExpensesSummary {
  /// Format for display
  String get formattedTotal => '₹${_formatNumber(totalSpent)}';

  /// Budget status
  String get budgetStatus {
    if (budgeted <= 0) return 'no_budget';
    if (totalSpent > budgeted) return 'over_budget';
    if (totalSpent > budgeted * 0.8) return 'near_limit';
    return 'within_budget';
  }
}

/// Number formatter helper
String _formatNumber(double value) {
  if (value >= 10000000) {
    return '${(value / 10000000).toStringAsFixed(2)}Cr';
  } else if (value >= 100000) {
    return '${(value / 100000).toStringAsFixed(2)}L';
  } else if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(1)}K';
  }
  return value.toStringAsFixed(0);
}
