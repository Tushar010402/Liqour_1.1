// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bank_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$TenantBankAccountImpl _$$TenantBankAccountImplFromJson(
        Map<String, dynamic> json) =>
    _$TenantBankAccountImpl(
      id: json['id'] as String,
      tenantId: json['tenant_id'] as String?,
      bankName: json['bank_name'] as String? ?? '',
      accountNumber: json['account_number'] as String? ?? '',
      accountHolderName: json['account_holder_name'] as String? ?? '',
      ifscCode: json['ifsc_code'] as String? ?? '',
      branchName: json['branch_name'] as String?,
      branchAddress: json['branch_address'] as String?,
      accountType: json['account_type'] as String? ?? 'savings',
      currentBalance: (json['current_balance'] as num?)?.toDouble() ?? 0.0,
      odLimit: (json['od_limit'] as num?)?.toDouble() ?? 0.0,
      usedOdAmount: (json['used_od_amount'] as num?)?.toDouble() ?? 0.0,
      availableOd: (json['available_od'] as num?)?.toDouble() ?? 0.0,
      totalAvailableBalance:
          (json['total_available_balance'] as num?)?.toDouble() ?? 0.0,
      odInterestRate: (json['od_interest_rate'] as num?)?.toDouble() ?? 0.0,
      isActive: json['is_active'] as bool? ?? true,
      isDefault: json['is_default'] as bool? ?? false,
      notes: json['notes'] as String?,
      createdBy: json['created_by'] as String?,
      createdAt: json['created_at'] == null
          ? null
          : DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.parse(json['updated_at'] as String),
      deletedAt: json['deleted_at'] == null
          ? null
          : DateTime.parse(json['deleted_at'] as String),
    );

Map<String, dynamic> _$$TenantBankAccountImplToJson(
        _$TenantBankAccountImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'tenant_id': instance.tenantId,
      'bank_name': instance.bankName,
      'account_number': instance.accountNumber,
      'account_holder_name': instance.accountHolderName,
      'ifsc_code': instance.ifscCode,
      'branch_name': instance.branchName,
      'branch_address': instance.branchAddress,
      'account_type': instance.accountType,
      'current_balance': instance.currentBalance,
      'od_limit': instance.odLimit,
      'used_od_amount': instance.usedOdAmount,
      'available_od': instance.availableOd,
      'total_available_balance': instance.totalAvailableBalance,
      'od_interest_rate': instance.odInterestRate,
      'is_active': instance.isActive,
      'is_default': instance.isDefault,
      'notes': instance.notes,
      'created_by': instance.createdBy,
      'created_at': instance.createdAt?.toIso8601String(),
      'updated_at': instance.updatedAt?.toIso8601String(),
      'deleted_at': instance.deletedAt?.toIso8601String(),
    };

_$BankTransactionImpl _$$BankTransactionImplFromJson(
        Map<String, dynamic> json) =>
    _$BankTransactionImpl(
      id: json['id'] as String,
      bankAccountId: json['bank_account_id'] as String? ?? '',
      tenantId: json['tenant_id'] as String?,
      transactionType: json['transaction_type'] as String? ?? 'adjustment',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      balanceBefore: (json['balance_before'] as num?)?.toDouble() ?? 0.0,
      balanceAfter: (json['balance_after'] as num?)?.toDouble() ?? 0.0,
      odUsedBefore: (json['od_used_before'] as num?)?.toDouble() ?? 0.0,
      odUsedAfter: (json['od_used_after'] as num?)?.toDouble() ?? 0.0,
      referenceType: json['reference_type'] as String?,
      referenceId: json['reference_id'] as String?,
      bankReferenceNo: json['bank_reference_no'] as String?,
      transactionDate: json['transaction_date'] == null
          ? null
          : DateTime.parse(json['transaction_date'] as String),
      description: json['description'] as String?,
      notes: json['notes'] as String?,
      isReconciled: json['is_reconciled'] as bool? ?? false,
      createdBy: json['created_by'] as String?,
      createdAt: json['created_at'] == null
          ? null
          : DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.parse(json['updated_at'] as String),
    );

Map<String, dynamic> _$$BankTransactionImplToJson(
        _$BankTransactionImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'bank_account_id': instance.bankAccountId,
      'tenant_id': instance.tenantId,
      'transaction_type': instance.transactionType,
      'amount': instance.amount,
      'balance_before': instance.balanceBefore,
      'balance_after': instance.balanceAfter,
      'od_used_before': instance.odUsedBefore,
      'od_used_after': instance.odUsedAfter,
      'reference_type': instance.referenceType,
      'reference_id': instance.referenceId,
      'bank_reference_no': instance.bankReferenceNo,
      'transaction_date': instance.transactionDate?.toIso8601String(),
      'description': instance.description,
      'notes': instance.notes,
      'is_reconciled': instance.isReconciled,
      'created_by': instance.createdBy,
      'created_at': instance.createdAt?.toIso8601String(),
      'updated_at': instance.updatedAt?.toIso8601String(),
    };

