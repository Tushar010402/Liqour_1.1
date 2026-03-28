import 'package:flutter/foundation.dart';

import '../../../core/services/dio_api_service.dart';
import '../../../core/utils/app_logger.dart';
import '../models/cash_models.dart';

/// CashService - Handles all cash management API calls
class CashService {
  final DioApiService _apiService;

  CashService(this._apiService);

  static const String _baseUrl = '/api/finance/cash';

  // ══════════════════════════════════════════════════════════════════════════════
  // Cash Balance Queries
  // ══════════════════════════════════════════════════════════════════════════════

  /// Get current user's total cash balance (across all shops)
  /// Cash is user-specific, not shop-specific
  Future<double> getCashBalance() async {
    try {
      final response = await _apiService.get(
        '$_baseUrl/balance',
        // No shop_id query param - backend returns total across all shops
      );

      if (response.success && response.data != null) {
        // FIX: Use 'user_balance' for the logged-in user's personal balance
        // 'balance' and 'total_balance' return team total - WRONG for "Cash in Hand"
        final balance = response.data['user_balance'] ?? response.data['my_holding'] ?? response.data['balance'] ?? 0;
        final result = (balance as num).toDouble();
        return result;
      } else {
        throw Exception('Failed to get cash balance: ${response.message}');
      }
    } catch (e) {
      AppLogger.error('Error getting cash balance: $e');
      rethrow;
    }
  }

  /// Get detailed cash holding information
  Future<CashHolding?> getCashHolding(String shopId) async {
    try {
      final response = await _apiService.get(
        '$_baseUrl/holding',
        queryParams: {'shop_id': shopId},
      );

      if (response.success && response.data != null) {
        return response.data['holding'] != null
            ? CashHolding.fromJson(response.data['holding'])
            : null;
      } else if (response.statusCode == 404) {
        return null; // No cash holding exists yet
      } else {
        throw Exception('Failed to get cash holding: ${response.message}');
      }
    } catch (e) {
      AppLogger.error('Error getting cash holding: $e');
      rethrow;
    }
  }

  /// Get cash balances of team members (subordinates)
  /// Visible to Executive, Assistant Manager, Manager, Admin
  /// shopId is optional - if null, returns balances across all shops
  Future<List<TeamCashBalance>> getTeamBalances([String? shopId]) async {
    try {
      // Only include shop_id in query params if provided
      final queryParams = shopId != null ? {'shop_id': shopId} : <String, dynamic>{};

      final response = await _apiService.get(
        '$_baseUrl/team-balances',
        queryParams: queryParams,
      );

      if (response.success && response.data != null) {
        final List<dynamic> balancesJson = response.data['team_balances'] ?? [];

        final result = balancesJson
            .map((json) => TeamCashBalance.fromJson(json))
            .toList();

        if (kDebugMode) {
          debugPrint('[CashService] getTeamBalances: ${result.length} members');
        }

        return result;
      } else {
        throw Exception('Failed to get team balances: ${response.message}');
      }
    } catch (e) {
      AppLogger.error('💰 [CashService] ❌ Error getting team balances: $e');
      rethrow;
    }
  }

