import 'package:freezed_annotation/freezed_annotation.dart';

part 'user_model.freezed.dart';
part 'user_model.g.dart';

/// Premium user model with comprehensive profile information
@freezed
class UserModel with _$UserModel {
  const factory UserModel({
    required String id,
    required String email,
    required String firstName,
    required String lastName,
    String? phoneNumber,
    String? businessName,
    String? businessType,
    String? businessAddress,
    String? avatar,
    String? bio,
    required UserRole role,
    required UserStatus status,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? emailVerifiedAt,
    DateTime? phoneVerifiedAt,
    DateTime? lastLoginAt,
    DateTime? lastActiveAt,
    String? timezone,
    String? language,
    String? currency,
    UserPreferences? preferences,
    UserSubscription? subscription,
    UserStats? stats,
    List<String>? permissions,
    Map<String, dynamic>? metadata,
  }) = _UserModel;

  factory UserModel.fromJson(Map<String, dynamic> json) => _$UserModelFromJson(json);
}

/// User role enumeration
@freezed
class UserRole with _$UserRole {
  const factory UserRole.admin() = UserRoleAdmin;
  const factory UserRole.manager() = UserRoleManager;
  const factory UserRole.employee() = UserRoleEmployee;
  const factory UserRole.customer() = UserRoleCustomer;
  const factory UserRole.vendor() = UserRoleVendor;
  
  factory UserRole.fromJson(Map<String, dynamic> json) => _$UserRoleFromJson(json);
}

/// User status enumeration
enum UserStatus {
  @JsonValue('active')
  active,
  
  @JsonValue('inactive')
  inactive,
  
  @JsonValue('suspended')
  suspended,
  
  @JsonValue('pending_verification')
  pendingVerification,
  
  @JsonValue('blocked')
  blocked,
}

/// User preferences model
@freezed
class UserPreferences with _$UserPreferences {
  const factory UserPreferences({
    @Default(true) bool notificationsEnabled,
    @Default(false) bool marketingNotifications,
    @Default(false) bool emailNotifications,
    @Default(true) bool pushNotifications,
    @Default(false) bool smsNotifications,
    @Default('dark') String theme,
    @Default('en') String language,
    @Default('USD') String currency,
    @Default('24h') String timeFormat,
    @Default('MM/dd/yyyy') String dateFormat,
    @Default(true) bool biometricEnabled,
    @Default(false) bool twoFactorEnabled,
    @Default(30) int sessionTimeout, // minutes
    @Default(true) bool autoLogout,
    @Default(false) bool rememberMe,
    Map<String, dynamic>? dashboardSettings,
    Map<String, dynamic>? reportSettings,
    List<String>? favoriteProducts,
    List<String>? quickActions,
  }) = _UserPreferences;

  factory UserPreferences.fromJson(Map<String, dynamic> json) => _$UserPreferencesFromJson(json);
}

/// User subscription model
@freezed
class UserSubscription with _$UserSubscription {
  const factory UserSubscription({
    required String id,
    required String planId,
    required String planName,
    required SubscriptionStatus status,
    required DateTime startDate,
    DateTime? endDate,
    DateTime? trialEndDate,
    bool? cancelAtPeriodEnd,
    String? cancelReason,
    double? monthlyPrice,
    double? yearlyPrice,
    String? currency,
    String? paymentMethod,
    DateTime? lastPaymentDate,
    DateTime? nextPaymentDate,
    List<SubscriptionFeature>? features,
    Map<String, int>? limits,
  }) = _UserSubscription;

  factory UserSubscription.fromJson(Map<String, dynamic> json) => _$UserSubscriptionFromJson(json);
}

/// Subscription status enumeration
enum SubscriptionStatus {
  @JsonValue('active')
  active,
  
  @JsonValue('trial')
  trial,
  
  @JsonValue('past_due')
  pastDue,
  
  @JsonValue('canceled')
  canceled,
  
  @JsonValue('expired')
  expired,
}

/// Subscription feature model
@freezed
class SubscriptionFeature with _$SubscriptionFeature {
  const factory SubscriptionFeature({
    required String id,
    required String name,
    required String description,
    required bool enabled,
    int? limit,
    String? unit,
  }) = _SubscriptionFeature;

  factory SubscriptionFeature.fromJson(Map<String, dynamic> json) => _$SubscriptionFeatureFromJson(json);
}

/// User statistics model
@freezed
class UserStats with _$UserStats {
  const factory UserStats({
    @Default(0) int totalOrders,
    @Default(0) int completedOrders,
    @Default(0) int cancelledOrders,
    @Default(0.0) double totalSpent,
    @Default(0.0) double averageOrderValue,
    @Default(0) int totalProducts,
    @Default(0) int activeProducts,
    @Default(0) int lowStockProducts,
    @Default(0) int outOfStockProducts,
    @Default(0) int totalCustomers,
    @Default(0) int activeCustomers,
    @Default(0) int newCustomersThisMonth,
    @Default(0.0) double totalRevenue,
    @Default(0.0) double monthlyRevenue,
    @Default(0.0) double yearlyRevenue,
    @Default(0) int loginCount,
    DateTime? lastLoginAt,
    @Default(0) int sessionCount,
    @Default(0) int averageSessionDuration, // minutes
    Map<String, dynamic>? additionalStats,
  }) = _UserStats;

  factory UserStats.fromJson(Map<String, dynamic> json) => _$UserStatsFromJson(json);
}

/// User profile extensions
extension UserModelExtensions on UserModel {
  /// Get full name
  String get fullName => '$firstName $lastName';
  
  /// Get display name with fallback
  String get displayName {
    if (firstName.isNotEmpty) return fullName;
    if (businessName != null && businessName!.isNotEmpty) return businessName!;
    return email;
  }
  
