import 'package:flutter/material.dart';
import 'package:provider/provider.dart' as provider_pkg;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/theme/ios_design_tokens.dart';
import '../../../core/widgets/home_screen_components.dart';
import '../../../core/providers/shop_selection_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import '../../finance/providers/cash_provider.dart';
import '../../sales/screens/daily_sales_entry_screen.dart';
import '../../sales/screens/simple_sales_history.dart';
import '../../inventory/screens/inventory_screen.dart';
import '../../finance/screens/cash_dashboard_screen.dart';
import '../../admin/screens/user_management_screen.dart';
import '../../reports/screens/reports_screen.dart';
import '../../settings/screens/settings_screen.dart';
import '../../inventory/screens/stock_update_approvals_screen.dart';

/// Manager Home Screen — approvals hero, shop comparison, team status, alerts.
class ManagerHomeScreen extends ConsumerStatefulWidget {
  const ManagerHomeScreen({super.key});

  @override
  ConsumerState<ManagerHomeScreen> createState() => _ManagerHomeScreenState();
}

class _ManagerHomeScreenState extends ConsumerState<ManagerHomeScreen> {
  bool _initialLoadDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    final shopProvider =
        provider_pkg.Provider.of<ShopSelectionProvider>(context, listen: false);
    final dashboardProvider =
        provider_pkg.Provider.of<DashboardProvider>(context, listen: false);
    final shopId = shopProvider.selectedShopId;
    if (shopId == null) return;
    await Future.wait([
      dashboardProvider.loadDashboard(),
      dashboardProvider.loadMetrics(shopId: shopId),
    ]);
    if (mounted) setState(() => _initialLoadDone = true);
  }

  Future<void> _refreshData() async => _loadData();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(horizontal: iOSDesignTokens.space16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                SizedBox(height: iOSDesignTokens.space12),
                _buildApprovalsHero(),
                _buildYesterdaySummary(),
                _buildTeamStatus(),
                _buildAlerts(),
                SizedBox(height: iOSDesignTokens.space16),
                _buildActionGrid(),
                SizedBox(height: iOSDesignTokens.space24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final auth = provider_pkg.Provider.of<AuthProvider>(context);
    final shop = provider_pkg.Provider.of<ShopSelectionProvider>(context);

    return HomeScreenHeader(
      greeting: getTimeGreeting(),
      userName: auth.currentUser?.firstName ?? 'User',
      shopName: shop.selectedShopName,
      onSettingsTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
      onShopTap: shop.shops.length > 1
          ? () => showShopPickerSheet(
                context,
                shops: shop.shops,
                selectedShopId: shop.selectedShopId,
                onSelect: (s) => shop.selectShop(s),
              )
          : null,
    );
  }

  Widget _buildApprovalsHero() {
    final shopProvider =
        provider_pkg.Provider.of<ShopSelectionProvider>(context);
    final shopId = shopProvider.selectedShopId;

    return provider_pkg.Consumer<DashboardProvider>(
      builder: (context, dashboardProvider, _) {
        final pendingSalesCount = dashboardProvider.summary?.pendingSales ?? 0;

        return Consumer(
          builder: (context, ref, _) {
            int pendingCashCount = 0;
            if (shopId != null) {
              final cashAsync = ref.watch(pendingCollectionsProvider(shopId));
              if (cashAsync.hasValue) {
                pendingCashCount = cashAsync.value?.length ?? 0;
              }
            }

            return Column(
              children: [
                Row(
                  children: [
                    HomeApprovalCard(
                      title: 'Daily Sales',
                      pendingCount: pendingSalesCount,
                      icon: Icons.receipt_long_rounded,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => Scaffold(
                            appBar: AppBar(
                              title: const Text('Daily Sales'),
                              elevation: 0,
                            ),
                            body: const SimpleSalesHistory(),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: iOSDesignTokens.space12),
                    HomeApprovalCard(
                      title: 'Cash',
                      pendingCount: pendingCashCount,
                      icon: Icons.account_balance_wallet_rounded,
                      onTap: () {
                        if (shopId == null) return;
                        final auth = provider_pkg.Provider.of<AuthProvider>(context,
                            listen: false);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CashDashboardScreen(
                              shopId: shopId,
                              userRole: auth.currentUser?.role ?? 'manager',
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                SizedBox(height: iOSDesignTokens.space12),
                SizedBox(
                  width: double.infinity,
                  child: HomeApprovalCard(
                    title: 'Stock Updates',
                    pendingCount: 0,
                    icon: Icons.inventory_2_rounded,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const StockUpdateApprovalsScreen(),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildYesterdaySummary() {
    return provider_pkg.Consumer<DashboardProvider>(
      builder: (context, provider, _) {
        final summary = provider.summary;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const HomeSectionHeader(title: "Yesterday's Summary"),
            if (summary != null && summary.shopSummaries.isNotEmpty)
              HomeShopComparisonTable(
                shops: summary.shopSummaries
                    .map((s) => ShopMetricData(
                          shopName: s.shopName,
                          salesCount: s.totalSales,
                          totalAmount: s.totalAmount,
                          pendingCount: s.pendingSales,
                        ))
                    .toList(),
              )
            else if (provider.isLoading)
              Padding(
                padding: EdgeInsets.all(iOSDesignTokens.space16),
                child: const Center(child: CircularProgressIndicator.adaptive()),
              )
            else
              Padding(
                padding: EdgeInsets.symmetric(vertical: iOSDesignTokens.space12),
                child: Text('No shop data available',
                    style: AppTextStyles.caption
                        .copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
          ],
        );
      },
    );
  }

  Widget _buildTeamStatus() {
    return provider_pkg.Consumer<DashboardProvider>(
      builder: (context, dashboardProvider, _) {
        final teamStatus = dashboardProvider.summary?.teamStatus;
        if (teamStatus == null && !_initialLoadDone) {
          return const SizedBox.shrink();
        }
        if (teamStatus == null || teamStatus.shops.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const HomeSectionHeader(title: 'Team Status'),
              Padding(
                padding: EdgeInsets.symmetric(vertical: iOSDesignTokens.space12),
                child: Text('No team data available',
                    style: AppTextStyles.caption
                        .copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HomeSectionHeader(
              title: 'Team Status (${teamStatus.totalSubmitted}/${teamStatus.totalSalesmen})',
            ),
            ...teamStatus.shops.expand((shop) => [
              Padding(
                padding: EdgeInsets.only(
                    top: iOSDesignTokens.space8, bottom: iOSDesignTokens.space4),
                child: Text(shop.shopName,
                    style: AppTextStyles.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
              ...shop.salesmen.map((salesman) => HomeTeamStatusRow(
                    personName: salesman.salesmanName,
                    hasSubmitted: salesman.status == 'submitted',
                    amount: salesman.status == 'submitted' ? salesman.totalAmount : null,
                  )),
            ]),
          ],
        );
      },
    );
  }

  Widget _buildAlerts() {
    return provider_pkg.Consumer<DashboardProvider>(
      builder: (context, dashboardProvider, _) {
        final alerts = <Widget>[];
        final summary = dashboardProvider.summary;
        final teamStatus = summary?.teamStatus;

        // Alert: pending sales
        final pendingSales = summary?.pendingSales ?? 0;
        if (pendingSales > 0) {
          alerts.add(HomeExceptionAlert(
            message: '$pendingSales sale${pendingSales > 1 ? 's' : ''} pending approval',
            severity: ExceptionSeverity.warning,
          ));
        }

        // Alert: missing submissions
        final totalMissing = teamStatus?.totalMissing ?? 0;
        if (totalMissing > 0) {
          alerts.add(HomeExceptionAlert(
            message: '$totalMissing salesman${totalMissing > 1 ? '' : ''} missing yesterday\'s entry',
            severity: ExceptionSeverity.warning,
          ));
        }

        if (alerts.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const HomeSectionHeader(title: 'Alerts'),
            ...alerts,
          ],
        );
      },
    );
  }

  Widget _buildActionGrid() {
    final shopProvider =
        provider_pkg.Provider.of<ShopSelectionProvider>(context);
    final authProvider = provider_pkg.Provider.of<AuthProvider>(context);
    final shopId = shopProvider.selectedShopId;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: HomeActionButton(
                label: 'Enter Sale',
                icon: Icons.point_of_sale_rounded,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          const DailySalesEntryScreen(showHeader: true)),
                ),
              ),
            ),
            SizedBox(width: iOSDesignTokens.space8),
            Expanded(
              child: HomeActionButton(
                label: 'Cash',
                icon: Icons.account_balance_wallet_rounded,
                color: AppColors.warning,
                onTap: () {
                  if (shopId == null) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CashDashboardScreen(
                        shopId: shopId,
                        userRole: authProvider.currentUser?.role ?? 'manager',
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        SizedBox(height: iOSDesignTokens.space8),
        Row(
          children: [
            Expanded(
              child: HomeActionButton(
                label: 'Team',
                icon: Icons.people_rounded,
                color: AppColors.info,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const UserManagementScreen()),
                ),
              ),
            ),
            SizedBox(width: iOSDesignTokens.space8),
            Expanded(
              child: HomeActionButton(
                label: 'More',
                icon: Icons.grid_view_rounded,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                onTap: () => _showMoreSheet(context),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showMoreSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.all(iOSDesignTokens.space16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              SizedBox(height: iOSDesignTokens.space16),
              _MoreSheetItem(
                icon: Icons.bar_chart_rounded,
                label: 'Reports',
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const ReportsScreen()));
                },
              ),
              _MoreSheetItem(
                icon: Icons.inventory_2_rounded,
                label: 'Inventory',
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const InventoryScreen()));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreSheetItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MoreSheetItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(label, style: AppTextStyles.bodyMedium),
      trailing: Icon(Icons.chevron_right_rounded,
          color: Theme.of(context).colorScheme.onSurfaceVariant, size: 20),
      onTap: onTap,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(iOSDesignTokens.radiusSmall)),
    );
  }
}
