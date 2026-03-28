import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/bank_models.dart';
import '../services/bank_service.dart';
import '../../../core/providers/service_providers.dart' show apiServiceProvider;

// ═══════════════════════════════════════════════════════════════════════════
// Bank Service Provider
// ═══════════════════════════════════════════════════════════════════════════

final bankServiceProvider = Provider<BankService>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  return BankService(apiService);
});

// ═══════════════════════════════════════════════════════════════════════════
// Bank Accounts List Provider
// ═══════════════════════════════════════════════════════════════════════════

final bankAccountsProvider =
    FutureProvider.autoDispose<List<TenantBankAccount>>((ref) async {
  final bankService = ref.watch(bankServiceProvider);
  return await bankService.getBankAccounts();
});

/// Provider for active bank accounts only
final activeBankAccountsProvider =
    FutureProvider.autoDispose<List<TenantBankAccount>>((ref) async {
  final bankService = ref.watch(bankServiceProvider);
  return await bankService.getBankAccounts(isActive: true);
});

// ═══════════════════════════════════════════════════════════════════════════
// Default Bank Account Provider
// ═══════════════════════════════════════════════════════════════════════════

final defaultBankAccountProvider =
    FutureProvider.autoDispose<TenantBankAccount?>((ref) async {
  final bankService = ref.watch(bankServiceProvider);
  return await bankService.getDefaultBankAccount();
});

// ═══════════════════════════════════════════════════════════════════════════
// Single Bank Account Provider (by ID)
// ═══════════════════════════════════════════════════════════════════════════

final bankAccountProvider = FutureProvider.autoDispose
    .family<TenantBankAccount, String>((ref, accountId) async {
  final bankService = ref.watch(bankServiceProvider);
  return await bankService.getBankAccount(accountId);
});

// ═══════════════════════════════════════════════════════════════════════════
// Bank Account Summary Provider
// ═══════════════════════════════════════════════════════════════════════════

final bankAccountSummaryProvider = FutureProvider.autoDispose
    .family<BankAccountSummaryResponse, String>((ref, accountId) async {
  final bankService = ref.watch(bankServiceProvider);
  return await bankService.getAccountSummary(accountId);
});

// ═══════════════════════════════════════════════════════════════════════════
// Bank Transactions Provider (by account ID)
// ═══════════════════════════════════════════════════════════════════════════

final bankTransactionsProvider = FutureProvider.autoDispose
    .family<List<BankTransaction>, String>((ref, accountId) async {
  final bankService = ref.watch(bankServiceProvider);
  return await bankService.getBankTransactions(accountId, limit: 50);
});

/// Provider for all transactions across all accounts
final allBankTransactionsProvider =
    FutureProvider.autoDispose<List<BankTransaction>>((ref) async {
  final bankService = ref.watch(bankServiceProvider);
  return await bankService.getAllBankTransactions(limit: 50);
});

// ═══════════════════════════════════════════════════════════════════════════
// Bank Reconciliations Provider (by account ID)
// ═══════════════════════════════════════════════════════════════════════════

final bankReconciliationsProvider = FutureProvider.autoDispose
    .family<List<BankReconciliation>, String>((ref, accountId) async {
  final bankService = ref.watch(bankServiceProvider);
  return await bankService.getReconciliations(accountId, limit: 20);
});

// ═══════════════════════════════════════════════════════════════════════════
// Selected Bank Account State Provider
// ═══════════════════════════════════════════════════════════════════════════

final selectedBankAccountProvider =
    StateProvider<TenantBankAccount?>((ref) => null);

// ═══════════════════════════════════════════════════════════════════════════
// Bank Account Form State Notifier
// ═══════════════════════════════════════════════════════════════════════════

class BankAccountFormState {
  final bool isLoading;
  final String? errorMessage;
  final TenantBankAccount? createdAccount;

  BankAccountFormState({
    this.isLoading = false,
    this.errorMessage,
    this.createdAccount,
  });

  BankAccountFormState copyWith({
    bool? isLoading,
    String? errorMessage,
    TenantBankAccount? createdAccount,
  }) {
    return BankAccountFormState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      createdAccount: createdAccount ?? this.createdAccount,
    );
  }
}

class BankAccountFormNotifier extends StateNotifier<BankAccountFormState> {
  final BankService bankService;

