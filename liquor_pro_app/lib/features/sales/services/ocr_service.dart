import 'dart:convert';
import 'dart:io';
import 'package:image/image.dart' as img;
import '../../../core/services/dio_api_service.dart';
import '../../../core/models/api_response.dart';
import '../../../core/utils/date_time_helper.dart';
import '../models/ocr_models.dart';
import '../../../core/utils/app_logger.dart';

class OCRService {
  final DioApiService _apiService;

  // Constructor with named parameter to match provider expectations
  OCRService({required DioApiService apiService}) : _apiService = apiService;

  /// Create a new OCR session by uploading image data (for provider)
  /// Uses single-image endpoint for reliability
  Future<OCRSession> createOCRSession({
    required String imageData,
    required String imageType,
    required String sessionType,
    required String shopId,
  }) async {
    try {
      AppLogger.info('Creating OCR session');
      AppLogger.info('📤 OCR Request - imageData length: ${imageData.length}, type: $imageType, shopId: $shopId');

      // Use single-image endpoint (more reliable than batch)
      final requestData = {
        'image_data': imageData,
        'image_type': imageType,
        'session_type': sessionType,
        'shop_id': shopId,
      };

      AppLogger.info('📤 OCR Request body keys: ${requestData.keys.toList()}');

      final response = await _apiService.post<Map<String, dynamic>>(
        '/api/sales/ocr/sessions',
        body: requestData,
        fromJson: (data) => data as Map<String, dynamic>,
      );

      if (response.success && response.data != null) {
        final data = response.data!;
        AppLogger.info('📥 OCR Response data keys: ${data.keys.toList()}');

        // Backend returns session - extract session_id or id
        final sessionId = data['session_id'] ?? data['id'];
        if (sessionId == null) {
          throw Exception('No session ID in response');
        }

        // Create a minimal OCRSession for the flow to continue
        // The actual session details will be fetched when polling
        final now = DateTime.now();
        return OCRSession(
          id: sessionId.toString(),
          tenantId: data['tenant_id']?.toString() ?? '',
          userId: data['user_id']?.toString() ?? '',
          shopId: shopId,
          imageUrl: data['image_url']?.toString() ?? '',
          imageSize: data['image_size'] as int? ?? 0,
          imageType: imageType,
          status: data['status']?.toString() ?? 'pending',
          expiresAt: now.add(const Duration(hours: 1)),
          createdAt: now,
          updatedAt: now,
        );
      } else {
        throw Exception(response.message ?? 'Failed to create OCR session');
      }
    } catch (e, stackTrace) {
      AppLogger.error('Error creating OCR session', e, stackTrace);
      rethrow;
    }
  }

  /// Create a new OCR session by uploading an image file (for invoice screen)
  /// Images are automatically compressed to reduce upload size while preserving OCR quality
  Future<ApiResponse<OCRSession>> createSession({
    required String imagePath,
    required String shopId,
    String sessionType = 'quick_sale',
  }) async {
    try {
      AppLogger.info('Creating OCR session for image: $imagePath');

      // Read image file
      final file = File(imagePath);
      if (!await file.exists()) {
        return ApiResponse(
          success: false,
          message: 'Image file not found',
          data: null,
        );
      }

      final bytes = await file.readAsBytes();
      final originalSizeKB = bytes.length ~/ 1024;
      AppLogger.info('Original image size: ${originalSizeKB}KB');

      // Compress image if too large (> 500KB)
      // OCR works well with 1024px width and 80% JPEG quality
      List<int> compressedBytes = bytes;
      String imageType = 'jpeg';

      if (originalSizeKB > 500) {
        AppLogger.info('Compressing image for OCR...');

        try {
          // Decode image
          final image = img.decodeImage(bytes);
          if (image != null) {
            // Resize if width > 1200px (good balance for OCR)
            img.Image resized = image;
            if (image.width > 1200) {
              final scale = 1200 / image.width;
              resized = img.copyResize(
                image,
                width: 1200,
                height: (image.height * scale).round(),
                interpolation: img.Interpolation.linear,
              );
              AppLogger.info('Resized: ${image.width}x${image.height} -> ${resized.width}x${resized.height}');
            }

            // Encode as JPEG with 80% quality
            compressedBytes = img.encodeJpg(resized, quality: 80);
            final compressedSizeKB = compressedBytes.length ~/ 1024;
            AppLogger.info('Compressed: ${originalSizeKB}KB -> ${compressedSizeKB}KB (${((1 - compressedSizeKB / originalSizeKB) * 100).toStringAsFixed(0)}% reduction)');
          }
        } catch (e) {
          AppLogger.warning('Image compression failed, using original: $e');
          compressedBytes = bytes;
          // Determine original image type
          final extension = imagePath.split('.').last.toLowerCase();
          imageType = extension == 'jpg' ? 'jpeg' : extension;
        }
      } else {
        // Use original if already small
        final extension = imagePath.split('.').last.toLowerCase();
        imageType = extension == 'jpg' ? 'jpeg' : extension;
      }

      final base64Image = base64Encode(compressedBytes);
      AppLogger.info('Base64 size: ${(base64Image.length / 1024).toStringAsFixed(0)}KB');

      final session = await createOCRSession(
        imageData: base64Image,
        imageType: imageType,
        sessionType: sessionType,
        shopId: shopId,
      );

      return ApiResponse(
        success: true,
        message: 'OCR session created successfully',
        data: session,
      );
    } catch (e, stackTrace) {
      AppLogger.error('Error creating OCR session', e, stackTrace);
      return ApiResponse(
        success: false,
        message: 'Failed to create OCR session: ${e.toString()}',
        data: null,
      );
    }
  }

