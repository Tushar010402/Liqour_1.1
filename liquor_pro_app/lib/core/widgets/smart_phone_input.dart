import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';

/// Industrial-grade phone input widget with smart formatting and real-time validation.
///
/// A production-ready phone number input widget that provides:
/// - **Multi-country support**: +91 (India), +1 (USA/Canada), +44 (UK), +86 (China)
/// - **Format-as-you-type**: Automatic formatting based on country code
/// - **Real-time validation**: Debounced API calls to check phone availability
/// - **Visual feedback**: Loading spinners, success/error icons, helper messages
/// - **Input sanitization**: Removes invalid characters, normalizes format
/// - **Accessibility**: Screen reader support, semantic labels
///
/// ## Usage Example
///
/// ```dart
/// SmartPhoneInput(
///   controller: phoneController,
///   label: 'Phone Number',
///   defaultCountryCode: '+91',
///   onValidate: (phoneNumber) async {
///     final service = UserManagementService(apiService);
///     final response = await service.validatePhoneAvailability(phoneNumber);
///     return ValidationResult(
///       isAvailable: response.available,
///       message: response.message,
///     );
///   },
///   onChanged: (fullPhoneNumber) {
///     print('Phone changed: $fullPhoneNumber');
///   },
/// )
/// ```
///
/// ## Performance Characteristics
///
/// - **Debouncing**: 800ms delay after typing stops (configurable)
/// - **API calls**: Only when format is valid (10 digits)
/// - **Caching**: Skips re-validation for same number
/// - **Cancellation**: Previous validations cancelled on new input
///
/// ## Accessibility
///
/// - Semantic labels for screen readers
/// - Color-independent visual feedback (icons + text)
/// - Keyboard navigation support
/// - Focus management
///
/// See also:
/// - [ValidationResult] for validation response structure
/// - [PhoneValidator] for phone number validation utilities
class SmartPhoneInput extends StatefulWidget {
  final TextEditingController controller;
  final String? label;
  final String? hint;
  final bool enabled;
  final Function(String)? onChanged;
  final String? errorText;
  final String defaultCountryCode;

  /// Optional callback for real-time phone number validation.
  ///
  /// Called after [validationDebounce] delay when user stops typing.
  /// Only triggered when phone number format is valid (10 digits).
  ///
  /// **Parameters:**
  /// - `phoneNumber`: Full phone number with country code (e.g., "+91 9876543210")
  ///
  /// **Returns:**
  /// - [ValidationResult] with availability status and user-friendly message
  ///
  /// **Performance Notes:**
  /// - Automatically debounced (800ms default)
  /// - Cached to avoid redundant calls
  /// - Cancelled if user types again
  ///
  /// **Example:**
  /// ```dart
  /// onValidate: (phoneNumber) async {
  ///   final response = await userService.validatePhoneAvailability(phoneNumber);
  ///   return ValidationResult(
  ///     isAvailable: response.available,
  ///     message: response.message,
  ///   );
  /// }
  /// ```
  final Future<ValidationResult> Function(String phoneNumber)? onValidate;

  /// Debounce duration for validation (default 800ms)
  final Duration validationDebounce;

  const SmartPhoneInput({
    super.key,
    required this.controller,
    this.label,
    this.hint,
    this.enabled = true,
    this.onChanged,
    this.errorText,
    this.defaultCountryCode = '+91', // India default
    this.onValidate,
    this.validationDebounce = const Duration(milliseconds: 800),
  });

  @override
  State<SmartPhoneInput> createState() => _SmartPhoneInputState();
}

/// Result object returned by phone number validation callbacks.
///
/// Contains the availability status and a user-friendly message
/// to display in the UI.
///
/// **Example:**
/// ```dart
/// // Available number
/// ValidationResult(
///   isAvailable: true,
///   message: 'Phone number available',
/// )
///
/// // Already registered
/// ValidationResult(
///   isAvailable: false,
///   message: 'Phone number already registered to another user',
/// )
/// ```
class ValidationResult {
  /// Whether the phone number is available for use.
  ///
  /// `true` = number is available, `false` = number is taken or error occurred
  final bool isAvailable;

  /// User-friendly message describing the validation result.
  final String message;

  /// Whether the phone needs a transfer (exists in another tenant)
  final bool needsTransfer;

  /// Existing user info (when needsTransfer is true)
  final String? existingName;
  final String? existingRole;
  final String? existingTenant;

  const ValidationResult({
    required this.isAvailable,
    required this.message,
    this.needsTransfer = false,
    this.existingName,
    this.existingRole,
    this.existingTenant,
  });

