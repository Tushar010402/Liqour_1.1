import 'package:flutter/material.dart';
import 'package:provider/provider.dart' as provider_pkg;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/theme/ios_design_tokens.dart';
import '../../../core/widgets/home_screen_components.dart';
import '../../../core/providers/shop_selection_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../sales/providers/daily_sales_provider.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import '../../admin/providers/user_management_provider.dart';
import '../../finance/providers/cash_provider.dart';
import '../../sales/screens/daily_sales_entry_screen.dart';
import '../../sales/screens/simple_sales_history.dart';
import '../../finance/screens/cash_dashboard_screen.dart';
import '../../admin/screens/user_management_screen.dart';
import '../../admin/screens/shops_screen.dart';
import '../../settings/screens/settings_screen.dart';
import '../../sales/screens/daily_sales_screen.dart';
import '../../reports/screens/purcha_report_screen.dart';
import '../../finance/screens/finance_screen.dart';

/// Admin Home Screen — same as Manager + Business Health section + Shops button.
class AdminHomeScreen extends ConsumerStatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  ConsumerState<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends ConsumerState<AdminHomeScreen> {
  bool _initialLoadDone = false;
  /// null = "All Shops", otherwise index into teamStatus.shops
  int? _selectedShopFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    if (!mounted) return;

    final shopProvider =
        provider_pkg.Provider.of<ShopSelectionProvider>(context, listen: false);
    final salesProvider =
        provider_pkg.Provider.of<DailySalesProvider>(context, listen: false);
    final dashboardProvider =
        provider_pkg.Provider.of<DashboardProvider>(context, listen: false);
    final userProvider =
        provider_pkg.Provider.of<UserManagementProvider>(context, listen: false);

    final shopId = shopProvider.selectedShopId;
    if (shopId == null) return;

    // Load yesterday's records WITHOUT status filter so team status
    // can see all submissions (not just pending ones)
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final yesterdayDate = DateTime(yesterday.year, yesterday.month, yesterday.day);

    // IMPORTANT: Admin home needs ALL shops data for Yesterday's Summary,
    // Team Status, and Alerts. Must load dashboard WITHOUT shop filter.
    // Previously loadDashboard() and loadMetrics(shopId) were called
    // concurrently — a race condition that filtered data to one shop only,
    // causing empty shop_summaries and incomplete team_status.

    // Clear shop filter so backend returns ALL shops' data.
    // setSelectedShop(null) triggers loadDashboard() internally when
    // the value changes. If already null, call loadDashboard() explicitly.
    if (dashboardProvider.selectedShopId != null) {
      dashboardProvider.setSelectedShop(null);
    } else {
      dashboardProvider.loadDashboard();
    }

