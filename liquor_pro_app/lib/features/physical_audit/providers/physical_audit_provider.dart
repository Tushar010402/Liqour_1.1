import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/service_providers.dart';
import '../models/physical_audit_models.dart';
import '../services/physical_audit_service.dart';

// =============================================================================
// SERVICE PROVIDER
// =============================================================================

/// Provider for PhysicalAuditService
final physicalAuditServiceProvider = Provider<PhysicalAuditService>((ref) {
  final apiService = ref.watch(dioApiServiceProvider);
  return PhysicalAuditService(apiService);
});

// =============================================================================
// UI STATE PROVIDERS
// =============================================================================

/// Selected shop filter for audits
final auditShopIdProvider = StateProvider<String?>((ref) => null);

/// Selected audit type filter
final auditTypeFilterProvider = StateProvider<AuditType?>((ref) => null);

/// Selected status filter
final auditStatusFilterProvider = StateProvider<AuditStatus?>((ref) => null);

/// Date range start
final auditStartDateProvider = StateProvider<DateTime?>((ref) => null);

/// Date range end
final auditEndDateProvider = StateProvider<DateTime?>((ref) => null);

/// Computed query from UI state
final auditQueryProvider = Provider<AuditQuery>((ref) {
  final shopId = ref.watch(auditShopIdProvider);
  final type = ref.watch(auditTypeFilterProvider);
  final status = ref.watch(auditStatusFilterProvider);
  final startDate = ref.watch(auditStartDateProvider);
  final endDate = ref.watch(auditEndDateProvider);

  return AuditQuery(
    shopId: shopId,
    type: type,
    status: status,
    startDate: startDate,
    endDate: endDate,
  );
});

// =============================================================================
// SCHEDULE PROVIDERS
// =============================================================================

/// All schedules for a shop
final auditSchedulesProvider =
    FutureProvider.family<List<AuditSchedule>, String?>((ref, shopId) async {
  final service = ref.watch(physicalAuditServiceProvider);
  final response = await service.getSchedules(shopId: shopId);
  if (response.success && response.data != null) {
    return response.data!;
  }
  throw Exception(response.message ?? 'Failed to fetch schedules');
});

/// Active schedules based on current shop selection
final activeSchedulesProvider = FutureProvider<List<AuditSchedule>>((ref) async {
  final shopId = ref.watch(auditShopIdProvider);
  return ref.watch(auditSchedulesProvider(shopId).future);
});

/// Pending audits (due soon)
final pendingAuditsProvider =
    FutureProvider.family<List<AuditSchedule>, String?>((ref, shopId) async {
  final service = ref.watch(physicalAuditServiceProvider);
  final response = await service.getPendingAudits(shopId: shopId);
  if (response.success && response.data != null) {
    return response.data!;
  }
  return [];
});

/// Active pending audits
final activePendingAuditsProvider = FutureProvider<List<AuditSchedule>>((ref) async {
  final shopId = ref.watch(auditShopIdProvider);
  return ref.watch(pendingAuditsProvider(shopId).future);
});

// =============================================================================
// SESSION PROVIDERS
// =============================================================================

/// Audit sessions with query
final auditSessionsProvider =
    FutureProvider.family<List<AuditSession>, AuditQuery>((ref, query) async {
  final service = ref.watch(physicalAuditServiceProvider);
  final response = await service.getSessions(query);
  if (response.success && response.data != null) {
    return response.data!;
  }
  throw Exception(response.message ?? 'Failed to fetch sessions');
});

/// Active sessions based on current query
final activeAuditSessionsProvider = FutureProvider<List<AuditSession>>((ref) async {
  final query = ref.watch(auditQueryProvider);
  return ref.watch(auditSessionsProvider(query).future);
});

/// Single session by ID
final auditSessionProvider =
    FutureProvider.family<AuditSession, String>((ref, sessionId) async {
  final service = ref.watch(physicalAuditServiceProvider);
  final response = await service.getSession(sessionId);
  if (response.success && response.data != null) {
    return response.data!;
  }
  throw Exception(response.message ?? 'Failed to fetch session');
});

// =============================================================================
// SUMMARY PROVIDERS
// =============================================================================

/// Audit summary for a shop
final auditSummaryProvider =
    FutureProvider.family<AuditSummary, String>((ref, shopId) async {
  final service = ref.watch(physicalAuditServiceProvider);
  final response = await service.getSummary(shopId: shopId);
  if (response.success && response.data != null) {
    return response.data!;
  }
  throw Exception(response.message ?? 'Failed to fetch summary');
});

