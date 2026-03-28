import 'package:freezed_annotation/freezed_annotation.dart';

part 'bank_models.freezed.dart';
part 'bank_models.g.dart';

/// Tenant Bank Account Model
/// Represents a bank account with OD (Overdraft) tracking
/// All fields have sensible defaults to handle null values from backend
@freezed
class TenantBankAccount with _$TenantBankAccount {
  const factory TenantBankAccount({
    required String id,
    @JsonKey(name: 'tenant_id') String? tenantId,
    @JsonKey(name: 'bank_name') @Default('') String bankName,
    @JsonKey(name: 'account_number') @Default('') String accountNumber,
    @JsonKey(name: 'account_holder_name') @Default('') String accountHolderName,
    @JsonKey(name: 'ifsc_code') @Default('') String ifscCode,
    @JsonKey(name: 'branch_name') String? branchName,
    @JsonKey(name: 'branch_address') String? branchAddress,
    @JsonKey(name: 'account_type') @Default('savings') String accountType, // current, savings, od, cash_credit
    @JsonKey(name: 'current_balance') @Default(0.0) double currentBalance,
    @JsonKey(name: 'od_limit') @Default(0.0) double odLimit,
    @JsonKey(name: 'used_od_amount') @Default(0.0) double usedOdAmount,
    @JsonKey(name: 'available_od') @Default(0.0) double availableOd, // Computed: odLimit - usedOdAmount
    @JsonKey(name: 'total_available_balance') @Default(0.0) double totalAvailableBalance, // Computed: currentBalance + availableOd
    @JsonKey(name: 'od_interest_rate') @Default(0.0) double odInterestRate,
    @JsonKey(name: 'is_active') @Default(true) bool isActive,
    @JsonKey(name: 'is_default') @Default(false) bool isDefault,
    String? notes,
    @JsonKey(name: 'created_by') String? createdBy,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    @JsonKey(name: 'updated_at') DateTime? updatedAt,
    @JsonKey(name: 'deleted_at') DateTime? deletedAt,
  }) = _TenantBankAccount;

  factory TenantBankAccount.fromJson(Map<String, dynamic> json) =>
      _$TenantBankAccountFromJson(json);
}

/// Bank Transaction Model
/// Represents a single bank transaction with balance snapshots
/// All fields have sensible defaults to handle null values from backend
@freezed
class BankTransaction with _$BankTransaction {
  const factory BankTransaction({
    required String id,
    @JsonKey(name: 'bank_account_id') @Default('') String bankAccountId,
    @JsonKey(name: 'tenant_id') String? tenantId,
    @JsonKey(name: 'transaction_type') @Default('adjustment') String transactionType, // deposit, withdrawal, od_usage, od_repayment, interest_charge, bank_charges, adjustment
    @Default(0.0) double amount,
    @JsonKey(name: 'balance_before') @Default(0.0) double balanceBefore,
    @JsonKey(name: 'balance_after') @Default(0.0) double balanceAfter,
    @JsonKey(name: 'od_used_before') @Default(0.0) double odUsedBefore,
    @JsonKey(name: 'od_used_after') @Default(0.0) double odUsedAfter,
    @JsonKey(name: 'reference_type') String? referenceType, // cash_submission, manual, vendor_payment, etc.
    @JsonKey(name: 'reference_id') String? referenceId,
    @JsonKey(name: 'bank_reference_no') String? bankReferenceNo,
    @JsonKey(name: 'transaction_date') DateTime? transactionDate,
    String? description,
    String? notes,
    @JsonKey(name: 'is_reconciled') @Default(false) bool isReconciled,
    @JsonKey(name: 'created_by') String? createdBy,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    @JsonKey(name: 'updated_at') DateTime? updatedAt,
  }) = _BankTransaction;

  factory BankTransaction.fromJson(Map<String, dynamic> json) =>
      _$BankTransactionFromJson(json);
}

