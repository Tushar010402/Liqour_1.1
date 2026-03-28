import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../constants/app_colors.dart';
import '../utils/haptic_feedback.dart';

/// Custom Button Widgets - Best Practice Buttons
/// Reusable button components with consistent design and behavior

/// Primary Button - Main action button
class PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final bool isFullWidth;
  final EdgeInsets? padding;
  final Color? backgroundColor;
  final Color? textColor;
  final double? height;
  final double borderRadius;

  const PrimaryButton({
    super.key,
    required this.text,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.isFullWidth = true,
    this.padding,
    this.backgroundColor,
    this.textColor,
    this.height = 56,
    this.borderRadius = 16,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = backgroundColor ?? theme.colorScheme.primary;
    final fgColor = textColor ?? Colors.white;

    final button = ElevatedButton(
      onPressed: isLoading ? null : () {
        HapticFeedbackUtil.medium();
        onPressed?.call();
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: bgColor,
        foregroundColor: fgColor,
        minimumSize: isFullWidth ? Size(double.infinity, height ?? 56) : null,
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        elevation: 2,
        shadowColor: bgColor.withValues(alpha:0.3),
      ),
      child: isLoading
          ? SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(fgColor),
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20),
                  const SizedBox(width: 8),
                ],
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: fgColor,
                  ),
                ),
              ],
            ),
    );

    return button.animate().fadeIn().scale();
  }
}

/// Secondary Button - Secondary action button
class SecondaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isFullWidth;
  final EdgeInsets? padding;
  final Color? borderColor;
  final Color? textColor;
  final double? height;
  final double borderRadius;

  const SecondaryButton({
    super.key,
    required this.text,
    this.onPressed,
    this.icon,
    this.isFullWidth = true,
    this.padding,
    this.borderColor,
    this.textColor,
    this.height = 56,
    this.borderRadius = 16,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bColor = borderColor ?? theme.colorScheme.primary;
    final tColor = textColor ?? theme.colorScheme.primary;

    final button = OutlinedButton(
      onPressed: () {
        HapticFeedbackUtil.light();
        onPressed?.call();
      },
      style: OutlinedButton.styleFrom(
        foregroundColor: tColor,
        minimumSize: isFullWidth ? Size(double.infinity, height ?? 56) : null,
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        side: BorderSide(color: bColor, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20),
            const SizedBox(width: 8),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: tColor,
            ),
          ),
        ],
      ),
    );

    return button.animate().fadeIn().scale();
  }
}

