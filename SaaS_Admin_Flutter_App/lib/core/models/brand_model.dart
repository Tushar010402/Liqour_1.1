import 'package:json_annotation/json_annotation.dart';

part 'brand_model.g.dart';

@JsonSerializable()
class Brand {
  final String id;
  final String name;
  final String description;
  final String picture;
  @JsonKey(name: 'is_active')
  final bool isActive;
  @JsonKey(name: 'sort_order')
  final int sortOrder;
  @JsonKey(name: 'brand_variants')
  final List<BrandVariant>? brandVariants;
  @JsonKey(name: 'created_at')
  final String? createdAt;
  @JsonKey(name: 'updated_at')
  final String? updatedAt;

  const Brand({
    required this.id,
    required this.name,
    required this.description,
    required this.picture,
    required this.isActive,
    required this.sortOrder,
    this.brandVariants,
    this.createdAt,
    this.updatedAt,
  });

  factory Brand.fromJson(Map<String, dynamic> json) => _$BrandFromJson(json);
  Map<String, dynamic> toJson() => _$BrandToJson(this);

  Brand copyWith({
    String? id,
    String? name,
    String? description,
    String? picture,
    bool? isActive,
    int? sortOrder,
    List<BrandVariant>? brandVariants,
    String? createdAt,
    String? updatedAt,
  }) {
    return Brand(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      picture: picture ?? this.picture,
      isActive: isActive ?? this.isActive,
      sortOrder: sortOrder ?? this.sortOrder,
      brandVariants: brandVariants ?? this.brandVariants,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

@JsonSerializable()
class BrandVariant {
  final String id;
  @JsonKey(name: 'brand_id')
  final String brandId;
  @JsonKey(name: 'category_id')
  final String categoryId;
  @JsonKey(name: 'subcategory_id')
  final String? subcategoryId;
  final String size;
  @JsonKey(name: 'alcohol_content')
  final double alcoholContent;
  final String picture;
  @JsonKey(name: 'government_duty')
  final double governmentDuty;
  @JsonKey(name: 'buying_price')
  final double buyingPrice;
  @JsonKey(name: 'selling_price')
  final double sellingPrice;
  final double mrp;
  final String description;
  final String barcode;
  @JsonKey(name: 'hsn_code')
  final String hsnCode;
  @JsonKey(name: 'is_active')
  final bool isActive;
  @JsonKey(name: 'sort_order')
  final int sortOrder;
  final BrandCategory? category;
  final BrandSubcategory? subcategory;
  @JsonKey(name: 'created_at')
  final String? createdAt;
  @JsonKey(name: 'updated_at')
  final String? updatedAt;

  const BrandVariant({
    required this.id,
    required this.brandId,
    required this.categoryId,
    this.subcategoryId,
    required this.size,
    required this.alcoholContent,
    required this.picture,
    required this.governmentDuty,
    required this.buyingPrice,
    required this.sellingPrice,
    required this.mrp,
    required this.description,
    required this.barcode,
    required this.hsnCode,
    required this.isActive,
    required this.sortOrder,
    this.category,
    this.subcategory,
    this.createdAt,
    this.updatedAt,
  });

  factory BrandVariant.fromJson(Map<String, dynamic> json) =>
      _$BrandVariantFromJson(json);
  Map<String, dynamic> toJson() => _$BrandVariantToJson(this);
}

@JsonSerializable()
class BrandCategory {
  final String id;
  final String name;
  final String description;
  @JsonKey(name: 'is_active')
  final bool isActive;
  @JsonKey(name: 'sort_order')
  final int sortOrder;
  @JsonKey(name: 'created_at')
  final String? createdAt;
  @JsonKey(name: 'updated_at')
  final String? updatedAt;

  const BrandCategory({
    required this.id,
    required this.name,
    required this.description,
    required this.isActive,
    required this.sortOrder,
    this.createdAt,
    this.updatedAt,
  });

  factory BrandCategory.fromJson(Map<String, dynamic> json) =>
      _$BrandCategoryFromJson(json);
  Map<String, dynamic> toJson() => _$BrandCategoryToJson(this);
}

@JsonSerializable()
class BrandSubcategory {
  final String id;
  final String name;
  @JsonKey(name: 'category_id')
  final String categoryId;
  final String description;
  @JsonKey(name: 'is_active')
  final bool isActive;
  @JsonKey(name: 'sort_order')
  final int sortOrder;
  @JsonKey(name: 'created_at')
  final String? createdAt;
  @JsonKey(name: 'updated_at')
  final String? updatedAt;

  const BrandSubcategory({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.description,
    required this.isActive,
    required this.sortOrder,
    this.createdAt,
    this.updatedAt,
  });

  factory BrandSubcategory.fromJson(Map<String, dynamic> json) =>
      _$BrandSubcategoryFromJson(json);
  Map<String, dynamic> toJson() => _$BrandSubcategoryToJson(this);
}

@JsonSerializable()
class CreateBrandRequest {
  final String name;
  final String description;
  final String picture;
  @JsonKey(name: 'is_active')
  final bool isActive;
  @JsonKey(name: 'sort_order')
  final int sortOrder;

  const CreateBrandRequest({
    required this.name,
    required this.description,
    required this.picture,
    this.isActive = true,
    this.sortOrder = 0,
  });

  factory CreateBrandRequest.fromJson(Map<String, dynamic> json) =>
      _$CreateBrandRequestFromJson(json);
  Map<String, dynamic> toJson() => _$CreateBrandRequestToJson(this);
}

@JsonSerializable()
class CreateBrandVariantRequest {
  @JsonKey(name: 'brand_id')
  final String brandId;
  @JsonKey(name: 'category_id')
  final String categoryId;
  @JsonKey(name: 'subcategory_id')
  final String? subcategoryId;
  final String size;
  @JsonKey(name: 'alcohol_content')
  final double alcoholContent;
  final String picture;
  @JsonKey(name: 'government_duty')
  final double governmentDuty;
  @JsonKey(name: 'buying_price')
  final double buyingPrice;
  @JsonKey(name: 'selling_price')
  final double sellingPrice;
  final double mrp;
  final String description;
  final String barcode;
  @JsonKey(name: 'hsn_code')
  final String hsnCode;
  @JsonKey(name: 'is_active')
  final bool isActive;
  @JsonKey(name: 'sort_order')
  final int sortOrder;

  const CreateBrandVariantRequest({
    required this.brandId,
    required this.categoryId,
    this.subcategoryId,
    required this.size,
    required this.alcoholContent,
    required this.picture,
    required this.governmentDuty,
    required this.buyingPrice,
    required this.sellingPrice,
    required this.mrp,
    required this.description,
    required this.barcode,
    required this.hsnCode,
    this.isActive = true,
    this.sortOrder = 0,
  });

  factory CreateBrandVariantRequest.fromJson(Map<String, dynamic> json) =>
      _$CreateBrandVariantRequestFromJson(json);
  Map<String, dynamic> toJson() => _$CreateBrandVariantRequestToJson(this);
}

@JsonSerializable()
class TenantBrandAssignmentRequest {
  @JsonKey(name: 'tenant_id')
  final String tenantId;
  @JsonKey(name: 'brand_ids')
  final List<String> brandIds;
  @JsonKey(name: 'variant_ids')
  final List<String> variantIds;

  const TenantBrandAssignmentRequest({
    required this.tenantId,
    required this.brandIds,
    required this.variantIds,
  });

  factory TenantBrandAssignmentRequest.fromJson(Map<String, dynamic> json) =>
      _$TenantBrandAssignmentRequestFromJson(json);
  Map<String, dynamic> toJson() => _$TenantBrandAssignmentRequestToJson(this);
}

@JsonSerializable()
class CreateBrandCategoryRequest {
  final String name;
  final String description;
  @JsonKey(name: 'is_active')
  final bool isActive;
  @JsonKey(name: 'sort_order')
  final int sortOrder;

  const CreateBrandCategoryRequest({
    required this.name,
    required this.description,
    this.isActive = true,
    this.sortOrder = 0,
  });

  factory CreateBrandCategoryRequest.fromJson(Map<String, dynamic> json) =>
      _$CreateBrandCategoryRequestFromJson(json);
  Map<String, dynamic> toJson() => _$CreateBrandCategoryRequestToJson(this);
}

@JsonSerializable()
class CreateBrandSubcategoryRequest {
  final String name;
  @JsonKey(name: 'category_id')
  final String categoryId;
  final String description;
  @JsonKey(name: 'is_active')
  final bool isActive;
  @JsonKey(name: 'sort_order')
  final int sortOrder;

  const CreateBrandSubcategoryRequest({
    required this.name,
    required this.categoryId,
    required this.description,
    this.isActive = true,
    this.sortOrder = 0,
  });

  factory CreateBrandSubcategoryRequest.fromJson(Map<String, dynamic> json) =>
      _$CreateBrandSubcategoryRequestFromJson(json);
  Map<String, dynamic> toJson() => _$CreateBrandSubcategoryRequestToJson(this);
}

@JsonSerializable()
class CreateBrandWithVariantsRequest {
  final String name;
  final String description;
  final String picture;
  @JsonKey(name: 'is_active')
  final bool isActive;
  @JsonKey(name: 'sort_order')
  final int sortOrder;
  final List<CreateBrandVariantRequest> variants;

  const CreateBrandWithVariantsRequest({
    required this.name,
    required this.description,
    required this.picture,
    this.isActive = true,
    this.sortOrder = 0,
    required this.variants,
  });

  factory CreateBrandWithVariantsRequest.fromJson(Map<String, dynamic> json) =>
      _$CreateBrandWithVariantsRequestFromJson(json);
  Map<String, dynamic> toJson() => _$CreateBrandWithVariantsRequestToJson(this);
}
