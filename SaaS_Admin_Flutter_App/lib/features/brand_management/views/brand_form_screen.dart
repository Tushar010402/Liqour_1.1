import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/brand_model.dart';
import '../../../core/models/category_model.dart';
import '../../../core/utils/text_input_utils.dart';
import '../controllers/brand_provider.dart';
import '../../category_management/controllers/category_provider.dart';

class BrandVariantForm {
  String size;
  String duty;
  double buyingPrice;
  double sellingPrice;
  double mrp;
  late TextEditingController sizeController;
  late TextEditingController dutyController;
  late TextEditingController buyingPriceController;
  late TextEditingController sellingPriceController;
  late TextEditingController mrpController;

  BrandVariantForm({
    this.size = '',
    this.duty = '',
    this.buyingPrice = 0.0,
    this.sellingPrice = 0.0,
    this.mrp = 0.0,
  }) {
    sizeController = TextEditingController(text: size);
    dutyController = TextEditingController(text: duty);
    buyingPriceController = TextEditingController(text: buyingPrice.toString());
    sellingPriceController = TextEditingController(text: sellingPrice.toString());
    mrpController = TextEditingController(text: mrp.toString());
  }

  void dispose() {
    sizeController.dispose();
    dutyController.dispose();
    buyingPriceController.dispose();
    sellingPriceController.dispose();
    mrpController.dispose();
  }
}

class BrandFormScreen extends StatefulWidget {
  final Brand? brand;

  const BrandFormScreen({super.key, this.brand});

  @override
  State<BrandFormScreen> createState() => _BrandFormScreenState();
}

