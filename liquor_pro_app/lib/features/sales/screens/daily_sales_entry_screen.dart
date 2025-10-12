import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../../inventory/providers/product_provider.dart';
import '../../inventory/models/product.dart' as models;
import '../providers/daily_sales_provider.dart';
import '../../admin/services/shop_service.dart';

/// Daily Sales Entry Screen - Multi-step wizard for UP Liquor Shop Bulk Entry
class DailySalesEntryScreen extends StatefulWidget {
  const DailySalesEntryScreen({super.key});

  @override
  State<DailySalesEntryScreen> createState() => _DailySalesEntryScreenState();
}

class _DailySalesEntryScreenState extends State<DailySalesEntryScreen> {
  int _currentStep = 0; // 0 = Products, 1 = Payment

  // Controllers for quantity inputs (dynamic, created per product)
  final Map<String, TextEditingController> _quantityControllers = {};

  // Payment controllers
  final _cashController = TextEditingController();
  final _cardController = TextEditingController();
  final _upiController = TextEditingController();
  final _creditController = TextEditingController();
  final _notesController = TextEditingController();

  List<Map<String, dynamic>> _shops = [];
  bool _isLoadingShops = false;
  bool _isLoadingProducts = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadShops();
    });
  }

  @override
  void dispose() {
    // Dispose all quantity controllers
    for (var controller in _quantityControllers.values) {
      controller.dispose();
    }
    _cashController.dispose();
    _cardController.dispose();
    _upiController.dispose();
    _creditController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadShops() async {
    print('🏪 [DailySalesEntry] ========== LOADING SHOPS ==========');
    setState(() => _isLoadingShops = true);
    try {
      final shopService = ShopService(context.read());
      print('🏪 [DailySalesEntry] Fetching shops from API...');
      final response = await shopService.getShops();

      print('🏪 [DailySalesEntry] API Response - Success: ${response.success}');
      if (response.success && response.data != null) {
        print('🏪 [DailySalesEntry] Shops loaded: ${response.data!.length}');
        setState(() {
          _shops = response.data!.map((shop) {
            print('   📍 Shop: ${shop.name} (ID: ${shop.id})');
            return {
              'id': shop.id,
              'name': shop.name,
            };
          }).toList();
        });
        print('✅ [DailySalesEntry] Shops state updated successfully');
      } else {
        print('❌ [DailySalesEntry] Failed to load shops: ${response.error}');
      }
    } catch (e) {
      print('❌ [DailySalesEntry] Exception loading shops: $e');
      if (mounted) {
        SnackbarHelper.showError(context, 'Failed to load shops');
      }
    } finally {
      setState(() => _isLoadingShops = false);
      print('🏪 [DailySalesEntry] ========== SHOPS LOADING COMPLETE ==========\n');
    }
  }

  Future<void> _loadProducts(String shopId) async {
    print('📦 [DailySalesEntry] ========== LOADING PRODUCTS ==========');
    print('📦 [DailySalesEntry] Shop ID: $shopId');
    setState(() => _isLoadingProducts = true);
    try {
      final provider = context.read<ProductProvider>();
      print('📦 [DailySalesEntry] Calling product provider loadProducts...');
      await provider.loadProducts(shopId: shopId);

      print('📦 [DailySalesEntry] Total products loaded: ${provider.products.length}');
      print('📦 [DailySalesEntry] Stock map entries: ${provider.stockByProductId.length}');

      // Count products with stock
      int withStock = 0;
      int withoutStock = 0;
      for (var product in provider.products) {
        final stock = provider.stockByProductId[product.id];
        if (stock != null && stock.quantity > 0) {
          withStock++;
          print('   ✅ ${product.name} - Stock: ${stock.quantity}');
        } else {
          withoutStock++;
          print('   ⚠️  ${product.name} - No stock');
        }
      }

      print('📦 [DailySalesEntry] Products WITH stock: $withStock');
      print('📦 [DailySalesEntry] Products WITHOUT stock: $withoutStock');
    } catch (e) {
      print('❌ [DailySalesEntry] Error loading products: $e');
    } finally {
      setState(() => _isLoadingProducts = false);
      print('📦 [DailySalesEntry] ========== PRODUCTS LOADING COMPLETE ==========\n');
    }
  }

  String _getShopName(String? shopId) {
    if (shopId == null) return 'Select Shop';
    try {
      final shop = _shops.firstWhere(
        (s) => s['id'] == shopId,
        orElse: () => <String, String>{},
      );
      return shop['name'] as String? ?? 'Unknown';
    } catch (e) {
      return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Daily Sales Entry',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: _buildStepIndicator(),
        ),
      ),
      body: _currentStep == 0 ? _buildStep1Products() : _buildStep2Payment(),
    );
  }

  Widget _buildStepIndicator() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          _buildStepChip(0, 'Products & Quantities'),
          const SizedBox(width: 8),
          Icon(CupertinoIcons.chevron_right, size: 16, color: Colors.grey[400]),
          const SizedBox(width: 8),
          _buildStepChip(1, 'Payment Breakdown'),
        ],
      ),
    );
  }

  Widget _buildStepChip(int step, String label) {
    final isActive = _currentStep == step;
    final isCompleted = _currentStep > step;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primary
              : isCompleted
                  ? Colors.green[50]
                  : Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? AppColors.primary
                : isCompleted
                    ? Colors.green
                    : Colors.grey[300]!,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isCompleted
                  ? CupertinoIcons.check_mark_circled_solid
                  : isActive
                      ? CupertinoIcons.circle_fill
                      : CupertinoIcons.circle,
              size: 16,
              color: isActive
                  ? Colors.white
                  : isCompleted
                      ? Colors.green
                      : Colors.grey,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  color: isActive
                      ? Colors.white
                      : isCompleted
                          ? Colors.green[700]
                          : Colors.grey[600],
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ========== STEP 1: PRODUCTS & QUANTITIES ==========

  Widget _buildStep1Products() {
    return Consumer<DailySalesProvider>(
      builder: (context, provider, child) {
        return Column(
          children: [
            // Filter Row
            _buildFilterRow(provider),

            // Products Table
            Expanded(
              child: _buildProductsTable(provider),
            ),

            // Next Button
            _buildStep1NextButton(provider),
          ],
        );
      },
    );
  }

  Widget _buildFilterRow(DailySalesProvider provider) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // Shop Filter
          Expanded(
            child: _buildShopFilter(provider),
          ),
          const SizedBox(width: 12),
          // Date Filter
          Expanded(
            child: _buildDateFilter(provider),
          ),
        ],
      ),
    );
  }

  Widget _buildShopFilter(DailySalesProvider provider) {
    return InkWell(
      onTap: () => _selectShop(provider),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: provider.selectedShopId != null ? AppColors.primary : Colors.grey[300]!,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              CupertinoIcons.building_2_fill,
              size: 18,
              color: provider.selectedShopId != null ? AppColors.primary : Colors.grey[600],
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Shop',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _getShopName(provider.selectedShopId),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: provider.selectedShopId != null ? Colors.black87 : Colors.grey[500],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_down,
              size: 16,
              color: Colors.grey[600],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateFilter(DailySalesProvider provider) {
    return InkWell(
      onTap: () => _selectDate(provider),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(
              CupertinoIcons.calendar,
              size: 18,
              color: Colors.grey[600],
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Date',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    Formatters.date(provider.recordDate),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_down,
              size: 16,
              color: Colors.grey[600],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductsTable(DailySalesProvider provider) {
    if (provider.selectedShopId == null) {
      return _buildEmptyState(
        icon: CupertinoIcons.building_2_fill,
        title: 'Select a Shop',
        subtitle: 'Choose a shop from the filter above to view products',
      );
    }

    if (_isLoadingProducts) {
      return const Center(child: CircularProgressIndicator());
    }

    final productProvider = context.watch<ProductProvider>();
    final allProducts = productProvider.products;
    final stockMap = productProvider.stockByProductId;

    // Filter products with stock > 0
    final productsWithStock = allProducts.where((product) {
      final stock = stockMap[product.id];
      return stock != null && stock.quantity > 0;
    }).toList();

    if (productsWithStock.isEmpty) {
      return _buildEmptyState(
        icon: CupertinoIcons.cube_box,
        title: 'No Products Available',
        subtitle: 'No products with stock found in selected shop',
      );
    }

    return Column(
      children: [
        // Table Header
        Container(
          color: AppColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const Expanded(
                flex: 3,
                child: Text(
                  'Product',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                flex: 1,
                child: Text(
                  'Stock',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                flex: 1,
                child: Text(
                  'Price',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: Text(
                  'Qty',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Table Body
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 120), // Extra space for button
            itemCount: productsWithStock.length,
            itemBuilder: (context, index) {
              final product = productsWithStock[index];
              final stock = stockMap[product.id];
              final stockQty = stock?.quantity ?? 0;

              // Create controller if not exists
              if (!_quantityControllers.containsKey(product.id)) {
                _quantityControllers[product.id] = TextEditingController();
              }

              return _buildProductRow(
                product: product,
                stockQty: stockQty,
                controller: _quantityControllers[product.id]!,
                isEven: index % 2 == 0,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildProductRow({
    required models.Product product,
    required int stockQty,
    required TextEditingController controller,
    required bool isEven,
  }) {
    return Container(
      color: isEven ? Colors.white : Colors.grey[50],
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Product Name & Brand
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  product.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${product.brand?.name ?? 'Unknown'} • ${product.size ?? 'N/A'}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Stock
          Expanded(
            flex: 1,
            child: Text(
              '$stockQty',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: stockQty > 10 ? Colors.green[700] : Colors.orange[700],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Price
          Expanded(
            flex: 1,
            child: Text(
              '₹${product.sellingPrice.toStringAsFixed(0)}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Quantity Input
          Expanded(
            flex: 1,
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: '0',
                hintStyle: TextStyle(color: Colors.grey[400]),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.primary, width: 2),
                ),
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep1NextButton(DailySalesProvider provider) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: provider.selectedShopId == null ? null : () => _proceedToPayment(provider),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              disabledBackgroundColor: Colors.grey[300],
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Next: Payment Breakdown',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(width: 8),
                Icon(CupertinoIcons.arrow_right, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _proceedToPayment(DailySalesProvider provider) {
    print('💰 [DailySalesEntry] ========== PROCEED TO PAYMENT ==========');
    print('💰 [DailySalesEntry] Collecting quantities from ${_quantityControllers.length} products');

    // Collect products with quantities > 0
    final productProvider = context.read<ProductProvider>();
    final allProducts = productProvider.products;
    print('💰 [DailySalesEntry] Total products available: ${allProducts.length}');

    provider.clearItems();
    print('💰 [DailySalesEntry] Cleared existing items in provider');

    int addedCount = 0;
    for (var product in allProducts) {
      final controller = _quantityControllers[product.id];
      if (controller != null && controller.text.isNotEmpty) {
        final quantity = int.tryParse(controller.text);
        print('   📝 ${product.name}: Quantity = ${controller.text} (parsed: $quantity)');
        if (quantity != null && quantity > 0) {
          provider.addItem(product, quantity: quantity);
          addedCount++;
          print('      ✅ Added to cart - Price: ₹${product.sellingPrice}, Total: ₹${product.sellingPrice * quantity}');
        } else {
          print('      ⚠️  Skipped (invalid quantity)');
        }
      }
    }

    print('💰 [DailySalesEntry] Total items added: $addedCount');
    print('💰 [DailySalesEntry] Cart total amount: ₹${provider.totalItemsAmount}');

    if (addedCount == 0) {
      print('❌ [DailySalesEntry] No items added - showing error');
      SnackbarHelper.showError(context, 'Please enter quantities for at least one product');
      return;
    }

    print('✅ [DailySalesEntry] Proceeding to payment step');
    setState(() {
      _currentStep = 1;
    });
    print('💰 [DailySalesEntry] ========== PAYMENT STEP ACTIVE ==========\n');
  }

  // ========== STEP 2: PAYMENT BREAKDOWN ==========

  Widget _buildStep2Payment() {
    return Consumer<DailySalesProvider>(
      builder: (context, provider, child) {
        return Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Summary Card
                    _buildSummaryCard(provider),
                    const SizedBox(height: 16),

                    // Payment Breakdown
                    _buildPaymentBreakdownCard(provider),
                    const SizedBox(height: 16),

                    // Notes
                    _buildNotesCard(provider),
                  ],
                ),
              ),
            ),

            // Bottom Buttons
            _buildStep2BottomButtons(provider),
          ],
        );
      },
    );
  }

  Widget _buildSummaryCard(DailySalesProvider provider) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sales Summary',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // Items Count
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total Products',
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                ),
                Text(
                  '${provider.totalItemsCount}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Total Quantity
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total Quantity',
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                ),
                Text(
                  '${provider.items.fold(0, (sum, item) => sum + item.quantity)}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            const Divider(),
            const SizedBox(height: 8),

            // Total Amount
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total Amount',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  Formatters.currency(provider.totalItemsAmount),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentBreakdownCard(DailySalesProvider provider) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Payment Breakdown',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (provider.items.isNotEmpty)
                  TextButton.icon(
                    onPressed: () {
                      provider.autoDistributePayment();
                      SnackbarHelper.showSuccess(context, 'Payment distributed across items');
                    },
                    icon: const Icon(CupertinoIcons.arrow_2_circlepath, size: 16),
                    label: const Text('Auto-Fill'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Cash
            _buildPaymentInput(
              controller: _cashController,
              label: 'Cash Amount',
              icon: CupertinoIcons.money_dollar,
              color: Colors.green,
              onChanged: (value) {
                provider.setCashAmount(double.tryParse(value) ?? 0);
              },
            ),
            const SizedBox(height: 12),

            // Card
            _buildPaymentInput(
              controller: _cardController,
              label: 'Card Amount',
              icon: CupertinoIcons.creditcard,
              color: Colors.blue,
              onChanged: (value) {
                provider.setCardAmount(double.tryParse(value) ?? 0);
              },
            ),
            const SizedBox(height: 12),

            // UPI
            _buildPaymentInput(
              controller: _upiController,
              label: 'UPI Amount',
              icon: CupertinoIcons.qrcode,
              color: Colors.purple,
              onChanged: (value) {
                provider.setUpiAmount(double.tryParse(value) ?? 0);
              },
            ),
            const SizedBox(height: 12),

            // Credit
            _buildPaymentInput(
              controller: _creditController,
              label: 'Credit Amount',
              icon: CupertinoIcons.time,
              color: Colors.orange,
              onChanged: (value) {
                provider.setCreditAmount(double.tryParse(value) ?? 0);
              },
            ),
            const SizedBox(height: 16),

            // Total Payment & Balance
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: provider.totalPaymentAmount == provider.totalItemsAmount
                    ? Colors.green.withValues(alpha: 0.1)
                    : Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: provider.totalPaymentAmount == provider.totalItemsAmount
                      ? Colors.green
                      : Colors.orange,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total Payment Entered',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        Formatters.currency(provider.totalPaymentAmount),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        provider.totalPaymentAmount == provider.totalItemsAmount
                            ? CupertinoIcons.check_mark_circled_solid
                            : CupertinoIcons.exclamationmark_triangle_fill,
                        size: 16,
                        color: provider.totalPaymentAmount == provider.totalItemsAmount
                            ? Colors.green
                            : Colors.orange,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        provider.totalPaymentAmount == provider.totalItemsAmount
                            ? 'Balanced'
                            : 'Difference: ${Formatters.currency((provider.totalItemsAmount - provider.totalPaymentAmount).abs())}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: provider.totalPaymentAmount == provider.totalItemsAmount
                              ? Colors.green[700]
                              : Colors.orange[700],
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

  Widget _buildPaymentInput({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required Color color,
    required Function(String) onChanged,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            decoration: InputDecoration(
              labelText: label,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              prefixText: '₹ ',
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildNotesCard(DailySalesProvider provider) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Notes (Optional)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Add any notes about today\'s sales...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
              onChanged: (value) => provider.setNotes(value),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep2BottomButtons(DailySalesProvider provider) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: SafeArea(
        child: Row(
          children: [
            // Back Button
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  setState(() {
                    _currentStep = 0;
                  });
                },
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.grey[400]!),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(CupertinoIcons.arrow_left, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Back',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Submit Button
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: provider.isSubmitting || !provider.isValid
                    ? null
                    : () => _submitRecord(provider),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  disabledBackgroundColor: Colors.grey[300],
                ),
                child: provider.isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(CupertinoIcons.check_mark_circled, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Submit for Approval',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ========== HELPER METHODS ==========

  Future<void> _selectDate(DailySalesProvider provider) async {
    final date = await showDatePicker(
      context: context,
      initialDate: provider.recordDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now(),
    );
    if (date != null) {
      provider.setRecordDate(date);
    }
  }

  Future<void> _selectShop(DailySalesProvider provider) async {
    if (_shops.isEmpty) {
      SnackbarHelper.showError(context, 'No shops available');
      return;
    }

    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Select Shop',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              ..._shops.map((shop) {
                return ListTile(
                  leading: const Icon(CupertinoIcons.building_2_fill),
                  title: Text(shop['name']),
                  onTap: () => Navigator.pop(context, shop),
                );
              }),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );

    if (selected != null) {
      final shopId = selected['id'] as String;
      provider.setShop(shopId);

      // Load products for the selected shop
      print('🏪 [DailySalesEntry] Shop selected: ${selected['name']} (ID: $shopId)');
      await _loadProducts(shopId);
      if (mounted) {
        SnackbarHelper.showSuccess(context, 'Products loaded for ${selected['name']}');
      }
    }
  }

  Future<void> _submitRecord(DailySalesProvider provider) async {
    print('📤 [DailySalesEntry] ========== SUBMIT RECORD ==========');
    print('📤 [DailySalesEntry] Validating form data...');

    final validationError = provider.validate();
    if (validationError != null) {
      print('❌ [DailySalesEntry] Validation failed: $validationError');
      SnackbarHelper.showError(context, validationError);
      return;
    }
    print('✅ [DailySalesEntry] Validation passed');

    print('📤 [DailySalesEntry] Showing confirmation dialog...');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Submit Daily Sales?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Please review before submitting:'),
              const SizedBox(height: 12),
              Text('Date: ${Formatters.date(provider.recordDate)}'),
              Text('Shop: ${_getShopName(provider.selectedShopId)}'),
              Text('Products: ${provider.totalItemsCount}'),
              Text('Total Amount: ${Formatters.currency(provider.totalItemsAmount)}'),
              const SizedBox(height: 12),
              const Text(
                'This will be sent to manager for approval.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
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
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              child: const Text('Submit'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      print('✅ [DailySalesEntry] User confirmed submission');
      print('📤 [DailySalesEntry] Calling provider.createRecord()...');
      final success = await provider.createRecord();

      print('📤 [DailySalesEntry] createRecord returned: $success');
      if (mounted) {
        if (success) {
          print('✅ [DailySalesEntry] Record created successfully!');
          SnackbarHelper.showSuccess(context, 'Daily sales record submitted successfully!');

          // Clear all quantity controllers
          print('🧹 [DailySalesEntry] Clearing form controllers...');
          for (var controller in _quantityControllers.values) {
            controller.clear();
          }
          _cashController.clear();
          _cardController.clear();
          _upiController.clear();
          _creditController.clear();
          _notesController.clear();

          // Reset to step 1
          setState(() {
            _currentStep = 0;
          });
          print('✅ [DailySalesEntry] Form reset complete');
        } else {
          print('❌ [DailySalesEntry] Record creation failed: ${provider.errorMessage}');
          // Show detailed error dialog
          await showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red, size: 28),
                  SizedBox(width: 12),
                  Text('Submission Failed'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Unable to submit daily sales record:',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 20, color: Colors.red.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            provider.errorMessage ?? 'Unknown error occurred',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.red.shade900,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Please check the error message above and try again.',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      }
    } else {
      print('❌ [DailySalesEntry] User cancelled submission');
    }
    print('📤 [DailySalesEntry] ========== SUBMIT COMPLETE ==========\n');
  }
}
