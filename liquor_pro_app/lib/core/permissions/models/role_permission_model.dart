import 'package:flutter/cupertino.dart';

/// AppRole - Immutable role definition with level-based hierarchy
///
/// Backend-aligned role hierarchy:
/// - saas_admin: 100 (Platform super admin)
/// - admin: 90 (Tenant admin)
/// - manager: 70 (Store/branch manager)
/// - assistant_manager: 50 (Assistant manager)
/// - executive: 30 (Sales executive)
/// - salesman: 10 (Salesman)
///
/// Rule: A user can only manage (create/update/delete) users with a LOWER level
class AppRole {
  final String name;
  final int level;
  final String displayName;
  final String description;
  final Color color;
  final IconData icon;

  const AppRole._({
    required this.name,
    required this.level,
    required this.displayName,
    required this.description,
    required this.color,
    required this.icon,
  });

  // ══════════════════════════════════════════════════════════════════════════════
  // Role Constants - Match Backend Exactly
  // ══════════════════════════════════════════════════════════════════════════════

  /// Platform super admin - Full platform access
  static const AppRole saasAdmin = AppRole._(
    name: 'saas_admin',
    level: 100,
    displayName: 'SaaS Admin',
    description: 'Platform administrator with global access',
    color: Color(0xFF5856D6), // Purple - unique for platform level
    icon: CupertinoIcons.shield_fill,
  );

  /// Tenant admin - Full tenant-level access
  static const AppRole admin = AppRole._(
    name: 'admin',
    level: 90,
    displayName: 'Admin',
    description: 'Full access to all features and settings',
    color: Color(0xFFFF3B30), // iOS Red
    icon: CupertinoIcons.person_badge_plus_fill,
  );

  /// Store/branch manager
  static const AppRole manager = AppRole._(
    name: 'manager',
    level: 70,
    displayName: 'Manager',
    description: 'Can manage users, inventory, and operations',
    color: Color(0xFF007AFF), // iOS Blue
    icon: CupertinoIcons.person_2_fill,
  );

  /// Assistant manager
  static const AppRole assistantManager = AppRole._(
    name: 'assistant_manager',
    level: 50,
    displayName: 'Assistant Manager',
    description: 'Access to finance and assistant operations',
    color: Color(0xFFFF9500), // iOS Orange
    icon: CupertinoIcons.person_crop_circle_badge_checkmark,
  );

  /// Sales executive
  static const AppRole executive = AppRole._(
    name: 'executive',
    level: 30,
    displayName: 'Executive',
    description: 'Access to finance and reporting features',
    color: Color(0xFFAF52DE), // iOS Purple
    icon: CupertinoIcons.briefcase_fill,
  );

  /// Salesman
  static const AppRole salesman = AppRole._(
    name: 'salesman',
    level: 10,
    displayName: 'Salesman',
    description: 'Access to sales operations only',
    color: Color(0xFF34C759), // iOS Green
    icon: CupertinoIcons.cart_fill,
  );

  // ══════════════════════════════════════════════════════════════════════════════
  // Static Collections
  // ══════════════════════════════════════════════════════════════════════════════

  /// All roles ordered by level (descending - highest first)
  static const List<AppRole> allRoles = [
    saasAdmin,
    admin,
    manager,
    assistantManager,
    executive,
    salesman,
  ];

  /// Roles available for tenant-level user creation (excludes saas_admin)
  static const List<AppRole> tenantRoles = [
    admin,
    manager,
    assistantManager,
    executive,
    salesman,
  ];

  /// Roles that can access admin features
  static const List<AppRole> adminAccessRoles = [
    saasAdmin,
    admin,
    manager,
  ];

  // ══════════════════════════════════════════════════════════════════════════════
  // Factory Methods
  // ══════════════════════════════════════════════════════════════════════════════

  /// Get AppRole from string name (returns null if not found)
  static AppRole? fromName(String? name) {
    if (name == null || name.isEmpty) return null;

    // Normalize the name (handle underscore/space variations)
    final normalizedName = name.toLowerCase().replaceAll(' ', '_');

    for (final role in allRoles) {
      if (role.name == normalizedName) {
        return role;
      }
    }
    return null;
  }

  /// Get AppRole from level (returns null if not found)
  static AppRole? fromLevel(int level) {
    for (final role in allRoles) {
      if (role.level == level) {
        return role;
      }
    }
    return null;
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // Permission Check Methods
  // ══════════════════════════════════════════════════════════════════════════════

  /// Check if this role can manage (create/update/delete) the target role
  /// Rule: Can only manage users with STRICTLY LOWER levels
  bool canManage(AppRole target) => level > target.level;

  /// Check if this role has equal or higher level than target
  bool hasEqualOrHigherLevel(AppRole target) => level >= target.level;

  /// Check if this role is at least the minimum required role
  bool isAtLeast(AppRole minRole) => level >= minRole.level;

  /// Check if this role is exactly the specified role
  bool isExactly(AppRole role) => name == role.name;

  /// Check if this role is higher than the target role
  bool isHigherThan(AppRole target) => level > target.level;

  // ══════════════════════════════════════════════════════════════════════════════
  // Display Helpers
  // ══════════════════════════════════════════════════════════════════════════════

  /// Get color with optional opacity
  Color colorWithOpacity(double opacity) => color.withOpacity(opacity);

  /// Get background color (10% opacity)
  Color get backgroundColor => color.withOpacity(0.10);

  /// Get border color (30% opacity)
  Color get borderColor => color.withOpacity(0.30);

  // ══════════════════════════════════════════════════════════════════════════════
  // Equality & HashCode
  // ══════════════════════════════════════════════════════════════════════════════

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppRole && other.name == name;
  }

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'AppRole($name, level: $level)';
}

/// PermissionResult - Result of a permission check with optional reason
class PermissionResult {
  final bool allowed;
  final String? reason;

  const PermissionResult._({
    required this.allowed,
    this.reason,
  });

  /// Create an allowed result
  factory PermissionResult.allowed() => const PermissionResult._(allowed: true);

  /// Create a denied result with optional reason
  factory PermissionResult.denied([String? reason]) => PermissionResult._(
        allowed: false,
        reason: reason,
      );

  /// Convenience getter for denied state
  bool get denied => !allowed;

  @override
  String toString() =>
      'PermissionResult(${allowed ? 'allowed' : 'denied'}${reason != null ? ', reason: $reason' : ''})';
}

/// PermissionContext - Context for permission checks
class PermissionContext {
  final AppRole? currentUserRole;
  final String? tenantId;

  const PermissionContext({
    this.currentUserRole,
    this.tenantId,
  });

  bool get isAuthenticated => currentUserRole != null;
  bool get hasTenant => tenantId != null && tenantId!.isNotEmpty;
}
