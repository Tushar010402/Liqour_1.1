import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../../../core/models/api_response.dart';
import '../../../core/services/dio_api_service.dart';
import '../../../core/utils/logger.dart';
import '../models/batch_ocr_models.dart';

/// Service for batch OCR operations (multi-image processing)
/// Handles communication with backend batch OCR endpoints
class BatchOCRService {
  final DioApiService _apiService;

  BatchOCRService({required DioApiService apiService}) : _apiService = apiService;

  // ==========================================
  // BATCH OCR SESSION OPERATIONS
  // ==========================================

  /// Create a batch OCR session from multiple images
  ///
  /// This initiates parallel processing of up to 10 images.
  /// Backend processes max 3 images concurrently using semaphore.
  ///
  /// Returns the batch session ID for tracking progress.
  Future<ApiResponse<BatchOCRSession>> createBatchSession({
    required List<ImageData> images,
    required String shopId,
    String sessionType = 'stock_initialization',
    Map<String, dynamic>? metadata,
  }) async {
    try {
      if (kDebugMode) {
        Logger.info('[BatchOCR] Creating session: ${images.length} images for shop $shopId');
      }

      // Validate input
      if (images.isEmpty) {
        return ApiResponse<BatchOCRSession>(
          success: false,
          message: 'At least one image is required',
        );
      }

      if (images.length > 10) {
        return ApiResponse<BatchOCRSession>(
          success: false,
          message: 'Maximum 10 images allowed per batch',
        );
      }

      // Prepare FormData for multipart upload
      final formData = FormData();

      // Add shop_id
      formData.fields.add(MapEntry('shop_id', shopId));

      // Add session_type
      formData.fields.add(MapEntry('session_type', sessionType));

      // Add metadata if provided
      if (metadata != null) {
        formData.fields.add(MapEntry('metadata', jsonEncode(metadata)));
      }

      // Add images as multipart files
      for (int i = 0; i < images.length; i++) {
        final image = images[i];
        final bytes = base64Decode(image.imageData);

        // Create a multipart file from the bytes
        final multipartFile = MultipartFile.fromBytes(
          bytes,
          filename: image.fileName ?? 'image_$i.${image.imageType}',
        );

        formData.files.add(MapEntry('images', multipartFile));
      }

      if (kDebugMode) {
        Logger.debug('[BatchOCR] Sending ${images.length} images to /api/sales/ocr/batch/sessions');
      }

      // Best Practice: Increase timeout for large multipart uploads
      // Images can be 1-5MB each, need sufficient time for upload + OCR processing
      final response = await _apiService.post<BatchOCRSession>(
        '/api/sales/ocr/batch/sessions',
        body: formData,
        options: Options(
          sendTimeout: const Duration(minutes: 2), // Allow 2 min for upload (large images)
          receiveTimeout: const Duration(minutes: 3), // Allow 3 min for OCR processing
        ),
        fromJson: (json) => BatchOCRSession.fromJson(json),
      );

      if (response.success && response.data != null) {
        if (kDebugMode) {
          Logger.info('[BatchOCR] Session created: ${response.data?.id}');
        }
      } else if (!response.success) {
        Logger.error('[BatchOCR] Session creation failed: ${response.message}');
      }

      return response;
    } catch (e) {
      Logger.error('[BatchOCR] Critical error: $e');

      return ApiResponse<BatchOCRSession>(
        success: false,
        message: 'Failed to create batch session: ${e.toString()}',
      );
    }
  }

  /// Get batch session status with real-time progress
  ///
  /// Returns current processing status, completed/failed counts,
  /// and total items extracted across all images.
  ///
  /// Poll this endpoint to track batch processing progress.
  Future<ApiResponse<BatchOCRSession>> getBatchSessionStatus(String batchId) async {
    try {
      if (kDebugMode) {
        Logger.debug('[BatchOCR] Getting session status: $batchId');
      }

      final response = await _apiService.get<BatchOCRSession>(
        '/api/sales/ocr/batch/sessions/$batchId',
        fromJson: (json) => BatchOCRSession.fromJson(json),
      );

      if (response.success && response.data != null) {
        final session = response.data!;
        if (kDebugMode) {
          Logger.info('[BatchOCR] Status: ${session.completedImages}/${session.totalImages} images, ${session.totalItemsExtracted} items extracted');
        }
      }

      return response;
    } catch (e) {
      if (kDebugMode) {
        Logger.error('[BatchOCR] Error getting batch status: $e');
      }
      return ApiResponse<BatchOCRSession>(
        success: false,
        message: 'Failed to get batch status: ${e.toString()}',
      );
    }
  }

