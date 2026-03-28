import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/services/dio_api_service.dart';
import '../../../core/providers/shop_selection_provider.dart';
import '../../../shared/widgets/empty_state_widget.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/sale.dart';
import '../services/sales_service.dart';
import '../widgets/receipt_table_widget.dart';
import 'edit_sale_screen.dart';

/// Sales History Screen with optional shop filter from Dashboard
class SalesHistoryScreen extends StatefulWidget {
  /// Optional shopId to pre-filter sales by shop (passed from Dashboard)
  final String? shopId;

  const SalesHistoryScreen({super.key, this.shopId});

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  bool _isLoading = false;
  List<Map<String, dynamic>> _sales = [];
  String _filterPeriod = 'all';
  bool _isTableView = false;

  // Service and filters
  late SalesService _salesService;
  DateTimeRange? _dateRange;
  String? _selectedStatus;

  /// Selected shop ID for filtering - initialized from Dashboard selection
  String? _selectedShopId;

  @override
  void initState() {
    super.initState();
    // Initialize shop filter from parameter (passed from Dashboard)
    _selectedShopId = widget.shopId;
    _salesService = SalesService(context.read<DioApiService>());
    _loadSales();
  }

  Future<void> _navigateToEditSale(Map<String, dynamic> sale) async {
    try {
      // Navigate to EditSaleScreen (to be created)
      final result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => EditSaleScreen(sale: sale)),
      );

