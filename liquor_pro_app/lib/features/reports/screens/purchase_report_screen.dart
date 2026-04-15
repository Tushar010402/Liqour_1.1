import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/theme/ios_design_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/providers/shop_selection_provider.dart';
import '../../inventory/providers/stock_purchase_provider.dart';
import '../../inventory/models/stock_purchase.dart';

/// Modern Purchase Report Screen
/// Matches the DailySalesScreen design language with pill filters,
/// summary grid, vendor breakdown, and purchase history.
class PurchaseReportScreen extends StatefulWidget {
  const PurchaseReportScreen({super.key});

  @override
  State<PurchaseReportScreen> createState() => _PurchaseReportScreenState();
}

class _PurchaseReportScreenState extends State<PurchaseReportScreen> {
  final _dateFmt = DateFormat('dd MMM yyyy');
  final _timeFmt = DateFormat('hh:mm a');
  final _scrollController = ScrollController();

  // Filter state
  _PurchasePeriod _selectedPeriod = _PurchasePeriod.thirtyDays;
  String? _selectedShopId;
  StockPurchaseStatus? _selectedStatus;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  DateRange _getDateRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    switch (_selectedPeriod) {
      case _PurchasePeriod.sevenDays:
        return DateRange(
            start: today.subtract(const Duration(days: 7)), end: today);
      case _PurchasePeriod.fifteenDays:
        return DateRange(
            start: today.subtract(const Duration(days: 15)), end: today);
      case _PurchasePeriod.thirtyDays:
        return DateRange(
            start: today.subtract(const Duration(days: 30)), end: today);
      case _PurchasePeriod.threeMonths:
        return DateRange(
            start: DateTime(now.year, now.month - 3, now.day), end: today);
      case _PurchasePeriod.sixMonths:
        return DateRange(
            start: DateTime(now.year, now.month - 6, now.day), end: today);
      case _PurchasePeriod.oneYear:
        return DateRange(
            start: DateTime(now.year - 1, now.month, now.day), end: today);
    }
  }

  Future<void> _loadData() async {
    final range = _getDateRange();
    final shopId =
        _selectedShopId ?? context.read<ShopSelectionProvider>().selectedShopId;
    await context.read<StockPurchaseProvider>().loadPurchaseHistory(
          shopId: shopId,
          status: _selectedStatus,
          fromDate: range.start,
          toDate: range.end,
          refresh: true,
        );
    if (mounted) setState(() => _isLoaded = true);
  }

  Future<void> _loadMore() async {
    final range = _getDateRange();
    final shopId =
        _selectedShopId ?? context.read<ShopSelectionProvider>().selectedShopId;
    await context.read<StockPurchaseProvider>().loadMoreHistory(
          shopId: shopId,
          status: _selectedStatus,
          fromDate: range.start,
          toDate: range.end,
        );
  }

  /// Extract unique shops from purchases
  List<_ShopInfo> _extractShops(List<StockPurchase> purchases) {
    final Map<String, String> shopMap = {};
    for (final p in purchases) {
      if (!shopMap.containsKey(p.shopId)) {
        shopMap[p.shopId] = p.shopName;
      }
    }
    return shopMap.entries
        .map((e) => _ShopInfo(id: e.key, name: e.value))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  /// Filter purchases by selected shop
  List<StockPurchase> _filterByShop(List<StockPurchase> purchases) {
    if (_selectedShopId == null) return purchases;
    return purchases.where((p) => p.shopId == _selectedShopId).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surfaceContainerHighest,
      body: Column(
        children: [
          // App bar
          _buildAppBar(cs),

          // Period filter bar
          _buildPeriodFilterBar(),

          // Content
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadData,
              color: cs.primary,
              child: Consumer<StockPurchaseProvider>(
                builder: (context, provider, _) {
                  if (provider.isLoading && provider.purchaseHistory.isEmpty) {
                    return _buildLoadingState();
                  }

                  if (!_isLoaded) {
                    return _buildLoadingState();
                  }

                  if (provider.purchaseHistory.isEmpty) {
                    return _buildEmptyState();
                  }

                  final allPurchases = provider.purchaseHistory;
                  final shops = _extractShops(allPurchases);
                  final filtered = _filterByShop(allPurchases);

                  return _buildPurchaseContent(
                    purchases: filtered,
                    allPurchases: allPurchases,
                    shops: shops,
                    hasMore: provider.hasMore,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // App Bar
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildAppBar(ColorScheme cs) {
    return Container(
      color: cs.surface,
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded,
                  size: 20, color: cs.onSurface),
              onPressed: () => Navigator.pop(context),
            ),
            Expanded(
              child: Text(
                'Purchase Report',
                style: AppTextStyles.h6.copyWith(color: cs.onSurface),
              ),
            ),
            IconButton(
              icon: Icon(CupertinoIcons.arrow_clockwise,
                  size: 20, color: cs.onSurfaceVariant),
              onPressed: _loadData,
              tooltip: 'Refresh',
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Period Filter Bar (pill chips — matches DailySalesScreen)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPeriodFilterBar() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surface,
      padding: EdgeInsets.fromLTRB(
        iOSDesignTokens.space16,
        iOSDesignTokens.space4,
        iOSDesignTokens.space16,
        iOSDesignTokens.space12,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _PurchasePeriod.values.map((period) {
            final isSelected = _selectedPeriod == period;
            return Padding(
              padding: EdgeInsets.only(right: iOSDesignTokens.space8),
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedPeriod = period);
                  _loadData();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? cs.primary
                        : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? cs.primary
                          : cs.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    period.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w500,
                      color:
                          isSelected ? Colors.white : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Shop Filter Chips (matches DailySalesScreen pattern)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildShopFilterChips(List<_ShopInfo> shops) {
    if (shops.length <= 1) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(bottom: iOSDesignTokens.space12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildShopChip(
              label: 'All Shops',
              isSelected: _selectedShopId == null,
              onTap: () => setState(() => _selectedShopId = null),
            ),
            ...shops.map((shop) => _buildShopChip(
                  label: shop.name,
                  isSelected: _selectedShopId == shop.id,
                  onTap: () => setState(() => _selectedShopId = shop.id),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildShopChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(right: iOSDesignTokens.space8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.info.withValues(alpha: 0.12)
                : cs.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? AppColors.info
                  : cs.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSelected) ...[
                Icon(Icons.store_rounded, size: 14, color: AppColors.info),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? AppColors.info : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Status Filter Chips (pill style, matching shop chips)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStatusFilterChips() {
    final statuses = [
      (null, 'All', AppColors.info),
      (StockPurchaseStatus.approved, 'Approved', AppColors.success),
      (StockPurchaseStatus.pending, 'Pending', AppColors.warning),
      (StockPurchaseStatus.rejected, 'Rejected', AppColors.error),
    ];
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: iOSDesignTokens.space12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: statuses.map((entry) {
            final isSelected = _selectedStatus == entry.$1;
            final color = entry.$3;
            return Padding(
              padding: EdgeInsets.only(right: iOSDesignTokens.space8),
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedStatus = entry.$1);
                  _loadData();
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? color.withValues(alpha: 0.12)
                        : cs.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected
                          ? color
                          : cs.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isSelected) ...[
                        Icon(_statusIcon(entry.$1), size: 13, color: color),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        entry.$2,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: isSelected ? color : cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Loading & Empty States
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildLoadingState() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator.adaptive(
            valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
          ),
          SizedBox(height: iOSDesignTokens.space16),
          Text(
            'Loading purchase data...',
            style:
                AppTextStyles.caption.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.2),
        Center(
          child: Column(
            children: [
              Icon(
                CupertinoIcons.cart,
                size: 56,
                color: cs.outlineVariant,
              ),
              SizedBox(height: iOSDesignTokens.space12),
              Text(
                'No Purchases Found',
                style: AppTextStyles.h5.copyWith(color: cs.onSurface),
              ),
              SizedBox(height: iOSDesignTokens.space4),
              Text(
                'No stock purchases for ${_selectedPeriod.label.toLowerCase()}',
                style: AppTextStyles.caption
                    .copyWith(color: cs.onSurfaceVariant),
              ),
              SizedBox(height: iOSDesignTokens.space20),
              FilledButton.icon(
                onPressed: _loadData,
                icon: const Icon(CupertinoIcons.arrow_clockwise, size: 16),
                label: const Text('Refresh'),
                style: FilledButton.styleFrom(
                  backgroundColor: cs.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(iOSDesignTokens.radiusSmall),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Main Purchase Content
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPurchaseContent({
    required List<StockPurchase> purchases,
    required List<StockPurchase> allPurchases,
    required List<_ShopInfo> shops,
    required bool hasMore,
  }) {
    final summary = _calculateSummary(purchases);

    return ListView(
      controller: _scrollController,
      padding: EdgeInsets.all(iOSDesignTokens.space16),
      children: [
        // Shop filter chips
        _buildShopFilterChips(shops),

        // Status filter chips
        _buildStatusFilterChips(),

        // Summary grid (4 cards)
        _buildSummaryGrid(summary),
        SizedBox(height: iOSDesignTokens.space20),

        // Vendor breakdown (when there are approved purchases)
        if (summary.vendors.isNotEmpty) ...[
          _buildSectionHeader(
              'Vendor Breakdown', CupertinoIcons.building_2_fill),
          SizedBox(height: iOSDesignTokens.space12),
          _buildVendorBreakdown(summary.vendors),
          SizedBox(height: iOSDesignTokens.space20),
        ],

        // Purchase history
        _buildSectionHeader(
            'Purchase History', CupertinoIcons.doc_text_fill),
        SizedBox(height: iOSDesignTokens.space12),
        _buildPurchaseHistory(purchases, hasMore),

        SizedBox(height: iOSDesignTokens.space24),
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: cs.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: AppTextStyles.bodyMedium.copyWith(
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Summary Grid (matches DailySalesScreen _SummaryCard + GridView.count)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSummaryGrid(_PurchaseSummary summary) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.5,
      children: [
        _PurchaseSummaryCard(
          title: 'Total Amount',
          value: Formatters.currency(summary.totalAmount),
          icon: CupertinoIcons.money_dollar_circle_fill,
          color: AppColors.success,
        ),
        _PurchaseSummaryCard(
          title: 'Total Items',
          value: '${summary.totalItems}',
          icon: CupertinoIcons.cube_box_fill,
          color: Theme.of(context).colorScheme.primary,
        ),
        _PurchaseSummaryCard(
          title: 'Approved',
          value: '${summary.approvedCount}',
          icon: CupertinoIcons.check_mark_circled_solid,
          color: AppColors.success,
        ),
        _PurchaseSummaryCard(
          title: 'Pending',
          value: '${summary.pendingCount}',
          icon: CupertinoIcons.clock_fill,
          color: AppColors.warning,
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Vendor Breakdown Table
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildVendorBreakdown(List<_VendorSummary> vendors) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
        border: Border.all(color: cs.outline.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          // Table header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(iOSDesignTokens.radiusMedium),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text('Vendor',
                      style: AppTextStyles.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant)),
                ),
                Expanded(
                  child: Text('Orders',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant)),
                ),
                Expanded(
                  flex: 2,
                  child: Text('Amount',
                      textAlign: TextAlign.right,
                      style: AppTextStyles.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant)),
                ),
              ],
            ),
          ),
          // Vendor rows
          ...vendors.asMap().entries.map((entry) {
            final v = entry.value;
            return Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                      color: cs.outline.withValues(alpha: 0.08)),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Row(
                      children: [
                        Icon(CupertinoIcons.building_2_fill,
                            size: 14,
                            color: cs.primary.withValues(alpha: 0.7)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            v.name,
                            style: AppTextStyles.bodySmall
                                .copyWith(fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${v.orderCount}',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodySmall
                          .copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      Formatters.currency(v.totalAmount),
                      textAlign: TextAlign.right,
                      style: AppTextStyles.bodySmall.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.success,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          // Total row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.04),
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(iOSDesignTokens.radiusMedium),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text('Total',
                      style: AppTextStyles.bodySmall
                          .copyWith(fontWeight: FontWeight.w700)),
                ),
                Expanded(
                  child: Text(
                    '${vendors.fold(0, (s, v) => s + v.orderCount)}',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodySmall
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    Formatters.currency(
                        vendors.fold(0.0, (s, v) => s + v.totalAmount)),
                    textAlign: TextAlign.right,
                    style: AppTextStyles.bodySmall.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.success,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Purchase History List
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPurchaseHistory(List<StockPurchase> purchases, bool hasMore) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
        border: Border.all(color: cs.outline.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          ...List.generate(purchases.length, (i) {
            final purchase = purchases[i];
            final statusColor = _statusColor(purchase.status);
            return InkWell(
              onTap: () => _showPurchaseDetail(purchase),
              borderRadius: i == 0
                  ? BorderRadius.vertical(
                      top: Radius.circular(iOSDesignTokens.radiusMedium))
                  : i == purchases.length - 1 && !hasMore
                      ? BorderRadius.vertical(
                          bottom:
                              Radius.circular(iOSDesignTokens.radiusMedium))
                      : null,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  border: i < purchases.length - 1 || hasMore
                      ? Border(
                          bottom: BorderSide(
                              color: cs.outline.withValues(alpha: 0.08)))
                      : null,
                ),
                child: Row(
                  children: [
                    // Status icon
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _statusIcon(purchase.status),
                        color: statusColor,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            purchase.vendorName,
                            style: AppTextStyles.bodySmall
                                .copyWith(fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  '${_dateFmt.format(purchase.createdAt)} \u00B7 ${purchase.items.length} items',
                                  style: AppTextStyles.caption
                                      .copyWith(color: cs.onSurfaceVariant),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (_selectedShopId == null) ...[
                                Text(' \u00B7 ',
                                    style: AppTextStyles.caption
                                        .copyWith(color: cs.outlineVariant)),
                                Flexible(
                                  child: Text(
                                    purchase.shopName,
                                    style: AppTextStyles.caption
                                        .copyWith(color: cs.onSurfaceVariant),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Amount + status
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          Formatters.currency(purchase.totalAmount),
                          style: AppTextStyles.bodySmall.copyWith(
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 3),
                        _buildStatusBadge(purchase.status),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
          if (hasMore)
            Padding(
              padding: EdgeInsets.all(iOSDesignTokens.space16),
              child: const Center(
                  child: CircularProgressIndicator.adaptive()),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(StockPurchaseStatus status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.displayName.toUpperCase(),
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Purchase Detail Bottom Sheet
  // ═══════════════════════════════════════════════════════════════════════════

  void _showPurchaseDetail(StockPurchase purchase) {
    final cs = Theme.of(context).colorScheme;
    final statusColor = _statusColor(purchase.status);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  // Handle bar
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Header
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            _statusIcon(purchase.status),
                            color: statusColor,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Purchase Order',
                                  style: AppTextStyles.h5),
                              Text(
                                '${purchase.vendorName} \u00B7 ${_dateFmt.format(purchase.createdAt)}',
                                style: AppTextStyles.caption
                                    .copyWith(color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        _buildStatusBadge(purchase.status),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // Content
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      children: [
                        // Purchase info
                        _buildDetailSection(
                          'Purchase Info',
                          CupertinoIcons.doc_text,
                          cs.primary,
                          [
                            _buildDetailRow('Vendor', purchase.vendorName),
                            _buildDetailRow('Shop', purchase.shopName),
                            _buildDetailRow('Date',
                                _dateFmt.format(purchase.createdAt)),
                            _buildDetailRow('Time',
                                _timeFmt.format(purchase.createdAt)),
                            if (purchase.createdByName.isNotEmpty)
                              _buildDetailRow(
                                  'Created by', purchase.createdByName),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Financials
                        _buildDetailSection(
                          'Financial Summary',
                          CupertinoIcons.money_dollar_circle,
                          AppColors.success,
                          [
                            _buildDetailRow('Subtotal',
                                Formatters.currency(purchase.subtotal)),
                            _buildDetailRow('TCS (2%)',
                                Formatters.currency(purchase.tcsAmount)),
                            if (purchase.roundOff != 0)
                              _buildDetailRow(
                                'Round Off',
                                purchase.roundOff >= 0
                                    ? '+${Formatters.currency(purchase.roundOff)}'
                                    : Formatters.currency(purchase.roundOff),
                              ),
                            _buildDetailRow(
                              'Total',
                              Formatters.currency(purchase.totalAmount),
                              isBold: true,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Items
                        _buildDetailSection(
                          'Items (${purchase.items.length})',
                          CupertinoIcons.cube_box,
                          AppColors.warning,
                          purchase.items
                              .map((item) => Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: cs.surfaceContainerHighest,
                                      borderRadius:
                                          BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                item.brandName ??
                                                    item.productName,
                                                style: AppTextStyles
                                                    .bodySmall
                                                    .copyWith(
                                                        fontWeight:
                                                            FontWeight.w500),
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                              ),
                                              if (item.size.isNotEmpty)
                                                Text(
                                                  item.size,
                                                  style: AppTextStyles
                                                      .caption
                                                      .copyWith(
                                                          color: cs
                                                              .onSurfaceVariant),
                                                ),
                                            ],
                                          ),
                                        ),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Text('x${item.quantity}',
                                                style: AppTextStyles
                                                    .bodySmall
                                                    .copyWith(
                                                        fontWeight:
                                                            FontWeight
                                                                .w500)),
                                            Text(
                                              Formatters.currency(
                                                  item.totalAmount),
                                              style: AppTextStyles.caption
                                                  .copyWith(
                                                fontWeight: FontWeight.w600,
                                                color: AppColors.success,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ))
                              .toList(),
                        ),
                        const SizedBox(height: 16),

                        // Audit trail
                        _buildDetailSection(
                          'Audit Trail',
                          CupertinoIcons.person_2,
                          cs.onSurfaceVariant,
                          [
                            _buildAuditRow(
                              'Created',
                              purchase.createdByName,
                              purchase.createdByRole,
                              purchase.createdAt,
                            ),
                            if (purchase.approvedByName != null)
                              _buildAuditRow(
                                'Approved',
                                purchase.approvedByName!,
                                purchase.approvedByRole ?? '',
                                purchase.approvedAt,
                              ),
                            if (purchase.rejectionReason != null)
                              Container(
                                margin: const EdgeInsets.only(top: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color:
                                      AppColors.error.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: AppColors.error
                                          .withValues(alpha: 0.2)),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                        CupertinoIcons
                                            .exclamationmark_triangle_fill,
                                        size: 16,
                                        color: AppColors.error),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        purchase.rejectionReason!,
                                        style: AppTextStyles.caption
                                            .copyWith(
                                                color: AppColors.error),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),

                        if (purchase.notes != null &&
                            purchase.notes!.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _buildDetailSection(
                            'Notes',
                            CupertinoIcons.doc_text,
                            cs.onSurfaceVariant,
                            [
                              Text(
                                purchase.notes!,
                                style: AppTextStyles.bodySmall
                                    .copyWith(color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ],

                        const SizedBox(height: 80),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDetailSection(
    String title,
    IconData icon,
    Color color,
    List<Widget> children,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(title,
                  style: AppTextStyles.bodySmall
                      .copyWith(fontWeight: FontWeight.w600, color: color)),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isBold = false}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: AppTextStyles.bodySmall
                  .copyWith(color: cs.onSurfaceVariant)),
          Text(value,
              style: AppTextStyles.bodySmall.copyWith(
                fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
                color: isBold ? AppColors.success : cs.onSurface,
              )),
        ],
      ),
    );
  }

  Widget _buildAuditRow(
      String action, String name, String role, DateTime? timestamp) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(CupertinoIcons.person_fill,
                size: 14, color: cs.onSurfaceVariant),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$action by $name',
                  style: AppTextStyles.caption.copyWith(
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface,
                  ),
                ),
                if (role.isNotEmpty)
                  Text(
                    role,
                    style: AppTextStyles.caption.copyWith(
                      color: cs.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ),
          if (timestamp != null)
            Text(
              '${_dateFmt.format(timestamp)}\n${_timeFmt.format(timestamp)}',
              style: TextStyle(
                fontSize: 9,
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.right,
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Status Helpers
  // ═══════════════════════════════════════════════════════════════════════════

  Color _statusColor(StockPurchaseStatus status) {
    switch (status) {
      case StockPurchaseStatus.approved:
        return AppColors.success;
      case StockPurchaseStatus.pending:
        return AppColors.warning;
      case StockPurchaseStatus.rejected:
        return AppColors.error;
      case StockPurchaseStatus.cancelled:
        return AppColors.disabled;
    }
  }

  IconData _statusIcon(StockPurchaseStatus? status) {
    switch (status) {
      case StockPurchaseStatus.approved:
        return CupertinoIcons.check_mark_circled_solid;
      case StockPurchaseStatus.pending:
        return CupertinoIcons.clock_fill;
      case StockPurchaseStatus.rejected:
        return CupertinoIcons.xmark_circle_fill;
      case StockPurchaseStatus.cancelled:
        return CupertinoIcons.slash_circle_fill;
      case null:
        return CupertinoIcons.line_horizontal_3_decrease_circle_fill;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Calculate Summary
  // ═══════════════════════════════════════════════════════════════════════════

  _PurchaseSummary _calculateSummary(List<StockPurchase> purchases) {
    final approved = purchases.where((p) => p.status.isApproved).toList();
    final pending = purchases.where((p) => p.status.isPending).toList();
    final totalAmount =
        approved.fold(0.0, (sum, p) => sum + p.totalAmount);
    final totalItems =
        approved.fold(0, (sum, p) => sum + p.totalItemCount);

    // Group by vendor
    final vendorMap = <String, _VendorSummary>{};
    for (final p in approved) {
      vendorMap.putIfAbsent(
        p.vendorName,
        () => _VendorSummary(name: p.vendorName),
      );
      vendorMap[p.vendorName]!.orderCount++;
      vendorMap[p.vendorName]!.totalAmount += p.totalAmount;
      vendorMap[p.vendorName]!.totalItems += p.totalItemCount;
    }

    final vendors = vendorMap.values.toList()
      ..sort((a, b) => b.totalAmount.compareTo(a.totalAmount));

    return _PurchaseSummary(
      totalAmount: totalAmount,
      totalItems: totalItems,
      approvedCount: approved.length,
      pendingCount: pending.length,
      totalOrders: purchases.length,
      vendors: vendors,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Summary Card Widget (matches DailySalesScreen _SummaryCard exactly)
// ══════════════════════════════════════════════════════════════════════════════

class _PurchaseSummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _PurchaseSummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.all(iOSDesignTokens.space12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
        border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    style: AppTextStyles.caption
                        .copyWith(color: cs.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
            ],
          ),
          Text(
            value,
            style: AppTextStyles.h5.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Data Models
// ══════════════════════════════════════════════════════════════════════════════

enum _PurchasePeriod {
  sevenDays('7 Days'),
  fifteenDays('15 Days'),
  thirtyDays('30 Days'),
  threeMonths('3 Months'),
  sixMonths('6 Months'),
  oneYear('1 Year');

  final String label;
  const _PurchasePeriod(this.label);
}

class DateRange {
  final DateTime start;
  final DateTime end;
  DateRange({required this.start, required this.end});
}

class _ShopInfo {
  final String id;
  final String name;
  const _ShopInfo({required this.id, required this.name});
}

class _VendorSummary {
  final String name;
  int orderCount = 0;
  double totalAmount = 0;
  int totalItems = 0;
  _VendorSummary({required this.name});
}

class _PurchaseSummary {
  final double totalAmount;
  final int totalItems;
  final int approvedCount;
  final int pendingCount;
  final int totalOrders;
  final List<_VendorSummary> vendors;

  _PurchaseSummary({
    required this.totalAmount,
    required this.totalItems,
    required this.approvedCount,
    required this.pendingCount,
    required this.totalOrders,
    required this.vendors,
  });
}
