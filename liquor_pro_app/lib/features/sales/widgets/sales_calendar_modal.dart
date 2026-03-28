import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/sale_details_modal.dart';
import '../models/daily_sales_models.dart';
import '../providers/daily_sales_provider.dart';
import '../services/daily_sales_service.dart';

/// Sales Calendar Modal - iOS 2026 style draggable bottom sheet
/// Features:
/// - Category-based coloring (Beer = amber, Spirits = purple)
/// - Status dots (approved/pending/rejected) on each date
/// - Quick approve/reject actions for pending records
/// - Monthly summary statistics
/// - Shop filter dropdown
/// - Drag to dismiss (iOS style)
class SalesCalendarModal extends StatefulWidget {
  final String? initialShopId;
  final VoidCallback? onRecordUpdated;
  final ScrollController? scrollController;

  const SalesCalendarModal({
    super.key,
    this.initialShopId,
    this.onRecordUpdated,
    this.scrollController,
  });

  @override
  State<SalesCalendarModal> createState() => _SalesCalendarModalState();
}

class _SalesCalendarModalState extends State<SalesCalendarModal> {
  late DateTime _currentMonth;
  DateTime? _selectedDate;
  List<DailySalesRecord> _monthRecords = [];
  bool _isLoading = false;
  String? _selectedShopId;

  // Grouped records by date
  Map<String, List<DailySalesRecord>> _recordsByDate = {};

  // Available shops from data
  final Map<String, String> _availableShops = {};

  @override
  void initState() {
    super.initState();
    _currentMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
    _selectedShopId = widget.initialShopId;
    _loadMonthData();
  }

