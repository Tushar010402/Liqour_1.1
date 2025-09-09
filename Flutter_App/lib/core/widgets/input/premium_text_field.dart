import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_typography.dart';

/// Premium text field with enhanced styling and validation
class PremiumTextField extends StatefulWidget {
  final String? label;
  final String? hint;
  final String? helperText;
  final String? errorText;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final bool obscureText;
  final bool readOnly;
  final bool enabled;
  final bool autofocus;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final VoidCallback? onEditingComplete;
  final FormFieldValidator<String>? validator;
  final List<TextInputFormatter>? inputFormatters;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final String? prefixText;
  final String? suffixText;
  final EdgeInsetsGeometry? contentPadding;
  final BorderRadius? borderRadius;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color? focusedBorderColor;
  final Color? errorBorderColor;
  final PremiumTextFieldVariant variant;
  final bool showCounter;
  final bool enableInteractiveSelection;
  final TextSelectionControls? selectionControls;
  final ScrollController? scrollController;
  final String? initialValue;

  const PremiumTextField({
    super.key,
    this.label,
    this.hint,
    this.helperText,
    this.errorText,
    this.controller,
    this.focusNode,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.obscureText = false,
    this.readOnly = false,
    this.enabled = true,
    this.autofocus = false,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.onEditingComplete,
    this.validator,
    this.inputFormatters,
    this.prefixIcon,
    this.suffixIcon,
    this.prefixText,
    this.suffixText,
    this.contentPadding,
    this.borderRadius,
    this.backgroundColor,
    this.borderColor,
    this.focusedBorderColor,
    this.errorBorderColor,
    this.variant = PremiumTextFieldVariant.filled,
    this.showCounter = false,
    this.enableInteractiveSelection = true,
    this.selectionControls,
    this.scrollController,
    this.initialValue,
  });

  const PremiumTextField.outlined({
    super.key,
    this.label,
    this.hint,
    this.helperText,
    this.errorText,
    this.controller,
    this.focusNode,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.obscureText = false,
    this.readOnly = false,
    this.enabled = true,
    this.autofocus = false,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.onEditingComplete,
    this.validator,
    this.inputFormatters,
    this.prefixIcon,
    this.suffixIcon,
    this.prefixText,
    this.suffixText,
    this.contentPadding,
    this.borderRadius,
    this.backgroundColor,
    this.borderColor,
    this.focusedBorderColor,
    this.errorBorderColor,
    this.showCounter = false,
    this.enableInteractiveSelection = true,
    this.selectionControls,
    this.scrollController,
    this.initialValue,
  }) : variant = PremiumTextFieldVariant.outlined;

  const PremiumTextField.underlined({
    super.key,
    this.label,
    this.hint,
    this.helperText,
    this.errorText,
    this.controller,
    this.focusNode,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.obscureText = false,
    this.readOnly = false,
    this.enabled = true,
    this.autofocus = false,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.onEditingComplete,
    this.validator,
    this.inputFormatters,
    this.prefixIcon,
    this.suffixIcon,
    this.prefixText,
    this.suffixText,
    this.contentPadding,
    this.borderRadius,
    this.backgroundColor,
    this.borderColor,
    this.focusedBorderColor,
    this.errorBorderColor,
    this.showCounter = false,
    this.enableInteractiveSelection = true,
    this.selectionControls,
    this.scrollController,
    this.initialValue,
  }) : variant = PremiumTextFieldVariant.underlined;

  @override
  State<PremiumTextField> createState() => _PremiumTextFieldState();
}

class _PremiumTextFieldState extends State<PremiumTextField> with TickerProviderStateMixin {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  late AnimationController _animationController;
  late Animation<double> _labelAnimation;
  late Animation<Color?> _borderColorAnimation;
  
