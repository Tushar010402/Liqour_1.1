import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/product_constants.dart';
import '../../../core/utils/text_input_utils.dart';
import '../../../core/services/dio_api_service.dart';
import '../models/brand_metadata.dart';
import '../services/brand_onboarding_service.dart';
import '../providers/product_provider.dart';

/// Helper class for managing variant forms
class BrandVariantForm {
  String? selectedSize;
  String duty;
  double buyingPrice;
  double sellingPrice;
  late TextEditingController dutyController;
  late TextEditingController buyingPriceController;
  late TextEditingController sellingPriceController;

  BrandVariantForm({
    this.selectedSize,
    this.duty = '',
    this.buyingPrice = 0.0,
    this.sellingPrice = 0.0,
  }) {
    dutyController = TextEditingController(text: duty);
    buyingPriceController = TextEditingController(text: buyingPrice > 0 ? buyingPrice.toString() : '');
    sellingPriceController = TextEditingController(text: sellingPrice > 0 ? sellingPrice.toString() : '');
  }

  void dispose() {
    dutyController.dispose();
    buyingPriceController.dispose();
    sellingPriceController.dispose();
  }
}

/// Custom Brand Form Screen - Create custom brands for tenant
/// Exactly matching SaaS Admin structure adapted for liquor_pro_app
class CustomBrandFormScreen extends StatefulWidget {
  const CustomBrandFormScreen({super.key});

  @override
  State<CustomBrandFormScreen> createState() => _CustomBrandFormScreenState();
}

