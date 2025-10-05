import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/custom_app_bar.dart';

/// Customer Detail Screen
class CustomerDetailScreen extends StatefulWidget {
  final Map<String, dynamic> customer;

  const CustomerDetailScreen({
    super.key,
    required this.customer,
  });

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;
  final List<Map<String, dynamic>> _purchases = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadCustomerData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomerData() async {
    setState(() => _isLoading = true);
    // TODO: Load customer purchases from API
    await Future.delayed(const Duration(seconds: 1));
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Customer Details',
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              // TODO: Navigate to edit customer
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Customer Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
            ),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: AppColors.primary.withOpacity(0.2),
                  child: Text(
                    (widget.customer['name'] ?? 'C')
                        .substring(0, 1)
                        .toUpperCase(),
                    style: AppTextStyles.h2.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  widget.customer['name'] ?? 'Customer',
                  style: AppTextStyles.h4.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.phone_outlined,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      widget.customer['phone'] ?? '',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                if (widget.customer['email'] != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.email_outlined,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        widget.customer['email'],
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Stats Cards
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    title: 'Total Spent',
                    value: Formatters.currency(
                      widget.customer['total_spent'] ?? 0,
                    ),
                    icon: Icons.currency_rupee,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    title: 'Orders',
                    value: '${widget.customer['total_purchases'] ?? 0}',
                    icon: Icons.shopping_bag,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),

          // Tabs
          Container(
            color: AppColors.background,
            child: TabBar(
              controller: _tabController,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              tabs: const [
                Tab(text: 'Purchase History'),
                Tab(text: 'Information'),
              ],
            ),
          ),

          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildPurchaseHistoryTab(),
                _buildInformationTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              value,
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

  Widget _buildPurchaseHistoryTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_purchases.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.shopping_bag_outlined,
              size: 80,
              color: AppColors.primary.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No Purchase History',
              style: AppTextStyles.h5,
            ),
            const SizedBox(height: 8),
            Text(
              'This customer hasn\'t made any purchases yet',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _purchases.length,
      itemBuilder: (context, index) {
        final purchase = _purchases[index];
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
              'Invoice #${purchase['invoice_number'] ?? 'N/A'}',
              style: AppTextStyles.bodyLarge.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  purchase['date'] ?? '',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${purchase['items_count'] ?? 0} items',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            trailing: Text(
              Formatters.currency(purchase['total'] ?? 0),
              style: AppTextStyles.h5.copyWith(
                color: AppColors.success,
                fontWeight: FontWeight.bold,
              ),
            ),
            onTap: () {
              // TODO: View purchase details
            },
          ),
        );
      },
    );
  }

  Widget _buildInformationTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Contact Information
        Text(
          'Contact Information',
          style: AppTextStyles.h5,
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildInfoRow('Phone', widget.customer['phone'] ?? 'N/A'),
                if (widget.customer['email'] != null) ...[
                  const Divider(height: 24),
                  _buildInfoRow('Email', widget.customer['email']),
                ],
                if (widget.customer['address'] != null) ...[
                  const Divider(height: 24),
                  _buildInfoRow('Address', widget.customer['address']),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Purchase Statistics
        Text(
          'Purchase Statistics',
          style: AppTextStyles.h5,
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildInfoRow(
                  'Total Orders',
                  '${widget.customer['total_purchases'] ?? 0}',
                ),
                const Divider(height: 24),
                _buildInfoRow(
                  'Total Spent',
                  Formatters.currency(widget.customer['total_spent'] ?? 0),
                ),
                const Divider(height: 24),
                _buildInfoRow(
                  'Average Order Value',
                  Formatters.currency(_calculateAverageOrder()),
                ),
                const Divider(height: 24),
                _buildInfoRow(
                  'Last Purchase',
                  widget.customer['last_purchase_date'] ?? 'Never',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Account Information
        Text(
          'Account Information',
          style: AppTextStyles.h5,
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildInfoRow(
                  'Customer Since',
                  widget.customer['created_at'] ?? 'N/A',
                ),
                const Divider(height: 24),
                _buildInfoRow(
                  'Customer ID',
                  widget.customer['id']?.toString() ?? 'N/A',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Actions
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              // TODO: Delete customer with confirmation
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: const BorderSide(color: AppColors.error),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete Customer'),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            value,
            style: AppTextStyles.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  double _calculateAverageOrder() {
    final totalPurchases = widget.customer['total_purchases'] ?? 0;
    final totalSpent = (widget.customer['total_spent'] ?? 0).toDouble();
    if (totalPurchases == 0) return 0;
    return totalSpent / totalPurchases;
  }
}
