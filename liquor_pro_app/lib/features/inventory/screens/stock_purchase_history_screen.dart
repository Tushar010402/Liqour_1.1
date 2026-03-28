// Stock Purchase History Screen - Complete Audit Trail
//
// Shows all stock purchase history with complete audit information.
// Follows best practices from modern platforms like Swiggy/Zomato.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/providers/shop_selection_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/stock_purchase_provider.dart';
import '../models/stock_purchase.dart';

class StockPurchaseHistoryScreen extends StatefulWidget {
  /// Optional shopId to pre-filter purchases by shop (passed from Dashboard)
  final String? shopId;

  const StockPurchaseHistoryScreen({super.key, this.shopId});

  @override
  State<StockPurchaseHistoryScreen> createState() =>
      _StockPurchaseHistoryScreenState();
}

class _StockPurchaseHistoryScreenState
    extends State<StockPurchaseHistoryScreen> {
  final _currencyFormat =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
  final _dateFormat = DateFormat('dd MMM yyyy, hh:mm a');
  final _scrollController = ScrollController();

  // Filter state
  StockPurchaseStatus? _selectedStatus;

  /// Selected shop ID for filtering - initialized from Dashboard selection
  String? _selectedShopId;

  @override
  void initState() {
    super.initState();
    // Initialize shop filter from parameter (passed from Dashboard)
    _selectedShopId = widget.shopId;
    _scrollController.addListener(_onScroll);
    // Defer loading to after the build phase completes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadHistory();
    });
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

  Future<void> _loadHistory() async {
    // Use local state if set, otherwise fall back to global provider
    final shopId = _selectedShopId ?? context.read<ShopSelectionProvider>().selectedShopId;
    await context.read<StockPurchaseProvider>().loadPurchaseHistory(
          shopId: shopId,
          status: _selectedStatus,
          refresh: true,
        );
  }

  Future<void> _loadMore() async {
    // Use local state if set, otherwise fall back to global provider
    final shopId = _selectedShopId ?? context.read<ShopSelectionProvider>().selectedShopId;
    await context.read<StockPurchaseProvider>().loadMoreHistory(
          shopId: shopId,
          status: _selectedStatus,
        );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surfaceContainerHighest,
      appBar: AppBar(
        title: const Text('Purchase History'),
        centerTitle: true,
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterSheet,
            tooltip: 'Filter',
          ),
        ],
      ),
      body: Column(
        children: [
          // Shop Filter Chips (matching Dashboard design)
          _buildShopFilterChips(),

          // Status Filter Chips
          _buildFilterChips(),

          // History List
          Expanded(
            child: Consumer<StockPurchaseProvider>(
              builder: (context, provider, child) {
                if (provider.isLoading && provider.purchaseHistory.isEmpty) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                if (provider.purchaseHistory.isEmpty) {
                  return _buildEmptyState();
                }

                return RefreshIndicator(
                  onRefresh: _loadHistory,
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: provider.purchaseHistory.length +
                        (provider.hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == provider.purchaseHistory.length) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }
                      final purchase = provider.purchaseHistory[index];
                      return _buildHistoryCard(purchase);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: cs.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildFilterChip(null, 'All'),
            const SizedBox(width: 8),
            _buildFilterChip(StockPurchaseStatus.approved, 'Approved'),
            const SizedBox(width: 8),
            _buildFilterChip(StockPurchaseStatus.pending, 'Pending'),
            const SizedBox(width: 8),
            _buildFilterChip(StockPurchaseStatus.rejected, 'Rejected'),
            const SizedBox(width: 8),
            _buildFilterChip(StockPurchaseStatus.cancelled, 'Cancelled'),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(StockPurchaseStatus? status, String label) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = _selectedStatus == status;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedStatus = selected ? status : null;
        });
        _loadHistory();
      },
      selectedColor: cs.primary.withValues(alpha: 0.2),
      checkmarkColor: cs.primary,
      labelStyle: TextStyle(
        color: isSelected ? cs.primary : cs.onSurface,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }

  Widget _buildEmptyState() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.history,
              size: 64,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No Purchase History',
            style: AppTextStyles.h3.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _selectedStatus != null
                ? 'No ${_selectedStatus!.displayName.toLowerCase()} purchases found'
                : 'No stock purchases have been made yet',
            style: AppTextStyles.bodyMedium.copyWith(
              color: cs.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _loadHistory,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(StockPurchase purchase) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: 1,
      child: InkWell(
        onTap: () => _showPurchaseDetails(purchase),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                children: [
                  _buildStatusBadge(purchase.status),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          purchase.vendorName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          purchase.shopName,
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        purchase.formattedTotal,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: cs.primary,
                        ),
                      ),
                      Text(
                        '${purchase.items.length} items',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // Audit Info
              Row(
                children: [
                  Expanded(
                    child: _buildAuditColumn(
                      'Created By',
                      purchase.createdByName,
                      purchase.createdByRole,
                      _dateFormat.format(purchase.createdAt),
                    ),
                  ),
                  if (purchase.status.isApproved &&
                      purchase.approvedByName != null) ...[
                    Container(
                      width: 1,
                      height: 50,
                      color: cs.outlineVariant,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildAuditColumn(
                        'Approved By',
                        purchase.approvedByName!,
                        purchase.approvedByRole ?? '',
                        purchase.approvedAt != null
                            ? _dateFormat.format(purchase.approvedAt!)
                            : '',
                      ),
                    ),
                  ],
                  if (purchase.status.isRejected) ...[
                    Container(
                      width: 1,
                      height: 50,
                      color: cs.outlineVariant,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Rejection Reason',
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            purchase.rejectionReason ?? 'Not specified',
                            style: TextStyle(
                              color: AppColors.error,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(StockPurchaseStatus status) {
    Color bgColor;
    Color iconColor;
    IconData icon;

    switch (status) {
      case StockPurchaseStatus.pending:
        bgColor = AppColors.warning.withValues(alpha: 0.1);
        iconColor = AppColors.warning;
        icon = Icons.hourglass_empty;
        break;
      case StockPurchaseStatus.approved:
        bgColor = AppColors.success.withValues(alpha: 0.1);
        iconColor = AppColors.success;
        icon = Icons.check_circle;
        break;
      case StockPurchaseStatus.rejected:
        bgColor = AppColors.error.withValues(alpha: 0.1);
        iconColor = AppColors.error;
        icon = Icons.cancel;
        break;
      case StockPurchaseStatus.cancelled:
        final cs = Theme.of(context).colorScheme;
        bgColor = cs.onSurfaceVariant.withValues(alpha: 0.1);
        iconColor = cs.onSurfaceVariant;
        icon = Icons.block;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: iconColor, size: 20),
    );
  }

  Widget _buildAuditColumn(
      String title, String name, String role, String date) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          name,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        Text(
          role,
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
        if (date.isNotEmpty)
          Text(
            date,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 10,
            ),
          ),
      ],
    );
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Filter Purchase History',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),

            // Status filter
            Text(
              'Status',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildFilterOption(null, 'All'),
                _buildFilterOption(StockPurchaseStatus.approved, 'Approved'),
                _buildFilterOption(StockPurchaseStatus.pending, 'Pending'),
                _buildFilterOption(StockPurchaseStatus.rejected, 'Rejected'),
                _buildFilterOption(StockPurchaseStatus.cancelled, 'Cancelled'),
              ],
            ),
            const SizedBox(height: 24),

            // Apply button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _loadHistory();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('Apply Filter'),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterOption(StockPurchaseStatus? status, String label) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = _selectedStatus == status;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedStatus = selected ? status : null;
        });
      },
      selectedColor: cs.primary.withValues(alpha: 0.2),
      labelStyle: TextStyle(
        color: isSelected ? cs.primary : cs.onSurface,
      ),
    );
  }

  /// Build shop filter chips matching Dashboard design
  Widget _buildShopFilterChips() {
    return Consumer<ShopSelectionProvider>(
      builder: (context, shopProvider, _) {
        final shops = shopProvider.shops;

        final cs = Theme.of(context).colorScheme;
        return Container(
          color: cs.surface,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // "All" chip
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: const Text('All'),
                    selected: _selectedShopId == null,
                    onSelected: (_) {
                      setState(() => _selectedShopId = null);
                      _loadHistory();
                    },
                    selectedColor: cs.primary.withValues(alpha: 0.2),
                    checkmarkColor: cs.primary,
                    labelStyle: TextStyle(
                      color: _selectedShopId == null
                          ? cs.primary
                          : cs.onSurface,
                      fontWeight: _selectedShopId == null
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ),
                // Shop chips
                ...shops.map((shop) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(shop.name),
                        selected: _selectedShopId == shop.id,
                        onSelected: (_) {
                          setState(() => _selectedShopId = shop.id);
                          _loadHistory();
                        },
                        selectedColor: cs.primary.withValues(alpha: 0.2),
                        checkmarkColor: cs.primary,
                        labelStyle: TextStyle(
                          color: _selectedShopId == shop.id
                              ? cs.primary
                              : cs.onSurface,
                          fontWeight: _selectedShopId == shop.id
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    )),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showPurchaseDetails(StockPurchase purchase) {
    final authProvider = context.read<AuthProvider>();
    final currentUserId = authProvider.currentUser?.id ?? '';
    final canCancel = purchase.status.isPending &&
        purchase.createdById == currentUserId;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    _buildStatusBadge(purchase.status),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Purchase Details',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            purchase.vendorName,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                      style: IconButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
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
                    // Summary
                    _buildDetailSection('Summary', [
                      _buildDetailRow('Shop', purchase.shopName),
                      _buildDetailRow('Godam', purchase.vendorName),
                      _buildDetailRow(
                          'Items', '${purchase.items.length} products'),
                      _buildDetailRow(
                          'Total Quantity', '${purchase.totalItemCount} units'),
                      _buildDetailRow('Subtotal',
                          _currencyFormat.format(purchase.subtotal)),
                      _buildDetailRow(
                          'TDS (1%)', _currencyFormat.format(purchase.tdsAmount)),
                      // Show round off if not zero
                      if (purchase.roundOff != 0)
                        _buildDetailRow(
                            'Round Off',
                            purchase.roundOff >= 0
                                ? '+${_currencyFormat.format(purchase.roundOff)}'
                                : _currencyFormat.format(purchase.roundOff)),
                      _buildDetailRow('Total Amount', purchase.formattedTotal,
                          isBold: true),
                    ]),

                    // Receipt Information (if available)
                    if (purchase.receiptImageUrl != null &&
                        purchase.receiptImageUrl!.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildReceiptSection(context, purchase),
                    ],

                    const SizedBox(height: 16),

                    // Items
                    _buildDetailSection('Items', [
                      ...purchase.items.map((item) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.productName,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w500),
                                      ),
                                      Text(
                                        item.size,
                                        style: TextStyle(
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    'x${item.quantity}',
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    _currencyFormat.format(item.totalAmount),
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          )),
                    ]),

                    const SizedBox(height: 16),

                    // Audit Trail
                    _buildDetailSection('Audit Trail', [
                      _buildAuditDetailRow(
                        'Created',
                        purchase.createdByName,
                        purchase.createdByRole,
                        purchase.createdAt,
                      ),
                      if (purchase.approvedByName != null)
                        _buildAuditDetailRow(
                          'Approved',
                          purchase.approvedByName!,
                          purchase.approvedByRole ?? '',
                          purchase.approvedAt,
                        ),
                      if (purchase.rejectionReason != null) ...[
                        const Divider(),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.info_outline,
                                color: AppColors.error, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Rejection Reason',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.error,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(purchase.rejectionReason!),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ]),

                    if (purchase.notes != null) ...[
                      const SizedBox(height: 16),
                      _buildDetailSection('Notes', [
                        Text(purchase.notes!),
                      ]),
                    ],

                    // Cancel button for user's own pending purchases
                    if (canCancel) ...[
                      const SizedBox(height: 24),
                      _buildCancelButton(sheetContext, purchase),
                    ],

                    // Extra padding at bottom for safe area
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build cancel button for pending purchases
  Widget _buildCancelButton(BuildContext sheetContext, StockPurchase purchase) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _confirmCancelPurchase(sheetContext, purchase),
        icon: const Icon(Icons.cancel_outlined),
        label: const Text('Cancel This Purchase'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.error,
          side: const BorderSide(color: AppColors.error),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  /// Confirm cancel purchase with dialog
  void _confirmCancelPurchase(BuildContext sheetContext, StockPurchase purchase) {
    HapticFeedback.mediumImpact();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 28),
            const SizedBox(width: 12),
            const Text('Cancel Purchase?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Are you sure you want to cancel this purchase request?',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    purchase.vendorName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${purchase.items.length} items · ${purchase.formattedTotal}',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'This action cannot be undone.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Keep it'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext); // Close dialog
              await _cancelPurchase(sheetContext, purchase);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );
  }

  /// Execute cancel purchase
  Future<void> _cancelPurchase(BuildContext sheetContext, StockPurchase purchase) async {
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    final provider = context.read<StockPurchaseProvider>();
    final success = await provider.cancelPurchase(purchase.id);

    // Hide loading
    if (mounted) Navigator.pop(context);

    if (success) {
      // Close the detail sheet
      if (mounted) Navigator.pop(sheetContext);

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('Purchase cancelled successfully'),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      // Refresh the list
      _loadHistory();
    } else {
      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(provider.errorMessage ?? 'Failed to cancel purchase'),
                ),
              ],
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _buildDetailSection(String title, List<Widget> children) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
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
          Text(
            label,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: isBold ? cs.primary : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuditDetailRow(
      String action, String name, String role, DateTime? timestamp) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.person, size: 16, color: cs.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$action by $name',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                if (role.isNotEmpty)
                  Text(
                    role,
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                  ),
              ],
            ),
          ),
          if (timestamp != null)
            Text(
              _dateFormat.format(timestamp),
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
            ),
        ],
      ),
    );
  }

  /// Build receipt section with thumbnail and receipt details
  Widget _buildReceiptSection(BuildContext context, StockPurchase purchase) {
    return _buildDetailSection('Receipt', [
      // Receipt Number & Date
      if (purchase.receiptNumber != null && purchase.receiptNumber!.isNotEmpty)
        _buildDetailRow('Receipt #', purchase.receiptNumber!),
      if (purchase.receiptDate != null)
        _buildDetailRow('Receipt Date', _dateFormat.format(purchase.receiptDate!)),
      if (purchase.receiptNotes != null && purchase.receiptNotes!.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Notes: ${purchase.receiptNotes}',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),

      // Receipt Image Thumbnail
      const SizedBox(height: 12),
      GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          _showReceiptImage(context, purchase.receiptImageUrl!);
        },
        child: Container(
          height: 120,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: purchase.receiptImageUrl!,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.broken_image, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 32),
                        const SizedBox(height: 4),
                        Text(
                          'Failed to load',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
                // Tap to view overlay
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.6),
                        ],
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.zoom_in, color: Colors.white, size: 16),
                        SizedBox(width: 4),
                        Text(
                          'Tap to view full image',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ]);
  }

  /// Show receipt image in full screen viewer
  void _showReceiptImage(BuildContext context, String imageUrl) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _ReceiptImageViewer(imageUrl: imageUrl),
      ),
    );
  }
}

