import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/service_providers.dart';
import '../models/tips_models.dart';
import '../services/tips_service.dart';

// =============================================================================
// SERVICE PROVIDER
// =============================================================================

/// Provider for TipsService
final tipsServiceProvider = Provider<TipsService>((ref) {
  final apiService = ref.watch(dioApiServiceProvider);
  return TipsService(apiService);
});

// =============================================================================
// UI STATE PROVIDERS
// =============================================================================

/// Selected shop filter
final tipsShopIdProvider = StateProvider<String?>((ref) => null);

/// Date range start
final tipsStartDateProvider = StateProvider<DateTime?>((ref) {
  // Default to start of current week
  final now = DateTime.now();
  return now.subtract(Duration(days: now.weekday - 1));
});

/// Date range end
final tipsEndDateProvider = StateProvider<DateTime?>((ref) {
  // Default to today
  return DateTime.now();
});

/// Computed query from UI state
final tipsQueryProvider = Provider<TipsQuery>((ref) {
  final shopId = ref.watch(tipsShopIdProvider);
  final startDate = ref.watch(tipsStartDateProvider);
  final endDate = ref.watch(tipsEndDateProvider);

  return TipsQuery(
    shopId: shopId,
    startDate: startDate,
    endDate: endDate,
  );
});

// =============================================================================
// TIP ENTRIES PROVIDERS
// =============================================================================

/// All tips with query
final tipsProvider =
    FutureProvider.family<List<TipEntry>, TipsQuery>((ref, query) async {
  final service = ref.watch(tipsServiceProvider);
  final response = await service.getTips(query);
  if (response.success && response.data != null) {
    return response.data!;
  }
  throw Exception(response.message ?? 'Failed to fetch tips');
});

/// Active tips based on current query
final activeTipsProvider = FutureProvider<List<TipEntry>>((ref) async {
  final query = ref.watch(tipsQueryProvider);
  return ref.watch(tipsProvider(query).future);
});

// =============================================================================
// TIP POOLS PROVIDERS
// =============================================================================

/// Active (open) pools for a shop
final activePoolsProvider =
    FutureProvider.family<List<TipPool>, String?>((ref, shopId) async {
  final service = ref.watch(tipsServiceProvider);
  final response = await service.getPools(shopId: shopId, isClosed: false);
  if (response.success && response.data != null) {
    return response.data!;
  }
  return [];
});

/// Closed pools for a shop
final closedPoolsProvider =
    FutureProvider.family<List<TipPool>, String?>((ref, shopId) async {
  final service = ref.watch(tipsServiceProvider);
  final response = await service.getPools(shopId: shopId, isClosed: true);
  if (response.success && response.data != null) {
    return response.data!;
  }
  return [];
});

/// Single pool by ID
final poolProvider =
    FutureProvider.family<TipPool, String>((ref, poolId) async {
  final service = ref.watch(tipsServiceProvider);
  final response = await service.getPool(poolId);
  if (response.success && response.data != null) {
    return response.data!;
  }
  throw Exception(response.message ?? 'Failed to fetch pool');
});

/// Distribution preview for a pool
final distributionPreviewProvider =
    FutureProvider.family<List<TipPoolEmployee>, String>((ref, poolId) async {
  final service = ref.watch(tipsServiceProvider);
  final response = await service.previewDistribution(poolId);
  if (response.success && response.data != null) {
    return response.data!;
  }
  return [];
});

// =============================================================================
// PAYOUT PROVIDERS
// =============================================================================

/// Pending payouts for a shop
final pendingPayoutsProvider =
    FutureProvider.family<List<TipPayout>, String?>((ref, shopId) async {
  final service = ref.watch(tipsServiceProvider);
  final response = await service.getPayouts(
    shopId: shopId,
    status: PayoutStatus.pending,
  );
  if (response.success && response.data != null) {
    return response.data!;
  }
  return [];
});

/// All payouts for a shop
final payoutsProvider =
    FutureProvider.family<List<TipPayout>, String?>((ref, shopId) async {
  final service = ref.watch(tipsServiceProvider);
  final response = await service.getPayouts(shopId: shopId);
  if (response.success && response.data != null) {
    return response.data!;
  }
  return [];
});