  bool _isFocused = false;
  bool _hasText = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    
    _controller = widget.controller ?? TextEditingController(text: widget.initialValue);
    _focusNode = widget.focusNode ?? FocusNode();
    _hasText = _controller.text.isNotEmpty;
    _errorText = widget.errorText;
    
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    
    _labelAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    
    _borderColorAnimation = ColorTween(
      begin: _getBorderColor(false, false),
      end: _getBorderColor(true, false),
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    
    _focusNode.addListener(_onFocusChanged);
    _controller.addListener(_onTextChanged);
    
    if (_isFocused || _hasText) {
      _animationController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(PremiumTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (widget.controller != oldWidget.controller) {
      _controller.removeListener(_onTextChanged);
      _controller = widget.controller ?? _controller;
      _controller.addListener(_onTextChanged);
      _hasText = _controller.text.isNotEmpty;
    }
    
    if (widget.focusNode != oldWidget.focusNode) {
      _focusNode.removeListener(_onFocusChanged);
      _focusNode = widget.focusNode ?? _focusNode;
      _focusNode.addListener(_onFocusChanged);
    }
    
    if (widget.errorText != oldWidget.errorText) {
      setState(() {
        _errorText = widget.errorText;
      });
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _controller.removeListener(_onTextChanged);
    
    if (widget.controller == null) {
      _controller.dispose();
    }
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    
    _animationController.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    setState(() {
      _isFocused = _focusNode.hasFocus;
    });
    
    if (_isFocused || _hasText) {
      _animationController.forward();
    } else {
      _animationController.reverse();
    }
  }

  void _onTextChanged() {
    final hasText = _controller.text.isNotEmpty;
    if (_hasText != hasText) {
      setState(() {
        _hasText = hasText;
      });
      
      if (_isFocused || _hasText) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    }
    
    // Clear error when user starts typing
    if (_errorText != null && _controller.text.isNotEmpty) {
      setState(() {
        _errorText = null;
      });
    }
    
    widget.onChanged?.call(_controller.text);
  }

  void _validate() {
    if (widget.validator != null) {
      final error = widget.validator!(_controller.text);
      setState(() {
        _errorText = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildTextField(),
        if (widget.helperText != null || _errorText != null || widget.showCounter)
          _buildHelperSection(),
      ],
    );
  }

  Widget _buildTextField() {
    final hasError = _errorText != null;
    
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Container(
          decoration: _getFieldDecoration(hasError),
          child: Stack(
            children: [
              TextFormField(
                controller: _controller,
                focusNode: _focusNode,
                keyboardType: widget.keyboardType,
                textInputAction: widget.textInputAction,
                textCapitalization: widget.textCapitalization,
                obscureText: widget.obscureText,
                readOnly: widget.readOnly,
                enabled: widget.enabled,
                autofocus: widget.autofocus,
                maxLines: widget.maxLines,
                minLines: widget.minLines,
                maxLength: widget.maxLength,
                onFieldSubmitted: widget.onSubmitted,
                onTap: widget.onTap,
                onEditingComplete: widget.onEditingComplete,
                inputFormatters: widget.inputFormatters,
                enableInteractiveSelection: widget.enableInteractiveSelection,
                selectionControls: widget.selectionControls,
                scrollController: widget.scrollController,
                style: _getTextStyle(),
                cursorColor: AppColors.premiumGold,
                decoration: _getInputDecoration(hasError),
                validator: widget.validator != null ? (value) {
                  final error = widget.validator!(value);
                  if (error != _errorText) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      setState(() {
                        _errorText = error;
                      });
                    });
                  }
                  return null; // Don't show default validation
                } : null,
              ),
              if (widget.label != null && widget.variant == PremiumTextFieldVariant.filled)
                _buildFloatingLabel(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFloatingLabel() {
    return Positioned(
      left: widget.prefixIcon != null ? 48 : 16,
      top: 0,
      child: AnimatedBuilder(
        animation: _labelAnimation,
        builder: (context, child) {
          final t = _labelAnimation.value;
          final scale = 0.75 + (0.25 * (1 - t));
          final dy = 16 + (12 * t);
          
          return Transform.translate(
            offset: Offset(0, dy),
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.centerLeft,
              child: Text(
                widget.label!,
                style: AppTypography.labelMedium.copyWith(
                  color: _isFocused 
                      ? AppColors.premiumGold 
                      : AppColors.mutedWhite,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHelperSection() {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0, left: 16.0, right: 16.0),
      child: Row(
        children: [
          if (_errorText != null)
            Expanded(
              child: Text(
                _errorText!,
                style: AppTypography.captionMedium.copyWith(
                  color: AppColors.errorRed,
                ),
              ),
            )
          else if (widget.helperText != null)
            Expanded(
              child: Text(
                widget.helperText!,
                style: AppTypography.captionMedium.copyWith(
                  color: AppColors.mutedWhite,
                ),
              ),
            )
          else
            const Spacer(),
          if (widget.showCounter && widget.maxLength != null)
            Text(
              '${_controller.text.length}/${widget.maxLength}',
              style: AppTypography.captionSmall.copyWith(
                color: AppColors.hintGrey,
              ),
            ),
        ],
      ),
    );
  }

  InputDecoration _getInputDecoration(bool hasError) {
    switch (widget.variant) {
      case PremiumTextFieldVariant.filled:
        return InputDecoration(
          hintText: widget.hint,
          hintStyle: AppTypography.bodyMedium.copyWith(
            color: AppColors.hintGrey,
          ),
          prefixIcon: widget.prefixIcon,
          suffixIcon: widget.suffixIcon,
          prefixText: widget.prefixText,
          suffixText: widget.suffixText,
          contentPadding: widget.contentPadding ?? const EdgeInsets.fromLTRB(16, 24, 16, 16),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          counterText: '',
        );
        
      case PremiumTextFieldVariant.outlined:
        return InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          hintStyle: AppTypography.bodyMedium.copyWith(
            color: AppColors.hintGrey,
          ),
          labelStyle: AppTypography.labelMedium.copyWith(
            color: _isFocused ? AppColors.premiumGold : AppColors.mutedWhite,
          ),
          prefixIcon: widget.prefixIcon,
          suffixIcon: widget.suffixIcon,
          prefixText: widget.prefixText,
          suffixText: widget.suffixText,
          contentPadding: widget.contentPadding ?? const EdgeInsets.all(16),
          border: _getOutlinedBorder(AppColors.borderGrey),
          enabledBorder: _getOutlinedBorder(_getBorderColor(false, hasError)),
          focusedBorder: _getOutlinedBorder(_getBorderColor(true, hasError)),
          errorBorder: _getOutlinedBorder(AppColors.errorRed),
          focusedErrorBorder: _getOutlinedBorder(AppColors.errorRed),
          counterText: '',
        );
        
      case PremiumTextFieldVariant.underlined:
        return InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          hintStyle: AppTypography.bodyMedium.copyWith(
            color: AppColors.hintGrey,
          ),
          labelStyle: AppTypography.labelMedium.copyWith(
            color: _isFocused ? AppColors.premiumGold : AppColors.mutedWhite,
          ),
          prefixIcon: widget.prefixIcon,
          suffixIcon: widget.suffixIcon,
          prefixText: widget.prefixText,
          suffixText: widget.suffixText,
          contentPadding: widget.contentPadding ?? const EdgeInsets.symmetric(vertical: 16),
          border: _getUnderlineBorder(AppColors.borderGrey),
          enabledBorder: _getUnderlineBorder(_getBorderColor(false, hasError)),
          focusedBorder: _getUnderlineBorder(_getBorderColor(true, hasError)),
          errorBorder: _getUnderlineBorder(AppColors.errorRed),
          focusedErrorBorder: _getUnderlineBorder(AppColors.errorRed),
          counterText: '',
        );
    }
  }

  BoxDecoration? _getFieldDecoration(bool hasError) {
    if (widget.variant != PremiumTextFieldVariant.filled) {
      return null;
    }
    
    return BoxDecoration(
      color: widget.backgroundColor ?? AppColors.inputGrey,
      borderRadius: widget.borderRadius ?? BorderRadius.circular(12),
      border: Border.all(
        color: _getBorderColor(_isFocused, hasError),
        width: _isFocused || hasError ? 2.0 : 1.0,
      ),
    );
  }

  OutlineInputBorder _getOutlinedBorder(Color color) {
    return OutlineInputBorder(
      borderRadius: widget.borderRadius ?? BorderRadius.circular(12),
      borderSide: BorderSide(
        color: color,
        width: _isFocused ? 2.0 : 1.0,
      ),
    );
  }

  UnderlineInputBorder _getUnderlineBorder(Color color) {
    return UnderlineInputBorder(
      borderSide: BorderSide(
        color: color,
        width: _isFocused ? 2.0 : 1.0,
      ),
    );
  }

  Color _getBorderColor(bool focused, bool hasError) {
    if (hasError) {
      return widget.errorBorderColor ?? AppColors.errorRed;
    }
    
    if (focused) {
      return widget.focusedBorderColor ?? AppColors.premiumGold;
    }
    
    return widget.borderColor ?? AppColors.borderGrey;
  }

  TextStyle _getTextStyle() {
    final baseStyle = AppTypography.bodyMedium.copyWith(
      color: widget.enabled ? AppColors.primaryWhite : AppColors.disabledGrey,
    );
    
    return baseStyle;
  }
}

enum PremiumTextFieldVariant {
  filled,
  outlined,
  underlined,
}

/// Specialized text field widgets
class EmailTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;

  const EmailTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.errorText,
    this.onChanged,
    this.onSubmitted,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return PremiumTextField(
      controller: controller,
      label: label ?? 'Email Address',
      hint: hint ?? 'Enter your email address',
      errorText: errorText,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      prefixIcon: const Icon(Icons.email_outlined),
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      validator: validator ?? _emailValidator,
    );
  }

  String? _emailValidator(String? value) {
    if (value == null || value.isEmpty) {
      return 'Email is required';
    }
    
    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
      return 'Please enter a valid email address';
    }
    
    return null;
  }
}

class PasswordTextField extends StatefulWidget {
  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;
  final bool showStrengthIndicator;

  const PasswordTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.errorText,
    this.onChanged,
    this.onSubmitted,
    this.validator,
    this.showStrengthIndicator = false,
  });

  @override
  State<PasswordTextField> createState() => _PasswordTextFieldState();
}

class _PasswordTextFieldState extends State<PasswordTextField> {
  bool _obscureText = true;
  late TextEditingController _controller;
  PasswordStrength _strength = PasswordStrength.none;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _controller.addListener(_onPasswordChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onPasswordChanged);
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _onPasswordChanged() {
    if (widget.showStrengthIndicator) {
      setState(() {
        _strength = _calculatePasswordStrength(_controller.text);
      });
    }
    widget.onChanged?.call(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        PremiumTextField(
          controller: _controller,
          label: widget.label ?? 'Password',
          hint: widget.hint ?? 'Enter your password',
          errorText: widget.errorText,
          obscureText: _obscureText,
          keyboardType: TextInputType.visiblePassword,
          textInputAction: TextInputAction.done,
          prefixIcon: const Icon(Icons.lock_outline),
          suffixIcon: IconButton(
            icon: Icon(_obscureText ? Icons.visibility_outlined : Icons.visibility_off_outlined),
            onPressed: () {
              setState(() {
                _obscureText = !_obscureText;
              });
            },
          ),
          onSubmitted: widget.onSubmitted,
          validator: widget.validator ?? _passwordValidator,
        ),
        if (widget.showStrengthIndicator)
          _buildPasswordStrengthIndicator(),
      ],
    );
  }

  Widget _buildPasswordStrengthIndicator() {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0, left: 16.0, right: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: _getStrengthValue(_strength),
                  backgroundColor: AppColors.borderGrey,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _getStrengthColor(_strength),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _getStrengthText(_strength),
                style: AppTypography.captionSmall.copyWith(
                  color: _getStrengthColor(_strength),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  PasswordStrength _calculatePasswordStrength(String password) {
    if (password.isEmpty) return PasswordStrength.none;
    if (password.length < 6) return PasswordStrength.weak;
    
    int score = 0;
    
    if (password.length >= 8) score++;
    if (RegExp(r'[a-z]').hasMatch(password)) score++;
    if (RegExp(r'[A-Z]').hasMatch(password)) score++;
    if (RegExp(r'[0-9]').hasMatch(password)) score++;
    if (RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password)) score++;
    
    switch (score) {
      case 0:
      case 1:
        return PasswordStrength.weak;
      case 2:
      case 3:
        return PasswordStrength.medium;
      case 4:
      case 5:
        return PasswordStrength.strong;
      default:
        return PasswordStrength.weak;
    }
  }

  double _getStrengthValue(PasswordStrength strength) {
    switch (strength) {
      case PasswordStrength.none:
        return 0.0;
      case PasswordStrength.weak:
        return 0.33;
      case PasswordStrength.medium:
        return 0.66;
      case PasswordStrength.strong:
        return 1.0;
    }
  }

  Color _getStrengthColor(PasswordStrength strength) {
    switch (strength) {
      case PasswordStrength.none:
        return AppColors.borderGrey;
      case PasswordStrength.weak:
        return AppColors.errorRed;
      case PasswordStrength.medium:
        return AppColors.warningAmber;
      case PasswordStrength.strong:
        return AppColors.successGreen;
    }
  }

  String _getStrengthText(PasswordStrength strength) {
    switch (strength) {
      case PasswordStrength.none:
        return '';
      case PasswordStrength.weak:
        return 'Weak';
      case PasswordStrength.medium:
        return 'Medium';
      case PasswordStrength.strong:
        return 'Strong';
    }
  }

  String? _passwordValidator(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }
    
    if (value.length < 8) {
      return 'Password must be at least 8 characters long';
    }
    
    return null;
  }
}

enum PasswordStrength {
  none,
  weak,
  medium,
  strong,
}