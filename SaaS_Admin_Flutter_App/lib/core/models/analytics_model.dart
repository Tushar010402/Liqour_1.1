class DashboardAnalytics {
  final int totalSubscriptions;
  final int activeSubscriptions;
  final int trialSubscriptions;
  final double totalRevenue;
  final double monthlyRevenue;
  final int totalTenants;
  final int newTenants;
  final double churnRate;
  final Map<String, int> planDistribution;
  final List<SubscriptionMetric> subscriptionMetrics;
  final Map<String, double> revenueByPlan;
  final Map<String, double> monthlyGrowth;

  DashboardAnalytics({
    required this.totalSubscriptions,
    required this.activeSubscriptions,
    required this.trialSubscriptions,
    required this.totalRevenue,
    required this.monthlyRevenue,
    required this.totalTenants,
    required this.newTenants,
    required this.churnRate,
    required this.planDistribution,
    required this.subscriptionMetrics,
    required this.revenueByPlan,
    required this.monthlyGrowth,
  });

  factory DashboardAnalytics.fromJson(Map<String, dynamic> json) {
    return DashboardAnalytics(
      totalSubscriptions: json['total_subscriptions'] ?? 0,
      activeSubscriptions: json['active_subscriptions'] ?? 0,
      trialSubscriptions: json['trial_subscriptions'] ?? 0,
      totalRevenue: (json['total_revenue'] as num?)?.toDouble() ?? 0.0,
      monthlyRevenue: (json['monthly_revenue'] as num?)?.toDouble() ?? 0.0,
      totalTenants: json['total_tenants'] ?? 0,
      newTenants: json['new_tenants'] ?? 0,
      churnRate: (json['churn_rate'] as num?)?.toDouble() ?? 0.0,
      planDistribution: Map<String, int>.from(json['plan_distribution'] ?? {}),
      subscriptionMetrics:
          (json['subscription_metrics'] as List<dynamic>? ?? [])
              .map((item) =>
                  SubscriptionMetric.fromJson(item as Map<String, dynamic>))
              .toList(),
      revenueByPlan: Map<String, double>.from(
        (json['revenue_by_plan'] as Map<String, dynamic>? ?? {})
            .map((key, value) => MapEntry(key, (value as num).toDouble())),
      ),
      monthlyGrowth: Map<String, double>.from(
        (json['monthly_growth'] as Map<String, dynamic>? ?? {})
            .map((key, value) => MapEntry(key, (value as num).toDouble())),
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'total_subscriptions': totalSubscriptions,
      'active_subscriptions': activeSubscriptions,
      'trial_subscriptions': trialSubscriptions,
      'total_revenue': totalRevenue,
      'monthly_revenue': monthlyRevenue,
      'total_tenants': totalTenants,
      'new_tenants': newTenants,
      'churn_rate': churnRate,
      'plan_distribution': planDistribution,
      'subscription_metrics':
          subscriptionMetrics.map((metric) => metric.toJson()).toList(),
      'revenue_by_plan': revenueByPlan,
      'monthly_growth': monthlyGrowth,
    };
  }

  int get cancelledSubscriptions =>
      totalSubscriptions - activeSubscriptions - trialSubscriptions;
  double get activePercentage => totalSubscriptions > 0
      ? (activeSubscriptions / totalSubscriptions) * 100
      : 0;
  double get trialPercentage => totalSubscriptions > 0
      ? (trialSubscriptions / totalSubscriptions) * 100
      : 0;
  double get cancelledPercentage => totalSubscriptions > 0
      ? (cancelledSubscriptions / totalSubscriptions) * 100
      : 0;
  double get averageRevenuePerSubscription =>
      activeSubscriptions > 0 ? totalRevenue / activeSubscriptions : 0;
}

class SubscriptionMetric {
  final String planName;
  final int count;
  final double percentage;

  SubscriptionMetric({
    required this.planName,
    required this.count,
    required this.percentage,
  });

  factory SubscriptionMetric.fromJson(Map<String, dynamic> json) {
    return SubscriptionMetric(
      planName: json['plan_name'] ?? '',
      count: json['count'] ?? 0,
      percentage: (json['percentage'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'plan_name': planName,
      'count': count,
      'percentage': percentage,
    };
  }
}

class ChartDataPoint {
  final String label;
  final double value;
  final String displayValue;

  ChartDataPoint({
    required this.label,
    required this.value,
    String? displayValue,
  }) : displayValue = displayValue ?? value.toString();
}

class AnalyticsPeriod {
  final String label;
  final String value;
  final DateTime? startDate;
  final DateTime? endDate;

  AnalyticsPeriod({
    required this.label,
    required this.value,
    this.startDate,
    this.endDate,
  });

  static List<AnalyticsPeriod> get defaultPeriods => [
        AnalyticsPeriod(label: 'Today', value: 'today'),
        AnalyticsPeriod(label: 'This Week', value: 'week'),
        AnalyticsPeriod(label: 'This Month', value: 'month'),
        AnalyticsPeriod(label: 'Last 3 Months', value: '3months'),
        AnalyticsPeriod(label: 'This Year', value: 'year'),
        AnalyticsPeriod(label: 'All Time', value: 'all'),
      ];
}
