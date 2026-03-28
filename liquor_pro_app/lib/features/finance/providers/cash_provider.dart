import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/service_providers.dart';
import '../services/cash_service.dart';
import '../models/cash_models.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Service Provider
// OPTIMIZED: Added kDebugMode guards and reduced logging verbosity
// ══════════════════════════════════════════════════════════════════════════════

// Provider for CashService - depends on DioApiService
final cashServiceProvider = Provider<CashService>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  return CashService(apiService);
});

// ══════════════════════════════════════════════════════════════════════════════
// Cash Balance Providers
// ══════════════════════════════════════════════════════════════════════════════

/// Provider for current user's total cash balance (across all shops)
/// Cash is user-specific, not shop-specific
final cashBalanceProvider =
    FutureProvider<double>((ref) async {
  final cashService = ref.watch(cashServiceProvider);
  return await cashService.getCashBalance();
});

/// Provider for detailed cash holding
final cashHoldingProvider =
    FutureProvider.family<CashHolding?, String>((ref, shopId) async {
  final cashService = ref.watch(cashServiceProvider);
  return await cashService.getCashHolding(shopId);
});

/// Provider for team cash balances (hierarchical view)
/// User-specific: returns all subordinates' cash holdings across all shops
/// OPTIMIZED: Reduced logging verbosity with kDebugMode guards
final teamBalancesProvider =
    FutureProvider<List<TeamCashBalance>>((ref) async {
  final cashService = ref.watch(cashServiceProvider);

  try {
    final balances = await cashService.getTeamBalances();
    if (kDebugMode) print('💰 TeamBalancesProvider: Loaded ${balances.length} team members');
    return balances;
  } catch (e) {
    if (kDebugMode) print('❌ TeamBalancesProvider: Error - $e');
    rethrow;
  }
});

/// Provider for tenant users (for cash request selection - NO cash amounts shown)
/// Maintains hierarchical privacy: users don't see cash holdings, just user list
/// OPTIMIZED: Reduced logging verbosity with kDebugMode guards
final tenantUsersProvider =
    FutureProvider<List<TenantUser>>((ref) async {
  final cashService = ref.watch(cashServiceProvider);

  try {
    final users = await cashService.getTenantUsers();
    if (kDebugMode) print('👥 TenantUsersProvider: Loaded ${users.length} users');
    return users;
  } catch (e) {
    if (kDebugMode) print('❌ TenantUsersProvider: Error - $e');
    rethrow;
  }
});

// ══════════════════════════════════════════════════════════════════════════════
// Cash Collection Providers
// ══════════════════════════════════════════════════════════════════════════════

/// Provider for cash collection history
final collectionsProvider = FutureProvider.family<List<CashCollection>,
    CollectionsQuery>((ref, query) async {
  final cashService = ref.watch(cashServiceProvider);
  return await cashService.getCollections(
    shopId: query.shopId,
    status: query.status,
    limit: query.limit,
  );
});

/// Provider for pending collections only
final pendingCollectionsProvider =
    FutureProvider.family<List<CashCollection>, String>((ref, shopId) async {
  final cashService = ref.watch(cashServiceProvider);
  return await cashService.getCollections(shopId: shopId, status: 'pending');
});

// ══════════════════════════════════════════════════════════════════════════════
// Cash Submission Providers
// ══════════════════════════════════════════════════════════════════════════════

/// Provider for cash submission history
final submissionsProvider = FutureProvider.family<List<CashSubmission>,
    SubmissionsQuery>((ref, query) async {
  final cashService = ref.watch(cashServiceProvider);
  return await cashService.getSubmissions(
    userId: query.userId,
    shopId: query.shopId,
    status: query.status,
    limit: query.limit,
  );
});

/// Provider for pending submissions (for approval)
final pendingSubmissionsProvider =
    FutureProvider.family<List<CashSubmission>, String?>((ref, shopId) async {
  final cashService = ref.watch(cashServiceProvider);
  return await cashService.getPendingSubmissions(shopId: shopId);
});

// ══════════════════════════════════════════════════════════════════════════════
// Cash Request Providers (User requests cash FROM another user)
// ══════════════════════════════════════════════════════════════════════════════

/// Provider for cash request history (both sent and received)
/// OPTIMIZED: Reduced logging verbosity with kDebugMode guards
final cashRequestsProvider = FutureProvider.family<List<CashRequest>,
    CashRequestsQuery>((ref, query) async {
  final cashService = ref.watch(cashServiceProvider);

  try {
    final requests = await cashService.getCashRequests(
      shopId: query.shopId,
      status: query.status,
      filterType: query.filterType,
      limit: query.limit,
    );
    if (kDebugMode) print('📝 CashRequestsProvider: Loaded ${requests.length} requests');
    return requests;
  } catch (e) {
    if (kDebugMode) print('❌ CashRequestsProvider: Error - $e');
    rethrow;
  }
});

