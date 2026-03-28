import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../providers/product_provider.dart';
import '../models/product.dart';
import '../models/product_tree.dart';
import 'edit_product_screen.dart';
import 'add_product_screen.dart';

/// Modern Tree-View Inventory Management Screen
/// Hierarchical display: Brand → Category → Subcategory → Size Variants
/// Features: Inline quantity editing, bulk actions, collapsible tree
class InventoryTreeScreen extends StatefulWidget {
  const InventoryTreeScreen({super.key});

  @override
  State<InventoryTreeScreen> createState() => _InventoryTreeScreenState();
}

class _InventoryTreeScreenState extends State<InventoryTreeScreen> {
  final TextEditingController _searchController = TextEditingController();
  Map<String, ProductBrandNode> _productTree = {};
  bool _isSearching = false;
  List<Product> _searchResults = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProductProvider>().initialize();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _buildTree(List<Product> products) {
    setState(() {
      _productTree = ProductTreeBuilder.buildTree(products);
    });
  }

  void _handleSearch(String query) {
    setState(() {
      if (query.isEmpty) {
        _isSearching = false;
        _searchResults = [];
      } else {
        _isSearching = true;
        _searchResults = ProductTreeBuilder.searchInTree(_productTree, query);
      }
    });
  }

  void _expandAll() {
    setState(() {
      ProductTreeBuilder.toggleAllNodes(_productTree, true);
    });
  }

  void _collapseAll() {
    setState(() {
      ProductTreeBuilder.toggleAllNodes(_productTree, false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: CustomAppBar(
        title: 'Inventory Management',
        actions: [
          IconButton(
            icon: const Icon(Icons.expand_more),
            onPressed: _expandAll,
            tooltip: 'Expand All',
          ),
          IconButton(
            icon: const Icon(Icons.expand_less),
            onPressed: _collapseAll,
            tooltip: 'Collapse All',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => context.read<ProductProvider>().refreshProducts(),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Consumer<ProductProvider>(
        builder: (context, provider, _) {
          // Build tree when products change
          if (provider.products.isNotEmpty && _productTree.isEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _buildTree(provider.products);
            });
          }

          if (provider.isLoading && provider.products.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.errorMessage != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: AppColors.error),
                  const SizedBox(height: 16),
                  Text(provider.errorMessage!),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => provider.refreshProducts(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (provider.products.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inventory_2_outlined, size: 64, color: cs.onSurfaceVariant),
                  const SizedBox(height: 16),
                  const Text('No products in inventory'),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AddProductScreen(),
                        ),
                      );
                      provider.refreshProducts();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add Product'),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              // Search Bar
              _buildSearchBar(),

              // Tree View or Search Results
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    await provider.refreshProducts();
                    _buildTree(provider.products);
                  },
                  child: _isSearching
                      ? _buildSearchResults()
                      : _buildTreeView(),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddProductScreen()),
          );
          context.read<ProductProvider>().refreshProducts();
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Product'),
        backgroundColor: cs.primary,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildSearchBar() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      color: cs.surface,
      child: TextField(
        controller: _searchController,
        onChanged: _handleSearch,
        decoration: InputDecoration(
          hintText: 'Search products, brands, barcodes...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _handleSearch('');
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          filled: true,
          fillColor: cs.surfaceContainerHighest,
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_searchResults.isEmpty) {
      final cs = Theme.of(context).colorScheme;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: cs.onSurfaceVariant),
            const SizedBox(height: 16),
            const Text('No products found'),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final product = _searchResults[index];
        return _ProductCard(product: product);
      },
    );
  }

  Widget _buildTreeView() {
    if (_productTree.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final brands = _productTree.values.toList()
      ..sort((a, b) => a.brandName.compareTo(b.brandName));

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: brands.length,
      itemBuilder: (context, index) {
        return _BrandTile(
          brand: brands[index],
          onToggle: () => setState(() {}),
        );
      },
    );
  }
}

/// Brand-level tile (top of tree)
class _BrandTile extends StatelessWidget {
  final ProductBrandNode brand;
  final VoidCallback onToggle;

