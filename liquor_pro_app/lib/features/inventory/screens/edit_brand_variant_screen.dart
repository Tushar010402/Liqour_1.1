import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/auth_service.dart';
import '../models/brand_variant_edit_model.dart';
import '../models/saas_brand.dart';
import '../services/brand_edit_service.dart';
import '../providers/product_provider.dart';
import '../../../core/utils/logger.dart';

/// Edit Brand Variant Screen - Tenant App
///
/// Modern iOS 16+ design matching Edit Product and Custom Brand Form screens
/// - Uses SaaS brand categories (not tenant categories)
/// - Category → Subcategory → Size flow
/// - "Buying Price" terminology (not "Cost Price")
/// - Industrial-grade UI with white section cards
class EditBrandVariantScreen extends StatefulWidget {
  final BrandVariantEditModel variant;

  const EditBrandVariantScreen({
    super.key,
    required this.variant,
  });

  @override
  State<EditBrandVariantScreen> createState() => _EditBrandVariantScreenState();
}

class _EditBrandVariantScreenState extends State<EditBrandVariantScreen> {
  final _formKey = GlobalKey<FormState>();
  late BrandEditService _brandEditService;

  // Form Controllers
  final _descriptionController = TextEditingController();
  final _alcoholContentController = TextEditingController();
  final _sellingPriceController = TextEditingController();
  final _buyingPriceController = TextEditingController();
  final _governmentDutyController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _hsnCodeController = TextEditingController();
  final _imageUrlController = TextEditingController();
  final _brandNameController = TextEditingController();

  // Form State
  late BrandVariantEditModel _editModel;

  // SaaS Admin Data
  List<SaasBrandCategory> _categories = [];
  List<SaasBrandSubcategory> _subcategories = [];
  List<String> _categorySizes = [];

  // Loading States
  bool _isLoadingData = true;
  bool _isSaving = false;

  // Disposal flag
  bool _isDisposed = false;

  // Legacy category flag
  bool _hasLegacyCategory = false;

  // Image Picker
  final ImagePicker _imagePicker = ImagePicker();
  File? _selectedImage;
  String? _imageBase64;

  @override
  void initState() {
    super.initState();

    _editModel = widget.variant;
    _brandEditService = BrandEditService(
      authService: context.read<AuthService>(),
    );

    // Populate form fields
    _populateFields();

    // Load SaaS Admin data
    _loadSaasData();
  }

  void _populateFields() {
    _brandNameController.text = _editModel.brandName;
    _descriptionController.text = _editModel.description;

    // Duty field - direct mapping
    _governmentDutyController.text = _editModel.governmentDuty.toString();

    // Alcohol % not displayed in UI - keep existing value
    _alcoholContentController.text = _editModel.alcoholContent.toString();

    // MRP removed - using selling price only
    _sellingPriceController.text = _editModel.sellingPrice.toString();
    _buyingPriceController.text = _editModel.buyingPrice.toString();
    _barcodeController.text = _editModel.barcode;
    _hsnCodeController.text = _editModel.hsnCode;
    _imageUrlController.text = _editModel.imageUrl ?? '';
  }

