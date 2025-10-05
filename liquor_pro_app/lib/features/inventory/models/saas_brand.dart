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
  });

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
    );
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
    );
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
