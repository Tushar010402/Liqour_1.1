import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../../shared/widgets/empty_state_widget.dart';

/// Stock Transfer Screen - Transfer inventory between shops
class StockTransferScreen extends StatefulWidget {
  const StockTransferScreen({super.key});

  @override
  State<StockTransferScreen> createState() => _StockTransferScreenState();
}

class _StockTransferScreenState extends State<StockTransferScreen> {
  bool _isLoading = false;
  final List<Map<String, dynamic>> _transfers = [];
  String _filterStatus = 'all'; // all/pending/in_transit/completed/cancelled

  @override
  void initState() {
    super.initState();
    _loadTransfers();
  }

  Future<void> _loadTransfers() async {
    setState(() => _isLoading = true);
    // TODO: Load transfers from API - GET /api/inventory/transfers
    await Future.delayed(const Duration(seconds: 1));
    setState(() => _isLoading = false);
  }

  void _showCreateTransferDialog() {
    final List<Map<String, dynamic>> selectedProducts = [];
    String? fromShopId;
    String? toShopId;
    final notesController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Create Stock Transfer'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // From Shop Dropdown
                  DropdownButtonFormField<String>(
                    value: fromShopId,
                    decoration: const InputDecoration(
                      labelText: 'From Shop',
                      prefixIcon: Icon(Icons.store),
                      border: OutlineInputBorder(),
                    ),
                    items: ['Shop 1', 'Shop 2', 'Shop 3', 'Warehouse']
                        .map((shop) => DropdownMenuItem(
                              value: shop.toLowerCase().replaceAll(' ', '_'),
                              child: Text(shop),
                            ))
                        .toList(),
                    onChanged: (value) {
                      setState(() => fromShopId = value);
                    },
                  ),
                  const SizedBox(height: 16),

                  // To Shop Dropdown
                  DropdownButtonFormField<String>(
                    value: toShopId,
                    decoration: const InputDecoration(
                      labelText: 'To Shop',
                      prefixIcon: Icon(Icons.store_outlined),
                      border: OutlineInputBorder(),
                    ),
                    items: ['Shop 1', 'Shop 2', 'Shop 3', 'Warehouse']
                        .map((shop) => DropdownMenuItem(
                              value: shop.toLowerCase().replaceAll(' ', '_'),
                              child: Text(shop),
                            ))
                        .toList(),
                    onChanged: (value) {
                      setState(() => toShopId = value);
                    },
                  ),
                  const SizedBox(height: 16),

                  // Products Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Products (${selectedProducts.length})',
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          // TODO: Show product selection dialog
                          setState(() {
                            selectedProducts.add({
                              'id': 'prod_${selectedProducts.length + 1}',
                              'name': 'Sample Product ${selectedProducts.length + 1}',
                              'quantity': 10,
                            });
                          });
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Add Product'),
                      ),
                    ],
                  ),

                  if (selectedProducts.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: selectedProducts.length,
                        itemBuilder: (context, index) {
                          final product = selectedProducts[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              title: Text(product['name']),
                              subtitle: Text('Quantity: ${product['quantity']}'),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: AppColors.error),
                                onPressed: () {
                                  setState(() => selectedProducts.removeAt(index));
                                },
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // Notes
                  TextField(
                    controller: notesController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Notes (Optional)',
                      hintText: 'Add any additional notes...',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.notes),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: fromShopId != null &&
                      toShopId != null &&
                      fromShopId != toShopId &&
                      selectedProducts.isNotEmpty
                  ? () {
                      // TODO: Create transfer - POST /api/inventory/transfers
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Transfer created successfully'),
                          backgroundColor: AppColors.success,
                        ),
                      );
                      _loadTransfers();
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Create Transfer'),
            ),
          ],
        ),
      ),
    );
  }

  void _showTransferDetails(Map<String, dynamic> transfer) {
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
          final status = transfer['status'] ?? 'pending';
          Color statusColor;
          switch (status) {
            case 'completed':
              statusColor = AppColors.success;
              break;
            case 'in_transit':
              statusColor = AppColors.warning;
              break;
            case 'cancelled':
              statusColor = AppColors.error;
              break;
            default:
              statusColor = AppColors.info;
          }

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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Transfer #${transfer['id']}',
                            style: AppTextStyles.h4,
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              status.toUpperCase(),
                              style: AppTextStyles.bodySmall.copyWith(
                                color: statusColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Divider(height: 32),

                // Transfer Route
                Row(
                  children: [
                    Expanded(
                      child: _buildLocationCard(
                        'From',
                        transfer['from_shop'] ?? 'Shop 1',
                        Icons.store,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.arrow_forward, color: AppColors.primary),
                    ),
                    Expanded(
                      child: _buildLocationCard(
                        'To',
                        transfer['to_shop'] ?? 'Shop 2',
                        Icons.store_outlined,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Transfer Details
                _buildDetailRow('Transfer Date', transfer['date'] ?? 'Jan 15, 2025'),
                _buildDetailRow('Initiated By', transfer['initiated_by'] ?? 'Admin User'),
                if (transfer['completed_date'] != null)
                  _buildDetailRow('Completed Date', transfer['completed_date']),
                if (transfer['notes'] != null) ...[
                  const SizedBox(height: 16),
                  Text('Notes', style: AppTextStyles.h5),
                  const SizedBox(height: 8),
                  Text(
                    transfer['notes'],
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Products
                Text('Products', style: AppTextStyles.h5),
                const SizedBox(height: 12),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: transfer['items']?.length ?? 0,
                  itemBuilder: (context, index) {
                    final item = transfer['items'][index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.inventory_2,
                            color: AppColors.primary,
                          ),
                        ),
                        title: Text(item['product_name'] ?? 'Product'),
                        subtitle: Text('SKU: ${item['sku'] ?? 'N/A'}'),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${item['quantity']} units',
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 24),

                // Action Buttons
                if (status == 'pending') ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        // TODO: Mark as in transit - PATCH /api/inventory/transfers/:id/dispatch
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Transfer dispatched'),
                            backgroundColor: AppColors.success,
                          ),
                        );
                        _loadTransfers();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      icon: const Icon(Icons.local_shipping),
                      label: const Text('Dispatch Transfer'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        // TODO: Cancel transfer - PATCH /api/inventory/transfers/:id/cancel
                        Navigator.pop(context);
                        _loadTransfers();
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.error),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      icon: const Icon(Icons.cancel),
                      label: const Text('Cancel Transfer'),
                    ),
                  ),
                ],
                if (status == 'in_transit') ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        // TODO: Mark as received - PATCH /api/inventory/transfers/:id/receive
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Transfer received and stock updated'),
                            backgroundColor: AppColors.success,
                          ),
                        );
                        _loadTransfers();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      icon: const Icon(Icons.check_circle),
                      label: const Text('Mark as Received'),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLocationCard(String label, String location, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.textSecondary.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.primary, size: 32),
          const SizedBox(height: 8),
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            location,
            style: AppTextStyles.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            value,
            style: AppTextStyles.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(
        title: 'Stock Transfers',
      ),
      body: Column(
        children: [
          // Filter Chips
          Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('All', 'all', Icons.all_inbox),
                  const SizedBox(width: 8),
                  _buildFilterChip('Pending', 'pending', Icons.pending),
                  const SizedBox(width: 8),
                  _buildFilterChip('In Transit', 'in_transit', Icons.local_shipping),
                  const SizedBox(width: 8),
                  _buildFilterChip('Completed', 'completed', Icons.check_circle),
                  const SizedBox(width: 8),
                  _buildFilterChip('Cancelled', 'cancelled', Icons.cancel),
                ],
              ),
            ),
          ),

          // Summary Cards
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: _buildSummaryCard(
                    'Pending',
                    '0',
                    AppColors.info,
                    Icons.pending,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSummaryCard(
                    'In Transit',
                    '0',
                    AppColors.warning,
                    Icons.local_shipping,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSummaryCard(
                    'Completed',
                    '0',
                    AppColors.success,
                    Icons.check_circle,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Transfers List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _transfers.isEmpty
                    ? const EmptyStateWidget(
                        icon: Icons.sync_alt,
                        title: 'No Transfers',
                        message: 'Create your first stock transfer',
                      )
                    : RefreshIndicator(
                        onRefresh: _loadTransfers,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _transfers.length,
                          itemBuilder: (context, index) {
                            final transfer = _transfers[index];
                            return _buildTransferCard(transfer);
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateTransferDialog,
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.sync_alt, color: Colors.white),
        label: const Text('New Transfer', style: TextStyle(color: Colors.white)),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, IconData icon) {
    final isSelected = _filterStatus == value;
    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: isSelected ? Colors.white : AppColors.textPrimary),
          const SizedBox(width: 4),
          Text(label),
        ],
      ),
      selected: isSelected,
      onSelected: (selected) {
        setState(() => _filterStatus = value);
        _loadTransfers();
      },
      selectedColor: AppColors.primary,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : AppColors.textPrimary,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }

  Widget _buildSummaryCard(String title, String count, Color color, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              count,
              style: AppTextStyles.h4.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransferCard(Map<String, dynamic> transfer) {
    final status = transfer['status'] ?? 'pending';
    Color statusColor;
    IconData statusIcon;

    switch (status) {
      case 'completed':
        statusColor = AppColors.success;
        statusIcon = Icons.check_circle;
        break;
      case 'in_transit':
        statusColor = AppColors.warning;
        statusIcon = Icons.local_shipping;
        break;
      case 'cancelled':
        statusColor = AppColors.error;
        statusIcon = Icons.cancel;
        break;
      default:
        statusColor = AppColors.info;
        statusIcon = Icons.pending;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _showTransferDetails(transfer),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Transfer #${transfer['id']}',
                    style: AppTextStyles.bodyLarge.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 14, color: statusColor),
                        const SizedBox(width: 4),
                        Text(
                          status.toUpperCase(),
                          style: AppTextStyles.bodySmall.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.store, size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    transfer['from_shop'] ?? 'Shop 1',
                    style: AppTextStyles.bodyMedium,
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.arrow_forward, size: 16, color: AppColors.primary),
                  ),
                  Icon(Icons.store_outlined, size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    transfer['to_shop'] ?? 'Shop 2',
                    style: AppTextStyles.bodyMedium,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.inventory_2, size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    '${transfer['items']?.length ?? 0} products',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.calendar_today, size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    transfer['date'] ?? 'Jan 15, 2025',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
