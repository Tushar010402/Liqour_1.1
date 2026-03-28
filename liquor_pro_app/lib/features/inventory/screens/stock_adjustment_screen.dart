import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/theme/ios_design_tokens.dart';
import '../../../core/services/dio_api_service.dart';
import '../../../core/providers/shop_selection_provider.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../models/product.dart';
import '../providers/product_provider.dart';
import '../services/stock_service.dart';
import '../../../core/utils/logger.dart';

/// Modern Stock Adjustment Screen
/// iOS-inspired design with quick numeric pad and intuitive controls
class StockAdjustmentScreen extends StatefulWidget {
  final Product? product;

  const StockAdjustmentScreen({
    super.key,
    this.product,
  });

  @override
  State<StockAdjustmentScreen> createState() => _StockAdjustmentScreenState();
}

class _StockAdjustmentScreenState extends State<StockAdjustmentScreen> {
  final _notesController = TextEditingController();

  String _adjustmentType = 'add'; // 'add' or 'remove'
  Product? _selectedProduct;
  int _quantity = 0;
  String _reason = 'Purchase';
  bool _isLoading = true;
  bool _isSubmitting = false;
  List<Product> _products = [];
  String? _selectedShopId;

  final List<String> _addReasons = [
    'Purchase',
    'Stock Return',
    'Correction',
    'Transfer In',
    'Other',
  ];

