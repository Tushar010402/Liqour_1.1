import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_typography.dart';

/// Premium app bar with enhanced styling and functionality
class PremiumAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final Widget? titleWidget;
  final List<Widget>? actions;
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final bool centerTitle;
  final double? elevation;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final SystemUiOverlayStyle? systemOverlayStyle;
  final double toolbarHeight;
  final double? leadingWidth;
  final bool? primary;
  final EdgeInsetsGeometry? titleSpacing;
  final double titleTextScaleFactor;
  final PreferredSizeWidget? bottom;
  final Clip clipBehavior;
  final PremiumAppBarVariant variant;
  final bool showBackButton;
  final VoidCallback? onBackPressed;
  final bool showLogo;
  final String? logoText;
  final Widget? logoWidget;
  final bool showNotificationBadge;
  final int notificationCount;

  const PremiumAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.centerTitle = true,
    this.elevation,
    this.backgroundColor,
    this.foregroundColor,
    this.systemOverlayStyle,
    this.toolbarHeight = kToolbarHeight,
    this.leadingWidth,
    this.primary,
    this.titleSpacing,
    this.titleTextScaleFactor = 1.0,
    this.bottom,
    this.clipBehavior = Clip.none,
    this.variant = PremiumAppBarVariant.elevated,
    this.showBackButton = false,
    this.onBackPressed,
    this.showLogo = false,
    this.logoText,
    this.logoWidget,
    this.showNotificationBadge = false,
    this.notificationCount = 0,
  });

  const PremiumAppBar.transparent({
    super.key,
    this.title,
    this.titleWidget,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.centerTitle = true,
    this.elevation,
    this.backgroundColor,
    this.foregroundColor,
    this.systemOverlayStyle,
    this.toolbarHeight = kToolbarHeight,
    this.leadingWidth,
    this.primary,
    this.titleSpacing,
    this.titleTextScaleFactor = 1.0,
    this.bottom,
    this.clipBehavior = Clip.none,
    this.showBackButton = false,
    this.onBackPressed,
    this.showLogo = false,
    this.logoText,
    this.logoWidget,
    this.showNotificationBadge = false,
    this.notificationCount = 0,
  }) : variant = PremiumAppBarVariant.transparent;

  const PremiumAppBar.gradient({
    super.key,
    this.title,
    this.titleWidget,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.centerTitle = true,
    this.elevation,
    this.backgroundColor,
    this.foregroundColor,
    this.systemOverlayStyle,
    this.toolbarHeight = kToolbarHeight,
    this.leadingWidth,
    this.primary,
    this.titleSpacing,
    this.titleTextScaleFactor = 1.0,
    this.bottom,
    this.clipBehavior = Clip.none,
    this.showBackButton = false,
    this.onBackPressed,
    this.showLogo = false,
    this.logoText,
    this.logoWidget,
    this.showNotificationBadge = false,
    this.notificationCount = 0,
  }) : variant = PremiumAppBarVariant.gradient;

  const PremiumAppBar.glass({
    super.key,
    this.title,
    this.titleWidget,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.centerTitle = true,
    this.elevation,
    this.backgroundColor,
    this.foregroundColor,
    this.systemOverlayStyle,
    this.toolbarHeight = kToolbarHeight,
    this.leadingWidth,
    this.primary,
    this.titleSpacing,
    this.titleTextScaleFactor = 1.0,
    this.bottom,
    this.clipBehavior = Clip.none,
    this.showBackButton = false,
    this.onBackPressed,
    this.showLogo = false,
    this.logoText,
    this.logoWidget,
    this.showNotificationBadge = false,
    this.notificationCount = 0,
  }) : variant = PremiumAppBarVariant.glass;

  @override
  Size get preferredSize => Size.fromHeight(
    toolbarHeight + (bottom?.preferredSize.height ?? 0.0),
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _getDecoration(),
      child: AppBar(
        title: _buildTitle(),
        actions: _buildActions(),
        leading: _buildLeading(context),
        automaticallyImplyLeading: automaticallyImplyLeading && !showBackButton,
        centerTitle: centerTitle,
        elevation: _getElevation(),
        backgroundColor: Colors.transparent,
        foregroundColor: foregroundColor ?? _getForegroundColor(),
        systemOverlayStyle: systemOverlayStyle ?? _getSystemOverlayStyle(),
        toolbarHeight: toolbarHeight,
        leadingWidth: leadingWidth,
        primary: primary ?? true,
        titleSpacing: titleSpacing,
        titleTextStyle: _getTitleStyle(),
        bottom: bottom,
        clipBehavior: clipBehavior,
      ),
    );
  }

  Widget? _buildTitle() {
    if (titleWidget != null) return titleWidget;
    
    if (showLogo) {
      return _buildLogo();
    }
    
    if (title != null) {
      return Text(
        title!,
        style: _getTitleStyle(),
        textScaleFactor: titleTextScaleFactor,
      );
    }
    
    return null;
  }

  Widget _buildLogo() {
    if (logoWidget != null) return logoWidget!;
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            gradient: AppColors.goldGradient,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.local_drink,
            color: AppColors.premiumBlack,
            size: 20,
          ),
        ),
        if (logoText != null) ...[
          const SizedBox(width: 8),
          Text(
            logoText!,
            style: AppTypography.headlineSmall.copyWith(
              color: AppColors.premiumGold,
              fontWeight: AppTypography.bold,
            ),
          ),
        ],
      ],
    );
  }

  Widget? _buildLeading(BuildContext context) {
    if (leading != null) return leading;
    
    if (showBackButton) {
      return IconButton(
        onPressed: onBackPressed ?? () => Navigator.of(context).pop(),
        icon: const Icon(Icons.arrow_back_ios_new),
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      );
    }
    
    return null;
  }

  List<Widget>? _buildActions() {
    final actionList = <Widget>[];
    
    if (actions != null) {
      actionList.addAll(actions!);
    }
    
    // Add notification icon with badge if enabled
    if (showNotificationBadge) {
      actionList.add(
        Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: Stack(
            children: [
              IconButton(
                onPressed: () {
                  // Handle notification tap
                },
                icon: const Icon(Icons.notifications_outlined),
                tooltip: 'Notifications',
              ),
              if (notificationCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.errorRed,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 20,
                      minHeight: 20,
                    ),
                    child: Text(
                      notificationCount > 99 ? '99+' : notificationCount.toString(),
                      style: AppTypography.captionSmall.copyWith(
                        color: AppColors.primaryWhite,
                        fontWeight: AppTypography.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    
    return actionList.isNotEmpty ? actionList : null;
  }

  BoxDecoration _getDecoration() {
    switch (variant) {
      case PremiumAppBarVariant.elevated:
        return BoxDecoration(
          color: backgroundColor ?? AppColors.premiumBlack,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: elevation ?? 4.0,
              offset: Offset(0, elevation ?? 4.0),
            ),
          ],
        );
        
      case PremiumAppBarVariant.transparent:
        return const BoxDecoration(
          color: Colors.transparent,
        );
        
      case PremiumAppBarVariant.gradient:
        return BoxDecoration(
          gradient: AppColors.goldGradient,
        );
        
      case PremiumAppBarVariant.glass:
        return BoxDecoration(
          color: AppColors.glassBackground,
          border: const Border(
            bottom: BorderSide(
              color: AppColors.glassBorder,
              width: 1.0,
            ),
          ),
        );
    }
  }

  double _getElevation() {
    switch (variant) {
      case PremiumAppBarVariant.elevated:
        return elevation ?? 4.0;
      case PremiumAppBarVariant.transparent:
      case PremiumAppBarVariant.gradient:
      case PremiumAppBarVariant.glass:
        return 0.0;
    }
  }

  Color _getForegroundColor() {
    switch (variant) {
      case PremiumAppBarVariant.elevated:
      case PremiumAppBarVariant.transparent:
      case PremiumAppBarVariant.glass:
        return AppColors.primaryWhite;
      case PremiumAppBarVariant.gradient:
        return AppColors.premiumBlack;
    }
  }

  SystemUiOverlayStyle _getSystemOverlayStyle() {
    switch (variant) {
      case PremiumAppBarVariant.elevated:
        return const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        );
      case PremiumAppBarVariant.transparent:
        return const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        );
      case PremiumAppBarVariant.gradient:
        return const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        );
      case PremiumAppBarVariant.glass:
        return const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        );
    }
  }

  TextStyle _getTitleStyle() {
    final baseStyle = AppTypography.headlineSmall.copyWith(
      color: _getForegroundColor(),
      fontWeight: AppTypography.semiBold,
    );
    
    return baseStyle;
  }
}