_$BankReconciliationImpl _$$BankReconciliationImplFromJson(
        Map<String, dynamic> json) =>
    _$BankReconciliationImpl(
      id: json['id'] as String,
      bankAccountId: json['bank_account_id'] as String? ?? '',
      tenantId: json['tenant_id'] as String?,
      reconciliationDate: json['reconciliation_date'] == null
          ? null
          : DateTime.parse(json['reconciliation_date'] as String),
      systemBalance: (json['system_balance'] as num?)?.toDouble() ?? 0.0,
      bankStatementBalance:
          (json['bank_statement_balance'] as num?)?.toDouble() ?? 0.0,
      difference: (json['difference'] as num?)?.toDouble() ?? 0.0,
      status: json['status'] as String? ?? 'pending',
      totalDeposits: (json['total_deposits'] as num?)?.toDouble() ?? 0.0,
      totalWithdrawals: (json['total_withdrawals'] as num?)?.toDouble() ?? 0.0,
      transactionCount: (json['transaction_count'] as num?)?.toInt() ?? 0,
      notes: json['notes'] as String?,
      reconciledBy: json['reconciled_by'] as String? ?? '',
      createdAt: json['created_at'] == null
          ? null
          : DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.parse(json['updated_at'] as String),
    );

Map<String, dynamic> _$$BankReconciliationImplToJson(
        _$BankReconciliationImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'bank_account_id': instance.bankAccountId,
      'tenant_id': instance.tenantId,
      'reconciliation_date': instance.reconciliationDate?.toIso8601String(),
      'system_balance': instance.systemBalance,
      'bank_statement_balance': instance.bankStatementBalance,
      'difference': instance.difference,
      'status': instance.status,
      'total_deposits': instance.totalDeposits,
      'total_withdrawals': instance.totalWithdrawals,
      'transaction_count': instance.transactionCount,
      'notes': instance.notes,
      'reconciled_by': instance.reconciledBy,
      'created_at': instance.createdAt?.toIso8601String(),
      'updated_at': instance.updatedAt?.toIso8601String(),
    };

_$BankAccountSummaryImpl _$$BankAccountSummaryImplFromJson(
        Map<String, dynamic> json) =>
    _$BankAccountSummaryImpl(
      account:
          TenantBankAccount.fromJson(json['account'] as Map<String, dynamic>),
      totalDepositsThisMonth:
          (json['totalDepositsThisMonth'] as num?)?.toDouble() ?? 0.0,
      totalWithdrawalsThisMonth:
          (json['totalWithdrawalsThisMonth'] as num?)?.toDouble() ?? 0.0,
      transactionCount: (json['transactionCount'] as num?)?.toInt() ?? 0,
      odUtilizationPercent:
          (json['odUtilizationPercent'] as num?)?.toDouble() ?? 0.0,
      lastReconciliationDate: json['lastReconciliationDate'] == null
          ? null
          : DateTime.parse(json['lastReconciliationDate'] as String),
      lastTransactionDate: json['lastTransactionDate'] as String?,
    );

Map<String, dynamic> _$$BankAccountSummaryImplToJson(
        _$BankAccountSummaryImpl instance) =>
    <String, dynamic>{
      'account': instance.account.toJson(),
      'totalDepositsThisMonth': instance.totalDepositsThisMonth,
      'totalWithdrawalsThisMonth': instance.totalWithdrawalsThisMonth,
      'transactionCount': instance.transactionCount,
      'odUtilizationPercent': instance.odUtilizationPercent,
      'lastReconciliationDate':
          instance.lastReconciliationDate?.toIso8601String(),
      'lastTransactionDate': instance.lastTransactionDate,
    };

_$CreateBankAccountRequestImpl _$$CreateBankAccountRequestImplFromJson(
        Map<String, dynamic> json) =>
    _$CreateBankAccountRequestImpl(
      bankName: json['bank_name'] as String,
      accountNumber: json['account_number'] as String,
      accountHolderName: json['account_holder_name'] as String,
      ifscCode: json['ifsc_code'] as String,
      branchName: json['branch_name'] as String?,
      accountType: json['account_type'] as String? ?? 'savings',
      openingBalance: (json['opening_balance'] as num?)?.toDouble() ?? 0.0,
      odLimit: (json['od_limit'] as num?)?.toDouble() ?? 0.0,
      odInterestRate: (json['od_interest_rate'] as num?)?.toDouble() ?? 0.0,
      isDefault: json['is_default'] as bool? ?? false,
      isPrimary: json['is_primary'] as bool? ?? false,
      notes: json['notes'] as String?,
    );