  final List<String> _removeReasons = [
    'Sale',
    'Damage',
    'Expiry',
    'Theft',
    'Transfer Out',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.product != null) {
      _selectedProduct = widget.product;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialData();
    });
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);

    try {
      final shopProvider = context.read<ShopSelectionProvider>();
      _selectedShopId = shopProvider.selectedShopId;

      final productProvider = context.read<ProductProvider>();
      await productProvider.loadProducts(shopId: _selectedShopId);

      setState(() {
        _products = productProvider.products;
        if (widget.product == null && _selectedProduct == null && _products.isNotEmpty) {
          _selectedProduct = _products.first;
        }
      });
    } catch (e) {
      Logger.debug('❌ Error loading initial data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _incrementQuantity(int amount) {
    setState(() {
      _quantity = (_quantity + amount).clamp(0, 9999);
    });
  }

  void _handleSubmit() async {
    if (_selectedShopId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a shop'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (_selectedProduct == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a product'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (_quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid quantity'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium)),
        title: Row(
          children: [
            Icon(
              _adjustmentType == 'add' ? Icons.add_circle : Icons.remove_circle,
              color: _adjustmentType == 'add' ? AppColors.success : AppColors.error,
            ),
            const SizedBox(width: 8),
            const Text('Confirm Adjustment'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_adjustmentType == 'add' ? 'Add' : 'Remove'} $_quantity units',
              style: AppTextStyles.h5,
            ),
            const SizedBox(height: 8),
            Text('Product: ${_selectedProduct!.name}'),
            Text('Reason: $_reason'),
            if (_notesController.text.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Notes: ${_notesController.text}'),
            ],
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
              backgroundColor: _adjustmentType == 'add' ? AppColors.success : AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSubmitting = true);

    try {
      final apiService = context.read<DioApiService>();
      final stockService = StockService(apiService);

      Logger.debug('📦 Adjusting stock: shop=$_selectedShopId, product=${_selectedProduct!.id}, qty=$_quantity, type=$_adjustmentType');

      final response = await stockService.adjustStock(
        shopId: _selectedShopId!,
        productId: _selectedProduct!.id,
        quantity: _quantity,
        adjustmentType: _adjustmentType,
        reason: _reason,
        notes: _notesController.text.isNotEmpty ? _notesController.text : null,
      );

      if (!mounted) return;

      if (response.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text('Stock ${_adjustmentType == 'add' ? 'added' : 'removed'} successfully'),
              ],
            ),
            backgroundColor: AppColors.success,
          ),
        );

        // Refresh product list
        context.read<ProductProvider>().loadProducts(shopId: _selectedShopId);

        // Navigate back
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response.message ?? 'Failed to adjust stock'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      Logger.debug('❌ Error adjusting stock: $e');
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final reasons = _adjustmentType == 'add' ? _addReasons : _removeReasons;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: CustomAppBar(
        title: 'Adjust Stock',
        actions: [
          if (_selectedProduct != null)
            IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium)),
                    title: const Text('Product Info'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_selectedProduct!.name, style: AppTextStyles.h5),
                        const SizedBox(height: 8),
                        Text('Size: ${_selectedProduct!.size}'),
                        Text('Current Stock: ${_selectedProduct!.stockQuantity ?? 0}'),
                        if (_selectedProduct!.brand?.name != null)
                          Text('Brand: ${_selectedProduct!.brand!.name}'),
                        if (_selectedProduct!.category?.name != null)
                          Text('Category: ${_selectedProduct!.category!.name}'),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Adjustment Type Selector
                      Container(
                        decoration: BoxDecoration(
                          color: cs.surface,
                          borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
                          border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Adjustment Type',
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildTypeButton(
                                    type: 'add',
                                    label: 'Add Stock',
                                    icon: Icons.add_circle,
                                    color: AppColors.success,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildTypeButton(
                                    type: 'remove',
                                    label: 'Remove',
                                    icon: Icons.remove_circle,
                                    color: AppColors.error,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Product Selector
                      if (widget.product == null) ...[
                        Container(
                          decoration: BoxDecoration(
                            color: cs.surface,
                            borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
                            border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
                          ),
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Select Product',
                                style: AppTextStyles.bodyMedium.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<Product>(
                                initialValue: _selectedProduct,
                                decoration: InputDecoration(
                                  prefixIcon: const Icon(Icons.inventory_2),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
                                  ),
                                  filled: true,
                                  fillColor: cs.surfaceContainerHighest,
                                ),
                                items: _products.map((product) {
                                  return DropdownMenuItem<Product>(
                                    value: product,
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: Text(
                                        '${product.name} - ${product.size}',
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                    ),
                                  );
                                }).toList(),
                                onChanged: _isSubmitting
                                    ? null
                                    : (value) => setState(() => _selectedProduct = value),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Current Product Display (if pre-selected)
                      if (widget.product != null && _selectedProduct != null) ...[
                        Container(
                          decoration: BoxDecoration(
                            color: cs.surface,
                            borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
                            border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(16),
                            leading: Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: cs.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
                              ),
                              child: Icon(Icons.liquor, color: cs.primary, size: 32),
                            ),
                            title: Text(
                              _selectedProduct!.name,
                              style: AppTextStyles.bodyLarge.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text('Size: ${_selectedProduct!.size}'),
                                Text('Current Stock: ${_selectedProduct!.stockQuantity ?? 0}'),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Quantity Input with Quick Buttons
                      Container(
                        decoration: BoxDecoration(
                          color: cs.surface,
                          borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
                          border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Quantity',
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Large quantity display
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    _quantity.toString(),
                                    style: TextStyle(
                                      fontSize: 48,
                                      fontWeight: FontWeight.bold,
                                      color: cs.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Quick adjustment buttons
                            Row(
                              children: [
                                Expanded(
                                  child: _buildQuantityButton(1, '+1'),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _buildQuantityButton(5, '+5'),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _buildQuantityButton(10, '+10'),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _buildQuantityButton(50, '+50'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildClearButton(),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _buildCustomButton(),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Reason Selector
                      Container(
                        decoration: BoxDecoration(
                          color: cs.surface,
                          borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
                          border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Reason',
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: reasons.map((reason) {
                                final isSelected = _reason == reason;
                                return ChoiceChip(
                                  label: Text(reason),
                                  selected: isSelected,
                                  onSelected: (selected) {
                                    if (selected) {
                                      setState(() => _reason = reason);
                                    }
                                  },
                                  selectedColor: cs.primary.withValues(alpha: 0.2),
                                  labelStyle: TextStyle(
                                    color: isSelected ? cs.primary : cs.onSurfaceVariant,
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Notes
                      Container(
                        decoration: BoxDecoration(
                          color: cs.surface,
                          borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
                          border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Notes (Optional)',
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _notesController,
                              maxLines: 3,
                              decoration: InputDecoration(
                                hintText: 'Add any additional notes',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
                                ),
                                filled: true,
                                fillColor: cs.surfaceContainerHighest,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Bottom Submit Button
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    border: Border(top: BorderSide(color: cs.outline.withValues(alpha: 0.2))),
                  ),
                  child: SafeArea(
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isSubmitting || _quantity == 0 ? null : _handleSubmit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _adjustmentType == 'add'
                              ? AppColors.success
                              : AppColors.error,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
                          ),
                          elevation: 0,
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _adjustmentType == 'add'
                                        ? Icons.add_circle
                                        : Icons.remove_circle,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${_adjustmentType == 'add' ? 'Add' : 'Remove'} $_quantity Units',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildTypeButton({
    required String type,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = _adjustmentType == type;
    return InkWell(
      onTap: () {
        setState(() {
          _adjustmentType = type;
          _reason = type == 'add' ? 'Purchase' : 'Sale';
        });
      },
      borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.1) : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
          border: Border.all(
            color: isSelected ? color : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? color : Theme.of(context).colorScheme.onSurfaceVariant,
              size: 32,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? color : Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuantityButton(int amount, String label) {
    final cs = Theme.of(context).colorScheme;
    return ElevatedButton(
      onPressed: () => _incrementQuantity(amount),
      style: ElevatedButton.styleFrom(
        backgroundColor: cs.primary.withValues(alpha: 0.1),
        foregroundColor: cs.primary,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
        ),
        elevation: 0,
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildClearButton() {
    return ElevatedButton(
      onPressed: () => setState(() => _quantity = 0),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.error.withValues(alpha: 0.1),
        foregroundColor: AppColors.error,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
        ),
        elevation: 0,
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.clear, size: 18),
          SizedBox(width: 4),
          Text(
            'Clear',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomButton() {
    final cs = Theme.of(context).colorScheme;
    return ElevatedButton(
      onPressed: () async {
        final controller = TextEditingController(text: _quantity > 0 ? _quantity.toString() : '');
        final result = await showDialog<int>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium)),
            title: const Text('Enter Custom Quantity'),
            content: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                hintText: 'Enter quantity',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  final value = int.tryParse(controller.text) ?? 0;
                  Navigator.pop(context, value);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: cs.primary,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Set'),
              ),
            ],
          ),
        );

        if (result != null) {
          setState(() => _quantity = result.clamp(0, 9999));
        }
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
        ),
        elevation: 0,
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.edit, size: 18),
          SizedBox(width: 4),
          Text(
            'Custom',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
