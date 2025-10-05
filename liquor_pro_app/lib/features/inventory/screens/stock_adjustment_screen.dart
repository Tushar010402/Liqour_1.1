import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../../../shared/widgets/custom_button.dart';
import '../models/product_model.dart';

/// Stock Adjustment Screen - Add or Remove Stock
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
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _notesController = TextEditingController();

  String _adjustmentType = 'add'; // 'add' or 'remove'
  String? _selectedShopId;
  String? _selectedProductId;
  String _reason = 'Purchase';

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
      _selectedProductId = widget.product!.id;
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedShopId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a shop'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (_selectedProductId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a product'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    // TODO: Call API to adjust stock
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Stock Adjustment'),
        content: Text(
          '${_adjustmentType == 'add' ? 'Add' : 'Remove'} ${_quantityController.text} units?\n'
          'Reason: $_reason',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
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
    final reasons = _adjustmentType == 'add' ? _addReasons : _removeReasons;

    return Scaffold(
      appBar: const CustomAppBar(
        title: 'Adjust Stock',
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Adjustment Type Selector
            Text(
              'Adjustment Type',
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'add',
                  label: Text('Add Stock'),
                  icon: Icon(Icons.add_circle_outline),
                ),
                ButtonSegment(
                  value: 'remove',
                  label: Text('Remove Stock'),
                  icon: Icon(Icons.remove_circle_outline),
                ),
              ],
              selected: {_adjustmentType},
              onSelectionChanged: (Set<String> selection) {
                setState(() {
                  _adjustmentType = selection.first;
                  _reason = _adjustmentType == 'add' ? 'Purchase' : 'Sale';
                });
              },
            ),
            const SizedBox(height: 24),

            // Shop Selector
            DropdownButtonFormField<String>(
              value: _selectedShopId,
              decoration: InputDecoration(
                labelText: 'Select Shop',
                prefixIcon: const Icon(Icons.store),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
              ),
              items: const [
                // TODO: Load from API
                DropdownMenuItem(value: 'shop1', child: Text('Downtown Store')),
                DropdownMenuItem(value: 'shop2', child: Text('Uptown Store')),
              ],
              onChanged: (value) {
                setState(() => _selectedShopId = value);
              },
              validator: (value) => value == null ? 'Please select a shop' : null,
            ),
            const SizedBox(height: 16),

            // Product Selector
            if (widget.product == null)
              DropdownButtonFormField<String>(
                value: _selectedProductId,
                decoration: InputDecoration(
                  labelText: 'Select Product',
                  prefixIcon: const Icon(Icons.inventory_2),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                ),
                items: const [
                  // TODO: Load from API
                  DropdownMenuItem(value: 'prod1', child: Text('Product 1')),
                  DropdownMenuItem(value: 'prod2', child: Text('Product 2')),
                ],
                onChanged: (value) {
                  setState(() => _selectedProductId = value);
                },
                validator: (value) => value == null ? 'Please select a product' : null,
              )
            else
              Card(
                child: ListTile(
                  leading: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.liquor, color: AppColors.primary),
                  ),
                  title: Text(widget.product!.name),
                  subtitle: Text('Current Stock: ${widget.product!.stockQuantity ?? 0}'),
                ),
              ),
            const SizedBox(height: 16),

            // Quantity
            CustomTextField(
              label: 'Quantity',
              hint: 'Enter quantity',
              controller: _quantityController,
              keyboardType: TextInputType.number,
              prefixIcon: const Icon(Icons.numbers),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter quantity';
                }
                if (int.tryParse(value) == null || int.parse(value) <= 0) {
                  return 'Please enter valid quantity';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Reason
            DropdownButtonFormField<String>(
              value: _reason,
              decoration: InputDecoration(
                labelText: 'Reason',
                prefixIcon: const Icon(Icons.info_outline),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
              ),
              items: reasons.map((reason) {
                return DropdownMenuItem(
                  value: reason,
                  child: Text(reason),
                );
              }).toList(),
              onChanged: (value) {
                setState(() => _reason = value!);
              },
            ),
            const SizedBox(height: 16),

            // Notes
            CustomTextField(
              label: 'Notes (Optional)',
              hint: 'Add any additional notes',
              controller: _notesController,
              maxLines: 3,
              prefixIcon: const Icon(Icons.note_outlined),
            ),
            const SizedBox(height: 24),

            // Summary Card
            Card(
              color: _adjustmentType == 'add'
                  ? AppColors.success.withOpacity(0.1)
                  : AppColors.error.withOpacity(0.1),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _adjustmentType == 'add' ? Icons.arrow_upward : Icons.arrow_downward,
                          color: _adjustmentType == 'add' ? AppColors.success : AppColors.error,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Stock ${_adjustmentType == 'add' ? 'Addition' : 'Removal'}',
                          style: AppTextStyles.h5.copyWith(
                            color: _adjustmentType == 'add' ? AppColors.success : AppColors.error,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'This will ${_adjustmentType == 'add' ? 'increase' : 'decrease'} the stock quantity.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Submit Button
            CustomButton(
              text: 'Adjust Stock',
              onPressed: _handleSubmit,
              icon: Icons.check,
            ),
          ],
        ),
      ),
    );
  }
}