Map<String, dynamic> _$$CreateBankAccountRequestImplToJson(
        _$CreateBankAccountRequestImpl instance) =>
    <String, dynamic>{
      'bank_name': instance.bankName,
      'account_number': instance.accountNumber,
      'account_holder_name': instance.accountHolderName,
      'ifsc_code': instance.ifscCode,
      'branch_name': instance.branchName,
      'account_type': instance.accountType,
      'opening_balance': instance.openingBalance,
      'od_limit': instance.odLimit,
      'od_interest_rate': instance.odInterestRate,
      'is_default': instance.isDefault,
      'is_primary': instance.isPrimary,
      'notes': instance.notes,
    };

_$UpdateBankAccountRequestImpl _$$UpdateBankAccountRequestImplFromJson(
        Map<String, dynamic> json) =>
    _$UpdateBankAccountRequestImpl(
      bankName: json['bank_name'] as String?,
      accountHolderName: json['account_holder_name'] as String?,
      branchName: json['branch_name'] as String?,
      odLimit: (json['od_limit'] as num?)?.toDouble(),
      odInterestRate: (json['od_interest_rate'] as num?)?.toDouble(),
      isActive: json['is_active'] as bool?,
      isDefault: json['is_default'] as bool?,
      isPrimary: json['is_primary'] as bool?,
      notes: json['notes'] as String?,
    );

Map<String, dynamic> _$$UpdateBankAccountRequestImplToJson(
        _$UpdateBankAccountRequestImpl instance) =>
    <String, dynamic>{
      'bank_name': instance.bankName,
      'account_holder_name': instance.accountHolderName,
      'branch_name': instance.branchName,
      'od_limit': instance.odLimit,
      'od_interest_rate': instance.odInterestRate,
      'is_active': instance.isActive,
      'is_default': instance.isDefault,
      'is_primary': instance.isPrimary,
      'notes': instance.notes,
    };

_$RecordBankTransactionRequestImpl _$$RecordBankTransactionRequestImplFromJson(
        Map<String, dynamic> json) =>
    _$RecordBankTransactionRequestImpl(
      transactionType: json['transaction_type'] as String,
      amount: (json['amount'] as num).toDouble(),
      bankReferenceNo: json['bank_reference_no'] as String?,
      transactionDate: json['transaction_date'] == null
          ? null
          : DateTime.parse(json['transaction_date'] as String),
      description: json['description'] as String?,
      notes: json['notes'] as String?,
    );

Map<String, dynamic> _$$RecordBankTransactionRequestImplToJson(
        _$RecordBankTransactionRequestImpl instance) =>
    <String, dynamic>{
      'transaction_type': instance.transactionType,
      'amount': instance.amount,
      'bank_reference_no': instance.bankReferenceNo,
      'transaction_date': _dateTimeToJson(instance.transactionDate),
      'description': instance.description,
      'notes': instance.notes,
    };

_$CreateBankReconciliationRequestImpl
    _$$CreateBankReconciliationRequestImplFromJson(Map<String, dynamic> json) =>
        _$CreateBankReconciliationRequestImpl(
          bankStatementBalance:
              (json['bankStatementBalance'] as num).toDouble(),
          reconciliationDate:
              DateTime.parse(json['reconciliationDate'] as String),
          notes: json['notes'] as String?,
        );

Map<String, dynamic> _$$CreateBankReconciliationRequestImplToJson(
        _$CreateBankReconciliationRequestImpl instance) =>
    <String, dynamic>{
      'bankStatementBalance': instance.bankStatementBalance,
      'reconciliationDate': instance.reconciliationDate.toIso8601String(),
      'notes': instance.notes,
    };

_$BankAccountResponseImpl _$$BankAccountResponseImplFromJson(
        Map<String, dynamic> json) =>
    _$BankAccountResponseImpl(
      bankAccount: TenantBankAccount.fromJson(
          json['bank_account'] as Map<String, dynamic>),
      message: json['message'] as String?,
    );

Map<String, dynamic> _$$BankAccountResponseImplToJson(
        _$BankAccountResponseImpl instance) =>
    <String, dynamic>{
      'bank_account': instance.bankAccount.toJson(),
      'message': instance.message,
    };