/// Bank Reconciliation Model
/// Represents a bank reconciliation record
/// All fields have sensible defaults to handle null values from backend
@freezed
class BankReconciliation with _$BankReconciliation {
  const factory BankReconciliation({
    required String id,
    @JsonKey(name: 'bank_account_id') @Default('') String bankAccountId,
    @JsonKey(name: 'tenant_id') String? tenantId,
    @JsonKey(name: 'reconciliation_date') DateTime? reconciliationDate,
    @JsonKey(name: 'system_balance') @Default(0.0) double systemBalance,
    @JsonKey(name: 'bank_statement_balance') @Default(0.0) double bankStatementBalance,
    @Default(0.0) double difference, // Computed: systemBalance - bankStatementBalance
    @Default('pending') String status, // pending, completed, discrepancy
    @JsonKey(name: 'total_deposits') @Default(0.0) double totalDeposits,
    @JsonKey(name: 'total_withdrawals') @Default(0.0) double totalWithdrawals,
    @JsonKey(name: 'transaction_count') @Default(0) int transactionCount,
    String? notes,
    @JsonKey(name: 'reconciled_by') @Default('') String reconciledBy,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    @JsonKey(name: 'updated_at') DateTime? updatedAt,
  }) = _BankReconciliation;

  factory BankReconciliation.fromJson(Map<String, dynamic> json) =>
      _$BankReconciliationFromJson(json);
}

/// Bank Account Summary Model
/// Represents analytics and summary for a bank account
/// All fields have sensible defaults to handle null values from backend
@freezed
class BankAccountSummary with _$BankAccountSummary {
  const factory BankAccountSummary({
    required TenantBankAccount account,
    @Default(0.0) double totalDepositsThisMonth,
    @Default(0.0) double totalWithdrawalsThisMonth,
    @Default(0) int transactionCount,
    @Default(0.0) double odUtilizationPercent,
    DateTime? lastReconciliationDate,
    String? lastTransactionDate,
  }) = _BankAccountSummary;

  factory BankAccountSummary.fromJson(Map<String, dynamic> json) =>
      _$BankAccountSummaryFromJson(json);
}

/// Account Type Enum
enum AccountType {
  current,
  savings,
  od,
  @JsonValue('cash_credit')
  cashCredit;

  String get displayName {
    switch (this) {
      case AccountType.current:
        return 'Current Account';
      case AccountType.savings:
        return 'Savings Account';
      case AccountType.od:
        return 'Overdraft Account';
      case AccountType.cashCredit:
        return 'Cash Credit Account';
    }
  }
}

/// Transaction Type Enum
enum TransactionType {
  deposit,
  withdrawal,
  @JsonValue('od_usage')
  odUsage,
  @JsonValue('od_repayment')
  odRepayment,
  @JsonValue('interest_charge')
  interestCharge,
  @JsonValue('bank_charges')
  bankCharges,
  adjustment;

  String get displayName {
    switch (this) {
      case TransactionType.deposit:
        return 'Deposit';
      case TransactionType.withdrawal:
        return 'Withdrawal';
      case TransactionType.odUsage:
        return 'OD Usage';
      case TransactionType.odRepayment:
        return 'OD Repayment';
      case TransactionType.interestCharge:
        return 'Interest Charge';
      case TransactionType.bankCharges:
        return 'Bank Charges';
      case TransactionType.adjustment:
        return 'Adjustment';
    }
  }

  String get icon {
    switch (this) {
      case TransactionType.deposit:
        return '💰';
      case TransactionType.withdrawal:
        return '💸';
      case TransactionType.odUsage:
        return '🔴';
      case TransactionType.odRepayment:
        return '✅';
      case TransactionType.interestCharge:
        return '📊';
      case TransactionType.bankCharges:
        return '🏦';
      case TransactionType.adjustment:
        return '⚙️';
    }
  }
}

/// Reconciliation Status Enum
enum ReconciliationStatus {
  pending,
  completed,
  discrepancy;

