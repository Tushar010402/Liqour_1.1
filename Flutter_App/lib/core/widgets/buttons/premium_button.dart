import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_typography.dart';

/// Premium button widget with multiple variants and animations
class PremiumButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final PremiumButtonVariant variant;
  final PremiumButtonSize size;
  final IconData? icon;
  final Widget? child;
  final bool isLoading;
  final bool isDisabled;
  final double? width;
  final EdgeInsetsGeometry? padding;
  final BorderRadiusGeometry? borderRadius;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? borderColor;
  final double? elevation;
  final bool enableFeedback;
  final Duration animationDuration;

  const PremiumButton({
    super.key,
    required this.text,
    this.onPressed,
    this.variant = PremiumButtonVariant.primary,
    this.size = PremiumButtonSize.medium,
    this.icon,
    this.child,
    this.isLoading = false,
    this.isDisabled = false,
    this.width,
    this.padding,
    this.borderRadius,
    this.backgroundColor,
    this.foregroundColor,
    this.borderColor,
    this.elevation,
    this.enableFeedback = true,
    this.animationDuration = const Duration(milliseconds: 150),
  });

  const PremiumButton.primary({
    super.key,
    required this.text,
    this.onPressed,
    this.size = PremiumButtonSize.medium,
    this.icon,
    this.child,
    this.isLoading = false,
    this.isDisabled = false,
    this.width,
    this.padding,
    this.borderRadius,
    this.backgroundColor,
    this.foregroundColor,
    this.borderColor,
    this.elevation,
    this.enableFeedback = true,
    this.animationDuration = const Duration(milliseconds: 150),
  }) : variant = PremiumButtonVariant.primary;

  const PremiumButton.secondary({
    super.key,
    required this.text,
    this.onPressed,
    this.size = PremiumButtonSize.medium,
    this.icon,
    this.child,
    this.isLoading = false,
    this.isDisabled = false,
    this.width,
    this.padding,
    this.borderRadius,
    this.backgroundColor,
    this.foregroundColor,
    this.borderColor,
    this.elevation,
    this.enableFeedback = true,
    this.animationDuration = const Duration(milliseconds: 150),
  }) : variant = PremiumButtonVariant.secondary;

  const PremiumButton.outline({
    super.key,
    required this.text,
    this.onPressed,
    this.size = PremiumButtonSize.medium,
    this.icon,
    this.child,
    this.isLoading = false,
    this.isDisabled = false,
    this.width,
    this.padding,
    this.borderRadius,
    this.backgroundColor,
    this.foregroundColor,
    this.borderColor,
    this.elevation,
    this.enableFeedback = true,
    this.animationDuration = const Duration(milliseconds: 150),
  }) : variant = PremiumButtonVariant.outline;

  const PremiumButton.ghost({
    super.key,
    required this.text,
    this.onPressed,
    this.size = PremiumButtonSize.medium,
    this.icon,
    this.child,
    this.isLoading = false,
    this.isDisabled = false,
    this.width,
    this.padding,
    this.borderRadius,
    this.backgroundColor,
    this.foregroundColor,
    this.borderColor,
    this.elevation,
    this.enableFeedback = true,
    this.animationDuration = const Duration(milliseconds: 150),
  }) : variant = PremiumButtonVariant.ghost;

  const PremiumButton.danger({
    super.key,
    required this.text,
    this.onPressed,
    this.size = PremiumButtonSize.medium,
    this.icon,
    this.child,
    this.isLoading = false,
    this.isDisabled = false,
    this.width,
    this.padding,
    this.borderRadius,
    this.backgroundColor,
    this.foregroundColor,
    this.borderColor,
    this.elevation,
    this.enableFeedback = true,
    this.animationDuration = const Duration(milliseconds: 150),
  }) : variant = PremiumButtonVariant.danger;

  @override
  State<PremiumButton> createState() => _PremiumButtonState();
}

