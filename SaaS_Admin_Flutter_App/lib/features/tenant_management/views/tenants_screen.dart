import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/tenant_provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/tenant_model.dart';

class TenantsScreen extends StatefulWidget {
  const TenantsScreen({super.key});

  @override
  State<TenantsScreen> createState() => _TenantsScreenState();
}

class _TenantsScreenState extends State<TenantsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedFilter = 'All';
  List<TenantModel> _filteredTenants = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TenantProvider>().loadTenantAnalytics();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterTenants(TenantProvider provider) {
    List<TenantModel> tenants = provider.tenants;

    // Apply search filter
    if (_searchController.text.isNotEmpty) {
      tenants = provider.searchTenants(_searchController.text);
    }

    // Apply status filter
    if (_selectedFilter != 'All') {
      tenants = tenants
          .where((tenant) =>
              tenant.status.toLowerCase() == _selectedFilter.toLowerCase())
          .toList();
    }

    setState(() {
      _filteredTenants = tenants;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGray,
      body: Consumer<TenantProvider>(
        builder: (context, provider, child) {
          // Update filtered tenants when data changes
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _filterTenants(provider);
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
                    'Error loading tenant data',
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
                    onPressed: () => provider.loadTenantAnalytics(),
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
                        Text(
                          'Tenant Management',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryBlack,
                              ),
                        ),
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

              // Tenants List
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
                  child: _buildTenantsList(),
                ),
              ),

              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAnalyticsCards(TenantAnalytics analytics) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Use smaller cards for narrow screens
        final isNarrow = constraints.maxWidth < 800;
        final cardSpacing = isNarrow ? 8.0 : 16.0;

        return Row(
          children: [
            Expanded(
              child: _buildAnalyticsCard(
                'Total Tenants',
                analytics.totalTenants.toString(),
                Icons.business_outlined,
                AppColors.primaryRed,
                isCompact: isNarrow,
              ),
            ),
            SizedBox(width: cardSpacing),
            Expanded(
              child: _buildAnalyticsCard(
                'Active Tenants',
                analytics.activeTenants.toString(),
                Icons.check_circle_outline,
                Colors.green,
                isCompact: isNarrow,
              ),
            ),
            SizedBox(width: cardSpacing),
            Expanded(
              child: _buildAnalyticsCard(
                'Avg Locations',
                analytics.averageLocations.toStringAsFixed(1),
                Icons.location_on_outlined,
                Colors.blue,
                isCompact: isNarrow,
              ),
            ),
            SizedBox(width: cardSpacing),
            Expanded(
              child: _buildAnalyticsCard(
                'Avg Products',
                analytics.averageProducts.toStringAsFixed(0),
                Icons.inventory_outlined,
                Colors.orange,
                isCompact: isNarrow,
              ),
            ),
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
              Icon(icon, color: color, size: isCompact ? 16 : 18),
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
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search tenants...',
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
              fillColor: AppColors.white,
              filled: true,
            ),
            onChanged: (value) {
              _filterTenants(context.read<TenantProvider>());
            },
          ),
        ),
        const SizedBox(width: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.borderGray),
            borderRadius: BorderRadius.circular(8),
            color: AppColors.white,
          ),
          child: DropdownButton<String>(
            value: _selectedFilter,
            underline: Container(),
            items: ['All', 'Active', 'Paused', 'Cancelled']
                .map((filter) => DropdownMenuItem(
                      value: filter,
                      child: Text(filter),
                    ))
                .toList(),
            onChanged: (value) {
              setState(() {
                _selectedFilter = value ?? 'All';
              });
              _filterTenants(context.read<TenantProvider>());
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTenantsList() {
    if (_filteredTenants.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.business_outlined,
              size: 64,
              color: AppColors.mediumGray,
            ),
            SizedBox(height: 16),
            Text(
              'No tenants found',
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
      itemCount: _filteredTenants.length,
      itemBuilder: (context, index) {
        final tenant = _filteredTenants[index];
        return _buildTenantCard(tenant);
      },
    );
  }

  Widget _buildTenantCard(TenantModel tenant) {
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
                      tenant.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryBlack,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tenant.email,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.mediumGray,
                          ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getStatusColor(tenant.status).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  tenant.status.toUpperCase(),
                  style: TextStyle(
                    color: _getStatusColor(tenant.status),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildInfoItem('Plan', tenant.subscriptionPlan),
              const SizedBox(width: 8),
              _buildInfoItem('Locations', tenant.locationsCount.toString()),
              const SizedBox(width: 8),
              _buildInfoItem('Users', tenant.usersCount.toString()),
              const SizedBox(width: 8),
              _buildInfoItem('Products', tenant.productsCount.toString()),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Created: ${_formatDate(tenant.createdAt)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.mediumGray,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (tenant.lastActive != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Last active: ${_formatDate(tenant.lastActive!)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.mediumGray,
                        ),
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Flexible(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.mediumGray,
                  fontSize: 10,
                ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryBlack,
                  fontSize: 12,
                ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return Colors.green;
      case 'paused':
        return Colors.orange;
      case 'cancelled':
        return Colors.red;
      default:
        return AppColors.mediumGray;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
