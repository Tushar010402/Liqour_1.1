import 'package:flutter/foundation.dart';
import '../../../core/services/dio_api_service.dart';
import '../../../core/models/api_response.dart';

/// Stock Service - Handles stock management operations
class StockService {
  final DioApiService _apiService;

  StockService(this._apiService);

  /// Adjust stock for a product
  Future<ApiResponse<Map<String, dynamic>>> adjustStock({
    required String shopId,
    required String productId,
    required int quantity,
    required String adjustmentType, // 'add', 'remove', 'set'
    required String reason,
    String? notes,
  }) async {
    try {
      debugPrint('📦 StockService.adjustStock() called');
      debugPrint('   - Shop ID: $shopId');
      debugPrint('   - Product ID: $productId');
      debugPrint('   - Quantity: $quantity');
      debugPrint('   - Type: $adjustmentType');
      debugPrint('   - Reason: $reason');

      final response = await _apiService.post(
        '/api/inventory/stocks/adjust',
        body: {
          'shop_id': shopId,
          'product_id': productId,
          'quantity': quantity,
          'adjustment_type': adjustmentType,
          'reason': reason,
          if (notes != null) 'notes': notes,
        },
      );

      if (response.success) {
        debugPrint('📦 StockService: Stock adjusted successfully');
        return ApiResponse<Map<String, dynamic>>(
          success: true,
          data: response.data as Map<String, dynamic>?,
          message: 'Stock adjusted successfully',
        );
      } else {
        return ApiResponse<Map<String, dynamic>>(
          success: false,
          message: response.message ?? 'Failed to adjust stock',
        );
      }
    } catch (e) {
      debugPrint('❌ StockService: Error adjusting stock - $e');
      return ApiResponse<Map<String, dynamic>>(
        success: false,
        message: 'Failed to adjust stock: $e',
      );
    }
  }

  /// Get stock by shop
  Future<ApiResponse<List<Map<String, dynamic>>>> getStockByShop({
    required String shopId,
    String? categoryId,
    String? search,
    bool? lowStock,
  }) async {
    try {
      debugPrint('📦 StockService.getStockByShop() called');
      debugPrint('   - Shop ID: $shopId');

      final queryParams = <String, dynamic>{
        'shop_id': shopId,
        if (categoryId != null) 'category_id': categoryId,
        if (search != null) 'search': search,
        if (lowStock != null) 'low_stock': lowStock,
      };

      final response = await _apiService.get(
        '/api/inventory/stocks',
        queryParams: queryParams,
      );

      final stockList = (response.data as List?)
              ?.map((item) => item as Map<String, dynamic>)
              .toList() ??
          [];

      debugPrint('📦 StockService: Retrieved ${stockList.length} stock items');
      return ApiResponse<List<Map<String, dynamic>>>(
        success: true,
        data: stockList,
      );
    } catch (e) {
      debugPrint('❌ StockService: Error getting stock - $e');
      return ApiResponse<List<Map<String, dynamic>>>(
        success: false,
        message: 'Failed to get stock: $e',
      );
    }
  }

  /// Transfer stock between shops
  Future<ApiResponse<Map<String, dynamic>>> transferStock({
    required String fromShopId,
    required String toShopId,
    required List<Map<String, dynamic>> items,
    String? notes,
  }) async {
    try {
      debugPrint('📦 StockService.transferStock() called');
      debugPrint('   - From Shop: $fromShopId');
      debugPrint('   - To Shop: $toShopId');
      debugPrint('   - Items: ${items.length}');

      final response = await _apiService.post(
        '/api/inventory/stocks/transfer',
        body: {
          'from_shop_id': fromShopId,
          'to_shop_id': toShopId,
          'transfer_date': DateTime.now().toIso8601String(),
          'items': items,
          if (notes != null) 'notes': notes,
        },
      );

      if (response.success) {
        debugPrint('📦 StockService: Stock transferred successfully');
        return ApiResponse<Map<String, dynamic>>(
          success: true,
          data: response.data as Map<String, dynamic>?,
          message: 'Stock transferred successfully',
        );
      } else {
        return ApiResponse<Map<String, dynamic>>(
          success: false,
          message: response.message ?? 'Failed to transfer stock',
        );
      }
    } catch (e) {
      debugPrint('❌ StockService: Error transferring stock - $e');
      return ApiResponse<Map<String, dynamic>>(
        success: false,
        message: 'Failed to transfer stock: $e',
      );
    }
  }