class _PremiumButtonState extends State<PremiumButton> with TickerProviderStateMixin {
  late AnimationController _animationController;
  late AnimationController _loadingController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _loadingAnimation;
  
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );
    
    _loadingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _loadingAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _loadingController,
      curve: Curves.easeInOut,
    ));

    if (widget.isLoading) {
      _loadingController.repeat();
    }
  }

  @override
  void didUpdateWidget(PremiumButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (widget.isLoading != oldWidget.isLoading) {
      if (widget.isLoading) {
        _loadingController.repeat();
      } else {
        _loadingController.stop();
        _loadingController.reset();
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _loadingController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    if (!_canInteract) return;
    
    setState(() => _isPressed = true);
    _animationController.forward();
  }

  void _onTapUp(TapUpDetails details) {
    if (!_canInteract) return;
    
    setState(() => _isPressed = false);
    _animationController.reverse();
  }

  void _onTapCancel() {
    setState(() => _isPressed = false);
    _animationController.reverse();
  }

  void _onTap() {
    if (!_canInteract) return;
    
    if (widget.enableFeedback) {
      HapticFeedback.lightImpact();
    }
    
    widget.onPressed?.call();
  }

  bool get _canInteract => 
      widget.onPressed != null && 
      !widget.isLoading && 
      !widget.isDisabled;

  @override
  Widget build(BuildContext context) {
    final buttonStyle = _getButtonStyle(context);
    
    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: SizedBox(
            width: widget.width,
            height: buttonStyle.height,
            child: GestureDetector(
              onTapDown: _onTapDown,
              onTapUp: _onTapUp,
              onTapCancel: _onTapCancel,
              onTap: _onTap,
              child: AnimatedContainer(
                duration: widget.animationDuration,
                decoration: BoxDecoration(
                  color: buttonStyle.backgroundColor,
                  borderRadius: widget.borderRadius ?? BorderRadius.circular(buttonStyle.borderRadius),
                  border: buttonStyle.border,
                  gradient: buttonStyle.gradient,
                  boxShadow: _canInteract ? buttonStyle.boxShadow : null,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: widget.padding ?? EdgeInsets.symmetric(
                      horizontal: buttonStyle.horizontalPadding,
                      vertical: buttonStyle.verticalPadding,
                    ),
                    child: _buildButtonContent(context, buttonStyle),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildButtonContent(BuildContext context, _ButtonStyle buttonStyle) {
    if (widget.child != null) {
      return Center(child: widget.child!);
    }

    final textWidget = Text(
      widget.text,
      style: buttonStyle.textStyle,
      textAlign: TextAlign.center,
      overflow: TextOverflow.ellipsis,
    );

    if (widget.isLoading) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: buttonStyle.iconSize,
            height: buttonStyle.iconSize,
            child: AnimatedBuilder(
              animation: _loadingAnimation,
              builder: (context, child) {
                return Transform.rotate(
                  angle: _loadingAnimation.value * 2 * 3.14159,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.0,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      buttonStyle.textStyle.color!,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          textWidget,
        ],
      );
    }

    if (widget.icon != null) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            widget.icon,
            size: buttonStyle.iconSize,
            color: buttonStyle.textStyle.color,
          ),
          const SizedBox(width: 8),
          textWidget,
        ],
      );
    }

    return Center(child: textWidget);
  }

  _ButtonStyle _getButtonStyle(BuildContext context) {
    final isDisabled = !_canInteract;
    
    switch (widget.variant) {
      case PremiumButtonVariant.primary:
        return _ButtonStyle(
          backgroundColor: isDisabled 
              ? AppColors.disabledGrey
              : widget.backgroundColor ?? AppColors.premiumGold,
          textStyle: _getTextStyle().copyWith(
            color: isDisabled 
                ? AppColors.mutedWhite 
                : widget.foregroundColor ?? AppColors.premiumBlack,
          ),
          gradient: isDisabled ? null : AppColors.goldGradient,
          boxShadow: isDisabled ? null : [
            BoxShadow(
              color: AppColors.premiumGold.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
          height: _getHeight(),
          borderRadius: _getBorderRadius(),
          horizontalPadding: _getHorizontalPadding(),
          verticalPadding: _getVerticalPadding(),
          iconSize: _getIconSize(),
        );
        
      case PremiumButtonVariant.secondary:
        return _ButtonStyle(
          backgroundColor: isDisabled 
              ? AppColors.disabledGrey
              : widget.backgroundColor ?? AppColors.cardGrey,
          textStyle: _getTextStyle().copyWith(
            color: isDisabled 
                ? AppColors.mutedWhite 
                : widget.foregroundColor ?? AppColors.primaryWhite,
          ),
          boxShadow: isDisabled ? null : [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
          height: _getHeight(),
          borderRadius: _getBorderRadius(),
          horizontalPadding: _getHorizontalPadding(),
          verticalPadding: _getVerticalPadding(),
          iconSize: _getIconSize(),
        );
        
      case PremiumButtonVariant.outline:
        return _ButtonStyle(
          backgroundColor: Colors.transparent,
          border: Border.all(
            color: isDisabled 
                ? AppColors.disabledGrey 
                : widget.borderColor ?? AppColors.premiumGold,
            width: 1.5,
          ),
          textStyle: _getTextStyle().copyWith(
            color: isDisabled 
                ? AppColors.disabledGrey 
                : widget.foregroundColor ?? AppColors.premiumGold,
          ),
          height: _getHeight(),
          borderRadius: _getBorderRadius(),
          horizontalPadding: _getHorizontalPadding(),
          verticalPadding: _getVerticalPadding(),
          iconSize: _getIconSize(),
        );
        
      case PremiumButtonVariant.ghost:
        return _ButtonStyle(
          backgroundColor: _isPressed && _canInteract 
              ? AppColors.hoverGrey 
              : Colors.transparent,
          textStyle: _getTextStyle().copyWith(
            color: isDisabled 
                ? AppColors.disabledGrey 
                : widget.foregroundColor ?? AppColors.primaryWhite,
          ),
          height: _getHeight(),
          borderRadius: _getBorderRadius(),
          horizontalPadding: _getHorizontalPadding(),
          verticalPadding: _getVerticalPadding(),
          iconSize: _getIconSize(),
        );
        
      case PremiumButtonVariant.danger:
        return _ButtonStyle(
          backgroundColor: isDisabled 
              ? AppColors.disabledGrey
              : widget.backgroundColor ?? AppColors.errorRed,
          textStyle: _getTextStyle().copyWith(
            color: isDisabled 
                ? AppColors.mutedWhite 
                : widget.foregroundColor ?? AppColors.primaryWhite,
          ),
          boxShadow: isDisabled ? null : [
            BoxShadow(
              color: AppColors.errorRed.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
          height: _getHeight(),
          borderRadius: _getBorderRadius(),
          horizontalPadding: _getHorizontalPadding(),
          verticalPadding: _getVerticalPadding(),
          iconSize: _getIconSize(),
        );
    }
  }

  TextStyle _getTextStyle() {
    switch (widget.size) {
      case PremiumButtonSize.small:
        return AppTypography.buttonSmall;
      case PremiumButtonSize.medium:
        return AppTypography.buttonMedium;
      case PremiumButtonSize.large:
        return AppTypography.buttonLarge;
    }
  }

  double _getHeight() {
    switch (widget.size) {
      case PremiumButtonSize.small:
        return 40.0;
      case PremiumButtonSize.medium:
        return 48.0;
      case PremiumButtonSize.large:
        return 56.0;
    }
  }

  double _getBorderRadius() {
    switch (widget.size) {
      case PremiumButtonSize.small:
        return 8.0;
      case PremiumButtonSize.medium:
        return 12.0;
      case PremiumButtonSize.large:
        return 16.0;
    }
  }

  double _getHorizontalPadding() {
    switch (widget.size) {
      case PremiumButtonSize.small:
        return 16.0;
      case PremiumButtonSize.medium:
        return 24.0;
      case PremiumButtonSize.large:
        return 32.0;
    }
  }

  double _getVerticalPadding() {
    return 0.0; // Height is controlled by container height
  }

  double _getIconSize() {
    switch (widget.size) {
      case PremiumButtonSize.small:
        return 16.0;
      case PremiumButtonSize.medium:
        return 20.0;
      case PremiumButtonSize.large:
        return 24.0;
    }
  }
}

enum PremiumButtonVariant {
  primary,
  secondary,
  outline,
  ghost,
  danger,
}

enum PremiumButtonSize {
  small,
  medium,
  large,
}

class _ButtonStyle {
  final Color? backgroundColor;
  final Border? border;
  final Gradient? gradient;
  final List<BoxShadow>? boxShadow;
  final TextStyle textStyle;
  final double height;
  final double borderRadius;
  final double horizontalPadding;
  final double verticalPadding;
  final double iconSize;

  const _ButtonStyle({
    this.backgroundColor,
    this.border,
    this.gradient,
    this.boxShadow,
    required this.textStyle,
    required this.height,
    required this.borderRadius,
    required this.horizontalPadding,
    required this.verticalPadding,
    required this.iconSize,
  });
}