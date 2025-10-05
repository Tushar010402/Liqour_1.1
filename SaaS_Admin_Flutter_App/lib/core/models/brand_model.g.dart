// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'brand_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Brand _$BrandFromJson(Map<String, dynamic> json) => Brand(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      picture: json['picture'] as String,
      isActive: json['is_active'] as bool,
      sortOrder: (json['sort_order'] as num).toInt(),
      brandVariants: (json['brand_variants'] as List<dynamic>?)
          ?.map((e) => BrandVariant.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
    );

Map<String, dynamic> _$BrandToJson(Brand instance) => <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'description': instance.description,
      'picture': instance.picture,
      'is_active': instance.isActive,
      'sort_order': instance.sortOrder,
      'brand_variants': instance.brandVariants,
      'created_at': instance.createdAt,
      'updated_at': instance.updatedAt,
    };

BrandVariant _$BrandVariantFromJson(Map<String, dynamic> json) => BrandVariant(
      id: json['id'] as String,
      brandId: json['brand_id'] as String,
      categoryId: json['category_id'] as String,
      subcategoryId: json['subcategory_id'] as String?,
      size: json['size'] as String,
      alcoholContent: (json['alcohol_content'] as num).toDouble(),
      picture: json['picture'] as String,
      governmentDuty: (json['government_duty'] as num).toDouble(),
      buyingPrice: (json['buying_price'] as num).toDouble(),
      sellingPrice: (json['selling_price'] as num).toDouble(),
      mrp: (json['mrp'] as num).toDouble(),
      description: json['description'] as String,
      barcode: json['barcode'] as String,
      hsnCode: json['hsn_code'] as String,
      isActive: json['is_active'] as bool,
      sortOrder: (json['sort_order'] as num).toInt(),
      category: json['category'] == null
          ? null
          : BrandCategory.fromJson(json['category'] as Map<String, dynamic>),
      subcategory: json['subcategory'] == null
          ? null
          : BrandSubcategory.fromJson(
              json['subcategory'] as Map<String, dynamic>),
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
    );

Map<String, dynamic> _$BrandVariantToJson(BrandVariant instance) =>
    <String, dynamic>{
      'id': instance.id,
      'brand_id': instance.brandId,
      'category_id': instance.categoryId,
      'subcategory_id': instance.subcategoryId,
      'size': instance.size,
      'alcohol_content': instance.alcoholContent,
      'picture': instance.picture,
      'government_duty': instance.governmentDuty,
      'buying_price': instance.buyingPrice,
      'selling_price': instance.sellingPrice,
      'mrp': instance.mrp,
      'description': instance.description,
      'barcode': instance.barcode,
      'hsn_code': instance.hsnCode,
      'is_active': instance.isActive,
      'sort_order': instance.sortOrder,
      'category': instance.category,
      'subcategory': instance.subcategory,
      'created_at': instance.createdAt,
      'updated_at': instance.updatedAt,
    };

BrandCategory _$BrandCategoryFromJson(Map<String, dynamic> json) =>
    BrandCategory(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      isActive: json['is_active'] as bool,
      sortOrder: (json['sort_order'] as num).toInt(),
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
    );

Map<String, dynamic> _$BrandCategoryToJson(BrandCategory instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'description': instance.description,
      'is_active': instance.isActive,
      'sort_order': instance.sortOrder,
      'created_at': instance.createdAt,
      'updated_at': instance.updatedAt,
    };

BrandSubcategory _$BrandSubcategoryFromJson(Map<String, dynamic> json) =>
    BrandSubcategory(
      id: json['id'] as String,
      name: json['name'] as String,
      categoryId: json['category_id'] as String,
      description: json['description'] as String,
      isActive: json['is_active'] as bool,
      sortOrder: (json['sort_order'] as num).toInt(),
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
    );

Map<String, dynamic> _$BrandSubcategoryToJson(BrandSubcategory instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'category_id': instance.categoryId,
      'description': instance.description,
      'is_active': instance.isActive,
      'sort_order': instance.sortOrder,
      'created_at': instance.createdAt,
      'updated_at': instance.updatedAt,
    };