  String get displayName {
    switch (this) {
      case ReconciliationStatus.pending:
        return 'Pending';
      case ReconciliationStatus.completed:
        return 'Completed';
      case ReconciliationStatus.discrepancy:
        return 'Discrepancy Found';
    }
  }

  String get icon {
    switch (this) {
      case ReconciliationStatus.pending:
        return '⏳';
      case ReconciliationStatus.completed:
        return '✅';
      case ReconciliationStatus.discrepancy:
        return '⚠️';
    }
  }
}

/// Create Bank Account Request
/// Matches backend API: POST /api/finance/bank-accounts
@freezed
class CreateBankAccountRequest with _$CreateBankAccountRequest {
  const factory CreateBankAccountRequest({
    @JsonKey(name: 'bank_name') required String bankName,
    @JsonKey(name: 'account_number') required String accountNumber,
    @JsonKey(name: 'account_holder_name') required String accountHolderName,
    @JsonKey(name: 'ifsc_code') required String ifscCode,
    @JsonKey(name: 'branch_name') String? branchName,
    @JsonKey(name: 'account_type') @Default('savings') String accountType,
    @JsonKey(name: 'opening_balance') @Default(0.0) double openingBalance,
    @JsonKey(name: 'od_limit') @Default(0.0) double odLimit,
    @JsonKey(name: 'od_interest_rate') @Default(0.0) double odInterestRate,
    @JsonKey(name: 'is_default') @Default(false) bool isDefault,
    @JsonKey(name: 'is_primary') @Default(false) bool isPrimary,
    String? notes,
  }) = _CreateBankAccountRequest;

  factory CreateBankAccountRequest.fromJson(Map<String, dynamic> json) =>
      _$CreateBankAccountRequestFromJson(json);
}

/// Update Bank Account Request
/// Matches backend API: PUT /api/finance/bank-accounts/:id
@freezed
class UpdateBankAccountRequest with _$UpdateBankAccountRequest {
  const factory UpdateBankAccountRequest({
    @JsonKey(name: 'bank_name') String? bankName,
    @JsonKey(name: 'account_holder_name') String? accountHolderName,
    @JsonKey(name: 'branch_name') String? branchName,
    @JsonKey(name: 'od_limit') double? odLimit,
    @JsonKey(name: 'od_interest_rate') double? odInterestRate,
    @JsonKey(name: 'is_active') bool? isActive,
    @JsonKey(name: 'is_default') bool? isDefault,
    @JsonKey(name: 'is_primary') bool? isPrimary,
    String? notes,
  }) = _UpdateBankAccountRequest;

  factory UpdateBankAccountRequest.fromJson(Map<String, dynamic> json) =>
      _$UpdateBankAccountRequestFromJson(json);
}

/// Record Bank Transaction Request
@freezed
class RecordBankTransactionRequest with _$RecordBankTransactionRequest {
  const factory RecordBankTransactionRequest({
    @JsonKey(name: 'transaction_type') required String transactionType,
    required double amount,
    @JsonKey(name: 'bank_reference_no') String? bankReferenceNo,
    @JsonKey(name: 'transaction_date', toJson: _dateTimeToJson) DateTime? transactionDate,
    String? description,
    String? notes,
  }) = _RecordBankTransactionRequest;

  factory RecordBankTransactionRequest.fromJson(Map<String, dynamic> json) =>
      _$RecordBankTransactionRequestFromJson(json);
}

/// Helper function to convert DateTime to ISO 8601 with timezone
String? _dateTimeToJson(DateTime? dateTime) {
  if (dateTime == null) return null;
  // Convert to UTC and format as ISO 8601 with 'Z' timezone indicator
  return dateTime.toUtc().toIso8601String();
}

/// Create Bank Reconciliation Request
@freezed
class CreateBankReconciliationRequest with _$CreateBankReconciliationRequest {
  const factory CreateBankReconciliationRequest({
    required double bankStatementBalance,
    required DateTime reconciliationDate,
    String? notes,
  }) = _CreateBankReconciliationRequest;

