/// SaaS Brand Model - Templates from SaaS Admin
class SaasBrand {
  final String id;
  final String name;
  final String description;
  final String picture;
  final bool isActive;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<SaasBrandVariant> variants;
  final String? categoryName;
  final String? subcategoryName;
  final bool? _isOnboardedFromApi; // Raw value from API (brand-level)

  SaasBrand({
    required this.id,
    required this.name,
    required this.description,
    required this.picture,
    required this.isActive,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    required this.variants,
    this.categoryName,
    this.subcategoryName,
    bool? isOnboarded,
  }) : _isOnboardedFromApi = isOnboarded;

  /// Check if brand is onboarded - ALWAYS compute from variants
  /// because backend sends incorrect brand-level is_onboarded (always true for all brands)
  /// A brand is considered "onboarded" if ALL its variants are onboarded
  bool? get isOnboarded {
    // IMPORTANT: Backend bug - brand-level is_onboarded is always true
    // So we MUST compute from variants to get accurate status
    if (variants.isEmpty) return false;
    // Brand is "onboarded" only if ALL variants are onboarded
    return variants.every((v) => v.isOnboarded == true);
  }

  factory SaasBrand.fromJson(Map<String, dynamic> json) {
    // Backend sends either 'brand_variants' or 'variants'
    List<dynamic>? variantsList = json['brand_variants'] as List<dynamic>?;
    variantsList ??= json['variants'] as List<dynamic>?;

    return SaasBrand(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      picture: json['picture'] ?? '',
      isActive: json['is_active'] ?? true,
      sortOrder: json['sort_order'] ?? 0,
      createdAt: json['created_at'] != null && json['created_at'] != '0001-01-01T00:00:00Z'
          ? DateTime.tryParse(json['created_at']) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null && json['updated_at'] != '0001-01-01T00:00:00Z'
          ? DateTime.tryParse(json['updated_at']) ?? DateTime.now()
          : DateTime.now(),
      variants: variantsList
              ?.map((v) => SaasBrandVariant.fromJson(v as Map<String, dynamic>))
              .toList() ??
          [],
      categoryName: json['category_name'],
      subcategoryName: json['subcategory_name'],
      isOnboarded: json['is_onboarded'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'picture': picture,
      'is_active': isActive,
      'sort_order': sortOrder,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'variants': variants.map((v) => v.toJson()).toList(),
      'category_name': categoryName,
      'subcategory_name': subcategoryName,
      'is_onboarded': _isOnboardedFromApi ?? isOnboarded,
    };
  }

  /// Helper to check if all variants are onboarded
  bool get hasAllVariantsOnboarded {
    return variants.every((v) => v.isOnboarded == true);
  }

  /// Helper to get count of onboarded variants
  int get onboardedVariantsCount {
    return variants.where((v) => v.isOnboarded == true).length;
  }

  /// Get category name from first variant (backend sends category in variants, not at brand level)
  String? get categoryNameFromVariant {
    if (variants.isEmpty) return categoryName;
    return variants.first.category?.name ?? categoryName;
  }

  /// Get subcategory name from first variant (backend sends subcategory in variants, not at brand level)
  String? get subcategoryNameFromVariant {
    if (variants.isEmpty) return subcategoryName;
    return variants.first.subcategory?.name ?? subcategoryName;
  }

  /// Get category ID from first variant
  String? get categoryIdFromVariant {
    if (variants.isEmpty) return null;
    return variants.first.categoryId;
  }

  /// Get subcategory ID from first variant
  String? get subcategoryIdFromVariant {
    if (variants.isEmpty) return null;
    return variants.first.subcategoryId;
  }
}

/// Lightweight Category Info for nested objects
class CategoryInfo {
  final String id;
  final String name;
  final String? icon;

  CategoryInfo({
    required this.id,
    required this.name,
    this.icon,
  });

  factory CategoryInfo.fromJson(Map<String, dynamic> json) {
    return CategoryInfo(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      icon: json['icon'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (icon != null) 'icon': icon,
    };
  }
}

/// Lightweight Subcategory Info for nested objects
class SubcategoryInfo {
  final String id;
  final String name;

  SubcategoryInfo({
    required this.id,
    required this.name,
  });

