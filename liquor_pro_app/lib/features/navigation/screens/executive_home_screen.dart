import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/theme/ios_design_tokens.dart';
import '../../../core/widgets/home_screen_components.dart';
import '../../../core/providers/shop_selection_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../sales/providers/daily_sales_provider.dart';
import '../../sales/screens/daily_sales_entry_screen.dart';
import '../../sales/screens/smart_sale_screen.dart';
import '../../sales/screens/salesman_sales_history_screen.dart';
import '../../inventory/screens/inventory_screen.dart';
import '../../finance/screens/cash_dashboard_screen.dart';
import '../../reports/screens/reports_screen.dart';
import '../../settings/screens/settings_screen.dart';

/// Executive Home Screen — identical to SalesmanHomeScreen + Reports link.
class ExecutiveHomeScreen extends StatefulWidget {
  const ExecutiveHomeScreen({super.key});

  @override
  State<ExecutiveHomeScreen> createState() => _ExecutiveHomeScreenState();
}

class _ExecutiveHomeScreenState extends State<ExecutiveHomeScreen> {
  bool _hasDraft = false;
  bool _initialLoadDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    if (!mounted) return;

    final shopProvider =
        Provider.of<ShopSelectionProvider>(context, listen: false);
    final salesProvider =
        Provider.of<DailySalesProvider>(context, listen: false);
    final shopId = shopProvider.selectedShopId;
    if (shopId == null) return;

    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final yesterdayOnly =
        DateTime(yesterday.year, yesterday.month, yesterday.day);

