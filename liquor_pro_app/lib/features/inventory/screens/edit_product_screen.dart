import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../providers/product_provider.dart';
import '../models/product.dart';
import '../models/brand.dart';
import '../../../core/utils/logger.dart';

/// Edit Product Screen - Update existing product with validation
class EditProductScreen extends StatefulWidget {
  final Product product;

  const EditProductScreen({
    super.key,
    required this.product,
  });

  @override
  State<EditProductScreen> createState() => _EditProductScreenState();
}

class _EditProductScreenState extends State<EditProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _sizeController = TextEditingController();
  final _alcoholContentController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _skuController = TextEditingController();
  final _costPriceController = TextEditingController();
  final _sellingPriceController = TextEditingController();
  final _mrpController = TextEditingController();

  String? _selectedCategoryId;
  String? _selectedBrandId;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    Logger.debug('\n📱 EditProductScreen.initState()');
    Logger.debug('   📦 Editing product: ${widget.product.name} (ID: ${widget.product.id})');
    _loadProductData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Logger.debug('   🔄 Loading categories and brands...');
      final provider = context.read<ProductProvider>();
      provider.loadCategories();
      provider.loadBrands();
    });
  }

  void _loadProductData() {
    Logger.debug('   📝 Loading product data into form...');
    final product = widget.product;
    _nameController.text = product.name;
    _descriptionController.text = product.description;
    _sizeController.text = product.size;
    _alcoholContentController.text = product.alcoholContent.toString();
    _barcodeController.text = product.barcode;
    _skuController.text = product.sku;
    _costPriceController.text = product.costPrice.toString();
    _sellingPriceController.text = product.sellingPrice.toString();
    _mrpController.text = product.mrp.toString();
    _selectedCategoryId = product.categoryId;
    _selectedBrandId = product.brandId;
    Logger.debug('   ✅ Product data loaded');
    Logger.debug('      - categoryId: $_selectedCategoryId');
    Logger.debug('      - brandId: $_selectedBrandId');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _sizeController.dispose();
    _alcoholContentController.dispose();
    _barcodeController.dispose();
    _skuController.dispose();
    _costPriceController.dispose();
    _sellingPriceController.dispose();
    _mrpController.dispose();
    super.dispose();
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedCategoryId == null) {
      _showError('Please select a category');
      return;
    }

    if (_selectedBrandId == null) {
      _showError('Please select a brand');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final provider = context.read<ProductProvider>();

      final success = await provider.updateProduct(
        id: widget.product.id,
        name: _nameController.text.trim(),
        categoryId: _selectedCategoryId!,
        brandId: _selectedBrandId!,
        size: _sizeController.text.trim(),
        alcoholContent: double.parse(_alcoholContentController.text),
        description: _descriptionController.text.trim(),
        barcode: _barcodeController.text.trim(),
        sku: _skuController.text.trim(),
        costPrice: double.parse(_costPriceController.text),
        sellingPrice: double.parse(_sellingPriceController.text),
        mrp: double.parse(_mrpController.text),
      );

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Product updated successfully'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context, true);
      } else if (mounted) {
        _showError(provider.errorMessage ?? 'Failed to update product');
      }
    } catch (e) {
      _showError('Invalid input: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _deleteProduct() async {
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
            const Text(
              'This action cannot be undone.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
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

    if (confirmed == true && mounted) {
      setState(() => _isLoading = true);

      final success = await context.read<ProductProvider>().deleteProduct(widget.product.id);

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Product deleted successfully'),
              backgroundColor: AppColors.success,
            ),
          );
          Navigator.pop(context, true);
        } else {
          setState(() => _isLoading = false);
          _showError('Failed to delete product');
        }
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(
        title: 'Edit Product',
      ),
      body: Consumer<ProductProvider>(
        builder: (context, provider, _) {
          return Stack(
            children: [
              Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Product Information Section
                    _buildSectionTitle('Product Information'),
                    const SizedBox(height: 16),

                    _buildTextField(
                      controller: _nameController,
                      label: 'Product Name',
                      hint: 'e.g., Johnnie Walker Black Label 750ml',
                      icon: Icons.liquor,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter product name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    _buildTextField(
                      controller: _descriptionController,
                      label: 'Description',
                      hint: 'Product description',
                      icon: Icons.description,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),

                    // Category Dropdown
                    _buildDropdown(
                      label: 'Category',
                      value: _selectedCategoryId,
                      hint: 'Select category',
                      icon: Icons.category,
                      items: provider.categories.map((cat) {
                        return DropdownMenuItem(
                          value: cat.id,
                          child: Text(cat.name),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedCategoryId = value;
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // Brand Dropdown
                    _buildDropdown(
                      label: 'Brand',
                      value: _selectedBrandId,
                      hint: 'Select brand',
                      icon: Icons.branding_watermark,
                      items: provider.brands.map((brand) {
                        return DropdownMenuItem(
                          value: brand.id,
                          child: Text(brand.name),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedBrandId = value;
                        });
                      },
                    ),
                    const SizedBox(height: 24),

                    // Product Details Section
                    _buildSectionTitle('Product Details'),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            controller: _sizeController,
                            label: 'Size',
                            hint: 'e.g., 750ml, 1L',
                            icon: Icons.straighten,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Required';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildTextField(
                            controller: _alcoholContentController,
                            label: 'Alcohol %',
                            hint: 'e.g., 40',
                            icon: Icons.local_bar,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Required';
                              }
                              final number = double.tryParse(value);
                              if (number == null || number < 0 || number > 100) {
                                return 'Invalid %';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            controller: _barcodeController,
                            label: 'Barcode',
                            hint: 'Product barcode',
                            icon: Icons.qr_code,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Required';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildTextField(
                            controller: _skuController,
                            label: 'SKU',
                            hint: 'Stock keeping unit',
                            icon: Icons.inventory,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Required';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Pricing Section
                    _buildSectionTitle('Pricing'),
                    const SizedBox(height: 16),

                    _buildTextField(
                      controller: _costPriceController,
                      label: 'Cost Price',
                      hint: 'Purchase/cost price',
                      icon: Icons.shopping_cart,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      prefixText: '₹ ',
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Required';
                        }
                        final number = double.tryParse(value);
                        if (number == null || number <= 0) {
                          return 'Invalid price';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    _buildTextField(
                      controller: _sellingPriceController,
                      label: 'Selling Price',
                      hint: 'Your selling price',
                      icon: Icons.sell,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      prefixText: '₹ ',
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Required';
                        }
                        final number = double.tryParse(value);
                        if (number == null || number <= 0) {
                          return 'Invalid price';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    _buildTextField(
                      controller: _mrpController,
                      label: 'MRP',
                      hint: 'Maximum retail price',
                      icon: Icons.attach_money,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      prefixText: '₹ ',
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Required';
                        }
                        final number = double.tryParse(value);
                        if (number == null || number <= 0) {
                          return 'Invalid price';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 32),

                    // Save Button
                    ElevatedButton(
                      onPressed: _isLoading ? null : _saveProduct,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'Save Changes',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                    const SizedBox(height: 16),

                    // Delete Button
                    OutlinedButton(
                      onPressed: _isLoading ? null : _deleteProduct,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.error),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.delete_outline),
                          SizedBox(width: 8),
                          Text(
                            'Delete Product',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),

              // Loading overlay
              if (provider.isLoading || provider.isCategoriesLoading || provider.isBrandsLoading)
                Container(
                  color: Colors.black26,
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: AppTextStyles.h5.copyWith(
        fontWeight: FontWeight.bold,
        color: AppColors.primary,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? prefixText,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: AppColors.primary),
        prefixText: prefixText,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        filled: true,
        fillColor: Colors.white,
      ),
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required String hint,
    required IconData icon,
    required List<DropdownMenuItem<String>> items,
    required void Function(String?) onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: AppColors.primary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        filled: true,
        fillColor: Colors.white,
      ),
      items: items,
      onChanged: onChanged,
      validator: (value) {
        if (value == null) {
          return 'Please select $label';
        }
        return null;
      },
    );
  }
}