  BankAccountFormNotifier(this.bankService) : super(BankAccountFormState());

  /// Create a new bank account
  Future<void> createBankAccount(CreateBankAccountRequest request) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final account = await bankService.createBankAccount(request);
      state = state.copyWith(
        isLoading: false,
        createdAccount: account,
        errorMessage: null,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// Update an existing bank account
  Future<void> updateBankAccount(
      String accountId, UpdateBankAccountRequest request) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final account =
          await bankService.updateBankAccount(accountId, request);
      state = state.copyWith(
        isLoading: false,
        createdAccount: account,
        errorMessage: null,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// Delete a bank account
  Future<void> deleteBankAccount(String accountId) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      await bankService.deleteBankAccount(accountId);
      state = state.copyWith(
        isLoading: false,
        errorMessage: null,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// Reset form state
  void reset() {
    state = BankAccountFormState();
  }
}

final bankAccountFormProvider =
    StateNotifierProvider<BankAccountFormNotifier, BankAccountFormState>(
        (ref) {
  final bankService = ref.watch(bankServiceProvider);
  return BankAccountFormNotifier(bankService);
});

// ═══════════════════════════════════════════════════════════════════════════
// Bank Transaction Form State Notifier
// ═══════════════════════════════════════════════════════════════════════════

class BankTransactionFormState {
  final bool isLoading;
  final String? errorMessage;
  final BankTransaction? createdTransaction;

  BankTransactionFormState({
    this.isLoading = false,
    this.errorMessage,
    this.createdTransaction,
  });

  BankTransactionFormState copyWith({
    bool? isLoading,
    String? errorMessage,
    BankTransaction? createdTransaction,
  }) {
    return BankTransactionFormState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      createdTransaction: createdTransaction ?? this.createdTransaction,
    );
  }
}

class BankTransactionFormNotifier
    extends StateNotifier<BankTransactionFormState> {
  final BankService bankService;

  BankTransactionFormNotifier(this.bankService)
      : super(BankTransactionFormState());

  /// Record a new transaction
  Future<void> recordTransaction(
      String accountId, RecordBankTransactionRequest request) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final transaction =
          await bankService.recordBankTransaction(accountId, request);
      state = state.copyWith(
        isLoading: false,
        createdTransaction: transaction,
        errorMessage: null,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// Reset form state
  void reset() {
    state = BankTransactionFormState();
  }
}

final bankTransactionFormProvider = StateNotifierProvider<
    BankTransactionFormNotifier, BankTransactionFormState>((ref) {
  final bankService = ref.watch(bankServiceProvider);
  return BankTransactionFormNotifier(bankService);
});

// ═══════════════════════════════════════════════════════════════════════════
// Bank Reconciliation Form State Notifier
// ═══════════════════════════════════════════════════════════════════════════

class BankReconciliationFormState {
  final bool isLoading;
  final String? errorMessage;
  final BankReconciliation? createdReconciliation;

  BankReconciliationFormState({
    this.isLoading = false,
    this.errorMessage,
    this.createdReconciliation,
  });

  BankReconciliationFormState copyWith({
    bool? isLoading,
    String? errorMessage,
    BankReconciliation? createdReconciliation,
  }) {
    return BankReconciliationFormState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      createdReconciliation:
          createdReconciliation ?? this.createdReconciliation,
    );
  }
}

class BankReconciliationFormNotifier
    extends StateNotifier<BankReconciliationFormState> {
  final BankService bankService;

  BankReconciliationFormNotifier(this.bankService)
      : super(BankReconciliationFormState());

  /// Create a new reconciliation
  Future<void> createReconciliation(
      String accountId, CreateBankReconciliationRequest request) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final reconciliation =
          await bankService.createReconciliation(accountId, request);
      state = state.copyWith(
        isLoading: false,
        createdReconciliation: reconciliation,
        errorMessage: null,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// Reset form state
  void reset() {
    state = BankReconciliationFormState();
  }
}

final bankReconciliationFormProvider = StateNotifierProvider<
    BankReconciliationFormNotifier, BankReconciliationFormState>((ref) {
  final bankService = ref.watch(bankServiceProvider);
  return BankReconciliationFormNotifier(bankService);
});