class _CustomBrandFormScreenState extends State<CustomBrandFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  bool _isActive = true;
  bool _isLoading = false;
  bool _isDisposed = false;

  String? _selectedCategoryId;
  String? _selectedSubcategoryId;
  final List<BrandVariantForm> _variants = [BrandVariantForm()];

  // Brand image
  File? _selectedImage;
  String? _imageBase64;

  // SaaS Brand Categories and Subcategories
  List<CategoryDetail> _categories = [];
  List<SubcategoryDetail> _allSubcategories = [];
  bool _isCategoriesLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadCategories();
    });
  }

  Future<void> _loadCategories() async {
    if (_isDisposed || !mounted) return;

    print('🔨 [CustomBrandForm] Loading SaaS brand metadata...');

    setState(() {
      _isCategoriesLoading = true;
    });

    try {
      // Get ApiService and load brand metadata
      final apiService = context.read<DioApiService>();

      print('🔨 [CustomBrandForm] Calling getBrandMetadata()...');
      final response = await getBrandMetadata(apiService);

      if (response.success && response.data != null) {
        final metadata = response.data!;

        if (!_isDisposed && mounted) {
          setState(() {
            _categories = metadata.categories;
            _allSubcategories = metadata.subcategories;
            _isCategoriesLoading = false;
          });
          print('🔨 [CustomBrandForm] ✅ Loaded ${_categories.length} categories, ${_allSubcategories.length} subcategories');
          if (_categories.isNotEmpty) {
            print('🔨 [CustomBrandForm] Categories: ${_categories.map((c) => c.name).join(", ")}');
          }
          if (_allSubcategories.isNotEmpty) {
            print('🔨 [CustomBrandForm] Sample subcategories: ${_allSubcategories.take(5).map((s) => s.name).join(", ")}');
          }
        }
      } else {
        print('🔨 [CustomBrandForm] ❌ Failed to load metadata: ${response.message}');
        if (!_isDisposed && mounted) {
          setState(() {
            _isCategoriesLoading = false;
          });
          _showError('Failed to load categories: ${response.message}');
        }
      }
    } catch (e) {
      print('🔨 [CustomBrandForm] ❌ Exception loading categories: $e');
      if (!_isDisposed && mounted) {
        setState(() {
          _isCategoriesLoading = false;
        });
        _showError('Failed to load categories: $e');
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _nameController.dispose();
    _descriptionController.dispose();
    for (var variant in _variants) {
      variant.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // CRITICAL: Check if route is popping and hide form immediately
    final route = ModalRoute.of(context);
    final isRoutePoppingBack = route?.animation?.status == AnimationStatus.reverse;

    if (_isDisposed || !mounted || isRoutePoppingBack) {
      return const Scaffold(
        body: SizedBox.shrink(),
      );
    }

    print('🔨 [CustomBrandForm] build() - Categories: ${_categories.length}, Loading: $_isCategoriesLoading');

    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surfaceContainerHighest,
      appBar: AppBar(
        title: const Text(
          'Add Custom Brand',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        elevation: 1,
        centerTitle: true,
      ),
      body: _isCategoriesLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildBasicInfo(),
                      const SizedBox(height: 16),
                      _buildCategorySelection(),
                      const SizedBox(height: 16),
                      _buildVariantsSection(),
                      const SizedBox(height: 16),
                      _buildStatusToggle(),
                      const SizedBox(height: 24),
                      _buildSaveButton(),
                      // Extra bottom padding to prevent overflow and ensure keyboard visibility
                      SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 50),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildBasicInfo() {
    // CRITICAL: Prevent using disposed controllers
    if (_isDisposed || !mounted) {
      return const SizedBox.shrink();
    }

    final cs = Theme.of(context).colorScheme;
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
                Icon(Icons.wine_bar, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                const Text(
                  'Brand Details',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Brand Image Picker
            _buildImagePicker(),
            const SizedBox(height: 12),
            if (!_isDisposed && mounted)
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
            if (!_isDisposed && mounted)
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

  Widget _buildImagePicker() {
    return GestureDetector(
      onTap: _showImagePickerOptions,
      child: Container(
        width: double.infinity,
        height: 120,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
            style: BorderStyle.solid,
          ),
        ),
        child: _selectedImage != null
            ? Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      _selectedImage!,
                      width: double.infinity,
                      height: 120,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedImage = null;
                          _imageBase64 = null;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppColors.error,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_photo_alternate_outlined,
                      size: 36, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(height: 8),
                  Text(
                    'Tap to add brand image',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '(Optional)',
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  void _showImagePickerOptions() {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Select Image Source',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.camera_alt, color: cs.primary),
                ),
                title: const Text('Camera'),
                subtitle: const Text('Take a new photo'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.photo_library, color: cs.primary),
                ),
                title: const Text('Gallery'),
                subtitle: const Text('Choose from gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 80,
      );

      if (pickedFile != null && mounted) {
        final file = File(pickedFile.path);
        final bytes = await file.readAsBytes();
        final base64String = base64Encode(bytes);

        setState(() {
          _selectedImage = file;
          _imageBase64 = base64String;
        });
      }
    } catch (e) {
      print('Error picking image: $e');
      if (mounted) {
        _showError('Failed to pick image: $e');
      }
    }
  }

  Widget _buildCategorySelection() {
    // CRITICAL: Prevent using disposed state
    if (_isDisposed) {
      return const SizedBox.shrink();
    }

    final cs = Theme.of(context).colorScheme;
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
                Icon(Icons.category, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                const Text(
                  'Category',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const ValueKey('category_dropdown'),
              initialValue: _selectedCategoryId,
              decoration: _getInputDecoration('Select Category'),
              isExpanded: true,
              menuMaxHeight: 300,
              style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface),
              items: _categories.isEmpty
                  ? [
                      DropdownMenuItem<String>(
                        value: null,
                        enabled: false,
                        child: Text('No categories available', style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ),
                    ]
                  : _categories
                      .where((category) => category.isActive)
                      .map((category) => DropdownMenuItem<String>(
                            value: category.id,
                            child: Row(
                              children: [
                                Icon(Icons.circle, size: 8, color: cs.primary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    category.name,
                                    style: const TextStyle(fontSize: 14),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ))
                      .toList(),
              onChanged: (value) {
                if (!_isDisposed && mounted) {
                  setState(() {
                    _selectedCategoryId = value;
                    _selectedSubcategoryId = null;
                    // Reset all variant sizes when category changes
                    for (var variant in _variants) {
                      variant.selectedSize = null;
                    }
                  });
                }
              },
              validator: (value) => value == null ? 'Please select a category' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const ValueKey('subcategory_dropdown'),
              initialValue: _selectedSubcategoryId,
              decoration: _getInputDecoration('Select Subcategory (Optional)'),
              isExpanded: true,
              menuMaxHeight: 300,
              style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface),
              items: _selectedCategoryId == null
                  ? []
                  : _getFilteredSubcategories()
                      .where((subcategory) => subcategory.isActive)
                      .map((subcategory) => DropdownMenuItem<String>(
                            value: subcategory.id,
                            child: Row(
                              children: [
                                Icon(Icons.subdirectory_arrow_right, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    subcategory.name,
                                    style: const TextStyle(fontSize: 14),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ))
                      .toList(),
              onChanged: _selectedCategoryId == null
                  ? null
                  : (value) {
                      if (!_isDisposed && mounted) {
                        setState(() {
                          _selectedSubcategoryId = value;
                        });
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  /// Get filtered subcategories for selected category
  List<SubcategoryDetail> _getFilteredSubcategories() {
    if (_selectedCategoryId == null || _selectedCategoryId!.isEmpty) {
      return []; // Return EMPTY if no category selected
    }

    // Filter: exact match OR universal subcategories (null/zero UUID)
    final filtered = _allSubcategories.where((sub) {
      // Exact match with selected category
      if (sub.categoryId == _selectedCategoryId) return true;

      // Universal subcategories (null or zero UUID - applies to all categories)
      if (sub.categoryId.isEmpty ||
          sub.categoryId == '00000000-0000-0000-0000-000000000000') {
        return true;
      }

      return false;
    }).toList();

    print('🔍 [CustomBrandForm] Filtered ${filtered.length} subcategories for category: $_selectedCategoryId');
    return filtered;
  }

  Widget _buildVariantsSection() {
    // CRITICAL: Prevent using disposed state
    if (_isDisposed) {
      return const SizedBox.shrink();
    }

    final cs = Theme.of(context).colorScheme;
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
                Icon(Icons.inventory_2, size: 18, color: cs.primary),
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
                    foregroundColor: cs.primary,
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
    // CRITICAL: Prevent using disposed variant controllers
    if (_isDisposed) {
      return const SizedBox.shrink();
    }

    final variant = _variants[index];
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cs.outlineVariant),
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
                  color: AppColors.error,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Size and Duty (optional) row
          Row(
            children: [
              Flexible(
                flex: 1,
                child: _buildSizeDropdown(variant),
              ),
              const SizedBox(width: 6),
              Flexible(
                flex: 1,
                child: TextInputUtils.buildTextFormFieldNoPredictive(
                  controller: variant.dutyController,
                  labelText: 'Duty ₹',
                  hintText: '0.00 (optional)',
                  decoration: _getCompactInputDecoration('Duty ₹ (opt)'),
                  inputFormatters: TextInputUtils.decimalInputFormatters,
                  onChanged: (value) => variant.duty = value,
                  // Duty is now optional - no validator
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Price fields - Buy and Sell only (MRP = Sell Price)
          Row(
            children: [
              Flexible(
                flex: 1,
                child: TextInputUtils.buildTextFormFieldNoPredictive(
                  controller: variant.buyingPriceController,
                  labelText: 'Cost Price ₹',
                  hintText: '0.00',
                  decoration: _getCompactInputDecoration('Cost ₹'),
                  inputFormatters: TextInputUtils.decimalInputFormatters,
                  onChanged: (value) => variant.buyingPrice = double.tryParse(value) ?? 0.0,
                  validator: (value) => value?.isEmpty == true ? 'Required' : null,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                flex: 1,
                child: TextInputUtils.buildTextFormFieldNoPredictive(
                  controller: variant.sellingPriceController,
                  labelText: 'Selling Price ₹',
                  hintText: '0.00',
                  decoration: _getCompactInputDecoration('Sell ₹'),
                  inputFormatters: TextInputUtils.decimalInputFormatters,
                  onChanged: (value) => variant.sellingPrice = double.tryParse(value) ?? 0.0,
                  validator: (value) => value?.isEmpty == true ? 'Required' : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSizeDropdown(BrandVariantForm variant) {
    // CRITICAL: Prevent using disposed variant state
    if (_isDisposed) {
      return const SizedBox.shrink();
    }

    // Get category name from selected category ID
    String categoryName = '';
    if (_selectedCategoryId != null) {
      final category = _categories
          .where((cat) => cat.id == _selectedCategoryId)
          .firstOrNull;
      categoryName = category?.name ?? '';
    }

    // Get size options from ProductConstants based on category
    List<String> sizeOptions = categoryName.isNotEmpty
        ? ProductConstants.getSizesForCategory(categoryName)
        : ProductConstants.spiritSizes;

    // NEW: Get already selected sizes from OTHER variants (prevent duplicates)
    final otherSelectedSizes = _variants
        .where((v) => v != variant)
        .map((v) => v.selectedSize)
        .where((size) => size != null && size.isNotEmpty)
        .toSet();

    // Filter out already selected sizes
    final availableSizes = sizeOptions
        .where((size) => !otherSelectedSizes.contains(size))
        .toList();

    // Check if selected size is valid for current category
    final isSizeValid = variant.selectedSize != null &&
        sizeOptions.contains(variant.selectedSize);

    return DropdownButtonFormField<String>(
      key: ValueKey('size_dropdown_${variant.hashCode}'),
      initialValue: isSizeValid ? variant.selectedSize : null,
      decoration: _getCompactInputDecoration('Size'),
      isExpanded: true,
      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w500),
      items: availableSizes.map((size) {
        return DropdownMenuItem(
          value: size,
          child: Text(size, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface)),
        );
      }).toList(),
      onChanged: _selectedCategoryId != null
          ? (value) {
              if (!_isDisposed && mounted) {
                setState(() {
                  variant.selectedSize = value;
                });
              }
            }
          : null,
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Required';
        }
        // Check if size is already used by another variant
        if (otherSelectedSizes.contains(value)) {
          return 'Already used';
        }
        return null;
      },
    );
  }

  Widget _buildStatusToggle() {
    // CRITICAL: Prevent using disposed state
    if (_isDisposed) {
      return const SizedBox.shrink();
    }

    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.toggle_on, size: 18, color: cs.primary),
            const SizedBox(width: 8),
            const Text(
              'Status',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Switch.adaptive(
              value: _isActive,
              onChanged: (value) {
                if (!_isDisposed && mounted) {
                  setState(() => _isActive = value);
                }
              },
              activeTrackColor: AppColors.success,
            ),
            const SizedBox(width: 8),
            Text(
              _isActive ? 'Active' : 'Inactive',
              style: TextStyle(
                fontSize: 12,
                color: _isActive ? AppColors.success : Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    // Prevent access to disposed controllers
    if (_isDisposed) {
      return const SizedBox.shrink();
    }

    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _saveBrand,
        style: ElevatedButton.styleFrom(
          backgroundColor: cs.primary,
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
            : const Text(
                'Create Custom Brand',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }

  InputDecoration _getInputDecoration(String label) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: cs.primary),
      ),
      filled: true,
      fillColor: cs.surface,
    );
  }

  InputDecoration _getCompactInputDecoration(String label) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(fontSize: 11, color: cs.onSurface, fontWeight: FontWeight.w600),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: cs.primary),
      ),
      filled: true,
      fillColor: cs.surface,
    );
  }

  void _addVariant() {
    if (!_isDisposed && mounted) {
      setState(() {
        _variants.add(BrandVariantForm());
      });
    }
  }

  void _removeVariant(int index) {
    if (_variants.length > 1 && !_isDisposed && mounted) {
      final variantToDispose = _variants[index];
      setState(() {
        _variants.removeAt(index);
      });
      // Dispose after the UI has updated
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isDisposed && mounted) {
          variantToDispose.dispose();
        }
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

    // NEW: Validate no duplicate sizes
    final sizes = _variants.map((v) => v.selectedSize).toList();
    final uniqueSizes = sizes.toSet();
    if (sizes.length != uniqueSizes.length) {
      _showError('Duplicate sizes detected. Each variant must have a unique size.');
      return;
    }

    if (!_isDisposed && mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final apiService = context.read<DioApiService>();
      final productProvider = context.read<ProductProvider>();

      // Build variants list from all variant forms
      // Send duty amount as 'duty_fee' (correct field name for backend)
      // MRP is set to selling price (user request - they are the same)
      // Size is normalized to uppercase ML format (e.g., '90ML', '180ML')
      final variantsList = _variants.map((variant) => {
        'size': ProductConstants.normalizeSize(variant.selectedSize ?? ''),
        'duty_fee': double.tryParse(variant.duty) ?? 0.0,  // Correct: duty goes to duty_fee
        'cost_price': variant.buyingPrice,
        'selling_price': variant.sellingPrice,
        'mrp': variant.sellingPrice,  // MRP = Selling Price (user request)
        'barcode': '',
      }).toList();

      print('🔨 [CustomBrandForm] Creating custom brand: ${_nameController.text.trim()}');
      print('🔨 [CustomBrandForm] Category ID: $_selectedCategoryId');
      print('🔨 [CustomBrandForm] Subcategory ID: $_selectedSubcategoryId');
      print('🔨 [CustomBrandForm] Number of variants: ${variantsList.length}');
      print('🔨 [CustomBrandForm] Variant sizes: ${_variants.map((v) => v.selectedSize).join(", ")}');
      print('🔨 [CustomBrandForm] Has image: ${_imageBase64 != null}');

      final response = await apiService.post<Map<String, dynamic>>(
        '/api/inventory/brands/custom',
        body: {
          'brand_name': _nameController.text.trim(),
          'description': _descriptionController.text.trim(),
          'category_id': _selectedCategoryId!,
          if (_selectedSubcategoryId != null) 'subcategory_id': _selectedSubcategoryId,
          if (_imageBase64 != null) 'image_base64': _imageBase64,
          'variants': variantsList,
        },
        fromJson: (data) => (data as Map<String, dynamic>?) ?? {},
      );

      if (response.success && mounted) {
        print('🔨 [CustomBrandForm] ✅ Brand created successfully: ${response.data}');
        if (!_isDisposed && mounted) {
          _showSuccess('Custom brand created successfully');
          // Refresh products list
          await productProvider.loadProducts();
          Navigator.of(context).pop();
        }
      } else if (mounted) {
        final errorMsg = response.message ?? 'Failed to create custom brand';
        print('🔨 [CustomBrandForm] ❌ Failed: $errorMsg');
        _showError(errorMsg);
      }
    } catch (e) {
      print('🔨 [CustomBrandForm] ❌ Exception: $e');
      if (mounted) {
        _showError('Error: ${e.toString()}');
      }
    } finally {
      if (!_isDisposed && mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 12)),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
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