  factory SubcategoryInfo.fromJson(Map<String, dynamic> json) {
    return SubcategoryInfo(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
    };
  }
}

/// SaaS Brand Variant - Size & price variations
class SaasBrandVariant {
  final String id;
  final String brandId;
  final String categoryId;
  final String? subcategoryId;
  final String size;
  final double alcoholContent;
  final String picture;
  final String barcode;
  final String hsnCode;
  final double governmentDuty;
  final double buyingPrice;
  final double sellingPrice;
  final double mrp;
  final bool isActive;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool? isOnboarded; // Track if this variant is already onboarded

  // Nested objects from backend
  final CategoryInfo? category;
  final SubcategoryInfo? subcategory;

  SaasBrandVariant({
    required this.id,
    required this.brandId,
    required this.categoryId,
    this.subcategoryId,
    required this.size,
    required this.alcoholContent,
    required this.picture,
    required this.barcode,
    required this.hsnCode,
    required this.governmentDuty,
    required this.buyingPrice,
    required this.sellingPrice,
    required this.mrp,
    required this.isActive,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    this.isOnboarded,
    this.category,
    this.subcategory,
  });

  factory SaasBrandVariant.fromJson(Map<String, dynamic> json) {
    return SaasBrandVariant(
      id: json['id'] ?? '',
      brandId: json['brand_id'] ?? '',
      categoryId: json['category_id'] ?? '',
      subcategoryId: json['subcategory_id'],
      size: json['size'] ?? '',
      alcoholContent: (json['alcohol_content'] ?? 0).toDouble(),
      picture: json['picture'] ?? '',
      barcode: json['barcode'] ?? '',
      hsnCode: json['hsn_code'] ?? '',
      governmentDuty: (json['government_duty'] ?? 0).toDouble(),
      buyingPrice: (json['buying_price'] ?? 0).toDouble(),
      sellingPrice: (json['selling_price'] ?? 0).toDouble(),
      mrp: (json['mrp'] ?? 0).toDouble(),
      isActive: json['is_active'] ?? true,
      sortOrder: json['sort_order'] ?? 0,
      createdAt: json['created_at'] != null && json['created_at'] != '0001-01-01T00:00:00Z'
          ? DateTime.tryParse(json['created_at']) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null && json['updated_at'] != '0001-01-01T00:00:00Z'
          ? DateTime.tryParse(json['updated_at']) ?? DateTime.now()
          : DateTime.now(),
      isOnboarded: json['is_onboarded'],
      category: json['category'] != null && json['category'] is Map<String, dynamic>
          ? CategoryInfo.fromJson(json['category'] as Map<String, dynamic>)
          : null,
      subcategory: json['subcategory'] != null && json['subcategory'] is Map<String, dynamic>
          ? SubcategoryInfo.fromJson(json['subcategory'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'brand_id': brandId,
      'category_id': categoryId,
      'subcategory_id': subcategoryId,
      'size': size,
      'alcohol_content': alcoholContent,
      'picture': picture,
      'barcode': barcode,
      'hsn_code': hsnCode,
      'government_duty': governmentDuty,
      'buying_price': buyingPrice,
      'selling_price': sellingPrice,
      'mrp': mrp,
      'is_active': isActive,
      'sort_order': sortOrder,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_onboarded': isOnboarded,
      if (category != null) 'category': category!.toJson(),
      if (subcategory != null) 'subcategory': subcategory!.toJson(),
    };
  }

  /// Display name for variant (Brand - Size)
  String getDisplayName(String brandName) {
    return '$brandName - $size';
  }
}

/// SaaS Brand Category
class SaasBrandCategory {
  final String id;
  final String name;
  final String description;
  final bool isActive;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  SaasBrandCategory({
    required this.id,
    required this.name,
    required this.description,
    required this.isActive,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SaasBrandCategory.fromJson(Map<String, dynamic> json) {
    return SaasBrandCategory(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      isActive: json['is_active'] ?? true,
      sortOrder: json['sort_order'] ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : DateTime.now(),
    );
  }
}

/// SaaS Brand Subcategory
class SaasBrandSubcategory {
  final String id;
  final String name;
  final String categoryId;
  final String priceRange;
  final String description;
  final int sortOrder;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  SaasBrandSubcategory({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.priceRange,
    required this.description,
    required this.sortOrder,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SaasBrandSubcategory.fromJson(Map<String, dynamic> json) {
    return SaasBrandSubcategory(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      categoryId: json['category_id'] ?? '',
      priceRange: json['price_range'] ?? '',
      description: json['description'] ?? '',
      sortOrder: json['sort_order'] ?? 0,
      isActive: json['is_active'] ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : DateTime.now(),
    );
  }
}
