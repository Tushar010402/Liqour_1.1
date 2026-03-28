// =============================================================================
// THEFT DETECTION SERVICE
// API Service for Z-Score Anomaly Detection
// =============================================================================

import '../../../core/models/api_response.dart';
import '../../../core/services/dio_api_service.dart';
import '../models/theft_models.dart';

class TheftDetectionService {
  final DioApiService _apiService;

  TheftDetectionService(this._apiService);

  // ===========================================================================
  // ANOMALIES
  // ===========================================================================

  /// Get all anomalies with optional filters
  Future<ApiResponse<List<Anomaly>>> getAnomalies({
    String? shopId,
    AnomalyType? type,
    SeverityLevel? severity,
    bool? isAcknowledged,
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
    int? offset,
  }) async {
    try {
      final queryParams = <String, dynamic>{};

      if (shopId != null) queryParams['shop_id'] = shopId;
      if (type != null) queryParams['type'] = _anomalyTypeToString(type);
      if (severity != null) queryParams['severity'] = severity.name;
      if (isAcknowledged != null) {
        queryParams['is_acknowledged'] = isAcknowledged.toString();
      }
      if (startDate != null) {
        queryParams['start_date'] = startDate.toIso8601String();
      }
      if (endDate != null) {
        queryParams['end_date'] = endDate.toIso8601String();
      }
      if (limit != null) queryParams['limit'] = limit.toString();
      if (offset != null) queryParams['offset'] = offset.toString();

      final response = await _apiService.get(
        '/api/theft/anomalies',
        queryParams: queryParams,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['data'] ?? response.data ?? [];
        final anomalies = data.map((e) => Anomaly.fromJson(e)).toList();
        return ApiResponse(success: true, data: anomalies);
      }

      return ApiResponse(
        success: false,
        message: response.data['message'] ?? 'Failed to fetch anomalies',
      );
    } catch (e) {
      return ApiResponse(success: false, message: e.toString());
    }
  }

  /// Get a single anomaly by ID
  Future<ApiResponse<Anomaly>> getAnomaly(String anomalyId) async {
    try {
      final response = await _apiService.get('/api/theft/anomalies/$anomalyId');

      if (response.statusCode == 200) {
        final data = response.data['data'] ?? response.data;
        return ApiResponse(success: true, data: Anomaly.fromJson(data));
      }

      return ApiResponse(
        success: false,
        message: response.data['message'] ?? 'Failed to fetch anomaly',
      );
    } catch (e) {
      return ApiResponse(success: false, message: e.toString());
    }
  }

  /// Acknowledge an anomaly
  Future<ApiResponse<void>> acknowledgeAnomaly(String anomalyId) async {
    try {
      final response = await _apiService.post(
        '/api/theft/anomalies/$anomalyId/acknowledge',
        body: {},
      );

      if (response.statusCode == 200) {
        return ApiResponse(success: true);
      }

      return ApiResponse(
        success: false,
        message: response.data['message'] ?? 'Failed to acknowledge anomaly',
      );
    } catch (e) {
      return ApiResponse(success: false, message: e.toString());
    }
  }

  /// Dismiss an anomaly (mark as false positive)
  Future<ApiResponse<void>> dismissAnomaly(
    String anomalyId, {
    String? reason,
  }) async {
    try {
      final response = await _apiService.post(
        '/api/theft/anomalies/$anomalyId/dismiss',
        body: {'reason': reason ?? 'Marked as false positive'},
      );

      if (response.statusCode == 200) {
        return ApiResponse(success: true);
      }

      return ApiResponse(
        success: false,
        message: response.data['message'] ?? 'Failed to dismiss anomaly',
      );
    } catch (e) {
      return ApiResponse(success: false, message: e.toString());
    }
  }

