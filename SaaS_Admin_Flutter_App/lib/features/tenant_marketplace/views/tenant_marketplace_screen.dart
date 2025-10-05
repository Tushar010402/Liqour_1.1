import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/brand_package_model.dart';
import '../../../core/models/brand_model.dart';
import '../controllers/marketplace_provider.dart';

class TenantMarketplaceScreen extends StatefulWidget {
  final String? tenantId;

  const TenantMarketplaceScreen({
    super.key,
    this.tenantId,
  });

  @override
  State<TenantMarketplaceScreen> createState() => _TenantMarketplaceScreenState();
}

class _TenantMarketplaceScreenState extends State<TenantMarketplaceScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MarketplaceProvider>().initialize();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGray,
      appBar: AppBar(
        title: const Text('Brand Marketplace'),
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.primaryBlack,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primaryRed,
          unselectedLabelColor: AppColors.mediumGray,
          indicatorColor: AppColors.primaryRed,
          tabs: const [
            Tab(text: 'Package Selection'),
            Tab(text: 'Custom Selection'),
          ],
          onTap: (index) {
            final provider = context.read<MarketplaceProvider>();
            provider.setOnboardingMode(index == 0 ? 'package' : 'custom');
          },
        ),
      ),
      body: Column(
        children: [
          _buildSearchAndFilters(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildPackageSelection(),
                _buildCustomSelection(),
              ],
            ),
          ),
          _buildBottomCheckout(),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    return Container(
      color: AppColors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Search bar
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search brands or packages...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _updateSearch();
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.lightGray),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.primaryRed),
              ),
            ),
            onChanged: (_) => _updateSearch(),
          ),
          const SizedBox(height: 12),
          // Filter chips
          _buildFilterChips(),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return Consumer<MarketplaceProvider>(
      builder: (context, provider, child) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              // Package type filters (for package mode)
              if (provider.onboardingMode == 'package') ...[
                _buildFilterChip('All Packages', null, provider.currentFilter.packageType),
                _buildFilterChip('Starter', 'starter', provider.currentFilter.packageType),
                _buildFilterChip('Premium', 'premium', provider.currentFilter.packageType),
                _buildFilterChip('Complete', 'full', provider.currentFilter.packageType),
              ],
              // Category filters
              ...provider.categories.map((category) =>
                _buildFilterChip(
                  category.name,
                  category.id,
                  provider.currentFilter.categoryId,
                  isCategory: true,
                ),
              ),
              // Clear filters
              if (provider.currentFilter.packageType != null ||
                  provider.currentFilter.categoryId != null ||
                  provider.currentFilter.searchQuery != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: ActionChip(
                    label: const Text('Clear Filters'),
                    onPressed: () => provider.clearFilters(),
                    backgroundColor: AppColors.lightGray,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterChip(String label, String? value, String? currentValue, {bool isCategory = false}) {
    final isSelected = currentValue == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (selected) {
          final provider = context.read<MarketplaceProvider>();
          final newFilter = provider.currentFilter.copyWith(
            packageType: isCategory ? provider.currentFilter.packageType : (selected ? value : null),
            categoryId: isCategory ? (selected ? value : null) : provider.currentFilter.categoryId,
          );
          provider.updateFilter(newFilter);
        },
        selectedColor: AppColors.primaryRed.withOpacity(0.2),
        checkmarkColor: AppColors.primaryRed,
      ),
    );
  }

  Widget _buildPackageSelection() {
    return Consumer<MarketplaceProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (provider.error != null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(provider.error!),
                ElevatedButton(
                  onPressed: () => provider.loadPackages(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: provider.packages.length,
          itemBuilder: (context, index) {
            final package = provider.packages[index];
            return _buildPackageCard(package, provider);
          },
        );
      },
    );
  }

  Widget _buildPackageCard(BrandPackage package, MarketplaceProvider provider) {
    final isSelected = provider.selectedPackage?.id == package.id;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: isSelected ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? AppColors.primaryRed : AppColors.lightGray,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: () {
          if (isSelected) {
            provider.clearPackageSelection();
          } else {
            provider.selectPackage(package);
          }
        },
        borderRadius: BorderRadius.circular(12),
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
                              package.name,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (package.isPopular)
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryRed,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'POPULAR',
                                  style: TextStyle(
                                    color: AppColors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          package.description,
                          style: const TextStyle(
                            color: AppColors.mediumGray,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (package.discountPercentage != null)
                        Text(
                          '₹${package.price.toStringAsFixed(0)}',
                          style: const TextStyle(
                            decoration: TextDecoration.lineThrough,
                            color: AppColors.mediumGray,
                            fontSize: 14,
                          ),
                        ),
                      Text(
                        '₹${package.finalPrice.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryRed,
                        ),
                      ),
                      if (package.discountPercentage != null)
                        Text(
                          '${package.discountPercentage!.toStringAsFixed(0)}% OFF',
                          style: const TextStyle(
                            color: AppColors.primaryRed,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Stats
              Row(
                children: [
                  _buildStatChip('${package.brandCount} Brands', Icons.local_drink),
                  const SizedBox(width: 12),
                  _buildStatChip('${package.variantCount} Products', Icons.inventory),
                ],
              ),
              const SizedBox(height: 16),

              // Features
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: package.features.map((feature) =>
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.check_circle,
                        size: 16,
                        color: AppColors.primaryRed,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        feature,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatChip(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.lightGray,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.mediumGray),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.mediumGray,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomSelection() {
    return Consumer<MarketplaceProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (provider.error != null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(provider.error!),
                ElevatedButton(
                  onPressed: () => provider.loadCustomBrands(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: provider.customBrands.length,
          itemBuilder: (context, index) {
            final brand = provider.customBrands[index];
            return _buildBrandCard(brand, provider);
          },
        );
      },
    );
  }

  Widget _buildBrandCard(Brand brand, MarketplaceProvider provider) {
    final isSelected = provider.selectedBrandIds.contains(brand.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isSelected ? 2 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isSelected ? AppColors.primaryRed : AppColors.lightGray,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundImage: brand.picture.isNotEmpty
              ? NetworkImage(brand.picture)
              : null,
          child: brand.picture.isEmpty
              ? Text(brand.name.substring(0, 1).toUpperCase())
              : null,
        ),
        title: Text(brand.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(brand.description),
            if (brand.brandVariants != null)
              Text(
                '${brand.brandVariants!.length} variants available',
                style: const TextStyle(fontSize: 12),
              ),
          ],
        ),
        trailing: Checkbox(
          value: isSelected,
          onChanged: (value) {
            provider.toggleBrandSelection(brand.id);
          },
          activeColor: AppColors.primaryRed,
        ),
        onTap: () => provider.toggleBrandSelection(brand.id),
      ),
    );
  }

  Widget _buildBottomCheckout() {
    return Consumer<MarketplaceProvider>(
      builder: (context, provider, child) {
        if (!provider.hasSelection) {
          return const SizedBox.shrink();
        }

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: AppColors.white,
            border: Border(
              top: BorderSide(color: AppColors.lightGray),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Selection summary
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${provider.totalSelectedBrands} Brands Selected',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${provider.totalSelectedVariants} Products',
                        style: const TextStyle(
                          color: AppColors.mediumGray,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '₹${provider.totalPrice.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryRed,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Complete onboarding button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: provider.isLoading
                      ? null
                      : () => _completeOnboarding(provider),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryRed,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: provider.isLoading
                      ? const CircularProgressIndicator(color: AppColors.white)
                      : const Text(
                          'Complete Setup',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _updateSearch() {
    final provider = context.read<MarketplaceProvider>();
    final newFilter = provider.currentFilter.copyWith(
      searchQuery: _searchController.text.trim().isEmpty ? null : _searchController.text.trim(),
    );
    provider.updateFilter(newFilter);
  }

  Future<void> _completeOnboarding(MarketplaceProvider provider) async {
    if (widget.tenantId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tenant ID not provided')),
      );
      return;
    }

    final success = await provider.completeOnboarding(widget.tenantId!);

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Onboarding completed successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.error ?? 'Failed to complete onboarding'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}