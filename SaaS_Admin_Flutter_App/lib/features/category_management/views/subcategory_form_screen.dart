import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/category_model.dart';
import '../../../core/utils/text_input_utils.dart';
import '../controllers/category_provider.dart';

class SubcategoryFormScreen extends StatefulWidget {
  final Subcategory? subcategory;

  const SubcategoryFormScreen({super.key, this.subcategory});

  @override
  State<SubcategoryFormScreen> createState() => _SubcategoryFormScreenState();
}

class _SubcategoryFormScreenState extends State<SubcategoryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _pictureController = TextEditingController();
  final _sortOrderController = TextEditingController(text: '0');

  bool _isActive = true;
  bool _isLoading = false;
  String? _selectedCategoryId;

  bool get _isEditing => widget.subcategory != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _populateFields();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<CategoryProvider>();
      if (provider.categories.isEmpty) {
        provider.loadCategories();
      }
    });
  }

  void _populateFields() {
    final subcategory = widget.subcategory!;
    _nameController.text = subcategory.name;
    _descriptionController.text = subcategory.description;
    _pictureController.text = subcategory.picture ?? '';
    _sortOrderController.text = subcategory.sortOrder.toString();
    _selectedCategoryId = subcategory.categoryId;
    _isActive = subcategory.isActive;
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
        title: Text(_isEditing ? 'Edit Subcategory' : 'Create Subcategory'),
        actions: [
          if (_isEditing)
            IconButton(
              onPressed: _showDeleteConfirmation,
              icon: const Icon(Icons.delete, color: AppColors.error),
              tooltip: 'Delete Subcategory',
            ),
        ],
      ),
      body: Consumer<CategoryProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.categories.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          return Form(
            key: _formKey,
            child: Column(
              children: [
                if (provider.errorMessage != null) _buildErrorBanner(provider),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildCategorySelectionCard(provider),
                        const SizedBox(height: 16),
                        _buildSubcategoryDetailsCard(),
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

  Widget _buildCategorySelectionCard(CategoryProvider provider) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.category, color: AppColors.primaryRed),
                const SizedBox(width: 8),
                const Text(
                  'Parent Category',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedCategoryId,
              decoration: InputDecoration(
                labelText: 'Select Parent Category *',
                prefixIcon: const Icon(Icons.category_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              ),
              hint: const Text('Choose a parent category'),
              isExpanded: true,
              items: provider.categories
                  .where((category) => category.isActive)
                  .map((category) => DropdownMenuItem<String>(
                        value: category.id,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.category, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                category.name,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                      ))
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedCategoryId = value;
                });
              },
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please select a parent category';
                }
                return null;
              },
            ),
            if (_selectedCategoryId != null) ...[
              const SizedBox(height: 12),
              _buildSelectedCategoryInfo(provider),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedCategoryInfo(CategoryProvider provider) {
    final category = provider.getCategoryById(_selectedCategoryId!);
    if (category == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primaryRed.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primaryRed.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.category, size: 32, color: AppColors.primaryRed),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryRed,
                  ),
                ),
                if (category.description.isNotEmpty)
                  Text(
                    category.description,
                    style: const TextStyle(
                      color: AppColors.mediumGray,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Chip(
            label: Text('${category.subcategories.length} subs'),
            backgroundColor: AppColors.lightRed,
            labelStyle: const TextStyle(
              color: AppColors.darkRed,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubcategoryDetailsCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.subdirectory_arrow_right,
                    color: AppColors.primaryRed),
                SizedBox(width: 8),
                Text(
                  'Subcategory Details',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextInputUtils.buildTextFormField(
              controller: _nameController,
              labelText: 'Subcategory Name *',
              hintText: 'Enter subcategory name',
              prefixIcon: const Icon(Icons.label),
              inputFormatters: TextInputUtils.englishOnlyInputFormatters,
              decoration: InputDecoration(
                labelText: 'Subcategory Name *',
                hintText: 'Enter subcategory name',
                prefixIcon: const Icon(Icons.label),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Subcategory name is required';
                }
                if (value.trim().length < 2) {
                  return 'Name must be at least 2 characters long';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextInputUtils.buildTextFormField(
              controller: _descriptionController,
              labelText: 'Description',
              hintText: 'Enter subcategory description',
              prefixIcon: const Icon(Icons.description),
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Description',
                hintText: 'Enter subcategory description',
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
            const SizedBox(height: 16),
            TextInputUtils.buildTextFormField(
              controller: _pictureController,
              labelText: 'Picture URL (Optional)',
              hintText: 'https://example.com/image.jpg',
              prefixIcon: const Icon(Icons.link),
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: 'Picture URL (Optional)',
                hintText: 'https://example.com/image.jpg',
                prefixIcon: const Icon(Icons.link),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Status',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.borderGray),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _isActive ? 'Active' : 'Inactive',
                              style: TextStyle(
                                color: _isActive
                                    ? AppColors.success
                                    : AppColors.mediumGray,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Switch(
                              value: _isActive,
                              onChanged: (value) =>
                                  setState(() => _isActive = value),
                              activeThumbColor: AppColors.success,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(CategoryProvider provider) {
    return Container(
      padding: const EdgeInsets.all(16),
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
              onPressed: _isLoading ? null : () => _saveSubcategory(provider),
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
                  : Text(
                      _isEditing ? 'Update Subcategory' : 'Create Subcategory'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveSubcategory(CategoryProvider provider) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a parent category'),
          backgroundColor: AppColors.error,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      print(
          'DEBUG: SubcategoryForm - Saving subcategory - isEditing: $_isEditing');
      final request = CreateSubcategoryRequest(
        categoryId: _selectedCategoryId!,
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        picture: _pictureController.text.trim().isEmpty
            ? null
            : _pictureController.text.trim(),
        isActive: _isActive,
        sortOrder: int.tryParse(_sortOrderController.text.trim()) ?? 0,
      );

      print('DEBUG: SubcategoryForm - Request: ${request.toJson()}');

      bool success;
      if (_isEditing) {
        print(
            'DEBUG: SubcategoryForm - Updating subcategory with ID: ${widget.subcategory!.id}');
        success =
            await provider.updateSubcategory(widget.subcategory!.id, request);
      } else {
        print('DEBUG: SubcategoryForm - Creating new subcategory');
        success = await provider.createSubcategory(request);
      }

      print('DEBUG: SubcategoryForm - Operation success: $success');

      if (success && mounted) {
        Navigator.of(context).pop();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _isEditing
                    ? 'Subcategory updated successfully'
                    : 'Subcategory created successfully',
              ),
              backgroundColor: AppColors.success,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else if (mounted && !success) {
        String errorMessage = provider.errorMessage ?? 'Unknown error occurred';
        print('DEBUG: SubcategoryForm - Error: $errorMessage');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to ${_isEditing ? 'update' : 'create'} subcategory: $errorMessage',
            ),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Retry',
              textColor: AppColors.white,
              onPressed: () => _saveSubcategory(provider),
            ),
          ),
        );
      }
    } catch (e) {
      print('DEBUG: SubcategoryForm - Exception: $e');
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
            Text('Delete Subcategory'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${widget.subcategory!.name}"? This action cannot be undone.',
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
                  'DEBUG: SubcategoryForm - Deleting subcategory: ${widget.subcategory!.id}');
              final provider = context.read<CategoryProvider>();
              final success =
                  await provider.deleteSubcategory(widget.subcategory!.id);

              print('DEBUG: SubcategoryForm - Delete result: $success');

              if (success && mounted) {
                if (mounted) Navigator.of(context).pop(); // Close form screen
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Subcategory "${widget.subcategory!.name}" deleted successfully'),
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
                      'Failed to delete subcategory: ${provider.errorMessage ?? 'Unknown error'}',
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
