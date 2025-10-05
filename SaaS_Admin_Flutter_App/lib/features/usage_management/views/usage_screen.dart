import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

class UsageScreen extends StatefulWidget {
  const UsageScreen({super.key});

  @override
  State<UsageScreen> createState() => _UsageScreenState();
}

class _UsageScreenState extends State<UsageScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedPeriod = 'This Month';
  String _selectedTenant = 'All Tenants';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGray,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildHeader(),
          _buildFilterRow(),
          Expanded(child: _buildUsageContent()),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text('Usage Management'),
      backgroundColor: AppColors.white,
      elevation: 0,
      foregroundColor: AppColors.primaryBlack,
      actions: [
        IconButton(
          icon: const Icon(Icons.download),
          onPressed: () => _exportUsageData(),
          tooltip: 'Export Usage Data',
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => _refreshUsageData(),
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
                hintText: 'Search tenants...',
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
            onPressed: () => _showUsageReportDialog(),
            icon: const Icon(Icons.analytics),
            label: const Text('Generate Report'),
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
          _buildFilterDropdown(
            label: 'Period',
            value: _selectedPeriod,
            items: [
              'This Month',
              'Last Month',
              'Last 3 Months',
              'Last 6 Months',
              'This Year'
            ],
            onChanged: (value) {
              setState(() {
                _selectedPeriod = value!;
              });
            },
          ),
          const SizedBox(width: 16),
          _buildFilterDropdown(
            label: 'Tenant',
            value: _selectedTenant,
            items: [
              'All Tenants',
              'Active Only',
              'Premium Plans',
              'Trial Users'
            ],
            onChanged: (value) {
              setState(() {
                _selectedTenant = value!;
              });
            },
          ),
          const Spacer(),
          Text(
            'Total Usage: 15,420 API calls',
            style: const TextStyle(
              color: AppColors.mediumGray,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.mediumGray,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        DropdownButton<String>(
          value: value,
          onChanged: onChanged,
          items: items.map((String item) {
            return DropdownMenuItem<String>(
              value: item,
              child: Text(
                item,
                style: const TextStyle(fontSize: 14),
              ),
            );
          }).toList(),
          underline: Container(),
          isDense: true,
        ),
      ],
    );
  }

  Widget _buildUsageContent() {
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 16),
          _buildUsageOverview(),
          const SizedBox(height: 16),
          _buildTopUsersSection(),
          const SizedBox(height: 16),
          _buildUsageChartSection(),
          const SizedBox(height: 16),
          _buildDetailedUsageList(),
        ],
      ),
    );
  }

  Widget _buildUsageOverview() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
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
          const Text(
            'Usage Overview',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: AppColors.primaryBlack,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                  child: _buildOverviewCard('Total API Calls', '15,420',
                      Icons.api, AppColors.primaryRed)),
              const SizedBox(width: 12),
              Expanded(
                  child: _buildOverviewCard(
                      'Active Users', '247', Icons.people, AppColors.success)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: _buildOverviewCard('Data Transfer', '2.3 GB',
                      Icons.cloud_download, AppColors.primaryBlue)),
              const SizedBox(width: 12),
              Expanded(
                  child: _buildOverviewCard('Error Rate', '0.02%',
                      Icons.error_outline, AppColors.warning)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewCard(
      String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: AppColors.primaryBlack,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopUsersSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
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
          Row(
            children: [
              const Text(
                'Top Users',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: AppColors.primaryBlack,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => _showAllUsers(),
                child: const Text('View All'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ..._buildTopUsersList(),
        ],
      ),
    );
  }

  List<Widget> _buildTopUsersList() {
    final topUsers = [
      {'name': 'TechCorp Solutions', 'usage': '3,420', 'plan': 'Enterprise'},
      {'name': 'StartupXYZ', 'usage': '2,150', 'plan': 'Professional'},
      {'name': 'LocalBiz Inc', 'usage': '1,890', 'plan': 'Professional'},
      {'name': 'MegaRetail', 'usage': '1,675', 'plan': 'Enterprise'},
      {'name': 'SmallShop', 'usage': '945', 'plan': 'Starter'},
    ];

    return topUsers
        .map((user) => _buildUserUsageCard(
              user['name']!,
              user['usage']!,
              user['plan']!,
            ))
        .toList();
  }

  Widget _buildUserUsageCard(String name, String usage, String plan) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.lightGray,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: AppColors.primaryRed.withValues(alpha: 0.1),
            ),
            child: const Icon(
              Icons.business,
              color: AppColors.primaryRed,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppColors.primaryBlack,
                  ),
                ),
                Text(
                  '$usage API calls • $plan Plan',
                  style: const TextStyle(
                    color: AppColors.mediumGray,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              plan,
              style: const TextStyle(
                color: AppColors.success,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsageChartSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
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
          const Text(
            'Usage Trends',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: AppColors.primaryBlack,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: AppColors.lightGray,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.show_chart,
                    size: 48,
                    color: AppColors.mediumGray,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Usage Chart',
                    style: TextStyle(
                      color: AppColors.mediumGray,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    'Chart visualization will be implemented',
                    style: TextStyle(
                      color: AppColors.mediumGray,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedUsageList() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
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
          Row(
            children: [
              const Text(
                'Detailed Usage',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: AppColors.primaryBlack,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.filter_list),
                onPressed: () => _showFilterDialog(),
                tooltip: 'Filter',
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildUsageTable(),
        ],
      ),
    );
  }

  Widget _buildUsageTable() {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(2),
        1: FlexColumnWidth(1),
        2: FlexColumnWidth(1),
        3: FlexColumnWidth(1),
      },
      children: [
        _buildTableHeader(),
        ..._buildTableRows(),
      ],
    );
  }

  TableRow _buildTableHeader() {
    return TableRow(
      decoration: BoxDecoration(
        color: AppColors.lightGray,
        borderRadius: BorderRadius.circular(8),
      ),
      children: [
        _buildTableHeaderCell('Tenant'),
        _buildTableHeaderCell('API Calls'),
        _buildTableHeaderCell('Data'),
        _buildTableHeaderCell('Plan'),
      ],
    );
  }

  Widget _buildTableHeaderCell(String text) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 12,
          color: AppColors.primaryBlack,
        ),
      ),
    );
  }

  List<TableRow> _buildTableRows() {
    final usageData = [
      {
        'tenant': 'TechCorp Solutions',
        'calls': '3,420',
        'data': '850MB',
        'plan': 'Enterprise'
      },
      {
        'tenant': 'StartupXYZ',
        'calls': '2,150',
        'data': '520MB',
        'plan': 'Professional'
      },
      {
        'tenant': 'LocalBiz Inc',
        'calls': '1,890',
        'data': '445MB',
        'plan': 'Professional'
      },
      {
        'tenant': 'MegaRetail',
        'calls': '1,675',
        'data': '398MB',
        'plan': 'Enterprise'
      },
      {
        'tenant': 'SmallShop',
        'calls': '945',
        'data': '230MB',
        'plan': 'Starter'
      },
    ];

    return usageData
        .map((data) => TableRow(
              children: [
                _buildTableCell(data['tenant']!),
                _buildTableCell(data['calls']!),
                _buildTableCell(data['data']!),
                _buildPlanCell(data['plan']!),
              ],
            ))
        .toList();
  }

  Widget _buildTableCell(String text) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          color: AppColors.primaryBlack,
        ),
      ),
    );
  }

  Widget _buildPlanCell(String plan) {
    Color color;
    switch (plan) {
      case 'Enterprise':
        color = AppColors.primaryRed;
        break;
      case 'Professional':
        color = AppColors.primaryBlue;
        break;
      case 'Starter':
        color = AppColors.success;
        break;
      default:
        color = AppColors.mediumGray;
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          plan,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  void _exportUsageData() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Export functionality will be implemented'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  void _refreshUsageData() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Usage data refreshed'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  void _showUsageReportDialog() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Generate report functionality will be implemented'),
      ),
    );
  }

  void _showAllUsers() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('All users view will be implemented'),
      ),
    );
  }

  void _showFilterDialog() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Filter dialog will be implemented'),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