  static const ValidationResult checking = ValidationResult(
    isAvailable: false,
    message: 'Checking availability...',
  );

  static const ValidationResult networkError = ValidationResult(
    isAvailable: false,
    message: 'Network error - please try again',
  );
}

class _SmartPhoneInputState extends State<SmartPhoneInput> {
  final FocusNode _focusNode = FocusNode();
  String _selectedCountryCode = '+91';
  bool _isValid = false;

  // Real-time validation state
  Timer? _debounceTimer;
  bool _isValidating = false;
  ValidationResult? _validationResult;
  String _lastValidatedNumber = '';

  // Supported country codes with their formats
  static const Map<String, PhoneFormat> _countryFormats = {
    '+91': PhoneFormat(
      code: '+91',
      name: 'India',
      flag: '🇮🇳',
      format: 'XXXXX XXXXX',
      length: 10,
      example: '98765 43210',
    ),
    '+1': PhoneFormat(
      code: '+1',
      name: 'USA/Canada',
      flag: '🇺🇸',
      format: '(XXX) XXX-XXXX',
      length: 10,
      example: '(555) 123-4567',
    ),
    '+44': PhoneFormat(
      code: '+44',
      name: 'UK',
      flag: '🇬🇧',
      format: 'XXXX XXXXXX',
      length: 10,
      example: '7700 900123',
    ),
    '+86': PhoneFormat(
      code: '+86',
      name: 'China',
      flag: '🇨🇳',
      format: 'XXX XXXX XXXX',
      length: 11,
      example: '138 0013 8000',
    ),
  };

