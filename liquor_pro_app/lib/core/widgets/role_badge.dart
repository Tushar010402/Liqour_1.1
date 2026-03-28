import 'package:flutter/material.dart';
import '../permissions/models/role_permission_model.dart';
import '../theme/ios_design_tokens.dart';
import '../utils/responsive_utils.dart';

/// RoleBadge - iOS-style pill badge for displaying user roles
///
/// Features:
/// - Role-specific colors and icons
/// - Compact and expanded modes
/// - Responsive sizing
/// - Optional pulse animation for active status
///
/// Usage:
/// ```dart
/// RoleBadge(role: AppRole.admin)
/// RoleBadge.fromName('manager')
/// RoleBadge.compact(role: AppRole.salesman)
/// ```
class RoleBadge extends StatelessWidget {
  /// The role to display
  final AppRole role;

  /// Whether to use compact mode (smaller, no icon)
  final bool compact;

  /// Whether to show an animated pulse (for active status)
  final bool showPulse;

  /// Optional tap callback
  final VoidCallback? onTap;

  /// Custom text (overrides role.displayName)
  final String? customText;

  const RoleBadge({
    super.key,
    required this.role,
    this.compact = false,
    this.showPulse = false,
    this.onTap,
    this.customText,
  });

  /// Create a role badge from a role name string
  factory RoleBadge.fromName(
    String? roleName, {
    bool compact = false,
    bool showPulse = false,
    VoidCallback? onTap,
  }) {
    final role = AppRole.fromName(roleName) ?? AppRole.salesman;
    return RoleBadge(
      role: role,
      compact: compact,
      showPulse: showPulse,
      onTap: onTap,
    );
  }

  /// Create a compact role badge
  factory RoleBadge.compact({
    required AppRole role,
    bool showPulse = false,
    VoidCallback? onTap,
  }) {
    return RoleBadge(
      role: role,
      compact: true,
      showPulse: showPulse,
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPhone = ResponsiveUtils.isPhone(context);

    // Responsive sizing
    final double height = compact
        ? (isPhone ? 24 : 28)
        : (isPhone ? 28 : 32);
    final double horizontalPadding = compact
        ? (isPhone ? 8 : 10)
        : (isPhone ? 10 : 14);
    final double fontSize = compact
        ? (isPhone ? 11 : 12)
        : (isPhone ? 12 : 13);
    final double iconSize = compact ? 0 : (isPhone ? 14 : 16);

    Widget badge = AnimatedContainer(
      duration: iOSDesignTokens.durationFast,
      height: height,
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      decoration: BoxDecoration(
        color: role.backgroundColor,
        borderRadius: BorderRadius.circular(height / 2),
        border: Border.all(
          color: role.borderColor,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!compact) ...[
            Icon(
              role.icon,
              color: role.color,
              size: iconSize,
            ),
            const SizedBox(width: 6),
          ],
          Text(
            customText ?? role.displayName,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: role.color,
              letterSpacing: 0.2,
            ),
          ),
          if (showPulse) ...[
            const SizedBox(width: 6),
            _PulsingDot(color: role.color),
          ],
        ],
      ),
    );

    if (onTap != null) {
      badge = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(height / 2),
          splashColor: role.color.withOpacity(0.2),
          child: badge,
        ),
      );
    }

    return Semantics(
      label: 'Role: ${role.displayName}',
      child: badge,
    );
  }
}

/// Pulsing dot for active status indication
class _PulsingDot extends StatefulWidget {
  final Color color;

  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: widget.color.withOpacity(_animation.value),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withOpacity(_animation.value * 0.5),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// RoleBadgeList - Display multiple roles in a row
class RoleBadgeList extends StatelessWidget {
  final List<AppRole> roles;
  final bool compact;
  final int maxVisible;
  final MainAxisAlignment alignment;

  const RoleBadgeList({
    super.key,
    required this.roles,
    this.compact = true,
    this.maxVisible = 3,
    this.alignment = MainAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    final visibleRoles = roles.take(maxVisible).toList();
    final remaining = roles.length - maxVisible;

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: alignment,
      children: [
        ...visibleRoles.map((role) => Padding(
              padding: const EdgeInsets.only(right: 6),
              child: RoleBadge(role: role, compact: compact),
            )),
        if (remaining > 0)
          Container(
            height: compact ? 24 : 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: iOSDesignTokens.neutralGray200,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Text(
              '+$remaining',
              style: iOSDesignTokens.labelSmall.copyWith(
                color: iOSDesignTokens.neutralGray600,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

/// StatusBadge - Generic status badge (active/inactive)
class StatusBadge extends StatelessWidget {
  final bool isActive;
  final bool compact;

  const StatusBadge({
    super.key,
    required this.isActive,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? iOSDesignTokens.success : iOSDesignTokens.neutralGray400;
    final text = isActive ? 'Active' : 'Inactive';

    return Container(
      height: compact ? 20 : 24,
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
