import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/size_range_constants.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/providers/shop_selection_provider.dart';
import '../../../core/services/dio_api_service.dart';
import '../providers/product_provider.dart';
import '../providers/stock_purchase_provider.dart';
import '../services/product_service.dart';
import '../services/stock_purchase_service.dart';
import '../services/stock_purchase_draft_service.dart';
import '../models/product_with_stock.dart';
import '../models/product.dart' as models;
import '../models/stock_purchase.dart';
import '../../finance/providers/vendor_provider.dart';
import '../../auth/providers/auth_provider.dart';
import 'products_grid_screen.dart';
import 'stock_adjustment_screen.dart';
import 'barcode_scanner_screen.dart';
import 'brand_catalog_modern_screen.dart';
import 'custom_brand_form_screen.dart';
import 'invoice_ocr_screen.dart';
import 'stock_management_screen.dart';
import 'ai_stock_setup_screen.dart';
import 'brand_onboarding_setup_screen.dart';

/// Inventory Screen - Modern Grid View
///
/// Design Philosophy:
/// - Clean, filter-based grid/list view for daily operations
/// - Category filtering with horizontal chips
/// - Real-time search across products
/// - FAB for quick actions (scan, adjust stock)
///
/// Key Concepts:
/// - Brands/Products are TENANT-WIDE (available across all shops)
/// - Stock/Quantity is SHOP-SPECIFIC (each shop maintains its own stock)
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  bool _isGridView = false;
  String? _selectedCategory;
  String? _selectedSizeRange;

  // === MULTI-SELECT STATE FOR STOCK PURCHASE ===
  final Set<String> _selectedProductIds = {};
  bool get _isSelectionMode => _selectedProductIds.isNotEmpty;

  /// Toggle product selection for stock purchase
  /// Products are fetched from backend API when showing purchase sheet
  void _toggleProductSelection(String productId) {
    HapticFeedback.lightImpact();
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

  @override
  void initState() {
    super.initState();
    // Pre-load categories so size setup has them ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final productProvider = context.read<ProductProvider>();
      final shopProvider = context.read<ShopSelectionProvider>();
      if (productProvider.categories.isEmpty) {
        productProvider.loadCategories(shopId: shopProvider.selectedShopId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Check if salesman — hide FAB and selection for salesman role
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final isSalesman = (authProvider.currentUser?.role ?? '').toLowerCase() == 'salesman';

    // Setup flow on the inventory tab — product grid opens as full-screen route (hides bottom bar)
    return Scaffold(
      body: _selectedCategory == null
          ? _buildCategorySetup()
          : _buildSizeSetup(),
    );
  }

  /// Build selection footer for stock purchase
  Widget _buildSelectionFooter() {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1), // KEEP: shadow
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
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
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.shopping_cart,
                    color: Theme.of(context).colorScheme.primary,
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
            onPressed: () => _showStockPurchaseSheet(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
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
  /// Fetches ALL selected products from backend API for consistency
  void _showStockPurchaseSheet() async {
    if (_selectedProductIds.isEmpty) return;

    final shopProvider = context.read<ShopSelectionProvider>();
    final apiService = context.read<DioApiService>();
    final productService = ProductService(apiService);

    // Show loading indicator while fetching products
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      // Fetch ALL selected products from backend API (not from local cache)
      // This ensures consistency regardless of current category/size filter
      final response = await productService.getProductsByIds(
        productIds: _selectedProductIds.toList(),
        shopId: shopProvider.selectedShopId,
      );

      // Close loading dialog
      if (mounted) Navigator.pop(context);

      if (!response.success || response.data == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Failed to fetch selected products'),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return;
      }

      final products = response.data!.products;
      if (products.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No products found'),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return;
      }

      // Convert Product to ProductWithStock for the bottom sheet
      final selectedProducts = products.map((p) => ProductWithStock(
        product: p,
        stock: p.stockQuantity != null ? models.Stock(
          id: '',
          shopId: shopProvider.selectedShopId ?? '',
          productId: p.id,
          quantity: p.stockQuantity ?? 0,
          reservedQuantity: 0,
          minimumLevel: 10,
          maximumLevel: 1000,
          averageCost: p.costPrice,
          lastPurchasePrice: p.costPrice,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ) : null,
      )).toList();

      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => _StockPurchaseBottomSheet(
          products: selectedProducts,
          shopName: shopProvider.selectedShopName ?? 'Shop',
          shopId: shopProvider.selectedShopId ?? '',
          onConfirm: (quantities, vendorId, items, {String? receiptNumber, DateTime? receiptDate, String? receiptImageUrl, double? roundOff}) async {
            // Get the purchase provider
            final purchaseProvider = context.read<StockPurchaseProvider>();
            final authProvider = context.read<AuthProvider>();
            final productProvider = context.read<ProductProvider>();

            // Submit purchase request via API with receipt info and round-off
            final success = await purchaseProvider.submitPurchaseRequest(
              shopId: shopProvider.selectedShopId ?? '',
              vendorId: vendorId ?? '',
              items: items,
              notes: null,
              roundOff: roundOff,
              receiptNumber: receiptNumber,
              receiptDate: receiptDate,
              receiptImageUrl: receiptImageUrl,
            );

            Navigator.pop(context);
            _clearSelection();

            if (success) {
              // Determine message based on user role (admin/manager = auto-approved)
              final userRole = (authProvider.currentUser?.role ?? '').toLowerCase();
              final isAutoApproved = ['admin', 'manager'].contains(userRole);

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    isAutoApproved
                        ? 'Stock added successfully!'
                        : 'Purchase request submitted for approval',
                  ),
                  backgroundColor: AppColors.success,
                ),
              );

              // Refresh products if auto-approved
              if (isAutoApproved) {
                productProvider.refreshProducts(shopId: shopProvider.selectedShopId);
              }
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(purchaseProvider.errorMessage ?? 'Failed to create purchase request'),
                  backgroundColor: AppColors.error,
                ),
              );
            }
          },
        ),
      );
    } catch (e) {
      // Close loading dialog on error
      if (mounted) Navigator.pop(context);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error fetching products: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // Floating Action Button with Speed Dial
  /// Get English category IDs (Whisky + Vodka + Rum + Gin etc. — all non-beer)
  List<String> _getEnglishCategoryIds(List categories) {
    return categories
        .where((c) => !c.name.toLowerCase().contains('beer'))
        .map<String>((c) => c.id as String)
        .toList();
  }

  /// Push product grid as full-screen route (hides bottom bar like daily sales entry)
  void _pushProductGrid(String category, String sizeRange) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final isSalesman = (authProvider.currentUser?.role ?? '').toLowerCase() == 'salesman';

    Navigator.push(context, MaterialPageRoute(
      builder: (_) => Scaffold(
        body: ProductsGridScreen(
          key: ValueKey('${category}_$sizeRange'),
          isGridView: _isGridView,
          onToggleView: () => setState(() => _isGridView = !_isGridView),
          selectedProductIds: isSalesman ? null : _selectedProductIds,
          onProductSelectionToggle: isSalesman ? null : _toggleProductSelection,
          initialCategory: category,
          initialSize: sizeRange.isNotEmpty ? sizeRange : null,
        ),
        floatingActionButton: isSalesman ? _buildSalesmanStockFAB() : _buildInventoryFAB(),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      ),
    )).then((_) {
      // Reset to category setup when returning
      setState(() {
        _selectedCategory = null;
        _selectedSizeRange = null;
      });
    });
  }

  // ══════════════════════════════════════════════════════════
  // Category & Size Setup Screens (same flow as Sales Entry)
  // ══════════════════════════════════════════════════════════

  Widget _buildCategorySetup() {
    final categories = [
      {'name': 'English', 'title': 'Whisky & Spirits', 'subtitle': 'Whisky, Vodka, Rum, Gin & more', 'image': 'assets/images/sales/whisky_card.png', 'icon': Icons.liquor},
      {'name': 'Beer', 'title': 'Beer', 'subtitle': 'Beer brands & variants', 'image': 'assets/images/sales/beer_card.png', 'icon': Icons.sports_bar},
    ];

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                const SizedBox(width: 8),
                Text('Inventory', style: GoogleFonts.montserratAlternates(fontSize: 18, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  ...categories.map((cat) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      final catName = cat['name'] as String;
                      if (catName == 'Beer') {
                        _pushProductGrid(catName, '');
                      } else {
                        // Load sizes for this category immediately
                        final productProvider = context.read<ProductProvider>();
                        final shopId = context.read<ShopSelectionProvider>().selectedShopId;
                        if (catName == 'English') {
                          final englishIds = _getEnglishCategoryIds(productProvider.categories);
                          if (englishIds.isNotEmpty) {
                            productProvider.loadAvailableSizes(categoryIds: englishIds, shopId: shopId);
                          }
                        }
                        setState(() => _selectedCategory = catName);
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: Colors.white,
                        border: Border.all(color: const Color(0xFFD0D4DC), width: 1.2),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: SizedBox(
                                width: double.infinity, height: 120,
                                child: Image.asset(cat['image'] as String, fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    color: const Color(0xFF1A1A2E),
                                    child: Center(child: Icon(cat['icon'] as IconData, size: 50, color: Colors.white24)),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(cat['title'] as String, style: GoogleFonts.nunito(fontSize: 16, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 3),
                                Text(cat['subtitle'] as String, style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w500, color: const Color(0xFF333333))),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )),
                  // Brand Onboarding button
                  _buildBrandOnboardingButton(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSizeSetup() {
    final isBeer = _selectedCategory == 'Beer';
    final categoryLabel = _selectedCategory == 'English' ? 'Whisky' : _selectedCategory ?? '';

    // Use sizes from the backend API (already range-grouped)
    final productProvider = context.watch<ProductProvider>();
    final sizesFromApi = productProvider.availableSizesWithCounts;

    // If sizes not loaded yet, trigger load
    if (sizesFromApi.isEmpty && !productProvider.isSizesLoading) {
      final shopId = context.read<ShopSelectionProvider>().selectedShopId;
      if (_selectedCategory == 'English') {
        final englishIds = _getEnglishCategoryIds(productProvider.categories);
        if (englishIds.isNotEmpty) {
          productProvider.loadAvailableSizes(categoryIds: englishIds, shopId: shopId);
        }
      } else if (_selectedCategory == 'Beer') {
        final beerCat = productProvider.categories.where((c) => c.name.toLowerCase().contains('beer')).firstOrNull;
        if (beerCat != null) {
          productProvider.loadAvailableSizes(categoryId: beerCat.id, shopId: shopId);
        }
      }
    }

    // Use API sizes — these are already range-grouped with product counts
    final displayRanges = sizesFromApi;

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => setState(() { _selectedCategory = null; _selectedSizeRange = null; }),
                  child: Container(
                    width: 40, height: 40,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF3855B3)),
                    child: const Icon(Icons.chevron_left, color: Colors.white, size: 26),
                  ),
                ),
                Expanded(child: Text('Type of capacity', textAlign: TextAlign.center,
                  style: GoogleFonts.montserratAlternates(fontSize: 17, fontWeight: FontWeight.w600))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: const Color(0xFF2E7D32), borderRadius: BorderRadius.circular(8)),
                  child: Text(categoryLabel, style: GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ],
            ),
          ),
          // Hero image
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFD0D4DC), width: 1.2),
              color: Colors.white,
            ),
            padding: const EdgeInsets.all(10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: double.infinity, height: 120,
                child: Image.asset(
                  isBeer ? 'assets/images/sales/beer_card.png' : 'assets/images/sales/whisky_hero.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(color: const Color(0xFF1A1A2E)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: productProvider.isSizesLoading
                ? const Center(child: CircularProgressIndicator.adaptive())
                : displayRanges.isEmpty
                    ? Center(child: Text('No products with stock', style: GoogleFonts.nunito(fontSize: 14, color: const Color(0xFF888888))))
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                        itemCount: displayRanges.length,
                        separatorBuilder: (_, __) => Divider(height: 0.5, color: Colors.grey.withValues(alpha: 0.15)),
                        itemBuilder: (context, index) {
                          final sizeData = displayRanges[index];
                          final productCount = sizeData.productCount;
                          return GestureDetector(
                            onTap: () {
                              HapticFeedback.mediumImpact();
                              _pushProductGrid(_selectedCategory!, sizeData.size);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 34, height: 34,
                                    decoration: BoxDecoration(
                                      color: productCount > 0 ? const Color(0xFFE8F5E9) : const Color(0xFFF0F1F5),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(isBeer ? Icons.sports_bar_rounded : Icons.liquor_rounded, size: 18,
                                      color: productCount > 0 ? const Color(0xFF2E7D32) : const Color(0xFF888888)),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('${sizeData.size} $categoryLabel',
                                          style: GoogleFonts.nunito(fontSize: 15, fontWeight: FontWeight.w600)),
                                        Text('$productCount products', style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF2E7D32))),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: const Color(0xFFD0D5DD)),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text('View', style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF888888))),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          // Brand Onboarding button below size list
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: _buildBrandOnboardingButton(),
          ),
        ],
      ),
    );
  }

  /// Brand Onboarding button — shown on category and size setup screens
  Widget _buildBrandOnboardingButton() {
    return GestureDetector(
      onTap: () async {
        HapticFeedback.mediumImpact();
        final productProvider = context.read<ProductProvider>();
        final shopProvider = context.read<ShopSelectionProvider>();
        final shopId = shopProvider.selectedShopId;

        await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (context) => const BrandOnboardingSetupScreen(),
          ),
        );

        // Reload inventory when returning
        if (mounted) {
          await productProvider.loadProducts(shopId: shopId);
          if (mounted) {
            await productProvider.loadAvailableSizes(
              categoryId: productProvider.selectedCategoryId,
              shopId: shopId,
            );
          }
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(
            colors: [Color(0xFF1349B8), Color(0xFF3855B3)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1349B8).withOpacity(0.25),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.storefront_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Text(
              'Brand Onboarding',
              style: GoogleFonts.nunito(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 14),
          ],
        ),
      ),
    );
  }

  /// FAB for salesman role — directly opens Brand Onboarding
  Widget _buildSalesmanStockFAB() {
    return FloatingActionButton.extended(
      onPressed: () async {
        final productProvider = context.read<ProductProvider>();
        final shopProvider = context.read<ShopSelectionProvider>();
        final shopId = shopProvider.selectedShopId;

        final result = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (context) => const BrandOnboardingSetupScreen(),
          ),
        );

        // Always reload inventory when returning — other screens may have changed provider state
        if (mounted) {
          await productProvider.loadProducts(shopId: shopId);
          if (mounted) {
            await productProvider.loadAvailableSizes(
              categoryId: productProvider.selectedCategoryId,
              shopId: shopId,
            );
          }
        }
      },
      backgroundColor: const Color(0xFF3855B3),
      foregroundColor: Colors.white,
      icon: const Icon(Icons.storefront, size: 20),
      label: const Text('Brand Onboarding', style: TextStyle(fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildInventoryFAB() {
    return Consumer<ProductProvider>(
      builder: (context, productProvider, _) {
        final lowStockCount = productProvider.lowStockCount;

        return FloatingActionButton.extended(
          onPressed: () => _showQuickActionsMenu(lowStockCount),
          backgroundColor: Theme.of(context).colorScheme.primary,
          icon: const Icon(Icons.bolt, color: Colors.white),
          label: const Text(
            'Quick Actions',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        );
      },
    );
  }

  void _showQuickActionsMenu(int lowStockCount) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Enable full control for scrollable modal
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            children: [
              // Drag Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title
              Row(
                children: [
                  Icon(Icons.bolt, color: Theme.of(context).colorScheme.primary, size: 28),
                  const SizedBox(width: 12),
                  const Text(
                    'Quick Actions',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Brand Catalog Browsing
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.info.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.store, color: AppColors.info),
                ),
                title: const Text('Browse Brand Catalog'),
                subtitle: const Text('Onboard brands from catalog'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  // Capture providers BEFORE closing modal
                  final productProvider = context.read<ProductProvider>();
                  final shopProvider = context.read<ShopSelectionProvider>();
                  final shopId = shopProvider.selectedShopId;

                  Navigator.pop(context);

                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const BrandCatalogModernScreen(),
                    ),
                  );

                  if (result == true && mounted) {
                    await productProvider.loadProducts(shopId: shopId);
                  }
                },
              ),

              // Custom Brand Creation
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.add_business, color: Theme.of(context).colorScheme.tertiary),
                ),
                title: const Text('Create Custom Brand'),
                subtitle: const Text('Add brand with variants'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CustomBrandFormScreen(),
                    ),
                  );
                },
              ),

              // Stock Purchases (Combined - Approvals + History)
              Consumer<StockPurchaseProvider>(
                builder: (context, purchaseProvider, child) {
                  final pendingCount = purchaseProvider.pendingCount;
                  return ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.inventory_2, color: Theme.of(context).colorScheme.secondary),
                    ),
                    title: const Text('Stock Purchases'),
                    subtitle: const Text('Approvals & History'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (pendingCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.warning,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '$pendingCount pending',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        const SizedBox(width: 8),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const StockManagementScreen(),
                        ),
                      );
                    },
                  );
                },
              ),

              // Brand Onboarding
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3855B3).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.storefront, color: Color(0xFF3855B3)),
                ),
                title: const Text('Brand Onboarding'),
                subtitle: const Text('Add brands from master catalog to your shop'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final productProvider = context.read<ProductProvider>();
                  final shopProvider = context.read<ShopSelectionProvider>();
                  final shopId = shopProvider.selectedShopId;

                  Navigator.pop(context);

                  final result = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const BrandOnboardingSetupScreen(),
                    ),
                  );

                  // Always reload when returning
                  if (mounted) {
                    await productProvider.loadProducts(shopId: shopId);
                    if (mounted) {
                      await productProvider.loadAvailableSizes(
                        categoryId: productProvider.selectedCategoryId,
                        shopId: shopId,
                      );
                    }
                  }
                },
              ),

              // Low Stock Alerts (conditional)
              if (lowStockCount > 0)
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.warning_amber, color: AppColors.error),
                  ),
                  title: const Text('Low Stock Alerts'),
                  subtitle: Text('$lowStockCount items need attention'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.error,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          lowStockCount.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Low stock filter coming soon!'),
                      ),
                    );
                  },
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
  final List<ProductWithStock> products;
  final String shopName;
  final String shopId;
  final Function(
    Map<String, int> quantities,
    String? vendorId,
    List<StockPurchaseItem> items, {
    String? receiptNumber,
    DateTime? receiptDate,
    String? receiptImageUrl,
    double? roundOff,
  }) onConfirm;

  const _StockPurchaseBottomSheet({
    required this.products,
    required this.shopName,
    required this.shopId,
    required this.onConfirm,
  });

  @override
  State<_StockPurchaseBottomSheet> createState() => _StockPurchaseBottomSheetState();
}

