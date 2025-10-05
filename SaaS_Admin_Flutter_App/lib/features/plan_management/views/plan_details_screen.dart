import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../controllers/plan_provider.dart';
import '../../../core/models/plan_model.dart';

class PlanDetailsScreen extends StatefulWidget {
  final String planId;

  const PlanDetailsScreen({super.key, required this.planId});

  @override
  State<PlanDetailsScreen> createState() => _PlanDetailsScreenState();
}

class _PlanDetailsScreenState extends State<PlanDetailsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  PlanModel? _plan;
  List<String> _features = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadPlanDetails();
  }

  void _loadPlanDetails() {
    final planProvider = context.read<PlanProvider>();
    _plan = planProvider.getPlanById(widget.planId);

    if (_plan != null) {
      _loadPlanFeatures();
    }
  }

  void _loadPlanFeatures() async {
    final planProvider = context.read<PlanProvider>();
    final features = await planProvider.getPlanFeatures(widget.planId);
    setState(() {
      _features = features;
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_plan == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Plan Details'),
        ),
        body: const Center(
          child: Text('Plan not found'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.lightGray,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            _buildSliverAppBar(),
            _buildPlanHeader(),
            _buildTabBar(),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildOverviewTab(),
            _buildBillingTab(),
            _buildFeaturesTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 0,
      floating: false,
      pinned: true,
      title: Text(_plan!.displayName),
      actions: [
        PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'edit':
                _handleEditPlan();
                break;
              case 'delete':
                _handleDeletePlan();
                break;
              case 'duplicate':
                _handleDuplicatePlan();
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit_outlined),
                  SizedBox(width: 12),
                  Text('Edit Plan'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'duplicate',
              child: Row(
                children: [
                  Icon(Icons.copy_outlined),
                  SizedBox(width: 12),
                  Text('Duplicate Plan'),
                ],
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete_outline, color: AppColors.error),
                  SizedBox(width: 12),
                  Text('Delete Plan', style: TextStyle(color: AppColors.error)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPlanHeader() {
    return SliverToBoxAdapter(
      child: Container(
        color: AppColors.white,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Plan Name and Tags
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _plan!.displayName,
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _plan!.description,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: AppColors.mediumGray,
                            ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _plan!.formattedPrice,
                      style:
                          Theme.of(context).textTheme.headlineLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryRed,
                              ),
                    ),
                    Text(
                      '/${_plan!.billingCycle}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.mediumGray,
                          ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Tags
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_plan!.popular) _buildTag('POPULAR', AppColors.warning),
                if (_plan!.enterprise)
                  _buildTag('ENTERPRISE', AppColors.primaryRed),
                if (_plan!.active)
                  _buildTag('ACTIVE', AppColors.success)
                else
                  _buildTag('INACTIVE', AppColors.mediumGray),
                _buildTag(_plan!.billingCycle.toUpperCase(), AppColors.info),
              ],
            ),

            const SizedBox(height: 24),

            // Quick Stats
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Trial Days',
                    _plan!.trialDays.toString(),
                    Icons.schedule_outlined,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    'Max Users',
                    _plan!.maxUsersText,
                    Icons.people_outline,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    'Max Locations',
                    _plan!.maxLocationsText,
                    Icons.location_on_outlined,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return SliverToBoxAdapter(
      child: Container(
        color: AppColors.white,
        child: TabBar(
          controller: _tabController,
          labelColor: AppColors.primaryRed,
          unselectedLabelColor: AppColors.mediumGray,
          indicatorColor: AppColors.primaryRed,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Billing'),
            Tab(text: 'Features'),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Basic Information
          _buildSectionCard(
            title: 'Basic Information',
            children: [
              _buildInfoRow('Plan ID', _plan!.id),
              _buildInfoRow('Internal Name', _plan!.name),
              _buildInfoRow('Display Name', _plan!.displayName),
              _buildInfoRow('Description', _plan!.description),
              _buildInfoRow('Currency', _plan!.currency),
              _buildInfoRow('Sort Order', _plan!.sortOrder.toString()),
            ],
          ),

          const SizedBox(height: 16),

          // Limits & Quotas
          _buildSectionCard(
            title: 'Limits & Quotas',
            children: [
              _buildInfoRow('Max Users', _plan!.maxUsersText),
              _buildInfoRow('Max Locations', _plan!.maxLocationsText),
              _buildInfoRow('Max Products', _plan!.maxProductsText),
              _buildInfoRow('Trial Period', '${_plan!.trialDays} days'),
            ],
          ),

          const SizedBox(height: 16),

          // Discounts
          _buildSectionCard(
            title: 'Discount Configuration',
            children: [
              _buildInfoRow('Yearly Discount', '${_plan!.yearlyDiscount}%'),
              if (_plan!.twoYearDiscount != null)
                _buildInfoRow('2-Year Discount', '${_plan!.twoYearDiscount}%'),
              if (_plan!.threeYearDiscount != null)
                _buildInfoRow(
                    '3-Year Discount', '${_plan!.threeYearDiscount}%'),
            ],
          ),

          const SizedBox(height: 16),

          // Integration
          _buildSectionCard(
            title: 'Integration',
            children: [
              _buildInfoRow(
                  'Razorpay Plan ID', _plan!.razorpayPlanId ?? 'Not set'),
              _buildInfoRow('Auto Create Variants',
                  _plan!.autoCreateVariants ? 'Yes' : 'No'),
              _buildInfoRow(
                  'Billing Term (Months)', _plan!.billingTermMonths.toString()),
            ],
          ),

          const SizedBox(height: 16),

          // Timestamps
          _buildSectionCard(
            title: 'Timestamps',
            children: [
              _buildInfoRow('Created At', _formatDateTime(_plan!.createdAt)),
              _buildInfoRow('Updated At', _formatDateTime(_plan!.updatedAt)),
              if (_plan!.deletedAt != null)
                _buildInfoRow('Deleted At', _formatDateTime(_plan!.deletedAt!)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBillingTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pricing Information
          _buildSectionCard(
            title: 'Pricing Information',
            children: [
              _buildInfoRow('Base Price', _plan!.formattedPrice),
              _buildInfoRow('Currency', _plan!.currency),
              _buildInfoRow('Billing Cycle', _plan!.billingCycle),
            ],
          ),

          const SizedBox(height: 16),

          // Discount Structure
          _buildSectionCard(
            title: 'Discount Structure',
            children: [
              _buildDiscountRow('Monthly', 0, _plan!.price),
              _buildDiscountRow(
                  'Yearly', _plan!.yearlyDiscount, _plan!.price * 12),
              if (_plan!.twoYearDiscount != null)
                _buildDiscountRow(
                    '2-Year', _plan!.twoYearDiscount!, _plan!.price * 24),
              if (_plan!.threeYearDiscount != null)
                _buildDiscountRow(
                    '3-Year', _plan!.threeYearDiscount!, _plan!.price * 36),
            ],
          ),

          const SizedBox(height: 16),

          // Payment Gateway Integration
          _buildSectionCard(
            title: 'Payment Gateway',
            children: [
              _buildInfoRow('Razorpay Plan ID',
                  _plan!.razorpayPlanId ?? 'Not configured'),
              _buildInfoRow('Auto Create Variants',
                  _plan!.autoCreateVariants ? 'Enabled' : 'Disabled'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturesTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Core Features
          if (_plan!.features.isNotEmpty)
            _buildSectionCard(
              title: 'Core Features',
              children: _plan!.features.map((feature) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle,
                        color: AppColors.success,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          feature.replaceAll('_', ' ').toUpperCase(),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),

          const SizedBox(height: 16),

          // AI Features
          if (_plan!.aiFeatures != null && _plan!.aiFeatures!.isNotEmpty)
            _buildSectionCard(
              title: 'AI Features',
              children: _plan!.aiFeatures!.map((feature) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.smart_toy,
                        color: AppColors.info,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          feature.replaceAll('_', ' ').toUpperCase(),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),

          const SizedBox(height: 16),

          // Additional Features (from API)
          if (_features.isNotEmpty)
            _buildSectionCard(
              title: 'Additional Features',
              children: _features.map((feature) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.star,
                        color: AppColors.warning,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          feature,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.white,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightGray,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderGray),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.primaryRed, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          Text(
            title,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.mediumGray,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.mediumGray,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.primaryBlack,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscountRow(String term, double discount, double basePrice) {
    final discountedPrice = basePrice * (1 - discount / 100);
    final savings = basePrice - discountedPrice;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              term,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '₹${discountedPrice.toStringAsFixed(0)}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    if (discount > 0) ...[
                      const SizedBox(width: 8),
                      Text(
                        '₹${basePrice.toStringAsFixed(0)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.mediumGray,
                              decoration: TextDecoration.lineThrough,
                            ),
                      ),
                    ],
                  ],
                ),
                if (discount > 0)
                  Text(
                    'Save ₹${savings.toStringAsFixed(0)} (${discount}% off)',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.success,
                        ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  void _handleEditPlan() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Edit plan feature coming soon'),
        backgroundColor: AppColors.info,
      ),
    );
  }

  void _handleDeletePlan() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Plan'),
        content: Text(
            'Are you sure you want to delete "${_plan!.displayName}"? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _confirmDeletePlan();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _confirmDeletePlan() async {
    final planProvider = context.read<PlanProvider>();
    final success = await planProvider.deletePlan(_plan!.id);

    if (success && mounted) {
      context.pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Plan deleted successfully'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  void _handleDuplicatePlan() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Duplicate plan feature coming soon'),
        backgroundColor: AppColors.info,
      ),
    );
  }
}
