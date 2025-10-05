class SubscriptionAnalytics {
  final String period;
  final int totalSubscriptions;
  final Map<String, int> statusDistribution;
  final Map<String, int> billingCycleBreakdown;
  final List<PlanPopularity> planPopularity;
  final Map<String, double> conversionRates;
  final double averageSubscriptionValue;

  SubscriptionAnalytics({
    required this.period,
    required this.totalSubscriptions,
    required this.statusDistribution,
    required this.billingCycleBreakdown,
    required this.planPopularity,
    required this.conversionRates,
    required this.averageSubscriptionValue,
  });

  factory SubscriptionAnalytics.fromJson(Map<String, dynamic> json) {
    return SubscriptionAnalytics(
      period: json['period'] ?? 'monthly',
      totalSubscriptions: json['total_subscriptions'] ?? 0,
      statusDistribution:
          Map<String, int>.from(json['status_distribution'] ?? {}),
      billingCycleBreakdown:
          Map<String, int>.from(json['billing_cycle_breakdown'] ?? {}),
      planPopularity: (json['plan_popularity'] as List<dynamic>? ?? [])
          .map((item) => PlanPopularity.fromJson(item as Map<String, dynamic>))
          .toList(),
      conversionRates: Map<String, double>.from(
        (json['conversion_rates'] as Map<String, dynamic>? ?? {})
            .map((key, value) => MapEntry(key, (value as num).toDouble())),
      ),
      averageSubscriptionValue:
          (json['average_subscription_value'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'period': period,
      'total_subscriptions': totalSubscriptions,
      'status_distribution': statusDistribution,
      'billing_cycle_breakdown': billingCycleBreakdown,
      'plan_popularity': planPopularity.map((plan) => plan.toJson()).toList(),
      'conversion_rates': conversionRates,
      'average_subscription_value': averageSubscriptionValue,
    };
  }

  int get activeSubscriptions => statusDistribution['active'] ?? 0;
  int get cancelledSubscriptions => statusDistribution['cancelled'] ?? 0;
  int get trialSubscriptions => statusDistribution['trial'] ?? 0;

  double get activePercentage => totalSubscriptions > 0
      ? (activeSubscriptions / totalSubscriptions) * 100
      : 0;
  double get cancelledPercentage => totalSubscriptions > 0
      ? (cancelledSubscriptions / totalSubscriptions) * 100
      : 0;
  double get trialPercentage => totalSubscriptions > 0
      ? (trialSubscriptions / totalSubscriptions) * 100
      : 0;
}

class PlanPopularity {
  final String planName;
  final int subscriptions;
  final double averageRevenue;

  PlanPopularity({
    required this.planName,
    required this.subscriptions,
    required this.averageRevenue,
  });

  factory PlanPopularity.fromJson(Map<String, dynamic> json) {
    return PlanPopularity(
      planName: json['plan_name'] ?? '',
      subscriptions: json['subscriptions'] ?? 0,
      averageRevenue: (json['average_revenue'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'plan_name': planName,
      'subscriptions': subscriptions,
      'average_revenue': averageRevenue,
    };
  }
}

class SubscriptionModel {
  final String id;
  final String tenantId;
  final String tenantName;
  final String planId;
  final String planName;
  final String status;
  final String billingCycle;
  final double amount;
  final DateTime startDate;
  final DateTime? endDate;
  final DateTime? trialEndDate;
  final DateTime? nextBillingDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, dynamic>? metadata;

  SubscriptionModel({
    required this.id,
    required this.tenantId,
    required this.tenantName,
    required this.planId,
    required this.planName,
    required this.status,
    required this.billingCycle,
    required this.amount,
    required this.startDate,
    this.endDate,
    this.trialEndDate,
    this.nextBillingDate,
    required this.createdAt,
    required this.updatedAt,
    this.metadata,
  });

  factory SubscriptionModel.fromJson(Map<String, dynamic> json) {
    return SubscriptionModel(
      id: json['id'] ?? '',
      tenantId: json['tenant_id'] ?? '',
      tenantName: json['tenant_name'] ?? '',
      planId: json['plan_id'] ?? '',
      planName: json['plan_name'] ?? '',
      status: json['status'] ?? 'unknown',
      billingCycle: json['billing_cycle'] ?? 'monthly',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      startDate: DateTime.parse(
          json['start_date'] ?? DateTime.now().toIso8601String()),
      endDate:
          json['end_date'] != null ? DateTime.parse(json['end_date']) : null,
      trialEndDate: json['trial_end_date'] != null
          ? DateTime.parse(json['trial_end_date'])
          : null,
      nextBillingDate: json['next_billing_date'] != null
          ? DateTime.parse(json['next_billing_date'])
          : null,
      createdAt: DateTime.parse(
          json['created_at'] ?? DateTime.now().toIso8601String()),
      updatedAt: DateTime.parse(
          json['updated_at'] ?? DateTime.now().toIso8601String()),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tenant_id': tenantId,
      'tenant_name': tenantName,
      'plan_id': planId,
      'plan_name': planName,
      'status': status,
      'billing_cycle': billingCycle,
      'amount': amount,
      'start_date': startDate.toIso8601String(),
      'end_date': endDate?.toIso8601String(),
      'trial_end_date': trialEndDate?.toIso8601String(),
      'next_billing_date': nextBillingDate?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'metadata': metadata,
    };
  }

  bool get isActive => status.toLowerCase() == 'active';
  bool get isCancelled => status.toLowerCase() == 'cancelled';
  bool get isTrial => status.toLowerCase() == 'trial';
  bool get isPaused => status.toLowerCase() == 'paused';

  int get daysRemaining {
    if (nextBillingDate != null) {
      final now = DateTime.now();
      final difference = nextBillingDate!.difference(now).inDays;
      return difference > 0 ? difference : 0;
    }
    return 0;
  }

  String get formattedAmount {
    return '\$${amount.toStringAsFixed(2)}';
  }
}