  /// Poll batch session until completion or timeout
  ///
  /// Automatically polls every [pollIntervalSeconds] until:
  /// - Processing completes successfully (status: completed/partial)
  /// - Processing fails (status: failed)
  /// - Timeout is reached (default: 5 minutes)
  ///
  /// Returns the final session state or throws timeout error.
  Future<ApiResponse<BatchOCRSession>> waitForBatchCompletion({
    required String batchId,
    int pollIntervalSeconds = 2,
    int timeoutSeconds = 300, // 5 minutes default
  }) async {
    try {
      if (kDebugMode) {
        Logger.debug('[BatchOCR] Waiting for batch completion: $batchId');
      }

      final startTime = DateTime.now();
      final timeoutDuration = Duration(seconds: timeoutSeconds);

      while (true) {
        // Check timeout
        if (DateTime.now().difference(startTime) > timeoutDuration) {
          return ApiResponse<BatchOCRSession>(
            success: false,
            message: 'Batch processing timeout after $timeoutSeconds seconds',
          );
        }

        // Get current status
        final response = await getBatchSessionStatus(batchId);
        if (!response.success || response.data == null) {
          return response;
        }

        final session = response.data!;

        // Check if completed
        if (session.status == BatchStatus.completed ||
            session.status == BatchStatus.partial) {
          if (kDebugMode) {
            Logger.info('[BatchOCR] Batch processing completed: ${session.status.name}');
          }
          return response;
        }

        // Check if failed
        if (session.status == BatchStatus.failed) {
          if (kDebugMode) {
            Logger.error('[BatchOCR] Batch processing failed');
          }
          return ApiResponse<BatchOCRSession>(
            success: false,
            message: 'Batch processing failed',
            data: session,
          );
        }

        // Wait before next poll
        await Future.delayed(Duration(seconds: pollIntervalSeconds));
      }
    } catch (e) {
      if (kDebugMode) {
        Logger.error('[BatchOCR] Error waiting for completion: $e');
      }
      return ApiResponse<BatchOCRSession>(
        success: false,
        message: 'Error waiting for completion: ${e.toString()}',
      );
    }
  }

  // ==========================================
  // DEDUPLICATION OPERATIONS
  // ==========================================

