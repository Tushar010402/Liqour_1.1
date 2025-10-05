import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/brand_model.dart';
import '../../../core/utils/text_input_utils.dart';
import '../controllers/brand_provider.dart';
import 'brand_form_screen.dart';
import 'brand_details_screen.dart';
import 'tenant_brand_assignment_screen.dart';

class BrandsScreen extends StatefulWidget {
  const BrandsScreen({super.key});

  @override
  State<BrandsScreen> createState() => _BrandsScreenState();
}

class _BrandsScreenState extends State<BrandsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedView = 'grid';
  String _selectedFilter = 'All';
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BrandProvider>().initialize();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 768;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: _buildAppBar(isMobile),
      body: Consumer<BrandProvider>(
        builder: (context, brandProvider, child) {
          return Column(
            children: [
              _buildCompactStats(brandProvider, isMobile),
              _buildSearchBar(brandProvider, isMobile),
              Expanded(
                child: _buildBrandContent(brandProvider, isMobile),
              ),
            ],
          );
        },
      ),
      floatingActionButton: _buildFAB(isMobile),
    );
  }

  PreferredSizeWidget _buildAppBar(bool isMobile) {
    return AppBar(
      elevation: 0,
      backgroundColor: AppColors.primaryRed,
      foregroundColor: Colors.white,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.local_drink_rounded, size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Brand Management',
                style: TextStyle(
                  fontSize: isMobile ? 16 : 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (!isMobile)
                Text(
                  'Manage liquor brands',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.8),
                    fontWeight: FontWeight.w400,
                  ),
                ),
            ],
          ),
        ],
      ),
      actions: [
        Consumer<BrandProvider>(
          builder: (context, provider, child) => IconButton(
            icon: provider.isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.refresh),
            onPressed: provider.isLoading ? null : () async {
              await provider.refresh();
            },
          ),
        ),
        IconButton(
          icon:
              Icon(_selectedView == 'grid' ? Icons.view_list : Icons.grid_view),
          onPressed: () {
            setState(() {
              _selectedView = _selectedView == 'grid' ? 'list' : 'grid';
            });
          },
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: _handleMenuAction,
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'filter',
              child: Row(
                children: [
                  Icon(Icons.filter_list, size: 18),
                  SizedBox(width: 8),
                  Text('Filter'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'sort',
              child: Row(
                children: [
                  Icon(Icons.sort, size: 18),
                  SizedBox(width: 8),
                  Text('Sort'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCompactStats(BrandProvider provider, bool isMobile) {
    final stats = [
      {
        'icon': Icons.inventory_rounded,
        'value': '${provider.brands.length}',
        'label': 'Total',
        'color': AppColors.primaryRed,
      },
      {
        'icon': Icons.check_circle,
        'value': '${provider.brands.where((b) => b.isActive).length}',
        'label': 'Active',
        'color': AppColors.success,
      },
      {
        'icon': Icons.category,
        'value': '${provider.categories.length}',
        'label': 'Categories',
        'color': AppColors.primaryBlue,
      },
      {
        'icon': Icons.apps,
        'value':
            '${provider.brands.fold(0, (sum, brand) => sum + (brand.brandVariants?.length ?? 0))}',
        'label': 'Variants',
        'color': AppColors.warning,
      },
    ];

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: stats.map((stat) {
          return Expanded(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (stat['color'] as Color).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    stat['icon'] as IconData,
                    size: 20,
                    color: stat['color'] as Color,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  stat['value'] as String,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
                Text(
                  stat['label'] as String,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSearchBar(BrandProvider provider, bool isMobile) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextInputUtils.buildTextField(
                controller: _searchController,
                hintText: 'Search brands...',
                prefixIcon: Icon(Icons.search, color: Colors.grey[500]),
                decoration: InputDecoration(
                  hintText: 'Search brands...',
                  hintStyle: TextStyle(color: Colors.grey[500]),
                  prefixIcon: Icon(Icons.search, color: Colors.grey[500]),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            provider.setSearchQuery('');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                onChanged: (value) => _onSearchChanged(value, provider),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: PopupMenuButton<String>(
              icon: const Icon(Icons.filter_list),
              onSelected: (filter) => _onFilterChanged(filter, provider),
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'All', child: Text('All')),
                const PopupMenuItem(value: 'Active', child: Text('Active')),
                const PopupMenuItem(value: 'Inactive', child: Text('Inactive')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrandContent(BrandProvider provider, bool isMobile) {
    if (provider.isLoading && provider.brands.isEmpty) {
      return _buildLoadingState();
    }

    final brands = provider.filteredBrands;

    if (brands.isEmpty) {
      return RefreshIndicator(
        onRefresh: () async {
          await provider.refresh();
        },
        child: _buildEmptyState(),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await provider.refresh();
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        child: _selectedView == 'grid'
            ? _buildGridView(brands, isMobile)
            : _buildListView(brands),
      ),
    );
  }

  Widget _buildGridView(List<Brand> brands, bool isMobile) {
    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isMobile ? 2 : 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: isMobile ? 0.85 : 0.9,
      ),
      itemCount: brands.length,
      itemBuilder: (context, index) => _buildCompactBrandCard(brands[index]),
    );
  }

  Widget _buildListView(List<Brand> brands) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: brands.length,
      itemBuilder: (context, index) => _buildBrandListItem(brands[index]),
    );
  }

  Widget _buildCompactBrandCard(Brand brand) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _navigateToBrandDetails(brand),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.primaryRed.withOpacity(0.1),
                            AppColors.primaryRed.withOpacity(0.2),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: brand.picture.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.network(
                                brand.picture,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    Icon(
                                  Icons.local_drink,
                                  color: AppColors.primaryRed,
                                  size: 20,
                                ),
                              ),
                            )
                          : Icon(
                              Icons.local_drink,
                              color: AppColors.primaryRed,
                              size: 20,
                            ),
                    ),
                    const Spacer(),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: brand.isActive
                              ? AppColors.success.withOpacity(0.1)
                              : AppColors.error.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          brand.isActive ? 'Active' : 'Inactive',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: brand.isActive
                                ? AppColors.success
                                : AppColors.error,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert,
                          size: 16, color: Colors.grey[600]),
                      onSelected: (value) => _handleBrandAction(value, brand),
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit, size: 16),
                              SizedBox(width: 8),
                              Text('Edit'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'variants',
                          child: Row(
                            children: [
                              Icon(Icons.inventory, size: 16),
                              SizedBox(width: 8),
                              Text('Variants'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'assign',
                          child: Row(
                            children: [
                              Icon(Icons.assignment_ind, size: 16),
                              SizedBox(width: 8),
                              Text('Assign'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete, size: 16, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Delete',
                                  style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  brand.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  brand.description.isEmpty
                      ? 'No description'
                      : brand.description,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const Spacer(),
                Flexible(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.inventory_2,
                          size: 12,
                          color: AppColors.primaryRed,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            '${brand.brandVariants?.length ?? 0}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF64748B),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrandListItem(Brand brand) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _navigateToBrandDetails(brand),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primaryRed.withOpacity(0.1),
                        AppColors.primaryRed.withOpacity(0.2),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: brand.picture.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            brand.picture,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Icon(
                              Icons.local_drink,
                              color: AppColors.primaryRed,
                              size: 24,
                            ),
                          ),
                        )
                      : Icon(
                          Icons.local_drink,
                          color: AppColors.primaryRed,
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
                              brand.name,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1E293B),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: brand.isActive
                                  ? AppColors.success.withOpacity(0.1)
                                  : AppColors.error.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              brand.isActive ? 'Active' : 'Inactive',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: brand.isActive
                                    ? AppColors.success
                                    : AppColors.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        brand.description.isEmpty
                            ? 'No description available'
                            : brand.description,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.inventory_2,
                            size: 12,
                            color: AppColors.primaryRed,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${brand.brandVariants?.length ?? 0} variants',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF94A3B8),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon:
                      Icon(Icons.more_vert, color: Colors.grey[600], size: 18),
                  onSelected: (value) => _handleBrandAction(value, brand),
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit, size: 16),
                          SizedBox(width: 8),
                          Text('Edit'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'variants',
                      child: Row(
                        children: [
                          Icon(Icons.inventory, size: 16),
                          SizedBox(width: 8),
                          Text('Variants'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'assign',
                      child: Row(
                        children: [
                          Icon(Icons.assignment_ind, size: 16),
                          SizedBox(width: 8),
                          Text('Assign'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, size: 16, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Delete', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: 6,
      itemBuilder: (context, index) => Container(
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.primaryRed.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.local_drink_outlined,
                size: 48,
                color: AppColors.primaryRed.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Brands Found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No brands found. Try refreshing or add your first brand.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Consumer<BrandProvider>(
                  builder: (context, provider, child) => OutlinedButton.icon(
                    onPressed: provider.isLoading ? null : () async {
                      await provider.refresh();
                    },
                    icon: provider.isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 18),
                    label: Text(provider.isLoading ? 'Refreshing...' : 'Refresh'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryRed,
                      side: const BorderSide(color: AppColors.primaryRed),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: () => _navigateToCreateBrand(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Brand'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryRed,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFAB(bool isMobile) {
    return FloatingActionButton(
      onPressed: () => _navigateToCreateBrand(),
      backgroundColor: AppColors.primaryRed,
      child: const Icon(Icons.add, color: Colors.white),
    );
  }

  // Event handlers
  void _handleMenuAction(String action) {
    switch (action) {
      case 'filter':
        _showFilterDialog();
        break;
      case 'sort':
        _showSortDialog();
        break;
    }
  }

  void _onSearchChanged(String value, BrandProvider provider) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      provider.setSearchQuery(value);
    });
  }

  void _onFilterChanged(String filter, BrandProvider provider) {
    setState(() => _selectedFilter = filter);
    switch (filter) {
      case 'Active':
        provider.setStatusFilter(true);
        break;
      case 'Inactive':
        provider.setStatusFilter(false);
        break;
      default:
        provider.clearFilters();
        break;
    }
  }

  void _handleBrandAction(String action, Brand brand) {
    switch (action) {
      case 'edit':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => BrandFormScreen(brand: brand),
          ),
        );
        break;
      case 'variants':
        _navigateToBrandDetails(brand);
        break;
      case 'assign':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) =>
                TenantBrandAssignmentScreen(selectedBrand: brand),
          ),
        );
        break;
      case 'delete':
        _showDeleteConfirmation(brand);
        break;
    }
  }

  void _showFilterDialog() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Filter Brands',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              title: const Text('All'),
              leading: Radio<String>(
                value: 'All',
                groupValue: _selectedFilter,
                onChanged: (value) {
                  if (value != null) {
                    _onFilterChanged(value, context.read<BrandProvider>());
                    Navigator.pop(context);
                  }
                },
              ),
            ),
            ListTile(
              title: const Text('Active'),
              leading: Radio<String>(
                value: 'Active',
                groupValue: _selectedFilter,
                onChanged: (value) {
                  if (value != null) {
                    _onFilterChanged(value, context.read<BrandProvider>());
                    Navigator.pop(context);
                  }
                },
              ),
            ),
            ListTile(
              title: const Text('Inactive'),
              leading: Radio<String>(
                value: 'Inactive',
                groupValue: _selectedFilter,
                onChanged: (value) {
                  if (value != null) {
                    _onFilterChanged(value, context.read<BrandProvider>());
                    Navigator.pop(context);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSortDialog() {
    // Implementation for sort dialog
  }

  void _navigateToCreateBrand() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const BrandFormScreen(),
      ),
    );
  }

  void _navigateToBrandDetails(Brand brand) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => BrandDetailsScreen(brand: brand),
      ),
    );
  }

  void _showDeleteConfirmation(Brand brand) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Brand'),
        content: Text('Are you sure you want to delete "${brand.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              final provider = context.read<BrandProvider>();
              final success = await provider.deleteBrand(brand.id);
              if (mounted) {
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Brand "${brand.name}" deleted successfully'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(provider.error ?? 'Failed to delete brand'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
