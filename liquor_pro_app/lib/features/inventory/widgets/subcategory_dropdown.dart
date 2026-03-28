import 'package:flutter/material.dart';
import '../models/brand_metadata.dart';

/// Subcategory Dropdown - For selecting subcategory (filtered by category)
class SubcategoryDropdown extends StatelessWidget {
  final String? selectedSubcategoryId;
  final List<SubcategoryDetail> subcategories;
  final ValueChanged<String?>? onChanged;
  final bool enabled;

  const SubcategoryDropdown({
    super.key,
    this.selectedSubcategoryId,
    required this.subcategories,
    this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DropdownButtonFormField<String>(
      initialValue: selectedSubcategoryId,
      decoration: InputDecoration(
        labelText: 'Subcategory (Optional)',
        prefixIcon: const Icon(Icons.list),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        filled: true,
        fillColor: enabled ? cs.surfaceContainerHighest : cs.surfaceContainerLow,
        helperText: enabled ? null : 'Select a category first',
      ),
      items: subcategories.isEmpty
          ? null
          : subcategories.map((subcat) {
              return DropdownMenuItem<String>(
                value: subcat.id,
                child: Text(
                  subcat.name,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
      onChanged: enabled && subcategories.isNotEmpty ? onChanged : null,
      isExpanded: true,
    );
  }
}
