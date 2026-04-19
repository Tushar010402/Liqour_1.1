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
import '../models/ai_stock_models.dart';

/// Service for the Smart AI Stock Setup extraction endpoint.
/// Calls POST /api/inventory/stocks/smart-setup/extract
class SmartStockService {
  final AuthService _authService;

  SmartStockService(this._authService);

  /// Extract stock items from stock register images using AI.
  ///
  /// Returns [SmartStockResult] with matched items and quantities.
  Future<ApiResponse<SmartStockResult>> extractFromStockRegister({
    required List<File> images,
    required String shopId,
    String? category,
    String? categoryId,
    String? size,
    String? stockColumn,
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
        Logger.info('SmartStockService: Starting extraction');
        Logger.debug('   Images: ${images.length}');
        Logger.debug('   Shop: $shopId');
        if (category != null) Logger.debug('   Category: $category');
        if (categoryId != null) Logger.debug('   CategoryId: $categoryId');
        if (size != null) Logger.debug('   Size: $size');
        if (stockColumn != null) Logger.debug('   StockColumn: $stockColumn');
      }

      final compressedImages = await ImageCompressor.compressImages(
        images,
        quality: 90,
        maxWidth: 2048,
        maxHeight: 2048,
      );

      // Phase 2: Upload
      onProgress?.call(1, 3, 'Uploading images...');

      final url = '${ApiConfig.baseUrl}/api/inventory/stocks/smart-setup/extract';
      final request = http.MultipartRequest('POST', Uri.parse(url));

      request.headers['Authorization'] = 'Bearer $token';
      request.headers['X-Tenant-ID'] = tenantId;

      request.fields['shop_id'] = shopId;
      if (category != null && category.isNotEmpty) {
        request.fields['category'] = category;
      }
      if (categoryId != null && categoryId.isNotEmpty) {
        request.fields['category_id'] = categoryId;
      }
      if (size != null && size.isNotEmpty) {
        request.fields['size'] = size;
      }
      if (stockColumn != null && stockColumn.isNotEmpty) {
        request.fields['stock_column'] = stockColumn;
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
        Logger.debug('SmartStockService: Sending to $url');
      }

      // Phase 3: Wait for AI processing
      onProgress?.call(2, 3, 'AI is reading your stock register...');

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 120),
      );
      final response = await http.Response.fromStream(streamedResponse);

      await ImageCompressor.cleanupTempFiles(compressedImages);

      if (kDebugMode) {
        Logger.debug('SmartStockService: Response ${response.statusCode}');
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        final result = SmartStockResult.fromJson(data);

        onProgress?.call(3, 3, 'Complete!');

        if (kDebugMode) {
          Logger.info('SmartStockService: Done');
          Logger.debug('   Status: ${result.status}');
          Logger.debug('   Items: ${result.items.length}');
          Logger.debug('   Matched: ${result.validation?.matchedItems ?? 0}');
          Logger.debug('   Low confidence: ${result.validation?.lowConfidenceItems ?? 0}');
          Logger.debug('   Not found: ${result.validation?.notFoundItems ?? 0}');
        }

        return ApiResponse.success(result);
      } else {
        final errorMessage = _parseErrorMessage(response);

        if (kDebugMode) {
          Logger.error('SmartStockService: Error $errorMessage');
          Logger.debug('   Status: ${response.statusCode}');
        }

        return ApiResponse.error(error: errorMessage);
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        Logger.error('SmartStockService: Exception $e');
      }
      AppLogger.error('Smart Stock extraction error', e, stackTrace);

      String userMessage;
      final msg = e.toString();
      if (msg.contains('SocketException') || msg.contains('Connection')) {
        userMessage = 'No internet connection. Please check your network.';
      } else if (msg.contains('TimeoutException') || msg.contains('timeout')) {
        userMessage = 'Request timed out. Please try again.';
      } else if (msg.contains('FormatException')) {
        userMessage = 'Server returned invalid response. Please try again.';
      } else {
        userMessage = 'Error processing stock register. Please try again.';
      }

      return ApiResponse.error(error: userMessage);
    }
  }

  /// Apply confirmed stock setup items via the dedicated backend endpoint.
  /// Uses POST /api/inventory/stocks/smart-setup/apply which runs in a single
  /// transaction and creates proper opening_stock_setup history entries.
  Future<ApiResponse<Map<String, dynamic>>> applyStockSetup({
    required String shopId,
    required List<Map<String, dynamic>> items,
    String? notes,
    String? categoryId,
    String? size,
    String? stockColumn,
    String? sessionId,
    List<String>? imageUrls,
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

      final url = '${ApiConfig.baseUrl}/api/inventory/stocks/smart-setup/apply';

      if (kDebugMode) {
        Logger.info('SmartStockService: Applying ${items.length} stock items');
        Logger.debug('   Shop: $shopId');
        for (final item in items) {
          Logger.debug('   Item: $item');
        }
      }

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'X-Tenant-ID': tenantId,
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'shop_id': shopId,
          'items': items,
          if (notes != null) 'notes': notes,
          if (categoryId != null) 'category_id': categoryId,
          if (size != null) 'size': size,
          if (stockColumn != null) 'stock_column': stockColumn,
          if (sessionId != null) 'session_id': sessionId,
          if (imageUrls != null) 'image_urls': imageUrls,
        }),
      ).timeout(const Duration(seconds: 30));

      if (kDebugMode) {
        Logger.debug('SmartStockService: Apply response ${response.statusCode}');
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);

        if (kDebugMode) {
          Logger.info('SmartStockService: Apply done - ${data['message']}');
        }

        return ApiResponse<Map<String, dynamic>>(
          success: true,
          data: data is Map<String, dynamic> ? data : {},
          message: data['message'] ?? 'Stock set successfully',
        );
      } else {
        final errorMessage = _parseErrorMessage(response);
        return ApiResponse.error(error: errorMessage);
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        Logger.error('SmartStockService: Apply exception $e');
      }
      AppLogger.error('Smart Stock apply error', e, stackTrace);

      String userMessage;
      final msg = e.toString();
      if (msg.contains('SocketException') || msg.contains('Connection')) {
        userMessage = 'No internet connection. Please check your network.';
      } else if (msg.contains('TimeoutException') || msg.contains('timeout')) {
        userMessage = 'Request timed out. Please try again.';
      } else {
        userMessage = 'Error setting stock. Please try again.';
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
        case 404: return 'AI Stock Setup feature not available. Please update.';
        case 401: return 'Session expired. Please login again.';
        case 403: return 'Access denied. Check your permissions.';
        default: return 'Server error (${response.statusCode}). Please try again.';
      }
    }

    try {
      final error = json.decode(response.body);
      return error['error'] ?? error['message'] ?? 'Failed to process stock register';
    } catch (_) {
      return 'Server error. Please try again.';
    }
  }
}
