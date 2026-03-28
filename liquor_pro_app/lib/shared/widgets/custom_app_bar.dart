import 'package:flutter/material.dart';
import '../../core/constants/app_text_styles.dart';

/// Custom App Bar Widget — matches JSX PageHeader design.
/// JSX: hamburger icon (3 bars) + centered title (fontSize 20, fontWeight 800)
/// + right spacer for balance. White bg, border-bottom #EAEDF1.
class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final Widget? leading;
  final PreferredSizeWidget? bottom;
  final bool centerTitle;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double elevation;

  const CustomAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.bottom,
    this.centerTitle = true,
    this.backgroundColor,
    this.foregroundColor,
    this.elevation = 0,
  });

  @override
  Widget build(BuildContext context) {
    final appBarTheme = Theme.of(context).appBarTheme;
    final effectiveBg = backgroundColor ?? appBarTheme.backgroundColor;
    final effectiveFg = foregroundColor ?? appBarTheme.foregroundColor;

    return AppBar(
      title: Text(
        title,
        style: AppTextStyles.h5.copyWith(
          color: effectiveFg ?? const Color(0xFF1A1A2E),
          fontWeight: FontWeight.w800,
          fontSize: 20,
          letterSpacing: -0.2,
        ),
      ),
      leading: leading,
      actions: actions,
      centerTitle: centerTitle,
      backgroundColor: effectiveBg ?? Colors.white,
      foregroundColor: effectiveFg ?? const Color(0xFF1A1A2E),
      elevation: elevation,
      surfaceTintColor: Colors.transparent,
      bottom: bottom ?? PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: const Color(0xFFEAEDF1)),
      ),
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(
    kToolbarHeight + (bottom?.preferredSize.height ?? 1),
  );
}