    await Future.wait([
      salesProvider.fetchRecords(
        shopId: shopId,
        startDate: yesterdayOnly,
        endDate: yesterdayOnly,
      ),
      salesProvider.hasDraft().then((v) {
        if (mounted) setState(() => _hasDraft = v);
      }),
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
                _buildStatusCard(),
                SizedBox(height: iOSDesignTokens.space16),
                _buildPrimaryActions(),
                _buildDraftRecovery(),
                _buildRecentSubmissions(),
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
    return Consumer2<AuthProvider, ShopSelectionProvider>(
      builder: (context, auth, shop, _) {
        return HomeScreenHeader(
          greeting: getTimeGreeting(),
          userName: auth.currentUser?.firstName ?? 'User',
          shopName: shop.selectedShopName,
          onSettingsTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SettingsScreen())),
          onShopTap: shop.shops.length > 1
              ? () => showShopPickerSheet(
                    context,
                    shops: shop.shops,
                    selectedShopId: shop.selectedShopId,
                    onSelect: (s) => shop.selectShop(s),
                  )
              : null,
        );
      },
    );
  }

  Widget _buildStatusCard() {
    return Consumer<DailySalesProvider>(
      builder: (context, provider, _) {
        final yesterday = DateTime.now().subtract(const Duration(days: 1));
        final yesterdayOnly =
            DateTime(yesterday.year, yesterday.month, yesterday.day);

        final record = provider.records
            .where((r) =>
                r.recordDate.year == yesterdayOnly.year &&
                r.recordDate.month == yesterdayOnly.month &&
                r.recordDate.day == yesterdayOnly.day)
            .firstOrNull;

        EntryStatus status;
        double? amount;
        if (record == null) {
          status = _hasDraft ? EntryStatus.draft : EntryStatus.notSubmitted;
        } else {
          status = mapRecordStatus(record.status);
          amount = record.totalSalesAmount;
        }

        return HomeStatusCard(
          title: "Yesterday's Entry",
          status: status,
          amount: amount,
          date: formatShortDate(yesterdayOnly),
          onTap: status == EntryStatus.rejected
              ? () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DailySalesEntryScreen(
                        showHeader: true,
                        editRecord: record,
                      ),
                    ),
                  )
              : null,
        );
      },
    );
  }

  Widget _buildPrimaryActions() {
    return Column(
      children: [
        HomeActionButton(
          isPrimary: true,
          label: 'Enter Daily Sale',
          icon: Icons.point_of_sale_rounded,
          subtitle: "Record yesterday's sales",
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const DailySalesEntryScreen(showHeader: true)),
          ),
        ),
        SizedBox(height: iOSDesignTokens.space8),
        HomeActionButton(
          label: 'Smart Sale (OCR)',
          icon: Icons.document_scanner_rounded,
          color: AppColors.info,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SmartSaleScreen()),
          ),
        ),
      ],
    );
  }

  Widget _buildDraftRecovery() {
    return Consumer<DailySalesProvider>(
      builder: (context, provider, _) {
        final yesterday = DateTime.now().subtract(const Duration(days: 1));
        final yesterdayOnly =
            DateTime(yesterday.year, yesterday.month, yesterday.day);
        final hasRecord = provider.records.any((r) {
          return r.recordDate.year == yesterdayOnly.year &&
              r.recordDate.month == yesterdayOnly.month &&
              r.recordDate.day == yesterdayOnly.day;
        });

        final showDraft = _hasDraft && !hasRecord;

        return AnimatedSize(
          duration: const Duration(milliseconds: 300),
          child: showDraft
              ? Container(
                  margin: EdgeInsets.only(top: iOSDesignTokens.space12),
                  padding: EdgeInsets.all(iOSDesignTokens.space12),
                  decoration: BoxDecoration(
                    color: AppColors.info.withValues(alpha: 0.08),
                    borderRadius:
                        BorderRadius.circular(iOSDesignTokens.radiusMedium),
                    border: Border.all(
                        color: AppColors.info.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.edit_note_rounded,
                              color: AppColors.info, size: 20),
                          SizedBox(width: iOSDesignTokens.space8),
                          Expanded(
                            child: Text(
                              'You have a saved draft. Continue?',
                              style: AppTextStyles.bodySmall
                                  .copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: iOSDesignTokens.space8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () async {
                                await provider.clearDraft();
                                if (mounted) setState(() => _hasDraft = false);
                              },
                              style: OutlinedButton.styleFrom(
                                  foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant),
                              child: const Text('Discard'),
                            ),
                          ),
                          SizedBox(width: iOSDesignTokens.space8),
                          Expanded(
                            child: FilledButton(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        const DailySalesEntryScreen(
                                            showHeader: true)),
                              ),
                              child: const Text('Continue'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        );
      },
    );
  }

  Widget _buildRecentSubmissions() {
    return Consumer<DailySalesProvider>(
      builder: (context, provider, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HomeSectionHeader(
              title: 'Recent Submissions',
              onSeeAll: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const SalesmanSalesHistoryScreen()),
              ),
            ),
            if (provider.isLoading && !_initialLoadDone)
              Padding(
                padding: EdgeInsets.all(iOSDesignTokens.space16),
                child:
                    const Center(child: CircularProgressIndicator.adaptive()),
              )
            else if (provider.records.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: iOSDesignTokens.space24),
                child: Center(
                  child: Text('No submissions yet',
                      style: AppTextStyles.caption
                          .copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ),
              )
            else
              ...provider.records.take(5).map((r) => HomeSubmissionRow(
                    date: formatShortDate(r.recordDate),
                    status: mapRecordStatus(r.status),
                    amount: r.totalSalesAmount,
                    shopName: r.shopName,
                    onTap: () {},
                  )),
          ],
        );
      },
    );
  }

  /// Quick links — 3 buttons: Inventory, Cash, Reports
  Widget _buildQuickLinks() {
    return Consumer2<ShopSelectionProvider, AuthProvider>(
      builder: (context, shopProvider, authProvider, _) {
        return Row(
          children: [
            Expanded(
              child: HomeActionButton(
                label: 'Inventory',
                icon: Icons.inventory_2_rounded,
                color: AppColors.success,
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const InventoryScreen())),
              ),
            ),
            SizedBox(width: iOSDesignTokens.space8),
            Expanded(
              child: HomeActionButton(
                label: 'Cash',
                icon: Icons.account_balance_wallet_rounded,
                color: AppColors.warning,
                onTap: () {
                  final shopId = shopProvider.selectedShopId;
                  if (shopId == null) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CashDashboardScreen(
                        shopId: shopId,
                        userRole: authProvider.currentUser?.role ?? 'executive',
                      ),
                    ),
                  );
                },
              ),
            ),
            SizedBox(width: iOSDesignTokens.space8),
            Expanded(
              child: HomeActionButton(
                label: 'Reports',
                icon: Icons.bar_chart_rounded,
                color: AppColors.info,
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ReportsScreen())),
              ),
            ),
          ],
        );
      },
    );
  }
}
