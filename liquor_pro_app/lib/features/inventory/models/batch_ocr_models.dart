import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:flutter/foundation.dart';

part 'batch_ocr_models.freezed.dart';
part 'batch_ocr_models.g.dart';

/// Batch OCR Session - Tracks processing of multiple images
@freezed
class BatchOCRSession with _$BatchOCRSession {
  const factory BatchOCRSession({
    required String id,
    @JsonKey(name: 'tenant_id') required String tenantId,
    @JsonKey(name: 'user_id') required String userId,
    @JsonKey(name: 'shop_id') required String shopId,
    @JsonKey(name: 'session_type') required String sessionType,
    required BatchStatus status,
    @JsonKey(name: 'total_images') required int totalImages,
    @JsonKey(name: 'completed_images') required int completedImages,
    @JsonKey(name: 'failed_images') required int failedImages,
    @JsonKey(name: 'total_items_extracted') required int totalItemsExtracted,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'started_at') DateTime? startedAt,
    @JsonKey(name: 'completed_at') DateTime? completedAt,
    @JsonKey(name: 'session_ids') @Default([]) List<String> sessionIds,
    Map<String, dynamic>? metadata,
  }) = _BatchOCRSession;

  factory BatchOCRSession.fromJson(Map<String, dynamic> json) =>
      _$BatchOCRSessionFromJson(json);
}

/// Batch processing status
enum BatchStatus {
  @JsonValue('pending')
  pending,
  @JsonValue('processing')
  processing,
  @JsonValue('completed')
  completed,
  @JsonValue('partial')
  partial,
  @JsonValue('failed')
  failed,
}

/// Phase 4: Failed image information for retry
@freezed
class FailedImage with _$FailedImage {
  const factory FailedImage({
    required String imagePath,
    required String errorMessage,
    required DateTime failedAt,
    @Default(0) int retryCount,
    String? errorCode,
  }) = _FailedImage;

  factory FailedImage.fromJson(Map<String, dynamic> json) =>
      _$FailedImageFromJson(json);
}

/// Phase 4: Processing timeout information
@freezed
class ProcessingTimeout with _$ProcessingTimeout {
  const factory ProcessingTimeout({
    required DateTime startTime,
    required Duration maxDuration,
    String? currentStage,
  }) = _ProcessingTimeout;

  const ProcessingTimeout._();

  /// Check if timeout has been exceeded
  bool get isTimedOut {
    final elapsed = DateTime.now().difference(startTime);
    return elapsed > maxDuration;
  }

  /// Get remaining time before timeout
  Duration get remainingTime {
    final elapsed = DateTime.now().difference(startTime);
    final remaining = maxDuration - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  factory ProcessingTimeout.fromJson(Map<String, dynamic> json) =>
      _$ProcessingTimeoutFromJson(json);
}

/// Image data for batch processing
@freezed
class ImageData with _$ImageData {
  const factory ImageData({
    @JsonKey(name: 'image_data') required String imageData, // Base64 encoded
    @JsonKey(name: 'image_type') required String imageType, // png, jpg, jpeg
    @JsonKey(name: 'file_name') String? fileName,
    @JsonKey(name: 'file_size') int? fileSize,
  }) = _ImageData;

  factory ImageData.fromJson(Map<String, dynamic> json) =>
      _$ImageDataFromJson(json);
}

/// Request to create a batch OCR session
@Freezed(toJson: true)
class CreateBatchOCRRequest with _$CreateBatchOCRRequest {
  const factory CreateBatchOCRRequest({
    required List<ImageData> images,
    @JsonKey(name: 'shop_id') required String shopId,
    @Default('stock_initialization') String sessionType,
    Map<String, dynamic>? metadata,
  }) = _CreateBatchOCRRequest;

  factory CreateBatchOCRRequest.fromJson(Map<String, dynamic> json) =>
      _$CreateBatchOCRRequestFromJson(json);
}

/// Response after creating a batch session
@freezed
class BatchOCRResponse with _$BatchOCRResponse {
  const factory BatchOCRResponse({
    required String id,
    required String status,
    @JsonKey(name: 'total_images') required int totalImages,
    required String message,
  }) = _BatchOCRResponse;

