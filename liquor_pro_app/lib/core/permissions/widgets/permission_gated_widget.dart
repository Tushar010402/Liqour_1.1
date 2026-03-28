import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/role_permission_model.dart';
import '../providers/permission_provider.dart';

/// PermissionGated - Conditionally renders child based on permission check
///
/// Declarative widget for hiding/showing UI based on user permissions.
/// Provides fallback widget when permission is denied.
///
/// Usage:
/// ```dart
/// // Simple minimum role check
/// PermissionGated.minimumRole(
///   minimumRole: AppRole.manager,
///   child: AddUserButton(),
/// )
///
/// // Check if can manage specific user
/// PermissionGated.canManageUser(
///   targetUserRole: user.role,
///   child: EditDeleteButtons(),
/// )
///
/// // Custom permission check
/// PermissionGated(
///   check: (p) => p.canAccessFinance && p.canAccessReports,
///   child: FinanceReportsTab(),
///   fallback: DisabledTab(),
/// )
/// ```
class PermissionGated extends StatelessWidget {
  /// The widget to show when permission is granted
  final Widget child;

  /// Optional widget to show when permission is denied
  /// Defaults to SizedBox.shrink() (invisible)
  final Widget? fallback;

  /// The permission check function
  final bool Function(PermissionProvider) check;

  /// Optional callback when permission is denied and user tries to interact
  final VoidCallback? onDenied;

  /// Whether to animate the transition between child and fallback
  final bool animated;

  /// Animation duration
  final Duration animationDuration;

  const PermissionGated({
    super.key,
    required this.child,
    required this.check,
    this.fallback,
    this.onDenied,
    this.animated = false,
    this.animationDuration = const Duration(milliseconds: 200),
  });

  // ══════════════════════════════════════════════════════════════════════════════
  // Convenience Constructors
  // ══════════════════════════════════════════════════════════════════════════════

  /// Show child only if user is at least the specified role level
  factory PermissionGated.minimumRole({
    Key? key,
    required AppRole minimumRole,
    required Widget child,
    Widget? fallback,
    VoidCallback? onDenied,
    bool animated = false,
  }) {
    return PermissionGated(
      key: key,
      check: (p) => p.currentUserRole?.isAtLeast(minimumRole) ?? false,
      onDenied: onDenied,
      animated: animated,
      fallback: fallback,
      child: child,
    );
  }

  /// Show child only if user can manage the target user
  factory PermissionGated.canManageUser({
    Key? key,
    required AppRole? targetUserRole,
    required Widget child,
    Widget? fallback,
    VoidCallback? onDenied,
    bool animated = false,
  }) {
    return PermissionGated(
      key: key,
      check: (p) => p.canManageUser(targetUserRole),
      onDenied: onDenied,
      animated: animated,
      fallback: fallback,
      child: child,
    );
  }

  /// Show child only if user can manage the target user by role name
  factory PermissionGated.canManageUserByRole({
    Key? key,
    required String? targetRoleName,
    required Widget child,
    Widget? fallback,
    VoidCallback? onDenied,
    bool animated = false,
  }) {
    return PermissionGated(
      key: key,
      check: (p) => p.canManageUserByRoleName(targetRoleName),
      onDenied: onDenied,
      animated: animated,
      fallback: fallback,
      child: child,
    );
  }

  /// Show child only if user can delete the target user
  factory PermissionGated.canDeleteUser({
    Key? key,
    required AppRole? targetUserRole,
    required Widget child,
    Widget? fallback,
    VoidCallback? onDenied,
    bool animated = false,
  }) {
    return PermissionGated(
      key: key,
      check: (p) => p.canDeleteUser(targetUserRole),
      onDenied: onDenied,
      animated: animated,
      fallback: fallback,
      child: child,
    );
  }

  /// Show child only if user can view user management
  factory PermissionGated.userManagement({
    Key? key,
    required Widget child,
    Widget? fallback,
    VoidCallback? onDenied,
    bool animated = false,
  }) {
    return PermissionGated(
      key: key,
      check: (p) => p.canViewUserManagement,
      onDenied: onDenied,
      animated: animated,
      fallback: fallback,
      child: child,
    );
  }

  /// Show child only if user can access tenant management (SaaS admin)
  factory PermissionGated.tenantManagement({
    Key? key,
    required Widget child,
    Widget? fallback,
    VoidCallback? onDenied,
    bool animated = false,
  }) {
    return PermissionGated(
      key: key,
      check: (p) => p.canAccessTenantManagement,
      onDenied: onDenied,
      animated: animated,
      fallback: fallback,
      child: child,
    );
  }

  /// Show child only if user can access shop management
  factory PermissionGated.shopManagement({
    Key? key,
    required Widget child,
    Widget? fallback,
    VoidCallback? onDenied,
    bool animated = false,
  }) {
    return PermissionGated(
      key: key,
      check: (p) => p.canAccessShopManagement,
      onDenied: onDenied,
      animated: animated,
      fallback: fallback,
      child: child,
    );
  }

  /// Show child only if user can access finance features
  factory PermissionGated.finance({
    Key? key,
    required Widget child,
    Widget? fallback,
    VoidCallback? onDenied,
    bool animated = false,
  }) {
    return PermissionGated(
      key: key,
      check: (p) => p.canAccessFinance,
      onDenied: onDenied,
      animated: animated,
      fallback: fallback,
      child: child,
    );
  }

  /// Show child only if user is authenticated
  factory PermissionGated.authenticated({
    Key? key,
    required Widget child,
    Widget? fallback,
    VoidCallback? onDenied,
    bool animated = false,
  }) {
    return PermissionGated(
      key: key,
      check: (p) => p.isAuthenticated,
      onDenied: onDenied,
      animated: animated,
      fallback: fallback,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PermissionProvider>(
      builder: (context, permissionProvider, _) {
        final hasPermission = check(permissionProvider);

        if (hasPermission) {
          if (animated) {
            return AnimatedSwitcher(
              duration: animationDuration,
              child: child,
            );
          }
          return child;
        }

        final fallbackWidget = fallback ?? const SizedBox.shrink();

        if (animated) {
          return AnimatedSwitcher(
            duration: animationDuration,
            child: fallbackWidget,
          );
        }

        return fallbackWidget;
      },
    );
  }
}

/// PermissionBuilder - More flexible version that provides permission state
///
/// Use when you need access to permission state in the builder function.
///
/// Usage:
/// ```dart
/// PermissionBuilder(
///   builder: (context, permissions, child) {
///     return ListTile(
///       title: Text('User Management'),
///       enabled: permissions.canViewUserManagement,
///       trailing: permissions.canViewUserManagement
///         ? Icon(Icons.chevron_right)
///         : Icon(Icons.lock),
///     );
///   },
/// )
/// ```
class PermissionBuilder extends StatelessWidget {
  /// Builder function that receives permission provider
  final Widget Function(
    BuildContext context,
    PermissionProvider permissions,
    Widget? child,
  ) builder;

  /// Optional static child widget (for optimization)
  final Widget? child;

  const PermissionBuilder({
    super.key,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<PermissionProvider>(
      builder: (context, permissions, _) => builder(context, permissions, child),
      child: child,
    );
  }
}
