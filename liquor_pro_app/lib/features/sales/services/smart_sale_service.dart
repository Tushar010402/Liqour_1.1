import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' as http_parser;
import 'dart:convert';
import '../../../core/config/api_config.dart';
import '../../../core/models/api_response.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/utils/logger.dart';
import '../../../core/utils/image_compressor.dart';
import '../models/smart_sale_models.dart';

/// Smart Sale Service - AI-powered automated sales entry
///
/// This service handles:
/// 1. Uploading receipt/invoice images to backend
/// 2. Backend processes images with AI vision capabilities
/// 3. Backend validates extracted data against inventory
/// 4. Backend auto-creates sales entries
/// 5. Returns results to frontend for display
class SmartSaleService {
  final AuthService _authService;

  SmartSaleService(this._authService);

  /// Process Smart Sale images
  ///
  /// Sends images along with metadata (shop, date, category, size) to backend.
  /// Backend will:
  /// 1. Use AI vision to extract data from images
  /// 2. Validate against inventory (stock, rates, products)
  /// 3. Auto-create daily sales entries
  /// 4. Return processing results
  ///
  /// Parameters:
  /// - images: List of receipt/invoice image files (max 5)
  /// - shopId: Selected shop ID
  /// - shopName: Selected shop name (for validation)
  /// - date: Selected date for the sale
  /// - category: 'beer' or 'non_beer'
  /// - size: Selected size (for non-beer only, e.g., '180ML', '750ML')
  ///
  /// Returns SmartSaleResult with:
  /// - Processing status
  /// - Extracted items with validation status
  /// - Created sale record ID (if successful)
  /// - Any validation errors
  Future<ApiResponse<SmartSaleResult>> processSmartSale({
    required List<File> images,
    required String shopId,
    required String shopName,
    required DateTime date,
    required String category,
    String? size,
    Map<String, String>? extraFields,
    Function(int current, int total, String status)? onProgress,
  }) async {
    try {
      if (images.isEmpty) {
        return ApiResponse.error(error: 'No images provided');
      }

      if (images.length > 5) {
        return ApiResponse.error(error: 'Maximum 5 images allowed');
      }

      final token = await _authService.getToken();
      if (token == null) {
        return ApiResponse.error(error: 'Not authenticated');
      }

      final tenantId = await _authService.getTenantId();
      if (tenantId == null) {
        return ApiResponse.error(error: 'Tenant ID not found');
      }

      // Phase 1: Compress images
      onProgress?.call(0, 3, 'Compressing images...');
      if (kDebugMode) {
        Logger.info('SmartSaleService: Starting Smart Sale processing');
        Logger.debug('   Images: ${images.length}');
        Logger.debug('   Shop: $shopName ($shopId)');
        Logger.debug('   Date: ${date.toIso8601String().split('T')[0]}');
        Logger.debug('   Category: $category');
        if (size != null) Logger.debug('   Size: $size');
      }

      final List<File> compressedImages = await ImageCompressor.compressImages(
        images,
        quality: 90, // Higher quality for OCR
        maxWidth: 2048,
        maxHeight: 2048,
      );

      // Phase 2: Upload to backend
      onProgress?.call(1, 3, 'Uploading images...');

      final url = '${ApiConfig.baseUrl}/api/sales/smart-sale/process';
      final request = http.MultipartRequest('POST', Uri.parse(url));

      // Add auth headers
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['X-Tenant-ID'] = tenantId;

      // Add metadata fields
      request.fields['shop_id'] = shopId;
      request.fields['shop_name'] = shopName;
      request.fields['date'] = date.toIso8601String().split('T')[0]; // YYYY-MM-DD
      request.fields['category'] = category;
      if (size != null && size.isNotEmpty) {
        request.fields['size'] = size;
      }
      if (extraFields != null) {
        request.fields.addAll(extraFields);
      }

      // Add images
      for (int i = 0; i < compressedImages.length; i++) {
        final file = compressedImages[i];
        final fileName = 'image_${i + 1}.jpg';
        final mimeType = 'image/jpeg';

        request.files.add(
          await http.MultipartFile.fromPath(
            'images',
            file.path,
            filename: fileName,
            contentType: http_parser.MediaType.parse(mimeType),
          ),
        );
      }

      if (kDebugMode) {
        Logger.debug('SmartSaleService: Sending request to $url');
      }

      // Phase 3: Wait for processing
      onProgress?.call(2, 3, 'Processing with AI...');

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 120), // Allow up to 2 minutes for AI processing
      );
      final response = await http.Response.fromStream(streamedResponse);

