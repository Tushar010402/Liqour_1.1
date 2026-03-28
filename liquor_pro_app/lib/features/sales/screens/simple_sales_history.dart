import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/config/api_config.dart';
import '../../../core/theme/ios_design_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/widgets/sale_details_modal.dart';
import '../providers/daily_sales_provider.dart';
import '../models/daily_sales_models.dart';
import '../models/sale.dart' hide DailySalesRecord;
import '../services/daily_sales_service.dart';
import '../widgets/ai_validation_badge.dart';
import '../widgets/ai_validation_modal.dart';
import '../widgets/receipt_image_viewer.dart';
import '../widgets/sales_calendar_modal.dart';

/// Normalize image URL to ensure it has a host
/// Handles legacy data with relative paths like "/uploads/..."
String _normalizeImageUrl(String url) {
  if (url.isEmpty) return url;
  if (url.startsWith('http://') || url.startsWith('https://')) {
    return url;
  }
  if (url.startsWith('/')) {
    return '${ApiConfig.baseUrl}$url';
  }
  return url;
}

/// Normalize all URLs in a list
List<String> _normalizeImageUrls(List<String> urls) {
  return urls.map(_normalizeImageUrl).toList();
}

/// Consolidated sales group - represents multiple sales on the same date for a shop
class ConsolidatedSaleGroup {
  final String dateKey;
  final String shopId;
  final String shopName;
  final List<DailySalesRecord> records;
  final DateTime recordDate;

  ConsolidatedSaleGroup({
    required this.dateKey,
    required this.shopId,
    required this.shopName,
    required this.records,
    required this.recordDate,
  });

  /// Total sales amount across all records
  double get totalAmount => records.fold(0.0, (sum, r) => sum + r.totalSalesAmount);

  /// Total items count across all records
  int get totalItems => records.fold(0, (sum, r) => sum + r.items.length);

  /// Total expenses across all records
  double get totalExpenses => records.fold(0.0, (sum, r) => sum + r.totalExpenseAmount);

  /// Unique categories across all records
  Set<String> get categories {
    final cats = <String>{};
    for (final record in records) {
      for (final item in record.items) {
        final catName = item.categoryName;
        if (catName != null && catName.isNotEmpty) {
          cats.add(catName);
        }
      }
    }
    return cats;
  }

  /// Category breakdown with counts
  Map<String, int> get categoryBreakdown {
    final breakdown = <String, int>{};
    for (final record in records) {
      for (final item in record.items) {
        final catName = item.categoryName;
        final cat = (catName != null && catName.isNotEmpty) ? catName : 'Other';
        breakdown[cat] = (breakdown[cat] ?? 0) + item.quantity;
      }
    }
    return breakdown;
  }

  /// Size breakdown with counts
  Map<String, int> get sizeBreakdown {
    final breakdown = <String, int>{};
    for (final record in records) {
      for (final item in record.items) {
        final sizeName = item.size;
        final size = (sizeName != null && sizeName.isNotEmpty) ? sizeName : 'Standard';
        breakdown[size] = (breakdown[size] ?? 0) + item.quantity;
      }
    }
    return breakdown;
  }

  /// Whether this group has multiple records
  bool get hasMultipleRecords => records.length > 1;

  /// Get the single record if only one exists
  DailySalesRecord? get singleRecord => records.length == 1 ? records.first : null;

  /// Get the most recent record's created at time
  DateTime? get latestCreatedAt {
    if (records.isEmpty) return null;
    return records.map((r) => r.createdAt ?? DateTime.now()).reduce((a, b) => a.isAfter(b) ? a : b);
  }

  /// Get dominant status (priority: pending > approved > rejected)
  String get dominantStatus {
    if (records.any((r) => r.status.toLowerCase() == 'pending')) return 'pending';
    if (records.any((r) => r.status.toLowerCase() == 'approved')) return 'approved';
    if (records.any((r) => r.status.toLowerCase() == 'rejected')) return 'rejected';
    return records.first.status;
  }

  /// Get the salesman names (unique)
  Set<String> get salesmanNames {
    return records
        .map((r) => r.createdByName ?? r.salesmanName ?? '')
        .where((n) => n.isNotEmpty)
        .toSet();
  }

  /// Check if any record has images
  bool get hasImages => records.any((r) => r.hasImages);

  /// Get the primary category type (for styling)
  String get primaryCategoryType {
    final breakdown = categoryBreakdown;
    if (breakdown.isEmpty) return 'mixed';

    final sorted = breakdown.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final topCategory = sorted.first.key.toLowerCase();
    if (topCategory.contains('beer')) return 'beer';
    if (topCategory.contains('wine')) return 'wine';
    if (topCategory.contains('whisky') || topCategory.contains('whiskey') ||
        topCategory.contains('rum') || topCategory.contains('vodka') ||
        topCategory.contains('gin') || topCategory.contains('brandy')) {
      return 'spirits';
    }
    return 'mixed';
  }
}

/// Simple Sales History Screen with clean design
class SimpleSalesHistory extends StatefulWidget {
  const SimpleSalesHistory({super.key});

  @override
  State<SimpleSalesHistory> createState() => _SimpleSalesHistoryState();
}

class _SimpleSalesHistoryState extends State<SimpleSalesHistory> {
  String _filterStatus = 'Pending';  // Default to Pending for approval workflow
  DateTimeRange? _dateRange;
  String? _selectedShopId;  // null = "All shops"

  // Scroll controller for infinite scroll detection
  final ScrollController _scrollController = ScrollController();

  // Best practice: Track if initial load is complete to prevent auto-loading on short lists
  bool _initialLoadComplete = false;
  // Best practice: Debounce to prevent rapid API calls
  DateTime? _lastLoadMoreTime;
  static const _loadMoreDebounce = Duration(milliseconds: 500);
  // Track previous scroll position to detect scroll direction
  double _previousScrollPosition = 0;

  // Status counts from backend API - for accurate display
  DailySalesStatusCounts? _statusCounts;
  bool _isLoadingCounts = false;

  // CRITICAL: Cache all available shops separately from filtered records
  // This ensures shop chips show all shops even when filtering by status
  Map<String, String> _allAvailableShops = {};

