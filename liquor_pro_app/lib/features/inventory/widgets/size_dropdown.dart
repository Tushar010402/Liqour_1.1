import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../models/brand_metadata.dart';

/// Size Dropdown - For selecting bottle size with common sizes highlighted
class SizeDropdown extends StatelessWidget {
  final String? selectedSize;
  final List<SizeOption> sizes;
  final ValueChanged<String?>? onChanged;
  final bool enabled;

  const SizeDropdown({
    super.key,
    this.selectedSize,
    required this.sizes,
    this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Separate common and uncommon sizes
    final commonSizes = sizes.where((s) => s.isCommon).toList();
    final otherSizes = sizes.where((s) => !s.isCommon).toList();

    return DropdownButtonFormField<String>(
      initialValue: selectedSize,
      decoration: InputDecoration(
        labelText: 'Size *',
        prefixIcon: const Icon(Icons.straighten),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        filled: true,
        fillColor: cs.surfaceContainerHighest,
        helperText: 'Common sizes are marked with ⭐',
      ),
      items: [
        // Common sizes first (with star)
        ...commonSizes.map((size) {
          return DropdownMenuItem<String>(
            value: size.value,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    size.label,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.star,
                  size: 16,
                  color: AppColors.warning,
                ),
              ],
            ),
          );
        }),

        // Divider between common and other sizes
        if (otherSizes.isNotEmpty)
          const DropdownMenuItem<String>(
            enabled: false,
            value: null,
            child: Divider(),
          ),

        // Other sizes
        ...otherSizes.map((size) {
          return DropdownMenuItem<String>(
            value: size.value,
            child: Text(
              size.label,
              overflow: TextOverflow.ellipsis,
            ),
          );
        }),
      ],
      onChanged: enabled ? onChanged : null,
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please select a size';
        }
        return null;
      },
      isExpanded: true,
    );
  }
}