  factory BatchOCRResponse.fromJson(Map<String, dynamic> json) =>
      _$BatchOCRResponseFromJson(json);
}

/// Deduplicated item from multiple OCR sessions
///
/// PRODUCTION-READY: Handles backend field variations and null safety
/// - Made all numeric fields nullable with defaults
/// - Gracefully handles null values with safe defaults
/// - Supports backend field variations
@freezed
class DeduplicatedItem with _$DeduplicatedItem {
  const factory DeduplicatedItem({
    @JsonKey(name: 'brand_text') @Default('') String brandText,
    @JsonKey(name: 'size_text') @Default('') String sizeText,
    // Backend sends 'quantity', map to totalStock
    @JsonKey(name: 'quantity') @Default(0) int totalStock,
    // Backend sends 'match_confidence' - map to matchConfidence (removed averageConfidence duplicate)
    @JsonKey(name: 'source_sessions') @Default([]) List<String> sourceSessionIds,
    @JsonKey(name: 'source_items') @Default([]) List<String> sourceItemIds,
    @JsonKey(name: 'category_id') String? categoryId,
    @JsonKey(name: 'subcategory_id') String? subcategoryId,
    // Category inference fields from backend OCR
    @JsonKey(name: 'inferred_category_name') String? inferredCategoryName,
    @JsonKey(name: 'category_confidence') double? categoryConfidence,
    @JsonKey(name: 'inferred_subcategory_name') String? inferredSubcategoryName,
    @JsonKey(name: 'matched_brand_id') String? matchedBrandId,
    @JsonKey(name: 'matched_variant_id') String? matchedVariantId,
    // This maps to backend's match_confidence field (for brand matching)
    @JsonKey(name: 'match_confidence') @Default(0.0) double matchConfidence,
    // OCR extraction confidence (for text recognition quality)
    @JsonKey(name: 'confidence') double? confidence,
    @JsonKey(name: 'is_duplicate') @Default(false) bool isDuplicate,
    @JsonKey(name: 'row_number') int? rowNumber,
    @JsonKey(name: 'selling_price') double? sellingPrice,
    // Additional fields from backend
    @JsonKey(name: 'id') String? id,
    @JsonKey(name: 'session_id') String? sessionId,
    @JsonKey(name: 'batch_id') String? batchId,
    @JsonKey(name: 'normalized_brand_name') String? normalizedBrandName,
    @JsonKey(name: 'match_strategy') String? matchStrategy,
    @JsonKey(name: 'is_reviewed') @Default(false) bool isReviewed,
    @JsonKey(name: 'is_selected') @Default(true) bool isSelected,
  }) = _DeduplicatedItem;

  factory DeduplicatedItem.fromJson(Map<String, dynamic> json) =>
      _$DeduplicatedItemFromJson(json);
}

/// Rejected Item - Items filtered out by brand validation
@freezed
class RejectedItem with _$RejectedItem {
  const factory RejectedItem({
    @JsonKey(name: 'brand_text') @Default('') String brandText,
    @JsonKey(name: 'size_text') String? sizeText,
    @JsonKey(name: 'quantity') @Default(0) int totalStock,
    @JsonKey(name: 'selling_price') double? sellingPrice,
    @JsonKey(name: 'rejection_reason') @Default('Unknown reason') String rejectionReason,
    @JsonKey(name: 'rejection_stage') @Default('validation') String rejectionStage,
    @JsonKey(name: 'can_recover') @Default(true) bool canRecover,
    @JsonKey(name: 'confidence') double? confidence,
    @JsonKey(name: 'id') String? id,
    @JsonKey(name: 'source_session_id') String? sourceSessionId,
  }) = _RejectedItem;

  factory RejectedItem.fromJson(Map<String, dynamic> json) =>
      _$RejectedItemFromJson(json);
}

/// Request to get deduplicated items
@freezed
class DeduplicateRequest with _$DeduplicateRequest {
  const factory DeduplicateRequest({
    @JsonKey(name: 'session_ids') required List<String> sessionIds,
  }) = _DeduplicateRequest;

