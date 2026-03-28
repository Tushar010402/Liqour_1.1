import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' as http;
import 'dart:convert';
import '../../../core/config/api_config.dart';
import '../../../core/models/api_response.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/utils/image_compressor.dart';
import '../../../core/utils/logger.dart';
import '../models/daily_sales_models.dart';
import '../models/sale.dart' show RevertOtpResponse;

/// Daily Sales Service - Handles API calls for bulk daily sales entry
/// OPTIMIZED: Reduced logging verbosity with kDebugMode guards
class DailySalesService {
  final AuthService _authService;

  DailySalesService(this._authService);

  /// Create new daily sales record
  /// OPTIMIZED: Reduced logging verbosity with kDebugMode guards
  Future<ApiResponse<DailySalesRecord>> createDailySalesRecord(
    DailySalesRecordRequest request,
  ) async {
    try {
      if (kDebugMode) {
        Logger.debug('DailySalesService: Creating record - ${request.recordDate}, Shop: ${request.shopId}, Total: ${request.totalSalesAmount}');
      }

      final token = await _authService.getToken();
      if (token == null) {
        if (kDebugMode) Logger.error('DailySalesService: Authentication failed');
        return ApiResponse.error(error: 'Not authenticated');
      }

      final tenantId = await _authService.getTenantId();
      if (tenantId == null) {
        if (kDebugMode) Logger.error('DailySalesService: Tenant ID not found');
        return ApiResponse.error(error: 'Tenant ID not found');
      }

      final url = '${ApiConfig.baseUrl}/api/sales/daily-sales';
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'X-Tenant-ID': tenantId,
          'Cache-Control': 'no-cache, no-store, must-revalidate',
          'Pragma': 'no-cache',
        },
        body: json.encode(request.toJson()),
      );

