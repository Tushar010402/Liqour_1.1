import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Text Input Utilities
/// Provides reusable text input formatters and builders
class TextInputUtils {
  /// Input formatters for alphanumeric text (letters, numbers, spaces)
  /// Disables autocorrect and suggestions
  static final List<TextInputFormatter> alphanumericInputFormatters = [
    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\s\-_.,]')),
  ];

  /// Input formatters for decimal numbers
  /// Allows digits and decimal point
  static final List<TextInputFormatter> decimalInputFormatters = [
    FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
  ];

  /// Input formatters for integer numbers only
  static final List<TextInputFormatter> integerInputFormatters = [
    FilteringTextInputFormatter.digitsOnly,
  ];

  /// Build a TextFormField without predictive text/autocorrect
  /// Useful for product names, brand names, etc.
  static Widget buildTextFormFieldNoPredictive({
    required TextEditingController controller,
    required String labelText,
    String? hintText,
    InputDecoration? decoration,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    int maxLines = 1,
    TextInputType? keyboardType,
    bool enabled = true,
    void Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      decoration: decoration ??
          InputDecoration(
            labelText: labelText,
            hintText: hintText,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
      inputFormatters: inputFormatters,
      validator: validator,
      maxLines: maxLines,
      keyboardType: keyboardType,
      enabled: enabled,
      onChanged: onChanged,
      // Disable autocorrect and suggestions
      autocorrect: false,
      enableSuggestions: false,
      enableInteractiveSelection: true,
    );
  }
}
