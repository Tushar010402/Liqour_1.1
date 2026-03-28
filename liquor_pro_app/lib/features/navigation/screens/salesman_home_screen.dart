import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/providers/shop_selection_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import '../../dashboard/models/dashboard_metrics.dart';
import '../../finance/widgets/add_expense_sheet.dart';
import '../../finance/widgets/cash_details_sheet.dart';
import '../../finance/widgets/upi_details_sheet.dart';
import '../../inventory/screens/purchase_entry_setup_screen.dart';
import '../../inventory/screens/stock_purchase_history_screen.dart';
import '../../sales/screens/sales_entry_setup_screen.dart';
import '../../sales/screens/simple_sales_history.dart';
import '../../settings/screens/settings_screen.dart';

/// Salesman Dashboard — pixel-matched to JSX Screen_Dashboard.
/// Date filters are dynamic and reload data from API.
/// Sales Summary is tappable -> shows sales history.
class SalesmanHomeScreen extends StatefulWidget {
  const SalesmanHomeScreen({super.key});

  @override
  State<SalesmanHomeScreen> createState() => _SalesmanHomeScreenState();
}

class _SalesmanHomeScreenState extends State<SalesmanHomeScreen> {
  // Maps UI chip index to DateFilterOption
  static const _filterOptions = [
    DateFilterOption.today,
    DateFilterOption.yesterday,
    DateFilterOption.last7Days,
    DateFilterOption.last30Days,
  ];
  static const _filterLabels = ['Today', 'Yesterday', 'Last 7 Days', 'Last Month'];

  /// When user is in Last 7 Days / Last Month and taps a specific date
  DateTime? _selectedDate;

