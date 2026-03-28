import 'package:freezed_annotation/freezed_annotation.dart';
import '../../inventory/models/product.dart';
import '../../inventory/models/brand.dart';

part 'ocr_models.freezed.dart';
part 'ocr_models.g.dart';

/// OCR Session model
@freezed
class OCRSession with _$OCRSession {
  const factory OCRSession({
    required String id,
    @JsonKey(name: 'tenant_id') required String tenantId,
    @JsonKey(name: 'user_id') required String userId,
    @JsonKey(name: 'shop_id') required String shopId,
    @JsonKey(name: 'image_url') required String imageUrl,
    @JsonKey(name: 'image_size') required int imageSize,
    @JsonKey(name: 'image_type') required String imageType,
    required String status,
    @JsonKey(name: 'ocr_provider') @Default('google_vision') String ocrProvider,
    @JsonKey(name: 'raw_text') String? rawText,
    @JsonKey(name: 'processed_at') DateTime? processedAt,
    @JsonKey(name: 'error_message') String? errorMessage,
    @JsonKey(name: 'confidence_score') double? confidenceScore,
    @JsonKey(name: 'processing_time_ms') int? processingTimeMs,
    @JsonKey(name: 'receipt_date') DateTime? receiptDate,
    @JsonKey(name: 'receipt_number') String? receiptNumber,
    @JsonKey(name: 'vendor_name') String? vendorName,
    @JsonKey(name: 'total_amount') double? totalAmount,
    @JsonKey(name: 'session_type') @Default('quick_sale') String sessionType,
    @JsonKey(name: 'expires_at') required DateTime expiresAt,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'updated_at') required DateTime updatedAt,
    @JsonKey(name: 'extracted_items') @Default([]) List<OCRExtractedItem> extractedItems,
  }) = _OCRSession;

  factory OCRSession.fromJson(Map<String, dynamic> json) =>
      _$OCRSessionFromJson(json);
}

/// OCR Extracted Item model
@freezed
class OCRExtractedItem with _$OCRExtractedItem {
  const factory OCRExtractedItem({
    required String id,
    @JsonKey(name: 'session_id') required String sessionId,
    @JsonKey(name: 'extracted_text') required String extractedText,
    @JsonKey(name: 'brand_text') String? brandText,
    @JsonKey(name: 'size_text') String? sizeText,
    @JsonKey(name: 'quantity_text') String? quantityText,
    @JsonKey(name: 'price_text') String? priceText,
    @JsonKey(name: 'parsed_quantity') int? parsedQuantity,
    @JsonKey(name: 'parsed_price') double? parsedPrice,
    @JsonKey(name: 'parsed_size') String? parsedSize,
    // Stock tracking fields
    @JsonKey(name: 'rate_per_unit') double? ratePerUnit,
    @JsonKey(name: 'opening_stock') int? openingStock,
    @JsonKey(name: 'closing_stock') int? closingStock,
    @JsonKey(name: 'row_number') int? rowNumber,
    @JsonKey(name: 'matched_product_id') String? matchedProductId,
    @JsonKey(name: 'matched_brand_id') String? matchedBrandId,
    @JsonKey(name: 'matched_variant_id') String? matchedVariantId,
    @JsonKey(name: 'match_confidence') required double matchConfidence,
    @JsonKey(name: 'match_method') String? matchMethod,
    @JsonKey(name: 'match_details') Map<String, dynamic>? matchDetails,
    @JsonKey(name: 'is_confirmed') @Default(false) bool isConfirmed,
    @JsonKey(name: 'is_rejected') @Default(false) bool isRejected,
    @JsonKey(name: 'user_corrected_product_id') String? userCorrectedProductId,
    @JsonKey(name: 'user_corrected_quantity') int? userCorrectedQuantity,
    @JsonKey(name: 'correction_reason') String? correctionReason,
    @JsonKey(name: 'line_number') int? lineNumber,
    @JsonKey(name: 'bounding_box') Map<String, dynamic>? boundingBox,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'updated_at') required DateTime updatedAt,
    // Related data (not serialized - runtime only)
    @JsonKey(ignore: true) Product? matchedProduct,
    @JsonKey(ignore: true) Brand? matchedBrand,
    @JsonKey(ignore: true) BrandVariant? matchedVariant,
  }) = _OCRExtractedItem;

  factory OCRExtractedItem.fromJson(Map<String, dynamic> json) =>
      _$OCRExtractedItemFromJson(json);
}

/// Brand Alias model
@freezed
class BrandAlias with _$BrandAlias {
  const factory BrandAlias({
    required String id,
    @JsonKey(name: 'tenant_id') required String tenantId,
    @JsonKey(name: 'brand_id') required String brandId,
    @JsonKey(name: 'alias_text') required String aliasText,
    @JsonKey(name: 'alias_type') required String aliasType,
    @JsonKey(name: 'match_count') @Default(0) int matchCount,
    @JsonKey(name: 'last_matched_at') DateTime? lastMatchedAt,
    @JsonKey(name: 'is_active') @Default(true) bool isActive,
    @JsonKey(name: 'created_by') String? createdBy,
    @JsonKey(name: 'approved_by') String? approvedBy,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'updated_at') required DateTime updatedAt,
    @JsonKey(ignore: true) Brand? brand,
  }) = _BrandAlias;

  factory BrandAlias.fromJson(Map<String, dynamic> json) =>
      _$BrandAliasFromJson(json);
}

