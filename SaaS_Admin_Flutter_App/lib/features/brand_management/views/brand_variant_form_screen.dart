import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/brand_model.dart';
import '../controllers/brand_provider.dart';

class BrandVariantFormScreen extends StatefulWidget {
  final Brand brand;
  final BrandVariant? variant;

  const BrandVariantFormScreen({
    super.key,
    required this.brand,
    this.variant,
  });

  @override
  State<BrandVariantFormScreen> createState() => _BrandVariantFormScreenState();
}

class _BrandVariantFormScreenState extends State<BrandVariantFormScreen>
    with TickerProviderStateMixin {
  // Fixed RenderFlex overflow issues with Flexible widgets and dropdown text overflow
  // Implemented complete update variant functionality
  final _formKey = GlobalKey<FormState>();

  // Form Controllers
  final _sizeController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _pictureController = TextEditingController();
  final _alcoholContentController = TextEditingController();
  final _mrpController = TextEditingController();
  final _sellingPriceController = TextEditingController();
  final _buyingPriceController = TextEditingController();
  final _governmentDutyController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _hsnCodeController = TextEditingController();
  final _sortOrderController = TextEditingController();

  // Form State
  bool _isActive = true;
  bool _isLoading = false;
  String? _selectedCategoryId;
  String? _selectedSubcategoryId;

  // Animation Controllers
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  bool get _isEditing => widget.variant != null;

  @override
  void initState() {
    super.initState();

    // Initialize animations
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    if (_isEditing) {
      _populateFields();
    } else {
      _sortOrderController.text = '0';
      _alcoholContentController.text = '0.0';
      _mrpController.text = '0.0';
      _sellingPriceController.text = '0.0';
      _buyingPriceController.text = '0.0';
      _governmentDutyController.text = '0.0';
    }

    // Start animations
    _fadeController.forward();
    _slideController.forward();

    // Load categories and subcategories
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<BrandProvider>();
      provider.loadBrandCategories();
      provider.loadBrandSubcategories();
    });
  }

  void _populateFields() {
    final variant = widget.variant!;
    _sizeController.text = variant.size;
    _descriptionController.text = variant.description;
    _pictureController.text = variant.picture;
    _alcoholContentController.text = variant.alcoholContent.toString();
    _mrpController.text = variant.mrp.toString();
    _sellingPriceController.text = variant.sellingPrice.toString();
    _buyingPriceController.text = variant.buyingPrice.toString();
    _governmentDutyController.text = variant.governmentDuty.toString();
    _barcodeController.text = variant.barcode;
    _hsnCodeController.text = variant.hsnCode;
    _sortOrderController.text = variant.sortOrder.toString();
    _isActive = variant.isActive;
    _selectedCategoryId = variant.categoryId;
    _selectedSubcategoryId = variant.subcategoryId;
  }

  @override
  void dispose() {
    _sizeController.dispose();
    _descriptionController.dispose();
    _pictureController.dispose();
    _alcoholContentController.dispose();
    _mrpController.dispose();
    _sellingPriceController.dispose();
    _buyingPriceController.dispose();
    _governmentDutyController.dispose();
    _barcodeController.dispose();
    _hsnCodeController.dispose();
    _sortOrderController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 768;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: Consumer<BrandProvider>(
        builder: (context, brandProvider, child) {
          return CustomScrollView(
            slivers: [
              _buildSliverAppBar(context, isMobile),
              if (brandProvider.error != null)
                SliverToBoxAdapter(
                  child: _buildEnhancedErrorBanner(brandProvider),
                ),
              SliverToBoxAdapter(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: Form(
                      key: _formKey,
                      child: Padding(
                        padding: EdgeInsets.all(isMobile ? 16 : 24),
                        child: Column(
                          children: [
                            _buildBrandInfoCard(),
                            const SizedBox(height: 24),
                            _buildVariantInfoSection(isMobile),
                            const SizedBox(height: 24),
                            _buildPricingSection(isMobile),
                            const SizedBox(height: 24),
                            _buildAdditionalInfoSection(isMobile),
                            const SizedBox(height: 100), // Space for FAB
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: _buildEnhancedActionButtons(context),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildSliverAppBar(BuildContext context, bool isMobile) {
    return SliverAppBar(
      expandedHeight: isMobile ? 100 : 120,
      floating: true,
      pinned: true,
      snap: true,
      elevation: 0,
      backgroundColor: AppColors.primaryRed,
      foregroundColor: Colors.white,
      flexibleSpace: FlexibleSpaceBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.inventory_2_rounded, size: 20),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _isEditing ? 'Edit Variant' : 'Add Variant',
                style: TextStyle(
                  fontSize: isMobile ? 16 : 18,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        centerTitle: false,
      ),
      actions: [
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close),
          tooltip: 'Close',
        ),
      ],
    );
  }

  Widget _buildEnhancedErrorBanner(BrandProvider provider) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.error,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.error_outline,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Error',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.error,
                  ),
                ),
                Text(
                  provider.error!,
                  style: TextStyle(
                    color: AppColors.error.withOpacity(0.8),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => provider.clearError(),
            icon: const Icon(Icons.close, size: 20),
            color: AppColors.error,
          ),
        ],
      ),
    );
  }

  Widget _buildBrandInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primaryRed.withOpacity(0.05),
            AppColors.primaryRed.withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primaryRed.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primaryRed.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: widget.brand.picture.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      widget.brand.picture,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                        Icons.local_drink,
                        color: AppColors.primaryRed,
                        size: 24,
                      ),
                    ),
                  )
                : const Icon(
                    Icons.local_drink,
                    color: AppColors.primaryRed,
                    size: 24,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.brand.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryRed,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isEditing
                      ? 'Editing variant for this brand'
                      : 'Adding new variant to this brand',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.primaryRed.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVariantInfoSection(bool isMobile) {
    return _buildSection(
      title: 'Variant Information',
      icon: Icons.inventory_2,
      color: AppColors.primaryBlue,
      children: [
        Row(
          children: [
            Expanded(
              flex: 2,
              child: _buildEnhancedTextField(
                controller: _sizeController,
                label: 'Size/Volume',
                hint: 'e.g., 750ml, 1L, 180ml',
                icon: Icons.straighten,
                isRequired: true,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Size is required';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildEnhancedTextField(
                controller: _alcoholContentController,
                label: 'Alcohol %',
                hint: '40.0',
                icon: Icons.local_bar,
                isRequired: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Alcohol content is required';
                  }
                  final alcohol = double.tryParse(value);
                  if (alcohol == null || alcohol < 0 || alcohol > 100) {
                    return 'Enter valid percentage (0-100)';
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _buildEnhancedTextField(
          controller: _descriptionController,
          label: 'Description',
          hint: 'Describe the variant characteristics',
          icon: Icons.description,
          maxLines: 3,
          validator: (value) {
            if (value != null && value.isNotEmpty && value.trim().length < 5) {
              return 'Description must be at least 5 characters';
            }
            return null;
          },
        ),
        const SizedBox(height: 20),
        _buildCategoryDropdowns(),
        const SizedBox(height: 20),
        _buildImageUploadSection(),
      ],
    );
  }

  Widget _buildPricingSection(bool isMobile) {
    return _buildSection(
      title: 'Pricing Information',
      icon: Icons.payments,
      color: AppColors.success,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildEnhancedTextField(
                controller: _mrpController,
                label: 'MRP',
                hint: '1500.00',
                icon: Icons.currency_rupee,
                isRequired: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'MRP is required';
                  }
                  final price = double.tryParse(value);
                  if (price == null || price <= 0) {
                    return 'Enter valid MRP';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildEnhancedTextField(
                controller: _sellingPriceController,
                label: 'Selling Price',
                hint: '1400.00',
                icon: Icons.sell,
                isRequired: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Selling price is required';
                  }
                  final price = double.tryParse(value);
                  if (price == null || price <= 0) {
                    return 'Enter valid selling price';
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _buildEnhancedTextField(
          controller: _buyingPriceController,
          label: 'Buying Price',
          hint: '1200.00',
          icon: Icons.shopping_cart,
          isRequired: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Buying price is required';
            }
            final price = double.tryParse(value);
            if (price == null || price <= 0) {
              return 'Enter valid buying price';
            }
            return null;
          },
        ),
        const SizedBox(height: 20),
        _buildEnhancedTextField(
          controller: _governmentDutyController,
          label: 'Government Duty',
          hint: '200.00',
          icon: Icons.account_balance,
          isRequired: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Government duty is required';
            }
            final duty = double.tryParse(value);
            if (duty == null || duty < 0) {
              return 'Enter valid government duty amount';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildAdditionalInfoSection(bool isMobile) {
    return _buildSection(
      title: 'Additional Information',
      icon: Icons.info,
      color: AppColors.charcoalGray,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildEnhancedTextField(
                controller: _barcodeController,
                label: 'Barcode',
                hint: '1234567890123',
                icon: Icons.qr_code,
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildEnhancedTextField(
                controller: _hsnCodeController,
                label: 'HSN Code',
                hint: '22081010',
                icon: Icons.numbers,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _buildEnhancedTextField(
                controller: _sortOrderController,
                label: 'Sort Order',
                hint: '0',
                icon: Icons.sort,
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value != null && value.isNotEmpty) {
                    final sortOrder = int.tryParse(value);
                    if (sortOrder == null || sortOrder < 0) {
                      return 'Enter valid sort order';
                    }
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: _buildStatusToggle(),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  color.withOpacity(0.05),
                  color.withOpacity(0.1),
                ],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  Widget _buildEnhancedTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool isRequired = false,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            text: label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.charcoalGray,
            ),
            children: isRequired
                ? [
                    const TextSpan(
                      text: ' *',
                      style: TextStyle(color: AppColors.error),
                    ),
                  ]
                : null,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: AppColors.mediumGray.withOpacity(0.7),
              fontSize: 14,
            ),
            prefixIcon: Icon(
              icon,
              color: AppColors.primaryRed.withOpacity(0.7),
              size: 20,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: AppColors.borderGray,
                width: 1.5,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: AppColors.borderGray.withOpacity(0.3),
                width: 1.5,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppColors.primaryRed,
                width: 2,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppColors.error,
                width: 2,
              ),
            ),
            filled: true,
            fillColor: Colors.grey.shade50,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
          maxLines: maxLines,
          // Aggressive anti-Hindi suggestion settings
          keyboardType: TextInputType.visiblePassword,
          autocorrect: false,
          enableSuggestions: false,
          enableInteractiveSelection: true,
          autofillHints: const <String>[],
          textCapitalization: TextCapitalization.none,
          smartDashesType: SmartDashesType.disabled,
          smartQuotesType: SmartQuotesType.disabled,
          validator: validator,
        ),
      ],
    );
  }

  Widget _buildCategoryDropdowns() {
    return Consumer<BrandProvider>(
      builder: (context, provider, child) {
        // Filter subcategories based on local selected category
        final filteredSubcategories = _selectedCategoryId != null
            ? provider.subcategories
                .where((sub) => sub.categoryId == _selectedCategoryId)
                .toList()
            : provider.subcategories;

        // Validate that selected category exists in the list
        final categoryExists = _selectedCategoryId != null &&
            provider.categories.any((cat) => cat.id == _selectedCategoryId);

        // Validate that selected subcategory exists in the filtered list
        final subcategoryExists = _selectedSubcategoryId != null &&
            filteredSubcategories.any((sub) => sub.id == _selectedSubcategoryId);

        return Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Category',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.charcoalGray,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: categoryExists ? _selectedCategoryId : null,
                    isExpanded: true,
                    decoration: InputDecoration(
                      hintText: 'Select category',
                      prefixIcon: Icon(
                        Icons.category,
                        color: AppColors.primaryRed.withOpacity(0.7),
                        size: 20,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: AppColors.borderGray.withOpacity(0.3),
                        ),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    items: provider.categories.map((category) {
                      return DropdownMenuItem(
                        value: category.id,
                        child: Text(
                          category.name,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedCategoryId = value;
                        _selectedSubcategoryId = null; // Reset subcategory
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Subcategory',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.charcoalGray,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: subcategoryExists ? _selectedSubcategoryId : null,
                    isExpanded: true,
                    decoration: InputDecoration(
                      hintText: 'Select subcategory',
                      prefixIcon: Icon(
                        Icons.subdirectory_arrow_right,
                        color: AppColors.primaryRed.withOpacity(0.7),
                        size: 20,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: AppColors.borderGray.withOpacity(0.3),
                        ),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    items: filteredSubcategories.map((subcategory) {
                      return DropdownMenuItem(
                        value: subcategory.id,
                        child: Text(
                          subcategory.name,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      );
                    }).toList(),
                    onChanged: _selectedCategoryId != null
                        ? (value) {
                            setState(() {
                              _selectedSubcategoryId = value;
                            });
                          }
                        : null,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildImageUploadSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Variant Image',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.charcoalGray,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _pictureController,
          decoration: InputDecoration(
            hintText: 'https://example.com/variant-image.jpg',
            hintStyle: TextStyle(
              color: AppColors.mediumGray.withOpacity(0.7),
              fontSize: 14,
            ),
            prefixIcon: Icon(
              Icons.image,
              color: AppColors.primaryRed.withOpacity(0.7),
              size: 20,
            ),
            suffixIcon: _pictureController.text.isNotEmpty
                ? IconButton(
                    onPressed: _showImagePreview,
                    icon: const Icon(
                      Icons.preview,
                      color: AppColors.primaryRed,
                    ),
                    tooltip: 'Preview Image',
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: AppColors.borderGray,
                width: 1.5,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: AppColors.borderGray.withOpacity(0.3),
                width: 1.5,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppColors.primaryRed,
                width: 2,
              ),
            ),
            filled: true,
            fillColor: Colors.grey.shade50,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
          // Aggressive anti-Hindi suggestion settings
          keyboardType: TextInputType.visiblePassword,
          autocorrect: false,
          enableSuggestions: false,
          enableInteractiveSelection: true,
          autofillHints: const <String>[],
          textCapitalization: TextCapitalization.none,
          smartDashesType: SmartDashesType.disabled,
          smartQuotesType: SmartQuotesType.disabled,
          validator: (value) {
            if (value != null && value.isNotEmpty) {
              final uri = Uri.tryParse(value);
              if (uri == null || !uri.hasScheme) {
                return 'Please enter a valid URL';
              }
            }
            return null;
          },
          onChanged: (value) => setState(() {}),
        ),
        if (_pictureController.text.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            height: 120,
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.borderGray.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(12),
              color: Colors.grey.shade50,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                _pictureController.text,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.primaryRed,
                      strokeWidth: 2,
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.broken_image,
                          color: AppColors.mediumGray,
                          size: 32,
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Failed to load image',
                          style: TextStyle(
                            color: AppColors.mediumGray,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStatusToggle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Status',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.charcoalGray,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(
              color: _isActive
                  ? AppColors.success.withOpacity(0.3)
                  : AppColors.error.withOpacity(0.3),
            ),
            borderRadius: BorderRadius.circular(12),
            color: _isActive
                ? AppColors.success.withOpacity(0.05)
                : AppColors.error.withOpacity(0.05),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _isActive ? AppColors.success : AppColors.error,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _isActive ? Icons.check_circle : Icons.cancel,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _isActive ? 'Active' : 'Inactive',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _isActive ? AppColors.success : AppColors.error,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Switch.adaptive(
                  key: ValueKey(_isActive),
                  value: _isActive,
                  onChanged: (value) => setState(() => _isActive = value),
                  activeColor: AppColors.success,
                  activeTrackColor: AppColors.success.withOpacity(0.3),
                  inactiveThumbColor: AppColors.error,
                  inactiveTrackColor: AppColors.error.withOpacity(0.3),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEnhancedActionButtons(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Consumer<BrandProvider>(
        builder: (context, brandProvider, child) {
          final isLoading = brandProvider.isCreating;

          return Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: isLoading ? null : () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: AppColors.mediumGray),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  child: ElevatedButton(
                    onPressed: isLoading ? null : () => _saveVariant(brandProvider),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryRed,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: isLoading ? 0 : 2,
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _isEditing ? Icons.update : Icons.add,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    _isEditing ? 'Update Variant' : 'Add Variant',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showImagePreview() {
    if (_pictureController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter an image URL first'),
          backgroundColor: AppColors.primaryRed,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Variant Image Preview'),
        content: SizedBox(
          width: 300,
          height: 300,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              _pictureController.text,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return const Center(
                  child: CircularProgressIndicator(color: AppColors.primaryRed),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.broken_image, color: AppColors.error, size: 64),
                      SizedBox(height: 16),
                      Text('Failed to load image'),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _saveVariant(BrandProvider brandProvider) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final variantRequest = CreateBrandVariantRequest(
        brandId: widget.brand.id,
        size: _sizeController.text.trim(),
        description: _descriptionController.text.trim(),
        picture: _pictureController.text.trim(),
        alcoholContent: double.tryParse(_alcoholContentController.text) ?? 0.0,
        mrp: double.tryParse(_mrpController.text) ?? 0.0,
        sellingPrice: double.tryParse(_sellingPriceController.text) ?? 0.0,
        buyingPrice: double.tryParse(_buyingPriceController.text) ?? 0.0,
        governmentDuty: double.tryParse(_governmentDutyController.text) ?? 0.0,
        barcode: _barcodeController.text.trim(),
        hsnCode: _hsnCodeController.text.trim(),
        sortOrder: int.tryParse(_sortOrderController.text) ?? 0,
        isActive: _isActive,
        categoryId: _selectedCategoryId ?? '',
        // Pass null instead of empty string for optional subcategoryId
        subcategoryId: (_selectedSubcategoryId == null || _selectedSubcategoryId!.isEmpty)
            ? null
            : _selectedSubcategoryId,
      );

      bool success;
      if (_isEditing) {
        success = await brandProvider.updateBrandVariant(widget.variant!.id, variantRequest);
      } else {
        success = await brandProvider.createBrandVariant(variantRequest);
      }

      if (success && mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _isEditing
                        ? 'Variant "${_sizeController.text}" updated successfully'
                        : 'Variant "${_sizeController.text}" added successfully',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Error: ${e.toString()}'),
                ),
              ],
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}