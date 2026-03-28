import 'package:flutter/material.dart';
import 'dart:ui';
import '../theme/ios_design_tokens.dart';

/// Glass Card - iOS 16 Liquid Glass Design
///
/// A translucent card with blur effect that adapts to content behind it,
/// simulating real-world glass optical qualities.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final Color? backgroundColor;
  final double backgroundOpacity;
  final double blurSigma;
  final BorderRadius? borderRadius;
  final List<BoxShadow>? shadows;
  final Border? border;
  final VoidCallback? onTap;
  final bool enableHapticFeedback;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.backgroundColor,
    this.backgroundOpacity = 0.70,
    this.blurSigma = 20.0,
    this.borderRadius,
    this.shadows,
    this.border,
    this.onTap,
    this.enableHapticFeedback = true,
  });

  /// Predefined styles
  factory GlassCard.light({
    required Widget child,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    VoidCallback? onTap,
  }) {
    return GlassCard(
      backgroundColor: iOSDesignTokens.neutralWhite,
      backgroundOpacity: 0.70,
      blurSigma: 20.0,
      padding: padding,
      margin: margin,
      onTap: onTap,
      child: child,
    );
  }

  factory GlassCard.heavy({
    required Widget child,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    VoidCallback? onTap,
  }) {
    return GlassCard(
      backgroundColor: iOSDesignTokens.neutralWhite,
      backgroundOpacity: 0.85,
      blurSigma: 30.0,
      padding: padding,
      margin: margin,
      shadows: iOSDesignTokens.shadowMedium,
      onTap: onTap,
      child: child,
    );
  }

  factory GlassCard.subtle({
    required Widget child,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    VoidCallback? onTap,
  }) {
    return GlassCard(
      backgroundColor: iOSDesignTokens.neutralWhite,
      backgroundOpacity: 0.50,
      blurSigma: 10.0,
      padding: padding,
      margin: margin,
      onTap: onTap,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveBackgroundColor = backgroundColor ?? iOSDesignTokens.neutralWhite;
    final effectiveBorderRadius = borderRadius ?? iOSDesignTokens.borderRadiusCard;
    final effectiveShadows = shadows ?? iOSDesignTokens.shadowSmall;

    Widget cardContent = ClipRRect(
      borderRadius: effectiveBorderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          width: width,
          height: height,
          padding: padding ?? const EdgeInsets.all(iOSDesignTokens.space16),
          decoration: BoxDecoration(
            color: effectiveBackgroundColor.withOpacity(backgroundOpacity),
            borderRadius: effectiveBorderRadius,
            border: border ??
                Border.all(
                  color: iOSDesignTokens.neutralWhite.withOpacity(0.20),
                  width: 1.5,
                ),
            boxShadow: effectiveShadows,
          ),
          child: child,
        ),
      ),
    );

    if (onTap != null) {
      return Container(
        margin: margin,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              if (enableHapticFeedback) {
                // HapticFeedback.lightImpact(); // Uncomment when testing on device
              }
              onTap!();
            },
            borderRadius: effectiveBorderRadius,
            splashColor: iOSDesignTokens.primary.withOpacity(0.10),
            highlightColor: iOSDesignTokens.primary.withOpacity(0.05),
            child: cardContent,
          ),
        ),
      );
    }

    return Container(
      margin: margin,
      child: cardContent,
    );
  }
}

/// Glass Card Variants

/// Stat Card - For displaying statistics with icon and value
class GlassStatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color iconColor;
  final Color? valueColor;
  final String? subtitle;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;

  const GlassStatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    this.iconColor = iOSDesignTokens.primary,
    this.valueColor,
    this.subtitle,
    this.onTap,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard.light(
      margin: margin,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: iOSDesignTokens.labelMedium.copyWith(
                    color: iOSDesignTokens.neutralGray600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(iOSDesignTokens.space8),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.10),
                  borderRadius: iOSDesignTokens.borderRadiusSmall,
                ),
                child: Icon(
                  icon,
                  color: iconColor,
                  size: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: iOSDesignTokens.space12),
          Text(
            value,
            style: iOSDesignTokens.displaySmall.copyWith(
              color: valueColor ?? iOSDesignTokens.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: iOSDesignTokens.space4),
            Text(
              subtitle!,
              style: iOSDesignTokens.bodySmall.copyWith(
                color: iOSDesignTokens.neutralGray500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Info Card - For informational messages
class GlassInfoCard extends StatelessWidget {
  final String title;
  final String? message;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final Widget? action;

  const GlassInfoCard({
    super.key,
    required this.title,
    this.message,
    required this.icon,
    this.color = iOSDesignTokens.info,
    this.onTap,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard.light(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(iOSDesignTokens.space12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: iOSDesignTokens.borderRadiusSmall,
            ),
            child: Icon(
              icon,
              color: color,
              size: 24,
            ),
          ),
          const SizedBox(width: iOSDesignTokens.space16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: iOSDesignTokens.headlineSmall.copyWith(
                    color: iOSDesignTokens.neutralGray900,
                  ),
                ),
                if (message != null) ...[
                  const SizedBox(height: iOSDesignTokens.space4),
                  Text(
                    message!,
                    style: iOSDesignTokens.bodySmall.copyWith(
                      color: iOSDesignTokens.neutralGray600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: iOSDesignTokens.space12),
            action!,
          ],
        ],
      ),
    );
  }
}

/// List Card - For list items with glass effect
class GlassListCard extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;

  const GlassListCard({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard.light(
      margin: margin,
      onTap: onTap,
      padding: const EdgeInsets.all(iOSDesignTokens.space16),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: iOSDesignTokens.space16),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: iOSDesignTokens.bodyLarge.copyWith(
                    fontWeight: FontWeight.w600,
                    color: iOSDesignTokens.neutralGray900,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: iOSDesignTokens.space4),
                  Text(
                    subtitle!,
                    style: iOSDesignTokens.bodySmall.copyWith(
                      color: iOSDesignTokens.neutralGray600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: iOSDesignTokens.space12),
            trailing!,
          ],
        ],
      ),
    );
  }
}