enum PremiumAppBarVariant {
  elevated,
  transparent,
  gradient,
  glass,
}

/// Sliver app bar variant
class PremiumSliverAppBar extends StatelessWidget {
  final String? title;
  final Widget? titleWidget;
  final List<Widget>? actions;
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final double expandedHeight;
  final double? collapsedHeight;
  final bool pinned;
  final bool floating;
  final bool snap;
  final double? elevation;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Widget? background;
  final bool stretch;
  final double stretchTriggerOffset;
  final AsyncCallback? onStretchTrigger;
  final PremiumAppBarVariant variant;
  final bool showBackButton;
  final VoidCallback? onBackPressed;
  final FlexibleSpaceBar? flexibleSpace;

  const PremiumSliverAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.expandedHeight = 200.0,
    this.collapsedHeight,
    this.pinned = true,
    this.floating = false,
    this.snap = false,
    this.elevation,
    this.backgroundColor,
    this.foregroundColor,
    this.background,
    this.stretch = false,
    this.stretchTriggerOffset = 100.0,
    this.onStretchTrigger,
    this.variant = PremiumAppBarVariant.elevated,
    this.showBackButton = false,
    this.onBackPressed,
    this.flexibleSpace,
  });

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      title: _buildTitle(),
      actions: actions,
      leading: _buildLeading(context),
      automaticallyImplyLeading: automaticallyImplyLeading && !showBackButton,
      expandedHeight: expandedHeight,
      collapsedHeight: collapsedHeight,
      pinned: pinned,
      floating: floating,
      snap: snap,
      elevation: _getElevation(),
      backgroundColor: _getBackgroundColor(),
      foregroundColor: foregroundColor ?? _getForegroundColor(),
      stretch: stretch,
      stretchTriggerOffset: stretchTriggerOffset,
      onStretchTrigger: onStretchTrigger,
      flexibleSpace: flexibleSpace ?? _buildFlexibleSpace(),
    );
  }

  Widget? _buildTitle() {
    if (titleWidget != null) return titleWidget;
    
    if (title != null) {
      return Text(
        title!,
        style: AppTypography.headlineSmall.copyWith(
          color: _getForegroundColor(),
          fontWeight: AppTypography.semiBold,
        ),
      );
    }
    
    return null;
  }

  Widget? _buildLeading(BuildContext context) {
    if (leading != null) return leading;
    
    if (showBackButton) {
      return IconButton(
        onPressed: onBackPressed ?? () => Navigator.of(context).pop(),
        icon: const Icon(Icons.arrow_back_ios_new),
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      );
    }
    
    return null;
  }

  Widget? _buildFlexibleSpace() {
    if (background == null && variant != PremiumAppBarVariant.gradient) {
      return null;
    }
    
    return FlexibleSpaceBar(
      background: Container(
        decoration: _getFlexibleDecoration(),
        child: background,
      ),
    );
  }

  BoxDecoration _getFlexibleDecoration() {
    switch (variant) {
      case PremiumAppBarVariant.elevated:
        return BoxDecoration(
          color: backgroundColor ?? AppColors.premiumBlack,
        );
        
      case PremiumAppBarVariant.transparent:
        return const BoxDecoration(
          color: Colors.transparent,
        );
        
      case PremiumAppBarVariant.gradient:
        return BoxDecoration(
          gradient: AppColors.goldGradient,
        );
        
      case PremiumAppBarVariant.glass:
        return BoxDecoration(
          color: AppColors.glassBackground,
        );
    }
  }

  double _getElevation() {
    switch (variant) {
      case PremiumAppBarVariant.elevated:
        return elevation ?? 4.0;
      case PremiumAppBarVariant.transparent:
      case PremiumAppBarVariant.gradient:
      case PremiumAppBarVariant.glass:
        return 0.0;
    }
  }

  Color _getBackgroundColor() {
    switch (variant) {
      case PremiumAppBarVariant.elevated:
        return backgroundColor ?? AppColors.premiumBlack;
      case PremiumAppBarVariant.transparent:
        return Colors.transparent;
      case PremiumAppBarVariant.gradient:
        return Colors.transparent;
      case PremiumAppBarVariant.glass:
        return AppColors.glassBackground;
    }
  }

  Color _getForegroundColor() {
    switch (variant) {
      case PremiumAppBarVariant.elevated:
      case PremiumAppBarVariant.transparent:
      case PremiumAppBarVariant.glass:
        return AppColors.primaryWhite;
      case PremiumAppBarVariant.gradient:
        return AppColors.premiumBlack;
    }
  }
}

/// App bar action button
class AppBarActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool showBadge;
  final int badgeCount;
  final Color? badgeColor;
  final Color? iconColor;

  const AppBarActionButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.showBadge = false,
    this.badgeCount = 0,
    this.badgeColor,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final button = IconButton(
      onPressed: onPressed,
      icon: Icon(icon, color: iconColor),
      tooltip: tooltip,
    );

    if (!showBadge || badgeCount == 0) {
      return button;
    }

    return Stack(
      children: [
        button,
        Positioned(
          right: 8,
          top: 8,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: badgeColor ?? AppColors.errorRed,
              borderRadius: BorderRadius.circular(10),
            ),
            constraints: const BoxConstraints(
              minWidth: 20,
              minHeight: 20,
            ),
            child: Text(
              badgeCount > 99 ? '99+' : badgeCount.toString(),
              style: AppTypography.captionSmall.copyWith(
                color: AppColors.primaryWhite,
                fontWeight: AppTypography.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }
}