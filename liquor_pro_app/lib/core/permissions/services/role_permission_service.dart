import '../models/role_permission_model.dart';

/// RolePermissionService - Centralized permission logic
///
/// Single source of truth for all role-based permission checks.
/// This service is stateless and contains pure business logic.
///
/// Usage:
/// ```dart
/// final service = RolePermissionService();
/// final result = service.canManageUser(
///   currentRole: AppRole.manager,
///   targetRole: AppRole.salesman,
/// );
/// if (result.allowed) {
///   // Proceed with action
/// } else {
///   // Show error: result.reason
/// }
/// ```
class RolePermissionService {
  // Singleton pattern for global access
  static final RolePermissionService _instance = RolePermissionService._();
  factory RolePermissionService() => _instance;
  RolePermissionService._();

  // ══════════════════════════════════════════════════════════════════════════════
  // User Management Permissions
  // ══════════════════════════════════════════════════════════════════════════════

  /// Check if current user can manage (view/edit/delete) target user
  ///
  /// Rule: Can only manage users with STRICTLY LOWER role levels
  PermissionResult canManageUser({
    required AppRole? currentRole,
    required AppRole? targetRole,
  }) {
    if (currentRole == null) {
      return PermissionResult.denied('Not authenticated');
    }

    // Can always view/edit users if targetRole is null (new user placeholder)
    if (targetRole == null) {
      return PermissionResult.allowed();
    }

    // Rule: Can only manage users with LOWER levels
    if (currentRole.level > targetRole.level) {
      return PermissionResult.allowed();
    }

    return PermissionResult.denied(
      'Cannot manage users with equal or higher role level. '
      'Your role: ${currentRole.displayName}, Target: ${targetRole.displayName}',
    );
  }

  /// Check if current user can create a user with the specified role
  ///
  /// Rule: Can only create users with STRICTLY LOWER role levels
  PermissionResult canCreateUserWithRole({
    required AppRole? currentRole,
    required AppRole targetRole,
  }) {
    if (currentRole == null) {
      return PermissionResult.denied('Not authenticated');
    }

    // Rule: Can only create users with LOWER levels
    if (currentRole.level > targetRole.level) {
      return PermissionResult.allowed();
    }

    return PermissionResult.denied(
      "Cannot create user with role '${targetRole.displayName}'. "
      'You can only create users below your level.',
    );
  }

  /// Check if current user can delete target user
  ///
  /// Additional restriction: Only admin-level and above can delete
  PermissionResult canDeleteUser({
    required AppRole? currentRole,
    required AppRole? targetRole,
  }) {
    if (currentRole == null) {
      return PermissionResult.denied('Not authenticated');
    }

    // Must be at least admin to delete users
    if (!currentRole.isAtLeast(AppRole.admin)) {
      return PermissionResult.denied(
        'Only administrators can delete users',
      );
    }

    if (targetRole == null) {
      return PermissionResult.denied('Target user role not specified');
    }

    // Rule: Can only delete users with LOWER levels
    if (currentRole.level > targetRole.level) {
      return PermissionResult.allowed();
    }

    return PermissionResult.denied(
      "Cannot delete user with role '${targetRole.displayName}'. "
      'You can only delete users below your level.',
    );
  }

