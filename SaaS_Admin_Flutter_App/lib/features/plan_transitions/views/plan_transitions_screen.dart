import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

class PlanTransitionsScreen extends StatefulWidget {
  const PlanTransitionsScreen({super.key});

  @override
  State<PlanTransitionsScreen> createState() => _PlanTransitionsScreenState();
}

class _PlanTransitionsScreenState extends State<PlanTransitionsScreen> {
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
          Expanded(child: _buildTransitionsList()),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text('Plan Transitions'),
      backgroundColor: AppColors.white,
      elevation: 0,
      foregroundColor: AppColors.primaryBlack,
      actions: [
        IconButton(
          icon: const Icon(Icons.analytics),
          onPressed: () => _showTransitionAnalytics(),
          tooltip: 'Analytics',
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => _refreshTransitions(),
          tooltip: 'Refresh',
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: AppColors.white,
      child: TextField(
        controller: _searchController,
        onChanged: (value) {
          setState(() {});
        },
        decoration: InputDecoration(
          hintText: 'Search transitions...',
          prefixIcon: const Icon(Icons.search, color: AppColors.mediumGray),
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
    );
  }

  Widget _buildFilterRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.white,
      child: Row(
        children: [
          DropdownButton<String>(
            value: _selectedStatus,
            onChanged: (value) {
              setState(() {
                _selectedStatus = value!;
              });
            },
            items:
                ['All', 'Completed', 'Pending', 'Failed'].map((String status) {
              return DropdownMenuItem<String>(
                value: status,
                child: Text(status),
              );
            }).toList(),
            underline: Container(),
          ),
          const Spacer(),
          const Text(
            'Total: 28 transitions | Completed: 25 | Pending: 2 | Failed: 1',
            style: TextStyle(
              color: AppColors.mediumGray,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransitionsList() {
    final transitions = _getTransitionData();

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: transitions.length,
      itemBuilder: (context, index) {
        final transition = transitions[index];
        return _buildTransitionCard(transition);
      },
    );
  }

  Widget _buildTransitionCard(Map<String, dynamic> transition) {
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
                      color: _getStatusColor(transition['status'])
                          .withValues(alpha: 0.1),
                    ),
                    child: Icon(
                      Icons.swap_horiz,
                      color: _getStatusColor(transition['status']),
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
                                transition['tenant'],
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
                                color: _getStatusColor(transition['status'])
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                transition['status'],
                                style: TextStyle(
                                  color: _getStatusColor(transition['status']),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${transition['fromPlan']} → ${transition['toPlan']}',
                          style: const TextStyle(
                            color: AppColors.mediumGray,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (transition['status'] == 'Pending')
                    PopupMenuButton<String>(
                      onSelected: (action) =>
                          _handleTransitionAction(action, transition),
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'approve',
                          child: Row(
                            children: [
                              Icon(Icons.check,
                                  size: 18, color: AppColors.success),
                              SizedBox(width: 8),
                              Text('Approve'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'reject',
                          child: Row(
                            children: [
                              Icon(Icons.close,
                                  size: 18, color: AppColors.error),
                              SizedBox(width: 8),
                              Text('Reject'),
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
                        _buildTransitionInfo('Date', transition['date']),
                        _buildTransitionInfo('Reason', transition['reason']),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildTransitionInfo(
                            'Processing Time', transition['processingTime']),
                        _buildTransitionInfo(
                            'Revenue Impact', transition['revenueImpact']),
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

  Widget _buildTransitionInfo(String label, String value) {
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

  List<Map<String, dynamic>> _getTransitionData() {
    return [
      {
        'tenant': 'TechCorp Solutions',
        'fromPlan': 'Professional',
        'toPlan': 'Enterprise',
        'status': 'Completed',
        'date': '15/01/2024',
        'reason': 'Upgrade',
        'processingTime': '2 hours',
        'revenueImpact': '+\$150/mo',
      },
      {
        'tenant': 'StartupXYZ',
        'fromPlan': 'Starter',
        'toPlan': 'Professional',
        'status': 'Pending',
        'date': '20/01/2024',
        'reason': 'Feature Requirements',
        'processingTime': 'Pending',
        'revenueImpact': '+\$50/mo',
      },
      {
        'tenant': 'LocalBiz Inc',
        'fromPlan': 'Enterprise',
        'toPlan': 'Professional',
        'status': 'Completed',
        'date': '18/01/2024',
        'reason': 'Downgrade',
        'processingTime': '1 hour',
        'revenueImpact': '-\$100/mo',
      },
    ];
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Completed':
        return AppColors.success;
      case 'Pending':
        return AppColors.warning;
      case 'Failed':
        return AppColors.error;
      default:
        return AppColors.mediumGray;
    }
  }

  void _handleTransitionAction(String action, Map<String, dynamic> transition) {
    switch (action) {
      case 'approve':
        _approveTransition(transition);
        break;
      case 'reject':
        _rejectTransition(transition);
        break;
    }
  }

  void _approveTransition(Map<String, dynamic> transition) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${transition['tenant']} transition approved'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  void _rejectTransition(Map<String, dynamic> transition) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${transition['tenant']} transition rejected'),
        backgroundColor: AppColors.error,
      ),
    );
  }

  void _showTransitionAnalytics() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Transition analytics will be implemented'),
      ),
    );
  }

  void _refreshTransitions() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Transitions refreshed'),
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
