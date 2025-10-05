import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../auth/providers/auth_provider.dart';
import '../../sales/screens/new_sale_screen.dart';
import '../../reports/screens/reports_screen.dart';
import '../../customers/screens/customers_screen.dart';
import '../../finance/screens/finance_screen.dart';
import '../../inventory/screens/stock_adjustment_screen.dart';
import '../../notifications/screens/notifications_center_screen.dart';
import '../widgets/stat_card.dart';
import '../widgets/quick_action_button.dart';
import '../providers/dashboard_provider.dart';
import 'package:intl/intl.dart';

/// Dashboard Screen - Main overview with statistics
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DashboardProvider>().loadDashboard();
    });
  }

  Future<void> _handleRefresh() async {
    await context.read<DashboardProvider>().refreshDashboard();
  }

  String _formatCurrency(double amount) {
    final formatter = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    );
    return formatter.format(amount);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    final crossAxisCount = isTablet ? 4 : 2;

    return Scaffold(
      appBar: CustomAppBar(
        title: 'Dashboard',
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const NotificationsCenterScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: Consumer<DashboardProvider>(
        builder: (context, dashboardProvider, _) {
          return RefreshIndicator(
            onRefresh: _handleRefresh,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Welcome Message
                  Consumer<AuthProvider>(
                    builder: (context, authProvider, _) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Welcome back,',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            authProvider.currentUser?.displayName ?? 'User',
                            style: AppTextStyles.h3,
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),

                  // Error State
                  if (dashboardProvider.errorMessage != null) ...[
                    Card(
                      color: AppColors.error.withOpacity(0.1),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: AppColors.error),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Failed to load dashboard',
                                    style: AppTextStyles.h6.copyWith(color: AppColors.error),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    dashboardProvider.errorMessage!,
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: AppColors.error.withOpacity(0.8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: () => dashboardProvider.loadDashboard(),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Statistics Cards
                  Text(
                    'Today\'s Overview',
                    style: AppTextStyles.h5,
                  ),
                  const SizedBox(height: 12),

                  if (dashboardProvider.isLoading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (dashboardProvider.summary != null)
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: isTablet ? 1.5 : 1.5,
                      children: [
                        StatCard(
                          title: 'Total Sales',
                          value: _formatCurrency(
                            dashboardProvider.summary!.todaysSales.totalAmount,
                          ),
                          subtitle: '${dashboardProvider.summary!.todaysSales.totalSales} orders',
                          icon: Icons.currency_rupee_rounded,
                          color: AppColors.salesColor,
                        ),
                        StatCard(
                          title: 'Approved',
                          value: _formatCurrency(
                            dashboardProvider.summary!.todaysSales.approvedAmount,
                          ),
                          subtitle: '${dashboardProvider.summary!.todaysSales.approvedSales} orders',
                          icon: Icons.check_circle_outline,
                          color: AppColors.success,
                        ),
                        StatCard(
                          title: 'Pending',
                          value: '${dashboardProvider.summary!.pendingSales}',
                          subtitle: _formatCurrency(
                            dashboardProvider.summary!.todaysSales.pendingAmount,
                          ),
                          icon: Icons.pending_outlined,
                          color: AppColors.warning,
                        ),
                        StatCard(
                          title: 'Returns',
                          value: _formatCurrency(
                            dashboardProvider.summary!.todaysReturns.totalAmount,
                          ),
                          subtitle: '${dashboardProvider.summary!.todaysReturns.totalReturns} items',
                          icon: Icons.assignment_return_outlined,
                          color: AppColors.error,
                        ),
                      ],
                    )
                  else
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: isTablet ? 1.5 : 1.5,
                      children: [
                        StatCard(
                          title: 'Total Sales',
                          value: '₹0',
                          subtitle: '0 orders',
                          icon: Icons.currency_rupee_rounded,
                          color: AppColors.salesColor,
                        ),
                        StatCard(
                          title: 'Approved',
                          value: '₹0',
                          subtitle: '0 orders',
                          icon: Icons.check_circle_outline,
                          color: AppColors.success,
                        ),
                        StatCard(
                          title: 'Pending',
                          value: '0',
                          subtitle: '₹0',
                          icon: Icons.pending_outlined,
                          color: AppColors.warning,
                        ),
                        StatCard(
                          title: 'Returns',
                          value: '₹0',
                          subtitle: '0 items',
                          icon: Icons.assignment_return_outlined,
                          color: AppColors.error,
                        ),
                      ],
                    ),

                  // Payment Breakdown
                  if (dashboardProvider.summary != null) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Payment Breakdown',
                      style: AppTextStyles.h5,
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _buildPaymentRow(
                              'Cash',
                              dashboardProvider.summary!.cashAmount,
                              Icons.money,
                              AppColors.success,
                            ),
                            const Divider(height: 24),
                            _buildPaymentRow(
                              'Card',
                              dashboardProvider.summary!.cardAmount,
                              Icons.credit_card,
                              AppColors.info,
                            ),
                            const Divider(height: 24),
                            _buildPaymentRow(
                              'UPI',
                              dashboardProvider.summary!.upiAmount,
                              Icons.qr_code,
                              AppColors.primary,
                            ),
                            const Divider(height: 24),
                            _buildPaymentRow(
                              'Credit',
                              dashboardProvider.summary!.creditAmount,
                              Icons.account_balance_wallet,
                              AppColors.warning,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 32),

                  // Quick Actions
                  Text(
                    'Quick Actions',
                    style: AppTextStyles.h5,
                  ),
                  const SizedBox(height: 12),

                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 3,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    children: [
                      QuickActionButton(
                        icon: Icons.point_of_sale_rounded,
                        label: 'New Sale',
                        color: AppColors.salesColor,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const NewSaleScreen(),
                            ),
                          );
                        },
                      ),
                      QuickActionButton(
                        icon: Icons.add_box_rounded,
                        label: 'Add Stock',
                        color: AppColors.inventoryColor,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const StockAdjustmentScreen(),
                            ),
                          );
                        },
                      ),
                      QuickActionButton(
                        icon: Icons.account_balance_rounded,
                        label: 'Finance',
                        color: AppColors.financeColor,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const FinanceScreen(),
                            ),
                          );
                        },
                      ),
                      QuickActionButton(
                        icon: Icons.analytics_rounded,
                        label: 'Reports',
                        color: AppColors.reportsColor,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ReportsScreen(),
                            ),
                          );
                        },
                      ),
                      QuickActionButton(
                        icon: Icons.groups_rounded,
                        label: 'Customers',
                        color: AppColors.customersColor,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const CustomersScreen(),
                            ),
                          );
                        },
                      ),
                      QuickActionButton(
                        icon: Icons.tune_rounded,
                        label: 'Settings',
                        color: AppColors.settingsColor,
                        onTap: () {
                          // Navigate to settings tab (index 3)
                          DefaultTabController.of(context).animateTo(3);
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // Recent Activity
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Recent Activity',
                        style: AppTextStyles.h5,
                      ),
                      if (dashboardProvider.summary != null &&
                          dashboardProvider.summary!.recentSales.isNotEmpty)
                        TextButton(
                          onPressed: () {
                            // TODO: View all activity
                          },
                          child: const Text('View All'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (dashboardProvider.summary != null &&
                      dashboardProvider.summary!.recentSales.isNotEmpty)
                    Card(
                      child: Column(
                        children: dashboardProvider.summary!.recentSales
                            .take(5)
                            .map((activity) {
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _getActivityColor(activity.type)
                                  .withOpacity(0.1),
                              child: Icon(
                                _getActivityIcon(activity.type),
                                color: _getActivityColor(activity.type),
                                size: 20,
                              ),
                            ),
                            title: Text(
                              '${activity.type.toUpperCase()} #${activity.number}',
                              style: AppTextStyles.h6,
                            ),
                            subtitle: Text(
                              '${activity.shopName} • ${activity.salesmanName}',
                              style: AppTextStyles.bodySmall,
                            ),
                            trailing: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _formatCurrency(activity.amount),
                                  style: AppTextStyles.h6,
                                ),
                                const SizedBox(height: 2),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _getStatusColor(activity.status)
                                        .withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    activity.status,
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: _getStatusColor(activity.status),
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    )
                  else
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.history,
                                size: 48,
                                color: AppColors.textSecondary.withOpacity(0.5),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'No recent activity',
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPaymentRow(String label, double amount, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.bodyLarge,
          ),
        ),
        Text(
          _formatCurrency(amount),
          style: AppTextStyles.h6,
        ),
      ],
    );
  }

  Color _getActivityColor(String type) {
    switch (type.toLowerCase()) {
      case 'sale':
        return AppColors.success;
      case 'return':
        return AppColors.error;
      case 'daily_record':
        return AppColors.info;
      default:
        return AppColors.primary;
    }
  }

  IconData _getActivityIcon(String type) {
    switch (type.toLowerCase()) {
      case 'sale':
        return Icons.shopping_cart;
      case 'return':
        return Icons.assignment_return;
      case 'daily_record':
        return Icons.receipt_long;
      default:
        return Icons.receipt;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
      case 'completed':
        return AppColors.success;
      case 'pending':
        return AppColors.warning;
      case 'rejected':
      case 'cancelled':
        return AppColors.error;
      default:
        return AppColors.info;
    }
  }
}
