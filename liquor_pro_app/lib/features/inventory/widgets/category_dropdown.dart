import 'package:flutter/material.dart';
import '../models/brand_metadata.dart';

/// Category Dropdown - For selecting category with icon
class CategoryDropdown extends StatelessWidget {
  final String? selectedCategoryId;
  final List<CategoryDetail> categories;
  final ValueChanged<String?>? onChanged;
  final bool enabled;

  const CategoryDropdown({
    super.key,
    this.selectedCategoryId,
    required this.categories,
    this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DropdownButtonFormField<String>(
      initialValue: selectedCategoryId,
      decoration: InputDecoration(
        labelText: 'Category *',
        prefixIcon: const Icon(Icons.category),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        filled: true,
        fillColor: cs.surfaceContainerHighest,
      ),
      items: categories.map((category) {
        return DropdownMenuItem<String>(
          value: category.id,
          child: Row(
            children: [
              Text(
                category.icon ?? '📦',
                style: const TextStyle(fontSize: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  category.name,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      }).toList(),
      onChanged: enabled ? onChanged : null,
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please select a category';
        }
        return null;
      },
      isExpanded: true,
    );
  }
}
