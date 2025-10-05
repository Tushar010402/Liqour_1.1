import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

class DiscountsScreen extends StatefulWidget {
  const DiscountsScreen({super.key});

  @override
  State<DiscountsScreen> createState() => _DiscountsScreenState();
}

class _DiscountsScreenState extends State<DiscountsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedStatus = 'All';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGray,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildHeader(),
          _buildFilterRow(),
          Expanded(child: _buildDiscountsList()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateDiscountDialog(),
        backgroundColor: AppColors.primaryRed,
        child: const Icon(Icons.add, color: AppColors.white),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text('Discount Management'),
      backgroundColor: AppColors.white,
      elevation: 0,
      foregroundColor: AppColors.primaryBlack,
      actions: [
        IconButton(
          icon: const Icon(Icons.analytics),
          onPressed: () => _showDiscountAnalytics(),
          tooltip: 'Analytics',
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => _refreshDiscounts(),
          tooltip: 'Refresh',
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: AppColors.white,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() {});
              },
              decoration: InputDecoration(
                hintText: 'Search discounts...',
                prefixIcon:
                    const Icon(Icons.search, color: AppColors.mediumGray),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.borderGray),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.borderGray),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.primaryRed),
                ),
                filled: true,
                fillColor: AppColors.lightGray,
              ),
            ),
          ),
          const SizedBox(width: 16),
          ElevatedButton.icon(
            onPressed: () => _showCreateDiscountDialog(),
            icon: const Icon(Icons.add),
            label: const Text('Create Discount'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryRed,
              foregroundColor: AppColors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.white,
      child: Row(
        children: [
          _buildStatusFilter(),
          const Spacer(),
          const Text(
            'Total: 12 discounts | Active: 8 | Expired: 4',
            style: TextStyle(
              color: AppColors.mediumGray,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusFilter() {
    return DropdownButton<String>(
      value: _selectedStatus,
      onChanged: (value) {
        setState(() {
          _selectedStatus = value!;
        });
      },
      items: ['All', 'Active', 'Expired', 'Scheduled'].map((String status) {
        return DropdownMenuItem<String>(
          value: status,
          child: Text(
            status,
            style: const TextStyle(fontSize: 14),
          ),
        );
      }).toList(),
      underline: Container(),
    );
  }

  Widget _buildDiscountsList() {
    final discounts = _getDiscountData();

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: discounts.length,
      itemBuilder: (context, index) {
        final discount = discounts[index];
        return _buildDiscountCard(discount);
      },
    );
  }

  Widget _buildDiscountCard(Map<String, dynamic> discount) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: _getDiscountColor(discount['type'])
                          .withValues(alpha: 0.1),
                    ),
                    child: Icon(
                      _getDiscountIcon(discount['type']),
                      color: _getDiscountColor(discount['type']),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                discount['name'],
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: AppColors.primaryBlack,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _getStatusColor(discount['status'])
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                discount['status'],
                                style: TextStyle(
                                  color: _getStatusColor(discount['status']),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          discount['description'],
                          style: const TextStyle(
                            color: AppColors.mediumGray,
                            fontSize: 14,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (action) =>
                        _handleDiscountAction(action, discount),
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 18),
                            SizedBox(width: 8),
                            Text('Edit'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'duplicate',
                        child: Row(
                          children: [
                            Icon(Icons.copy, size: 18),
                            SizedBox(width: 8),
                            Text('Duplicate'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete,
                                size: 18, color: AppColors.error),
                            SizedBox(width: 8),
                            Text('Delete',
                                style: TextStyle(color: AppColors.error)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.lightGray,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _buildDiscountInfo('Type', discount['type']),
                        _buildDiscountInfo('Value', discount['value']),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildDiscountInfo('Valid From', discount['startDate']),
                        _buildDiscountInfo('Valid To', discount['endDate']),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDiscountInfo(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.mediumGray,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.primaryBlack,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _getDiscountData() {
    return [
      {
        'name': 'New Year Special',
        'description': '50% discount on all Enterprise plans',
        'type': 'Percentage',
        'value': '50%',
        'status': 'Active',
        'startDate': '01/01/2024',
        'endDate': '31/01/2024',
      },
      {
        'name': 'Startup Discount',
        'description': 'Fixed discount for new startups',
        'type': 'Fixed Amount',
        'value': '\$100',
        'status': 'Active',
        'startDate': '15/12/2023',
        'endDate': '15/03/2024',
      },
      {
        'name': 'Black Friday',
        'description': 'Limited time offer for all plans',
        'type': 'Percentage',
        'value': '30%',
        'status': 'Expired',
        'startDate': '24/11/2023',
        'endDate': '27/11/2023',
      },
      {
        'name': 'Volume Discount',
        'description': 'Bulk subscription discount',
        'type': 'Tiered',
        'value': '10-25%',
        'status': 'Active',
        'startDate': '01/10/2023',
        'endDate': '31/12/2024',
      },
    ];
  }

  IconData _getDiscountIcon(String type) {
    switch (type) {
      case 'Percentage':
        return Icons.percent;
      case 'Fixed Amount':
        return Icons.attach_money;
      case 'Tiered':
        return Icons.stairs;
      default:
        return Icons.local_offer;
    }
  }

  Color _getDiscountColor(String type) {
    switch (type) {
      case 'Percentage':
        return AppColors.success;
      case 'Fixed Amount':
        return AppColors.primaryBlue;
      case 'Tiered':
        return AppColors.warning;
      default:
        return AppColors.primaryRed;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Active':
        return AppColors.success;
      case 'Expired':
        return AppColors.error;
      case 'Scheduled':
        return AppColors.warning;
      default:
        return AppColors.mediumGray;
    }
  }

  void _handleDiscountAction(String action, Map<String, dynamic> discount) {
    switch (action) {
      case 'edit':
        _showEditDiscountDialog(discount);
        break;
      case 'duplicate':
        _duplicateDiscount(discount);
        break;
      case 'delete':
        _showDeleteConfirmation(discount);
        break;
    }
  }

  void _showCreateDiscountDialog() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Create discount functionality will be implemented'),
      ),
    );
  }

  void _showEditDiscountDialog(Map<String, dynamic> discount) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text('Edit ${discount['name']} functionality will be implemented'),
      ),
    );
  }

  void _duplicateDiscount(Map<String, dynamic> discount) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${discount['name']} duplicated successfully'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  void _showDeleteConfirmation(Map<String, dynamic> discount) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning, color: AppColors.error),
            SizedBox(width: 12),
            Text('Delete Discount'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${discount['name']}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${discount['name']} deleted successfully'),
                  backgroundColor: AppColors.success,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showDiscountAnalytics() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Discount analytics will be implemented'),
      ),
    );
  }

  void _refreshDiscounts() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Discounts refreshed'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