      // If sale was updated, reload the list
      if (result == true) {
        _loadSales();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening edit screen: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _loadSales() async {
    print(
      '🚀 [SalesHistory] _loadSales() called - Loading individual sales...',
    );
    print(
      '🚀 [SalesHistory] This is the SALES HISTORY screen (not daily sales)',
    );
    print('🚀 [SalesHistory] Shop filter: $_selectedShopId');
    setState(() => _isLoading = true);

    try {
      print(
        '🚀 [SalesHistory] Calling getSales API with shopId: $_selectedShopId',
      );
      final response = await _salesService.getSales(
        shopId: _selectedShopId, // Pass selected shop filter
        startDate: _dateRange?.start,
        endDate: _dateRange?.end,
        status: _selectedStatus,
        page: 1,
        limit: 50,
      );

      print(
        '🚀 [SalesHistory] API Response received - Success: ${response.success}',
      );
      if (response.success && response.data != null) {
        print('🚀 [SalesHistory] Got ${response.data!.length} sales from API');

        setState(() {
          // Convert Sale objects to Map for compatibility with existing UI
          _sales = response.data!.map((sale) {
            print('🔍 [SalesHistory] Processing sale: ${sale.id}');
            print('🔍 [SalesHistory] Sale status: ${sale.status}');
            print('🔍 [SalesHistory] Sale salesmanId: ${sale.salesmanId}');

            return {
              'id': sale.id,
              'date': sale.saleDate.toLocal().toString().split(' ')[0] ?? '',
              'shop': sale.shopId,
              'shop_name':
                  'Shop ${sale.shopId}', // TODO: Add shopName to Sale model
              'customer': sale.customerName ?? 'Walk-in',
              'customer_phone': sale.customerPhone,
              'status': sale.status,
              'payment_status': sale.paymentStatus,
              'total': sale.totalAmount,
              'paid': sale.paidAmount,
              'items':
                  sale.items
                      ?.map(
                        (item) => {
                          'product_id': item.productId,
                          'name': item.productName,
                          'quantity': item.quantity,
                          'price': item
                              .unitPrice, // Using unitPrice instead of price
                          'total': item
                              .totalPrice, // Using totalPrice instead of total
                        },
                      )
                      .toList() ??
                  [],
              'salesman_id': sale.salesmanId,
              'created_by_id':
                  sale.salesmanId, // Using salesmanId as created_by_id
              'shop_id': sale.shopId, // Add shop_id for consistency
              // Payment details - TODO: Add these fields to Sale model when backend is ready
              'cash_amount': 0, // sale.cashAmount,
              'card_amount': 0, // sale.cardAmount,
              'upi_amount': 0, // sale.upiAmount,
              'credit_amount': 0, // sale.creditAmount,
              'notes': '', // sale.notes,
              // Rejection tracking fields - now available in Sale model
              'rejection_reason': sale.rejectionReason,
              'rejected_by': sale.rejectedBy,
              'rejected_at': sale.rejectedAt?.toIso8601String(),
              'rejected_by_id': sale.rejectedById,
              'created_at': sale.createdAt.toIso8601String(),
              'updated_at': sale.updatedAt.toIso8601String(),
              // Location tracking fields
              'latitude': sale.latitude,
              'longitude': sale.longitude,
              'location_accuracy': sale.locationAccuracy,
            };
          }).toList();
        });
      } else {
        // Show error message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.error ?? 'Failed to load sales'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading sales: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _viewSaleDetails(Map<String, dynamic> sale) {
    final canEdit = _canEditSale(sale);
    final status = sale['status'] ?? 'pending';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          final cs = Theme.of(context).colorScheme;
          return SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Sale Details', style: AppTextStyles.h4),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              'Invoice #${sale['id'] ?? 'N/A'}',
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Status badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _getStatusColor(
                                  status,
                                ).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                status.toUpperCase(),
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: _getStatusColor(status),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Divider(height: 32),

                // Rejection reason if exists
                if (status.toLowerCase() == 'rejected' &&
                    sale['rejection_reason'] != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              color: AppColors.error,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Rejection Reason',
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.error,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          sale['rejection_reason'] ?? '',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.error,
                          ),
                        ),
                        if (sale['rejected_by'] != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Rejected by: ${sale['rejected_by']}',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.error.withValues(alpha: 0.7),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Sale Info
                _buildInfoRow('Date', sale['date'] ?? 'N/A'),
                const SizedBox(height: 12),
                _buildInfoRow('Shop', sale['shop_name'] ?? 'Unknown Shop'),
                const SizedBox(height: 12),
                _buildInfoRow('Customer', sale['customer'] ?? 'Walk-in'),
                if (sale['customer_phone'] != null) ...[
                  const SizedBox(height: 12),
                  _buildInfoRow('Phone', sale['customer_phone']),
                ],
                const Divider(height: 32),

                // Location Section
                if (sale['latitude'] != null && sale['longitude'] != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.green.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on,
                              color: Colors.green,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Sale Location',
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.green[700],
                              ),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: () => _openInMaps(
                                sale['latitude'] as double,
                                sale['longitude'] as double,
                              ),
                              icon: const Icon(Icons.map_outlined, size: 16),
                              label: const Text('Open in Maps'),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.green,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Lat: ${(sale['latitude'] as double).toStringAsFixed(6)}',
                        ),
                        Text(
                          'Lng: ${(sale['longitude'] as double).toStringAsFixed(6)}',
                        ),
                        if (sale['location_accuracy'] != null)
                          Text('Accuracy: ${sale['location_accuracy']}m'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.location_off,
                          color: Colors.orange[700],
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Location not captured for this sale',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: Colors.orange[700],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Items Section with Size Grouping
                Builder(
                  builder: (context) {
                    final items = (sale['items'] as List? ?? []);
                    final saleSize = sale['size'];

                    // Group items by size if multiple sizes exist
                    final Map<String, List<dynamic>> itemsBySize = {};
                    for (final item in items) {
                      final size = item['size']?.toString() ?? saleSize ?? 'Unknown';
                      itemsBySize.putIfAbsent(size, () => []).add(item);
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('Items', style: AppTextStyles.h5),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: cs.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${items.length}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: cs.primary,
                                ),
                              ),
                            ),
                            if (saleSize != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  saleSize.toString(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blue[700],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Display items grouped by size if multiple sizes
                        if (itemsBySize.length > 1) ...[
                          ...itemsBySize.entries.map((entry) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${entry.key} (${entry.value.length} items)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.blue[700],
                                    ),
                                  ),
                                ),
                                ...entry.value.map((item) => _buildItemCard(item)),
                              ],
                            );
                          }),
                        ] else ...[
                          // Single size or no size grouping
                          ...items.map((item) => _buildItemCard(item)),
                        ],
                      ],
                    );
                  },
                ),
                const Divider(height: 32),

                // Payment Info
                if (sale['payment_status'] != null ||
                    (sale['cash_amount'] != null || sale['card_amount'] != null ||
                     sale['upi_amount'] != null || sale['credit_amount'] != null)) ...[
                  Text('Payment Details', style: AppTextStyles.h5),
                  const SizedBox(height: 12),
                  if (sale['cash_amount'] != null && (sale['cash_amount'] as num) > 0)
                    _buildInfoRow(
                      'Cash',
                      Formatters.currency(sale['cash_amount']),
                    ),
                  if (sale['card_amount'] != null && (sale['card_amount'] as num) > 0)
                    _buildInfoRow(
                      'Card',
                      Formatters.currency(sale['card_amount']),
                    ),
                  if (sale['upi_amount'] != null && (sale['upi_amount'] as num) > 0)
                    _buildInfoRow(
                      'UPI',
                      Formatters.currency(sale['upi_amount']),
                    ),
                  if (sale['credit_amount'] != null && (sale['credit_amount'] as num) > 0)
                    _buildInfoRow(
                      'Credit',
                      Formatters.currency(sale['credit_amount']),
                    ),
                  const Divider(height: 32),
                ],

                // Expenses Section (NEW)
                if (sale['expenses'] != null && (sale['expenses'] as List).isNotEmpty) ...[
                  Row(
                    children: [
                      Icon(Icons.receipt_long_outlined, color: Colors.red[600], size: 20),
                      const SizedBox(width: 8),
                      Text('Expenses', style: AppTextStyles.h5),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          Formatters.currency(sale['total_expense_amount'] ??
                            (sale['expenses'] as List).fold(0.0, (sum, e) => sum + ((e['amount'] ?? 0) as num).toDouble())
                          ),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.red[700],
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...(sale['expenses'] as List).map((expense) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.withValues(alpha: 0.1)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.remove_circle_outline, color: Colors.red[400], size: 16),
                              const SizedBox(width: 8),
                              Text(
                                expense['header'] ?? expense['name'] ?? 'Expense',
                                style: const TextStyle(fontSize: 14),
                              ),
                            ],
                          ),
                          Text(
                            Formatters.currency(expense['amount'] ?? 0),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.red[700],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  const Divider(height: 32),
                ],

                // Totals
                // Gross Amount (if expenses exist)
                Builder(
                  builder: (context) {
                    final hasExpenses = sale['expenses'] != null && (sale['expenses'] as List).isNotEmpty;
                    final grossAmount = sale['gross_amount'] ?? sale['subtotal'] ?? sale['total'] ?? 0;
                    final totalExpenses = sale['total_expense_amount'] ??
                        (hasExpenses ? (sale['expenses'] as List).fold(0.0, (sum, e) => sum + ((e['amount'] ?? 0) as num).toDouble()) : 0.0);
                    final netAmount = sale['total'] ?? (grossAmount - totalExpenses);

                    return Column(
                      children: [
                        // Always show Gross Sales
                        _buildTotalRow(
                          hasExpenses ? 'Gross Sales' : 'Subtotal',
                          grossAmount,
                        ),
                        const SizedBox(height: 8),

                        // Expenses deduction if present
                        if (hasExpenses && totalExpenses > 0) ...[
                          _buildTotalRow(
                            'Less: Expenses',
                            totalExpenses,
                            isNegative: true,
                          ),
                          const SizedBox(height: 8),
                        ],

                        // Discount if present
                        if (sale['discount'] != null && (sale['discount'] as num) > 0) ...[
                          _buildTotalRow(
                            'Discount',
                            sale['discount'],
                            isNegative: true,
                          ),
                          const SizedBox(height: 8),
                        ],

                        // Tax if present
                        if (sale['tax'] != null && (sale['tax'] as num) > 0) ...[
                          _buildTotalRow('Tax', sale['tax']),
                          const SizedBox(height: 8),
                        ],

                        const Divider(height: 24),

                        // Net Amount / Total
                        _buildTotalRow(
                          hasExpenses ? 'Net Amount' : 'Total',
                          netAmount,
                          isTotal: true,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),

                // Actions
                Builder(
                  builder: (context) {
                    final authProvider = context.read<AuthProvider>();
                    final currentUser = authProvider.currentUser;
                    final userRole = currentUser?.role.toLowerCase() ?? '';
                    final isAdmin = userRole == 'admin' || userRole == 'saas_admin' || userRole == 'super_admin';
                    final saleStatus = status.toLowerCase();
                    final canRevert = isAdmin && saleStatus == 'approved';

                    // Debug logging
                    print('🔍 [Revert] User role: $userRole');
                    print('🔍 [Revert] Is admin: $isAdmin');
                    print('🔍 [Revert] Sale status: $saleStatus');
                    print('🔍 [Revert] Can revert: $canRevert');

                    return Column(
                      children: [
                        // Revert button - Admin only for approved sales
                        if (canRevert) ...[
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(context); // Close modal
                                _showRevertConfirmation(sale);
                              },
                              icon: const Icon(Icons.undo_rounded),
                              label: const Text('Revert Sale'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange.shade700,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        // Edit button if user has permission
                        if (canEdit && status.toLowerCase() != 'reverted') ...[
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(context); // Close modal
                                _navigateToEditSale(sale);
                              },
                              icon: Icon(
                                status.toLowerCase() == 'rejected'
                                    ? Icons.refresh
                                    : Icons.edit,
                              ),
                              label: Text(_getEditButtonLabel(sale)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _getEditButtonColor(sale),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  // TODO: Print/Share invoice
                                },
                                icon: const Icon(Icons.print),
                                label: const Text('Print'),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 48),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            if (status.toLowerCase() != 'returned' &&
                                status.toLowerCase() != 'reverted')
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    // TODO: Process return
                                  },
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.error,
                                    minimumSize: const Size(0, 48),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  icon: const Icon(Icons.keyboard_return),
                                  label: const Text('Return'),
                                ),
                              ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surfaceContainerHighest,
      appBar: AppBar(
        title: const Text('Sales History'),
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

          // Filter Chips and Toggle Button
          Container(
            color: cs.surface,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Time Period Filter Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('All', 'all'),
                      const SizedBox(width: 8),
                      _buildFilterChip('Today', 'today'),
                      const SizedBox(width: 8),
                      _buildFilterChip('This Week', 'week'),
                      const SizedBox(width: 8),
                      _buildFilterChip('This Month', 'month'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // View Toggle Button
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      _isTableView ? 'Table View' : 'Card View',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _isTableView = !_isTableView;
                        });
                      },
                      icon: Icon(
                        _isTableView
                            ? Icons.view_list_rounded
                            : Icons.table_chart_rounded,
                        color: cs.primary,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: cs.primary.withValues(
                          alpha: 0.1,
                        ),
                      ),
                      tooltip: _isTableView
                          ? 'Switch to Card View'
                          : 'Switch to Table View',
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Sales List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _sales.isEmpty
                ? const EmptyStateWidget(
                    icon: Icons.receipt_long_outlined,
                    title: 'No Sales',
                    message:
                        'Sales will appear here once you make transactions',
                  )
                : _isTableView
                ? _buildTableView()
                : _buildGroupedSalesList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = _filterPeriod == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() => _filterPeriod = value);
        _loadSales();
      },
      selectedColor: cs.primary,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : cs.onSurface,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }

  /// Build grouped sales list with date section headers (Apple-style)
  Widget _buildGroupedSalesList() {
    final groupedSales = _groupSalesByDate(_sales);
    final sortedKeys = groupedSales.keys.toList();

    // Sort keys: Today first, Yesterday second, then by date descending
    sortedKeys.sort((a, b) {
      if (a == 'Today') return -1;
      if (b == 'Today') return 1;
      if (a == 'Yesterday') return -1;
      if (b == 'Yesterday') return 1;
      // For other dates, try to parse and sort descending
      try {
        final dateA = DateFormat('d MMMM yyyy').parse(a);
        final dateB = DateFormat('d MMMM yyyy').parse(b);
        return dateB.compareTo(dateA); // Descending
      } catch (_) {
        return a.compareTo(b);
      }
    });

    return RefreshIndicator(
      onRefresh: _loadSales,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 20),
        itemCount: sortedKeys.fold<int>(
          0,
          (sum, key) => sum + 1 + groupedSales[key]!.length,
        ),
        itemBuilder: (context, index) {
          // Calculate which section and item we're at
          int currentIndex = 0;
          for (final key in sortedKeys) {
            // Check if this is a header
            if (currentIndex == index) {
              return _buildDateHeader(key);
            }
            currentIndex++;

            // Check items in this section
            final sales = groupedSales[key]!;
            for (int i = 0; i < sales.length; i++) {
              if (currentIndex == index) {
                return _buildSaleCard(sales[i]);
              }
              currentIndex++;
            }
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  /// Modern Apple-style sale card
  Widget _buildSaleCard(Map<String, dynamic> sale) {
    final cs = Theme.of(context).colorScheme;
    final canEdit = _canEditSale(sale);
    final status = sale['status'] ?? 'pending';
    final shopName = sale['shop_name'] ?? 'Unknown Shop';
    final creatorName = sale['created_by_name'] ?? sale['customer'] ?? 'Walk-in';
    final itemCount = (sale['items'] as List?)?.length ?? 0;
    final total = sale['total'] ?? 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _viewSaleDetails(sale),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Row 1: Shop name with icon
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.store_outlined,
                        color: cs.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        shopName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Chevron indicator
                    Icon(
                      Icons.chevron_right,
                      color: cs.onSurfaceVariant,
                      size: 22,
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Row 2: Creator name • Items count
                Padding(
                  padding: const EdgeInsets.only(left: 44),
                  child: Row(
                    children: [
                      Icon(
                        Icons.person_outline,
                        size: 14,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '$creatorName • $itemCount items',
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Row 3: Amount and Status badge
                Padding(
                  padding: const EdgeInsets.only(left: 44),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        Formatters.currency(total),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.success,
                        ),
                      ),
                      _buildStatusBadge(status),
                    ],
                  ),
                ),

                // Rejection reason if applicable
                if (status.toLowerCase() == 'rejected' &&
                    sale['rejection_reason'] != null) ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.only(left: 44),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 14,
                            color: AppColors.error,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${sale['rejection_reason']}',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.error,
                                fontStyle: FontStyle.italic,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                // Edit button if user has permission
                if (canEdit) ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.only(left: 44),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _navigateToEditSale(sale),
                        icon: Icon(
                          status.toLowerCase() == 'rejected'
                              ? Icons.refresh
                              : Icons.edit_outlined,
                          size: 16,
                        ),
                        label: Text(_getEditButtonLabel(sale)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _getEditButtonColor(sale),
                          side: BorderSide(
                            color: _getEditButtonColor(sale).withValues(alpha: 0.3),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
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

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
      case 'completed':
        return AppColors.success;
      case 'rejected':
        return AppColors.error;
      case 'pending':
        return AppColors.warning;
      case 'returned':
        return AppColors.info;
      case 'reverted':
        return Colors.orange; // Distinct orange for reverted sales
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  /// Get status icon for modern badge
  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
      case 'completed':
        return Icons.check_circle_outline;
      case 'rejected':
        return Icons.cancel_outlined;
      case 'pending':
        return Icons.schedule;
      case 'returned':
        return Icons.replay;
      case 'reverted':
        return Icons.undo_rounded;
      default:
        return Icons.help_outline;
    }
  }

  /// Group sales by date for section headers
  Map<String, List<Map<String, dynamic>>> _groupSalesByDate(
      List<Map<String, dynamic>> sales) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    for (final sale in sales) {
      final dateStr = sale['date'] as String?;
      if (dateStr == null) {
        grouped.putIfAbsent('Unknown Date', () => []).add(sale);
        continue;
      }

      // Parse date - try different formats
      DateTime? saleDate;
      try {
        // Try ISO format first
        saleDate = DateTime.tryParse(dateStr);
        // Try common date formats
        if (saleDate == null) {
          final formats = ['dd/MM/yyyy', 'yyyy-MM-dd', 'd MMM yyyy', 'dd-MM-yyyy'];
          for (final format in formats) {
            try {
              saleDate = DateFormat(format).parse(dateStr);
              break;
            } catch (_) {}
          }
        }
      } catch (_) {}

      if (saleDate == null) {
        grouped.putIfAbsent(dateStr, () => []).add(sale);
        continue;
      }

      final saleDateOnly = DateTime(saleDate.year, saleDate.month, saleDate.day);

      String groupKey;
      if (saleDateOnly == today) {
        groupKey = 'Today';
      } else if (saleDateOnly == yesterday) {
        groupKey = 'Yesterday';
      } else {
        groupKey = DateFormat('d MMMM yyyy').format(saleDate);
      }

      grouped.putIfAbsent(groupKey, () => []).add(sale);
    }
    return grouped;
  }

  /// Build date section header (Apple-style)
  Widget _buildDateHeader(String dateGroup) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
      child: Text(
        dateGroup.toUpperCase(),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: cs.onSurfaceVariant,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  /// Build modern status badge with icon
  Widget _buildStatusBadge(String status) {
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

  Widget _buildTableView() {
    return RefreshIndicator(
      onRefresh: _loadSales,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _sales.length,
        itemBuilder: (context, index) {
          final saleData = _sales[index];

          // Convert to Sale object for table widget
          final sale = Sale(
            id: saleData['id'] ?? 'N/A',
            saleNumber: 'INV-${saleData['id'] ?? 'N/A'}',
            shopId: saleData['shop_id'] ?? '',
            saleDate:
                DateTime.tryParse(saleData['date'] ?? '') ?? DateTime.now(),
            customerName: saleData['customer'],
            customerPhone: saleData['customer_phone'],
            subTotal: (saleData['subtotal'] ?? 0).toDouble(),
            discountAmount: (saleData['discount'] ?? 0).toDouble(),
            taxAmount: (saleData['tax'] ?? 0).toDouble(),
            totalAmount: (saleData['total'] ?? 0).toDouble(),
            paidAmount: (saleData['paid_amount'] ?? saleData['total'] ?? 0)
                .toDouble(),
            dueAmount: 0,
            paymentMethod: saleData['payment_method'] ?? 'cash',
            paymentStatus: 'paid',
            status: saleData['status'] ?? 'completed',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            items: (saleData['items'] as List? ?? [])
                .map(
                  (item) => SaleItem(
                    id: item['id'] ?? '',
                    saleId: saleData['id'] ?? '',
                    productId: item['product_id'] ?? '',
                    productName: item['name'] ?? '',
                    brandName: item['brand'] ?? '',
                    categoryName: item['category'] ?? '',
                    size: item['size'] ?? item['ml'] ?? '',
                    sku: item['sku'],
                    quantity: item['quantity'] ?? 1,
                    unitPrice: (item['price'] ?? 0).toDouble(),
                    totalPrice: (item['total'] ?? 0).toDouble(),
                    discountAmount: 0,
                  ),
                )
                .toList(),
          );

          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: GestureDetector(
              onTap: () => _viewSaleDetails(saleData),
              child: ReceiptTableWidget(
                sale: sale,
                showHeader: true,
                showPaymentDetails: true,
                groupBySize: false,
              ),
            ),
          );
        },
      ),
    );
  }

  // Permission helper methods
  bool _canEditSale(Map<String, dynamic> sale) {
    // TEMPORARY: Show edit button for all sales to test
    print(
      '🔍 [EditPermission] TEMPORARY - Showing edit button for sale ${sale['id']}',
    );
    return true;

    /* Original logic - uncomment after testing
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;

    // Debug logging
    print('🔍 [EditPermission] Checking edit permission for sale ${sale['id']}');
    print('🔍 [EditPermission] Current user: ${currentUser?.toJson()}');
    print('🔍 [EditPermission] Sale salesman_id: ${sale['salesman_id']}');
    print('🔍 [EditPermission] Sale created_by_id: ${sale['created_by_id']}');
    print('🔍 [EditPermission] Sale status: ${sale['status']}');

    if (currentUser == null) {
      print('🔍 [EditPermission] No current user - returning false');
      return false;
    }
    final status = sale['status'] ?? 'pending';
    final isCreator = sale['salesman_id'] == currentUser.id ||
                     sale['created_by_id'] == currentUser.id;
    final managementRoles = ['admin', 'manager', 'assistant_manager'];
    final isManager = managementRoles.contains(currentUser.role);

    print('🔍 [EditPermission] User role: ${currentUser.role}');
    print('🔍 [EditPermission] User id: ${currentUser.id}');
    print('🔍 [EditPermission] Is creator: $isCreator');
    print('🔍 [EditPermission] Is manager: $isManager');

    // Permission logic based on status and role
    bool canEdit = false;
    switch (status.toLowerCase()) {
      case 'pending':
        canEdit = isCreator || isManager; // Creator and managers can edit pending sales
        break;
      case 'rejected':
        canEdit = isCreator || isManager; // Creator can edit & resubmit rejected sales
        break;
      case 'approved':
        canEdit = isManager; // Only managers can edit approved sales
        break;
      case 'completed':
        canEdit = isManager; // Only managers can edit completed sales
        break;
      case 'returned':
        canEdit = false; // No one can edit returned sales
        break;
      default:
        canEdit = false;
    }

    print('🔍 [EditPermission] Can edit: $canEdit');
    return canEdit;
    */
  }

  String _getEditButtonLabel(Map<String, dynamic> sale) {
    final status = sale['status'] ?? 'pending';
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;

    if (currentUser == null) return 'Edit';

    final isCreator =
        sale['salesman_id'] == currentUser.id ||
        sale['created_by_id'] == currentUser.id;

    // If rejected and user is creator, show "Edit & Resubmit"
    if (status.toLowerCase() == 'rejected' && isCreator) {
      return 'Edit & Resubmit';
    }

    return 'Edit Sale';
  }

  Color _getEditButtonColor(Map<String, dynamic> sale) {
    final cs = Theme.of(context).colorScheme;
    final status = sale['status'] ?? 'pending';

    switch (status.toLowerCase()) {
      case 'rejected':
        return AppColors.warning; // Orange for rejected sales
      case 'approved':
        return cs.primary; // Primary color for approved
      case 'pending':
        return AppColors.info; // Blue for pending
      default:
        return cs.primary;
    }
  }

  /// Show revert confirmation dialog - Admin only
  /// Step 1: Collect reason and request OTP
  void _showRevertConfirmation(Map<String, dynamic> sale) {
    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.undo_rounded, color: Colors.orange.shade700, size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Revert Sale',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Security notice
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.security, color: Colors.blue.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'For security, OTP verification on both Email & Phone is required.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue.shade800,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Warning
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This will restore all items back to inventory and mark the sale as reverted.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.orange.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Sale Total: ${Formatters.currency(sale['total'] ?? 0)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Items: ${(sale['items'] as List?)?.length ?? 0}',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: reasonController,
                decoration: InputDecoration(
                  labelText: 'Reason for Reverting *',
                  hintText: 'Enter reason for reverting this sale...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  prefixIcon: const Icon(Icons.notes),
                ),
                maxLines: 3,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please provide a reason for reverting';
                  }
                  if (value.trim().length < 10) {
                    return 'Reason must be at least 10 characters';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(context);
                _requestRevertOtp(sale, reasonController.text.trim());
              }
            },
            icon: const Icon(Icons.send, size: 18),
            label: const Text('Send OTP'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Request OTP for sale revert - calls backend API
  Future<void> _requestRevertOtp(Map<String, dynamic> sale, String reason) async {
    final saleId = sale['id'] as String?;
    if (saleId == null) return;

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: Text('Sending OTP to your email and phone...')),
          ],
        ),
      ),
    );

    try {
      final response = await _salesService.requestRevertOtp(saleId);

      // Close loading dialog
      if (mounted) Navigator.pop(context);

      if (response.success && response.data != null) {
        // Show OTP verification dialog
        if (mounted) {
          _showOtpVerificationDialog(sale, reason, response.data!);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.error ?? 'Failed to send OTP'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      // Close loading dialog
      if (mounted) Navigator.pop(context);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending OTP: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Show OTP verification dialog with dual OTP inputs
  void _showOtpVerificationDialog(
    Map<String, dynamic> sale,
    String reason,
    RevertOtpResponse otpResponse,
  ) {
    final emailOtpController = TextEditingController();
    final phoneOtpController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isVerifying = false;
    bool isResending = false;
    int remainingSeconds = otpResponse.remainingSeconds;
    RevertOtpResponse currentOtpResponse = otpResponse;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Start countdown timer
          Future.delayed(const Duration(seconds: 1), () {
            if (remainingSeconds > 0) {
              setDialogState(() => remainingSeconds--);
            }
          });

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.verified_user, color: Colors.green.shade700, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Verify OTP',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Timer and info / Resend button
                    if (remainingSeconds > 0)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: remainingSeconds > 60
                              ? Colors.green.shade50
                              : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: remainingSeconds > 60
                                ? Colors.green.shade200
                                : Colors.red.shade200,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.timer,
                              color: remainingSeconds > 60
                                  ? Colors.green.shade700
                                  : Colors.red.shade700,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Expires in: ${remainingSeconds ~/ 60}:${(remainingSeconds % 60).toString().padLeft(2, '0')}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: remainingSeconds > 60
                                    ? Colors.green.shade700
                                    : Colors.red.shade700,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      // OTP Expired - Show Resend Button
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(Icons.timer_off, color: Colors.red.shade700, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'OTPs have expired',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red.shade700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: isResending
                                    ? null
                                    : () async {
                                        setDialogState(() => isResending = true);
                                        await _resendOtps(
                                          sale['id'] as String,
                                          setDialogState,
                                          (newResponse) {
                                            setDialogState(() {
                                              currentOtpResponse = newResponse;
                                              remainingSeconds = newResponse.remainingSeconds;
                                              isResending = false;
                                              // Clear OTP fields for new attempt
                                              emailOtpController.clear();
                                              phoneOtpController.clear();
                                            });
                                          },
                                        );
                                        if (isResending) {
                                          setDialogState(() => isResending = false);
                                        }
                                      },
                                icon: isResending
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.refresh, size: 18),
                                label: Text(isResending ? 'Sending...' : 'Resend OTPs'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange.shade600,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),

                    // Email OTP Section
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.email, color: Colors.blue.shade600, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Email OTP',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                              const Spacer(),
                              if (currentOtpResponse.emailSent)
                                Icon(Icons.check_circle, color: Colors.green.shade400, size: 16),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Sent to: ${currentOtpResponse.maskedEmail}',
                            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: emailOtpController,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            maxLength: 6,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 8,
                            ),
                            decoration: InputDecoration(
                              hintText: '••••••',
                              counterText: '',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              filled: true,
                              fillColor: Theme.of(context).colorScheme.surface,
                            ),
                            validator: (value) {
                              if (value == null || value.length != 6) {
                                return 'Enter 6-digit OTP';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Phone OTP Section
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.phone_android, color: Colors.green.shade600, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Phone OTP',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade700,
                                ),
                              ),
                              const Spacer(),
                              if (currentOtpResponse.phoneSent)
                                Icon(Icons.check_circle, color: Colors.green.shade400, size: 16),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Sent to: ${currentOtpResponse.maskedPhone}',
                            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: phoneOtpController,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            maxLength: 6,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 8,
                            ),
                            decoration: InputDecoration(
                              hintText: '••••••',
                              counterText: '',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              filled: true,
                              fillColor: Theme.of(context).colorScheme.surface,
                            ),
                            validator: (value) {
                              if (value == null || value.length != 6) {
                                return 'Enter 6-digit OTP';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Security notice
                    Row(
                      children: [
                        Icon(Icons.info_outline, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Different OTPs are sent to each channel for enhanced security',
                            style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isVerifying ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: isVerifying || remainingSeconds <= 0
                    ? null
                    : () async {
                        if (formKey.currentState?.validate() ?? false) {
                          setDialogState(() => isVerifying = true);
                          await _verifyAndRevertSale(
                            sale,
                            reason,
                            emailOtpController.text.trim(),
                            phoneOtpController.text.trim(),
                            dialogContext,
                          );
                          setDialogState(() => isVerifying = false);
                        }
                      },
                icon: isVerifying
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check_circle, size: 18),
                label: Text(isVerifying ? 'Verifying...' : 'Verify & Revert'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Resend OTPs - requests new OTPs to both email and phone
  Future<void> _resendOtps(
    String saleId,
    void Function(void Function()) setDialogState,
    void Function(RevertOtpResponse) onNewOtpResponse,
  ) async {
    try {
      final response = await _salesService.resendRevertOtp(saleId);

      if (response.success && response.data != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('New OTPs sent to email and phone'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 2),
            ),
          );
          // Update with new OTP response (new expiry time)
          onNewOtpResponse(response.data!);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.error ?? 'Failed to resend OTP'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error resending OTP: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Verify OTPs and revert sale
  Future<void> _verifyAndRevertSale(
    Map<String, dynamic> sale,
    String reason,
    String emailOtp,
    String phoneOtp,
    BuildContext dialogContext,
  ) async {
    final saleId = sale['id'] as String?;
    if (saleId == null) return;

    try {
      final response = await _salesService.verifyAndRevertSale(
        saleId: saleId,
        emailOtp: emailOtp,
        phoneOtp: phoneOtp,
        reason: reason,
      );

      if (response.success) {
        // Close OTP dialog
        if (mounted) Navigator.pop(dialogContext);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text('Sale reverted successfully. Stock restored to inventory.'),
                  ),
                ],
              ),
              backgroundColor: Colors.green.shade600,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
          // Reload sales list
          _loadSales();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.error ?? 'OTP verification failed. Max 3 attempts allowed.'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Opens the location in Google Maps or Apple Maps
  Future<void> _openInMaps(double lat, double lng) async {
    final googleMapsUrl = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );
    final appleMapsUrl = Uri.parse('https://maps.apple.com/?q=$lat,$lng');

    try {
      if (await canLaunchUrl(googleMapsUrl)) {
        await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
      } else if (await canLaunchUrl(appleMapsUrl)) {
        await launchUrl(appleMapsUrl, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not open maps application'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening maps: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Build item card for sale details modal
  Widget _buildItemCard(dynamic item) {
    final cs = Theme.of(context).colorScheme;
    // Handle different field names from backend
    final name = item['name'] ?? item['brand_name'] ?? item['product_name'] ?? 'Unknown';
    final quantity = item['quantity'] ?? item['qty'] ?? 0;
    final price = (item['price'] ?? item['rate'] ?? item['unit_price'] ?? 0).toDouble();
    final total = (item['total'] ?? item['amount'] ?? (quantity * price)).toDouble();
    final size = item['size'];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            // Item info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '$quantity × ${Formatters.currency(price)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      if (size != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            size.toString(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: Colors.blue[700],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // Total
            Text(
              Formatters.currency(total),
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.bold,
                color: cs.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTextStyles.bodyMedium.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildTotalRow(
    String label,
    dynamic amount, {
    bool isNegative = false,
    bool isTotal = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    // Safely convert to double
    final amountDouble = (amount is num) ? amount.toDouble() : 0.0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: isTotal ? AppTextStyles.h5 : AppTextStyles.bodyMedium,
        ),
        Text(
          '${isNegative ? '-' : ''}${Formatters.currency(amountDouble)}',
          style: isTotal
              ? AppTextStyles.h4.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.bold,
                )
              : AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isNegative ? AppColors.error : null,
                ),
        ),
      ],
    );
  }

  /// Show filter bottom sheet
  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Filter Sales',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            // Status filter
            Text(
              'Status',
              style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildStatusFilterOption(null, 'All'),
                _buildStatusFilterOption('pending', 'Pending'),
                _buildStatusFilterOption('approved', 'Approved'),
                _buildStatusFilterOption('rejected', 'Rejected'),
                _buildStatusFilterOption('returned', 'Returned'),
                _buildStatusFilterOption('reverted', 'Reverted'),
              ],
            ),
            const SizedBox(height: 20),

            // Date Range filter
            Text(
              'Date Range',
              style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                  initialDateRange: _dateRange,
                );
                if (picked != null) {
                  setState(() {
                    _dateRange = picked;
                  });
                }
              },
              icon: const Icon(Icons.calendar_today),
              label: Text(
                _dateRange != null
                    ? '${_dateRange!.start.day}/${_dateRange!.start.month}/${_dateRange!.start.year} - ${_dateRange!.end.day}/${_dateRange!.end.month}/${_dateRange!.end.year}'
                    : 'Select Date Range',
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
            const SizedBox(height: 24),

            // Apply button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _loadSales();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: cs.primary,
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
      );
      },
    );
  }

  Widget _buildStatusFilterOption(String? status, String label) {
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
        final cs = Theme.of(context).colorScheme;
        final shops = shopProvider.shops;

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
                      _loadSales();
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
                ...shops.map(
                  (shop) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(shop.name),
                      selected: _selectedShopId == shop.id,
                      onSelected: (_) {
                        setState(() => _selectedShopId = shop.id);
                        _loadSales();
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
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
