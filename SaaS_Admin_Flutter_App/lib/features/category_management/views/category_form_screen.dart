import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/category_model.dart';
import '../../../core/utils/text_input_utils.dart';
import '../controllers/category_provider.dart';

class CategoryFormScreen extends StatefulWidget {
  final Category? category;

  const CategoryFormScreen({super.key, this.category});

  @override
  State<CategoryFormScreen> createState() => _CategoryFormScreenState();
}

class _CategoryFormScreenState extends State<CategoryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _pictureController = TextEditingController();
  final _sortOrderController = TextEditingController();

  bool _isActive = true;
  bool _isLoading = false;

  bool get _isEditing => widget.category != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _populateFields();
    }
  }

  void _populateFields() {
    final category = widget.category!;
    _nameController.text = category.name;
    _descriptionController.text = category.description;
    _pictureController.text = category.picture ?? '';
    _sortOrderController.text = category.sortOrder.toString();
    _isActive = category.isActive;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _pictureController.dispose();
    _sortOrderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGray,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.primaryBlack,
        title: Text(_isEditing ? 'Edit Category' : 'Create New Category'),
        actions: [
          if (_isEditing)
            IconButton(
              onPressed: _showDeleteConfirmation,
              icon: const Icon(Icons.delete, color: AppColors.error),
              tooltip: 'Delete Category',
            ),
        ],
      ),
      body: Consumer<CategoryProvider>(
        builder: (context, provider, child) {
          return Form(
            key: _formKey,
            child: Column(
              children: [
                if (provider.errorMessage != null) _buildErrorBanner(provider),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildMainInfoSection(),
                        const SizedBox(height: 32),
                        _buildDisplaySection(),
                        const SizedBox(height: 32),
                        _buildSettingsSection(),
                      ],
                    ),
                  ),
                ),
                _buildActionButtons(provider),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildErrorBanner(CategoryProvider provider) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: AppColors.error.withValues(alpha: 0.1),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              provider.errorMessage!,
              style: const TextStyle(color: AppColors.error),
            ),
          ),
          TextButton(
            onPressed: () => provider.clearError(),
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }

  Widget _buildMainInfoSection() {
    return _buildSection(
      title: 'Basic Information',
      icon: Icons.info_outline,
      children: [
        TextInputUtils.buildTextFormField(
          controller: _nameController,
          labelText: 'Category Name *',
          hintText: 'Enter category name',
          prefixIcon: const Icon(Icons.category),
          inputFormatters: TextInputUtils.englishOnlyInputFormatters,
          decoration: InputDecoration(
            labelText: 'Category Name *',
            hintText: 'Enter category name',
            prefixIcon: const Icon(Icons.category),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Category name is required';
            }
            if (value.trim().length < 2) {
              return 'Category name must be at least 2 characters long';
            }
            if (value.trim().length > 100) {
              return 'Category name cannot exceed 100 characters';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        TextInputUtils.buildTextFormField(
          controller: _descriptionController,
          labelText: 'Description',
          hintText: 'Enter category description',
          prefixIcon: const Icon(Icons.description),
          maxLines: 3,
          decoration: InputDecoration(
            labelText: 'Description',
            hintText: 'Enter category description',
            prefixIcon: const Icon(Icons.description),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          validator: (value) {
            if (value != null && value.length > 500) {
              return 'Description cannot exceed 500 characters';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildDisplaySection() {
    return _buildSection(
      title: 'Display & Media',
      icon: Icons.image,
      children: [
        TextInputUtils.buildTextFormField(
          controller: _pictureController,
          labelText: 'Picture URL',
          hintText: 'https://example.com/category-image.jpg',
          prefixIcon: const Icon(Icons.link),
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: 'Picture URL',
            hintText: 'https://example.com/category-image.jpg',
            prefixIcon: const Icon(Icons.link),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            suffixIcon: IconButton(
              onPressed: _showImagePreview,
              icon: const Icon(Icons.preview),
              tooltip: 'Preview Image',
            ),
          ),
          validator: (value) {
            if (value != null && value.isNotEmpty) {
              final uri = Uri.tryParse(value);
              if (uri == null || !uri.hasScheme) {
                return 'Please enter a valid URL';
              }
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        if (_pictureController.text.isNotEmpty) _buildImagePreview(),
      ],
    );
  }

  Widget _buildImagePreview() {
    return Container(
      height: 120,
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.borderGray),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          _pictureController.text,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return const Center(child: CircularProgressIndicator());
          },
          errorBuilder: (context, error, stackTrace) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.broken_image, color: AppColors.mediumGray),
                  SizedBox(height: 8),
                  Text(
                    'Failed to load image',
                    style: TextStyle(color: AppColors.mediumGray, fontSize: 12),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSettingsSection() {
    return _buildSection(
      title: 'Settings',
      icon: Icons.settings,
      children: [
        Row(
          children: [
            Expanded(
              child: TextInputUtils.buildTextFormField(
                controller: _sortOrderController,
                labelText: 'Sort Order',
                hintText: '0',
                prefixIcon: const Icon(Icons.sort),
                keyboardType: TextInputType.number,
                inputFormatters: TextInputUtils.numericInputFormatters,
                decoration: InputDecoration(
                  labelText: 'Sort Order',
                  hintText: '0',
                  prefixIcon: const Icon(Icons.sort),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  helperText: 'Lower numbers appear first',
                ),
                validator: (value) {
                  if (value != null && value.isNotEmpty) {
                    final sortOrder = int.tryParse(value);
                    if (sortOrder == null) {
                      return 'Please enter a valid number';
                    }
                    if (sortOrder < 0) {
                      return 'Sort order cannot be negative';
                    }
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.borderGray),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.visibility),
                    const SizedBox(width: 8),
                    const Text('Status:'),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Switch(
                            value: _isActive,
                            onChanged: (value) =>
                                setState(() => _isActive = value),
                            activeThumbColor: AppColors.success,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                          Text(
                            _isActive ? 'Active' : 'Inactive',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: _isActive
                                          ? AppColors.success
                                          : AppColors.mediumGray,
                                      fontWeight: FontWeight.w500,
                                    ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primaryRed),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryBlack,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildActionButtons(CategoryProvider provider) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(
          top: BorderSide(color: AppColors.borderGray, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton(
              onPressed: _isLoading ? null : () => _saveCategory(provider),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryRed,
                foregroundColor: AppColors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(AppColors.white),
                      ),
                    )
                  : Text(_isEditing ? 'Update Category' : 'Create Category'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveCategory(CategoryProvider provider) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      print('DEBUG: CategoryForm - Saving category - isEditing: $_isEditing');
      final request = CreateCategoryRequest(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        picture: _pictureController.text.trim().isEmpty
            ? null
            : _pictureController.text.trim(),
        isActive: _isActive,
        sortOrder: int.tryParse(_sortOrderController.text.trim()) ?? 0,
      );

      print('DEBUG: CategoryForm - Request: ${request.toJson()}');

      bool success;
      if (_isEditing) {
        print(
            'DEBUG: CategoryForm - Updating category with ID: ${widget.category!.id}');
        success = await provider.updateCategory(widget.category!.id, request);
      } else {
        print('DEBUG: CategoryForm - Creating new category');
        success = await provider.createCategory(request);
      }

      print('DEBUG: CategoryForm - Operation success: $success');

      if (success) {
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _isEditing
                    ? 'Category updated successfully'
                    : 'Category created successfully',
              ),
              backgroundColor: AppColors.success,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        // Enhanced error handling
        if (mounted) {
          String errorMessage =
              provider.errorMessage ?? 'Unknown error occurred';
          print('DEBUG: CategoryForm - Error: $errorMessage');

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Failed to ${_isEditing ? 'update' : 'create'} category: $errorMessage',
              ),
              backgroundColor: AppColors.error,
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                label: 'Retry',
                textColor: AppColors.white,
                onPressed: () => _saveCategory(provider),
              ),
            ),
          );
        }
      }
    } catch (e) {
      print('DEBUG: CategoryForm - Exception: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('An unexpected error occurred: ${e.toString()}'),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showImagePreview() {
    if (_pictureController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an image URL first')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                title: const Text('Image Preview'),
                backgroundColor: AppColors.primaryRed,
                foregroundColor: AppColors.white,
                automaticallyImplyLeading: false,
                actions: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  child: Image.network(
                    _pictureController.text.trim(),
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.broken_image,
                                size: 64, color: AppColors.mediumGray),
                            SizedBox(height: 16),
                            Text(
                              'Failed to load image',
                              style: TextStyle(color: AppColors.mediumGray),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteConfirmation() {
    if (!_isEditing) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning, color: AppColors.error),
            SizedBox(width: 12),
            Text('Delete Category'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${widget.category!.name}"? This action cannot be undone and will also delete all associated subcategories.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop(); // Close dialog

              print(
                  'DEBUG: CategoryForm - Deleting category: ${widget.category!.id}');
              final provider = context.read<CategoryProvider>();
              final success =
                  await provider.deleteCategory(widget.category!.id);

              print('DEBUG: CategoryForm - Delete result: $success');

              if (success && mounted) {
                if (mounted) Navigator.of(context).pop(); // Close form screen
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Category "${widget.category!.name}" deleted successfully'),
                      backgroundColor: AppColors.success,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              } else if (mounted && !success) {
                // Show error message if deletion failed
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Failed to delete category: ${provider.errorMessage ?? 'Unknown error'}',
                    ),
                    backgroundColor: AppColors.error,
                    duration: const Duration(seconds: 4),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
