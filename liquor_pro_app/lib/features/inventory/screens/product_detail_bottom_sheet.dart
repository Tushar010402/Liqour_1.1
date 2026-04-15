import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/dio_api_service.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../core/providers/shop_selection_provider.dart';
import '../models/product_with_stock.dart';
import '../providers/product_provider.dart';
import '../models/brand_variant_edit_model.dart';
import 'edit_brand_variant_screen.dart';
import '../services/stock_service.dart';

/// Product Detail Bottom Sheet with Tabbed Interface
///
/// Features:
/// - Details Tab: Complete product information with pricing breakdown
/// - Adjust Stock Tab: Inline stock adjustment (no page navigation)
///
/// Usage:
/// - ProductDetailBottomSheet.show(context, product) → Opens Details tab
/// - ProductDetailBottomSheet.show(context, product, initialTab: 'stock_adjustment') → Opens Stock Adjustment tab
class ProductDetailBottomSheet extends StatefulWidget {
  final ProductWithStock product;
  final String? initialTab; // 'details' or 'stock_adjustment'

  const ProductDetailBottomSheet({
    super.key,
    required this.product,
    this.initialTab,
  });

  static Future<void> show(
    BuildContext context,
    ProductWithStock product, {
    String? initialTab,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ProductDetailBottomSheet(
        product: product,
        initialTab: initialTab,
      ),
    );
  }

  @override
  State<ProductDetailBottomSheet> createState() => _ProductDetailBottomSheetState();
}