      if (kDebugMode) {
        Logger.debug('DailySalesService: Response - Status: ${response.statusCode}');
      }

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = json.decode(response.body);
        final record = DailySalesRecord.fromJson(data['data'] ?? data);
        if (kDebugMode) Logger.info('DailySalesService: Record created - ID: ${record.id}');
        return ApiResponse.success(record);
      } else {
        final error = json.decode(response.body);
        if (kDebugMode) Logger.error('DailySalesService: Failed (${response.statusCode}) - ${error['error']}');
        AppLogger.error('Daily sales API error: $error');
        return ApiResponse.error(error: error['error'] ?? error['errors']?.toString() ?? 'Failed to create daily sales record');
      }
    } catch (e, stackTrace) {
      if (kDebugMode) Logger.error('DailySalesService: Exception - $e');
      AppLogger.error('Error creating daily sales record: $e', e, stackTrace);
      return ApiResponse.error(error: 'Error creating daily sales record: $e');
    }
  }

  /// Get daily sales records with filters
  Future<ApiResponse<List<DailySalesRecord>>> getDailySalesRecords({
    String? shopId,
    DateTime? startDate,
    DateTime? endDate,
    String? status,
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      AppLogger.info('Fetching daily sales records');

      final token = await _authService.getToken();
      if (token == null) {
        return ApiResponse.error(error: 'Not authenticated');
      }

      final tenantId = await _authService.getTenantId();
      if (tenantId == null) {
        return ApiResponse.error(error: 'Tenant ID not found');
      }

      final queryParams = <String, String>{
        'page': page.toString(),
        'page_size': pageSize.toString(),
      };

      if (shopId != null) queryParams['shop_id'] = shopId;
      if (startDate != null) {
        // Format: YYYY-MM-DD (date only, no time component)
        queryParams['start_date'] = startDate.toIso8601String().split('T')[0];
      }
      if (endDate != null) {
        // Format: YYYY-MM-DD (date only, no time component)
        queryParams['end_date'] = endDate.toIso8601String().split('T')[0];
      }
      if (status != null) queryParams['status'] = status;

      final uri = Uri.parse('${ApiConfig.baseUrl}/api/sales/daily-sales')
          .replace(queryParameters: queryParams);

      // Debug: Log the full URL with query params
      debugPrint('📡 [DailySalesService] API Call: ${uri.toString()}');
      debugPrint('📡 [DailySalesService] Query params: $queryParams');

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'X-Tenant-ID': tenantId,
        },
      );

      AppLogger.info('Get daily sales response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // Backend returns: { "records": [...], "total_count": 14, "page": 1, ... }
        final totalCount = data['total_count'] ?? 0;
        final returnedPage = data['page'] ?? 1;
        final returnedPageSize = data['page_size'] ?? pageSize;
        debugPrint('📡 [DailySalesService] Response: total_count=$totalCount, page=$returnedPage/${ (totalCount / pageSize).ceil()}, page_size=$returnedPageSize');

        final recordsData = data['records'] as List? ?? [];
        final records = recordsData
            .map((record) => DailySalesRecord.fromJson(record))
            .toList();

        debugPrint('📡 [DailySalesService] Parsed ${records.length} records (total available: $totalCount)');
        if (records.isNotEmpty) {
          final dates = records.map((r) => r.recordDate).toList()..sort();
          debugPrint('📡 [DailySalesService] Date range in response: ${dates.first} to ${dates.last}');
        }

        // Log if there are more records to fetch
        if (totalCount > records.length && returnedPage == 1) {
          final remainingRecords = totalCount - records.length;
          debugPrint('⚠️ [DailySalesService] WARNING: $remainingRecords more records exist - pagination required!');
        }

        return ApiResponse.success(records);
      } else {
        final error = json.decode(response.body);
        return ApiResponse.error(error: error['error'] ?? 'Failed to fetch daily sales records');
      }
    } catch (e) {
      AppLogger.error('Error fetching daily sales records: $e');
      return ApiResponse.error(error: 'Error fetching daily sales records: $e');
    }
  }

  /// Get daily sales record by ID
  Future<ApiResponse<DailySalesRecord>> getDailySalesRecordById(String id) async {
    try {
      AppLogger.info('Fetching daily sales record: $id');

      final token = await _authService.getToken();
      if (token == null) {
        return ApiResponse.error(error: 'Not authenticated');
      }

      final tenantId = await _authService.getTenantId();
      if (tenantId == null) {
        return ApiResponse.error(error: 'Tenant ID not found');
      }

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/sales/daily-sales/$id'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'X-Tenant-ID': tenantId,
        },
      );

      AppLogger.info('Get daily sales record response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // Backend returns the record directly
        final record = DailySalesRecord.fromJson(data);
        return ApiResponse.success(record);
      } else {
        final error = json.decode(response.body);
        return ApiResponse.error(error: error['error'] ?? 'Failed to fetch daily sales record');
      }
    } catch (e) {
      AppLogger.error('Error fetching daily sales record: $e');
      return ApiResponse.error(error: 'Error fetching daily sales record: $e');
    }
  }

  /// Update daily sales record
  Future<ApiResponse<DailySalesRecord>> updateDailySalesRecord(
    String id,
    DailySalesRecordRequest request,
  ) async {
    try {
      AppLogger.info('Updating daily sales record: $id');

      final token = await _authService.getToken();
      if (token == null) {
        return ApiResponse.error(error: 'Not authenticated');
      }

      final tenantId = await _authService.getTenantId();
      if (tenantId == null) {
        return ApiResponse.error(error: 'Tenant ID not found');
      }

      final requestBody = request.toJson();

      // Debug: Log the full request body
      if (kDebugMode) {
        Logger.debug('UPDATE DAILY SALES REQUEST:');
        Logger.debug('   URL: ${ApiConfig.baseUrl}/api/sales/daily-sales/$id');
        Logger.debug('   shop_id: ${requestBody['shop_id']}');
        Logger.debug('   record_date: ${requestBody['record_date']}');
        Logger.debug('   total_sales_amount: ${requestBody['total_sales_amount']}');
        Logger.debug('   items count: ${(requestBody['items'] as List?)?.length ?? 0}');
        Logger.debug('   Full body: ${json.encode(requestBody)}');
      }

      final response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/api/sales/daily-sales/$id'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'X-Tenant-ID': tenantId,
        },
        body: json.encode(requestBody),
      );

      AppLogger.info('Update daily sales response: ${response.statusCode}');

      // Debug: Log response body for errors
      if (kDebugMode && response.statusCode != 200) {
        Logger.error('UPDATE FAILED - Response: ${response.body}');
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // Backend may return record directly or wrapped in 'data'
        final record = DailySalesRecord.fromJson(data['data'] ?? data);
        return ApiResponse.success(record);
      } else {
        final error = json.decode(response.body);
        return ApiResponse.error(error: error['error'] ?? error['errors']?.toString() ?? 'Failed to update daily sales record');
      }
    } catch (e) {
      AppLogger.error('Error updating daily sales record: $e');
      return ApiResponse.error(error: 'Error updating daily sales record: $e');
    }
  }

  /// Approve daily sales record (Manager only)
  Future<ApiResponse<DailySalesRecord>> approveDailySalesRecord(String id) async {
    try {
      AppLogger.info('Approving daily sales record: $id');

      final token = await _authService.getToken();
      if (token == null) {
        return ApiResponse.error(error: 'Not authenticated');
      }

      final tenantId = await _authService.getTenantId();
      if (tenantId == null) {
        return ApiResponse.error(error: 'Tenant ID not found');
      }

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/sales/daily-sales/$id/approve'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'X-Tenant-ID': tenantId,
        },
      );

      AppLogger.info('Approve daily sales response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // Backend returns the record directly (not wrapped in 'data')
        final record = DailySalesRecord.fromJson(data);
        return ApiResponse.success(record);
      } else {
        final error = json.decode(response.body);
        return ApiResponse.error(error: error['error'] ?? 'Failed to approve daily sales record');
      }
    } catch (e) {
      AppLogger.error('Error approving daily sales record: $e');
      return ApiResponse.error(error: 'Error approving daily sales record: $e');
    }
  }

  /// Reject daily sales record (Manager only)
  Future<ApiResponse<void>> rejectDailySalesRecord(String id, String reason) async {
    try {
      AppLogger.info('Rejecting daily sales record: $id');

      final token = await _authService.getToken();
      if (token == null) {
        return ApiResponse.error(error: 'Not authenticated');
      }

      final tenantId = await _authService.getTenantId();
      if (tenantId == null) {
        return ApiResponse.error(error: 'Tenant ID not found');
      }

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/sales/daily-sales/$id/reject'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'X-Tenant-ID': tenantId,
        },
        body: json.encode({'reason': reason}),
      );

      AppLogger.info('Reject daily sales response: ${response.statusCode}');

      if (response.statusCode == 200) {
        return ApiResponse.success(null);
      } else {
        final error = json.decode(response.body);
        return ApiResponse.error(error: error['error'] ?? 'Failed to reject daily sales record');
      }
    } catch (e) {
      AppLogger.error('Error rejecting daily sales record: $e');
      return ApiResponse.error(error: 'Error rejecting daily sales record: $e');
    }
  }

  /// Validate products batch before submission
  /// Returns validation results for each product (stock availability, etc.)
  Future<ApiResponse<BatchValidationResult>> validateProductsBatch({
    required String shopId,
    required List<BatchValidationItem> items,
  }) async {
    try {
      if (kDebugMode) {
        Logger.debug('DailySalesService: Validating ${items.length} products for shop $shopId');
      }

      final token = await _authService.getToken();
      if (token == null) {
        return ApiResponse.error(error: 'Not authenticated');
      }

      final tenantId = await _authService.getTenantId();
      if (tenantId == null) {
        return ApiResponse.error(error: 'Tenant ID not found');
      }

      final url = '${ApiConfig.baseUrl}/api/sales/products/validate-batch';
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'X-Tenant-ID': tenantId,
        },
        body: json.encode({
          'shop_id': shopId,
          'items': items.map((item) => item.toJson()).toList(),
        }),
      );

      if (kDebugMode) {
        Logger.debug('DailySalesService: Validation response - ${response.statusCode}');
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final result = BatchValidationResult.fromJson(data);
        if (kDebugMode) {
          Logger.info('DailySalesService: Validation complete - ${result.validCount} valid, ${result.invalidCount} invalid');
        }
        return ApiResponse.success(result);
      } else {
        final error = json.decode(response.body);
        if (kDebugMode) Logger.error('DailySalesService: Validation failed - ${error["error"]}');
        return ApiResponse.error(error: error['error'] ?? 'Failed to validate products');
      }
    } catch (e) {
      if (kDebugMode) Logger.error('DailySalesService: Validation exception - $e');
      AppLogger.error('Error validating products batch: $e');
      return ApiResponse.error(error: 'Error validating products: $e');
    }
  }

  // ============================================================================
  // IMAGE UPLOAD METHODS
  // ============================================================================

  /// Upload a single image for daily sales record
  /// Returns the URL of the uploaded image
  Future<ApiResponse<String>> uploadSalesImage(File imageFile) async {
    try {
      if (kDebugMode) {
        Logger.debug('DailySalesService: Uploading image - ${imageFile.path}');
      }

      final token = await _authService.getToken();
      if (token == null) {
        return ApiResponse.error(error: 'Not authenticated');
      }

      final tenantId = await _authService.getTenantId();
      if (tenantId == null) {
        return ApiResponse.error(error: 'Tenant ID not found');
      }

      // Create multipart request
      final url = '${ApiConfig.baseUrl}/api/sales/daily-sales/upload-image';
      final request = http.MultipartRequest('POST', Uri.parse(url));

      // Add auth headers
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['X-Tenant-ID'] = tenantId;

      // Add file
      final fileName = imageFile.path.split('/').last;
      final fileExtension = fileName.split('.').last.toLowerCase();
      final mimeType = _getMimeType(fileExtension);

      request.files.add(
        await http.MultipartFile.fromPath(
          'images',  // Backend expects 'images' field name
          imageFile.path,
          contentType: http.MediaType.parse(mimeType),
        ),
      );

      // Send request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (kDebugMode) {
        Logger.debug('DailySalesService: Upload response - ${response.statusCode}');
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);

        if (kDebugMode) {
          Logger.debug('DailySalesService: Response body - ${response.body}');
        }

        // Backend returns image_urls as array - get first URL
        String? imageUrl;

        // Check for image_urls array (backend response format)
        if (data['image_urls'] != null && data['image_urls'] is List) {
          final urls = data['image_urls'] as List;
          if (urls.isNotEmpty) {
            imageUrl = urls.first.toString();
          }
        }

        // Fallback to single URL fields
        imageUrl ??= data['image_url']?.toString() ??
                     data['url']?.toString() ??
                     data['file_url']?.toString() ??
                     data['data']?['url']?.toString();

        if (imageUrl != null && imageUrl.isNotEmpty) {
          // ═══════════════════════════════════════════════════════════════════════
          // CRITICAL FIX: Convert relative paths to full URLs
          // Backend returns relative paths like "/uploads/daily_sales/..."
          // CachedNetworkImageProvider requires full URLs with host
          // ═══════════════════════════════════════════════════════════════════════
          if (imageUrl.startsWith('/') && !imageUrl.startsWith('http')) {
            imageUrl = '${ApiConfig.baseUrl}$imageUrl';
            if (kDebugMode) {
              Logger.debug('DailySalesService: Converted relative path to full URL');
            }
          }
          if (kDebugMode) {
            Logger.info('DailySalesService: Image uploaded - $imageUrl');
          }
          return ApiResponse.success(imageUrl);
        } else {
          if (kDebugMode) {
            Logger.error('DailySalesService: No URL in response - $data');
          }
          return ApiResponse.error(error: 'No URL returned from upload');
        }
      } else {
        final error = json.decode(response.body);
        if (kDebugMode) {
          Logger.error('DailySalesService: Upload failed - ${error['error']}');
        }
        return ApiResponse.error(error: error['error'] ?? 'Failed to upload image');
      }
    } catch (e) {
      if (kDebugMode) {
        Logger.error('DailySalesService: Upload exception - $e');
      }
      AppLogger.error('Error uploading sales image: $e');
      return ApiResponse.error(error: 'Error uploading image: $e');
    }
  }

  /// Upload multiple images and return list of URLs
  ///
  /// INDUSTRIAL-GRADE IMPLEMENTATION:
  /// - Compresses images in background isolate before upload (9MB → ~200KB)
  /// - Sequential uploads with delay to prevent backend race condition
  /// - Backend generates filenames using timestamp+counter (e.g., 201945_1.jpg)
  /// - If uploads happen within same second, backend may return duplicate URLs
  /// - Solution: Add 1.1 second delay between uploads to ensure unique timestamps
  /// - Also deduplicates URLs as a safety net
  ///
  /// [onCompressionProgress] - Callback for compression progress (current, total, filename)
  /// [onUploadProgress] - Callback for upload progress (current, total, filename)
  Future<ApiResponse<List<String>>> uploadSalesImages(
    List<File> imageFiles, {
    Function(int current, int total, String fileName)? onCompressionProgress,
    Function(int current, int total, String fileName)? onUploadProgress,
  }) async {
    try {
      if (kDebugMode) {
        Logger.info('DailySalesService: Starting upload of ${imageFiles.length} images');
        Logger.debug('DailySalesService: Phase 1 - Compressing images in background...');
        int totalOriginalSize = 0;
        for (int i = 0; i < imageFiles.length; i++) {
          final file = imageFiles[i];
          final fileName = file.path.split('/').last;
          final fileSize = await file.length();
          totalOriginalSize += fileSize;
          Logger.debug('   Image ${i + 1}: $fileName (${(fileSize / 1024).toStringAsFixed(1)} KB)');
        }
        Logger.debug('   Total original size: ${(totalOriginalSize / 1024 / 1024).toStringAsFixed(1)} MB');
      }

      // ═══════════════════════════════════════════════════════════════════════
      // PHASE 1: COMPRESS IMAGES IN BACKGROUND (Non-blocking)
      // Uses native compression (libjpeg-turbo/ImageIO) for 10-50x faster than Dart
      // Runs in isolate - UI remains responsive
      // ═══════════════════════════════════════════════════════════════════════
      final List<File> compressedFiles = await ImageCompressor.compressImages(
        imageFiles,
        quality: 85, // High quality JPEG
        maxWidth: 2048,
        maxHeight: 2048,
        onProgress: (current, total, fileName) {
          onCompressionProgress?.call(current, total, fileName);
          if (kDebugMode) {
            Logger.debug('DailySalesService: Compressing $current/$total - $fileName');
          }
        },
      );

      // Log compression results
      if (kDebugMode) {
        int totalCompressedSize = 0;
        for (final file in compressedFiles) {
          totalCompressedSize += await file.length();
        }
        Logger.info('DailySalesService: Compression complete!');
        Logger.debug('   Total compressed size: ${(totalCompressedSize / 1024).toStringAsFixed(0)} KB');
        Logger.debug('DailySalesService: Phase 2 - Uploading compressed images...');
      }

      // ═══════════════════════════════════════════════════════════════════════
      // PHASE 2: UPLOAD COMPRESSED IMAGES
      // ═══════════════════════════════════════════════════════════════════════
      final List<String> uploadedUrls = [];
      final Set<String> seenUrls = {}; // Track URLs to detect duplicates in real-time

      for (int i = 0; i < compressedFiles.length; i++) {
        // Report upload progress
        final fileName = compressedFiles[i].path.split('/').last;
        onUploadProgress?.call(i + 1, compressedFiles.length, fileName);

        // Add delay between uploads to prevent backend race condition
        // Backend uses timestamp (HHMMSS) in filename - uploads within same second
        // get the same filename and overwrite each other
        // Delay of 1100ms ensures each upload gets a unique timestamp
        if (i > 0) {
          if (kDebugMode) {
            Logger.debug('DailySalesService: Waiting 1.1s before next upload...');
          }
          await Future.delayed(const Duration(milliseconds: 1100));
        }

        final result = await uploadSalesImage(compressedFiles[i]);

        if (result.success && result.data != null) {
          final url = result.data!;

          // Real-time duplicate detection
          if (seenUrls.contains(url)) {
            if (kDebugMode) {
              Logger.warning('DailySalesService: DUPLICATE URL detected for image ${i + 1}: $url');
              Logger.warning('   This indicates backend race condition - retrying with additional delay...');
            }
            // Retry with extra delay
            await Future.delayed(const Duration(milliseconds: 2000));
            final retryResult = await uploadSalesImage(compressedFiles[i]);
            if (retryResult.success && retryResult.data != null && !seenUrls.contains(retryResult.data!)) {
              uploadedUrls.add(retryResult.data!);
              seenUrls.add(retryResult.data!);
              if (kDebugMode) {
                Logger.info('DailySalesService: Retry successful with unique URL: ${retryResult.data}');
              }
            } else {
              // Still got duplicate or error - add anyway with warning
              uploadedUrls.add(url);
              if (kDebugMode) {
                Logger.warning('DailySalesService: Retry still returned duplicate - proceeding anyway');
              }
            }
          } else {
            uploadedUrls.add(url);
            seenUrls.add(url);
            if (kDebugMode) {
              Logger.info('DailySalesService: Image ${i + 1}/${compressedFiles.length} uploaded -> $url');
            }
          }
        } else {
          // CRITICAL FIX: Don't fail entire batch on single upload failure!
          // Continue uploading remaining images and return partial success
          if (kDebugMode) {
            Logger.error('DailySalesService: Image ${i + 1} upload FAILED: ${result.error}');
            Logger.warning('   Continuing with remaining images (partial upload)');
          }
        }
      }

      // ═══════════════════════════════════════════════════════════════════════
      // CLEANUP: Delete temporary compressed files
      // ═══════════════════════════════════════════════════════════════════════
      await ImageCompressor.cleanupTempFiles(compressedFiles);

      // SAFETY NET: Final deduplication (should not be needed with delays)
      final uniqueUrls = uploadedUrls.toSet().toList();

      if (kDebugMode) {
        final successCount = uniqueUrls.length;
        final failCount = imageFiles.length - successCount;
        if (failCount > 0) {
          Logger.warning('DailySalesService: Partial upload - $successCount/${imageFiles.length} succeeded ($failCount failed)');
        } else {
          Logger.info('DailySalesService: All ${imageFiles.length} images uploaded successfully');
        }
        Logger.debug('Final URLs: ${uniqueUrls.length} unique (uploaded: ${uploadedUrls.length})');
        if (uniqueUrls.length != uploadedUrls.length) {
          Logger.warning('WARNING: ${uploadedUrls.length - uniqueUrls.length} duplicate(s) removed');
        }
        for (int i = 0; i < uniqueUrls.length; i++) {
          Logger.debug('   ${i + 1}. ${uniqueUrls[i]}');
        }
      }

      // CRITICAL: Only fail if NO images were uploaded
      // Return partial success if at least some images uploaded
      if (uniqueUrls.isEmpty && imageFiles.isNotEmpty) {
        return ApiResponse.error(error: 'All image uploads failed');
      }

      // Return whatever URLs we successfully collected
      return ApiResponse.success(uniqueUrls);
    } catch (e) {
      if (kDebugMode) {
        Logger.error('DailySalesService: Upload batch exception - $e');
      }
      AppLogger.error('Error uploading sales images: $e');
      return ApiResponse.error(error: 'Error uploading images: $e');
    }
  }

  /// Helper to get MIME type from file extension
  String _getMimeType(String extension) {
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }

  /// Delete/Cancel a daily sales record (only pending records)
  /// Used by salesman to cancel their own pending submissions
  Future<ApiResponse<void>> deleteDailySalesRecord(String id) async {
    try {
      if (kDebugMode) {
        Logger.info('DailySalesService: Deleting record $id');
      }

      final token = await _authService.getToken();
      if (token == null) {
        return ApiResponse.error(error: 'Not authenticated');
      }

      final tenantId = await _authService.getTenantId();
      if (tenantId == null) {
        return ApiResponse.error(error: 'Tenant ID not found');
      }

      final url = '${ApiConfig.baseUrl}/api/sales/daily-sales/$id';
      final response = await http.delete(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'X-Tenant-ID': tenantId,
        },
      );

      if (kDebugMode) {
        Logger.debug('DailySalesService: Delete response - ${response.statusCode}');
      }

      if (response.statusCode == 200 || response.statusCode == 204) {
        if (kDebugMode) Logger.info('DailySalesService: Record deleted successfully');
        return ApiResponse.success(null);
      } else {
        final error = json.decode(response.body);
        if (kDebugMode) Logger.error('DailySalesService: Delete failed - ${error["error"]}');
        return ApiResponse.error(error: error['error'] ?? 'Failed to delete record');
      }
    } catch (e) {
      if (kDebugMode) Logger.error('DailySalesService: Delete exception - $e');
      AppLogger.error('Error deleting daily sales record: $e');
      return ApiResponse.error(error: 'Error deleting record: $e');
    }
  }

  // ============================================================================
  // AI VALIDATION METHODS
  // ============================================================================

  /// Get AI validation results for a daily sales record
  /// This fetches the detailed comparison between entered data and OCR-extracted data
  Future<ApiResponse<AIValidationResult>> getValidation(String recordId) async {
    try {
      if (kDebugMode) {
        Logger.debug('DailySalesService: Fetching AI validation for record $recordId');
      }

      final token = await _authService.getToken();
      if (token == null) {
        return ApiResponse.error(error: 'Not authenticated');
      }

      final tenantId = await _authService.getTenantId();
      if (tenantId == null) {
        return ApiResponse.error(error: 'Tenant ID not found');
      }

      final url = '${ApiConfig.baseUrl}/api/sales/daily-sales/$recordId/validation';
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'X-Tenant-ID': tenantId,
        },
      );

      if (kDebugMode) {
        Logger.debug('DailySalesService: Validation response - ${response.statusCode}');
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // Backend may return directly or wrapped in 'data'
        final validationData = data['data'] ?? data;
        final result = AIValidationResult.fromJson(validationData);
        if (kDebugMode) {
          Logger.info('DailySalesService: Validation fetched - Status: ${result.status}, Mismatches: ${result.mismatchCount}');
        }
        return ApiResponse.success(result);
      } else if (response.statusCode == 404) {
        // No validation available yet (OCR not triggered or still processing)
        return ApiResponse.success(const AIValidationResult(status: 'pending'));
      } else {
        final error = json.decode(response.body);
        if (kDebugMode) Logger.error('DailySalesService: Validation fetch failed - ${error["error"]}');
        return ApiResponse.error(error: error['error'] ?? 'Failed to fetch validation');
      }
    } catch (e) {
      if (kDebugMode) Logger.error('DailySalesService: Validation exception - $e');
      AppLogger.error('Error fetching AI validation: $e');
      return ApiResponse.error(error: 'Error fetching validation: $e');
    }
  }

  /// Trigger AI validation manually for a record (if not already done)
  Future<ApiResponse<void>> triggerValidation(String recordId) async {
    try {
      if (kDebugMode) {
        Logger.debug('DailySalesService: Triggering AI validation for record $recordId');
      }

      final token = await _authService.getToken();
      if (token == null) {
        return ApiResponse.error(error: 'Not authenticated');
      }

      final tenantId = await _authService.getTenantId();
      if (tenantId == null) {
        return ApiResponse.error(error: 'Tenant ID not found');
      }

      final url = '${ApiConfig.baseUrl}/api/sales/daily-sales/$recordId/validate';
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'X-Tenant-ID': tenantId,
        },
      );

      if (kDebugMode) {
        Logger.debug('DailySalesService: Trigger response - ${response.statusCode}');
      }

      if (response.statusCode == 200 || response.statusCode == 202) {
        if (kDebugMode) Logger.info('DailySalesService: Validation triggered successfully');
        return ApiResponse.success(null);
      } else {
        final error = json.decode(response.body);
        if (kDebugMode) Logger.error('DailySalesService: Trigger failed - ${error["error"]}');
        return ApiResponse.error(error: error['error'] ?? 'Failed to trigger validation');
      }
    } catch (e) {
      if (kDebugMode) Logger.error('DailySalesService: Trigger exception - $e');
      AppLogger.error('Error triggering AI validation: $e');
      return ApiResponse.error(error: 'Error triggering validation: $e');
    }
  }

  // ============================================================================
  // RECORD MANAGEMENT METHODS
  // ============================================================================

  /// Change the date of a daily sales record
  /// Rules: Pending = anyone can change, Approved = admin/manager only, Rejected = cannot change
  /// Returns ChangeDateResponse with old date, new date, and success status
  Future<ApiResponse<ChangeDateResponse>> changeDailySalesRecordDate(
    String id, {
    required DateTime newDate,
    String? reason,
  }) async {
    try {
      if (kDebugMode) {
        Logger.info('DailySalesService: Changing date for record $id to ${newDate.toIso8601String().split('T')[0]}');
      }

      final token = await _authService.getToken();
      if (token == null) {
        return ApiResponse.error(error: 'Not authenticated');
      }

      final tenantId = await _authService.getTenantId();
      if (tenantId == null) {
        return ApiResponse.error(error: 'Tenant ID not found');
      }

      final url = '${ApiConfig.baseUrl}/api/sales/daily-sales/$id/change-date';
      final response = await http.patch(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'X-Tenant-ID': tenantId,
        },
        body: json.encode({
          'new_date': newDate.toIso8601String().split('T')[0], // Format: YYYY-MM-DD
          if (reason != null && reason.isNotEmpty) 'reason': reason,
        }),
      );

      if (kDebugMode) {
        Logger.debug('DailySalesService: Change date response - ${response.statusCode}');
        if (response.statusCode != 200) {
          Logger.debug('DailySalesService: Response body - ${response.body}');
        }
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final result = ChangeDateResponse.fromJson(data);
        if (kDebugMode) {
          Logger.info('DailySalesService: Date changed successfully');
          Logger.debug('   Old date: ${result.oldDate}');
          Logger.debug('   New date: ${result.newDate}');
        }
        return ApiResponse.success(result);
      } else {
        final error = json.decode(response.body);
        if (kDebugMode) Logger.error('DailySalesService: Change date failed - ${error["error"]}');
        return ApiResponse.error(error: error['error'] ?? 'Failed to change date');
      }
    } catch (e) {
      if (kDebugMode) Logger.error('DailySalesService: Change date exception - $e');
      AppLogger.error('Error changing daily sales record date: $e');
      return ApiResponse.error(error: 'Error changing date: $e');
    }
  }

  // ============================================================================
  // REVERT METHODS (Admin Only)
  // ============================================================================

  /// Request OTP for daily sales record revert - Admin only
  /// Sends different OTPs to both email and phone for security
  Future<ApiResponse<RevertOtpResponse>> requestRevertOtp(String recordId) async {
    try {
      if (kDebugMode) {
        Logger.info('DailySalesService: Requesting revert OTP for record $recordId');
      }

      final token = await _authService.getToken();
      if (token == null) {
        return ApiResponse.error(error: 'Not authenticated');
      }

      final tenantId = await _authService.getTenantId();
      if (tenantId == null) {
        return ApiResponse.error(error: 'Tenant ID not found');
      }

      final url = '${ApiConfig.baseUrl}/api/sales/daily-sales/$recordId/revert/request-otp';
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'X-Tenant-ID': tenantId,
        },
      );

      if (kDebugMode) {
        Logger.debug('DailySalesService: OTP request response - ${response.statusCode}');
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final result = RevertOtpResponse.fromJson(data);
        if (kDebugMode) {
          Logger.info('DailySalesService: OTP sent - Email: ${result.emailSent}, Phone: ${result.phoneSent}');
        }
        return ApiResponse.success(result);
      } else {
        final error = json.decode(response.body);
        if (kDebugMode) Logger.error('DailySalesService: OTP request failed - ${error["error"]}');
        return ApiResponse.error(error: error['error'] ?? 'Failed to request OTP');
      }
    } catch (e) {
      if (kDebugMode) Logger.error('DailySalesService: OTP request exception - $e');
      AppLogger.error('Error requesting revert OTP: $e');
      return ApiResponse.error(error: 'Error requesting OTP: $e');
    }
  }

  /// Verify OTPs and revert daily sales record - Admin only
  /// Requires both email and phone OTPs to be correct
  /// Max 3 attempts, OTPs expire after 10 minutes
  Future<ApiResponse<Map<String, dynamic>>> verifyAndRevertRecord({
    required String recordId,
    required String emailOtp,
    required String phoneOtp,
    required String reason,
  }) async {
    try {
      if (kDebugMode) {
        Logger.info('DailySalesService: Verifying OTPs and reverting record $recordId');
      }

      final token = await _authService.getToken();
      if (token == null) {
        return ApiResponse.error(error: 'Not authenticated');
      }

      final tenantId = await _authService.getTenantId();
      if (tenantId == null) {
        return ApiResponse.error(error: 'Tenant ID not found');
      }

      final url = '${ApiConfig.baseUrl}/api/sales/daily-sales/$recordId/revert';
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'X-Tenant-ID': tenantId,
        },
        body: json.encode({
          'email_otp': emailOtp,
          'phone_otp': phoneOtp,
          'reason': reason,
        }),
      );

      if (kDebugMode) {
        Logger.debug('DailySalesService: Revert response - ${response.statusCode}');
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (kDebugMode) Logger.info('DailySalesService: Record reverted successfully');
        return ApiResponse.success(data as Map<String, dynamic>);
      } else {
        final error = json.decode(response.body);
        if (kDebugMode) Logger.error('DailySalesService: Revert failed - ${error["error"]}');
        return ApiResponse.error(error: error['error'] ?? 'Failed to revert record');
      }
    } catch (e) {
      if (kDebugMode) Logger.error('DailySalesService: Revert exception - $e');
      AppLogger.error('Error reverting record: $e');
      return ApiResponse.error(error: 'Error reverting record: $e');
    }
  }

  /// Resend OTP for daily sales record revert - re-requests new OTPs
  Future<ApiResponse<RevertOtpResponse>> resendRevertOtp(String recordId) async {
    // Just call requestRevertOtp again to get new OTPs
    return requestRevertOtp(recordId);
  }

  // ============================================================================
  // BACKEND VERIFICATION METHODS (Industrial-Grade)
  // ============================================================================

  /// Verify a record exists on backend by fetching it
  /// INDUSTRIAL-GRADE: Used to confirm successful submission before clearing draft
  ///
  /// Returns:
  /// - ApiResponse.success(true) if record exists and is valid
  /// - ApiResponse.success(false) if record doesn't exist (404)
  /// - ApiResponse.error() if network/server error
  Future<ApiResponse<bool>> verifyRecordExists(String recordId) async {
    try {
      if (kDebugMode) {
        Logger.debug('DailySalesService: Verifying record exists - $recordId');
      }

      final token = await _authService.getToken();
      if (token == null) {
        return ApiResponse.error(error: 'Not authenticated');
      }

      final tenantId = await _authService.getTenantId();
      if (tenantId == null) {
        return ApiResponse.error(error: 'Tenant ID not found');
      }

      final url = '${ApiConfig.baseUrl}/api/sales/daily-sales/$recordId';
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'X-Tenant-ID': tenantId,
          'Cache-Control': 'no-cache, no-store, must-revalidate',
          'Pragma': 'no-cache',
        },
      );

      if (kDebugMode) {
        Logger.debug('DailySalesService: Verify response - ${response.statusCode}');
      }

      if (response.statusCode == 200) {
        // Record exists - parse to make sure it's valid JSON
        try {
          final data = json.decode(response.body);
          // Check for record ID in response to double-confirm
          final returnedId = data['id']?.toString() ?? data['data']?['id']?.toString();
          if (returnedId == recordId) {
            if (kDebugMode) Logger.info('DailySalesService: Record verified - $recordId');
            return ApiResponse.success(true);
          } else {
            if (kDebugMode) Logger.warning('DailySalesService: ID mismatch - expected $recordId, got $returnedId');
            return ApiResponse.success(false);
          }
        } catch (e) {
          if (kDebugMode) Logger.warning('DailySalesService: Invalid JSON in verify response');
          return ApiResponse.error(error: 'Invalid response format');
        }
      } else if (response.statusCode == 404) {
        if (kDebugMode) Logger.error('DailySalesService: Record not found - $recordId');
        return ApiResponse.success(false);
      } else {
        if (kDebugMode) Logger.error('DailySalesService: Verify failed - ${response.statusCode}');
        return ApiResponse.error(error: 'Failed to verify record (${response.statusCode})');
      }
    } catch (e) {
      if (kDebugMode) Logger.error('DailySalesService: Verify exception - $e');
      return ApiResponse.error(error: 'Error verifying record: $e');
    }
  }

  /// Verify record exists with retry and exponential backoff
  /// INDUSTRIAL-GRADE: Handles network flakiness gracefully
  ///
  /// Parameters:
  /// - recordId: The record ID to verify
  /// - maxRetries: Maximum number of retry attempts (default: 3)
  /// - initialDelayMs: Initial delay before first retry in milliseconds (default: 500)
  ///
  /// Returns true only if record is confirmed to exist on backend
  Future<bool> verifyRecordExistsWithRetry(
    String recordId, {
    int maxRetries = 3,
    int initialDelayMs = 500,
  }) async {
    int attempt = 0;
    int delay = initialDelayMs;

    while (attempt < maxRetries) {
      attempt++;

      if (kDebugMode) {
        Logger.debug('DailySalesService: Verify attempt $attempt/$maxRetries for record $recordId');
      }

      final result = await verifyRecordExists(recordId);

      if (result.success && result.data == true) {
        // Record confirmed to exist
        return true;
      }

      if (result.success && result.data == false) {
        // Record definitively doesn't exist (404) - don't retry
        if (kDebugMode) {
          Logger.error('DailySalesService: Record definitely doesn\'t exist, stopping retries');
        }
        return false;
      }

      // Network/server error - retry with exponential backoff
      if (attempt < maxRetries) {
        if (kDebugMode) {
          Logger.debug('DailySalesService: Waiting ${delay}ms before retry...');
        }
        await Future.delayed(Duration(milliseconds: delay));
        delay *= 2; // Exponential backoff: 500ms -> 1000ms -> 2000ms
      }
    }

    if (kDebugMode) {
      Logger.error('DailySalesService: Failed to verify after $maxRetries attempts');
    }
    return false;
  }

  /// Copy a rejected record to create a new draft
  /// Useful for recovering rejected records after fixes
  Future<ApiResponse<DailySalesRecord>> copyDailySalesRecord(String id) async {
    try {
      if (kDebugMode) {
        Logger.info('DailySalesService: Copying record $id');
      }

      final token = await _authService.getToken();
      if (token == null) {
        return ApiResponse.error(error: 'Not authenticated');
      }

      final tenantId = await _authService.getTenantId();
      if (tenantId == null) {
        return ApiResponse.error(error: 'Tenant ID not found');
      }

      final url = '${ApiConfig.baseUrl}/api/sales/daily-sales/$id/copy';
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'X-Tenant-ID': tenantId,
        },
      );

      if (kDebugMode) {
        Logger.debug('DailySalesService: Copy response - ${response.statusCode}');
      }

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = json.decode(response.body);
        final record = DailySalesRecord.fromJson(data['data'] ?? data);
        if (kDebugMode) Logger.info('DailySalesService: Record copied - New ID: ${record.id}');
        return ApiResponse.success(record);
      } else {
        final error = json.decode(response.body);
        if (kDebugMode) Logger.error('DailySalesService: Copy failed - ${error["error"]}');
        return ApiResponse.error(error: error['error'] ?? 'Failed to copy record');
      }
    } catch (e) {
      if (kDebugMode) Logger.error('DailySalesService: Copy exception - $e');
      AppLogger.error('Error copying daily sales record: $e');
      return ApiResponse.error(error: 'Error copying record: $e');
    }
  }

  /// Get status counts from dashboard summary API
  /// Returns accurate counts for pending, approved, rejected records
  Future<ApiResponse<DailySalesStatusCounts>> getStatusCounts({String? shopId}) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        return ApiResponse.error(error: 'Not authenticated');
      }

      final tenantId = await _authService.getTenantId();
      if (tenantId == null) {
        return ApiResponse.error(error: 'Tenant ID not found');
      }

      String url = '${ApiConfig.baseUrl}/api/sales/dashboard/summary';
      if (shopId != null && shopId.isNotEmpty) {
        url += '?shop_id=$shopId';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'X-Tenant-ID': tenantId,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final todaySales = data['todays_sales'] ?? {};

        // Extract counts from dashboard summary
        final counts = DailySalesStatusCounts(
          pendingCount: data['pending_sales'] ?? todaySales['pending_sales'] ?? 0,
          approvedCount: todaySales['approved_sales'] ?? 0,
          totalCount: todaySales['total_sales'] ?? 0,
          pendingAmount: (todaySales['pending_amount'] ?? 0).toDouble(),
          approvedAmount: (todaySales['approved_amount'] ?? 0).toDouble(),
          totalAmount: (todaySales['total_amount'] ?? 0).toDouble(),
        );
        return ApiResponse.success(counts);
      } else {
        return ApiResponse.error(error: 'Failed to fetch status counts');
      }
    } catch (e) {
      AppLogger.error('Error fetching status counts: $e');
      return ApiResponse.error(error: 'Error fetching status counts: $e');
    }
  }
}