  Future<void> _loadSaasData() async {
    try {
      Logger.debug('🔄 Loading SaaS data for editing...');

      // Load categories
      Logger.debug('📋 Fetching SaaS brand categories...');
      final rawCategories = await _brandEditService.getSaasBrandCategories();

      // Remove duplicates based on ID
      final categoryMap = <String, SaasBrandCategory>{};
      for (final category in rawCategories) {
        categoryMap[category.id] = category;
      }
      _categories = categoryMap.values.toList();
      Logger.info('✅ Loaded ${_categories.length} categories (${rawCategories.length} raw)');

      // Load ALL subcategories upfront (like SaaS Admin app)
      Logger.debug('📋 Fetching ALL SaaS brand subcategories...');
      final rawSubcategories = await _brandEditService.getSaasBrandSubcategories();

      // Remove duplicates based on ID
      final subcategoryMap = <String, SaasBrandSubcategory>{};
      for (final subcategory in rawSubcategories) {
        subcategoryMap[subcategory.id] = subcategory;
      }
      _subcategories = subcategoryMap.values.toList();
      Logger.debug('✅ Loaded ${_subcategories.length} subcategories (${rawSubcategories.length} raw)');
      if (_subcategories.isNotEmpty) {
        Logger.debug('   Sample: ${_subcategories.take(2).map((s) => '${s.name}->cat:${s.categoryId}').join(', ')}');
      }

      // Load sizes for current category if product has one
      if (_editModel.categoryId.isNotEmpty) {
        Logger.debug('📏 Fetching sizes for product category: ${_editModel.categoryId}...');
        final rawSizes = await _brandEditService.getCategorySizes(
          categoryId: _editModel.categoryId,
        );
        // Remove duplicate sizes
        _categorySizes = rawSizes.toSet().toList();
        Logger.info('✅ Loaded ${_categorySizes.length} sizes (${rawSizes.length} raw)');
      } else {
        Logger.debug('ℹ️  No category ID on product, will load when category selected');
        _categorySizes = [];
      }

      // Validate that the categoryId exists in loaded categories
      if (_editModel.categoryId.isNotEmpty) {
        final categoryExists = _categories.any((c) => c.id == _editModel.categoryId);
        if (!categoryExists) {
          Logger.warning('⚠️  Category ID ${_editModel.categoryId} not found in SaaS categories');
          Logger.warning('   This product uses TENANT category (legacy), not SaaS category.');
          Logger.warning('   Keeping existing data but category/subcategory/size will be read-only.');

          // DON'T reset data - keep it but mark as legacy
          _hasLegacyCategory = true;

          // Show warning to user
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.white),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '⚠️ Legacy Product: Category and size cannot be changed. Other fields can be edited.',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  backgroundColor: AppColors.warning,
                  duration: const Duration(seconds: 6),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          });
        }
      }

      setState(() {
        _isLoadingData = false;
      });

      Logger.info('✅ SaaS data loaded successfully');
    } catch (e, stackTrace) {
      Logger.error('❌ Error loading SaaS data: $e');
      Logger.error('Stack trace: $stackTrace');

      setState(() {
        _isLoadingData = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading categories: ${e.toString()}'),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () {
                setState(() {
                  _isLoadingData = true;
                });
                _loadSaasData();
              },
            ),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _descriptionController.dispose();
    _alcoholContentController.dispose();
    _sellingPriceController.dispose();
    _buyingPriceController.dispose();
    _governmentDutyController.dispose();
    _barcodeController.dispose();
    _hsnCodeController.dispose();
    _imageUrlController.dispose();
    _brandNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // CRITICAL: Check if route is popping and hide form immediately (matches SaaS Admin)
    final route = ModalRoute.of(context);
    final isRoutePoppingBack = route?.animation?.status == AnimationStatus.reverse;

    if (_isDisposed || !mounted || isRoutePoppingBack) {
      return const Scaffold(body: SizedBox.shrink());
    }

    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surfaceContainerHighest,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: cs.surface,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, size: 20, color: cs.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Edit Brand Variant',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            Text(
              _editModel.brandName,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          if (_isSaving)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(right: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: _isLoadingData
          ? const Center(child: CircularProgressIndicator())
          : _buildForm(),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionCard(
            title: 'Brand Information',
            children: [
              _buildTextField(
                controller: _brandNameController,
                label: 'Brand Name',
                hint: 'Enter brand name',
                icon: Icons.local_drink,
                isRequired: true,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Brand name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _descriptionController,
                label: 'Description',
                hint: 'Describe the variant',
                icon: Icons.description,
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              _buildImagePicker(),
            ],
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            title: 'Variant Details',
            children: [
              _buildCategoryDropdowns(),
              const SizedBox(height: 12),
              _buildSizeDropdown(),
            ],
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            title: 'Pricing',
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildCompactTextField(
                      controller: _sellingPriceController,
                      label: 'Selling Price ₹',
                      hint: '1400.00',
                      isRequired: true,
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Required';
                        }
                        final price = double.tryParse(value);
                        if (price == null || price <= 0) {
                          return 'Invalid';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildCompactTextField(
                      controller: _buyingPriceController,
                      label: 'Buy ₹',
                      hint: '1200.00',
                      isRequired: true,
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Required';
                        }
                        final price = double.tryParse(value);
                        if (price == null || price <= 0) {
                          return 'Invalid';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildCompactTextField(
                      controller: _governmentDutyController,
                      label: 'Duty ₹ (opt)',
                      hint: '0.00',
                      isRequired: false, // Duty is optional
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        // Duty is optional - allow empty (defaults to 0)
                        if (value != null && value.trim().isNotEmpty) {
                          final duty = double.tryParse(value);
                          if (duty == null || duty < 0) {
                            return 'Invalid';
                          }
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            title: 'Additional Information',
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildCompactTextField(
                      controller: _barcodeController,
                      label: 'Barcode',
                      hint: '1234567890123',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildCompactTextField(
                      controller: _hsnCodeController,
                      label: 'HSN Code',
                      hint: '22081010',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildStatusToggle(),
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
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildImagePicker() {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: _isSaving ? null : _showImagePickerOptions,
      child: Container(
        width: double.infinity,
        height: 120,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outline),
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
                        child: const Icon(Icons.close, size: 16, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              )
            : (_imageUrlController.text.isNotEmpty
                ? Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          _imageUrlController.text,
                          width: double.infinity,
                          height: 120,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildImagePlaceholder(),
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _imageUrlController.clear();
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: AppColors.error,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close, size: 16, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  )
                : _buildImagePlaceholder()),
      ),
    );
  }

  Widget _buildImagePlaceholder() {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.add_photo_alternate_outlined, size: 36, color: cs.onSurfaceVariant),
        const SizedBox(height: 8),
        Text('Tap to change image', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        const SizedBox(height: 4),
        Text('(Optional)', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
      ],
    );
  }

  void _showImagePickerOptions() {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
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
                  color: cs.outline,
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
          _imageUrlController.clear(); // Clear URL when new image selected
        });
      }
    } catch (e) {
      Logger.error('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pick image: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool isRequired = false,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    bool enabled = true,
  }) {
    return TextFormField(
      controller: controller,
      decoration: _getInputDecoration(label, hint),
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      enabled: enabled && !_isSaving,
    );
  }

  Widget _buildCompactTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool isRequired = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      decoration: _getCompactInputDecoration(label, hint),
      keyboardType: keyboardType,
      validator: validator,
      enabled: !_isSaving,
    );
  }

  Widget _buildCategoryDropdowns() {
    // IMPORTANT: Show ALL subcategories regardless of category since they're universal
    // The subcategories in SaaS are not category-specific, they apply to all categories
    final filteredSubcategories = _subcategories; // Always show ALL subcategories

    // Debug logging
    Logger.debug('🔍 [Edit Screen] Category: ${_editModel.categoryId}');
    Logger.debug('🔍 [Edit Screen] Product subcategoryId: ${_editModel.subcategoryId}');
    Logger.debug('🔍 [Edit Screen] Total subcategories loaded: ${_subcategories.length}');
    Logger.debug('🔍 [Edit Screen] Showing ${filteredSubcategories.length} subcategories (all universal)');
    if (filteredSubcategories.isNotEmpty) {
      Logger.debug('🔍 [Edit Screen] Available: ${filteredSubcategories.map((s) => '${s.name} (${s.id})').join(', ')}');
    } else {
      Logger.warning('⚠️ [Edit Screen] No subcategories loaded! Check if API returned subcategories.');
    }

    // Show legacy category warning if applicable
    if (_hasLegacyCategory) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: AppColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This product uses legacy categories. Category and size are read-only.',
                    style: TextStyle(fontSize: 12, color: AppColors.warning),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Show existing category/size as read-only text
          _buildTextField(
            controller: TextEditingController(text: 'Legacy Category (${_editModel.categoryId})'),
            label: 'Category',
            hint: 'Legacy category',
            icon: Icons.category,
            enabled: false,
          ),
        ],
      );
    }

    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: _editModel.categoryId.isNotEmpty ? _editModel.categoryId : null,
            isExpanded: true,
            decoration: _getInputDecoration('Category', 'Select category'),
            style: TextStyle(fontSize: 15, color: cs.onSurface),
            items: _categories.map((category) {
              return DropdownMenuItem(
                value: category.id,
                child: Text(
                  category.name,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: _isSaving
                ? null
                : (value) async {
                    if (!_isDisposed && mounted && value != null) {
                      Logger.info('📝 [Edit Screen] Category changed to: $value');

                      // Load sizes for new category
                      Logger.debug('📏 [Edit Screen] Loading sizes for category: $value');
                      final rawSizes = await _brandEditService.getCategorySizes(
                        categoryId: value,
                      );
                      // Remove duplicates
                      final sizes = rawSizes.toSet().toList();
                      Logger.info('✅ [Edit Screen] Loaded ${sizes.length} sizes: ${sizes.join(', ')}');

                      setState(() {
                        _editModel = _editModel.copyWith(
                          categoryId: value,
                          subcategoryId: '', // Reset subcategory
                          size: '', // Reset size
                        );
                        _categorySizes = sizes;
                        Logger.info('✅ [Edit Screen] State updated - sizes available in dropdown');
                      });
                    }
                  },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: _editModel.subcategoryId?.isNotEmpty == true &&
                   filteredSubcategories.any((s) => s.id == _editModel.subcategoryId)
                ? _editModel.subcategoryId
                : null,
            isExpanded: true,
            decoration: _getInputDecoration(
              'Subcategory',
              filteredSubcategories.isEmpty ? 'No subcategories available' : 'Select subcategory (Optional)',
            ),
            style: TextStyle(fontSize: 15, color: cs.onSurface),
            items: filteredSubcategories.isEmpty
                ? [
                    DropdownMenuItem<String>(
                      value: '',
                      enabled: false,
                      child: Text(
                        'No subcategories loaded',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ),
                  ]
                : filteredSubcategories.map((subcategory) {
                    return DropdownMenuItem<String>(
                      value: subcategory.id,
                      child: Text(
                        subcategory.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
            onChanged: _isSaving || filteredSubcategories.isEmpty
                ? null
                : (value) {
                    if (!_isDisposed && mounted) {
                      setState(() {
                        _editModel = _editModel.copyWith(subcategoryId: value ?? '');
                      });
                    }
                  },
          ),
        ),
      ],
    );
  }

  Widget _buildSizeDropdown() {
    // If legacy category, show as read-only text field
    if (_hasLegacyCategory) {
      return _buildTextField(
        controller: TextEditingController(text: _editModel.size),
        label: 'Size',
        hint: 'Legacy size',
        icon: Icons.straighten,
        enabled: false,
      );
    }

    final cs = Theme.of(context).colorScheme;

    return DropdownButtonFormField<String>(
      initialValue: _editModel.size.isNotEmpty && _categorySizes.contains(_editModel.size)
          ? _editModel.size
          : null,
      isExpanded: true,
      decoration: _getInputDecoration(
        'Size',
        _categorySizes.isEmpty ? 'Select category first' : 'Select size',
      ),
      style: TextStyle(fontSize: 15, color: cs.onSurface),
      items: _categorySizes.isEmpty
          ? [
              DropdownMenuItem<String>(
                value: '',
                enabled: false,
                child: Text(
                  _editModel.categoryId.isEmpty
                      ? 'Select category first'
                      : 'Loading sizes...',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
            ]
          : _categorySizes.map((size) {
              return DropdownMenuItem(
                value: size,
                child: Text(size, overflow: TextOverflow.ellipsis),
              );
            }).toList(),
      onChanged: _isSaving || _categorySizes.isEmpty
          ? null
          : (value) {
              if (!_isDisposed && mounted && value != null) {
                setState(() {
                  _editModel = _editModel.copyWith(size: value);
                });
              }
            },
      validator: (value) {
        if (_categorySizes.isEmpty) {
          return 'Select category first';
        }
        if (value == null || value.isEmpty) {
          return 'Size required';
        }
        return null;
      },
    );
  }


  Widget _buildStatusToggle() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _editModel.isActive
            ? AppColors.success.withValues(alpha: 0.05)
            : AppColors.error.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _editModel.isActive
              ? AppColors.success.withValues(alpha: 0.2)
              : AppColors.error.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _editModel.isActive ? Icons.check_circle : Icons.cancel,
            color: _editModel.isActive ? AppColors.success : AppColors.error,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _editModel.isActive ? 'Active' : 'Inactive',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _editModel.isActive ? AppColors.success : AppColors.error,
              ),
            ),
          ),
          Switch.adaptive(
            value: _editModel.isActive,
            onChanged: _isSaving
                ? null
                : (value) {
                    if (!_isDisposed && mounted) {
                      setState(() {
                        _editModel = _editModel.copyWith(isActive: value);
                      });
                    }
                  },
            activeColor: AppColors.success,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _isSaving ? null : () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              side: BorderSide(color: cs.outline),
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
            onPressed: _isSaving ? null : _saveChanges,
            style: ElevatedButton.styleFrom(
              backgroundColor: cs.primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
            child: _isSaving
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

  InputDecoration _getInputDecoration(String label, String hint) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      hintText: hint,
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
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: cs.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: cs.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: cs.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.error, width: 1),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
    );
  }

  InputDecoration _getCompactInputDecoration(String label, String hint) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      hintText: hint,
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
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: cs.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: cs.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: cs.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: AppColors.error, width: 1),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
    );
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) {
      Logger.warning('❌ Form validation failed');
      return;
    }

    Logger.info('💾 Starting save process...');
    setState(() => _isSaving = true);

    try {
      // Handle image - prioritize new image over existing URL
      String? finalImageUrl = _imageUrlController.text.trim();
      if (_imageBase64 != null) {
        // New image selected - clear URL, backend will handle base64
        finalImageUrl = '';
        Logger.info('📷 New image selected, will upload as base64');
      }

      // Update model with form data
      // Direct mapping - no swap needed (fixed at source)
      _editModel = _editModel.copyWith(
        brandName: _brandNameController.text.trim(),
        description: _descriptionController.text.trim(),
        // Direct mapping: alcohol % controller -> alcoholContent field
        alcoholContent: double.tryParse(_alcoholContentController.text) ?? 0,
        // Direct mapping: duty controller -> governmentDuty field
        governmentDuty: double.tryParse(_governmentDutyController.text) ?? 0,
        // MRP = Selling Price (no separate MRP field)
        mrp: double.tryParse(_sellingPriceController.text) ?? 0,
        sellingPrice: double.tryParse(_sellingPriceController.text) ?? 0,
        buyingPrice: double.tryParse(_buyingPriceController.text) ?? 0,
        barcode: _barcodeController.text.trim(),
        hsnCode: _hsnCodeController.text.trim(),
        imageUrl: finalImageUrl.isNotEmpty ? finalImageUrl : null,
      );

      Logger.info('📝 Model updated with form data');

      // Validate model
      final errors = _editModel.validate();
      if (errors.isNotEmpty) {
        Logger.error('❌ Model validation errors: ${errors.join(", ")}');
        throw Exception(errors.join('\n'));
      }

      Logger.info('✅ Model validation passed');

      // Prepare update data
      final updateData = _editModel.toJson();

      // Add image_base64 if a new image was selected
      if (_imageBase64 != null) {
        updateData['image_base64'] = _imageBase64;
        Logger.debug('📷 Added image_base64 to update payload');
      }

      Logger.debug('📦 Update payload: ${updateData.keys.join(", ")}');

      // Update via service
      Logger.debug('🔄 Calling update API...');
      final success = await _brandEditService.updateBrandVariant(
        productId: _editModel.id,
        updateData: updateData,
      );

      if (success && mounted) {
        Logger.info('✅ Product updated successfully');

        // Refresh product list
        Logger.info('🔄 Refreshing product list...');
        await context.read<ProductProvider>().refreshProducts();

        Navigator.pop(context, true);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Product "${_editModel.brandName} - ${_editModel.size}" updated successfully',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      } else {
        Logger.error('❌ Update failed or widget not mounted');
        throw Exception('Update failed');
      }
    } catch (e, stackTrace) {
      Logger.error('❌ Error saving changes: $e');
      Logger.error('Stack trace: $stackTrace');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Error saving product',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  e.toString(),
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
}
