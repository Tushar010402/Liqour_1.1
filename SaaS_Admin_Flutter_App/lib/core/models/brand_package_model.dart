import 'package:json_annotation/json_annotation.dart';
import 'brand_model.dart';

part 'brand_package_model.g.dart';

@JsonSerializable()
class BrandPackage {
  final String id;
  final String name;
  final String description;
  final String type; // 'starter', 'premium', 'full'
  final double price;
  @JsonKey(name: 'brand_count')
  final int brandCount;
  @JsonKey(name: 'variant_count')
  final int variantCount;
  final List<String> features;
  @JsonKey(name: 'is_popular')
  final bool isPopular;
  @JsonKey(name: 'discount_percentage')
  final double? discountPercentage;
  final List<Brand> brands;
  @JsonKey(name: 'created_at')
  final String? createdAt;

  const BrandPackage({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.price,
    required this.brandCount,
    required this.variantCount,
    required this.features,
    this.isPopular = false,
    this.discountPercentage,
    required this.brands,
    this.createdAt,
  });

  factory BrandPackage.fromJson(Map<String, dynamic> json) => _$BrandPackageFromJson(json);
  Map<String, dynamic> toJson() => _$BrandPackageToJson(this);

  // Calculate final price after discount
  double get finalPrice {
    if (discountPercentage != null && discountPercentage! > 0) {
      return price * (1 - discountPercentage! / 100);
    }
    return price;
  }

  // Get all variant IDs from brands
  List<String> get allVariantIds {
    final variantIds = <String>[];
    for (final brand in brands) {
      if (brand.brandVariants != null) {
        variantIds.addAll(brand.brandVariants!.map((v) => v.id));
      }
    }
    return variantIds;
  }

  // Get all brand IDs
  List<String> get allBrandIds {
    return brands.map((b) => b.id).toList();
  }
}

@JsonSerializable()
class MarketplaceFilter {
  @JsonKey(name: 'category_id')
  final String? categoryId;
  @JsonKey(name: 'price_range')
  final PriceRange? priceRange;
  @JsonKey(name: 'package_type')
  final String? packageType;
  @JsonKey(name: 'search_query')
  final String? searchQuery;

  const MarketplaceFilter({
    this.categoryId,
    this.priceRange,
    this.packageType,
    this.searchQuery,
  });

  factory MarketplaceFilter.fromJson(Map<String, dynamic> json) => _$MarketplaceFilterFromJson(json);
  Map<String, dynamic> toJson() => _$MarketplaceFilterToJson(this);

  MarketplaceFilter copyWith({
    String? categoryId,
    PriceRange? priceRange,
    String? packageType,
    String? searchQuery,
  }) {
    return MarketplaceFilter(
      categoryId: categoryId ?? this.categoryId,
      priceRange: priceRange ?? this.priceRange,
      packageType: packageType ?? this.packageType,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}

@JsonSerializable()
class PriceRange {
  final double min;
  final double max;

  const PriceRange({
    required this.min,
    required this.max,
  });

  factory PriceRange.fromJson(Map<String, dynamic> json) => _$PriceRangeFromJson(json);
  Map<String, dynamic> toJson() => _$PriceRangeToJson(this);
}

@JsonSerializable()
class TenantOnboardingRequest {
  @JsonKey(name: 'tenant_id')
  final String tenantId;
  @JsonKey(name: 'package_id')
  final String? packageId;
  @JsonKey(name: 'selected_brand_ids')
  final List<String> selectedBrandIds;
  @JsonKey(name: 'selected_variant_ids')
  final List<String> selectedVariantIds;
  @JsonKey(name: 'onboarding_type')
  final String onboardingType; // 'package', 'custom'

  const TenantOnboardingRequest({
    required this.tenantId,
    this.packageId,
    required this.selectedBrandIds,
    required this.selectedVariantIds,
    required this.onboardingType,
  });

  factory TenantOnboardingRequest.fromJson(Map<String, dynamic> json) => _$TenantOnboardingRequestFromJson(json);
  Map<String, dynamic> toJson() => _$TenantOnboardingRequestToJson(this);
}