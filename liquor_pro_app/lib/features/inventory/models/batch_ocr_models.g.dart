// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'batch_ocr_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$BatchOCRSessionImpl _$$BatchOCRSessionImplFromJson(
        Map<String, dynamic> json) =>
    _$BatchOCRSessionImpl(
      id: json['id'] as String,
      tenantId: json['tenant_id'] as String,
      userId: json['user_id'] as String,
      shopId: json['shop_id'] as String,
      sessionType: json['session_type'] as String,
      status: $enumDecode(_$BatchStatusEnumMap, json['status']),
      totalImages: (json['total_images'] as num).toInt(),
      completedImages: (json['completed_images'] as num).toInt(),
      failedImages: (json['failed_images'] as num).toInt(),
      totalItemsExtracted: (json['total_items_extracted'] as num).toInt(),
      createdAt: DateTime.parse(json['created_at'] as String),
      startedAt: json['started_at'] == null
          ? null
          : DateTime.parse(json['started_at'] as String),
      completedAt: json['completed_at'] == null
          ? null
          : DateTime.parse(json['completed_at'] as String),
      sessionIds: (json['session_ids'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      metadata: json['metadata'] as Map<String, dynamic>?,
    );

Map<String, dynamic> _$$BatchOCRSessionImplToJson(
        _$BatchOCRSessionImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'tenant_id': instance.tenantId,
      'user_id': instance.userId,
      'shop_id': instance.shopId,
      'session_type': instance.sessionType,
      'status': _$BatchStatusEnumMap[instance.status]!,
      'total_images': instance.totalImages,
      'completed_images': instance.completedImages,
      'failed_images': instance.failedImages,
      'total_items_extracted': instance.totalItemsExtracted,
      'created_at': instance.createdAt.toIso8601String(),
      'started_at': instance.startedAt?.toIso8601String(),
      'completed_at': instance.completedAt?.toIso8601String(),
      'session_ids': instance.sessionIds,
      'metadata': instance.metadata,
    };

const _$BatchStatusEnumMap = {
  BatchStatus.pending: 'pending',
  BatchStatus.processing: 'processing',
  BatchStatus.completed: 'completed',
  BatchStatus.partial: 'partial',
  BatchStatus.failed: 'failed',
};

_$FailedImageImpl _$$FailedImageImplFromJson(Map<String, dynamic> json) =>
    _$FailedImageImpl(
      imagePath: json['imagePath'] as String,
      errorMessage: json['errorMessage'] as String,
      failedAt: DateTime.parse(json['failedAt'] as String),
      retryCount: (json['retryCount'] as num?)?.toInt() ?? 0,
      errorCode: json['errorCode'] as String?,
    );

Map<String, dynamic> _$$FailedImageImplToJson(_$FailedImageImpl instance) =>
    <String, dynamic>{
      'imagePath': instance.imagePath,
      'errorMessage': instance.errorMessage,
      'failedAt': instance.failedAt.toIso8601String(),
      'retryCount': instance.retryCount,
      'errorCode': instance.errorCode,
    };

_$ProcessingTimeoutImpl _$$ProcessingTimeoutImplFromJson(
        Map<String, dynamic> json) =>
    _$ProcessingTimeoutImpl(
      startTime: DateTime.parse(json['startTime'] as String),
      maxDuration: Duration(microseconds: (json['maxDuration'] as num).toInt()),
      currentStage: json['currentStage'] as String?,
    );

Map<String, dynamic> _$$ProcessingTimeoutImplToJson(
        _$ProcessingTimeoutImpl instance) =>
    <String, dynamic>{
      'startTime': instance.startTime.toIso8601String(),
      'maxDuration': instance.maxDuration.inMicroseconds,
      'currentStage': instance.currentStage,
    };

_$ImageDataImpl _$$ImageDataImplFromJson(Map<String, dynamic> json) =>
    _$ImageDataImpl(
      imageData: json['image_data'] as String,
      imageType: json['image_type'] as String,
      fileName: json['file_name'] as String?,
      fileSize: (json['file_size'] as num?)?.toInt(),
    );

Map<String, dynamic> _$$ImageDataImplToJson(_$ImageDataImpl instance) =>
    <String, dynamic>{
      'image_data': instance.imageData,
      'image_type': instance.imageType,
      'file_name': instance.fileName,
      'file_size': instance.fileSize,
    };

_$CreateBatchOCRRequestImpl _$$CreateBatchOCRRequestImplFromJson(
        Map<String, dynamic> json) =>
    _$CreateBatchOCRRequestImpl(
      images: (json['images'] as List<dynamic>)
          .map((e) => ImageData.fromJson(e as Map<String, dynamic>))
          .toList(),
      shopId: json['shop_id'] as String,
      sessionType: json['sessionType'] as String? ?? 'stock_initialization',
      metadata: json['metadata'] as Map<String, dynamic>?,
    );

Map<String, dynamic> _$$CreateBatchOCRRequestImplToJson(
        _$CreateBatchOCRRequestImpl instance) =>
    <String, dynamic>{
      'images': instance.images.map((e) => e.toJson()).toList(),
      'shop_id': instance.shopId,
      'sessionType': instance.sessionType,
      'metadata': instance.metadata,
    };

_$BatchOCRResponseImpl _$$BatchOCRResponseImplFromJson(
        Map<String, dynamic> json) =>
    _$BatchOCRResponseImpl(
      id: json['id'] as String,
      status: json['status'] as String,
      totalImages: (json['total_images'] as num).toInt(),
      message: json['message'] as String,
    );

Map<String, dynamic> _$$BatchOCRResponseImplToJson(
        _$BatchOCRResponseImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'status': instance.status,
      'total_images': instance.totalImages,
      'message': instance.message,
    };

_$DeduplicatedItemImpl _$$DeduplicatedItemImplFromJson(
        Map<String, dynamic> json) =>
    _$DeduplicatedItemImpl(
      brandText: json['brand_text'] as String? ?? '',
      sizeText: json['size_text'] as String? ?? '',
      totalStock: (json['quantity'] as num?)?.toInt() ?? 0,
      sourceSessionIds: (json['source_sessions'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      sourceItemIds: (json['source_items'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      categoryId: json['category_id'] as String?,
      subcategoryId: json['subcategory_id'] as String?,
      inferredCategoryName: json['inferred_category_name'] as String?,
      categoryConfidence: (json['category_confidence'] as num?)?.toDouble(),
      inferredSubcategoryName: json['inferred_subcategory_name'] as String?,
      matchedBrandId: json['matched_brand_id'] as String?,
      matchedVariantId: json['matched_variant_id'] as String?,
      matchConfidence: (json['match_confidence'] as num?)?.toDouble() ?? 0.0,
      confidence: (json['confidence'] as num?)?.toDouble(),
      isDuplicate: json['is_duplicate'] as bool? ?? false,
      rowNumber: (json['row_number'] as num?)?.toInt(),
      sellingPrice: (json['selling_price'] as num?)?.toDouble(),
      id: json['id'] as String?,
      sessionId: json['session_id'] as String?,
      batchId: json['batch_id'] as String?,
      normalizedBrandName: json['normalized_brand_name'] as String?,
      matchStrategy: json['match_strategy'] as String?,
      isReviewed: json['is_reviewed'] as bool? ?? false,
      isSelected: json['is_selected'] as bool? ?? true,
    );

Map<String, dynamic> _$$DeduplicatedItemImplToJson(
        _$DeduplicatedItemImpl instance) =>
    <String, dynamic>{
      'brand_text': instance.brandText,
      'size_text': instance.sizeText,
      'quantity': instance.totalStock,
      'source_sessions': instance.sourceSessionIds,
      'source_items': instance.sourceItemIds,
      'category_id': instance.categoryId,
      'subcategory_id': instance.subcategoryId,
      'inferred_category_name': instance.inferredCategoryName,
      'category_confidence': instance.categoryConfidence,
      'inferred_subcategory_name': instance.inferredSubcategoryName,
      'matched_brand_id': instance.matchedBrandId,
      'matched_variant_id': instance.matchedVariantId,
      'match_confidence': instance.matchConfidence,
      'confidence': instance.confidence,
      'is_duplicate': instance.isDuplicate,
      'row_number': instance.rowNumber,
      'selling_price': instance.sellingPrice,
      'id': instance.id,
      'session_id': instance.sessionId,
      'batch_id': instance.batchId,
      'normalized_brand_name': instance.normalizedBrandName,
      'match_strategy': instance.matchStrategy,
      'is_reviewed': instance.isReviewed,
      'is_selected': instance.isSelected,
    };

_$RejectedItemImpl _$$RejectedItemImplFromJson(Map<String, dynamic> json) =>
    _$RejectedItemImpl(
      brandText: json['brand_text'] as String? ?? '',
      sizeText: json['size_text'] as String?,
      totalStock: (json['quantity'] as num?)?.toInt() ?? 0,
      sellingPrice: (json['selling_price'] as num?)?.toDouble(),
      rejectionReason: json['rejection_reason'] as String? ?? 'Unknown reason',
      rejectionStage: json['rejection_stage'] as String? ?? 'validation',
      canRecover: json['can_recover'] as bool? ?? true,
      confidence: (json['confidence'] as num?)?.toDouble(),
      id: json['id'] as String?,
      sourceSessionId: json['source_session_id'] as String?,
    );

Map<String, dynamic> _$$RejectedItemImplToJson(_$RejectedItemImpl instance) =>
    <String, dynamic>{
      'brand_text': instance.brandText,
      'size_text': instance.sizeText,
      'quantity': instance.totalStock,
      'selling_price': instance.sellingPrice,
      'rejection_reason': instance.rejectionReason,
      'rejection_stage': instance.rejectionStage,
      'can_recover': instance.canRecover,
      'confidence': instance.confidence,
      'id': instance.id,
      'source_session_id': instance.sourceSessionId,
    };

_$DeduplicateRequestImpl _$$DeduplicateRequestImplFromJson(
        Map<String, dynamic> json) =>
    _$DeduplicateRequestImpl(
      sessionIds: (json['session_ids'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
    );

Map<String, dynamic> _$$DeduplicateRequestImplToJson(
        _$DeduplicateRequestImpl instance) =>
    <String, dynamic>{
      'session_ids': instance.sessionIds,
    };

_$EnrichedStockItemImpl _$$EnrichedStockItemImplFromJson(
        Map<String, dynamic> json) =>
    _$EnrichedStockItemImpl(
      ocrItemId: json['ocr_item_id'] as String,
      brandText: json['brand_text'] as String,
      sizeText: json['size_text'] as String,
      availableStock: (json['available_stock'] as num).toInt(),
      categoryId: json['category_id'] as String?,
      subcategoryId: json['subcategory_id'] as String?,
      saasBrandId: json['saas_brand_id'] as String?,
      brandVariantId: json['brand_variant_id'] as String?,
      sellingPrice: (json['selling_price'] as num?)?.toDouble(),
      costPrice: (json['cost_price'] as num?)?.toDouble(),
      mrp: (json['mrp'] as num?)?.toDouble(),
      reorderLevel: (json['reorder_level'] as num?)?.toInt(),
      isDuplicate: json['is_duplicate'] as bool? ?? false,
      isConfirmed: json['is_confirmed'] as bool? ?? false,
      enrichmentStatus: $enumDecodeNullable(
              _$EnrichmentStatusEnumMap, json['enrichment_status']) ??
          EnrichmentStatus.pending,
      validationErrors: (json['validation_errors'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
    );

Map<String, dynamic> _$$EnrichedStockItemImplToJson(
        _$EnrichedStockItemImpl instance) =>
    <String, dynamic>{
      'ocr_item_id': instance.ocrItemId,
      'brand_text': instance.brandText,
      'size_text': instance.sizeText,
      'available_stock': instance.availableStock,
      'category_id': instance.categoryId,
      'subcategory_id': instance.subcategoryId,
      'saas_brand_id': instance.saasBrandId,
      'brand_variant_id': instance.brandVariantId,
      'selling_price': instance.sellingPrice,
      'cost_price': instance.costPrice,
      'mrp': instance.mrp,
      'reorder_level': instance.reorderLevel,
      'is_duplicate': instance.isDuplicate,
      'is_confirmed': instance.isConfirmed,
      'enrichment_status':
          _$EnrichmentStatusEnumMap[instance.enrichmentStatus]!,
      'validation_errors': instance.validationErrors,
    };

const _$EnrichmentStatusEnumMap = {
  EnrichmentStatus.pending: 'pending',
  EnrichmentStatus.inProgress: 'in_progress',
  EnrichmentStatus.complete: 'complete',
  EnrichmentStatus.skipped: 'skipped',
};

_$InitializeStockFromOCRRequestImpl
    _$$InitializeStockFromOCRRequestImplFromJson(Map<String, dynamic> json) =>
        _$InitializeStockFromOCRRequestImpl(
          sessionIds: (json['session_ids'] as List<dynamic>)
              .map((e) => e as String)
              .toList(),
          shopId: json['shop_id'] as String,
          reason: json['reason'] as String,
          items: (json['items'] as List<dynamic>)
              .map((e) =>
                  EnrichedStockItemRequest.fromJson(e as Map<String, dynamic>))
              .toList(),
        );

Map<String, dynamic> _$$InitializeStockFromOCRRequestImplToJson(
        _$InitializeStockFromOCRRequestImpl instance) =>
    <String, dynamic>{
      'session_ids': instance.sessionIds,
      'shop_id': instance.shopId,
      'reason': instance.reason,
      'items': instance.items.map((e) => e.toJson()).toList(),
    };

_$EnrichedStockItemRequestImpl _$$EnrichedStockItemRequestImplFromJson(
        Map<String, dynamic> json) =>
    _$EnrichedStockItemRequestImpl(
      ocrItemId: json['ocr_item_id'] as String,
      brandText: json['brand_text'] as String,
      sizeText: json['size_text'] as String,
      categoryId: json['category_id'] as String,
      subcategoryId: json['subcategory_id'] as String?,
      sellingPrice: (json['selling_price'] as num).toDouble(),
      costPrice: (json['cost_price'] as num).toDouble(),
      mrp: (json['mrp'] as num).toDouble(),
      availableStock: (json['available_stock'] as num).toInt(),
      reorderLevel: (json['reorder_level'] as num?)?.toInt(),
      isDuplicate: json['is_duplicate'] as bool? ?? false,
    );

Map<String, dynamic> _$$EnrichedStockItemRequestImplToJson(
        _$EnrichedStockItemRequestImpl instance) =>
    <String, dynamic>{
      'ocr_item_id': instance.ocrItemId,
      'brand_text': instance.brandText,
      'size_text': instance.sizeText,
      'category_id': instance.categoryId,
      'subcategory_id': instance.subcategoryId,
      'selling_price': instance.sellingPrice,
      'cost_price': instance.costPrice,
      'mrp': instance.mrp,
      'available_stock': instance.availableStock,
      'reorder_level': instance.reorderLevel,
      'is_duplicate': instance.isDuplicate,
    };

_$InitializeStockResponseImpl _$$InitializeStockResponseImplFromJson(
        Map<String, dynamic> json) =>
    _$InitializeStockResponseImpl(
      success: json['success'] as bool,
      message: json['message'] as String,
      itemsProcessed: (json['items_processed'] as num).toInt(),
      itemsCreated: (json['items_created'] as num).toInt(),
      itemsFailed: (json['items_failed'] as num).toInt(),
      results: (json['results'] as List<dynamic>?)
              ?.map((e) =>
                  StockInitializationResult.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      summary: json['summary'] as Map<String, dynamic>?,
    );

Map<String, dynamic> _$$InitializeStockResponseImplToJson(
        _$InitializeStockResponseImpl instance) =>
    <String, dynamic>{
      'success': instance.success,
      'message': instance.message,
      'items_processed': instance.itemsProcessed,
      'items_created': instance.itemsCreated,
      'items_failed': instance.itemsFailed,
      'results': instance.results.map((e) => e.toJson()).toList(),
      'summary': instance.summary,
    };

_$StockInitializationResultImpl _$$StockInitializationResultImplFromJson(
        Map<String, dynamic> json) =>
    _$StockInitializationResultImpl(
      ocrItemId: json['ocr_item_id'] as String,
      success: json['success'] as bool,
      productId: json['product_id'] as String?,
      error: json['error'] as String?,
      details: json['details'] as Map<String, dynamic>?,
    );

Map<String, dynamic> _$$StockInitializationResultImplToJson(
        _$StockInitializationResultImpl instance) =>
    <String, dynamic>{
      'ocr_item_id': instance.ocrItemId,
      'success': instance.success,
      'product_id': instance.productId,
      'error': instance.error,
      'details': instance.details,
    };

_$BatchOCRProgressImpl _$$BatchOCRProgressImplFromJson(
        Map<String, dynamic> json) =>
    _$BatchOCRProgressImpl(
      batchId: json['batch_id'] as String,
      totalImages: (json['total_images'] as num).toInt(),
      completedImages: (json['completed_images'] as num).toInt(),
      failedImages: (json['failed_images'] as num).toInt(),
      progressPercentage: (json['progress_percentage'] as num).toDouble(),
      status: $enumDecode(_$BatchStatusEnumMap, json['status']),
      currentImageName: json['current_image_name'] as String?,
      estimatedTimeRemainingSeconds:
          (json['estimated_time_remaining_seconds'] as num?)?.toInt(),
      stage: json['stage'] as String?,
      itemsExtracted: (json['items_extracted'] as num?)?.toInt(),
      currentItem: json['current_item'] as String?,
    );

Map<String, dynamic> _$$BatchOCRProgressImplToJson(
        _$BatchOCRProgressImpl instance) =>
    <String, dynamic>{
      'batch_id': instance.batchId,
      'total_images': instance.totalImages,
      'completed_images': instance.completedImages,
      'failed_images': instance.failedImages,
      'progress_percentage': instance.progressPercentage,
      'status': _$BatchStatusEnumMap[instance.status]!,
      'current_image_name': instance.currentImageName,
      'estimated_time_remaining_seconds':
          instance.estimatedTimeRemainingSeconds,
      'stage': instance.stage,
      'items_extracted': instance.itemsExtracted,
      'current_item': instance.currentItem,
    };

_$EnrichmentWorkflowStateImpl _$$EnrichmentWorkflowStateImplFromJson(
        Map<String, dynamic> json) =>
    _$EnrichmentWorkflowStateImpl(
      batchId: json['batch_id'] as String,
      sessionIds: (json['session_ids'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      deduplicatedItems: (json['deduplicated_items'] as List<dynamic>)
          .map((e) => DeduplicatedItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      enrichedItems: (json['enriched_items'] as List<dynamic>)
          .map((e) => EnrichedStockItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      currentItemIndex: (json['current_item_index'] as num).toInt(),
      currentStep: $enumDecode(_$EnrichmentStepEnumMap, json['current_step']),
      isLoading: json['is_loading'] as bool? ?? false,
      error: json['error'] as String?,
    );

Map<String, dynamic> _$$EnrichmentWorkflowStateImplToJson(
        _$EnrichmentWorkflowStateImpl instance) =>
    <String, dynamic>{
      'batch_id': instance.batchId,
      'session_ids': instance.sessionIds,
      'deduplicated_items':
          instance.deduplicatedItems.map((e) => e.toJson()).toList(),
      'enriched_items': instance.enrichedItems.map((e) => e.toJson()).toList(),
      'current_item_index': instance.currentItemIndex,
      'current_step': _$EnrichmentStepEnumMap[instance.currentStep]!,
      'is_loading': instance.isLoading,
      'error': instance.error,
    };

const _$EnrichmentStepEnumMap = {
  EnrichmentStep.enrichment: 'enrichment',
  EnrichmentStep.review: 'review',
  EnrichmentStep.submission: 'submission',
  EnrichmentStep.complete: 'complete',
};
