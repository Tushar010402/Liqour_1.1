import 'package:flutter/foundation.dart';
import '../models/role_permission_model.dart';
import '../services/role_permission_service.dart';

/// PermissionProvider - Bridges permission service with Flutter state management
///
/// This provider listens to AuthProvider for role changes and provides
/// reactive permission state to the UI layer.
///
/// Usage:
/// ```dart
/// // In widget
/// Consumer<PermissionProvider>(
///   builder: (context, permissions, _) {
///     if (permissions.canViewUserManagement) {
///       return UserManagementScreen();
///     }
///     return PermissionDeniedScreen();
///   },
/// )
/// ```
class PermissionProvider extends ChangeNotifier {
  final RolePermissionService _permissionService;

  AppRole? _currentUserRole;
  String? _tenantId;
  bool _isInitialized = false;

  PermissionProvider({RolePermissionService? permissionService})
      : _permissionService = permissionService ?? RolePermissionService();

  // ══════════════════════════════════════════════════════════════════════════════
  // State Getters
  // ══════════════════════════════════════════════════════════════════════════════

  /// Current user's role (null if not authenticated)
  AppRole? get currentUserRole => _currentUserRole;

  /// Current user's role name (empty string if not authenticated)
  String get currentRoleName => _currentUserRole?.name ?? '';

  /// Current tenant ID
  String? get tenantId => _tenantId;

  /// Whether the provider has been initialized with a role
  bool get isInitialized => _isInitialized;

  /// Whether user is authenticated (has a role)
  bool get isAuthenticated => _currentUserRole != null;

  // ══════════════════════════════════════════════════════════════════════════════
  // State Setters
  // ══════════════════════════════════════════════════════════════════════════════

  /// Set the current user's role (call when user logs in or role changes)
  ///
  /// [roleName] - The role name from the API (e.g., 'admin', 'manager')
  /// [tenantId] - Optional tenant ID for multi-tenant context
  void setCurrentRole(String? roleName, {String? tenantId}) {
    final newRole = AppRole.fromName(roleName);
    final changed = _currentUserRole != newRole || _tenantId != tenantId;

    _currentUserRole = newRole;
    _tenantId = tenantId;
    _isInitialized = true;

    if (changed) {
      notifyListeners();
    }
  }

