import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/services/api_service.dart';
import '../../../core/utils/haptic_feedback.dart';
import '../../../core/utils/logger.dart';
import '../../../core/utils/performance_monitor.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../admin/models/shop_model.dart';
import '../../admin/services/shop_service.dart';
import '../providers/brand_onboarding_provider.dart';
import '../providers/product_provider.dart';
import '../services/stock_service.dart';
import '../widgets/brand_category_tabs.dart';
import '../widgets/brand_variant_card_with_stock.dart';

/// Enhanced Brand Catalog Screen - Mobile-First Design for 100-200 Brands
/// Features:
/// - Hierarchical navigation (Category → Subcategory)
/// - Inline stock entry during selection
/// - Batch onboarding with stock
/// - Optimized for mobile touch interaction
class EnhancedBrandCatalogScreen extends StatefulWidget {
  const EnhancedBrandCatalogScreen({super.key});

  @override
  State<EnhancedBrandCatalogScreen> createState() =>
      _EnhancedBrandCatalogScreenState();
}

class _EnhancedBrandCatalogScreenState
    extends State<EnhancedBrandCatalogScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Shop> _shops = [];
  bool _isLoadingShops = false;
  bool _showStockInput = false;

  @override
  void initState() {
    super.initState();

    // Track screen view
    AnalyticsService.trackScreenView('enhanced_brand_catalog');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<BrandOnboardingProvider>();
      provider.loadAvailableBrands();
      _loadShops();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadShops() async {
    setState(() => _isLoadingShops = true);

    try {
      final apiService = context.read<ApiService>();
      final shopService = ShopService(apiService);
      final response = await shopService.getShops();

      if (response.success && response.data != null) {
        setState(() {
          _shops = response.data!;
        });

        // Auto-select first shop
        if (_shops.isNotEmpty) {
          final provider = context.read<BrandOnboardingProvider>();
          provider.selectShop(_shops.first.id);
        }
      }
    } catch (e) {
      Logger.error('Error loading shops', e);
    } finally {
      setState(() => _isLoadingShops = false);
    }
  }

  Future<void> _onboardBrandsWithStock(
      BrandOnboardingProvider provider) async {
    if (provider.selectedVariantsCount == 0) {
      _showSnackBar('Please select at least one product', AppColors.warning);
      return;
    }

    if (provider.selectedShopId == null) {
      _showSnackBar('Please select a shop first', AppColors.warning);
      return;
    }

    // Confirm onboarding
    final confirmed = await _showConfirmDialog(
      'Onboard ${provider.selectedVariantsCount} Products?',
      _showStockInput
          ? 'Products will be added to your inventory with initial stock quantities.'
          : 'Products will be added to your inventory. You can set stock later.',
    );

    if (!confirmed || !mounted) return;

    setState(() => _showStockInput = false); // Disable editing during save

    try {
      // Step 1: Onboard brands with performance tracking
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
        setState(() => _showStockInput = true);
        return;
      }

      // Step 2: Set stock quantities (if any)
      final productIds = provider.lastOnboardingResult?.productIds ?? [];
      if (_showStockInput && productIds.isNotEmpty) {
        await _setInitialStock(provider, productIds);
      }

      if (!mounted) return;

      // Success
      await HapticFeedbackUtil.success();

      // Track analytics
      AnalyticsService.trackProductOnboarding(
        productCount: productIds.length,
        withStock: _showStockInput,
      );

      _showSnackBar(
        'Successfully onboarded ${productIds.length} products',
        AppColors.success,
      );

      // Refresh product list
      context.read<ProductProvider>().loadProducts();

      // Navigate back
      Navigator.pop(context, true);
    } catch (e) {
      Logger.error('Error onboarding brands', e);
      _showSnackBar('Error: $e', AppColors.error);
      setState(() => _showStockInput = true);
    }
  }

  Future<void> _setInitialStock(
    BrandOnboardingProvider provider,
    List<String> productIds,
  ) async {
    final apiService = context.read<ApiService>();
    final stockService = StockService(apiService);

    int successCount = 0;
    int errorCount = 0;

    for (var i = 0; i < productIds.length; i++) {
      final productId = productIds[i];
      final variantId = provider.selectedVariantIds.elementAt(i);
      final quantity = provider.getVariantStock(variantId);

      if (quantity > 0) {
        final response = await stockService.adjustStock(
          shopId: provider.selectedShopId!,
          productId: productId,
          quantity: quantity,
          adjustmentType: 'set',
          reason: 'Initial Stock',
          notes: 'Initial stock setup during brand onboarding',
        );

        if (response.success) {
          successCount++;
        } else {
          errorCount++;
          Logger.error('Failed to set stock for $productId', response.message);
        }
      }
    }

    if (errorCount > 0) {
      Logger.warning('Stock saved with $errorCount errors ($successCount succeeded)');
    } else {
      Logger.info('Stock saved successfully for $successCount products');
    }
  }

  void _showSnackBar(String message, Color backgroundColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<bool> _showConfirmDialog(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
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

    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BrandOnboardingProvider>(
      builder: (context, provider, _) {
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: CustomAppBar(
            title: 'Brand Catalog',
            actions: [
              // Selected count badge
              if (provider.selectedVariantsCount > 0)
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(right: 16),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                ),
            ],
          ),
          body: Column(
            children: [
              // Shop Selector (sticky header)
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.white,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.store, color: AppColors.primary, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Select Shop',
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        // Toggle stock input mode
                        TextButton.icon(
                          onPressed: () async {
                            await HapticFeedbackUtil.toggle();
                            setState(() {
                              _showStockInput = !_showStockInput;
                            });
                          },
                          icon: Icon(
                            _showStockInput
                                ? Icons.inventory_2
                                : Icons.inventory_2_outlined,
                            size: 18,
                          ),
                          label: Text(
                            _showStockInput ? 'With Stock' : 'Stock Later',
                            style: TextStyle(fontSize: 12),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: _showStockInput
                                ? AppColors.primary
                                : AppColors.textSecondary,
                            backgroundColor: _showStockInput
                                ? AppColors.primary.withOpacity(0.1)
                                : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _isLoadingShops
                        ? const LinearProgressIndicator()
                        : _shops.isEmpty
                            ? Text(
                                'No shops available',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              )
                            : DropdownButtonFormField<String>(
                                value: provider.selectedShopId,
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  prefixIcon: const Icon(Icons.storefront),
                                ),
                                items: _shops.map((shop) {
                                  return DropdownMenuItem<String>(
                                    value: shop.id,
                                    child: Text(shop.name),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  provider.selectShop(value);
                                },
                              ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Search Bar
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.white,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search brands, products...',
                    prefixIcon: const Icon(Icons.search),
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
                    ),
                    filled: true,
                    fillColor: AppColors.surface,
                  ),
                  onChanged: (value) {
                    provider.applySearch(value);
                  },
                ),
              ),

              // Category/Subcategory Tabs
              BrandCategoryTabs(
                categories: provider.getCategoryGroups(),
                selectedCategoryId: provider.categoryFilter,
                selectedSubcategoryId: provider.subcategoryFilter,
                onFilterChanged: (categoryId, subcategoryId) {
                  provider.applyFilter(
                    categoryId: categoryId,
                    subcategoryId: subcategoryId,
                  );
                },
              ),

              const Divider(height: 1),

              // Brand Variants List
              Expanded(
                child: provider.isLoadingBrands
                    ? const Center(child: CircularProgressIndicator())
                    : provider.filteredBrands.isEmpty
                        ? _buildEmptyState()
                        : RefreshIndicator(
                            onRefresh: () => provider.loadAvailableBrands(),
                            child: ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.all(16),
                              itemCount: _getVariantsCount(provider),
                              itemBuilder: (context, index) {
                                return _buildVariantCard(provider, index);
                              },
                            ),
                          ),
              ),
            ],
          ),

          // Floating Action Button
          floatingActionButton: provider.selectedVariantsCount > 0
              ? FloatingActionButton.extended(
                  onPressed: provider.isOnboarding
                      ? null
                      : () => _onboardBrandsWithStock(provider),
                  backgroundColor: AppColors.primary,
                  icon: provider.isOnboarding
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.download, color: Colors.white),
                  label: Text(
                    provider.isOnboarding
                        ? 'Saving...'
                        : 'Onboard (${provider.selectedVariantsCount})',
                    style: const TextStyle(color: Colors.white),
                  ),
                )
              : null,
          floatingActionButtonLocation:
              FloatingActionButtonLocation.centerFloat,
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
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
            'No brands found',
            style: AppTextStyles.bodyLarge.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try adjusting your filters',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  int _getVariantsCount(BrandOnboardingProvider provider) {
    return provider.filteredBrands.fold(
      0,
      (sum, brand) => sum + brand.variants.length,
    );
  }

  Widget _buildVariantCard(BrandOnboardingProvider provider, int index) {
    // Flatten all variants across filtered brands
    final allVariants = <({String brandName, dynamic variant})>[];

    for (var brand in provider.filteredBrands) {
      for (var variant in brand.variants) {
        allVariants.add((brandName: brand.name, variant: variant));
      }
    }

    if (index >= allVariants.length) return const SizedBox.shrink();

    final item = allVariants[index];

    return BrandVariantCardWithStock(
      variant: item.variant,
      brandName: item.brandName,
      isSelected: provider.isVariantSelected(item.variant.id),
      stockQuantity: provider.getVariantStock(item.variant.id),
      showStockInput: _showStockInput,
      onSelectionChanged: (selected) {
        // Find the brand ID for this variant
        final brand = provider.filteredBrands.firstWhere(
          (b) => b.variants.any((v) => v.id == item.variant.id),
        );
        provider.toggleVariant(brand.id, item.variant.id);
      },
      onStockChanged: (quantity) {
        provider.setVariantStock(item.variant.id, quantity);
      },
    );
  }
}