_$BankAccountsListResponseImpl _$$BankAccountsListResponseImplFromJson(
        Map<String, dynamic> json) =>
    _$BankAccountsListResponseImpl(
      bankAccounts: (json['bank_accounts'] as List<dynamic>?)
              ?.map(
                  (e) => TenantBankAccount.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      count: (json['count'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toInt() ?? 0,
      totalCount: (json['total_count'] as num?)?.toInt() ?? 0,
      page: (json['page'] as num?)?.toInt() ?? 1,
      pageSize: (json['page_size'] as num?)?.toInt() ?? 100,
      totalPages: (json['total_pages'] as num?)?.toInt() ?? 1,
      tenantId: json['tenant_id'] as String?,
    );

Map<String, dynamic> _$$BankAccountsListResponseImplToJson(
        _$BankAccountsListResponseImpl instance) =>
    <String, dynamic>{
      'bank_accounts': instance.bankAccounts.map((e) => e.toJson()).toList(),
      'count': instance.count,
      'total': instance.total,
      'total_count': instance.totalCount,
      'page': instance.page,
      'page_size': instance.pageSize,
      'total_pages': instance.totalPages,
      'tenant_id': instance.tenantId,
    };

_$BankTransactionResponseImpl _$$BankTransactionResponseImplFromJson(
        Map<String, dynamic> json) =>
    _$BankTransactionResponseImpl(
      transaction:
          BankTransaction.fromJson(json['transaction'] as Map<String, dynamic>),
      message: json['message'] as String?,
    );

Map<String, dynamic> _$$BankTransactionResponseImplToJson(
        _$BankTransactionResponseImpl instance) =>
    <String, dynamic>{
      'transaction': instance.transaction.toJson(),
      'message': instance.message,
    };

_$BankTransactionsListResponseImpl _$$BankTransactionsListResponseImplFromJson(
        Map<String, dynamic> json) =>
    _$BankTransactionsListResponseImpl(
      transactions: (json['transactions'] as List<dynamic>)
          .map((e) => BankTransaction.fromJson(e as Map<String, dynamic>))
          .toList(),
      limit: (json['limit'] as num?)?.toInt() ?? 0,
      offset: (json['offset'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$$BankTransactionsListResponseImplToJson(
        _$BankTransactionsListResponseImpl instance) =>
    <String, dynamic>{
      'transactions': instance.transactions.map((e) => e.toJson()).toList(),
      'limit': instance.limit,
      'offset': instance.offset,
      'total': instance.total,
    };

_$BankReconciliationResponseImpl _$$BankReconciliationResponseImplFromJson(
        Map<String, dynamic> json) =>
    _$BankReconciliationResponseImpl(
      reconciliation: BankReconciliation.fromJson(
          json['reconciliation'] as Map<String, dynamic>),
      message: json['message'] as String?,
    );

Map<String, dynamic> _$$BankReconciliationResponseImplToJson(
        _$BankReconciliationResponseImpl instance) =>
    <String, dynamic>{
      'reconciliation': instance.reconciliation.toJson(),
      'message': instance.message,
    };

_$BankReconciliationsListResponseImpl
    _$$BankReconciliationsListResponseImplFromJson(Map<String, dynamic> json) =>
        _$BankReconciliationsListResponseImpl(
          reconciliations: (json['reconciliations'] as List<dynamic>?)
                  ?.map((e) =>
                      BankReconciliation.fromJson(e as Map<String, dynamic>))
                  .toList() ??
              const [],
          count: (json['count'] as num?)?.toInt() ?? 0,
        );

Map<String, dynamic> _$$BankReconciliationsListResponseImplToJson(
        _$BankReconciliationsListResponseImpl instance) =>
    <String, dynamic>{
      'reconciliations':
          instance.reconciliations.map((e) => e.toJson()).toList(),
      'count': instance.count,
    };

_$BankAccountSummaryResponseImpl _$$BankAccountSummaryResponseImplFromJson(
        Map<String, dynamic> json) =>
    _$BankAccountSummaryResponseImpl(
      account: json['account'] == null
          ? null
          : TenantBankAccount.fromJson(json['account'] as Map<String, dynamic>),
      totalDepositsThisMonth:
          (json['total_deposits_this_month'] as num?)?.toDouble() ?? 0.0,
      totalWithdrawalsThisMonth:
          (json['total_withdrawals_this_month'] as num?)?.toDouble() ?? 0.0,
      transactionCount: (json['transaction_count'] as num?)?.toInt() ?? 0,
      odUtilizationPercent:
          (json['od_utilization_percent'] as num?)?.toDouble() ?? 0.0,
      lastReconciliationDate: json['last_reconciliation_date'] == null
          ? null
          : DateTime.parse(json['last_reconciliation_date'] as String),
    );

Map<String, dynamic> _$$BankAccountSummaryResponseImplToJson(
        _$BankAccountSummaryResponseImpl instance) =>
    <String, dynamic>{
      'account': instance.account?.toJson(),
      'total_deposits_this_month': instance.totalDepositsThisMonth,
      'total_withdrawals_this_month': instance.totalWithdrawalsThisMonth,
      'transaction_count': instance.transactionCount,
      'od_utilization_percent': instance.odUtilizationPercent,
      'last_reconciliation_date':
          instance.lastReconciliationDate?.toIso8601String(),
    };