class _ProductDetailBottomSheetState extends State<ProductDetailBottomSheet>
    with TickerProviderStateMixin {
  TabController? _tabController;
  bool? _canModify;

  // Stock adjustment state
  int _adjustmentQuantity = 1;
  bool _isAddingStock = true; // true = add, false = remove
  String _selectedReason = 'Purchase';
  final TextEditingController _notesController = TextEditingController();
  bool _isSubmitting = false;

  final List<String> _addReasons = [
    'Purchase',
    'Stock Transfer In',
    'Return from Customer',
    'Found',
    'Adjustment',
  ];

  final List<String> _removeReasons = [
    'Sale',
    'Stock Transfer Out',
    'Damaged',
    'Expired',
    'Lost',
    'Adjustment',
  ];

  Color get _stockColor {
    if (widget.product.currentStock <= 10) return AppColors.error;
    if (widget.product.currentStock <= 50) return AppColors.warning;
    return AppColors.success;
  }

  /// Check if user has permission to modify products (Admin, Manager, Assistant Manager)
  bool _checkCanModifyProducts(BuildContext context) {
    final authProvider = context.read<AuthProvider>();
    final role = (authProvider.currentUser?.role ?? '').toLowerCase();
    // Salesman and Executive can only view, not modify
    return role != 'salesman' && role != 'executive';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final canModify = _checkCanModifyProducts(context);

    // Only create/recreate controller if role permissions changed or first time
    if (_canModify != canModify || _tabController == null) {
      _canModify = canModify;
      _tabController?.dispose();

      final tabLength = canModify ? 2 : 1;
      final initialIndex = (widget.initialTab == 'stock_adjustment' && canModify) ? 1 : 0;

      _tabController = TabController(
        length: tabLength,
        vsync: this,
        initialIndex: initialIndex,
      );
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Drag Handle
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Product Header (always visible)
              _buildProductHeader(),

              // TabBar - Only show Adjust Stock tab for users with modify permissions
              Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  border: Border(
                    bottom: BorderSide(color: cs.outlineVariant),
                  ),
                ),
                child: TabBar(
                  controller: _tabController!,
                  labelColor: cs.primary,
                  unselectedLabelColor: cs.onSurfaceVariant,
                  indicatorColor: cs.primary,
                  indicatorWeight: 3,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  tabs: [
                    const Tab(
                      icon: Icon(Icons.info_outline, size: 20),
                      text: 'Details',
                    ),
                    if (_canModify == true)
                      const Tab(
                        icon: Icon(Icons.add_circle_outline, size: 20),
                        text: 'Adjust Stock',
                      ),
                  ],
                ),
              ),

              // Tab Content
              Expanded(
                child: TabBarView(
                  controller: _tabController!,
                  children: [
                    _buildDetailsTab(scrollController),
                    if (_canModify == true)
                      _buildStockAdjustmentTab(scrollController),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Product header with stock badge, name, and close button
  Widget _buildProductHeader() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Stock Badge
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: _stockColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _stockColor, width: 2),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${widget.product.currentStock}',
                  style: TextStyle(
                    color: _stockColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                Text(
                  'units',
                  style: TextStyle(
                    color: _stockColor,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // Product Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.product.brand != null)
                  Text(
                    widget.product.brand!.name,
                    style: AppTextStyles.caption.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                Text(
                  widget.product.name,
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    Text(
                      widget.product.size,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    if (widget.product.category != null) ...[
                      Text(' • ', style: TextStyle(color: cs.onSurfaceVariant)),
                      Text(
                        widget.product.category!.name,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Close Button
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
            color: cs.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  /// Details Tab - Product information with pricing breakdown
  Widget _buildDetailsTab(ScrollController scrollController) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        // Low Stock Warning
        if (widget.product.isLowStock)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.error.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber, color: AppColors.error),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Low Stock! Only ${widget.product.currentStock} units remaining.',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Pricing Information Section
        _buildSectionHeader('Pricing Breakdown', Icons.monetization_on),
        const SizedBox(height: 12),

        _buildInfoCard(
          icon: Icons.shopping_cart,
          label: 'Cost Price',
          value: '₹${widget.product.costPrice.toStringAsFixed(2)}',
          color: AppColors.info,
          subtitle: 'Base purchasing price',
        ),
        const SizedBox(height: 8),

        _buildInfoCard(
          icon: Icons.account_balance,
          label: 'Duty Fee',
          value: '₹${widget.product.governmentDuty.toStringAsFixed(2)}',
          color: cs.tertiary,
          subtitle: 'Government excise duty',
        ),
        const SizedBox(height: 8),

        _buildInfoCard(
          icon: Icons.calculate,
          label: 'Total Cost',
          value: '₹${widget.product.costPrice.toStringAsFixed(2)}',
          color: cs.secondary,
          subtitle: 'Your buying price',
        ),
        const SizedBox(height: 8),

        _buildInfoCard(
          icon: Icons.sell,
          label: 'Selling Price',
          value: '₹${(widget.product.sellingPrice > 0 ? widget.product.sellingPrice : widget.product.mrp).toStringAsFixed(2)}',
          color: AppColors.success,
          subtitle: 'Your selling price',
        ),
        const SizedBox(height: 8),

        _buildInfoCard(
          icon: Icons.local_offer,
          label: 'MRP',
          value: '₹${widget.product.mrp.toStringAsFixed(2)}',
          color: const Color(0xFF3855B3),
          subtitle: 'Maximum retail price',
        ),
        const SizedBox(height: 8),

        _buildInfoCard(
          icon: Icons.trending_up,
          label: 'Profit Margin',
          value: '₹${((widget.product.sellingPrice > 0 ? widget.product.sellingPrice : widget.product.mrp) - widget.product.costPrice).toStringAsFixed(2)}',
          color: (widget.product.sellingPrice > 0 ? widget.product.sellingPrice : widget.product.mrp) > widget.product.costPrice
              ? AppColors.success
              : AppColors.error,
          subtitle: '${_calculateProfitPercentage(widget.product)}% margin',
        ),

        const SizedBox(height: 24),

        // Product Details Section
        _buildSectionHeader('Product Information', Icons.info_outline),
        const SizedBox(height: 12),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _buildDetailRow('Product ID', widget.product.id),
              _buildDetailRow('Barcode', widget.product.barcode),
              _buildDetailRow('SKU', widget.product.hsnCode),
              _buildDetailRow('Size', widget.product.size),
              if (widget.product.category != null)
                _buildDetailRow('Category', widget.product.category!.name),
              if (widget.product.subcategory != null)
                _buildDetailRow('Subcategory', widget.product.subcategory!.name),
              if (widget.product.brand != null)
                _buildDetailRow('Brand', widget.product.brand!.name),
              _buildDetailRow('Status', widget.product.isActive ? 'Active' : 'Inactive'),
              if (widget.product.product.description.isNotEmpty)
                _buildDetailRow('Description', widget.product.product.description, maxLines: 3),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Stock Information Section
        if (widget.product.stock != null) ...[
          _buildSectionHeader('Stock Details', Icons.inventory),
          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _buildDetailRow('Current Stock', '${widget.product.currentStock} units'),
                _buildDetailRow('Reserved', '${widget.product.reservedQuantity} units'),
                _buildDetailRow('Available', '${widget.product.availableQuantity} units'),
                _buildDetailRow('Minimum Level', '${widget.product.minimumLevel} units'),
                _buildDetailRow('Maximum Level', '${widget.product.maximumLevel} units'),
                if (widget.product.stock!.lastPurchasePrice > 0)
                  _buildDetailRow('Last Purchase Price', '₹${widget.product.stock!.lastPurchasePrice.toStringAsFixed(2)}'),
                if (widget.product.stock!.lastPurchaseDate != null)
                  _buildDetailRow('Last Purchase', _formatDate(widget.product.stock!.lastPurchaseDate!)),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],

        // Quick Actions - Only show for users with modify permissions
        if (_canModify == true) ...[
          Text('Quick Actions', style: AppTextStyles.h6.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          Row(
            children: [
              // Adjust Stock Button (switches to Stock tab)
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    _tabController?.animateTo(1);
                  },
                  icon: const Icon(Icons.inventory, color: Colors.white),
                  label: const Text(
                    'Adjust Stock',
                    style: TextStyle(color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // Edit Button
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    final editModel = BrandVariantEditModel.fromProduct(widget.product.product);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => EditBrandVariantScreen(variant: editModel),
                      ),
                    );
                  },
                  icon: const Icon(Icons.edit, color: Colors.white),
                  label: const Text(
                    'Edit',
                    style: TextStyle(color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Delete Button
          OutlinedButton.icon(
            onPressed: () => _showDeleteConfirmation(context),
            icon: Icon(Icons.delete, color: AppColors.error),
            label: Text(
              'Delete Product',
              style: TextStyle(color: AppColors.error),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppColors.error),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Stock Adjustment Tab - Compact inline stock adjustment
  Widget _buildStockAdjustmentTab(ScrollController scrollController) {
    final cs = Theme.of(context).colorScheme;
    final newStock = _isAddingStock
        ? widget.product.currentStock + _adjustmentQuantity
        : widget.product.currentStock - _adjustmentQuantity;

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        // Compact Add/Remove Toggle with Current Stock
        Row(
          children: [
            // Current Stock Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _stockColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _stockColor.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inventory_2, color: _stockColor, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    '${widget.product.currentStock}',
                    style: TextStyle(
                      color: _stockColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Compact Toggle
            Expanded(
              child: Container(
                height: 36,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          setState(() {
                            _isAddingStock = true;
                            _selectedReason = 'Purchase';
                          });
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: _isAddingStock ? AppColors.success : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.add,
                                color: _isAddingStock ? Colors.white : cs.onSurfaceVariant,
                                size: 18,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Add',
                                style: TextStyle(
                                  color: _isAddingStock ? Colors.white : cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          setState(() {
                            _isAddingStock = false;
                            _selectedReason = 'Sale';
                          });
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: !_isAddingStock ? AppColors.error : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.remove,
                                color: !_isAddingStock ? Colors.white : cs.onSurfaceVariant,
                                size: 18,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Remove',
                                style: TextStyle(
                                  color: !_isAddingStock ? Colors.white : cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Compact Quantity Controls
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Decrease Button
              _buildCompactQuantityButton(
                icon: Icons.remove,
                onTap: () {
                  if (_adjustmentQuantity > 1) {
                    HapticFeedback.lightImpact();
                    setState(() => _adjustmentQuantity--);
                  }
                },
                enabled: _adjustmentQuantity > 1,
              ),
              // Quantity Display
              GestureDetector(
                onTap: _showCustomQuantityDialog,
                child: Text(
                  '$_adjustmentQuantity',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: _isAddingStock ? AppColors.success : AppColors.error,
                  ),
                ),
              ),
              // Increase Button
              _buildCompactQuantityButton(
                icon: Icons.add,
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() => _adjustmentQuantity++);
                },
                enabled: true,
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // Quick Add Buttons - Like earlier design
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildQuickButton('+1', () => setState(() => _adjustmentQuantity += 1)),
            _buildQuickButton('+5', () => setState(() => _adjustmentQuantity += 5)),
            _buildQuickButton('+10', () => setState(() => _adjustmentQuantity += 10)),
            _buildQuickButton('+25', () => setState(() => _adjustmentQuantity += 25)),
            _buildQuickButton('+50', () => setState(() => _adjustmentQuantity += 50)),
            _buildQuickButton('+100', () => setState(() => _adjustmentQuantity += 100)),
            _buildQuickButton('Custom', _showCustomQuantityDialog, isCustom: true),
            _buildQuickButton('Clear', () => setState(() => _adjustmentQuantity = 1), isDestructive: true),
          ],
        ),

        const SizedBox(height: 12),

        // Compact Reason Selector - Horizontal Scroll
        SizedBox(
          height: 32,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: (_isAddingStock ? _addReasons : _removeReasons).map((reason) {
              final isSelected = _selectedReason == reason;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _selectedReason = reason);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? (_isAddingStock ? AppColors.success : AppColors.error)
                          : cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected
                            ? (_isAddingStock ? AppColors.success : AppColors.error)
                            : cs.outlineVariant,
                      ),
                    ),
                    child: Text(
                      reason,
                      style: TextStyle(
                        color: isSelected ? Colors.white : cs.onSurface,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 12),

        // Compact Preview Row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: cs.primary.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${widget.product.currentStock}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  _isAddingStock ? Icons.add : Icons.remove,
                  color: _isAddingStock ? AppColors.success : AppColors.error,
                  size: 18,
                ),
              ),
              Text(
                '$_adjustmentQuantity',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: _isAddingStock ? AppColors.success : AppColors.error,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('=', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$newStock',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Compact Submit Button
        SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton(
            onPressed: _isSubmitting ? null : _submitStockAdjustment,
            style: ElevatedButton.styleFrom(
              backgroundColor: _isAddingStock ? AppColors.success : AppColors.error,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              disabledBackgroundColor: cs.outlineVariant,
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(
                    _isAddingStock ? 'Add $_adjustmentQuantity' : 'Remove $_adjustmentQuantity',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
          ),
        ),

        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildCompactQuantityButton({
    required IconData icon,
    required VoidCallback onTap,
    required bool enabled,
  }) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: enabled ? cs.primary : cs.outlineVariant,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          color: enabled ? Colors.white : cs.onSurfaceVariant,
          size: 24,
        ),
      ),
    );
  }

  Widget _buildQuickButton(String label, VoidCallback onTap, {bool isDestructive = false, bool isCustom = false}) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isDestructive
              ? AppColors.error.withOpacity(0.1)
              : isCustom
                  ? AppColors.warning.withValues(alpha: 0.1)
                  : cs.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDestructive
                ? AppColors.error.withOpacity(0.3)
                : isCustom
                    ? AppColors.warning.withValues(alpha: 0.3)
                    : cs.primary.withOpacity(0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isDestructive
                ? AppColors.error
                : isCustom
                    ? AppColors.warning
                    : cs.primary,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
  void _showCustomQuantityDialog() {
    final controller = TextEditingController(); // Start empty

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enter Quantity'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Enter quantity',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final value = int.tryParse(controller.text);
              if (value != null && value > 0) {
                setState(() => _adjustmentQuantity = value);
              }
              Navigator.pop(dialogContext);
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitStockAdjustment() async {
    setState(() => _isSubmitting = true);

    try {
      // Get the API service and shop ID from the ShopSelectionProvider (NOT from product stock)
      // This ensures we always adjust stock for the currently selected shop
      final apiService = context.read<DioApiService>();
      final shopProvider = context.read<ShopSelectionProvider>();
      final shopId = shopProvider.selectedShopId ?? '';

      if (shopId.isEmpty) {
        throw Exception('No shop selected. Please select a shop first.');
      }

      final stockService = StockService(apiService);

      // Determine adjustment type: 'add', 'remove', or 'set'
      final adjustmentType = _isAddingStock ? 'add' : 'remove';

      // Call the stock adjustment API
      final response = await stockService.adjustStock(
        shopId: shopId,
        productId: widget.product.id,
        quantity: _adjustmentQuantity,
        adjustmentType: adjustmentType,
        reason: _selectedReason,
        notes: _notesController.text.isEmpty ? null : _notesController.text,
      );

      if (!response.success) {
        throw Exception(response.message ?? 'Failed to adjust stock');
      }

      // Update local stock cache only (no full refresh) - maintains scroll position
      // Use backend-returned value for consistency, fallback to calculated value
      if (mounted) {
        final productProvider = context.read<ProductProvider>();
        final responseData = response.data;
        int newStock;

        // Try to get actual stock from backend response
        if (responseData != null && responseData['new_quantity'] != null) {
          newStock = responseData['new_quantity'] as int;
          print('📦 [StockAdjust] Using backend-returned stock: $newStock');
        } else if (responseData != null && responseData['stock'] != null) {
          newStock = (responseData['stock'] is Map)
              ? (responseData['stock']['quantity'] as int? ?? 0)
              : (responseData['stock'] as int? ?? 0);
          print('📦 [StockAdjust] Using backend stock object: $newStock');
        } else {
          // Fallback to calculated value (API succeeded, so this should be correct)
          newStock = _isAddingStock
              ? widget.product.currentStock + _adjustmentQuantity
              : widget.product.currentStock - _adjustmentQuantity;
          print('📦 [StockAdjust] Using calculated stock: $newStock');
        }

        productProvider.updateLocalStock(
          productId: widget.product.id,
          newQuantity: newStock,
          shopId: shopId, // Pass shopId to create cache entry if missing
        );
      }

      if (mounted) {
        HapticFeedback.heavyImpact();
        Navigator.pop(context);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _isAddingStock
                        ? 'Added $_adjustmentQuantity units to ${widget.product.name}'
                        : 'Removed $_adjustmentQuantity units from ${widget.product.name}',
                  ),
                ),
              ],
            ),
            backgroundColor: _isAddingStock ? AppColors.success : AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Failed to adjust stock: ${e.toString()}'),
                ),
              ],
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: cs.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: AppTextStyles.h6.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    String? subtitle,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: AppTextStyles.caption.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: AppTextStyles.bodyLarge.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {int? maxLines}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: AppTextStyles.bodySmall.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
              textAlign: TextAlign.right,
              maxLines: maxLines,
              overflow: maxLines != null ? TextOverflow.ellipsis : null,
            ),
          ),
        ],
      ),
    );
  }

  String _calculateProfitPercentage(ProductWithStock product) {
    final totalCost = product.costPrice;
    if (totalCost == 0) return '0.0';
    final effectivePrice = product.sellingPrice > 0 ? product.sellingPrice : product.mrp;
    final profit = effectivePrice - totalCost;
    final percentage = (profit / totalCost) * 100;
    return percentage.toStringAsFixed(1);
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return '$weeks ${weeks == 1 ? "week" : "weeks"} ago';
    } else if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return '$months ${months == 1 ? "month" : "months"} ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  Future<void> _showDeleteConfirmation(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Product'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to delete "${widget.product.name}"?'),
            const SizedBox(height: 8),
            Text(
              'This action cannot be undone.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      Navigator.pop(context);

      final success = await context.read<ProductProvider>().deleteProduct(widget.product.id);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Product deleted successfully' : 'Failed to delete product'),
            backgroundColor: success ? AppColors.success : AppColors.error,
          ),
        );
      }
    }
  }
}