CreateBrandRequest _$CreateBrandRequestFromJson(Map<String, dynamic> json) =>
    CreateBrandRequest(
      name: json['name'] as String,
      description: json['description'] as String,
      picture: json['picture'] as String,
      isActive: json['is_active'] as bool? ?? true,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$CreateBrandRequestToJson(CreateBrandRequest instance) =>
    <String, dynamic>{
      'name': instance.name,
      'description': instance.description,
      'picture': instance.picture,
      'is_active': instance.isActive,
      'sort_order': instance.sortOrder,
    };

CreateBrandVariantRequest _$CreateBrandVariantRequestFromJson(
        Map<String, dynamic> json) =>
    CreateBrandVariantRequest(
      brandId: json['brand_id'] as String,
      categoryId: json['category_id'] as String,
      subcategoryId: json['subcategory_id'] as String?,
      size: json['size'] as String,
      alcoholContent: (json['alcohol_content'] as num).toDouble(),
      picture: json['picture'] as String,
      governmentDuty: (json['government_duty'] as num).toDouble(),
      buyingPrice: (json['buying_price'] as num).toDouble(),
      sellingPrice: (json['selling_price'] as num).toDouble(),
      mrp: (json['mrp'] as num).toDouble(),
      description: json['description'] as String,
      barcode: json['barcode'] as String,
      hsnCode: json['hsn_code'] as String,
      isActive: json['is_active'] as bool? ?? true,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$CreateBrandVariantRequestToJson(
        CreateBrandVariantRequest instance) =>
    <String, dynamic>{
      'brand_id': instance.brandId,
      'category_id': instance.categoryId,
      'subcategory_id': instance.subcategoryId,
      'size': instance.size,
      'alcohol_content': instance.alcoholContent,
      'picture': instance.picture,
      'government_duty': instance.governmentDuty,
      'buying_price': instance.buyingPrice,
      'selling_price': instance.sellingPrice,
      'mrp': instance.mrp,
      'description': instance.description,
      'barcode': instance.barcode,
      'hsn_code': instance.hsnCode,
      'is_active': instance.isActive,
      'sort_order': instance.sortOrder,
    };

TenantBrandAssignmentRequest _$TenantBrandAssignmentRequestFromJson(
        Map<String, dynamic> json) =>
    TenantBrandAssignmentRequest(
      tenantId: json['tenant_id'] as String,
      brandIds:
          (json['brand_ids'] as List<dynamic>).map((e) => e as String).toList(),
      variantIds: (json['variant_ids'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
    );

Map<String, dynamic> _$TenantBrandAssignmentRequestToJson(
        TenantBrandAssignmentRequest instance) =>
    <String, dynamic>{
      'tenant_id': instance.tenantId,
      'brand_ids': instance.brandIds,
      'variant_ids': instance.variantIds,
    };

CreateBrandCategoryRequest _$CreateBrandCategoryRequestFromJson(
        Map<String, dynamic> json) =>
    CreateBrandCategoryRequest(
      name: json['name'] as String,
      description: json['description'] as String,
      isActive: json['is_active'] as bool? ?? true,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$CreateBrandCategoryRequestToJson(
        CreateBrandCategoryRequest instance) =>
    <String, dynamic>{
      'name': instance.name,
      'description': instance.description,
      'is_active': instance.isActive,
      'sort_order': instance.sortOrder,
    };

CreateBrandSubcategoryRequest _$CreateBrandSubcategoryRequestFromJson(
        Map<String, dynamic> json) =>
    CreateBrandSubcategoryRequest(
      name: json['name'] as String,
      categoryId: json['category_id'] as String,
      description: json['description'] as String,
      isActive: json['is_active'] as bool? ?? true,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$CreateBrandSubcategoryRequestToJson(
        CreateBrandSubcategoryRequest instance) =>
    <String, dynamic>{
      'name': instance.name,
      'category_id': instance.categoryId,
      'description': instance.description,
      'is_active': instance.isActive,
      'sort_order': instance.sortOrder,
    };

CreateBrandWithVariantsRequest _$CreateBrandWithVariantsRequestFromJson(
        Map<String, dynamic> json) =>
    CreateBrandWithVariantsRequest(
      name: json['name'] as String,
      description: json['description'] as String,
      picture: json['picture'] as String,
      isActive: json['is_active'] as bool? ?? true,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      variants: (json['variants'] as List<dynamic>)
          .map((e) =>
              CreateBrandVariantRequest.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$CreateBrandWithVariantsRequestToJson(
        CreateBrandWithVariantsRequest instance) =>
    <String, dynamic>{
      'name': instance.name,
      'description': instance.description,
      'picture': instance.picture,
      'is_active': instance.isActive,
      'sort_order': instance.sortOrder,
      'variants': instance.variants,
    };
