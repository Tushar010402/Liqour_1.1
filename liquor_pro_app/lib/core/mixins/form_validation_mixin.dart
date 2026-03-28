import 'package:flutter/services.dart';

/// Form Validation Mixin - Modern best practices for form validation
/// Provides reusable validators, input formatters, and helpers
mixin FormValidationMixin {
  /// Email validation
  String? validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Email is required';
    }

    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );

    if (!emailRegex.hasMatch(value)) {
      return 'Please enter a valid email address';
    }

    return null;
  }

  /// Phone number validation (Indian format)
  String? validatePhone(String? value) {
    if (value == null || value.isEmpty) {
      return 'Phone number is required';
    }

    // Remove spaces, dashes, and country code
    final cleaned = value.replaceAll(RegExp(r'[\s\-\+]'), '');

    // Must be 10 digits
    if (cleaned.length != 10) {
      return 'Phone number must be 10 digits';
    }

    // Must start with 6-9
    if (!RegExp(r'^[6-9]').hasMatch(cleaned)) {
      return 'Phone number must start with 6, 7, 8, or 9';
    }

    return null;
  }

  /// Required field validation
  String? validateRequired(String? value, {String? fieldName}) {
    if (value == null || value.trim().isEmpty) {
      return '${fieldName ?? 'This field'} is required';
    }
    return null;
  }

  /// Minimum length validation
  String? validateMinLength(String? value, int minLength, {String? fieldName}) {
    if (value == null || value.isEmpty) {
      return '${fieldName ?? 'This field'} is required';
    }

    if (value.length < minLength) {
      return '${fieldName ?? 'This field'} must be at least $minLength characters';
    }

    return null;
  }

  /// Maximum length validation
  String? validateMaxLength(String? value, int maxLength, {String? fieldName}) {
    if (value != null && value.length > maxLength) {
      return '${fieldName ?? 'This field'} must not exceed $maxLength characters';
    }
    return null;
  }

  /// Number validation
  String? validateNumber(String? value, {String? fieldName}) {
    if (value == null || value.isEmpty) {
      return '${fieldName ?? 'This field'} is required';
    }

    if (double.tryParse(value) == null) {
      return 'Please enter a valid number';
    }

    return null;
  }

  /// Positive number validation
  String? validatePositiveNumber(String? value, {String? fieldName}) {
    final error = validateNumber(value, fieldName: fieldName);
    if (error != null) return error;

    final number = double.parse(value!);
    if (number <= 0) {
      return '${fieldName ?? 'This field'} must be greater than 0';
    }

    return null;
  }

  /// Price validation (supports decimals)
  String? validatePrice(String? value, {double? min, double? max}) {
    if (value == null || value.isEmpty) {
      return 'Price is required';
    }

    final price = double.tryParse(value);
    if (price == null) {
      return 'Please enter a valid price';
    }

    if (price < 0) {
      return 'Price cannot be negative';
    }

    if (min != null && price < min) {
      return 'Price must be at least ₹$min';
    }

    if (max != null && price > max) {
      return 'Price must not exceed ₹$max';
    }

    return null;
  }

  /// Quantity validation (integers only)
  String? validateQuantity(String? value, {int? min, int? max}) {
    if (value == null || value.isEmpty) {
      return 'Quantity is required';
    }

    final quantity = int.tryParse(value);
    if (quantity == null) {
      return 'Please enter a valid quantity';
    }

    if (quantity < 0) {
      return 'Quantity cannot be negative';
    }

    if (min != null && quantity < min) {
      return 'Quantity must be at least $min';
    }

    if (max != null && quantity > max) {
      return 'Quantity must not exceed $max';
    }

    return null;
  }

  /// Password validation
  String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }

    if (value.length < 6) {
      return 'Password must be at least 6 characters';
    }

    return null;
  }

  /// Confirm password validation
  String? validateConfirmPassword(String? value, String? password) {
    if (value == null || value.isEmpty) {
      return 'Please confirm your password';
    }

    if (value != password) {
      return 'Passwords do not match';
    }

    return null;
  }

  /// GST number validation (Indian GST)
  String? validateGST(String? value) {
    if (value == null || value.isEmpty) {
      return null; // Optional field
    }

    final gstRegex = RegExp(
      r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$',
    );

    if (!gstRegex.hasMatch(value)) {
      return 'Please enter a valid GST number';
    }

    return null;
  }

  /// PAN number validation (Indian PAN)
  String? validatePAN(String? value) {
    if (value == null || value.isEmpty) {
      return null; // Optional field
    }

    final panRegex = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$');

    if (!panRegex.hasMatch(value)) {
      return 'Please enter a valid PAN number';
    }

    return null;
  }

  /// Barcode validation (EAN-13)
  String? validateBarcode(String? value) {
    if (value == null || value.isEmpty) {
      return 'Barcode is required';
    }

    // Most common: 8, 12, or 13 digits
    if (!RegExp(r'^\d{8}$|^\d{12}$|^\d{13}$').hasMatch(value)) {
      return 'Barcode must be 8, 12, or 13 digits';
    }

    return null;
  }

  /// URL validation
  String? validateURL(String? value) {
    if (value == null || value.isEmpty) {
      return null; // Optional field
    }

    final urlRegex = RegExp(
      r'^https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)$',
    );

    if (!urlRegex.hasMatch(value)) {
      return 'Please enter a valid URL';
    }

    return null;
  }

  /// Combine multiple validators
  String? combineValidators(String? value, List<String? Function(String?)> validators) {
    for (final validator in validators) {
      final error = validator(value);
      if (error != null) return error;
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Input Formatters
  // ═══════════════════════════════════════════════════════════════════════════

  /// Phone number formatter (auto-formats as user types)
  List<TextInputFormatter> get phoneFormatter => [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(10),
      ];

  /// Price formatter (allows decimals)
  List<TextInputFormatter> get priceFormatter => [
        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
      ];

  /// Quantity formatter (integers only)
  List<TextInputFormatter> get quantityFormatter => [
        FilteringTextInputFormatter.digitsOnly,
      ];

  /// Uppercase formatter
  List<TextInputFormatter> get uppercaseFormatter => [
        UpperCaseTextFormatter(),
      ];

  /// Name formatter (letters and spaces only)
  List<TextInputFormatter> get nameFormatter => [
        FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
      ];

  /// GST formatter
  List<TextInputFormatter> get gstFormatter => [
        LengthLimitingTextInputFormatter(15),
        UpperCaseTextFormatter(),
      ];

  /// PAN formatter
  List<TextInputFormatter> get panFormatter => [
        LengthLimitingTextInputFormatter(10),
        UpperCaseTextFormatter(),
      ];
}

/// Custom uppercase text formatter
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

/// Decimal text formatter with precision
class DecimalTextFormatter extends TextInputFormatter {
  final int decimalPlaces;

  DecimalTextFormatter({this.decimalPlaces = 2});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    // Allow only numbers and one decimal point
    final regex = RegExp(r'^\d+\.?\d{0,' + decimalPlaces.toString() + r'}');
    final match = regex.firstMatch(newValue.text);

    if (match != null) {
      return newValue;
    }

    return oldValue;
  }
}
