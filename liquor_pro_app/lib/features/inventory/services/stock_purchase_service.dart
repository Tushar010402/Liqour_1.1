// Stock Purchase Service - Industrial Grade API Client
//
// Handles all stock purchase operations with approval workflow.
// Follows best practices from modern platforms like Swiggy/Zomato.

import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../../core/services/dio_api_service.dart';
import '../../../core/models/api_response.dart';
import '../models/stock_purchase.dart';

/// Stock Purchase Service - API client for purchase operations
class StockPurchaseService {
  final DioApiService _apiService;

  StockPurchaseService(this._apiService);

  /// Create a new stock purchase request
  ///
  /// For Admin/Manager: Auto-approved and stock updated immediately
  /// For others: Creates pending request requiring approval
  Future<ApiResponse<StockPurchase>> createPurchaseRequest({
    required String shopId,
    required String vendorId,
    required List<StockPurchaseItem> items,
    String? notes,
    double? roundOff, // Round-off adjustment (auto-calculated or manual)
    // Receipt Information
    String? receiptNumber,
    DateTime? receiptDate,
    String? receiptImageUrl,
    String? receiptNotes,
  }) async {
    try {
      debugPrint('📦 StockPurchaseService.createPurchaseRequest() called');
      debugPrint('   - Shop ID: $shopId');
      debugPrint('   - Vendor ID: $vendorId');
      debugPrint('   - Items: ${items.length}');
      debugPrint('   - Round Off: ${roundOff?.toStringAsFixed(2) ?? 'Auto'}');
      debugPrint('   - Receipt Number: ${receiptNumber ?? 'None'}');
      debugPrint('   - Receipt Date: ${receiptDate?.toIso8601String() ?? 'None'}');
      debugPrint('   - Receipt Image URL: ${receiptImageUrl ?? 'None'}');

      final request = CreateStockPurchaseRequest(
        shopId: shopId,
        vendorId: vendorId,
        items: items,
        notes: notes,
        roundOff: roundOff,
        receiptNumber: receiptNumber,
        receiptDate: receiptDate,
        receiptImageUrl: receiptImageUrl,
        receiptNotes: receiptNotes,
      );

      debugPrint('   - Subtotal: ₹${request.subtotal.toStringAsFixed(2)}');
      debugPrint('   - TDS (1%): ₹${request.tdsAmount.toStringAsFixed(2)}');
      debugPrint('   - Round Off: ₹${request.effectiveRoundOff.toStringAsFixed(2)}');
      debugPrint('   - Total: ₹${request.totalAmount.toStringAsFixed(2)}');

      final response = await _apiService.post<StockPurchase>(
        '/api/inventory/purchases',
        body: request.toJson(),
        fromJson: (data) {
          if (data is Map<String, dynamic>) {
            return StockPurchase.fromJson(data);
          }
          throw Exception('Invalid response format');
        },
      );

      if (response.success && response.data != null) {
        final purchase = response.data!;
        debugPrint('✅ StockPurchaseService: Purchase request created');
        debugPrint('   - ID: ${purchase.id}');
        debugPrint('   - Status: ${purchase.status.displayName}');

        return ApiResponse<StockPurchase>(
          success: true,
          data: purchase,
          message: purchase.status.isApproved
              ? 'Stock added successfully'
              : 'Purchase request submitted for approval',
        );
      }

      return ApiResponse<StockPurchase>(
        success: false,
        message: response.message ?? 'Failed to create purchase request',
      );
    } catch (e) {
      debugPrint('❌ StockPurchaseService: Error creating purchase - $e');
      return ApiResponse<StockPurchase>(
        success: false,
        message: 'Failed to create purchase request: $e',
      );
    }
  }

  /// Upload purchase receipt image
  ///
  /// Returns the URL of the uploaded receipt image
  Future<ApiResponse<String>> uploadReceiptImage(File imageFile) async {
    try {
      debugPrint('📦 StockPurchaseService.uploadReceiptImage() called');
      debugPrint('   - File: ${imageFile.path}');

      final response = await _apiService.uploadFile<String>(
        '/api/inventory/purchases/upload-receipt',
        imageFile.path,
        fileFieldName: 'receipt',
        fromJson: (data) {
          if (data is Map<String, dynamic>) {
            return data['receipt_url']?.toString() ??
                   data['url']?.toString() ??
                   data['file_url']?.toString() ?? '';
          }
          return data?.toString() ?? '';
        },
      );

      if (response.success && response.data != null && response.data!.isNotEmpty) {
        debugPrint('✅ StockPurchaseService: Receipt uploaded successfully');
        debugPrint('   - URL: ${response.data}');
        return ApiResponse<String>(
          success: true,
          data: response.data,
          message: 'Receipt uploaded successfully',
        );
      }

      return ApiResponse<String>(
        success: false,
        message: response.message ?? 'Failed to upload receipt',
      );
    } catch (e) {
      debugPrint('❌ StockPurchaseService: Error uploading receipt - $e');
      return ApiResponse<String>(
        success: false,
        message: 'Failed to upload receipt: $e',
      );
    }
  }

