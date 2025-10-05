import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../inventory/models/product_model.dart';
import '../models/cart_item_model.dart';

/// New Sale Screen with Cart
class NewSaleScreen extends StatefulWidget {
  const NewSaleScreen({super.key});

  @override
  State<NewSaleScreen> createState() => _NewSaleScreenState();
}

class _NewSaleScreenState extends State<NewSaleScreen> {
  final List<CartItem> _cartItems = [];
  final List<Product> _products = []; // TODO: Load from API
  String _searchQuery = '';
  String? _selectedShopId;

  List<Product> get _filteredProducts {
    if (_searchQuery.isEmpty) return _products;
    return _products.where((product) {
      return product.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (product.brandName?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);
    }).toList();
  }

  double get _subtotal => _cartItems.fold(0, (sum, item) => sum + item.totalPrice);
  double get _totalProfit => _cartItems.fold(0, (sum, item) => sum + item.totalProfit);

  void _addToCart(Product product) {
    // Find all variants (same brand and name, different sizes)
    final variants = _products.where((p) =>
      p.brandName == product.brandName &&
      _getProductBaseName(p.name) == _getProductBaseName(product.name) &&
      p.id != product.id
    ).toList();

    // If product has variants, show selection dialog
    if (variants.isNotEmpty) {
      _showVariantSelection(product, variants);
      return;
    }

    // No variants, add directly
    _addProductToCart(product);
  }

  String _getProductBaseName(String name) {
    // Remove size indicators from product name
    return name.replaceAll(RegExp(r'\s*(750ml|1L|1l|180ml|375ml|90ml|2L|2l)', caseSensitive: false), '').trim();
  }

  void _addProductToCart(Product product) {
    final existingItem = _cartItems.firstWhere(
      (item) => item.product.id == product.id,
      orElse: () => CartItem(product: product, quantity: 0),
    );

    if (existingItem.quantity > 0) {
      setState(() {
        existingItem.quantity++;
      });
    } else {
      setState(() {
        _cartItems.add(CartItem(product: product));
      });
    }
  }

  void _showVariantSelection(Product selectedProduct, List<Product> variants) {
    final allVariants = [selectedProduct, ...variants]..sort((a, b) {
      // Sort by size (smaller first)
      final sizeA = a.size ?? '';
      final sizeB = b.size ?? '';
      return sizeA.compareTo(sizeB);
    });

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Title
            Text(
              'Select Size',
              style: AppTextStyles.h5.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              selectedProduct.brandName ?? '',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            Text(
              _getProductBaseName(selectedProduct.name),
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),

            // Variants
            ...allVariants.map((variant) {
              final stockQuantity = variant.stockQuantity ?? 0;
              final isOutOfStock = stockQuantity <= 0;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: isOutOfStock ? AppColors.border : AppColors.primary,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  enabled: !isOutOfStock,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  title: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          variant.size ?? 'N/A',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              Formatters.currency(variant.sellingPrice),
                              style: AppTextStyles.bodyLarge.copyWith(
                                fontWeight: FontWeight.bold,
                                color: isOutOfStock ? AppColors.textSecondary : AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              isOutOfStock ? 'Out of Stock' : 'Stock: $stockQuantity',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: isOutOfStock ? AppColors.error : AppColors.success,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!isOutOfStock)
                        const Icon(
                          Icons.add_circle,
                          color: AppColors.primary,
                          size: 32,
                        ),
                    ],
                  ),
                  onTap: isOutOfStock
                      ? null
                      : () {
                          Navigator.pop(context);
                          _addProductToCart(variant);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Added ${variant.size} to cart'),
                              backgroundColor: AppColors.success,
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        },
                ),
              );
            }),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _removeFromCart(CartItem item) {
    setState(() {
      if (item.quantity > 1) {
        item.quantity--;
      } else {
        _cartItems.remove(item);
      }
    });
  }

  void _completeSale() {
    if (_cartItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add items to cart'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (_selectedShopId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a shop'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    // TODO: Process sale API call
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Sale'),
        content: Text(
          'Total Amount: ${Formatters.currency(_subtotal)}\n'
          'Complete this sale?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              // TODO: Complete sale
              Navigator.pop(context);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(
        title: 'New Sale',
      ),
      body: Column(
        children: [
          // Shop Selector
          Container(
            padding: const EdgeInsets.all(16),
            color: AppColors.background,
            child: DropdownButtonFormField<String>(
              value: _selectedShopId,
              decoration: InputDecoration(
                labelText: 'Select Shop',
                prefixIcon: const Icon(Icons.store),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
              items: const [
                // TODO: Load shops from API
                DropdownMenuItem(
                  value: 'shop1',
                  child: Text('Shop 1'),
                ),
              ],
              onChanged: (value) {
                setState(() => _selectedShopId = value);
              },
            ),
          ),

          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              onChanged: (value) {
                setState(() => _searchQuery = value);
              },
              decoration: InputDecoration(
                hintText: 'Search products...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: AppColors.background,
              ),
            ),
          ),

          // Products List
          Expanded(
            child: _filteredProducts.isEmpty
                ? Center(
                    child: Text(
                      'No products available',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _filteredProducts.length,
                    itemBuilder: (context, index) {
                      final product = _filteredProducts[index];
                      final inCart = _cartItems.any((item) => item.product.id == product.id);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.liquor,
                              color: AppColors.primary,
                            ),
                          ),
                          title: Text(
                            product.name,
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            '${product.brandName ?? ''} • Stock: ${product.stockQuantity ?? 0}',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                Formatters.currency(product.sellingPrice),
                                style: AppTextStyles.bodyLarge.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: Icon(
                                  inCart ? Icons.check_circle : Icons.add_circle_outline,
                                  color: inCart ? AppColors.success : AppColors.primary,
                                ),
                                onPressed: () => _addToCart(product),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Cart Summary
          if (_cartItems.isNotEmpty)
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.shadow.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Cart Items
                  Container(
                    constraints: const BoxConstraints(maxHeight: 150),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _cartItems.length,
                      itemBuilder: (context, index) {
                        final item = _cartItems[index];
                        return ListTile(
                          dense: true,
                          title: Text(
                            item.product.name,
                            style: AppTextStyles.bodySmall,
                          ),
                          subtitle: Text(
                            '${Formatters.currency(item.product.sellingPrice)} × ${item.quantity}',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline, size: 20),
                                onPressed: () => _removeFromCart(item),
                                color: AppColors.error,
                              ),
                              Text(
                                Formatters.currency(item.totalPrice),
                                style: AppTextStyles.bodyMedium.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const Divider(height: 1),

                  // Total
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Subtotal',
                              style: AppTextStyles.h5,
                            ),
                            Text(
                              Formatters.currency(_subtotal),
                              style: AppTextStyles.h4.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _completeSale,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            icon: const Icon(Icons.check),
                            label: Text(
                              'Complete Sale (${_cartItems.length} items)',
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
