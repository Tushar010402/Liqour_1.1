import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../controllers/dashboard_provider.dart';
import '../../authentication/controllers/auth_provider.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DashboardProvider>().loadDashboard();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return RefreshIndicator(
      onRefresh: () => context.read<DashboardProvider>().refresh(),
      child: Consumer<DashboardProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && !provider.hasData) {
            return _buildLoadingState();
          }

          if (provider.hasError) {
            return _buildErrorState(provider.errorMessage!);
          }

          if (provider.hasData) {
            return _buildDashboardContent(provider);
          }

          return _buildEmptyState();
        },
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryRed),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
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
              'Failed to load dashboard',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppColors.primaryBlack,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.mediumGray,
                  ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () =>
                  context.read<DashboardProvider>().loadDashboard(),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.dashboard,
            size: 64,
            color: AppColors.mediumGray,
          ),
          const SizedBox(height: 16),
          Text(
            'No data available',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppColors.mediumGray,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardContent(DashboardProvider provider) {
    final data = provider.data!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isTablet = constraints.maxWidth > 600;
        final isDesktop = constraints.maxWidth > 1024;

        return SingleChildScrollView(
          padding: EdgeInsets.all(isDesktop ? 24 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Key Metrics Cards
              _buildResponsiveMetricsCards(data, isTablet, isDesktop),

              const SizedBox(height: 24),

              // Charts Row (for larger screens)
              if (isTablet) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: _buildRevenueChart(data),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 1,
                      child: _buildSubscriptionMetrics(data),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildRecentActivity(data),
              ] else ...[
                // Mobile layout - stacked
                _buildRevenueChart(data),
                const SizedBox(height: 24),
                _buildSubscriptionMetrics(data),
                const SizedBox(height: 24),
                _buildRecentActivity(data),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildResponsiveMetricsCards(
      DashboardData data, bool isTablet, bool isDesktop) {
    final metrics = [
      {
        'title': AppStrings.totalRevenue,
        'value': '₹${NumberFormat('#,##,###').format(data.totalRevenue)}',
        'icon': Icons.trending_up,
        'color': AppColors.success,
      },
      {
        'title': AppStrings.activeSubscriptions,
        'value': data.activeSubscriptions.toString(),
        'icon': Icons.subscriptions,
        'color': AppColors.info,
      },
      {
        'title': AppStrings.totalTenants,
        'value': data.totalTenants.toString(),
        'icon': Icons.business,
        'color': AppColors.warning,
      },
      {
        'title': AppStrings.systemHealth,
        'value': data.systemHealth.toUpperCase(),
        'icon': Icons.health_and_safety,
        'color': data.systemHealth == 'healthy'
            ? AppColors.success
            : AppColors.error,
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Key Metrics',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 16),
        if (isDesktop) ...[
          // Desktop: 4 columns
          Row(
            children: metrics.map((metric) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _buildMetricCard(
                    title: metric['title'] as String,
                    value: metric['value'] as String,
                    icon: metric['icon'] as IconData,
                    color: metric['color'] as Color,
                  ),
                ),
              );
            }).toList(),
          ),
        ] else if (isTablet) ...[
          // Tablet: 2 rows, 2 columns each
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  title: metrics[0]['title'] as String,
                  value: metrics[0]['value'] as String,
                  icon: metrics[0]['icon'] as IconData,
                  color: metrics[0]['color'] as Color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  title: metrics[1]['title'] as String,
                  value: metrics[1]['value'] as String,
                  icon: metrics[1]['icon'] as IconData,
                  color: metrics[1]['color'] as Color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  title: metrics[2]['title'] as String,
                  value: metrics[2]['value'] as String,
                  icon: metrics[2]['icon'] as IconData,
                  color: metrics[2]['color'] as Color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  title: metrics[3]['title'] as String,
                  value: metrics[3]['value'] as String,
                  icon: metrics[3]['icon'] as IconData,
                  color: metrics[3]['color'] as Color,
                ),
              ),
            ],
          ),
        ] else ...[
          // Mobile: 2 rows, 2 columns each
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  title: metrics[0]['title'] as String,
                  value: metrics[0]['value'] as String,
                  icon: metrics[0]['icon'] as IconData,
                  color: metrics[0]['color'] as Color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  title: metrics[1]['title'] as String,
                  value: metrics[1]['value'] as String,
                  icon: metrics[1]['icon'] as IconData,
                  color: metrics[1]['color'] as Color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  title: metrics[2]['title'] as String,
                  value: metrics[2]['value'] as String,
                  icon: metrics[2]['icon'] as IconData,
                  color: metrics[2]['color'] as Color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  title: metrics[3]['title'] as String,
                  value: metrics[3]['value'] as String,
                  icon: metrics[3]['icon'] as IconData,
                  color: metrics[3]['color'] as Color,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                Icon(
                  Icons.more_vert,
                  color: AppColors.mediumGray,
                  size: 16,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryBlack,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.mediumGray,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRevenueChart(DashboardData data) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  AppStrings.revenueGrowth,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.successLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.trending_up,
                        size: 14,
                        color: AppColors.success,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '+12.5%',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.success,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() < data.revenueChart.length) {
                            return Text(
                              data.revenueChart[value.toInt()].month,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: AppColors.mediumGray,
                                  ),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: data.revenueChart.asMap().entries.map((entry) {
                        return FlSpot(
                            entry.key.toDouble(), entry.value.amount / 1000);
                      }).toList(),
                      isCurved: true,
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primaryRed,
                          AppColors.primaryRed.withValues(alpha: 0.3),
                        ],
                      ),
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            AppColors.primaryRed.withValues(alpha: 0.3),
                            AppColors.primaryRed.withValues(alpha: 0.1),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubscriptionMetrics(DashboardData data) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppStrings.subscriptionTrends,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 20),
            ...data.subscriptionMetrics
                .map((metric) => _buildSubscriptionMetricItem(metric)),
          ],
        ),
      ),
    );
  }

  Widget _buildSubscriptionMetricItem(SubscriptionMetric metric) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  metric.planName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              Text(
                '${metric.count} (${metric.percentage.toStringAsFixed(1)}%)',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.mediumGray,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: metric.percentage / 100,
            backgroundColor: AppColors.borderGray,
            valueColor: AlwaysStoppedAnimation<Color>(
              AppColors.chartColors[
                  metric.planName.hashCode % AppColors.chartColors.length],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentActivity(DashboardData data) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  AppStrings.recentActivity,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {},
                  child: const Text('View All'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...data.recentActivity
                .take(5)
                .map((activity) => _buildActivityItem(activity)),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityItem(ActivityItem activity) {
    IconData icon;
    Color iconColor;

    switch (activity.type) {
      case 'subscription':
        icon = Icons.subscriptions;
        iconColor = AppColors.success;
        break;
      case 'upgrade':
        icon = Icons.upgrade;
        iconColor = AppColors.info;
        break;
      case 'payment':
        icon = Icons.payment;
        iconColor = AppColors.warning;
        break;
      default:
        icon = Icons.notifications;
        iconColor = AppColors.mediumGray;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activity.title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                Text(
                  activity.description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.mediumGray,
                      ),
                ),
              ],
            ),
          ),
          Text(
            _formatTime(activity.timestamp),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.mediumGray,
                ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  void _showQuickActions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Quick Actions',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 20),
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 3,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 0.7,
              children: [
                _buildQuickActionItem(
                  icon: Icons.person_add,
                  label: 'Add Tenant',
                  onTap: () {
                    Navigator.pop(context);
                    // Navigate to add tenant
                  },
                ),
                _buildQuickActionItem(
                  icon: Icons.assignment_add,
                  label: 'New Plan',
                  onTap: () {
                    Navigator.pop(context);
                    // Navigate to add plan
                  },
                ),
                _buildQuickActionItem(
                  icon: Icons.local_offer,
                  label: 'Create Discount',
                  onTap: () {
                    Navigator.pop(context);
                    // Navigate to add discount
                  },
                ),
                _buildQuickActionItem(
                  icon: Icons.analytics,
                  label: 'View Reports',
                  onTap: () {
                    Navigator.pop(context);
                    // Navigate to analytics
                  },
                ),
                _buildQuickActionItem(
                  icon: Icons.settings,
                  label: 'Settings',
                  onTap: () {
                    Navigator.pop(context);
                    // Navigate to settings
                  },
                ),
                _buildQuickActionItem(
                  icon: Icons.help_outline,
                  label: 'Help',
                  onTap: () {
                    Navigator.pop(context);
                    // Show help
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.lightGray,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderGray),
        ),
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: AppColors.primaryRed,
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  void _handleLogout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text(AppStrings.confirmLogout),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(AppStrings.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<AuthProvider>().logout();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            child: const Text(AppStrings.logout),
          ),
        ],
      ),
    );
  }
}
