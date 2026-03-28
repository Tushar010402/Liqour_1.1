/// Dashboard Metrics Models
///
/// Data structures for the manager/admin dashboard summary view
/// API: GET /api/sales/dashboard/summary
library;

class DashboardMetrics {
  final DateRange dateRange;
  final ShopFilter shopFilter;
  final MetricsSummary metrics;

  DashboardMetrics({
    required this.dateRange,
    required this.shopFilter,
    required this.metrics,
  });

  factory DashboardMetrics.fromJson(Map<String, dynamic> json) {
    // Handle both /dashboard/metrics and /dashboard/summary response formats
    // /dashboard/metrics returns: { date_range: {...}, shop_filter: {...}, metrics: {...} }
    // /dashboard/summary returns flat structure with different keys

    final dateRangeData = json['date_range'] as Map<String, dynamic>?;
    final shopFilterData = json['shop_filter'] as Map<String, dynamic>?;
    final metricsData = json['metrics'] as Map<String, dynamic>?;

    return DashboardMetrics(
      dateRange: dateRangeData != null
          ? DateRange.fromJson(dateRangeData)
          : DateRange(
              startDate: DateTime.now().subtract(const Duration(days: 1)),
              endDate: DateTime.now().subtract(const Duration(days: 1)),
              filterApplied: 'yesterday',
            ),
      shopFilter: shopFilterData != null
          ? ShopFilter.fromJson(shopFilterData)
          : ShopFilter(shopId: null, shopName: 'All Shops'),
      metrics: metricsData != null
          ? MetricsSummary.fromJson(metricsData)
          : MetricsSummary.empty(),
    );
  }

  /// Empty/default metrics
  factory DashboardMetrics.empty() {
    return DashboardMetrics(
      dateRange: DateRange(
        startDate: DateTime.now().subtract(const Duration(days: 1)),
        endDate: DateTime.now().subtract(const Duration(days: 1)),
        filterApplied: 'yesterday',
      ),
      shopFilter: ShopFilter(shopId: null, shopName: 'All Shops'),
      metrics: MetricsSummary.empty(),
    );
  }
}

class DateRange {
  final DateTime startDate;
  final DateTime endDate;
  final String filterApplied;

  DateRange({
    required this.startDate,
    required this.endDate,
    required this.filterApplied,
  });

  factory DateRange.fromJson(Map<String, dynamic> json) {
    return DateRange(
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: DateTime.parse(json['end_date'] as String),
      filterApplied: json['filter_applied'] as String? ?? 'yesterday',
    );
  }
}

class ShopFilter {
  final String? shopId;
  final String shopName;

  ShopFilter({
    this.shopId,
    required this.shopName,
  });

  factory ShopFilter.fromJson(Map<String, dynamic> json) {
    return ShopFilter(
      shopId: json['shop_id'] as String?,
      shopName: json['shop_name'] as String? ?? 'All Shops',
    );
  }
}

class MetricsSummary {
  final MetricItem payment;
  final MetricItem purchase;
  final MetricItem sale;
  final MetricItem expense;

  MetricsSummary({
    required this.payment,
    required this.purchase,
    required this.sale,
    required this.expense,
  });

  factory MetricsSummary.fromJson(Map<String, dynamic> json) {
    return MetricsSummary(
      payment: MetricItem.fromJson(json['payment'] as Map<String, dynamic>? ?? {}),
      purchase: MetricItem.fromJson(json['purchase'] as Map<String, dynamic>? ?? {}),
      sale: MetricItem.fromJson(json['sale'] as Map<String, dynamic>? ?? {}),
      expense: MetricItem.fromJson(json['expense'] as Map<String, dynamic>? ?? {}),
    );
  }

  factory MetricsSummary.empty() {
    return MetricsSummary(
      payment: MetricItem(totalAmount: 0),
      purchase: MetricItem(totalAmount: 0),
      sale: MetricItem(totalAmount: 0),
      expense: MetricItem(totalAmount: 0),
    );
  }
}

class MetricItem {
  final double totalAmount;
  final int? count;

  MetricItem({
    required this.totalAmount,
    this.count,
  });

  factory MetricItem.fromJson(Map<String, dynamic> json) {
    return MetricItem(
      totalAmount: (json['total_amount'] ?? 0).toDouble(),
      count: json['count'] as int?,
    );
  }
}

/// Date filter options for the dashboard
enum DateFilterOption {
  today('today', 'Today'),
  yesterday('yesterday', 'Yesterday'),
  last7Days('last_7_days', 'Last 7 Days'),
  last30Days('last_30_days', 'Last 30 Days'),
  thisMonth('this_month', 'This Month'),
  custom('custom', 'Custom');

  final String value;
  final String label;

  const DateFilterOption(this.value, this.label);

  static DateFilterOption fromValue(String value) {
    return DateFilterOption.values.firstWhere(
      (e) => e.value == value,
      orElse: () => DateFilterOption.yesterday,
    );
  }
}
