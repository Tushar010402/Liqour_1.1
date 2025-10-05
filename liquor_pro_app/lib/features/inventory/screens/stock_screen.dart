import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../shared/widgets/empty_state_widget.dart';
import '../providers/product_provider.dart';
import '../models/product.dart' as models;

/// Stock Management Screen - View and manage stock levels
class StockScreen extends StatefulWidget {
  const StockScreen({super.key});

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _filterType = 'all'; // all, low, out

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadStock();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadStock() async {
    if (!mounted) return;
    await context.read<ProductProvider>().loadStock();
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
    return Scaffold(
      body: Consumer<ProductProvider>(
        builder: (context, provider, child) {
          final filteredStock = _getFilteredStock(provider);

          return Column(
            children: [
              // Search and Filter Bar
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
                        fillColor: Colors.white,
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
                          AppColors.primary,
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
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _filterType == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _filterType = value;
        });
      },
      selectedColor: AppColors.primary.withOpacity(0.2),
      labelStyle: TextStyle(
        color: isSelected ? AppColors.primary : AppColors.textSecondary,
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
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.3),
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
                // Product Image
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    image: product.imageUrl.isNotEmpty
                        ? DecorationImage(
                            image: NetworkImage(product.imageUrl),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: product.imageUrl.isEmpty
                      ? const Icon(Icons.liquor, color: AppColors.textSecondary)
                      : null,
                ),
                const SizedBox(width: 12),

                // Product Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
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
                            color: AppColors.textSecondary,
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        product.size,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),

                // Status Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor.withOpacity(0.3)),
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
                    AppColors.textSecondary,
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
                    AppColors.primary,
                  ),
                ),
                Expanded(
                  child: _buildStockDetail(
                    'Avg Cost',
                    _formatCurrency(stock.averageCost),
                    Icons.attach_money,
                    AppColors.textSecondary,
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
                      const Icon(
                        Icons.calendar_today,
                        size: 14,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Last Purchase: ${DateFormat('MMM dd, yyyy').format(stock.lastPurchaseDate!)}',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    _formatCurrency(stock.lastPurchasePrice),
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.primary,
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
            color: AppColors.textSecondary,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}
