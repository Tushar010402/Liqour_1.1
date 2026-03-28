import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../providers/sales_provider.dart';
import '../../inventory/models/product.dart';
import '../models/cart_item_model.dart';
import 'modern_invoice_screen.dart';

/// Modern iOS-style Point of Sale Screen
class ModernPOSScreen extends StatefulWidget {
  const ModernPOSScreen({super.key});

  @override
  State<ModernPOSScreen> createState() => _ModernPOSScreenState();
}

class _ModernPOSScreenState extends State<ModernPOSScreen>
    with TickerProviderStateMixin {
  // Controllers
  final _searchController = TextEditingController();
  final _customerPhoneController = TextEditingController();
  final _customerNameController = TextEditingController();
  late TabController _tabController;
  late AnimationController _cartAnimationController;
  late AnimationController _productAnimationController;
  late Animation<double> _cartAnimation;
  late Animation<double> _productAnimation;

  // State
  String _selectedCategory = 'All';
  bool _showCart = false;
  bool _showCustomerDetails = false;
  String _paymentMethod = 'cash';
  final List<String> _categories = [
    'All',
    'Whiskey',
    'Beer',
    'Wine',
    'Vodka',
    'Rum',
    'Gin',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initAnimations();
    _loadProducts();
  }

  void _initAnimations() {
    _cartAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _cartAnimation = CurvedAnimation(
      parent: _cartAnimationController,
      curve: Curves.easeOutBack,
    );

    _productAnimationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _productAnimation = CurvedAnimation(
      parent: _productAnimationController,
      curve: Curves.easeOutCubic,
    );

    _productAnimationController.forward();
  }

  void _loadProducts() {
    // Products are loaded from ProductProvider - see products_grid_screen.dart
    // This POS screen is for UI reference only
  }

  @override
  void dispose() {
    _searchController.dispose();
    _customerPhoneController.dispose();
    _customerNameController.dispose();
    _tabController.dispose();
    _cartAnimationController.dispose();
    _productAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;
    final provider = context.watch<SalesProvider>();

    return Scaffold(
      backgroundColor: cs.surface,
      body: Stack(
        children: [
          // Main Content
          Row(
            children: [
              // Products Section
              Expanded(
                flex: _showCart ? 3 : 1,
                child: Column(
                  children: [
                    // App Bar
                    _buildAppBar(),

                    // Search Bar
                    _buildSearchBar(),

                    // Category Chips
                    _buildCategoryChips(),

                    // Products Grid
                    Expanded(
                      child: _buildProductsGrid(),
                    ),
                  ],
                ),
              ),

              // Cart Section (Animated)
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                width: _showCart ? size.width * 0.35 : 80,
                child: _showCart ? _buildExpandedCart() : _buildCollapsedCart(),
              ),
            ],
          ),

          // Floating Cart Badge
          if (!_showCart && provider.itemCount > 0)
            Positioned(
              right: 90,
              bottom: 30,
              child: _buildFloatingCartBadge(),
            ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 100,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top,
        left: 20,
        right: 20,
        bottom: 10,
      ),
      decoration: BoxDecoration(
        color: cs.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(CupertinoIcons.arrow_left),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 12),
          const Text(
            'Point of Sale',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          // Customer Info Button
          IconButton(
            icon: Icon(
              CupertinoIcons.person_crop_circle,
              color: _showCustomerDetails ? cs.primary : cs.onSurfaceVariant,
            ),
            onPressed: () {
              setState(() => _showCustomerDetails = !_showCustomerDetails);
              HapticFeedback.lightImpact();
            },
          ),
          // Barcode Scanner
          IconButton(
            icon: const Icon(CupertinoIcons.barcode_viewfinder),
            onPressed: _openBarcodeScanner,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search products...',
                  hintStyle: TextStyle(color: cs.onSurfaceVariant),
                  prefixIcon: Icon(
                    CupertinoIcons.search,
                    color: cs.onSurfaceVariant,
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(CupertinoIcons.clear_circled_solid),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                ),
                onChanged: (value) => setState(() {}),
              ),
            ),
          ),
          if (_showCustomerDetails) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _customerPhoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    hintText: 'Customer Phone',
                    hintStyle: TextStyle(color: cs.onSurfaceVariant),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCategoryChips() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final category = _categories[index];
          final isSelected = _selectedCategory == category;

          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilterChip(
              label: Text(category),
              selected: isSelected,
              onSelected: (selected) {
                setState(() => _selectedCategory = category);
                HapticFeedback.lightImpact();
              },
              backgroundColor: cs.surface,
              selectedColor: cs.primary,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : cs.onSurface,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: isSelected ? 4 : 2,
            ),
          );
        },
      ),
    );
  }

  Widget _buildProductsGrid() {
    // Filter products based on search and category
    final filteredProducts = _getFilteredProducts();

    if (filteredProducts.isEmpty) {
      return _buildEmptyProducts();
    }

    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.75,
      ),
      itemCount: filteredProducts.length,
      itemBuilder: (context, index) {
        final product = filteredProducts[index];
        return _buildProductCard(product, index);
      },
    );
  }

  Widget _buildProductCard(Product product, int index) {
    final cs = Theme.of(context).colorScheme;
    final provider = context.watch<SalesProvider>();
    final cartItem = provider.cartItems.firstWhere(
      (item) => item.product.id == product.id,
      orElse: () => CartItem(product: product, quantity: 0),
    );
    final inCart = cartItem.quantity > 0;

    return FadeTransition(
      opacity: _productAnimation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset(0, 0.1 * (index % 3)),
          end: Offset.zero,
        ).animate(_productAnimation),
        child: GestureDetector(
          onTap: () => _addToCart(product),
          child: Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product Image
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(20),
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            CupertinoIcons.photo,
                            size: 50,
                            color: cs.onSurfaceVariant,
                          ),
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
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            product.brand?.name ?? '',
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                Formatters.currency(product.sellingPrice),
                                style: TextStyle(
                                  color: cs.primary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              if (inCart)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: cs.primary,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${cartItem.quantity}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
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

                // Stock Badge
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _getStockColor(product.stockQuantity ?? 0),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Stock: ${product.stockQuantity ?? 0}',
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
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsedCart() {
    final provider = context.watch<SalesProvider>();

    return GestureDetector(
      onTap: () {
        setState(() => _showCart = true);
        _cartAnimationController.forward();
        HapticFeedback.mediumImpact();
      },
      child: Container(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Transform.rotate(
              angle: -math.pi / 2,
              child: Text(
                'CART',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (provider.itemCount > 0) ...[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${provider.itemCount}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                Formatters.currencyCompact(provider.total),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedCart() {
    final cs = Theme.of(context).colorScheme;
    final provider = context.watch<SalesProvider>();

    return Container(
      color: cs.surface,
      child: Column(
        children: [
          // Cart Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.05),
              border: Border(
                bottom: BorderSide(
                  color: cs.outlineVariant,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.cart_fill,
                  color: cs.primary,
                ),
                const SizedBox(width: 12),
                const Text(
                  'Shopping Cart',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(CupertinoIcons.xmark),
                  onPressed: () {
                    setState(() => _showCart = false);
                    _cartAnimationController.reverse();
                    HapticFeedback.lightImpact();
                  },
                ),
              ],
            ),
          ),

          // Cart Items
          Expanded(
            child: provider.cartItems.isEmpty
                ? _buildEmptyCart()
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: provider.cartItems.length,
                    itemBuilder: (context, index) {
                      final item = provider.cartItems[index];
                      return _buildCartItem(item);
                    },
                  ),
          ),

          // Cart Summary
          _buildCartSummary(),

          // Checkout Button
          _buildCheckoutButton(),
        ],
      ),
    );
  }

  Widget _buildCartItem(CartItem item) {
    final cs = Theme.of(context).colorScheme;
    final provider = context.read<SalesProvider>();

    return ScaleTransition(
      scale: _cartAnimation,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // Product Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.product.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    Formatters.currency(item.product.sellingPrice),
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            // Quantity Controls
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 5,
                  ),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(CupertinoIcons.minus_circle),
                    onPressed: () {
                      provider.updateQuantity(
                        item.product,
                        item.quantity - 1,
                      );
                      HapticFeedback.lightImpact();
                    },
                    iconSize: 20,
                  ),
                  SizedBox(
                    width: 40,
                    child: Center(
                      child: Text(
                        '${item.quantity}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(CupertinoIcons.plus_circle),
                    onPressed: () {
                      provider.updateQuantity(
                        item.product,
                        item.quantity + 1,
                      );
                      HapticFeedback.lightImpact();
                    },
                    iconSize: 20,
                  ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            // Total
            Text(
              Formatters.currency(item.totalPrice),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCartSummary() {
    final cs = Theme.of(context).colorScheme;
    final provider = context.watch<SalesProvider>();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        border: Border(
          top: BorderSide(
            color: cs.outlineVariant,
          ),
        ),
      ),
      child: Column(
        children: [
          _buildSummaryRow('Subtotal', provider.subtotal),
          if (provider.discount > 0)
            _buildSummaryRow('Discount', -provider.discount, isDiscount: true),
          _buildSummaryRow('Tax (18%)', provider.tax),
          const Divider(height: 20),
          _buildSummaryRow('Total', provider.total, isTotal: true),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, double amount,
      {bool isTotal = false, bool isDiscount = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 18 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
              color: isDiscount ? AppColors.success : null,
            ),
          ),
          Text(
            Formatters.currency(amount.abs()),
            style: TextStyle(
              fontSize: isTotal ? 18 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
              color: isDiscount ? AppColors.success : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckoutButton() {
    final cs = Theme.of(context).colorScheme;
    final provider = context.watch<SalesProvider>();

    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Payment Method Selector
          Container(
            height: 50,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                _buildPaymentOption('Cash', 'cash', CupertinoIcons.money_dollar),
                _buildPaymentOption('Card', 'card', CupertinoIcons.creditcard),
                _buildPaymentOption('UPI', 'upi', CupertinoIcons.device_phone_portrait),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Checkout Button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: provider.hasItems ? _processCheckout : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: provider.hasItems ? 4 : 0,
              ),
              child: provider.isProcessingPayment
                  ? const CupertinoActivityIndicator(color: Colors.white)
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(CupertinoIcons.checkmark_alt_circle_fill),
                        const SizedBox(width: 12),
                        Text(
                          'Checkout • ${Formatters.currency(provider.total)}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentOption(String label, String value, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = _paymentMethod == value;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _paymentMethod = value);
          context.read<SalesProvider>().setPaymentMethod(value);
          HapticFeedback.lightImpact();
        },
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? cs.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? Colors.white : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : cs.onSurfaceVariant,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyCart() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            CupertinoIcons.cart,
            size: 64,
            color: cs.outlineVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'Your cart is empty',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add products to get started',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyProducts() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            CupertinoIcons.cube_box,
            size: 64,
            color: cs.outlineVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'No products found',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try adjusting your search or filters',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingCartBadge() {
    final provider = context.watch<SalesProvider>();

    return GestureDetector(
      onTap: () {
        setState(() => _showCart = true);
        _cartAnimationController.forward();
        HapticFeedback.mediumImpact();
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.primary.withValues(alpha: 0.8)],
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              CupertinoIcons.cart_fill,
              color: Colors.white,
              size: 24,
            ),
            if (provider.itemCount > 0) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${provider.itemCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Product> _getFilteredProducts() {
    // This is a reference UI screen - actual product loading is handled by ProductProvider
    // See products_grid_screen.dart for the working implementation
    return [];
  }

  void _addToCart(Product product) {
    context.read<SalesProvider>().addToCart(product);
    HapticFeedback.mediumImpact();

    // Show success animation
    _showAddToCartAnimation();
  }

  void _showAddToCartAnimation() {
    // Implement cart add animation
  }

  void _openBarcodeScanner() {
    HapticFeedback.mediumImpact();
    // Navigate to barcode scanner
  }

  Future<void> _processCheckout() async {
    final provider = context.read<SalesProvider>();

    // Set customer details if provided
    if (_customerPhoneController.text.isNotEmpty) {
      provider.setCustomer(
        name: _customerNameController.text,
        phone: _customerPhoneController.text,
      );
    }

    // Process sale
    final success = await provider.createSale();

    if (success) {
      // Navigate to invoice
      Navigator.pushReplacement(
        context,
        CupertinoPageRoute(
          builder: (_) => ModernInvoiceScreen(sale: provider.currentSale!),
        ),
      );
    } else {
      // Show error
      _showErrorDialog(provider.lastError ?? 'Failed to process sale');
    }
  }

  void _showErrorDialog(String message) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            child: const Text('OK'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Color _getStockColor(int stock) {
    if (stock == 0) return Colors.red;
    if (stock < 10) return Colors.orange;
    return Colors.green;
  }
}