  /// Get initials for avatar
  String get initials {
    final first = firstName.isNotEmpty ? firstName[0].toUpperCase() : '';
    final last = lastName.isNotEmpty ? lastName[0].toUpperCase() : '';
    return first + last;
  }
  
  /// Check if user is verified
  bool get isVerified => emailVerifiedAt != null;
  
  /// Check if phone is verified
  bool get isPhoneVerified => phoneVerifiedAt != null;
  
  /// Check if user is active
  bool get isActive => status == UserStatus.active;
  
  /// Check if user is admin
  bool get isAdmin => role is UserRoleAdmin;
  
  /// Check if user is manager
  bool get isManager => role is UserRoleManager || role is UserRoleAdmin;
  
  /// Check if user has permission
  bool hasPermission(String permission) {
    return permissions?.contains(permission) ?? false;
  }
  
  /// Check if user has any of the given permissions
  bool hasAnyPermission(List<String> permissionList) {
    if (permissions == null) return false;
    return permissionList.any((permission) => permissions!.contains(permission));
  }
  
  /// Check if user has all of the given permissions
  bool hasAllPermissions(List<String> permissionList) {
    if (permissions == null) return false;
    return permissionList.every((permission) => permissions!.contains(permission));
  }
  
  /// Get user's subscription status
  bool get hasActiveSubscription => 
      subscription?.status == SubscriptionStatus.active ||
      subscription?.status == SubscriptionStatus.trial;
  
  /// Check if subscription feature is enabled
  bool hasFeature(String featureId) {
    return subscription?.features?.any((feature) => 
        feature.id == featureId && feature.enabled) ?? false;
  }
  
  /// Get feature limit
  int? getFeatureLimit(String featureId) {
    return subscription?.features
        ?.firstWhere((feature) => feature.id == featureId)
        .limit;
  }
  
  /// Check if user is within feature limit
  bool isWithinFeatureLimit(String featureId, int currentUsage) {
    final limit = getFeatureLimit(featureId);
    return limit == null || currentUsage < limit;
  }
  
  /// Get time since last login
  Duration? get timeSinceLastLogin {
    if (lastLoginAt == null) return null;
    return DateTime.now().difference(lastLoginAt!);
  }
  
  /// Get time since last active
  Duration? get timeSinceLastActive {
    if (lastActiveAt == null) return null;
    return DateTime.now().difference(lastActiveAt!);
  }
  
  /// Check if user was recently active (within last 15 minutes)
  bool get isRecentlyActive {
    final timeSince = timeSinceLastActive;
    return timeSince != null && timeSince.inMinutes <= 15;
  }
  
  /// Get user status color for UI
  String get statusColor {
    switch (status) {
      case UserStatus.active:
        return '#10B981'; // Green
      case UserStatus.inactive:
        return '#6B7280'; // Gray
      case UserStatus.suspended:
        return '#F59E0B'; // Amber
      case UserStatus.pendingVerification:
        return '#3B82F6'; // Blue
      case UserStatus.blocked:
        return '#EF4444'; // Red
    }
  }
  
  /// Get role display name
  String get roleDisplayName {
    return role.when(
      admin: () => 'Administrator',
      manager: () => 'Manager',
      employee: () => 'Employee',
      customer: () => 'Customer',
      vendor: () => 'Vendor',
    );
  }
  
  /// Create copy with updated last active timestamp
  UserModel updateLastActive() {
    return copyWith(lastActiveAt: DateTime.now());
  }
  
  /// Create copy with updated preferences
  UserModel updatePreferences(UserPreferences newPreferences) {
    return copyWith(
      preferences: newPreferences,
      updatedAt: DateTime.now(),
    );
  }
  
  /// Convert to JSON for API requests
  Map<String, dynamic> toApiJson() {
    return {
      'id': id,
      'email': email,
      'first_name': firstName,
      'last_name': lastName,
      'phone_number': phoneNumber,
      'business_name': businessName,
      'business_type': businessType,
      'business_address': businessAddress,
      'avatar': avatar,
      'bio': bio,
      'role': role.toJson(),
      'status': status.name,
      'timezone': timezone,
      'language': language,
      'currency': currency,
      'preferences': preferences?.toJson(),
      'metadata': metadata,
    };
  }
}

/// User role extensions
extension UserRoleExtensions on UserRole {
  /// Get role hierarchy level (higher number = more permissions)
  int get hierarchyLevel {
    return when(
      admin: () => 4,
      manager: () => 3,
      employee: () => 2,
      customer: () => 1,
      vendor: () => 1,
    );
  }
  
  /// Check if this role can manage another role
  bool canManage(UserRole otherRole) {
    return hierarchyLevel > otherRole.hierarchyLevel;
  }
  
  /// Get default permissions for this role
  List<String> get defaultPermissions {
    return when(
      admin: () => [
        'users.view',
        'users.create',
        'users.edit',
        'users.delete',
        'products.view',
        'products.create',
        'products.edit',
        'products.delete',
        'orders.view',
        'orders.create',
        'orders.edit',
        'orders.delete',
        'reports.view',
        'reports.export',
        'settings.view',
        'settings.edit',
      ],
      manager: () => [
        'users.view',
        'users.edit',
        'products.view',
        'products.create',
        'products.edit',
        'orders.view',
        'orders.create',
        'orders.edit',
        'reports.view',
        'reports.export',
        'settings.view',
      ],
      employee: () => [
        'products.view',
        'orders.view',
        'orders.create',
        'orders.edit',
        'reports.view',
      ],
      customer: () => [
        'orders.view',
        'orders.create',
      ],
      vendor: () => [
        'products.view',
        'orders.view',
      ],
    );
  }
}