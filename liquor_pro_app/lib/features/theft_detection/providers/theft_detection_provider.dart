import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/service_providers.dart';
import '../models/theft_models.dart';
import '../services/theft_detection_service.dart';

// =============================================================================
// SERVICE PROVIDER
// =============================================================================

/// Provider for TheftDetectionService
final theftDetectionServiceProvider = Provider<TheftDetectionService>((ref) {
  final apiService = ref.watch(dioApiServiceProvider);
  return TheftDetectionService(apiService);
});

// =============================================================================
// UI STATE PROVIDERS
// =============================================================================

/// Selected shop filter
final theftShopIdProvider = StateProvider<String?>((ref) => null);

/// Anomaly type filter
final theftTypeFilterProvider = StateProvider<AnomalyType?>((ref) => null);

/// Severity filter
final theftSeverityFilterProvider = StateProvider<SeverityLevel?>((ref) => null);

/// Date range start
final theftStartDateProvider = StateProvider<DateTime?>((ref) {
  // Default to last 7 days
  return DateTime.now().subtract(const Duration(days: 7));
});

/// Date range end
final theftEndDateProvider = StateProvider<DateTime?>((ref) {
  return DateTime.now();
});

/// Show acknowledged anomalies
final showAcknowledgedProvider = StateProvider<bool>((ref) => false);

/// Investigation status filter
final investigationStatusFilterProvider =
    StateProvider<InvestigationStatus?>((ref) => null);

/// Computed query from UI state
final anomalyQueryProvider = Provider<AnomalyQuery>((ref) {
  final shopId = ref.watch(theftShopIdProvider);
  final type = ref.watch(theftTypeFilterProvider);
  final severity = ref.watch(theftSeverityFilterProvider);
  final startDate = ref.watch(theftStartDateProvider);
  final endDate = ref.watch(theftEndDateProvider);
  final showAcknowledged = ref.watch(showAcknowledgedProvider);

  return AnomalyQuery(
    shopId: shopId,
    type: type,
    severity: severity,
    isAcknowledged: showAcknowledged ? null : false,
    startDate: startDate,
    endDate: endDate,
  );
});

// =============================================================================
// ANOMALY PROVIDERS
// =============================================================================

/// All anomalies with query
final anomaliesProvider =
    FutureProvider.family<List<Anomaly>, AnomalyQuery>((ref, query) async {
  final service = ref.watch(theftDetectionServiceProvider);
  final response = await service.getAnomalies(
    shopId: query.shopId,
    type: query.type,
    severity: query.severity,
    isAcknowledged: query.isAcknowledged,
    startDate: query.startDate,
    endDate: query.endDate,
  );
  if (response.success && response.data != null) {
    return response.data!;
  }
  throw Exception(response.message ?? 'Failed to fetch anomalies');
});

/// Active anomalies based on current query
final activeAnomaliesProvider = FutureProvider<List<Anomaly>>((ref) async {
  final query = ref.watch(anomalyQueryProvider);
  return ref.watch(anomaliesProvider(query).future);
});

/// Single anomaly by ID
final anomalyProvider =
    FutureProvider.family<Anomaly, String>((ref, anomalyId) async {
  final service = ref.watch(theftDetectionServiceProvider);
  final response = await service.getAnomaly(anomalyId);
  if (response.success && response.data != null) {
    return response.data!;
  }
  throw Exception(response.message ?? 'Failed to fetch anomaly');
});

/// Critical anomalies (unacknowledged, high/critical severity)
final criticalAnomaliesProvider = FutureProvider<List<Anomaly>>((ref) async {
  final shopId = ref.watch(theftShopIdProvider);
  final service = ref.watch(theftDetectionServiceProvider);

  final response = await service.getAnomalies(
    shopId: shopId,
    isAcknowledged: false,
    limit: 10,
  );

  if (response.success && response.data != null) {
    // Filter for high/critical severity
    return response.data!
        .where((a) =>
            a.severity == SeverityLevel.high ||
            a.severity == SeverityLevel.critical)
        .toList();
  }
  return [];
});

