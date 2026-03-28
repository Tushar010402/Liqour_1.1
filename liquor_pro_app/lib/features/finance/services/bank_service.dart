import '../../../core/services/dio_api_service.dart';
import '../../../core/utils/logger.dart';
import '../models/bank_models.dart';

/// Bank Account Service
/// Handles all bank account management API calls
class BankService {
  final DioApiService _apiService;

  BankService(this._apiService);

  // ═══════════════════════════════════════════════════════════════════════════
  // Bank Account CRUD Operations
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a new bank account
  Future<TenantBankAccount> createBankAccount(
      CreateBankAccountRequest request) async {
    try {
      Logger.info('[BankService] createBankAccount called');
      Logger.debug('[BankService] Request data: ${request.toJson()}');

      final response = await _apiService.post(
        '/api/finance/bank-accounts',
        body: request.toJson(),
      );

      Logger.info('[BankService] Create response received');
      Logger.debug('[BankService] Response success: ${response.success}');
      Logger.debug('[BankService] Response status: ${response.statusCode}');
      Logger.debug('[BankService] Response message: ${response.message}');
      Logger.debug('[BankService] Response data type: ${response.data.runtimeType}');
      Logger.debug('[BankService] Response data: ${response.data}');

      // Check if response was successful
      if (!response.success) {
        Logger.error('[BankService] API returned error: ${response.message}');
        throw Exception('API error: ${response.message ?? 'Unknown error'}');
      }

      // Check if data exists
      if (response.data == null) {
        Logger.error('[BankService] Response data is NULL!');
        throw Exception('No data returned from API');
      }

      // Data should be a Map
      if (response.data is! Map<String, dynamic>) {
        Logger.error('[BankService] Response data is not a Map! Type: ${response.data.runtimeType}');
        throw Exception('Invalid response format');
      }

      final dataMap = response.data as Map<String, dynamic>;
      Logger.debug('[BankService] Response has bank_account key: ${dataMap.containsKey('bank_account')}');

      final accountResponse = BankAccountResponse.fromJson(dataMap);
      Logger.info('[BankService] Successfully created bank account: ${accountResponse.bankAccount.id}');
      return accountResponse.bankAccount;
    } catch (e, stackTrace) {
      Logger.error('[BankService] Error in createBankAccount: $e');
      Logger.error('[BankService] Stack trace: $stackTrace');
      throw Exception('Failed to create bank account: $e');
    }
  }

  /// Get all bank accounts for the tenant
  Future<List<TenantBankAccount>> getBankAccounts({
    bool? isActive,
    String? accountType,
  }) async {
    try {
      Logger.info('[BankService] getBankAccounts called');
      final queryParams = <String, dynamic>{};

      if (isActive != null) {
        queryParams['is_active'] = isActive.toString();
      }
      if (accountType != null) {
        queryParams['account_type'] = accountType;
      }

      Logger.debug('[BankService] Calling GET /api/finance/bank-accounts');
      Logger.debug('[BankService] Query params: $queryParams');

      final response = await _apiService.get(
        '/api/finance/bank-accounts',
        queryParams: queryParams,
      );

      Logger.info('[BankService] Response received');
      Logger.debug('[BankService] Response success: ${response.success}');
      Logger.debug('[BankService] Response status: ${response.statusCode}');
      Logger.debug('[BankService] Response message: ${response.message}');

      // Check if response was successful
      if (!response.success) {
        Logger.error('[BankService] API returned error: ${response.message}');
        throw Exception(response.message ?? 'Failed to fetch bank accounts');
      }

      // DEFENSIVE: Handle null data gracefully
      if (response.data == null) {
        Logger.warning('[BankService] Response data is NULL - returning empty list');
        Logger.warning('[BankService] This may indicate authentication or routing issues');
        return [];
      }

      // DEFENSIVE: Handle non-Map data
      if (response.data is! Map<String, dynamic>) {
        Logger.warning('[BankService] Response data is not a Map: ${response.data.runtimeType}');
        Logger.debug('[BankService] Data: ${response.data}');
        return [];
      }

      final dataMap = response.data as Map<String, dynamic>;
      Logger.debug('[BankService] Response keys: ${dataMap.keys.toList()}');

      // DEFENSIVE: Handle missing bank_accounts key
      if (!dataMap.containsKey('bank_accounts')) {
        Logger.warning('[BankService] bank_accounts key missing - returning empty list');
        Logger.debug('[BankService] Available keys: ${dataMap.keys.toList()}');
        return [];
      }

      final listResponse = BankAccountsListResponse.fromJson(dataMap);
      Logger.info('[BankService] Parsed ${listResponse.bankAccounts.length} accounts');
      return listResponse.bankAccounts;
    } catch (e, stackTrace) {
      Logger.error('[BankService] Error in getBankAccounts: $e');
      Logger.error('[BankService] Stack trace: $stackTrace');
      throw Exception('Failed to fetch bank accounts: $e');
    }
  }

