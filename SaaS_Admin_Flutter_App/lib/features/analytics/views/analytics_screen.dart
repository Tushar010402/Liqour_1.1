import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/analytics_provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/analytics_model.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  String _selectedPeriod = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AnalyticsProvider>().loadDashboardAnalytics();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGray,
      body: Consumer<AnalyticsProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primaryRed),
            );
          }

          if (provider.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 64,
                    color: AppColors.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Error loading analytics data',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    provider.errorMessage ?? 'Unknown error occurred',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.mediumGray,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => provider.loadDashboardAnalytics(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryRed,
                      foregroundColor: AppColors.white,
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Analytics Dashboard',
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryBlack,
                              ),
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.borderGray),
                            borderRadius: BorderRadius.circular(8),
                            color: AppColors.white,
                          ),
                          child: DropdownButton<String>(
                            value: _selectedPeriod,
                            underline: Container(),
                            items: AnalyticsPeriod.defaultPeriods
                                .map((period) => DropdownMenuItem(
                                      value: period.value,
                                      child: Text(period.label),
                                    ))
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _selectedPeriod = value;
                                });
                                provider.changePeriod(value);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton.icon(
                          onPressed: () => provider.refresh(),
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Refresh'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryRed,
                            foregroundColor: AppColors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // KPI Cards Row 1
                if (provider.analytics != null) _buildKPICards(provider),

                const SizedBox(height: 24),

                // Chart Cards Row
                if (provider.analytics != null) _buildChartCards(provider),

                const SizedBox(height: 24),

                // Plan Distribution and Status Charts
                if (provider.analytics != null)
                  _buildDistributionCharts(provider),

                const SizedBox(height: 24),

                // Detailed Metrics
                if (provider.analytics != null) _buildDetailedMetrics(provider),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildKPICards(AnalyticsProvider provider) {
    final analytics = provider.analytics!;

    return Column(
      children: [
        // First Row
        Row(
          children: [
            Expanded(
              child: _buildKPICard(
                'Total Subscriptions',
                analytics.totalSubscriptions.toString(),
                Icons.subscriptions_outlined,
                AppColors.primaryRed,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildKPICard(
                'Active Subscriptions',
                analytics.activeSubscriptions.toString(),
                Icons.check_circle_outline,
                Colors.green,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildKPICard(
                'Total Tenants',
                analytics.totalTenants.toString(),
                Icons.business_outlined,
                Colors.blue,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildKPICard(
                'New Tenants',
                analytics.newTenants.toString(),
                Icons.add_business_outlined,
                Colors.orange,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Second Row
        Row(
          children: [
            Expanded(
              child: _buildKPICard(
                'Total Revenue',
                '\$${analytics.totalRevenue.toStringAsFixed(0)}',
                Icons.monetization_on_outlined,
                Colors.green,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildKPICard(
                'Monthly Revenue',
                '\$${analytics.monthlyRevenue.toStringAsFixed(0)}',
                Icons.trending_up_outlined,
                Colors.teal,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildKPICard(
                'Avg Revenue/Sub',
                '\$${analytics.averageRevenuePerSubscription.toStringAsFixed(0)}',
                Icons.analytics_outlined,
                Colors.purple,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildKPICard(
                'Churn Rate',
                '${analytics.churnRate.toStringAsFixed(1)}%',
                Icons.trending_down_outlined,
                analytics.churnRate > 5 ? Colors.red : Colors.green,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildKPICard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlack.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 24),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryBlack,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.mediumGray,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartCards(AnalyticsProvider provider) {
    final analytics = provider.analytics!;

    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryBlack.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Subscription Status',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryBlack,
                      ),
                ),
                const SizedBox(height: 16),
                _buildStatusChart(analytics),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryBlack.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recent Activity',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryBlack,
                      ),
                ),
                const SizedBox(height: 16),
                _buildRecentActivity(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusChart(DashboardAnalytics analytics) {
    return Column(
      children: [
        _buildStatusItem('Active', analytics.activeSubscriptions, Colors.green),
        _buildStatusItem('Trial', analytics.trialSubscriptions, Colors.orange),
        _buildStatusItem(
            'Cancelled', analytics.cancelledSubscriptions, Colors.red),
      ],
    );
  }

  Widget _buildStatusItem(String label, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(width: 8),
              Text(label),
            ],
          ),
          Text(
            count.toString(),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentActivity() {
    final activities = [
      {
        'action': 'New subscription',
        'tenant': 'Liquor Mart Express',
        'time': '2h ago'
      },
      {
        'action': 'Plan upgrade',
        'tenant': 'Premium Wine Store',
        'time': '4h ago'
      },
      {
        'action': 'Trial ended',
        'tenant': 'City Spirits Shop',
        'time': '6h ago'
      },
      {
        'action': 'New tenant',
        'tenant': 'Elite Beverage Center',
        'time': '1d ago'
      },
    ];

    return Column(
      children: activities
          .map((activity) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      activity['action'] == 'New subscription'
                          ? Icons.add_circle_outline
                          : activity['action'] == 'Plan upgrade'
                              ? Icons.upgrade_outlined
                              : activity['action'] == 'Trial ended'
                                  ? Icons.schedule_outlined
                                  : Icons.business_outlined,
                      size: 16,
                      color: AppColors.mediumGray,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            activity['action']!,
                            style: const TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            activity['tenant']!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.mediumGray,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      activity['time']!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.mediumGray,
                      ),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }

  Widget _buildDistributionCharts(AnalyticsProvider provider) {
    final analytics = provider.analytics!;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlack.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Plan Distribution',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryBlack,
                ),
          ),
          const SizedBox(height: 16),
          Row(
            children: analytics.subscriptionMetrics
                .map(
                  (metric) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            metric.planName,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primaryBlack,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${metric.count} subscriptions',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppColors.mediumGray,
                                    ),
                          ),
                          Text(
                            '${metric.percentage.toStringAsFixed(1)}%',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppColors.primaryRed,
                                      fontWeight: FontWeight.w500,
                                    ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedMetrics(AnalyticsProvider provider) {
    final analytics = provider.analytics!;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlack.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Key Metrics Summary',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryBlack,
                ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildMetricRow(
                        'Conversion Rate', 'N/A', Icons.trending_up),
                    _buildMetricRow(
                        'Average Subscription Value',
                        '\$${analytics.averageRevenuePerSubscription.toStringAsFixed(2)}',
                        Icons.monetization_on),
                    _buildMetricRow(
                        'Customer Lifetime Value', 'N/A', Icons.timeline),
                  ],
                ),
              ),
              const SizedBox(width: 32),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildMetricRow(
                        'Monthly Recurring Revenue',
                        '\$${analytics.monthlyRevenue.toStringAsFixed(2)}',
                        Icons.repeat),
                    _buildMetricRow(
                        'Active Subscription Rate',
                        '${analytics.activePercentage.toStringAsFixed(1)}%',
                        Icons.check_circle),
                    _buildMetricRow(
                        'Trial Conversion Rate', 'N/A', Icons.transform),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.primaryRed),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryBlack,
                ),
          ),
        ],
      ),
    );
  }
}