    await Future.wait([
      salesProvider.fetchRecords(
        shopId: shopId,
        startDate: yesterdayDate,
        endDate: yesterdayDate,
      ),
      userProvider.loadUsers(),
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
                _buildActionGrid(),
                SizedBox(height: iOSDesignTokens.space12),
                _buildApprovalsHero(),
                _buildYesterdaySummary(),
                _buildTeamStatus(),
                _buildAlerts(),
                _buildBusinessHealth(),
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

    return HomeScreenHeader(
      greeting: getTimeGreeting(),
      userName: auth.currentUser?.firstName ?? 'User',
      onSettingsTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
    );
  }

  Widget _buildApprovalsHero() {
    final shopProvider =
        provider_pkg.Provider.of<ShopSelectionProvider>(context);
    final shopId = shopProvider.selectedShopId;

    return provider_pkg.Consumer2<DailySalesProvider, DashboardProvider>(
      builder: (context, salesProvider, dashboardProvider, _) {
        // Use dashboard summary for total pending count (covers all dates)
        // rather than counting from the (yesterday-filtered) records list
        final pendingSalesCount = dashboardProvider.summary?.pendingSales ??
            salesProvider.records.where((r) => r.status == 'pending').length;

        return Consumer(
          builder: (context, ref, _) {
            int pendingCashCount = 0;
            if (shopId != null) {
              final cashAsync = ref.watch(pendingCollectionsProvider(shopId));
              if (cashAsync.hasValue) {
                pendingCashCount = cashAsync.value?.length ?? 0;
              }
            }

            return Row(
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
                          userRole: auth.currentUser?.role ?? 'admin',
                        ),
                      ),
                    );
                  },
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

        // Reset filter if it's out of range (e.g. data refreshed with fewer shops)
        if (_selectedShopFilter != null &&
            _selectedShopFilter! >= teamStatus.shops.length) {
          _selectedShopFilter = null;
        }

        // Compute header counts based on filter
        final int headerSubmitted;
        final int headerTotal;
        if (_selectedShopFilter != null) {
          final shop = teamStatus.shops[_selectedShopFilter!];
          headerSubmitted = shop.submittedCount;
          headerTotal = shop.salesmen.length;
        } else {
          headerSubmitted = teamStatus.totalSubmitted;
          headerTotal = teamStatus.totalSalesmen;
        }

        // Determine which shops to display
        final shopsToShow = _selectedShopFilter != null
            ? [teamStatus.shops[_selectedShopFilter!]]
            : teamStatus.shops;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HomeSectionHeader(
              title: 'Team Status ($headerSubmitted/$headerTotal)',
            ),
            // Shop filter chips
            if (teamStatus.shops.length > 1)
              Padding(
                padding: EdgeInsets.only(bottom: iOSDesignTokens.space8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Padding(
                        padding: EdgeInsets.only(right: iOSDesignTokens.space8),
                        child: ChoiceChip(
                          label: const Text('All Shops'),
                          selected: _selectedShopFilter == null,
                          onSelected: (_) =>
                              setState(() => _selectedShopFilter = null),
                        ),
                      ),
                      ...List.generate(teamStatus.shops.length, (i) {
                        return Padding(
                          padding:
                              EdgeInsets.only(right: iOSDesignTokens.space8),
                          child: ChoiceChip(
                            label: Text(teamStatus.shops[i].shopName),
                            selected: _selectedShopFilter == i,
                            onSelected: (_) =>
                                setState(() => _selectedShopFilter = i),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            // Salesman rows
            ...shopsToShow.expand((shop) => [
              // Only show shop name label when viewing all shops
              if (_selectedShopFilter == null)
                Padding(
                  padding: EdgeInsets.only(
                      top: iOSDesignTokens.space8,
                      bottom: iOSDesignTokens.space4),
                  child: Text(shop.shopName,
                      style: AppTextStyles.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                ),
              ...shop.salesmen.map((salesman) => HomeTeamStatusRow(
                    personName: salesman.salesmanName,
                    hasSubmitted: salesman.status == 'submitted',
                    amount: salesman.status == 'submitted'
                        ? salesman.totalAmount
                        : null,
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
            message: '$totalMissing salesman${totalMissing > 1 ? 's' : ''} missing yesterday\'s entry',
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

  /// Business Health section — admin-only
  Widget _buildBusinessHealth() {
    return provider_pkg.Consumer2<UserManagementProvider, ShopSelectionProvider>(
      builder: (context, userProvider, shopProvider, _) {
        final activeUsers = userProvider.users.where((u) => u.isActive).length;
        final totalUsers = userProvider.users.length;
        final shopCount = shopProvider.shops.length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const HomeSectionHeader(title: 'Business Health'),
            Row(
              children: [
                _InfoTile(
                    label: 'Active Users',
                    value: '$activeUsers/$totalUsers',
                    accentColor: AppColors.info,
                    icon: Icons.people_rounded),
                SizedBox(width: iOSDesignTokens.space8),
                _InfoTile(
                    label: 'Shops',
                    value: '$shopCount',
                    accentColor: AppColors.success,
                    icon: Icons.store_rounded),
                SizedBox(width: iOSDesignTokens.space8),
                _InfoTile(
                    label: 'Subscription',
                    value: 'Active',
                    accentColor: Theme.of(context).colorScheme.primary,
                    icon: Icons.verified_rounded),
              ],
            ),
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
                        userRole: authProvider.currentUser?.role ?? 'admin',
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
                label: 'Shops',
                icon: Icons.store_rounded,
                color: AppColors.success,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ShopsScreen()),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: iOSDesignTokens.space8),
        Row(
          children: [
            Expanded(
              child: HomeActionButton(
                label: 'Sale Reports',
                icon: Icons.bar_chart_rounded,
                color: AppColors.info,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(
                        title: const Text('Sale Reports'),
                        backgroundColor: Theme.of(context).colorScheme.surface,
                        elevation: 0,
                        iconTheme: IconThemeData(
                            color: Theme.of(context).colorScheme.onSurface),
                        titleTextStyle: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      body: const DailySalesScreen(),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(width: iOSDesignTokens.space8),
            Expanded(
              child: HomeActionButton(
                label: 'Purchase Report',
                icon: Icons.shopping_cart_rounded,
                color: const Color(0xFF9C27B0),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const PurchaReportScreen()),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: iOSDesignTokens.space8),
        Row(
          children: [
            Expanded(
              child: HomeActionButton(
                label: 'Finance',
                icon: Icons.account_balance_rounded,
                color: const Color(0xFF00897B),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const FinanceScreen()),
                ),
              ),
            ),
            SizedBox(width: iOSDesignTokens.space8),
            const Expanded(child: SizedBox()),
          ],
        ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  final Color? accentColor;
  final IconData? icon;

  const _InfoTile({
    required this.label,
    required this.value,
    this.accentColor,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? Theme.of(context).colorScheme.primary;
    return Expanded(
      child: Container(
        padding: EdgeInsets.all(iOSDesignTokens.space12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              color.withValues(alpha: 0.06),
              Theme.of(context).colorScheme.surface,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
          border: Border.all(color: color.withValues(alpha: 0.12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null)
              Icon(icon, color: color, size: 18),
            if (icon != null) SizedBox(height: iOSDesignTokens.space4),
            Text(label,
                style: AppTextStyles.caption
                    .copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            SizedBox(height: iOSDesignTokens.space4),
            Text(value,
                style: AppTextStyles.bodySmall
                    .copyWith(fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      ),
    );
  }
}