  /// Check if current user can change target user's role to newRole
  PermissionResult canChangeUserRole({
    required AppRole? currentRole,
    required AppRole? currentTargetRole,
    required AppRole newRole,
  }) {
    if (currentRole == null) {
      return PermissionResult.denied('Not authenticated');
    }

    // Must be able to manage the user first
    final canManage = canManageUser(
      currentRole: currentRole,
      targetRole: currentTargetRole,
    );
    if (!canManage.allowed) {
      return canManage;
    }

    // Must be able to assign the new role
    return canCreateUserWithRole(
      currentRole: currentRole,
      targetRole: newRole,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // Role Assignment Helpers
  // ══════════════════════════════════════════════════════════════════════════════

  /// Get list of roles that current user can assign to new/edited users
  ///
  /// Returns roles with STRICTLY LOWER levels than current user
  List<AppRole> getAssignableRoles(AppRole? currentRole) {
    if (currentRole == null) return [];

    return AppRole.allRoles
        .where((role) => currentRole.level > role.level)
        .toList();
  }

  /// Get list of tenant-level roles that current user can assign
  /// (excludes saas_admin even if user is saas_admin)
  List<AppRole> getAssignableTenantRoles(AppRole? currentRole) {
    if (currentRole == null) return [];

    return AppRole.tenantRoles
        .where((role) => currentRole.level > role.level)
        .toList();
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // Feature Access Permissions
  // ══════════════════════════════════════════════════════════════════════════════

  /// Check if user can access user management features
  ///
  /// Required: manager level or above
  bool canViewUserManagement(AppRole? role) {
    return role != null && role.isAtLeast(AppRole.manager);
  }

  /// Check if user can create new users
  ///
  /// Required: manager level or above
  bool canCreateUsers(AppRole? role) {
    return role != null && role.isAtLeast(AppRole.manager);
  }

  /// Check if user can delete any users
  ///
  /// Required: admin level or above
  bool canDeleteAnyUsers(AppRole? role) {
    return role != null && role.isAtLeast(AppRole.admin);
  }

  /// Check if user can access tenant management (multi-tenant features)
  ///
  /// Required: saas_admin only
  bool canAccessTenantManagement(AppRole? role) {
    return role != null && role.isExactly(AppRole.saasAdmin);
  }

  /// Check if user can access shop management
  ///
  /// Required: manager level or above (matches backend RoleMiddleware)
  bool canAccessShopManagement(AppRole? role) {
    return role != null && role.isAtLeast(AppRole.manager);
  }

  /// Check if user can access admin routes (/api/admin/*)
  ///
  /// Required: manager level or above for most admin routes
  bool canAccessAdminRoutes(AppRole? role) {
    return role != null && role.isAtLeast(AppRole.manager);
  }

  /// Check if user can access finance features
  ///
  /// Required: assistant_manager level or above
  bool canAccessFinance(AppRole? role) {
    return role != null && role.isAtLeast(AppRole.assistantManager);
  }

  /// Check if user can access reports
  ///
  /// Required: executive level or above
  bool canAccessReports(AppRole? role) {
    return role != null && role.isAtLeast(AppRole.executive);
  }

  /// Check if user can access sales features
  ///
  /// All authenticated users can access sales
  bool canAccessSales(AppRole? role) {
    return role != null;
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // Route-Based Access Control
  // ══════════════════════════════════════════════════════════════════════════════

  /// Route restrictions map: route pattern -> minimum required role
  static final Map<String, AppRole> _routeRestrictions = {
    '/admin/tenants': AppRole.saasAdmin,
    '/admin/users': AppRole.manager,
    '/admin/shops': AppRole.manager, // Manager can manage shops (matches backend)
    '/settings/system': AppRole.admin,
    '/finance': AppRole.assistantManager,
    '/reports': AppRole.executive,
  };

  /// Check if user can access a specific route
  PermissionResult canAccessRoute({
    required AppRole? currentRole,
    required String route,
  }) {
    if (currentRole == null) {
      return PermissionResult.denied('Not authenticated');
    }

    // Check route restrictions
    for (final entry in _routeRestrictions.entries) {
      if (route.startsWith(entry.key)) {
        final requiredRole = entry.value;
        if (currentRole.isAtLeast(requiredRole)) {
          return PermissionResult.allowed();
        }
        return PermissionResult.denied(
          'This page requires ${requiredRole.displayName} access or higher',
        );
      }
    }

    // No restriction found - allow access
    return PermissionResult.allowed();
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // Error Message Helpers
  // ══════════════════════════════════════════════════════════════════════════════

  /// Get user-friendly error message for 403 API errors
  String get403ErrorMessage(String? apiError) {
    if (apiError == null || apiError.isEmpty) {
      return 'You do not have permission to perform this action.';
    }

    final lowerError = apiError.toLowerCase();

    if (lowerError.contains('tenant')) {
      return 'Tenant management requires SaaS Admin access.';
    }
    if (lowerError.contains('create user') && lowerError.contains('role')) {
      return 'You can only create users with roles below your own level.';
    }
    if (lowerError.contains('update user') || lowerError.contains('modify')) {
      return 'You can only modify users with roles below your own level.';
    }
    if (lowerError.contains('delete')) {
      return 'You can only delete users with roles below your own level.';
    }
    if (lowerError.contains('assign role')) {
      return 'You can only assign roles that are below your own level.';
    }
    if (lowerError.contains('shop')) {
      return 'You do not have permission to manage shops.';
    }

    return 'Permission denied: $apiError';
  }
}
