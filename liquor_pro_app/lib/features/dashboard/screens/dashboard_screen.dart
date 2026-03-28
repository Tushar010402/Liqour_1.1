import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/theme/ios_design_tokens.dart';
import '../../../core/providers/shop_selection_provider.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../auth/providers/auth_provider.dart';
import '../../sales/screens/smart_sale_screen.dart';
import '../../reports/screens/reports_screen.dart';
import '../../customers/screens/customers_screen.dart';
import '../../finance/screens/finance_screen.dart';
import '../../inventory/screens/stock_adjustment_screen.dart';
import '../../inventory/screens/inventory_tree_screen.dart';
import '../../inventory/screens/products_list_screen.dart';
import '../../inventory/screens/brand_catalog_modern_screen.dart';
import '../../notifications/screens/notifications_center_screen.dart';
import '../../finance_matrix/screens/finance_matrix_screen.dart';
import '../../theft_detection/screens/theft_detection_screen.dart';
import '../../tips/screens/tips_screen.dart';
import '../../physical_audit/screens/physical_audit_screen.dart';
import '../../sales/screens/sales_history_screen.dart';
import '../../inventory/screens/stock_purchase_history_screen.dart';
import '../widgets/stat_card.dart';
import '../widgets/quick_action_button.dart';
import '../providers/dashboard_provider.dart';
import '../models/dashboard_metrics.dart';
import '../models/dashboard_summary.dart';
import '../../inventory/providers/product_provider.dart';
import 'package:intl/intl.dart';
import '../../../core/widgets/modern_skeleton_loader.dart';
import '../../../core/widgets/modern_error_banner.dart';
import '../../../core/widgets/modern_pull_to_refresh.dart';