class _StockPurchaseBottomSheetState extends State<_StockPurchaseBottomSheet> {
  final Map<String, int> _quantities = {};
  final Map<String, TextEditingController> _qtyControllers = {};
  String? _selectedVendorId;
  final _currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

  // Receipt capture state
  File? _receiptImage;
  String? _receiptImageUrl;
  final _receiptNumberController = TextEditingController();
  DateTime? _receiptDate;
  bool _isUploadingReceipt = false;
  final _imagePicker = ImagePicker();

  // === FILTER STATE (Backend API driven) ===
  String? _selectedCategoryId;
  String? _selectedSize;
  List<ProductWithStock> _filteredProducts = [];
  List<String> _availableCategories = []; // Unique categories from products
  List<String> _availableSizes = [];      // Unique sizes from products
  final Map<String, String> _categoryIdMap = {}; // category name -> category id
  bool _isLoadingFiltered = false;

  // === AUTO-SAVE STATE ===
  late StockPurchaseDraftService _draftService;
  StockPurchaseDraft? _currentDraft;
  Timer? _autoSaveTimer;
  bool _isLoadingDraft = false;
  bool _hasUnsavedChanges = false;
  DateTime? _lastAutoSaveTime;
  static const _autoSaveDelay = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    // Initialize with all products (no filter)
    _filteredProducts = List.from(widget.products);

