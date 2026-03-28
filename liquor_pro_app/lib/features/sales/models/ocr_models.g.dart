// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ocr_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$OCRSessionImpl _$$OCRSessionImplFromJson(Map<String, dynamic> json) =>
    _$OCRSessionImpl(
      id: json['id'] as String,
      tenantId: json['tenant_id'] as String,
      userId: json['user_id'] as String,
      shopId: json['shop_id'] as String,
      imageUrl: json['image_url'] as String,
      imageSize: (json['image_size'] as num).toInt(),
      imageType: json['image_type'] as String,
      status: json['status'] as String,
      ocrProvider: json['ocr_provider'] as String? ?? 'google_vision',
      rawText: json['raw_text'] as String?,
      processedAt: json['processed_at'] == null
          ? null
          : DateTime.parse(json['processed_at'] as String),
      errorMessage: json['error_message'] as String?,
      confidenceScore: (json['confidence_score'] as num?)?.toDouble(),
      processingTimeMs: (json['processing_time_ms'] as num?)?.toInt(),
      receiptDate: json['receipt_date'] == null
          ? null
          : DateTime.parse(json['receipt_date'] as String),
      receiptNumber: json['receipt_number'] as String?,
      vendorName: json['vendor_name'] as String?,
      totalAmount: (json['total_amount'] as num?)?.toDouble(),
      sessionType: json['session_type'] as String? ?? 'quick_sale',
      expiresAt: DateTime.parse(json['expires_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      extractedItems: (json['extracted_items'] as List<dynamic>?)
              ?.map((e) => OCRExtractedItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );

Map<String, dynamic> _$$OCRSessionImplToJson(_$OCRSessionImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'tenant_id': instance.tenantId,
      'user_id': instance.userId,
      'shop_id': instance.shopId,
      'image_url': instance.imageUrl,
      'image_size': instance.imageSize,
      'image_type': instance.imageType,
      'status': instance.status,
      'ocr_provider': instance.ocrProvider,
      'raw_text': instance.rawText,
      'processed_at': instance.processedAt?.toIso8601String(),
      'error_message': instance.errorMessage,
      'confidence_score': instance.confidenceScore,
      'processing_time_ms': instance.processingTimeMs,
      'receipt_date': instance.receiptDate?.toIso8601String(),
      'receipt_number': instance.receiptNumber,
      'vendor_name': instance.vendorName,
      'total_amount': instance.totalAmount,
      'session_type': instance.sessionType,
      'expires_at': instance.expiresAt.toIso8601String(),
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt.toIso8601String(),
      'extracted_items':
          instance.extractedItems.map((e) => e.toJson()).toList(),
    };

_$OCRExtractedItemImpl _$$OCRExtractedItemImplFromJson(
        Map<String, dynamic> json) =>
    _$OCRExtractedItemImpl(
      id: json['id'] as String,
      sessionId: json['session_id'] as String,
      extractedText: json['extracted_text'] as String,
      brandText: json['brand_text'] as String?,
      sizeText: json['size_text'] as String?,
      quantityText: json['quantity_text'] as String?,
      priceText: json['price_text'] as String?,
      parsedQuantity: (json['parsed_quantity'] as num?)?.toInt(),
      parsedPrice: (json['parsed_price'] as num?)?.toDouble(),
      parsedSize: json['parsed_size'] as String?,
      ratePerUnit: (json['rate_per_unit'] as num?)?.toDouble(),
      openingStock: (json['opening_stock'] as num?)?.toInt(),
      closingStock: (json['closing_stock'] as num?)?.toInt(),
      rowNumber: (json['row_number'] as num?)?.toInt(),
      matchedProductId: json['matched_product_id'] as String?,
      matchedBrandId: json['matched_brand_id'] as String?,
      matchedVariantId: json['matched_variant_id'] as String?,
      matchConfidence: (json['match_confidence'] as num).toDouble(),
      matchMethod: json['match_method'] as String?,
      matchDetails: json['match_details'] as Map<String, dynamic>?,
      isConfirmed: json['is_confirmed'] as bool? ?? false,
      isRejected: json['is_rejected'] as bool? ?? false,
      userCorrectedProductId: json['user_corrected_product_id'] as String?,
      userCorrectedQuantity: (json['user_corrected_quantity'] as num?)?.toInt(),
      correctionReason: json['correction_reason'] as String?,
      lineNumber: (json['line_number'] as num?)?.toInt(),
      boundingBox: json['bounding_box'] as Map<String, dynamic>?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );

Map<String, dynamic> _$$OCRExtractedItemImplToJson(
        _$OCRExtractedItemImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'session_id': instance.sessionId,
      'extracted_text': instance.extractedText,
      'brand_text': instance.brandText,
      'size_text': instance.sizeText,
      'quantity_text': instance.quantityText,
      'price_text': instance.priceText,
      'parsed_quantity': instance.parsedQuantity,
      'parsed_price': instance.parsedPrice,
      'parsed_size': instance.parsedSize,
      'rate_per_unit': instance.ratePerUnit,
      'opening_stock': instance.openingStock,
      'closing_stock': instance.closingStock,
      'row_number': instance.rowNumber,
      'matched_product_id': instance.matchedProductId,
      'matched_brand_id': instance.matchedBrandId,
      'matched_variant_id': instance.matchedVariantId,
      'match_confidence': instance.matchConfidence,
      'match_method': instance.matchMethod,
      'match_details': instance.matchDetails,
      'is_confirmed': instance.isConfirmed,
      'is_rejected': instance.isRejected,
      'user_corrected_product_id': instance.userCorrectedProductId,
      'user_corrected_quantity': instance.userCorrectedQuantity,
      'correction_reason': instance.correctionReason,
      'line_number': instance.lineNumber,
      'bounding_box': instance.boundingBox,
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt.toIso8601String(),
    };

_$BrandAliasImpl _$$BrandAliasImplFromJson(Map<String, dynamic> json) =>
    _$BrandAliasImpl(
      id: json['id'] as String,
      tenantId: json['tenant_id'] as String,
      brandId: json['brand_id'] as String,
      aliasText: json['alias_text'] as String,
      aliasType: json['alias_type'] as String,
      matchCount: (json['match_count'] as num?)?.toInt() ?? 0,
      lastMatchedAt: json['last_matched_at'] == null
          ? null
          : DateTime.parse(json['last_matched_at'] as String),
      isActive: json['is_active'] as bool? ?? true,
      createdBy: json['created_by'] as String?,
      approvedBy: json['approved_by'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );

Map<String, dynamic> _$$BrandAliasImplToJson(_$BrandAliasImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'tenant_id': instance.tenantId,
      'brand_id': instance.brandId,
      'alias_text': instance.aliasText,
      'alias_type': instance.aliasType,
      'match_count': instance.matchCount,
      'last_matched_at': instance.lastMatchedAt?.toIso8601String(),
      'is_active': instance.isActive,
      'created_by': instance.createdBy,
      'approved_by': instance.approvedBy,
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt.toIso8601String(),
    };

_$OCRSessionResponseImpl _$$OCRSessionResponseImplFromJson(
        Map<String, dynamic> json) =>
    _$OCRSessionResponseImpl(
      session: OCRSession.fromJson(json['session'] as Map<String, dynamic>),
      extractedItems: (json['extracted_items'] as List<dynamic>?)
              ?.map((e) => OCRExtractedItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      summary: json['summary'] == null
          ? null
          : OCRProcessingSummary.fromJson(
              json['summary'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$$OCRSessionResponseImplToJson(
        _$OCRSessionResponseImpl instance) =>
    <String, dynamic>{
      'session': instance.session.toJson(),
      'extracted_items':
          instance.extractedItems.map((e) => e.toJson()).toList(),
      'summary': instance.summary?.toJson(),
    };

_$OCRProcessingSummaryImpl _$$OCRProcessingSummaryImplFromJson(
        Map<String, dynamic> json) =>
    _$OCRProcessingSummaryImpl(
      totalItems: (json['total_items'] as num).toInt(),
      matchedItems: (json['matched_items'] as num).toInt(),
      unmatchedItems: (json['unmatched_items'] as num).toInt(),
      confidenceAvg: (json['confidence_avg'] as num).toDouble(),
      processingTimeMs: (json['processing_time_ms'] as num).toInt(),
      requiresReview: json['requires_review'] as bool,
    );

Map<String, dynamic> _$$OCRProcessingSummaryImplToJson(
        _$OCRProcessingSummaryImpl instance) =>
    <String, dynamic>{
      'total_items': instance.totalItems,
      'matched_items': instance.matchedItems,
      'unmatched_items': instance.unmatchedItems,
      'confidence_avg': instance.confidenceAvg,
      'processing_time_ms': instance.processingTimeMs,
      'requires_review': instance.requiresReview,
    };

_$CreateOCRSessionRequestImpl _$$CreateOCRSessionRequestImplFromJson(
        Map<String, dynamic> json) =>
    _$CreateOCRSessionRequestImpl(
      imageData: json['image_data'] as String,
      imageType: json['image_type'] as String,
      sessionType: json['session_type'] as String,
      shopId: json['shop_id'] as String,
    );

Map<String, dynamic> _$$CreateOCRSessionRequestImplToJson(
        _$CreateOCRSessionRequestImpl instance) =>
    <String, dynamic>{
      'image_data': instance.imageData,
      'image_type': instance.imageType,
      'session_type': instance.sessionType,
      'shop_id': instance.shopId,
    };

_$ConfirmOCRItemsRequestImpl _$$ConfirmOCRItemsRequestImplFromJson(
        Map<String, dynamic> json) =>
    _$ConfirmOCRItemsRequestImpl(
      sessionId: json['session_id'] as String,
      items: (json['items'] as List<dynamic>)
          .map((e) => OCRItemConfirmation.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$$ConfirmOCRItemsRequestImplToJson(
        _$ConfirmOCRItemsRequestImpl instance) =>
    <String, dynamic>{
      'session_id': instance.sessionId,
      'items': instance.items.map((e) => e.toJson()).toList(),
    };

_$OCRItemConfirmationImpl _$$OCRItemConfirmationImplFromJson(
        Map<String, dynamic> json) =>
    _$OCRItemConfirmationImpl(
      itemId: json['item_id'] as String,
      isConfirmed: json['is_confirmed'] as bool,
      productId: json['product_id'] as String?,
      quantity: (json['quantity'] as num).toInt(),
    );

Map<String, dynamic> _$$OCRItemConfirmationImplToJson(
        _$OCRItemConfirmationImpl instance) =>
    <String, dynamic>{
      'item_id': instance.itemId,
      'is_confirmed': instance.isConfirmed,
      'product_id': instance.productId,
      'quantity': instance.quantity,
    };

_$QuickSaleFromOCRRequestImpl _$$QuickSaleFromOCRRequestImplFromJson(
        Map<String, dynamic> json) =>
    _$QuickSaleFromOCRRequestImpl(
      sessionId: json['session_id'] as String,
      customerPhone: json['customer_phone'] as String?,
      paymentMethod: json['payment_method'] as String,
      notes: json['notes'] as String?,
    );

Map<String, dynamic> _$$QuickSaleFromOCRRequestImplToJson(
        _$QuickSaleFromOCRRequestImpl instance) =>
    <String, dynamic>{
      'session_id': instance.sessionId,
      'customer_phone': instance.customerPhone,
      'payment_method': instance.paymentMethod,
      'notes': instance.notes,
    };

_$OCRMatchingConfigImpl _$$OCRMatchingConfigImplFromJson(
        Map<String, dynamic> json) =>
    _$OCRMatchingConfigImpl(
      minConfidenceScore: (json['min_confidence_score'] as num).toDouble(),
      fuzzyMatchThreshold: (json['fuzzy_match_threshold'] as num).toDouble(),
      enableAliasMatching: json['enable_alias_matching'] as bool,
      enablePatternMatching: json['enable_pattern_matching'] as bool,
      maxSuggestionsPerItem: (json['max_suggestions_per_item'] as num).toInt(),
      autoConfirmHighMatches: json['auto_confirm_high_matches'] as bool,
    );

Map<String, dynamic> _$$OCRMatchingConfigImplToJson(
        _$OCRMatchingConfigImpl instance) =>
    <String, dynamic>{
      'min_confidence_score': instance.minConfidenceScore,
      'fuzzy_match_threshold': instance.fuzzyMatchThreshold,
      'enable_alias_matching': instance.enableAliasMatching,
      'enable_pattern_matching': instance.enablePatternMatching,
      'max_suggestions_per_item': instance.maxSuggestionsPerItem,
      'auto_confirm_high_matches': instance.autoConfirmHighMatches,
    };