/// Text Button - Tertiary action button
class CustomTextButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? textColor;
  final EdgeInsets? padding;
  final double fontSize;

  const CustomTextButton({
    super.key,
    required this.text,
    this.onPressed,
    this.icon,
    this.textColor,
    this.padding,
    this.fontSize = 16,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = textColor ?? theme.colorScheme.primary;

    return TextButton(
      onPressed: () {
        HapticFeedbackUtil.light();
        onPressed?.call();
      },
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Danger Button - For destructive actions
class DangerButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final bool isFullWidth;
  final double? height;

  const DangerButton({
    super.key,
    required this.text,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.isFullWidth = true,
    this.height = 56,
  });

  @override
  Widget build(BuildContext context) {
    return PrimaryButton(
      text: text,
      onPressed: () {
        HapticFeedbackUtil.heavy();
        onPressed?.call();
      },
      icon: icon ?? Icons.delete,
      isLoading: isLoading,
      isFullWidth: isFullWidth,
      height: height,
      backgroundColor: AppColors.error,
      textColor: Colors.white,
    );
  }
}

/// Icon Button with background - Circular icon button
class IconButtonWithBackground extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? backgroundColor;
  final Color? iconColor;
  final double size;
  final double iconSize;
  final String? tooltip;

  const IconButtonWithBackground({
    super.key,
    required this.icon,
    this.onPressed,
    this.backgroundColor,
    this.iconColor,
    this.size = 48,
    this.iconSize = 24,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = backgroundColor ?? theme.colorScheme.primary.withValues(alpha:0.1);
    final iColor = iconColor ?? theme.colorScheme.primary;

    final button = Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(size / 2),
      child: InkWell(
        onTap: () {
          HapticFeedbackUtil.light();
          onPressed?.call();
        },
        borderRadius: BorderRadius.circular(size / 2),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          child: Icon(
            icon,
            color: iColor,
            size: iconSize,
          ),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(
        message: tooltip!,
        child: button,
      );
    }

    return button.animate().fadeIn().scale();
  }
}

/// Floating Action Button with animation
class AnimatedFAB extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String? label;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final bool isExtended;

  const AnimatedFAB({
    super.key,
    required this.icon,
    required this.onPressed,
    this.label,
    this.backgroundColor,
    this.foregroundColor,
    this.isExtended = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = backgroundColor ?? theme.colorScheme.primary;
    final fgColor = foregroundColor ?? Colors.white;

    if (isExtended && label != null) {
      return FloatingActionButton.extended(
        onPressed: () {
          HapticFeedbackUtil.medium();
          onPressed();
        },
        backgroundColor: bgColor,
        foregroundColor: fgColor,
        icon: Icon(icon),
        label: Text(
          label!,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ).animate().fadeIn().scale();
    }

    return FloatingActionButton(
      onPressed: () {
        HapticFeedbackUtil.medium();
        onPressed();
      },
      backgroundColor: bgColor,
      foregroundColor: fgColor,
      child: Icon(icon),
    ).animate().fadeIn().scale();
  }
}

/// Chip Button - For filters and selections
class ChipButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isSelected;
  final IconData? icon;
  final Color? selectedColor;
  final Color? unselectedColor;

  const ChipButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isSelected = false,
    this.icon,
    this.selectedColor,
    this.unselectedColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final selColor = selectedColor ?? theme.colorScheme.primary;
    final unselColor = unselectedColor ?? cs.outlineVariant;

    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : cs.onSurface,
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : cs.onSurface,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
      selected: isSelected,
      onSelected: onPressed != null ? (selected) {
        HapticFeedbackUtil.light();
        onPressed!();
      } : null,
      backgroundColor: unselColor,
      selectedColor: selColor,
      checkmarkColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ).animate().fadeIn().scale();
  }
}

/// Social Login Button - For OAuth providers
class SocialLoginButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final String iconAsset;
  final Color backgroundColor;
  final Color textColor;

  const SocialLoginButton({
    super.key,
    required this.text,
    required this.onPressed,
    required this.iconAsset,
    this.backgroundColor = Colors.white,
    this.textColor = Colors.black87,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveBg = backgroundColor == Colors.white ? cs.surface : backgroundColor;
    final effectiveText = textColor == Colors.black87 ? cs.onSurface : textColor;
    return ElevatedButton(
      onPressed: () {
        HapticFeedbackUtil.medium();
        onPressed();
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: effectiveBg,
        foregroundColor: effectiveText,
        minimumSize: const Size(double.infinity, 56),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: cs.outlineVariant),
        ),
        elevation: 0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            iconAsset,
            width: 24,
            height: 24,
          ),
          const SizedBox(width: 12),
          Text(
            text,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: effectiveText,
            ),
          ),
        ],
      ),
    ).animate().fadeIn().scale();
  }
}

/// Gradient Button - Button with gradient background
class GradientButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final IconData? icon;
  final List<Color> gradientColors;
  final bool isFullWidth;
  final double? height;

  const GradientButton({
    super.key,
    required this.text,
    this.onPressed,
    this.icon,
    required this.gradientColors,
    this.isFullWidth = true,
    this.height = 56,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: isFullWidth ? double.infinity : null,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: gradientColors[0].withValues(alpha: 0.3)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedbackUtil.medium();
            onPressed?.call();
          },
          borderRadius: BorderRadius.circular(16),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                ],
                Text(
                  text,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn().scale();
  }
}
