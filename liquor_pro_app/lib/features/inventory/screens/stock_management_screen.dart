// Stock Management Screen - Combined Approvals & History with Tabs
//
// Combines Stock Approvals and Purchase History into a single tabbed interface.
// Design matches the "Add New Stock" bottom sheet for consistency.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/providers/shop_selection_provider.dart';
import '../../../core/utils/date_time_helper.dart';
import '../providers/stock_purchase_provider.dart';
import '../models/stock_purchase.dart';
import '../../auth/providers/auth_provider.dart';

class StockManagementScreen extends StatefulWidget {
  const StockManagementScreen({super.key});

  @override
  State<StockManagementScreen> createState() => _StockManagementScreenState();
}

class _StockManagementScreenState extends State<StockManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _currencyFormat =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
  final _dateFormat = DateFormat('dd MMM yyyy, hh:mm a');
  final _scrollController = ScrollController();

  // Shop filter state - null means "All Shops"
  String? _selectedShopId;

  // History filter state
  StockPurchaseStatus? _selectedStatus;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _scrollController.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    // Use local filter - null means ALL shops (industrial UX pattern)
    final provider = context.read<StockPurchaseProvider>();
    await Future.wait([
      provider.loadPendingApprovals(shopId: _selectedShopId, refresh: true),
      provider.loadPurchaseHistory(shopId: _selectedShopId, status: _selectedStatus, refresh: true),
    ]);
  }

  void _onScroll() {
    if (_tabController.index == 1 &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200) {
      _loadMoreHistory();
    }
  }

  Future<void> _loadMoreHistory() async {
    // Use local filter - null means ALL shops
    await context.read<StockPurchaseProvider>().loadMoreHistory(
          shopId: _selectedShopId,
          status: _selectedStatus,
        );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surfaceContainerHighest,
      appBar: AppBar(
        title: const Text('Stock Purchases'),
        centerTitle: true,
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: cs.primary,
          unselectedLabelColor: cs.onSurfaceVariant,
          indicatorColor: cs.primary,
          indicatorWeight: 3,
          tabs: [
            Consumer<StockPurchaseProvider>(
              builder: (context, provider, child) {
                final count = provider.pendingCount;
                return Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.pending_actions, size: 18),
                      const SizedBox(width: 6),
                      const Text('Pending'),
                      if (count > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.warning,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            count > 99 ? '99+' : count.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
            const Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history, size: 18),
                  SizedBox(width: 6),
                  Text('History'),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Shop Filter Dropdown - Industrial UX Pattern
          _buildShopFilterDropdown(),
          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildApprovalsTab(),
                _buildHistoryTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== SHOP FILTER DROPDOWN ====================

  Widget _buildShopFilterDropdown() {
    return Consumer<ShopSelectionProvider>(
      builder: (context, shopProvider, child) {
        final shops = shopProvider.shops;

        final cs = Theme.of(context).colorScheme;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: cs.surface,
            border: Border(
              bottom: BorderSide(color: cs.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.store_outlined, size: 20, color: cs.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: _selectedShopId,
                      isExpanded: true,
                      icon: Icon(Icons.keyboard_arrow_down, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      hint: const Text(
                        'All Shops',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      items: [
                        // "All Shops" option
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: cs.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Icon(
                                  Icons.all_inclusive,
                                  size: 16,
                                  color: cs.primary,
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                'All Shops',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                        // Individual shops
                        ...shops.map((shop) => DropdownMenuItem<String?>(
                              value: shop.id,
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.outlineVariant,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Icon(
                                      Icons.store,
                                      size: 16,
                                      color: Theme.of(context).colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      shop.name,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                ],
                              ),
                            )),
                      ],
                      onChanged: (value) {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _selectedShopId = value;
                        });
                        _loadData();
                      },
                    ),
                  ),
                ),
              ),
              // Selected shop indicator
              if (_selectedShopId != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _selectedShopId = null;
                    });
                    _loadData();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.clear,
                      size: 18,
                      color: cs.primary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ==================== APPROVALS TAB ====================

  Widget _buildApprovalsTab() {
    return Consumer<StockPurchaseProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading && provider.pendingApprovals.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (provider.pendingApprovals.isEmpty) {
          return _buildEmptyState(
            icon: Icons.check_circle_outline,
            title: 'No Pending Approvals',
            subtitle: 'All stock purchases have been reviewed',
            color: AppColors.success,
          );
        }

        return RefreshIndicator(
          onRefresh: _loadData,
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: provider.pendingApprovals.length,
            itemBuilder: (context, index) {
              return _buildApprovalCard(provider.pendingApprovals[index]);
            },
          ),
        );
      },
    );
  }

  Widget _buildApprovalCard(StockPurchase purchase) {
    final cs = Theme.of(context).colorScheme;
    final authProvider = context.read<AuthProvider>();
    final userRole = (authProvider.currentUser?.role ?? '').toLowerCase();
    final canApprove = purchase.canBeApprovedBy(userRole);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header - Industrial Design with Date/Time & Creator
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              children: [
                // Top Row: Vendor, Shop, Status
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.pending_actions, color: AppColors.warning, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            purchase.vendorName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          RichText(
                            text: TextSpan(
                              style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                              children: [
                                const TextSpan(text: 'Shop: '),
                                TextSpan(
                                  text: purchase.shopName,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.warning,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'PENDING',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Bottom Row: Created By & Date/Time
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.person_outline, size: 16, color: AppColors.warning),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          purchase.createdByName.isNotEmpty
                              ? '${purchase.createdByName} (${purchase.createdByRole})'
                              : 'Created by ${purchase.createdByRole.isNotEmpty ? purchase.createdByRole : "User"}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 20,
                        color: AppColors.warning.withValues(alpha: 0.3),
                        margin: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      Icon(Icons.access_time, size: 14, color: AppColors.warning),
                      const SizedBox(width: 6),
                      Text(
                        DateTimeHelper.formatIST(purchase.createdAt),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Summary Card - Same style as "Add New Stock"
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  _buildSummaryItemWithIcon('Items', '${purchase.items.length}', Icons.inventory_2),
                  Container(width: 1, height: 40, color: cs.primary.withValues(alpha: 0.2)),
                  _buildSummaryItemWithIcon('Total Qty', '${purchase.totalItemCount}', Icons.numbers),
                  Container(width: 1, height: 40, color: cs.primary.withValues(alpha: 0.2)),
                  _buildSummaryItemWithIcon('Amount', purchase.formattedTotal, Icons.currency_rupee),
                ],
              ),
            ),
          ),

          // Items Table - Same style as "Add New Stock"
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Items',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      // Table Header
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                        ),
                        child: Row(
                          children: [
                            Expanded(flex: 3, child: Text('Product', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant))),
                            Expanded(flex: 1, child: Text('Size', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant))),
                            Expanded(flex: 1, child: Center(child: Text('Qty', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)))),
                            Expanded(flex: 1, child: Text('Total', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant), textAlign: TextAlign.right)),
                          ],
                        ),
                      ),
                      // Table Rows
                      ...purchase.items.map((item) => _buildTableRow(item)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Price Breakdown - Same style as "Add New Stock"
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _buildPriceRow('Subtotal', purchase.subtotal),
                  const SizedBox(height: 4),
                  _buildPriceRow('TDS (1%)', purchase.tdsAmount),
                  const SizedBox(height: 4),
                  _buildPriceRow('Round Off', purchase.roundOff, isRoundOff: true),
                  const Divider(height: 16),
                  _buildPriceRow('Total Amount', purchase.totalAmount, isBold: true),
                ],
              ),
            ),
          ),

          // Receipt Information (if available)
          if (purchase.receiptImageUrl != null || purchase.receiptNumber != null)
            _buildReceiptInfoSection(purchase),

          const SizedBox(height: 16),

          // Action Buttons - Matching style
          if (canApprove)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: () => _showRejectDialog(purchase),
                        icon: Icon(Icons.close, color: AppColors.error, size: 18),
                        label: Text('Reject', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: AppColors.error, width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: () => _showApproveDialog(purchase),
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Approve', style: TextStyle(fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: AppColors.warning, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Only Assistant Manager or above can approve',
                      style: TextStyle(color: AppColors.warning, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ==================== HISTORY TAB ====================

  Widget _buildHistoryTab() {
    return Column(
      children: [
        // Filter Chips
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Theme.of(context).colorScheme.surface,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip(null, 'All', Icons.list),
                const SizedBox(width: 8),
                _buildFilterChip(StockPurchaseStatus.approved, 'Approved', Icons.check_circle),
                const SizedBox(width: 8),
                _buildFilterChip(StockPurchaseStatus.pending, 'Pending', Icons.pending),
                const SizedBox(width: 8),
                _buildFilterChip(StockPurchaseStatus.rejected, 'Rejected', Icons.cancel),
              ],
            ),
          ),
        ),

        // History List
        Expanded(
          child: Consumer<StockPurchaseProvider>(
            builder: (context, provider, child) {
              if (provider.isLoading && provider.purchaseHistory.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }

              final filteredHistory = _selectedStatus == null
                  ? provider.purchaseHistory
                  : provider.purchaseHistory.where((p) => p.status == _selectedStatus).toList();

              if (filteredHistory.isEmpty) {
                return _buildEmptyState(
                  icon: Icons.history,
                  title: 'No Purchases Found',
                  subtitle: _selectedStatus == null
                      ? 'No stock purchases yet'
                      : 'No ${_selectedStatus!.displayName.toLowerCase()} purchases',
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                );
              }

              return RefreshIndicator(
                onRefresh: _loadData,
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: filteredHistory.length + (provider.hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= filteredHistory.length) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    return _buildHistoryCard(filteredHistory[index]);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(StockPurchaseStatus? status, String label, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = _selectedStatus == status;
    return FilterChip(
      avatar: Icon(
        icon,
        size: 16,
        color: isSelected ? cs.primary : cs.onSurfaceVariant,
      ),
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        HapticFeedback.selectionClick();
        setState(() {
          _selectedStatus = selected ? status : null;
        });
      },
      selectedColor: cs.primary.withValues(alpha: 0.15),
      checkmarkColor: cs.primary,
      labelStyle: TextStyle(
        color: isSelected ? cs.primary : cs.onSurface,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected ? cs.primary : cs.outlineVariant,
        ),
      ),
    );
  }

  Widget _buildHistoryCard(StockPurchase purchase) {
    final cs = Theme.of(context).colorScheme;
    final statusColor = _getStatusColor(purchase.status);
    final authProvider = context.read<AuthProvider>();
    final userRole = (authProvider.currentUser?.role ?? '').toLowerCase();
    final canApprove = purchase.status.isPending && purchase.canBeApprovedBy(userRole);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04), // KEEP: shadow with opacity
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Tappable content
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _showPurchaseDetails(purchase),
              borderRadius: BorderRadius.vertical(
                top: const Radius.circular(16),
                bottom: canApprove ? Radius.zero : const Radius.circular(16),
              ),
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.08),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(_getStatusIcon(purchase.status), color: statusColor, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                purchase.vendorName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              RichText(
                                text: TextSpan(
                                  style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  children: [
                                    const TextSpan(text: 'Shop: '),
                                    TextSpan(
                                      text: purchase.shopName,
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: statusColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            purchase.status.displayName.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Content
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        // Summary Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildInfoChip(Icons.inventory_2_outlined, '${purchase.items.length} items'),
                            _buildInfoChip(Icons.numbers, '${purchase.totalItemCount} qty'),
                            // Receipt Badge
                            if (purchase.receiptImageUrl != null || purchase.receiptNumber != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.info.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.receipt, size: 12, color: AppColors.info),
                                    const SizedBox(width: 3),
                                    Text(
                                      'Receipt',
                                      style: TextStyle(fontSize: 10, color: AppColors.info, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                            Text(
                              purchase.formattedTotal,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: cs.primary,
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        // Audit Row - Created By + Date
                        Row(
                          children: [
                            Icon(Icons.person, size: 14, color: AppColors.info),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                purchase.createdByName.isNotEmpty
                                    ? '${purchase.createdByName} (${purchase.createdByRole})'
                                    : 'Created by ${purchase.createdByRole.isNotEmpty ? purchase.createdByRole : "User"}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(Icons.schedule, size: 14, color: AppColors.warning),
                            const SizedBox(width: 4),
                            Text(
                              DateTimeHelper.formatIST(purchase.createdAt),
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.chevron_right, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Action Buttons for Pending items
          if (canApprove)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: OutlinedButton.icon(
                        onPressed: () => _showRejectDialog(purchase),
                        icon: Icon(Icons.close, color: AppColors.error, size: 16),
                        label: Text('Reject', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: AppColors.error, width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: ElevatedButton.icon(
                        onPressed: () => _showApproveDialog(purchase),
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('Approve', style: TextStyle(fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
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

  Widget _buildInfoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Color _getStatusColor(StockPurchaseStatus status) {
    switch (status) {
      case StockPurchaseStatus.approved:
        return AppColors.success;
      case StockPurchaseStatus.pending:
        return AppColors.warning;
      case StockPurchaseStatus.rejected:
        return AppColors.error;
      case StockPurchaseStatus.cancelled:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  IconData _getStatusIcon(StockPurchaseStatus status) {
    switch (status) {
      case StockPurchaseStatus.approved:
        return Icons.check_circle;
      case StockPurchaseStatus.pending:
        return Icons.pending;
      case StockPurchaseStatus.rejected:
        return Icons.cancel;
      case StockPurchaseStatus.cancelled:
        return Icons.block;
    }
  }

  // ==================== SHARED WIDGETS ====================

  Widget _buildSummaryItemWithIcon(String label, String value, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: cs.primary, size: 18),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          Text(
            label,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildTableRow(StockPurchaseItem item) {
    // Remove size from product name to avoid duplicacy (e.g., "GOD FATHER - 500ML" → "GOD FATHER")
    String displayName = item.productName;
    if (item.size.isNotEmpty) {
      // Remove patterns like " - 500ML", " - 500ml", "- 500ML" from end
      final sizePattern = RegExp(r'\s*[-–]\s*' + RegExp.escape(item.size) + r'$', caseSensitive: false);
      displayName = displayName.replaceAll(sizePattern, '').trim();
      // Also try without dash: "Product 500ML" → "Product"
      final sizeOnlyPattern = RegExp(r'\s+' + RegExp.escape(item.size) + r'$', caseSensitive: false);
      displayName = displayName.replaceAll(sizeOnlyPattern, '').trim();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                // Only show brand name if it's different from product name (avoid duplicacy)
                if (item.brandName != null &&
                    item.brandName!.toLowerCase() != displayName.toLowerCase() &&
                    item.brandName!.toLowerCase() != item.productName.toLowerCase())
                  Text(
                    item.brandName!,
                    style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(item.size, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          Expanded(
            flex: 1,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'x${item.quantity}',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              _currencyFormat.format(item.totalAmount),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceRow(String label, double amount, {bool isBold = false, bool isRoundOff = false}) {
    // Format round-off with sign prefix (e.g., -₹0.05 or +₹0.05)
    String formattedAmount;
    if (isRoundOff) {
      final sign = amount >= 0 ? '+' : '';
      formattedAmount = '$sign${_currencyFormat.format(amount)}';
    } else {
      formattedAmount = _currencyFormat.format(amount);
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            fontSize: isBold ? 14 : 12,
            color: isBold ? Theme.of(context).colorScheme.onSurface : (isRoundOff ? Theme.of(context).colorScheme.onSurfaceVariant : Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        Text(
          formattedAmount,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            fontSize: isBold ? 14 : 12,
            color: isBold ? Theme.of(context).colorScheme.primary : (isRoundOff ? Theme.of(context).colorScheme.onSurfaceVariant : Theme.of(context).colorScheme.onSurface),
          ),
        ),
      ],
    );
  }

  // ========== RECEIPT DISPLAY HELPERS ==========

  /// Build receipt info section for approval cards
  Widget _buildReceiptInfoSection(StockPurchase purchase) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.info.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.info.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.receipt_long, size: 18, color: AppColors.info),
                const SizedBox(width: 8),
                Text(
                  'Receipt Attached',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.info,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Receipt Image Thumbnail
                if (purchase.receiptImageUrl != null)
                  GestureDetector(
                    onTap: () => _showReceiptImage(purchase.receiptImageUrl!),
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: Image.network(
                          purchase.receiptImageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stack) => Container(
                            color: Theme.of(context).colorScheme.outlineVariant,
                            child: Icon(Icons.image_not_supported, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 24),
                          ),
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  value: progress.expectedTotalBytes != null
                                      ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                                      : null,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                if (purchase.receiptImageUrl != null) const SizedBox(width: 12),
                // Receipt Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (purchase.receiptNumber != null)
                        Row(
                          children: [
                            Icon(Icons.tag, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                purchase.receiptNumber!,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      if (purchase.receiptDate != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.calendar_today, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                            const SizedBox(width: 6),
                            Text(
                              DateTimeHelper.formatISTDate(purchase.receiptDate!),
                              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface),
                            ),
                          ],
                        ),
                      ],
                      if (purchase.receiptImageUrl != null) ...[
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: () => _showReceiptImage(purchase.receiptImageUrl!),
                          child: Text(
                            'Tap image to view full size',
                            style: TextStyle(fontSize: 10, color: AppColors.info, fontStyle: FontStyle.italic),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Show receipt image in full-screen dialog
  void _showReceiptImage(String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            // Zoomable Image
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Center(
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stack) => Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.broken_image, color: Colors.white54, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        'Failed to load image',
                        style: TextStyle(color: Colors.white54),
                      ),
                    ],
                  ),
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Center(
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        value: progress.expectedTotalBytes != null
                            ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                            : null,
                      ),
                    );
                  },
                ),
              ),
            ),
            // Close Button
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 20),
                ),
              ),
            ),
            // Title
            Positioned(
              top: 16,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Purchase Receipt',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build receipt detail card for detail bottom sheet
  Widget _buildReceiptDetailCard(StockPurchase purchase) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Receipt Image (if available)
          if (purchase.receiptImageUrl != null) ...[
            GestureDetector(
              onTap: () => _showReceiptImage(purchase.receiptImageUrl!),
              child: Container(
                height: 120,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        purchase.receiptImageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stack) => Container(
                          color: Theme.of(context).colorScheme.outlineVariant,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.broken_image, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 32),
                              const SizedBox(height: 4),
                              Text('Failed to load', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 10)),
                            ],
                          ),
                        ),
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return Container(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            child: Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                value: progress.expectedTotalBytes != null
                                    ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                                    : null,
                              ),
                            ),
                          );
                        },
                      ),
                      // Tap to view indicator
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.zoom_in, size: 12, color: Colors.white),
                              SizedBox(width: 4),
                              Text('Tap to view', style: TextStyle(fontSize: 10, color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Receipt Details
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Receipt Number
                    if (purchase.receiptNumber != null && purchase.receiptNumber!.isNotEmpty) ...[
                      Row(
                        children: [
                          Icon(Icons.receipt_long, size: 16, color: AppColors.info),
                          const SizedBox(width: 8),
                          Text(
                            'Invoice Number',
                            style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.only(left: 24),
                        child: Text(
                          purchase.receiptNumber!,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Receipt Date
                    if (purchase.receiptDate != null) ...[
                      Row(
                        children: [
                          Icon(Icons.calendar_today, size: 16, color: AppColors.info),
                          const SizedBox(width: 8),
                          Text(
                            'Receipt Date',
                            style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.only(left: 24),
                        child: Text(
                          DateTimeHelper.formatIST(purchase.receiptDate!),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          // Receipt Notes
          if (purchase.receiptNotes != null && purchase.receiptNotes!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.notes, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      purchase.receiptNotes!,
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 48, color: color),
          ),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(subtitle, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Refresh'),
            style: ElevatedButton.styleFrom(
              backgroundColor: cs.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== DIALOGS ====================

  void _showApproveDialog(StockPurchase purchase) {
    // Capture screen context before showing dialog to avoid disposal issues
    final screenContext = context;
    final provider = context.read<StockPurchaseProvider>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.check_circle, color: AppColors.success),
            ),
            const SizedBox(width: 12),
            const Text('Approve Purchase'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Approve this purchase from ${purchase.vendorName}?'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  _buildDialogInfoRow('Amount', purchase.formattedTotal),
                  _buildDialogInfoRow('Items', '${purchase.items.length}'),
                  _buildDialogInfoRow('Qty', '${purchase.totalItemCount}'),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Cancel', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              final success = await provider.approvePurchase(purchase.id);
              // Use screen context and mounted check to avoid disposal error
              if (mounted) {
                HapticFeedback.mediumImpact();
                ScaffoldMessenger.of(screenContext).showSnackBar(
                  SnackBar(
                    content: Text(success ? 'Purchase approved - Stock updated!' : 'Failed to approve'),
                    backgroundColor: success ? AppColors.success : AppColors.error,
                  ),
                );
                if (success) _loadData();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
  }

  void _showRejectDialog(StockPurchase purchase) {
    // Capture screen context before showing dialog to avoid disposal issues
    final screenContext = context;
    final provider = context.read<StockPurchaseProvider>();
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.cancel, color: AppColors.error),
            ),
            const SizedBox(width: 12),
            const Text('Reject Purchase'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reject this purchase from ${purchase.vendorName}?'),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                labelText: 'Reason for rejection *',
                hintText: 'Enter reason...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Cancel', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (reasonController.text.trim().isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Please provide a reason'),
                    backgroundColor: AppColors.warning,
                  ),
                );
                return;
              }
              Navigator.pop(dialogContext);
              final success = await provider.rejectPurchase(
                    purchase.id,
                    reasonController.text.trim(),
                  );
              // Use screen context and mounted check to avoid disposal error
              if (mounted) {
                HapticFeedback.mediumImpact();
                ScaffoldMessenger.of(screenContext).showSnackBar(
                  SnackBar(
                    content: Text(success ? 'Purchase rejected' : 'Failed to reject'),
                    backgroundColor: success ? AppColors.warning : AppColors.error,
                  ),
                );
                if (success) _loadData();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }

  void _showPurchaseDetails(StockPurchase purchase) {
    final statusColor = _getStatusColor(purchase.status);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Drag Handle
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header - Same as "Add New Stock"
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(_getStatusIcon(purchase.status), color: statusColor, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            purchase.vendorName,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Shop: ${purchase.shopName}',
                            style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: statusColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        purchase.status.displayName.toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
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
                    // Summary Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          _buildSummaryItemWithIcon('Items', '${purchase.items.length}', Icons.inventory_2),
                          Container(width: 1, height: 40, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)),
                          _buildSummaryItemWithIcon('Total Qty', '${purchase.totalItemCount}', Icons.numbers),
                          Container(width: 1, height: 40, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)),
                          _buildSummaryItemWithIcon('Amount', purchase.formattedTotal, Icons.currency_rupee),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Items Table
                    const Text('Items', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                            ),
                            child: Row(
                              children: [
                                Expanded(flex: 3, child: Text('Product', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant))),
                                Expanded(flex: 1, child: Text('Size', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant))),
                                Expanded(flex: 1, child: Center(child: Text('Qty', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)))),
                                Expanded(flex: 1, child: Text('Total', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant), textAlign: TextAlign.right)),
                              ],
                            ),
                          ),
                          ...purchase.items.map((item) => _buildTableRow(item)),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Price Breakdown
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          _buildPriceRow('Subtotal', purchase.subtotal),
                          const SizedBox(height: 8),
                          _buildPriceRow('TDS (1%)', purchase.tdsAmount),
                          const SizedBox(height: 8),
                          _buildPriceRow('Round Off', purchase.roundOff, isRoundOff: true),
                          const Divider(height: 20),
                          _buildPriceRow('Total Amount', purchase.totalAmount, isBold: true),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Audit Trail
                    const Text('Audit Trail', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _buildAuditRow(
                      Icons.person,
                      'Created by',
                      purchase.createdByName.isNotEmpty
                          ? '${purchase.createdByName} (${purchase.createdByRole})'
                          : purchase.createdByRole.isNotEmpty
                              ? purchase.createdByRole
                              : 'User',
                      DateTimeHelper.formatIST(purchase.createdAt),
                    ),
                    if (purchase.approvedByName != null && purchase.approvedAt != null)
                      _buildAuditRow(Icons.check_circle, 'Approved by', purchase.approvedByName!, DateTimeHelper.formatIST(purchase.approvedAt!)),
                    if (purchase.rejectionReason != null)
                      _buildAuditRow(Icons.cancel, 'Rejected', purchase.rejectionReason!, purchase.rejectedAt != null ? DateTimeHelper.formatIST(purchase.rejectedAt!) : ''),

                    // Receipt Section (if available)
                    if (purchase.receiptImageUrl != null || purchase.receiptNumber != null) ...[
                      const SizedBox(height: 20),
                      const Text('Receipt', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      _buildReceiptDetailCard(purchase),
                    ],

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAuditRow(IconData icon, String label, String value, String timestamp) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.info),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11)),
                Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                if (timestamp.isNotEmpty)
                  Text(timestamp, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