/// Single payout by ID
final payoutProvider =
    FutureProvider.family<TipPayout, String>((ref, payoutId) async {
  final service = ref.watch(tipsServiceProvider);
  final response = await service.getPayout(payoutId);
  if (response.success && response.data != null) {
    return response.data!;
  }
  throw Exception(response.message ?? 'Failed to fetch payout');
});

// =============================================================================
// SUMMARY PROVIDERS
// =============================================================================

/// Summary query
class TipsSummaryQuery {
  final String shopId;
  final DateTime? startDate;
  final DateTime? endDate;

  const TipsSummaryQuery({
    required this.shopId,
    this.startDate,
    this.endDate,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TipsSummaryQuery &&
          runtimeType == other.runtimeType &&
          shopId == other.shopId &&
          startDate == other.startDate &&
          endDate == other.endDate;

  @override
  int get hashCode => shopId.hashCode ^ startDate.hashCode ^ endDate.hashCode;
}

/// Tips summary for a shop
final tipsSummaryProvider =
    FutureProvider.family<TipsSummary, TipsSummaryQuery>((ref, query) async {
  final service = ref.watch(tipsServiceProvider);
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

/// Active summary based on current shop
final activeTipsSummaryProvider = FutureProvider<TipsSummary?>((ref) async {
  final shopId = ref.watch(tipsShopIdProvider);
  if (shopId == null) return null;

  final startDate = ref.watch(tipsStartDateProvider);
  final endDate = ref.watch(tipsEndDateProvider);

  final query = TipsSummaryQuery(
    shopId: shopId,
    startDate: startDate,
    endDate: endDate,
  );

  return ref.watch(tipsSummaryProvider(query).future);
});

// =============================================================================
// SETTINGS PROVIDERS
// =============================================================================

/// Tip settings for a shop
final tipSettingsProvider =
    FutureProvider.family<TipSettings, String>((ref, shopId) async {
  final service = ref.watch(tipsServiceProvider);
  final response = await service.getSettings(shopId);
  if (response.success && response.data != null) {
    return response.data!;
  }
  // Return defaults if not found
  return TipSettings(shopId: shopId);
});

// =============================================================================
// TIPS NOTIFIER (MUTATIONS)
// =============================================================================

/// StateNotifier for tip mutations
class TipsNotifier extends StateNotifier<AsyncValue<void>> {
  final TipsService _service;
  final Ref _ref;

  TipsNotifier(this._service, this._ref) : super(const AsyncValue.data(null));

  /// Create a tip entry
  Future<TipEntry?> createTip(CreateTipRequest request) async {
    state = const AsyncValue.loading();
    try {
      final response = await _service.createTip(request);
      if (response.success && response.data != null) {
        _invalidateProviders();
        state = const AsyncValue.data(null);
        return response.data;
      }
      state = AsyncValue.error(
        response.message ?? 'Failed to create tip',
        StackTrace.current,
      );
      return null;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return null;
    }
  }

  /// Delete a tip
  Future<bool> deleteTip(String tipId) async {
    state = const AsyncValue.loading();
    try {
      final response = await _service.deleteTip(tipId);
      if (response.success) {
        _invalidateProviders();
        state = const AsyncValue.data(null);
        return true;
      }
      state = AsyncValue.error(
        response.message ?? 'Failed to delete tip',
        StackTrace.current,
      );
      return false;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// Create a pool
  Future<TipPool?> createPool(CreatePoolRequest request) async {
    state = const AsyncValue.loading();
    try {
      final response = await _service.createPool(request);
      if (response.success && response.data != null) {
        _invalidateProviders();
        state = const AsyncValue.data(null);
        return response.data;
      }
      state = AsyncValue.error(
        response.message ?? 'Failed to create pool',
        StackTrace.current,
      );
      return null;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return null;
    }
  }

  /// Close a pool
  Future<bool> closePool(String poolId) async {
    state = const AsyncValue.loading();
    try {
      final response = await _service.closePool(poolId);
      if (response.success) {
        _invalidateProviders();
        state = const AsyncValue.data(null);
        return true;
      }
      state = AsyncValue.error(
        response.message ?? 'Failed to close pool',
        StackTrace.current,
      );
      return false;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// Create a payout
  Future<TipPayout?> createPayout(CreatePayoutRequest request) async {
    state = const AsyncValue.loading();
    try {
      final response = await _service.createPayout(request);
      if (response.success && response.data != null) {
        _invalidateProviders();
        state = const AsyncValue.data(null);
        return response.data;
      }
      state = AsyncValue.error(
        response.message ?? 'Failed to create payout',
        StackTrace.current,
      );
      return null;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return null;
    }
  }

  /// Approve a payout
  Future<bool> approvePayout(String payoutId) async {
    state = const AsyncValue.loading();
    try {
      final response = await _service.approvePayout(payoutId);
      if (response.success) {
        _invalidateProviders();
        state = const AsyncValue.data(null);
        return true;
      }
      state = AsyncValue.error(
        response.message ?? 'Failed to approve payout',
        StackTrace.current,
      );
      return false;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// Mark payout as paid
  Future<bool> markPaid(String payoutId) async {
    state = const AsyncValue.loading();
    try {
      final response = await _service.markPaid(payoutId);
      if (response.success) {
        _invalidateProviders();
        state = const AsyncValue.data(null);
        return true;
      }
      state = AsyncValue.error(
        response.message ?? 'Failed to mark as paid',
        StackTrace.current,
      );
      return false;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// Cancel a payout
  Future<bool> cancelPayout(String payoutId, String reason) async {
    state = const AsyncValue.loading();
    try {
      final response = await _service.cancelPayout(payoutId, reason);
      if (response.success) {
        _invalidateProviders();
        state = const AsyncValue.data(null);
        return true;
      }
      state = AsyncValue.error(
        response.message ?? 'Failed to cancel payout',
        StackTrace.current,
      );
      return false;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// Update settings
  Future<bool> updateSettings(TipSettings settings) async {
    state = const AsyncValue.loading();
    try {
      final response = await _service.updateSettings(settings);
      if (response.success) {
        _ref.invalidate(tipSettingsProvider(settings.shopId));
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
    _ref.invalidate(activeTipsProvider);
    _ref.invalidate(activeTipsSummaryProvider);
    final shopId = _ref.read(tipsShopIdProvider);
    if (shopId != null) {
      _ref.invalidate(activePoolsProvider(shopId));
      _ref.invalidate(pendingPayoutsProvider(shopId));
      _ref.invalidate(payoutsProvider(shopId));
    }
  }
}

/// Provider for tips notifier
final tipsNotifierProvider =
    StateNotifierProvider<TipsNotifier, AsyncValue<void>>((ref) {
  final service = ref.watch(tipsServiceProvider);
  return TipsNotifier(service, ref);
});

// =============================================================================
// HELPER EXTENSIONS
// =============================================================================

extension TipPayoutX on TipPayout {
  /// Get status color value
  int get statusColorValue {
    switch (status) {
      case PayoutStatus.paid:
        return 0xFF10B981; // Green
      case PayoutStatus.approved:
        return 0xFF3B82F6; // Blue
      case PayoutStatus.processing:
        return 0xFF8B5CF6; // Purple
      case PayoutStatus.pending:
        return 0xFFF59E0B; // Yellow
      case PayoutStatus.cancelled:
        return 0xFF6B7280; // Gray
    }
  }

  /// Can be approved
  bool get canApprove => status == PayoutStatus.pending;

  /// Can be marked as paid
  bool get canMarkPaid =>
      status == PayoutStatus.approved || status == PayoutStatus.processing;

  /// Can be cancelled
  bool get canCancel =>
      status == PayoutStatus.pending || status == PayoutStatus.approved;
}

extension TipPoolX on TipPool {
  /// Get average per employee
  double get averagePerEmployee {
    if (employees.isEmpty) return 0;
    return totalAmount / employees.length;
  }

  /// Is active
  bool get isActive => !isClosed;

  /// Days remaining in period
  int get daysRemaining {
    if (isClosed) return 0;
    final remaining = periodEnd.difference(DateTime.now()).inDays;
    return remaining > 0 ? remaining : 0;
  }
}
