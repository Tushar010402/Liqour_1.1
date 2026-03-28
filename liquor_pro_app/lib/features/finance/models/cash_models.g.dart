// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cash_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CashHolding _$CashHoldingFromJson(Map<String, dynamic> json) => CashHolding(
      id: json['id'] as String,
      userId: json['user_id'] as String? ?? '',
      shopId: json['shop_id'] as String?,
      currentBalance: (json['current_balance'] as num?)?.toDouble() ?? 0.0,
      lastUpdatedAt: json['last_updated_at'] == null
          ? null
          : DateTime.parse(json['last_updated_at'] as String),
      createdAt: json['created_at'] == null
          ? null
          : DateTime.parse(json['created_at'] as String),
      user: json['user'] == null
          ? null
          : UserBasicInfo.fromJson(json['user'] as Map<String, dynamic>),
      shop: json['shop'] == null
          ? null
          : ShopBasicInfo.fromJson(json['shop'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$CashHoldingToJson(CashHolding instance) =>
    <String, dynamic>{
      'id': instance.id,
      'user_id': instance.userId,
      'shop_id': instance.shopId,
      'current_balance': instance.currentBalance,
      'last_updated_at': instance.lastUpdatedAt?.toIso8601String(),
      'created_at': instance.createdAt?.toIso8601String(),
      'user': instance.user?.toJson(),
      'shop': instance.shop?.toJson(),
    };

CashCollection _$CashCollectionFromJson(Map<String, dynamic> json) =>
    CashCollection(
      id: json['id'] as String,
      fromUserId: json['from_user_id'] as String? ?? '',
      toUserId: json['to_user_id'] as String? ?? '',
      shopId: json['shop_id'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      collectionDate: json['collection_date'] == null
          ? null
          : DateTime.parse(json['collection_date'] as String),
      notes: json['notes'] as String?,
      status: json['status'] as String? ?? 'pending',
      expiresAt: json['expires_at'] == null
          ? null
          : DateTime.parse(json['expires_at'] as String),
      approvedAt: json['approved_at'] == null
          ? null
          : DateTime.parse(json['approved_at'] as String),
      approvedById: json['approved_by_id'] as String?,
      rejectedAt: json['rejected_at'] == null
          ? null
          : DateTime.parse(json['rejected_at'] as String),
      rejectReason: json['reject_reason'] as String?,
      createdAt: json['created_at'] == null
          ? null
          : DateTime.parse(json['created_at'] as String),
      fromUser: json['from_user'] == null
          ? null
          : UserBasicInfo.fromJson(json['from_user'] as Map<String, dynamic>),
      toUser: json['to_user'] == null
          ? null
          : UserBasicInfo.fromJson(json['to_user'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$CashCollectionToJson(CashCollection instance) =>
    <String, dynamic>{
      'id': instance.id,
      'from_user_id': instance.fromUserId,
      'to_user_id': instance.toUserId,
      'shop_id': instance.shopId,
      'amount': instance.amount,
      'collection_date': instance.collectionDate?.toIso8601String(),
      'notes': instance.notes,
      'status': instance.status,
      'expires_at': instance.expiresAt?.toIso8601String(),
      'approved_at': instance.approvedAt?.toIso8601String(),
      'approved_by_id': instance.approvedById,
      'rejected_at': instance.rejectedAt?.toIso8601String(),
      'reject_reason': instance.rejectReason,
      'created_at': instance.createdAt?.toIso8601String(),
      'from_user': instance.fromUser?.toJson(),
      'to_user': instance.toUser?.toJson(),
    };

CashSubmission _$CashSubmissionFromJson(Map<String, dynamic> json) =>
    CashSubmission(
      id: json['id'] as String? ?? '',
      userId: json['created_by_id'] as String? ?? '',
      userName: json['created_by_name'] as String? ?? '',
      shopId: json['shop_id'] as String? ?? '',
      shopName: json['shop_name'] as String? ?? '',
      totalAmount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      notes500: (json['notes_500'] as num?)?.toInt() ?? 0,
      notes200: (json['notes_200'] as num?)?.toInt() ?? 0,
      notes100: (json['notes_100'] as num?)?.toInt() ?? 0,
      notes50: (json['notes_50'] as num?)?.toInt() ?? 0,
      notes20: (json['notes_20'] as num?)?.toInt() ?? 0,
      notes10: (json['notes_10'] as num?)?.toInt() ?? 0,
      bankAccountId: json['bank_account_id'] as String?,
      bankAccountName: json['bank_account_name'] as String? ?? '',
      bankSlipNumber: json['slip_number'] as String?,
      depositDate: _$JsonConverterFromJson<String, DateTime>(
          json['deposit_date'], const Rfc3339DateTimeConverter().fromJson),
      receiptPhotoUrl: json['receipt_photo_url'] as String? ?? '',
      notes: json['notes'] as String?,
      status: json['status'] as String? ?? 'pending',
      approvedAt: json['approved_at'] == null
          ? null
          : DateTime.parse(json['approved_at'] as String),
      approvedById: json['approved_by_id'] as String?,
      rejectionReason: json['rejection_reason'] as String?,
      createdAt: json['created_at'] == null
          ? null
          : DateTime.parse(json['created_at'] as String),
      user: json['user'] == null
          ? null
          : UserBasicInfo.fromJson(json['user'] as Map<String, dynamic>),
      approvedBy: json['approved_by'] == null
          ? null
          : UserBasicInfo.fromJson(json['approved_by'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$CashSubmissionToJson(CashSubmission instance) =>
    <String, dynamic>{
      'id': instance.id,
      'created_by_id': instance.userId,
      'created_by_name': instance.userName,
      'shop_id': instance.shopId,
      'shop_name': instance.shopName,
      'amount': instance.totalAmount,
      'notes_500': instance.notes500,
      'notes_200': instance.notes200,
      'notes_100': instance.notes100,
      'notes_50': instance.notes50,
      'notes_20': instance.notes20,
      'notes_10': instance.notes10,
      'bank_account_id': instance.bankAccountId,
      'bank_account_name': instance.bankAccountName,
      'slip_number': instance.bankSlipNumber,
      'deposit_date': _$JsonConverterToJson<String, DateTime>(
          instance.depositDate, const Rfc3339DateTimeConverter().toJson),
      'receipt_photo_url': instance.receiptPhotoUrl,
      'notes': instance.notes,
      'status': instance.status,
      'approved_at': instance.approvedAt?.toIso8601String(),
      'approved_by_id': instance.approvedById,
      'rejection_reason': instance.rejectionReason,
      'created_at': instance.createdAt?.toIso8601String(),
      'user': instance.user?.toJson(),
      'approved_by': instance.approvedBy?.toJson(),
    };

Value? _$JsonConverterFromJson<Json, Value>(
  Object? json,
  Value? Function(Json json) fromJson,
) =>
    json == null ? null : fromJson(json as Json);

Json? _$JsonConverterToJson<Json, Value>(
  Value? value,
  Json? Function(Value value) toJson,
) =>
    value == null ? null : toJson(value);

CashTransaction _$CashTransactionFromJson(Map<String, dynamic> json) =>
    CashTransaction(
      id: json['id'] as String,
      userId: json['user_id'] as String? ?? '',
      userName: json['user_name'] as String?,
      shopId: json['shop_id'] as String?,
      transactionType: json['transaction_type'] as String? ?? 'adjustment',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      previousBalance: (json['previous_balance'] as num?)?.toDouble() ?? 0.0,
      newBalance: (json['new_balance'] as num?)?.toDouble() ?? 0.0,
      relatedEntityType: json['related_entity_type'] as String?,
      relatedEntityId: json['related_entity_id'] as String?,
      description: json['description'] as String? ?? '',
      transactionDate: json['transaction_date'] == null
          ? null
          : DateTime.parse(json['transaction_date'] as String),
      createdAt: json['created_at'] == null
          ? null
          : DateTime.parse(json['created_at'] as String),
      counterpartyId: json['counterparty_id'] as String?,
      counterpartyName: json['counterparty_name'] as String?,
    );

Map<String, dynamic> _$CashTransactionToJson(CashTransaction instance) =>
    <String, dynamic>{
      'id': instance.id,
      'user_id': instance.userId,
      'user_name': instance.userName,
      'shop_id': instance.shopId,
      'transaction_type': instance.transactionType,
      'amount': instance.amount,
      'previous_balance': instance.previousBalance,
      'new_balance': instance.newBalance,
      'related_entity_type': instance.relatedEntityType,
      'related_entity_id': instance.relatedEntityId,
      'description': instance.description,
      'transaction_date': instance.transactionDate?.toIso8601String(),
      'created_at': instance.createdAt?.toIso8601String(),
      'counterparty_id': instance.counterpartyId,
      'counterparty_name': instance.counterpartyName,
    };

CashRequest _$CashRequestFromJson(Map<String, dynamic> json) => CashRequest(
      id: json['id'] as String,
      requesterId: json['requester_id'] as String,
      requestedFromId: json['requested_from_id'] as String,
      shopId: json['shop_id'] as String?,
      amount: (json['amount'] as num).toDouble(),
      reason: json['reason'] as String?,
      requestDate: DateTime.parse(json['request_date'] as String),
      status: json['status'] as String,
      expiresAt: json['expires_at'] == null
          ? null
          : DateTime.parse(json['expires_at'] as String),
      approvedAt: json['approved_at'] == null
          ? null
          : DateTime.parse(json['approved_at'] as String),
      approvedById: json['approved_by_id'] as String?,
      rejectedAt: json['rejected_at'] == null
          ? null
          : DateTime.parse(json['rejected_at'] as String),
      rejectReason: json['reject_reason'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      requester: json['requester'] == null
          ? null
          : UserBasicInfo.fromJson(json['requester'] as Map<String, dynamic>),
      requestedFrom: json['requested_from'] == null
          ? null
          : UserBasicInfo.fromJson(
              json['requested_from'] as Map<String, dynamic>),
      shop: json['shop'] == null
          ? null
          : ShopBasicInfo.fromJson(json['shop'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$CashRequestToJson(CashRequest instance) =>
    <String, dynamic>{
      'id': instance.id,
      'requester_id': instance.requesterId,
      'requested_from_id': instance.requestedFromId,
      'shop_id': instance.shopId,
      'amount': instance.amount,
      'reason': instance.reason,
      'request_date': instance.requestDate.toIso8601String(),
      'status': instance.status,
      'expires_at': instance.expiresAt?.toIso8601String(),
      'approved_at': instance.approvedAt?.toIso8601String(),
      'approved_by_id': instance.approvedById,
      'rejected_at': instance.rejectedAt?.toIso8601String(),
      'reject_reason': instance.rejectReason,
      'created_at': instance.createdAt.toIso8601String(),
      'requester': instance.requester?.toJson(),
      'requested_from': instance.requestedFrom?.toJson(),
      'shop': instance.shop?.toJson(),
    };

TeamCashBalance _$TeamCashBalanceFromJson(Map<String, dynamic> json) =>
    TeamCashBalance(
      userId: json['user_id'] as String? ?? '',
      username: json['user_name'] as String? ?? '',
      fullName: json['full_name'] as String? ?? '',
      role: json['role'] as String? ?? '',
      shopId: json['shop_id'] as String? ?? '',
      shopName: json['shop_name'] as String? ?? '',
      currentBalance: (json['current_balance'] as num?)?.toDouble() ?? 0.0,
      lastUpdatedAt: json['last_updated_at'] == null
          ? null
          : DateTime.parse(json['last_updated_at'] as String),
    );

Map<String, dynamic> _$TeamCashBalanceToJson(TeamCashBalance instance) =>
    <String, dynamic>{
      'user_id': instance.userId,
      'user_name': instance.username,
      'full_name': instance.fullName,
      'role': instance.role,
      'shop_id': instance.shopId,
      'shop_name': instance.shopName,
      'current_balance': instance.currentBalance,
      'last_updated_at': instance.lastUpdatedAt?.toIso8601String(),
    };

UserBasicInfo _$UserBasicInfoFromJson(Map<String, dynamic> json) =>
    UserBasicInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      role: json['role'] as String,
    );

Map<String, dynamic> _$UserBasicInfoToJson(UserBasicInfo instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'email': instance.email,
      'phone': instance.phone,
      'role': instance.role,
    };

ShopBasicInfo _$ShopBasicInfoFromJson(Map<String, dynamic> json) =>
    ShopBasicInfo(
      id: json['id'] as String,
      name: json['name'] as String,
    );

Map<String, dynamic> _$ShopBasicInfoToJson(ShopBasicInfo instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
    };

TenantUser _$TenantUserFromJson(Map<String, dynamic> json) => TenantUser(
      id: json['id'] as String,
      username: json['username'] as String? ?? '',
      fullName: json['full_name'] as String? ?? '',
      firstName: json['first_name'] as String? ?? '',
      lastName: json['last_name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      role: json['role'] as String,
      isActive: json['is_active'] as bool? ?? true,
      shopId: json['shop_id'] as String? ?? '',
      shopName: json['shop_name'] as String? ?? '',
      currentBalance: (json['current_balance'] as num?)?.toDouble() ?? 0.0,
    );

Map<String, dynamic> _$TenantUserToJson(TenantUser instance) =>
    <String, dynamic>{
      'id': instance.id,
      'username': instance.username,
      'full_name': instance.fullName,
      'first_name': instance.firstName,
      'last_name': instance.lastName,
      'email': instance.email,
      'phone': instance.phone,
      'role': instance.role,
      'is_active': instance.isActive,
      'shop_id': instance.shopId,
      'shop_name': instance.shopName,
      'current_balance': instance.currentBalance,
    };

CollectCashRequest _$CollectCashRequestFromJson(Map<String, dynamic> json) =>
    CollectCashRequest(
      fromUserId: json['from_user_id'] as String,
      toUserId: json['to_user_id'] as String,
      shopId: json['shop_id'] as String,
      amount: (json['amount'] as num).toDouble(),
      notes: json['notes'] as String?,
    );

Map<String, dynamic> _$CollectCashRequestToJson(CollectCashRequest instance) =>
    <String, dynamic>{
      'from_user_id': instance.fromUserId,
      'to_user_id': instance.toUserId,
      'shop_id': instance.shopId,
      'amount': instance.amount,
      'notes': instance.notes,
    };

SubmitCashRequest _$SubmitCashRequestFromJson(Map<String, dynamic> json) =>
    SubmitCashRequest(
      shopId: json['shop_id'] as String,
      totalAmount: (json['amount'] as num).toDouble(),
      notes500: (json['notes_500'] as num).toInt(),
      notes200: (json['notes_200'] as num).toInt(),
      notes100: (json['notes_100'] as num).toInt(),
      notes50: (json['notes_50'] as num).toInt(),
      notes20: (json['notes_20'] as num).toInt(),
      notes10: (json['notes_10'] as num).toInt(),
      bankAccountId: json['bank_account_id'] as String?,
      bankSlipNumber: json['bank_slip_number'] as String?,
      depositDate:
          const SimpleDateConverter().fromJson(json['deposit_date'] as String),
      receiptPhotoUrl: json['receipt_photo_url'] as String,
      notes: json['notes'] as String?,
    );

Map<String, dynamic> _$SubmitCashRequestToJson(SubmitCashRequest instance) =>
    <String, dynamic>{
      'shop_id': instance.shopId,
      'amount': instance.totalAmount,
      'notes_500': instance.notes500,
      'notes_200': instance.notes200,
      'notes_100': instance.notes100,
      'notes_50': instance.notes50,
      'notes_20': instance.notes20,
      'notes_10': instance.notes10,
      'bank_account_id': instance.bankAccountId,
      'bank_slip_number': instance.bankSlipNumber,
      'deposit_date': const SimpleDateConverter().toJson(instance.depositDate),
      'receipt_photo_url': instance.receiptPhotoUrl,
      'notes': instance.notes,
    };

ApprovalRequest _$ApprovalRequestFromJson(Map<String, dynamic> json) =>
    ApprovalRequest(
      rejectionReason: json['reason'] as String?,
    );

Map<String, dynamic> _$ApprovalRequestToJson(ApprovalRequest instance) =>
    <String, dynamic>{
      'reason': instance.rejectionReason,
    };