  @override
  void initState() {
    super.initState();
    _selectedCountryCode = widget.defaultCountryCode;

    debugPrint('📱 [SmartPhoneInput] initState called');
    debugPrint('   defaultCountryCode: ${widget.defaultCountryCode}');
    debugPrint('   controller.text: "${widget.controller.text}"');

    // Parse existing value if any
    if (widget.controller.text.isNotEmpty) {
      _parsePhoneNumber(widget.controller.text);

      // ✅ FIX: Format the initial value after frame is built
      // This ensures the value is properly displayed and validated
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          debugPrint('📱 [SmartPhoneInput] Post-frame callback - formatting initial value');
          _formatPhoneNumber();
        }
      });
    }

    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      // Format on blur
      _formatPhoneNumber();
    }
  }

  void _parsePhoneNumber(String value) {
    // Detect country code from existing number
    for (var entry in _countryFormats.entries) {
      if (value.startsWith(entry.key)) {
        setState(() {
          _selectedCountryCode = entry.key;
        });
        break;
      }
    }
  }

  String _formatPhoneNumber() {
    final text = widget.controller.text;
    final format = _countryFormats[_selectedCountryCode]!;

    debugPrint('📱 [SmartPhoneInput] _formatPhoneNumber called');
    debugPrint('   Input text: "$text"');
    debugPrint('   Country code: $_selectedCountryCode');

    // Extract only digits
    String digitsOnly = text.replaceAll(RegExp(r'[^0-9]'), '');
    debugPrint('   Digits only: "$digitsOnly"');

    // Remove country code digits ONLY if user pasted a full international number
    // (i.e., total digits exceed expected length for this country)
    // This prevents stripping "91" from phone numbers that legitimately start with 91
    String countryDigits = _selectedCountryCode.replaceAll('+', '');
    if (digitsOnly.startsWith(countryDigits) && digitsOnly.length > format.length) {
      digitsOnly = digitsOnly.substring(countryDigits.length);
      debugPrint('   After removing country prefix (pasted full number): "$digitsOnly"');
    }

    // Limit to max length
    if (digitsOnly.length > format.length) {
      digitsOnly = digitsOnly.substring(0, format.length);
      debugPrint('   After length limit: "$digitsOnly"');
    }

    // Format based on country (WITHOUT country code)
    String formatted = _applyFormat(digitsOnly, format);
    debugPrint('   Formatted: "$formatted"');

    // Update controller with ONLY the phone number (no country code in input)
    widget.controller.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );

    // Validate
    final isValid = digitsOnly.length == format.length;
    debugPrint('   Is valid: $isValid (length: ${digitsOnly.length}/${format.length})');
    setState(() {
      _isValid = isValid;
    });

    // Pass full number with country code to callback (WITHOUT spaces for API)
    // Use digitsOnly instead of formatted to avoid spaces
    String fullNumber = digitsOnly.isEmpty ? '' : '$_selectedCountryCode$digitsOnly';
    debugPrint('   Full number for callback (no spaces): "$fullNumber"');

    widget.onChanged?.call(fullNumber);

    // Trigger real-time validation if enabled
    if (widget.onValidate != null && isValid) {
      _scheduleValidation(fullNumber);
    } else if (!isValid) {
      // Clear validation state if phone becomes invalid
      setState(() {
        _validationResult = null;
        _isValidating = false;
      });
    }

    return fullNumber;
  }

  /// Schedule validation with debouncing
  void _scheduleValidation(String phoneNumber) {
    // Cancel previous timer
    _debounceTimer?.cancel();

    // Skip if we already validated this number (compare digits only)
    if (PhoneValidator.areEqual(phoneNumber, _lastValidatedNumber) &&
        _validationResult != null) {
      return;
    }

    // Set validating state immediately
    setState(() {
      _isValidating = true;
      _validationResult = null;
    });

    // Schedule new validation
    _debounceTimer = Timer(widget.validationDebounce, () {
      _performValidation(phoneNumber);
    });
  }

  /// Perform actual validation API call
  Future<void> _performValidation(String phoneNumber) async {
    if (widget.onValidate == null) return;

    debugPrint('📞 [SmartPhoneInput] Validating: $phoneNumber');

    try {
      final result = await widget.onValidate!(phoneNumber);

      debugPrint('📞 [SmartPhoneInput] ✅ Got validation result from API');
      debugPrint('   Result available: ${result.isAvailable}');
      debugPrint('   Result message: ${result.message}');

      // ✅ FIX: Build current full number from controller text to compare properly (without spaces)
      String currentDigits = widget.controller.text.replaceAll(RegExp(r'[^0-9]'), '');
      String currentFullNumber = currentDigits.isEmpty
          ? ''
          : '$_selectedCountryCode$currentDigits';

      debugPrint('📞 [SmartPhoneInput] Comparing numbers:');
      debugPrint('   Validated: "$phoneNumber"');
      debugPrint('   Current:   "$currentFullNumber"');
      debugPrint('   Mounted: $mounted');
      debugPrint('   Are equal: ${PhoneValidator.areEqual(phoneNumber, currentFullNumber)}');

      // Only update if still validating the same number (compare digits only)
      if (mounted && PhoneValidator.areEqual(phoneNumber, currentFullNumber)) {
        debugPrint('📞 [SmartPhoneInput] ✅ Numbers match - updating UI state');
        setState(() {
          _validationResult = result;
          _isValidating = false;
          _lastValidatedNumber = phoneNumber;
        });

        debugPrint('📞 [SmartPhoneInput] ✅ Validation result SET: ${result.isAvailable ? "Available" : "Unavailable"}');
        debugPrint('   Message: ${result.message}');
        debugPrint('   _validationResult is now: $_validationResult');
      } else {
        debugPrint('📞 [SmartPhoneInput] ❌ Number changed during validation - ignoring result');
      }
    } catch (e, stackTrace) {
      debugPrint('📞 [SmartPhoneInput] ❌ Validation error: $e');
      debugPrint('   Stack: $stackTrace');

      if (mounted) {
        setState(() {
          _validationResult = ValidationResult.networkError;
          _isValidating = false;
        });
      }
    }
  }

  String _applyFormat(String digits, PhoneFormat format) {
    if (digits.isEmpty) return '';

    String formatted = '';
    int digitIndex = 0;

    for (int i = 0; i < format.format.length && digitIndex < digits.length; i++) {
      if (format.format[i] == 'X') {
        formatted += digits[digitIndex];
        digitIndex++;
      } else {
        formatted += format.format[i];
      }
    }

    return formatted;
  }

  void _handlePaste(String pastedText) {
    // Smart paste handling
    String cleaned = pastedText.trim();

    // Detect and set country code from pasted text
    for (var entry in _countryFormats.entries) {
      if (cleaned.startsWith(entry.key)) {
        setState(() {
          _selectedCountryCode = entry.key;
        });
        break;
      }
    }

    // Set text and format
    widget.controller.text = cleaned;
    _formatPhoneNumber();
  }

  /// Build suffix icon based on validation state
  Widget? _buildSuffixIcon() {
    // Show validation results if validation is enabled
    if (widget.onValidate != null && _isValid) {
      if (_isValidating) {
        final cs = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.all(12.0),
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
            ),
          ),
        );
      }

      if (_validationResult != null) {
        if (_validationResult!.needsTransfer) {
          return const Icon(Icons.swap_horiz, color: Color(0xFFFF8F00), size: 20);
        }
        return Icon(
          _validationResult!.isAvailable ? Icons.check_circle : Icons.error,
          color: _validationResult!.isAvailable
              ? AppColors.success
              : AppColors.error,
          size: 20,
        );
      }
    }

    // Default: show check if format is valid (no validation enabled)
    if (_isValid && widget.onValidate == null) {
      return const Icon(
        Icons.check_circle,
        color: AppColors.success,
        size: 20,
      );
    }

    return null;
  }

  /// Get helper/error text to display
  String? _getHelperText() {
    // Show external error first
    if (widget.errorText != null) {
      return widget.errorText;
    }

    // Show transfer info
    if (_validationResult != null && _validationResult!.needsTransfer) {
      final name = _validationResult!.existingName ?? 'another user';
      final tenant = _validationResult!.existingTenant ?? 'another organization';
      return 'Registered to $name in $tenant — OTP required to transfer';
    }

    // Show validation message
    if (_validationResult != null && !_validationResult!.isAvailable) {
      return _validationResult!.message;
    }

    // Show validation in progress
    if (_isValidating) {
      return 'Checking availability...';
    }

    // Show success message
    if (_validationResult != null && _validationResult!.isAvailable) {
      return 'Phone number available';
    }

    // Show format hint when focused
    if (_focusNode.hasFocus) {
      final format = _countryFormats[_selectedCountryCode]!;
      return 'Example: ${format.code} ${format.example}';
    }

    return null;
  }

  /// Get icon for helper text
  IconData _getHelperIcon() {
    if (widget.errorText != null ||
        (_validationResult != null && !_validationResult!.isAvailable)) {
      return Icons.error_outline;
    }

    if (_validationResult != null && _validationResult!.isAvailable) {
      return Icons.check_circle_outline;
    }

    return Icons.info_outline;
  }

  /// Get color for helper text
  Color _getHelperColor(ColorScheme cs) {
    if (widget.errorText != null ||
        (_validationResult != null && !_validationResult!.isAvailable)) {
      return AppColors.error;
    }

    if (_validationResult != null && _validationResult!.isAvailable) {
      return AppColors.success;
    }

    return cs.onSurfaceVariant;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final format = _countryFormats[_selectedCountryCode]!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              widget.label!,
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: widget.enabled ? cs.surface : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.errorText != null
                  ? AppColors.error
                  : _focusNode.hasFocus
                      ? cs.primary
                      : _isValid
                          ? AppColors.success
                          : cs.onSurfaceVariant.withValues(alpha: 0.3),
              width: _focusNode.hasFocus || widget.errorText != null ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              // Country Code Selector
              InkWell(
                onTap: widget.enabled ? _showCountryPicker : null,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(11),
                      bottomLeft: Radius.circular(11),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        format.flag,
                        style: const TextStyle(fontSize: 20),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _selectedCountryCode,
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_drop_down,
                        size: 20,
                        color: cs.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
              // Divider
              Container(
                width: 1,
                height: 40,
                color: cs.onSurfaceVariant.withValues(alpha: 0.2),
              ),
              // Phone Number Input
              Expanded(
                child: Row(
                  children: [
                    // Show country code prefix ONLY when user has typed something
                    if (widget.controller.text.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: Text(
                          _selectedCountryCode,
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: TextField(
                        controller: widget.controller,
                        focusNode: _focusNode,
                        enabled: widget.enabled,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9\s\-()]')),
                          LengthLimitingTextInputFormatter(20),
                        ],
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.5,
                        ),
                        decoration: InputDecoration(
                          hintText: widget.hint ?? 'Phone number',
                          hintStyle: AppTextStyles.bodyMedium.copyWith(
                            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.only(
                            left: widget.controller.text.isEmpty ? 16 : 0,
                            right: 16,
                            top: 16,
                            bottom: 16,
                          ),
                          suffixIcon: _buildSuffixIcon(),
                        ),
                        onChanged: (value) {
                          _formatPhoneNumber();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Helper text - Show validation status or hints
        if (_getHelperText() != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 12),
            child: Row(
              children: [
                Icon(
                  _getHelperIcon(),
                  size: 14,
                  color: _getHelperColor(cs),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _getHelperText()!,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: _getHelperColor(cs),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _showCountryPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final sheetCs = Theme.of(sheetContext).colorScheme;
        return Container(
          decoration: BoxDecoration(
            color: sheetCs.surface,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: sheetCs.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Text(
                      'Select Country',
                      style: AppTextStyles.h4.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close),
                      style: IconButton.styleFrom(
                        backgroundColor: sheetCs.surfaceContainerHighest,
                      ),
                    ),
                  ],
                ),
              ),
              // Country list
              ..._countryFormats.entries.map((entry) {
                final format = entry.value;
                return ListTile(
                  leading: Text(
                    format.flag,
                    style: const TextStyle(fontSize: 28),
                  ),
                  title: Text(
                    format.name,
                    style: AppTextStyles.bodyLarge.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    '${format.code} • Example: ${format.code} ${format.example}',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: sheetCs.onSurfaceVariant,
                    ),
                  ),
                  trailing: _selectedCountryCode == format.code
                      ? const Icon(
                          Icons.check_circle,
                          color: AppColors.success,
                        )
                      : null,
                  onTap: () {
                    setState(() {
                      _selectedCountryCode = format.code;
                    });
                    Navigator.pop(sheetContext);
                    _formatPhoneNumber();
                  },
                );
              }),
              SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
            ],
          ),
        );
      },
    );
  }
}