      // Cleanup temp files
      await ImageCompressor.cleanupTempFiles(compressedImages);

      if (kDebugMode) {
        Logger.debug('SmartSaleService: Response status ${response.statusCode}');
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);

        if (kDebugMode) {
          Logger.debug('SmartSaleService: Raw response keys: ${data.keys.toList()}');
          Logger.debug('SmartSaleService: Raw status: ${data['status']}');
          Logger.debug('SmartSaleService: Raw message: ${data['message']}');
          Logger.debug('SmartSaleService: Raw items count: ${(data['extracted_items'] as List?)?.length ?? 0}');

          // Log first 3 items for debugging - show ALL keys to find system stock/rate fields
          final items = data['extracted_items'] as List? ?? [];
          for (int i = 0; i < items.length && i < 3; i++) {
            final item = items[i] as Map<String, dynamic>;
            Logger.debug('Item $i KEYS: ${item.keys.toList()}');
            Logger.debug('Item $i STOCK: opening=${item['opening_stock']}, system_opening=${item['system_opening']}, db_stock=${item['db_stock']}, system_stock=${item['system_stock']}');
            Logger.debug('Item $i RATE: rate=${item['rate']}, system_rate=${item['system_rate']}, db_rate=${item['db_rate']}, inventory_rate=${item['inventory_rate']}');
          }
        }

        final result = SmartSaleResult.fromJson(data);

        onProgress?.call(3, 3, 'Complete!');

        if (kDebugMode) {
          Logger.info('SmartSaleService: Processing complete');
          Logger.debug('   Status: ${result.status}');
          Logger.debug('   Items extracted: ${result.extractedItems.length}');
          Logger.debug('   Total amount: ${result.totalAmount}');
          Logger.debug('   Valid items: ${result.validItemCount}');
          Logger.debug('   Invalid items: ${result.invalidItemCount}');
          if (result.saleRecordId != null) {
            Logger.debug('   Sale Record ID: ${result.saleRecordId}');
          }
          if (result.validation != null) {
            Logger.debug('   Validation: shop=${result.validation!.shopNameMatch}, date=${result.validation!.dateMatch}');
          }
          // Log parsed items with system stock/rate info
          for (int i = 0; i < result.extractedItems.length && i < 3; i++) {
            final item = result.extractedItems[i];
            Logger.debug('   Parsed Item ${i+1}: ${item.brandName} | OCR_Open:${item.openingStock} | DB_Stock:${item.dbStock} | OCR_Rate:${item.rate} | SYS_Rate:${item.inventoryRate} | Rcpt:${item.receiptQty} | Qty:${item.quantity}');
          }
        }

