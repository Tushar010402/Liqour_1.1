import 'package:flutter/foundation.dart';
import '../../../core/services/dio_api_service.dart';
import '../../../core/models/api_response.dart';
import '../models/physical_audit_models.dart';

/// Physical Audit Service - Cash Counting & Inventory Verification
class PhysicalAuditService {
  final DioApiService _apiService;

  PhysicalAuditService(this._apiService);

  // ===========================================================================
  // AUDIT SCHEDULES
  // ===========================================================================

  /// Get all audit schedules for a shop
  Future<ApiResponse<List<AuditSchedule>>> getSchedules({
    String? shopId,
    AuditType? type,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('📋 PhysicalAuditService: Fetching schedules');
        debugPrint('   - Shop: ${shopId ?? "all"}');
      }

      final response = await _apiService.get(
        '/api/audits/schedules',
        queryParams: {
          if (shopId != null) 'shop_id': shopId,
          if (type != null) 'type': type.value,
        },
      );

      if (response.success && response.data != null) {
        final List<dynamic> items = response.data is List
            ? response.data as List
            : (response.data['schedules'] as List?) ?? [];
        final schedules = items
            .map((e) => AuditSchedule.fromJson(e as Map<String, dynamic>))
            .toList();
        if (kDebugMode) {
          debugPrint('✅ PhysicalAuditService: ${schedules.length} schedules');
        }
        return ApiResponse<List<AuditSchedule>>(
          success: true,
          data: schedules,
        );
      }

      return ApiResponse<List<AuditSchedule>>(
        success: false,
        message: response.message ?? 'Failed to fetch schedules',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ PhysicalAuditService: Error - $e');
      return ApiResponse<List<AuditSchedule>>(
        success: false,
        message: 'Error fetching schedules: $e',
      );
    }
  }