/// Phone format configuration
class PhoneFormat {
  final String code;
  final String name;
  final String flag;
  final String format; // X represents digit, others are formatting chars
  final int length;
  final String example;

  const PhoneFormat({
    required this.code,
    required this.name,
    required this.flag,
    required this.format,
    required this.length,
    required this.example,
  });
}

/// Validator utility for phone numbers
class PhoneValidator {
  /// Validates if phone number is complete and properly formatted
  static bool isValid(String phoneNumber) {
    // Remove all non-digit characters except +
    String cleaned = phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');

    // Must start with +
    if (!cleaned.startsWith('+')) return false;

    // Must have country code and at least 10 digits
    if (cleaned.length < 12) return false;

    // Check specific country formats
    if (cleaned.startsWith('+91')) {
      // India: +91 + 10 digits
      return cleaned.length == 13;
    } else if (cleaned.startsWith('+1')) {
      // USA/Canada: +1 + 10 digits
      return cleaned.length == 12;
    } else if (cleaned.startsWith('+44')) {
      // UK: +44 + 10 digits
      return cleaned.length == 13;
    } else if (cleaned.startsWith('+86')) {
      // China: +86 + 11 digits
      return cleaned.length == 14;
    }

    // Default: Must have at least 10 digits after country code
    return cleaned.length >= 12;
  }

