import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pinput/pinput.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/app_theme.dart';

/// Modern OTP Input widget using Pinput with native iOS/Android autofill support
/// - iOS: Native keyboard OTP suggestion via AutofillHints.oneTimeCode
/// - Android: Works with smart_auth SMS Retriever
/// - Swiggy-style shake animation on error
class ModernOtpInput extends StatefulWidget {
  final Function(String) onCompleted;
  final Function(String) onChanged;
  final bool enabled;
  final String? errorText;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool showCursor;
  final bool autofocus;
  final bool shouldShake; // Triggers shake animation on error

  const ModernOtpInput({
    super.key,
    required this.onCompleted,
    required this.onChanged,
    this.enabled = true,
    this.errorText,
    this.controller,
    this.focusNode,
    this.showCursor = true,
    this.autofocus = true,
    this.shouldShake = false,
  });

  @override
  State<ModernOtpInput> createState() => _ModernOtpInputState();
}

class _ModernOtpInputState extends State<ModernOtpInput> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _focusNode = widget.focusNode ?? FocusNode();
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    }
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasError = widget.errorText != null;

    // Default theme - clean minimal design
    final defaultPinTheme = PinTheme(
      width: 52,
      height: 60,
      textStyle: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: cs.onSurface,
      ),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasError ? AppTheme.errorColor : AppTheme.borderColor,
          width: hasError ? 1.5 : 1,
        ),
      ),
    );

    // Focused state - highlighted with primary color
    final focusedPinTheme = defaultPinTheme.copyWith(
      decoration: defaultPinTheme.decoration?.copyWith(
        border: Border.all(color: AppTheme.primaryColor, width: 2),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );

    // Submitted/filled state - subtle primary tint
    final submittedPinTheme = defaultPinTheme.copyWith(
      decoration: defaultPinTheme.decoration?.copyWith(
        color: AppTheme.primaryColor.withOpacity(0.05),
        border: Border.all(
          color: AppTheme.primaryColor.withOpacity(0.3),
        ),
      ),
    );

    // Error state
    final errorPinTheme = defaultPinTheme.copyWith(
      decoration: defaultPinTheme.decoration?.copyWith(
        border: Border.all(color: AppTheme.errorColor, width: 1.5),
        color: AppTheme.errorColor.withOpacity(0.05),
      ),
    );

    // Build the Pinput widget
    Widget pinputWidget = AutofillGroup(
      child: Pinput(
        length: 6,
        controller: _controller,
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        defaultPinTheme: hasError ? errorPinTheme : defaultPinTheme,
        focusedPinTheme: focusedPinTheme,
        submittedPinTheme: submittedPinTheme,
        errorPinTheme: errorPinTheme,
        enabled: widget.enabled,

        // iOS native keyboard OTP suggestion
        autofillHints: const [AutofillHints.oneTimeCode],

        onCompleted: (code) {
          HapticFeedback.mediumImpact();
          widget.onCompleted(code);
        },
        onChanged: (value) {
          // Light haptic on each digit entry
          if (value.isNotEmpty) {
            HapticFeedback.selectionClick();
          }
          widget.onChanged(value);
        },

        // Elegant cursor
        cursor: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              width: 24,
              height: 2,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ),
        showCursor: widget.showCursor,

        // Haptic feedback type
        hapticFeedbackType: HapticFeedbackType.lightImpact,

        // Close keyboard on complete
        closeKeyboardWhenCompleted: false,

        // Animation
        animationDuration: const Duration(milliseconds: 200),
        animationCurve: Curves.easeOutCubic,

        // Pin animation
        pinAnimationType: PinAnimationType.scale,

        // Input formatting
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
        ],
      ),
    );

    // Apply shake animation when triggered (Swiggy-style wrong OTP feedback)
    if (widget.shouldShake) {
      pinputWidget = pinputWidget
          .animate(onPlay: (controller) => controller.forward())
          .shake(hz: 4, rotation: 0.03, duration: 400.ms);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        pinputWidget,

        // Error message
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 16,
                  color: AppTheme.errorColor,
                ),
                const SizedBox(width: 6),
                Text(
                  widget.errorText!,
                  style: const TextStyle(
                    color: AppTheme.errorColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          )
          .animate()
          .fadeIn(duration: 200.ms)
          .shake(hz: 3, rotation: 0.02, duration: 400.ms),
      ],
    );
  }

  /// Programmatically set the OTP code (for auto-fill from SMS)
  void setCode(String code) {
    _controller.text = code;
    widget.onChanged(code);
    if (code.length == 6) {
      widget.onCompleted(code);
    }
  }

  /// Clear the input
  void clear() {
    _controller.clear();
    widget.onChanged('');
  }
}