  /// Get deduplicated items from multiple OCR sessions
  ///
  /// Backend merges items with same brand+size (case-insensitive),
  /// sums total stock, and calculates average confidence scores.
  ///
  /// Example: If 3 sessions each have 2x "Royal Stag 750ml",
  /// this returns 1 item with total_stock=6.
  ///
  /// Returns a Map with 'items' and 'receipt_type' keys
  Future<ApiResponse<Map<String, dynamic>>> getDeduplicatedItems({
    required List<String> sessionIds,
  }) async {
    try {
      if (kDebugMode) {
        Logger.debug('[BatchOCR] Deduplicating ${sessionIds.length} sessions');
      }

      // Validate input
      if (sessionIds.isEmpty) {
        return ApiResponse<Map<String, dynamic>>(
          success: false,
          message: 'At least one session ID is required',
        );
      }

      // Prepare request
      final request = DeduplicateRequest(sessionIds: sessionIds);

      // Call backend
      final response = await _apiService.post<Map<String, dynamic>>(
        '/api/sales/ocr/batch/deduplicate',
        body: request.toJson(),
        fromJson: (json) {
          if (kDebugMode) {
            Logger.debug('[BatchOCR] Parsing deduplicate response (${json.runtimeType})');
          }

          try {
            String? receiptType;
            List<DeduplicatedItem> items = [];

            if (kDebugMode) {
              Logger.debug('[BatchOCR] Deduplicate response keys: ${json is Map ? json.keys : json.runtimeType}');
            }

            // Handle new format (v1.0.39+): { "receipt_type": "...", "items": [...] }
            if (json is Map<String, dynamic>) {
              if (kDebugMode) {
                Logger.debug('[BatchOCR] Response: receipt_type=${json['receipt_type']}, total_items=${json['total_items']}, duplicates_removed=${json['duplicates_removed']}');
              }

              receiptType = json['receipt_type'] as String?;

              final itemsData = json['items'];
              if (itemsData is List) {
                if (kDebugMode) {
                  Logger.debug('[BatchOCR] Extracted ${itemsData.length} items');
                }

                items = itemsData
                    .map((item) {
                      try {
                        // PRODUCTION-READY: Sanitize and normalize backend data
                        final itemMap = _sanitizeItemJson(item as Map<String, dynamic>);

                        // Clean up common OCR artifacts in brand names
                        if (itemMap['brand_text'] != null) {
                          String originalText = itemMap['brand_text'].toString();
                          String cleanedText = originalText.trim();

                          // Remove leading pipes, slashes, or backslashes
                          cleanedText = cleanedText.replaceAll(RegExp(r'^[|/\\]+\s*'), '').trim();

                          if (cleanedText != originalText && kDebugMode) {
                            Logger.debug('[BatchOCR] Cleaned: "$originalText" -> "$cleanedText"');
                          }

                          itemMap['brand_text'] = cleanedText;
                        }

                        return DeduplicatedItem.fromJson(itemMap);
                      } catch (e, stack) {
                        if (kDebugMode) {
                          Logger.warning('[BatchOCR] Error parsing item, using fallback: $e');
                          Logger.warning('  Stack: ${stack.toString().split('\n').take(3).join('\n')}');
                        }

                        // FALLBACK: Create a minimal valid item from raw data
                        return _createFallbackItem(item as Map<String, dynamic>);
                      }
                    })
                    .toList();

                if (kDebugMode) {
                  Logger.info('[BatchOCR] Parsed ${items.length} deduplicated items (new format)');
                }
              }
            }
            // Handle old format (backward compatibility): [...]
            else if (json is List) {
              if (kDebugMode) {
                Logger.debug('[BatchOCR] Legacy array format, ${json.length} items');
              }

              items = json
                  .map((item) {
                    try {
                      // PRODUCTION-READY: Sanitize and normalize backend data
                      final itemMap = _sanitizeItemJson(item as Map<String, dynamic>);

                      // Clean up common OCR artifacts in brand names
                      if (itemMap['brand_text'] != null) {
                        String originalText = itemMap['brand_text'].toString();
                        String cleanedText = originalText.trim();
                        // Remove leading pipes, slashes, or backslashes
                        cleanedText = cleanedText.replaceAll(RegExp(r'^[|/\\]+\s*'), '').trim();
                        if (cleanedText != originalText && kDebugMode) {
                          Logger.debug('[BatchOCR] Cleaned: "$originalText" -> "$cleanedText"');
                        }
                        itemMap['brand_text'] = cleanedText;
                      }

                      return DeduplicatedItem.fromJson(itemMap);
                    } catch (e, stack) {
                      if (kDebugMode) {
                        Logger.warning('[BatchOCR] Error parsing legacy item, using fallback: $e');
                        Logger.warning('  Stack: ${stack.toString().split('\n').take(3).join('\n')}');
                      }

                      // FALLBACK: Create a minimal valid item from raw data
                      return _createFallbackItem(item as Map<String, dynamic>);
                    }
                  })
                  .toList();

              if (kDebugMode) {
                Logger.info('[BatchOCR] Parsed ${items.length} deduplicated items (legacy format)');
              }
            } else {
              if (kDebugMode) {
                Logger.warning('[BatchOCR] Response format not recognized (expected Map or List)');
              }
            }

            // Sort items by row_number (serial number)
            if (items.isNotEmpty) {
              items.sort((a, b) {
                // Handle null row numbers
                if (a.rowNumber == null) return 1;
                if (b.rowNumber == null) return -1;
                return a.rowNumber!.compareTo(b.rowNumber!);
              });

              if (kDebugMode) {
                Logger.debug('[BatchOCR] Items sorted by row_number');
              }
            }

            // Extract raw texts, total_items, and duplicates_removed from response
            Map<String, String>? rawTexts;
            int? totalItems;
            int? duplicatesRemoved;

            if (json is Map<String, dynamic>) {
              // Parse raw_texts map with proper type conversion
              if (json['raw_texts'] != null && json['raw_texts'] is Map) {
                final rawTextsMap = json['raw_texts'] as Map;
                rawTexts = {};
                rawTextsMap.forEach((key, value) {
                  if (value != null) {
                    rawTexts![key.toString()] = value.toString();
                  }
                });

                if (kDebugMode) {
                  Logger.debug('[BatchOCR] Raw texts parsed: ${rawTexts.length} sessions');
                }
              }

              // Parse statistics
              totalItems = (json['total_items'] as num?)?.toInt();
              duplicatesRemoved = (json['duplicates_removed'] as num?)?.toInt();

              if (kDebugMode) {
                Logger.debug('[BatchOCR] Stats: totalItems=$totalItems, duplicatesRemoved=$duplicatesRemoved, rawTexts=${rawTexts?.length ?? 0}');
              }
            }

            // Return map with all fields including raw texts
            return {
              'receipt_type': receiptType,
              'items': items,
              'raw_texts': rawTexts,
              'total_items': totalItems,
              'duplicates_removed': duplicatesRemoved,
            };
          } catch (e, stack) {
            if (kDebugMode) {
              Logger.error('[BatchOCR] Error parsing deduplicated items: $e');
              Logger.error('[BatchOCR] Stack trace: $stack');
            }
            return {
              'receipt_type': null,
              'items': <DeduplicatedItem>[],
              'raw_texts': null,
              'total_items': null,
              'duplicates_removed': null,
            };
          }
        },
      );

      if (kDebugMode && response.success && response.data != null) {
        final items = response.data!['items'] as List<DeduplicatedItem>;
        Logger.info('[BatchOCR] Extraction complete: ${items.length} items, ${items.where((i) => i.matchedBrandId != null).length} matched');
      }

      return response;
    } catch (e) {
      if (kDebugMode) {
        Logger.error('[BatchOCR] Error deduplicating items: $e');
      }
      return ApiResponse<Map<String, dynamic>>(
        success: false,
        message: 'Failed to deduplicate items: ${e.toString()}',
      );
    }
  }

