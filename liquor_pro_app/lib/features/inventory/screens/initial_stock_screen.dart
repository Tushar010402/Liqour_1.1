import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../admin/models/shop_model.dart';
import '../../admin/services/shop_service.dart';
import '../models/product.dart';
import '../providers/product_provider.dart';
import '../services/stock_service.dart';
import '../../../core/utils/logger.dart';

/// Initial Stock Setup Screen - Set stock for newly onboarded products
class InitialStockScreen extends StatefulWidget {
  final List<String> productIds;
  final String? shopId;

  const InitialStockScreen({
    super.key,
    required this.productIds,
    this.shopId,
  });

  @override
  State<InitialStockScreen> createState() => _InitialStockScreenState();
}

class _InitialStockScreenState extends State<InitialStockScreen> {
  final Map<String, TextEditingController> _stockControllers = {};
  final Map<String, int> _stockValues = {};
  bool _isLoading = true;
  bool _isSaving = false;
  List<Product> _products = [];
  List<Shop> _shops = [];
  String? _selectedShopId;

  @override
  void initState() {
    super.initState();
    _selectedShopId = widget.shopId;
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    await Future.wait([
      _loadProducts(),
      _loadShops(),
    ]);
  }

  Future<void> _loadShops() async {
    try {
      final apiService = context.read<ApiService>();
      final shopService = ShopService(apiService);
      final response = await shopService.getShops();

      if (response.success && response.data != null) {
        setState(() {
          _shops = response.data!;
          // Auto-select first shop if no shop is pre-selected
          if (_selectedShopId == null && _shops.isNotEmpty) {
            _selectedShopId = _shops.first.id;
          }
        });
      }
    } catch (e) {
      Logger.debug('❌ Error loading shops: $e');
    }
  }

  @override
  void dispose() {
    for (var controller in _stockControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);

    try {
      final productProvider = context.read<ProductProvider>();
      await productProvider.loadProducts();

      // Filter to only show newly onboarded products
      _products = productProvider.products
          .where((p) => widget.productIds.contains(p.id))
          .toList();

      // Initialize controllers
      for (var product in _products) {
        _stockControllers[product.id] = TextEditingController(text: '0');
        _stockValues[product.id] = 0;
      }
    } catch (e) {
      Logger.debug('❌ Error loading products: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveStock() async {
    if (_selectedShopId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a shop first'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    // Check if at least one product has stock
    final hasStock = _stockValues.values.any((stock) => stock > 0);
    if (!hasStock) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please set stock for at least one product'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final apiService = context.read<ApiService>();
      final stockService = StockService(apiService);
      int successCount = 0;
      int errorCount = 0;

      for (var entry in _stockValues.entries) {
        if (entry.value > 0) {
          final response = await stockService.adjustStock(
            shopId: _selectedShopId!,
            productId: entry.key,
            quantity: entry.value,
            adjustmentType: 'set',
            reason: 'Initial Stock',
            notes: 'Initial stock setup for onboarded product',
          );

          if (response.success) {
            successCount++;
          } else {
            Logger.debug('❌ Error setting stock for ${entry.key}: ${response.message}');
            errorCount++;
          }
        }
      }

      if (!mounted) return;

      if (successCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Successfully set stock for $successCount product${successCount > 1 ? 's' : ''}' +
                  (errorCount > 0 ? ' ($errorCount failed)' : ''),
            ),
            backgroundColor: errorCount > 0 ? AppColors.warning : AppColors.success,
          ),
        );

        // Refresh product list
        context.read<ProductProvider>().loadProducts();

        // Navigate back
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to set stock. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      Logger.debug('❌ Error saving stock: $e');
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(
        title: 'Set Initial Stock',
        actions: [
          if (_products.isNotEmpty && !_isLoading)
            TextButton(
              onPressed: _isSaving ? null : () => Navigator.pop(context),
              child: Text(
                'Skip',
                style: TextStyle(
                  color: _isSaving ? AppColors.textSecondary : AppColors.primary,
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _products.isEmpty
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
                        'No products to set stock for',
                        style: AppTextStyles.bodyLarge.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 24),
                      CustomButton(
                        text: 'Go Back',
                        onPressed: () => Navigator.pop(context),
                        isOutlined: true,
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Info Banner
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: AppColors.primary.withOpacity(0.1),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: AppColors.primary,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Set initial stock quantities for your newly onboarded products',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Shop Selector
                    if (_shops.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        color: Colors.white,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Select Shop',
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: _selectedShopId,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                prefixIcon: const Icon(Icons.store),
                              ),
                              items: _shops.map((shop) {
                                return DropdownMenuItem<String>(
                                  value: shop.id,
                                  child: Text(shop.name),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() {
                                  _selectedShopId = value;
                                });
                              },
                            ),
                          ],
                        ),
                      ),

                    const Divider(height: 1),

                    // Products List
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _products.length,
                        itemBuilder: (context, index) {
                          final product = _products[index];
                          return _buildProductStockCard(product);
                        },
                      ),
                    ),

                    // Bottom Action Bar
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, -5),
                          ),
                        ],
                      ),
                      child: SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Total Products',
                                        style: AppTextStyles.bodySmall.copyWith(
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${_products.length}',
                                        style: AppTextStyles.h5.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Total Units',
                                        style: AppTextStyles.bodySmall.copyWith(
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${_stockValues.values.fold<int>(0, (sum, stock) => sum + stock)}',
                                        style: AppTextStyles.h5.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.success,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            CustomButton(
                              text: 'Save Stock',
                              onPressed: _isSaving ? null : _saveStock,
                              isLoading: _isSaving,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildProductStockCard(Product product) {
    final controller = _stockControllers[product.id]!;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product Info
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.liquor,
                    color: AppColors.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${product.brand?.name ?? 'Unknown Brand'} • ${product.category?.name ?? 'Unknown Category'}',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Stock Input
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Initial Stock Quantity',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: controller,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          hintText: '0',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          suffixText: 'units',
                        ),
                        onChanged: (value) {
                          setState(() {
                            _stockValues[product.id] = int.tryParse(value) ?? 0;
                          });
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // Quick action buttons
                Column(
                  children: [
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        _buildQuickButton(
                          icon: Icons.add,
                          onPressed: () {
                            final current = int.tryParse(controller.text) ?? 0;
                            final newValue = current + 10;
                            controller.text = newValue.toString();
                            setState(() {
                              _stockValues[product.id] = newValue;
                            });
                          },
                          label: '+10',
                        ),
                        const SizedBox(width: 8),
                        _buildQuickButton(
                          icon: Icons.remove,
                          onPressed: () {
                            final current = int.tryParse(controller.text) ?? 0;
                            final newValue = (current - 10).clamp(0, 999999);
                            controller.text = newValue.toString();
                            setState(() {
                              _stockValues[product.id] = newValue;
                            });
                          },
                          label: '-10',
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickButton({
    required IconData icon,
    required VoidCallback onPressed,
    required String label,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppColors.primary.withOpacity(0.3),
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