  /// Tracks which multi-day range is active (survives custom date picks)
  /// null = not in a multi-day range (Today/Yesterday selected)
  DateFilterOption? _activeRangeFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    final shopProvider = Provider.of<ShopSelectionProvider>(context, listen: false);
    final dashboardProvider = Provider.of<DashboardProvider>(context, listen: false);
    final shopId = shopProvider.selectedShopId;
    if (shopId != null) {
      dashboardProvider.setSelectedShop(shopId);
    }
  }

  int _chipIndexFromFilter(DateFilterOption opt) {
    final idx = _filterOptions.indexOf(opt);
    return idx >= 0 ? idx : 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: Consumer<DashboardProvider>(
          builder: (context, dashboard, _) {
            return RefreshIndicator(
              onRefresh: () => dashboard.refreshDashboard(),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(dashboard),
                    // Show date strip for multi-day filters (persists when a specific date is tapped)
                    if (_activeRangeFilter == DateFilterOption.last7Days ||
                        _activeRangeFilter == DateFilterOption.last30Days)
                      _buildDateStrip(dashboard),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                      child: Column(
                        children: [
                          _buildSalesCard(dashboard),
                          const SizedBox(height: 14),
                          _buildPurchaseCard(dashboard),
                          const SizedBox(height: 14),
                          _buildDayClosingCard(dashboard),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(DashboardProvider dashboard) {
    return Consumer2<AuthProvider, ShopSelectionProvider>(
      builder: (context, auth, shop, _) {
        final today = DateFormat('dd-MM-yyyy').format(DateTime.now());
        final shopName = shop.selectedShopName ?? 'Select Shop';
        // Use activeRangeFilter for chip highlight when a specific date is picked
        final effectiveFilter = _activeRangeFilter ?? dashboard.dateFilter;
        final selectedChip = _chipIndexFromFilter(effectiveFilter);

        return Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          color: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RichText(
                          text: TextSpan(
                            style: AppTextStyles.bodySmall.copyWith(
                              fontSize: 13, fontWeight: FontWeight.w500, color: const Color(0xFF888888),
                            ),
                            children: [
                              TextSpan(text: 'Om ', style: TextStyle(color: const Color(0xFF2E7D32), fontWeight: FontWeight.w600)),
                              TextSpan(
                                text: 'Namah',
                                style: TextStyle(
                                  color: const Color(0xFF2E7D32),
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                              TextSpan(text: ' Shivaya, '),
                              TextSpan(text: today, style: const TextStyle(fontStyle: FontStyle.italic)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(Icons.view_list_rounded, color: Color(0xFF0D47A1), size: 22),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(shopName, style: AppTextStyles.h4.copyWith(
                                fontWeight: FontWeight.w900, fontSize: 22, color: const Color(0xFF1A1A2E),
                              ), overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
                    child: Container(
                      width: 36, height: 36,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFE8F0FE)),
                      child: const Icon(Icons.palette_outlined, color: Color(0xFF0D47A1), size: 18),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Date filter chips — actually wired to DashboardProvider
              SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _filterLabels.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final isSelected = selectedChip == index;
                    return GestureDetector(
                      onTap: () {
                        final filter = _filterOptions[index];
                        setState(() {
                          _selectedDate = null;
                          // Track multi-day range locally
                          if (filter == DateFilterOption.last7Days || filter == DateFilterOption.last30Days) {
                            _activeRangeFilter = filter;
                          } else {
                            _activeRangeFilter = null;
                          }
                        });
                        dashboard.setDateFilter(filter);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF0D47A1) : Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          border: isSelected ? null : Border.all(color: const Color(0xFFD0D5DD), width: 1.8),
                        ),
                        child: Text(
                          _filterLabels[index],
                          style: AppTextStyles.caption.copyWith(
                            fontWeight: FontWeight.w700, fontSize: 13,
                            color: isSelected ? Colors.white : const Color(0xFF1A1A2E),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
            ],
          ),
        );
      },
    );
  }

  /// Date strip — shows individual dates for Last 7 Days / Last Month
  Widget _buildDateStrip(DashboardProvider dashboard) {
    final isLast7 = _activeRangeFilter == DateFilterOption.last7Days;
    final dayCount = isLast7 ? 7 : 30;
    final today = DateTime.now();
    // Generate dates from today going backward
    final dates = List.generate(dayCount, (i) => today.subtract(Duration(days: i)));

    // "All" is selected when no specific date is picked
    final allSelected = _selectedDate == null;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        height: 64,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: dates.length + 1, // +1 for "All" chip
          itemBuilder: (context, index) {
            // First item = "All" (aggregate)
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () {
                    setState(() => _selectedDate = null);
                    // Reload the full range
                    dashboard.setDateFilter(
                      isLast7 ? DateFilterOption.last7Days : DateFilterOption.last30Days,
                    );
                  },
                  child: Container(
                    width: 52,
                    decoration: BoxDecoration(
                      color: allSelected ? const Color(0xFF0D47A1) : const Color(0xFFF5F6FA),
                      borderRadius: BorderRadius.circular(12),
                      border: allSelected ? null : Border.all(color: const Color(0xFFE0E3EA)),
                    ),
                    child: Center(
                      child: Text('All', style: AppTextStyles.bodySmall.copyWith(
                        fontWeight: FontWeight.w800, fontSize: 13,
                        color: allSelected ? Colors.white : const Color(0xFF1A1A2E),
                      )),
                    ),
                  ),
                ),
              );
            }

            final date = dates[index - 1];
            final isSelected = _selectedDate != null &&
                _selectedDate!.year == date.year &&
                _selectedDate!.month == date.month &&
                _selectedDate!.day == date.day;
            final isToday = date.year == today.year && date.month == today.month && date.day == today.day;
            final dayName = DateFormat('EEE').format(date); // Mon, Tue...
            final dayNum = date.day.toString();
            final monthName = DateFormat('MMM').format(date); // Jan, Feb...

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () {
                  setState(() => _selectedDate = date);
                  // Use named filters for today/yesterday (backend handles these reliably)
                  // Fall back to custom range for other specific dates
                  final now = DateTime.now();
                  final todayDate = DateTime(now.year, now.month, now.day);
                  final yesterdayDate = todayDate.subtract(const Duration(days: 1));
                  if (date.year == todayDate.year && date.month == todayDate.month && date.day == todayDate.day) {
                    dashboard.setDateFilter(DateFilterOption.today);
                  } else if (date.year == yesterdayDate.year && date.month == yesterdayDate.month && date.day == yesterdayDate.day) {
                    dashboard.setDateFilter(DateFilterOption.yesterday);
                  } else {
                    dashboard.setCustomDateRange(date, date);
                  }
                },
                child: Container(
                  width: 52,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF0D47A1)
                        : isToday
                            ? const Color(0xFFE8F0FE)
                            : const Color(0xFFF5F6FA),
                    borderRadius: BorderRadius.circular(12),
                    border: isSelected
                        ? null
                        : Border.all(
                            color: isToday ? const Color(0xFF0D47A1).withValues(alpha: 0.3) : const Color(0xFFE0E3EA)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(dayName, style: AppTextStyles.overline.copyWith(
                        fontWeight: FontWeight.w600, fontSize: 10,
                        color: isSelected ? Colors.white70 : const Color(0xFF888888),
                      )),
                      const SizedBox(height: 2),
                      Text(dayNum, style: AppTextStyles.h4.copyWith(
                        fontWeight: FontWeight.w900, fontSize: 18,
                        color: isSelected ? Colors.white : const Color(0xFF1A1A2E),
                      )),
                      Text(monthName, style: AppTextStyles.overline.copyWith(
                        fontWeight: FontWeight.w600, fontSize: 9,
                        color: isSelected ? Colors.white70 : const Color(0xFF888888),
                      )),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Sales Summary — tappable, shows real revenue, opens sales history or daily entry
  Widget _buildSalesCard(DashboardProvider dashboard) {
    final summary = dashboard.summary;
    final totalRevenue = summary?.totalRevenue ?? 0;
    final totalSales = summary?.todaysSales.totalSales ?? 0;
    final myStatus = summary?.myStatus;
    final hasSubmitted = myStatus?.status == 'submitted';
    final isLoading = dashboard.isLoading;

    return GestureDetector(
      onTap: () {
        // Tap sales card -> show sales history
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(
              title: const Text('Sales History'),
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              foregroundColor: const Color(0xFF1A1A2E),
            ),
            body: const SimpleSalesHistory(),
          ),
        ));
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 5)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.trending_up_rounded, color: Color(0xFF0D47A1), size: 18),
                const SizedBox(width: 8),
                Text('SALES SUMMARY', style: AppTextStyles.overline.copyWith(
                  fontWeight: FontWeight.w800, fontSize: 12, color: const Color(0xFF0D47A1), letterSpacing: 1.5)),
                const Spacer(),
                // Status badge
                if (myStatus != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: hasSubmitted ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      hasSubmitted ? (myStatus.recordStatus ?? 'submitted').toUpperCase() : 'NOT SUBMITTED',
                      style: AppTextStyles.overline.copyWith(
                        fontWeight: FontWeight.w700, fontSize: 9,
                        color: hasSubmitted ? const Color(0xFF2E7D32) : const Color(0xFFE65100),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    isLoading
                      ? Container(width: 120, height: 32, decoration: BoxDecoration(color: const Color(0xFFF0F1F4), borderRadius: BorderRadius.circular(6)))
                      : Text('\u20B9 ${_formatAmount(totalRevenue)}', style: AppTextStyles.h2.copyWith(
                          fontWeight: FontWeight.w900, fontSize: 32, color: const Color(0xFF1A1A2E))),
                    const SizedBox(height: 5),
                    Text(
                      totalSales > 0 ? '$totalSales entries' : 'Tap to view history',
                      style: AppTextStyles.bodySmall.copyWith(
                        fontWeight: FontWeight.w600, fontSize: 13, color: const Color(0xFF888888)),
                    ),
                  ],
                ),
                CustomPaint(size: const Size(60, 48), painter: _TrendChartPainter()),
              ],
            ),
            // Enter Sale button inside card
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                onPressed: () => _showEntryModeSelector(context),
                icon: const Icon(Icons.point_of_sale_rounded, size: 18),
                label: Text('Enter Daily Sale', style: AppTextStyles.bodySmall.copyWith(
                  fontWeight: FontWeight.w800, fontSize: 14, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D47A1),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Purchase Summary — tappable, navigates to purchase history
  Widget _buildPurchaseCard(DashboardProvider dashboard) {
    final summary = dashboard.summary;
    final isLoading = dashboard.isLoading;
    final totalReturns = summary?.todaysReturns.totalAmount ?? 0;
    final returnCount = summary?.todaysReturns.totalReturns ?? 0;
    final shopId = context.read<ShopSelectionProvider>().selectedShopId;

    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => StockPurchaseHistoryScreen(shopId: shopId),
        ));
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 5)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.shopping_cart_rounded, color: Color(0xFFE53935), size: 18),
                const SizedBox(width: 8),
                Text('PURCHASE SUMMARY', style: AppTextStyles.overline.copyWith(
                  fontWeight: FontWeight.w800, fontSize: 12, color: const Color(0xFFE53935), letterSpacing: 1.5)),
                const Spacer(),
                const Icon(Icons.chevron_right_rounded, color: Color(0xFFCCCCCC), size: 22),
              ],
            ),
            const SizedBox(height: 8),
            isLoading
              ? Container(width: 100, height: 32, decoration: BoxDecoration(color: const Color(0xFFF0F1F4), borderRadius: BorderRadius.circular(6)))
              : Text('\u20B9 ${_formatAmount(totalReturns)}', style: AppTextStyles.h2.copyWith(
                  fontWeight: FontWeight.w900, fontSize: 32, color: const Color(0xFF1A1A2E))),
            const SizedBox(height: 5),
            Text(
              returnCount > 0 ? '$returnCount items · Tap for history' : 'Tap to view purchase history',
              style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600, fontSize: 13, color: const Color(0xFF888888)),
            ),
            // Add Purchase button
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const PurchaseEntrySetupScreen()));
                },
                icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                label: Text('Add Purchase', style: AppTextStyles.bodySmall.copyWith(
                  fontWeight: FontWeight.w800, fontSize: 14, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D47A1),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Day Closing Reconciliation — matches JSX screenshot exactly
  Widget _buildDayClosingCard(DashboardProvider dashboard) {
    final cashAmount = dashboard.effectiveCashAmount;
    final upiAmount = dashboard.effectiveUpiAmount;
    final totalExpense = dashboard.effectiveExpenseAmount;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B3E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.description_outlined, color: Color(0xFF5B9BD5), size: 18),
              const SizedBox(width: 8),
              Text('DAY CLOSING RECONCILIATION', style: AppTextStyles.overline.copyWith(
                fontWeight: FontWeight.w800, fontSize: 12, color: Colors.white, letterSpacing: 1.3)),
            ],
          ),
          const SizedBox(height: 16),
          // Daily Expenses
          Container(
            padding: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Daily Expenses', style: AppTextStyles.bodySmall.copyWith(
                  fontWeight: FontWeight.w500, fontSize: 14, color: Colors.white.withValues(alpha: 0.4))),
                Text('\u20B9${_formatAmount(totalExpense)}', style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w800, fontSize: 17, color: const Color(0xFFE53935))),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Cash + UPI boxes — both tappable to enter amounts
          Row(
            children: [
              Expanded(child: _buildDarkBox('CASH IN HAND', '\u20B9${_formatAmount(cashAmount)}',
                  onTap: () => CashDetailsSheet.show(context, onAdd: (denominations, total) {
                    dashboard.updateCashAmount(denominations, total);
                  }))),
              const SizedBox(width: 12),
              Expanded(child: _buildDarkBox('TOTAL UPI', '\u20B9${_formatAmount(upiAmount)}',
                  onTap: () => UpiDetailsSheet.show(context, onAdd: (entries, total) {
                    dashboard.updateUpiAmount(entries, total);
                  }))),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () => AddExpenseSheet.show(context, onAdd: (expenses) {
                final total = expenses.values.fold(0.0, (s, v) => s + v);
                dashboard.updateExpenseAmount(expenses, total);
              }),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2196F3),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Text('Add Expenses', style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w800, fontSize: 15, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  /// Navigate to entry setup screen — passes dashboard's selected date
  void _showEntryModeSelector(BuildContext context) {
    final dashboard = Provider.of<DashboardProvider>(context, listen: false);
    final filter = dashboard.dateFilter;
    DateTime date;
    String label;
    switch (filter) {
      case DateFilterOption.today:
        date = DateTime.now();
        label = 'Today';
      case DateFilterOption.yesterday:
        date = DateTime.now().subtract(const Duration(days: 1));
        label = 'Yesterday';
      default:
        // For custom/range, use selectedDate if set, otherwise yesterday
        date = _selectedDate ?? DateTime.now().subtract(const Duration(days: 1));
        label = DateFormat('dd MMM').format(date);
    }
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => SalesEntrySetupScreen(initialDate: date, initialDateLabel: label),
    ));
  }

  Widget _buildDarkBox(String label, String value, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTextStyles.overline.copyWith(
              fontWeight: FontWeight.w800, fontSize: 10, color: const Color(0xFF5B9BD5), letterSpacing: 1.2)),
            const SizedBox(height: 8),
            Text(value, style: AppTextStyles.h4.copyWith(
              fontWeight: FontWeight.w900, fontSize: 24, color: Colors.white)),
          ],
        ),
      ),
    );
  }

  String _formatAmount(double amount) {
    if (amount >= 1000) return NumberFormat('#,##,###').format(amount.toInt());
    return amount.toStringAsFixed(0);
  }
}

class _TrendChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFC8D6E5)..strokeWidth = 2.8
      ..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(5, size.height * 0.83)..lineTo(size.width * 0.27, size.height * 0.63)
      ..lineTo(size.width * 0.4, size.height * 0.71)..lineTo(size.width * 0.63, size.height * 0.25)
      ..lineTo(size.width * 0.87, size.height * 0.17);
    canvas.drawPath(path, paint);
    final ap = Paint()..color = const Color(0xFFC8D6E5)..strokeWidth = 2.2..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(size.width * 0.77, size.height * 0.1), Offset(size.width * 0.9, size.height * 0.17), ap);
    canvas.drawLine(Offset(size.width * 0.83, size.height * 0.31), Offset(size.width * 0.9, size.height * 0.17), ap);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
