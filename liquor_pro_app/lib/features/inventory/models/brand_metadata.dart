/// Brand Metadata Models - For custom brand creation dropdowns
/// Categories, Subcategories, and Common Sizes
library;

class BrandMetadata {
  final List<CategoryDetail> categories;
  final List<SubcategoryDetail> subcategories;
  final List<SizeOption> commonSizes;

  BrandMetadata({
    required this.categories,
    required this.subcategories,
    required this.commonSizes,
  });

  factory BrandMetadata.fromJson(Map<String, dynamic> json) {
    return BrandMetadata(
      categories: (json['categories'] as List?)
              ?.map((c) => CategoryDetail.fromJson(c))
              .toList() ??
          [],
      subcategories: (json['subcategories'] as List?)
              ?.map((s) => SubcategoryDetail.fromJson(s))
              .toList() ??
          [],
      commonSizes: (json['common_sizes'] as List?)
              ?.map((s) => SizeOption.fromJson(s))
              .toList() ??
          [],
    );
  }
}

class CategoryDetail {
  final String id;
  final String name;
  final String description;
  final String? icon;
  final int subcategoryCount;
  final bool isActive;
  final int sortOrder;

  CategoryDetail({
    required this.id,
    required this.name,
    required this.description,
    this.icon,
    required this.subcategoryCount,
    required this.isActive,
    required this.sortOrder,
  });

  factory CategoryDetail.fromJson(Map<String, dynamic> json) {
    return CategoryDetail(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      icon: json['icon'] as String?,
      subcategoryCount: json['subcategory_count'] as int? ?? 0,
      isActive: json['is_active'] as bool? ?? true,
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }
}

class SubcategoryDetail {
  final String id;
  final String categoryId;
  final String name;
  final String description;
  final bool isActive;
  final int sortOrder;

  SubcategoryDetail({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.description,
    required this.isActive,
    required this.sortOrder,
  });

  factory SubcategoryDetail.fromJson(Map<String, dynamic> json) {
    return SubcategoryDetail(
      id: json['id'] as String,
      categoryId: json['category_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      isActive: json['is_active'] as bool? ?? true,
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }
}

class SizeOption {
  final String value;
  final String label;
  final String category;
  final bool isCommon;

  SizeOption({
    required this.value,
    required this.label,
    required this.category,
    required this.isCommon,
  });

  factory SizeOption.fromJson(Map<String, dynamic> json) {
    return SizeOption(
      value: json['value'] as String,
      label: json['label'] as String,
      category: json['category'] as String,
      isCommon: json['is_common'] as bool? ?? false,
    );
  }

  @override
  String toString() => label;
}
