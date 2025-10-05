import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../providers/brand_onboarding_provider.dart';
import '../models/saas_brand.dart' show SaasBrand;
import 'initial_stock_screen.dart';
import '../../../core/utils/logger.dart';

/// Brand Catalog Screen - Professional & Clean Design
class BrandCatalogScreen extends StatefulWidget {
  const BrandCatalogScreen({super.key});

  @override
  State<BrandCatalogScreen> createState() => _BrandCatalogScreenState();
}

class _BrandCatalogScreenState extends State<BrandCatalogScreen> {
  final TextEditingController _searchController = TextEditingController();
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BrandOnboardingProvider>().loadAvailableBrands();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _onboardBrands(BrandOnboardingProvider provider) async {
    if (provider.selectedVariantsCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select products to onboard'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Onboarding'),
        content: Text(
          'Onboard ${provider.selectedVariantsCount} product${provider.selectedVariantsCount > 1 ? 's' : ''}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final success = await provider.onboardSelectedBrands();

    if (!mounted) return;

    if (success) {
      // Get the onboarded product IDs from the result
      final productIds = provider.lastOnboardingResult?.productIds ?? [];

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully onboarded ${productIds.length} products'),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 2),
        ),
      );

      // Navigate to initial stock screen
      if (productIds.isNotEmpty) {
        final shouldSetStock = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Set Initial Stock'),
            content: const Text(
              'Would you like to set initial stock quantities for the onboarded products?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Skip'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                child: const Text('Set Stock'),
              ),
            ],
          ),
        );

        if (shouldSetStock == true && mounted) {
          // Navigate to initial stock screen
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => InitialStockScreen(
                productIds: productIds,
                shopId: provider.selectedShopId,
              ),
            ),
          );
        }
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.errorMessage ?? 'Failed to onboard brands'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(
        title: 'Brand Catalog',
        actions: [
          Consumer<BrandOnboardingProvider>(
            builder: (context, provider, _) {
              if (provider.selectedVariantsCount > 0) {
                return Center(
                  child: Container(
                    margin: const EdgeInsets.only(right: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${provider.selectedVariantsCount} selected',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              }
              return const SizedBox();
            },
          ),
        ],
      ),
      body: Consumer<BrandOnboardingProvider>(
        builder: (context, provider, _) {
          return Column(
            children: [
              // Search Bar
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.white,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search brands...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: AppColors.surface,
                  ),
                  onChanged: (value) {
                    setState(() {});
                  },
                ),
              ),

              // Category Filter (if categories exist)
              if (provider.availableCategories.isNotEmpty)
                Container(
                  height: 50,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  color: Colors.white,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _buildCategoryChip('All', null),
                      ...provider.availableCategories.map(
                        (category) => _buildCategoryChip(
                          category,
                          category,
                        ),
                      ),
                    ],
                  ),
                ),

              // Statistics Row
              if (!provider.isLoadingBrands)
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.white,
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildStatBox(
                          'Available Brands',
                          '${provider.availableBrands.length}',
                          Icons.local_offer,
                          AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatBox(
                          'Products',
                          '${provider.selectedVariantsCount}',
                          Icons.inventory_2,
                          AppColors.success,
                        ),
                      ),
                    ],
                  ),
                ),

              const Divider(height: 1),

              // Brands List
              Expanded(
                child: provider.isLoadingBrands
                    ? const Center(child: CircularProgressIndicator())
                    : provider.availableBrands.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.local_offer_outlined,
                                  size: 64,
                                  color: AppColors.textSecondary.withOpacity(0.5),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No brands available',
                                  style: AppTextStyles.bodyLarge.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _filteredBrands(provider).length,
                            itemBuilder: (context, index) {
                              final brand = _filteredBrands(provider)[index];
                              return _buildBrandCard(brand, provider);
                            },
                          ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: Consumer<BrandOnboardingProvider>(
        builder: (context, provider, _) {
          if (provider.selectedVariantsCount == 0) {
            return const SizedBox.shrink();
          }

          return FloatingActionButton.extended(
            onPressed: () => _onboardBrands(provider),
            backgroundColor: AppColors.primary,
            icon: const Icon(Icons.download, color: Colors.white),
            label: Text(
              'Onboard (${provider.selectedVariantsCount})',
              style: const TextStyle(color: Colors.white),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCategoryChip(String label, String? categoryId) {
    final isSelected = _selectedCategory == categoryId;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedCategory = categoryId;
          });
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: isSelected ? Colors.white : AppColors.textPrimary,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatBox(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: AppTextStyles.h6.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  label,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: color.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrandCard(SaasBrand brand, BrandOnboardingProvider provider) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExpansionTile(
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.local_offer,
            color: AppColors.primary,
            size: 28,
          ),
        ),
        title: Text(
          brand.name,
          style: AppTextStyles.h6.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (brand.description.isNotEmpty)
              Text(
                brand.description,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 4),
            Text(
              '${brand.variants.length} products',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        children: brand.variants.map((variant) {
          final isSelected = provider.isVariantSelected(variant.id);

          // ✅ DEBUG: Validate variant belongs to this brand
          if (variant.brandId != brand.id) {
            Logger.debug('⚠️ VARIANT MISMATCH!');
            Logger.debug('   Brand: ${brand.name} (${brand.id})');
            Logger.debug('   Variant: ${variant.size} (${variant.id})');
            Logger.debug('   Variant\'s Brand ID: ${variant.brandId}');
            Logger.debug('   ❌ This variant does NOT belong to this brand!');
          }

          return CheckboxListTile(
            value: isSelected,
            onChanged: (value) {
              provider.toggleVariant(brand.id, variant.id);
            },
            title: Text(
              '${brand.name} ${variant.size}',
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  brand.categoryName ?? 'Unknown Category',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      'MRP: ₹${variant.mrp.toStringAsFixed(0)}',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.success,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'ABV: ${variant.alcoholContent}%',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            activeColor: AppColors.primary,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          );
        }).toList(),
      ),
    );
  }

  List<SaasBrand> _filteredBrands(BrandOnboardingProvider provider) {
    var brands = provider.availableBrands;

    // Filter by search
    if (_searchController.text.isNotEmpty) {
      final query = _searchController.text.toLowerCase();
      brands = brands.where((brand) {
        return brand.name.toLowerCase().contains(query) ||
            brand.description.toLowerCase().contains(query);
      }).toList();
    }

    // Filter by category
    if (_selectedCategory != null) {
      brands = brands.where((brand) {
        return brand.categoryName == _selectedCategory;
      }).toList();
    }

    return brands;
  }
}