  // ==========================================
  // STOCK INITIALIZATION OPERATIONS
  // ==========================================

  /// Initialize stock from enriched OCR data
  ///
  /// Creates products and initial stock records for user-enriched items.
  /// Items must include category, pricing, and stock information.
  ///
  /// Backend performs transactional insert - all succeed or all fail.
  Future<ApiResponse<InitializeStockResponse>> initializeStockFromOCR({
    required List<String> sessionIds,
    required String shopId,
    required String reason,
    required List<EnrichedStockItem> items,
  }) async {
    try {
      if (kDebugMode) {
        Logger.debug('[BatchOCR] Initializing stock from ${items.length} OCR items');
      }

      // Validate input
      if (items.isEmpty) {
        return ApiResponse<InitializeStockResponse>(
          success: false,
          message: 'At least one item is required',
        );
      }

      // Validate each item
      for (final item in items) {
        final errors = item.validate();
        if (errors.isNotEmpty) {
          return ApiResponse<InitializeStockResponse>(
            success: false,
            message: 'Validation failed: ${errors.join(', ')}',
          );
        }
      }

      // Convert to request items
      final requestItems = items
          .where((item) => item.enrichmentStatus == EnrichmentStatus.complete)
          .map((item) => EnrichedStockItemRequest.fromEnriched(item))
          .toList();

      if (requestItems.isEmpty) {
        return ApiResponse<InitializeStockResponse>(
          success: false,
          message: 'No items ready for submission',
        );
      }

      // Prepare request
      final request = InitializeStockFromOCRRequest(
        sessionIds: sessionIds,
        shopId: shopId,
        reason: reason,
        items: requestItems,
      );

      // Call backend
      final response = await _apiService.post<InitializeStockResponse>(
        '/api/sales/ocr/stock/initialize',
        body: request.toJson(),
        fromJson: (json) => InitializeStockResponse.fromJson(json),
      );

      if (kDebugMode && response.success && response.data != null) {
        final data = response.data!;
        Logger.info('[BatchOCR] Stock initialized: ${data.itemsCreated}/${data.itemsProcessed} items created');
      }

      return response;
    } catch (e) {
      if (kDebugMode) {
        Logger.error('[BatchOCR] Error initializing stock: $e');
      }
      return ApiResponse<InitializeStockResponse>(
        success: false,
        message: 'Failed to initialize stock: ${e.toString()}',
      );
    }
  }

  // ==========================================
  // HELPER METHODS
  // ==========================================

  /// Convert image file to base64 ImageData
  ///
  /// Reads image bytes and encodes to base64 for API transmission.
  /// Automatically detects image type from file extension.
  static Future<ImageData?> imageFileToBase64(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        if (kDebugMode) Logger.error('[BatchOCR] Image file not found: $filePath');
        return null;
      }

      final bytes = await file.readAsBytes();
      final base64String = base64Encode(bytes);
      final extension = filePath.split('.').last.toLowerCase();

