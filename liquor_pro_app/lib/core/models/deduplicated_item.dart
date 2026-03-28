/// DeduplicatedItem Model
/// Represents an OCR-scanned item that has been deduplicated and is ready for review
///
/// Used in OCR export service and review screens
library;

class DeduplicatedItem {
  final String? id;
  final String? brandName;
  final String? inferredCategory;
  final String? inferredSubcategory;
  final String? inferredSize;
  final double? inferredMrp;
  final double? confidence;
  final String? matchedSaaSBrandId;
  final String? matchedBrandVariantId;
  final String? rawText;
  final String? imageUrl;
  final String? shopId;
  final DateTime? createdAt;
  final Map<String, dynamic>? metadata;

  DeduplicatedItem({
    this.id,
    this.brandName,
    this.inferredCategory,
    this.inferredSubcategory,
    this.inferredSize,
    this.inferredMrp,
    this.confidence,
    this.matchedSaaSBrandId,
    this.matchedBrandVariantId,
    this.rawText,
    this.imageUrl,
    this.shopId,
    this.createdAt,
    this.metadata,
  });

  factory DeduplicatedItem.fromJson(Map<String, dynamic> json) {
    return DeduplicatedItem(
      id: json['id']?.toString(),
      brandName: json['brand_name'] ?? json['brandName'],
      inferredCategory: json['inferred_category'] ?? json['inferredCategory'] ?? json['category'],
      inferredSubcategory: json['inferred_subcategory'] ?? json['inferredSubcategory'] ?? json['subcategory'],
      inferredSize: json['inferred_size'] ?? json['inferredSize'] ?? json['size'],
      inferredMrp: _parseDouble(json['inferred_mrp'] ?? json['inferredMrp'] ?? json['mrp']),
      confidence: _parseDouble(json['confidence']),
      matchedSaaSBrandId: json['matched_saas_brand_id'] ?? json['matchedSaaSBrandId'],
      matchedBrandVariantId: json['matched_brand_variant_id'] ?? json['matchedBrandVariantId'],
      rawText: json['raw_text'] ?? json['rawText'],
      imageUrl: json['image_url'] ?? json['imageUrl'],
      shopId: json['shop_id'] ?? json['shopId'],
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'brand_name': brandName,
      'inferred_category': inferredCategory,
      'inferred_subcategory': inferredSubcategory,
      'inferred_size': inferredSize,
      'inferred_mrp': inferredMrp,
      'confidence': confidence,
      'matched_saas_brand_id': matchedSaaSBrandId,
      'matched_brand_variant_id': matchedBrandVariantId,
      'raw_text': rawText,
      'image_url': imageUrl,
      'shop_id': shopId,
      'created_at': createdAt?.toIso8601String(),
      'metadata': metadata,
    };
  }

  DeduplicatedItem copyWith({
    String? id,
    String? brandName,
    String? inferredCategory,
    String? inferredSubcategory,
    String? inferredSize,
    double? inferredMrp,
    double? confidence,
    String? matchedSaaSBrandId,
    String? matchedBrandVariantId,
    String? rawText,
    String? imageUrl,
    String? shopId,
    DateTime? createdAt,
    Map<String, dynamic>? metadata,
  }) {
    return DeduplicatedItem(
      id: id ?? this.id,
      brandName: brandName ?? this.brandName,
      inferredCategory: inferredCategory ?? this.inferredCategory,
      inferredSubcategory: inferredSubcategory ?? this.inferredSubcategory,
      inferredSize: inferredSize ?? this.inferredSize,
      inferredMrp: inferredMrp ?? this.inferredMrp,
      confidence: confidence ?? this.confidence,
      matchedSaaSBrandId: matchedSaaSBrandId ?? this.matchedSaaSBrandId,
      matchedBrandVariantId: matchedBrandVariantId ?? this.matchedBrandVariantId,
      rawText: rawText ?? this.rawText,
      imageUrl: imageUrl ?? this.imageUrl,
      shopId: shopId ?? this.shopId,
      createdAt: createdAt ?? this.createdAt,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Check if this item has a matching brand in the database
  bool get hasMatch => matchedSaaSBrandId != null || matchedBrandVariantId != null;

  /// Get formatted display name
  String get displayName => brandName ?? 'Unknown Brand';

  /// Get formatted confidence percentage
  String get confidencePercent {
    if (confidence == null) return '0%';
    return '${(confidence! * 100).toStringAsFixed(0)}%';
  }

  /// Get status based on matching
  String get matchStatus {
    if (matchedBrandVariantId != null) return 'exact_match';
    if (matchedSaaSBrandId != null) return 'brand_match';
    return 'new_brand';
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DeduplicatedItem && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'DeduplicatedItem(id: $id, brandName: $brandName, category: $inferredCategory, size: $inferredSize)';
  }
}
