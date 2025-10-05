/// Form Validators - Best Practice Input Validation
/// Centralized validation logic for consistent form validation

class Validators {
  // Private constructor to prevent instantiation
  Validators._();

  // ==================== Basic Validators ====================

  /// Required field validator
  static String? required(String? value, {String? fieldName}) {
    if (value == null || value.trim().isEmpty) {
      return '${fieldName ?? 'This field'} is required';
    }
    return null;
  }

  /// Email validator
  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required';
    }

    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );

    if (!emailRegex.hasMatch(value.trim())) {
      return 'Please enter a valid email address';
    }

    return null;
  }

  /// Phone number validator (Indian format)
  static String? phone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Phone number is required';
    }

    final phoneRegex = RegExp(r'^[6-9]\d{9}$');

    if (!phoneRegex.hasMatch(value.trim())) {
      return 'Please enter a valid 10-digit phone number';
    }

    return null;
  }

  /// Password validator
  static String? password(String? value, {int minLength = 8}) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }

    if (value.length < minLength) {
      return 'Password must be at least $minLength characters';
    }

    if (!value.contains(RegExp(r'[A-Z]'))) {
      return 'Password must contain at least one uppercase letter';
    }

    if (!value.contains(RegExp(r'[a-z]'))) {
      return 'Password must contain at least one lowercase letter';
    }

    if (!value.contains(RegExp(r'[0-9]'))) {
      return 'Password must contain at least one number';
    }

    if (!value.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) {
      return 'Password must contain at least one special character';
    }

    return null;
  }

  /// Confirm password validator
  static String? confirmPassword(String? value, String? password) {
    if (value == null || value.isEmpty) {
      return 'Please confirm your password';
    }

    if (value != password) {
      return 'Passwords do not match';
    }

    return null;
  }

  /// Name validator
  static String? name(String? value, {String? fieldName}) {
    if (value == null || value.trim().isEmpty) {
      return '${fieldName ?? 'Name'} is required';
    }

    if (value.trim().length < 2) {
      return '${fieldName ?? 'Name'} must be at least 2 characters';
    }

    return null;
  }

  // ==================== Numeric Validators ====================

  /// Number validator
  static String? number(String? value, {String? fieldName}) {
    if (value == null || value.trim().isEmpty) {
      return '${fieldName ?? 'This field'} is required';
    }

    if (double.tryParse(value.trim()) == null) {
      return 'Please enter a valid number';
    }

    return null;
  }

  /// Integer validator
  static String? integer(String? value, {String? fieldName}) {
    if (value == null || value.trim().isEmpty) {
      return '${fieldName ?? 'This field'} is required';
    }

    if (int.tryParse(value.trim()) == null) {
      return 'Please enter a valid whole number';
    }

    return null;
  }

  /// Positive number validator
  static String? positiveNumber(String? value, {String? fieldName}) {
    final numberError = number(value, fieldName: fieldName);
    if (numberError != null) return numberError;

    final numValue = double.parse(value!.trim());
    if (numValue <= 0) {
      return '${fieldName ?? 'Value'} must be greater than 0';
    }

    return null;
  }

  /// Price validator (alias for positive number)
  static String? price(String? value, {String? fieldName}) {
    return positiveNumber(value, fieldName: fieldName ?? 'Price');
  }

  /// Amount validator (currency)
  static String? amount(String? value, {double? min, double? max}) {
    if (value == null || value.trim().isEmpty) {
      return 'Amount is required';
    }

    final amount = double.tryParse(value.trim());
    if (amount == null) {
      return 'Please enter a valid amount';
    }

    if (amount < 0) {
      return 'Amount cannot be negative';
    }

    if (min != null && amount < min) {
      return 'Amount must be at least ₹$min';
    }

    if (max != null && amount > max) {
      return 'Amount cannot exceed ₹$max';
    }

    return null;
  }

  /// Quantity validator
  static String? quantity(String? value, {int? min, int? max}) {
    if (value == null || value.trim().isEmpty) {
      return 'Quantity is required';
    }

    final qty = int.tryParse(value.trim());
    if (qty == null) {
      return 'Please enter a valid quantity';
    }

    if (qty < 0) {
      return 'Quantity cannot be negative';
    }

    if (min != null && qty < min) {
      return 'Minimum quantity is $min';
    }

    if (max != null && qty > max) {
      return 'Maximum quantity is $max';
    }

    return null;
  }

  // ==================== Length Validators ====================

  /// Minimum length validator
  static String? minLength(String? value, int min, {String? fieldName}) {
    if (value == null || value.isEmpty) {
      return '${fieldName ?? 'This field'} is required';
    }

    if (value.length < min) {
      return '${fieldName ?? 'This field'} must be at least $min characters';
    }

    return null;
  }

  /// Maximum length validator
  static String? maxLength(String? value, int max, {String? fieldName}) {
    if (value == null) return null;

    if (value.length > max) {
      return '${fieldName ?? 'This field'} must be at most $max characters';
    }

    return null;
  }

  /// Exact length validator
  static String? exactLength(String? value, int length, {String? fieldName}) {
    if (value == null || value.isEmpty) {
      return '${fieldName ?? 'This field'} is required';
    }

    if (value.length != length) {
      return '${fieldName ?? 'This field'} must be exactly $length characters';
    }

    return null;
  }

  // ==================== Pattern Validators ====================

  /// Alphanumeric validator
  static String? alphanumeric(String? value, {String? fieldName}) {
    if (value == null || value.trim().isEmpty) {
      return '${fieldName ?? 'This field'} is required';
    }

    if (!RegExp(r'^[a-zA-Z0-9]+$').hasMatch(value.trim())) {
      return '${fieldName ?? 'This field'} must contain only letters and numbers';
    }

    return null;
  }

  /// Alphabetic validator
  static String? alphabetic(String? value, {String? fieldName}) {
    if (value == null || value.trim().isEmpty) {
      return '${fieldName ?? 'This field'} is required';
    }

    if (!RegExp(r'^[a-zA-Z\s]+$').hasMatch(value.trim())) {
      return '${fieldName ?? 'This field'} must contain only letters';
    }

    return null;
  }

  /// URL validator
  static String? url(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'URL is required';
    }

    final urlRegex = RegExp(
      r'^https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)$',
    );

    if (!urlRegex.hasMatch(value.trim())) {
      return 'Please enter a valid URL';
    }

    return null;
  }

  // ==================== Business-Specific Validators ====================

  /// GST number validator (Indian)
  static String? gst(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'GST number is required';
    }

    final gstRegex = RegExp(
      r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$',
    );

    if (!gstRegex.hasMatch(value.trim().toUpperCase())) {
      return 'Please enter a valid GST number';
    }

    return null;
  }

  /// PAN number validator (Indian)
  static String? pan(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'PAN number is required';
    }

    final panRegex = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$');

    if (!panRegex.hasMatch(value.trim().toUpperCase())) {
      return 'Please enter a valid PAN number';
    }

    return null;
  }

  /// Barcode validator
  static String? barcode(String? value, {int? length}) {
    // Barcode is optional
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    if (!RegExp(r'^[a-zA-Z0-9]+$').hasMatch(value.trim())) {
      return 'Barcode can only contain letters and numbers';
    }

    if (length != null && value.trim().length != length) {
      return 'Barcode must be exactly $length characters';
    }

    return null;
  }

  /// SKU validator
  static String? sku(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'SKU is required';
    }

    if (!RegExp(r'^[A-Z0-9\-_]+$').hasMatch(value.trim().toUpperCase())) {
      return 'SKU must contain only letters, numbers, hyphens, and underscores';
    }

    return null;
  }

  /// Percentage validator
  static String? percentage(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Percentage is required';
    }

    final percent = double.tryParse(value.trim());
    if (percent == null) {
      return 'Please enter a valid percentage';
    }

    if (percent < 0 || percent > 100) {
      return 'Percentage must be between 0 and 100';
    }

    return null;
  }

  // ==================== LiquorPro Specific Validators ====================

  /// Validate selling price (selling price >= cost price + duty)
  static String? validateSellingPrice({
    required String? value,
    required double costPrice,
    required double upDuty,
  }) {
    final error = positiveNumber(value, fieldName: 'Selling price');
    if (error != null) return error;

    final sellingPrice = double.parse(value!);
    final minPrice = costPrice + upDuty;

    if (sellingPrice < minPrice) {
      return 'Selling price must be at least ${minPrice.toStringAsFixed(2)} (cost + duty)';
    }

    return null;
  }

  /// Validate MRP (MRP >= selling price)
  static String? validateMRP({
    required String? value,
    required double sellingPrice,
  }) {
    final error = positiveNumber(value, fieldName: 'MRP');
    if (error != null) return error;

    final mrp = double.parse(value!);

    if (mrp < sellingPrice) {
      return 'MRP must be at least ${sellingPrice.toStringAsFixed(2)}';
    }

    return null;
  }

  // ==================== Composite Validators ====================

  /// Combine multiple validators
  static String? Function(String?) combine(
    List<String? Function(String?)> validators,
  ) {
    return (String? value) {
      for (final validator in validators) {
        final error = validator(value);
        if (error != null) {
          return error;
        }
      }
      return null;
    };
  }

  /// Conditional validator
  static String? Function(String?) when(
    bool Function() condition,
    String? Function(String?) validator,
  ) {
    return (String? value) {
      if (condition()) {
        return validator(value);
      }
      return null;
    };
  }

  // ==================== Custom Validators ====================

  /// Match pattern validator
  static String? matchPattern(
    String? value,
    RegExp pattern, {
    String? errorMessage,
    String? fieldName,
  }) {
    if (value == null || value.trim().isEmpty) {
      return '${fieldName ?? 'This field'} is required';
    }

    if (!pattern.hasMatch(value.trim())) {
      return errorMessage ?? '${fieldName ?? 'This field'} is invalid';
    }

    return null;
  }

  /// Range validator
  static String? range(
    String? value, {
    required double min,
    required double max,
    String? fieldName,
  }) {
    if (value == null || value.trim().isEmpty) {
      return '${fieldName ?? 'This field'} is required';
    }

    final numValue = double.tryParse(value.trim());
    if (numValue == null) {
      return 'Please enter a valid number';
    }

    if (numValue < min || numValue > max) {
      return '${fieldName ?? 'Value'} must be between $min and $max';
    }

    return null;
  }

  /// Date validator (not in future)
  static String? notFutureDate(DateTime? value, {String? fieldName}) {
    if (value == null) {
      return '${fieldName ?? 'Date'} is required';
    }

    if (value.isAfter(DateTime.now())) {
      return '${fieldName ?? 'Date'} cannot be in the future';
    }

    return null;
  }

  /// Date validator (not in past)
  static String? notPastDate(DateTime? value, {String? fieldName}) {
    if (value == null) {
      return '${fieldName ?? 'Date'} is required';
    }

    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final valueDate = DateTime(value.year, value.month, value.day);

    if (valueDate.isBefore(todayDate)) {
      return '${fieldName ?? 'Date'} cannot be in the past';
    }

    return null;
  }
}