  /// Extracts clean phone number (only + and digits)
  static String clean(String phoneNumber) {
    return phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');
  }

  /// Extracts digits only from phone number (removes +, spaces, and all formatting)
  /// Used for comparing phone numbers regardless of country code or formatting
  static String digitsOnly(String phoneNumber) {
    return phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
  }

  /// Checks if two phone numbers are the same (compares digits only)
  /// Ignores country codes, spaces, and formatting
  static bool areEqual(String phone1, String phone2) {
    return digitsOnly(phone1) == digitsOnly(phone2);
  }

  /// Formats phone number for display
  static String format(String phoneNumber) {
    String cleaned = clean(phoneNumber);

    if (cleaned.startsWith('+91') && cleaned.length == 13) {
      // India format: +91 98765 43210
      return '+91 ${cleaned.substring(3, 8)} ${cleaned.substring(8)}';
    } else if (cleaned.startsWith('+1') && cleaned.length == 12) {
      // USA format: +1 (555) 123-4567
      return '+1 (${cleaned.substring(2, 5)}) ${cleaned.substring(5, 8)}-${cleaned.substring(8)}';
    } else if (cleaned.startsWith('+44') && cleaned.length == 13) {
      // UK format: +44 7700 900123
      return '+44 ${cleaned.substring(3, 7)} ${cleaned.substring(7)}';
    } else if (cleaned.startsWith('+86') && cleaned.length == 14) {
      // China format: +86 138 0013 8000
      return '+86 ${cleaned.substring(3, 6)} ${cleaned.substring(6, 10)} ${cleaned.substring(10)}';
    }

    return phoneNumber;
  }

  /// Gets error message for invalid phone number
  static String? getErrorMessage(String phoneNumber) {
    if (phoneNumber.isEmpty) {
      return 'Phone number is required';
    }

    if (!phoneNumber.startsWith('+')) {
      return 'Phone number must start with country code (e.g., +91)';
    }

    String cleaned = clean(phoneNumber);

    if (cleaned.length < 12) {
      return 'Phone number is too short';
    }

    if (!isValid(phoneNumber)) {
      return 'Invalid phone number format';
    }

    return null;
  }
}