        return ApiResponse.success(result);
      } else {
        // Handle non-2xx responses with proper error messages
        String errorMessage;

        // Check if response is HTML (server error pages)
        final isHtml = response.body.trim().startsWith('<') ||
                       response.body.contains('<!DOCTYPE') ||
                       response.body.contains('<html');

        if (isHtml) {
          // Server returned HTML error page
          if (kDebugMode) {
            Logger.error('SmartSaleService: Server returned HTML error page');
            Logger.debug('   Status: ${response.statusCode}');
          }

          // Map status codes to user-friendly messages
          switch (response.statusCode) {
            case 502:
              errorMessage = 'Server is temporarily unavailable. Please try again in a moment.';
              break;
            case 503:
              errorMessage = 'Service is under maintenance. Please try again later.';
              break;
            case 504:
              errorMessage = 'Server took too long to respond. Please try again.';
              break;
            case 500:
              errorMessage = 'Server error occurred. Please try again.';
              break;
            case 404:
              errorMessage = 'Smart Sale feature is not available. Please contact support.';
              break;
            case 401:
              errorMessage = 'Session expired. Please login again.';
              break;
            case 403:
              errorMessage = 'Access denied. Please check your permissions.';
              break;
            default:
              errorMessage = 'Server error (${response.statusCode}). Please try again.';
          }
        } else {
          // Try to parse JSON error
          try {
            final error = json.decode(response.body);
            final rawError = error['error'] ?? error['message'] ?? 'Failed to process Smart Sale';
            // Sanitize error message - don't expose internal details to users
            errorMessage = _sanitizeErrorMessage(rawError, response.statusCode);
          } catch (_) {
            errorMessage = 'Server error. Please try again.';
          }
        }

        if (kDebugMode) {
          Logger.error('SmartSaleService: Error - $errorMessage');
          Logger.debug('   Status Code: ${response.statusCode}');
        }

        return ApiResponse.error(error: errorMessage);
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        Logger.error('SmartSaleService: Exception - $e');
      }
      AppLogger.error('Smart Sale processing error', e, stackTrace);

      // Provide user-friendly error messages for common exceptions
      String userMessage;
      if (e.toString().contains('SocketException') || e.toString().contains('Connection')) {
        userMessage = 'No internet connection. Please check your network.';
      } else if (e.toString().contains('TimeoutException') || e.toString().contains('timeout')) {
        userMessage = 'Request timed out. Please try again.';
      } else if (e.toString().contains('FormatException')) {
        userMessage = 'Server returned invalid response. Please try again.';
      } else {
        userMessage = 'Error processing Smart Sale. Please try again.';
      }

      return ApiResponse.error(error: userMessage);
    }
  }

  /// Apply (confirm) a reviewed Smart Sale
  ///
  /// Called after user reviews OCR results and edits items.
  /// Creates the daily sale record + deducts stock + learns aliases.
  Future<ApiResponse<Map<String, dynamic>>> applySmartSale({
    required String shopId,
    required String date,
    required String category,
    String? size,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        return ApiResponse.error(error: 'Not authenticated');
      }

      final tenantId = await _authService.getTenantId();
      if (tenantId == null) {
        return ApiResponse.error(error: 'Tenant ID not found');
      }

      final body = {
        'shop_id': shopId,
        'date': date,
        'category': category,
        if (size != null) 'size': size,
        'items': items,
      };

      final url = '${ApiConfig.baseUrl}/api/sales/smart-sale/apply';

      if (kDebugMode) {
        Logger.debug('SmartSaleService.applySmartSale: Applying ${items.length} items');
        Logger.debug('   URL: $url');
        Logger.debug('   Shop: $shopId, Date: $date, Category: $category, Size: $size');
        Logger.debug('   Token: ${token.substring(0, 20)}...');
        Logger.debug('   TenantID: $tenantId');
      }
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'X-Tenant-ID': tenantId,
        },
        body: json.encode(body),
      );

      if (kDebugMode) {
        Logger.debug('SmartSaleService.applySmartSale: Response ${response.statusCode}');
        Logger.debug('SmartSaleService.applySmartSale: Body: ${response.body.length > 500 ? response.body.substring(0, 500) : response.body}');
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        if (kDebugMode) {
          Logger.info('SmartSaleService.applySmartSale: Success - Sale created');
        }
        return ApiResponse.success(data);
      } else {
        String errorMessage;
        try {
          final error = json.decode(response.body);
          errorMessage = _sanitizeErrorMessage(
            error['error'] ?? error['message'] ?? 'Failed to apply sale',
            response.statusCode,
          );
        } catch (_) {
          errorMessage = _getGenericErrorMessage(response.statusCode);
        }
        return ApiResponse.error(error: errorMessage);
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        Logger.error('SmartSaleService.applySmartSale: Exception - $e');
      }
      AppLogger.error('Apply Smart Sale error', e, stackTrace);
      return ApiResponse.error(error: _sanitizeErrorMessage('$e', 0));
    }
  }

  /// Get Smart Sale processing history
  /// Returns list of recent Smart Sale submissions
  Future<ApiResponse<List<SmartSaleRecord>>> getSmartSaleHistory({
    String? shopId,
    DateTime? startDate,
    DateTime? endDate,
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
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
        queryParams['start_date'] = startDate.toIso8601String().split('T')[0];
      }
      if (endDate != null) {
        queryParams['end_date'] = endDate.toIso8601String().split('T')[0];
      }

      final uri = Uri.parse('${ApiConfig.baseUrl}/api/sales/smart-sale/history')
          .replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'X-Tenant-ID': tenantId,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final records = (data['records'] as List? ?? [])
            .map((r) => SmartSaleRecord.fromJson(r))
            .toList();
        return ApiResponse.success(records);
      } else {
        final error = json.decode(response.body);
        return ApiResponse.error(error: error['error'] ?? 'Failed to fetch history');
      }
    } catch (e) {
      AppLogger.error('Error fetching Smart Sale history: $e');
      return ApiResponse.error(error: 'Error fetching history: $e');
    }
  }

  /// Retry failed Smart Sale processing
  Future<ApiResponse<SmartSaleResult>> retrySmartSale(String smartSaleId) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        return ApiResponse.error(error: 'Not authenticated');
      }

      final tenantId = await _authService.getTenantId();
      if (tenantId == null) {
        return ApiResponse.error(error: 'Tenant ID not found');
      }

      final url = '${ApiConfig.baseUrl}/api/sales/smart-sale/$smartSaleId/retry';
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'X-Tenant-ID': tenantId,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return ApiResponse.success(SmartSaleResult.fromJson(data));
      } else {
        final error = json.decode(response.body);
        return ApiResponse.error(error: error['error'] ?? 'Failed to retry');
      }
    } catch (e) {
      return ApiResponse.error(error: 'Error retrying: $e');
    }
  }

  /// Submit finalized Smart Sale with payment breakdown and expenses
  ///
  /// After user reviews items and enters payment breakdown,
  /// this method submits the finalized sale to the backend.
  ///
  /// Parameters (in request map):
  /// - shop_id: Selected shop ID
  /// - shop_name: Selected shop name
  /// - date: Sale date (YYYY-MM-DD)
  /// - items: List of sale items with edited quantities
  /// - total_amount: Total sale amount
  /// - cash_amount: Cash payment amount
  /// - card_amount: Card payment amount
  /// - upi_amount: UPI payment amount
  /// - credit_amount: Credit payment amount
  /// - expenses: List of expenses [{header, amount}]
  /// - notes: Optional notes
  /// - smart_sale_id: Original Smart Sale record ID (if any)
  /// - size: Selected/detected size
  Future<ApiResponse<Map<String, dynamic>>> submitFinalizedSale(
    Map<String, dynamic> request,
  ) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        return ApiResponse.error(error: 'Not authenticated');
      }

      final tenantId = await _authService.getTenantId();
      if (tenantId == null) {
        return ApiResponse.error(error: 'Tenant ID not found');
      }

      if (kDebugMode) {
        final totalAmount = request['total_amount'] ?? 0;
        final totalExpenses = request['total_expense_amount'] ?? 0;
        final totalPayment = (request['cash_amount'] ?? 0) +
                            (request['card_amount'] ?? 0) +
                            (request['upi_amount'] ?? 0) +
                            (request['credit_amount'] ?? 0);

        Logger.debug('SmartSaleService.submitFinalizedSale: Submitting finalized sale');
        Logger.debug('   Shop: ${request['shop_name']} (${request['shop_id']})');
        Logger.debug('   Date: ${request['date']}');
        Logger.debug('   Items: ${(request['items'] as List?)?.length ?? 0}');
        Logger.debug('   Items Total:    ₹$totalAmount');
        Logger.debug('   Expenses:       ₹$totalExpenses (${(request['expenses'] as List?)?.length ?? 0} items)');
        Logger.debug('   Cash (adjusted):₹${request['cash_amount']} (includes expenses)');
        Logger.debug('   Card:           ₹${request['card_amount']}');
        Logger.debug('   UPI:            ₹${request['upi_amount']}');
        Logger.debug('   Credit:         ₹${request['credit_amount']}');
        Logger.debug('   Total Payment:  ₹$totalPayment');
        if ((totalPayment - (totalAmount as num)).abs() < 0.01) {
          Logger.info('   BACKEND VALIDATION WILL PASS: payment == total_amount');
        } else {
          Logger.warning('   WARNING: payment ($totalPayment) != total_amount ($totalAmount)');
        }
      }

      final url = '${ApiConfig.baseUrl}/api/sales/smart-sale/finalize';
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'X-Tenant-ID': tenantId,
        },
        body: json.encode(request),
      );

      if (kDebugMode) {
        Logger.debug('SmartSaleService.submitFinalizedSale: Response status ${response.statusCode}');
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);

        if (kDebugMode) {
          Logger.info('SmartSaleService.submitFinalizedSale: Success');
          Logger.debug('   Sale ID: ${data['sale_id'] ?? data['id']}');
        }

        return ApiResponse.success(data);
      } else {
        final error = json.decode(response.body);
        final errorMessage = error['error'] ?? error['message'] ?? 'Submission failed';

        if (kDebugMode) {
          Logger.error('SmartSaleService.submitFinalizedSale: Error - $errorMessage');
          Logger.debug('   Response: ${response.body}');
        }

        return ApiResponse.error(error: errorMessage);
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        Logger.error('SmartSaleService.submitFinalizedSale: Exception - $e');
      }
      AppLogger.error('Submit finalized sale error', e, stackTrace);
      return ApiResponse.error(error: _sanitizeErrorMessage('$e', 0));
    }
  }

  /// Sanitize error messages to hide internal/technical details from users
  /// This is a security and UX best practice
  String _sanitizeErrorMessage(String rawError, int statusCode) {
    final lowerError = rawError.toLowerCase();

    // List of sensitive patterns that should never be shown to users
    final sensitivePatterns = [
      'api_key', 'api-key', 'apikey',
      'openai', 'gpt', 'claude', 'gemini', 'anthropic',
      'secret', 'token', 'credential', 'password',
      'internal server', 'stack trace', 'traceback',
      'sql', 'database error', 'connection refused',
      'null pointer', 'undefined', 'exception:',
      'client not available', 'not configured',
      'environment variable', 'env var',
    ];

    // Check if error contains any sensitive patterns
    for (final pattern in sensitivePatterns) {
      if (lowerError.contains(pattern)) {
        // Return a generic user-friendly message based on status code
        return _getGenericErrorMessage(statusCode);
      }
    }

    // If error is too technical (contains code-like patterns), sanitize it
    if (rawError.contains('::') ||
        rawError.contains('()') ||
        rawError.contains('_') && rawError.contains('.') ||
        rawError.length > 150) {
      return _getGenericErrorMessage(statusCode);
    }

    // Error seems safe to show, but clean it up
    return rawError
        .replaceAll(RegExp(r'\s+'), ' ') // Normalize whitespace
        .trim();
  }

  /// Get generic user-friendly error message based on HTTP status code
  String _getGenericErrorMessage(int statusCode) {
    switch (statusCode) {
      case 400:
        return 'Invalid request. Please check your input and try again.';
      case 401:
        return 'Session expired. Please login again.';
      case 403:
        return 'Access denied. Please check your permissions.';
      case 404:
        return 'Service not available. Please try again later.';
      case 408:
        return 'Request timed out. Please try again.';
      case 429:
        return 'Too many requests. Please wait a moment and try again.';
      case 500:
        return 'Service temporarily unavailable. Please try again in a moment.';
      case 502:
      case 503:
        return 'Server is undergoing maintenance. Please try again later.';
      case 504:
        return 'Server took too long to respond. Please try again.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }
}
