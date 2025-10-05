import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../providers/product_provider.dart';
import '../models/brand.dart';
import '../../../core/utils/logger.dart';

/// Add Product Screen - Create new product with validation
class AddProductScreen extends StatefulWidget {
  const AddProductScreen({super.key});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
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
    Logger.debug('\n📱 AddProductScreen.initState()');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Logger.debug('   🔄 Loading categories and brands...');
      final provider = context.read<ProductProvider>();
      provider.loadCategories();
      provider.loadBrands();
    });
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
    Logger.debug('\n📱 AddProductScreen._saveProduct() - START');

    if (!_formKey.currentState!.validate()) {
      Logger.debug('   ❌ Form validation failed');
      return;
    }

    if (_selectedCategoryId == null) {
      Logger.debug('   ❌ No category selected');
      _showError('Please select a category');
      return;
    }

    if (_selectedBrandId == null) {
      Logger.debug('   ❌ No brand selected');
      _showError('Please select a brand');
      return;
    }

    Logger.debug('   ✅ Validation passed');
    Logger.debug('   📝 Product details:');
    Logger.debug('      - name: ${_nameController.text.trim()}');
    Logger.debug('      - categoryId: $_selectedCategoryId');
    Logger.debug('      - brandId: $_selectedBrandId');
    Logger.debug('      - size: ${_sizeController.text.trim()}');
    Logger.debug('      - barcode: ${_barcodeController.text.trim()}');
    Logger.debug('      - sku: ${_skuController.text.trim()}');

    setState(() {
      _isLoading = true;
    });

    try {
      final provider = context.read<ProductProvider>();

      Logger.debug('   🚀 Calling createProduct()...');
      final success = await provider.createProduct(
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

      Logger.debug('   📦 createProduct() returned: $success');

      if (success && mounted) {
        Logger.debug('   ✅ Product added successfully - showing success message');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Product added successfully'),
            backgroundColor: AppColors.success,
          ),
        );
        Logger.debug('   🔙 Navigating back with result=true');
        Navigator.pop(context, true);
      } else if (mounted) {
        final errorMsg = provider.errorMessage ?? 'Failed to add product';
        Logger.debug('   ❌ Failed to add product: $errorMsg');
        _showError(errorMsg);
      }
    } catch (e, stackTrace) {
      Logger.debug('   ❌ EXCEPTION in _saveProduct:');
      Logger.debug('      Error: $e');
      Logger.debug('      StackTrace: $stackTrace');
      _showError('Invalid input: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      Logger.debug('📱 AddProductScreen._saveProduct() - END\n');
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
        title: 'Add New Product',
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
                              'Add Product',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
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
