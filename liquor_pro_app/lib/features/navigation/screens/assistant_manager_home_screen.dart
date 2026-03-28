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
import '../../finance/providers/cash_provider.dart';
import '../../sales/screens/daily_sales_entry_screen.dart';
import '../../inventory/screens/inventory_screen.dart';
import '../../finance/screens/cash_dashboard_screen.dart';
import '../../settings/screens/settings_screen.dart';

/// Assistant Manager Home Screen — my entry, team submissions, cash tasks, summary.
class AssistantManagerHomeScreen extends ConsumerStatefulWidget {
  const AssistantManagerHomeScreen({super.key});

  @override
  ConsumerState<AssistantManagerHomeScreen> createState() =>
      _AssistantManagerHomeScreenState();
}

class _AssistantManagerHomeScreenState
    extends ConsumerState<AssistantManagerHomeScreen> {
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
    final salesProvider =
        provider_pkg.Provider.of<DailySalesProvider>(context, listen: false);
    final dashboardProvider =
        provider_pkg.Provider.of<DashboardProvider>(context, listen: false);

    final shopId = shopProvider.selectedShopId;
    if (shopId == null) return;

    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final yesterdayOnly =
        DateTime(yesterday.year, yesterday.month, yesterday.day);

    await Future.wait([
      salesProvider.fetchRecords(shopId: shopId, startDate: yesterdayOnly, endDate: yesterdayOnly),
      dashboardProvider.loadDashboard(),
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
                _buildMyEntryCard(),
                _buildTeamSubmissions(),
                _buildCashSection(),
                _buildYesterdaySummary(),
                SizedBox(height: iOSDesignTokens.space16),
                _buildQuickLinks(),
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

  Widget _buildMyEntryCard() {
    return provider_pkg.Consumer<DailySalesProvider>(
      builder: (context, provider, _) {
        final yesterday = DateTime.now().subtract(const Duration(days: 1));
        final yesterdayOnly =
            DateTime(yesterday.year, yesterday.month, yesterday.day);
        final auth =
            provider_pkg.Provider.of<AuthProvider>(context, listen: false);
        final myId = auth.currentUser?.id;

        final myRecord = provider.records
            .where((r) {
              final matchesDate = r.recordDate.year == yesterdayOnly.year &&
                  r.recordDate.month == yesterdayOnly.month &&
                  r.recordDate.day == yesterdayOnly.day;
              if (myId != null && r.salesmanId != null) {
                return matchesDate && r.salesmanId == myId;
              }
              return matchesDate;
            })
            .firstOrNull;

        EntryStatus status;
        double? amount;
        if (myRecord == null) {
          status = EntryStatus.notSubmitted;
        } else {
          status = mapRecordStatus(myRecord.status);
          amount = myRecord.totalSalesAmount;
        }

        return HomeStatusCard(
          compact: true,
          title: 'My Entry',
          status: status,
          amount: amount,
          date: formatShortDate(yesterdayOnly),
        );
      },
    );
  }

  Widget _buildTeamSubmissions() {
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
              const HomeSectionHeader(title: 'Team Submissions'),
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
              title: 'Team Submissions (${teamStatus.totalSubmitted}/${teamStatus.totalSalesmen})',
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

  Widget _buildCashSection() {
    final shopProvider =
        provider_pkg.Provider.of<ShopSelectionProvider>(context);
    final authProvider = provider_pkg.Provider.of<AuthProvider>(context);
    final shopId = shopProvider.selectedShopId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const HomeSectionHeader(title: 'Cash Tasks'),
        Container(
          padding: EdgeInsets.all(iOSDesignTokens.space12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
            border: Border.all(color: Theme.of(context).colorScheme.outline),
          ),
          child: Column(
            children: [
              // Cash on Hand
              Consumer(
                builder: (context, ref, _) {
                  final balanceAsync = ref.watch(cashBalanceProvider);
                  return Row(
                    children: [
                      Icon(Icons.account_balance_wallet_outlined,
                          color: AppColors.warning, size: 20),
                      SizedBox(width: iOSDesignTokens.space8),
                      Text('Cash on Hand', style: AppTextStyles.bodySmall.copyWith(color: Theme.of(context).colorScheme.onSurface)),
                      const Spacer(),
                      balanceAsync.when(
                        data: (balance) => Text(
                            '₹${balance.toStringAsFixed(0)}',
                            style: AppTextStyles.priceMedium.copyWith(color: Theme.of(context).colorScheme.primary)),
                        loading: () => const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator.adaptive(
                                strokeWidth: 2)),
                        error: (_, __) => Text('--',
                            style: AppTextStyles.bodySmall
                                .copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ),
                    ],
                  );
                },
              ),
              SizedBox(height: iOSDesignTokens.space8),
              // Cash action buttons
              Row(
                children: [
                  Expanded(
                    child: _CashActionChip(
                      label: 'Collect Cash',
                      icon: Icons.move_to_inbox_rounded,
                      onTap: () {
                        if (shopId == null) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CashDashboardScreen(
                              shopId: shopId,
                              userRole:
                                  authProvider.currentUser?.role ?? 'assistant_manager',
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  SizedBox(width: iOSDesignTokens.space8),
                  Expanded(
                    child: _CashActionChip(
                      label: 'Submit to Bank',
                      icon: Icons.account_balance_rounded,
                      onTap: () {
                        if (shopId == null) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CashDashboardScreen(
                              shopId: shopId,
                              userRole:
                                  authProvider.currentUser?.role ?? 'assistant_manager',
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
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
            if (provider.isLoading && summary == null)
              Padding(
                padding: EdgeInsets.all(iOSDesignTokens.space16),
                child:
                    const Center(child: CircularProgressIndicator.adaptive()),
              )
            else if (summary == null)
              Padding(
                padding: EdgeInsets.symmetric(vertical: iOSDesignTokens.space12),
                child: Text('No data available',
                    style: AppTextStyles.caption
                        .copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              )
            else
              Row(
                children: [
                  _SummaryTile(
                      label: 'Total Sales',
                      value: '₹${summary.totalRevenue.toStringAsFixed(0)}'),
                  SizedBox(width: iOSDesignTokens.space8),
                  _SummaryTile(
                      label: 'Cash',
                      value: '₹${summary.cashAmount.toStringAsFixed(0)}'),
                  SizedBox(width: iOSDesignTokens.space8),
                  _SummaryTile(
                      label: 'Card+UPI',
                      value:
                          '₹${(summary.cardAmount + summary.upiAmount).toStringAsFixed(0)}'),
                ],
              ),
          ],
        );
      },
    );
  }

  Widget _buildQuickLinks() {
    return Row(
      children: [
        Expanded(
          child: HomeActionButton(
            label: 'Daily Sale',
            icon: Icons.point_of_sale_rounded,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const DailySalesEntryScreen(showHeader: true)),
            ),
          ),
        ),
        SizedBox(width: iOSDesignTokens.space8),
        Expanded(
          child: HomeActionButton(
            label: 'Inventory',
            icon: Icons.inventory_2_rounded,
            color: AppColors.success,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const InventoryScreen())),
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Private helper widgets
// ══════════════════════════════════════════════════════════════════════════════

class _SummaryTile extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: EdgeInsets.all(iOSDesignTokens.space12),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
          border: Border.all(color: cs.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTextStyles.caption.copyWith(color: cs.onSurfaceVariant)),
            SizedBox(height: iOSDesignTokens.space4),
            Text(value, style: AppTextStyles.priceSmall.copyWith(color: cs.primary)),
          ],
        ),
      ),
    );
  }
}

class _CashActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  const _CashActionChip({
    required this.label,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(iOSDesignTokens.radiusSmall),
      child: Container(
        padding: EdgeInsets.symmetric(
            vertical: iOSDesignTokens.space8,
            horizontal: iOSDesignTokens.space8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(iOSDesignTokens.radiusSmall),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
            SizedBox(width: iOSDesignTokens.space4),
            Flexible(
              child: Text(label,
                  style: AppTextStyles.caption
                      .copyWith(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}