  factory DeduplicateRequest.fromJson(Map<String, dynamic> json) =>
      _$DeduplicateRequestFromJson(json);
}

/// Enriched stock item - OCR item with user-added product details
@freezed
class EnrichedStockItem with _$EnrichedStockItem {
  const factory EnrichedStockItem({
    @JsonKey(name: 'ocr_item_id') required String ocrItemId,
    @JsonKey(name: 'brand_text') required String brandText,
    @JsonKey(name: 'size_text') required String sizeText,
    @JsonKey(name: 'available_stock') required int availableStock,
    @JsonKey(name: 'category_id') String? categoryId,
    @JsonKey(name: 'subcategory_id') String? subcategoryId,
    @JsonKey(name: 'saas_brand_id') String? saasBrandId,
    @JsonKey(name: 'brand_variant_id') String? brandVariantId,
    @JsonKey(name: 'selling_price') double? sellingPrice,
    @JsonKey(name: 'cost_price') double? costPrice,
    double? mrp,
    @JsonKey(name: 'reorder_level') int? reorderLevel,
    @JsonKey(name: 'is_duplicate') @Default(false) bool isDuplicate,
    @JsonKey(name: 'is_confirmed') @Default(false) bool isConfirmed,
    // Enrichment status
    @JsonKey(name: 'enrichment_status') @Default(EnrichmentStatus.pending) EnrichmentStatus enrichmentStatus,
    @JsonKey(name: 'validation_errors') List<String>? validationErrors,
  }) = _EnrichedStockItem;

  const EnrichedStockItem._();

  factory EnrichedStockItem.fromJson(Map<String, dynamic> json) =>
      _$EnrichedStockItemFromJson(json);

  /// Create from deduplicated item
  factory EnrichedStockItem.fromDeduplicated(DeduplicatedItem item) {
    return EnrichedStockItem(
      ocrItemId: item.sourceItemIds.isNotEmpty ? item.sourceItemIds.first : '',
      brandText: item.brandText,
      sizeText: item.sizeText,
      availableStock: item.totalStock,
      categoryId: item.categoryId,
      subcategoryId: item.subcategoryId,
      saasBrandId: item.matchedBrandId,
      brandVariantId: item.matchedVariantId,
      isDuplicate: item.isDuplicate,
    );
  }

  /// Check if item is ready for submission
  bool get isReadyForSubmission {
    return enrichmentStatus == EnrichmentStatus.complete &&
        categoryId != null &&
        sellingPrice != null &&
        costPrice != null &&
        mrp != null;
  }

  /// Validate enriched data
  List<String> validate() {
    final errors = <String>[];

    if (categoryId == null || categoryId!.isEmpty) {
      errors.add('Category is required');
    }

    if (sellingPrice == null || sellingPrice! <= 0) {
      errors.add('Selling price must be greater than 0');
    }

    if (costPrice == null || costPrice! <= 0) {
      errors.add('Cost price must be greater than 0');
    }

    if (mrp == null || mrp! <= 0) {
      errors.add('MRP must be greater than 0');
    }

    if (sellingPrice != null &&
        costPrice != null &&
        sellingPrice! < costPrice!) {
      errors.add('Selling price cannot be less than cost price');
    }

    if (mrp != null && sellingPrice != null && sellingPrice! > mrp!) {
      errors.add('Selling price cannot be greater than MRP');
    }

    if (availableStock < 0) {
      errors.add('Stock cannot be negative');
    }

    return errors;
  }
}

/// Enrichment status for stock items
enum EnrichmentStatus {
  @JsonValue('pending')
  pending,
  @JsonValue('in_progress')
  inProgress,
  @JsonValue('complete')
  complete,
  @JsonValue('skipped')
  skipped,
}

/// Request to initialize stock from OCR batch
@freezed
class InitializeStockFromOCRRequest with _$InitializeStockFromOCRRequest {
  const factory InitializeStockFromOCRRequest({
    @JsonKey(name: 'session_ids') required List<String> sessionIds,
    @JsonKey(name: 'shop_id') required String shopId,
    required String reason,
    required List<EnrichedStockItemRequest> items,
  }) = _InitializeStockFromOCRRequest;