  /// Get a single bank account by ID
  Future<TenantBankAccount> getBankAccount(String accountId) async {
    try {
      Logger.info('[BankService] getBankAccount called for: $accountId');
      final response = await _apiService.get(
        '/api/finance/bank-accounts/$accountId',
      );

      Logger.debug('[BankService] getBankAccount response received');
      Logger.debug('[BankService] Response success: ${response.success}');
      Logger.debug('[BankService] Response data type: ${response.data.runtimeType}');

      // DEFENSIVE: Check if data is null or empty
      if (response.data == null) {
        throw Exception('Response data is null');
      }

      if (response.data is! Map<String, dynamic>) {
        throw Exception('Response data is not a Map, got: ${response.data.runtimeType}');
      }

      final dataMap = response.data as Map<String, dynamic>;
      Logger.debug('[BankService] Response keys: ${dataMap.keys.toList()}');

      // FIX: API returns data directly, not wrapped in 'bank_account'
      // Check if we have 'bank_account' wrapper OR direct data with 'id' key
      if (dataMap.containsKey('bank_account') && dataMap['bank_account'] != null) {
        // Wrapped response
        final accountResponse = BankAccountResponse.fromJson(dataMap);
        Logger.info('[BankService] Parsed wrapped bank account: ${accountResponse.bankAccount.bankName}');
        return accountResponse.bankAccount;
      } else if (dataMap.containsKey('id')) {
        // Direct response - parse directly as TenantBankAccount
        final account = TenantBankAccount.fromJson(dataMap);
        Logger.info('[BankService] Parsed direct bank account: ${account.bankName}');
        return account;
      } else {
        Logger.warning('[BankService] Neither bank_account nor id key found');
        Logger.debug('[BankService] Available keys: ${dataMap.keys.toList()}');
        throw Exception('Invalid response format - missing account data');
      }
    } catch (e, stackTrace) {
      Logger.error('[BankService] Error in getBankAccount: $e');
      Logger.error('[BankService] Stack trace: $stackTrace');
      throw Exception('Failed to fetch bank account: $e');
    }
  }

  /// Get the default bank account for the tenant
  Future<TenantBankAccount?> getDefaultBankAccount() async {
    try {
      final response = await _apiService.get(
        '/api/finance/bank-accounts/default',
      );

      final accountResponse = BankAccountResponse.fromJson(response.data);
      return accountResponse.bankAccount;
    } catch (e) {
      // No default account found or other error
      return null;
    }
  }

  /// Update a bank account
  Future<TenantBankAccount> updateBankAccount(
      String accountId, UpdateBankAccountRequest request) async {
    try {
      final response = await _apiService.put(
        '/api/finance/bank-accounts/$accountId',
        body: request.toJson(),
      );

      final accountResponse = BankAccountResponse.fromJson(response.data);
      return accountResponse.bankAccount;
    } catch (e) {
      throw Exception('Failed to update bank account: $e');
    }
  }

