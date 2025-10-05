import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../../../shared/widgets/custom_button.dart';
import '../models/product_model.dart';

/// Product Edit Screen
class ProductEditScreen extends StatefulWidget {
  final Product? product; // null for add, non-null for edit

  const ProductEditScreen({
    super.key,
    this.product,
  });

  @override
  State<ProductEditScreen> createState() => _ProductEditScreenState();
}

class _ProductEditScreenState extends State<ProductEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _skuController = TextEditingController();
  final _costPriceController = TextEditingController();
  final _sellingPriceController = TextEditingController();
  final _mrpController = TextEditingController();
  final _stockQuantityController = TextEditingController();
  final _minStockController = TextEditingController();
  final _alcoholPercentageController = TextEditingController();
  final _volumeController = TextEditingController();

  String _selectedCategory = 'Select Category';
  String _selectedBrand = 'Select Brand';
  String _selectedUnit = 'ML';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.product != null) {
      _loadProductData();
    }
  }

  void _loadProductData() {
    final product = widget.product!;
    _nameController.text = product.name;
    _descriptionController.text = product.description ?? '';
    _barcodeController.text = product.barcode ?? '';
    _skuController.text = product.sku ?? '';
    _costPriceController.text = product.costPrice.toString();
    _sellingPriceController.text = product.sellingPrice.toString();
    _mrpController.text = product.mrp?.toString() ?? '';
    _stockQuantityController.text = product.stockQuantity?.toString() ?? '';
    _minStockController.text = product.minStockLevel?.toString() ?? '';
    _alcoholPercentageController.text = product.alcoholPercentage?.toString() ?? '';
    _volumeController.text = product.volume?.toString() ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _barcodeController.dispose();
    _skuController.dispose();
    _costPriceController.dispose();
    _sellingPriceController.dispose();
    _mrpController.dispose();
    _stockQuantityController.dispose();
    _minStockController.dispose();
    _alcoholPercentageController.dispose();
    _volumeController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    // TODO: Save product API call
    // POST /api/inventory/products (for add)
    // PUT /api/inventory/products/:id (for edit)

    await Future.delayed(const Duration(seconds: 1));

    if (mounted) {
      Navigator.pop(context, true); // Return true to indicate success
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.product == null
                ? 'Product added successfully'
                : 'Product updated successfully',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: widget.product == null ? 'Add Product' : 'Edit Product',
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Basic Information
            Text(
              'Basic Information',
              style: AppTextStyles.h5,
            ),
            const SizedBox(height: 12),

            CustomTextField(
              label: 'Product Name',
              controller: _nameController,
              prefixIcon: const Icon(Icons.local_bar),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter product name';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            CustomTextField(
              label: 'Description (Optional)',
              controller: _descriptionController,
              maxLines: 3,
              prefixIcon: const Icon(Icons.description),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: CustomTextField(
                    label: 'Barcode',
                    controller: _barcodeController,
                    prefixIcon: const Icon(Icons.qr_code),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: CustomTextField(
                    label: 'SKU',
                    controller: _skuController,
                    prefixIcon: const Icon(Icons.tag),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Category & Brand
            Text(
              'Category & Brand',
              style: AppTextStyles.h5,
            ),
            const SizedBox(height: 12),

            DropdownButtonFormField<String>(
              value: _selectedCategory,
              decoration: const InputDecoration(
                labelText: 'Category',
                prefixIcon: Icon(Icons.category),
                border: OutlineInputBorder(),
              ),
              items: ['Select Category', 'Whisky', 'Vodka', 'Rum', 'Beer', 'Wine']
                  .map((category) => DropdownMenuItem(
                        value: category,
                        child: Text(category),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedCategory = value);
                }
              },
            ),
            const SizedBox(height: 16),

            DropdownButtonFormField<String>(
              value: _selectedBrand,
              decoration: const InputDecoration(
                labelText: 'Brand',
                prefixIcon: Icon(Icons.business),
                border: OutlineInputBorder(),
              ),
              items: ['Select Brand', 'Brand 1', 'Brand 2', 'Brand 3']
                  .map((brand) => DropdownMenuItem(
                        value: brand,
                        child: Text(brand),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedBrand = value);
                }
              },
            ),
            const SizedBox(height: 24),

            // Pricing
            Text(
              'Pricing',
              style: AppTextStyles.h5,
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: CustomTextField(
                    label: 'Cost Price',
                    controller: _costPriceController,
                    keyboardType: TextInputType.number,
                    prefixIcon: const Icon(Icons.currency_rupee),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Required';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: CustomTextField(
                    label: 'Selling Price',
                    controller: _sellingPriceController,
                    keyboardType: TextInputType.number,
                    prefixIcon: const Icon(Icons.currency_rupee),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Required';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            CustomTextField(
              label: 'MRP (Optional)',
              controller: _mrpController,
              keyboardType: TextInputType.number,
              prefixIcon: const Icon(Icons.currency_rupee),
            ),
            const SizedBox(height: 24),

            // Inventory
            Text(
              'Inventory',
              style: AppTextStyles.h5,
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: CustomTextField(
                    label: 'Stock Quantity',
                    controller: _stockQuantityController,
                    keyboardType: TextInputType.number,
                    prefixIcon: const Icon(Icons.inventory),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: CustomTextField(
                    label: 'Min Stock Level',
                    controller: _minStockController,
                    keyboardType: TextInputType.number,
                    prefixIcon: const Icon(Icons.warning),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Product Details
            Text(
              'Product Details',
              style: AppTextStyles.h5,
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: CustomTextField(
                    label: 'Alcohol %',
                    controller: _alcoholPercentageController,
                    keyboardType: TextInputType.number,
                    prefixIcon: const Icon(Icons.percent),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: CustomTextField(
                    label: 'Volume',
                    controller: _volumeController,
                    keyboardType: TextInputType.number,
                    prefixIcon: const Icon(Icons.local_drink),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            DropdownButtonFormField<String>(
              value: _selectedUnit,
              decoration: const InputDecoration(
                labelText: 'Volume Unit',
                prefixIcon: Icon(Icons.straighten),
                border: OutlineInputBorder(),
              ),
              items: ['ML', 'L', 'OZ']
                  .map((unit) => DropdownMenuItem(
                        value: unit,
                        child: Text(unit),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedUnit = value);
                }
              },
            ),
            const SizedBox(height: 32),

            // Save Button
            CustomButton(
              text: widget.product == null ? 'Add Product' : 'Save Changes',
              onPressed: _isLoading ? null : _handleSave,
              icon: Icons.check,
              isLoading: _isLoading,
            ),

            if (widget.product != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {
                  // TODO: Delete product with confirmation
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete Product'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
