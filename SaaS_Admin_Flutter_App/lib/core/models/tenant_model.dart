class TenantModel {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String status;
  final String subscriptionPlan;
  final DateTime createdAt;
  final DateTime? lastActive;
  final int locationsCount;
  final int usersCount;
  final int productsCount;
  final Map<String, dynamic>? usage;

  TenantModel({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.status,
    required this.subscriptionPlan,
    required this.createdAt,
    this.lastActive,
    this.locationsCount = 0,
    this.usersCount = 0,
    this.productsCount = 0,
    this.usage,
  });

  factory TenantModel.fromJson(Map<String, dynamic> json) {
    return TenantModel(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? json['tenant_name'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'] ?? '',
      status: json['status'] ?? 'active',
      subscriptionPlan:
          json['subscription_plan'] ?? json['plan_name'] ?? 'Unknown',
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      lastActive: DateTime.tryParse(json['last_active'] ?? ''),
      locationsCount: json['locations_count'] ?? json['average_locations'] ?? 0,
      usersCount: json['users_count'] ?? json['average_users'] ?? 0,
      productsCount: json['products_count'] ?? json['average_products'] ?? 0,
      usage: json['usage'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'status': status,
      'subscription_plan': subscriptionPlan,
      'created_at': createdAt.toIso8601String(),
      'last_active': lastActive?.toIso8601String(),
      'locations_count': locationsCount,
      'users_count': usersCount,
      'products_count': productsCount,
      'usage': usage,
    };
  }

  bool get isActive => status.toLowerCase() == 'active';
  bool get isPaused => status.toLowerCase() == 'paused';
  bool get isCancelled => status.toLowerCase() == 'cancelled';
}

class TenantAnalytics {
  final int totalTenants;
  final int activeTenants;
  final double averageLocations;
  final double averageUsers;
  final double averageProducts;
  final Map<String, dynamic> usageByPlan;
  final List<TenantModel> topTenants;

  TenantAnalytics({
    required this.totalTenants,
    required this.activeTenants,
    required this.averageLocations,
    required this.averageUsers,
    required this.averageProducts,
    required this.usageByPlan,
    required this.topTenants,
  });

  factory TenantAnalytics.fromJson(Map<String, dynamic> json) {
    return TenantAnalytics(
      totalTenants: json['total_tenants'] ?? 0,
      activeTenants: json['active_tenants'] ?? 0,
      averageLocations: (json['average_locations'] ?? 0).toDouble(),
      averageUsers: (json['average_users'] ?? 0).toDouble(),
      averageProducts: (json['average_products'] ?? 0).toDouble(),
      usageByPlan: json['usage_by_plan'] ?? {},
      topTenants: (json['top_tenants'] as List?)
              ?.map((tenant) => TenantModel.fromJson(tenant))
              .toList() ??
          [],
    );
  }
}