  /// Run detection analysis manually
  Future<ApiResponse<List<Anomaly>>> runDetection({
    required String shopId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final response = await _apiService.post(
        '/api/theft/detect',
        body: {
          'shop_id': shopId,
          if (startDate != null) 'start_date': startDate.toIso8601String(),
          if (endDate != null) 'end_date': endDate.toIso8601String(),
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['data'] ?? response.data ?? [];
        final anomalies = data.map((e) => Anomaly.fromJson(e)).toList();
        return ApiResponse(success: true, data: anomalies);
      }

      return ApiResponse(
        success: false,
        message: response.data['message'] ?? 'Failed to run detection',
      );
    } catch (e) {
      return ApiResponse(success: false, message: e.toString());
    }
  }

  // ===========================================================================
  // INVESTIGATIONS
  // ===========================================================================

  /// Get all investigations
  Future<ApiResponse<List<Investigation>>> getInvestigations({
    String? shopId,
    InvestigationStatus? status,
    String? assigneeId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final queryParams = <String, dynamic>{};

      if (shopId != null) queryParams['shop_id'] = shopId;
      if (status != null) queryParams['status'] = _statusToString(status);
      if (assigneeId != null) queryParams['assignee_id'] = assigneeId;
      if (startDate != null) {
        queryParams['start_date'] = startDate.toIso8601String();
      }
      if (endDate != null) {
        queryParams['end_date'] = endDate.toIso8601String();
      }

      final response = await _apiService.get(
        '/api/theft/investigations',
        queryParams: queryParams,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['data'] ?? response.data ?? [];
        final investigations =
            data.map((e) => Investigation.fromJson(e)).toList();
        return ApiResponse(success: true, data: investigations);
      }

      return ApiResponse(
        success: false,
        message: response.data['message'] ?? 'Failed to fetch investigations',
      );
    } catch (e) {
      return ApiResponse(success: false, message: e.toString());
    }
  }

  /// Get a single investigation by ID
  Future<ApiResponse<Investigation>> getInvestigation(
    String investigationId,
  ) async {
    try {
      final response = await _apiService.get(
        '/api/theft/investigations/$investigationId',
      );

      if (response.statusCode == 200) {
        final data = response.data['data'] ?? response.data;
        return ApiResponse(success: true, data: Investigation.fromJson(data));
      }

      return ApiResponse(
        success: false,
        message: response.data['message'] ?? 'Failed to fetch investigation',
      );
    } catch (e) {
      return ApiResponse(success: false, message: e.toString());
    }
  }

  /// Create a new investigation
  Future<ApiResponse<Investigation>> createInvestigation(
    CreateInvestigationRequest request,
  ) async {
    try {
      final response = await _apiService.post(
        '/api/theft/investigations',
        body: request.toJson(),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = response.data['data'] ?? response.data;
        return ApiResponse(success: true, data: Investigation.fromJson(data));
      }

      return ApiResponse(
        success: false,
        message: response.data['message'] ?? 'Failed to create investigation',
      );
    } catch (e) {
      return ApiResponse(success: false, message: e.toString());
    }
  }

  /// Update an investigation
  Future<ApiResponse<Investigation>> updateInvestigation(
    String investigationId,
    UpdateInvestigationRequest request,
  ) async {
    try {
      final response = await _apiService.put(
        '/api/theft/investigations/$investigationId',
        body: request.toJson(),
      );

      if (response.statusCode == 200) {
        final data = response.data['data'] ?? response.data;
        return ApiResponse(success: true, data: Investigation.fromJson(data));
      }

      return ApiResponse(
        success: false,
        message: response.data['message'] ?? 'Failed to update investigation',
      );
    } catch (e) {
      return ApiResponse(success: false, message: e.toString());
    }
  }

  /// Add a note to an investigation
  Future<ApiResponse<InvestigationNote>> addNote(
    String investigationId,
    AddNoteRequest request,
  ) async {
    try {
      final response = await _apiService.post(
        '/api/theft/investigations/$investigationId/notes',
        body: request.toJson(),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = response.data['data'] ?? response.data;
        return ApiResponse(
          success: true,
          data: InvestigationNote.fromJson(data),
        );
      }

      return ApiResponse(
        success: false,
        message: response.data['message'] ?? 'Failed to add note',
      );
    } catch (e) {
      return ApiResponse(success: false, message: e.toString());
    }
  }

  /// Assign investigation to a user
  Future<ApiResponse<void>> assignInvestigation(
    String investigationId,
    String assigneeId,
  ) async {
    try {
      final response = await _apiService.post(
        '/api/theft/investigations/$investigationId/assign',
        body: {'assignee_id': assigneeId},
      );

      if (response.statusCode == 200) {
        return ApiResponse(success: true);
      }

      return ApiResponse(
        success: false,
        message: response.data['message'] ?? 'Failed to assign investigation',
      );
    } catch (e) {
      return ApiResponse(success: false, message: e.toString());
    }
  }

  /// Resolve an investigation
  Future<ApiResponse<void>> resolveInvestigation(
    String investigationId, {
    required ResolutionType resolution,
    required String notes,
    double? actualLoss,
    double? recoveredAmount,
  }) async {
    try {
      final response = await _apiService.post(
        '/api/theft/investigations/$investigationId/resolve',
        body: {
          'resolution': resolution.name,
          'resolution_notes': notes,
          if (actualLoss != null) 'actual_loss': actualLoss,
          if (recoveredAmount != null) 'recovered_amount': recoveredAmount,
        },
      );

      if (response.statusCode == 200) {
        return ApiResponse(success: true);
      }

      return ApiResponse(
        success: false,
        message: response.data['message'] ?? 'Failed to resolve investigation',
      );
    } catch (e) {
      return ApiResponse(success: false, message: e.toString());
    }
  }

  /// Escalate an investigation
  Future<ApiResponse<void>> escalateInvestigation(
    String investigationId, {
    String? reason,
  }) async {
    try {
      final response = await _apiService.post(
        '/api/theft/investigations/$investigationId/escalate',
        body: {'reason': reason},
      );

      if (response.statusCode == 200) {
        return ApiResponse(success: true);
      }

      return ApiResponse(
        success: false,
        message:
            response.data['message'] ?? 'Failed to escalate investigation',
      );
    } catch (e) {
      return ApiResponse(success: false, message: e.toString());
    }
  }

  // ===========================================================================
  // ALERTS
  // ===========================================================================

  /// Get all alerts
  Future<ApiResponse<List<TheftAlert>>> getAlerts({
    String? shopId,
    bool? isRead,
    AlertPriority? priority,
    int? limit,
  }) async {
    try {
      final queryParams = <String, dynamic>{};

      if (shopId != null) queryParams['shop_id'] = shopId;
      if (isRead != null) queryParams['is_read'] = isRead.toString();
      if (priority != null) queryParams['priority'] = priority.name;
      if (limit != null) queryParams['limit'] = limit.toString();

      final response = await _apiService.get(
        '/api/theft/alerts',
        queryParams: queryParams,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['data'] ?? response.data ?? [];
        final alerts = data.map((e) => TheftAlert.fromJson(e)).toList();
        return ApiResponse(success: true, data: alerts);
      }

      return ApiResponse(
        success: false,
        message: response.data['message'] ?? 'Failed to fetch alerts',
      );
    } catch (e) {
      return ApiResponse(success: false, message: e.toString());
    }
  }

  /// Mark alert as read
  Future<ApiResponse<void>> markAlertRead(String alertId) async {
    try {
      final response = await _apiService.post(
        '/api/theft/alerts/$alertId/read',
        body: {},
      );

      if (response.statusCode == 200) {
        return ApiResponse(success: true);
      }

      return ApiResponse(
        success: false,
        message: response.data['message'] ?? 'Failed to mark alert as read',
      );
    } catch (e) {
      return ApiResponse(success: false, message: e.toString());
    }
  }

  /// Dismiss an alert
  Future<ApiResponse<void>> dismissAlert(String alertId) async {
    try {
      final response = await _apiService.post(
        '/api/theft/alerts/$alertId/dismiss',
        body: {},
      );

      if (response.statusCode == 200) {
        return ApiResponse(success: true);
      }

      return ApiResponse(
        success: false,
        message: response.data['message'] ?? 'Failed to dismiss alert',
      );
    } catch (e) {
      return ApiResponse(success: false, message: e.toString());
    }
  }

  /// Mark all alerts as read
  Future<ApiResponse<void>> markAllAlertsRead({String? shopId}) async {
    try {
      final response = await _apiService.post(
        '/api/theft/alerts/read-all',
        body: shopId != null ? {'shop_id': shopId} : {},
      );

      if (response.statusCode == 200) {
        return ApiResponse(success: true);
      }

      return ApiResponse(
        success: false,
        message:
            response.data['message'] ?? 'Failed to mark all alerts as read',
      );
    } catch (e) {
      return ApiResponse(success: false, message: e.toString());
    }
  }

  // ===========================================================================
  // SUMMARY & ANALYTICS
  // ===========================================================================

  /// Get theft detection summary
  Future<ApiResponse<TheftSummary>> getSummary({
    String? shopId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final queryParams = <String, dynamic>{};

      if (shopId != null) queryParams['shop_id'] = shopId;
      if (startDate != null) {
        queryParams['start_date'] = startDate.toIso8601String();
      }
      if (endDate != null) {
        queryParams['end_date'] = endDate.toIso8601String();
      }

      final response = await _apiService.get(
        '/api/theft/summary',
        queryParams: queryParams,
      );

      if (response.statusCode == 200) {
        final data = response.data['data'] ?? response.data;
        return ApiResponse(success: true, data: TheftSummary.fromJson(data));
      }

      return ApiResponse(
        success: false,
        message: response.data['message'] ?? 'Failed to fetch summary',
      );
    } catch (e) {
      return ApiResponse(success: false, message: e.toString());
    }
  }

  /// Get high-risk employees
  Future<ApiResponse<List<HighRiskEmployee>>> getHighRiskEmployees({
    String? shopId,
    int? limit,
  }) async {
    try {
      final queryParams = <String, dynamic>{};

      if (shopId != null) queryParams['shop_id'] = shopId;
      if (limit != null) queryParams['limit'] = limit.toString();

      final response = await _apiService.get(
        '/api/theft/high-risk/employees',
        queryParams: queryParams,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['data'] ?? response.data ?? [];
        final employees =
            data.map((e) => HighRiskEmployee.fromJson(e)).toList();
        return ApiResponse(success: true, data: employees);
      }

      return ApiResponse(
        success: false,
        message:
            response.data['message'] ?? 'Failed to fetch high-risk employees',
      );
    } catch (e) {
      return ApiResponse(success: false, message: e.toString());
    }
  }

  /// Get high-risk products
  Future<ApiResponse<List<HighRiskProduct>>> getHighRiskProducts({
    String? shopId,
    int? limit,
  }) async {
    try {
      final queryParams = <String, dynamic>{};

      if (shopId != null) queryParams['shop_id'] = shopId;
      if (limit != null) queryParams['limit'] = limit.toString();

      final response = await _apiService.get(
        '/api/theft/high-risk/products',
        queryParams: queryParams,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['data'] ?? response.data ?? [];
        final products = data.map((e) => HighRiskProduct.fromJson(e)).toList();
        return ApiResponse(success: true, data: products);
      }

      return ApiResponse(
        success: false,
        message:
            response.data['message'] ?? 'Failed to fetch high-risk products',
      );
    } catch (e) {
      return ApiResponse(success: false, message: e.toString());
    }
  }

  // ===========================================================================
  // SETTINGS
  // ===========================================================================

  /// Get detection settings for a shop
  Future<ApiResponse<DetectionSettings>> getSettings(String shopId) async {
    try {
      final response = await _apiService.get(
        '/api/theft/settings/$shopId',
      );

      if (response.statusCode == 200) {
        final data = response.data['data'] ?? response.data;
        return ApiResponse(
          success: true,
          data: DetectionSettings.fromJson(data),
        );
      }

      // Return defaults if not found
      if (response.statusCode == 404) {
        return ApiResponse(
          success: true,
          data: DetectionSettings(shopId: shopId),
        );
      }

      return ApiResponse(
        success: false,
        message: response.data['message'] ?? 'Failed to fetch settings',
      );
    } catch (e) {
      return ApiResponse(success: false, message: e.toString());
    }
  }

  /// Update detection settings
  Future<ApiResponse<DetectionSettings>> updateSettings(
    DetectionSettings settings,
  ) async {
    try {
      final response = await _apiService.put(
        '/api/theft/settings/${settings.shopId}',
        body: settings.toJson(),
      );

      if (response.statusCode == 200) {
        final data = response.data['data'] ?? response.data;
        return ApiResponse(
          success: true,
          data: DetectionSettings.fromJson(data),
        );
      }

      return ApiResponse(
        success: false,
        message: response.data['message'] ?? 'Failed to update settings',
      );
    } catch (e) {
      return ApiResponse(success: false, message: e.toString());
    }
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  String _anomalyTypeToString(AnomalyType type) {
    switch (type) {
      case AnomalyType.cashDiscrepancy:
        return 'cash_discrepancy';
      case AnomalyType.inventoryMismatch:
        return 'inventory_mismatch';
      case AnomalyType.salesPattern:
        return 'sales_pattern';
      case AnomalyType.returnAnomaly:
        return 'return_anomaly';
      case AnomalyType.priceManipulation:
        return 'price_manipulation';
      case AnomalyType.voidPattern:
        return 'void_pattern';
      case AnomalyType.timeAnomaly:
        return 'time_anomaly';
      case AnomalyType.employeeBehavior:
        return 'employee_behavior';
    }
  }

  String _statusToString(InvestigationStatus status) {
    switch (status) {
      case InvestigationStatus.open:
        return 'open';
      case InvestigationStatus.inProgress:
        return 'in_progress';
      case InvestigationStatus.pendingReview:
        return 'pending_review';
      case InvestigationStatus.resolved:
        return 'resolved';
      case InvestigationStatus.closed:
        return 'closed';
      case InvestigationStatus.escalated:
        return 'escalated';
    }
  }
}
