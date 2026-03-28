import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../providers/sales_provider.dart';
import '../models/sale.dart';
import 'modern_invoice_screen.dart';

/// Modern Sales History Screen with iOS-style UI
class SalesHistoryModern extends StatefulWidget {
  const SalesHistoryModern({super.key});

  @override
  State<SalesHistoryModern> createState() => _SalesHistoryModernState();
}

class _SalesHistoryModernState extends State<SalesHistoryModern>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _searchController = TextEditingController();
  late TabController _tabController;
  final _scrollController = ScrollController();
  bool _isInitialLoad = true;

  // Filters
  SaleFilter _currentFilter = SaleFilter.all;
  DateRange? _selectedDateRange;
  final bool _showFilterSheet = false;

  @override
  void initState() {
    super.initState();
    // Add app lifecycle observer for app resume detection
    WidgetsBinding.instance.addObserver(this);

    _tabController = TabController(length: 5, vsync: this);
    _scrollController.addListener(_onScroll);
    _loadSales();
    _isInitialLoad = false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Auto-refresh when screen becomes visible (after navigation back)
    if (!_isInitialLoad && mounted) {
      _loadSales();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Auto-refresh when app resumes from background
    if (state == AppLifecycleState.resumed && mounted) {
      _loadSales();
    }
  }

  void _loadSales() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SalesProvider>().fetchSales(refresh: true);
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      context.read<SalesProvider>().fetchSales();
    }
  }

  @override
  void dispose() {
    // Remove app lifecycle observer
    WidgetsBinding.instance.removeObserver(this);

    _searchController.dispose();
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          // App Bar
          _buildSliverAppBar(),

          // Search Bar
          SliverToBoxAdapter(
            child: _buildSearchBar(),
          ),

          // Filter Tabs
          SliverPersistentHeader(
            pinned: true,
            delegate: _FilterTabsDelegate(
              tabController: _tabController,
              onTabChanged: (filter) {
                setState(() => _currentFilter = filter);
                context.read<SalesProvider>().filterByStatus(filter);
                HapticFeedback.lightImpact();
              },
            ),
          ),
        ],
        body: Consumer<SalesProvider>(
          builder: (context, provider, _) {
            if (provider.isLoading && provider.sales.isEmpty) {
              return _buildLoadingState();
            }

            if (provider.sales.isEmpty) {
              return _buildEmptyState();
            }

            return RefreshIndicator(
              onRefresh: () => provider.fetchSales(refresh: true),
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: provider.sales.length + (provider.isLoading ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == provider.sales.length) {
                    return _buildLoadingIndicator();
                  }

                  final sale = provider.sales[index];
                  return _buildSaleCard(sale, index);
                },
              ),
            );
          },
        ),
      ),

      // Filter FAB
      floatingActionButton: _buildFilterFAB(),
    );
  }

  Widget _buildSliverAppBar() {
    final cs = Theme.of(context).colorScheme;
    return SliverAppBar(
      expandedHeight: 140,
      floating: true,
      pinned: true,
      backgroundColor: cs.surface,
      elevation: 0,
      leading: IconButton(
        icon: Icon(CupertinoIcons.arrow_left, color: cs.onSurface),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            color: cs.surface,
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Text(
                    'Sales History',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Consumer<SalesProvider>(
                    builder: (context, provider, _) {
                      return Text(
                        '${provider.sales.length} transactions',
                        style: TextStyle(
                          fontSize: 16,
                          color: cs.onSurfaceVariant,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        IconButton(
          icon: Icon(CupertinoIcons.calendar, color: cs.onSurface),
          onPressed: _selectDateRange,
        ),
        IconButton(
          icon: Icon(CupertinoIcons.arrow_down_doc, color: cs.onSurface),
          onPressed: _exportSales,
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.all(16),
      height: 48,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search by invoice, customer, or amount...',
          hintStyle: TextStyle(color: cs.onSurfaceVariant),
          prefixIcon: Icon(
            CupertinoIcons.search,
            color: cs.onSurfaceVariant,
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(CupertinoIcons.clear_circled_solid),
                  onPressed: () {
                    _searchController.clear();
                    context.read<SalesProvider>().searchSales('');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 14,
          ),
        ),
        onChanged: (value) {
          context.read<SalesProvider>().searchSales(value);
        },
      ),
    );
  }

  Widget _buildSaleCard(Sale sale, int index) {
    final cs = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 300 + (index * 50)),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: Opacity(
            opacity: value,
            child: child,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _viewInvoice(sale),
            onLongPress: () => _showSaleOptions(sale),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Header Row
                  Row(
                    children: [
                      // Status Icon
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: _getStatusColor(sale.status).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _getStatusIcon(sale.status),
                          color: _getStatusColor(sale.status),
                        ),
                      ),
                      const SizedBox(width: 16),

                      // Sale Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '#${sale.saleNumber}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _getPaymentColor(sale.paymentMethod),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    sale.paymentMethod.toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              sale.customerName ?? 'Walk-in Customer',
                              style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Amount & Time
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            Formatters.currency(sale.totalAmount),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: cs.primary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            Formatters.smartTimestamp(sale.createdAt),
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  // Items Preview
                  if (sale.items != null && sale.items!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            CupertinoIcons.cube_box,
                            size: 16,
                            color: cs.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${sale.items!.length} items',
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 13,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            sale.items!.take(2).map((i) => i.productName).join(', '),
                            style: TextStyle(
                              color: cs.onSurface,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Outstanding Amount
                  if (sale.hasOutstanding) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            CupertinoIcons.exclamationmark_circle_fill,
                            size: 16,
                            color: AppColors.warning,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Outstanding: ${Formatters.currency(sale.dueAmount)}',
                            style: const TextStyle(
                              color: AppColors.warning,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Shimmer.fromColors(
            baseColor: Colors.grey[300]!,
            highlightColor: Colors.grey[100]!,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 120,
                            height: 16,
                            color: Colors.white,
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: 80,
                            height: 14,
                            color: Colors.white,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 80,
                      height: 20,
                      color: Colors.white,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            CupertinoIcons.doc_text,
            size: 80,
            color: cs.outlineVariant,
          ),
          const SizedBox(height: 24),
          Text(
            'No sales found',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try adjusting your filters or search',
            style: TextStyle(
              fontSize: 16,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () {
              context.read<SalesProvider>().filterByStatus(SaleFilter.all);
              _searchController.clear();
            },
            icon: const Icon(CupertinoIcons.arrow_clockwise),
            label: const Text('Reset Filters'),
            style: ElevatedButton.styleFrom(
              backgroundColor: cs.primary,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: CupertinoActivityIndicator(),
      ),
    );
  }

  Widget _buildFilterFAB() {
    final cs = Theme.of(context).colorScheme;
    return FloatingActionButton(
      onPressed: () {
        HapticFeedback.mediumImpact();
        _showFilterBottomSheet();
      },
      backgroundColor: cs.primary,
      child: const Icon(CupertinoIcons.line_horizontal_3_decrease),
    );
  }

  void _showFilterBottomSheet() {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle
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
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const Text(
                    'Filters',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      // Reset filters
                      Navigator.pop(context);
                    },
                    child: const Text('Reset'),
                  ),
                ],
              ),
            ),

            // Filter Options
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // Date Range
                  _buildFilterSection(
                    'Date Range',
                    CupertinoIcons.calendar,
                    Column(
                      children: [
                        _buildDateOption('Today'),
                        _buildDateOption('Yesterday'),
                        _buildDateOption('This Week'),
                        _buildDateOption('This Month'),
                        _buildDateOption('Custom Range'),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Payment Method
                  _buildFilterSection(
                    'Payment Method',
                    CupertinoIcons.creditcard,
                    Wrap(
                      spacing: 8,
                      children: [
                        _buildChip('Cash'),
                        _buildChip('Card'),
                        _buildChip('UPI'),
                        _buildChip('Credit'),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Amount Range
                  _buildFilterSection(
                    'Amount Range',
                    CupertinoIcons.money_dollar,
                    Column(
                      children: [
                        _buildAmountSlider(),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Apply Button
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cs.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _applyFilters();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: cs.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Apply Filters',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterSection(String title, IconData icon, Widget content) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: cs.primary),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        content,
      ],
    );
  }

  Widget _buildDateOption(String label) {
    return ListTile(
      title: Text(label),
      trailing: const Icon(CupertinoIcons.chevron_right, size: 16),
      onTap: () {
        // Handle date selection
      },
    );
  }

  Widget _buildChip(String label) {
    return FilterChip(
      label: Text(label),
      selected: false,
      onSelected: (selected) {
        // Handle selection
      },
    );
  }

  Widget _buildAmountSlider() {
    return RangeSlider(
      values: const RangeValues(0, 10000),
      max: 50000,
      divisions: 100,
      labels: const RangeLabels('₹0', '₹10,000'),
      onChanged: (values) {
        // Handle range change
      },
    );
  }

  void _viewInvoice(Sale sale) {
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => ModernInvoiceScreen(sale: sale),
      ),
    );
  }

  void _showSaleOptions(Sale sale) {
    HapticFeedback.mediumImpact();
    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text('Invoice #${sale.saleNumber}'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _viewInvoice(sale);
            },
            child: const Text('View Invoice'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              // Share invoice
            },
            child: const Text('Share'),
          ),
          if (sale.isPending)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(context);
                // Approve sale
              },
              child: const Text('Approve'),
            ),
          if (sale.isApproved)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(context);
                // Process return
              },
              isDestructiveAction: true,
              child: const Text('Return'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _selectDateRange() async {
    HapticFeedback.lightImpact();
    // Implement date range picker
  }

  void _exportSales() {
    HapticFeedback.lightImpact();
    // Implement export functionality
  }

  void _applyFilters() {
    // Apply selected filters
    HapticFeedback.mediumImpact();
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'approved':
        return AppColors.success;
      case 'pending':
        return AppColors.warning;
      case 'rejected':
        return AppColors.error;
      case 'returned':
        return AppColors.info;
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'approved':
        return CupertinoIcons.checkmark_circle_fill;
      case 'pending':
        return CupertinoIcons.clock_fill;
      case 'rejected':
        return CupertinoIcons.xmark_circle_fill;
      case 'returned':
        return CupertinoIcons.arrow_turn_up_left;
      default:
        return CupertinoIcons.circle;
    }
  }

  Color _getPaymentColor(String method) {
    switch (method.toLowerCase()) {
      case 'cash':
        return Colors.green;
      case 'card':
        return Colors.blue;
      case 'upi':
        return Colors.purple;
      case 'credit':
        return Colors.orange;
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }
}

// Custom Delegate for Filter Tabs
class _FilterTabsDelegate extends SliverPersistentHeaderDelegate {
  final TabController tabController;
  final Function(SaleFilter) onTabChanged;

  _FilterTabsDelegate({
    required this.tabController,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surface,
      child: TabBar(
        controller: tabController,
        isScrollable: true,
        labelColor: cs.primary,
        unselectedLabelColor: cs.onSurfaceVariant,
        indicatorColor: cs.primary,
        indicatorWeight: 3,
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
        tabs: const [
          Tab(text: 'All'),
          Tab(text: 'Pending'),
          Tab(text: 'Approved'),
          Tab(text: 'Rejected'),
          Tab(text: 'Unpaid'),
        ],
        onTap: (index) {
          final filters = [
            SaleFilter.all,
            SaleFilter.pending,
            SaleFilter.approved,
            SaleFilter.rejected,
            SaleFilter.unpaid,
          ];
          onTabChanged(filters[index]);
        },
      ),
    );
  }

  @override
  double get maxExtent => 50;

  @override
  double get minExtent => 50;

  @override
  bool shouldRebuild(_FilterTabsDelegate oldDelegate) => false;
}