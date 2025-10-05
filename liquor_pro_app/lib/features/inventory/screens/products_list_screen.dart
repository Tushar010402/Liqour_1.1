import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../providers/product_provider.dart';
import '../models/product.dart';
import 'enhanced_brand_catalog_screen.dart';
import 'edit_product_screen.dart';
import 'add_product_screen.dart';

/// Products List Screen - Inventory management with responsive design
class ProductsListScreen extends StatefulWidget {
  const ProductsListScreen({super.key});

  @override
  State<ProductsListScreen> createState() => _ProductsListScreenState();
}

class _ProductsListScreenState extends State<ProductsListScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _viewMode = 'list'; // 'list' or 'grid'

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProductProvider>().initialize();
    });
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.9) {
      context.read<ProductProvider>().loadMoreProducts();
    }
  }

  Future<void> _handleRefresh() async {
    await context.read<ProductProvider>().refreshProducts();
  }

  String _formatCurrency(double amount) {
    final formatter = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    );
    return formatter.format(amount);
  }

  void _showFilterSheet() {
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
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
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
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;

    return Scaffold(
      appBar: CustomAppBar(
        title: 'Inventory',
        actions: [
          IconButton(
            icon: Icon(_viewMode == 'grid' ? Icons.view_list : Icons.grid_view),
            onPressed: () {
              setState(() {
                _viewMode = _viewMode == 'grid' ? 'list' : 'grid';
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterSheet,
          ),
        ],
      ),
      body: Consumer<ProductProvider>(
        builder: (context, provider, _) {
          return Column(
            children: [
              // Search Bar & Quick Actions
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Search Field
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search by name, barcode, or SKU...',
                        hintStyle: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_searchController.text.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.clear, size: 20),
                                onPressed: () {
                                  _searchController.clear();
                                  provider.applySearch('');
                                },
                              ),
                            IconButton(
                              icon: const Icon(Icons.qr_code_scanner, size: 20),
                              tooltip: 'Scan Barcode',
                              onPressed: () {
                                // TODO: Integrate barcode scanner
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
                          borderRadius: BorderRadius.circular(12),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.primary, width: 2),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      onChanged: (value) {
                        provider.applySearch(value);
                      },
                    ),
                    const SizedBox(height: 12),

                    // Quick Action - Onboard Brands
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const EnhancedBrandCatalogScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.download),
                        label: const Text('Onboard Brands'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: const BorderSide(color: AppColors.primary),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Statistics Summary
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    bottom: BorderSide(color: AppColors.border.withOpacity(0.3)),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        label: 'Total',
                        value: '${provider.products.length}',
                        icon: Icons.inventory_2,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        label: 'Low Stock',
                        value: '${provider.lowStockCount}',
                        icon: Icons.warning_amber_rounded,
                        color: AppColors.warning,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        label: 'Out',
                        value: '${provider.outOfStockCount}',
                        icon: Icons.error_outline,
                        color: AppColors.error,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        label: 'Value',
                        value: _formatCurrency(provider.totalInventoryValue),
                        icon: Icons.account_balance_wallet,
                        color: AppColors.success,
                        isCompact: true,
                      ),
                    ),
                  ],
                ),
              ),

              // Quick Filter Tabs
              Container(
                height: 50,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    bottom: BorderSide(color: AppColors.border.withOpacity(0.5)),
                  ),
                ),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _buildQuickFilterChip(
                      label: 'All Products',
                      isSelected: provider.selectedCategoryId == null && provider.selectedBrandId == null,
                      icon: Icons.apps,
                      onTap: () => provider.clearFilters(),
                    ),
                    const SizedBox(width: 8),
                    _buildQuickFilterChip(
                      label: 'Low Stock',
                      isSelected: provider.stockFilter == 'low_stock',
                      icon: Icons.warning_amber_rounded,
                      iconColor: AppColors.warning,
                      onTap: () {
                        if (provider.stockFilter == 'low_stock') {
                          provider.applyStockFilter(null);
                        } else {
                          provider.applyStockFilter('low_stock');
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    _buildQuickFilterChip(
                      label: 'Out of Stock',
                      isSelected: provider.stockFilter == 'out_of_stock',
                      icon: Icons.error_outline,
                      iconColor: AppColors.error,
                      onTap: () {
                        if (provider.stockFilter == 'out_of_stock') {
                          provider.applyStockFilter(null);
                        } else {
                          provider.applyStockFilter('out_of_stock');
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    if (provider.categories.isNotEmpty) ...[
                      ...provider.categories.take(3).map(
                            (category) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: _buildQuickFilterChip(
                                label: category.name,
                                isSelected: provider.selectedCategoryId == category.id,
                                onTap: () {
                                  if (provider.selectedCategoryId == category.id) {
                                    provider.applyCategory(null);
                                  } else {
                                    provider.applyCategory(category.id);
                                  }
                                },
                              ),
                            ),
                          ),
                    ],
                  ],
                ),
              ),

              // Active Filters (if any custom filters applied)
              if (provider.selectedCategoryId != null || provider.selectedBrandId != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.05),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.filter_alt, size: 16, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              if (provider.selectedCategoryId != null) ...[
                                Chip(
                                  label: Text(
                                    provider.categories
                                        .firstWhere((c) => c.id == provider.selectedCategoryId)
                                        .name,
                                  ),
                                  deleteIcon: const Icon(Icons.close, size: 16),
                                  onDeleted: () => provider.applyCategory(null),
                                  backgroundColor: AppColors.primary.withOpacity(0.1),
                                ),
                                const SizedBox(width: 8),
                              ],
                              if (provider.selectedBrandId != null) ...[
                                Chip(
                                  label: Text(
                                    provider.brands
                                        .firstWhere((b) => b.id == provider.selectedBrandId)
                                        .name,
                                  ),
                                  deleteIcon: const Icon(Icons.close, size: 16),
                                  onDeleted: () => provider.applyBrand(null),
                                  backgroundColor: AppColors.primary.withOpacity(0.1),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => provider.clearFilters(),
                        child: const Text('Clear All'),
                      ),
                    ],
                  ),
                ),

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
                                      color: AppColors.textSecondary.withOpacity(0.5),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'No products found',
                                      style: AppTextStyles.bodyLarge.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Onboard brands to get started',
                                      style: AppTextStyles.bodySmall,
                                    ),
                                    const SizedBox(height: 16),
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => const EnhancedBrandCatalogScreen(),
                                          ),
                                        );
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
      floatingActionButton: FloatingActionButton.extended(
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
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Add Product',
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildGridView(ProductProvider provider, bool isTablet) {
    final products = provider.filteredProducts;
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
    final products = provider.filteredProducts;
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
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.3),
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
                      color: color.withOpacity(0.2),
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
                color: color.withOpacity(0.8),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
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
                color: isSelected ? Colors.white : (iconColor ?? AppColors.textSecondary),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                color: isSelected ? Colors.white : AppColors.textPrimary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductCard(Product product, ProductProvider provider) {
    final stock = provider.getStockForProduct(product.id);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EditProductScreen(product: product),
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
                  color: AppColors.surface,
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
                      const Center(
                        child: Icon(Icons.liquor, size: 48, color: AppColors.textSecondary),
                      ),
                    // Stock Badge
                    if (stock != null)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: stock.isOutOfStock
                                ? AppColors.error
                                : stock.isLowStock
                                    ? AppColors.warning
                                    : AppColors.success,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${stock.quantity}',
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
                      color: AppColors.textSecondary,
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
                          color: AppColors.primary,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.success.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'MRP ${_formatCurrency(product.mrp)}',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.success,
                            fontSize: 10,
                          ),
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
    final stock = provider.getStockForProduct(product.id);
    final profit = product.sellingPrice - product.costPrice;
    final profitMargin = (profit / product.costPrice * 100);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: stock != null && stock.isLowStock
              ? AppColors.warning.withOpacity(0.3)
              : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: InkWell(
        onTap: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EditProductScreen(product: product),
            ),
          );
          if (result == true) {
            provider.refreshProducts();
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product Image with Stock Badge
              Stack(
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      image: product.imageUrl.isNotEmpty
                          ? DecorationImage(
                              image: NetworkImage(product.imageUrl),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: product.imageUrl.isEmpty
                        ? const Icon(Icons.liquor, size: 32, color: AppColors.textSecondary)
                        : null,
                  ),
                  // Stock Badge
                  if (stock != null)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: stock.isOutOfStock
                              ? AppColors.error
                              : stock.isLowStock
                                  ? AppColors.warning
                                  : AppColors.success,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Text(
                          '${stock.quantity}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),

              // Product Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product Name
                    Text(
                      product.name,
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),

                    // Brand & Size
                    Row(
                      children: [
                        if (product.brand != null) ...[
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                product.brand!.name,
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.primary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(
                            product.size,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (product.alcoholContent > 0) ...[
                          const SizedBox(width: 6),
                          Text(
                            '${product.alcoholContent}%',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Pricing & Profit Info
                    Row(
                      children: [
                        // Selling Price
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Selling',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.textSecondary,
                                  fontSize: 10,
                                ),
                              ),
                              Text(
                                _formatCurrency(product.sellingPrice),
                                style: AppTextStyles.bodyLarge.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Profit
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Profit',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.textSecondary,
                                  fontSize: 10,
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      _formatCurrency(profit),
                                      style: AppTextStyles.bodyMedium.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.success,
                                        fontSize: 13,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 3),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: AppColors.success.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(
                                      '${profitMargin.toStringAsFixed(0)}%',
                                      style: AppTextStyles.bodySmall.copyWith(
                                        color: AppColors.success,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Quick Actions
              Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // MRP Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: AppColors.warning.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      'MRP ${_formatCurrency(product.mrp)}',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.warning,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Status Indicator
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: product.isActive
                          ? AppColors.success.withOpacity(0.1)
                          : AppColors.error.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
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
    );
  }
}