// =============================================================================
// INVESTIGATION PROVIDERS
// =============================================================================

/// Query for investigations
class InvestigationQuery {
  final String? shopId;
  final InvestigationStatus? status;
  final String? assigneeId;

  const InvestigationQuery({
    this.shopId,
    this.status,
    this.assigneeId,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InvestigationQuery &&
          runtimeType == other.runtimeType &&
          shopId == other.shopId &&
          status == other.status &&
          assigneeId == other.assigneeId;

  @override
  int get hashCode =>
      shopId.hashCode ^ status.hashCode ^ assigneeId.hashCode;
}

/// All investigations with query
final investigationsProvider =
    FutureProvider.family<List<Investigation>, InvestigationQuery>(
        (ref, query) async {
  final service = ref.watch(theftDetectionServiceProvider);
  final response = await service.getInvestigations(
    shopId: query.shopId,
    status: query.status,
    assigneeId: query.assigneeId,
  );
  if (response.success && response.data != null) {
    return response.data!;
  }
  throw Exception(response.message ?? 'Failed to fetch investigations');
});

/// Active investigations based on current filters
final activeInvestigationsProvider =
    FutureProvider<List<Investigation>>((ref) async {
  final shopId = ref.watch(theftShopIdProvider);
  final status = ref.watch(investigationStatusFilterProvider);

  final query = InvestigationQuery(
    shopId: shopId,
    status: status,
  );

  return ref.watch(investigationsProvider(query).future);
});

/// Single investigation by ID
final investigationProvider =
    FutureProvider.family<Investigation, String>((ref, investigationId) async {
  final service = ref.watch(theftDetectionServiceProvider);
  final response = await service.getInvestigation(investigationId);
  if (response.success && response.data != null) {
    return response.data!;
  }
  throw Exception(response.message ?? 'Failed to fetch investigation');
});

/// Open investigations count
final openInvestigationsCountProvider = FutureProvider<int>((ref) async {
  final shopId = ref.watch(theftShopIdProvider);

  final query = InvestigationQuery(
    shopId: shopId,
    status: InvestigationStatus.open,
  );

  final investigations = await ref.watch(investigationsProvider(query).future);
  return investigations.length;
});

// =============================================================================
// ALERT PROVIDERS
// =============================================================================

/// Query for alerts
class AlertQuery {
  final String? shopId;
  final bool? isRead;
  final AlertPriority? priority;
  final int? limit;

  const AlertQuery({
    this.shopId,
    this.isRead,
    this.priority,
    this.limit,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AlertQuery &&
          runtimeType == other.runtimeType &&
          shopId == other.shopId &&
          isRead == other.isRead &&
          priority == other.priority;

  @override
  int get hashCode => shopId.hashCode ^ isRead.hashCode ^ priority.hashCode;
}

/// All alerts with query
final alertsProvider =
    FutureProvider.family<List<TheftAlert>, AlertQuery>((ref, query) async {
  final service = ref.watch(theftDetectionServiceProvider);
  final response = await service.getAlerts(
    shopId: query.shopId,
    isRead: query.isRead,
    priority: query.priority,
    limit: query.limit,
  );
  if (response.success && response.data != null) {
    return response.data!;
  }
  return [];
});

/// Unread alerts
final unreadAlertsProvider = FutureProvider<List<TheftAlert>>((ref) async {
  final shopId = ref.watch(theftShopIdProvider);

  final query = AlertQuery(
    shopId: shopId,
    isRead: false,
    limit: 20,
  );

  return ref.watch(alertsProvider(query).future);
});

/// Unread alerts count
final unreadAlertsCountProvider = FutureProvider<int>((ref) async {
  final alerts = await ref.watch(unreadAlertsProvider.future);
  return alerts.length;
});

// =============================================================================
// SUMMARY PROVIDERS
// =============================================================================

/// Summary query
class TheftSummaryQuery {
  final String? shopId;
  final DateTime? startDate;
  final DateTime? endDate;

  const TheftSummaryQuery({
    this.shopId,
    this.startDate,
    this.endDate,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TheftSummaryQuery &&
          runtimeType == other.runtimeType &&
          shopId == other.shopId &&
          startDate == other.startDate &&
          endDate == other.endDate;

  @override
  int get hashCode =>
      shopId.hashCode ^ startDate.hashCode ^ endDate.hashCode;
}

/// Theft detection summary
final theftSummaryProvider =
    FutureProvider.family<TheftSummary, TheftSummaryQuery>(
        (ref, query) async {
  final service = ref.watch(theftDetectionServiceProvider);
  final response = await service.getSummary(
    shopId: query.shopId,
    startDate: query.startDate,
    endDate: query.endDate,
  );
  if (response.success && response.data != null) {
    return response.data!;
  }
  throw Exception(response.message ?? 'Failed to fetch summary');
});

/// Active summary based on current filters
final activeTheftSummaryProvider = FutureProvider<TheftSummary?>((ref) async {
  final shopId = ref.watch(theftShopIdProvider);
  final startDate = ref.watch(theftStartDateProvider);
  final endDate = ref.watch(theftEndDateProvider);

  final query = TheftSummaryQuery(
    shopId: shopId,
    startDate: startDate,
    endDate: endDate,
  );

  return ref.watch(theftSummaryProvider(query).future);
});

/// High-risk employees
final highRiskEmployeesProvider =
    FutureProvider<List<HighRiskEmployee>>((ref) async {
  final shopId = ref.watch(theftShopIdProvider);
  final service = ref.watch(theftDetectionServiceProvider);

  final response = await service.getHighRiskEmployees(
    shopId: shopId,
    limit: 10,
  );

  if (response.success && response.data != null) {
    return response.data!;
  }
  return [];
});

/// High-risk products
final highRiskProductsProvider =
    FutureProvider<List<HighRiskProduct>>((ref) async {
  final shopId = ref.watch(theftShopIdProvider);
  final service = ref.watch(theftDetectionServiceProvider);

  final response = await service.getHighRiskProducts(
    shopId: shopId,
    limit: 10,
  );

  if (response.success && response.data != null) {
    return response.data!;
  }
  return [];
});

// =============================================================================
// SETTINGS PROVIDERS
// =============================================================================

/// Detection settings for a shop
final detectionSettingsProvider =
    FutureProvider.family<DetectionSettings, String>((ref, shopId) async {
  final service = ref.watch(theftDetectionServiceProvider);
  final response = await service.getSettings(shopId);
  if (response.success && response.data != null) {
    return response.data!;
  }
  // Return defaults if not found
  return DetectionSettings(shopId: shopId);
});

// =============================================================================
// THEFT DETECTION NOTIFIER (MUTATIONS)
// =============================================================================

/// StateNotifier for theft detection mutations
class TheftDetectionNotifier extends StateNotifier<AsyncValue<void>> {
  final TheftDetectionService _service;
  final Ref _ref;

  TheftDetectionNotifier(this._service, this._ref)
      : super(const AsyncValue.data(null));

  /// Acknowledge an anomaly
  Future<bool> acknowledgeAnomaly(String anomalyId) async {
    state = const AsyncValue.loading();
    try {
      final response = await _service.acknowledgeAnomaly(anomalyId);
      if (response.success) {
        _invalidateProviders();
        state = const AsyncValue.data(null);
        return true;
      }
      state = AsyncValue.error(
        response.message ?? 'Failed to acknowledge anomaly',
        StackTrace.current,
      );
      return false;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// Dismiss an anomaly
  Future<bool> dismissAnomaly(String anomalyId, {String? reason}) async {
    state = const AsyncValue.loading();
    try {
      final response = await _service.dismissAnomaly(anomalyId, reason: reason);
      if (response.success) {
        _invalidateProviders();
        state = const AsyncValue.data(null);
        return true;
      }
      state = AsyncValue.error(
        response.message ?? 'Failed to dismiss anomaly',
        StackTrace.current,
      );
      return false;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// Run detection manually
  Future<List<Anomaly>?> runDetection(String shopId,
      {DateTime? startDate, DateTime? endDate}) async {
    state = const AsyncValue.loading();
    try {
      final response = await _service.runDetection(
        shopId: shopId,
        startDate: startDate,
        endDate: endDate,
      );
      if (response.success && response.data != null) {
        _invalidateProviders();
        state = const AsyncValue.data(null);
        return response.data;
      }
      state = AsyncValue.error(
        response.message ?? 'Failed to run detection',
        StackTrace.current,
      );
      return null;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return null;
    }
  }

  /// Create an investigation
  Future<Investigation?> createInvestigation(
      CreateInvestigationRequest request) async {
    state = const AsyncValue.loading();
    try {
      final response = await _service.createInvestigation(request);
      if (response.success && response.data != null) {
        _invalidateProviders();
        state = const AsyncValue.data(null);
        return response.data;
      }
      state = AsyncValue.error(
        response.message ?? 'Failed to create investigation',
        StackTrace.current,
      );
      return null;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return null;
    }
  }

  /// Update an investigation
  Future<Investigation?> updateInvestigation(
    String investigationId,
    UpdateInvestigationRequest request,
  ) async {
    state = const AsyncValue.loading();
    try {
      final response =
          await _service.updateInvestigation(investigationId, request);
      if (response.success && response.data != null) {
        _ref.invalidate(investigationProvider(investigationId));
        _invalidateProviders();
        state = const AsyncValue.data(null);
        return response.data;
      }
      state = AsyncValue.error(
        response.message ?? 'Failed to update investigation',
        StackTrace.current,
      );
      return null;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return null;
    }
  }

  /// Add note to investigation
  Future<InvestigationNote?> addNote(
    String investigationId,
    AddNoteRequest request,
  ) async {
    state = const AsyncValue.loading();
    try {
      final response = await _service.addNote(investigationId, request);
      if (response.success && response.data != null) {
        _ref.invalidate(investigationProvider(investigationId));
        state = const AsyncValue.data(null);
        return response.data;
      }
      state = AsyncValue.error(
        response.message ?? 'Failed to add note',
        StackTrace.current,
      );
      return null;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return null;
    }
  }

  /// Assign investigation
  Future<bool> assignInvestigation(
    String investigationId,
    String assigneeId,
  ) async {
    state = const AsyncValue.loading();
    try {
      final response =
          await _service.assignInvestigation(investigationId, assigneeId);
      if (response.success) {
        _ref.invalidate(investigationProvider(investigationId));
        _invalidateProviders();
        state = const AsyncValue.data(null);
        return true;
      }
      state = AsyncValue.error(
        response.message ?? 'Failed to assign investigation',
        StackTrace.current,
      );
      return false;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// Resolve investigation
  Future<bool> resolveInvestigation(
    String investigationId, {
    required ResolutionType resolution,
    required String notes,
    double? actualLoss,
    double? recoveredAmount,
  }) async {
    state = const AsyncValue.loading();
    try {
      final response = await _service.resolveInvestigation(
        investigationId,
        resolution: resolution,
        notes: notes,
        actualLoss: actualLoss,
        recoveredAmount: recoveredAmount,
      );
      if (response.success) {
        _ref.invalidate(investigationProvider(investigationId));
        _invalidateProviders();
        state = const AsyncValue.data(null);
        return true;
      }
      state = AsyncValue.error(
        response.message ?? 'Failed to resolve investigation',
        StackTrace.current,
      );
      return false;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// Escalate investigation
  Future<bool> escalateInvestigation(
    String investigationId, {
    String? reason,
  }) async {
    state = const AsyncValue.loading();
    try {
      final response = await _service.escalateInvestigation(
        investigationId,
        reason: reason,
      );
      if (response.success) {
        _ref.invalidate(investigationProvider(investigationId));
        _invalidateProviders();
        state = const AsyncValue.data(null);
        return true;
      }
      state = AsyncValue.error(
        response.message ?? 'Failed to escalate investigation',
        StackTrace.current,
      );
      return false;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// Mark alert as read
  Future<bool> markAlertRead(String alertId) async {
    try {
      final response = await _service.markAlertRead(alertId);
      if (response.success) {
        _ref.invalidate(unreadAlertsProvider);
        _ref.invalidate(unreadAlertsCountProvider);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Dismiss alert
  Future<bool> dismissAlert(String alertId) async {
    try {
      final response = await _service.dismissAlert(alertId);
      if (response.success) {
        _ref.invalidate(unreadAlertsProvider);
        _ref.invalidate(unreadAlertsCountProvider);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Mark all alerts as read
  Future<bool> markAllAlertsRead({String? shopId}) async {
    try {
      final response = await _service.markAllAlertsRead(shopId: shopId);
      if (response.success) {
        _ref.invalidate(unreadAlertsProvider);
        _ref.invalidate(unreadAlertsCountProvider);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Update detection settings
  Future<bool> updateSettings(DetectionSettings settings) async {
    state = const AsyncValue.loading();
    try {
      final response = await _service.updateSettings(settings);
      if (response.success) {
        _ref.invalidate(detectionSettingsProvider(settings.shopId));
        state = const AsyncValue.data(null);
        return true;
      }
      state = AsyncValue.error(
        response.message ?? 'Failed to update settings',
        StackTrace.current,
      );
      return false;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// Refresh all data
  void refresh() {
    _invalidateProviders();
  }

  void _invalidateProviders() {
    _ref.invalidate(activeAnomaliesProvider);
    _ref.invalidate(criticalAnomaliesProvider);
    _ref.invalidate(activeInvestigationsProvider);
    _ref.invalidate(openInvestigationsCountProvider);
    _ref.invalidate(unreadAlertsProvider);
    _ref.invalidate(unreadAlertsCountProvider);
    _ref.invalidate(activeTheftSummaryProvider);
    _ref.invalidate(highRiskEmployeesProvider);
    _ref.invalidate(highRiskProductsProvider);
  }
}

/// Provider for theft detection notifier
final theftDetectionNotifierProvider =
    StateNotifierProvider<TheftDetectionNotifier, AsyncValue<void>>((ref) {
  final service = ref.watch(theftDetectionServiceProvider);
  return TheftDetectionNotifier(service, ref);
});

// =============================================================================
// HELPER EXTENSIONS
// =============================================================================

extension AnomalyX on Anomaly {
  /// Get formatted Z-score
  String get formattedZScore => zScore.toStringAsFixed(2);

  /// Get deviation direction
  bool get isPositiveDeviation => value > expectedValue;

  /// Risk level text
  String get riskLevelText {
    if (zScore >= 3) return 'Critical';
    if (zScore >= 2.5) return 'High';
    if (zScore >= 2) return 'Medium';
    return 'Low';
  }
}

extension InvestigationX on Investigation {
  /// Is active (not resolved/closed)
  bool get isActive =>
      status != InvestigationStatus.resolved &&
      status != InvestigationStatus.closed;

  /// Net loss (actual loss - recovered)
  double get netLoss {
    final actual = actualLoss ?? estimatedLoss;
    return actual - (recoveredAmount ?? 0);
  }

  /// Recovery percentage
  double get recoveryPercentage {
    final actual = actualLoss ?? estimatedLoss;
    if (actual == 0) return 0;
    return ((recoveredAmount ?? 0) / actual) * 100;
  }
}
