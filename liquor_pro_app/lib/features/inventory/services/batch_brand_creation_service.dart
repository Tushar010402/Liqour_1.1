import '../../../core/models/api_response.dart';
import '../../../core/services/dio_api_service.dart';
import '../../../core/utils/app_logger.dart';
import '../models/batch_ocr_models.dart';
import '../models/brand_creation_result.dart';

/// Service for creating brands in batch from OCR deduplicated items
class BatchBrandCreationService {
  final DioApiService _apiService;

  BatchBrandCreationService(this._apiService);

  /// Create all brands from OCR deduplicated items
  Future<ApiResponse<BrandCreationResult>> createBrandsFromOCR({
    required List<DeduplicatedItem> items,
    required String shopId,
    bool skipZeroStock = true,
  }) async {
    try {
      // Filter items based on stock
      final itemsToCreate = skipZeroStock
          ? items.where((item) => item.totalStock > 0).toList()
          : items;

      if (itemsToCreate.isEmpty) {
        return ApiResponse(
          success: false,
          message: 'No items to create (all have zero stock)',
        );
      }

      AppLogger.info('🚀 Creating ${itemsToCreate.length} brands from OCR');

      int successCount = 0;
      int failureCount = 0;
      List<String> createdBrandIds = [];
      List<String> errors = [];
      int totalStockCreated = 0;

      // Create each brand sequentially
      for (final item in itemsToCreate) {
        try {
          AppLogger.info(
            '   Creating: ${item.brandText} ${item.sizeText} (${item.totalStock} units)',
          );

          final response = await _createCustomBrand(
            brandName: item.brandText,
            size: item.sizeText,
            stock: item.totalStock,
            shopId: shopId,
          );

          if (response.success && response.data != null) {
            successCount++;
            createdBrandIds.add(response.data!);
            totalStockCreated += item.totalStock;
            AppLogger.info('   ✅ Created: ${item.brandText}');
          } else {
            failureCount++;
            final errorMsg = '${item.brandText}: ${response.message ?? "Unknown error"}';
            errors.add(errorMsg);
            AppLogger.error('   ❌ Failed: $errorMsg');
          }
        } catch (e) {
          failureCount++;
          final errorMsg = '${item.brandText}: $e';
          errors.add(errorMsg);
          AppLogger.error('   ❌ Exception: $errorMsg');
        }
      }

      final result = BrandCreationResult(
        totalItems: itemsToCreate.length,
        successCount: successCount,
        failureCount: failureCount,
        createdBrandIds: createdBrandIds,
        errors: errors,
        totalStockCreated: totalStockCreated,
      );

      AppLogger.info(
        '📊 Batch creation complete: $successCount success, $failureCount failed',
      );

      return ApiResponse(
        success: successCount > 0,
        message: result.summaryMessage,
        data: result,
      );
    } catch (e) {
      AppLogger.error('❌ Batch brand creation failed: $e');
      return ApiResponse(
        success: false,
        message: 'Failed to create brands: $e',
      );
    }
  }