/// Batch validation request item
class BatchValidationItem {
  final String productId;
  final int quantity;

  BatchValidationItem({
    required this.productId,
    required this.quantity,
  });

  Map<String, dynamic> toJson() => {
    'product_id': productId,
    'quantity': quantity,
  };
}

/// Batch validation result
class BatchValidationResult {
  final bool isValid;
  final int validCount;
  final int invalidCount;
  final List<ProductValidationResult> results;

  BatchValidationResult({
    required this.isValid,
    required this.validCount,
    required this.invalidCount,
    required this.results,
  });

  factory BatchValidationResult.fromJson(Map<String, dynamic> json) {
    final resultsData = json['results'] as List? ?? [];
    return BatchValidationResult(
      isValid: json['is_valid'] ?? false,
      validCount: json['valid_count'] ?? 0,
      invalidCount: json['invalid_count'] ?? 0,
      results: resultsData
          .map((r) => ProductValidationResult.fromJson(r))
          .toList(),
    );
  }
}

/// Individual product validation result
class ProductValidationResult {
  final String productId;
  final String productName;
  final bool isValid;
  final int requestedQuantity;
  final int availableStock;
  final String? errorMessage;

  ProductValidationResult({
    required this.productId,
    required this.productName,
    required this.isValid,
    required this.requestedQuantity,
    required this.availableStock,
    this.errorMessage,
  });

