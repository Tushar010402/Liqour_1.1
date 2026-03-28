/// User Management Models - For admin user operations
library;

import '../../../core/utils/date_time_helper.dart';

/// Create User Request
class CreateUserRequest {
  final String username;
  final String? email;            // ✅ NOW OPTIONAL
  final String password;
  final String firstName;
  final String lastName;
  final String? phone;
  final String role;
  final bool isActive;
  final double? salary;          // Optional salary for all roles
  final String? shopId;           // Required for salesman role
  final String? certificateImage; // Optional certificate for salesman

  CreateUserRequest({
    required this.username,
    this.email,                   // ✅ NOW OPTIONAL
    required this.password,
    required this.firstName,
    required this.lastName,
    this.phone,
    required this.role,
    this.isActive = true,
    this.salary,
    this.shopId,
    this.certificateImage,
  });

  Map<String, dynamic> toJson() {
    return {
      'username': username,
      if (email != null && email!.isNotEmpty) 'email': email,  // ✅ Only send if provided
      'password': password,
      'first_name': firstName,
      'last_name': lastName,
      if (phone != null) 'phone': phone,
      'role': role,
      'is_active': isActive,
      if (salary != null) 'salary': salary,
      if (shopId != null) 'shop_id': shopId,
      if (certificateImage != null) 'certificate_image': certificateImage,
    };
  }
}

/// Update User Request - Comprehensive update with all editable fields
class UpdateUserRequest {
  final String? firstName;
  final String? lastName;
  final String? email;
  final String? phone;
  final String? role;
  final String? profileImage;
  final String? certificateImage;
  final bool? isActive;
  final double? salary;
  final String? shopId;

  UpdateUserRequest({
    this.firstName,
    this.lastName,
    this.email,
    this.phone,
    this.role,
    this.profileImage,
    this.certificateImage,
    this.isActive,
    this.salary,
    this.shopId,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (firstName != null) json['first_name'] = firstName;
    if (lastName != null) json['last_name'] = lastName;
    if (email != null) json['email'] = email;
    if (phone != null) json['phone'] = phone;
    if (role != null) json['role'] = role;
    if (profileImage != null) json['profile_image'] = profileImage;
    if (certificateImage != null) json['certificate_image'] = certificateImage;
    if (isActive != null) json['is_active'] = isActive;
    if (salary != null) json['salary'] = salary;
    if (shopId != null) json['shop_id'] = shopId;
    return json;
  }
}

/// User List Response
class UserListResponse {
  final List<UserItem> users;
  final int totalCount;
  final int page;
  final int pageSize;
  final int totalPages;

  UserListResponse({
    required this.users,
    required this.totalCount,
    required this.page,
    required this.pageSize,
    required this.totalPages,
  });

  factory UserListResponse.fromJson(Map<String, dynamic> json) {
    return UserListResponse(
      users: (json['users'] as List<dynamic>?)
              ?.map((e) => UserItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      totalCount: json['total_count'] as int? ?? 0,
      page: json['page'] as int? ?? 1,
      pageSize: json['page_size'] as int? ?? 20,
      totalPages: json['total_pages'] as int? ?? 0,
    );
  }
}

/// User Item - Lightweight user info for listings
class UserItem {
  final String id;
  final String username;
  final String email;
  final String firstName;
  final String lastName;
  final String role;
  final String? phone;
  final String? profileImage;
  final bool isActive;
  final DateTime? createdAt;
  final double? salary;
  final String? shopId;
  final String? shopName;
  final String? certificateImage;

  UserItem({
    required this.id,
    required this.username,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.role,
    this.phone,
    this.profileImage,
    this.isActive = true,
    this.createdAt,
    this.salary,
    this.shopId,
    this.shopName,
    this.certificateImage,
  });

  factory UserItem.fromJson(Map<String, dynamic> json) {
    return UserItem(
      id: json['id'] as String,
      username: json['username'] as String,
      email: json['email'] as String? ?? '',
      firstName: json['first_name'] as String? ?? '',
      lastName: json['last_name'] as String? ?? '',
      role: json['role'] as String,
      phone: json['phone'] as String?,
      profileImage: json['profile_image'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTimeHelper.parseIsoToLocal(json['created_at'] as String?),
      salary: (json['salary'] as num?)?.toDouble(),
      shopId: json['shop_id'] as String?,
      shopName: json['shop_name'] as String?,
      certificateImage: json['certificate_image'] as String?,
    );
  }

  String get displayName => '$firstName $lastName'.trim().isEmpty
      ? username
      : '$firstName $lastName'.trim();

  String get initials {
    final first = firstName.isNotEmpty ? firstName[0] : '';
    final last = lastName.isNotEmpty ? lastName[0] : '';
    return (first + last).toUpperCase();
  }
}

/// User Roles - Matches backend roles
class UserRole {
  static const String admin = 'admin';
  static const String manager = 'manager';
  static const String executive = 'executive';
  static const String salesman = 'salesman';
  static const String assistantManager = 'assistant_manager';
  static const String saasAdmin = 'saas_admin';

  static const List<String> allRoles = [
    admin,
    manager,
    executive,
    assistantManager,
    salesman,
  ];

  static String getDisplayName(String role) {
    switch (role) {
      case admin:
        return 'Admin';
      case manager:
        return 'Manager';
      case executive:
        return 'Executive';
      case assistantManager:
        return 'Assistant Manager';
      case salesman:
        return 'Salesman';
      case saasAdmin:
        return 'SaaS Admin';
      default:
        return role;
    }
  }

  static String getDescription(String role) {
    switch (role) {
      case admin:
        return 'Full access to all features and settings';
      case manager:
        return 'Can manage users, inventory, and operations';
      case executive:
        return 'Access to finance and reporting features';
      case assistantManager:
        return 'Access to finance operations';
      case salesman:
        return 'Access to sales operations';
      case saasAdmin:
        return 'Platform administrator (global access)';
      default:
        return '';
    }
  }

  /// Check if a user can manage other users
  static bool canManageUsers(String role) {
    return role == admin || role == manager;
  }

  /// Check if a user can delete other users
  static bool canDeleteUsers(String role) {
    return role == admin;
  }
}

/// Validation Response - For real-time phone/email validation
class ValidationResponse {
  final bool available;
  final String message;

  ValidationResponse({
    required this.available,
    required this.message,
  });

  factory ValidationResponse.fromJson(Map<String, dynamic> json) {
    return ValidationResponse(
      available: json['available'] as bool? ?? false,
      message: json['message'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'available': available,
      'message': message,
    };
  }
}
