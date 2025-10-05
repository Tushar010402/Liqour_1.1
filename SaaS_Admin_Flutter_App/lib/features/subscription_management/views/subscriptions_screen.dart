import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/subscription_provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/subscription_model.dart';

class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedFilter = 'All';
  String _selectedPlanFilter = 'All';
  String _sortBy = 'name';
  bool _sortAscending = true;
  bool _isSelectionMode = false;
  List<String> _selectedSubscriptionIds = [];
  List<SubscriptionModel> _filteredSubscriptions = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SubscriptionProvider>().loadSubscriptionAnalytics();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterSubscriptions(SubscriptionProvider provider) {
    List<SubscriptionModel> subscriptions = provider.subscriptions;

    // Apply search filter
    if (_searchController.text.isNotEmpty) {
      subscriptions = provider.searchSubscriptions(_searchController.text);
    }

    // Apply status filter
    if (_selectedFilter != 'All') {
      subscriptions = subscriptions
          .where((subscription) =>
              subscription.status.toLowerCase() ==
              _selectedFilter.toLowerCase())
          .toList();
    }

    // Apply plan filter
    if (_selectedPlanFilter != 'All') {
      subscriptions = subscriptions
          .where((subscription) => subscription.planName
              .toLowerCase()
              .contains(_selectedPlanFilter.toLowerCase()))
          .toList();
    }

    // Apply sorting
    subscriptions.sort((a, b) {
      int result = 0;
      switch (_sortBy) {
        case 'name':
          result = a.tenantName.compareTo(b.tenantName);
          break;
        case 'plan':
          result = a.planName.compareTo(b.planName);
          break;
        case 'amount':
          result = a.amount.compareTo(b.amount);
          break;
        case 'status':
          result = a.status.compareTo(b.status);
          break;
        case 'created':
          result = a.createdAt.compareTo(b.createdAt);
          break;
      }
      return _sortAscending ? result : -result;
    });

    setState(() {
      _filteredSubscriptions = subscriptions;
    });
  }

  void _toggleSelection(String subscriptionId) {
    setState(() {
      if (_selectedSubscriptionIds.contains(subscriptionId)) {
        _selectedSubscriptionIds.remove(subscriptionId);
      } else {
        _selectedSubscriptionIds.add(subscriptionId);
      }
      _isSelectionMode = _selectedSubscriptionIds.isNotEmpty;
    });
  }

  void _selectAll() {
    setState(() {
      if (_selectedSubscriptionIds.length == _filteredSubscriptions.length) {
        _selectedSubscriptionIds.clear();
        _isSelectionMode = false;
      } else {
        _selectedSubscriptionIds =
            _filteredSubscriptions.map((s) => s.id).toList();
        _isSelectionMode = true;
      }
    });
  }

  void _showBulkActionsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title:
            Text('Bulk Actions (${_selectedSubscriptionIds.length} selected)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.pause, color: Colors.orange),
              title: const Text('Pause Selected'),
              onTap: () {
                Navigator.pop(context);
                _performBulkAction('pause');
              },
            ),
            ListTile(
              leading: const Icon(Icons.play_arrow, color: Colors.green),
              title: const Text('Resume Selected'),
              onTap: () {
                Navigator.pop(context);
                _performBulkAction('resume');
              },
            ),
            ListTile(
              leading: const Icon(Icons.cancel, color: Colors.red),
              title: const Text('Cancel Selected'),
              onTap: () {
                Navigator.pop(context);
                _performBulkAction('cancel');
              },
            ),
            ListTile(
              leading: const Icon(Icons.email, color: Colors.blue),
              title: const Text('Send Email'),
              onTap: () {
                Navigator.pop(context);
                _performBulkAction('email');
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _performBulkAction(String action) {
    // Mock implementation - replace with actual API calls
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            '$action performed on ${_selectedSubscriptionIds.length} subscriptions'),
        backgroundColor: Colors.green,
      ),
    );
    setState(() {
      _selectedSubscriptionIds.clear();
      _isSelectionMode = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGray,
      body: Consumer<SubscriptionProvider>(
        builder: (context, provider, child) {
          // Update filtered subscriptions when data changes
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _filterSubscriptions(provider);
          });

          if (provider.isLoading) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primaryRed),
            );
          }

          if (provider.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: AppColors.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Error loading subscription data',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    provider.errorMessage ?? 'Unknown error occurred',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.mediumGray,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => provider.loadSubscriptionAnalytics(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryRed,
                      foregroundColor: AppColors.white,
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header and Analytics Cards
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Subscription Management',
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryBlack,
                                ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () => provider.refresh(),
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Refresh'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryRed,
                            foregroundColor: AppColors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Analytics Cards
                    if (provider.analytics != null)
                      _buildAnalyticsCards(provider.analytics!),

                    const SizedBox(height: 24),

                    // Search and Filter
                    _buildSearchAndFilter(),
                  ],
                ),
              ),

              // Subscriptions List
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryBlack.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: _buildSubscriptionsList(),
                ),
              ),

              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAnalyticsCards(SubscriptionAnalytics analytics) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 800;
        final cardSpacing = isNarrow ? 8.0 : 16.0;

        return Column(
          children: [
            // First Row - Main Stats
            Row(
              children: [
                Expanded(
                  child: _buildAnalyticsCard(
                    'Total Subscriptions',
                    analytics.totalSubscriptions.toString(),
                    Icons.subscriptions_outlined,
                    AppColors.primaryRed,
                    isCompact: isNarrow,
                  ),
                ),
                SizedBox(width: cardSpacing),
                Expanded(
                  child: _buildAnalyticsCard(
                    'Active Subscriptions',
                    analytics.activeSubscriptions.toString(),
                    Icons.check_circle_outline,
                    Colors.green,
                    isCompact: isNarrow,
                  ),
                ),
                SizedBox(width: cardSpacing),
                Expanded(
                  child: _buildAnalyticsCard(
                    'Average Value',
                    '\$${analytics.averageSubscriptionValue.toStringAsFixed(2)}',
                    Icons.monetization_on_outlined,
                    Colors.blue,
                    isCompact: isNarrow,
                  ),
                ),
                SizedBox(width: cardSpacing),
                Expanded(
                  child: _buildAnalyticsCard(
                    'Trial Conversion',
                    '${analytics.conversionRates['trial_to_active']?.toStringAsFixed(1) ?? '0'}%',
                    Icons.trending_up_outlined,
                    Colors.orange,
                    isCompact: isNarrow,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  Widget _buildAnalyticsCard(
      String title, String value, IconData icon, Color color,
      {bool isCompact = false}) {
    return Container(
      padding: EdgeInsets.all(isCompact ? 12 : 20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlack.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: isCompact ? 16 : 20),
              SizedBox(width: isCompact ? 4 : 8),
              Expanded(
                child: Text(
                  value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryBlack,
                        fontSize: isCompact ? 14 : 16,
                      ),
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          SizedBox(height: isCompact ? 4 : 8),
          Text(
            title,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.mediumGray,
                  fontSize: isCompact ? 11 : 12,
                ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilter() {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return Column(
            children: [
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search subscriptions...',
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
                  fillColor: AppColors.white,
                  filled: true,
                ),
                onChanged: (value) {
                  _filterSubscriptions(context.read<SubscriptionProvider>());
                },
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.borderGray),
                  borderRadius: BorderRadius.circular(8),
                  color: AppColors.white,
                ),
                child: DropdownButton<String>(
                  value: _selectedFilter,
                  underline: Container(),
                  isExpanded: true,
                  items: ['All', 'Active', 'Trial', 'Cancelled', 'Paused']
                      .map((filter) => DropdownMenuItem(
                            value: filter,
                            child: Text(filter),
                          ))
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedFilter = value ?? 'All';
                    });
                    _filterSubscriptions(context.read<SubscriptionProvider>());
                  },
                ),
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search subscriptions...',
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
                  fillColor: AppColors.white,
                  filled: true,
                ),
                onChanged: (value) {
                  _filterSubscriptions(context.read<SubscriptionProvider>());
                },
              ),
            ),
            const SizedBox(width: 16),
            Flexible(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.borderGray),
                  borderRadius: BorderRadius.circular(8),
                  color: AppColors.white,
                ),
                child: DropdownButton<String>(
                  value: _selectedFilter,
                  underline: Container(),
                  items: ['All', 'Active', 'Trial', 'Cancelled', 'Paused']
                      .map((filter) => DropdownMenuItem(
                            value: filter,
                            child: Text(filter),
                          ))
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedFilter = value ?? 'All';
                    });
                    _filterSubscriptions(context.read<SubscriptionProvider>());
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSubscriptionsList() {
    if (_filteredSubscriptions.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.subscriptions_outlined,
              size: 64,
              color: AppColors.mediumGray,
            ),
            SizedBox(height: 16),
            Text(
              'No subscriptions found',
              style: TextStyle(
                fontSize: 18,
                color: AppColors.mediumGray,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _filteredSubscriptions.length,
      itemBuilder: (context, index) {
        final subscription = _filteredSubscriptions[index];
        return _buildSubscriptionCard(subscription);
      },
    );
  }

  Widget _buildSubscriptionCard(SubscriptionModel subscription) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderGray.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subscription.tenantName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryBlack,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subscription.planName,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.primaryRed,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getStatusColor(subscription.status)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      subscription.status.toUpperCase(),
                      style: TextStyle(
                        color: _getStatusColor(subscription.status),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subscription.formattedAmount,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryBlack,
                        ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              // For narrow screens, use column layout
              if (constraints.maxWidth < 600) {
                return Column(
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: _buildInfoItem('Billing Cycle',
                              subscription.billingCycle.toUpperCase()),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: _buildInfoItem('Start Date',
                              _formatDate(subscription.startDate)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Flexible(
                          child: _buildInfoItem(
                            'Next Billing',
                            subscription.nextBillingDate != null
                                ? _formatDate(subscription.nextBillingDate!)
                                : 'N/A',
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (subscription.daysRemaining > 0)
                          Flexible(
                            child: _buildInfoItem(
                              'Days Left',
                              subscription.daysRemaining.toString(),
                            ),
                          ),
                        if (subscription.daysRemaining <= 0)
                          const Flexible(child: SizedBox()),
                      ],
                    ),
                  ],
                );
              }

              // For wider screens, keep the row layout
              return Row(
                children: [
                  Flexible(
                    child: _buildInfoItem('Billing Cycle',
                        subscription.billingCycle.toUpperCase()),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: _buildInfoItem(
                        'Start Date', _formatDate(subscription.startDate)),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: _buildInfoItem(
                      'Next Billing',
                      subscription.nextBillingDate != null
                          ? _formatDate(subscription.nextBillingDate!)
                          : 'N/A',
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (subscription.daysRemaining > 0)
                    Flexible(
                      child: _buildInfoItem(
                        'Days Left',
                        subscription.daysRemaining.toString(),
                      ),
                    ),
                  if (subscription.daysRemaining <= 0)
                    const Flexible(child: SizedBox()),
                ],
              );
            },
          ),
          if (subscription.isTrial && subscription.trialEndDate != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.schedule, color: Colors.orange, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Trial ends: ${_formatDate(subscription.trialEndDate!)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.orange[700],
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.mediumGray,
              ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.primaryBlack,
              ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ],
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return Colors.green;
      case 'trial':
        return Colors.orange;
      case 'cancelled':
        return Colors.red;
      case 'paused':
        return Colors.grey;
      default:
        return AppColors.mediumGray;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
