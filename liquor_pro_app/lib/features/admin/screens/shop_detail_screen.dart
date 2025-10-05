import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../models/shop_model.dart';

/// Shop Detail Screen
class ShopDetailScreen extends StatefulWidget {
  final Shop shop;

  const ShopDetailScreen({
    super.key,
    required this.shop,
  });

  @override
  State<ShopDetailScreen> createState() => _ShopDetailScreenState();
}

class _ShopDetailScreenState extends State<ShopDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;
  final Map<String, dynamic> _shopStats = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadShopStats();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadShopStats() async {
    setState(() => _isLoading = true);
    // TODO: Load shop statistics from API
    await Future.delayed(const Duration(seconds: 1));
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Shop Details',
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              // TODO: Navigate to edit shop screen
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Shop Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: widget.shop.isActive
                  ? AppColors.primary.withOpacity(0.1)
                  : AppColors.textSecondary.withOpacity(0.1),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: widget.shop.isActive
                        ? AppColors.primary.withOpacity(0.2)
                        : AppColors.textSecondary.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.store,
                    size: 48,
                    color: widget.shop.isActive
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  widget.shop.name,
                  style: AppTextStyles.h4.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: widget.shop.isActive
                        ? AppColors.success.withOpacity(0.1)
                        : AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    widget.shop.isActive ? 'ACTIVE' : 'INACTIVE',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: widget.shop.isActive
                          ? AppColors.success
                          : AppColors.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
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
                    title: 'Today\'s Sales',
                    value: Formatters.currency(_shopStats['today_sales'] ?? 0),
                    icon: Icons.attach_money,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    title: 'Products',
                    value: '${_shopStats['total_products'] ?? 0}',
                    icon: Icons.inventory,
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
                Tab(text: 'Information'),
                Tab(text: 'Performance'),
                Tab(text: 'Staff'),
              ],
            ),
          ),

          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildInformationTab(),
                _buildPerformanceTab(),
                _buildStaffTab(),
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
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
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
                _buildInfoRow('Phone', widget.shop.phone),
                if (widget.shop.email != null) ...[
                  const Divider(height: 24),
                  _buildInfoRow('Email', widget.shop.email!),
                ],
                const Divider(height: 24),
                _buildInfoRow('Address', widget.shop.address),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // License Information
        Text(
          'License Information',
          style: AppTextStyles.h5,
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildInfoRow('License Number', widget.shop.licenseNumber),
                const Divider(height: 24),
                _buildInfoRow('Issue Date', 'Jan 1, 2024'), // TODO: Add to model
                const Divider(height: 24),
                _buildInfoRow('Expiry Date', 'Dec 31, 2025'), // TODO: Add to model
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Location
        if (widget.shop.latitude != null && widget.shop.longitude != null) ...[
          Text(
            'Location',
            style: AppTextStyles.h5,
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildInfoRow('Latitude', widget.shop.latitude!.toString()),
                  const Divider(height: 24),
                  _buildInfoRow('Longitude', widget.shop.longitude!.toString()),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        // TODO: Open in maps
                      },
                      icon: const Icon(Icons.map),
                      label: const Text('Open in Maps'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),

        // Actions
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              // TODO: Toggle shop status
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: widget.shop.isActive
                  ? AppColors.error
                  : AppColors.success,
              side: BorderSide(
                color: widget.shop.isActive
                    ? AppColors.error
                    : AppColors.success,
              ),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            icon: Icon(widget.shop.isActive ? Icons.block : Icons.check_circle),
            label: Text(widget.shop.isActive ? 'Deactivate Shop' : 'Activate Shop'),
          ),
        ),
      ],
    );
  }

  Widget _buildPerformanceTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Sales Performance
        Text(
          'Sales Performance',
          style: AppTextStyles.h5,
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildStatRow('Today', Formatters.currency(0)),
                const Divider(height: 24),
                _buildStatRow('This Week', Formatters.currency(0)),
                const Divider(height: 24),
                _buildStatRow('This Month', Formatters.currency(0)),
                const Divider(height: 24),
                _buildStatRow('Total (All Time)', Formatters.currency(0)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Inventory
        Text(
          'Inventory Status',
          style: AppTextStyles.h5,
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildStatRow('Total Products', '0'),
                const Divider(height: 24),
                _buildStatRow('In Stock', '0'),
                const Divider(height: 24),
                _buildStatRow('Low Stock', '0'),
                const Divider(height: 24),
                _buildStatRow('Out of Stock', '0'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Transactions
        Text(
          'Transactions',
          style: AppTextStyles.h5,
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildStatRow('Total Transactions', '0'),
                const Divider(height: 24),
                _buildStatRow('Average Transaction', Formatters.currency(0)),
                const Divider(height: 24),
                _buildStatRow('Returns', '0'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStaffTab() {
    final List<Map<String, dynamic>> staff = [
      // TODO: Load from API
    ];

    if (staff.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 80,
              color: AppColors.primary.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No Staff Assigned',
              style: AppTextStyles.h5,
            ),
            const SizedBox(height: 8),
            Text(
              'Assign staff members to this shop',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                // TODO: Navigate to assign staff
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.person_add),
              label: const Text('Assign Staff'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: staff.length,
      itemBuilder: (context, index) {
        final member = staff[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.primary.withOpacity(0.1),
              child: Text(
                member['name'][0].toUpperCase(),
                style: AppTextStyles.h5.copyWith(
                  color: AppColors.primary,
                ),
              ),
            ),
            title: Text(
              member['name'],
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              member['role'],
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () {
                // TODO: Show staff options
              },
            ),
          ),
        );
      },
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

  Widget _buildStatRow(String label, String value) {
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
}
