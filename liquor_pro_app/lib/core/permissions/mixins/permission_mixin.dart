import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/role_permission_model.dart';
import '../providers/permission_provider.dart';
import '../../theme/ios_design_tokens.dart';

/// PermissionMixin - Mixin providing permission helpers to StatefulWidgets
///
/// Provides convenient access to permission checks and UI helpers
/// without boilerplate code.
///
/// Usage:
/// ```dart
/// class _MyScreenState extends State<MyScreen> with PermissionMixin {
///   @override
///   Widget build(BuildContext context) {
///     if (!canViewUserManagement) {
///       return PermissionDeniedWidget();
///     }
///
///     return ListView.builder(
///       itemBuilder: (context, index) {
///         final user = users[index];
///         return ListTile(
///           title: Text(user.name),
///           trailing: canManageUserByRoleName(user.role)
///             ? EditButton(onTap: () => editUser(user))
///             : null,
///         );
///       },
///     );
///   }
/// }
/// ```
mixin PermissionMixin<T extends StatefulWidget> on State<T> {
  PermissionProvider? _permissionProvider;

  // ══════════════════════════════════════════════════════════════════════════════
  // Provider Access
  // ══════════════════════════════════════════════════════════════════════════════

  /// Get the permission provider (cached for performance)
  PermissionProvider get permissionProvider {
    _permissionProvider ??= context.read<PermissionProvider>();
    return _permissionProvider!;
  }

  /// Get the permission provider with listen (for reactive updates)
  PermissionProvider get permissionProviderWatch {
    return context.watch<PermissionProvider>();
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // Current User Info
  // ══════════════════════════════════════════════════════════════════════════════

  /// Current user's role
  AppRole? get currentUserRole => permissionProvider.currentUserRole;

  /// Current user's role name
  String get currentRoleName => permissionProvider.currentRoleName;

  /// Whether user is authenticated
  bool get isAuthenticated => permissionProvider.isAuthenticated;

  // ══════════════════════════════════════════════════════════════════════════════
  // User Management Permissions
  // ══════════════════════════════════════════════════════════════════════════════

  /// Check if current user can manage a specific target user
  bool canManageUser(AppRole? targetRole) =>
      permissionProvider.canManageUser(targetRole);

  /// Check if current user can manage a user by role name
  bool canManageUserByRoleName(String? targetRoleName) =>
      permissionProvider.canManageUserByRoleName(targetRoleName);

  /// Check if current user can create a user with the specified role
  bool canCreateWithRole(AppRole targetRole) =>
      permissionProvider.canCreateWithRole(targetRole);

  /// Check if current user can delete a user with the given role
  bool canDeleteUser(AppRole? targetRole) =>
      permissionProvider.canDeleteUser(targetRole);

  /// Check if current user can delete a user by role name
  bool canDeleteUserByRoleName(String? targetRoleName) =>
      permissionProvider.canDeleteUserByRoleName(targetRoleName);

  // ══════════════════════════════════════════════════════════════════════════════
  // Role Assignment
  // ══════════════════════════════════════════════════════════════════════════════

  /// Get list of roles that current user can assign
  List<AppRole> get assignableRoles => permissionProvider.assignableRoles;

  /// Get list of role names that current user can assign
  List<String> get assignableRoleNames => permissionProvider.assignableRoleNames;

  /// Check if a role is assignable by current user
  bool isRoleAssignable(String? roleName) =>
      permissionProvider.isRoleAssignable(roleName);

  // ══════════════════════════════════════════════════════════════════════════════
  // Feature Access
  // ══════════════════════════════════════════════════════════════════════════════

  /// Can access user management (manager+)
  bool get canViewUserManagement => permissionProvider.canViewUserManagement;

  /// Can create users (manager+)
  bool get canCreateUsers => permissionProvider.canCreateUsers;

  /// Can delete any users (admin+)
  bool get canDeleteAnyUsers => permissionProvider.canDeleteAnyUsers;

  /// Can access tenant management (saas_admin only)
  bool get canAccessTenantManagement =>
      permissionProvider.canAccessTenantManagement;

  /// Can access shop management (admin+)
  bool get canAccessShopManagement => permissionProvider.canAccessShopManagement;

  /// Can access admin routes (manager+)
  bool get canAccessAdminRoutes => permissionProvider.canAccessAdminRoutes;

  /// Can access finance (assistant_manager+)
  bool get canAccessFinance => permissionProvider.canAccessFinance;

  /// Can access reports (executive+)
  bool get canAccessReports => permissionProvider.canAccessReports;

  // ══════════════════════════════════════════════════════════════════════════════
  // Role Checks
  // ══════════════════════════════════════════════════════════════════════════════

  /// Is current user a SaaS admin
  bool get isSaasAdmin => permissionProvider.isSaasAdmin;

  /// Is current user an admin (or higher)
  bool get isAdmin => permissionProvider.isAdmin;

  /// Is current user a manager (or higher)
  bool get isManager => permissionProvider.isManager;

  /// Is current user at least the specified role level
  bool isAtLeast(AppRole minRole) => permissionProvider.isAtLeast(minRole);

  // ══════════════════════════════════════════════════════════════════════════════
  // UI Helpers
  // ══════════════════════════════════════════════════════════════════════════════

  /// Show permission denied snackbar with optional custom message
  void showPermissionDenied([String? message]) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.lock_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message ?? 'You do not have permission for this action',
                style: iOSDesignTokens.bodyMedium.copyWith(
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: iOSDesignTokens.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
        ),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  /// Show 403 error with user-friendly message
  void show403Error(String? apiError) {
    if (!mounted) return;

    final message = permissionProvider.get403ErrorMessage(apiError);
    showPermissionDenied(message);
  }

  /// Show permission denied dialog with more details
  void showPermissionDeniedDialog({
    String? title,
    String? message,
    String? requiredRole,
    VoidCallback? onContactAdmin,
  }) {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(iOSDesignTokens.radiusLarge),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iOSDesignTokens.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.lock_outline,
                color: iOSDesignTokens.error,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title ?? 'Access Restricted',
                style: iOSDesignTokens.headlineMedium.copyWith(
                  color: iOSDesignTokens.neutralGray900,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message ?? 'You do not have permission to perform this action.',
              style: iOSDesignTokens.bodyMedium.copyWith(
                color: iOSDesignTokens.neutralGray700,
              ),
            ),
            if (requiredRole != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: iOSDesignTokens.neutralGray100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: iOSDesignTokens.neutralGray600,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Required role: $requiredRole',
                        style: iOSDesignTokens.labelMedium.copyWith(
                          color: iOSDesignTokens.neutralGray700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: iOSDesignTokens.neutralGray100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.person_outline,
                    color: iOSDesignTokens.neutralGray600,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Your role: ${currentUserRole?.displayName ?? 'None'}',
                    style: iOSDesignTokens.labelMedium.copyWith(
                      color: iOSDesignTokens.neutralGray700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (onContactAdmin != null)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                onContactAdmin();
              },
              child: Text(
                'Contact Admin',
                style: TextStyle(color: iOSDesignTokens.primary),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'OK',
              style: TextStyle(
                color: iOSDesignTokens.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// PermissionStatelessMixin - Extension for StatelessWidget permission access
///
/// Since mixins can't be used with StatelessWidget directly,
/// use this extension method instead.
extension PermissionContext on BuildContext {
  /// Get permission provider
  PermissionProvider get permissions => read<PermissionProvider>();

  /// Watch permission provider (reactive)
  PermissionProvider get watchPermissions => watch<PermissionProvider>();

  /// Quick check: can view user management
  bool get canViewUserManagement => permissions.canViewUserManagement;

  /// Quick check: can access tenant management
  bool get canAccessTenantManagement => permissions.canAccessTenantManagement;

  /// Quick check: is admin or higher
  bool get isAdmin => permissions.isAdmin;

  /// Quick check: is manager or higher
  bool get isManager => permissions.isManager;
}
