import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/empty_state_widget.dart';

/// Sales History Screen
class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  bool _isLoading = false;
  final List<Map<String, dynamic>> _sales = [];
  String _filterPeriod = 'all';

  @override
  void initState() {
    super.initState();
    _loadSales();
  }

  Future<void> _loadSales() async {
    setState(() => _isLoading = true);
    // TODO: Load from API
    await Future.delayed(const Duration(seconds: 1));
    setState(() => _isLoading = false);
  }

  void _viewSaleDetails(Map<String, dynamic> sale) {
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
                    Text(
                      'Sale Details',
                      style: AppTextStyles.h4,
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Invoice #${sale['id'] ?? 'N/A'}',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const Divider(height: 32),

                // Sale Info
                _buildInfoRow('Date', sale['date'] ?? 'N/A'),
                const SizedBox(height: 12),
                _buildInfoRow('Shop', sale['shop'] ?? 'N/A'),
                const SizedBox(height: 12),
                _buildInfoRow('Customer', sale['customer'] ?? 'Walk-in'),
                const Divider(height: 32),

                // Items
                Text(
                  'Items',
                  style: AppTextStyles.h5,
                ),
                const SizedBox(height: 12),
                ...(sale['items'] as List? ?? []).map((item) {
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(item['name'] ?? ''),
                      subtitle: Text('${item['quantity']} × ${Formatters.currency(item['price'])}'),
                      trailing: Text(
                        Formatters.currency(item['total']),
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                }),
                const Divider(height: 32),

                // Totals
                _buildTotalRow('Subtotal', sale['subtotal'] ?? 0),
                const SizedBox(height: 8),
                if (sale['discount'] != null && sale['discount'] > 0) ...[
                  _buildTotalRow('Discount', sale['discount'], isNegative: true),
                  const SizedBox(height: 8),
                ],
                if (sale['tax'] != null && sale['tax'] > 0) ...[
                  _buildTotalRow('Tax', sale['tax']),
                  const SizedBox(height: 8),
                ],
                const Divider(height: 24),
                _buildTotalRow(
                  'Total',
                  sale['total'] ?? 0,
                  isTotal: true,
                ),
                const SizedBox(height: 24),

                // Actions
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          // TODO: Print/Share invoice
                        },
                        icon: const Icon(Icons.print),
                        label: const Text('Print'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          // TODO: Process return
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                        ),
                        icon: const Icon(Icons.keyboard_return),
                        label: const Text('Return'),
                      ),
                    ),
                  ],
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
    return Scaffold(
      body: Column(
        children: [
          // Filter Chips
          Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
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
          ),

          // Sales List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _sales.isEmpty
                    ? const EmptyStateWidget(
                        icon: Icons.receipt_long_outlined,
                        title: 'No Sales',
                        message: 'Sales will appear here once you make transactions',
                      )
                    : RefreshIndicator(
                        onRefresh: _loadSales,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _sales.length,
                          itemBuilder: (context, index) {
                            final sale = _sales[index];
                            return _buildSaleCard(sale);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _filterPeriod == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() => _filterPeriod = value);
        _loadSales();
      },
      selectedColor: AppColors.primary,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : AppColors.textPrimary,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }

  Widget _buildSaleCard(Map<String, dynamic> sale) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: AppColors.success.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.receipt,
            color: AppColors.success,
          ),
        ),
        title: Text(
          'Invoice #${sale['id'] ?? 'N/A'}',
          style: AppTextStyles.bodyLarge.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              '${sale['date']} • ${sale['shop'] ?? 'N/A'}',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${sale['items_count'] ?? 0} items',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        trailing: Text(
          Formatters.currency(sale['total'] ?? 0),
          style: AppTextStyles.h5.copyWith(
            color: AppColors.success,
            fontWeight: FontWeight.bold,
          ),
        ),
        onTap: () => _viewSaleDetails(sale),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
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
    );
  }

  Widget _buildTotalRow(String label, double amount, {bool isNegative = false, bool isTotal = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: isTotal
              ? AppTextStyles.h5
              : AppTextStyles.bodyMedium,
        ),
        Text(
          '${isNegative ? '-' : ''}${Formatters.currency(amount)}',
          style: isTotal
              ? AppTextStyles.h4.copyWith(
                  color: AppColors.primary,
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
}