  factory InitializeStockFromOCRRequest.fromJson(Map<String, dynamic> json) =>
      _$InitializeStockFromOCRRequestFromJson(json);
}

/// Enriched stock item for API request
@freezed
class EnrichedStockItemRequest with _$EnrichedStockItemRequest {
  const factory EnrichedStockItemRequest({
    @JsonKey(name: 'ocr_item_id') required String ocrItemId,
    @JsonKey(name: 'brand_text') required String brandText,
    @JsonKey(name: 'size_text') required String sizeText,
    @JsonKey(name: 'category_id') required String categoryId,
    @JsonKey(name: 'subcategory_id') String? subcategoryId,
    @JsonKey(name: 'selling_price') required double sellingPrice,
    @JsonKey(name: 'cost_price') required double costPrice,
    required double mrp,
    @JsonKey(name: 'available_stock') required int availableStock,
    @JsonKey(name: 'reorder_level') int? reorderLevel,
    @JsonKey(name: 'is_duplicate') @Default(false) bool isDuplicate,
  }) = _EnrichedStockItemRequest;

  factory EnrichedStockItemRequest.fromJson(Map<String, dynamic> json) =>
      _$EnrichedStockItemRequestFromJson(json);

  /// Create from enriched item
  factory EnrichedStockItemRequest.fromEnriched(EnrichedStockItem item) {
    return EnrichedStockItemRequest(
      ocrItemId: item.ocrItemId,
      brandText: item.brandText,
      sizeText: item.sizeText,
      categoryId: item.categoryId!,
      subcategoryId: item.subcategoryId,
      sellingPrice: item.sellingPrice!,
      costPrice: item.costPrice!,
      mrp: item.mrp!,
      availableStock: item.availableStock,
      reorderLevel: item.reorderLevel,
      isDuplicate: item.isDuplicate,
    );
  }
}

/// Response after stock initialization
@freezed
class InitializeStockResponse with _$InitializeStockResponse {
  const factory InitializeStockResponse({
    required bool success,
    required String message,
    @JsonKey(name: 'items_processed') required int itemsProcessed,
    @JsonKey(name: 'items_created') required int itemsCreated,
    @JsonKey(name: 'items_failed') required int itemsFailed,
    @Default([]) List<StockInitializationResult> results,
    Map<String, dynamic>? summary,
  }) = _InitializeStockResponse;

  factory InitializeStockResponse.fromJson(Map<String, dynamic> json) =>
      _$InitializeStockResponseFromJson(json);
}

/// Individual stock initialization result
@freezed
class StockInitializationResult with _$StockInitializationResult {
  const factory StockInitializationResult({
    @JsonKey(name: 'ocr_item_id') required String ocrItemId,
    required bool success,
    @JsonKey(name: 'product_id') String? productId,
    String? error,
    Map<String, dynamic>? details,
  }) = _StockInitializationResult;

  factory StockInitializationResult.fromJson(Map<String, dynamic> json) =>
      _$StockInitializationResultFromJson(json);
}

/// Batch OCR progress tracking
@freezed
class BatchOCRProgress with _$BatchOCRProgress {
  const factory BatchOCRProgress({
    @JsonKey(name: 'batch_id') required String batchId,
    @JsonKey(name: 'total_images') required int totalImages,
    @JsonKey(name: 'completed_images') required int completedImages,
    @JsonKey(name: 'failed_images') required int failedImages,
    @JsonKey(name: 'progress_percentage') required double progressPercentage,
    required BatchStatus status,
    @JsonKey(name: 'current_image_name') String? currentImageName,
    @JsonKey(name: 'estimated_time_remaining_seconds') int? estimatedTimeRemainingSeconds,
    // Phase 1.2: Add stage tracking from WebSocket
    String? stage, // Current OCR stage: "text_extraction", "brand_matching", etc.
    @JsonKey(name: 'items_extracted') int? itemsExtracted, // Phase 2.2: Items count
    @JsonKey(name: 'current_item') String? currentItem, // Phase 2.1: Current item being processed
  }) = _BatchOCRProgress;

