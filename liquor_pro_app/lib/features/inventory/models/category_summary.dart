/// Category summary with brand count for category-first navigation
class CategorySummary {
  final String id;
  final String name;
  final String icon;
  final int brandCount;
  final bool isPopular;
  final int sortOrder;

  CategorySummary({
    required this.id,
    required this.name,
    required this.icon,
    required this.brandCount,
    required this.isPopular,
    required this.sortOrder,
  });

  factory CategorySummary.fromJson(Map<String, dynamic> json) {
    return CategorySummary(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      icon: json['icon'] as String? ?? '🍾',
      brandCount: json['brand_count'] as int? ?? 0,
      isPopular: json['is_popular'] as bool? ?? false,
      sortOrder: json['sort_order'] as int? ?? 999,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'icon': icon,
      'brand_count': brandCount,
      'is_popular': isPopular,
      'sort_order': sortOrder,
    };
  }
}