  /// Clear the current role (call on logout)
  void clearRole() {
    final hadRole = _currentUserRole != null;
    _currentUserRole = null;
    _tenantId = null;
    _isInitialized = false;

    if (hadRole) {
      notifyListeners();
    }
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // User Management Permissions
  // ══════════════════════════════════════════════════════════════════════════════

  /// Check if current user can manage (view/edit) a user with the given role
  bool canManageUser(AppRole? targetRole) {
    return _permissionService
        .canManageUser(
          currentRole: _currentUserRole,
          targetRole: targetRole,
        )
        .allowed;
  }

  /// Check if current user can manage a user by role name
  bool canManageUserByRoleName(String? targetRoleName) {
    return canManageUser(AppRole.fromName(targetRoleName));
  }

  /// Check if current user can create a user with the specified role
  bool canCreateWithRole(AppRole targetRole) {
    return _permissionService
        .canCreateUserWithRole(
          currentRole: _currentUserRole,
          targetRole: targetRole,
        )
        .allowed;
  }

  /// Check if current user can create a user with the specified role name
  bool canCreateWithRoleName(String? targetRoleName) {
    final role = AppRole.fromName(targetRoleName);
    if (role == null) return false;
    return canCreateWithRole(role);
  }

  /// Check if current user can delete a user with the given role
  bool canDeleteUser(AppRole? targetRole) {
    return _permissionService
        .canDeleteUser(
          currentRole: _currentUserRole,
          targetRole: targetRole,
        )
        .allowed;
  }

  /// Check if current user can delete a user by role name
  bool canDeleteUserByRoleName(String? targetRoleName) {
    return canDeleteUser(AppRole.fromName(targetRoleName));
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // Role Assignment
  // ══════════════════════════════════════════════════════════════════════════════

  /// Get list of roles that current user can assign
  List<AppRole> get assignableRoles =>
      _permissionService.getAssignableRoles(_currentUserRole);

  /// Get list of role names that current user can assign
  List<String> get assignableRoleNames =>
      assignableRoles.map((r) => r.name).toList();

  /// Get list of tenant-level roles that current user can assign
  List<AppRole> get assignableTenantRoles =>
      _permissionService.getAssignableTenantRoles(_currentUserRole);

  /// Check if a role is assignable by current user
  bool isRoleAssignable(String? roleName) {
    if (roleName == null) return false;
    return assignableRoleNames.contains(roleName);
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // Feature Access Permissions
  // ══════════════════════════════════════════════════════════════════════════════

  /// Can access user management features (manager+)
  bool get canViewUserManagement =>
      _permissionService.canViewUserManagement(_currentUserRole);

  /// Can create new users (manager+)
  bool get canCreateUsers =>
      _permissionService.canCreateUsers(_currentUserRole);

  /// Alias for canViewUserManagement + canCreateUsers (manager+)
  bool get canManageUsers =>
      canViewUserManagement && canCreateUsers;

  /// Can delete users (admin+)
  bool get canDeleteAnyUsers =>
      _permissionService.canDeleteAnyUsers(_currentUserRole);

  /// Alias for canDeleteAnyUsers
  bool get canDeleteUsers => canDeleteAnyUsers;

  /// Can access tenant management (saas_admin only)
  bool get canAccessTenantManagement =>
      _permissionService.canAccessTenantManagement(_currentUserRole);

  /// Can access shop management (admin+)
  bool get canAccessShopManagement =>
      _permissionService.canAccessShopManagement(_currentUserRole);

  /// Can access admin routes (manager+)
  bool get canAccessAdminRoutes =>
      _permissionService.canAccessAdminRoutes(_currentUserRole);

  /// Can access finance features (assistant_manager+)
  bool get canAccessFinance =>
      _permissionService.canAccessFinance(_currentUserRole);

  /// Can access reports (executive+)
  bool get canAccessReports =>
      _permissionService.canAccessReports(_currentUserRole);

  /// Can access sales features (all authenticated users)
  bool get canAccessSales => _permissionService.canAccessSales(_currentUserRole);

  // ══════════════════════════════════════════════════════════════════════════════
  // Route Access
  // ══════════════════════════════════════════════════════════════════════════════

  /// Check if current user can access a specific route
  bool canAccessRoute(String route) {
    return _permissionService
        .canAccessRoute(
          currentRole: _currentUserRole,
          route: route,
        )
        .allowed;
  }

  /// Get permission result for a route (includes reason if denied)
  PermissionResult getRoutePermission(String route) {
    return _permissionService.canAccessRoute(
      currentRole: _currentUserRole,
      route: route,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // Role Comparison Helpers
  // ══════════════════════════════════════════════════════════════════════════════

  /// Check if current user is at least the specified role level
  bool isAtLeast(AppRole minRole) {
    return _currentUserRole?.isAtLeast(minRole) ?? false;
  }

  /// Check if current user is at least the specified role by name
  bool isAtLeastByName(String? roleName) {
    final role = AppRole.fromName(roleName);
    if (role == null) return false;
    return isAtLeast(role);
  }

  /// Check if current user is exactly the specified role
  bool isExactly(AppRole role) {
    return _currentUserRole?.isExactly(role) ?? false;
  }

  /// Check if current user is exactly the specified role by name
  bool isExactlyByName(String? roleName) {
    final role = AppRole.fromName(roleName);
    if (role == null) return false;
    return isExactly(role);
  }

  /// Check if current user is a SaaS admin
  bool get isSaasAdmin => isExactly(AppRole.saasAdmin);

  /// Check if current user is an admin (or higher)
  bool get isAdmin => isAtLeast(AppRole.admin);

  /// Check if current user is a manager (or higher)
  bool get isManager => isAtLeast(AppRole.manager);

  // ══════════════════════════════════════════════════════════════════════════════
  // Error Handling
  // ══════════════════════════════════════════════════════════════════════════════

  /// Get user-friendly message for a 403 API error
  String get403ErrorMessage(String? apiError) {
    return _permissionService.get403ErrorMessage(apiError);
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // Debug Helpers
  // ══════════════════════════════════════════════════════════════════════════════

  @override
  String toString() {
    return 'PermissionProvider('
        'role: ${_currentUserRole?.name ?? 'none'}, '
        'tenantId: $_tenantId, '
        'initialized: $_isInitialized)';
  }

  /// Get debug info for logging
  Map<String, dynamic> get debugInfo => {
        'currentRole': _currentUserRole?.name,
        'roleLevel': _currentUserRole?.level,
        'tenantId': _tenantId,
        'isInitialized': _isInitialized,
        'canViewUserManagement': canViewUserManagement,
        'canCreateUsers': canCreateUsers,
        'canDeleteAnyUsers': canDeleteAnyUsers,
        'canAccessTenantManagement': canAccessTenantManagement,
        'assignableRoles': assignableRoleNames,
      };
}
