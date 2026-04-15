import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/providers/shop_selection_provider.dart';
import '../../../core/widgets/shop_selector_widget.dart';
import '../../../shared/widgets/empty_state_widget.dart';
import '../providers/product_provider.dart';
import '../models/product.dart' as models;
import 'ai_stock_setup_screen.dart';

/// Stock Management Screen - View and manage stock levels
class StockScreen extends StatefulWidget {
  const StockScreen({super.key});

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _filterType = 'all'; // all, low, out

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadStock();
    });
  }

  void _onScroll() {
    // Dismiss keyboard when scrolling (best practice for data entry screens)
    _dismissKeyboard();
  }

  /// Dismiss keyboard when tapping outside input fields or scrolling
  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _openAiStockSetup() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AiStockSetupScreen()),
    );
    if (result == true && mounted) {
      // AiStockSetupScreen already refreshed provider before popping,
      // but do a safety refresh of both products + stock
      final shopId = context.read<ShopSelectionProvider>().selectedShopId;
      if (shopId != null) {
        await context.read<ProductProvider>().loadProducts(shopId: shopId);
      }
      _loadStock();
    }
  }

  Future<void> _loadStock() async {
    if (!mounted) return;

    // Get shop ID from ShopSelectionProvider
    final shopProvider = context.read<ShopSelectionProvider>();
    final shopId = shopProvider.selectedShopId;

    if (shopId != null) {
      // Pass shop ID to loadStock to get shop-specific stock data
      await context.read<ProductProvider>().loadStock(shopId: shopId);
    }
  }

  List<models.Stock> _getFilteredStock(ProductProvider provider) {
    final allStock = provider.stockByProductId.values.toList();

    // Apply search filter
    List<models.Stock> filtered = allStock;
    if (_searchController.text.isNotEmpty) {
      final query = _searchController.text.toLowerCase();
      filtered = filtered.where((stock) {
        final product = provider.products.firstWhere(
          (p) => p.id == stock.productId,
          orElse: () => models.Product(
            id: '',
            name: '',
            size: '',
            categoryId: '',
            category: models.Category(
              id: '',
              name: '',
              description: '',
              isActive: true,
              sortOrder: 0,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
            brandId: '',
            alcoholContent: 0,
            description: '',
            barcode: '',
            sku: '',
            imageUrl: '',
            isActive: true,
            costPrice: 0,
            dutyFee: 0,
            totalCost: 0,
            sellingPrice: 0,
            mrp: 0,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
        return product.name.toLowerCase().contains(query);
      }).toList();
    }

    // Apply stock filter
    switch (_filterType) {
      case 'low':
        filtered = filtered.where((stock) => stock.isLowStock && !stock.isOutOfStock).toList();
        break;
      case 'out':
        filtered = filtered.where((stock) => stock.isOutOfStock).toList();
        break;
      default:
        break;
    }

    return filtered;
  }

  String _formatCurrency(double amount) {
    final formatter = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    );
    return formatter.format(amount);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAiStockSetup,
        backgroundColor: const Color(0xFF3855B3),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.auto_awesome, size: 20),
        label: const Text('AI Stock Setup', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: GestureDetector(
        onTap: _dismissKeyboard,
        behavior: HitTestBehavior.translucent,
        child: Consumer<ProductProvider>(
          builder: (context, provider, child) {
            final filteredStock = _getFilteredStock(provider);

            return Column(
            children: [
              // Shop Selector
              ShopSelectorWidget(
                onShopChanged: (shopId) {
                  // Reload stock when shop changes
                  if (shopId != null) {
                    _loadStock();
                  }
                },
              ),

              // Search and Filter Bar
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.surface,
                  border: Border(bottom: BorderSide(color: cs.outline.withValues(alpha: 0.2))),
                ),
                child: Column(
                  children: [
                    // Search Field
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search products...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  setState(() {
                                    _searchController.clear();
                                  });
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: cs.surfaceContainerHighest,
                      ),
                      onChanged: (value) {
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 12),

                    // Filter Chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip('All Stock', 'all'),
                          const SizedBox(width: 8),
                          _buildFilterChip('Low Stock', 'low'),
                          const SizedBox(width: 8),
                          _buildFilterChip('Out of Stock', 'out'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Stock Summary Cards
              if (provider.stockByProductId.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildSummaryCard(
                          'Total Items',
                          provider.stockByProductId.length.toString(),
                          Icons.inventory_2,
                          cs.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildSummaryCard(
                          'Low Stock',
                          provider.stockByProductId.values
                              .where((s) => s.isLowStock && !s.isOutOfStock)
                              .length
                              .toString(),
                          Icons.warning,
                          AppColors.warning,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildSummaryCard(
                          'Out of Stock',
                          provider.stockByProductId.values
                              .where((s) => s.isOutOfStock)
                              .length
                              .toString(),
                          Icons.error,
                          AppColors.error,
                        ),
                      ),
                    ],
                  ),
                ),

              // Stock List
              Expanded(
                child: filteredStock.isEmpty
                    ? const EmptyStateWidget(
                        icon: Icons.inventory_2_outlined,
                        title: 'No Stock Data',
                        message: 'Stock information will appear here',
                      )
                    : RefreshIndicator(
                        onRefresh: _loadStock,
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: filteredStock.length,
                          itemBuilder: (context, index) {
                            final stock = filteredStock[index];
                            final product = provider.products.firstWhere(
                              (p) => p.id == stock.productId,
                              orElse: () => models.Product(
                                id: stock.productId,
                                name: 'Unknown Product',
                                size: '',
                                categoryId: '',
                                category: models.Category(
                                  id: '',
                                  name: '',
                                  description: '',
                                  isActive: true,
                                  sortOrder: 0,
                                  createdAt: DateTime.now(),
                                  updatedAt: DateTime.now(),
                                ),
                                brandId: '',
                                alcoholContent: 0,
                                description: '',
                                barcode: '',
                                sku: '',
                                imageUrl: '',
                                isActive: true,
                                costPrice: 0,
                                dutyFee: 0,
                                totalCost: 0,
                                sellingPrice: 0,
                                mrp: 0,
                                createdAt: DateTime.now(),
                                updatedAt: DateTime.now(),
                              ),
                            );
                            return _buildStockCard(stock, product);
                          },
                        ),
                      ),
              ),
            ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = _filterType == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _filterType = value;
        });
      },
      selectedColor: cs.primary.withValues(alpha: 0.2),
      labelStyle: TextStyle(
        color: isSelected ? cs.primary : cs.onSurfaceVariant,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }

  Widget _buildSummaryCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
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
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: AppTextStyles.h5.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: AppTextStyles.bodySmall.copyWith(
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildStockCard(models.Stock stock, models.Product product) {
    final cs = Theme.of(context).colorScheme;
    final statusColor = stock.isOutOfStock
        ? AppColors.error
        : stock.isLowStock
            ? AppColors.warning
            : AppColors.success;

    final statusText = stock.isOutOfStock
        ? 'Out of Stock'
        : stock.isLowStock
            ? 'Low Stock'
            : 'In Stock';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product Header
            Row(
              children: [
                // Product Image (use stock's imageUrl if available)
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(8),
                    image: (stock.imageUrl?.isNotEmpty ?? false)
                        ? DecorationImage(
                            image: NetworkImage(stock.imageUrl!),
                            fit: BoxFit.cover,
                            onError: (exception, stackTrace) {
                              // Silently handle image load errors - fallback will show
                            },
                          )
                        : (product.imageUrl.isNotEmpty
                            ? DecorationImage(
                                image: NetworkImage(product.imageUrl),
                                fit: BoxFit.cover,
                                onError: (exception, stackTrace) {
                                  // Silently handle image load errors - fallback will show
                                },
                              )
                            : null),
                  ),
                  child: (stock.imageUrl?.isEmpty ?? true) && product.imageUrl.isEmpty
                      ? Icon(Icons.liquor, color: cs.onSurfaceVariant)
                      : null,
                ),
                const SizedBox(width: 12),

                // Product Info (use stock's productName if available)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stock.productName ?? product.name,
                        style: AppTextStyles.bodyLarge.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      if (product.brand != null)
                        Text(
                          product.brand!.name,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        product.size,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),

                // Status Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor.withValues(alpha:0.3)),
                  ),
                  child: Text(
                    statusText,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),

            // Stock Details Grid
            Row(
              children: [
                Expanded(
                  child: _buildStockDetail(
                    'Current',
                    stock.quantity.toString(),
                    Icons.inventory,
                    statusColor,
                  ),
                ),
                Expanded(
                  child: _buildStockDetail(
                    'Reserved',
                    stock.reservedQuantity.toString(),
                    Icons.lock,
                    cs.onSurfaceVariant,
                  ),
                ),
                Expanded(
                  child: _buildStockDetail(
                    'Available',
                    stock.availableQuantity.toString(),
                    Icons.check_circle,
                    AppColors.success,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: _buildStockDetail(
                    'Min Level',
                    stock.minimumLevel.toString(),
                    Icons.arrow_downward,
                    AppColors.warning,
                  ),
                ),
                Expanded(
                  child: _buildStockDetail(
                    'Max Level',
                    stock.maximumLevel.toString(),
                    Icons.arrow_upward,
                    cs.primary,
                  ),
                ),
                Expanded(
                  child: _buildStockDetail(
                    'Avg Cost',
                    _formatCurrency(stock.averageCost),
                    Icons.attach_money,
                    cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),

            // Last Purchase Info
            if (stock.lastPurchaseDate != null) ...[
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 14,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Last Purchase: ${DateFormat('MMM dd, yyyy').format(stock.lastPurchaseDate!)}',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    _formatCurrency(stock.lastPurchasePrice),
                    style: AppTextStyles.bodySmall.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStockDetail(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTextStyles.bodyMedium.copyWith(
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            color: cs.onSurfaceVariant,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}