  /// Get pending approvals for the current user (managers only)
  Future<ApiResponse<StockPurchaseListResponse>> getPendingApprovals({
    String? shopId,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      debugPrint('📦 StockPurchaseService.getPendingApprovals() called');

      final queryParams = <String, dynamic>{
        'status': 'pending',
        'page': page.toString(),
        'limit': limit.toString(),
        if (shopId != null) 'shop_id': shopId,
      };

      final response = await _apiService.get<StockPurchaseListResponse>(
        '/api/inventory/purchases/pending',
        queryParams: queryParams,
        fromJson: (data) {
          if (data is Map<String, dynamic>) {
            return StockPurchaseListResponse.fromJson(data);
          }
          if (data is List) {
            return StockPurchaseListResponse(
              purchases: data
                  .map((p) => StockPurchase.fromJson(p as Map<String, dynamic>))
                  .toList(),
              total: data.length,
            );
          }
          return StockPurchaseListResponse(purchases: [], total: 0);
        },
      );

      if (response.success && response.data != null) {
        debugPrint(
            '✅ StockPurchaseService: Loaded ${response.data!.purchases.length} pending approvals');
        return response;
      }

      return ApiResponse<StockPurchaseListResponse>(
        success: false,
        message: response.message ?? 'Failed to load pending approvals',
      );
    } catch (e) {
      debugPrint('❌ StockPurchaseService: Error loading pending approvals - $e');
      return ApiResponse<StockPurchaseListResponse>(
        success: false,
        message: 'Failed to load pending approvals: $e',
      );
    }
  }

  /// Approve a stock purchase request
  ///
  /// Only authorized roles can approve (based on creator's role)
  Future<ApiResponse<StockPurchase>> approvePurchase({
    required String purchaseId,
    String? notes,
  }) async {
    try {
      debugPrint('📦 StockPurchaseService.approvePurchase() called');
      debugPrint('   - Purchase ID: $purchaseId');

      final response = await _apiService.post<StockPurchase>(
        '/api/inventory/purchases/$purchaseId/approve',
        body: {
          if (notes != null) 'notes': notes,
        },
        fromJson: (data) {
          if (data is Map<String, dynamic>) {
            return StockPurchase.fromJson(data);
          }
          throw Exception('Invalid response format');
        },
      );

      if (response.success) {
        debugPrint('✅ StockPurchaseService: Purchase approved successfully');
        return ApiResponse<StockPurchase>(
          success: true,
          data: response.data,
          message: 'Purchase approved and stock updated',
        );
      }

      return ApiResponse<StockPurchase>(
        success: false,
        message: response.message ?? 'Failed to approve purchase',
      );
    } catch (e) {
      debugPrint('❌ StockPurchaseService: Error approving purchase - $e');
      return ApiResponse<StockPurchase>(
        success: false,
        message: 'Failed to approve purchase: $e',
      );
    }
  }

  /// Reject a stock purchase request
  Future<ApiResponse<StockPurchase>> rejectPurchase({
    required String purchaseId,
    required String reason,
  }) async {
    try {
      debugPrint('📦 StockPurchaseService.rejectPurchase() called');
      debugPrint('   - Purchase ID: $purchaseId');
      debugPrint('   - Reason: $reason');

      final response = await _apiService.post<StockPurchase>(
        '/api/inventory/purchases/$purchaseId/reject',
        body: {
          'reason': reason,
        },
        fromJson: (data) {
          if (data is Map<String, dynamic>) {
            return StockPurchase.fromJson(data);
          }
          throw Exception('Invalid response format');
        },
      );

      if (response.success) {
        debugPrint('✅ StockPurchaseService: Purchase rejected');
        return ApiResponse<StockPurchase>(
          success: true,
          data: response.data,
          message: 'Purchase request rejected',
        );
      }

      return ApiResponse<StockPurchase>(
        success: false,
        message: response.message ?? 'Failed to reject purchase',
      );
    } catch (e) {
      debugPrint('❌ StockPurchaseService: Error rejecting purchase - $e');
      return ApiResponse<StockPurchase>(
        success: false,
        message: 'Failed to reject purchase: $e',
      );
    }
  }

