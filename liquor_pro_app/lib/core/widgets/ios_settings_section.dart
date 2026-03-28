import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../theme/ios_design_tokens.dart';

/// IOSSettingsSection - iOS Settings app style grouped section
///
/// Creates a grouped list of items with:
/// - Uppercase section header
/// - Rounded corners on first/last items
/// - Inset separators
/// - Chevron indicators for navigation
/// - Lock icon for disabled items
///
/// Usage:
/// ```dart
/// IOSSettingsSection(
///   title: 'ACCOUNT',
///   items: [
///     IOSSettingsItem(
///       icon: CupertinoIcons.person_fill,
///       title: 'Profile',
///       onTap: () => Navigator.push(...),
///     ),
///     IOSSettingsItem(
///       icon: CupertinoIcons.lock_fill,
///       title: 'Security',
///       subtitle: 'Change password, 2FA',
///       onTap: () => Navigator.push(...),
///     ),
///   ],
/// )
/// ```
class IOSSettingsSection extends StatelessWidget {
  /// Section header text (will be uppercased)
  final String? title;

  /// List of settings items
  final List<IOSSettingsItem> items;

  /// Footer text below the section
  final String? footer;

  /// Padding around the section
  final EdgeInsetsGeometry? padding;

  const IOSSettingsSection({
    super.key,
    this.title,
    required this.items,
    this.footer,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          if (title != null && title!.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 8),
              child: Text(
                title!.toUpperCase(),
                style: iOSDesignTokens.labelSmall.copyWith(
                  color: iOSDesignTokens.neutralGray500,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],

          // Items container
          Container(
            decoration: BoxDecoration(
              color: iOSDesignTokens.neutralWhite,
              borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
              boxShadow: [
                BoxShadow(
                  color: iOSDesignTokens.neutralBlack.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
              child: Column(
                children: List.generate(items.length, (index) {
                  final item = items[index];
                  final isFirst = index == 0;
                  final isLast = index == items.length - 1;

                  return Column(
                    children: [
                      _IOSSettingsItemTile(
                        item: item,
                        isFirst: isFirst,
                        isLast: isLast,
                      ),
                      if (!isLast)
                        _InsetDivider(
                          indent: item.icon != null ? 52 : 16,
                        ),
                    ],
                  );
                }),
              ),
            ),
          ),

          // Footer
          if (footer != null && footer!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                footer!,
                style: iOSDesignTokens.labelSmall.copyWith(
                  color: iOSDesignTokens.neutralGray500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// IOSSettingsItem - Data class for a settings item
class IOSSettingsItem {
  /// Leading icon
  final IconData? icon;

  /// Icon background color
  final Color? iconColor;

  /// Item title
  final String title;

  /// Optional subtitle
  final String? subtitle;

  /// Tap callback (null makes it non-interactive)
  final VoidCallback? onTap;

  /// Whether the item is enabled
  final bool enabled;

  /// Optional badge text (e.g., count)
  final String? badge;

  /// Badge color
  final Color? badgeColor;

  /// Trailing widget (overrides default chevron)
  final Widget? trailing;

  /// Whether to show chevron (default: true for onTap items)
  final bool? showChevron;

  /// Whether this is a destructive action (red text)
  final bool destructive;

  const IOSSettingsItem({
    this.icon,
    this.iconColor,
    required this.title,
    this.subtitle,
    this.onTap,
    this.enabled = true,
    this.badge,
    this.badgeColor,
    this.trailing,
    this.showChevron,
    this.destructive = false,
  });
}

class _IOSSettingsItemTile extends StatelessWidget {
  final IOSSettingsItem item;
  final bool isFirst;
  final bool isLast;

  const _IOSSettingsItemTile({
    required this.item,
    required this.isFirst,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveEnabled = item.enabled && item.onTap != null;
    final showChevron = item.showChevron ?? (item.onTap != null && item.trailing == null);
    final textColor = item.destructive
        ? iOSDesignTokens.error
        : (effectiveEnabled
            ? iOSDesignTokens.neutralGray900
            : iOSDesignTokens.neutralGray400);

    Widget content = Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Icon
          if (item.icon != null) ...[
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: item.iconColor ?? iOSDesignTokens.primary,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                item.icon,
                color: iOSDesignTokens.neutralWhite,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
          ],

          // Title & subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.title,
                  style: iOSDesignTokens.bodyLarge.copyWith(
                    color: textColor,
                  ),
                ),
                if (item.subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.subtitle!,
                    style: iOSDesignTokens.bodySmall.copyWith(
                      color: iOSDesignTokens.neutralGray500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),

          // Badge
          if (item.badge != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: (item.badgeColor ?? iOSDesignTokens.primary).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                item.badge!,
                style: iOSDesignTokens.labelSmall.copyWith(
                  color: item.badgeColor ?? iOSDesignTokens.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],

          // Trailing widget or chevron
          if (item.trailing != null) ...[
            const SizedBox(width: 8),
            item.trailing!,
          ] else if (showChevron) ...[
            const SizedBox(width: 8),
            Icon(
              CupertinoIcons.chevron_right,
              color: iOSDesignTokens.neutralGray400,
              size: 18,
            ),
          ],

          // Lock icon for disabled items
          if (!item.enabled && item.onTap != null) ...[
            const SizedBox(width: 8),
            Icon(
              CupertinoIcons.lock_fill,
              color: iOSDesignTokens.neutralGray400,
              size: 16,
            ),
          ],
        ],
      ),
    );

    if (effectiveEnabled) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: item.onTap,
          splashColor: iOSDesignTokens.neutralGray100,
          highlightColor: iOSDesignTokens.neutralGray100,
          child: content,
        ),
      );
    }

    return content;
  }
}

class _InsetDivider extends StatelessWidget {
  final double indent;

  const _InsetDivider({required this.indent});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 0.5,
      margin: EdgeInsets.only(left: indent),
      color: iOSDesignTokens.neutralGray200,
    );
  }
}

/// IOSDestructiveButton - Red "Sign Out" style button
class IOSDestructiveButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool enabled;

  const IOSDestructiveButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: iOSDesignTokens.neutralWhite,
        borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
        boxShadow: [
          BoxShadow(
            color: iOSDesignTokens.neutralBlack.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
          splashColor: iOSDesignTokens.error.withOpacity(0.1),
          highlightColor: iOSDesignTokens.error.withOpacity(0.05),
          child: Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    color: enabled ? iOSDesignTokens.error : iOSDesignTokens.neutralGray400,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: iOSDesignTokens.bodyLarge.copyWith(
                    color: enabled ? iOSDesignTokens.error : iOSDesignTokens.neutralGray400,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// IOSSettingsToggleItem - Settings item with switch
class IOSSettingsToggleItem extends StatelessWidget {
  final IconData? icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;

  const IOSSettingsToggleItem({
    super.key,
    this.icon,
    this.iconColor,
    required this.title,
    this.subtitle,
    required this.value,
    this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: iconColor ?? iOSDesignTokens.primary,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                icon,
                color: iOSDesignTokens.neutralWhite,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: iOSDesignTokens.bodyLarge.copyWith(
                    color: enabled
                        ? iOSDesignTokens.neutralGray900
                        : iOSDesignTokens.neutralGray400,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: iOSDesignTokens.bodySmall.copyWith(
                      color: iOSDesignTokens.neutralGray500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          CupertinoSwitch(
            value: value,
            onChanged: enabled ? onChanged : null,
            activeTrackColor: iOSDesignTokens.success,
          ),
        ],
      ),
    );
  }
}