class _BrandFormScreenState extends State<BrandFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  bool _isActive = true;
  bool _isLoading = false;
  String? _selectedCategoryId;
  String? _selectedSubcategoryId;
  List<BrandVariantForm> _variants = [BrandVariantForm()];

  bool get _isEditing => widget.brand != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<CategoryProvider>().loadCategories();
      if (_isEditing) {
        _populateFields();
      }
    });
  }

  void _populateFields() {
    if (widget.brand != null) {
      final brand = widget.brand!;
      _nameController.text = brand.name;
      _descriptionController.text = brand.description;
      _isActive = brand.isActive;

      if (brand.brandVariants != null && brand.brandVariants!.isNotEmpty) {
        for (var variant in _variants) {
          variant.dispose();
        }
        _variants.clear();

        for (var brandVariant in brand.brandVariants!) {
          final variantForm = BrandVariantForm(
            size: brandVariant.size,
            duty: brandVariant.alcoholContent.toString(),
            buyingPrice: brandVariant.buyingPrice,
            sellingPrice: brandVariant.sellingPrice,
            mrp: brandVariant.mrp,
          );
          _variants.add(variantForm);
        }

        final firstVariant = brand.brandVariants!.first;
        _selectedCategoryId = firstVariant.categoryId;
        _selectedSubcategoryId = firstVariant.subcategoryId;
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    for (var variant in _variants) {
      variant.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          _isEditing ? 'Edit Brand' : 'Add Brand',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 1,
        centerTitle: true,
      ),
      body: Consumer<CategoryProvider>(
        builder: (context, categoryProvider, child) {
          return Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildBasicInfo(),
                  const SizedBox(height: 16),
                  _buildCategorySelection(categoryProvider),
                  const SizedBox(height: 16),
                  _buildVariantsSection(),
                  const SizedBox(height: 16),
                  _buildStatusToggle(),
                  const SizedBox(height: 24),
                  _buildSaveButton(),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBasicInfo() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.wine_bar, size: 18, color: AppColors.primaryRed),
                const SizedBox(width: 8),
                const Text(
                  'Brand Details',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextInputUtils.buildTextFormFieldNoPredictive(
              controller: _nameController,
              labelText: 'Brand Name',
              hintText: 'Enter brand name',
              decoration: _getInputDecoration('Brand Name'),
              inputFormatters: TextInputUtils.alphanumericInputFormatters,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Brand name is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextInputUtils.buildTextFormFieldNoPredictive(
              controller: _descriptionController,
              labelText: 'Description',
              hintText: 'Brief description (optional)',
              decoration: _getInputDecoration('Description'),
              inputFormatters: TextInputUtils.alphanumericInputFormatters,
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategorySelection(CategoryProvider categoryProvider) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.category, size: 18, color: AppColors.primaryRed),
                const SizedBox(width: 8),
                const Text(
                  'Category',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedCategoryId,
              decoration: _getInputDecoration('Select Category'),
              isExpanded: true,
              style: const TextStyle(fontSize: 14, color: Colors.black87),
              items: categoryProvider.categories
                  .where((category) => category.isActive)
                  .map((category) => DropdownMenuItem<String>(
                        value: category.id,
                        child: Text(category.name, style: const TextStyle(fontSize: 14)),
                      ))
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedCategoryId = value;
                  _selectedSubcategoryId = null;
                });
              },
              validator: (value) => value == null ? 'Please select a category' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedSubcategoryId,
              decoration: _getInputDecoration('Select Subcategory'),
              isExpanded: true,
              style: const TextStyle(fontSize: 14, color: Colors.black87),
              items: _selectedCategoryId == null
                  ? []
                  : categoryProvider
                      .getSubcategoriesForCategory(_selectedCategoryId!)
                      .where((subcategory) => subcategory.isActive)
                      .map((subcategory) => DropdownMenuItem<String>(
                            value: subcategory.id,
                            child: Text(subcategory.name, style: const TextStyle(fontSize: 14)),
                          ))
                      .toList(),
              onChanged: _selectedCategoryId == null
                  ? null
                  : (value) {
                      setState(() {
                        _selectedSubcategoryId = value;
                      });
                    },
              validator: (value) => value == null ? 'Please select a subcategory' : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVariantsSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.inventory_2, size: 18, color: AppColors.primaryRed),
                const SizedBox(width: 8),
                const Text(
                  'Variants',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addVariant,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primaryRed,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...List.generate(_variants.length, (index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildVariantCard(index),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildVariantCard(int index) {
    final variant = _variants[index];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'Variant ${index + 1}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              if (_variants.length > 1)
                IconButton(
                  onPressed: () => _removeVariant(index),
                  icon: const Icon(Icons.close, size: 16),
                  color: Colors.red[400],
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextInputUtils.buildTextFormFieldNoPredictive(
                  controller: variant.sizeController,
                  labelText: 'Size',
                  hintText: '750ml',
                  decoration: _getCompactInputDecoration('Size'),
                  inputFormatters: TextInputUtils.alphanumericInputFormatters,
                  onChanged: (value) => variant.size = value,
                  validator: (value) => value?.isEmpty == true ? 'Required' : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextInputUtils.buildTextFormFieldNoPredictive(
                  controller: variant.dutyController,
                  labelText: 'Duty %',
                  hintText: '12.5',
                  decoration: _getCompactInputDecoration('Duty %'),
                  inputFormatters: TextInputUtils.decimalInputFormatters,
                  onChanged: (value) => variant.duty = value,
                  validator: (value) => value?.isEmpty == true ? 'Required' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextInputUtils.buildTextFormFieldNoPredictive(
                  controller: variant.buyingPriceController,
                  labelText: 'Buy ₹',
                  hintText: '0.00',
                  decoration: _getCompactInputDecoration('Buy Price'),
                  inputFormatters: TextInputUtils.decimalInputFormatters,
                  onChanged: (value) => variant.buyingPrice = double.tryParse(value) ?? 0.0,
                  validator: (value) => value?.isEmpty == true ? 'Required' : null,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextInputUtils.buildTextFormFieldNoPredictive(
                  controller: variant.sellingPriceController,
                  labelText: 'Sell ₹',
                  hintText: '0.00',
                  decoration: _getCompactInputDecoration('Sell Price'),
                  inputFormatters: TextInputUtils.decimalInputFormatters,
                  onChanged: (value) => variant.sellingPrice = double.tryParse(value) ?? 0.0,
                  validator: (value) => value?.isEmpty == true ? 'Required' : null,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextInputUtils.buildTextFormFieldNoPredictive(
                  controller: variant.mrpController,
                  labelText: 'MRP ₹',
                  hintText: '0.00',
                  decoration: _getCompactInputDecoration('MRP'),
                  inputFormatters: TextInputUtils.decimalInputFormatters,
                  onChanged: (value) => variant.mrp = double.tryParse(value) ?? 0.0,
                  validator: (value) => value?.isEmpty == true ? 'Required' : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusToggle() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.toggle_on, size: 18, color: AppColors.primaryRed),
            const SizedBox(width: 8),
            const Text(
              'Status',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Switch.adaptive(
              value: _isActive,
              onChanged: (value) => setState(() => _isActive = value),
              activeColor: AppColors.success,
            ),
            const SizedBox(width: 8),
            Text(
              _isActive ? 'Active' : 'Inactive',
              style: TextStyle(
                fontSize: 12,
                color: _isActive ? AppColors.success : Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return Consumer<BrandProvider>(
      builder: (context, brandProvider, child) {
        return SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _saveBrand,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 2,
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    _isEditing ? 'Update Brand' : 'Create Brand',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
          ),
        );
      },
    );
  }

  InputDecoration _getInputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 12, color: Colors.grey),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: AppColors.primaryRed),
      ),
      filled: true,
      fillColor: Colors.white,
    );
  }

  InputDecoration _getCompactInputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 11, color: Colors.grey),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: AppColors.primaryRed),
      ),
      filled: true,
      fillColor: Colors.white,
    );
  }

  void _addVariant() {
    setState(() {
      _variants.add(BrandVariantForm());
    });
  }

  void _removeVariant(int index) {
    if (_variants.length > 1) {
      setState(() {
        _variants[index].dispose();
        _variants.removeAt(index);
      });
    }
  }

  Future<void> _saveBrand() async {
    if (!_formKey.currentState!.validate()) return;
    if (_variants.isEmpty) {
      _showError('Please add at least one variant');
      return;
    }
    if (_selectedCategoryId == null) {
      _showError('Please select a category');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final brandProvider = Provider.of<BrandProvider>(context, listen: false);

      final List<CreateBrandVariantRequest> variantRequests = _variants.map((variant) {
        return CreateBrandVariantRequest(
          brandId: '',
          categoryId: _selectedCategoryId!,
          subcategoryId: _selectedSubcategoryId,
          size: variant.size,
          alcoholContent: double.tryParse(variant.duty) ?? 0.0,
          picture: '',
          governmentDuty: double.tryParse(variant.duty) ?? 0.0,
          buyingPrice: variant.buyingPrice,
          sellingPrice: variant.sellingPrice,
          mrp: variant.mrp,
          description: variant.size,
          barcode: '',
          hsnCode: '',
          isActive: _isActive,
          sortOrder: 0,
        );
      }).toList();

      bool success;
      if (_isEditing) {
        final brandRequest = CreateBrandRequest(
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          picture: '',
          isActive: _isActive,
          sortOrder: 0,
        );
        success = await brandProvider.updateBrand(widget.brand!.id, brandRequest);

        if (success) {
          final existingVariants = widget.brand!.brandVariants ?? [];
          for (int i = 0; i < variantRequests.length; i++) {
            final variantRequest = CreateBrandVariantRequest(
              brandId: widget.brand!.id,
              categoryId: variantRequests[i].categoryId,
              subcategoryId: variantRequests[i].subcategoryId,
              size: variantRequests[i].size,
              alcoholContent: variantRequests[i].alcoholContent,
              picture: variantRequests[i].picture,
              governmentDuty: variantRequests[i].governmentDuty,
              buyingPrice: variantRequests[i].buyingPrice,
              sellingPrice: variantRequests[i].sellingPrice,
              mrp: variantRequests[i].mrp,
              description: variantRequests[i].description,
              barcode: variantRequests[i].barcode,
              hsnCode: variantRequests[i].hsnCode,
              isActive: variantRequests[i].isActive,
              sortOrder: variantRequests[i].sortOrder,
            );

            if (i < existingVariants.length) {
              await brandProvider.updateBrandVariant(existingVariants[i].id, variantRequest);
            } else {
              await brandProvider.createBrandVariant(variantRequest);
            }
          }

          if (existingVariants.length > variantRequests.length) {
            for (int i = variantRequests.length; i < existingVariants.length; i++) {
              await brandProvider.deleteBrandVariant(existingVariants[i].id);
            }
          }
        }
      } else {
        final request = CreateBrandWithVariantsRequest(
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          picture: '',
          isActive: _isActive,
          sortOrder: 0,
          variants: variantRequests,
        );
        success = await brandProvider.createBrandWithVariants(request);
      }

      if (success && mounted) {
        await brandProvider.loadBrands(showLoading: false);
        Navigator.of(context).pop();
        _showSuccess(_isEditing ? 'Brand updated successfully' : 'Brand created successfully');
      } else if (mounted) {
        _showError(brandProvider.error ?? 'Failed to save brand');
      }
    } catch (e) {
      if (mounted) {
        _showError('Error: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 12)),
        backgroundColor: Colors.red[600],
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 12)),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}