  factory CreateBankReconciliationRequest.fromJson(
          Map<String, dynamic> json) =>
      _$CreateBankReconciliationRequestFromJson(json);
}

/// API Response Models
@freezed
class BankAccountResponse with _$BankAccountResponse {
  const factory BankAccountResponse({
    @JsonKey(name: 'bank_account') required TenantBankAccount bankAccount,
    String? message,
  }) = _BankAccountResponse;

  factory BankAccountResponse.fromJson(Map<String, dynamic> json) =>
      _$BankAccountResponseFromJson(json);
}

@freezed
class BankAccountsListResponse with _$BankAccountsListResponse {
  const factory BankAccountsListResponse({
    @JsonKey(name: 'bank_accounts') @Default([]) List<TenantBankAccount> bankAccounts,
    @Default(0) int count,
    @Default(0) int total,
    @JsonKey(name: 'total_count') @Default(0) int totalCount,
    @Default(1) int page,
    @JsonKey(name: 'page_size') @Default(100) int pageSize,
    @JsonKey(name: 'total_pages') @Default(1) int totalPages,
    @JsonKey(name: 'tenant_id') String? tenantId,
  }) = _BankAccountsListResponse;

  factory BankAccountsListResponse.fromJson(Map<String, dynamic> json) =>
      _$BankAccountsListResponseFromJson(json);
}

@freezed
class BankTransactionResponse with _$BankTransactionResponse {
  const factory BankTransactionResponse({
    required BankTransaction transaction,
    String? message,
  }) = _BankTransactionResponse;

  factory BankTransactionResponse.fromJson(Map<String, dynamic> json) =>
      _$BankTransactionResponseFromJson(json);
}

@freezed
class BankTransactionsListResponse with _$BankTransactionsListResponse {
  const factory BankTransactionsListResponse({
    required List<BankTransaction> transactions,
    @Default(0) int limit,
    @Default(0) int offset,
    @Default(0) int total,
  }) = _BankTransactionsListResponse;

  factory BankTransactionsListResponse.fromJson(Map<String, dynamic> json) =>
      _$BankTransactionsListResponseFromJson(json);
}

@freezed
class BankReconciliationResponse with _$BankReconciliationResponse {
  const factory BankReconciliationResponse({
    required BankReconciliation reconciliation,
    String? message,
  }) = _BankReconciliationResponse;

  factory BankReconciliationResponse.fromJson(Map<String, dynamic> json) =>
      _$BankReconciliationResponseFromJson(json);
}

@freezed
class BankReconciliationsListResponse with _$BankReconciliationsListResponse {
  const factory BankReconciliationsListResponse({
    @Default([]) List<BankReconciliation> reconciliations,
    @Default(0) int count,
  }) = _BankReconciliationsListResponse;

  factory BankReconciliationsListResponse.fromJson(
          Map<String, dynamic> json) =>
      _$BankReconciliationsListResponseFromJson(json);
}

@freezed
class BankAccountSummaryResponse with _$BankAccountSummaryResponse {
  const factory BankAccountSummaryResponse({
    TenantBankAccount? account, // Made nullable for default responses when endpoint doesn't exist
    @JsonKey(name: 'total_deposits_this_month') @Default(0.0) double totalDepositsThisMonth,
    @JsonKey(name: 'total_withdrawals_this_month') @Default(0.0) double totalWithdrawalsThisMonth,
    @JsonKey(name: 'transaction_count') @Default(0) int transactionCount,
    @JsonKey(name: 'od_utilization_percent') @Default(0.0) double odUtilizationPercent,
    @JsonKey(name: 'last_reconciliation_date') DateTime? lastReconciliationDate,
  }) = _BankAccountSummaryResponse;

  factory BankAccountSummaryResponse.fromJson(Map<String, dynamic> json) =>
      _$BankAccountSummaryResponseFromJson(json);
}