  /// Delete a bank account
  Future<void> deleteBankAccount(String accountId) async {
    try {
      await _apiService.delete(
        '/api/finance/bank-accounts/$accountId',
      );
    } catch (e) {
      throw Exception('Failed to delete bank account: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Bank Transaction Operations
  // ═══════════════════════════════════════════════════════════════════════════

  /// Record a bank transaction
  Future<BankTransaction> recordBankTransaction(
      String accountId, RecordBankTransactionRequest request) async {
    try {
      Logger.info('[BankService] recordBankTransaction called');
      Logger.debug('[BankService] Account ID: $accountId');
      Logger.debug('[BankService] Transaction type: ${request.transactionType}');
      Logger.debug('[BankService] Amount: ${request.amount}');

      final response = await _apiService.post(
        '/api/finance/bank-accounts/$accountId/transactions',
        body: request.toJson(),
      );

      Logger.info('[BankService] Transaction response received');
      Logger.debug('[BankService] Response success: ${response.success}');
      Logger.debug('[BankService] Response status: ${response.statusCode}');
      Logger.debug('[BankService] Response message: ${response.message}');
      Logger.debug('[BankService] Response data type: ${response.data.runtimeType}');

      // DEFENSIVE: Check response success
      if (!response.success) {
        Logger.error('[BankService] API returned error: ${response.message}');
        throw Exception(response.message ?? 'Failed to record transaction');
      }

      // DEFENSIVE: Handle null data
      if (response.data == null) {
        Logger.error('[BankService] Response data is NULL!');
        Logger.warning('[BankService] This may indicate authentication or backend issues');
        throw Exception('No data returned from server');
      }

      // DEFENSIVE: Handle non-Map data
      if (response.data is! Map<String, dynamic>) {
        Logger.error('[BankService] Response data is not a Map: ${response.data.runtimeType}');
        throw Exception('Invalid response format from server');
      }

      final dataMap = response.data as Map<String, dynamic>;
      Logger.debug('[BankService] Response keys: ${dataMap.keys.toList()}');

      // DEFENSIVE: Check for transaction key
      if (!dataMap.containsKey('transaction')) {
        Logger.warning('[BankService] transaction key missing in response');
        Logger.debug('[BankService] Available keys: ${dataMap.keys.toList()}');
        throw Exception('Invalid response structure from server');
      }

      final transactionResponse = BankTransactionResponse.fromJson(dataMap);
      Logger.info('[BankService] Transaction recorded successfully: ${transactionResponse.transaction.id}');
      return transactionResponse.transaction;
    } catch (e, stackTrace) {
      Logger.error('[BankService] Error in recordBankTransaction: $e');
      Logger.error('[BankService] Stack trace: $stackTrace');
      throw Exception('Failed to record transaction: $e');
    }
  }

  /// Get transactions for a specific bank account
  Future<List<BankTransaction>> getBankTransactions(String accountId,
      {DateTime? startDate, DateTime? endDate, int? limit}) async {
    try {
      final queryParams = <String, dynamic>{};

      if (startDate != null) {
        queryParams['start_date'] = startDate.toIso8601String();
      }
      if (endDate != null) {
        queryParams['end_date'] = endDate.toIso8601String();
      }
      if (limit != null) {
        queryParams['limit'] = limit.toString();
      }

      Logger.debug('[BankService] getBankTransactions called for account: $accountId');

      final response = await _apiService.get(
        '/api/finance/bank-accounts/$accountId/transactions',
        queryParams: queryParams,
      );

      Logger.debug('[BankService] Transactions response received');
      Logger.debug('[BankService] Response success: ${response.success}');

      // DEFENSIVE: Handle unsuccessful response
      if (!response.success) {
        Logger.error('[BankService] API returned error: ${response.message}');
        return [];
      }

      // DEFENSIVE: Handle null or invalid data
      if (response.data == null || response.data is! Map<String, dynamic>) {
        Logger.warning('[BankService] Invalid transaction response data - returning empty list');
        return [];
      }

      final listResponse = BankTransactionsListResponse.fromJson(response.data);
      Logger.info('[BankService] Parsed ${listResponse.transactions.length} transactions');
      return listResponse.transactions;
    } catch (e, stackTrace) {
      Logger.error('[BankService] Error in getBankTransactions: $e');
      Logger.error('[BankService] Stack trace: $stackTrace');
      // Return empty list instead of throwing to prevent crashes
      return [];
    }
  }

  /// Get all transactions across all bank accounts
  Future<List<BankTransaction>> getAllBankTransactions({
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
  }) async {
    try {
      final queryParams = <String, dynamic>{};

      if (startDate != null) {
        queryParams['start_date'] = startDate.toIso8601String();
      }
      if (endDate != null) {
        queryParams['end_date'] = endDate.toIso8601String();
      }
      if (limit != null) {
        queryParams['limit'] = limit.toString();
      }

      final response = await _apiService.get(
        '/api/finance/bank-accounts/transactions',
        queryParams: queryParams,
      );

      final listResponse = BankTransactionsListResponse.fromJson(response.data);
      return listResponse.transactions;
    } catch (e) {
      throw Exception('Failed to fetch transactions: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Bank Account Summary & Analytics
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get account summary with analytics
  /// Returns default values if endpoint doesn't exist (404)
  Future<BankAccountSummaryResponse> getAccountSummary(
      String accountId) async {
    try {
      Logger.debug('[BankService] getAccountSummary called for: $accountId');
      final response = await _apiService.get(
        '/api/finance/bank-accounts/$accountId/summary',
      );

      Logger.debug('[BankService] Summary response: ${response.success}');

      if (!response.success || response.data == null) {
        // Return default summary if endpoint doesn't exist
        Logger.warning('[BankService] Summary endpoint not available, returning defaults');
        return BankAccountSummaryResponse(
          totalDepositsThisMonth: 0,
          totalWithdrawalsThisMonth: 0,
          transactionCount: 0,
          odUtilizationPercent: 0,
        );
      }

      return BankAccountSummaryResponse.fromJson(response.data);
    } catch (e) {
      Logger.error('[BankService] Summary error (returning defaults): $e');
      // Return default summary on any error
      return BankAccountSummaryResponse(
        totalDepositsThisMonth: 0,
        totalWithdrawalsThisMonth: 0,
        transactionCount: 0,
        odUtilizationPercent: 0,
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Bank Reconciliation Operations
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a bank reconciliation
  Future<BankReconciliation> createReconciliation(
      String accountId, CreateBankReconciliationRequest request) async {
    try {
      final response = await _apiService.post(
        '/api/finance/bank-accounts/$accountId/reconciliations',
        body: request.toJson(),
      );

      final reconciliationResponse =
          BankReconciliationResponse.fromJson(response.data);
      return reconciliationResponse.reconciliation;
    } catch (e) {
      throw Exception('Failed to create reconciliation: $e');
    }
  }

  /// Get reconciliations for a specific bank account
  Future<List<BankReconciliation>> getReconciliations(String accountId,
      {int? limit}) async {
    try {
      final queryParams = <String, dynamic>{};

      if (limit != null) {
        queryParams['limit'] = limit.toString();
      }

      final response = await _apiService.get(
        '/api/finance/bank-accounts/$accountId/reconciliations',
        queryParams: queryParams,
      );

      final listResponse = BankReconciliationsListResponse.fromJson(response.data);
      return listResponse.reconciliations;
    } catch (e) {
      throw Exception('Failed to fetch reconciliations: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Helper Methods
  // ═══════════════════════════════════════════════════════════════════════════

  /// Calculate OD utilization percentage
  double calculateOdUtilization(TenantBankAccount account) {
    if (account.odLimit == 0) return 0.0;
    return (account.usedOdAmount / account.odLimit) * 100;
  }

  /// Check if account is close to OD limit (>80%)
  bool isOdLimitCritical(TenantBankAccount account) {
    return calculateOdUtilization(account) > 80;
  }

  /// Get OD utilization color
  /// Green: 0-50%, Yellow: 50-80%, Red: 80-100%
  String getOdUtilizationColor(TenantBankAccount account) {
    final utilization = calculateOdUtilization(account);
    if (utilization <= 50) return 'green';
    if (utilization <= 80) return 'yellow';
    return 'red';
  }

  /// Format currency for display
  String formatCurrency(double amount, {String symbol = '₹'}) {
    return '$symbol${amount.toStringAsFixed(2)}';
  }

  /// Format OD utilization as percentage
  String formatOdUtilization(TenantBankAccount account) {
    return '${calculateOdUtilization(account).toStringAsFixed(1)}%';
  }
}