/// Expected cash for a shop
final expectedCashProvider =
    FutureProvider.family<double, String>((ref, shopId) async {
  final service = ref.watch(physicalAuditServiceProvider);
  final response = await service.getExpectedCash(shopId);
  if (response.success && response.data != null) {
    return response.data!;
  }
  return 0.0;
});

// =============================================================================
// INVENTORY ITEMS PROVIDER
// =============================================================================

/// Query for inventory items
class InventoryItemsQuery {
  final String shopId;
  final String? category;
  final String? searchQuery;
  final int limit;
  final int offset;

  const InventoryItemsQuery({
    required this.shopId,
    this.category,
    this.searchQuery,
    this.limit = 50,
    this.offset = 0,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InventoryItemsQuery &&
          runtimeType == other.runtimeType &&
          shopId == other.shopId &&
          category == other.category &&
          searchQuery == other.searchQuery &&
          limit == other.limit &&
          offset == other.offset;

  @override
  int get hashCode =>
      shopId.hashCode ^
      category.hashCode ^
      searchQuery.hashCode ^
      limit.hashCode ^
      offset.hashCode;
}

/// Inventory items for audit
final inventoryItemsForAuditProvider =
    FutureProvider.family<List<InventoryAuditItem>, InventoryItemsQuery>(
        (ref, query) async {
  final service = ref.watch(physicalAuditServiceProvider);
  final response = await service.getInventoryItems(
    shopId: query.shopId,
    category: query.category,
    searchQuery: query.searchQuery,
    limit: query.limit,
    offset: query.offset,
  );
  if (response.success && response.data != null) {
    return response.data!;
  }
  return [];
});

// =============================================================================
// AUDIT SESSION NOTIFIER (Active Audit State)
// =============================================================================

/// State for an active audit session being conducted
class ActiveAuditState {
  final AuditSession? session;
  final CashAuditData? cashData;
  final InventoryAuditData? inventoryData;
  final bool isSubmitting;
  final String? error;

  const ActiveAuditState({
    this.session,
    this.cashData,
    this.inventoryData,
    this.isSubmitting = false,
    this.error,
  });

  ActiveAuditState copyWith({
    AuditSession? session,
    CashAuditData? cashData,
    InventoryAuditData? inventoryData,
    bool? isSubmitting,
    String? error,
  }) {
    return ActiveAuditState(
      session: session ?? this.session,
      cashData: cashData ?? this.cashData,
      inventoryData: inventoryData ?? this.inventoryData,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: error,
    );
  }

  bool get hasSession => session != null;
  bool get isCashAudit =>
      session?.type == AuditType.cash || session?.type == AuditType.combined;
  bool get isInventoryAudit =>
      session?.type == AuditType.inventory || session?.type == AuditType.combined;
}

/// StateNotifier for managing active audit session
class ActiveAuditNotifier extends StateNotifier<ActiveAuditState> {
  final PhysicalAuditService _service;
  final Ref _ref;

  ActiveAuditNotifier(this._service, this._ref)
      : super(const ActiveAuditState());

  /// Start a new audit session
  Future<bool> startAudit(StartAuditRequest request) async {
    state = state.copyWith(isSubmitting: true, error: null);
    try {
      final response = await _service.startSession(request);
      if (response.success && response.data != null) {
        state = ActiveAuditState(
          session: response.data,
          cashData: request.type == AuditType.cash ||
                  request.type == AuditType.combined
              ? CashAuditData(
                  expectedAmount: 0,
                  actualAmount: 0,
                  denominations: {},
                  variance: 0,
                )
              : null,
          inventoryData: request.type == AuditType.inventory ||
                  request.type == AuditType.combined
              ? InventoryAuditData(
                  itemsChecked: 0,
                  itemsWithVariance: 0,
                  totalExpectedValue: 0,
                  totalActualValue: 0,
                  items: [],
                )
              : null,
        );
        return true;
      }
      state = state.copyWith(
        isSubmitting: false,
        error: response.message ?? 'Failed to start audit',
      );
      return false;
    } catch (e) {
      state = state.copyWith(isSubmitting: false, error: e.toString());
      return false;
    }
  }

  /// Update cash denominations
  void updateDenominations(Map<String, int> denominations) {
    if (state.cashData == null) return;

    final total = CashAuditData.calculateTotal(denominations);
    final expected = state.cashData!.expectedAmount;

    state = state.copyWith(
      cashData: CashAuditData(
        expectedAmount: expected,
        actualAmount: total,
        denominations: denominations,
        variance: total - expected,
        notes: state.cashData!.notes,
      ),
    );
  }

  /// Set expected cash amount
  void setExpectedCash(double amount) {
    if (state.cashData == null) return;

    state = state.copyWith(
      cashData: CashAuditData(
        expectedAmount: amount,
        actualAmount: state.cashData!.actualAmount,
        denominations: state.cashData!.denominations,
        variance: state.cashData!.actualAmount - amount,
        notes: state.cashData!.notes,
      ),
    );
  }

  /// Update inventory item count
  void updateInventoryItem(InventoryAuditItem updatedItem) {
    if (state.inventoryData == null) return;

    final items = List<InventoryAuditItem>.from(state.inventoryData!.items);
    final index = items.indexWhere((i) => i.productId == updatedItem.productId);

    if (index >= 0) {
      items[index] = updatedItem;
    } else {
      items.add(updatedItem);
    }

    // Recalculate totals
    int itemsWithVariance = 0;
    double totalExpected = 0;
    double totalActual = 0;

    for (final item in items) {
      if (item.variance != 0) itemsWithVariance++;
      totalExpected += item.expectedQuantity * (item.unitPrice ?? 0);
      totalActual += item.actualQuantity * (item.unitPrice ?? 0);
    }

    state = state.copyWith(
      inventoryData: InventoryAuditData(
        itemsChecked: items.length,
        itemsWithVariance: itemsWithVariance,
        totalExpectedValue: totalExpected,
        totalActualValue: totalActual,
        items: items,
      ),
    );
  }

  /// Submit cash audit
  Future<bool> submitCashAudit() async {
    if (state.session == null || state.cashData == null) return false;

    state = state.copyWith(isSubmitting: true, error: null);
    try {
      final response = await _service.submitCashAudit(
        state.session!.id,
        state.cashData!,
      );
      if (response.success && response.data != null) {
        state = state.copyWith(session: response.data, isSubmitting: false);
        _invalidateProviders();
        return true;
      }
      state = state.copyWith(
        isSubmitting: false,
        error: response.message ?? 'Failed to submit cash audit',
      );
      return false;
    } catch (e) {
      state = state.copyWith(isSubmitting: false, error: e.toString());
      return false;
    }
  }

  /// Submit inventory audit
  Future<bool> submitInventoryAudit() async {
    if (state.session == null || state.inventoryData == null) return false;

    state = state.copyWith(isSubmitting: true, error: null);
    try {
      final response = await _service.submitInventoryAudit(
        state.session!.id,
        state.inventoryData!,
      );
      if (response.success && response.data != null) {
        state = state.copyWith(session: response.data, isSubmitting: false);
        _invalidateProviders();
        return true;
      }
      state = state.copyWith(
        isSubmitting: false,
        error: response.message ?? 'Failed to submit inventory audit',
      );
      return false;
    } catch (e) {
      state = state.copyWith(isSubmitting: false, error: e.toString());
      return false;
    }
  }

  /// Complete the audit session
  Future<bool> completeAudit({String? notes}) async {
    if (state.session == null) return false;

    state = state.copyWith(isSubmitting: true, error: null);
    try {
      final response = await _service.completeSession(
        state.session!.id,
        notes: notes,
      );
      if (response.success && response.data != null) {
        state = state.copyWith(session: response.data, isSubmitting: false);
        _invalidateProviders();
        return true;
      }
      state = state.copyWith(
        isSubmitting: false,
        error: response.message ?? 'Failed to complete audit',
      );
      return false;
    } catch (e) {
      state = state.copyWith(isSubmitting: false, error: e.toString());
      return false;
    }
  }

  /// Cancel the audit session
  Future<bool> cancelAudit(String reason) async {
    if (state.session == null) return false;

    state = state.copyWith(isSubmitting: true, error: null);
    try {
      final response = await _service.cancelSession(state.session!.id, reason);
      if (response.success) {
        state = const ActiveAuditState();
        _invalidateProviders();
        return true;
      }
      state = state.copyWith(
        isSubmitting: false,
        error: response.message ?? 'Failed to cancel audit',
      );
      return false;
    } catch (e) {
      state = state.copyWith(isSubmitting: false, error: e.toString());
      return false;
    }
  }

  /// Clear current audit state
  void clear() {
    state = const ActiveAuditState();
  }

  void _invalidateProviders() {
    _ref.invalidate(activeAuditSessionsProvider);
    _ref.invalidate(activeSchedulesProvider);
    _ref.invalidate(activePendingAuditsProvider);
  }
}

/// Provider for active audit notifier
final activeAuditNotifierProvider =
    StateNotifierProvider<ActiveAuditNotifier, ActiveAuditState>((ref) {
  final service = ref.watch(physicalAuditServiceProvider);
  return ActiveAuditNotifier(service, ref);
});

// =============================================================================
// SCHEDULE NOTIFIER (CRUD Operations)
// =============================================================================

/// StateNotifier for schedule CRUD operations
class AuditScheduleNotifier extends StateNotifier<AsyncValue<void>> {
  final PhysicalAuditService _service;
  final Ref _ref;

  AuditScheduleNotifier(this._service, this._ref)
      : super(const AsyncValue.data(null));

  /// Create a new schedule
  Future<AuditSchedule?> createSchedule(CreateScheduleRequest request) async {
    state = const AsyncValue.loading();
    try {
      final response = await _service.createSchedule(request);
      if (response.success && response.data != null) {
        _ref.invalidate(activeSchedulesProvider);
        state = const AsyncValue.data(null);
        return response.data;
      }
      state = AsyncValue.error(
        response.message ?? 'Failed to create schedule',
        StackTrace.current,
      );
      return null;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return null;
    }
  }

  /// Update a schedule
  Future<bool> updateSchedule(String id, Map<String, dynamic> updates) async {
    state = const AsyncValue.loading();
    try {
      final response = await _service.updateSchedule(id, updates);
      if (response.success) {
        _ref.invalidate(activeSchedulesProvider);
        state = const AsyncValue.data(null);
        return true;
      }
      state = AsyncValue.error(
        response.message ?? 'Failed to update schedule',
        StackTrace.current,
      );
      return false;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// Delete a schedule
  Future<bool> deleteSchedule(String id) async {
    state = const AsyncValue.loading();
    try {
      final response = await _service.deleteSchedule(id);
      if (response.success) {
        _ref.invalidate(activeSchedulesProvider);
        state = const AsyncValue.data(null);
        return true;
      }
      state = AsyncValue.error(
        response.message ?? 'Failed to delete schedule',
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
    _ref.invalidate(activeSchedulesProvider);
    _ref.invalidate(activeAuditSessionsProvider);
    _ref.invalidate(activePendingAuditsProvider);
  }
}

/// Provider for schedule notifier
final auditScheduleNotifierProvider =
    StateNotifierProvider<AuditScheduleNotifier, AsyncValue<void>>((ref) {
  final service = ref.watch(physicalAuditServiceProvider);
  return AuditScheduleNotifier(service, ref);
});

// =============================================================================
// HELPER EXTENSIONS
// =============================================================================

extension AuditSessionX on AuditSession {
  /// Get status color value
  int get statusColorValue {
    switch (status) {
      case AuditStatus.completed:
        return 0xFF10B981; // Green
      case AuditStatus.inProgress:
        return 0xFF3B82F6; // Blue
      case AuditStatus.pending:
        return 0xFFF59E0B; // Yellow
      case AuditStatus.cancelled:
        return 0xFF6B7280; // Gray
      case AuditStatus.missed:
        return 0xFFEF4444; // Red
    }
  }

  /// Has variance
  bool get hasVariance {
    if (cashAudit != null && cashAudit!.variance.abs() > 0.01) return true;
    if (inventoryAudit != null && inventoryAudit!.itemsWithVariance > 0) return true;
    return false;
  }

  /// Total variance amount
  double get totalVariance {
    double total = 0;
    if (cashAudit != null) total += cashAudit!.variance;
    if (inventoryAudit != null) {
      total += inventoryAudit!.totalActualValue - inventoryAudit!.totalExpectedValue;
    }
    return total;
  }
}

extension AuditScheduleX on AuditSchedule {
  /// Is overdue
  bool get isOverdue {
    if (nextScheduledAt == null) return false;
    return nextScheduledAt!.isBefore(DateTime.now());
  }

  /// Time until next audit
  Duration? get timeUntilNext {
    if (nextScheduledAt == null) return null;
    return nextScheduledAt!.difference(DateTime.now());
  }

  /// Formatted next audit time
  String get formattedNextAudit {
    if (nextScheduledAt == null) return 'Not scheduled';
    final diff = timeUntilNext!;
    if (diff.isNegative) return 'Overdue';
    if (diff.inDays > 0) return 'In ${diff.inDays} days';
    if (diff.inHours > 0) return 'In ${diff.inHours} hours';
    return 'In ${diff.inMinutes} minutes';
  }
}
