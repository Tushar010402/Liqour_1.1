import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/providers/shop_selection_provider.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/utils/haptic_feedback.dart';
import '../../../core/utils/logger.dart';
import '../../../core/utils/performance_monitor.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../providers/brand_onboarding_provider.dart';
import '../providers/product_provider.dart';

/// Brand Catalog V2 - Brand-Level Selection
///
/// Modern, clean UI with brand-level selection:
/// - Shows Brand Name + Category as primary information
/// - When user selects a brand → ALL variants imported automatically
/// - Material Design 3 principles
/// - Mobile-first, touch-optimized
class BrandCatalogV2Screen extends StatefulWidget {
  const BrandCatalogV2Screen({super.key});

  @override
  State<BrandCatalogV2Screen> createState() => _BrandCatalogV2ScreenState();
}

class _BrandCatalogV2ScreenState extends State<BrandCatalogV2Screen> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategory = 'All';

  @override
  void initState() {
    super.initState();
    print('🎯 ═══════════════════════════════════════════════════════════');
    print('🎯 SCREEN OPENED: BrandCatalogV2Screen (Material Design Import)');
    print('🎯 FILE: brand_catalog_v2_screen.dart');
    print('🎯 ═══════════════════════════════════════════════════════════');
    AnalyticsService.trackScreenView('brand_catalog_v2');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<BrandOnboardingProvider>();
      provider.loadAvailableBrands();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _onboardBrands(BrandOnboardingProvider provider) async {
    if (provider.selectedBrandsCount == 0) {
      _showSnackBar('Please select at least one brand', AppColors.warning);
      return;
    }

    final brandsCount = provider.selectedBrandsCount;
    final variantsCount = provider.selectedVariantsCount;

    // Confirm onboarding
    final confirmed = await _showConfirmDialog(
      'Onboard $brandsCount ${brandsCount == 1 ? 'Brand' : 'Brands'}?',
      'This will import $variantsCount product variants to your inventory.\n\nYou can set stock quantities per shop later.',
    );

    if (!confirmed || !mounted) return;

    try {
      final success = await PerformanceMonitor.measureAsync(
        operationName: 'brand_onboarding',
        category: 'inventory',
        operation: () => provider.onboardSelectedBrands(),
      );

      if (!success || !mounted) {
        await HapticFeedbackUtil.error();
        _showSnackBar(
          provider.errorMessage ?? 'Failed to onboard brands',
          AppColors.error,
        );
        return;
      }

      await HapticFeedbackUtil.success();

      // Track analytics
      AnalyticsService.trackProductOnboarding(
        productCount: variantsCount,
        withStock: false,
      );

      _showSnackBar(
        'Successfully onboarded $brandsCount brands ($variantsCount variants)',
        AppColors.success,
      );

      // Refresh product list
      if (mounted) {
        final shopId = context.read<ShopSelectionProvider>().selectedShopId;
        context.read<ProductProvider>().loadProducts(shopId: shopId);
      }

      // Navigate back
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      Logger.error('Error onboarding brands', e);
      _showSnackBar('Error: $e', AppColors.error);
    }
  }

  void _showSnackBar(String message, Color backgroundColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<bool> _showConfirmDialog(String title, String message) async {
    final cs = Theme.of(context).colorScheme;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title, style: AppTextStyles.h4),
        content: Text(message, style: AppTextStyles.bodyMedium),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: cs.onSurfaceVariant)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: cs.primary,
            ),
            child: const Text('Onboard'),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  List<String> _getCategories(BrandOnboardingProvider provider) {
    final categories = <String>{'All'};
    for (var brand in provider.availableBrands) {
      if (brand.categoryNameFromVariant != null) {
        categories.add(brand.categoryNameFromVariant!);
      }
    }
    return categories.toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BrandOnboardingProvider>(
      builder: (context, provider, _) {
        final categories = _getCategories(provider);
        final filteredBrands = _selectedCategory == 'All'
            ? provider.filteredBrands
            : provider.filteredBrands.where((brand) {
                return brand.categoryNameFromVariant == _selectedCategory;
              }).toList();

        final cs = Theme.of(context).colorScheme;
        return Scaffold(
          backgroundColor: cs.surface,
          appBar: CustomAppBar(
            title: 'Brand Catalog',
            actions: [
              if (provider.selectedBrandsCount > 0)
                Container(
                  margin: const EdgeInsets.only(right: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.white, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        '${provider.selectedBrandsCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          body: provider.isLoadingBrands
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    // Search Bar
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: cs.surface,
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search brands...',
                          hintStyle: TextStyle(color: cs.onSurfaceVariant),
                          prefixIcon: Icon(Icons.search, color: cs.onSurfaceVariant),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchController.clear();
                                    provider.applySearch('');
                                  },
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: cs.outline),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: cs.outline),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: cs.primary, width: 2),
                          ),
                          filled: true,
                          fillColor: cs.surfaceContainerHighest,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        onChanged: (value) => provider.applySearch(value),
                      ),
                    ),

                    // Category Chips
                    if (categories.length > 1)
                      Container(
                        height: 50,
                        color: cs.surface,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: categories.length,
                          itemBuilder: (context, index) {
                            final category = categories[index];
                            final isSelected = category == _selectedCategory;

                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                label: Text(category),
                                selected: isSelected,
                                onSelected: (selected) {
                                  setState(() {
                                    _selectedCategory = category;
                                  });
                                },
                                backgroundColor: cs.surface,
                                selectedColor: cs.primary.withValues(alpha: 0.1),
                                labelStyle: TextStyle(
                                  color: isSelected ? cs.primary : cs.onSurfaceVariant,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                                side: BorderSide(
                                  color: isSelected ? cs.primary : cs.outline,
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                    const Divider(height: 1),

                    // Brand Grid
                    Expanded(
                      child: filteredBrands.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.inventory_2_outlined, size: 64, color: cs.onSurfaceVariant),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No brands found',
                                    style: AppTextStyles.h4.copyWith(color: cs.onSurfaceVariant),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Try adjusting your search or filters',
                                    style: AppTextStyles.bodyMedium.copyWith(color: cs.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            )
                          : GridView.builder(
                              padding: const EdgeInsets.all(16),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                childAspectRatio: 0.75,
                              ),
                              itemCount: filteredBrands.length,
                              itemBuilder: (context, index) {
                                final brand = filteredBrands[index];
                                final isSelected = provider.isBrandSelected(brand.id);
                                final isOnboarded = brand.isOnboarded ?? false;
                                final variantCount = brand.variants.length;
                                final category = brand.categoryNameFromVariant ?? 'Uncategorized';

                                return _BrandCard(
                                  brand: brand,
                                  category: category,
                                  variantCount: variantCount,
                                  isSelected: isSelected,
                                  isOnboarded: isOnboarded,
                                  onTap: () {
                                    HapticFeedbackUtil.selection();
                                    provider.toggleBrandSelection(brand.id);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
          bottomNavigationBar: provider.selectedBrandsCount > 0
              ? SafeArea(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, -5),
                        ),
                      ],
                    ),
                    child: FilledButton(
                      onPressed: () => _onboardBrands(provider),
                      style: FilledButton.styleFrom(
                        backgroundColor: cs.primary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Onboard ${provider.selectedBrandsCount} ${provider.selectedBrandsCount == 1 ? 'Brand' : 'Brands'} (${provider.selectedVariantsCount} variants)',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                )
              : null,
        );
      },
    );
  }
}

/// Brand Card Widget
class _BrandCard extends StatelessWidget {
  final dynamic brand;
  final String category;
  final int variantCount;
  final bool isSelected;
  final bool isOnboarded;
  final VoidCallback onTap;

  const _BrandCard({
    required this.brand,
    required this.category,
    required this.variantCount,
    required this.isSelected,
    required this.isOnboarded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? cs.primary
                : isOnboarded
                    ? AppColors.success
                    : cs.outline,
            width: isSelected || isOnboarded ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? cs.primary.withValues(alpha: 0.2)
                  : Colors.black.withValues(alpha: 0.05),
              blurRadius: isSelected ? 8 : 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Image Section
                Expanded(
                  flex: 3,
                  child: Container(
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    child: brand.picture != null && brand.picture!.isNotEmpty
                        ? ClipRRect(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                            child: Image.network(
                              brand.picture!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => _buildPlaceholderImage(context),
                            ),
                          )
                        : _buildPlaceholderImage(context),
                  ),
                ),

                // Info Section
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Brand Name
                        Text(
                          brand.name ?? 'Unknown Brand',
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),

                        // Category
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            category,
                            style: TextStyle(
                              fontSize: 10,
                              color: cs.primary,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),

                        const Spacer(),

                        // Variant Count
                        Row(
                          children: [
                            Icon(Icons.inventory_2, size: 12, color: cs.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Text(
                              '$variantCount ${variantCount == 1 ? 'variant' : 'variants'}',
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // Selection Indicator
            if (isSelected || isOnboarded)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: isSelected ? cs.primary : AppColors.success,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    isOnboarded ? Icons.check : Icons.check,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),

            // Onboarded Badge
            if (isOnboarded)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'ADDED',
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholderImage(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Icon(
        Icons.liquor,
        size: 48,
        color: cs.onSurfaceVariant.withValues(alpha: 0.3),
      ),
    );
  }
}
