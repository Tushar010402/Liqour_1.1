import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' as http;
import 'dart:convert';
import '../../../core/config/api_config.dart';
import '../../../core/models/api_response.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/utils/app_logger.dart';
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
        print('🌐 DailySalesService: Creating record - ${request.recordDate}, Shop: ${request.shopId}, Total: ${request.totalSalesAmount}');
      }

      final token = await _authService.getToken();
      if (token == null) {
        if (kDebugMode) print('❌ DailySalesService: Authentication failed');
        return ApiResponse.error(error: 'Not authenticated');
      }

      final tenantId = await _authService.getTenantId();
      if (tenantId == null) {
        if (kDebugMode) print('❌ DailySalesService: Tenant ID not found');
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
        print('🌐 DailySalesService: Response - Status: ${response.statusCode}');
      }

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = json.decode(response.body);
        final record = DailySalesRecord.fromJson(data['data'] ?? data);
        if (kDebugMode) print('✅ DailySalesService: Record created - ID: ${record.id}');
        return ApiResponse.success(record);
      } else {
        final error = json.decode(response.body);
        if (kDebugMode) print('❌ DailySalesService: Failed (${response.statusCode}) - ${error['error']}');
        AppLogger.error('Daily sales API error: ${error}');
        return ApiResponse.error(error: error['error'] ?? error['errors']?.toString() ?? 'Failed to create daily sales record');
      }
    } catch (e, stackTrace) {
      if (kDebugMode) print('❌ DailySalesService: Exception - $e');
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
        final recordsData = data['records'] as List;
        final records = recordsData
            .map((record) => DailySalesRecord.fromJson(record))
            .toList();
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
        print('🔍 UPDATE DAILY SALES REQUEST:');
        print('   URL: ${ApiConfig.baseUrl}/api/sales/daily-sales/$id');
        print('   shop_id: ${requestBody['shop_id']}');
        print('   record_date: ${requestBody['record_date']}');
        print('   total_sales_amount: ${requestBody['total_sales_amount']}');
        print('   items count: ${(requestBody['items'] as List?)?.length ?? 0}');
        print('   Full body: ${json.encode(requestBody)}');
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
        print('❌ UPDATE FAILED - Response: ${response.body}');
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
        print('🔍 DailySalesService: Validating ${items.length} products for shop $shopId');
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
        print('🔍 DailySalesService: Validation response - ${response.statusCode}');
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final result = BatchValidationResult.fromJson(data);
        if (kDebugMode) {
          print('✅ DailySalesService: Validation complete - ${result.validCount} valid, ${result.invalidCount} invalid');
        }
        return ApiResponse.success(result);
      } else {
        final error = json.decode(response.body);
        if (kDebugMode) print('❌ DailySalesService: Validation failed - ${error['error']}');
        return ApiResponse.error(error: error['error'] ?? 'Failed to validate products');
      }
    } catch (e) {
      if (kDebugMode) print('❌ DailySalesService: Validation exception - $e');
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
        print('📸 DailySalesService: Uploading image - ${imageFile.path}');
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
        print('📸 DailySalesService: Upload response - ${response.statusCode}');
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);

        if (kDebugMode) {
          print('📸 DailySalesService: Response body - ${response.body}');
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
          if (kDebugMode) {
            print('✅ DailySalesService: Image uploaded - $imageUrl');
          }
          return ApiResponse.success(imageUrl);
        } else {
          if (kDebugMode) {
            print('❌ DailySalesService: No URL in response - $data');
          }
          return ApiResponse.error(error: 'No URL returned from upload');
        }
      } else {
        final error = json.decode(response.body);
        if (kDebugMode) {
          print('❌ DailySalesService: Upload failed - ${error['error']}');
        }
        return ApiResponse.error(error: error['error'] ?? 'Failed to upload image');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ DailySalesService: Upload exception - $e');
      }
      AppLogger.error('Error uploading sales image: $e');
      return ApiResponse.error(error: 'Error uploading image: $e');
    }
  }

  /// Upload multiple images and return list of URLs
  Future<ApiResponse<List<String>>> uploadSalesImages(List<File> imageFiles) async {
    try {
      if (kDebugMode) {
        print('📸 DailySalesService: Uploading ${imageFiles.length} images');
      }

      final List<String> uploadedUrls = [];

      for (int i = 0; i < imageFiles.length; i++) {
        final result = await uploadSalesImage(imageFiles[i]);

        if (result.success && result.data != null) {
          uploadedUrls.add(result.data!);
          if (kDebugMode) {
            print('📸 DailySalesService: Image ${i + 1}/${imageFiles.length} uploaded');
          }
        } else {
          // If any upload fails, return error
          return ApiResponse.error(error: result.error ?? 'Failed to upload image ${i + 1}');
        }
      }

      if (kDebugMode) {
        print('✅ DailySalesService: All ${uploadedUrls.length} images uploaded successfully');
      }
      return ApiResponse.success(uploadedUrls);
    } catch (e) {
      if (kDebugMode) {
        print('❌ DailySalesService: Upload batch exception - $e');
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
        print('🗑️ DailySalesService: Deleting record $id');
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
        print('🗑️ DailySalesService: Delete response - ${response.statusCode}');
      }

      if (response.statusCode == 200 || response.statusCode == 204) {
        if (kDebugMode) print('✅ DailySalesService: Record deleted successfully');
        return ApiResponse.success(null);
      } else {
        final error = json.decode(response.body);
        if (kDebugMode) print('❌ DailySalesService: Delete failed - ${error['error']}');
        return ApiResponse.error(error: error['error'] ?? 'Failed to delete record');
      }
    } catch (e) {
      if (kDebugMode) print('❌ DailySalesService: Delete exception - $e');
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
        print('🤖 DailySalesService: Fetching AI validation for record $recordId');
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
        print('🤖 DailySalesService: Validation response - ${response.statusCode}');
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // Backend may return directly or wrapped in 'data'
        final validationData = data['data'] ?? data;
        final result = AIValidationResult.fromJson(validationData);
        if (kDebugMode) {
          print('✅ DailySalesService: Validation fetched - Status: ${result.status}, Mismatches: ${result.mismatchCount}');
        }
        return ApiResponse.success(result);
      } else if (response.statusCode == 404) {
        // No validation available yet (OCR not triggered or still processing)
        return ApiResponse.success(const AIValidationResult(status: 'pending'));
      } else {
        final error = json.decode(response.body);
        if (kDebugMode) print('❌ DailySalesService: Validation fetch failed - ${error['error']}');
        return ApiResponse.error(error: error['error'] ?? 'Failed to fetch validation');
      }
    } catch (e) {
      if (kDebugMode) print('❌ DailySalesService: Validation exception - $e');
      AppLogger.error('Error fetching AI validation: $e');
      return ApiResponse.error(error: 'Error fetching validation: $e');
    }
  }

  /// Trigger AI validation manually for a record (if not already done)
  Future<ApiResponse<void>> triggerValidation(String recordId) async {
    try {
      if (kDebugMode) {
        print('🤖 DailySalesService: Triggering AI validation for record $recordId');
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
        print('🤖 DailySalesService: Trigger response - ${response.statusCode}');
      }

      if (response.statusCode == 200 || response.statusCode == 202) {
        if (kDebugMode) print('✅ DailySalesService: Validation triggered successfully');
        return ApiResponse.success(null);
      } else {
        final error = json.decode(response.body);
        if (kDebugMode) print('❌ DailySalesService: Trigger failed - ${error['error']}');
        return ApiResponse.error(error: error['error'] ?? 'Failed to trigger validation');
      }
    } catch (e) {
      if (kDebugMode) print('❌ DailySalesService: Trigger exception - $e');
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
        print('📅 DailySalesService: Changing date for record $id to ${newDate.toIso8601String().split('T')[0]}');
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
        print('📅 DailySalesService: Change date response - ${response.statusCode}');
        if (response.statusCode != 200) {
          print('📅 DailySalesService: Response body - ${response.body}');
        }
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final result = ChangeDateResponse.fromJson(data);
        if (kDebugMode) {
          print('✅ DailySalesService: Date changed successfully');
          print('   Old date: ${result.oldDate}');
          print('   New date: ${result.newDate}');
        }
        return ApiResponse.success(result);
      } else {
        final error = json.decode(response.body);
        if (kDebugMode) print('❌ DailySalesService: Change date failed - ${error['error']}');
        return ApiResponse.error(error: error['error'] ?? 'Failed to change date');
      }
    } catch (e) {
      if (kDebugMode) print('❌ DailySalesService: Change date exception - $e');
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
        print('🔐 DailySalesService: Requesting revert OTP for record $recordId');
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
        print('🔐 DailySalesService: OTP request response - ${response.statusCode}');
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final result = RevertOtpResponse.fromJson(data);
        if (kDebugMode) {
          print('✅ DailySalesService: OTP sent - Email: ${result.emailSent}, Phone: ${result.phoneSent}');
        }
        return ApiResponse.success(result);
      } else {
        final error = json.decode(response.body);
        if (kDebugMode) print('❌ DailySalesService: OTP request failed - ${error['error']}');
        return ApiResponse.error(error: error['error'] ?? 'Failed to request OTP');
      }
    } catch (e) {
      if (kDebugMode) print('❌ DailySalesService: OTP request exception - $e');
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
        print('🔐 DailySalesService: Verifying OTPs and reverting record $recordId');
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
        print('🔐 DailySalesService: Revert response - ${response.statusCode}');
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (kDebugMode) print('✅ DailySalesService: Record reverted successfully');
        return ApiResponse.success(data as Map<String, dynamic>);
      } else {
        final error = json.decode(response.body);
        if (kDebugMode) print('❌ DailySalesService: Revert failed - ${error['error']}');
        return ApiResponse.error(error: error['error'] ?? 'Failed to revert record');
      }
    } catch (e) {
      if (kDebugMode) print('❌ DailySalesService: Revert exception - $e');
      AppLogger.error('Error reverting record: $e');
      return ApiResponse.error(error: 'Error reverting record: $e');
    }
  }

  /// Resend OTP for daily sales record revert - re-requests new OTPs
  Future<ApiResponse<RevertOtpResponse>> resendRevertOtp(String recordId) async {
    // Just call requestRevertOtp again to get new OTPs
    return requestRevertOtp(recordId);
  }

  /// Copy a rejected record to create a new draft
  /// Useful for recovering rejected records after fixes
  Future<ApiResponse<DailySalesRecord>> copyDailySalesRecord(String id) async {
    try {
      if (kDebugMode) {
        print('📋 DailySalesService: Copying record $id');
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
        print('📋 DailySalesService: Copy response - ${response.statusCode}');
      }

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = json.decode(response.body);
        final record = DailySalesRecord.fromJson(data['data'] ?? data);
        if (kDebugMode) print('✅ DailySalesService: Record copied - New ID: ${record.id}');
        return ApiResponse.success(record);
      } else {
        final error = json.decode(response.body);
        if (kDebugMode) print('❌ DailySalesService: Copy failed - ${error['error']}');
        return ApiResponse.error(error: error['error'] ?? 'Failed to copy record');
      }
    } catch (e) {
      if (kDebugMode) print('❌ DailySalesService: Copy exception - $e');
      AppLogger.error('Error copying daily sales record: $e');
      return ApiResponse.error(error: 'Error copying record: $e');
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
