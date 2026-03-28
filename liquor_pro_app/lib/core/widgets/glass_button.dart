import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import '../theme/ios_design_tokens.dart';

/// Glass Button - iOS 16 Liquid Glass Design
///
/// Interactive button with glassmorphic effect and haptic feedback
class GlassButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? textColor;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final bool isLoading;
  final bool enabled;
  final ButtonStyle buttonStyle;
  final bool enableHapticFeedback;

  const GlassButton({
    super.key,
    required this.text,
    this.onPressed,
    this.icon,
    this.backgroundColor,
    this.textColor,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.isLoading = false,
    this.enabled = true,
    this.buttonStyle = ButtonStyle.primary,
    this.enableHapticFeedback = true,
  });

  /// Primary button (filled with color)
  factory GlassButton.primary({
    required String text,
    required VoidCallback onPressed,
    IconData? icon,
    bool isLoading = false,
    double? width,
    EdgeInsetsGeometry? margin,
  }) {
    return GlassButton(
      text: text,
      onPressed: onPressed,
      icon: icon,
      isLoading: isLoading,
      width: width,
      margin: margin,
      buttonStyle: ButtonStyle.primary,
    );
  }

  /// Secondary button (outlined)
  factory GlassButton.secondary({
    required String text,
    required VoidCallback onPressed,
    IconData? icon,
    bool isLoading = false,
    double? width,
    EdgeInsetsGeometry? margin,
  }) {
    return GlassButton(
      text: text,
      onPressed: onPressed,
      icon: icon,
      isLoading: isLoading,
      width: width,
      margin: margin,
      buttonStyle: ButtonStyle.secondary,
    );
  }

  /// Tertiary button (text only)
  factory GlassButton.tertiary({
    required String text,
    required VoidCallback onPressed,
    IconData? icon,
    double? width,
    EdgeInsetsGeometry? margin,
  }) {
    return GlassButton(
      text: text,
      onPressed: onPressed,
      icon: icon,
      width: width,
      margin: margin,
      buttonStyle: ButtonStyle.tertiary,
    );
  }

  /// Glass button (translucent)
  factory GlassButton.glass({
    required String text,
    required VoidCallback onPressed,
    IconData? icon,
    bool isLoading = false,
    double? width,
    EdgeInsetsGeometry? margin,
  }) {
    return GlassButton(
      text: text,
      onPressed: onPressed,
      icon: icon,
      isLoading: isLoading,
      width: width,
      margin: margin,
      buttonStyle: ButtonStyle.glass,
    );
  }

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: iOSDesignTokens.durationFast,
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(
        parent: _scaleController,
        curve: iOSDesignTokens.curveStandard,
      ),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    if (widget.enabled && !widget.isLoading) {
      _scaleController.forward();
      if (widget.enableHapticFeedback) {
        HapticFeedback.lightImpact();
      }
    }
  }

  void _handleTapUp(TapUpDetails details) {
    _scaleController.reverse();
  }

  void _handleTapCancel() {
    _scaleController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final isDisabled = !widget.enabled || widget.isLoading || widget.onPressed == null;

    return Container(
      margin: widget.margin,
      width: widget.width,
      height: widget.height ?? iOSDesignTokens.touchTargetComfortable,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: GestureDetector(
          onTapDown: _handleTapDown,
          onTapUp: _handleTapUp,
          onTapCancel: _handleTapCancel,
          onTap: isDisabled ? null : widget.onPressed,
          child: _buildButtonContent(isDisabled),
        ),
      ),
    );
  }

  Widget _buildButtonContent(bool isDisabled) {
    switch (widget.buttonStyle) {
      case ButtonStyle.primary:
        return _buildPrimaryButton(isDisabled);
      case ButtonStyle.secondary:
        return _buildSecondaryButton(isDisabled);
      case ButtonStyle.tertiary:
        return _buildTertiaryButton(isDisabled);
      case ButtonStyle.glass:
        return _buildGlassButton(isDisabled);
    }
  }

  Widget _buildPrimaryButton(bool isDisabled) {
    final backgroundColor = widget.backgroundColor ?? iOSDesignTokens.primary;
    final textColor = widget.textColor ?? iOSDesignTokens.neutralWhite;

    return Container(
      padding: widget.padding ??
          const EdgeInsets.symmetric(
            horizontal: iOSDesignTokens.space24,
            vertical: iOSDesignTokens.space16,
          ),
      decoration: BoxDecoration(
        gradient: isDisabled
            ? null
            : LinearGradient(
                colors: [
                  backgroundColor,
                  backgroundColor.withOpacity(0.85),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        color: isDisabled ? iOSDesignTokens.neutralGray300 : null,
        borderRadius: iOSDesignTokens.borderRadiusButton,
        boxShadow: isDisabled ? null : iOSDesignTokens.shadowMedium,
      ),
      child: _buildButtonLabel(
        textColor: isDisabled ? iOSDesignTokens.neutralGray500 : textColor,
      ),
    );
  }

  Widget _buildSecondaryButton(bool isDisabled) {
    final borderColor = widget.backgroundColor ?? iOSDesignTokens.primary;
    final textColor = widget.textColor ?? iOSDesignTokens.primary;

    return Container(
      padding: widget.padding ??
          const EdgeInsets.symmetric(
            horizontal: iOSDesignTokens.space24,
            vertical: iOSDesignTokens.space16,
          ),
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border.all(
          color: isDisabled ? iOSDesignTokens.neutralGray300 : borderColor,
          width: 2,
        ),
        borderRadius: iOSDesignTokens.borderRadiusButton,
      ),
      child: _buildButtonLabel(
        textColor: isDisabled ? iOSDesignTokens.neutralGray500 : textColor,
      ),
    );
  }

  Widget _buildTertiaryButton(bool isDisabled) {
    final textColor = widget.textColor ?? iOSDesignTokens.primary;

    return Container(
      padding: widget.padding ??
          const EdgeInsets.symmetric(
            horizontal: iOSDesignTokens.space16,
            vertical: iOSDesignTokens.space12,
          ),
      child: _buildButtonLabel(
        textColor: isDisabled ? iOSDesignTokens.neutralGray500 : textColor,
      ),
    );
  }

  Widget _buildGlassButton(bool isDisabled) {
    final textColor = widget.textColor ?? iOSDesignTokens.primary;

    return ClipRRect(
      borderRadius: iOSDesignTokens.borderRadiusButton,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
        child: Container(
          padding: widget.padding ??
              const EdgeInsets.symmetric(
                horizontal: iOSDesignTokens.space24,
                vertical: iOSDesignTokens.space16,
              ),
          decoration: BoxDecoration(
            color: iOSDesignTokens.neutralWhite.withOpacity(
              isDisabled ? 0.40 : 0.70,
            ),
            border: Border.all(
              color: iOSDesignTokens.neutralWhite.withOpacity(0.30),
              width: 1.5,
            ),
            borderRadius: iOSDesignTokens.borderRadiusButton,
            boxShadow: isDisabled ? null : iOSDesignTokens.shadowGlass,
          ),
          child: _buildButtonLabel(
            textColor: isDisabled ? iOSDesignTokens.neutralGray500 : textColor,
          ),
        ),
      ),
    );
  }

  Widget _buildButtonLabel({required Color textColor}) {
    if (widget.isLoading) {
      return Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(textColor),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.icon != null) ...[
          Icon(
            widget.icon,
            color: textColor,
            size: 20,
          ),
          const SizedBox(width: iOSDesignTokens.space8),
        ],
        Text(
          widget.text,
          style: iOSDesignTokens.labelLarge.copyWith(
            color: textColor,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// Button Style Enum
enum ButtonStyle {
  primary,
  secondary,
  tertiary,
  glass,
}

/// Icon Button with Glass Effect
class GlassIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? iconColor;
  final Color? backgroundColor;
  final double size;
  final String? tooltip;
  final bool enableHapticFeedback;

  const GlassIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.iconColor,
    this.backgroundColor,
    this.size = 44.0,
    this.tooltip,
    this.enableHapticFeedback = true,
  });

  @override
  State<GlassIconButton> createState() => _GlassIconButtonState();
}

class _GlassIconButtonState extends State<GlassIconButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: iOSDesignTokens.durationFast,
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.90).animate(
      CurvedAnimation(
        parent: _scaleController,
        curve: iOSDesignTokens.curveStandard,
      ),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (widget.onPressed != null) {
      _scaleController.forward().then((_) => _scaleController.reverse());
      if (widget.enableHapticFeedback) {
        HapticFeedback.lightImpact();
      }
      widget.onPressed!();
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveBackgroundColor =
        widget.backgroundColor ?? iOSDesignTokens.primary;
    final effectiveIconColor = widget.iconColor ?? iOSDesignTokens.neutralWhite;

    Widget button = ClipRRect(
      borderRadius: BorderRadius.circular(widget.size / 2),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: effectiveBackgroundColor.withOpacity(0.85),
            shape: BoxShape.circle,
            boxShadow: iOSDesignTokens.shadowSmall,
          ),
          child: Icon(
            widget.icon,
            color: effectiveIconColor,
            size: widget.size * 0.45,
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      button = Tooltip(
        message: widget.tooltip!,
        child: button,
      );
    }

    return ScaleTransition(
      scale: _scaleAnimation,
      child: GestureDetector(
        onTap: _handleTap,
        child: button,
      ),
    );
  }
}