  @override
  void initState() {
    super.initState();
    // Add scroll listener for infinite scroll
    _scrollController.addListener(_onScroll);
    // Use addPostFrameCallback to avoid calling setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAllShops(); // Load all shops first (for filter chips)
      _loadSales();
      _loadStatusCounts(); // Fetch accurate counts from backend
    });
  }

  /// Load all shops (without status filter) for the shop filter chips
  /// Uses pagination to ensure ALL shops are captured
  Future<void> _loadAllShops() async {
    final authService = context.read<AuthService>();
    final service = DailySalesService(authService);

    final shops = <String, String>{};
    int currentPage = 1;
    bool hasMorePages = true;
    const int pageSize = 100;

    // Paginate through records to get ALL unique shops
    while (hasMorePages && currentPage <= 10) { // Safety limit
      final result = await service.getDailySalesRecords(
        page: currentPage,
        pageSize: pageSize,
      );

      if (result.isSuccess && result.data != null) {
        for (final record in result.data!) {
          if (record.shopId.isNotEmpty && !shops.containsKey(record.shopId)) {
            shops[record.shopId] = record.shopName ?? record.shopId;
          }
        }

        // Check if there are more pages
        if (result.data!.length < pageSize) {
          hasMorePages = false;
        } else {
          currentPage++;
        }
      } else {
        hasMorePages = false;
      }
    }

    if (mounted) {
      setState(() {
        _allAvailableShops = shops;
      });
    }
    print('📜 [SalesHistory] Loaded ${shops.length} shops for filter chips (fetched $currentPage pages)');
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// Infinite scroll detection - load more when near bottom (Best Practice: Instagram-style)
  void _onScroll() {
    // Best practice: Only trigger on user scroll after initial load
    if (!_initialLoadComplete) return;

    final currentScroll = _scrollController.position.pixels;
    final maxScroll = _scrollController.position.maxScrollExtent;

    // Best practice: Only load more when scrolling DOWN (not up)
    final isScrollingDown = currentScroll > _previousScrollPosition;
    _previousScrollPosition = currentScroll;

    if (!isScrollingDown) return;

    // Check if near bottom (200px threshold)
    final threshold = maxScroll - 200;

    if (currentScroll >= threshold && currentScroll > 0) {
      _loadMoreSales();
    }
  }

  /// Load more sales (next page) with debounce
  Future<void> _loadMoreSales() async {
    final provider = context.read<DailySalesProvider>();
    if (provider.isLoadingMore || !provider.hasMoreRecords) return;

    // Best practice: Debounce to prevent rapid API calls
    final now = DateTime.now();
    if (_lastLoadMoreTime != null &&
        now.difference(_lastLoadMoreTime!) < _loadMoreDebounce) {
      return;
    }
    _lastLoadMoreTime = now;

    print('📜 [SalesHistory] Loading more records (filter: $_filterStatus)...');
    final statusFilter = _filterStatus == 'All' ? null : _filterStatus.toLowerCase();
    await provider.loadMoreRecords(
      startDate: _dateRange?.start,
      endDate: _dateRange?.end,
      status: statusFilter, // Pass status filter for consistency
    );
  }

  Future<void> _loadSales() async {
    print('📜 [SalesHistory] Loading daily sales records with filter: $_filterStatus');
    _initialLoadComplete = false; // Reset on new load
    final provider = context.read<DailySalesProvider>();
    // CRITICAL FIX: Pass status filter to API to fetch old pending records
    // Without this, backend returns newest records first and old pending records are missed
    final statusFilter = _filterStatus == 'All' ? null : _filterStatus.toLowerCase();
    await provider.fetchRecords(
      startDate: _dateRange?.start,
      endDate: _dateRange?.end,
      status: statusFilter, // Pass status to backend API
    );
    print('📜 [SalesHistory] Loaded ${provider.records.length} daily sales records (status: ${statusFilter ?? "all"})');

    // Refresh status counts from backend for accurate display
    _loadStatusCounts();

    // Best practice: Mark initial load complete after a short delay
    // This prevents auto-loading when the filtered list is short
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _initialLoadComplete = true;
        });
      }
    });
  }

  /// Load accurate status counts from backend API
  /// This ensures pending/approved counts are accurate regardless of pagination
  Future<void> _loadStatusCounts() async {
    if (_isLoadingCounts) return;

    setState(() => _isLoadingCounts = true);

    try {
      final authService = context.read<AuthService>();
      final service = DailySalesService(authService);
      final result = await service.getStatusCounts(shopId: _selectedShopId);

      if (mounted && result.isSuccess && result.data != null) {
        setState(() {
          _statusCounts = result.data;
          _isLoadingCounts = false;
        });
      } else {
        setState(() => _isLoadingCounts = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingCounts = false);
      }
    }
  }

  /// Open Sales Calendar visualization modal (iOS 2026 style)
  void _openCalendarView() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: true, // iOS-style drag to dismiss
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.95, // 95% height
        minChildSize: 0.5,      // Minimum 50% before dismiss
        maxChildSize: 0.95,     // Max 95%
        expand: false,
        builder: (context, scrollController) => SalesCalendarModal(
          initialShopId: _selectedShopId,
          scrollController: scrollController,
          onRecordUpdated: () {
            // Refresh data when record is approved/rejected in calendar
            _loadSales();
          },
        ),
      ),
    );
  }

  // _getUniqueShops removed — unused, shop list comes from _allAvailableShops

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Don't use Scaffold since we're embedded in AdaptiveSalesScreen
    return Container(
      color: cs.surfaceContainerHighest,
      child: Column(
        children: [
          // Filters Bar - Clean, Settings-style
          Container(
            padding: const EdgeInsets.symmetric(horizontal: iOSDesignTokens.space12, vertical: iOSDesignTokens.space8),
            color: cs.surface,
            child: Column(
              children: [
                // Shop Quick Filter Chips - Settings-style bordered chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildShopChip('All', null),
                      ..._allAvailableShops.entries.map(
                        (entry) => _buildShopChip(entry.value, entry.key),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: iOSDesignTokens.space8),
                // Status Segmented Row + Date + Calendar
                Row(
                  children: [
                    // Status segmented chips
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: ['All', 'Pending', 'Approved', 'Rejected'].map((status) {
                            final isSelected = _filterStatus == status;
                            return Padding(
                              padding: const EdgeInsets.only(right: iOSDesignTokens.space6),
                              child: GestureDetector(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  setState(() => _filterStatus = status);
                                  _loadSales();
                                },
                                child: AnimatedContainer(
                                  duration: iOSDesignTokens.durationFast,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: isSelected ? cs.primary : Colors.transparent,
                                    borderRadius: BorderRadius.circular(iOSDesignTokens.radiusSmall),
                                    border: Border.all(
                                      color: isSelected ? cs.primary : cs.outline.withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Text(
                                    status,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                      color: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    const SizedBox(width: iOSDesignTokens.space8),
                    // Date Range Button
                    GestureDetector(
                      onTap: _selectDateRange,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          border: Border.all(color: cs.outline.withValues(alpha: 0.3)),
                          borderRadius: BorderRadius.circular(iOSDesignTokens.radiusSmall),
                          color: _dateRange != null ? cs.primary.withValues(alpha: 0.08) : null,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(CupertinoIcons.calendar, size: 16, color: cs.primary),
                            const SizedBox(width: 4),
                            Text(
                              _dateRange == null
                                  ? 'Date'
                                  : '${Formatters.dateShort(_dateRange!.start)} - ${Formatters.dateShort(_dateRange!.end)}',
                              style: TextStyle(fontSize: 13, color: cs.onSurface),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: iOSDesignTokens.space8),
                // Quick Stats - Uniform primary tint
                _buildQuickStats(),
              ],
            ),
          ),
          // Daily Sales Records List
          Expanded(
            child: Consumer<DailySalesProvider>(
              builder: (context, provider, child) {
                final records = _getFilteredRecords(provider.records);

                if (provider.isLoading) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CupertinoActivityIndicator(radius: 14, color: cs.primary),
                        const SizedBox(height: iOSDesignTokens.space12),
                        Text(
                          'Loading records...',
                          style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  );
                }

                if (records.isEmpty) {
                  return _buildEmptyState();
                }

                print('📜 [SalesHistory] Displaying ${records.length} daily sales records');

                // Use grouped list with date headers (Apple-style)
                return _buildGroupedList(records);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Settings-style shop filter chip
  Widget _buildShopChip(String label, String? shopId) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = _selectedShopId == shopId;
    return Padding(
      padding: const EdgeInsets.only(right: iOSDesignTokens.space6),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _selectedShopId = shopId);
          _loadStatusCounts();
        },
        child: AnimatedContainer(
          duration: iOSDesignTokens.durationFast,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? cs.primary.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(iOSDesignTokens.radiusSmall),
            border: Border.all(
              color: isSelected ? cs.primary : cs.outline.withValues(alpha: 0.2),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              color: isSelected ? cs.primary : cs.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  /// Settings-style empty state
  Widget _buildEmptyState() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(iOSDesignTokens.space32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                CupertinoIcons.doc_text,
                size: 36,
                color: cs.primary.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: iOSDesignTokens.space20),
            Text(
              'No sales records found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: iOSDesignTokens.space8),
            Text(
              'Try adjusting your filters or pull down to refresh.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: iOSDesignTokens.space20),
            GestureDetector(
              onTap: _loadSales,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(iOSDesignTokens.radiusButton),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.arrow_clockwise, size: 16, color: cs.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Refresh',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: cs.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStats() {
    final cs = Theme.of(context).colorScheme;
    return Consumer<DailySalesProvider>(
      builder: (context, provider, child) {
        final todayRecords = provider.records.where((r) {
          final today = DateTime.now();
          return r.recordDate.day == today.day &&
                 r.recordDate.month == today.month &&
                 r.recordDate.year == today.year;
        }).toList();

        final todayTotal = todayRecords.fold<double>(
          0, (sum, record) => sum + record.totalSalesAmount
        );

        return Row(
          children: [
            Expanded(
              child: _buildStatChip(
                icon: CupertinoIcons.doc_text_fill,
                label: 'Today',
                value: '${todayRecords.length}',
              ),
            ),
            const SizedBox(width: iOSDesignTokens.space6),
            Expanded(
              child: _buildStatChip(
                icon: CupertinoIcons.money_dollar_circle_fill,
                label: 'Revenue',
                value: Formatters.currencyCompact(todayTotal),
              ),
            ),
            const SizedBox(width: iOSDesignTokens.space6),
            Expanded(
              child: _buildStatChip(
                icon: CupertinoIcons.clock_fill,
                label: 'Pending',
                value: _statusCounts != null
                    ? '${_statusCounts!.pendingCount}'
                    : '${provider.records.where((r) => r.status == 'pending').length}',
                isLoading: _isLoadingCounts && _statusCounts == null,
              ),
            ),
            const SizedBox(width: iOSDesignTokens.space6),
            // Calendar View Button
            GestureDetector(
              onTap: _openCalendarView,
              child: Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(iOSDesignTokens.radiusSmall),
                  border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
                ),
                child: Icon(
                  CupertinoIcons.calendar_badge_plus,
                  color: cs.primary,
                  size: 18,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatChip({
    required IconData icon,
    required String label,
    required String value,
    bool isLoading = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(iOSDesignTokens.radiusSmall),
        border: Border.all(color: cs.primary.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Icon(icon, color: cs.primary, size: 15),
          const SizedBox(width: 4),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: cs.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                isLoading
                    ? SizedBox(
                        height: 12,
                        width: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                        ),
                      )
                    : Text(
                        value,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: cs.primary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // _buildRecordCard removed — dead code, replaced by unified _buildSaleCard

  // _isItemBeer, _getSaleCategoryType, _getCategoryBackgroundColor, _getCategoryIndicator
  // removed — category-colored backgrounds are no longer used

  /// Unified compact sale card — replaces _buildRecordCard, _buildModernRecordCard
  Widget _buildSaleCard(DailySalesRecord record) {
    final cs = Theme.of(context).colorScheme;
    final createdBy = record.createdByName ?? record.salesmanName;
    final shopName = record.shopName ?? 'Shop ${record.shopId}';
    final status = record.status;
    final isReverted = status.toLowerCase() == 'returned' || status.toLowerCase() == 'reverted';
    final timeStr = DateFormat('h:mm a').format(record.createdAt ?? DateTime.now());

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
        border: Border.all(color: cs.outline.withValues(alpha: 0.15)),
      ),
      child: Stack(
        children: [
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
            child: InkWell(
              borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
              onTap: () => _viewRecordDetails(record),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Row 1: Shop name + Amount
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            shopName,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          Formatters.currency(record.totalSalesAmount),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: cs.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Row 2: Creator • item count • time
                    Text(
                      [
                        if (createdBy != null) createdBy,
                        '${record.items.length} items',
                        timeStr,
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // Row 3: Category + size chips (compact, uniform primary tint)
                    if (record.items.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _buildCompactChips(record),
                    ],
                    const SizedBox(height: 8),
                    // Row 4: Status + AI badge + receipt thumb + chevron
                    Row(
                      children: [
                        _buildModernStatusBadge(status),
                        // AI Validation Badge (compact for pending with images)
                        if (record.hasImages && status.toLowerCase() == 'pending') ...[
                          const SizedBox(width: 8),
                          AIValidationBadge(
                            record: record,
                            compact: true,
                            onTap: () => _showValidationModal(record),
                          ),
                        ],
                        const Spacer(),
                        if (record.hasImages) ...[
                          _buildReceiptThumbnail(record),
                          const SizedBox(width: 6),
                        ],
                        Icon(CupertinoIcons.chevron_right, size: 16, color: cs.onSurfaceVariant),
                      ],
                    ),
                    // Row 5 (conditional): Approval/rejection/resubmission — single subtle line
                    _buildStatusInfoLine(record),
                  ],
                ),
              ),
            ),
          ),
          // Reverted overlay badge instead of Opacity wrapper
          if (isReverted)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'REVERTED',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: Colors.orange.shade700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Compact category + size chips (uniform primary tint)
  Widget _buildCompactChips(DailySalesRecord record) {
    final cs = Theme.of(context).colorScheme;
    final categoryCount = <String, int>{};
    final sizeCount = <String, int>{};

    for (final item in record.items) {
      final category = _extractCategory(item);
      categoryCount[category] = (categoryCount[category] ?? 0) + item.quantity;

      String size = item.size ?? '';
      if (size.isEmpty || size == 'N/A') {
        size = _extractSizeFromName(item.productName);
      }
      if (size.isNotEmpty && size != 'N/A') {
        sizeCount[size.toUpperCase()] = (sizeCount[size.toUpperCase()] ?? 0) + item.quantity;
      }
    }

    final sortedCats = categoryCount.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final sortedSizes = sizeCount.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    if (sortedCats.isEmpty && sortedSizes.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        ...sortedCats.take(3).map((e) => _chipWidget('${e.key} ${e.value}', cs.primary)),
        ...sortedSizes.take(2).map((e) => _chipWidget('${e.key} ×${e.value}', cs.onSurfaceVariant)),
      ],
    );
  }

  Widget _chipWidget(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: color),
      ),
    );
  }

  /// Single-line status info (approval, rejection, resubmission)
  Widget _buildStatusInfoLine(DailySalesRecord record) {
    final status = record.status.toLowerCase();
    final cs = Theme.of(context).colorScheme;

    if (status == 'approved') {
      return Column(
        children: [
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(CupertinoIcons.checkmark_seal_fill, size: 13, color: Colors.green),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        [
                          if (record.approvedByName != null) 'Approved by ${record.approvedByName}',
                          if (record.approvedAt != null) Formatters.relativeTime(record.approvedAt!),
                        ].join(' · '),
                        style: TextStyle(fontSize: 12, color: Colors.green.shade600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              // Revert Button - Admin Only
              FutureBuilder<String?>(
                future: Provider.of<AuthService>(context, listen: false).getUserRole(),
                builder: (context, snapshot) {
                  final userRole = snapshot.data ?? '';
                  final isAdmin = userRole == 'admin' || userRole == 'saas_admin';
                  if (!isAdmin) return const SizedBox.shrink();
                  return GestureDetector(
                    onTap: () => _showRevertConfirmation(record),
                    child: Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(CupertinoIcons.arrow_uturn_left, size: 12, color: Colors.red),
                          SizedBox(width: 4),
                          Text('Revert', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.red)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      );
    }

    if (status == 'rejected') {
      return Column(
        children: [
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(CupertinoIcons.xmark_seal_fill, size: 13, color: Colors.red),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  [
                    record.rejectedByName != null ? 'Rejected by ${record.rejectedByName}' : 'Rejected',
                    if (record.rejectionReason != null && record.rejectionReason!.isNotEmpty)
                      '"${record.rejectionReason}"',
                  ].join(' · '),
                  style: TextStyle(fontSize: 12, color: Colors.red.shade600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      );
    }

    if (record.resubmitCount > 0) {
      return Column(
        children: [
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(CupertinoIcons.arrow_2_circlepath, size: 12, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                record.resubmittedByName != null
                    ? 'Resubmitted by ${record.resubmittedByName}'
                    : 'Resubmitted (${record.resubmitCount}x)',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  /// Modern status badge with icon
  Widget _buildModernStatusBadge(String status) {
    final color = _getStatusColor(status);
    final icon = _getStatusIcon(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            status.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  // _buildStatusBadge removed — replaced by _buildModernStatusBadge

  // _isBeerCategory, _getCategoryChipColor, _getCategoryChipBgColor removed — no longer used

  /// Extract size from product name if not available directly
  /// E.g., "Kingfisher Premium 650ML" → "650ML"
  String _extractSizeFromName(String? productName) {
    if (productName == null || productName.isEmpty) return 'N/A';

    // Match patterns like "650ML", "750ml", "180 ML", "1L", "1LTR"
    final sizePattern = RegExp(
      r'(\d+(?:\.\d+)?)\s*(ml|ML|ltr|LTR|L)\b',
      caseSensitive: false,
    );
    final match = sizePattern.firstMatch(productName);
    if (match != null) {
      final number = match.group(1)!;
      final unit = match.group(2)!.toUpperCase();
      // Normalize unit
      final normalizedUnit = unit == 'LTR' ? 'L' : unit;
      return '$number$normalizedUnit';
    }
    return 'N/A';
  }

  /// Extract category from item - uses categoryName directly from backend
  String _extractCategory(DailySalesItem item) {
    // Use categoryName directly from backend (e.g., "Whisky", "Beer", "Rum", "Vodka")
    if (item.categoryName != null && item.categoryName!.isNotEmpty) {
      return item.categoryName!;
    }

    // Fallback: Try to extract from brand name or product name
    final searchText = '${item.brandName ?? ''} ${item.productName ?? ''}'.toLowerCase();

    if (searchText.contains('beer') || searchText.contains('lager') ||
        searchText.contains('kingfisher') || searchText.contains('budweiser') ||
        searchText.contains('heineken') || searchText.contains('carlsberg') ||
        searchText.contains('tuborg') || searchText.contains('foster')) {
      return 'Beer';
    }
    if (searchText.contains('whisky') || searchText.contains('whiskey') ||
        searchText.contains('scotch') || searchText.contains('bourbon')) {
      return 'Whisky';
    }
    if (searchText.contains('rum') || searchText.contains('bacardi') ||
        searchText.contains('old monk')) {
      return 'Rum';
    }
    if (searchText.contains('vodka') || searchText.contains('smirnoff') ||
        searchText.contains('absolut')) {
      return 'Vodka';
    }
    if (searchText.contains('wine') || searchText.contains('champagne')) {
      return 'Wine';
    }
    if (searchText.contains('brandy') || searchText.contains('cognac')) {
      return 'Brandy';
    }
    if (searchText.contains('gin')) {
      return 'Gin';
    }

    return 'Other';
  }

  // _buildCategoryChips removed — replaced by _buildCompactChips in _buildSaleCard

  Color _getStatusColor(String status) {
    final cs = Theme.of(context).colorScheme;
    switch (status.toLowerCase()) {
      case 'approved':
        return Colors.green;
      case 'pending':
        return const Color(0xFF1976D2); // Blue 700 - distinct from Beer amber
      case 'rejected':
        return Colors.red;
      case 'returned':
        return Colors.purple;
      default:
        return cs.onSurfaceVariant;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return CupertinoIcons.checkmark_circle_fill;
      case 'pending':
        return CupertinoIcons.clock_fill;
      case 'rejected':
        return CupertinoIcons.xmark_circle_fill;
      case 'returned':
        return CupertinoIcons.arrow_uturn_left_circle_fill;
      default:
        return CupertinoIcons.doc_text_fill;
    }
  }

  List<DailySalesRecord> _getFilteredRecords(List<DailySalesRecord> records) {
    List<DailySalesRecord> filtered = List<DailySalesRecord>.from(records);

    // Filter by status
    if (_filterStatus != 'All') {
      filtered = filtered.where((DailySalesRecord r) =>
        r.status.toLowerCase() == _filterStatus.toLowerCase()
      ).toList();
    }

    // Filter by selected shop
    if (_selectedShopId != null) {
      filtered = filtered.where((DailySalesRecord r) => r.shopId == _selectedShopId).toList();
    }

    // Filter by date range
    if (_dateRange != null) {
      filtered = filtered.where((DailySalesRecord r) =>
        r.recordDate.isAfter(_dateRange!.start) &&
        r.recordDate.isBefore(_dateRange!.end.add(const Duration(days: 1)))
      ).toList();
    }

    // Sort based on status:
    // - PENDING: Sort by CREATION time (newest submissions first) - so manager sees recent submissions
    //   FIX: Previously sorted by recordDate which caused recent submissions to not appear
    //   because recordDate is the DATE of sales (e.g., Dec 24) not when submitted (Dec 25)
    // - Others (Approved, Rejected, etc.): Newest recordDate first
    if (_filterStatus.toLowerCase() == 'pending') {
      // Sort by createdAt (when submitted) - newest submissions first
      filtered.sort((DailySalesRecord a, DailySalesRecord b) {
        final aTime = a.createdAt ?? a.recordDate;
        final bTime = b.createdAt ?? b.recordDate;
        return bTime.compareTo(aTime); // Newest submissions first
      });
    } else {
      filtered.sort((DailySalesRecord a, DailySalesRecord b) => b.recordDate.compareTo(a.recordDate)); // Newest first
    }

    print('📜 [SalesHistory] Filtered ${filtered.length} records from ${records.length} total (filter: $_filterStatus)');
    if (filtered.isNotEmpty && _filterStatus.toLowerCase() == 'pending') {
      print('📜 [SalesHistory] First pending record: ${filtered.first.shopName} - createdAt: ${filtered.first.createdAt}, recordDate: ${filtered.first.recordDate}');
    }

    return filtered;
  }

  // _groupRecordsByDate removed — replaced by _groupRecordsIntoConsolidated

  /// Group records by date AND shop into consolidated groups
  Map<String, List<ConsolidatedSaleGroup>> _groupRecordsIntoConsolidated(List<DailySalesRecord> records) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    // First group by date, then by shop
    final Map<String, Map<String, List<DailySalesRecord>>> dateShopGroups = {};

    for (final record in records) {
      final recordDateOnly = DateTime(
        record.recordDate.year,
        record.recordDate.month,
        record.recordDate.day,
      );

      String dateKey;
      if (recordDateOnly == today) {
        dateKey = 'Today';
      } else if (recordDateOnly == yesterday) {
        dateKey = 'Yesterday';
      } else {
        dateKey = DateFormat('d MMMM yyyy').format(record.recordDate);
      }

      dateShopGroups.putIfAbsent(dateKey, () => {});
      final shopId = record.shopId;
      dateShopGroups[dateKey]!.putIfAbsent(shopId, () => []).add(record);
    }

    // Convert to consolidated groups
    final Map<String, List<ConsolidatedSaleGroup>> result = {};

    for (final dateEntry in dateShopGroups.entries) {
      final dateKey = dateEntry.key;
      final shopGroups = dateEntry.value;

      result[dateKey] = [];

      for (final shopEntry in shopGroups.entries) {
        final shopRecords = shopEntry.value;
        if (shopRecords.isEmpty) continue;

        result[dateKey]!.add(ConsolidatedSaleGroup(
          dateKey: dateKey,
          shopId: shopEntry.key,
          shopName: shopRecords.first.shopName ?? 'Shop ${shopEntry.key}',
          records: shopRecords,
          recordDate: shopRecords.first.recordDate,
        ));
      }

      // Sort consolidated groups by latest activity (newest first)
      result[dateKey]!.sort((a, b) {
        final aTime = a.latestCreatedAt ?? DateTime.now();
        final bTime = b.latestCreatedAt ?? DateTime.now();
        return bTime.compareTo(aTime);
      });
    }

    return result;
  }

  /// Show bottom sheet with list of individual sales for a consolidated group
  void _showMultipleSalesSheet(ConsolidatedSaleGroup group) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (context, scrollController) {
          final cs = Theme.of(context).colorScheme;
          return Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(iOSDesignTokens.radiusSheet)),
            ),
            child: Column(
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 36, height: 4,
                  decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(2)),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              group.shopName,
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: cs.onSurface),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${group.records.length} sales on ${group.dateKey}',
                              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          Formatters.currency(group.totalAmount),
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: cs.primary),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: cs.outline.withValues(alpha: 0.1)),
                // Sales list
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.all(iOSDesignTokens.space16),
                    itemCount: group.records.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final record = group.records[index];
                      return _buildCompactSaleCard(record, index + 1);
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Build a compact sale card for the multi-sale list
  Widget _buildCompactSaleCard(DailySalesRecord record, int index) {
    final status = record.status;
    final createdBy = record.createdByName ?? record.salesmanName ?? 'Unknown';
    final categoryBreakdown = <String, int>{};

    for (final item in record.items) {
      final catName = item.categoryName;
      final cat = (catName != null && catName.isNotEmpty) ? catName : 'Other';
      categoryBreakdown[cat] = (categoryBreakdown[cat] ?? 0) + item.quantity;
    }

    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
      child: InkWell(
        borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
        onTap: () {
          Navigator.pop(context);
          _viewRecordDetails(record);
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
            border: Border.all(color: cs.outline.withValues(alpha: 0.15)),
          ),
          child: Row(
            children: [
              // Index badge
              Container(
                width: 30, height: 30,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text('$index', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.primary)),
                ),
              ),
              const SizedBox(width: 10),
              // Sale info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$createdBy · ${DateFormat('h:mm a').format(record.createdAt ?? DateTime.now())}',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: categoryBreakdown.entries.take(3).map((e) {
                        return _chipWidget('${e.key} ${e.value}', cs.primary);
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Amount and status
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    Formatters.currency(record.totalSalesAmount),
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: cs.primary),
                  ),
                  const SizedBox(height: 4),
                  _buildMiniStatusBadge(status),
                ],
              ),
              const SizedBox(width: 4),
              Icon(CupertinoIcons.chevron_right, size: 14, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  /// Build a mini status badge for compact cards
  Widget _buildMiniStatusBadge(String status) {
    final color = _getStatusColor(status);
    final icon = _getStatusIcon(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            status.toUpperCase(),
            style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 0.3, color: color),
          ),
        ],
      ),
    );
  }

  /// Build date section header — Settings-style with accent bar
  Widget _buildDateHeader(String dateGroup) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 20, 0, 10),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 16,
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            dateGroup.toUpperCase(),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  /// Build consolidated sale card — compact, uniform design matching _buildSaleCard
  Widget _buildConsolidatedCard(ConsolidatedSaleGroup group) {
    final cs = Theme.of(context).colorScheme;
    final allReverted = group.records.every((r) =>
      r.status.toLowerCase() == 'returned' || r.status.toLowerCase() == 'reverted'
    );

    // For single-record groups, delegate to _buildSaleCard
    if (!group.hasMultipleRecords && group.singleRecord != null) {
      return _buildSaleCard(group.singleRecord!);
    }

    final timeStr = DateFormat('h:mm a').format(group.latestCreatedAt ?? DateTime.now());

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
        border: Border.all(color: cs.outline.withValues(alpha: 0.15)),
      ),
      child: Stack(
        children: [
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
            child: InkWell(
              borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
              onTap: () => _showMultipleSalesSheet(group),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Row 1: Shop name + "N sales" badge + Amount
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  group.shopName,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: cs.onSurface,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: cs.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${group.records.length} sales',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: cs.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          Formatters.currency(group.totalAmount),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: cs.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Row 2: Salesmen • items • time
                    Text(
                      [
                        if (group.salesmanNames.isNotEmpty) group.salesmanNames.join(', '),
                        '${group.totalItems} items',
                        timeStr,
                      ].join(' · '),
                      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // Row 3: Category + size chips
                    if (group.categoryBreakdown.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          ...group.categoryBreakdown.entries.take(3).map(
                            (e) => _chipWidget('${e.key} ${e.value}', cs.primary),
                          ),
                          ...group.sizeBreakdown.entries.take(2).map(
                            (e) => _chipWidget('${e.key} ×${e.value}', cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    // Row 4: Status + expenses + chevron
                    Row(
                      children: [
                        _buildConsolidatedStatusBadge(group),
                        if (group.totalExpenses > 0) ...[
                          const SizedBox(width: 8),
                          Text(
                            '- ${Formatters.currency(group.totalExpenses)} exp',
                            style: TextStyle(fontSize: 11, color: Colors.red.shade400, fontWeight: FontWeight.w500),
                          ),
                        ],
                        const Spacer(),
                        Icon(CupertinoIcons.chevron_down, size: 16, color: cs.onSurfaceVariant),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (allReverted)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'REVERTED',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.orange.shade700, letterSpacing: 0.5),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Build status badge for consolidated card (shows mixed status if applicable)
  Widget _buildConsolidatedStatusBadge(ConsolidatedSaleGroup group) {
    final status = group.dominantStatus;
    final hasMixedStatus = group.records.map((r) => r.status.toLowerCase()).toSet().length > 1;

    if (hasMixedStatus) {
      final pendingCount = group.records.where((r) => r.status.toLowerCase() == 'pending').length;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.circle_grid_hex_fill, size: 11, color: Colors.orange.shade700),
            const SizedBox(width: 4),
            Text(
              pendingCount > 0 ? '$pendingCount pending' : 'Mixed',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.orange.shade700),
            ),
          ],
        ),
      );
    }

    return _buildModernStatusBadge(status);
  }

  /// Build grouped list with date headers and infinite scroll (CONSOLIDATED VIEW)
  Widget _buildGroupedList(List<DailySalesRecord> records) {
    final consolidatedGroups = _groupRecordsIntoConsolidated(records);
    final sortedKeys = consolidatedGroups.keys.toList();

    // Sort date groups: Always newest dates first for better UX
    sortedKeys.sort((a, b) {
      if (a == 'Today') return -1;
      if (b == 'Today') return 1;
      if (a == 'Yesterday') return -1;
      if (b == 'Yesterday') return 1;
      try {
        final dateA = DateFormat('d MMMM yyyy').parse(a);
        final dateB = DateFormat('d MMMM yyyy').parse(b);
        return dateB.compareTo(dateA);
      } catch (_) {
        return b.compareTo(a);
      }
    });

    // Calculate total item count including loading indicator
    final baseCount = sortedKeys.fold<int>(
      0,
      (sum, key) => sum + 1 + consolidatedGroups[key]!.length,
    );

    return RefreshIndicator(
      onRefresh: _loadSales,
      child: Consumer<DailySalesProvider>(
        builder: (context, provider, _) {
          final itemCount = baseCount + (provider.hasMoreRecords ? 1 : 0);

          return ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: itemCount,
            itemBuilder: (context, index) {
              if (index == baseCount && provider.hasMoreRecords) {
                return _buildLoadingIndicator(provider.isLoadingMore);
              }

              int currentIndex = 0;
              for (final key in sortedKeys) {
                if (currentIndex == index) {
                  return _buildDateHeader(key);
                }
                currentIndex++;

                final groups = consolidatedGroups[key]!;
                for (int i = 0; i < groups.length; i++) {
                  if (currentIndex == index) {
                    return _buildConsolidatedCard(groups[i]);
                  }
                  currentIndex++;
                }
              }
              return const SizedBox.shrink();
            },
          );
        },
      ),
    );
  }

  /// Build loading indicator for infinite scroll
  Widget _buildLoadingIndicator(bool isLoading) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: iOSDesignTokens.space24),
      child: Center(
        child: isLoading
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CupertinoActivityIndicator(radius: 12, color: cs.primary),
                  const SizedBox(height: iOSDesignTokens.space8),
                  Text('Loading more...', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              )
            : GestureDetector(
                onTap: _loadMoreSales,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.arrow_down_circle, size: 16, color: cs.primary),
                      const SizedBox(width: 8),
                      Text('Load more', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: cs.primary)),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  /// Build receipt thumbnail widget for sale card
  Widget _buildReceiptThumbnail(DailySalesRecord record) {
    if (record.imageUrls.isEmpty) {
      return const SizedBox.shrink();
    }

    // Normalize URLs to handle legacy data with relative paths
    final normalizedUrls = _normalizeImageUrls(record.imageUrls);

    return GestureDetector(
      onTap: () => ReceiptImageViewer.show(
        context,
        imageUrls: normalizedUrls,
        title: 'Receipt',
      ),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: normalizedUrls.first,
              width: 44,
              height: 44,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                width: 44,
                height: 44,
                color: Theme.of(context).colorScheme.outlineVariant,
                child: const CupertinoActivityIndicator(radius: 8),
              ),
              errorWidget: (context, url, error) => Container(
                width: 44,
                height: 44,
                color: Theme.of(context).colorScheme.outlineVariant,
                child: Icon(
                  CupertinoIcons.photo,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 18,
                ),
              ),
            ),
          ),
          // Multiple images indicator
          if (record.imageUrls.length > 1)
            Positioned(
              top: 2,
              right: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${record.imageUrls.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Show AI validation modal for a record
  /// Fetches validation data from the backend before showing the modal
  void _showValidationModal(DailySalesRecord record) async {
    // Get current user role for approval permissions
    final authService = Provider.of<AuthService>(context, listen: false);
    final userRole = await authService.getUserRole();
    final canApprove = userRole == 'admin' ||
                      userRole == 'manager' ||
                      userRole == 'assistant_manager';

    if (!mounted) return;

    // Show loading indicator while fetching validation
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: CupertinoActivityIndicator(radius: 16),
      ),
    );

    // Fetch validation data from backend
    AIValidationResult? validationResult = record.validationResult;

    if (record.id != null) {
      try {
        // DailySalesService requires AuthService, not DioApiService
        final dailySalesService = DailySalesService(authService);

        print('🤖 [SalesHistory] Fetching AI validation for record ${record.id}');
        final response = await dailySalesService.getValidation(record.id!);

        if (response.success && response.data != null) {
          validationResult = response.data;
          print('✅ [SalesHistory] AI validation loaded: ${validationResult?.status}');
          print('   - Accuracy: ${validationResult?.overallAccuracy}%');
          print('   - Critical: ${validationResult?.criticalCount}, Warning: ${validationResult?.warningCount}');
          print('   - Has AI Summary: ${validationResult?.hasAISummary}');
        } else {
          print('⚠️ [SalesHistory] No validation data: ${response.error}');
        }
      } catch (e) {
        print('❌ [SalesHistory] Error fetching validation: $e');
      }
    }

    // Dismiss loading indicator
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (!mounted) return;

    await AIValidationModal.show(
      context,
      record: record,
      validationResult: validationResult,
      onApprove: canApprove ? () => _approveRecord(record) : null,
      onReject: canApprove ? () => _rejectRecord(record) : null,
      showActions: canApprove && record.status == 'pending',
    );
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      initialDateRange: _dateRange,
    );

    if (picked != null) {
      setState(() {
        _dateRange = picked;
      });
    }
  }

  void _viewRecordDetails(DailySalesRecord record) async {
    // Get current user role for approval permissions
    final authService = Provider.of<AuthService>(context, listen: false);
    final userRole = await authService.getUserRole();
    final canApprove = userRole == 'admin' ||
                      userRole == 'manager' ||
                      userRole == 'assistant_manager';

    // Show the modern iOS 16-style modal with product details and action buttons
    await SaleDetailsModal.show(
      context,
      record,
      onApprove: canApprove ? () => _approveRecord(record) : null,
      onReject: canApprove ? () => _rejectRecord(record) : null,
      showActions: canApprove && record.status == 'pending',
    );
  }

  // _buildDetailRow removed — unused dead code

  Future<void> _approveRecord(DailySalesRecord record) async {
    final cs = Theme.of(context).colorScheme;
    // Show modern bottom sheet confirmation
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(iOSDesignTokens.radiusSheet)),
          ),
          padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 36, height: 4,
                decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 20),
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
                    ),
                    child: const Icon(CupertinoIcons.checkmark_circle_fill, color: Colors.green, size: 24),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text('Approve Sales Record', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Details
              _buildSheetDetailRow('Shop', record.shopName ?? record.shopId),
              _buildSheetDetailRow('Amount', Formatters.currency(record.totalSalesAmount)),
              _buildSheetDetailRow('Items', '${record.items.length} products'),
              const SizedBox(height: 16),
              // Warning
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(iOSDesignTokens.radiusSmall),
                ),
                child: Row(
                  children: [
                    Icon(CupertinoIcons.exclamationmark_triangle_fill, size: 18, color: Colors.orange.shade700),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Stock will be deducted upon approval.',
                        style: TextStyle(fontSize: 13, color: Colors.orange.shade800),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: CupertinoButton(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(iOSDesignTokens.radiusButton),
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text('Cancel', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: CupertinoButton(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(iOSDesignTokens.radiusButton),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(CupertinoIcons.checkmark_alt, size: 18, color: Colors.white),
                          SizedBox(width: 6),
                          Text('Approve', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    if (confirmed != true || !mounted) return;

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CupertinoActivityIndicator(radius: 14)),
    );

    // Call approval API
    final authService = Provider.of<AuthService>(context, listen: false);
    final dailySalesService = DailySalesService(authService);
    final response = await dailySalesService.approveDailySalesRecord(record.id!);

    if (!mounted) return;
    Navigator.pop(context); // Close loading dialog

    if (response.success) {
      await _loadSales();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Daily sales record approved successfully'), backgroundColor: Colors.green),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to approve: ${response.message}'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _rejectRecord(DailySalesRecord record) async {
    final cs = Theme.of(context).colorScheme;
    final reasonController = TextEditingController();

    // Show modern bottom sheet with reason input
    final reason = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(iOSDesignTokens.radiusSheet)),
          ),
          padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 36, height: 4,
                decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 20),
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
                    ),
                    child: const Icon(CupertinoIcons.xmark_circle_fill, color: Colors.red, size: 24),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text('Reject Sales Record', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Details
              _buildSheetDetailRow('Shop', record.shopName ?? record.shopId),
              _buildSheetDetailRow('Amount', Formatters.currency(record.totalSalesAmount)),
              const SizedBox(height: 16),
              // Reason field
              TextField(
                controller: reasonController,
                decoration: InputDecoration(
                  labelText: 'Reason for rejection *',
                  hintText: 'Enter reason...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium)),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                ),
                maxLines: 3,
                autofocus: true,
              ),
              const SizedBox(height: 24),
              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: CupertinoButton(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(iOSDesignTokens.radiusButton),
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('Cancel', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: CupertinoButton(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(iOSDesignTokens.radiusButton),
                      onPressed: () {
                        if (reasonController.text.trim().isEmpty) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('Please enter a reason')),
                          );
                          return;
                        }
                        Navigator.pop(ctx, reasonController.text.trim());
                      },
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(CupertinoIcons.xmark, size: 18, color: Colors.white),
                          SizedBox(width: 6),
                          Text('Reject', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    if (reason == null || reason.isEmpty || !mounted) return;

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CupertinoActivityIndicator(radius: 14)),
    );

    // Call rejection API
    final authService = Provider.of<AuthService>(context, listen: false);
    final dailySalesService = DailySalesService(authService);
    final response = await dailySalesService.rejectDailySalesRecord(record.id!, reason);

    if (!mounted) return;
    Navigator.pop(context); // Close loading dialog

    if (response.success) {
      await _loadSales();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Daily sales record rejected'), backgroundColor: Colors.orange),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to reject: ${response.message}'), backgroundColor: Colors.red),
      );
    }
  }

  /// Helper for bottom sheet detail rows
  Widget _buildSheetDetailRow(String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ============================================================================
  // REVERT FUNCTIONALITY (Admin Only)
  // ============================================================================

  /// Show revert confirmation dialog with reason input
  Future<void> _showRevertConfirmation(DailySalesRecord record) async {
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(CupertinoIcons.arrow_uturn_left, color: Colors.red, size: 20),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Revert Sale', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(CupertinoIcons.exclamationmark_triangle_fill, color: Colors.orange, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'This will restore stock to inventory and require OTP verification.',
                        style: TextStyle(fontSize: 13, color: Colors.orange[800]),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Record Details',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              _buildRevertDetailRow('Shop', record.shopName ?? 'Shop ${record.shopId}'),
              _buildRevertDetailRow('Date', DateFormat('d MMM yyyy').format(record.recordDate)),
              _buildRevertDetailRow('Amount', Formatters.currency(record.totalSalesAmount)),
              _buildRevertDetailRow('Items', '${record.items.length} products'),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                decoration: InputDecoration(
                  labelText: 'Reason for revert *',
                  hintText: 'Enter reason...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                maxLines: 2,
                autofocus: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (reasonController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a reason for reverting')),
                );
                return;
              }
              Navigator.pop(context, true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Request OTP'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      _requestRevertOtp(record, reasonController.text.trim());
    }
  }

  Widget _buildRevertDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  /// Request OTP for revert
  Future<void> _requestRevertOtp(DailySalesRecord record, String reason) async {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    final authService = Provider.of<AuthService>(context, listen: false);
    final dailySalesService = DailySalesService(authService);
    final response = await dailySalesService.requestRevertOtp(record.id!);

    if (!mounted) return;
    Navigator.pop(context); // Close loading

    if (response.success && response.data != null) {
      _showOtpVerificationDialog(record, reason, response.data!);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Failed to send OTP: ${response.error ?? 'Unknown error'}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Show modern iOS 26 style OTP verification modal
  /// Features: Individual digit inputs, auto-focus, resend cooldown, haptic feedback
  void _showOtpVerificationDialog(DailySalesRecord record, String reason, RevertOtpResponse otpResponse) {
    HapticFeedback.mediumImpact();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (context) => _ModernOtpVerificationSheet(
        record: record,
        reason: reason,
        otpResponse: otpResponse,
        onVerify: (emailOtp, phoneOtp) {
          _verifyAndRevertRecord(record, emailOtp, phoneOtp, reason);
        },
        onResendOtp: () {
          Navigator.pop(context);
          _requestRevertOtp(record, reason);
        },
      ),
    );
  }

  /// Verify OTPs and revert the record
  Future<void> _verifyAndRevertRecord(
    DailySalesRecord record,
    String emailOtp,
    String phoneOtp,
    String reason,
  ) async {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    final authService = Provider.of<AuthService>(context, listen: false);
    final dailySalesService = DailySalesService(authService);
    final response = await dailySalesService.verifyAndRevertRecord(
      recordId: record.id!,
      emailOtp: emailOtp,
      phoneOtp: phoneOtp,
      reason: reason,
    );

    if (!mounted) return;
    Navigator.pop(context); // Close loading

    if (response.success) {
      // Refresh the list
      await _loadSales();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Sale reverted successfully. Stock has been restored.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 4),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Failed to revert: ${response.error ?? 'Unknown error'}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

// ============================================================================
// MODERN iOS 26 STYLE OTP VERIFICATION SHEET
// ============================================================================

/// Modern OTP Verification Bottom Sheet
/// Features:
/// - Individual digit inputs with auto-focus navigation
/// - Dual OTP support (Email + Phone)
/// - Resend cooldown timer with visual feedback
/// - Haptic feedback on interactions
/// - Attempt tracking with lockout protection
/// - iOS 26 inspired design language
class _ModernOtpVerificationSheet extends StatefulWidget {
  final DailySalesRecord record;
  final String reason;
  final RevertOtpResponse otpResponse;
  final void Function(String emailOtp, String phoneOtp) onVerify;
  final VoidCallback onResendOtp;

  const _ModernOtpVerificationSheet({
    required this.record,
    required this.reason,
    required this.otpResponse,
    required this.onVerify,
    required this.onResendOtp,
  });

  @override
  State<_ModernOtpVerificationSheet> createState() => _ModernOtpVerificationSheetState();
}

class _ModernOtpVerificationSheetState extends State<_ModernOtpVerificationSheet>
    with SingleTickerProviderStateMixin {
  // Email OTP controllers (6 digits)
  final List<TextEditingController> _emailControllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _emailFocusNodes = List.generate(6, (_) => FocusNode());

  // Phone OTP controllers (6 digits)
  final List<TextEditingController> _phoneControllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _phoneFocusNodes = List.generate(6, (_) => FocusNode());

  // State
  late int _remainingSeconds;
  int _attemptCount = 0;
  static const int _maxAttempts = 3;
  static const int _resendCooldown = 30; // Seconds before resend is enabled
  int _resendCooldownRemaining = 0;
  bool _isVerifying = false;
  Timer? _expiryTimer;
  Timer? _resendTimer;

  // Animation
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.otpResponse.remainingSeconds;
    _startExpiryTimer();

    // Shake animation for errors
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 10).chain(
      CurveTween(curve: Curves.elasticIn),
    ).animate(_shakeController);

    // Auto-focus first email input
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _emailFocusNodes[0].requestFocus();
    });
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _resendTimer?.cancel();
    _shakeController.dispose();
    for (var c in _emailControllers) {
      c.dispose();
    }
    for (var c in _phoneControllers) {
      c.dispose();
    }
    for (var f in _emailFocusNodes) {
      f.dispose();
    }
    for (var f in _phoneFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _startExpiryTimer() {
    _expiryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() => _remainingSeconds--);
      } else {
        timer.cancel();
      }
    });
  }

  void _startResendCooldown() {
    _resendCooldownRemaining = _resendCooldown;
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCooldownRemaining > 0) {
        setState(() => _resendCooldownRemaining--);
      } else {
        timer.cancel();
      }
    });
  }

  String get _emailOtp => _emailControllers.map((c) => c.text).join();
  String get _phoneOtp => _phoneControllers.map((c) => c.text).join();
  bool get _isExpired => _remainingSeconds <= 0;
  bool get _canResend => _resendCooldownRemaining <= 0;
  bool get _isComplete => _emailOtp.length == 6 && _phoneOtp.length == 6;

  void _onDigitChanged(
    String value,
    int index,
    List<TextEditingController> controllers,
    List<FocusNode> focusNodes,
    List<FocusNode>? nextGroupFocusNodes,
  ) {
    if (value.length == 1) {
      HapticFeedback.selectionClick();
      // Move to next field
      if (index < 5) {
        focusNodes[index + 1].requestFocus();
      } else if (nextGroupFocusNodes != null) {
        // Move to first field of next group (phone OTP)
        nextGroupFocusNodes[0].requestFocus();
      } else {
        // Last digit entered - unfocus
        focusNodes[index].unfocus();
      }
    }
  }

  void _onKeyPressed(
    KeyEvent event,
    int index,
    List<TextEditingController> controllers,
    List<FocusNode> focusNodes,
    List<FocusNode>? prevGroupFocusNodes,
  ) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.backspace) {
      if (controllers[index].text.isEmpty && index > 0) {
        // Move to previous field on backspace when empty
        focusNodes[index - 1].requestFocus();
        controllers[index - 1].clear();
        HapticFeedback.selectionClick();
      } else if (controllers[index].text.isEmpty && index == 0 && prevGroupFocusNodes != null) {
        // Move to last field of previous group (email OTP)
        prevGroupFocusNodes[5].requestFocus();
        HapticFeedback.selectionClick();
      }
    }
  }

  Future<void> _handleVerify() async {
    if (!_isComplete) {
      HapticFeedback.heavyImpact();
      _shakeController.forward().then((_) => _shakeController.reset());
      return;
    }

    if (_isExpired) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('OTP has expired. Please request a new one.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _attemptCount++);

    if (_attemptCount >= _maxAttempts) {
      HapticFeedback.heavyImpact();
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maximum attempts exceeded. Please try again later.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isVerifying = true);
    HapticFeedback.mediumImpact();

    // Close sheet and verify
    Navigator.pop(context);
    widget.onVerify(_emailOtp, _phoneOtp);
  }

  void _handleResend() {
    if (!_canResend) return;

    HapticFeedback.mediumImpact();
    _startResendCooldown();
    widget.onResendOtp();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(_shakeAnimation.value, 0),
          child: child,
        );
      },
      child: Container(
        margin: EdgeInsets.only(bottom: bottomPadding),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle bar
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Header
                  _buildHeader(),
                  const SizedBox(height: 24),

                  // Timer
                  _buildTimer(),
                  const SizedBox(height: 28),

                  // Email OTP Section
                  _buildOtpSection(
                    icon: CupertinoIcons.mail_solid,
                    iconColor: Colors.blue,
                    label: 'Email OTP',
                    maskedValue: widget.otpResponse.maskedEmail,
                    controllers: _emailControllers,
                    focusNodes: _emailFocusNodes,
                    nextGroupFocusNodes: _phoneFocusNodes,
                    prevGroupFocusNodes: null,
                  ),
                  const SizedBox(height: 24),

                  // Phone OTP Section
                  _buildOtpSection(
                    icon: CupertinoIcons.phone_fill,
                    iconColor: Colors.green,
                    label: 'Phone OTP',
                    maskedValue: widget.otpResponse.maskedPhone,
                    controllers: _phoneControllers,
                    focusNodes: _phoneFocusNodes,
                    nextGroupFocusNodes: null,
                    prevGroupFocusNodes: _emailFocusNodes,
                  ),
                  const SizedBox(height: 20),

                  // Attempts remaining
                  if (_attemptCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            CupertinoIcons.exclamationmark_circle,
                            size: 14,
                            color: _attemptCount >= 2 ? Colors.red : Colors.orange,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${_maxAttempts - _attemptCount} attempt${_maxAttempts - _attemptCount != 1 ? 's' : ''} remaining',
                            style: TextStyle(
                              fontSize: 13,
                              color: _attemptCount >= 2 ? Colors.red : Colors.orange,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Resend OTP
                  _buildResendButton(),
                  const SizedBox(height: 24),

                  // Action buttons
                  _buildActionButtons(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        // Shield icon with gradient background
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                cs.primary.withValues(alpha: 0.15),
                cs.primary.withValues(alpha: 0.05),
              ],
            ),
            shape: BoxShape.circle,
          ),
          child: Icon(
            CupertinoIcons.lock_shield_fill,
            size: 36,
            color: cs.primary,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Verify Your Identity',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Enter the 6-digit codes sent to your email and phone to confirm this revert action.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildTimer() {
    final minutes = _remainingSeconds ~/ 60;
    final seconds = _remainingSeconds % 60;
    final isUrgent = _remainingSeconds <= 60;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: _isExpired
            ? Colors.red.withValues(alpha: 0.1)
            : isUrgent
                ? Colors.orange.withValues(alpha: 0.1)
                : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: _isExpired
              ? Colors.red.withValues(alpha: 0.3)
              : isUrgent
                  ? Colors.orange.withValues(alpha: 0.3)
                  : Colors.transparent,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _isExpired ? CupertinoIcons.xmark_circle_fill : CupertinoIcons.clock_fill,
            size: 18,
            color: _isExpired
                ? Colors.red
                : isUrgent
                    ? Colors.orange
                    : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text(
            _isExpired
                ? 'Code expired'
                : 'Expires in ${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _isExpired
                  ? Colors.red
                  : isUrgent
                      ? Colors.orange
                      : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOtpSection({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String maskedValue,
    required List<TextEditingController> controllers,
    required List<FocusNode> focusNodes,
    required List<FocusNode>? nextGroupFocusNodes,
    required List<FocusNode>? prevGroupFocusNodes,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label with icon
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 16, color: iconColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    maskedValue,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // OTP digit inputs
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (index) {
            return SizedBox(
              width: 48,
              height: 56,
              child: KeyboardListener(
                focusNode: FocusNode(),
                onKeyEvent: (event) => _onKeyPressed(
                  event,
                  index,
                  controllers,
                  focusNodes,
                  prevGroupFocusNodes,
                ),
                child: TextField(
                  controller: controllers[index],
                  focusNode: focusNodes[index],
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  maxLength: 1,
                  enabled: !_isExpired && !_isVerifying,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    filled: true,
                    fillColor: _isExpired ? Theme.of(context).colorScheme.surfaceContainerHighest : Theme.of(context).colorScheme.surfaceContainerHighest,
                    contentPadding: EdgeInsets.zero,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: iconColor, width: 2),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  onChanged: (value) => _onDigitChanged(
                    value,
                    index,
                    controllers,
                    focusNodes,
                    nextGroupFocusNodes,
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildResendButton() {
    final cs = Theme.of(context).colorScheme;
    if (_isExpired) {
      return GestureDetector(
        onTap: _handleResend,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(CupertinoIcons.arrow_clockwise, size: 18, color: Colors.orange[700]),
              const SizedBox(width: 8),
              Text(
                'Resend OTP Codes',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange[700],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          "Didn't receive the code? ",
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        GestureDetector(
          onTap: _canResend ? _handleResend : null,
          child: Text(
            _canResend ? 'Resend' : 'Resend in ${_resendCooldownRemaining}s',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _canResend ? cs.primary : cs.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        // Cancel button
        Expanded(
          child: CupertinoButton(
            padding: const EdgeInsets.symmetric(vertical: 14),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.pop(context);
            },
            child: Text(
              'Cancel',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),

        // Verify button
        Expanded(
          flex: 2,
          child: CupertinoButton(
            padding: const EdgeInsets.symmetric(vertical: 14),
            color: _isComplete && !_isExpired
                ? cs.primary
                : cs.outlineVariant,
            borderRadius: BorderRadius.circular(14),
            onPressed: _isVerifying ? null : _handleVerify,
            child: _isVerifying
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        CupertinoIcons.checkmark_shield_fill,
                        size: 20,
                        color: _isComplete && !_isExpired
                            ? Colors.white
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Verify & Revert',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: _isComplete && !_isExpired
                              ? Colors.white
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}