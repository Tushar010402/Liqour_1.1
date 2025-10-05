import 'package:flutter/foundation.dart';
import '../../../core/services/api_service.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/models/analytics_model.dart';

enum AnalyticsState {
  initial,
  loading,
  loaded,
  error,
}

class AnalyticsProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();

  AnalyticsState _state = AnalyticsState.initial;
  DashboardAnalytics? _analytics;
  String? _errorMessage;
  DateTime? _lastUpdated;
  String _selectedPeriod = 'all';

  // Getters
  AnalyticsState get state => _state;
  DashboardAnalytics? get analytics => _analytics;
  String? get errorMessage => _errorMessage;
  DateTime? get lastUpdated => _lastUpdated;
  String get selectedPeriod => _selectedPeriod;

  bool get isLoading => _state == AnalyticsState.loading;
  bool get hasError => _state == AnalyticsState.error;
  bool get hasData => _analytics != null;

  // Load dashboard analytics
  Future<void> loadDashboardAnalytics() async {
    _setState(AnalyticsState.loading);

    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        ApiEndpoints.analyticsDashboard,
        fromJson: (data) => data as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        _analytics = DashboardAnalytics.fromJson(response.data!);
        _lastUpdated = DateTime.now();
        _setState(AnalyticsState.loaded);
      } else {
        _setError('Failed to load analytics: ${response.error}');
      }
    } catch (e) {
      debugPrint('Failed to load analytics: $e');
      _setError('Failed to load analytics: ${e.toString()}');
    }
  }

  // Refresh analytics data
  Future<void> refresh() async {
    await loadDashboardAnalytics();
  }

  // Change selected period
  void changePeriod(String period) {
    if (_selectedPeriod != period) {
      _selectedPeriod = period;
      notifyListeners();
      // In a real app, you would reload data with the new period
      // For now, we'll just refresh the existing data
      refresh();
    }
  }

  // Get chart data for plan distribution
  List<ChartDataPoint> getPlanDistributionChartData() {
    if (_analytics == null) return [];

    return _analytics!.planDistribution.entries.map((entry) {
      final percentage = _analytics!.subscriptionMetrics
          .firstWhere(
            (metric) => metric.planName == entry.key,
            orElse: () => SubscriptionMetric(
                planName: entry.key, count: entry.value, percentage: 0),
          )
          .percentage;

      return ChartDataPoint(
        label: entry.key,
        value: entry.value.toDouble(),
        displayValue: '${entry.value} (${percentage.toStringAsFixed(1)}%)',
      );
    }).toList();
  }

  // Get chart data for subscription status
  List<ChartDataPoint> getSubscriptionStatusChartData() {
    if (_analytics == null) return [];

    return [
      ChartDataPoint(
        label: 'Active',
        value: _analytics!.activeSubscriptions.toDouble(),
        displayValue:
            '${_analytics!.activeSubscriptions} (${_analytics!.activePercentage.toStringAsFixed(1)}%)',
      ),
      ChartDataPoint(
        label: 'Trial',
        value: _analytics!.trialSubscriptions.toDouble(),
        displayValue:
            '${_analytics!.trialSubscriptions} (${_analytics!.trialPercentage.toStringAsFixed(1)}%)',
      ),
      ChartDataPoint(
        label: 'Cancelled',
        value: _analytics!.cancelledSubscriptions.toDouble(),
        displayValue:
            '${_analytics!.cancelledSubscriptions} (${_analytics!.cancelledPercentage.toStringAsFixed(1)}%)',
      ),
    ];
  }

  // Get revenue metrics
  Map<String, String> getRevenueMetrics() {
    if (_analytics == null) {
      return {
        'total': '\$0.00',
        'monthly': '\$0.00',
        'average': '\$0.00',
        'growth': '0.0%',
      };
    }

    return {
      'total': '\$${_analytics!.totalRevenue.toStringAsFixed(2)}',
      'monthly': '\$${_analytics!.monthlyRevenue.toStringAsFixed(2)}',
      'average':
          '\$${_analytics!.averageRevenuePerSubscription.toStringAsFixed(2)}',
      'growth':
          '${(_analytics!.monthlyGrowth['revenue'] ?? 0).toStringAsFixed(1)}%',
    };
  }

  // Get growth metrics
  Map<String, String> getGrowthMetrics() {
    if (_analytics == null) {
      return {
        'tenants': '0.0%',
        'subscriptions': '0.0%',
        'churn_rate': '0.0%',
      };
    }

    return {
      'tenants':
          '${(_analytics!.monthlyGrowth['tenants'] ?? 0).toStringAsFixed(1)}%',
      'subscriptions':
          '${(_analytics!.monthlyGrowth['subscriptions'] ?? 0).toStringAsFixed(1)}%',
      'churn_rate': '${_analytics!.churnRate.toStringAsFixed(1)}%',
    };
  }

  // Get key performance indicators
  Map<String, dynamic> getKPIs() {
    if (_analytics == null) {
      return {
        'total_subscriptions': 0,
        'active_subscriptions': 0,
        'total_tenants': 0,
        'total_revenue': 0.0,
        'avg_revenue_per_subscription': 0.0,
        'churn_rate': 0.0,
      };
    }

    return {
      'total_subscriptions': _analytics!.totalSubscriptions,
      'active_subscriptions': _analytics!.activeSubscriptions,
      'total_tenants': _analytics!.totalTenants,
      'total_revenue': _analytics!.totalRevenue,
      'avg_revenue_per_subscription': _analytics!.averageRevenuePerSubscription,
      'churn_rate': _analytics!.churnRate,
    };
  }

  // Get trend data (placeholder for future implementation)
  List<ChartDataPoint> getTrendData(String metric) {
    // In a real app, this would fetch historical data
    // For now, return sample trend data
    final now = DateTime.now();
    return List.generate(12, (index) {
      final date = DateTime(now.year, now.month - (11 - index), 1);
      final value = (_analytics?.totalSubscriptions ?? 0) *
              (0.7 + (index * 0.03)) + // Growth trend
          (index % 3 == 0
              ? -2
              : index % 2 == 0
                  ? 1
                  : 0); // Some variation

      return ChartDataPoint(
        label: '${date.month}/${date.year}',
        value: value,
        displayValue: value.toInt().toString(),
      );
    });
  }

  // Clear error
  void clearError() {
    _errorMessage = null;
    if (_state == AnalyticsState.error) {
      _setState(AnalyticsState.initial);
    }
  }

  // Private methods
  void _setState(AnalyticsState state) {
    _state = state;
    notifyListeners();
  }

  void _setError(String error) {
    _errorMessage = error;
    _state = AnalyticsState.error;
    notifyListeners();
  }
}