  const _BrandTile({
    required this.brand,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              brand.isExpanded = !brand.isExpanded;
              onToggle();
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.primary,
              ),
              child: Row(
                children: [
                  Icon(
                    brand.isExpanded ? Icons.expand_more : Icons.chevron_right,
                    color: cs.onPrimary,
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.label, color: cs.onPrimary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          brand.brandName,
                          style: AppTextStyles.bodyLarge.copyWith(
                            color: cs.onPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${brand.categories.length} categories • ${brand.allProducts.length} products',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: cs.onPrimary.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${brand.totalQuantity} units',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: cs.onPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '₹${NumberFormat('#,##0').format(brand.totalValue)}',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: cs.onPrimary.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (brand.isExpanded)
            ...brand.categories.values.map((category) => _CategoryTile(
                  category: category,
                  brandName: brand.brandName,
                  onToggle: onToggle,
                )),
        ],
      ),
    );
  }
}

/// Category-level tile
class _CategoryTile extends StatelessWidget {
  final ProductCategoryNode category;
  final String brandName;
  final VoidCallback onToggle;

  const _CategoryTile({
    required this.category,
    required this.brandName,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        InkWell(
          onTap: () {
            category.isExpanded = !category.isExpanded;
            onToggle();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            margin: const EdgeInsets.only(left: 16),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              border: Border(
                left: BorderSide(color: cs.primary, width: 3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  category.isExpanded ? Icons.expand_more : Icons.chevron_right,
                  color: cs.onPrimaryContainer,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Icon(Icons.category, color: cs.onPrimaryContainer, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category.categoryName,
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                      Text(
                        '${category.subcategories.length} subcategories',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${category.totalQuantity} units',
                  style: AppTextStyles.bodySmall.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (category.isExpanded)
          ...category.subcategories.values.map((subcategory) =>
              _SubcategoryTile(
                subcategory: subcategory,
                brandName: brandName,
                categoryName: category.categoryName,
                onToggle: onToggle,
              )),
      ],
    );
  }
}

/// Subcategory-level tile
class _SubcategoryTile extends StatelessWidget {
  final ProductSubcategoryNode subcategory;
  final String brandName;
  final String categoryName;
  final VoidCallback onToggle;

  const _SubcategoryTile({
    required this.subcategory,
    required this.brandName,
    required this.categoryName,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        InkWell(
          onTap: () {
            subcategory.isExpanded = !subcategory.isExpanded;
            onToggle();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            margin: const EdgeInsets.only(left: 32),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              border: Border(
                left: BorderSide(color: cs.outlineVariant, width: 2),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  subcategory.isExpanded
                      ? Icons.expand_more
                      : Icons.chevron_right,
                  color: cs.onSurfaceVariant,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Icon(Icons.list_alt, color: cs.onSurfaceVariant, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    subcategory.subcategoryName,
                    style: AppTextStyles.bodyMedium,
                  ),
                ),
                Text(
                  '${subcategory.products.length} sizes',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${subcategory.totalQuantity} units',
                  style: AppTextStyles.bodySmall.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (subcategory.isExpanded)
          ...subcategory.products.map((product) => _ProductCard(
                product: product,
                isInTree: true,
              )),
      ],
    );
  }
}

/// Product card with inline quantity editing
class _ProductCard extends StatefulWidget {
  final Product product;
  final bool isInTree;

  const _ProductCard({
    required this.product,
    this.isInTree = false,
  });

  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard> {
  final TextEditingController _quantityController = TextEditingController();
  bool _isEditingQuantity = false;

  @override
  void initState() {
    super.initState();
    // Initialize with current stock quantity
    // Stock will be fetched from ProductProvider in build()
    _quantityController.text = '0'; // Default, will update in didChangeDependencies
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Get current stock from provider
    final productProvider = context.read<ProductProvider>();
    final stock = productProvider.getStockForProduct(widget.product.id);
    final currentQuantity = stock?.quantity ?? 0;
    if (_quantityController.text != currentQuantity.toString()) {
      _quantityController.text = currentQuantity.toString();
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _updateQuantity() async {
    final newQuantity = int.tryParse(_quantityController.text) ?? 0;
    // Get current stock from provider
    final productProvider = context.read<ProductProvider>();
    final stock = productProvider.getStockForProduct(widget.product.id);
    final currentQuantity = stock?.quantity ?? 0;

    if (newQuantity == currentQuantity) {
      setState(() => _isEditingQuantity = false);
      return;
    }

    // Show stock adjustment dialog
    await _showStockAdjustmentDialog(newQuantity);
  }

  Future<void> _showStockAdjustmentDialog(int newQuantity) async {
    // Get current stock from provider
    final productProvider = context.read<ProductProvider>();
    final stock = productProvider.getStockForProduct(widget.product.id);
    final currentQuantity = stock?.quantity ?? 0;
    final difference = newQuantity - currentQuantity;
    final TextEditingController reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Adjust Stock'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Product: ${widget.product.name}'),
            const SizedBox(height: 8),
            Text('Current: $currentQuantity units'),
            Text('New: $newQuantity units'),
            Text(
              'Change: ${difference > 0 ? '+' : ''}$difference units',
              style: TextStyle(
                color: difference > 0 ? AppColors.success : AppColors.error,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                hintText: 'e.g., Stock received, Damaged goods',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      // TODO: Call API to update stock
      // await context.read<ProductProvider>().adjustStock(
      //   productId: widget.product.id,
      //   quantity: difference,
      //   reason: reasonController.text,
      // );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Stock updated: ${widget.product.name}'),
          backgroundColor: AppColors.success,
        ),
      );

      setState(() => _isEditingQuantity = false);
    } else {
      _quantityController.text = currentQuantity.toString();
      setState(() => _isEditingQuantity = false);
    }

    reasonController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final product = widget.product;

    // Get stock from ProductProvider
    final productProvider = context.watch<ProductProvider>();
    final stock = productProvider.getStockForProduct(product.id);
    final stockQuantity = stock?.quantity ?? 0;

    // Color coding based on stock levels
    final stockColor = stockQuantity <= 10
        ? AppColors.error
        : stockQuantity <= 50
            ? AppColors.warning
            : AppColors.success;

    return Container(
      margin: EdgeInsets.only(
        left: widget.isInTree ? 48 : 0,
        right: 0,
        bottom: 1,
      ),
      decoration: BoxDecoration(
        color: cs.surface,
        border: widget.isInTree
            ? Border(
                left: BorderSide(color: cs.outlineVariant, width: 2),
                bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
              )
            : null,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: stockColor.withValues(alpha: 0.1),
          child: Text(
            product.size ?? '',
            style: TextStyle(
              color: stockColor,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
        title: Text(
          product.name,
          style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('CP: ₹${product.costPrice} • SP: ₹${product.sellingPrice}'),
            if (product.barcode.isNotEmpty)
              Text('Barcode: ${product.barcode}', style: AppTextStyles.bodySmall),
          ],
        ),
        trailing: SizedBox(
          width: 120,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Quantity editor
              if (_isEditingQuantity)
                Expanded(
                  child: TextField(
                    controller: _quantityController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _updateQuantity(),
                    autofocus: true,
                  ),
                )
              else
                InkWell(
                  onTap: () => setState(() => _isEditingQuantity = true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: stockColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: stockColor),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$stockQuantity', // Uses local variable defined above
                          style: TextStyle(
                            color: stockColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'units',
                          style: TextStyle(
                            color: stockColor,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.edit, size: 18),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => EditProductScreen(product: product),
                    ),
                  );
                  context.read<ProductProvider>().refreshProducts();
                },
                tooltip: 'Edit Product',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