  Future<void> _loadMonthData() async {
    setState(() => _isLoading = true);

    try {
      final authService = context.read<AuthService>();
      final service = DailySalesService(authService);

      final startDate = _currentMonth;
      final endDate = DateTime(_currentMonth.year, _currentMonth.month + 1, 0);

      debugPrint('📅 [Calendar] Loading month data: ${DateFormat('MMM yyyy').format(_currentMonth)}');
      debugPrint('📅 [Calendar] Selected shop filter: $_selectedShopId');
      debugPrint('📅 [Calendar] Date range: ${DateFormat('yyyy-MM-dd').format(startDate)} to ${DateFormat('yyyy-MM-dd').format(endDate)}');

      // ═══════════════════════════════════════════════════════════════════════
      // PAGINATION FIX: Fetch ALL records for the month
      // Backend may limit page_size, so we need to fetch multiple pages
      // ═══════════════════════════════════════════════════════════════════════
      List<DailySalesRecord> allRecords = [];
      int currentPage = 1;
      const int pageSize = 100; // Use reasonable page size for pagination
      bool hasMorePages = true;

      while (hasMorePages) {
        debugPrint('📅 [Calendar] Fetching page $currentPage...');

        final result = await service.getDailySalesRecords(
          startDate: startDate,
          endDate: endDate,
          page: currentPage,
          pageSize: pageSize,
        );

        if (result.isSuccess && result.data != null) {
          final records = result.data!;
          debugPrint('📅 [Calendar] Page $currentPage returned ${records.length} records');

          allRecords.addAll(records);

          // Check if there are more pages
          // If we got fewer records than pageSize, we've reached the end
          if (records.length < pageSize) {
            hasMorePages = false;
            debugPrint('📅 [Calendar] Last page reached (got ${records.length} < $pageSize)');
          } else {
            currentPage++;
            // Safety limit to prevent infinite loops
            if (currentPage > 50) {
              debugPrint('⚠️ [Calendar] Safety limit reached, stopping pagination');
              hasMorePages = false;
            }
          }
        } else {
          debugPrint('❌ [Calendar] Page $currentPage failed: ${result.error}');
          hasMorePages = false;
        }
      }

      debugPrint('📅 [Calendar] Total records fetched: ${allRecords.length} across $currentPage pages');

      // Log date range of returned records
      if (allRecords.isNotEmpty) {
        final dates = allRecords.map((r) => r.recordDate).toList()..sort();
        debugPrint('📅 [Calendar] Record dates: ${DateFormat('MMM dd').format(dates.first)} to ${DateFormat('MMM dd').format(dates.last)}');
      }

      // Collect all unique shops from the data
      final newShops = <String, String>{};
      for (final record in allRecords) {
        if (record.shopId.isNotEmpty && !newShops.containsKey(record.shopId)) {
          newShops[record.shopId] = record.shopName ?? record.shopId;
        }
      }
      // Update available shops (preserve existing, add new)
      _availableShops.addAll(newShops);
      debugPrint('📅 [Calendar] Found ${_availableShops.length} shops: ${_availableShops.values.join(", ")}');

      // Auto-select first shop if none selected
      if (_selectedShopId == null && _availableShops.isNotEmpty) {
        _selectedShopId = _availableShops.keys.first;
        debugPrint('📅 [Calendar] Auto-selected first shop: $_selectedShopId');
      }

      // Filter records by selected shop (required - no "All Shops" option)
      List<DailySalesRecord> recordsToDisplay;

      if (_selectedShopId != null) {
        recordsToDisplay = allRecords
            .where((r) => r.shopId == _selectedShopId)
            .toList();
        final shopName = _availableShops[_selectedShopId] ?? _selectedShopId;
        debugPrint('📅 [Calendar] Filtered to shop $shopName: ${recordsToDisplay.length} records');
      } else {
        // Fallback if no shops available
        recordsToDisplay = [];
        debugPrint('📅 [Calendar] No shops available');
      }

      if (mounted) {
        _processRecords(recordsToDisplay);
      }
    } catch (e) {
      debugPrint('❌ [Calendar] Error loading month data: $e');
      // Clear records on error to avoid showing stale data
      if (mounted) {
        _processRecords([]);
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _processRecords(List<DailySalesRecord> records) {
    _monthRecords = records;
    _recordsByDate = {};

    // Group by date
    for (final record in records) {
      final dateKey = DateFormat('yyyy-MM-dd').format(record.recordDate);
      _recordsByDate.putIfAbsent(dateKey, () => []).add(record);
    }

    setState(() {});
  }

  void _goToPreviousMonth() {
    HapticFeedback.lightImpact();
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
      _selectedDate = null;
    });
    _loadMonthData();
  }

  void _goToNextMonth() {
    HapticFeedback.lightImpact();
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);
      _selectedDate = null;
    });
    _loadMonthData();
  }

  void _selectDate(DateTime date) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedDate = date;
    });
  }

  List<DailySalesRecord> _getRecordsForDate(DateTime date) {
    final dateKey = DateFormat('yyyy-MM-dd').format(date);
    return _recordsByDate[dateKey] ?? [];
  }

  /// Check if item is beer based on category, brand, or product name
  bool _isItemBeer(DailySalesItem item) {
    final category = (item.categoryName ?? '').toLowerCase();
    if (category.contains('beer') || category.contains('lager') ||
        category.contains('ale') || category.contains('stout') ||
        category.contains('pilsner')) {
      return true;
    }

    final searchText = '${item.brandName ?? ''} ${item.productName ?? ''}'.toLowerCase();
    return searchText.contains('beer') || searchText.contains('lager') ||
        searchText.contains('kingfisher') || searchText.contains('budweiser') ||
        searchText.contains('heineken') || searchText.contains('carlsberg') ||
        searchText.contains('tuborg') || searchText.contains('foster') ||
        searchText.contains('corona') || searchText.contains('bira') ||
        searchText.contains('haywards');
  }

  /// Get category breakdown for a list of records
  Map<String, int> _getCategoryBreakdown(List<DailySalesRecord> records) {
    int beerCount = 0;
    int spiritsCount = 0;

    for (final record in records) {
      for (final item in record.items) {
        if (_isItemBeer(item)) {
          beerCount += item.quantity;
        } else {
          spiritsCount += item.quantity;
        }
      }
    }

    return {'beer': beerCount, 'spirits': spiritsCount};
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // iOS-style drag handle
          _buildDragHandle(),

          // Header with title and shop filter
          _buildHeader(),

          // Month Navigation
          _buildMonthNavigation(),

          // Shop Filter Chips (visible)
          _buildShopFilter(),

          // Content
          Expanded(
            child: _isLoading
                ? _buildLoadingSkeleton()
                : ListView(
                    controller: widget.scrollController,
                    padding: EdgeInsets.zero,
                    children: [
                      // Weekday Headers
                      _buildWeekdayHeaders(),

                      // Calendar Grid
                      _buildCalendarGrid(),

                      // Monthly Summary
                      _buildMonthlySummary(),

                      // Selected Date Detail Panel
                      if (_selectedDate != null) _buildDetailPanel(),

                      const SizedBox(height: 40),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDragHandle() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: cs.outlineVariant,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          // Close button
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(CupertinoIcons.xmark, size: 18, color: cs.onSurfaceVariant),
            ),
          ),
          const Spacer(),
          // Title
          Text(
            'Sales Calendar',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
            ),
          ),
          const Spacer(),
          // Placeholder for symmetry
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildShopFilter() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Shop chips only (no "All Shops" option)
            ..._availableShops.entries.map((entry) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(entry.value),
                    selected: _selectedShopId == entry.key,
                    onSelected: (_) {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedShopId = entry.key);
                      _loadMonthData();
                    },
                    selectedColor: cs.primary.withValues(alpha: 0.2),
                    checkmarkColor: cs.primary,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      color: _selectedShopId == entry.key ? cs.primary : cs.onSurface,
                      fontWeight: _selectedShopId == entry.key ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthNavigation() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(CupertinoIcons.chevron_left),
            onPressed: _goToPreviousMonth,
            color: cs.primary,
          ),
          Text(
            DateFormat('MMMM yyyy').format(_currentMonth),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
            ),
          ),
          IconButton(
            icon: const Icon(CupertinoIcons.chevron_right),
            onPressed: _goToNextMonth,
            color: cs.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildWeekdayHeaders() {
    final cs = Theme.of(context).colorScheme;
    const weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Row(
        children: weekdays
            .map((day) => Expanded(
                  child: Center(
                    child: Text(
                      day,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildCalendarGrid() {
    final firstDayOfMonth = _currentMonth;
    final lastDayOfMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 0);
    final firstWeekday = firstDayOfMonth.weekday % 7; // Sunday = 0
    final daysInMonth = lastDayOfMonth.day;

    // Calculate total cells needed (6 weeks max)
    final totalCells = ((firstWeekday + daysInMonth) / 7).ceil() * 7;

    return Container(
      padding: const EdgeInsets.all(8),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          childAspectRatio: 0.85,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
        ),
        itemCount: totalCells,
        itemBuilder: (context, index) {
          final dayNumber = index - firstWeekday + 1;

          // Empty cell for padding
          if (dayNumber < 1 || dayNumber > daysInMonth) {
            return const SizedBox.shrink();
          }

          final date = DateTime(_currentMonth.year, _currentMonth.month, dayNumber);
          final records = _getRecordsForDate(date);
          final isSelected = _selectedDate != null &&
              _selectedDate!.year == date.year &&
              _selectedDate!.month == date.month &&
              _selectedDate!.day == date.day;
          final isToday = date.year == DateTime.now().year &&
              date.month == DateTime.now().month &&
              date.day == DateTime.now().day;

          return _buildDateCell(date, records, isSelected, isToday);
        },
      ),
    );
  }

  Widget _buildDateCell(
    DateTime date,
    List<DailySalesRecord> records,
    bool isSelected,
    bool isToday,
  ) {
    final cs = Theme.of(context).colorScheme;
    final totalRevenue = records.fold<double>(0, (sum, r) => sum + r.totalSalesAmount);
    final pendingCount = records.where((r) => r.status == 'pending').length;
    final approvedCount = records.where((r) => r.status == 'approved').length;
    final rejectedCount = records.where((r) => r.status == 'rejected').length;

    // Category breakdown for coloring
    final categoryBreakdown = _getCategoryBreakdown(records);
    final beerCount = categoryBreakdown['beer'] ?? 0;
    final spiritsCount = categoryBreakdown['spirits'] ?? 0;
    final total = beerCount + spiritsCount;

    // Calculate proportions for split coloring
    final beerRatio = total > 0 ? beerCount / total : 0.0;
    final spiritsRatio = total > 0 ? spiritsCount / total : 0.0;

    return GestureDetector(
      onTap: () => _selectDate(date),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? cs.primary
                : isToday
                    ? Colors.orange
                    : cs.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: cs.primary.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Stack(
            children: [
              // Category-based background (split coloring)
              if (records.isNotEmpty)
                Positioned.fill(
                  child: Row(
                    children: [
                      // Beer portion (amber)
                      if (beerRatio > 0)
                        Expanded(
                          flex: (beerRatio * 100).round().clamp(1, 100),
                          child: Container(color: Colors.amber.withValues(alpha: 0.15)),
                        ),
                      // Spirits portion (purple)
                      if (spiritsRatio > 0)
                        Expanded(
                          flex: (spiritsRatio * 100).round().clamp(1, 100),
                          child: Container(color: Colors.purple.withValues(alpha: 0.15)),
                        ),
                    ],
                  ),
                ),

              // Content overlay
              Padding(
                padding: const EdgeInsets.all(4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Date number
                    Text(
                      '${date.day}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isToday ? FontWeight.bold : FontWeight.w600,
                        color: isToday ? Colors.orange[800] : cs.onSurface,
                      ),
                    ),

                    // Status dots
                    if (records.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (approvedCount > 0)
                            _buildStatusDot(Colors.green, approvedCount),
                          if (pendingCount > 0)
                            _buildStatusDot(Colors.orange, pendingCount),
                          if (rejectedCount > 0)
                            _buildStatusDot(Colors.red, rejectedCount),
                        ],
                      ),
                    ],

                    // Revenue (compact)
                    if (totalRevenue > 0) ...[
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          Formatters.currencyCompact(totalRevenue),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusDot(Color color, int count) {
    return Container(
      width: count > 1 ? 14 : 8,
      height: 8,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: count > 1
          ? Center(
              child: Text(
                '$count',
                style: const TextStyle(
                  fontSize: 6,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildMonthlySummary() {
    final totalRevenue = _monthRecords.fold<double>(0, (sum, r) => sum + r.totalSalesAmount);
    final pendingAmount = _monthRecords
        .where((r) => r.status == 'pending')
        .fold<double>(0, (sum, r) => sum + r.totalSalesAmount);
    final approvedAmount = _monthRecords
        .where((r) => r.status == 'approved')
        .fold<double>(0, (sum, r) => sum + r.totalSalesAmount);
    final rejectedAmount = _monthRecords
        .where((r) => r.status == 'rejected')
        .fold<double>(0, (sum, r) => sum + r.totalSalesAmount);

    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Monthly Summary',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  'Total',
                  Formatters.currencyCompact(totalRevenue),
                  CupertinoIcons.money_dollar_circle_fill,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryCard(
                  'Pending',
                  Formatters.currencyCompact(pendingAmount),
                  CupertinoIcons.clock_fill,
                  Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  'Approved',
                  Formatters.currencyCompact(approvedAmount),
                  CupertinoIcons.checkmark_circle_fill,
                  Colors.green,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryCard(
                  'Rejected',
                  Formatters.currencyCompact(rejectedAmount),
                  CupertinoIcons.xmark_circle_fill,
                  Colors.red,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String label, String value, IconData icon, Color color) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailPanel() {
    final cs = Theme.of(context).colorScheme;
    final records = _getRecordsForDate(_selectedDate!);
    final formattedDate = DateFormat('EEEE, MMM d').format(_selectedDate!);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formattedDate,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${records.length} records',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),

          if (records.isEmpty) ...[
            const SizedBox(height: 24),
            Center(
              child: Column(
                children: [
                  Icon(CupertinoIcons.doc_text, size: 40, color: cs.onSurfaceVariant),
                  const SizedBox(height: 8),
                  Text(
                    'No sales records for this date',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ] else ...[
            const SizedBox(height: 16),
            ...records.map((record) => _buildRecordItem(record)),
          ],
        ],
      ),
    );
  }

  Widget _buildRecordItem(DailySalesRecord record) {
    final cs = Theme.of(context).colorScheme;
    final statusColor = record.status == 'approved'
        ? Colors.green
        : record.status == 'rejected'
            ? Colors.red
            : Colors.orange;

    final breakdown = _getCategoryBreakdown([record]);
    final hasBeer = (breakdown['beer'] ?? 0) > 0;
    final hasSpirits = (breakdown['spirits'] ?? 0) > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Shop name and status
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.shopName ?? 'Shop',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Category badges
                    Row(
                      children: [
                        if (hasBeer)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            margin: const EdgeInsets.only(right: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFE082),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'BEER',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFFFF8F00)),
                            ),
                          ),
                        if (hasSpirits)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFCE93D8),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'SPIRITS',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF7B1FA2)),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      record.status == 'approved'
                          ? CupertinoIcons.checkmark_circle_fill
                          : record.status == 'rejected'
                              ? CupertinoIcons.xmark_circle_fill
                              : CupertinoIcons.clock_fill,
                      size: 12,
                      color: statusColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      record.status.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Amount and created by
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                Formatters.currency(record.totalSalesAmount),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              ),
              Text(
                'by ${record.createdByName ?? record.salesmanName ?? 'Unknown'}',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),

          // Actions for pending
          if (record.status == 'pending') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _approveRecord(record),
                    icon: const Icon(CupertinoIcons.checkmark, size: 16),
                    label: const Text('Approve'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.green,
                      side: const BorderSide(color: Colors.green),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _rejectRecord(record),
                    icon: const Icon(CupertinoIcons.xmark, size: 16),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ],
            ),
          ],

          // View details button
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => _viewRecordDetails(record),
              child: const Text('View Details →'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _approveRecord(DailySalesRecord record) async {
    HapticFeedback.mediumImpact();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve Sale'),
        content: Text(
          'Approve sale of ${Formatters.currency(record.totalSalesAmount)} from ${record.shopName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Approve'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final provider = context.read<DailySalesProvider>();
      final success = await provider.approveRecord(record.id!);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sale approved successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _loadMonthData();
        widget.onRecordUpdated?.call();
      }
    }
  }

  Future<void> _rejectRecord(DailySalesRecord record) async {
    HapticFeedback.mediumImpact();

    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Sale'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Reject sale of ${Formatters.currency(record.totalSalesAmount)} from ${record.shopName}?',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Rejection Reason',
                hintText: 'Enter reason for rejection',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted && reasonController.text.isNotEmpty) {
      final provider = context.read<DailySalesProvider>();
      final success = await provider.rejectRecord(record.id!, reasonController.text);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sale rejected'),
            backgroundColor: Colors.red,
          ),
        );
        _loadMonthData();
        widget.onRecordUpdated?.call();
      }
    }
  }

  void _viewRecordDetails(DailySalesRecord record) {
    SaleDetailsModal.show(
      context,
      record,
      showActions: record.status == 'pending',
      onApprove: () {
        _loadMonthData();
        widget.onRecordUpdated?.call();
      },
      onReject: () {
        _loadMonthData();
        widget.onRecordUpdated?.call();
      },
    );
  }

  Widget _buildLoadingSkeleton() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'Loading calendar...',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
