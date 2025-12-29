import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/dio_api_service.dart';
import '../../../core/widgets/sale_details_modal.dart';
import '../providers/daily_sales_provider.dart';
import '../models/daily_sales_models.dart';
import '../models/sale.dart' hide DailySalesRecord;
import '../services/daily_sales_service.dart';
import '../services/sales_service.dart';
import '../widgets/ai_validation_badge.dart';
import '../widgets/ai_validation_modal.dart';
import '../widgets/receipt_image_viewer.dart';

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

  @override
  void initState() {
    super.initState();
    // Add scroll listener for infinite scroll
    _scrollController.addListener(_onScroll);
    // Use addPostFrameCallback to avoid calling setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSales();
    });
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

    print('📜 [SalesHistory] Loading more records...');
    await provider.loadMoreRecords(
      startDate: _dateRange?.start,
      endDate: _dateRange?.end,
    );
  }

  Future<void> _loadSales() async {
    print('📜 [SalesHistory] Loading daily sales records...');
    _initialLoadComplete = false; // Reset on new load
    final provider = context.read<DailySalesProvider>();
    // Always load ALL records - filter by status client-side only
    // This ensures shop chips always show all available shops
    await provider.fetchRecords(
      startDate: _dateRange?.start,
      endDate: _dateRange?.end,
      // Don't pass status to API - filter client-side instead
    );
    print('📜 [SalesHistory] Loaded ${provider.records.length} daily sales records');

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

  /// Extract unique shops from records
  Map<String, String> _getUniqueShops(List<DailySalesRecord> records) {
    final shopMap = <String, String>{};
    for (final record in records) {
      if (record.shopId.isNotEmpty && !shopMap.containsKey(record.shopId)) {
        shopMap[record.shopId] = record.shopName ?? record.shopId;
      }
    }
    return shopMap;
  }

  @override
  Widget build(BuildContext context) {
    // Don't use Scaffold since we're embedded in AdaptiveSalesScreen
    return Container(
      color: Colors.grey[50],
      child: Column(
        children: [
          // Filters Bar
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              children: [
                // Shop Quick Filter Chips
                Consumer<DailySalesProvider>(
                  builder: (context, provider, _) {
                    final shops = _getUniqueShops(provider.records);
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          // "All" chip
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: const Text('All'),
                              selected: _selectedShopId == null,
                              onSelected: (_) => setState(() => _selectedShopId = null),
                              selectedColor: AppColors.primary.withOpacity(0.2),
                              checkmarkColor: AppColors.primary,
                              labelStyle: TextStyle(
                                color: _selectedShopId == null ? AppColors.primary : Colors.black87,
                                fontWeight: _selectedShopId == null ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ),
                          // Shop chips
                          ...shops.entries.map((entry) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(entry.value),
                              selected: _selectedShopId == entry.key,
                              onSelected: (_) => setState(() => _selectedShopId = entry.key),
                              selectedColor: AppColors.primary.withOpacity(0.2),
                              checkmarkColor: AppColors.primary,
                              labelStyle: TextStyle(
                                color: _selectedShopId == entry.key ? AppColors.primary : Colors.black87,
                                fontWeight: _selectedShopId == entry.key ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          )),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                // Filter Row - Date Range and Status
                Row(
                  children: [
                    // Date Range - Flexible
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _selectDateRange,
                        icon: const Icon(CupertinoIcons.calendar, size: 16),
                        label: Text(
                          _dateRange == null
                              ? 'Select Date'
                              : '${Formatters.dateShort(_dateRange!.start)} - ${Formatters.dateShort(_dateRange!.end)}',
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Status Filter - Compact
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButton<String>(
                        value: _filterStatus,
                        underline: const SizedBox(),
                        isDense: true,
                        style: const TextStyle(fontSize: 14, color: Colors.black87),
                        items: ['All', 'Pending', 'Approved', 'Rejected']
                            .map((status) => DropdownMenuItem(
                                  value: status,
                                  child: Text(status),
                                ))
                            .toList(),
                        onChanged: (value) {
                          setState(() {
                            _filterStatus = value!;
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Quick Stats
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
                  return const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.primary,
                    ),
                  );
                }

                if (records.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          CupertinoIcons.doc_text,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No daily sales records found',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: _loadSales,
                          child: const Text('Refresh'),
                        ),
                      ],
                    ),
                  );
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

  Widget _buildQuickStats() {
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
                color: Colors.blue,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildStatChip(
                icon: CupertinoIcons.money_dollar_circle_fill,
                label: 'Revenue',
                value: Formatters.currencyCompact(todayTotal),
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildStatChip(
                icon: CupertinoIcons.clock_fill,
                label: 'Pending',
                value: '${provider.records.where((r) => r.status == 'pending').length}',
                color: Colors.orange,
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
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
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

  Widget _buildRecordCard(DailySalesRecord record) {
    // Get creator info - prefer createdByName, fallback to salesmanName
    final createdBy = record.createdByName ?? record.salesmanName;

    // Check if there are multiple payment methods
    final hasMultiplePayments = [
      record.totalCashAmount,
      record.totalCardAmount,
      record.totalUpiAmount,
      record.totalCreditAmount,
    ].where((amt) => amt > 0).length > 1;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: () => _viewRecordDetails(record),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Main Row: Status Avatar + Info + Amount
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status Avatar (like Inventory design)
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: _getStatusColor(record.status).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _getStatusIcon(record.status),
                      color: _getStatusColor(record.status),
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Info Section
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Date + Status Badge Row
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                DateFormat('d MMM yyyy').format(record.recordDate),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1A1A1A),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildStatusBadge(record.status),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // Shop Row
                        Row(
                          children: [
                            Icon(
                              CupertinoIcons.building_2_fill,
                              size: 13,
                              color: Colors.grey[500],
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                record.shopName ?? 'Shop ${record.shopId}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // Created By Row (NEW - User Attribution)
                        if (createdBy != null) ...[
                          Row(
                            children: [
                              Icon(
                                CupertinoIcons.person_fill,
                                size: 13,
                                color: AppColors.primary.withValues(alpha: 0.7),
                              ),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  'Created by: $createdBy',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.primary.withValues(alpha: 0.8),
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                        // Time Ago Row
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              CupertinoIcons.clock,
                              size: 12,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(width: 5),
                            Text(
                              Formatters.relativeTime(record.recordDate),
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Amount Column
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        Formatters.currency(record.totalSalesAmount),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Items count badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${record.items.length} items',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // Approval Info (for APPROVED status)
              if (record.status.toLowerCase() == 'approved' && record.approvedByName != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        CupertinoIcons.checkmark_seal_fill,
                        size: 16,
                        color: Colors.green,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              const TextSpan(
                                text: 'Approved by: ',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.green,
                                ),
                              ),
                              TextSpan(
                                text: record.approvedByName!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green,
                                ),
                              ),
                              if (record.approvedAt != null) ...[
                                TextSpan(
                                  text: ' • ${Formatters.relativeTime(record.approvedAt!)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.green.withValues(alpha: 0.7),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Rejection Info (for REJECTED status)
              if (record.status.toLowerCase() == 'rejected') ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            CupertinoIcons.xmark_seal_fill,
                            size: 16,
                            color: Colors.red,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: record.rejectedByName != null
                                        ? 'Rejected by: ${record.rejectedByName}'
                                        : 'Rejected',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.red,
                                    ),
                                  ),
                                  if (record.rejectedAt != null) ...[
                                    TextSpan(
                                      text: ' • ${Formatters.relativeTime(record.rejectedAt!)}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.red.withValues(alpha: 0.7),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      // Show rejection reason if available
                      if (record.rejectionReason != null && record.rejectionReason!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              CupertinoIcons.text_quote,
                              size: 14,
                              color: Colors.red.withValues(alpha: 0.6),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '"${record.rejectionReason}"',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic,
                                  color: Colors.red.withValues(alpha: 0.8),
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],

              // Resubmission Info (if record was resubmitted)
              if (record.resubmitCount > 0) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        CupertinoIcons.arrow_2_circlepath,
                        size: 14,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        record.resubmittedByName != null
                            ? 'Resubmitted by: ${record.resubmittedByName}'
                            : 'Resubmitted (${record.resubmitCount}x)',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Payment Breakdown (only show if multiple payment methods)
              if (hasMultiplePayments) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      if (record.totalCashAmount > 0)
                        Flexible(child: _buildPaymentChip('Cash', record.totalCashAmount, Colors.green, CupertinoIcons.money_dollar)),
                      if (record.totalCardAmount > 0)
                        Flexible(child: _buildPaymentChip('Card', record.totalCardAmount, Colors.blue, CupertinoIcons.creditcard)),
                      if (record.totalUpiAmount > 0)
                        Flexible(child: _buildPaymentChip('UPI', record.totalUpiAmount, Colors.purple, CupertinoIcons.qrcode)),
                      if (record.totalCreditAmount > 0)
                        Flexible(child: _buildPaymentChip('Credit', record.totalCreditAmount, Colors.orange, CupertinoIcons.doc_text)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentChip(String label, double amount, Color color, IconData icon) {
    if (amount == 0) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          Formatters.currency(amount),
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  /// Modern Apple-style record card with shop-first hierarchy
  Widget _buildModernRecordCard(DailySalesRecord record) {
    final createdBy = record.createdByName ?? record.salesmanName;
    final shopName = record.shopName ?? 'Shop ${record.shopId}';
    final status = record.status;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _viewRecordDetails(record),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Row 1: Shop name with icon + Receipt thumbnail + chevron
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        CupertinoIcons.building_2_fill,
                        color: AppColors.primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        shopName,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A1A),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Receipt thumbnail (NEW - AI Validation Feature)
                    if (record.hasImages) ...[
                      _buildReceiptThumbnail(record),
                      const SizedBox(width: 8),
                    ],
                    Icon(
                      CupertinoIcons.chevron_right,
                      color: Colors.grey[400],
                      size: 20,
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Row 2: Creator name • Items count
                Padding(
                  padding: const EdgeInsets.only(left: 54),
                  child: Row(
                    children: [
                      Icon(
                        CupertinoIcons.person_fill,
                        size: 14,
                        color: Colors.grey[500],
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          createdBy != null
                              ? '$createdBy • ${record.items.length} items'
                              : '${record.items.length} items',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

                // Row 2.5: Category breakdown chips (NEW)
                if (record.items.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 54),
                    child: _buildCategoryChips(record),
                  ),
                ],
                const SizedBox(height: 14),

                // Row 3: Amount and Status badge
                Padding(
                  padding: const EdgeInsets.only(left: 54),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        Formatters.currency(record.totalSalesAmount),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                      _buildModernStatusBadge(status),
                    ],
                  ),
                ),

                // AI Validation Badge (NEW - for pending records with images)
                if (record.hasImages && status.toLowerCase() == 'pending') ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.only(left: 54),
                    child: AIValidationBadge(
                      record: record,
                      compact: false,
                      onTap: () => _showValidationModal(record),
                    ),
                  ),
                ],

                // Approval Info + Revert Button (Admin Only)
                if (status.toLowerCase() == 'approved') ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.only(left: 54),
                    child: Row(
                      children: [
                        // Approved by info
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                const Icon(CupertinoIcons.checkmark_seal_fill, size: 14, color: Colors.green),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    record.approvedByName != null
                                        ? 'Approved by ${record.approvedByName}'
                                        : 'Approved',
                                    style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w500),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Revert Button - Admin Only
                        FutureBuilder<String?>(
                          future: Provider.of<AuthService>(context, listen: false).getUserRole(),
                          builder: (context, snapshot) {
                            final userRole = snapshot.data ?? '';
                            final isAdmin = userRole == 'admin' || userRole == 'saas_admin';

                            if (!isAdmin) return const SizedBox.shrink();

                            return Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Material(
                                color: Colors.red.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                child: InkWell(
                                  onTap: () => _showRevertConfirmation(record),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          CupertinoIcons.arrow_uturn_left,
                                          size: 14,
                                          color: Colors.red,
                                        ),
                                        const SizedBox(width: 6),
                                        const Text(
                                          'Revert',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.red,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],

                // Rejection Info
                if (status.toLowerCase() == 'rejected') ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.only(left: 54),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(CupertinoIcons.xmark_seal_fill, size: 14, color: Colors.red),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  record.rejectedByName != null
                                      ? 'Rejected by ${record.rejectedByName}'
                                      : 'Rejected',
                                  style: const TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w500),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          if (record.rejectionReason != null && record.rejectionReason!.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              '"${record.rejectionReason}"',
                              style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.red.withOpacity(0.8)),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],

                // Resubmission Info
                if (record.resubmitCount > 0) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 54),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(CupertinoIcons.arrow_2_circlepath, size: 14, color: Colors.orange),
                          const SizedBox(width: 6),
                          Text(
                            record.resubmittedByName != null
                                ? 'Resubmitted by ${record.resubmittedByName}'
                                : 'Resubmitted (${record.resubmitCount}x)',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.orange),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Modern status badge with icon
  Widget _buildModernStatusBadge(String status) {
    final color = _getStatusColor(status);
    final icon = _getStatusIcon(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
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

  Widget _buildStatusBadge(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _getStatusColor(status),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: _getStatusColor(status).withValues(alpha: 0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        status.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  /// Build category breakdown chips (e.g., WHISKEY/IMFL 42, BEER 18)
  Widget _buildCategoryChips(DailySalesRecord record) {
    // Group items by category and count
    final categoryCount = <String, int>{};
    for (final item in record.items) {
      final category = item.categoryName ?? 'Other';
      categoryCount[category] = (categoryCount[category] ?? 0) + item.quantity.toInt();
    }

    // Sort by count descending and take top 3
    final sortedCategories = categoryCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topCategories = sortedCategories.take(3).toList();

    if (topCategories.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: topCategories.map((entry) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.primary.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Text(
            '${entry.key} ${entry.value}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.primary.withOpacity(0.85),
            ),
          ),
        );
      }).toList(),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'rejected':
        return Colors.red;
      case 'returned':
        return Colors.purple;
      default:
        return Colors.grey;
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

  /// Group records by date for section headers (Apple-style)
  Map<String, List<DailySalesRecord>> _groupRecordsByDate(List<DailySalesRecord> records) {
    final grouped = <String, List<DailySalesRecord>>{};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    for (final record in records) {
      final recordDateOnly = DateTime(
        record.recordDate.year,
        record.recordDate.month,
        record.recordDate.day,
      );

      String groupKey;
      if (recordDateOnly == today) {
        groupKey = 'Today';
      } else if (recordDateOnly == yesterday) {
        groupKey = 'Yesterday';
      } else {
        groupKey = DateFormat('d MMMM yyyy').format(record.recordDate);
      }

      grouped.putIfAbsent(groupKey, () => []).add(record);
    }
    return grouped;
  }

  /// Build date section header (Apple-style)
  Widget _buildDateHeader(String dateGroup) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(
        dateGroup.toUpperCase(),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.grey[500],
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  /// Build grouped list with date headers and infinite scroll
  Widget _buildGroupedList(List<DailySalesRecord> records) {
    final groupedRecords = _groupRecordsByDate(records);
    final sortedKeys = groupedRecords.keys.toList();

    // Sort date groups: Always newest dates first for better UX
    // The individual records within each group are already sorted by createdAt for Pending
    sortedKeys.sort((a, b) {
      // Newest first: Today first, oldest dates last
      if (a == 'Today') return -1;
      if (b == 'Today') return 1;
      if (a == 'Yesterday') return -1;
      if (b == 'Yesterday') return 1;
      try {
        final dateA = DateFormat('d MMMM yyyy').parse(a);
        final dateB = DateFormat('d MMMM yyyy').parse(b);
        return dateB.compareTo(dateA); // Descending - newest first
      } catch (_) {
        return b.compareTo(a);
      }
    });

    // Calculate total item count including loading indicator
    final baseCount = sortedKeys.fold<int>(
      0,
      (sum, key) => sum + 1 + groupedRecords[key]!.length,
    );

    return RefreshIndicator(
      onRefresh: _loadSales,
      child: Consumer<DailySalesProvider>(
        builder: (context, provider, _) {
          // Add 1 for loading indicator if has more records
          final itemCount = baseCount + (provider.hasMoreRecords ? 1 : 0);

          return ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: itemCount,
            itemBuilder: (context, index) {
              // If this is the last item and we have more records, show loading indicator
              if (index == baseCount && provider.hasMoreRecords) {
                return _buildLoadingIndicator(provider.isLoadingMore);
              }

              int currentIndex = 0;
              for (final key in sortedKeys) {
                if (currentIndex == index) {
                  return _buildDateHeader(key);
                }
                currentIndex++;

                final sectionRecords = groupedRecords[key]!;
                for (int i = 0; i < sectionRecords.length; i++) {
                  if (currentIndex == index) {
                    return _buildModernRecordCard(sectionRecords[i]);
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

  /// Build loading indicator for infinite scroll (Instagram-style)
  Widget _buildLoadingIndicator(bool isLoading) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: isLoading
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Loading more...',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              )
            : GestureDetector(
                onTap: _loadMoreSales,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.arrow_down_circle,
                        size: 16,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Load more',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.primary,
                        ),
                      ),
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

    return GestureDetector(
      onTap: () => ReceiptImageViewer.show(
        context,
        imageUrls: record.imageUrls,
        title: 'Receipt',
      ),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: record.imageUrls.first,
              width: 44,
              height: 44,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                width: 44,
                height: 44,
                color: Colors.grey[200],
                child: const CupertinoActivityIndicator(radius: 8),
              ),
              errorWidget: (context, url, error) => Container(
                width: 44,
                height: 44,
                color: Colors.grey[200],
                child: Icon(
                  CupertinoIcons.photo,
                  color: Colors.grey[400],
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
                  color: Colors.black.withOpacity(0.7),
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
  void _showValidationModal(DailySalesRecord record) async {
    // Get current user role for approval permissions
    final authService = Provider.of<AuthService>(context, listen: false);
    final userRole = await authService.getUserRole();
    final canApprove = userRole == 'admin' ||
                      userRole == 'manager' ||
                      userRole == 'assistant_manager';

    if (!mounted) return;

    await AIValidationModal.show(
      context,
      record: record,
      validationResult: record.validationResult,
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

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _approveRecord(DailySalesRecord record) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve Daily Sales'),
        content: Text(
          'Approve sales record for ${record.shopName ?? record.shopId}?\n\n'
          'Amount: ${Formatters.currency(record.totalSalesAmount)}\n\n'
          'Stock will be deducted upon approval.',
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

    if (confirmed != true || !mounted) return;

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    // Call approval API
    final authService = Provider.of<AuthService>(context, listen: false);
    final dailySalesService = DailySalesService(authService);
    final response = await dailySalesService.approveDailySalesRecord(record.id!);

    if (!mounted) return;
    Navigator.pop(context); // Close loading dialog

    if (response.success) {
      // Refresh the list
      await _loadSales();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Daily sales record approved successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Failed to approve: ${response.message}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _rejectRecord(DailySalesRecord record) async {
    // Show reason input dialog
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Daily Sales'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Reject sales record for ${record.shopName ?? record.shopId}?',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason for rejection *',
                hintText: 'Enter reason...',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (reasonController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a reason')),
                );
                return;
              }
              Navigator.pop(context, reasonController.text.trim());
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (reason == null || reason.isEmpty || !mounted) return;

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    // Call rejection API
    final authService = Provider.of<AuthService>(context, listen: false);
    final dailySalesService = DailySalesService(authService);
    final response = await dailySalesService.rejectDailySalesRecord(record.id!, reason);

    if (!mounted) return;
    Navigator.pop(context); // Close loading dialog

    if (response.success) {
      // Refresh the list
      await _loadSales();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Daily sales record rejected'),
          backgroundColor: Colors.orange,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Failed to reject: ${response.message}'),
          backgroundColor: Colors.red,
        ),
      );
    }
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
                color: Colors.red.withOpacity(0.1),
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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
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
              style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500),
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
                fillColor: Colors.grey[50],
              ),
              maxLines: 3,
              autofocus: true,
            ),
          ],
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
          Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
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

  /// Show OTP verification dialog with dual OTP inputs
  void _showOtpVerificationDialog(DailySalesRecord record, String reason, RevertOtpResponse otpResponse) {
    final emailOtpController = TextEditingController();
    final phoneOtpController = TextEditingController();
    int remainingSeconds = otpResponse.remainingSeconds;
    int attemptCount = 0;
    const maxAttempts = 3;
    Timer? countdownTimer;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // Start countdown timer
            countdownTimer ??= Timer.periodic(const Duration(seconds: 1), (timer) {
              if (remainingSeconds > 0) {
                setDialogState(() {
                  remainingSeconds--;
                });
              } else {
                timer.cancel();
              }
            });

            final minutes = remainingSeconds ~/ 60;
            final seconds = remainingSeconds % 60;
            final isExpired = remainingSeconds <= 0;

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(CupertinoIcons.lock_shield_fill, color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('OTP Verification', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Info box
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Enter OTPs sent to:',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(CupertinoIcons.mail_solid, size: 14, color: Colors.blue),
                              const SizedBox(width: 6),
                              Text(
                                otpResponse.maskedEmail,
                                style: const TextStyle(fontSize: 12, color: Colors.blue),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(CupertinoIcons.phone_fill, size: 14, color: Colors.green),
                              const SizedBox(width: 6),
                              Text(
                                otpResponse.maskedPhone,
                                style: const TextStyle(fontSize: 12, color: Colors.green),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Timer or Resend button
                    Center(
                      child: isExpired
                          ? ElevatedButton.icon(
                              onPressed: () async {
                                countdownTimer?.cancel();
                                Navigator.pop(dialogContext);
                                _requestRevertOtp(record, reason);
                              },
                              icon: const Icon(CupertinoIcons.arrow_clockwise, size: 16),
                              label: const Text('Resend OTPs'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                              ),
                            )
                          : Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: remainingSeconds <= 60 ? Colors.red.withOpacity(0.1) : Colors.grey[100],
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    CupertinoIcons.clock,
                                    size: 16,
                                    color: remainingSeconds <= 60 ? Colors.red : Colors.grey[600],
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Expires in ${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: remainingSeconds <= 60 ? Colors.red : Colors.grey[700],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                    const SizedBox(height: 16),

                    // Email OTP input
                    TextField(
                      controller: emailOtpController,
                      decoration: InputDecoration(
                        labelText: 'Email OTP',
                        hintText: '6-digit code',
                        prefixIcon: const Icon(CupertinoIcons.mail, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.grey[50],
                      ),
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      enabled: !isExpired,
                    ),
                    const SizedBox(height: 12),

                    // Phone OTP input
                    TextField(
                      controller: phoneOtpController,
                      decoration: InputDecoration(
                        labelText: 'Phone OTP',
                        hintText: '6-digit code',
                        prefixIcon: const Icon(CupertinoIcons.phone, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.grey[50],
                      ),
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      enabled: !isExpired,
                    ),

                    // Attempts remaining
                    if (attemptCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Attempts remaining: ${maxAttempts - attemptCount}',
                          style: TextStyle(
                            fontSize: 12,
                            color: attemptCount >= 2 ? Colors.red : Colors.grey[600],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    countdownTimer?.cancel();
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isExpired
                      ? null
                      : () async {
                          final emailOtp = emailOtpController.text.trim();
                          final phoneOtp = phoneOtpController.text.trim();

                          if (emailOtp.length != 6 || phoneOtp.length != 6) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please enter both 6-digit OTPs')),
                            );
                            return;
                          }

                          attemptCount++;
                          if (attemptCount >= maxAttempts) {
                            countdownTimer?.cancel();
                            Navigator.pop(dialogContext);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('❌ Maximum attempts exceeded. Please try again.'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }

                          countdownTimer?.cancel();
                          Navigator.pop(dialogContext);
                          _verifyAndRevertRecord(record, emailOtp, phoneOtp, reason);
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Verify & Revert'),
                ),
              ],
            );
          },
        );
      },
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