  /// Create a new audit schedule
  Future<ApiResponse<AuditSchedule>> createSchedule(CreateScheduleRequest request) async {
    try {
      if (kDebugMode) {
        debugPrint('📋 PhysicalAuditService: Creating schedule');
        debugPrint('   - Shop: ${request.shopId}');
        debugPrint('   - Type: ${request.type.displayName}');
      }

      final response = await _apiService.post(
        '/api/audits/schedules',
        body: request.toJson(),
      );

      if (response.success && response.data != null) {
        final schedule = AuditSchedule.fromJson(
          response.data as Map<String, dynamic>,
        );
        if (kDebugMode) {
          debugPrint('✅ PhysicalAuditService: Schedule created: ${schedule.id}');
        }
        return ApiResponse<AuditSchedule>(
          success: true,
          data: schedule,
        );
      }

      return ApiResponse<AuditSchedule>(
        success: false,
        message: response.message ?? 'Failed to create schedule',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ PhysicalAuditService: Error - $e');
      return ApiResponse<AuditSchedule>(
        success: false,
        message: 'Error creating schedule: $e',
      );
    }
  }

  /// Update an audit schedule
  Future<ApiResponse<AuditSchedule>> updateSchedule(
    String scheduleId,
    Map<String, dynamic> updates,
  ) async {
    try {
      if (kDebugMode) {
        debugPrint('📋 PhysicalAuditService: Updating schedule $scheduleId');
      }

      final response = await _apiService.put(
        '/api/audits/schedules/$scheduleId',
        body: updates,
      );

      if (response.success && response.data != null) {
        final schedule = AuditSchedule.fromJson(
          response.data as Map<String, dynamic>,
        );
        if (kDebugMode) debugPrint('✅ PhysicalAuditService: Schedule updated');
        return ApiResponse<AuditSchedule>(
          success: true,
          data: schedule,
        );
      }

      return ApiResponse<AuditSchedule>(
        success: false,
        message: response.message ?? 'Failed to update schedule',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ PhysicalAuditService: Error - $e');
      return ApiResponse<AuditSchedule>(
        success: false,
        message: 'Error updating schedule: $e',
      );
    }
  }

  /// Delete an audit schedule
  Future<ApiResponse<void>> deleteSchedule(String scheduleId) async {
    try {
      if (kDebugMode) {
        debugPrint('📋 PhysicalAuditService: Deleting schedule $scheduleId');
      }

      final response = await _apiService.delete(
        '/api/audits/schedules/$scheduleId',
      );

      if (response.success) {
        if (kDebugMode) debugPrint('✅ PhysicalAuditService: Schedule deleted');
        return ApiResponse<void>(success: true);
      }

      return ApiResponse<void>(
        success: false,
        message: response.message ?? 'Failed to delete schedule',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ PhysicalAuditService: Error - $e');
      return ApiResponse<void>(
        success: false,
        message: 'Error deleting schedule: $e',
      );
    }
  }

  // ===========================================================================
  // AUDIT SESSIONS
  // ===========================================================================

  /// Get audit sessions with filters
  Future<ApiResponse<List<AuditSession>>> getSessions(AuditQuery query) async {
    try {
      if (kDebugMode) {
        debugPrint('📋 PhysicalAuditService: Fetching sessions');
        debugPrint('   - Shop: ${query.shopId ?? "all"}');
        debugPrint('   - Status: ${query.status?.displayName ?? "all"}');
      }

      final response = await _apiService.get(
        '/api/audits/sessions',
        queryParams: query.toQueryParams(),
      );

      if (response.success && response.data != null) {
        final List<dynamic> items = response.data is List
            ? response.data as List
            : (response.data['sessions'] as List?) ?? [];
        final sessions = items
            .map((e) => AuditSession.fromJson(e as Map<String, dynamic>))
            .toList();
        if (kDebugMode) {
          debugPrint('✅ PhysicalAuditService: ${sessions.length} sessions');
        }
        return ApiResponse<List<AuditSession>>(
          success: true,
          data: sessions,
        );
      }

      return ApiResponse<List<AuditSession>>(
        success: false,
        message: response.message ?? 'Failed to fetch sessions',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ PhysicalAuditService: Error - $e');
      return ApiResponse<List<AuditSession>>(
        success: false,
        message: 'Error fetching sessions: $e',
      );
    }
  }

  /// Get a single audit session by ID
  Future<ApiResponse<AuditSession>> getSession(String sessionId) async {
    try {
      if (kDebugMode) {
        debugPrint('📋 PhysicalAuditService: Fetching session $sessionId');
      }

      final response = await _apiService.get('/api/audits/sessions/$sessionId');

      if (response.success && response.data != null) {
        final session = AuditSession.fromJson(
          response.data as Map<String, dynamic>,
        );
        if (kDebugMode) debugPrint('✅ PhysicalAuditService: Session loaded');
        return ApiResponse<AuditSession>(
          success: true,
          data: session,
        );
      }

      return ApiResponse<AuditSession>(
        success: false,
        message: response.message ?? 'Failed to fetch session',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ PhysicalAuditService: Error - $e');
      return ApiResponse<AuditSession>(
        success: false,
        message: 'Error fetching session: $e',
      );
    }
  }

  /// Start a new audit session
  Future<ApiResponse<AuditSession>> startSession(StartAuditRequest request) async {
    try {
      if (kDebugMode) {
        debugPrint('📋 PhysicalAuditService: Starting audit session');
        debugPrint('   - Shop: ${request.shopId}');
        debugPrint('   - Type: ${request.type.displayName}');
      }

      final response = await _apiService.post(
        '/api/audits/sessions/start',
        body: request.toJson(),
      );

      if (response.success && response.data != null) {
        final session = AuditSession.fromJson(
          response.data as Map<String, dynamic>,
        );
        if (kDebugMode) {
          debugPrint('✅ PhysicalAuditService: Session started: ${session.id}');
        }
        return ApiResponse<AuditSession>(
          success: true,
          data: session,
        );
      }

      return ApiResponse<AuditSession>(
        success: false,
        message: response.message ?? 'Failed to start session',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ PhysicalAuditService: Error - $e');
      return ApiResponse<AuditSession>(
        success: false,
        message: 'Error starting session: $e',
      );
    }
  }

  /// Submit cash audit data
  Future<ApiResponse<AuditSession>> submitCashAudit(
    String sessionId,
    CashAuditData cashData,
  ) async {
    try {
      if (kDebugMode) {
        debugPrint('📋 PhysicalAuditService: Submitting cash audit');
        debugPrint('   - Session: $sessionId');
        debugPrint('   - Actual: ₹${cashData.actualAmount}');
      }

      final response = await _apiService.post(
        '/api/audits/sessions/$sessionId/cash',
        body: cashData.toJson(),
      );

      if (response.success && response.data != null) {
        final session = AuditSession.fromJson(
          response.data as Map<String, dynamic>,
        );
        if (kDebugMode) debugPrint('✅ PhysicalAuditService: Cash audit submitted');
        return ApiResponse<AuditSession>(
          success: true,
          data: session,
        );
      }

      return ApiResponse<AuditSession>(
        success: false,
        message: response.message ?? 'Failed to submit cash audit',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ PhysicalAuditService: Error - $e');
      return ApiResponse<AuditSession>(
        success: false,
        message: 'Error submitting cash audit: $e',
      );
    }
  }

  /// Submit inventory audit data
  Future<ApiResponse<AuditSession>> submitInventoryAudit(
    String sessionId,
    InventoryAuditData inventoryData,
  ) async {
    try {
      if (kDebugMode) {
        debugPrint('📋 PhysicalAuditService: Submitting inventory audit');
        debugPrint('   - Session: $sessionId');
        debugPrint('   - Items checked: ${inventoryData.itemsChecked}');
      }

      final response = await _apiService.post(
        '/api/audits/sessions/$sessionId/inventory',
        body: inventoryData.toJson(),
      );

      if (response.success && response.data != null) {
        final session = AuditSession.fromJson(
          response.data as Map<String, dynamic>,
        );
        if (kDebugMode) debugPrint('✅ PhysicalAuditService: Inventory audit submitted');
        return ApiResponse<AuditSession>(
          success: true,
          data: session,
        );
      }

      return ApiResponse<AuditSession>(
        success: false,
        message: response.message ?? 'Failed to submit inventory audit',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ PhysicalAuditService: Error - $e');
      return ApiResponse<AuditSession>(
        success: false,
        message: 'Error submitting inventory audit: $e',
      );
    }
  }

  /// Complete an audit session
  Future<ApiResponse<AuditSession>> completeSession(
    String sessionId, {
    String? notes,
    List<String>? attachments,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('📋 PhysicalAuditService: Completing session $sessionId');
      }

      final response = await _apiService.post(
        '/api/audits/sessions/$sessionId/complete',
        body: {
          if (notes != null) 'notes': notes,
          if (attachments != null) 'attachments': attachments,
        },
      );

      if (response.success && response.data != null) {
        final session = AuditSession.fromJson(
          response.data as Map<String, dynamic>,
        );
        if (kDebugMode) debugPrint('✅ PhysicalAuditService: Session completed');
        return ApiResponse<AuditSession>(
          success: true,
          data: session,
        );
      }

      return ApiResponse<AuditSession>(
        success: false,
        message: response.message ?? 'Failed to complete session',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ PhysicalAuditService: Error - $e');
      return ApiResponse<AuditSession>(
        success: false,
        message: 'Error completing session: $e',
      );
    }
  }

  /// Cancel an audit session
  Future<ApiResponse<void>> cancelSession(String sessionId, String reason) async {
    try {
      if (kDebugMode) {
        debugPrint('📋 PhysicalAuditService: Cancelling session $sessionId');
      }

      final response = await _apiService.post(
        '/api/audits/sessions/$sessionId/cancel',
        body: {'reason': reason},
      );

      if (response.success) {
        if (kDebugMode) debugPrint('✅ PhysicalAuditService: Session cancelled');
        return ApiResponse<void>(success: true);
      }

      return ApiResponse<void>(
        success: false,
        message: response.message ?? 'Failed to cancel session',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ PhysicalAuditService: Error - $e');
      return ApiResponse<void>(
        success: false,
        message: 'Error cancelling session: $e',
      );
    }
  }

  // ===========================================================================
  // AUDIT SUMMARIES & REPORTS
  // ===========================================================================

  /// Get audit summary for a shop
  Future<ApiResponse<AuditSummary>> getSummary({
    required String shopId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('📋 PhysicalAuditService: Fetching audit summary');
        debugPrint('   - Shop: $shopId');
      }

      final response = await _apiService.get(
        '/api/audits/summary',
        queryParams: {
          'shop_id': shopId,
          if (startDate != null) 'start_date': startDate.toIso8601String(),
          if (endDate != null) 'end_date': endDate.toIso8601String(),
        },
      );

      if (response.success && response.data != null) {
        final summary = AuditSummary.fromJson(
          response.data as Map<String, dynamic>,
        );
        if (kDebugMode) {
          debugPrint('✅ PhysicalAuditService: Summary loaded');
          debugPrint('   - Total scheduled: ${summary.totalScheduled}');
        }
        return ApiResponse<AuditSummary>(
          success: true,
          data: summary,
        );
      }

      return ApiResponse<AuditSummary>(
        success: false,
        message: response.message ?? 'Failed to fetch summary',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ PhysicalAuditService: Error - $e');
      return ApiResponse<AuditSummary>(
        success: false,
        message: 'Error fetching summary: $e',
      );
    }
  }

  /// Get pending audits (scheduled but not started)
  Future<ApiResponse<List<AuditSchedule>>> getPendingAudits({
    String? shopId,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('📋 PhysicalAuditService: Fetching pending audits');
      }

      final response = await _apiService.get(
        '/api/audits/pending',
        queryParams: {
          if (shopId != null) 'shop_id': shopId,
        },
      );

      if (response.success && response.data != null) {
        final List<dynamic> items = response.data is List
            ? response.data as List
            : (response.data['pending'] as List?) ?? [];
        final pending = items
            .map((e) => AuditSchedule.fromJson(e as Map<String, dynamic>))
            .toList();
        if (kDebugMode) {
          debugPrint('✅ PhysicalAuditService: ${pending.length} pending audits');
        }
        return ApiResponse<List<AuditSchedule>>(
          success: true,
          data: pending,
        );
      }

      return ApiResponse<List<AuditSchedule>>(
        success: false,
        message: response.message ?? 'Failed to fetch pending audits',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ PhysicalAuditService: Error - $e');
      return ApiResponse<List<AuditSchedule>>(
        success: false,
        message: 'Error fetching pending audits: $e',
      );
    }
  }

  /// Get variance report
  Future<ApiResponse<Map<String, dynamic>>> getVarianceReport({
    String? shopId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('📋 PhysicalAuditService: Fetching variance report');
      }

      final response = await _apiService.get(
        '/api/audits/reports/variance',
        queryParams: {
          if (shopId != null) 'shop_id': shopId,
          if (startDate != null) 'start_date': startDate.toIso8601String(),
          if (endDate != null) 'end_date': endDate.toIso8601String(),
        },
      );

      if (response.success && response.data != null) {
        if (kDebugMode) debugPrint('✅ PhysicalAuditService: Variance report loaded');
        return ApiResponse<Map<String, dynamic>>(
          success: true,
          data: response.data as Map<String, dynamic>,
        );
      }

      return ApiResponse<Map<String, dynamic>>(
        success: false,
        message: response.message ?? 'Failed to fetch variance report',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ PhysicalAuditService: Error - $e');
      return ApiResponse<Map<String, dynamic>>(
        success: false,
        message: 'Error fetching variance report: $e',
      );
    }
  }

  /// Export audit report
  Future<ApiResponse<String>> exportReport({
    required String shopId,
    required String format, // 'pdf', 'excel', 'csv'
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('📋 PhysicalAuditService: Exporting report as $format');
      }

      final response = await _apiService.get(
        '/api/audits/reports/export',
        queryParams: {
          'shop_id': shopId,
          'format': format,
          if (startDate != null) 'start_date': startDate.toIso8601String(),
          if (endDate != null) 'end_date': endDate.toIso8601String(),
        },
      );

      if (response.success && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        final downloadUrl = data['download_url'] as String?;
        if (downloadUrl != null) {
          if (kDebugMode) debugPrint('✅ PhysicalAuditService: Export ready');
          return ApiResponse<String>(
            success: true,
            data: downloadUrl,
          );
        }
      }

      return ApiResponse<String>(
        success: false,
        message: response.message ?? 'Failed to export report',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ PhysicalAuditService: Error - $e');
      return ApiResponse<String>(
        success: false,
        message: 'Error exporting report: $e',
      );
    }
  }

  // ===========================================================================
  // INVENTORY ITEMS (for audit selection)
  // ===========================================================================

  /// Get inventory items for audit (simplified list)
  Future<ApiResponse<List<InventoryAuditItem>>> getInventoryItems({
    required String shopId,
    String? category,
    String? searchQuery,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('📋 PhysicalAuditService: Fetching inventory items for audit');
      }

      final response = await _apiService.get(
        '/api/audits/inventory-items',
        queryParams: {
          'shop_id': shopId,
          if (category != null) 'category': category,
          if (searchQuery != null) 'search': searchQuery,
          'limit': limit.toString(),
          'offset': offset.toString(),
        },
      );

      if (response.success && response.data != null) {
        final List<dynamic> items = response.data is List
            ? response.data as List
            : (response.data['items'] as List?) ?? [];
        final inventoryItems = items
            .map((e) => InventoryAuditItem.fromJson(e as Map<String, dynamic>))
            .toList();
        if (kDebugMode) {
          debugPrint('✅ PhysicalAuditService: ${inventoryItems.length} items');
        }
        return ApiResponse<List<InventoryAuditItem>>(
          success: true,
          data: inventoryItems,
        );
      }

      return ApiResponse<List<InventoryAuditItem>>(
        success: false,
        message: response.message ?? 'Failed to fetch inventory items',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ PhysicalAuditService: Error - $e');
      return ApiResponse<List<InventoryAuditItem>>(
        success: false,
        message: 'Error fetching inventory items: $e',
      );
    }
  }

  /// Get expected cash amount for a shop
  Future<ApiResponse<double>> getExpectedCash(String shopId) async {
    try {
      if (kDebugMode) {
        debugPrint('📋 PhysicalAuditService: Getting expected cash for $shopId');
      }

      final response = await _apiService.get(
        '/api/audits/expected-cash',
        queryParams: {'shop_id': shopId},
      );

      if (response.success && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        final expected = (data['expected_amount'] as num?)?.toDouble() ?? 0.0;
        if (kDebugMode) {
          debugPrint('✅ PhysicalAuditService: Expected cash = ₹$expected');
        }
        return ApiResponse<double>(
          success: true,
          data: expected,
        );
      }

      return ApiResponse<double>(
        success: false,
        message: response.message ?? 'Failed to fetch expected cash',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ PhysicalAuditService: Error - $e');
      return ApiResponse<double>(
        success: false,
        message: 'Error fetching expected cash: $e',
      );
    }
  }
}