  /// Get stock history
  Future<ApiResponse<List<Map<String, dynamic>>>> getStockHistory({
    required String stockId,
    int? limit,
  }) async {
    try {
      debugPrint('📦 StockService.getStockHistory() called');
      debugPrint('   - Stock ID: $stockId');

      final queryParams = <String, dynamic>{
        if (limit != null) 'limit': limit,
      };

      final response = await _apiService.get(
        '/api/inventory/stocks/$stockId/history',
        queryParams: queryParams,
      );

      final historyList = (response.data as List?)
              ?.map((item) => item as Map<String, dynamic>)
              .toList() ??
          [];

      debugPrint('📦 StockService: Retrieved ${historyList.length} history items');
      return ApiResponse<List<Map<String, dynamic>>>(
        success: true,
        data: historyList,
      );
    } catch (e) {
      debugPrint('❌ StockService: Error getting stock history - $e');
      return ApiResponse<List<Map<String, dynamic>>>(
        success: false,
        message: 'Failed to get stock history: $e',
      );
    }
  }

  /// Get low stock alerts
  Future<ApiResponse<List<Map<String, dynamic>>>> getLowStockAlerts({
    String? shopId,
  }) async {
    try {
      debugPrint('📦 StockService.getLowStockAlerts() called');
      if (shopId != null) {
        debugPrint('   - Shop ID: $shopId');
      }

      final queryParams = <String, dynamic>{
        if (shopId != null) 'shop_id': shopId,
      };

      final response = await _apiService.get(
        '/api/inventory/stocks/alerts',
        queryParams: queryParams,
      );

      final alertsList = (response.data as List?)
              ?.map((item) => item as Map<String, dynamic>)
              .toList() ??
          [];

      debugPrint('📦 StockService: Retrieved ${alertsList.length} low stock alerts');
      return ApiResponse<List<Map<String, dynamic>>>(
        success: true,
        data: alertsList,
      );
    } catch (e) {
      debugPrint('❌ StockService: Error getting low stock alerts - $e');
      return ApiResponse<List<Map<String, dynamic>>>(
        success: false,
        message: 'Failed to get low stock alerts: $e',
      );
    }
  }

  /// Batch adjust stock for multiple products
  Future<ApiResponse<Map<String, dynamic>>> batchAdjustStock({
    required String shopId,
    required List<Map<String, dynamic>> adjustments,
    required String reason,
    String? notes,
  }) async {
    try {
      debugPrint('📦 StockService.batchAdjustStock() called');
      debugPrint('   - Shop ID: $shopId');
      debugPrint('   - Adjustments count: ${adjustments.length}');
      debugPrint('   - Reason: $reason');

      int successCount = 0;
      int errorCount = 0;
      final errors = <String>[];

      for (var adjustment in adjustments) {
        try {
          final response = await adjustStock(
            shopId: shopId,
            productId: adjustment['product_id'] as String,
            quantity: adjustment['quantity'] as int,
            adjustmentType: adjustment['adjustment_type'] as String? ?? 'set',
            reason: reason,
            notes: notes,
          );
          if (response.success) {
            successCount++;
          } else {
            errorCount++;
            errors.add('Product ${adjustment['product_id']}: ${response.message}');
          }
        } catch (e) {
          errorCount++;
          errors.add('Product ${adjustment['product_id']}: $e');
        }
      }

      debugPrint('📦 StockService: Batch adjustment complete');
      debugPrint('   - Success: $successCount');
      debugPrint('   - Errors: $errorCount');

      return ApiResponse<Map<String, dynamic>>(
        success: errorCount == 0,
        data: {
          'success_count': successCount,
          'error_count': errorCount,
          'errors': errors,
        },
        message: errorCount > 0
            ? 'Completed with $errorCount errors'
            : 'All adjustments successful',
      );
    } catch (e) {
      debugPrint('❌ StockService: Error in batch adjustment - $e');
      return ApiResponse<Map<String, dynamic>>(
        success: false,
        message: 'Failed to batch adjust stock: $e',
      );
    }
  }
}
