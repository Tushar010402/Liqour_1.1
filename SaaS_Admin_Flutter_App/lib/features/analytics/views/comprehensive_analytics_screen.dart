import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../controllers/analytics_provider.dart';

class ComprehensiveAnalyticsScreen extends StatefulWidget {
  const ComprehensiveAnalyticsScreen({super.key});

  @override
  State<ComprehensiveAnalyticsScreen> createState() =>
      _ComprehensiveAnalyticsScreenState();
}

class _ComprehensiveAnalyticsScreenState
    extends State<ComprehensiveAnalyticsScreen> {
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
          return CustomScrollView(
            slivers: [
              _buildHeader(),
              if (provider.isLoading && provider.analytics == null)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (provider.errorMessage != null)
                _buildErrorSliver(provider)
              else
                _buildAnalyticsContent(provider),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader() {
    return SliverToBoxAdapter(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.white,
          border: Border(
            bottom: BorderSide(color: AppColors.borderGray, width: 1),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primaryRed.withValues(alpha: 0.1),
                    AppColors.primaryRed.withValues(alpha: 0.2),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.analytics,
                color: AppColors.primaryRed,
                size: 32,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Analytics Dashboard',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryBlack,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Real-time SaaS metrics and insights',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.mediumGray,
                        ),
                  ),
                ],
              ),
            ),
            _buildRefreshButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildRefreshButton() {
    return Consumer<AnalyticsProvider>(
      builder: (context, provider, child) {
        return IconButton.filled(
          onPressed: provider.isLoading
              ? null
              : () => provider.loadDashboardAnalytics(),
          style: IconButton.styleFrom(
            backgroundColor: AppColors.primaryRed,
            foregroundColor: AppColors.white,
          ),
          icon: provider.isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.white,
                  ),
                )
              : const Icon(Icons.refresh, size: 20),
        );
      },
    );
  }

  Widget _buildErrorSliver(AnalyticsProvider provider) {
    return SliverFillRemaining(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: AppColors.error.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: AppColors.error,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Failed to Load Analytics',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.error,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    provider.errorMessage!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.mediumGray,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => provider.loadDashboardAnalytics(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      foregroundColor: AppColors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyticsContent(AnalyticsProvider provider) {
    final analytics = provider.analytics!;

    return SliverPadding(
      padding: const EdgeInsets.all(24),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          // Key Metrics Row
          _buildKeyMetricsRow(analytics),
          const SizedBox(height: 24),

          // Subscription Analytics
          _buildSubscriptionAnalytics(analytics),
          const SizedBox(height: 24),

          // Revenue Analytics
          _buildRevenueAnalytics(analytics),
          const SizedBox(height: 24),

          // Tenant Analytics
          _buildTenantAnalytics(analytics),
          const SizedBox(height: 24),

          // Plan Distribution
          _buildPlanDistribution(analytics),
        ]),
      ),
    );
  }

  Widget _buildKeyMetricsRow(dynamic analytics) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmallScreen = constraints.maxWidth < 800;

        if (isSmallScreen) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(
                      child: _buildMetricCard(
                          'Total Subscriptions',
                          analytics['total_subscriptions']?.toString() ?? '0',
                          Icons.subscriptions,
                          AppColors.primaryRed)),
                  const SizedBox(width: 16),
                  Expanded(
                      child: _buildMetricCard(
                          'Active Subs',
                          analytics['active_subscriptions']?.toString() ?? '0',
                          Icons.check_circle,
                          AppColors.success)),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                      child: _buildMetricCard(
                          'Trial Subs',
                          analytics['trial_subscriptions']?.toString() ?? '0',
                          Icons.timer,
                          AppColors.warning)),
                  const SizedBox(width: 16),
                  Expanded(
                      child: _buildMetricCard(
                          'Total Tenants',
                          analytics['total_tenants']?.toString() ?? '0',
                          Icons.business,
                          AppColors.primaryBlue)),
                ],
              ),
            ],
          );
        } else {
          return Row(
            children: [
              Expanded(
                  child: _buildMetricCard(
                      'Total Subscriptions',
                      analytics['total_subscriptions']?.toString() ?? '0',
                      Icons.subscriptions,
                      AppColors.primaryRed)),
              const SizedBox(width: 16),
              Expanded(
                  child: _buildMetricCard(
                      'Active Subscriptions',
                      analytics['active_subscriptions']?.toString() ?? '0',
                      Icons.check_circle,
                      AppColors.success)),
              const SizedBox(width: 16),
              Expanded(
                  child: _buildMetricCard(
                      'Trial Subscriptions',
                      analytics['trial_subscriptions']?.toString() ?? '0',
                      Icons.timer,
                      AppColors.warning)),
              const SizedBox(width: 16),
              Expanded(
                  child: _buildMetricCard(
                      'Total Tenants',
                      analytics['total_tenants']?.toString() ?? '0',
                      Icons.business,
                      AppColors.primaryBlue)),
            ],
          );
        }
      },
    );
  }

  Widget _buildMetricCard(
      String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Live',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: color,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.mediumGray,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionAnalytics(dynamic analytics) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [AppColors.cardShadow],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.subscriptions, color: AppColors.primaryRed),
              const SizedBox(width: 12),
              Text(
                'Subscription Metrics',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (analytics['subscription_metrics'] != null)
            ...List.generate(
              (analytics['subscription_metrics'] as List).length,
              (index) => _buildSubscriptionMetricItem(
                  analytics['subscription_metrics'][index]),
            ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionMetricItem(dynamic metric) {
    final planName = metric['plan_name'] ?? 'Unknown Plan';
    final count = metric['count'] ?? 0;
    final percentage = metric['percentage'] ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              planName,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
          Expanded(
            flex: 3,
            child: LinearProgressIndicator(
              value: percentage / 100,
              backgroundColor: AppColors.borderGray,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.primaryRed),
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 60,
            child: Text(
              '$count subs',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryRed,
                  ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRevenueAnalytics(dynamic analytics) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [AppColors.cardShadow],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.monetization_on, color: AppColors.success),
              const SizedBox(width: 12),
              Text(
                'Revenue Analytics',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildRevenueItem(
                  'Total Revenue',
                  '₹${analytics['total_revenue'] ?? 0}',
                  AppColors.success,
                  Icons.trending_up,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildRevenueItem(
                  'Monthly Revenue',
                  '₹${analytics['monthly_revenue'] ?? 0}',
                  AppColors.primaryBlue,
                  Icons.calendar_month,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRevenueItem(
      String title, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.mediumGray,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildTenantAnalytics(dynamic analytics) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [AppColors.cardShadow],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.business, color: AppColors.primaryBlue),
              const SizedBox(width: 12),
              Text(
                'Tenant Analytics',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildTenantItem(
                  'New Tenants',
                  analytics['new_tenants']?.toString() ?? '0',
                  AppColors.success,
                  Icons.person_add,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildTenantItem(
                  'Churn Rate',
                  '${analytics['churn_rate'] ?? 0}%',
                  AppColors.error,
                  Icons.trending_down,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTenantItem(
      String title, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.mediumGray,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanDistribution(dynamic analytics) {
    final planDistribution =
        analytics['plan_distribution'] as Map<String, dynamic>? ?? {};

    if (planDistribution.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [AppColors.cardShadow],
        ),
        child: Column(
          children: [
            const Icon(Icons.pie_chart_outline,
                size: 48, color: AppColors.mediumGray),
            const SizedBox(height: 16),
            Text(
              'No Plan Distribution Data',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.mediumGray,
                  ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [AppColors.cardShadow],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.pie_chart, color: AppColors.warning),
              const SizedBox(width: 12),
              Text(
                'Plan Distribution',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...planDistribution.entries.map((entry) => _buildPlanDistributionItem(
                entry.key,
                entry.value?.toString() ?? '0',
              )),
        ],
      ),
    );
  }

  Widget _buildPlanDistributionItem(String planName, String count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: AppColors.chartColors[
                  planName.hashCode % AppColors.chartColors.length],
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              planName,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.lightGray,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              count,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