  /// Create a single custom brand with variant and initial stock
  /// If brand exists (409), updates the stock for the existing variant
  Future<ApiResponse<String>> _createCustomBrand({
    required String brandName,
    required String size,
    required int stock,
    required String shopId,
  }) async {
    try {
      // Guess category based on brand name (simplified heuristics)
      final categoryId = _guessCategory(brandName);

      final body = {
        'brand_name': brandName.trim(),
        'category_id': categoryId, // Add category_id at brand level (required by backend)
        'description': 'Created via OCR batch import',
        'is_active': true,
        'variants': [
          {
            'size': size.trim(),
            'initial_stock': stock,
            'shop_id': shopId,
            'category_id': categoryId,
            'selling_price': 0.0, // User can update later
            'cost_price': 0.0,    // User can update later
            'mrp': 0.0,           // User can update later
            'alcohol_content': 0.0,
            'is_active': true,
          }
        ],
      };

      final response = await _apiService.post<Map<String, dynamic>>(
        '/api/inventory/brands/custom',
        body: body,
        fromJson: (data) => data as Map<String, dynamic>,
      );

      // Check if we got a 409 error (brand/variant already exists)
      if (response.statusCode == 409 ||
          (response.message != null && response.message!.contains('already exist'))) {

        AppLogger.info('   Brand already exists, updating stock for: $brandName $size');

        // Try to update stock for existing variant
        final stockUpdateResponse = await _updateExistingBrandStock(
          brandName: brandName,
          size: size,
          stock: stock,
          shopId: shopId,
        );

        if (stockUpdateResponse.success) {
          return ApiResponse(
            success: true,
            message: 'Stock updated for existing brand',
            data: 'existing_updated',
          );
        } else {
          // If stock update also fails, return the original 409 message
          return ApiResponse(
            success: false,
            message: 'Brand exists but stock update failed: ${stockUpdateResponse.message}',
          );
        }
      }

      if (response.success && response.data != null) {
        // Extract brand ID from response
        final brandId = response.data!['brand_id'] as String? ??
            response.data!['id'] as String? ??
            '';

        return ApiResponse(
          success: true,
          message: 'Brand created successfully',
          data: brandId,
        );
      }

      return ApiResponse(
        success: false,
        message: response.message ?? 'Failed to create brand',
      );
    } catch (e) {
      return ApiResponse(
        success: false,
        message: 'Error creating brand: $e',
      );
    }
  }

  /// Update stock for an existing brand variant
  Future<ApiResponse<bool>> _updateExistingBrandStock({
    required String brandName,
    required String size,
    required int stock,
    required String shopId,
  }) async {
    try {
      // First, try to find the existing brand variant
      // This assumes we have an endpoint to search for brands
      // You may need to adjust this based on your backend API

      final stockAdjustBody = {
        'brand_name': brandName.trim(),
        'size': size.trim(),
        'adjustment_quantity': stock,
        'adjustment_type': 'add', // Adding stock
        'shop_id': shopId,
        'reason': 'OCR batch import - adding to existing',
      };

      // Try to adjust stock using the stock adjustment endpoint
      final response = await _apiService.post<Map<String, dynamic>>(
        '/api/inventory/stock/adjustment',
        body: stockAdjustBody,
        fromJson: (data) => data as Map<String, dynamic>,
      );

      if (response.success) {
        AppLogger.info('   ✅ Stock updated for existing: $brandName $size (+$stock)');
        return ApiResponse(
          success: true,
          message: 'Stock updated successfully',
          data: true,
        );
      }

      return ApiResponse(
        success: false,
        message: response.message ?? 'Failed to update stock',
        data: false,
      );
    } catch (e) {
      AppLogger.error('   Failed to update stock for existing brand: $e');
      return ApiResponse(
        success: false,
        message: 'Error updating stock: $e',
        data: false,
      );
    }
  }

  /// Guess category ID based on brand name using simple heuristics
  String _guessCategory(String brandName) {
    final lowerName = brandName.toLowerCase();

    // Whisky indicators
    if (lowerName.contains('royal') ||
        lowerName.contains('stag') ||
        lowerName.contains('blender') ||
        lowerName.contains('officer') ||
        lowerName.contains('black dog') ||
        lowerName.contains('signature') ||
        lowerName.contains('100 piper') ||
        lowerName.contains('antiquity')) {
      return '62310fa1-505b-46f0-8eae-88627b5204a9'; // Rum category (placeholder)
    }

    // Rum indicators
    if (lowerName.contains('rum') ||
        lowerName.contains('bacardi') ||
        lowerName.contains('monk') ||
        lowerName.contains('morpheus')) {
      return '62310fa1-505b-46f0-8eae-88627b5204a9'; // Rum
    }

    // Beer indicators
    if (lowerName.contains('beer') ||
        lowerName.contains('kingfisher') ||
        lowerName.contains('carlsberg') ||
        lowerName.contains('tuborg')) {
      return 'a05a1550-068e-48bf-a0ed-650423df257d'; // Beer
    }

    // Vodka indicators
    if (lowerName.contains('vodka') ||
        lowerName.contains('absolute') ||
        lowerName.contains('smirnoff')) {
      return '62310fa1-505b-46f0-8eae-88627b5204a9'; // Use Rum as default for now
    }

    // Default to Rum category (since it exists in your system)
    return '62310fa1-505b-46f0-8eae-88627b5204a9';
  }
}
