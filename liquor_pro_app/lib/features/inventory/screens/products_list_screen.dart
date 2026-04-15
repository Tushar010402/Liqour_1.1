import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/providers/shop_selection_provider.dart';
import '../../../core/widgets/shop_selector_widget.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../providers/product_provider.dart';
import '../models/product.dart';
import '../models/brand_variant_edit_model.dart';
import 'brand_catalog_v2_screen.dart';
import 'edit_brand_variant_screen.dart';
import 'add_product_screen.dart';

/// Products List Screen - Inventory management with responsive design
class ProductsListScreen extends StatefulWidget {
  const ProductsListScreen({super.key});

  @override
  State<ProductsListScreen> createState() => _ProductsListScreenState();
}

class _ProductsListScreenState extends State<ProductsListScreen> with WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _viewMode = 'list'; // 'list' or 'grid'
  bool _isInitialLoad = true;
  bool _hasRestoredFilters = false; // Track if filters have been restored from provider

  // Inline filter state (synced with provider for persistence across navigation)
  String? _selectedCategoryName;        // Single-select category
  final Set<String> _selectedSizes = {}; // Multi-select sizes

  // === MULTI-SELECT STATE FOR STOCK PURCHASE ===
  final Set<String> _selectedProductIds = {};
  bool get _isSelectionMode => _selectedProductIds.isNotEmpty;

  /// Toggle product selection for stock purchase
  void _toggleProductSelection(String productId) {
    setState(() {
      if (_selectedProductIds.contains(productId)) {
        _selectedProductIds.remove(productId);
      } else {
        _selectedProductIds.add(productId);
      }
    });
  }

  /// Clear all selections
  void _clearSelection() {
    setState(() {
      _selectedProductIds.clear();
    });
  }

  /// Get selected products list
  List<Product> _getSelectedProducts(ProductProvider provider) {
    return provider.products.where((p) => _selectedProductIds.contains(p.id)).toList();
  }

  /// Build selection footer for stock purchase
  Widget _buildSelectionFooter(ProductProvider provider) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outline.withValues(alpha: 0.2))),
      ),
      child: Row(
        children: [
          // Selection count
          Expanded(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.shopping_cart,
                    color: cs.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_selectedProductIds.length} products selected',
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    GestureDetector(
                      onTap: _clearSelection,
                      child: Text(
                        'Clear all',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.error,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Next button
          ElevatedButton.icon(
            onPressed: () => _showStockPurchaseSheet(provider),
            style: ElevatedButton.styleFrom(
              backgroundColor: cs.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: const Text(
              'Next',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  /// Show stock purchase bottom sheet
  void _showStockPurchaseSheet(ProductProvider provider) {
    final selectedProducts = _getSelectedProducts(provider);
    final shopProvider = context.read<ShopSelectionProvider>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _StockPurchaseBottomSheet(
        products: selectedProducts,
        shopName: shopProvider.selectedShopName ?? 'Shop',
        onConfirm: (quantities, vendorId) async {
          // TODO: Implement stock purchase API call
          Navigator.pop(context);
          _clearSelection();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Stock purchase recorded successfully!'),
              backgroundColor: AppColors.success,
            ),
          );
          // Refresh products
          provider.refreshProducts();
        },
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    // Add app lifecycle observer for app resume detection
    WidgetsBinding.instance.addObserver(this);

    print('🎯 ═══════════════════════════════════════════════════════════');
    print('🎯 SCREEN OPENED: ProductsListScreen (Legacy List View)');
    print('🎯 FILE: products_list_screen.dart');
    print('🎯 ═══════════════════════════════════════════════════════════');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final shopId = context.read<ShopSelectionProvider>().selectedShopId;
      final productProvider = context.read<ProductProvider>();
      productProvider.loadProducts(shopId: shopId);
      productProvider.loadCategories();
      productProvider.loadBrands();
      _isInitialLoad = false;
    });
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Restore filters from provider (persisted across navigation)
    _restoreFiltersFromProvider();
    // Auto-refresh when screen becomes visible (after navigation back)
    // Provider's refreshProducts() now uses stored filters
    if (!_isInitialLoad && mounted) {
      _handleRefresh();
    }
  }

  @override
  void dispose() {
    // Remove app lifecycle observer
    WidgetsBinding.instance.removeObserver(this);

    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Auto-refresh when app resumes from background
    if (state == AppLifecycleState.resumed && mounted) {
      _handleRefresh();
    }
  }

  void _onScroll() {
    // Dismiss keyboard when scrolling (best practice for data entry screens)
    _dismissKeyboard();

    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.9) {
      context.read<ProductProvider>().loadMoreProducts();
    }
  }

  /// Dismiss keyboard when tapping outside input fields or scrolling
  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _handleRefresh() async {
    // Refresh using provider's stored filters (persists across navigation)
    await context.read<ProductProvider>().refreshProducts();
  }

  /// Restore filters from provider (called on navigation back)
  /// Always re-syncs from provider to handle cases where another screen
  /// (e.g., Daily Sales Entry) modified the provider's filter state
  void _restoreFiltersFromProvider() {
    final provider = context.read<ProductProvider>();

    final providerCategoryName = provider.selectedCategoryName;
    final providerSize = provider.selectedSize;
    final currentLocalSize = _selectedSizes.isNotEmpty ? _selectedSizes.first : null;

    // Check if provider state differs from local state
    final hasChanged = _selectedCategoryName != providerCategoryName ||
        currentLocalSize != providerSize;

    if (!hasChanged && _hasRestoredFilters) return; // No change, skip

    setState(() {
      _selectedCategoryName = providerCategoryName;
      _selectedSizes.clear();
      if (providerSize != null) {
        _selectedSizes.add(providerSize);
      }
      _hasRestoredFilters = true;
    });
    print('🔄 [ProductsListScreen] Restored filters: category=$_selectedCategoryName, sizes=$_selectedSizes');
  }

  /// Sync local filter state to provider (for persistence)
  void _syncFiltersToProvider() {
    final provider = context.read<ProductProvider>();
    provider.setSelectedCategory(
      _selectedCategoryName != null ? _getCategoryIdByName(_selectedCategoryName!) : null,
      _selectedCategoryName,
    );
    provider.setSelectedSize(_selectedSizes.isNotEmpty ? _selectedSizes.first : null);
  }

  /// Get category ID by name (helper method)
  String? _getCategoryIdByName(String name) {
    final provider = context.read<ProductProvider>();
    try {
      final category = provider.categories.firstWhere((c) => c.name == name);
      return category.id;
    } catch (e) {
      return null;
    }
  }

  String _formatCurrency(double amount) {
    final formatter = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    );
    return formatter.format(amount);
  }

  /// Get unique category names from products
  List<String> _getAvailableCategories(List<Product> products) {
    final categories = <String>{};
    for (var product in products) {
      if (product.category != null && product.category!.name.isNotEmpty) {
        categories.add(product.category!.name);
      }
    }
    return categories.toList()..sort();
  }

  /// Get unique sizes from products
  List<String> _getAvailableSizes(List<Product> products) {
    final sizes = <String>{};
    for (var product in products) {
      if (product.size.isNotEmpty) {
        sizes.add(product.size.toUpperCase());
      }
    }
    // Sort by numeric value
    final sizeList = sizes.toList();
    sizeList.sort((a, b) {
      final aNum = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      final bNum = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      return aNum.compareTo(bNum);
    });
    return sizeList;
  }

  /// Filter products based on selected category and sizes
  List<Product> _filterProducts(List<Product> products) {
    return products.where((product) {
      // Category filter (single-select)
      if (_selectedCategoryName != null) {
        if (product.category?.name != _selectedCategoryName) {
          return false;
        }
      }
      // Size filter (multi-select)
      if (_selectedSizes.isNotEmpty) {
        if (!_selectedSizes.contains(product.size.toUpperCase())) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  /// Clear all inline filters
  void _clearInlineFilters() {
    setState(() {
      _selectedCategoryName = null;
      _selectedSizes.clear();
    });
    _syncFiltersToProvider(); // Persist to provider
    print('🧹 [ProductsListScreen] All inline filters cleared');
  }

  /// Build Category filter section with stock quantity badges
  Widget _buildCategoryFilterSection(List<Product> products) {
    final cs = Theme.of(context).colorScheme;
    final categories = _getAvailableCategories(products);
    if (categories.isEmpty) return const SizedBox.shrink();

    // Calculate total stock for each category
    Map<String, int> categoryStockMap = {};
    for (var category in categories) {
      final stockForCategory = products
          .where((p) => p.category?.name == category)
          .fold<int>(0, (sum, p) => sum + (p.stockQuantity ?? 0));
      categoryStockMap[category] = stockForCategory;
    }

    // Calculate total stock for "All"
    final totalStock = products.fold<int>(0, (sum, p) => sum + (p.stockQuantity ?? 0));

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          bottom: BorderSide(color: cs.outline.withValues(alpha: 0.3)),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // "All" option with total stock badge
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildCategoryChipWithStock(
                label: 'All',
                stockQuantity: totalStock,
                isSelected: _selectedCategoryName == null,
                onSelected: (selected) {
                  if (selected) {
                    setState(() => _selectedCategoryName = null);
                    _syncFiltersToProvider();
                  }
                },
              ),
            ),
            // Category chips with stock badges
            ...categories.map((category) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildCategoryChipWithStock(
                label: category,
                stockQuantity: categoryStockMap[category] ?? 0,
                isSelected: _selectedCategoryName == category,
                onSelected: (selected) {
                  setState(() {
                    _selectedCategoryName = selected ? category : null;
                  });
                  _syncFiltersToProvider();
                },
              ),
            )),
          ],
        ),
      ),
    );
  }

  /// Category chip with stock quantity badge at bottom-right
  Widget _buildCategoryChipWithStock({
    required String label,
    required int stockQuantity,
    required bool isSelected,
    required Function(bool) onSelected,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isOutOfStock = stockQuantity <= 0;
    final isLowStock = stockQuantity > 0 && stockQuantity <= 20;

    // Get emoji for category
    String emoji = '📦';
    switch (label.toLowerCase()) {
      case 'whisky':
      case 'whiskey':
        emoji = '🥃';
        break;
      case 'beer':
        emoji = '🍺';
        break;
      case 'wine':
        emoji = '🍷';
        break;
      case 'vodka':
      case 'gin':
        emoji = '🍸';
        break;
      case 'rum':
        emoji = '🥃';
        break;
      case 'brandy':
        emoji = '🍷';
        break;
      case 'all':
        emoji = '📦';
        break;
    }

    return GestureDetector(
      onTap: () => onSelected(!isSelected),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Main chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? cs.primary : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20),
              border: isSelected
                  ? null
                  : Border.all(color: cs.outlineVariant, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : cs.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),

          // Stock quantity badge at bottom-right
          Positioned(
            bottom: -6,
            right: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isOutOfStock
                    ? AppColors.error
                    : isLowStock
                        ? AppColors.warning
                        : AppColors.success,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cs.surface, width: 1.5),
              ),
              child: Text(
                stockQuantity > 999 ? '999+' : '$stockQuantity',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build Size filter section (multi-select) with stock quantity badges
  Widget _buildSizeFilterSection(List<Product> products) {
    final cs = Theme.of(context).colorScheme;
    final sizes = _getAvailableSizes(products);
    if (sizes.isEmpty) return const SizedBox.shrink();

    // Calculate total stock for each size
    Map<String, int> sizeStockMap = {};
    for (var size in sizes) {
      final stockForSize = products
          .where((p) => p.size.toUpperCase() == size.toUpperCase())
          .fold<int>(0, (sum, p) => sum + (p.stockQuantity ?? 0));
      sizeStockMap[size] = stockForSize;
    }

    // Calculate total stock for "All"
    final totalStock = products.fold<int>(0, (sum, p) => sum + (p.stockQuantity ?? 0));

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 14),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          bottom: BorderSide(color: cs.outline.withValues(alpha: 0.3)),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        child: Row(
          children: [
            // "All" option with total stock badge
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildSizeChipWithStock(
                label: 'All',
                stockQuantity: totalStock,
                isSelected: _selectedSizes.isEmpty,
                onSelected: (selected) {
                  if (selected) {
                    setState(() => _selectedSizes.clear());
                    _syncFiltersToProvider();
                  }
                },
              ),
            ),
            // Size chips with stock quantity badges
            ...sizes.map((size) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildSizeChipWithStock(
                label: size,
                stockQuantity: sizeStockMap[size] ?? 0,
                isSelected: _selectedSizes.contains(size),
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedSizes.add(size);
                    } else {
                      _selectedSizes.remove(size);
                    }
                  });
                  _syncFiltersToProvider();
                },
                isMultiSelect: true,
              ),
            )),
          ],
        ),
      ),
    );
  }

  /// Size chip with stock quantity badge at bottom-right
  Widget _buildSizeChipWithStock({
    required String label,
    required int stockQuantity,
    required bool isSelected,
    required Function(bool) onSelected,
    bool isMultiSelect = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isOutOfStock = stockQuantity <= 0;
    final isLowStock = stockQuantity > 0 && stockQuantity <= 10;

    return GestureDetector(
      onTap: () => onSelected(!isSelected),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Main chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? cs.primary : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20),
              border: isSelected
                  ? null
                  : Border.all(color: cs.outlineVariant, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isMultiSelect && isSelected) ...[
                  const Icon(Icons.check, size: 16, color: Colors.white),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : cs.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),

          // Stock quantity badge at bottom-right
          Positioned(
            bottom: -6,
            right: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isOutOfStock
                    ? AppColors.error
                    : isLowStock
                        ? AppColors.warning
                        : AppColors.success,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cs.surface, width: 1.5),
              ),
              child: Text(
                stockQuantity > 999 ? '999+' : '$stockQuantity',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showFilterSheet() {
    final cs = Theme.of(context).colorScheme;
    final provider = context.read<ProductProvider>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.8,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Filters', style: AppTextStyles.h5),
                    TextButton(
                      onPressed: () {
                        provider.clearFilters();
                        Navigator.pop(context);
                      },
                      child: const Text('Clear All'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Filters
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Category Filter
                    Text('Category', style: AppTextStyles.h6),
                    const SizedBox(height: 12),
                    Consumer<ProductProvider>(
                      builder: (context, provider, _) {
                        if (provider.isCategoriesLoading) {
                          return const CircularProgressIndicator();
                        }
                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('All'),
                              selected: provider.selectedCategoryId == null,
                              onSelected: (_) => provider.applyCategory(null),
                            ),
                            ...provider.categories.map(
                              (category) => ChoiceChip(
                                label: Text(category.name),
                                selected: provider.selectedCategoryId == category.id,
                                onSelected: (_) => provider.applyCategory(category.id),
                              ),
                            ),
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 24),

                    // Brand Filter
                    Text('Brand', style: AppTextStyles.h6),
                    const SizedBox(height: 12),
                    Consumer<ProductProvider>(
                      builder: (context, provider, _) {
                        if (provider.isBrandsLoading) {
                          return const CircularProgressIndicator();
                        }
                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('All'),
                              selected: provider.selectedBrandId == null,
                              onSelected: (_) => provider.applyBrand(null),
                            ),
                            ...provider.brands.map(
                              (brand) => ChoiceChip(
                                label: Text(brand.name),
                                selected: provider.selectedBrandId == brand.id,
                                onSelected: (_) => provider.applyBrand(brand.id),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),

              // Apply Button
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    child: const Text('Apply Filters'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;

    return Scaffold(
      appBar: CustomAppBar(
        title: 'Inventory',
        actions: [
          // View toggle button (list/grid)
          IconButton(
            icon: Icon(_viewMode == 'grid' ? Icons.view_list : Icons.grid_view),
            onPressed: () {
              setState(() {
                _viewMode = _viewMode == 'grid' ? 'list' : 'grid';
              });
            },
          ),
          // Filter modal removed - using inline chips now
        ],
      ),
      body: GestureDetector(
        onTap: _dismissKeyboard,
        behavior: HitTestBehavior.translucent,
        child: Consumer<ProductProvider>(
          builder: (context, provider, _) {
            return Column(
            children: [
              // Shop Selector - Compact
              Container(
                color: cs.surface,
                child: ShopSelectorWidget(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  onShopChanged: (shopId) {
                    // Clear local filter state when shop changes
                    setState(() {
                      _selectedCategoryName = null;
                      _selectedSizes.clear();
                      _hasRestoredFilters = false;
                    });
                    // Clear provider filters and reload for new shop
                    provider.clearAllFilters();
                    provider.loadProducts(shopId: shopId);
                    print('🔄 [ProductsListScreen] Shop changed - filters cleared, loading new shop: $shopId');
                  },
                ),
              ),

              // Search Bar & Quick Actions - Compact
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.surface,
                  border: Border(bottom: BorderSide(color: cs.outline.withValues(alpha: 0.2))),
                ),
                child: Column(
                  children: [
                    // Search Field - Compact
                    SizedBox(
                      height: 40,
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Search by name, barcode, or SKU...',
                          hintStyle: AppTextStyles.bodySmall.copyWith(
                            color: cs.onSurfaceVariant,
                            fontSize: 13,
                          ),
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_searchController.text.isNotEmpty)
                                IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    _searchController.clear();
                                    provider.applySearch('');
                                  },
                                ),
                              IconButton(
                                icon: const Icon(Icons.qr_code_scanner, size: 18),
                                tooltip: 'Scan Barcode',
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Barcode scanner coming soon'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: cs.outline),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: cs.primary, width: 2),
                          ),
                          filled: true,
                          fillColor: cs.surface,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        onChanged: (value) {
                          provider.applySearch(value);
                        },
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Quick Action - Onboard Brands - Compact
                    SizedBox(
                      width: double.infinity,
                      height: 36,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final productProvider = context.read<ProductProvider>();
                          final shopProvider = context.read<ShopSelectionProvider>();
                          final shopId = shopProvider.selectedShopId;

                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const BrandCatalogV2Screen(),
                            ),
                          );

                          if (result == true && mounted) {
                            await productProvider.loadProducts(shopId: shopId);
                          }
                        },
                        icon: const Icon(Icons.download, size: 18),
                        label: const Text('Onboard Brands', style: TextStyle(fontSize: 13)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          side: BorderSide(color: cs.primary),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Statistics Summary - Compact (Hidden to save space)
              // Uncomment if stats are needed
              /*
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.surface,
                  border: Border(
                    bottom: BorderSide(color: cs.outline.withValues(alpha:0.3)),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(child: _buildStatCard(label: 'Total', value: '${provider.products.length}', icon: Icons.inventory_2, color: cs.primary)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildStatCard(label: 'Low', value: '${provider.lowStockCount}', icon: Icons.warning_amber_rounded, color: AppColors.warning)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildStatCard(label: 'Out', value: '${provider.outOfStockCount}', icon: Icons.error_outline, color: AppColors.error)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildStatCard(label: 'Value', value: _formatCurrency(provider.totalInventoryValue), icon: Icons.account_balance_wallet, color: AppColors.success, isCompact: true)),
                  ],
                ),
              ),
              */

              // Category Filter Chips
              _buildCategoryFilterSection(provider.products),

              // Size Filter Chips
              _buildSizeFilterSection(provider.products),

              // Products List
              Expanded(
                child: provider.isLoading && provider.filteredProducts.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : provider.errorMessage != null && provider.filteredProducts.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.error_outline, size: 64, color: AppColors.error),
                                const SizedBox(height: 16),
                                Text(
                                  provider.errorMessage!,
                                  style: AppTextStyles.bodyLarge,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: () => provider.refreshProducts(),
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          )
                        : provider.filteredProducts.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.inventory_2_outlined,
                                      size: 64,
                                      color: cs.onSurfaceVariant.withValues(alpha:0.5),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'No products found',
                                      style: AppTextStyles.bodyLarge.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Onboard brands to get started',
                                      style: AppTextStyles.bodySmall,
                                    ),
                                    const SizedBox(height: 16),
                                    ElevatedButton.icon(
                                      onPressed: () async {
                                        // Capture providers BEFORE navigation
                                        final productProvider = context.read<ProductProvider>();
                                        final shopProvider = context.read<ShopSelectionProvider>();
                                        final shopId = shopProvider.selectedShopId;

                                        // Navigate to brand catalog and wait for result
                                        final result = await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => const BrandCatalogV2Screen(),
                                          ),
                                        );

                                        // If brands were imported, refresh inventory
                                        if (result == true && mounted) {
                                          print('🔄 [ProductsListScreen] Brands imported - refreshing product provider');
                                          await productProvider.loadProducts(shopId: shopId);
                                          print('✅ [ProductsListScreen] Product list refreshed after brand import');
                                        }
                                      },
                                      icon: const Icon(Icons.download),
                                      label: const Text('Onboard Brands'),
                                    ),
                                  ],
                                ),
                              )
                            : RefreshIndicator(
                                onRefresh: _handleRefresh,
                                child: _viewMode == 'grid'
                                    ? _buildGridView(provider, isTablet)
                                    : _buildListView(provider),
                              ),
              ),
            ],
          );
          },
        ),
      ),
      // Conditionally show FAB or hide when in selection mode
      floatingActionButton: _isSelectionMode
          ? null
          : FloatingActionButton.extended(
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AddProductScreen(),
                  ),
                );
                // Refresh list if product was added
                if (result == true && mounted) {
                  context.read<ProductProvider>().refreshProducts();
                }
              },
              backgroundColor: cs.primary,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'Add Product',
                style: TextStyle(color: Colors.white),
              ),
            ),
      // Show selection footer when products are selected
      bottomNavigationBar: _isSelectionMode
          ? _buildSelectionFooter(context.read<ProductProvider>())
          : null,
    );
  }

  Widget _buildGridView(ProductProvider provider, bool isTablet) {
    final products = _filterProducts(provider.filteredProducts);
    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isTablet ? 4 : 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.7,
      ),
      itemCount: products.length + (provider.hasMore && provider.stockFilter == null ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == products.length) {
          return const Center(child: CircularProgressIndicator());
        }
        final product = products[index];
        return _buildProductCard(product, provider);
      },
    );
  }

  Widget _buildListView(ProductProvider provider) {
    final products = _filterProducts(provider.filteredProducts);
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: products.length + (provider.hasMore && provider.stockFilter == null ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == products.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          );
        }
        final product = products[index];
        return _buildProductListTile(product, provider);
      },
    );
  }

  Widget _buildStatCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    bool isCompact = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha:0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha:0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              if (!isCompact) ...[
                const SizedBox(width: 4),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha:0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      label,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: color,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: AppTextStyles.h6.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: isCompact ? 13 : 18,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (isCompact) ...[
            const SizedBox(height: 2),
            Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                color: color.withValues(alpha:0.8),
                fontSize: 9,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickFilterChip({
    required String label,
    required bool isSelected,
    IconData? icon,
    Color? iconColor,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? cs.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? cs.primary : cs.outline,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 16,
                color: isSelected ? Colors.white : (iconColor ?? cs.onSurfaceVariant),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                color: isSelected ? Colors.white : cs.onSurface,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductCard(Product product, ProductProvider provider) {
    final cs = Theme.of(context).colorScheme;
    // Get stock quantity from product (with fallback from Stock if available)
    final stockQuantity = product.stockQuantity ?? 0;
    final isOutOfStock = stockQuantity <= 0;
    final isLowStock = stockQuantity > 0 && stockQuantity <= 10;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: InkWell(
        onTap: () async {
          // Convert product to brand variant edit model
          final editModel = BrandVariantEditModel.fromProduct(product);
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EditBrandVariantScreen(variant: editModel),
            ),
          );
          // Refresh list if product was updated
          if (result == true) {
            provider.refreshProducts();
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product Image
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  image: product.imageUrl.isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(product.imageUrl),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: Stack(
                  children: [
                    if (product.imageUrl.isEmpty)
                      Center(
                        child: Icon(Icons.liquor, size: 48, color: cs.onSurfaceVariant),
                      ),
                    // Stock Badge
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isOutOfStock
                              ? AppColors.error
                              : isLowStock
                                  ? AppColors.warning
                                  : AppColors.success,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$stockQuantity',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Product Info
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    product.size,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatCurrency(product.sellingPrice),
                        style: AppTextStyles.bodyLarge.copyWith(
                          fontWeight: FontWeight.bold,
                          color: cs.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductListTile(Product product, ProductProvider provider) {
    final cs = Theme.of(context).colorScheme;
    // Get stock quantity from product (with fallback from Stock if available)
    final stockQuantity = product.stockQuantity ?? 0;
    final isOutOfStock = stockQuantity <= 0;
    final isLowStock = stockQuantity > 0 && stockQuantity <= 10;
    final isSelected = _selectedProductIds.contains(product.id);

    // Card height: 50% more than before (was ~90, now ~135)
    const double cardHeight = 130.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected
              ? cs.primary
              : isLowStock
                  ? AppColors.warning.withValues(alpha: 0.3)
                  : cs.outline.withValues(alpha: 0.2),
          width: isSelected ? 2.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: () async {
          // Convert product to brand variant edit model
          final editModel = BrandVariantEditModel.fromProduct(product);
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EditBrandVariantScreen(variant: editModel),
            ),
          );
          if (result == true) {
            provider.refreshProducts();
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: cardHeight,
          child: Row(
            children: [
              // ========== LEFT: IMAGE AREA (40% width) ==========
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  _toggleProductSelection(product.id);
                },
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.35, // ~40% of card
                  height: cardHeight,
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                    ),
                    border: isSelected
                        ? Border.all(color: cs.primary, width: 3)
                        : null,
                    image: product.imageUrl.isNotEmpty
                        ? DecorationImage(
                            image: NetworkImage(product.imageUrl),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: Stack(
                    children: [
                      // Placeholder icon when no image
                      if (product.imageUrl.isEmpty)
                        Center(
                          child: Icon(
                            Icons.liquor,
                            size: 48,
                            color: cs.onSurfaceVariant,
                          ),
                        ),

                      // Plus button for selection (top-right of image)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? cs.primary
                                : cs.surface,
                            shape: BoxShape.circle,
                            border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
                          ),
                          child: Icon(
                            isSelected ? Icons.check : Icons.add,
                            size: 20,
                            color: isSelected ? Colors.white : cs.primary,
                          ),
                        ),
                      ),

                      // Stock badge (bottom-right of image)
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isOutOfStock
                                ? AppColors.error
                                : isLowStock
                                    ? AppColors.warning
                                    : AppColors.success,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$stockQuantity',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ========== RIGHT: INFO AREA (60% width) ==========
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Row 1: Brand Name (top)
                      Text(
                        product.brand?.name ?? product.name.split(' - ').first,
                        style: AppTextStyles.bodyLarge.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),

                      // Row 2: Category + Size (inline)
                      Row(
                        children: [
                          // Category chip
                          if (product.category != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: cs.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                product.category!.name,
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: cs.primary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          // Size badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              product.size.toUpperCase(),
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.accent,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),

                      // Row 3: Price + Status (bottom)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // Price (prominent)
                          Text(
                            _formatCurrency(product.sellingPrice),
                            style: AppTextStyles.h5.copyWith(
                              fontWeight: FontWeight.bold,
                              color: cs.primary,
                              fontSize: 20,
                            ),
                          ),

                          // Active/Inactive status
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: product.isActive
                                  ? AppColors.success.withValues(alpha: 0.1)
                                  : AppColors.error.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: product.isActive ? AppColors.success : AppColors.error,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  product.isActive ? 'Active' : 'Inactive',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: product.isActive ? AppColors.success : AppColors.error,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
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
        ),
      ),
    );
  }
}

/// Stock Purchase Bottom Sheet - Quantity entry and vendor selection
class _StockPurchaseBottomSheet extends StatefulWidget {
  final List<Product> products;
  final String shopName;
  final Function(Map<String, int> quantities, String? vendorId) onConfirm;

  const _StockPurchaseBottomSheet({
    required this.products,
    required this.shopName,
    required this.onConfirm,
  });

  @override
  State<_StockPurchaseBottomSheet> createState() => _StockPurchaseBottomSheetState();
}

class _StockPurchaseBottomSheetState extends State<_StockPurchaseBottomSheet> {
  final Map<String, int> _quantities = {};
  String? _selectedVendorId;
  final _currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

  @override
  void initState() {
    super.initState();
    // Initialize quantities to 1 for each product
    for (var product in widget.products) {
      _quantities[product.id] = 1;
    }
  }

  int get _totalQuantity => _quantities.values.fold(0, (a, b) => a + b);

  double get _purchaseValue {
    double total = 0;
    for (var product in widget.products) {
      final qty = _quantities[product.id] ?? 1;
      total += product.costPrice * qty;
    }
    return total;
  }

  double get _tcsAmount => _purchaseValue * 0.02; // 2% TCS (Tax Collected at Source)

  double get _totalAmount => _purchaseValue + _tcsAmount;

  /// Group products by size for display (sorted high to low: 750ML, 375ML, 180ML, 90ML)
  Map<String, List<Product>> _groupProductsBySize() {
    final Map<String, List<Product>> grouped = {};

    for (final product in widget.products) {
      final size = product.size.toUpperCase();
      grouped.putIfAbsent(size, () => []);
      grouped[size]!.add(product);
    }

    // Sort sizes by numeric value (high to low)
    final sortedKeys = grouped.keys.toList()
      ..sort((a, b) {
        final aNum = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        final bNum = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        return bNum.compareTo(aNum); // High to low
      });

    return Map.fromEntries(sortedKeys.map((k) => MapEntry(k, grouped[k]!)));
  }

  /// Calculate stats for a size group
  Map<String, dynamic> _getSizeGroupStats(List<Product> products) {
    int totalQty = 0;
    double totalAmount = 0;

    for (final product in products) {
      final qty = _quantities[product.id] ?? 1;
      totalQty += qty;
      totalAmount += product.costPrice * qty;
    }

    return {
      'productCount': products.length,
      'totalQty': totalQty,
      'totalAmount': totalAmount,
    };
  }

  void _incrementQuantity(String productId) {
    setState(() {
      _quantities[productId] = (_quantities[productId] ?? 1) + 1;
    });
    HapticFeedback.selectionClick();
  }

  void _decrementQuantity(String productId) {
    if ((_quantities[productId] ?? 1) > 1) {
      setState(() {
        _quantities[productId] = (_quantities[productId] ?? 1) - 1;
      });
      HapticFeedback.selectionClick();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Drag Handle
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.add_shopping_cart,
                      color: cs.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Add New Stock',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Shop: ${widget.shopName}',
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    style: IconButton.styleFrom(
                      backgroundColor: cs.surfaceContainerHighest,
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Content
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                children: [
                  // Summary Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildSummaryItem('Items', '${widget.products.length}', Icons.inventory_2),
                        Container(width: 1, height: 40, color: cs.primary.withValues(alpha: 0.2)),
                        _buildSummaryItem('Total Qty', '$_totalQuantity', Icons.numbers),
                        Container(width: 1, height: 40, color: cs.primary.withValues(alpha: 0.2)),
                        _buildSummaryItem('Amount', _currencyFormat.format(_totalAmount), Icons.currency_rupee),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Products Table Header with column labels
                  Row(
                    children: [
                      const Text(
                        'Selected Items',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${widget.products.length} products',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Table Column Headers
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Expanded(flex: 3, child: Text('Product', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: cs.onSurfaceVariant))),
                        Expanded(flex: 2, child: Text('Qty', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: cs.onSurfaceVariant), textAlign: TextAlign.center)),
                        Expanded(flex: 1, child: Text('Price', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: cs.onSurfaceVariant), textAlign: TextAlign.right)),
                        Expanded(flex: 1, child: Text('Total', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: cs.onSurfaceVariant), textAlign: TextAlign.right)),
                      ],
                    ),
                  ),

                  // Size-Grouped Products
                  ..._buildSizeGroupedProducts(),

                  const SizedBox(height: 16),

                  // Price Breakdown
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        _buildPriceRow('Purchase Value', _purchaseValue),
                        const SizedBox(height: 8),
                        _buildPriceRow('TCS (2%)', _tcsAmount, isSubtle: true),
                        const Divider(height: 20),
                        _buildPriceRow('Total Amount', _totalAmount, isBold: true),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Vendor Selection
                  const Text(
                    'Select Vendor *',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: cs.outlineVariant),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedVendorId,
                        isExpanded: true,
                        hint: Row(
                          children: [
                            Icon(Icons.store, color: cs.onSurfaceVariant),
                            const SizedBox(width: 12),
                            const Text('Choose vendor...'),
                          ],
                        ),
                        items: [
                          // TODO: Replace with actual vendor list from API
                          const DropdownMenuItem(
                            value: 'vendor_1',
                            child: Text('ABC Distributors'),
                          ),
                          const DropdownMenuItem(
                            value: 'vendor_2',
                            child: Text('XYZ Suppliers'),
                          ),
                          const DropdownMenuItem(
                            value: 'vendor_3',
                            child: Text('State Beverage Corp'),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() => _selectedVendorId = value);
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),

            // Confirm Button
            Container(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: MediaQuery.of(context).padding.bottom + 12,
              ),
              decoration: BoxDecoration(
                color: cs.surface,
                border: Border(top: BorderSide(color: cs.outline.withValues(alpha: 0.2))),
              ),
              child: ElevatedButton(
                onPressed: _selectedVendorId == null
                    ? null
                    : () => widget.onConfirm(_quantities, _selectedVendorId),
                style: ElevatedButton.styleFrom(
                  backgroundColor: cs.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: cs.outlineVariant,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  minimumSize: const Size(double.infinity, 52),
                ),
                child: Text(
                  _selectedVendorId == null
                      ? 'Select a vendor to continue'
                      : 'Confirm Purchase ${_currencyFormat.format(_totalAmount)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Icon(icon, color: cs.primary, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: cs.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildProductRow(Product product) {
    final cs = Theme.of(context).colorScheme;
    final qty = _quantities[product.id] ?? 1;
    final total = product.costPrice * qty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          // Product Name (with brand)
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.brand?.name ?? product.name,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (product.brand != null && product.name != product.brand!.name)
                  Text(
                    product.name,
                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          // Quantity Stepper
          Expanded(
            flex: 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildStepperButton(Icons.remove, () => _decrementQuantity(product.id)),
                SizedBox(
                  width: 36,
                  child: Text(
                    '$qty',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                _buildStepperButton(Icons.add, () => _incrementQuantity(product.id)),
              ],
            ),
          ),
          // Unit Price
          Expanded(
            flex: 1,
            child: Text(
              '₹${product.costPrice.toInt()}',
              style: TextStyle(fontSize: 11, color: cs.onSurface),
              textAlign: TextAlign.right,
            ),
          ),
          // Total
          Expanded(
            flex: 1,
            child: Text(
              '₹${total.toInt()}',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.primary),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepperButton(IconData icon, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 14, color: cs.primary),
      ),
    );
  }

  Widget _buildPriceRow(String label, double amount, {bool isBold = false, bool isSubtle = false}) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isBold ? 15 : 13,
            fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
            color: isSubtle ? cs.onSurface : null,
          ),
        ),
        Text(
          _currencyFormat.format(amount),
          style: TextStyle(
            fontSize: isBold ? 16 : 13,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            color: isBold ? cs.primary : (isSubtle ? cs.onSurface : null),
          ),
        ),
      ],
    );
  }

  /// Size divider header with centered label
  Widget _buildSizeSubheading(String size) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 16, bottom: 8),
      child: Row(
        children: [
          Expanded(child: Divider(color: cs.primary.withValues(alpha: 0.35), thickness: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
              ),
              child: Text(
                size,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: cs.primary.withValues(alpha: 0.9),
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          Expanded(child: Divider(color: cs.primary.withValues(alpha: 0.35), thickness: 1)),
        ],
      ),
    );
  }

  /// Size group summary with product count, quantity, and total
  Widget _buildSizeGroupSummary(int productCount, int totalQty, double totalAmount) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildSummaryStat(Icons.inventory_2_outlined, 'Products', '$productCount'),
          Container(width: 1, height: 24, color: cs.primary.withValues(alpha: 0.2)),
          _buildSummaryStat(Icons.numbers, 'Qty', '$totalQty'),
          Container(width: 1, height: 24, color: cs.primary.withValues(alpha: 0.2)),
          _buildSummaryStat(Icons.currency_rupee, 'Total', '₹${totalAmount.toStringAsFixed(0)}', isPrimary: true),
        ],
      ),
    );
  }

  /// Individual stat chip for size group summary
  Widget _buildSummaryStat(IconData icon, String label, String value, {bool isPrimary = false}) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: isPrimary ? cs.primary : cs.onSurface,
        ),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isPrimary ? cs.primary : cs.onSurface,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Build size-grouped product list
  List<Widget> _buildSizeGroupedProducts() {
    final grouped = _groupProductsBySize();
    final List<Widget> widgets = [];

    for (final entry in grouped.entries) {
      final size = entry.key;
      final products = entry.value;
      final stats = _getSizeGroupStats(products);

      // Add size subheading
      widgets.add(_buildSizeSubheading(size));

      // Add product rows for this size group
      for (final product in products) {
        widgets.add(_buildProductRow(product));
      }

      // Add size group summary
      widgets.add(_buildSizeGroupSummary(
        stats['productCount'] as int,
        stats['totalQty'] as int,
        stats['totalAmount'] as double,
      ));
    }

    return widgets;
  }
}
