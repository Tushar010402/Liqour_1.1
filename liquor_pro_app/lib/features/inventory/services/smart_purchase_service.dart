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
import '../models/ai_purchase_models.dart';

/// Service for the Smart AI Purchase extraction endpoint.
/// Calls POST /api/inventory/purchases/smart-purchase/extract
class SmartPurchaseService {
  final AuthService _authService;

  SmartPurchaseService(this._authService);

  /// Extract purchase items from invoice images using AI.
  ///
  /// Returns [SmartPurchaseResult] with matched items, vendor info, and totals.
  Future<ApiResponse<SmartPurchaseResult>> extractFromInvoice({
    required List<File> images,
    required String shopId,
    String? vendorId,
    DateTime? invoiceDate,
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

      // Phase 1: Compress
      onProgress?.call(0, 3, 'Compressing images...');

      if (kDebugMode) {
        Logger.info('SmartPurchaseService: Starting extraction');
        Logger.debug('   Images: ${images.length}');
        Logger.debug('   Shop: $shopId');
        if (vendorId != null) Logger.debug('   Vendor: $vendorId');
      }

      final compressedImages = await ImageCompressor.compressImages(
        images,
        quality: 90,
        maxWidth: 2048,
        maxHeight: 2048,
      );

      // Phase 2: Upload
      onProgress?.call(1, 3, 'Uploading images...');

      final url = '${ApiConfig.baseUrl}/api/inventory/purchases/smart-purchase/extract';
      final request = http.MultipartRequest('POST', Uri.parse(url));

      request.headers['Authorization'] = 'Bearer $token';
      request.headers['X-Tenant-ID'] = tenantId;

      request.fields['shop_id'] = shopId;
      if (vendorId != null && vendorId.isNotEmpty) {
        request.fields['vendor_id'] = vendorId;
      }
      if (invoiceDate != null) {
        request.fields['invoice_date'] = invoiceDate.toIso8601String().split('T')[0];
      }

      for (int i = 0; i < compressedImages.length; i++) {
        final file = compressedImages[i];
        request.files.add(
          await http.MultipartFile.fromPath(
            'images',
            file.path,
            filename: 'image_${i + 1}.jpg',
            contentType: http_parser.MediaType.parse('image/jpeg'),
          ),
        );
      }

      if (kDebugMode) {
        Logger.debug('SmartPurchaseService: Sending to $url');
      }

      // Phase 3: Wait for AI processing
      onProgress?.call(2, 3, 'AI is reading your invoice...');

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 120),
      );
      final response = await http.Response.fromStream(streamedResponse);

      await ImageCompressor.cleanupTempFiles(compressedImages);

      if (kDebugMode) {
        Logger.debug('SmartPurchaseService: Response ${response.statusCode}');
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        final result = SmartPurchaseResult.fromJson(data);

        onProgress?.call(3, 3, 'Complete!');

        if (kDebugMode) {
          Logger.info('SmartPurchaseService: Done');
          Logger.debug('   Status: ${result.status}');
          Logger.debug('   Items: ${result.items.length}');
          Logger.debug('   Matched: ${result.validation?.matchedItems ?? 0}');
          Logger.debug('   Low confidence: ${result.validation?.lowConfidenceItems ?? 0}');
          Logger.debug('   Not found: ${result.validation?.notFoundItems ?? 0}');
          if (result.matchedVendorName != null) {
            Logger.debug('   Vendor: ${result.matchedVendorName} (${(result.vendorConfidence * 100).toInt()}%)');
          }
        }

        return ApiResponse.success(result);
      } else {
        final errorMessage = _parseErrorMessage(response);

        if (kDebugMode) {
          Logger.error('SmartPurchaseService: Error $errorMessage');
          Logger.debug('   Status: ${response.statusCode}');
        }

        return ApiResponse.error(error: errorMessage);
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        Logger.error('SmartPurchaseService: Exception $e');
      }
      AppLogger.error('Smart Purchase extraction error', e, stackTrace);

      String userMessage;
      final msg = e.toString();
      if (msg.contains('SocketException') || msg.contains('Connection')) {
        userMessage = 'No internet connection. Please check your network.';
      } else if (msg.contains('TimeoutException') || msg.contains('timeout')) {
        userMessage = 'Request timed out. Please try again.';
      } else if (msg.contains('FormatException')) {
        userMessage = 'Server returned invalid response. Please try again.';
      } else {
        userMessage = 'Error processing invoice. Please try again.';
      }

      return ApiResponse.error(error: userMessage);
    }
  }

  String _parseErrorMessage(http.Response response) {
    final isHtml = response.body.trim().startsWith('<') ||
        response.body.contains('<!DOCTYPE') ||
        response.body.contains('<html');

    if (isHtml) {
      switch (response.statusCode) {
        case 502: return 'Server is temporarily unavailable. Please try again.';
        case 503: return 'Service under maintenance. Please try again later.';
        case 504: return 'Server took too long. Please try again.';
        case 500: return 'Server error. Please try again.';
        case 404: return 'Smart Purchase feature not available. Please update.';
        case 401: return 'Session expired. Please login again.';
        case 403: return 'Access denied. Check your permissions.';
        default: return 'Server error (${response.statusCode}). Please try again.';
      }
    }

    try {
      final error = json.decode(response.body);
      return error['error'] ?? error['message'] ?? 'Failed to process invoice';
    } catch (_) {
      return 'Server error. Please try again.';
    }
  }
}