/// Full screen receipt image viewer
class _ReceiptImageViewer extends StatefulWidget {
  final String imageUrl;

  const _ReceiptImageViewer({required this.imageUrl});

  @override
  State<_ReceiptImageViewer> createState() => _ReceiptImageViewerState();
}

class _ReceiptImageViewerState extends State<_ReceiptImageViewer> {
  final TransformationController _transformationController =
      TransformationController();
  double _currentScale = 1.0;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
    setState(() {
      _currentScale = 1.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Receipt Image'),
        actions: [
          if (_currentScale != 1.0)
            IconButton(
              icon: const Icon(Icons.zoom_out_map),
              onPressed: _resetZoom,
              tooltip: 'Reset zoom',
            ),
        ],
      ),
      body: InteractiveViewer(
        transformationController: _transformationController,
        minScale: 0.5,
        maxScale: 4.0,
        onInteractionEnd: (details) {
          setState(() {
            _currentScale = _transformationController.value.getMaxScaleOnAxis();
          });
        },
        child: Center(
          child: CachedNetworkImage(
            imageUrl: widget.imageUrl,
            fit: BoxFit.contain,
            placeholder: (context, url) => const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            errorWidget: (context, url, error) => Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.broken_image, color: Colors.white54, size: 64),
                const SizedBox(height: 16),
                Text(
                  'Failed to load image',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                  ),
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
