import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../utils/haptic_feedback.dart';

/// Custom Text Field Widgets - Best Practice Input Fields
/// Reusable text field components with consistent design

/// Primary Text Field - Standard input field
class PrimaryTextField extends StatefulWidget {
  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? prefixText;
  final String? suffixText;
  final IconData? prefixIcon;
  final IconData? suffixIcon;
  final VoidCallback? onSuffixIconTap;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool enabled;
  final bool readOnly;
  final int? maxLines;
  final int? maxLength;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final void Function(String)? onSubmitted;
  final VoidCallback? onTap;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final FocusNode? focusNode;
  final EdgeInsets? contentPadding;
  final Color? fillColor;
  final double borderRadius;

  const PrimaryTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.prefixText,
    this.suffixText,
    this.prefixIcon,
    this.suffixIcon,
    this.onSuffixIconTap,
    this.keyboardType,
    this.obscureText = false,
    this.enabled = true,
    this.readOnly = false,
    this.maxLines = 1,
    this.maxLength,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.focusNode,
    this.contentPadding,
    this.fillColor,
    this.borderRadius = 16,
  });

  @override
  State<PrimaryTextField> createState() => _PrimaryTextFieldState();
}

class _PrimaryTextFieldState extends State<PrimaryTextField> {
  late bool _obscureText;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _obscureText = widget.obscureText;
    widget.focusNode?.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode?.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    setState(() {
      _isFocused = widget.focusNode?.hasFocus ?? false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final primaryColor = cs.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ).animate().fadeIn().slideX(begin: -0.1, end: 0),
          const SizedBox(height: 8),
        ],
        TextFormField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          obscureText: _obscureText,
          enabled: widget.enabled,
          readOnly: widget.readOnly,
          maxLines: widget.maxLines,
          maxLength: widget.maxLength,
          keyboardType: widget.keyboardType,
          textCapitalization: widget.textCapitalization,
          inputFormatters: widget.inputFormatters,
          validator: widget.validator,
          onChanged: widget.onChanged,
          onFieldSubmitted: widget.onSubmitted,
          onTap: () {
            HapticFeedbackUtil.light();
            widget.onTap?.call();
          },
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 16,
              fontWeight: FontWeight.w400,
            ),
            prefixText: widget.prefixText,
            suffixText: widget.suffixText,
            prefixIcon: widget.prefixIcon != null
                ? Icon(widget.prefixIcon, color: _isFocused ? primaryColor : cs.onSurfaceVariant)
                : null,
            suffixIcon: widget.obscureText
                ? IconButton(
                    icon: Icon(
                      _obscureText ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      color: cs.onSurfaceVariant,
                    ),
                    onPressed: () {
                      HapticFeedbackUtil.light();
                      setState(() {
                        _obscureText = !_obscureText;
                      });
                    },
                  )
                : (widget.suffixIcon != null
                    ? IconButton(
                        icon: Icon(widget.suffixIcon, color: cs.onSurfaceVariant),
                        onPressed: () {
                          HapticFeedbackUtil.light();
                          widget.onSuffixIconTap?.call();
                        },
                      )
                    : null),
            filled: true,
            fillColor: widget.fillColor ?? cs.surfaceContainerHighest,
            contentPadding: widget.contentPadding ??
                const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              borderSide: BorderSide(color: cs.outlineVariant, width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              borderSide: BorderSide(color: cs.outlineVariant, width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              borderSide: BorderSide(color: primaryColor, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              borderSide: BorderSide(color: cs.error, width: 1.5),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              borderSide: BorderSide(color: cs.error, width: 2),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              borderSide: BorderSide(color: cs.outlineVariant, width: 1.5),
            ),
          ),
        ).animate().fadeIn().slideY(begin: 0.1, end: 0),
      ],
    );
  }
}

/// Search Text Field - For search functionality
class SearchTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String hint;
  final void Function(String)? onChanged;
  final VoidCallback? onClear;
  final bool showClearButton;

  const SearchTextField({
    super.key,
    this.controller,
    this.hint = 'Search...',
    this.onChanged,
    this.onClear,
    this.showClearButton = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      onTap: () => HapticFeedbackUtil.light(),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: cs.onSurfaceVariant,
          fontSize: 16,
        ),
        prefixIcon: Icon(Icons.search, color: cs.onSurfaceVariant),
        suffixIcon: showClearButton && controller?.text.isNotEmpty == true
            ? IconButton(
                icon: Icon(Icons.clear, color: cs.onSurfaceVariant),
                onPressed: () {
                  HapticFeedbackUtil.light();
                  controller?.clear();
                  onClear?.call();
                  onChanged?.call('');
                },
              )
            : null,
        filled: true,
        fillColor: cs.surfaceContainerHighest,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide(color: cs.primary, width: 2),
        ),
      ),
    ).animate().fadeIn().scale();
  }
}