      // Map file extensions to image types
      String imageType;
      switch (extension) {
        case 'jpg':
        case 'jpeg':
          imageType = 'jpeg';
          break;
        case 'png':
          imageType = 'png';
          break;
        default:
          imageType = extension;
      }

      return ImageData(
        imageData: base64String,
        imageType: imageType,
        fileName: filePath.split('/').last,
        fileSize: bytes.length,
      );
    } catch (e) {
      if (kDebugMode) Logger.error('[BatchOCR] Error converting image to base64: $e');
      return null;
    }
  }

  /// Convert multiple image files to ImageData list
  static Future<List<ImageData>> imageFilesToBase64(List<String> filePaths) async {
    final images = <ImageData>[];

    for (final path in filePaths) {
      final imageData = await imageFileToBase64(path);
      if (imageData != null) {
        images.add(imageData);
      }
    }

    return images;
  }

  // ==========================================
  // PRODUCTION-READY: ROBUST JSON PARSING
  // ==========================================

  /// Sanitize item JSON to handle backend field variations and null values
  ///
  /// BEST PRACTICE: Normalize backend data before parsing to handle:
  /// - Null values where numbers expected
  /// - Missing fields
  /// - Field name variations (e.g., 'total_stock' vs 'quantity')
  static Map<String, dynamic> _sanitizeItemJson(Map<String, dynamic> json) {
    final sanitized = Map<String, dynamic>.from(json);

    // Handle numeric fields that might be null
    sanitized['quantity'] = _safeInt(json['quantity'] ?? json['total_stock'], defaultValue: 0);
    sanitized['selling_price'] = _safeDouble(json['selling_price'] ?? json['price'], defaultValue: null);
    sanitized['match_confidence'] = _safeDouble(json['match_confidence'] ?? json['confidence'], defaultValue: 0.0);
    sanitized['row_number'] = _safeInt(json['row_number'] ?? json['serial_number'], defaultValue: null);

    // Handle string fields with defaults
    sanitized['brand_text'] = json['brand_text']?.toString() ?? '';
    sanitized['size_text'] = json['size_text']?.toString() ?? '';

    // Handle list fields
    sanitized['source_sessions'] = _safeList(json['source_sessions']);
    sanitized['source_items'] = _safeList(json['source_items']);

    // Handle boolean fields
    sanitized['is_duplicate'] = json['is_duplicate'] == true;
    sanitized['is_reviewed'] = json['is_reviewed'] == true;
    sanitized['is_selected'] = json['is_selected'] ?? true; // Default to selected

    // Preserve optional fields as-is (nullable)
    // These are handled by the model's nullable fields
    sanitized['id'] = json['id'];
    sanitized['session_id'] = json['session_id'];
    sanitized['batch_id'] = json['batch_id'];
    sanitized['category_id'] = json['category_id'];
    sanitized['subcategory_id'] = json['subcategory_id'];
    sanitized['matched_brand_id'] = json['matched_brand_id'];
    sanitized['matched_variant_id'] = json['matched_variant_id'];
    sanitized['normalized_brand_name'] = json['normalized_brand_name'];
    sanitized['match_strategy'] = json['match_strategy'];

    return sanitized;
  }

  /// Safe integer conversion with fallback
  static int? _safeInt(dynamic value, {int? defaultValue}) {
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  /// Safe double conversion with fallback
  static double? _safeDouble(dynamic value, {double? defaultValue}) {
    if (value == null) return defaultValue;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  /// Safe list conversion
  static List<String> _safeList(dynamic value) {
    if (value == null) return [];
    if (value is List) {
      return value.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
    }
    return [];
  }

  /// Create a fallback DeduplicatedItem when parsing fails
  ///
  /// FALLBACK STRATEGY: Extract minimum required fields from raw JSON
  /// This ensures we never lose user data even if parsing fails
  static DeduplicatedItem _createFallbackItem(Map<String, dynamic> json) {
    return DeduplicatedItem(
      brandText: json['brand_text']?.toString() ?? 'Unknown Brand',
      sizeText: json['size_text']?.toString() ?? '',
      totalStock: _safeInt(json['quantity'] ?? json['total_stock'], defaultValue: 0) ?? 0,
      matchConfidence: _safeDouble(json['match_confidence'], defaultValue: 0.0) ?? 0.0,
      sellingPrice: _safeDouble(json['selling_price']),
      rowNumber: _safeInt(json['row_number']),
      // All other fields will use model defaults
    );
  }
}
