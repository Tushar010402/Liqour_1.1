import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/product_constants.dart';
import '../../../core/services/api_service.dart';
import '../../../core/theme/ios_design_tokens.dart';
import '../../../core/utils/text_input_utils.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../models/product.dart';
import '../models/brand_metadata.dart';
import '../providers/product_provider.dart';

/// Edit Product Screen - Redesigned to match Custom Brand Form
/// Industrial-grade UI with modern iOS 16+ design
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
  final _dutyController = TextEditingController();
  final _costPriceController = TextEditingController();
  final _sellingPriceController = TextEditingController();
  final _barcodeController = TextEditingController();

  bool _isLoading = false;
  bool _isDisposed = false;
  bool _isCategoriesLoading = false;

  String? _selectedCategoryId;
  String? _selectedSubcategoryId;
  String? _selectedSize;
  String? _brandId;
  String? _brandName;

  List<CategoryDetail> _categories = [];
  List<SubcategoryDetail> _allSubcategories = [];

  @override
  void initState() {
    super.initState();
    _loadProductData();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadCategories();
    });
  }

  void _loadProductData() {
    final product = widget.product;
    _nameController.text = product.name;
    _descriptionController.text = product.description;
    _dutyController.text = product.alcoholContent.toString();
    _costPriceController.text = product.costPrice.toString();
    _sellingPriceController.text = product.sellingPrice.toString();
    _barcodeController.text = product.barcode;
    _selectedCategoryId = product.categoryId;
    _selectedSubcategoryId = product.subcategoryId;
    _selectedSize = product.size;
    _brandId = product.brandId;
    _brandName = product.brand?.name;

    print('🔨 [EditProduct] Loaded product: ${product.name}');
    print('🔨 [EditProduct] Category: $_selectedCategoryId, Subcategory: $_selectedSubcategoryId');
    print('🔨 [EditProduct] Size: $_selectedSize, Brand: $_brandName');
  }

  Future<void> _loadCategories() async {
    if (!mounted || _isDisposed) return;

    setState(() => _isCategoriesLoading = true);

    try {
      final apiService = context.read<ApiService>();
      print('🔨 [EditProduct] Loading SaaS brand metadata...');

      final response = await apiService.get<Map<String, dynamic>>(
        '/api/inventory/saas-brands/metadata',
        fromJson: (data) => data as Map<String, dynamic>? ?? {},
      );

      if (response.success && response.data != null && mounted && !_isDisposed) {
        final data = response.data!;
        final categoriesData = data['categories'] as List? ?? [];
        final subcategoriesData = data['subcategories'] as List? ?? [];

        setState(() {
          _categories = categoriesData
              .map((cat) => CategoryDetail.fromJson(cat as Map<String, dynamic>))
              .toList();
          _allSubcategories = subcategoriesData
              .map((sub) => SubcategoryDetail.fromJson(sub as Map<String, dynamic>))
              .toList();
        });

        print('🔨 [EditProduct] ✅ Loaded ${_categories.length} categories, ${_allSubcategories.length} subcategories');
      }
    } catch (e) {
      print('🔨 [EditProduct] ❌ Failed to load categories: $e');
      if (mounted) {
        _showError('Failed to load categories: $e');
      }
    } finally {
      if (mounted && !_isDisposed) {
        setState(() => _isCategoriesLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _nameController.dispose();
    _descriptionController.dispose();
    _dutyController.dispose();
    _costPriceController.dispose();
    _sellingPriceController.dispose();
    _barcodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Check if route is popping
    final route = ModalRoute.of(context);
    final isRoutePoppingBack = route?.animation?.status == AnimationStatus.reverse;

    if (_isDisposed || !mounted || isRoutePoppingBack) {
      return const Scaffold(body: SizedBox.shrink());
    }

    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: CustomAppBar(
        title: 'Edit Product',
        actions: [
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(right: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _saveProduct,
              child: Text(
                'Save',
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                  color: cs.primary,
                ),
              ),
            ),
        ],
      ),
      body: _isCategoriesLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildForm(),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: EdgeInsets.all(iOSDesignTokens.space16),
        children: [
          _buildSectionCard(
            title: 'Product Information',
            children: [
              TextInputUtils.buildTextFormFieldNoPredictive(
                controller: _nameController,
                labelText: 'Product Name',
                hintText: 'Enter product name',
                decoration: _getInputDecoration('Product Name'),
                validator: (value) => value?.isEmpty == true ? 'Required' : null,
                enabled: !_isLoading,
              ),
              SizedBox(height: iOSDesignTokens.space12),
              TextInputUtils.buildTextFormFieldNoPredictive(
                controller: _descriptionController,
                labelText: 'Description (Optional)',
                hintText: 'Enter product description',
                decoration: _getInputDecoration('Description'),
                maxLines: 2,
                enabled: !_isLoading,
              ),
            ],
          ),
          SizedBox(height: iOSDesignTokens.space16),
          _buildSectionCard(
            title: 'Category & Details',
            children: [
              DropdownButtonFormField<String>(
                initialValue: _selectedCategoryId,
                decoration: _getInputDecoration('Select Category'),
                isExpanded: true,
                style: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurface),
                items: _categories.map((category) {
                  return DropdownMenuItem(
                    value: category.id,
                    child: Text(category.name),
                  );
                }).toList(),
                onChanged: _isLoading
                    ? null
                    : (value) {
                        if (!_isDisposed && mounted) {
                          setState(() {
                            _selectedCategoryId = value;
                            _selectedSubcategoryId = null;
                            _selectedSize = null;
                          });
                        }
                      },
                validator: (value) => value == null ? 'Please select a category' : null,
              ),
              SizedBox(height: iOSDesignTokens.space12),
              DropdownButtonFormField<String>(
                initialValue: _getValidSubcategoryValue(),
                decoration: _getInputDecoration('Select Subcategory (Optional)'),
                isExpanded: true,
                style: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurface),
                items: _buildSubcategoryItems(),
                onChanged: _isLoading
                    ? null
                    : (value) {
                        if (!_isDisposed && mounted) {
                          setState(() => _selectedSubcategoryId = value);
                        }
                      },
              ),
              SizedBox(height: iOSDesignTokens.space12),
              _buildSizeDropdown(),
            ],
          ),
          SizedBox(height: iOSDesignTokens.space16),
          _buildSectionCard(
            title: 'Pricing & Content',
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextInputUtils.buildTextFormFieldNoPredictive(
                      controller: _dutyController,
                      labelText: 'Alcohol %',
                      hintText: '12.5',
                      decoration: _getCompactInputDecoration('Alcohol %'),
                      inputFormatters: TextInputUtils.decimalInputFormatters,
                      validator: (value) => value?.isEmpty == true ? 'Required' : null,
                      enabled: !_isLoading,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextInputUtils.buildTextFormFieldNoPredictive(
                      controller: _barcodeController,
                      labelText: 'Barcode (Optional)',
                      hintText: 'Barcode',
                      decoration: _getCompactInputDecoration('Barcode'),
                      enabled: !_isLoading,
                    ),
                  ),
                ],
              ),
              SizedBox(height: iOSDesignTokens.space12),
              Row(
                children: [
                  Expanded(
                    child: TextInputUtils.buildTextFormFieldNoPredictive(
                      controller: _costPriceController,
                      labelText: 'Cost ₹',
                      hintText: '0.00',
                      decoration: _getCompactInputDecoration('Cost Price'),
                      inputFormatters: TextInputUtils.decimalInputFormatters,
                      validator: (value) => value?.isEmpty == true ? 'Required' : null,
                      enabled: !_isLoading,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextInputUtils.buildTextFormFieldNoPredictive(
                      controller: _sellingPriceController,
                      labelText: 'Sell ₹',
                      hintText: '0.00',
                      decoration: _getCompactInputDecoration('Sell Price'),
                      inputFormatters: TextInputUtils.decimalInputFormatters,
                      validator: (value) => value?.isEmpty == true ? 'Required' : null,
                      enabled: !_isLoading,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 32),
          _buildActionButtons(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required List<Widget> children,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 3,
              height: 14,
              decoration: BoxDecoration(
                color: cs.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(width: iOSDesignTokens.space8),
            Text(title,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                )),
          ],
        ),
        SizedBox(height: iOSDesignTokens.space8),
        Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
            border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
          ),
          padding: EdgeInsets.all(iOSDesignTokens.space16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }

  /// Get valid subcategory value that exists in dropdown items
  String? _getValidSubcategoryValue() {
    if (_selectedSubcategoryId == null || _selectedSubcategoryId!.isEmpty) {
      return null;
    }

    // Check if selected subcategory exists in the items list
    final items = _buildSubcategoryItems();
    final exists = items.any((item) => item.value == _selectedSubcategoryId);

    if (!exists) {
      print('🔨 [EditProduct] ⚠️ Selected subcategory $_selectedSubcategoryId not found in items list');
      return null;
    }

    return _selectedSubcategoryId;
  }

  /// Build subcategory dropdown items with proper filtering
  List<DropdownMenuItem<String>> _buildSubcategoryItems() {
    if (_selectedCategoryId == null) {
      return [];
    }

    // Get all subcategories that match the selected category
    final filteredSubcategories = _allSubcategories.where((sub) {
      // Exact match with selected category
      if (sub.categoryId == _selectedCategoryId) return true;

      // Global subcategories (null or empty UUID) belong to ALL categories
      if (sub.categoryId.isEmpty ||
          sub.categoryId == '00000000-0000-0000-0000-000000000000') {
        return true;
      }

      // IMPORTANT: Also include the currently selected subcategory
      // This ensures it shows even if category changed
      if (_selectedSubcategoryId != null && sub.id == _selectedSubcategoryId) {
        return true;
      }

      return false;
    }).toList();

    print('🔨 [EditProduct] Building subcategory items: ${filteredSubcategories.length} items');
    print('🔨 [EditProduct] Selected subcategory ID: $_selectedSubcategoryId');

    return filteredSubcategories.map((subcategory) {
      return DropdownMenuItem(
        value: subcategory.id,
        child: Text(subcategory.name),
      );
    }).toList();
  }

  Widget _buildSizeDropdown() {
    if (_isDisposed) return const SizedBox.shrink();

    String categoryName = '';
    if (_selectedCategoryId != null) {
      final category = _categories
          .where((cat) => cat.id == _selectedCategoryId)
          .firstOrNull;
      categoryName = category?.name ?? '';
    }

    List<String> sizeOptions = categoryName.isNotEmpty
        ? ProductConstants.getSizesForCategory(categoryName)
        : ProductConstants.spiritSizes;

    // Check if selected size is valid for current category
    if (_selectedSize != null && !sizeOptions.contains(_selectedSize)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isDisposed) {
          setState(() => _selectedSize = null);
        }
      });
    }

    return DropdownButtonFormField<String>(
      initialValue: _selectedSize,
      decoration: _getInputDecoration('Select Size'),
      isExpanded: true,
      style: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurface),
      items: sizeOptions.map((size) {
        return DropdownMenuItem(
          value: size,
          child: Text(size),
        );
      }).toList(),
      onChanged: _isLoading
          ? null
          : (value) {
              if (!_isDisposed && mounted) {
                setState(() => _selectedSize = value);
              }
            },
      validator: (value) => value == null ? 'Please select a size' : null,
    );
  }

  Widget _buildActionButtons() {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              side: BorderSide(color: cs.outlineVariant),
            ),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _saveProduct,
            style: ElevatedButton.styleFrom(
              backgroundColor: cs.primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
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
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  InputDecoration _getInputDecoration(String label) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        fontSize: 14,
        color: cs.onSurface,
        fontWeight: FontWeight.w500,
      ),
      hintStyle: TextStyle(
        fontSize: 15,
        color: cs.onSurfaceVariant,
      ),
      filled: true,
      fillColor: cs.surfaceContainerHighest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(iOSDesignTokens.radiusSmall),
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(iOSDesignTokens.radiusSmall),
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(iOSDesignTokens.radiusSmall),
        borderSide: BorderSide(color: cs.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(iOSDesignTokens.radiusSmall),
        borderSide: BorderSide(color: cs.error, width: 1),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(iOSDesignTokens.radiusSmall),
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
    );
  }

  InputDecoration _getCompactInputDecoration(String label) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        fontSize: 13,
        color: cs.onSurface,
        fontWeight: FontWeight.w500,
      ),
      hintStyle: TextStyle(
        fontSize: 14,
        color: cs.onSurfaceVariant,
      ),
      filled: true,
      fillColor: cs.surfaceContainerHighest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(iOSDesignTokens.space6),
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(iOSDesignTokens.space6),
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(iOSDesignTokens.space6),
        borderSide: BorderSide(color: cs.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(iOSDesignTokens.space6),
        borderSide: BorderSide(color: cs.error, width: 1),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(iOSDesignTokens.space6),
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
    );
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedCategoryId == null) {
      _showError('Please select a category');
      return;
    }

    if (_selectedSize == null) {
      _showError('Please select a size');
      return;
    }

    if (!_isDisposed && mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final productProvider = context.read<ProductProvider>();

      print('🔨 [EditProduct] Updating product: ${widget.product.id}');
      print('🔨 [EditProduct] Name: ${_nameController.text.trim()}');
      print('🔨 [EditProduct] Size: $_selectedSize');
      print('🔨 [EditProduct] Category: $_selectedCategoryId');

      final success = await productProvider.updateProduct(
        id: widget.product.id,
        name: _nameController.text.trim(),
        categoryId: _selectedCategoryId!,
        brandId: _brandId ?? widget.product.brandId,
        size: _selectedSize!,
        alcoholContent: double.tryParse(_dutyController.text) ?? 0.0,
        description: _descriptionController.text.trim(),
        barcode: _barcodeController.text.trim(),
        sku: widget.product.sku,
        costPrice: double.tryParse(_costPriceController.text) ?? 0.0,
        sellingPrice: double.tryParse(_sellingPriceController.text) ?? 0.0,
      );

      if (success) {
        print('🔨 [EditProduct] ✅ Product updated successfully');
      }

      if (mounted && !_isDisposed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Product updated successfully' : 'Failed to update product'),
            backgroundColor: success ? AppColors.success : AppColors.error,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
        if (success) {
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      print('🔨 [EditProduct] ❌ Failed to update product: $e');
      if (mounted) {
        _showError('Failed to update product: $e');
      }
    } finally {
      if (mounted && !_isDisposed) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