/// Dashboard Screen - Manager/Admin Summary View
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
      // Single API call loads all dashboard data (summary + metrics)
      context.read<DashboardProvider>().loadDashboard();
    });
  }

  Future<void> _handleRefresh() async {
    await context.read<DashboardProvider>().refreshDashboard();
  }

  String _formatCurrency(double amount) {
    final formatter = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '\u20B9',
      decimalDigits: 0,
    );
    return formatter.format(amount);
  }

  void _showDateFilterPicker(BuildContext context, DashboardProvider provider) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Select Date Range',
              style: AppTextStyles.h5,
            ),
            const SizedBox(height: 16),
            ...DateFilterOption.values.map((option) {
              if (option == DateFilterOption.custom) {
                return ListTile(
                  leading: Icon(
                    Icons.date_range,
                    color: provider.dateFilter == option ? cs.primary : cs.onSurfaceVariant,
                  ),
                  title: Text(option.label),
                  trailing: provider.dateFilter == option
                      ? Icon(Icons.check, color: cs.primary)
                      : null,
                  onTap: () async {
                    Navigator.pop(context);
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                      initialDateRange: provider.customStartDate != null && provider.customEndDate != null
                          ? DateTimeRange(start: provider.customStartDate!, end: provider.customEndDate!)
                          : DateTimeRange(
                              start: DateTime.now().subtract(const Duration(days: 7)),
                              end: DateTime.now(),
                            ),
                    );
                    if (picked != null) {
                      provider.setCustomDateRange(picked.start, picked.end);
                    }
                  },
                );
              }
              return ListTile(
                leading: Icon(
                  _getDateFilterIcon(option),
                  color: provider.dateFilter == option ? cs.primary : cs.onSurfaceVariant,
                ),
                title: Text(option.label),
                trailing: provider.dateFilter == option
                    ? Icon(Icons.check, color: cs.primary)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  provider.setDateFilter(option);
                },
              );
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  IconData _getDateFilterIcon(DateFilterOption option) {
    switch (option) {
      case DateFilterOption.today:
        return Icons.today;
      case DateFilterOption.yesterday:
        return Icons.event;
      case DateFilterOption.last7Days:
        return Icons.date_range;
      case DateFilterOption.last30Days:
        return Icons.calendar_month;
      case DateFilterOption.thisMonth:
        return Icons.calendar_today;
      case DateFilterOption.custom:
        return Icons.edit_calendar;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;

    return Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
        final userRole = authProvider.currentUser?.role ?? '';
        final hasManagerAccess = ['admin', 'manager', 'assistant_manager'].contains(userRole);

        return Scaffold(
          appBar: hasManagerAccess
              ? _buildManagerAppBar(context)
              : CustomAppBar(
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
              return ModernPullToRefresh(
                onRefresh: _handleRefresh,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.all(iOSDesignTokens.space16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Manager/Admin Summary View
                      if (hasManagerAccess) ...[
                        // Shop Filter Chips
                        _buildShopFilterChips(context, dashboardProvider),
                        const SizedBox(height: 12),

                        // 4 Summary Cards: Payment, Purchase, Sale, Expense
                        _buildSummaryMetricsCards(context, dashboardProvider, isTablet),
                        const SizedBox(height: 16),

                        // Pending Approvals Section
                        _buildPendingSection(context, dashboardProvider),
                        const SizedBox(height: 16),

                        // Payment Breakdown (from original API)
                        _buildPaymentBreakdownSection(dashboardProvider),
                        const SizedBox(height: 16),

                        // Team Status (per-shop breakdown)
                        _buildTeamStatusSection(dashboardProvider),
                        const SizedBox(height: 16),

                        // Alerts
                        _buildAlertsSection(dashboardProvider),
                        const SizedBox(height: 16),
                      ] else ...[
                        // Simple dashboard for salesman/owner
                        _buildSimpleDashboard(context, dashboardProvider, authProvider, isTablet),
                      ],

                      // Quick Actions (visible to all)
                      _buildQuickActionsSection(context),
                      const SizedBox(height: 20),

                      // Inventory Management (visible to all)
                      _buildInventoryManagementSection(context),
                      const SizedBox(height: 20),

                      // Advanced Tools (some items manager-only)
                      _buildAdvancedToolsSection(context, authProvider),

                      // Recent Activity
                      _buildRecentActivitySection(dashboardProvider),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildManagerAppBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CustomAppBar(
      title: 'Dashboard',
      actions: [
        Consumer<DashboardProvider>(
          builder: (context, provider, _) {
            return TextButton.icon(
              onPressed: () => _showDateFilterPicker(context, provider),
              icon: Icon(Icons.calendar_today, size: 16, color: cs.primary),
              label: Text(
                provider.dateFilterLabel,
                style: AppTextStyles.caption.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          },
        ),
        IconButton(
          icon: Icon(Icons.notifications_outlined, color: cs.primary),
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
    );
  }

  Widget _buildShopFilterChips(BuildContext context, DashboardProvider dashboardProvider) {
    final cs = Theme.of(context).colorScheme;
    return Consumer<ShopSelectionProvider>(
      builder: (context, shopProvider, _) {
        final shops = shopProvider.shops;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              // "All" chip - Compact
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: const Text('All', style: TextStyle(fontSize: 13)),
                  selected: dashboardProvider.selectedShopId == null,
                  onSelected: (_) {
                    dashboardProvider.setSelectedShop(null);
                  },
                  selectedColor: cs.primary.withValues(alpha: 0.2),
                  checkmarkColor: cs.primary,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  labelStyle: TextStyle(
                    fontSize: 13,
                    color: dashboardProvider.selectedShopId == null
                        ? cs.primary
                        : cs.onSurface,
                    fontWeight: dashboardProvider.selectedShopId == null
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ),
              // Shop chips - Compact
              ...shops.map((shop) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: Text(shop.name, style: const TextStyle(fontSize: 13)),
                  selected: dashboardProvider.selectedShopId == shop.id,
                  onSelected: (_) {
                    dashboardProvider.setSelectedShop(shop.id);
                  },
                  selectedColor: cs.primary.withValues(alpha: 0.2),
                  checkmarkColor: cs.primary,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  labelStyle: TextStyle(
                    fontSize: 13,
                    color: dashboardProvider.selectedShopId == shop.id
                        ? cs.primary
                        : cs.onSurface,
                    fontWeight: dashboardProvider.selectedShopId == shop.id
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              )),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSummaryMetricsCards(BuildContext context, DashboardProvider provider, bool isTablet) {
    if (provider.isMetricsLoading) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: CardSkeleton(height: 100)),
              const SizedBox(width: 12),
              Expanded(child: CardSkeleton(height: 100)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: CardSkeleton(height: 100)),
              const SizedBox(width: 12),
              Expanded(child: CardSkeleton(height: 100)),
            ],
          ),
        ],
      );
    }

    if (provider.metricsError != null) {
      return ModernErrorBanner(
        message: provider.metricsError!,
        actionLabel: 'Retry',
        onAction: () => provider.loadDashboard(),
      );
    }

    final summary = provider.summary;
    if (summary == null) {
      return const SizedBox.shrink();
    }

    final revenue = summary.totalRevenue;
    final sale = summary.todaysSales.totalAmount;
    final pendingAmount = summary.todaysSales.pendingAmount;
    final credit = summary.creditAmount;

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: isTablet ? 1.5 : 1.5,
      children: [
        StatCard(
          title: 'Revenue',
          value: _formatCurrency(revenue),
          subtitle: '${summary.todaysSales.totalSales} transactions',
          icon: Icons.payments_outlined,
          color: AppColors.success,
          onTap: () => _showPaymentDetails(context),
        ),
        StatCard(
          title: 'Sales',
          value: _formatCurrency(sale),
          subtitle: '${summary.todaysSales.approvedSales} approved',
          icon: Icons.point_of_sale,
          color: AppColors.salesColor,
          onTap: () => _navigateToSalesHistory(context),
        ),
        StatCard(
          title: 'Pending',
          value: _formatCurrency(pendingAmount),
          subtitle: '${summary.pendingSales} awaiting approval',
          icon: Icons.pending_outlined,
          color: AppColors.warning,
          onTap: () => _navigateToSalesHistory(context),
        ),
        StatCard(
          title: 'Credit',
          value: _formatCurrency(credit),
          subtitle: 'Outstanding',
          icon: Icons.account_balance_wallet_outlined,
          color: AppColors.error,
          onTap: () => _navigateToExpenses(context),
        ),
      ],
    );
  }

  Widget _buildPaymentBreakdownSection(DashboardProvider dashboardProvider) {
    final cs = Theme.of(context).colorScheme;
    if (dashboardProvider.summary == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Payment Breakdown'),
        const SizedBox(height: 12),
        Container(
          padding: EdgeInsets.all(iOSDesignTokens.space16),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
            border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
          ),
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
                cs.primary,
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
      ],
    );
  }

  Widget _buildSimpleDashboard(
    BuildContext context,
    DashboardProvider dashboardProvider,
    AuthProvider authProvider,
    bool isTablet,
  ) {
    final cs = Theme.of(context).colorScheme;
    final crossAxisCount = isTablet ? 4 : 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Welcome Message
        Text(
          'Welcome back,',
          style: AppTextStyles.bodyMedium.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          authProvider.currentUser?.displayName ?? 'User',
          style: AppTextStyles.h3,
        ),
        const SizedBox(height: 24),

        // Error Banner
        if (dashboardProvider.errorMessage != null) ...[
          ModernErrorBanner(
            message: dashboardProvider.errorMessage!,
            actionLabel: 'Retry',
            onAction: () => dashboardProvider.loadDashboard(),
          ),
          const SizedBox(height: 16),
        ],

        // Dynamic overview header
        Consumer<DashboardProvider>(
          builder: (context, dp, _) => _buildSectionHeader('${dp.dateFilterLabel} Overview'),
        ),
        const SizedBox(height: 12),

        if (dashboardProvider.isLoading)
          Column(
            children: [
              Row(
                children: [
                  Expanded(child: CardSkeleton(height: 100)),
                  const SizedBox(width: 12),
                  Expanded(child: CardSkeleton(height: 100)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: CardSkeleton(height: 100)),
                  const SizedBox(width: 12),
                  Expanded(child: CardSkeleton(height: 100)),
                ],
              ),
            ],
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
                value: '\u20B90',
                subtitle: '0 orders',
                icon: Icons.currency_rupee_rounded,
                color: AppColors.salesColor,
              ),
              StatCard(
                title: 'Approved',
                value: '\u20B90',
                subtitle: '0 orders',
                icon: Icons.check_circle_outline,
                color: AppColors.success,
              ),
              StatCard(
                title: 'Pending',
                value: '0',
                subtitle: '\u20B90',
                icon: Icons.pending_outlined,
                color: AppColors.warning,
              ),
              StatCard(
                title: 'Returns',
                value: '\u20B90',
                subtitle: '0 items',
                icon: Icons.assignment_return_outlined,
                color: AppColors.error,
              ),
            ],
          ),

        // Payment Breakdown for simple dashboard
        if (dashboardProvider.summary != null) ...[
          const SizedBox(height: 24),
          _buildPaymentBreakdownSection(dashboardProvider),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildQuickActionsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Quick Actions'),
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
                    builder: (context) => const SmartSaleScreen(),
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
      ],
    );
  }

  Widget _buildInventoryManagementSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionHeader('Inventory Management'),
            TextButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const InventoryTreeScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.arrow_forward, size: 16),
              label: const Text('View All'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Consumer<ProductProvider>(
          builder: (context, productProvider, _) {
            final lowStockCount = productProvider.lowStockCount;
            final totalProducts = productProvider.products.length;

            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.2,
              children: [
                QuickActionButton(
                  icon: Icons.account_tree,
                  label: 'Tree View',
                  color: Theme.of(context).colorScheme.primary,
                  subtitle: '$totalProducts products',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const InventoryTreeScreen(),
                      ),
                    );
                  },
                ),
                QuickActionButton(
                  icon: Icons.warning_amber,
                  label: 'Low Stock',
                  color: lowStockCount > 0 ? AppColors.error : AppColors.success,
                  subtitle: '$lowStockCount items',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ProductsListScreen(),
                      ),
                    );
                  },
                ),
                QuickActionButton(
                  icon: Icons.qr_code_scanner,
                  label: 'Quick Update',
                  color: AppColors.inventoryColor,
                  subtitle: 'Scan & Update',
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
                  icon: Icons.add_business,
                  label: 'Add Brands',
                  color: AppColors.success,
                  subtitle: 'Import catalog',
                  onTap: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const BrandCatalogModernScreen(),
                      ),
                    );

                    if (result == true && mounted) {
                      final productProvider = context.read<ProductProvider>();
                      final shopProvider = context.read<ShopSelectionProvider>();
                      final shopId = shopProvider.selectedShopId;
                      await productProvider.loadProducts(shopId: shopId);
                    }
                  },
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildAdvancedToolsSection(BuildContext context, AuthProvider authProvider) {
    final userRole = authProvider.currentUser?.role ?? '';
    final isManagerOrAdmin = userRole == 'admin' || userRole == 'manager';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Advanced Tools'),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.2,
          children: [
            QuickActionButton(
              icon: Icons.dashboard_customize,
              label: 'Finance Matrix',
              color: Theme.of(context).colorScheme.primary,
              subtitle: 'Unified Dashboard',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const FinanceMatrixScreen(),
                  ),
                );
              },
            ),
            QuickActionButton(
              icon: Icons.volunteer_activism,
              label: 'Tips',
              color: AppColors.success,
              subtitle: 'Manage Tips',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const TipsScreen(),
                  ),
                );
              },
            ),
            if (isManagerOrAdmin)
              QuickActionButton(
                icon: Icons.fact_check,
                label: 'Physical Audit',
                color: AppColors.info,
                subtitle: 'Cash & Inventory',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const PhysicalAuditScreen(),
                    ),
                  );
                },
              ),
            if (isManagerOrAdmin)
              QuickActionButton(
                icon: Icons.security,
                label: 'Theft Detection',
                color: AppColors.error,
                subtitle: 'Anomaly Alerts',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const TheftDetectionScreen(),
                    ),
                  );
                },
              ),
          ],
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildRecentActivitySection(DashboardProvider dashboardProvider) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionHeader('Recent Activity'),
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
          Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
              border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
            ),
            child: Column(
              children: dashboardProvider.summary!.recentSales
                  .take(5)
                  .map((activity) {
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _getActivityColor(activity.type)
                        .withValues(alpha: 0.1),
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
                    '${activity.shopName} \u2022 ${activity.salesmanName}',
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
                              .withValues(alpha: 0.1),
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
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
              border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.history,
                    size: 48,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No recent activity',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPaymentRow(String label, double amount, IconData icon, Color color) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                cs.primary.withValues(alpha: 0.15),
                cs.primary.withValues(alpha: 0.06),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: cs.primary, size: 20),
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
        return Theme.of(context).colorScheme.primary;
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

  // ========== Navigation Methods ==========

  /// Navigate to Sales History screen with selected shop filter
  void _navigateToSalesHistory(BuildContext context) {
    final dashboardProvider = context.read<DashboardProvider>();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SalesHistoryScreen(
          shopId: dashboardProvider.selectedShopId,
        ),
      ),
    );
  }

  /// Navigate to Stock Purchase History screen with selected shop filter
  void _navigateToPurchaseHistory(BuildContext context) {
    final dashboardProvider = context.read<DashboardProvider>();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StockPurchaseHistoryScreen(
          shopId: dashboardProvider.selectedShopId,
        ),
      ),
    );
  }

  /// Navigate to Expenses screen
  void _navigateToExpenses(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const FinanceScreen(),
      ),
    );
  }

  /// Show Payment Details in a modal bottom sheet
  void _showPaymentDetails(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dashboardProvider = context.read<DashboardProvider>();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Payment Details',
                style: AppTextStyles.h5,
              ),
              const SizedBox(height: 20),
              if (dashboardProvider.summary != null) ...[
                _buildPaymentDetailRow(
                  'Cash',
                  dashboardProvider.summary!.cashAmount,
                  Icons.money,
                  AppColors.success,
                ),
                const Divider(height: 24),
                _buildPaymentDetailRow(
                  'Card',
                  dashboardProvider.summary!.cardAmount,
                  Icons.credit_card,
                  AppColors.info,
                ),
                const Divider(height: 24),
                _buildPaymentDetailRow(
                  'UPI',
                  dashboardProvider.summary!.upiAmount,
                  Icons.qr_code,
                  cs.primary,
                ),
                const Divider(height: 24),
                _buildPaymentDetailRow(
                  'Credit',
                  dashboardProvider.summary!.creditAmount,
                  Icons.account_balance_wallet,
                  AppColors.warning,
                ),
              ] else ...[
                const Center(
                  child: Text('No payment data available'),
                ),
              ],
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentDetailRow(String label, double amount, IconData icon, Color color) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                cs.primary.withValues(alpha: 0.15),
                cs.primary.withValues(alpha: 0.06),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: cs.primary, size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w500),
          ),
        ),
        Text(
          _formatCurrency(amount),
          style: AppTextStyles.h5.copyWith(color: cs.primary),
        ),
      ],
    );
  }

  // ========== Pending Section ==========

  /// Build the Pending Approvals section
  Widget _buildPendingSection(BuildContext context, DashboardProvider provider) {
    // Get pending counts from summary
    final pendingSales = provider.summary?.pendingSales ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionHeader('Quick Access'),
            TextButton.icon(
              onPressed: () => _showHistoryOptions(context),
              icon: const Icon(Icons.history, size: 18),
              label: const Text('View History'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildPendingCard(
          context: context,
          icon: Icons.point_of_sale,
          title: 'Pending Sales',
          count: pendingSales,
          color: AppColors.salesColor,
          onTap: () => _navigateToSalesHistory(context),
        ),
        const SizedBox(height: 8),
        _buildPendingCard(
          context: context,
          icon: Icons.shopping_cart_outlined,
          title: 'Stock Purchases',
          count: 0,
          color: AppColors.info,
          onTap: () => _navigateToPurchaseHistory(context),
          showCount: false,
        ),
        const SizedBox(height: 8),
        _buildPendingCard(
          context: context,
          icon: Icons.account_balance_wallet_outlined,
          title: 'Finance & Cash',
          count: 0,
          color: AppColors.financeColor,
          onTap: () => _navigateToExpenses(context),
          showCount: false,
        ),
      ],
    );
  }

  /// Build individual pending card
  Widget _buildPendingCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required int count,
    required Color color,
    required VoidCallback onTap,
    bool showCount = true,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: iOSDesignTokens.space6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
          child: Container(
            padding: EdgeInsets.symmetric(
                horizontal: iOSDesignTokens.space12,
                vertical: iOSDesignTokens.space12),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
              border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        cs.primary.withValues(alpha: 0.15),
                        cs.primary.withValues(alpha: 0.06),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: cs.primary, size: 20),
                ),
                SizedBox(width: iOSDesignTokens.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: AppTextStyles.bodyMedium.copyWith(
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface)),
                      if (showCount && count > 0)
                        Text('$count pending',
                            style: AppTextStyles.caption
                                .copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.5), size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Show History Options modal bottom sheet
  void _showHistoryOptions(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'View History',
              style: AppTextStyles.h5,
            ),
            const SizedBox(height: 8),
            Text(
              'Select which history to view',
              style: AppTextStyles.bodyMedium.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      cs.primary.withValues(alpha: 0.15),
                      cs.primary.withValues(alpha: 0.06),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.point_of_sale, color: cs.primary, size: 20),
              ),
              title: const Text(
                'Sale History',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('View all sales transactions'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(context);
                _navigateToSalesHistory(context);
              },
            ),
            const Divider(height: 1, indent: 72),
            ListTile(
              leading: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      cs.primary.withValues(alpha: 0.15),
                      cs.primary.withValues(alpha: 0.06),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.shopping_cart, color: cs.primary, size: 20),
              ),
              title: const Text(
                'Purchase History',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('View all stock purchases'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(context);
                _navigateToPurchaseHistory(context);
              },
            ),
            const Divider(height: 1, indent: 72),
            ListTile(
              leading: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      cs.primary.withValues(alpha: 0.15),
                      cs.primary.withValues(alpha: 0.06),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.account_balance, color: cs.primary, size: 20),
              ),
              title: const Text(
                'Finance History',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('View all financial transactions'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(context);
                _navigateToExpenses(context);
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // ========== Team Status Section ==========

  Widget _buildTeamStatusSection(DashboardProvider dashboardProvider) {
    final cs = Theme.of(context).colorScheme;
    final teamStatus = dashboardProvider.summary?.teamStatus;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(teamStatus != null
            ? 'Team Status (${teamStatus.totalSubmitted}/${teamStatus.totalSalesmen})'
            : 'Team Status'),
        const SizedBox(height: 12),
        if (teamStatus == null || teamStatus.shops.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
              border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.people_outline_rounded,
                    size: 40,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No team activity for this period',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          )
        else ...[
          // Submission rate bar
          if (teamStatus.totalSalesmen > 0) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
                border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Submission Rate',
                          style: AppTextStyles.caption.copyWith(color: cs.onSurfaceVariant)),
                      Text('${teamStatus.submissionRate.toStringAsFixed(0)}%',
                          style: AppTextStyles.bodyMedium.copyWith(
                              fontWeight: FontWeight.w600,
                              color: teamStatus.submissionRate >= 100
                                  ? AppColors.success
                                  : teamStatus.submissionRate >= 50
                                      ? AppColors.warning
                                      : AppColors.error)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: teamStatus.submissionRate / 100,
                      backgroundColor: cs.outline.withValues(alpha: 0.2),
                      valueColor: AlwaysStoppedAnimation(
                        teamStatus.submissionRate >= 100
                            ? AppColors.success
                            : teamStatus.submissionRate >= 50
                                ? AppColors.warning
                                : AppColors.error,
                      ),
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          // Per-shop salesman cards
          ...teamStatus.shops.map((shop) => _buildShopTeamCard(shop)),
        ],
      ],
    );
  }

  Widget _buildShopTeamCard(ShopSubmissionSummary shop) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: EdgeInsets.all(iOSDesignTokens.space12),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
          border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.store, color: cs.primary, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    shop.shopName,
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: shop.missingCount == 0
                        ? AppColors.success.withValues(alpha: 0.1)
                        : AppColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${shop.submittedCount}/${shop.submittedCount + shop.missingCount}',
                    style: AppTextStyles.caption.copyWith(
                      color: shop.missingCount == 0 ? AppColors.success : AppColors.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...shop.salesmen.map((salesman) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Icon(
                        salesman.status == 'submitted'
                            ? Icons.check_circle_rounded
                            : Icons.cancel_rounded,
                        size: 16,
                        color: salesman.status == 'submitted'
                            ? AppColors.success
                            : AppColors.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          salesman.salesmanName,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                      if (salesman.status == 'submitted' && salesman.recordStatus != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: salesman.recordStatus == 'approved'
                                ? AppColors.success.withValues(alpha: 0.1)
                                : AppColors.warning.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            salesman.recordStatus!,
                            style: AppTextStyles.overline.copyWith(
                              color: salesman.recordStatus == 'approved'
                                  ? AppColors.success
                                  : AppColors.warning,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      if (salesman.status == 'submitted')
                        Text(
                          _formatCurrency(salesman.totalAmount),
                          style: AppTextStyles.priceSmall.copyWith(color: AppColors.success),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Missing',
                            style: AppTextStyles.caption.copyWith(
                                color: AppColors.error,
                                fontSize: 10,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  // ========== Alerts Section ==========

  Widget _buildAlertsSection(DashboardProvider dashboardProvider) {
    final cs = Theme.of(context).colorScheme;
    final pendingSales = dashboardProvider.summary?.pendingSales ?? 0;
    final pendingReturns = dashboardProvider.summary?.pendingReturns ?? 0;

    // Get low stock count from product provider
    final productProvider = context.watch<ProductProvider>();
    final lowStockCount = productProvider.lowStockCount;

    // Build alert items
    final alerts = <_AlertItem>[];

    if (pendingSales > 0) {
      alerts.add(_AlertItem(
        icon: Icons.pending_actions,
        message: '$pendingSales sales pending approval',
        color: AppColors.warning,
        onTap: () => _navigateToSalesHistory(context),
      ));
    }

    if (pendingReturns > 0) {
      alerts.add(_AlertItem(
        icon: Icons.assignment_return,
        message: '$pendingReturns returns pending',
        color: AppColors.warning,
        onTap: () {},
      ));
    }

    // Alert: missing team submissions
    final totalMissing = dashboardProvider.summary?.teamStatus?.totalMissing ?? 0;
    if (totalMissing > 0) {
      alerts.add(_AlertItem(
        icon: Icons.person_off,
        message: '$totalMissing salesman${totalMissing > 1 ? 's' : ''} missing entry',
        color: AppColors.error,
        onTap: () {},
      ));
    }

    if (lowStockCount > 0) {
      alerts.add(_AlertItem(
        icon: Icons.warning_amber,
        message: '$lowStockCount items low on stock',
        color: AppColors.error,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const ProductsListScreen(),
            ),
          );
        },
      ));
    }

    if (alerts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Alerts'),
        const SizedBox(height: 12),
        ...alerts.map((alert) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: alert.onTap,
                  borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: iOSDesignTokens.space12,
                      vertical: iOSDesignTokens.space10,
                    ),
                    decoration: BoxDecoration(
                      color: alert.color.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
                      border: Border.all(color: alert.color.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        Icon(alert.icon, color: alert.color, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            alert.message,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: cs.onSurface,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Icon(Icons.chevron_right, color: alert.color.withValues(alpha: 0.6), size: 20),
                      ],
                    ),
                  ),
                ),
              ),
            )),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: cs.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        SizedBox(width: iOSDesignTokens.space8),
        Text(title,
            style: AppTextStyles.bodyMedium.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            )),
      ],
    );
  }
}

/// Simple data class for alert items
class _AlertItem {
  final IconData icon;
  final String message;
  final Color color;
  final VoidCallback onTap;

  _AlertItem({
    required this.icon,
    required this.message,
    required this.color,
    required this.onTap,
  });
}