  /// Get tenant users for cash request selection (NO cash amounts shown - maintains hierarchical privacy)
  /// Available to: All users
  /// Returns list of users without cash amounts
  Future<List<TenantUser>> getTenantUsers([String? shopId]) async {
    try {
      // Only include shop_id in query params if provided
      final queryParams = shopId != null ? {'shop_id': shopId} : <String, dynamic>{};

      final response = await _apiService.get(
        '$_baseUrl/tenant-users',
        queryParams: queryParams,
      );

      if (response.success && response.data != null) {
        final List<dynamic> usersJson = response.data['users'] ?? [];

        final result = usersJson
            .map((json) => TenantUser.fromJson(json))
            .toList();

        if (kDebugMode) {
          debugPrint('[CashService] getTenantUsers: ${result.length} users');
        }

        return result;
      } else {
        throw Exception('Failed to get tenant users: ${response.message}');
      }
    } catch (e) {
      AppLogger.error('👥 [CashService] ❌ Error getting tenant users: $e');
      rethrow;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // Cash Collection (From Subordinates)
  // ══════════════════════════════════════════════════════════════════════════════

  /// Collect cash from a subordinate
  /// Available to: Executive, Assistant Manager, Manager, Admin
  Future<CashCollection> collectCash(CollectCashRequest request) async {
    try {
      final response = await _apiService.post(
        '$_baseUrl/collect',
        body: request.toJson(),
      );

      if (response.success && response.data != null) {
        // Backend returns collection directly at root, not nested under 'collection' key
        return CashCollection.fromJson(response.data);
      } else {
        throw Exception('Failed to collect cash: ${response.message}');
      }
    } catch (e) {
      AppLogger.error('Error collecting cash: $e');
      rethrow;
    }
  }

  /// Get collection history (both given and received)
  Future<List<CashCollection>> getCollections({
    String? shopId,
    String? status,
    int limit = 50,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (shopId != null) queryParams['shop_id'] = shopId;
      if (status != null) queryParams['status'] = status;
      queryParams['limit'] = limit.toString();

      final response = await _apiService.get(
        '$_baseUrl/collections',
        queryParams: queryParams,
      );

      if (response.success && response.data != null) {
        final List<dynamic> collectionsJson = response.data['collections'] ?? [];
        return collectionsJson
            .map((json) => CashCollection.fromJson(json))
            .toList();
      } else {
        throw Exception('Failed to get collections: ${response.message}');
      }
    } catch (e) {
      AppLogger.error('Error getting collections: $e');
      rethrow;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // Cash Submission (To Bank)
  // ══════════════════════════════════════════════════════════════════════════════

  /// Submit cash to bank with denomination breakdown
  Future<CashSubmission> submitCash(SubmitCashRequest request) async {
    try {
      // Validate before sending
      if (!request.isValid) {
        throw Exception(
            'Invalid denomination breakdown: calculated ₹${request.calculatedTotal} != declared ₹${request.totalAmount}');
      }

      final response = await _apiService.post(
        '$_baseUrl/submit',
        body: request.toJson(),
      );

      if (response.success && response.data != null) {
        // Backend may return data at root or nested under 'submission' key
        final submissionData = response.data['submission'] ?? response.data;
        return CashSubmission.fromJson(submissionData);
      } else {
        throw Exception('Failed to submit cash: ${response.message}');
      }
    } catch (e) {
      AppLogger.error('Error submitting cash: $e');
      rethrow;
    }
  }

  /// Get submission history
  Future<List<CashSubmission>> getSubmissions({
    String? userId,
    String? shopId,
    String? status,
    int limit = 50,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (userId != null) queryParams['user_id'] = userId;
      if (shopId != null) queryParams['shop_id'] = shopId;
      if (status != null) queryParams['status'] = status;
      queryParams['limit'] = limit.toString();

      final response = await _apiService.get(
        '$_baseUrl/submissions',
        queryParams: queryParams,
      );

      if (response.success && response.data != null) {
        // Backend returns 'cash_deposits' not 'submissions'
        final List<dynamic> submissionsJson = response.data['cash_deposits'] ?? [];
        return submissionsJson
            .map((json) => CashSubmission.fromJson(json))
            .toList();
      } else {
        throw Exception('Failed to get submissions: ${response.message}');
      }
    } catch (e) {
      AppLogger.error('Error getting submissions: $e');
      rethrow;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // Approval Workflow (Manager and Above)
  // ══════════════════════════════════════════════════════════════════════════════

  /// Approve a cash submission
  /// Available to: Manager, Admin
  /// Returns void on success, throws on failure
  Future<void> approveSubmission(String submissionId) async {
    try {
      AppLogger.info('💰 [CashService] Approving submission: $submissionId');

      final response = await _apiService.post(
        '$_baseUrl/submissions/$submissionId/approve',
        body: {},
      );

      AppLogger.info('💰 [CashService] Approve response - success: ${response.success}, statusCode: ${response.statusCode}');

      if (response.success) {
        AppLogger.info('✅ [CashService] Submission approved successfully');
        return; // Success - API returned 200
      } else {
        throw Exception('Failed to approve submission: ${response.message ?? 'Unknown error'}');
      }
    } catch (e) {
      AppLogger.error('Error approving submission: $e');
      rethrow;
    }
  }

  /// Reject a cash submission
  /// Available to: Manager, Admin
  /// Returns void on success, throws on failure
  Future<void> rejectSubmission(
    String submissionId,
    String reason,
  ) async {
    try {
      AppLogger.info('💰 [CashService] Rejecting submission: $submissionId with reason: $reason');

      final response = await _apiService.post(
        '$_baseUrl/submissions/$submissionId/reject',
        body: {'rejection_reason': reason},
      );

      AppLogger.info('💰 [CashService] Reject response - success: ${response.success}, statusCode: ${response.statusCode}');

      if (response.success) {
        AppLogger.info('✅ [CashService] Submission rejected successfully');
        return; // Success - API returned 200
      } else {
        throw Exception('Failed to reject submission: ${response.message ?? 'Unknown error'}');
      }
    } catch (e) {
      AppLogger.error('Error rejecting submission: $e');
      rethrow;
    }
  }

  /// Get pending submissions for approval (Manager/Admin view)
  Future<List<CashSubmission>> getPendingSubmissions({String? shopId}) async {
    return getSubmissions(shopId: shopId, status: 'pending');
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // Audit Trail
  // ══════════════════════════════════════════════════════════════════════════════

  /// Get complete cash transaction history
  Future<List<CashTransaction>> getCashHistory({
    String? shopId,
    String? transactionType,
    int limit = 100,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (shopId != null) queryParams['shop_id'] = shopId;
      if (transactionType != null) {
        queryParams['transaction_type'] = transactionType;
      }
      queryParams['limit'] = limit.toString();

      final response = await _apiService.get(
        '$_baseUrl/history',
        queryParams: queryParams,
      );

      if (response.success && response.data != null) {
        // Backend now sends transactions array directly
        final List<dynamic> historyJson = response.data['transactions'] ?? [];

        if (kDebugMode) {
          debugPrint('[CashService] getCashHistory: ${historyJson.length} transactions');
        }
        return historyJson
            .map((json) => CashTransaction.fromJson(json as Map<String, dynamic>))
            .toList();
      } else {
        throw Exception('Failed to get cash history: ${response.message}');
      }
    } catch (e) {
      AppLogger.error('Error getting cash history: $e');
      rethrow;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // Helper Methods
  // ══════════════════════════════════════════════════════════════════════════════

  /// Upload receipt photo to server and return the URL
  Future<String?> uploadReceiptPhoto(String filePath) async {
    try {
      AppLogger.info('📸 [CashService] Uploading receipt: $filePath');

      // Use the uploadFile method from DioApiService
      final response = await _apiService.uploadFile(
        '/api/finance/cash/upload-receipt',
        filePath,
        fileFieldName: 'receipt',
      );

      if (response.success && response.data != null) {
        // Backend returns receipt_url in the response
        final receiptUrl = response.data['receipt_url'] as String?;
        if (receiptUrl != null && receiptUrl.isNotEmpty) {
          AppLogger.info('📸 [CashService] ✅ Receipt uploaded successfully: $receiptUrl');
          return receiptUrl;
        } else {
          AppLogger.warning('📸 [CashService] ⚠️ Upload succeeded but no URL returned');
          return null;
        }
      } else {
        AppLogger.error('📸 [CashService] ❌ Upload failed: ${response.message}');
        return null;
      }
    } catch (e, stackTrace) {
      AppLogger.error('❌ [CashService] Error uploading receipt photo: $e');
      AppLogger.error('❌ [CashService] Stack: $stackTrace');
      return null;
    }
  }

  /// Calculate denomination breakdown from total amount (helper for UI)
  /// Returns a suggested breakdown using largest notes first
  Map<String, int> suggestDenominations(double totalAmount) {
    int remaining = totalAmount.round();
    final breakdown = <String, int>{};

    breakdown['notes_500'] = remaining ~/ 500;
    remaining = remaining % 500;

    breakdown['notes_200'] = remaining ~/ 200;
    remaining = remaining % 200;

    breakdown['notes_100'] = remaining ~/ 100;
    remaining = remaining % 100;

    breakdown['notes_50'] = remaining ~/ 50;
    remaining = remaining % 50;

    breakdown['notes_20'] = remaining ~/ 20;
    remaining = remaining % 20;

    breakdown['notes_10'] = remaining ~/ 10;

    return breakdown;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Approval Workflow Methods
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get pending collection requests for current user (requests TO them)
  Future<List<CashCollection>> getPendingCollections({
    required String shopId,
  }) async {
    try {
      final response = await _apiService.get(
        '$_baseUrl/collections/pending',
        queryParams: {'shop_id': shopId},
      );

      if (!response.success) {
        throw Exception(response.message ?? 'Failed to fetch pending collections');
      }

      final List<dynamic> data = response.data['collections'] ?? [];
      return data.map((json) => CashCollection.fromJson(json)).toList();
    } catch (e) {
      AppLogger.error('Error fetching pending collections: $e');
      rethrow;
    }
  }

  /// Approve a pending collection request
  Future<void> approveCollection(String collectionId) async {
    try {
      final response = await _apiService.post(
        '$_baseUrl/collections/$collectionId/approve',
        body: {},
      );

      if (!response.success) {
        throw Exception(response.message ?? 'Failed to approve collection');
      }

      AppLogger.info('Collection approved successfully: $collectionId');
    } catch (e) {
      AppLogger.error('Error approving collection: $e');
      rethrow;
    }
  }

  /// Reject a pending collection request with reason
  Future<void> rejectCollection(String collectionId, String reason) async {
    try {
      final response = await _apiService.post(
        '$_baseUrl/collections/$collectionId/reject',
        body: {'reason': reason},
      );

      if (!response.success) {
        throw Exception(response.message ?? 'Failed to reject collection');
      }

      AppLogger.info('Collection rejected: $collectionId - Reason: $reason');
    } catch (e) {
      AppLogger.error('Error rejecting collection: $e');
      rethrow;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // Cash Request System (User requests cash FROM another user)
  // ══════════════════════════════════════════════════════════════════════════════

  /// Create a cash request to another user
  /// Any user can request cash from another user in their tenant
  Future<CashRequest> createCashRequest({
    required String executiveId,
    String? shopId, // Shop is now optional (backend updated)
    required double amount,
    String? notes,
  }) async {
    try {
      final response = await _apiService.post(
        '$_baseUrl/request',
        body: {
          'executive_id': executiveId,
          if (shopId != null && shopId.isNotEmpty) 'shop_id': shopId,
          'amount': amount,
          if (notes != null && notes.isNotEmpty) 'notes': notes,
        },
      );

      if (response.success && response.data != null) {
        return CashRequest.fromJson(response.data);
      } else {
        throw Exception('Failed to create cash request: ${response.message}');
      }
    } catch (e) {
      AppLogger.error('Error creating cash request: $e');
      rethrow;
    }
  }

  /// Get cash requests with filters
  /// Returns both sent and received requests
  Future<List<CashRequest>> getCashRequests({
    String? shopId,
    String? status,
    String? filterType, // 'sent', 'received', or null for both
    int limit = 50,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (shopId != null) queryParams['shop_id'] = shopId;
      if (status != null) queryParams['status'] = status;
      if (filterType != null) queryParams['filter'] = filterType;
      queryParams['limit'] = limit.toString();

      final response = await _apiService.get(
        '$_baseUrl/requests',
        queryParams: queryParams,
      );

      if (response.success && response.data != null) {
        // Backend may return 'collections' or 'requests' depending on endpoint
        final List<dynamic> requestsJson = response.data['requests'] ?? response.data['collections'] ?? [];
        if (kDebugMode) {
          debugPrint('[CashService] getCashRequests: ${requestsJson.length} requests');
        }
        return requestsJson
            .map((json) => CashRequest.fromJson(json))
            .toList();
      } else {
        throw Exception('Failed to get cash requests: ${response.message}');
      }
    } catch (e) {
      AppLogger.error('Error getting cash requests: $e');
      rethrow;
    }
  }

  /// Get pending cash requests that need approval
  /// Returns requests where current user is the requested_from user
  Future<List<CashRequest>> getPendingCashRequests({
    required String shopId,
  }) async {
    try {
      final response = await _apiService.get(
        '$_baseUrl/requests/pending',
        queryParams: {'shop_id': shopId},
      );

      if (response.success && response.data != null) {
        final List<dynamic> requestsJson = response.data['cash_requests'] ?? [];
        return requestsJson
            .map((json) => CashRequest.fromJson(json))
            .toList();
      } else {
        throw Exception('Failed to get pending requests: ${response.message}');
      }
    } catch (e) {
      AppLogger.error('Error getting pending cash requests: $e');
      rethrow;
    }
  }

  /// Approve a pending cash request
  /// Transfers cash from approver to requester
  Future<void> approveCashRequest(String requestId) async {
    try {
      final response = await _apiService.post(
        '$_baseUrl/requests/$requestId/approve',
        body: {},
      );

      if (!response.success) {
        throw Exception(response.message ?? 'Failed to approve cash request');
      }

      AppLogger.info('Cash request approved successfully: $requestId');
    } catch (e) {
      AppLogger.error('Error approving cash request: $e');
      rethrow;
    }
  }

  /// Reject a pending cash request with reason
  Future<void> rejectCashRequest(String requestId, String reason) async {
    try {
      final response = await _apiService.post(
        '$_baseUrl/requests/$requestId/reject',
        body: {'reject_reason': reason},
      );

      if (!response.success) {
        throw Exception(response.message ?? 'Failed to reject cash request');
      }

      AppLogger.info('Cash request rejected: $requestId - Reason: $reason');
    } catch (e) {
      AppLogger.error('Error rejecting cash request: $e');
      rethrow;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // Admin Balance Management (Admin Only)
  // ══════════════════════════════════════════════════════════════════════════════

  /// Pre-defined adjustment reasons for admin balance changes
  static const Map<String, String> adjustmentReasons = {
    'fresh_start': 'Fresh Start - New Period',
    'correction': 'Balance Correction',
    'audit_fix': 'Audit Adjustment',
    'reconciliation': 'Cash Reconciliation',
    'period_close': 'Period/Month Close',
    'system_error': 'System Error Fix',
    'other': 'Other (See Notes)',
  };

  /// Admin: Set a user's cash balance to a specific amount
  /// Returns AdminBalanceResult with previous/new balance info
  Future<AdminBalanceResult> adminSetBalance({
    required String userId,
    required double newBalance,
    required String reason,
    String? notes,
  }) async {
    try {
      AppLogger.info('💰 [CashService] Admin setting balance for user: $userId to ₹$newBalance');
      AppLogger.info('   Reason: $reason, Notes: ${notes ?? 'N/A'}');

      final response = await _apiService.post(
        '$_baseUrl/admin/set-balance',
        body: {
          'user_id': userId,
          'new_balance': newBalance,
          'reason': reason,
          if (notes != null && notes.isNotEmpty) 'notes': notes,
        },
      );

      if (response.success && response.data != null) {
        AppLogger.info('✅ [CashService] Balance set successfully');
        return AdminBalanceResult.fromJson(response.data);
      } else {
        throw Exception('Failed to set balance: ${response.message}');
      }
    } catch (e) {
      AppLogger.error('❌ [CashService] Error setting balance: $e');
      rethrow;
    }
  }

  /// Admin: Bulk reset multiple users' cash balances
  /// If userIds is empty, resets all subordinates
  /// Returns number of affected users
  Future<int> adminBulkReset({
    List<String>? userIds,
    required double newBalance,
    required String reason,
    String? notes,
  }) async {
    try {
      AppLogger.info('💰 [CashService] Admin bulk reset');
      AppLogger.info('   Users: ${userIds?.length ?? 'ALL'}, New Balance: ₹$newBalance');
      AppLogger.info('   Reason: $reason, Notes: ${notes ?? 'N/A'}');

      final response = await _apiService.post(
        '$_baseUrl/admin/bulk-reset',
        body: {
          'user_ids': userIds ?? [],
          'new_balance': newBalance,
          'reason': reason,
          if (notes != null && notes.isNotEmpty) 'notes': notes,
        },
      );

      if (response.success && response.data != null) {
        final affectedUsers = response.data['affected_users'] as int? ?? 0;
        AppLogger.info('✅ [CashService] Bulk reset completed: $affectedUsers users affected');
        return affectedUsers;
      } else {
        throw Exception('Failed to bulk reset: ${response.message}');
      }
    } catch (e) {
      AppLogger.error('❌ [CashService] Error bulk resetting: $e');
      rethrow;
    }
  }

  /// Get a specific user's current cash balance (for admin view)
  Future<double> getUserBalance(String userId) async {
    try {
      final response = await _apiService.get(
        '$_baseUrl/admin/user-balance',
        queryParams: {'user_id': userId},
      );

      if (response.success && response.data != null) {
        return (response.data['balance'] as num?)?.toDouble() ?? 0.0;
      } else {
        // Fallback: Try getting from team balances
        AppLogger.warning('⚠️ User balance endpoint not available, using fallback');
        return 0.0;
      }
    } catch (e) {
      AppLogger.error('Error getting user balance: $e');
      return 0.0;
    }
  }
}

/// Result of admin balance adjustment
class AdminBalanceResult {
  final bool success;
  final String message;
  final double previousBalance;
  final double newBalance;
  final double adjustment;

  AdminBalanceResult({
    required this.success,
    required this.message,
    required this.previousBalance,
    required this.newBalance,
    required this.adjustment,
  });

  factory AdminBalanceResult.fromJson(Map<String, dynamic> json) {
    return AdminBalanceResult(
      success: json['success'] as bool? ?? true,
      message: json['message'] as String? ?? 'Balance updated',
      previousBalance: (json['previous_balance'] as num?)?.toDouble() ?? 0.0,
      newBalance: (json['new_balance'] as num?)?.toDouble() ?? 0.0,
      adjustment: (json['adjustment'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