/// Provider for pending cash requests that need approval
final pendingCashRequestsProvider =
    FutureProvider.family<List<CashRequest>, String>((ref, shopId) async {
  final cashService = ref.watch(cashServiceProvider);
  return await cashService.getPendingCashRequests(shopId: shopId);
});

// ══════════════════════════════════════════════════════════════════════════════
// Cash History Provider
// ══════════════════════════════════════════════════════════════════════════════

/// Provider for complete cash transaction history
final cashHistoryProvider = FutureProvider.family<List<CashTransaction>,
    HistoryQuery>((ref, query) async {
  final cashService = ref.watch(cashServiceProvider);
  return await cashService.getCashHistory(
    shopId: query.shopId,
    transactionType: query.transactionType,
    limit: query.limit,
  );
});

// ══════════════════════════════════════════════════════════════════════════════
// Stateful Notifier Providers (for mutations)
// ══════════════════════════════════════════════════════════════════════════════

/// State notifier for cash operations
class CashNotifier extends StateNotifier<AsyncValue<void>> {
  final CashService _cashService;
  final Ref _ref;

  CashNotifier(this._cashService, this._ref) : super(const AsyncValue.data(null));

  /// Collect cash from a subordinate
  Future<bool> collectCash(CollectCashRequest request) async {
    state = const AsyncValue.loading();
    try {
      await _cashService.collectCash(request);

      // Invalidate related providers to refresh data
      _ref.invalidate(cashBalanceProvider);
      _ref.invalidate(cashHoldingProvider);
      _ref.invalidate(teamBalancesProvider);
      _ref.invalidate(collectionsProvider);
      _ref.invalidate(cashHistoryProvider);

      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// Submit cash to bank
  /// NOTE: Balance is NOT deducted at submission - only at approval
  /// So we only invalidate submission-related providers, not balance providers
  Future<bool> submitCash(SubmitCashRequest request) async {
    state = const AsyncValue.loading();
    try {
      await _cashService.submitCash(request);

      // Invalidate submission-related providers only
      // Balance providers NOT invalidated - balance changes only on APPROVAL
      _ref.invalidate(submissionsProvider);
      _ref.invalidate(pendingSubmissionsProvider);
      // Note: No transaction created until approval, so history unchanged

      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// Approve a cash submission
  /// NOTE: Balance IS deducted at approval - this is when cash actually moves
  Future<bool> approveSubmission(String submissionId) async {
    state = const AsyncValue.loading();
    try {
      await _cashService.approveSubmission(submissionId);

      // Invalidate ALL related providers - balance changes NOW
      _ref.invalidate(cashBalanceProvider);         // User's balance decreases
      _ref.invalidate(cashHoldingProvider);         // Holdings update
      _ref.invalidate(teamBalancesProvider);        // Manager sees updated team balances
      _ref.invalidate(submissionsProvider);         // Submission status changes
      _ref.invalidate(pendingSubmissionsProvider);  // Removed from pending list
      _ref.invalidate(cashHistoryProvider);         // Transaction created

      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// Reject a cash submission
  /// NOTE: Balance is NOT restored - it was never deducted (deduction only happens on approval)
  Future<bool> rejectSubmission(String submissionId, String reason) async {
    state = const AsyncValue.loading();
    try {
      await _cashService.rejectSubmission(submissionId, reason);

      // Invalidate submission-related providers only
      // Balance providers NOT invalidated - balance was never deducted
      _ref.invalidate(submissionsProvider);
      _ref.invalidate(pendingSubmissionsProvider);
      // No transaction created on rejection, so history unchanged

      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// Approve a cash collection request
  Future<bool> approveCollection(String collectionId) async {
    state = const AsyncValue.loading();
    try {
      await _cashService.approveCollection(collectionId);

      // Invalidate related providers to refresh data
      _ref.invalidate(collectionsProvider);
      _ref.invalidate(pendingCollectionsProvider);
      _ref.invalidate(cashHistoryProvider);
      _ref.invalidate(cashBalanceProvider); // Balance updated after approval
      _ref.invalidate(cashHoldingProvider);
      _ref.invalidate(teamBalancesProvider);

      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// Reject a cash collection request
  Future<bool> rejectCollection(String collectionId, String reason) async {
    state = const AsyncValue.loading();
    try {
      await _cashService.rejectCollection(collectionId, reason);

      // Invalidate related providers to refresh data
      _ref.invalidate(collectionsProvider);
      _ref.invalidate(pendingCollectionsProvider);
      _ref.invalidate(cashHistoryProvider);

      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// Create a cash request to another user
  Future<CashRequest?> createCashRequest({
    required String executiveId,
    String? shopId, // Shop is now optional (backend updated)
    required double amount,
    String? notes,
  }) async {
    state = const AsyncValue.loading();
    try {
      final request = await _cashService.createCashRequest(
        executiveId: executiveId,
        shopId: shopId,
        amount: amount,
        notes: notes,
      );

      // Invalidate related providers to refresh data
      _ref.invalidate(cashRequestsProvider);
      _ref.invalidate(cashHistoryProvider);

      state = const AsyncValue.data(null);
      return request;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return null;
    }
  }

  /// Approve a cash request (as requested_from user)
  Future<bool> approveCashRequest(String requestId) async {
    state = const AsyncValue.loading();
    try {
      await _cashService.approveCashRequest(requestId);

      // Invalidate related providers to refresh data
      _ref.invalidate(cashRequestsProvider);
      _ref.invalidate(pendingCashRequestsProvider);
      _ref.invalidate(cashHistoryProvider);
      _ref.invalidate(cashBalanceProvider); // Balance updated after approval
      _ref.invalidate(cashHoldingProvider);

      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// Reject a cash request
  Future<bool> rejectCashRequest(String requestId, String reason) async {
    state = const AsyncValue.loading();
    try {
      await _cashService.rejectCashRequest(requestId, reason);

      // Invalidate related providers to refresh data
      _ref.invalidate(cashRequestsProvider);
      _ref.invalidate(pendingCashRequestsProvider);
      _ref.invalidate(cashHistoryProvider);

      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// Upload receipt photo
  Future<String?> uploadReceiptPhoto(String filePath) async {
    try {
      return await _cashService.uploadReceiptPhoto(filePath);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return null;
    }
  }
}

final cashNotifierProvider =
    StateNotifierProvider<CashNotifier, AsyncValue<void>>((ref) {
  final cashService = ref.watch(cashServiceProvider);
  return CashNotifier(cashService, ref);
});

// ══════════════════════════════════════════════════════════════════════════════
// Query Objects for Family Providers
// ══════════════════════════════════════════════════════════════════════════════

class CollectionsQuery {
  final String? shopId;
  final String? status;
  final int limit;

  const CollectionsQuery({
    this.shopId,
    this.status,
    this.limit = 50,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CollectionsQuery &&
          runtimeType == other.runtimeType &&
          shopId == other.shopId &&
          status == other.status &&
          limit == other.limit;

  @override
  int get hashCode => shopId.hashCode ^ status.hashCode ^ limit.hashCode;
}

class SubmissionsQuery {
  final String? userId;  // Filter by specific user
  final String? shopId;
  final String? status;
  final int limit;

  const SubmissionsQuery({
    this.userId,
    this.shopId,
    this.status,
    this.limit = 50,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SubmissionsQuery &&
          runtimeType == other.runtimeType &&
          userId == other.userId &&
          shopId == other.shopId &&
          status == other.status &&
          limit == other.limit;

  @override
  int get hashCode => userId.hashCode ^ shopId.hashCode ^ status.hashCode ^ limit.hashCode;
}

class HistoryQuery {
  final String? shopId;
  final String? transactionType;
  final int limit;

  const HistoryQuery({
    this.shopId,
    this.transactionType,
    this.limit = 100,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HistoryQuery &&
          runtimeType == other.runtimeType &&
          shopId == other.shopId &&
          transactionType == other.transactionType &&
          limit == other.limit;

  @override
  int get hashCode =>
      shopId.hashCode ^ transactionType.hashCode ^ limit.hashCode;
}

class CashRequestsQuery {
  final String? shopId;
  final String? status;
  final String? filterType; // 'sent', 'received', or null for both
  final int limit;

  const CashRequestsQuery({
    this.shopId,
    this.status,
    this.filterType,
    this.limit = 50,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CashRequestsQuery &&
          runtimeType == other.runtimeType &&
          shopId == other.shopId &&
          status == other.status &&
          filterType == other.filterType &&
          limit == other.limit;

  @override
  int get hashCode =>
      shopId.hashCode ^ status.hashCode ^ filterType.hashCode ^ limit.hashCode;
}
