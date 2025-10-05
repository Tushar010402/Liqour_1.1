import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../routes/app_routes.dart';
import '../controllers/plan_provider.dart';
import '../../../core/models/plan_model.dart';

class PlanListScreen extends StatefulWidget {
  const PlanListScreen({super.key});

  @override
  State<PlanListScreen> createState() => _PlanListScreenState();
}

class _PlanListScreenState extends State<PlanListScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  String _selectedFilter = 'all';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PlanProvider>().loadPlansWithBillingOptions();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      backgroundColor: AppColors.lightGray,
      appBar: _buildAppBar(),
      body: Consumer<PlanProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && !provider.hasPlans) {
            return _buildLoadingState();
          }

          if (provider.hasError) {
            return _buildErrorState(provider.errorMessage!);
          }

          return _buildPlansList(provider);
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _handleCreatePlan,
        child: const Icon(Icons.add),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text(AppStrings.planManagement),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          onPressed: _showSearchDialog,
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.filter_list),
          onSelected: (value) {
            setState(() {
              _selectedFilter = value;
            });
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'all',
              child: Text('All Plans'),
            ),
            const PopupMenuItem(
              value: 'popular',
              child: Text('Popular Plans'),
            ),
            const PopupMenuItem(
              value: 'enterprise',
              child: Text('Enterprise Plans'),
            ),
            const PopupMenuItem(
              value: 'active',
              child: Text('Active Plans'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryRed),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: AppColors.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load plans',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppColors.primaryBlack,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.mediumGray,
                  ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () =>
                  context.read<PlanProvider>().loadPlansWithBillingOptions(),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlansList(PlanProvider provider) {
    final filteredPlans = _getFilteredPlans(provider.plans);

    if (filteredPlans.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: () => provider.refresh(),
      child: Column(
        children: [
          // Filter Chips
          _buildFilterChips(),

          // Plans List
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: filteredPlans.length,
              itemBuilder: (context, index) {
                return _buildPlanCard(filteredPlans[index]);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _buildFilterChip('all', 'All Plans'),
          _buildFilterChip('popular', 'Popular'),
          _buildFilterChip('enterprise', 'Enterprise'),
          _buildFilterChip('active', 'Active'),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
    final isSelected = _selectedFilter == value;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: isSelected,
        label: Text(label),
        onSelected: (selected) {
          setState(() {
            _selectedFilter = value;
          });
        },
        backgroundColor: AppColors.white,
        selectedColor: AppColors.lightRed,
        checkmarkColor: AppColors.primaryRed,
        labelStyle: TextStyle(
          color: isSelected ? AppColors.primaryRed : AppColors.charcoalGray,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.assignment_outlined,
              size: 64,
              color: AppColors.mediumGray,
            ),
            const SizedBox(height: 16),
            Text(
              'No plans found',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppColors.mediumGray,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create your first plan to get started',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.mediumGray,
                  ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _handleCreatePlan,
              icon: const Icon(Icons.add),
              label: const Text('Create Plan'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanCard(PlanModel plan) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: () => context.push('${AppRoutes.plans}/${plan.id}'),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              plan.displayName,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            if (plan.popular) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.warning,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'POPULAR',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        color: AppColors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                              ),
                            ],
                            if (plan.enterprise) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryRed,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'ENTERPRISE',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        color: AppColors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          plan.description,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppColors.mediumGray,
                                  ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        plan.formattedPrice,
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryRed,
                                ),
                      ),
                      Text(
                        '/${plan.billingCycle}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.mediumGray,
                            ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Limits
              Row(
                children: [
                  Expanded(
                    child: _buildLimitItem(
                      'Users',
                      plan.maxUsersText,
                      Icons.people_outline,
                    ),
                  ),
                  Expanded(
                    child: _buildLimitItem(
                      'Locations',
                      plan.maxLocationsText,
                      Icons.location_on_outlined,
                    ),
                  ),
                  Expanded(
                    child: _buildLimitItem(
                      'Products',
                      plan.maxProductsText,
                      Icons.inventory_outlined,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Features
              if (plan.features.isNotEmpty) ...[
                Text(
                  'Key Features:',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: plan.features.take(3).map((feature) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.lightRed,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        feature.replaceAll('_', ' ').toUpperCase(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: AppColors.darkRed,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    );
                  }).toList(),
                ),
                if (plan.features.length > 3) ...[
                  const SizedBox(height: 4),
                  Text(
                    '+${plan.features.length - 3} more features',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.mediumGray,
                          fontStyle: FontStyle.italic,
                        ),
                  ),
                ],
              ],

              const SizedBox(height: 16),

              // Actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _handleEditPlan(plan),
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Edit'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          context.push('${AppRoutes.plans}/${plan.id}'),
                      icon: const Icon(Icons.visibility_outlined, size: 16),
                      label: const Text('View Details'),
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

  Widget _buildLimitItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: AppColors.mediumGray, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.mediumGray,
              ),
        ),
      ],
    );
  }

  List<PlanModel> _getFilteredPlans(List<PlanModel> plans) {
    var filtered = plans;

    // Apply filter
    switch (_selectedFilter) {
      case 'popular':
        filtered = plans.where((plan) => plan.popular).toList();
        break;
      case 'enterprise':
        filtered = plans.where((plan) => plan.enterprise).toList();
        break;
      case 'active':
        filtered = plans.where((plan) => plan.active).toList();
        break;
    }

    // Apply search
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((plan) {
        return plan.displayName
                .toLowerCase()
                .contains(_searchQuery.toLowerCase()) ||
            plan.description.toLowerCase().contains(_searchQuery.toLowerCase());
      }).toList();
    }

    return filtered;
  }

  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Search Plans'),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter plan name or description...',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) {
            setState(() {
              _searchQuery = value;
            });
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _searchQuery = '';
              });
              Navigator.pop(context);
            },
            child: const Text('Clear'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Search'),
          ),
        ],
      ),
    );
  }

  void _handleCreatePlan() {
    context.push('${AppRoutes.plans}/form');
  }

  void _handleEditPlan(PlanModel plan) {
    context.push('${AppRoutes.plans}/edit/${plan.id}');
  }
}
