/// User Model - Matches backend UserResponse structure
class UserModel {
  final String id; // UUID from backend
  final String username;
  final String email;
  final String firstName;
  final String lastName;
  final String role;
  final String? phone;
  final String? tenantId; // UUID from backend (extracted from tenant object)
  final String? tenantName;
  final String? profileImage;
  final bool isActive;
  final DateTime? createdAt;

  UserModel({
    required this.id,
    required this.username,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.role,
    this.phone,
    this.tenantId,
    this.tenantName,
    this.profileImage,
    this.isActive = true,
    this.createdAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      username: json['username'] as String,
      email: json['email'] as String,
      firstName: json['first_name'] as String? ?? '',
      lastName: json['last_name'] as String? ?? '',
      role: json['role'] as String,
      phone: json['phone'] as String?,
      tenantId: json['tenant_id'] as String?, // Will be added by AuthProvider
      tenantName: json['tenant_name'] as String?,
      profileImage: json['profile_image'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'first_name': firstName,
      'last_name': lastName,
      'role': role,
      'phone': phone,
      'tenant_id': tenantId,
      'tenant_name': tenantName,
      'profile_image': profileImage,
      'is_active': isActive,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  String get displayName => '$firstName $lastName'.trim().isEmpty
      ? username
      : '$firstName $lastName'.trim();

  String get fullName => '$firstName $lastName'.trim();
}

/// Login Request - Backend expects "username" field
class LoginRequest {
  final String email;
  final String password;

  LoginRequest({
    required this.email,
    required this.password,
  });

  Map<String, dynamic> toJson() {
    return {
      'username': email, // Backend accepts email OR username in "username" field
      'password': password,
    };
  }
}

/// Login Response - Matches backend structure
class LoginResponse {
  final String token;
  final String? refreshToken;
  final DateTime? expiresAt;
  final UserModel user;
  final TenantModel? tenant;

  LoginResponse({
    required this.token,
    this.refreshToken,
    this.expiresAt,
    required this.user,
    this.tenant,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    // Extract user data
    final userData = json['user'] as Map<String, dynamic>;

    // Extract tenant ID from tenant object if exists
    final tenantData = json['tenant'] as Map<String, dynamic>?;
    if (tenantData != null && tenantData['id'] != null) {
      userData['tenant_id'] = tenantData['id'] as String;
      userData['tenant_name'] = tenantData['name'] as String?;
    }

    return LoginResponse(
      token: json['token'] as String,
      refreshToken: json['refresh_token'] as String?,
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : null,
      user: UserModel.fromJson(userData),
      tenant: tenantData != null ? TenantModel.fromJson(tenantData) : null,
    );
  }
}

/// Tenant Model
class TenantModel {
  final String id;
  final String name;
  final String? domain;
  final bool isActive;

  TenantModel({
    required this.id,
    required this.name,
    this.domain,
    this.isActive = true,
  });

  factory TenantModel.fromJson(Map<String, dynamic> json) {
    return TenantModel(
      id: json['id'] as String,
      name: json['name'] as String,
      domain: json['domain'] as String?,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'domain': domain,
      'is_active': isActive,
    };
  }
}