/// OCR Session Response model
@freezed
class OCRSessionResponse with _$OCRSessionResponse {
  const factory OCRSessionResponse({
    required OCRSession session,
    @JsonKey(name: 'extracted_items') @Default([]) List<OCRExtractedItem> extractedItems,
    OCRProcessingSummary? summary,
  }) = _OCRSessionResponse;

  factory OCRSessionResponse.fromJson(Map<String, dynamic> json) =>
      _$OCRSessionResponseFromJson(json);
}

/// OCR Processing Summary
@freezed
class OCRProcessingSummary with _$OCRProcessingSummary {
  const factory OCRProcessingSummary({
    @JsonKey(name: 'total_items') required int totalItems,
    @JsonKey(name: 'matched_items') required int matchedItems,
    @JsonKey(name: 'unmatched_items') required int unmatchedItems,
    @JsonKey(name: 'confidence_avg') required double confidenceAvg,
    @JsonKey(name: 'processing_time_ms') required int processingTimeMs,
    @JsonKey(name: 'requires_review') required bool requiresReview,
  }) = _OCRProcessingSummary;

  factory OCRProcessingSummary.fromJson(Map<String, dynamic> json) =>
      _$OCRProcessingSummaryFromJson(json);
}

/// Create OCR Session Request
@freezed
class CreateOCRSessionRequest with _$CreateOCRSessionRequest {
  const factory CreateOCRSessionRequest({
    @JsonKey(name: 'image_data') required String imageData,
    @JsonKey(name: 'image_type') required String imageType,
    @JsonKey(name: 'session_type') required String sessionType,
    @JsonKey(name: 'shop_id') required String shopId,
  }) = _CreateOCRSessionRequest;

  factory CreateOCRSessionRequest.fromJson(Map<String, dynamic> json) =>
      _$CreateOCRSessionRequestFromJson(json);
}

/// Confirm OCR Items Request
@freezed
class ConfirmOCRItemsRequest with _$ConfirmOCRItemsRequest {
  const factory ConfirmOCRItemsRequest({
    @JsonKey(name: 'session_id') required String sessionId,
    required List<OCRItemConfirmation> items,
  }) = _ConfirmOCRItemsRequest;

  factory ConfirmOCRItemsRequest.fromJson(Map<String, dynamic> json) =>
      _$ConfirmOCRItemsRequestFromJson(json);
}

/// OCR Item Confirmation
@freezed
class OCRItemConfirmation with _$OCRItemConfirmation {
  const factory OCRItemConfirmation({
    @JsonKey(name: 'item_id') required String itemId,
    @JsonKey(name: 'is_confirmed') required bool isConfirmed,
    @JsonKey(name: 'product_id') String? productId,
    required int quantity,
  }) = _OCRItemConfirmation;

  factory OCRItemConfirmation.fromJson(Map<String, dynamic> json) =>
      _$OCRItemConfirmationFromJson(json);
}

/// Quick Sale from OCR Request
@freezed
class QuickSaleFromOCRRequest with _$QuickSaleFromOCRRequest {
  const factory QuickSaleFromOCRRequest({
    @JsonKey(name: 'session_id') required String sessionId,
    @JsonKey(name: 'customer_phone') String? customerPhone,
    @JsonKey(name: 'payment_method') required String paymentMethod,
    String? notes,
  }) = _QuickSaleFromOCRRequest;

  factory QuickSaleFromOCRRequest.fromJson(Map<String, dynamic> json) =>
      _$QuickSaleFromOCRRequestFromJson(json);
}

/// OCR Matching Configuration
@freezed
class OCRMatchingConfig with _$OCRMatchingConfig {
  const factory OCRMatchingConfig({
    @JsonKey(name: 'min_confidence_score') required double minConfidenceScore,
    @JsonKey(name: 'fuzzy_match_threshold') required double fuzzyMatchThreshold,
    @JsonKey(name: 'enable_alias_matching') required bool enableAliasMatching,
    @JsonKey(name: 'enable_pattern_matching') required bool enablePatternMatching,
    @JsonKey(name: 'max_suggestions_per_item') required int maxSuggestionsPerItem,
    @JsonKey(name: 'auto_confirm_high_matches') required bool autoConfirmHighMatches,
  }) = _OCRMatchingConfig;

  factory OCRMatchingConfig.fromJson(Map<String, dynamic> json) =>
      _$OCRMatchingConfigFromJson(json);
}

/// Brand Variant model for OCR
class BrandVariant {
  final String id;
  final String brandId;
  final String size;
  final double? price;

  BrandVariant({
    required this.id,
    required this.brandId,
    required this.size,
    this.price,
  });

  factory BrandVariant.fromJson(Map<String, dynamic> json) {
    return BrandVariant(
      id: json['id'] ?? '',
      brandId: json['brand_id'] ?? '',
      size: json['size'] ?? '',
      price: json['price']?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'brand_id': brandId,
      'size': size,
      if (price != null) 'price': price,
    };
  }
}

/// OCR Status enum
enum OCRStatus {
  pending,
  processing,
  completed,
  failed,
  expired,
}

/// OCR Match Method enum
enum OCRMatchMethod {
  exact,
  fuzzy,
  alias,
  pattern,
  manual,
}

