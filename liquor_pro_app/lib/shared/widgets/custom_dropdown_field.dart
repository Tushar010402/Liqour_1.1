import 'package:flutter/material.dart';

/// Custom Dropdown Field Widget
class CustomDropdownField<T> extends StatelessWidget {
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final String label;
  final ValueChanged<T?>? onChanged;
  final String? Function(T?)? validator;
  final String? hint;
  final bool enabled;

  const CustomDropdownField({
    Key? key,
    required this.value,
    required this.items,
    required this.label,
    this.onChanged,
    this.validator,
    this.hint,
    this.enabled = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      items: items,
      onChanged: enabled ? onChanged : null,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        filled: true,
        fillColor: enabled ? null : Colors.grey[100],
      ),
      isExpanded: true,
    );
  }
}
