import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Utility class for standardizing text input behavior across the app
/// Prevents Hindi/auto-suggestions and auto-correction issues
class TextInputUtils {

  /// Convert problematic keyboard types to safe alternatives that don't trigger Hindi conversion
  static TextInputType _getSafeKeyboardType(TextInputType? keyboardType) {
    if (keyboardType == null) return TextInputType.text;

    // Convert problematic types to visiblePassword to prevent auto-suggestions
    switch (keyboardType) {
      case TextInputType.number:
      case TextInputType.phone:
        return TextInputType.visiblePassword;
      default:
        return keyboardType;
    }
  }

  /// Standard text input configuration to prevent Hindi suggestions
  /// and auto-correction issues
  static InputDecoration getStandardDecoration({
    String? hintText,
    String? labelText,
    Widget? prefixIcon,
    Widget? suffixIcon,
    bool filled = true,
    Color? fillColor,
    EdgeInsets? contentPadding,
    OutlineInputBorder? border,
    OutlineInputBorder? enabledBorder,
    OutlineInputBorder? focusedBorder,
    TextStyle? hintStyle,
    TextStyle? labelStyle,
  }) {
    return InputDecoration(
      hintText: hintText,
      labelText: labelText,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      filled: filled,
      fillColor: fillColor,
      contentPadding: contentPadding,
      border: border,
      enabledBorder: enabledBorder,
      focusedBorder: focusedBorder,
      hintStyle: hintStyle,
      labelStyle: labelStyle,
    );
  }

  /// Standard TextField widget with disabled auto-suggestions and auto-correction
  static Widget buildTextField({
    required TextEditingController controller,
    String? hintText,
    String? labelText,
    Widget? prefixIcon,
    Widget? suffixIcon,
    TextInputType? keyboardType,
    bool obscureText = false,
    int? maxLines = 1,
    int? maxLength,
    ValueChanged<String>? onChanged,
    VoidCallback? onTap,
    InputDecoration? decoration,
    TextStyle? style,
    bool readOnly = false,
    bool enabled = true,
    FocusNode? focusNode,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,

      // Force English-only input behavior
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: null,
      textCapitalization: TextCapitalization.none,

      keyboardType: _getSafeKeyboardType(keyboardType),
      obscureText: obscureText,
      maxLines: maxLines,
      maxLength: maxLength,
      onChanged: onChanged,
      onTap: onTap,
      style: style,
      readOnly: readOnly,
      enabled: enabled,
      focusNode: focusNode,
      inputFormatters: inputFormatters,

      decoration: decoration ?? getStandardDecoration(
        hintText: hintText,
        labelText: labelText,
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
      ),
    );
  }

  /// Standard TextFormField widget with disabled auto-suggestions and auto-correction
  static Widget buildTextFormField({
    required TextEditingController controller,
    String? hintText,
    String? labelText,
    Widget? prefixIcon,
    Widget? suffixIcon,
    TextInputType? keyboardType,
    bool obscureText = false,
    int? maxLines = 1,
    int? maxLength,
    ValueChanged<String>? onChanged,
    VoidCallback? onTap,
    FormFieldValidator<String>? validator,
    InputDecoration? decoration,
    TextStyle? style,
    bool readOnly = false,
    bool enabled = true,
    FocusNode? focusNode,
    List<TextInputFormatter>? inputFormatters,
    AutovalidateMode? autovalidateMode,
  }) {
    return TextFormField(
      controller: controller,

      // Completely disable all forms of auto-correction and suggestions
      autocorrect: false,
      enableSuggestions: false,
      enableInteractiveSelection: true,
      autofillHints: const <String>[],  // Empty list instead of null
      textCapitalization: TextCapitalization.none,

      // Convert problematic keyboard types to safe ones to prevent Hindi number conversion
      keyboardType: _getSafeKeyboardType(keyboardType),

      obscureText: obscureText,
      maxLines: maxLines,
      maxLength: maxLength,
      onChanged: onChanged,
      onTap: onTap,
      validator: validator,
      style: style,
      readOnly: readOnly,
      enabled: enabled,
      focusNode: focusNode,
      inputFormatters: inputFormatters,
      autovalidateMode: autovalidateMode,

      decoration: decoration ?? getStandardDecoration(
        hintText: hintText,
        labelText: labelText,
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
      ),
    );
  }

  /// Numeric input formatters for numbers only
  static List<TextInputFormatter> get numericInputFormatters => [
    FilteringTextInputFormatter.digitsOnly,
  ];

  /// Decimal input formatters for decimal numbers
  static List<TextInputFormatter> get decimalInputFormatters => [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
  ];

  /// Alphanumeric input formatters (English letters and numbers only)
  static List<TextInputFormatter> get alphanumericInputFormatters => [
    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\s]')),
  ];

  /// English letters only input formatters
  static List<TextInputFormatter> get englishOnlyInputFormatters => [
    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
  ];

  /// Email input formatters
  static List<TextInputFormatter> get emailInputFormatters => [
    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9@._-]')),
  ];

  /// TextFormField specifically for text input with aggressive anti-Hindi settings
  static Widget buildTextFormFieldNoPredictive({
    required TextEditingController controller,
    String? hintText,
    String? labelText,
    Widget? prefixIcon,
    Widget? suffixIcon,
    bool obscureText = false,
    int? maxLines = 1,
    int? maxLength,
    ValueChanged<String>? onChanged,
    VoidCallback? onTap,
    FormFieldValidator<String>? validator,
    InputDecoration? decoration,
    TextStyle? style,
    bool readOnly = false,
    bool enabled = true,
    FocusNode? focusNode,
    List<TextInputFormatter>? inputFormatters,
    AutovalidateMode? autovalidateMode,
  }) {
    return TextFormField(
      controller: controller,

      // Extremely aggressive anti-suggestion settings
      autocorrect: false,
      enableSuggestions: false,
      enableInteractiveSelection: true,
      autofillHints: const <String>[],
      textCapitalization: TextCapitalization.none,
      smartDashesType: SmartDashesType.disabled,
      smartQuotesType: SmartQuotesType.disabled,

      // Use visiblePassword keyboard type to disable all predictive text
      keyboardType: TextInputType.visiblePassword,

      obscureText: obscureText,
      maxLines: maxLines,
      maxLength: maxLength,
      onChanged: onChanged,
      onTap: onTap,
      validator: validator,
      style: style,
      readOnly: readOnly,
      enabled: enabled,
      focusNode: focusNode,
      inputFormatters: inputFormatters ?? alphanumericInputFormatters,
      autovalidateMode: autovalidateMode,

      decoration: decoration ?? getStandardDecoration(
        hintText: hintText,
        labelText: labelText,
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
      ),
    );
  }
}