/// Dropdown Text Field - Select from options
class DropdownTextField<T> extends StatelessWidget {
  final String? label;
  final String hint;
  final T? value;
  final List<T> items;
  final String Function(T) itemLabel;
  final void Function(T?)? onChanged;
  final IconData? prefixIcon;
  final String? Function(T?)? validator;

  const DropdownTextField({
    super.key,
    this.label,
    required this.hint,
    this.value,
    required this.items,
    required this.itemLabel,
    this.onChanged,
    this.prefixIcon,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ).animate().fadeIn().slideX(begin: -0.1, end: 0),
          const SizedBox(height: 8),
        ],
        DropdownButtonFormField<T>(
          initialValue: value,
          hint: Text(hint),
          items: items.map((item) {
            return DropdownMenuItem<T>(
              value: item,
              child: Text(itemLabel(item)),
            );
          }).toList(),
          onChanged: (newValue) {
            HapticFeedbackUtil.light();
            onChanged?.call(newValue);
          },
          validator: validator,
          decoration: InputDecoration(
            prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
            filled: true,
            fillColor: cs.surfaceContainerHighest,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: cs.outlineVariant, width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: cs.outlineVariant, width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: cs.primary, width: 2),
            ),
          ),
        ).animate().fadeIn().slideY(begin: 0.1, end: 0),
      ],
    );
  }
}

/// Amount Text Field - For currency input
class AmountTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? label;
  final String hint;
  final String? currencySymbol;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;

  const AmountTextField({
    super.key,
    this.controller,
    this.label,
    this.hint = '0.00',
    this.currencySymbol = '₹',
    this.validator,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PrimaryTextField(
      controller: controller,
      label: label,
      hint: hint,
      prefixText: currencySymbol,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
      ],
      validator: validator,
      onChanged: onChanged,
    );
  }
}

/// Phone Text Field - For phone number input
class PhoneTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? label;
  final String hint;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;

  const PhoneTextField({
    super.key,
    this.controller,
    this.label,
    this.hint = 'Enter phone number',
    this.validator,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PrimaryTextField(
      controller: controller,
      label: label,
      hint: hint,
      prefixIcon: Icons.phone,
      keyboardType: TextInputType.phone,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(10),
      ],
      validator: validator,
      onChanged: onChanged,
    );
  }
}

/// Email Text Field - For email input
class EmailTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? label;
  final String hint;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;

  const EmailTextField({
    super.key,
    this.controller,
    this.label,
    this.hint = 'Enter email address',
    this.validator,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PrimaryTextField(
      controller: controller,
      label: label,
      hint: hint,
      prefixIcon: Icons.email_outlined,
      keyboardType: TextInputType.emailAddress,
      textCapitalization: TextCapitalization.none,
      validator: validator,
      onChanged: onChanged,
    );
  }
}

/// Password Text Field - For password input
class PasswordTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? label;
  final String hint;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;

  const PasswordTextField({
    super.key,
    this.controller,
    this.label,
    this.hint = 'Enter password',
    this.validator,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PrimaryTextField(
      controller: controller,
      label: label,
      hint: hint,
      prefixIcon: Icons.lock_outline,
      obscureText: true,
      validator: validator,
      onChanged: onChanged,
    );
  }
}

/// Multi-line Text Field - For long text input
class MultilineTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? label;
  final String hint;
  final int maxLines;
  final int? maxLength;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;

  const MultilineTextField({
    super.key,
    this.controller,
    this.label,
    this.hint = 'Enter text...',
    this.maxLines = 5,
    this.maxLength,
    this.validator,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PrimaryTextField(
      controller: controller,
      label: label,
      hint: hint,
      maxLines: maxLines,
      maxLength: maxLength,
      textCapitalization: TextCapitalization.sentences,
      validator: validator,
      onChanged: onChanged,
    );
  }
}

/// Date Picker Text Field - For date selection
class DatePickerTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? label;
  final String hint;
  final DateTime? initialDate;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final void Function(DateTime)? onDateSelected;
  final String? Function(String?)? validator;

  const DatePickerTextField({
    super.key,
    this.controller,
    this.label,
    this.hint = 'Select date',
    this.initialDate,
    this.firstDate,
    this.lastDate,
    this.onDateSelected,
    this.validator,
  });

  Future<void> _selectDate(BuildContext context) async {
    HapticFeedbackUtil.light();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate ?? DateTime.now(),
      firstDate: firstDate ?? DateTime(2000),
      lastDate: lastDate ?? DateTime(2100),
    );

    if (picked != null) {
      controller?.text = '${picked.day}/${picked.month}/${picked.year}';
      onDateSelected?.call(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PrimaryTextField(
      controller: controller,
      label: label,
      hint: hint,
      prefixIcon: Icons.calendar_today,
      readOnly: true,
      onTap: () => _selectDate(context),
      validator: validator,
    );
  }
}