  /// Get OCR session with extracted items (for provider)
  Future<OCRSessionResponse> getOCRSession(String sessionId) async {
    try {
      AppLogger.info('Fetching OCR session: $sessionId');

      final response = await _apiService.get<Map<String, dynamic>>(
        '/api/sales/ocr/sessions/$sessionId',
        fromJson: (data) => data as Map<String, dynamic>,
      );

      if (response.success && response.data != null) {
        final responseData = response.data!;
        AppLogger.info('📥 getOCRSession response keys: ${responseData.keys.toList()}');

        // Backend returns: { "success": true, "data": {...}, "items": [...], "quality_metrics": {...} }
        // OR legacy format with session data at root level
        Map<String, dynamic> sessionData;
        if (responseData['data'] != null && responseData['data'] is Map<String, dynamic>) {
          // New format: session metadata in 'data' key
          sessionData = responseData['data'] as Map<String, dynamic>;
          AppLogger.info('📥 Using new format: data key found');
        } else if (responseData['session'] != null) {
          sessionData = responseData['session'] as Map<String, dynamic>;
        } else if (responseData['id'] != null || responseData['session_id'] != null) {
          // Batch API returns data directly at root level
          sessionData = responseData;
        } else {
          throw Exception('Invalid response: missing session data. Keys: ${responseData.keys.toList()}');
        }

        // Build OCRSession from batch response data
        final now = DateTime.now();
        final status = sessionData['status']?.toString() ?? 'pending';

        final session = OCRSession(
          id: (sessionData['id'] ?? sessionData['session_id'] ?? sessionId).toString(),
          tenantId: sessionData['tenant_id']?.toString() ?? '',
          userId: sessionData['user_id']?.toString() ?? '',
          shopId: sessionData['shop_id']?.toString() ?? '',
          imageUrl: sessionData['image_url']?.toString() ?? '',
          imageSize: sessionData['image_size'] as int? ?? 0,
          imageType: sessionData['image_type']?.toString() ?? 'jpeg',
          status: status,
          rawText: sessionData['raw_text']?.toString(),
          // Use DateTimeHelper to properly handle timezone conversion
          expiresAt: sessionData['expires_at'] != null
              ? DateTimeHelper.parseIsoToLocal(sessionData['expires_at'].toString()) ?? now.add(const Duration(hours: 1))
              : now.add(const Duration(hours: 1)),
          createdAt: sessionData['created_at'] != null
              ? DateTimeHelper.parseIsoToLocal(sessionData['created_at'].toString()) ?? now
              : now,
          updatedAt: sessionData['updated_at'] != null
              ? DateTimeHelper.parseIsoToLocal(sessionData['updated_at'].toString()) ?? now
              : now,
        );

        // Parse extracted items from response - check multiple possible keys
        // New backend format: items at root level alongside 'data' and 'quality_metrics'
        List<dynamic> extractedItemsList = [];
        if (responseData['items'] != null && responseData['items'] is List) {
          // New format: items at root level
          extractedItemsList = responseData['items'] as List<dynamic>;
          AppLogger.info('📥 Found ${extractedItemsList.length} items at root level');
        } else if (responseData['extracted_items'] != null) {
          extractedItemsList = responseData['extracted_items'] as List<dynamic>;
        } else if (sessionData['extracted_items'] != null) {
          extractedItemsList = sessionData['extracted_items'] as List<dynamic>;
        } else if (sessionData['items'] != null) {
          extractedItemsList = sessionData['items'] as List<dynamic>;
        }

        // Log quality metrics if available
        if (responseData['quality_metrics'] != null) {
          final metrics = responseData['quality_metrics'] as Map<String, dynamic>;
          AppLogger.info('📊 Quality metrics: score=${metrics['quality_score']}, verified=${metrics['verified_count']}, mismatch=${metrics['mismatch_count']}');
        }

        final extractedItems = extractedItemsList.map((item) {
          final itemMap = item as Map<String, dynamic>;
          return OCRExtractedItem(
            id: (itemMap['id'] ?? '').toString(),
            sessionId: sessionId,
            extractedText: itemMap['extracted_text']?.toString() ?? itemMap['brand_text']?.toString() ?? '',
            brandText: itemMap['brand_text']?.toString(),
            sizeText: itemMap['size_text']?.toString(),
            quantityText: itemMap['quantity_text']?.toString(),
            // New backend fields: opening_stock, sale_quantity, quantity (closing), selling_price
            parsedQuantity: _parseInt(itemMap['quantity']) ?? _parseInt(itemMap['parsed_quantity']),
            parsedSize: itemMap['parsed_size']?.toString() ?? itemMap['size_text']?.toString(),
            parsedPrice: _parseDouble(itemMap['selling_price']) ?? _parseDouble(itemMap['parsed_price']),
            // Stock tracking fields from new backend
            openingStock: _parseInt(itemMap['opening_stock']),
            closingStock: _parseInt(itemMap['quantity']) ?? _parseInt(itemMap['closing_stock']),
            ratePerUnit: _parseDouble(itemMap['selling_price']) ?? _parseDouble(itemMap['rate_per_unit']),
            rowNumber: _parseInt(itemMap['row_number']),
            // Matching fields
            matchedProductId: itemMap['matched_product_id']?.toString(),
            matchedBrandId: itemMap['matched_brand_id']?.toString(),
            matchedVariantId: itemMap['matched_variant_id']?.toString(),
            matchConfidence: (itemMap['match_confidence'] as num?)?.toDouble() ?? 0.0,
            matchMethod: itemMap['match_method']?.toString() ?? itemMap['match_strategy']?.toString(),
            // Verification status from backend
            isConfirmed: itemMap['is_confirmed'] as bool? ??
                         (itemMap['verification_status']?.toString() == 'verified'),
            createdAt: now,
            updatedAt: now,
          );
        }).toList();

        // Build summary
        final matchedItems = extractedItems.where((item) => item.matchedProductId != null).length;
        final summary = OCRProcessingSummary(
          totalItems: extractedItems.length,
          matchedItems: matchedItems,
          unmatchedItems: extractedItems.length - matchedItems,
          confidenceAvg: extractedItems.isEmpty
              ? 0.0
              : extractedItems.fold<double>(0, (sum, item) => sum + item.matchConfidence) /
                  extractedItems.length,
          processingTimeMs: sessionData['processing_time_ms'] as int? ?? 0,
          requiresReview: matchedItems < extractedItems.length,
        );

        final sessionResponse = OCRSessionResponse(
          session: session,
          extractedItems: extractedItems,
          summary: summary,
        );

        AppLogger.info('OCR session fetched: ${extractedItems.length} items, status: $status');
        return sessionResponse;
      } else {
        throw Exception(response.message ?? 'Failed to fetch OCR session');
      }
    } catch (e, stackTrace) {
      AppLogger.error('Error fetching OCR session', e, stackTrace);
      rethrow;
    }
  }