  const BatchOCRProgress._();

  factory BatchOCRProgress.fromJson(Map<String, dynamic> json) =>
      _$BatchOCRProgressFromJson(json);

  /// Create from batch session
  factory BatchOCRProgress.fromSession(BatchOCRSession session) {
    final progress = session.totalImages > 0
        ? (session.completedImages / session.totalImages) * 100
        : 0.0;

    return BatchOCRProgress(
      batchId: session.id,
      totalImages: session.totalImages,
      completedImages: session.completedImages,
      failedImages: session.failedImages,
      progressPercentage: progress,
      status: session.status,
    );
  }

  /// Check if processing is complete
  bool get isComplete =>
      status == BatchStatus.completed || status == BatchStatus.partial;

  /// Check if processing failed
  bool get isFailed => status == BatchStatus.failed;

  /// Check if processing is in progress
  bool get isProcessing => status == BatchStatus.processing;
}

/// Enrichment workflow state
@freezed
class EnrichmentWorkflowState with _$EnrichmentWorkflowState {
  const factory EnrichmentWorkflowState({
    @JsonKey(name: 'batch_id') required String batchId,
    @JsonKey(name: 'session_ids') required List<String> sessionIds,
    @JsonKey(name: 'deduplicated_items') required List<DeduplicatedItem> deduplicatedItems,
    @JsonKey(name: 'enriched_items') required List<EnrichedStockItem> enrichedItems,
    @JsonKey(name: 'current_item_index') required int currentItemIndex,
    @JsonKey(name: 'current_step') required EnrichmentStep currentStep,
    @JsonKey(name: 'is_loading') @Default(false) bool isLoading,
    String? error,
  }) = _EnrichmentWorkflowState;

  const EnrichmentWorkflowState._();

  factory EnrichmentWorkflowState.fromJson(Map<String, dynamic> json) =>
      _$EnrichmentWorkflowStateFromJson(json);

  /// Create initial state
  factory EnrichmentWorkflowState.initial({
    required String batchId,
    required List<String> sessionIds,
    required List<DeduplicatedItem> deduplicatedItems,
  }) {
    return EnrichmentWorkflowState(
      batchId: batchId,
      sessionIds: sessionIds,
      deduplicatedItems: deduplicatedItems,
      enrichedItems: deduplicatedItems
          .map((item) => EnrichedStockItem.fromDeduplicated(item))
          .toList(),
      currentItemIndex: 0,
      currentStep: EnrichmentStep.enrichment,
    );
  }

  /// Get current item being enriched
  EnrichedStockItem? get currentItem {
    if (currentItemIndex >= 0 && currentItemIndex < enrichedItems.length) {
      return enrichedItems[currentItemIndex];
    }
    return null;
  }

  /// Calculate completion percentage
  double get completionPercentage {
    if (enrichedItems.isEmpty) return 0.0;
    final completed = enrichedItems
        .where((item) =>
            item.enrichmentStatus == EnrichmentStatus.complete ||
            item.enrichmentStatus == EnrichmentStatus.skipped)
        .length;
    return (completed / enrichedItems.length) * 100;
  }

  /// Check if all items are ready for submission
  bool get isReadyForSubmission {
    return enrichedItems.isNotEmpty &&
        enrichedItems.every((item) =>
            item.enrichmentStatus == EnrichmentStatus.complete ||
            item.enrichmentStatus == EnrichmentStatus.skipped);
  }

  /// Get items ready for submission (exclude skipped)
  List<EnrichedStockItem> get itemsForSubmission {
    return enrichedItems
        .where((item) => item.enrichmentStatus == EnrichmentStatus.complete)
        .toList();
  }
}

/// Enrichment workflow steps
enum EnrichmentStep {
  @JsonValue('enrichment')
  enrichment,
  @JsonValue('review')
  review,
  @JsonValue('submission')
  submission,
  @JsonValue('complete')
  complete,
}
