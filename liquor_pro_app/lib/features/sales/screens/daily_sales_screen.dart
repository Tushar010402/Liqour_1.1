import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/theme/ios_design_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/services/auth_service.dart';
import '../providers/daily_sales_provider.dart';
import '../models/daily_sales_models.dart';
import '../services/daily_sales_service.dart';

/// Modern Daily Sales Summary Screen with Quick Filters & Analytics
class DailySalesScreen extends StatefulWidget {
  const DailySalesScreen({super.key});

  @override
  State<DailySalesScreen> createState() => _DailySalesScreenState();
}

class _DailySalesScreenState extends State<DailySalesScreen> with WidgetsBindingObserver {
  TimePeriod _selectedPeriod = TimePeriod.fifteenDays;
  bool _isInitialLoad = true;

  /// null = "All Shops", otherwise shop ID string
  String? _selectedShopId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSalesData();
      _isInitialLoad = false;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialLoad && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadSalesData();
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _loadSalesData();
    }
  }

  Future<void> _loadSalesData() async {
    final dateRange = _getDateRange();

    final provider = context.read<DailySalesProvider>();
    // Fetch without shop filter so we get ALL shops' data for comparison
    await provider.fetchRecords(
      startDate: dateRange.start,
      endDate: dateRange.end,
    );
  }

  DateRange _getDateRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    switch (_selectedPeriod) {
      case TimePeriod.yesterday:
        final yesterday = today.subtract(const Duration(days: 1));
        return DateRange(start: yesterday, end: today);
      case TimePeriod.sevenDays:
        return DateRange(
          start: today.subtract(const Duration(days: 7)),
          end: today,
        );
      case TimePeriod.fifteenDays:
        return DateRange(
          start: today.subtract(const Duration(days: 15)),
          end: today,
        );
      case TimePeriod.oneMonth:
        return DateRange(
          start: DateTime(now.year, now.month - 1, now.day),
          end: today,
        );
      case TimePeriod.quarterly:
        final quarter = ((now.month - 1) ~/ 3);
        final quarterStartMonth = quarter * 3 + 1;
        return DateRange(
          start: DateTime(now.year, quarterStartMonth, 1),
          end: today,
        );
      case TimePeriod.halfYear:
        return DateRange(
          start: DateTime(now.year, now.month - 6, now.day),
          end: today,
        );
      case TimePeriod.oneYear:
        return DateRange(
          start: DateTime(now.year - 1, now.month, now.day),
          end: today,
        );
    }
  }

  /// Filter records by selected shop
  List<DailySalesRecord> _filterByShop(List<DailySalesRecord> records) {
    if (_selectedShopId == null) return records;
    return records.where((r) => r.shopId == _selectedShopId).toList();
  }

  /// Extract unique shops from records
  List<_ShopInfo> _extractShops(List<DailySalesRecord> records) {
    final Map<String, String> shopMap = {};
    for (final r in records) {
      if (!shopMap.containsKey(r.shopId)) {
        shopMap[r.shopId] = r.shopName ?? 'Shop';
      }
    }
    return shopMap.entries
        .map((e) => _ShopInfo(id: e.key, name: e.value))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainerHighest,
      child: Column(
        children: [
          // Period filter bar
          _buildPeriodFilterBar(),

          // Sales content
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadSalesData,
              color: cs.primary,
              child: Consumer<DailySalesProvider>(
                builder: (context, provider, child) {
                  if (provider.isLoading) {
                    return _buildLoadingState();
                  }

                  if (provider.records.isEmpty) {
                    return _buildEmptyState();
                  }

                  final allRecords = provider.records;
                  final shops = _extractShops(allRecords);
                  final filtered = _filterByShop(allRecords);
                  final summary = _calculateSummary(filtered);

                  return _buildSalesContent(
                    summary: summary,
                    records: filtered,
                    allRecords: allRecords,
                    shops: shops,
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
  // Period Filter Bar
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPeriodFilterBar() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surface,
      padding: EdgeInsets.fromLTRB(
        iOSDesignTokens.space16, iOSDesignTokens.space12,
        iOSDesignTokens.space16, iOSDesignTokens.space12,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: TimePeriod.values.map((period) {
            final isSelected = _selectedPeriod == period;
            return Padding(
              padding: EdgeInsets.only(right: iOSDesignTokens.space8),
              child: GestureDetector(
                onTap: () {
                  setState(() => _selectedPeriod = period);
                  _loadSalesData();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
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
                      color: isSelected
                          ? Colors.white
                          : cs.onSurfaceVariant,
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
  // Shop Filter Chips
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
            'Loading sales data...',
            style: AppTextStyles.caption.copyWith(color: cs.onSurfaceVariant),
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
                CupertinoIcons.chart_bar_circle,
                size: 56,
                color: cs.outlineVariant,
              ),
              SizedBox(height: iOSDesignTokens.space12),
              Text(
                'No Sales Data',
                style: AppTextStyles.h5.copyWith(color: cs.onSurface),
              ),
              SizedBox(height: iOSDesignTokens.space4),
              Text(
                'No sales recorded for ${_selectedPeriod.label.toLowerCase()}',
                style: AppTextStyles.caption.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Main Sales Content
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSalesContent({
    required SalesSummary summary,
    required List<DailySalesRecord> records,
    required List<DailySalesRecord> allRecords,
    required List<_ShopInfo> shops,
  }) {
    return ListView(
      padding: EdgeInsets.all(iOSDesignTokens.space16),
      children: [
        // Shop filter chips
        _buildShopFilterChips(shops),

        // Summary stats
        _buildSummaryGrid(summary),
        SizedBox(height: iOSDesignTokens.space20),

        // Shop-wise breakdown (when "All Shops" selected)
        if (_selectedShopId == null && shops.length > 1) ...[
          _buildSectionHeader('Shop-wise Sales', Icons.store_rounded),
          SizedBox(height: iOSDesignTokens.space12),
          _buildShopWiseBreakdown(allRecords, shops),
          SizedBox(height: iOSDesignTokens.space20),
        ],

        // Sales trend chart
        _buildSectionHeader('Sales Trend', CupertinoIcons.graph_square),
        SizedBox(height: iOSDesignTokens.space12),
        _buildSalesTrendChart(records),
        SizedBox(height: iOSDesignTokens.space20),

        // Payment methods
        _buildSectionHeader('Payment Methods', CupertinoIcons.creditcard),
        SizedBox(height: iOSDesignTokens.space12),
        _buildPaymentMethodsChart(summary),
        SizedBox(height: iOSDesignTokens.space20),

        // Top products
        if (summary.topProducts.isNotEmpty) ...[
          _buildSectionHeader('Top Selling Products', CupertinoIcons.star_fill),
          SizedBox(height: iOSDesignTokens.space12),
          _buildTopProductsList(summary.topProducts),
          SizedBox(height: iOSDesignTokens.space20),
        ],

        // Recent transactions
        _buildSectionHeader('Recent Transactions', CupertinoIcons.list_bullet),
        SizedBox(height: iOSDesignTokens.space12),
        _buildRecentTransactions(records),

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
  // Summary Grid (4 cards)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSummaryGrid(SalesSummary summary) {
    final cs = Theme.of(context).colorScheme;
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.5,
      children: [
        _SummaryCard(
          title: 'Total Sales',
          value: Formatters.currency(summary.totalSales),
          icon: CupertinoIcons.money_dollar_circle_fill,
          color: AppColors.success,
        ),
        _SummaryCard(
          title: 'Transactions',
          value: '${summary.totalTransactions}',
          icon: CupertinoIcons.doc_text_fill,
          color: cs.primary,
        ),
        _SummaryCard(
          title: 'Items Sold',
          value: '${summary.totalItems}',
          icon: CupertinoIcons.cube_box_fill,
          color: AppColors.warning,
        ),
        _SummaryCard(
          title: 'Avg. Sale',
          value: Formatters.currency(summary.averageSale),
          icon: CupertinoIcons.chart_bar_circle_fill,
          color: const Color(0xFF9C27B0),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Shop-wise Breakdown Table
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildShopWiseBreakdown(
      List<DailySalesRecord> allRecords, List<_ShopInfo> shops) {
    final cs = Theme.of(context).colorScheme;

    // Group records by shop
    final Map<String, List<DailySalesRecord>> shopRecords = {};
    for (final r in allRecords) {
      shopRecords.putIfAbsent(r.shopId, () => []).add(r);
    }

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
                  child: Text('Shop',
                      style: AppTextStyles.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant)),
                ),
                Expanded(
                  flex: 2,
                  child: Text('Sales',
                      textAlign: TextAlign.right,
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
          // Shop rows
          ...shops.map((shop) {
            final records = shopRecords[shop.id] ?? [];
            final total = records.fold<double>(
                0, (sum, r) => sum + r.totalSalesAmount);
            return InkWell(
              onTap: () => setState(() => _selectedShopId = shop.id),
              child: Container(
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
                          Icon(Icons.store_rounded,
                              size: 16, color: cs.primary.withValues(alpha: 0.7)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              shop.name,
                              style: AppTextStyles.bodySmall.copyWith(
                                  fontWeight: FontWeight.w500),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '${records.length}',
                        textAlign: TextAlign.right,
                        style: AppTextStyles.bodySmall
                            .copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        Formatters.currency(total),
                        textAlign: TextAlign.right,
                        style: AppTextStyles.bodySmall.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.success,
                        ),
                      ),
                    ),
                  ],
                ),
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
                  flex: 2,
                  child: Text(
                    '${allRecords.length}',
                    textAlign: TextAlign.right,
                    style: AppTextStyles.bodySmall
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    Formatters.currency(allRecords.fold<double>(
                        0, (sum, r) => sum + r.totalSalesAmount)),
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
  // Sales Trend Chart
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSalesTrendChart(List<DailySalesRecord> records) {
    final cs = Theme.of(context).colorScheme;

    // Group by date
    final Map<String, double> dailySales = {};
    for (var record in records) {
      final dateKey = Formatters.dateOnly(record.recordDate);
      dailySales[dateKey] = (dailySales[dateKey] ?? 0) + record.totalSalesAmount;
    }

    final sortedDates = dailySales.keys.toList()..sort();
    final spots = <FlSpot>[];
    for (int i = 0; i < sortedDates.length && i < 30; i++) {
      spots.add(FlSpot(i.toDouble(), dailySales[sortedDates[i]] ?? 0));
    }

    if (spots.isEmpty) return _buildEmptyChartCard();

    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final interval = maxY > 0 ? maxY / 4 : 1.0;

    return Container(
      height: 220,
      padding: const EdgeInsets.fromLTRB(8, 20, 20, 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
        border: Border.all(color: cs.outline.withValues(alpha: 0.15)),
      ),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: interval,
            getDrawingHorizontalLine: (value) {
              return FlLine(color: cs.outlineVariant.withValues(alpha: 0.3), strokeWidth: 1);
            },
          ),
          titlesData: FlTitlesData(
            show: true,
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: spots.length > 7 ? spots.length / 5 : 1,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i >= 0 && i < sortedDates.length) {
                    final parts = sortedDates[i].split('-');
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '${parts[2]}/${parts[1]}',
                        style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                      ),
                    );
                  }
                  return const Text('');
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                interval: interval,
                getTitlesWidget: (value, meta) {
                  if (value == 0) return const Text('');
                  return Text(
                    '₹${(value / 1000).toStringAsFixed(0)}k',
                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          minX: 0,
          maxX: spots.length - 1.0,
          minY: 0,
          maxY: maxY * 1.15,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: cs.primary,
              barWidth: 2.5,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: spots.length <= 15,
                getDotPainter: (spot, percent, barData, index) {
                  return FlDotCirclePainter(
                    radius: 3.5,
                    color: Colors.white,
                    strokeWidth: 2,
                    strokeColor: cs.primary,
                  );
                },
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    cs.primary.withValues(alpha: 0.15),
                    cs.primary.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Payment Methods Chart
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPaymentMethodsChart(SalesSummary summary) {
    final cs = Theme.of(context).colorScheme;
    final paymentData = [
      PaymentMethodData('Cash', summary.cashSales, AppColors.success),
      PaymentMethodData('Card', summary.cardSales, cs.primary),
      PaymentMethodData('UPI', summary.upiSales, const Color(0xFF9C27B0)),
      PaymentMethodData('Credit', summary.creditSales, AppColors.warning),
    ].where((data) => data.amount > 0).toList();

    if (paymentData.isEmpty) return _buildEmptyChartCard();

    final total = paymentData.fold<double>(0, (sum, d) => sum + d.amount);

    return Container(
      padding: EdgeInsets.all(iOSDesignTokens.space16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
        border: Border.all(color: cs.outline.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          // Horizontal bar breakdown (cleaner than pie for mobile)
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 14,
              child: Row(
                children: paymentData.map((d) {
                  final fraction = d.amount / total;
                  return Expanded(
                    flex: (fraction * 1000).toInt().clamp(1, 1000),
                    child: Container(color: d.color),
                  );
                }).toList(),
              ),
            ),
          ),
          SizedBox(height: iOSDesignTokens.space16),
          // Legend rows
          ...paymentData.map((d) {
            final pct = (d.amount / total * 100).toStringAsFixed(1);
            return Padding(
              padding: EdgeInsets.only(bottom: iOSDesignTokens.space8),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: d.color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(d.method,
                      style: AppTextStyles.bodySmall
                          .copyWith(color: cs.onSurfaceVariant)),
                  const Spacer(),
                  Text(Formatters.currency(d.amount),
                      style: AppTextStyles.bodySmall
                          .copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 42,
                    child: Text('$pct%',
                        textAlign: TextAlign.right,
                        style: AppTextStyles.caption
                            .copyWith(color: cs.onSurfaceVariant)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Top Products
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTopProductsList(List<ProductSales> products) {
    final cs = Theme.of(context).colorScheme;
    final top = products.take(5).toList();

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
        border: Border.all(color: cs.outline.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: List.generate(top.length, (i) {
          final product = top[i];
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: i < top.length - 1
                  ? Border(
                      bottom: BorderSide(
                          color: cs.outline.withValues(alpha: 0.08)))
                  : null,
            ),
            child: Row(
              children: [
                // Rank badge
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: i == 0
                        ? AppColors.warning.withValues(alpha: 0.15)
                        : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: i == 0 ? AppColors.warning : cs.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(product.name,
                          style: AppTextStyles.bodySmall
                              .copyWith(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text('${product.quantity} units',
                          style: AppTextStyles.caption
                              .copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                Text(
                  Formatters.currency(product.total),
                  style: AppTextStyles.bodySmall.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.success,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Recent Transactions
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildRecentTransactions(List<DailySalesRecord> records) {
    final cs = Theme.of(context).colorScheme;
    final recent = records.take(10).toList();

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
        border: Border.all(color: cs.outline.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: List.generate(recent.length, (i) {
          final record = recent[i];
          final statusColor = _getStatusColor(record.status);
          return InkWell(
            onTap: () => _showRecordDetails(record),
            borderRadius: i == 0
                ? BorderRadius.vertical(
                    top: Radius.circular(iOSDesignTokens.radiusMedium))
                : i == recent.length - 1
                    ? BorderRadius.vertical(
                        bottom:
                            Radius.circular(iOSDesignTokens.radiusMedium))
                    : null,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: i < recent.length - 1
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
                    child: Icon(_getStatusIcon(record.status),
                        color: statusColor, size: 18),
                  ),
                  const SizedBox(width: 12),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${record.totalItems > 0 ? record.totalItems : record.items.length} items',
                          style: AppTextStyles.bodySmall
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                Formatters.dateTime(record.recordDate),
                                style: AppTextStyles.caption
                                    .copyWith(color: cs.onSurfaceVariant),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (record.shopName != null &&
                                _selectedShopId == null) ...[
                              Text(' · ',
                                  style: AppTextStyles.caption
                                      .copyWith(color: cs.outlineVariant)),
                              Flexible(
                                child: Text(
                                  record.shopName!,
                                  style: AppTextStyles.caption
                                      .copyWith(color: cs.onSurfaceVariant),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                            if (record.hasLocation) ...[
                              const SizedBox(width: 4),
                              Icon(Icons.location_on,
                                  size: 12, color: AppColors.success),
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
                        Formatters.currency(record.totalSalesAmount),
                        style: AppTextStyles.bodySmall.copyWith(
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface),
                      ),
                      const SizedBox(height: 3),
                      _buildStatusBadge(record.status),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    final color = _getStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.toUpperCase(),
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
  // Empty Chart Placeholder
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildEmptyChartCard() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 140,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
        border: Border.all(color: cs.outline.withValues(alpha: 0.15)),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(CupertinoIcons.chart_bar, size: 32, color: cs.outlineVariant),
            SizedBox(height: iOSDesignTokens.space8),
            Text('No data available',
                style: AppTextStyles.caption
                    .copyWith(color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Status helpers
  // ═══════════════════════════════════════════════════════════════════════════

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return AppColors.success;
      case 'pending':
        return AppColors.warning;
      case 'rejected':
        return AppColors.error;
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return CupertinoIcons.check_mark_circled_solid;
      case 'pending':
        return CupertinoIcons.clock_fill;
      case 'rejected':
        return CupertinoIcons.xmark_circle_fill;
      default:
        return CupertinoIcons.doc_text_fill;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Record Details Modal
  // ═══════════════════════════════════════════════════════════════════════════

  void _showRecordDetails(DailySalesRecord record) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator.adaptive()),
    );

    DailySalesRecord fullRecord = record;
    if (record.id != null) {
      try {
        final authService = context.read<AuthService>();
        final service = DailySalesService(authService);
        final response = await service.getDailySalesRecordById(record.id!);
        if (response.success && response.data != null) {
          fullRecord = response.data!;
        }
      } catch (_) {
        // Fall back to list record
      }
    }

    if (mounted) Navigator.of(context).pop();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          final cs = Theme.of(context).colorScheme;
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
                          color: _getStatusColor(fullRecord.status)
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          _getStatusIcon(fullRecord.status),
                          color: _getStatusColor(fullRecord.status),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Daily Sales Record',
                                style: AppTextStyles.h5),
                            Text(
                              Formatters.dateTime(fullRecord.recordDate),
                              style: AppTextStyles.caption
                                  .copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      _buildStatusBadge(fullRecord.status),
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
                      // Location
                      if (fullRecord.hasLocation) ...[
                        _buildDetailSection(
                          'Sale Location',
                          Icons.location_on,
                          AppColors.success,
                          [
                            _buildDetailRow('Latitude',
                                '${fullRecord.latitude?.toStringAsFixed(6)}'),
                            _buildDetailRow('Longitude',
                                '${fullRecord.longitude?.toStringAsFixed(6)}'),
                            _buildDetailRow('Accuracy',
                                '${fullRecord.locationAccuracy ?? "Unknown"}m'),
                          ],
                          trailing: TextButton.icon(
                            onPressed: () => _openInMaps(
                                fullRecord.latitude!, fullRecord.longitude!),
                            icon: const Icon(Icons.map_outlined, size: 18),
                            label: const Text('Maps'),
                            style: TextButton.styleFrom(
                                foregroundColor: AppColors.success),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color:
                                    AppColors.warning.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.location_off,
                                  color: AppColors.warning, size: 20),
                              const SizedBox(width: 10),
                              Text('Location not captured',
                                  style: AppTextStyles.bodySmall
                                      .copyWith(color: AppColors.warning)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Sales summary
                      _buildDetailSection(
                        'Sales Summary',
                        CupertinoIcons.money_dollar_circle,
                        cs.primary,
                        [
                          _buildDetailRow('Total Amount',
                              Formatters.currency(fullRecord.totalSalesAmount)),
                          _buildDetailRow(
                              'Items', '${fullRecord.items.length} products'),
                          _buildDetailRow(
                              'Shop', fullRecord.shopName ?? fullRecord.shopId),
                          if (fullRecord.createdByName != null)
                            _buildDetailRow(
                                'Recorded by', fullRecord.createdByName!),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Payment breakdown
                      _buildDetailSection(
                        'Payment Breakdown',
                        CupertinoIcons.creditcard,
                        AppColors.info,
                        [
                          _buildDetailRow('Cash',
                              Formatters.currency(fullRecord.totalCashAmount)),
                          _buildDetailRow('Card',
                              Formatters.currency(fullRecord.totalCardAmount)),
                          _buildDetailRow('UPI',
                              Formatters.currency(fullRecord.totalUpiAmount)),
                          _buildDetailRow('Credit',
                              Formatters.currency(fullRecord.totalCreditAmount)),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Items
                      if (fullRecord.items.isNotEmpty) ...[
                        Text('Items Sold',
                            style: AppTextStyles.bodyMedium
                                .copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        ...fullRecord.items.map((item) => Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            item.productName ?? 'Product',
                                            style: AppTextStyles.bodySmall
                                                .copyWith(
                                                    fontWeight:
                                                        FontWeight.w500)),
                                        if (item.brandName != null ||
                                            item.size != null)
                                          Text(
                                            '${item.brandName ?? ""} ${item.size ?? ""}'
                                                .trim(),
                                            style: AppTextStyles.caption
                                                .copyWith(
                                                    color:
                                                        cs.onSurfaceVariant),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.end,
                                    children: [
                                      Text('x${item.quantity}',
                                          style: AppTextStyles.bodySmall
                                              .copyWith(
                                                  fontWeight:
                                                      FontWeight.w500)),
                                      Text(
                                          Formatters.currency(
                                              item.totalAmount),
                                          style: AppTextStyles.caption
                                              .copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.success)),
                                    ],
                                  ),
                                ],
                              ),
                            )),
                      ],

                      // Approval info
                      if (fullRecord.status == 'approved' &&
                          fullRecord.approvedByName != null) ...[
                        const SizedBox(height: 16),
                        _buildDetailSection(
                          'Approval Info',
                          CupertinoIcons.check_mark_circled,
                          AppColors.success,
                          [
                            _buildDetailRow(
                                'Approved by', fullRecord.approvedByName!),
                            if (fullRecord.approvedAt != null)
                              _buildDetailRow('Approved at',
                                  Formatters.dateTime(fullRecord.approvedAt!)),
                          ],
                        ),
                      ],

                      // Notes
                      if (fullRecord.notes.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _buildDetailSection(
                          'Notes',
                          CupertinoIcons.doc_text,
                          cs.onSurfaceVariant,
                          [
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 4),
                              child: Text(fullRecord.notes,
                                  style: AppTextStyles.bodySmall),
                            ),
                          ],
                        ),
                      ],

                      // Copy button for rejected records
                      if (fullRecord.status.toLowerCase() == 'rejected') ...[
                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color:
                                    AppColors.warning.withValues(alpha: 0.2)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                      CupertinoIcons
                                          .exclamationmark_triangle_fill,
                                      color: AppColors.warning,
                                      size: 18),
                                  const SizedBox(width: 8),
                                  Text('Record Rejected',
                                      style: AppTextStyles.bodySmall.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.warning)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Copy this record to create a new draft. Make corrections and submit again.',
                                style: AppTextStyles.caption
                                    .copyWith(color: AppColors.warning),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () => _copyRejectedRecord(
                                      context, fullRecord),
                                  icon: const Icon(CupertinoIcons.doc_on_doc,
                                      size: 16),
                                  label: const Text('Copy to New Draft'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.warning,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
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
      ),
    );
  }

  Widget _buildDetailSection(
    String title,
    IconData icon,
    Color color,
    List<Widget> children, {
    Widget? trailing,
  }) {
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
              if (trailing != null) ...[const Spacer(), trailing],
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style:
                  AppTextStyles.bodySmall.copyWith(color: cs.onSurfaceVariant)),
          Text(value,
              style: AppTextStyles.bodySmall
                  .copyWith(fontWeight: FontWeight.w500, color: cs.onSurface)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Actions
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _openInMaps(double lat, double lng) async {
    final googleMapsUrl =
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    final appleMapsUrl = Uri.parse('https://maps.apple.com/?q=$lat,$lng');

    try {
      if (await canLaunchUrl(googleMapsUrl)) {
        await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
      } else if (await canLaunchUrl(appleMapsUrl)) {
        await launchUrl(appleMapsUrl, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open maps: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _copyRejectedRecord(
      BuildContext modalContext, DailySalesRecord record) async {
    if (record.id == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Cannot copy: Record ID missing'),
              backgroundColor: Colors.red),
        );
      }
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(ctx).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator.adaptive(),
              SizedBox(height: 16),
              Text('Creating new draft...'),
            ],
          ),
        ),
      ),
    );

    try {
      final authService = context.read<AuthService>();
      final service = DailySalesService(authService);
      final result = await service.copyDailySalesRecord(record.id!);

      if (mounted) Navigator.of(context).pop();

      if (result.success && result.data != null) {
        if (mounted) Navigator.of(modalContext).pop();
        _loadSalesData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(CupertinoIcons.check_mark_circled, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Record copied! New draft created.'),
                ],
              ),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.error ?? 'Failed to copy record'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Calculate Summary
  // ═══════════════════════════════════════════════════════════════════════════

  SalesSummary _calculateSummary(List<DailySalesRecord> records) {
    double totalSales = 0;
    double cashSales = 0;
    double cardSales = 0;
    double upiSales = 0;
    double creditSales = 0;
    int totalItems = 0;

    final Map<String, ProductSales> productSales = {};

    for (var record in records) {
      totalSales += record.totalSalesAmount;
      cashSales += record.totalCashAmount;
      cardSales += record.totalCardAmount;
      upiSales += record.totalUpiAmount;
      creditSales += record.totalCreditAmount;

      for (var item in record.items) {
        totalItems += item.quantity;

        final key = item.productId;
        if (productSales.containsKey(key)) {
          productSales[key] = ProductSales(
            name: item.productName ?? 'Unknown',
            quantity: productSales[key]!.quantity + item.quantity,
            total: productSales[key]!.total + item.totalAmount,
          );
        } else {
          productSales[key] = ProductSales(
            name: item.productName ?? 'Unknown',
            quantity: item.quantity,
            total: item.totalAmount,
          );
        }
      }
    }

    final topProducts = productSales.values.toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    return SalesSummary(
      totalSales: totalSales,
      totalTransactions: records.length,
      totalItems: totalItems,
      averageSale: records.isNotEmpty ? totalSales / records.length : 0,
      cashSales: cashSales,
      cardSales: cardSales,
      upiSales: upiSales,
      creditSales: creditSales,
      topProducts: topProducts,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Summary Card Widget
// ══════════════════════════════════════════════════════════════════════════════

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard({
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
// Helper class
// ══════════════════════════════════════════════════════════════════════════════

class _ShopInfo {
  final String id;
  final String name;
  const _ShopInfo({required this.id, required this.name});
}

// ══════════════════════════════════════════════════════════════════════════════
// Data Models
// ══════════════════════════════════════════════════════════════════════════════

enum TimePeriod {
  yesterday('Yesterday'),
  sevenDays('7 Days'),
  fifteenDays('15 Days'),
  oneMonth('1 Month'),
  quarterly('Quarter'),
  halfYear('6 Months'),
  oneYear('1 Year');

  final String label;
  const TimePeriod(this.label);
}

class DateRange {
  final DateTime start;
  final DateTime end;

  DateRange({required this.start, required this.end});
}

class SalesSummary {
  final double totalSales;
  final int totalTransactions;
  final int totalItems;
  final double averageSale;
  final double cashSales;
  final double cardSales;
  final double upiSales;
  final double creditSales;
  final List<ProductSales> topProducts;

  SalesSummary({
    required this.totalSales,
    required this.totalTransactions,
    required this.totalItems,
    required this.averageSale,
    required this.cashSales,
    required this.cardSales,
    required this.upiSales,
    required this.creditSales,
    required this.topProducts,
  });
}

class ProductSales {
  final String name;
  final int quantity;
  final double total;

  ProductSales({
    required this.name,
    required this.quantity,
    required this.total,
  });
}

class PaymentMethodData {
  final String method;
  final double amount;
  final Color color;

  PaymentMethodData(this.method, this.amount, this.color);
}