  /// Get OCR session with extracted items (wrapper for ApiResponse)
  Future<ApiResponse<OCRSessionResponse>> getSession(String sessionId) async {
    try {
      final sessionResponse = await getOCRSession(sessionId);
      return ApiResponse(
        success: true,
        message: 'OCR session fetched successfully',
        data: sessionResponse,
      );
    } catch (e, stackTrace) {
      AppLogger.error('Error fetching OCR session', e, stackTrace);
      return ApiResponse(
        success: false,
        message: 'Failed to fetch OCR session: ${e.toString()}',
        data: null,
      );
    }
  }

  /// Get OCR session status (quick check)
  Future<ApiResponse<String>> getSessionStatus(String sessionId) async {
    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        '/api/sales/ocr/sessions/$sessionId/status',
        fromJson: (data) => data as Map<String, dynamic>,
      );

      if (response.success && response.data != null) {
        final status = response.data!['status'] as String;
        return ApiResponse(
          success: true,
          message: 'Status fetched successfully',
          data: status,
        );
      } else {
        return ApiResponse(
          success: false,
          message: 'Failed to fetch status',
          data: null,
        );
      }
    } catch (e, stackTrace) {
      AppLogger.error('Error fetching OCR status', e, stackTrace);
      return ApiResponse(
        success: false,
        message: 'Error: ${e.toString()}',
        data: null,
      );
    }
  }

  /// Get OCR configuration
  Future<OCRMatchingConfig> getOCRConfig() async {
    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        '/api/sales/ocr/batch/config',
        fromJson: (data) => data as Map<String, dynamic>,
      );

      if (response.success && response.data != null) {
        return OCRMatchingConfig.fromJson(response.data!);
      } else {
        // Return default config if not available
        return const OCRMatchingConfig(
          minConfidenceScore: 0.7,
          fuzzyMatchThreshold: 0.8,
          enableAliasMatching: true,
          enablePatternMatching: true,
          maxSuggestionsPerItem: 3,
          autoConfirmHighMatches: true,
        );
      }
    } catch (e) {
      AppLogger.error('Error fetching OCR config, using defaults', e, null);
      // Return default config on error
      return const OCRMatchingConfig(
        minConfidenceScore: 0.7,
        fuzzyMatchThreshold: 0.8,
        enableAliasMatching: true,
        enablePatternMatching: true,
        maxSuggestionsPerItem: 3,
        autoConfirmHighMatches: true,
      );
    }
  }

  /// Get brand aliases
  Future<List<BrandAlias>> getBrandAliases(String brandId) async {
    try {
      final response = await _apiService.get<List<dynamic>>(
        '/api/sales/ocr/batch/brands/$brandId/aliases',
        fromJson: (data) => data as List<dynamic>,
      );

      if (response.success && response.data != null) {
        return response.data!
            .map((json) => BrandAlias.fromJson(json as Map<String, dynamic>))
            .toList();
      } else {
        return [];
      }
    } catch (e) {
      AppLogger.error('Error fetching brand aliases', e, null);
      return [];
    }
  }

  /// Create brand alias
  Future<BrandAlias> createBrandAlias({
    required String brandId,
    required String aliasText,
    required String aliasType,
  }) async {
    try {
      final response = await _apiService.post<BrandAlias>(
        '/api/sales/ocr/batch/brands/$brandId/aliases',
        body: {
          'alias_text': aliasText,
          'alias_type': aliasType,
        },
        fromJson: (data) => BrandAlias.fromJson(data as Map<String, dynamic>),
      );

      if (response.success && response.data != null) {
        return response.data!;
      } else {
        throw Exception(response.message ?? 'Failed to create brand alias');
      }
    } catch (e, stackTrace) {
      AppLogger.error('Error creating brand alias', e, stackTrace);
      rethrow;
    }
  }

  /// Confirm OCR items
  Future<void> confirmOCRItems({
    required String sessionId,
    required List<OCRItemConfirmation> items,
  }) async {
    try {
      final response = await _apiService.post<void>(
        '/api/sales/ocr/sessions/$sessionId/confirm',
        body: {
          'items': items.map((item) => item.toJson()).toList(),
        },
        fromJson: (_) {},
      );

      if (!response.success) {
        throw Exception(response.message ?? 'Failed to confirm OCR items');
      }
    } catch (e, stackTrace) {
      AppLogger.error('Error confirming OCR items', e, stackTrace);
      rethrow;
    }
  }

  /// Create quick sale from OCR
  Future<Map<String, dynamic>> createQuickSaleFromOCR({
    required String sessionId,
    String? customerPhone,
    required String paymentMethod,
    String? notes,
  }) async {
    try {
      final response = await _apiService.post<Map<String, dynamic>>(
        '/api/sales/ocr/sessions/$sessionId/quick-sale',
        body: {
          if (customerPhone != null) 'customer_phone': customerPhone,
          'payment_method': paymentMethod,
          if (notes != null) 'notes': notes,
        },
        fromJson: (data) => data as Map<String, dynamic>,
      );

      if (response.success && response.data != null) {
        return response.data!;
      } else {
        throw Exception(response.message ?? 'Failed to create quick sale from OCR');
      }
    } catch (e, stackTrace) {
      AppLogger.error('Error creating quick sale from OCR', e, stackTrace);
      rethrow;
    }
  }

  // Helper method to safely parse int from dynamic value
  int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  // Helper method to safely parse double from dynamic value
  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
