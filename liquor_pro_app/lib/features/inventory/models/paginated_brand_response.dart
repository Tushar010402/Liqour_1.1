import 'saas_brand.dart';

/// Paginated response for brand list with filtering
class PaginatedBrandResponse {
  final List<SaasBrand> brands;
  final int total;
  final int page;
  final int limit;
  final bool hasMore;

  PaginatedBrandResponse({
    required this.brands,
    required this.total,
    required this.page,
    required this.limit,
    required this.hasMore,
  });

  factory PaginatedBrandResponse.fromJson(Map<String, dynamic> json) {
    return PaginatedBrandResponse(
      brands: (json['brands'] as List<dynamic>?)
              ?.map((e) => SaasBrand.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      total: json['total'] as int? ?? 0,
      page: json['page'] as int? ?? 1,
      limit: json['limit'] as int? ?? 30,
      hasMore: json['has_more'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'brands': brands.map((e) => e.toJson()).toList(),
      'total': total,
      'page': page,
      'limit': limit,
      'has_more': hasMore,
    };
  }
}
