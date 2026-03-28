import 'package:flutter/foundation.dart';
import '../../../core/services/dio_api_service.dart';
import '../../../core/models/api_response.dart';
import '../models/tips_models.dart';

/// Tips Management Service
class TipsService {
  final DioApiService _apiService;

  TipsService(this._apiService);

  // ===========================================================================
  // TIP ENTRIES
  // ===========================================================================

  /// Get tip entries with filters
  Future<ApiResponse<List<TipEntry>>> getTips(TipsQuery query) async {
    try {
      if (kDebugMode) {
        debugPrint('💰 TipsService: Fetching tips');
      }

      final response = await _apiService.get(
        '/api/tips',
        queryParams: query.toQueryParams(),
      );

      if (response.success && response.data != null) {
        final List<dynamic> items = response.data is List
            ? response.data as List
            : (response.data['tips'] as List?) ?? [];
        final tips = items
            .map((e) => TipEntry.fromJson(e as Map<String, dynamic>))
            .toList();
        if (kDebugMode) {
          debugPrint('✅ TipsService: ${tips.length} tips');
        }
        return ApiResponse<List<TipEntry>>(success: true, data: tips);
      }

      return ApiResponse<List<TipEntry>>(
        success: false,
        message: response.message ?? 'Failed to fetch tips',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ TipsService: Error - $e');
      return ApiResponse<List<TipEntry>>(
        success: false,
        message: 'Error fetching tips: $e',
      );
    }
  }

  /// Create a tip entry
  Future<ApiResponse<TipEntry>> createTip(CreateTipRequest request) async {
    try {
      if (kDebugMode) {
        debugPrint('💰 TipsService: Creating tip');
        debugPrint('   - Amount: ₹${request.amount}');
      }

      final response = await _apiService.post(
        '/api/tips',
        body: request.toJson(),
      );

      if (response.success && response.data != null) {
        final tip = TipEntry.fromJson(response.data as Map<String, dynamic>);
        if (kDebugMode) debugPrint('✅ TipsService: Tip created: ${tip.id}');
        return ApiResponse<TipEntry>(success: true, data: tip);
      }

      return ApiResponse<TipEntry>(
        success: false,
        message: response.message ?? 'Failed to create tip',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ TipsService: Error - $e');
      return ApiResponse<TipEntry>(
        success: false,
        message: 'Error creating tip: $e',
      );
    }
  }

  /// Delete a tip entry
  Future<ApiResponse<void>> deleteTip(String tipId) async {
    try {
      if (kDebugMode) debugPrint('💰 TipsService: Deleting tip $tipId');

      final response = await _apiService.delete('/api/tips/$tipId');

      if (response.success) {
        if (kDebugMode) debugPrint('✅ TipsService: Tip deleted');
        return ApiResponse<void>(success: true);
      }

      return ApiResponse<void>(
        success: false,
        message: response.message ?? 'Failed to delete tip',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ TipsService: Error - $e');
      return ApiResponse<void>(
        success: false,
        message: 'Error deleting tip: $e',
      );
    }
  }

  // ===========================================================================
  // TIP POOLS
  // ===========================================================================

  /// Get tip pools for a shop
  Future<ApiResponse<List<TipPool>>> getPools({
    String? shopId,
    bool? isClosed,
  }) async {
    try {
      if (kDebugMode) debugPrint('💰 TipsService: Fetching pools');

      final response = await _apiService.get(
        '/api/tips/pools',
        queryParams: {
          if (shopId != null) 'shop_id': shopId,
          if (isClosed != null) 'is_closed': isClosed.toString(),
        },
      );

      if (response.success && response.data != null) {
        final List<dynamic> items = response.data is List
            ? response.data as List
            : (response.data['pools'] as List?) ?? [];
        final pools = items
            .map((e) => TipPool.fromJson(e as Map<String, dynamic>))
            .toList();
        if (kDebugMode) debugPrint('✅ TipsService: ${pools.length} pools');
        return ApiResponse<List<TipPool>>(success: true, data: pools);
      }

      return ApiResponse<List<TipPool>>(
        success: false,
        message: response.message ?? 'Failed to fetch pools',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ TipsService: Error - $e');
      return ApiResponse<List<TipPool>>(
        success: false,
        message: 'Error fetching pools: $e',
      );
    }
  }

  /// Get a single pool by ID
  Future<ApiResponse<TipPool>> getPool(String poolId) async {
    try {
      if (kDebugMode) debugPrint('💰 TipsService: Fetching pool $poolId');

      final response = await _apiService.get('/api/tips/pools/$poolId');

      if (response.success && response.data != null) {
        final pool = TipPool.fromJson(response.data as Map<String, dynamic>);
        if (kDebugMode) debugPrint('✅ TipsService: Pool loaded');
        return ApiResponse<TipPool>(success: true, data: pool);
      }

      return ApiResponse<TipPool>(
        success: false,
        message: response.message ?? 'Failed to fetch pool',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ TipsService: Error - $e');
      return ApiResponse<TipPool>(
        success: false,
        message: 'Error fetching pool: $e',
      );
    }
  }

  /// Create a tip pool
  Future<ApiResponse<TipPool>> createPool(CreatePoolRequest request) async {
    try {
      if (kDebugMode) {
        debugPrint('💰 TipsService: Creating pool');
        debugPrint('   - Name: ${request.name}');
      }

      final response = await _apiService.post(
        '/api/tips/pools',
        body: request.toJson(),
      );

      if (response.success && response.data != null) {
        final pool = TipPool.fromJson(response.data as Map<String, dynamic>);
        if (kDebugMode) debugPrint('✅ TipsService: Pool created: ${pool.id}');
        return ApiResponse<TipPool>(success: true, data: pool);
      }

      return ApiResponse<TipPool>(
        success: false,
        message: response.message ?? 'Failed to create pool',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ TipsService: Error - $e');
      return ApiResponse<TipPool>(
        success: false,
        message: 'Error creating pool: $e',
      );
    }
  }

  /// Close a tip pool
  Future<ApiResponse<TipPool>> closePool(String poolId) async {
    try {
      if (kDebugMode) debugPrint('💰 TipsService: Closing pool $poolId');

      final response = await _apiService.post(
        '/api/tips/pools/$poolId/close',
        body: {},
      );

      if (response.success && response.data != null) {
        final pool = TipPool.fromJson(response.data as Map<String, dynamic>);
        if (kDebugMode) debugPrint('✅ TipsService: Pool closed');
        return ApiResponse<TipPool>(success: true, data: pool);
      }

      return ApiResponse<TipPool>(
        success: false,
        message: response.message ?? 'Failed to close pool',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ TipsService: Error - $e');
      return ApiResponse<TipPool>(
        success: false,
        message: 'Error closing pool: $e',
      );
    }
  }

  /// Add employee to pool
  Future<ApiResponse<void>> addEmployeeToPool(
    String poolId,
    String employeeId, {
    double points = 1.0,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('💰 TipsService: Adding employee to pool');
      }

      final response = await _apiService.post(
        '/api/tips/pools/$poolId/employees',
        body: {
          'employee_id': employeeId,
          'points': points,
        },
      );

      if (response.success) {
        if (kDebugMode) debugPrint('✅ TipsService: Employee added to pool');
        return ApiResponse<void>(success: true);
      }

      return ApiResponse<void>(
        success: false,
        message: response.message ?? 'Failed to add employee',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ TipsService: Error - $e');
      return ApiResponse<void>(
        success: false,
        message: 'Error adding employee: $e',
      );
    }
  }

  /// Calculate pool distribution preview
  Future<ApiResponse<List<TipPoolEmployee>>> previewDistribution(
    String poolId,
  ) async {
    try {
      if (kDebugMode) {
        debugPrint('💰 TipsService: Previewing distribution');
      }

      final response = await _apiService.get(
        '/api/tips/pools/$poolId/distribution-preview',
      );

      if (response.success && response.data != null) {
        final List<dynamic> items = response.data is List
            ? response.data as List
            : (response.data['employees'] as List?) ?? [];
        final employees = items
            .map((e) => TipPoolEmployee.fromJson(e as Map<String, dynamic>))
            .toList();
        if (kDebugMode) {
          debugPrint('✅ TipsService: Distribution preview ready');
        }
        return ApiResponse<List<TipPoolEmployee>>(
          success: true,
          data: employees,
        );
      }

      return ApiResponse<List<TipPoolEmployee>>(
        success: false,
        message: response.message ?? 'Failed to preview distribution',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ TipsService: Error - $e');
      return ApiResponse<List<TipPoolEmployee>>(
        success: false,
        message: 'Error previewing distribution: $e',
      );
    }
  }

  // ===========================================================================
  // PAYOUTS
  // ===========================================================================

  /// Get payouts
  Future<ApiResponse<List<TipPayout>>> getPayouts({
    String? shopId,
    PayoutStatus? status,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      if (kDebugMode) debugPrint('💰 TipsService: Fetching payouts');

      final response = await _apiService.get(
        '/api/tips/payouts',
        queryParams: {
          if (shopId != null) 'shop_id': shopId,
          if (status != null) 'status': status.apiValue,
          'limit': limit.toString(),
          'offset': offset.toString(),
        },
      );

      if (response.success && response.data != null) {
        final List<dynamic> items = response.data is List
            ? response.data as List
            : (response.data['payouts'] as List?) ?? [];
        final payouts = items
            .map((e) => TipPayout.fromJson(e as Map<String, dynamic>))
            .toList();
        if (kDebugMode) debugPrint('✅ TipsService: ${payouts.length} payouts');
        return ApiResponse<List<TipPayout>>(success: true, data: payouts);
      }

      return ApiResponse<List<TipPayout>>(
        success: false,
        message: response.message ?? 'Failed to fetch payouts',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ TipsService: Error - $e');
      return ApiResponse<List<TipPayout>>(
        success: false,
        message: 'Error fetching payouts: $e',
      );
    }
  }

  /// Get a single payout by ID
  Future<ApiResponse<TipPayout>> getPayout(String payoutId) async {
    try {
      if (kDebugMode) debugPrint('💰 TipsService: Fetching payout $payoutId');

      final response = await _apiService.get('/api/tips/payouts/$payoutId');

      if (response.success && response.data != null) {
        final payout = TipPayout.fromJson(response.data as Map<String, dynamic>);
        if (kDebugMode) debugPrint('✅ TipsService: Payout loaded');
        return ApiResponse<TipPayout>(success: true, data: payout);
      }

      return ApiResponse<TipPayout>(
        success: false,
        message: response.message ?? 'Failed to fetch payout',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ TipsService: Error - $e');
      return ApiResponse<TipPayout>(
        success: false,
        message: 'Error fetching payout: $e',
      );
    }
  }

  /// Create a payout batch
  Future<ApiResponse<TipPayout>> createPayout(CreatePayoutRequest request) async {
    try {
      if (kDebugMode) {
        debugPrint('💰 TipsService: Creating payout');
      }

      final response = await _apiService.post(
        '/api/tips/payouts',
        body: request.toJson(),
      );

      if (response.success && response.data != null) {
        final payout = TipPayout.fromJson(response.data as Map<String, dynamic>);
        if (kDebugMode) {
          debugPrint('✅ TipsService: Payout created: ${payout.id}');
        }
        return ApiResponse<TipPayout>(success: true, data: payout);
      }

      return ApiResponse<TipPayout>(
        success: false,
        message: response.message ?? 'Failed to create payout',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ TipsService: Error - $e');
      return ApiResponse<TipPayout>(
        success: false,
        message: 'Error creating payout: $e',
      );
    }
  }

  /// Approve a payout
  Future<ApiResponse<TipPayout>> approvePayout(String payoutId) async {
    try {
      if (kDebugMode) debugPrint('💰 TipsService: Approving payout $payoutId');

      final response = await _apiService.post(
        '/api/tips/payouts/$payoutId/approve',
        body: {},
      );

      if (response.success && response.data != null) {
        final payout = TipPayout.fromJson(response.data as Map<String, dynamic>);
        if (kDebugMode) debugPrint('✅ TipsService: Payout approved');
        return ApiResponse<TipPayout>(success: true, data: payout);
      }

      return ApiResponse<TipPayout>(
        success: false,
        message: response.message ?? 'Failed to approve payout',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ TipsService: Error - $e');
      return ApiResponse<TipPayout>(
        success: false,
        message: 'Error approving payout: $e',
      );
    }
  }

  /// Mark payout as paid
  Future<ApiResponse<TipPayout>> markPaid(String payoutId) async {
    try {
      if (kDebugMode) debugPrint('💰 TipsService: Marking payout $payoutId as paid');

      final response = await _apiService.post(
        '/api/tips/payouts/$payoutId/pay',
        body: {},
      );

      if (response.success && response.data != null) {
        final payout = TipPayout.fromJson(response.data as Map<String, dynamic>);
        if (kDebugMode) debugPrint('✅ TipsService: Payout marked as paid');
        return ApiResponse<TipPayout>(success: true, data: payout);
      }

      return ApiResponse<TipPayout>(
        success: false,
        message: response.message ?? 'Failed to mark payout as paid',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ TipsService: Error - $e');
      return ApiResponse<TipPayout>(
        success: false,
        message: 'Error marking payout as paid: $e',
      );
    }
  }

  /// Cancel a payout
  Future<ApiResponse<void>> cancelPayout(String payoutId, String reason) async {
    try {
      if (kDebugMode) debugPrint('💰 TipsService: Cancelling payout $payoutId');

      final response = await _apiService.post(
        '/api/tips/payouts/$payoutId/cancel',
        body: {'reason': reason},
      );

      if (response.success) {
        if (kDebugMode) debugPrint('✅ TipsService: Payout cancelled');
        return ApiResponse<void>(success: true);
      }

      return ApiResponse<void>(
        success: false,
        message: response.message ?? 'Failed to cancel payout',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ TipsService: Error - $e');
      return ApiResponse<void>(
        success: false,
        message: 'Error cancelling payout: $e',
      );
    }
  }

  // ===========================================================================
  // SUMMARY & SETTINGS
  // ===========================================================================

  /// Get tips summary
  Future<ApiResponse<TipsSummary>> getSummary({
    required String shopId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      if (kDebugMode) debugPrint('💰 TipsService: Fetching summary');

      final response = await _apiService.get(
        '/api/tips/summary',
        queryParams: {
          'shop_id': shopId,
          if (startDate != null) 'start_date': startDate.toIso8601String(),
          if (endDate != null) 'end_date': endDate.toIso8601String(),
        },
      );

      if (response.success && response.data != null) {
        final summary = TipsSummary.fromJson(
          response.data as Map<String, dynamic>,
        );
        if (kDebugMode) {
          debugPrint('✅ TipsService: Summary loaded');
          debugPrint('   - Total: ₹${summary.totalTips}');
        }
        return ApiResponse<TipsSummary>(success: true, data: summary);
      }

      return ApiResponse<TipsSummary>(
        success: false,
        message: response.message ?? 'Failed to fetch summary',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ TipsService: Error - $e');
      return ApiResponse<TipsSummary>(
        success: false,
        message: 'Error fetching summary: $e',
      );
    }
  }

  /// Get tip settings
  Future<ApiResponse<TipSettings>> getSettings(String shopId) async {
    try {
      if (kDebugMode) debugPrint('💰 TipsService: Fetching settings');

      final response = await _apiService.get(
        '/api/tips/settings',
        queryParams: {'shop_id': shopId},
      );

      if (response.success && response.data != null) {
        final settings = TipSettings.fromJson(
          response.data as Map<String, dynamic>,
        );
        if (kDebugMode) debugPrint('✅ TipsService: Settings loaded');
        return ApiResponse<TipSettings>(success: true, data: settings);
      }

      return ApiResponse<TipSettings>(
        success: false,
        message: response.message ?? 'Failed to fetch settings',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ TipsService: Error - $e');
      return ApiResponse<TipSettings>(
        success: false,
        message: 'Error fetching settings: $e',
      );
    }
  }

  /// Update tip settings
  Future<ApiResponse<TipSettings>> updateSettings(TipSettings settings) async {
    try {
      if (kDebugMode) debugPrint('💰 TipsService: Updating settings');

      final response = await _apiService.put(
        '/api/tips/settings',
        body: settings.toJson(),
      );

      if (response.success && response.data != null) {
        final updated = TipSettings.fromJson(
          response.data as Map<String, dynamic>,
        );
        if (kDebugMode) debugPrint('✅ TipsService: Settings updated');
        return ApiResponse<TipSettings>(success: true, data: updated);
      }

      return ApiResponse<TipSettings>(
        success: false,
        message: response.message ?? 'Failed to update settings',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ TipsService: Error - $e');
      return ApiResponse<TipSettings>(
        success: false,
        message: 'Error updating settings: $e',
      );
    }
  }
}