  /// Get purchase history with filters
  Future<ApiResponse<StockPurchaseListResponse>> getPurchaseHistory({
    String? shopId,
    String? vendorId,
    StockPurchaseStatus? status,
    DateTime? fromDate,
    DateTime? toDate,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      debugPrint('📦 StockPurchaseService.getPurchaseHistory() called');
      debugPrint('   - Page: $page, Limit: $limit');

      final queryParams = <String, dynamic>{
        'page': page.toString(),
        'limit': limit.toString(),
        if (shopId != null) 'shop_id': shopId,
        if (vendorId != null) 'vendor_id': vendorId,
        if (status != null) 'status': status.name,
        if (fromDate != null) 'from_date': fromDate.toIso8601String(),
        if (toDate != null) 'to_date': toDate.toIso8601String(),
      };

      final response = await _apiService.get<StockPurchaseListResponse>(
        '/api/inventory/purchases',
        queryParams: queryParams,
        fromJson: (data) {
          if (data is Map<String, dynamic>) {
            return StockPurchaseListResponse.fromJson(data);
          }
          if (data is List) {
            return StockPurchaseListResponse(
              purchases: data
                  .map((p) => StockPurchase.fromJson(p as Map<String, dynamic>))
                  .toList(),
              total: data.length,
            );
          }
          return StockPurchaseListResponse(purchases: [], total: 0);
        },
      );

      if (response.success && response.data != null) {
        debugPrint(
            '✅ StockPurchaseService: Loaded ${response.data!.purchases.length} purchases');
        return response;
      }

      return ApiResponse<StockPurchaseListResponse>(
        success: false,
        message: response.message ?? 'Failed to load purchase history',
      );
    } catch (e) {
      debugPrint('❌ StockPurchaseService: Error loading purchase history - $e');
      return ApiResponse<StockPurchaseListResponse>(
        success: false,
        message: 'Failed to load purchase history: $e',
      );
    }
  }

  /// Get single purchase by ID (for detail view)
  Future<ApiResponse<StockPurchase>> getPurchase(String purchaseId) async {
    try {
      debugPrint('📦 StockPurchaseService.getPurchase() called');
      debugPrint('   - Purchase ID: $purchaseId');

      final response = await _apiService.get<StockPurchase>(
        '/api/inventory/purchases/$purchaseId',
        fromJson: (data) {
          if (data is Map<String, dynamic>) {
            return StockPurchase.fromJson(data);
          }
          throw Exception('Invalid response format');
        },
      );

      if (response.success && response.data != null) {
        debugPrint('✅ StockPurchaseService: Loaded purchase details');
        return response;
      }

      return ApiResponse<StockPurchase>(
        success: false,
        message: response.message ?? 'Failed to load purchase details',
      );
    } catch (e) {
      debugPrint('❌ StockPurchaseService: Error loading purchase - $e');
      return ApiResponse<StockPurchase>(
        success: false,
        message: 'Failed to load purchase details: $e',
      );
    }
  }

  /// Cancel a pending purchase request (only by creator)
  Future<ApiResponse<void>> cancelPurchase(String purchaseId) async {
    try {
      debugPrint('📦 StockPurchaseService.cancelPurchase() called');
      debugPrint('   - Purchase ID: $purchaseId');

      final response = await _apiService.post<void>(
        '/api/inventory/purchases/$purchaseId/cancel',
        body: {},
        fromJson: (_) {},
      );

      if (response.success) {
        debugPrint('✅ StockPurchaseService: Purchase cancelled');
        return ApiResponse<void>(
          success: true,
          message: 'Purchase request cancelled',
        );
      }

      return ApiResponse<void>(
        success: false,
        message: response.message ?? 'Failed to cancel purchase',
      );
    } catch (e) {
      debugPrint('❌ StockPurchaseService: Error cancelling purchase - $e');
      return ApiResponse<void>(
        success: false,
        message: 'Failed to cancel purchase: $e',
      );
    }
  }

  /// Get approval statistics (for dashboard)
  Future<ApiResponse<Map<String, dynamic>>> getApprovalStats({
    String? shopId,
  }) async {
    try {
      debugPrint('📦 StockPurchaseService.getApprovalStats() called');

      final queryParams = <String, dynamic>{
        if (shopId != null) 'shop_id': shopId,
      };

      final response = await _apiService.get<Map<String, dynamic>>(
        '/api/inventory/purchases/stats',
        queryParams: queryParams,
        fromJson: (data) {
          if (data is Map<String, dynamic>) {
            return data;
          }
          return <String, dynamic>{};
        },
      );

      if (response.success && response.data != null) {
        debugPrint('✅ StockPurchaseService: Loaded approval stats');
        return response;
      }

      return ApiResponse<Map<String, dynamic>>(
        success: false,
        message: response.message ?? 'Failed to load stats',
      );
    } catch (e) {
      debugPrint('❌ StockPurchaseService: Error loading stats - $e');
      return ApiResponse<Map<String, dynamic>>(
        success: false,
        message: 'Failed to load stats: $e',
      );
    }
  }
}