    // Extract unique categories and sizes from products
    _extractFiltersFromProducts();

    // Initialize quantities and controllers for each product
    // Start with empty quantity field for better UX - user must enter the quantity
    for (var product in widget.products) {
      _quantities[product.id] = 0; // 0 means not yet entered
      _qtyControllers[product.id] = TextEditingController(text: ''); // Empty field
    }

    // Initialize draft service and load any existing draft
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<VendorProvider>().loadVendors();
      _initializeDraftService();
    });
  }

  /// Initialize draft service and load existing draft
  Future<void> _initializeDraftService() async {
    final apiService = context.read<DioApiService>();
    final authProvider = context.read<AuthProvider>();
    _draftService = StockPurchaseDraftService(apiService);

    final userId = authProvider.currentUser?.id ?? '';
    if (userId.isEmpty) return;

    setState(() => _isLoadingDraft = true);

    try {
      // Try to load existing draft for this shop + user
      final existingDraft = await _draftService.loadDraftLocally(
        shopId: widget.shopId,
        userId: userId,
      );

      if (existingDraft != null && existingDraft.items.isNotEmpty) {
        // Restore quantities from draft
        _restoreFromDraft(existingDraft);
        _currentDraft = existingDraft;
        _showDraftRestoredSnackbar(existingDraft);
      } else {
        // Create new draft
        _currentDraft = await _createNewDraft(userId);
      }
    } catch (e) {
      debugPrint('❌ Error initializing draft: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingDraft = false);
      }
    }
  }

  /// Create a new draft from current products
  Future<StockPurchaseDraft> _createNewDraft(String userId) async {
    final items = widget.products.map((p) => StockPurchaseDraftItem(
      productId: p.id,
      productName: p.name,
      brandName: p.brand?.name,
      size: p.size,
      quantity: _quantities[p.id] ?? 0, // 0 = not yet entered
      costPrice: p.costPrice,
    )).toList();

    return _draftService.createDraft(
      shopId: widget.shopId,
      userId: userId,
      shopName: widget.shopName,
      items: items,
    );
  }

  /// Restore UI state from a saved draft
  void _restoreFromDraft(StockPurchaseDraft draft) {
    for (final item in draft.items) {
      if (_quantities.containsKey(item.productId)) {
        _quantities[item.productId] = item.quantity;
        // Show empty text for 0 quantity, otherwise show the number
        _qtyControllers[item.productId]?.text = item.quantity > 0 ? item.quantity.toString() : '';
      }
    }

    if (draft.vendorId != null) {
      _selectedVendorId = draft.vendorId;
    }

    if (draft.receiptNumber != null) {
      _receiptNumberController.text = draft.receiptNumber!;
    }

    if (draft.receiptDate != null) {
      _receiptDate = draft.receiptDate;
    }

    if (draft.receiptUrl != null) {
      _receiptImageUrl = draft.receiptUrl;
    }
  }

  /// Show snackbar when draft is restored
  void _showDraftRestoredSnackbar(StockPurchaseDraft draft) {
    if (!mounted) return;

    final timeAgo = _formatTimeAgo(draft.updatedAt);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.restore, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Draft restored (${draft.itemCount} items, ₹${draft.totalAmount.toStringAsFixed(0)}) • $timeAgo',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Clear',
          textColor: Colors.white,
          onPressed: _clearDraft,
        ),
      ),
    );
  }

  /// Format time ago string
  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  /// Clear the current draft
  Future<void> _clearDraft() async {
    final authProvider = context.read<AuthProvider>();
    final userId = authProvider.currentUser?.id ?? '';

    await _draftService.deleteDraftLocally(
      shopId: widget.shopId,
      userId: userId,
    );

    // Reset quantities to empty (0)
    for (var product in widget.products) {
      _quantities[product.id] = 0;
      _qtyControllers[product.id]?.text = '';
    }

    _selectedVendorId = null;
    _receiptNumberController.clear();
    _receiptDate = null;
    _receiptImageUrl = null;
    _receiptImage = null;
    _currentDraft = await _createNewDraft(userId);
    _hasUnsavedChanges = false;

    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Draft cleared'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// Schedule auto-save with debouncing
  void _scheduleAutoSave() {
    _hasUnsavedChanges = true;
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(_autoSaveDelay, _performAutoSave);
  }

  /// Perform the actual auto-save
  Future<void> _performAutoSave() async {
    if (_currentDraft == null || !_hasUnsavedChanges) return;

    final authProvider = context.read<AuthProvider>();
    final userId = authProvider.currentUser?.id ?? '';
    if (userId.isEmpty) return;

    try {
      // Update draft with current quantities (0 = not entered)
      final items = widget.products.map((p) => StockPurchaseDraftItem(
        productId: p.id,
        productName: p.name,
        brandName: p.brand?.name,
        size: p.size,
        quantity: _quantities[p.id] ?? 0,
        costPrice: p.costPrice,
      )).toList();

      _currentDraft = _currentDraft!.copyWith(
        items: items,
        vendorId: _selectedVendorId,
        receiptUrl: _receiptImageUrl,
        receiptNumber: _receiptNumberController.text.isNotEmpty
            ? _receiptNumberController.text
            : null,
        receiptDate: _receiptDate,
        updatedAt: DateTime.now(),
        isSynced: false,
      );

      await _draftService.saveDraftLocally(_currentDraft!);

      // Also try to sync to server (non-blocking)
      _draftService.syncDraftToServer(_currentDraft!);

      _hasUnsavedChanges = false;
      _lastAutoSaveTime = DateTime.now();

      debugPrint('✅ Auto-saved draft: ${_currentDraft!.itemCount} items, ₹${_currentDraft!.totalAmount.toStringAsFixed(0)}');
    } catch (e) {
      debugPrint('❌ Auto-save error: $e');
    }
  }

  /// Extract unique categories and sizes from products for filter chips
  void _extractFiltersFromProducts() {
    final categorySet = <String>{};
    final sizeSet = <String>{};

    for (var product in widget.products) {
      if (product.category != null) {
        categorySet.add(product.category!.name);
        _categoryIdMap[product.category!.name] = product.category!.id;
      }
      if (product.size.isNotEmpty) {
        sizeSet.add(product.size.toUpperCase());
      }
    }

    _availableCategories = categorySet.toList()..sort();
    _availableSizes = sizeSet.toList()..sort((a, b) {
      // Sort sizes numerically (90ML < 180ML < 375ML)
      final aNum = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      final bNum = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      return aNum.compareTo(bNum);
    });
  }

  /// Apply filters via backend API for consistency
  Future<void> _applyFilters() async {
    setState(() => _isLoadingFiltered = true);

    try {
      final apiService = context.read<DioApiService>();
      final productService = ProductService(apiService);

      // Get all selected product IDs
      final allProductIds = widget.products.map((p) => p.id).toList();

      // Fetch products with filters from backend
      final response = await productService.getProductsByIds(
        productIds: allProductIds,
        shopId: widget.shopId,
      );

      if (response.success && response.data != null) {
        var products = response.data!.products;

        // Apply category filter
        if (_selectedCategoryId != null) {
          products = products.where((p) => p.categoryId == _selectedCategoryId).toList();
        }

        // Apply size filter
        if (_selectedSize != null) {
          products = products.where((p) => p.size.toUpperCase() == _selectedSize).toList();
        }

        // Convert to ProductWithStock
        setState(() {
          _filteredProducts = products.map((p) => ProductWithStock(
            product: p,
            stock: p.stockQuantity != null ? models.Stock(
              id: '',
              shopId: widget.shopId,
              productId: p.id,
              quantity: p.stockQuantity ?? 0,
              reservedQuantity: 0,
              minimumLevel: 10,
              maximumLevel: 1000,
              averageCost: p.costPrice,
              lastPurchasePrice: p.costPrice,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ) : null,
          )).toList();

          // Initialize quantities for newly filtered products (empty by default)
          for (var product in _filteredProducts) {
            if (!_quantities.containsKey(product.id)) {
              _quantities[product.id] = 0;
              _qtyControllers[product.id] = TextEditingController(text: '');
            }
          }
        });
      }
    } catch (e) {
      print('Error applying filters: $e');
      // Fallback to client-side filtering
      _applyClientSideFilters();
    } finally {
      setState(() => _isLoadingFiltered = false);
    }
  }

  /// Fallback: Apply filters on client side if backend fails
  void _applyClientSideFilters() {
    var filtered = List<ProductWithStock>.from(widget.products);

    if (_selectedCategoryId != null) {
      filtered = filtered.where((p) => p.category?.id == _selectedCategoryId).toList();
    }

    if (_selectedSize != null) {
      filtered = filtered.where((p) => p.size.toUpperCase() == _selectedSize).toList();
    }

    setState(() {
      _filteredProducts = filtered;
    });
  }

  /// Handle category filter selection
  void _onCategorySelected(String? categoryName) {
    setState(() {
      if (categoryName == null || _selectedCategoryId == _categoryIdMap[categoryName]) {
        _selectedCategoryId = null; // Deselect
      } else {
        _selectedCategoryId = _categoryIdMap[categoryName];
      }
    });
    _applyFilters();
  }

  /// Handle size filter selection
  void _onSizeSelected(String? size) {
    setState(() {
      if (size == null || _selectedSize == size) {
        _selectedSize = null; // Deselect
      } else {
        _selectedSize = size;
      }
    });
    _applyFilters();
  }

  /// Group filtered products by size for display (sorted by size: high to low for size groups)
  /// Products WITHIN each size group are sorted by price (low to high) to match inventory page
  Map<String, List<ProductWithStock>> _groupProductsBySize() {
    final Map<String, List<ProductWithStock>> grouped = {};

    for (final product in _filteredProducts) {
      final size = product.size.toUpperCase();
      grouped.putIfAbsent(size, () => []);
      grouped[size]!.add(product);
    }

    // Sort sizes by numeric value (high to low: 750ML, 375ML, 180ML, 90ML)
    final sortedKeys = grouped.keys.toList()
      ..sort((a, b) {
        final aNum = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        final bNum = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        return bNum.compareTo(aNum); // High to low
      });

    // Sort products WITHIN each size group by price (low to high) - matches inventory page
    for (final key in sortedKeys) {
      grouped[key]!.sort((a, b) => a.costPrice.compareTo(b.costPrice));
    }

    return Map.fromEntries(sortedKeys.map((k) => MapEntry(k, grouped[k]!)));
  }

  /// Calculate stats for a size group (0 if quantity not entered)
  Map<String, dynamic> _getSizeGroupStats(List<ProductWithStock> products) {
    int totalQty = 0;
    double totalAmount = 0;

    for (final product in products) {
      final qty = _quantities[product.id] ?? 0;
      totalQty += qty;
      totalAmount += product.costPrice * qty;
    }

    return {
      'productCount': products.length,
      'totalQty': totalQty,
      'totalAmount': totalAmount,
    };
  }

  @override
  void dispose() {
    // Cancel auto-save timer and perform final save
    _autoSaveTimer?.cancel();
    if (_hasUnsavedChanges) {
      _performAutoSave();
    }
    // Dispose all text controllers
    for (var controller in _qtyControllers.values) {
      controller.dispose();
    }
    _receiptNumberController.dispose();
    super.dispose();
  }

  void _updateQuantityFromText(String productId, String value) {
    // Allow empty value (0) - user clears the field
    final qty = value.isEmpty ? 0 : (int.tryParse(value) ?? 0);
    if (qty >= 0 && qty <= 9999) {
      setState(() {
        _quantities[productId] = qty;
      });
      // Trigger auto-save
      _scheduleAutoSave();
    }
  }

  /// Called when vendor selection changes
  void _onVendorChanged(String? vendorId) {
    setState(() => _selectedVendorId = vendorId);
    _scheduleAutoSave();
  }

  /// Called when receipt info changes
  void _onReceiptInfoChanged() {
    _scheduleAutoSave();
  }

  /// Delete draft after successful purchase
  Future<void> _deleteDraftAfterPurchase() async {
    final authProvider = context.read<AuthProvider>();
    final userId = authProvider.currentUser?.id ?? '';

    _autoSaveTimer?.cancel();

    await _draftService.deleteDraftLocally(
      shopId: widget.shopId,
      userId: userId,
    );

    // Also delete from server
    _draftService.deleteDraftFromServer(
      shopId: widget.shopId,
      userId: userId,
    );
  }

  /// Total quantity of filtered products only (0 if not entered)
  int get _totalQuantity {
    int total = 0;
    for (var product in _filteredProducts) {
      total += _quantities[product.id] ?? 0;
    }
    return total;
  }

  /// Purchase value of filtered products only (0 if quantity not entered)
  double get _purchaseValue {
    double total = 0;
    for (var product in _filteredProducts) {
      final qty = _quantities[product.id] ?? 0;
      total += product.costPrice * qty;
    }
    return total;
  }

  /// Check if any product has valid quantity entered (> 0)
  bool get _hasValidQuantities {
    return widget.products.any((product) => (_quantities[product.id] ?? 0) > 0);
  }

  double get _tcsAmount => _purchaseValue * 0.02; // 2% TCS (Tax Collected at Source)

  /// Auto-calculate round-off to make total a whole number
  double get _roundOffAmount {
    final afterTcs = _purchaseValue + _tcsAmount;
    final rounded = afterTcs.round().toDouble();
    return rounded - afterTcs;
  }

  double get _totalAmount => _purchaseValue + _tcsAmount + _roundOffAmount;

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
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
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
                color: Theme.of(context).colorScheme.outlineVariant,
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
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.add_shopping_cart,
                      color: Theme.of(context).colorScheme.primary,
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
                            Flexible(
                              child: Text(
                                'Add New Stock',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            // Auto-save indicator
                            if (_hasUnsavedChanges)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.warning.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 8,
                                      height: 8,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.5,
                                        color: AppColors.warning,
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      'Saving',
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: AppColors.warning,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else if (_lastAutoSaveTime != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.success.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.cloud_done, size: 10, color: AppColors.success),
                                    const SizedBox(width: 3),
                                    Text(
                                      'Saved',
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: AppColors.success,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        Text(
                          'Shop: ${widget.shopName}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Clear draft button
                  if (_currentDraft != null && _currentDraft!.items.isNotEmpty)
                    IconButton(
                      onPressed: _clearDraft,
                      icon: const Icon(Icons.delete_outline, size: 20),
                      tooltip: 'Clear draft',
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.error.withOpacity(0.1),
                        foregroundColor: AppColors.error,
                      ),
                    ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    style: IconButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
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
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        _buildSummaryItem(
                          'Items',
                          '${_filteredProducts.length}/${widget.products.length}',
                          Icons.inventory_2,
                        ),
                        Container(
                          width: 1,
                          height: 40,
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                        ),
                        _buildSummaryItem(
                          'Total Qty',
                          _totalQuantity.toString(),
                          Icons.numbers,
                        ),
                        Container(
                          width: 1,
                          height: 40,
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                        ),
                        _buildSummaryItem(
                          'Amount',
                          _currencyFormat.format(_purchaseValue),
                          Icons.currency_rupee,
                        ),
                      ],
                    ),
                  ),

                  // === CATEGORY FILTER CHIPS ===
                  if (_availableCategories.length > 1) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 36,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          // "All" chip
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _buildFilterChip(
                              label: 'All',
                              isSelected: _selectedCategoryId == null,
                              onTap: () => _onCategorySelected(null),
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          // Category chips
                          ..._availableCategories.map((category) {
                            final count = widget.products.where((p) => p.category?.name == category).length;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: _buildFilterChip(
                                label: '$category ($count)',
                                isSelected: _selectedCategoryId == _categoryIdMap[category],
                                onTap: () => _onCategorySelected(category),
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ],

                  // === SIZE FILTER CHIPS ===
                  if (_availableSizes.length > 1) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 36,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          // "All Sizes" chip
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _buildFilterChip(
                              label: 'All Sizes',
                              isSelected: _selectedSize == null,
                              onTap: () => _onSizeSelected(null),
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                          ),
                          // Size chips
                          ..._availableSizes.map((size) {
                            final count = widget.products.where((p) => p.size.toUpperCase() == size).length;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: _buildFilterChip(
                                label: '$size ($count)',
                                isSelected: _selectedSize == size,
                                onTap: () => _onSizeSelected(size),
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ],

                  // Loading indicator for filters
                  if (_isLoadingFiltered)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),

                  const SizedBox(height: 16),

                  // Products Table Header with count
                  Row(
                    children: [
                      const Text(
                        'Selected Items',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${_filteredProducts.length} products',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Table Column Headers (without Size column since sizes are grouped)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Expanded(flex: 3, child: Text('Product', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant))),
                        Expanded(flex: 2, child: Center(child: Text('Qty', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)))),
                        Expanded(flex: 1, child: Text('Price', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant), textAlign: TextAlign.right)),
                        Expanded(flex: 1, child: Text('Total', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant), textAlign: TextAlign.right)),
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
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        _buildPriceRow('Purchase Value', _purchaseValue),
                        const SizedBox(height: 8),
                        _buildPriceRow('TCS (2%)', _tcsAmount),
                        const SizedBox(height: 8),
                        _buildPriceRow('Round Off', _roundOffAmount, isRoundOff: true),
                        const Divider(height: 20),
                        _buildPriceRow('Total Amount', _totalAmount, isBold: true),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Godam Selection - Load real godams from API
                  const Text(
                    'Select Godam *',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Consumer<VendorProvider>(
                    builder: (context, vendorProvider, child) {
                      final vendors = vendorProvider.activeVendors;
                      final isLoading = vendorProvider.isLoading;

                      if (isLoading && vendors.isEmpty) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Loading godams...',
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        );
                      }

                      if (vendors.isEmpty) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.warning),
                            borderRadius: BorderRadius.circular(12),
                            color: AppColors.warning.withOpacity(0.1),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'No godams available. Please add a godam first.',
                                  style: TextStyle(color: AppColors.warning, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return DropdownButtonFormField<String>(
                        initialValue: _selectedVendorId,
                        decoration: InputDecoration(
                          hintText: 'Choose godam...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        items: vendors.map((vendor) {
                          // Show vendor name with optional contact person
                          final subtitle = vendor.contactPerson != null && vendor.contactPerson!.isNotEmpty
                              ? ' (${vendor.contactPerson})'
                              : '';
                          return DropdownMenuItem<String>(
                            value: vendor.id,
                            child: Text(
                              '${vendor.name}$subtitle',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: _onVendorChanged,
                      );
                    },
                  ),

                  const SizedBox(height: 20),

                  // Receipt Section
                  _buildReceiptSection(),

                  const SizedBox(height: 24),

                  // Confirm Button - requires vendor AND at least one product with quantity > 0
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _selectedVendorId != null && !_isUploadingReceipt && _hasValidQuantities
                          ? () {
                              // Create StockPurchaseItem list for API - only include products with quantity > 0
                              final items = widget.products
                                  .where((product) => (_quantities[product.id] ?? 0) > 0)
                                  .map((product) {
                                    final qty = _quantities[product.id] ?? 0;
                                    return StockPurchaseItem.fromSelection(
                                      productId: product.id,
                                      productName: product.name,
                                      brandName: product.brand?.name,
                                      size: product.size,
                                      quantity: qty,
                                      costPrice: product.costPrice,
                                    );
                                  }).toList();

                              // Get receipt info if provided
                              final receiptNumber = _receiptNumberController.text.trim().isNotEmpty
                                  ? _receiptNumberController.text.trim()
                                  : null;

                              // Delete draft after successful purchase
                              _deleteDraftAfterPurchase();

                              widget.onConfirm(
                                _quantities,
                                _selectedVendorId,
                                items,
                                receiptNumber: receiptNumber,
                                receiptDate: _receiptDate,
                                receiptImageUrl: _receiptImageUrl,
                                roundOff: _roundOffAmount,
                              );
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        disabledBackgroundColor: Theme.of(context).colorScheme.outlineVariant,
                      ),
                      child: Text(
                        _hasValidQuantities
                            ? 'Confirm Purchase ${_currencyFormat.format(_totalAmount)}'
                            : 'Enter quantities to continue',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, IconData icon) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  /// Build filter chip for category/size selection
  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required Color color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? color : Theme.of(context).colorScheme.outlineVariant,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildProductRow(ProductWithStock product) {
    final qty = _quantities[product.id] ?? 0;
    final total = product.costPrice * qty;

    // Extract product name without size (remove " - SIZE" suffix if present)
    final productName = product.name.contains(' - ')
        ? product.name.split(' - ').first
        : product.name;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              productName,
              style: const TextStyle(fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              product.size,
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          // Simple text input field for quantity (max 4 digits)
          Expanded(
            flex: 2,
            child: Center(
              child: SizedBox(
                width: 60,
                height: 32,
                child: TextField(
                  controller: _qtyControllers[product.id],
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 4,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    counterText: '', // Hide character counter
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5),
                    ),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                  onChanged: (value) => _updateQuantityFromText(product.id, value),
                  onSubmitted: (value) {
                    // Ensure minimum value of 1
                    final qty = int.tryParse(value) ?? 1;
                    if (qty < 1) {
                      _qtyControllers[product.id]?.text = '1';
                      _updateQuantityFromText(product.id, '1');
                    }
                  },
                ),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              '₹${product.costPrice.toStringAsFixed(0)}',
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
              textAlign: TextAlign.right,
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              '₹${total.toStringAsFixed(0)}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQtyButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 14, color: Theme.of(context).colorScheme.primary),
      ),
    );
  }

  /// Size divider header with centered label
  Widget _buildSizeSubheading(String size) {
    return Container(
      margin: const EdgeInsets.only(top: 16, bottom: 8),
      child: Row(
        children: [
          Expanded(child: Divider(color: Theme.of(context).colorScheme.primary.withOpacity(0.35), thickness: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.3)),
              ),
              child: Text(
                size,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.9),
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          Expanded(child: Divider(color: Theme.of(context).colorScheme.primary.withOpacity(0.35), thickness: 1)),
        ],
      ),
    );
  }

  /// Size group summary with product count, quantity, and total
  Widget _buildSizeGroupSummary(int productCount, int totalQty, double totalAmount) {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.15)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildSummaryStat(Icons.inventory_2_outlined, 'Products', '$productCount'),
          Container(width: 1, height: 24, color: Theme.of(context).colorScheme.primary.withOpacity(0.2)),
          _buildSummaryStat(Icons.numbers, 'Qty', '$totalQty'),
          Container(width: 1, height: 24, color: Theme.of(context).colorScheme.primary.withOpacity(0.2)),
          _buildSummaryStat(Icons.currency_rupee, 'Total', '₹${totalAmount.toStringAsFixed(0)}', isPrimary: true),
        ],
      ),
    );
  }

  /// Individual stat chip for size group summary
  Widget _buildSummaryStat(IconData icon, String label, String value, {bool isPrimary = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: isPrimary ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
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
                color: isPrimary ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
        widgets.add(_buildProductRowSimple(product));
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

  /// Simplified product row for size-grouped display (without size column)
  Widget _buildProductRowSimple(ProductWithStock product) {
    final qty = _quantities[product.id] ?? 0;
    final total = product.costPrice * qty;

    // Extract product name without size (remove " - SIZE" suffix if present)
    final productName = product.name.contains(' - ')
        ? product.name.split(' - ').first
        : product.name;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          // Product Name
          Expanded(
            flex: 3,
            child: Text(
              productName,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Quantity Input
          Expanded(
            flex: 2,
            child: Center(
              child: SizedBox(
                width: 60,
                height: 32,
                child: TextField(
                  controller: _qtyControllers[product.id],
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 4,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5),
                    ),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                  onChanged: (value) => _updateQuantityFromText(product.id, value),
                  onSubmitted: (value) {
                    final qty = int.tryParse(value) ?? 1;
                    if (qty < 1) {
                      _qtyControllers[product.id]?.text = '1';
                      _updateQuantityFromText(product.id, '1');
                    }
                  },
                ),
              ),
            ),
          ),
          // Unit Price
          Expanded(
            flex: 1,
            child: Text(
              '₹${product.costPrice.toStringAsFixed(0)}',
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
              textAlign: TextAlign.right,
            ),
          ),
          // Total
          Expanded(
            flex: 1,
            child: Text(
              '₹${total.toStringAsFixed(0)}',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceRow(String label, double amount, {bool isBold = false, bool isRoundOff = false}) {
    // Format round-off with sign prefix (e.g., -₹0.05 or +₹0.05)
    String formattedAmount;
    if (isRoundOff) {
      final sign = amount >= 0 ? '+' : '';
      formattedAmount = '$sign${_currencyFormat.format(amount)}';
    } else {
      formattedAmount = _currencyFormat.format(amount);
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            fontSize: isBold ? 16 : 14,
            color: isRoundOff ? Theme.of(context).colorScheme.onSurfaceVariant : null,
          ),
        ),
        Text(
          formattedAmount,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            fontSize: isBold ? 16 : 14,
            color: isBold ? Theme.of(context).colorScheme.primary : (isRoundOff ? Theme.of(context).colorScheme.onSurfaceVariant : null),
          ),
        ),
      ],
    );
  }

  // ========== RECEIPT CAPTURE HELPERS ==========

  /// Build the receipt section with image capture and number input
  Widget _buildReceiptSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header
          Row(
            children: [
              Icon(Icons.receipt_long, size: 20, color: Theme.of(context).colorScheme.onSurface),
              const SizedBox(width: 8),
              const Text(
                'Purchase Receipt',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Optional',
                  style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Receipt Image Section
          _buildReceiptImageSection(),

          const SizedBox(height: 16),

          // Receipt Number Field
          TextField(
            controller: _receiptNumberController,
            decoration: InputDecoration(
              labelText: 'Receipt/Invoice Number',
              hintText: 'e.g., INV-2025-001',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              prefixIcon: const Icon(Icons.tag, size: 20),
            ),
          ),

          const SizedBox(height: 12),

          // Receipt Date Picker
          _buildReceiptDatePicker(),
        ],
      ),
    );
  }

  /// Build receipt image capture/preview section
  Widget _buildReceiptImageSection() {
    // If uploading, show progress
    if (_isUploadingReceipt) {
      return Container(
        height: 100,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(height: 8),
              Text('Uploading...', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
      );
    }

    // If receipt image captured, show preview
    if (_receiptImage != null || _receiptImageUrl != null) {
      return Stack(
        children: [
          Container(
            height: 100,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.success),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: _receiptImage != null
                  ? Image.file(
                      _receiptImage!,
                      height: 100,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    )
                  : Image.network(
                      _receiptImageUrl!,
                      height: 100,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) => Container(
                        color: Theme.of(context).colorScheme.outlineVariant,
                        child: Center(
                          child: Icon(Icons.broken_image, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ),
            ),
          ),
          // Remove button
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _receiptImage = null;
                  _receiptImageUrl = null;
                });
              },
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 16, color: Colors.white),
              ),
            ),
          ),
          // Success badge
          Positioned(
            bottom: 4,
            left: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.success,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, size: 12, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    'Receipt attached',
                    style: TextStyle(fontSize: 10, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // Default - show camera/gallery buttons
    return Row(
      children: [
        Expanded(
          child: _buildImagePickerButton(
            icon: Icons.camera_alt,
            label: 'Camera',
            onTap: () => _pickReceiptImage(ImageSource.camera),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildImagePickerButton(
            icon: Icons.photo_library,
            label: 'Gallery',
            onTap: () => _pickReceiptImage(ImageSource.gallery),
          ),
        ),
      ],
    );
  }

  /// Build image picker button
  Widget _buildImagePickerButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Icon(icon, size: 28, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Pick receipt image from camera or gallery
  Future<void> _pickReceiptImage(ImageSource source) async {
    try {
      final pickedFile = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
      );

      if (pickedFile == null) return;

      final imageFile = File(pickedFile.path);

      setState(() {
        _receiptImage = imageFile;
        _isUploadingReceipt = true;
      });

      // Upload to server immediately
      final service = context.read<DioApiService>();
      final stockPurchaseService = StockPurchaseService(service);

      debugPrint('📸 Uploading receipt image...');
      final response = await stockPurchaseService.uploadReceiptImage(imageFile);

      if (response.success && response.data != null && response.data!.isNotEmpty) {
        debugPrint('✅ Receipt uploaded successfully: ${response.data}');
        setState(() {
          _receiptImageUrl = response.data;
          _isUploadingReceipt = false;
        });
        HapticFeedback.lightImpact();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Receipt uploaded successfully'),
              backgroundColor: AppColors.success,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        debugPrint('❌ Receipt upload failed: ${response.message}');
        setState(() {
          _isUploadingReceipt = false;
          // Keep local image for preview but clear URL
          _receiptImageUrl = null;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to upload receipt: ${response.message ?? "Unknown error"}'),
              backgroundColor: AppColors.warning,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Receipt capture/upload error: $e');
      setState(() {
        _isUploadingReceipt = false;
        _receiptImage = null;
        _receiptImageUrl = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to capture receipt: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// Build receipt date picker
  Widget _buildReceiptDatePicker() {
    final dateFormat = DateFormat('dd MMM yyyy');

    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _receiptDate ?? DateTime.now(),
          firstDate: DateTime.now().subtract(const Duration(days: 365)),
          lastDate: DateTime.now(),
        );
        if (picked != null) {
          setState(() => _receiptDate = picked);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.onSurfaceVariant),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _receiptDate != null
                    ? dateFormat.format(_receiptDate!)
                    : 'Receipt Date (optional)',
                style: TextStyle(
                  fontSize: 14,
                  color: _receiptDate != null ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (_receiptDate != null)
              GestureDetector(
                onTap: () => setState(() => _receiptDate = null),
                child: Icon(Icons.close, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}