  factory ProductValidationResult.fromJson(Map<String, dynamic> json) {
    return ProductValidationResult(
      productId: json['product_id'] ?? '',
      productName: json['product_name'] ?? '',
      isValid: json['is_valid'] ?? false,
      requestedQuantity: json['requested_quantity'] ?? 0,
      availableStock: json['available_stock'] ?? 0,
      errorMessage: json['error_message'],
    );
  }

  /// Check if this is a stock issue
  bool get isStockIssue => !isValid && availableStock < requestedQuantity;
}

/// Response from change-date API
class ChangeDateResponse {
  final bool success;
  final String message;
  final String recordId;
  final DateTime oldDate;
  final DateTime newDate;
  final String changedBy;
  final bool requestSent; // True if admin approval request was sent (for approved records by non-admin)

  ChangeDateResponse({
    required this.success,
    required this.message,
    required this.recordId,
    required this.oldDate,
    required this.newDate,
    required this.changedBy,
    this.requestSent = false,
  });

  factory ChangeDateResponse.fromJson(Map<String, dynamic> json) {
    return ChangeDateResponse(
      success: json['success'] ?? false,
      message: json['message'] ?? '',
      recordId: json['record_id'] ?? '',
      oldDate: _parseDate(json['old_date']),
      newDate: _parseDate(json['new_date']),
      changedBy: json['changed_by'] ?? '',
      requestSent: json['request_sent'] ?? false,
    );
  }

  static DateTime _parseDate(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is String) {
      // Try ISO format first
      try {
        return DateTime.parse(value);
      } catch (_) {
        // Try YYYY-MM-DD format
        final parts = value.split('-');
        if (parts.length == 3) {
          return DateTime(
            int.tryParse(parts[0]) ?? 2024,
            int.tryParse(parts[1]) ?? 1,
            int.tryParse(parts[2]) ?? 1,
          );
        }
      }
    }
    return DateTime.now();
  }
}

/// Model for daily sales status counts - fetched from backend for accuracy
class DailySalesStatusCounts {
  final int pendingCount;
  final int approvedCount;
  final int totalCount;
  final double pendingAmount;
  final double approvedAmount;
  final double totalAmount;

  DailySalesStatusCounts({
    required this.pendingCount,
    required this.approvedCount,
    required this.totalCount,
    required this.pendingAmount,
    required this.approvedAmount,
    required this.totalAmount,
  });

  int get rejectedCount => totalCount - pendingCount - approvedCount;
}
