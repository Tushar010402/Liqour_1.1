import 'package:json_annotation/json_annotation.dart';

part 'cash_models.g.dart';

// ══════════════════════════════════════════════════════════════════════════════
// DateTime Converter for RFC3339 format (required by Go backend)
// ══════════════════════════════════════════════════════════════════════════════

class Rfc3339DateTimeConverter implements JsonConverter<DateTime, String> {
  const Rfc3339DateTimeConverter();

  @override
  DateTime fromJson(String json) {
    return DateTime.parse(json);
  }

  @override
  String toJson(DateTime date) {
    // Convert to UTC and format as RFC3339 with Z suffix
    return date.toUtc().toIso8601String();
  }
}

/// Simple date converter for YYYY-MM-DD format (required by bank deposit API)
class SimpleDateConverter implements JsonConverter<DateTime, String> {
  const SimpleDateConverter();

  @override
  DateTime fromJson(String json) {
    return DateTime.parse(json);
  }

  @override
  String toJson(DateTime date) {
    // Format as simple YYYY-MM-DD (no time component)
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Cash Models - Hierarchical Cash Management
// ══════════════════════════════════════════════════════════════════════════════

/// CashHolding - Real-time cash balance for a user at a shop
/// All fields have sensible defaults to handle null values from backend
@JsonSerializable()
class CashHolding {
  final String id;
  @JsonKey(name: 'user_id', defaultValue: '')
  final String userId;
  @JsonKey(name: 'shop_id')
  final String? shopId; // Nullable - cash is user-specific, shop is optional metadata
  @JsonKey(name: 'current_balance', defaultValue: 0.0)
  final double currentBalance;
  @JsonKey(name: 'last_updated_at')
  final DateTime? lastUpdatedAt;
  @JsonKey(name: 'created_at')
  final DateTime? createdAt;

  // Optional: populated when fetching with user details
  final UserBasicInfo? user;
  final ShopBasicInfo? shop;

  CashHolding({
    required this.id,
    this.userId = '',
    this.shopId, // Optional - cash is user-specific, shop is metadata
    this.currentBalance = 0.0,
    this.lastUpdatedAt,
    this.createdAt,
    this.user,
    this.shop,
  });

  factory CashHolding.fromJson(Map<String, dynamic> json) =>
      _$CashHoldingFromJson(json);
  Map<String, dynamic> toJson() => _$CashHoldingToJson(this);
}

/// CashCollection - Cash collection from subordinate to superior
/// All fields have sensible defaults to handle null values from backend
@JsonSerializable()
class CashCollection {
  final String id;
  @JsonKey(name: 'from_user_id', defaultValue: '')
  final String fromUserId;
  @JsonKey(name: 'to_user_id', defaultValue: '')
  final String toUserId;
  @JsonKey(name: 'shop_id', defaultValue: '')
  final String shopId;
  @JsonKey(defaultValue: 0.0)
  final double amount;
  @JsonKey(name: 'collection_date')
  final DateTime? collectionDate;
  final String? notes;
  @JsonKey(defaultValue: 'pending')
  final String status; // 'pending', 'approved', 'rejected', 'expired'
  @JsonKey(name: 'expires_at')
  final DateTime? expiresAt; // 10-minute deadline for approval
  @JsonKey(name: 'approved_at')
  final DateTime? approvedAt;
  @JsonKey(name: 'approved_by_id')
  final String? approvedById;
  @JsonKey(name: 'rejected_at')
  final DateTime? rejectedAt;
  @JsonKey(name: 'reject_reason')
  final String? rejectReason;
  @JsonKey(name: 'created_at')
  final DateTime? createdAt;

  // Optional: populated when fetching with user details
  @JsonKey(name: 'from_user')
  final UserBasicInfo? fromUser;
  @JsonKey(name: 'to_user')
  final UserBasicInfo? toUser;

  CashCollection({
    required this.id,
    this.fromUserId = '',
    this.toUserId = '',
    this.shopId = '',
    this.amount = 0.0,
    this.collectionDate,
    this.notes,
    this.status = 'pending',
    this.expiresAt,
    this.approvedAt,
    this.approvedById,
    this.rejectedAt,
    this.rejectReason,
    this.createdAt,
    this.fromUser,
    this.toUser,
  });

  factory CashCollection.fromJson(Map<String, dynamic> json) =>
      _$CashCollectionFromJson(json);
  Map<String, dynamic> toJson() => _$CashCollectionToJson(this);

  // Status checks
  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
  bool get isExpired => status == 'expired';

  // Expiration checks
  bool get hasExpired {
    if (expiresAt == null) return false;
    return DateTime.now().toUtc().isAfter(expiresAt!);
  }

  Duration? get timeRemaining {
    if (expiresAt == null || hasExpired) return null;
    return expiresAt!.difference(DateTime.now().toUtc());
  }

  String? get timeRemainingFormatted {
    final remaining = timeRemaining;
    if (remaining == null) return null;
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

/// CashSubmission - Bank deposit with denomination breakdown
/// All fields have sensible defaults to handle null values from backend
@JsonSerializable()
class CashSubmission {
  @JsonKey(defaultValue: '')
  final String id;

  // Backend sends 'created_by_id' for the user who created the submission
  @JsonKey(name: 'created_by_id', defaultValue: '')
  final String userId;
  @JsonKey(name: 'created_by_name', defaultValue: '')
  final String userName;

  @JsonKey(name: 'shop_id', defaultValue: '')
  final String shopId;
  @JsonKey(name: 'shop_name', defaultValue: '')
  final String shopName;

  // Backend sends 'amount' not 'total_amount'
  @JsonKey(name: 'amount', defaultValue: 0.0)
  final double totalAmount;

  // Denomination breakdown (may not be present in all responses)
  @JsonKey(name: 'notes_500', defaultValue: 0)
  final int notes500;
  @JsonKey(name: 'notes_200', defaultValue: 0)
  final int notes200;
  @JsonKey(name: 'notes_100', defaultValue: 0)
  final int notes100;
  @JsonKey(name: 'notes_50', defaultValue: 0)
  final int notes50;
  @JsonKey(name: 'notes_20', defaultValue: 0)
  final int notes20;
  @JsonKey(name: 'notes_10', defaultValue: 0)
  final int notes10;

  // Bank details
  @JsonKey(name: 'bank_account_id')
  final String? bankAccountId;
  @JsonKey(name: 'bank_account_name', defaultValue: '')
  final String bankAccountName;
  // Backend sends 'slip_number' not 'bank_slip_number'
  @JsonKey(name: 'slip_number')
  final String? bankSlipNumber;
  @JsonKey(name: 'deposit_date')
  @Rfc3339DateTimeConverter()
  final DateTime? depositDate;
  // Receipt photo URL for evidence (bank deposit slip image)
  @JsonKey(name: 'receipt_photo_url', defaultValue: '')
  final String receiptPhotoUrl;
  final String? notes;

  // Approval workflow
  @JsonKey(defaultValue: 'pending')
  final String status; // 'pending', 'approved', 'rejected'
  @JsonKey(name: 'approved_at')
  final DateTime? approvedAt;
  @JsonKey(name: 'approved_by_id')
  final String? approvedById;
  @JsonKey(name: 'rejection_reason')
  final String? rejectionReason;
  @JsonKey(name: 'created_at')
  final DateTime? createdAt;

  // Optional: populated when fetching with user details
  final UserBasicInfo? user;
  @JsonKey(name: 'approved_by')
  final UserBasicInfo? approvedBy;

  CashSubmission({
    this.id = '',
    this.userId = '',
    this.userName = '',
    this.shopId = '',
    this.shopName = '',
    this.totalAmount = 0.0,
    this.notes500 = 0,
    this.notes200 = 0,
    this.notes100 = 0,
    this.notes50 = 0,
    this.notes20 = 0,
    this.notes10 = 0,
    this.bankAccountId,
    this.bankAccountName = '',
    this.bankSlipNumber,
    this.depositDate,
    this.receiptPhotoUrl = '',
    this.notes,
    this.status = 'pending',
    this.approvedAt,
    this.approvedById,
    this.rejectionReason,
    this.createdAt,
    this.user,
    this.approvedBy,
  });

  factory CashSubmission.fromJson(Map<String, dynamic> json) =>
      _$CashSubmissionFromJson(json);
  Map<String, dynamic> toJson() => _$CashSubmissionToJson(this);

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';

  /// Calculate total from denominations (for validation)
  double get calculatedTotal =>
      (notes500 * 500) +
      (notes200 * 200) +
      (notes100 * 100) +
      (notes50 * 50) +
      (notes20 * 20) +
      (notes10 * 10).toDouble();

  /// Check if denomination breakdown matches total amount
  bool get isValid => (calculatedTotal - totalAmount).abs() < 0.01;
}

/// CashTransaction - Audit trail entry with UPI-style display support
/// All fields have sensible defaults to handle null values from backend
@JsonSerializable()
class CashTransaction {
  final String id;
  @JsonKey(name: 'user_id', defaultValue: '')
  final String userId;
  @JsonKey(name: 'user_name')
  final String? userName; // Current user's name
  @JsonKey(name: 'shop_id')
  final String? shopId; // Nullable - transactions are user-specific, shop is optional metadata
  @JsonKey(name: 'transaction_type', defaultValue: 'adjustment')
  final String transactionType; // 'sale', 'collection_received', 'collection_given', 'submission', 'adjustment'
  @JsonKey(defaultValue: 0.0)
  final double amount;
  @JsonKey(name: 'previous_balance', defaultValue: 0.0)
  final double previousBalance;
  @JsonKey(name: 'new_balance', defaultValue: 0.0)
  final double newBalance;
  @JsonKey(name: 'related_entity_type')
  final String? relatedEntityType;
  @JsonKey(name: 'related_entity_id')
  final String? relatedEntityId;
  @JsonKey(defaultValue: '')
  final String description;
  @JsonKey(name: 'transaction_date')
  final DateTime? transactionDate;
  @JsonKey(name: 'created_at')
  final DateTime? createdAt;

  // Counterparty info for UPI-style display
  @JsonKey(name: 'counterparty_id')
  final String? counterpartyId;
  @JsonKey(name: 'counterparty_name')
  final String? counterpartyName;

  CashTransaction({
    required this.id,
    this.userId = '',
    this.userName,
    this.shopId, // Optional - transactions are user-specific, shop is metadata
    this.transactionType = 'adjustment',
    this.amount = 0.0,
    this.previousBalance = 0.0,
    this.newBalance = 0.0,
    this.relatedEntityType,
    this.relatedEntityId,
    this.description = '',
    this.transactionDate,
    this.createdAt,
    this.counterpartyId,
    this.counterpartyName,
  });

  factory CashTransaction.fromJson(Map<String, dynamic> json) =>
      _$CashTransactionFromJson(json);
  Map<String, dynamic> toJson() => _$CashTransactionToJson(this);

  bool get isIncoming => amount > 0;
  bool get isOutgoing => amount < 0;

  /// Display name for UPI-style transaction list
  /// Shows counterparty name if available, otherwise falls back to description
  String get displayName {
    if (counterpartyName != null && counterpartyName!.isNotEmpty) {
      return counterpartyName!;
    }
    return description;
  }

  /// Get initials for avatar (first letter of display name)
  String get avatarInitial {
    final name = displayName;
    if (name.isEmpty) return '?';
    return name[0].toUpperCase();
  }
}

/// CashRequest - Cash request from one user to another with approval workflow
@JsonSerializable()
class CashRequest {
  final String id;
  @JsonKey(name: 'requester_id')
  final String requesterId;
  @JsonKey(name: 'requested_from_id')
  final String requestedFromId;
  @JsonKey(name: 'shop_id')
  final String? shopId; // Shop is optional - cash is user-specific
  final double amount;
  final String? reason;
  @JsonKey(name: 'request_date')
  final DateTime requestDate;
  final String status; // 'pending', 'approved', 'rejected', 'expired'
  @JsonKey(name: 'expires_at')
  final DateTime? expiresAt; // 10-minute deadline for approval
  @JsonKey(name: 'approved_at')
  final DateTime? approvedAt;
  @JsonKey(name: 'approved_by_id')
  final String? approvedById;
  @JsonKey(name: 'rejected_at')
  final DateTime? rejectedAt;
  @JsonKey(name: 'reject_reason')
  final String? rejectReason;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;

  // Optional: populated when fetching with user details
  final UserBasicInfo? requester;
  @JsonKey(name: 'requested_from')
  final UserBasicInfo? requestedFrom;
  final ShopBasicInfo? shop;

  CashRequest({
    required this.id,
    required this.requesterId,
    required this.requestedFromId,
    this.shopId, // Shop is optional - cash is user-specific
    required this.amount,
    this.reason,
    required this.requestDate,
    required this.status,
    this.expiresAt,
    this.approvedAt,
    this.approvedById,
    this.rejectedAt,
    this.rejectReason,
    required this.createdAt,
    this.requester,
    this.requestedFrom,
    this.shop,
  });

  /// Custom fromJson to handle backend response format
  /// Backend returns different field names and empty strings for null DateTime fields
  /// Backend format:
  /// - executive_id / requested_from_user_id -> requestedFromId
  /// - collected_at / request_date -> requestDate
  /// - deadline_at / expires_at -> expiresAt
  /// - approved_at: "" (empty string for null)
  /// - approved_by -> approvedById
  factory CashRequest.fromJson(Map<String, dynamic> json) {
    // Helper to parse DateTime, treating empty strings as null
    DateTime? parseDateTime(dynamic value) {
      if (value == null || value == '' || (value is String && value.isEmpty)) {
        return null;
      }
      return DateTime.parse(value as String);
    }

    // Helper to parse nullable string, treating empty strings as null
    String? parseNullableString(dynamic value) {
      if (value == null || value == '' || (value is String && value.isEmpty)) {
        return null;
      }
      return value as String;
    }

    // Helper to get string from multiple possible keys
    String getString(List<String> keys) {
      for (final key in keys) {
        final value = json[key];
        if (value != null && value is String && value.isNotEmpty) {
          return value;
        }
      }
      return '';
    }

    // Helper to get DateTime from multiple possible keys
    DateTime getDateTime(List<String> keys) {
      for (final key in keys) {
        final value = json[key];
        if (value != null && value is String && value.isNotEmpty) {
          return DateTime.parse(value);
        }
      }
      return DateTime.now();
    }

    // Helper to get nullable DateTime from multiple possible keys
    DateTime? getNullableDateTime(List<String> keys) {
      for (final key in keys) {
        final value = parseDateTime(json[key]);
        if (value != null) return value;
      }
      return null;
    }

    return CashRequest(
      id: json['id'] as String,
      // Backend sends: requester_id
      requesterId: json['requester_id'] as String? ?? '',
      // Backend sends: executive_id OR requested_from_user_id
      requestedFromId: getString(['requested_from_id', 'executive_id', 'requested_from_user_id']),
      shopId: parseNullableString(json['shop_id']),
      amount: (json['amount'] as num).toDouble(),
      // Backend sends: notes OR reason
      reason: parseNullableString(json['reason'] ?? json['notes']),
      // Backend sends: collected_at OR request_date
      requestDate: getDateTime(['request_date', 'collected_at']),
      status: json['status'] as String? ?? 'pending',
      // Backend sends: deadline_at OR expires_at
      expiresAt: getNullableDateTime(['expires_at', 'deadline_at']),
      approvedAt: parseDateTime(json['approved_at']),
      // Backend sends: approved_by OR approved_by_id
      approvedById: parseNullableString(json['approved_by_id'] ?? json['approved_by']),
      rejectedAt: parseDateTime(json['rejected_at']),
      rejectReason: parseNullableString(json['reject_reason']),
      createdAt: getDateTime(['created_at']),
      // Build requester info from flat fields if nested object not present
      requester: json['requester'] != null
          ? UserBasicInfo.fromJson(json['requester'] as Map<String, dynamic>)
          : (json['requester_name'] != null && (json['requester_name'] as String).isNotEmpty
              ? UserBasicInfo(
                  id: json['requester_id'] as String? ?? '',
                  name: json['requester_name'] as String,
                  role: '',
                )
              : null),
      // Build requestedFrom info from flat fields if nested object not present
      requestedFrom: json['requested_from'] != null
          ? UserBasicInfo.fromJson(json['requested_from'] as Map<String, dynamic>)
          : (getString(['requested_from_name', 'executive_name']).isNotEmpty
              ? UserBasicInfo(
                  id: getString(['requested_from_id', 'executive_id', 'requested_from_user_id']),
                  name: getString(['requested_from_name', 'executive_name']),
                  role: '',
                )
              : null),
      // Build shop info from flat fields if nested object not present
      shop: json['shop'] != null
          ? ShopBasicInfo.fromJson(json['shop'] as Map<String, dynamic>)
          : (parseNullableString(json['shop_id']) != null && parseNullableString(json['shop_name']) != null
              ? ShopBasicInfo(
                  id: json['shop_id'] as String,
                  name: json['shop_name'] as String,
                )
              : null),
    );
  }

  Map<String, dynamic> toJson() => _$CashRequestToJson(this);

  // Status checks
  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
  bool get isExpired => status == 'expired';

  // Expiration checks
  bool get hasExpired {
    if (expiresAt == null) return false;
    return DateTime.now().toUtc().isAfter(expiresAt!);
  }

  Duration? get timeRemaining {
    if (expiresAt == null || hasExpired) return null;
    return expiresAt!.difference(DateTime.now().toUtc());
  }

  String? get timeRemainingFormatted {
    final remaining = timeRemaining;
    if (remaining == null) return null;
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

/// TeamCashBalance - Aggregated cash balance per user (user-specific, not shop-specific)
@JsonSerializable()
class TeamCashBalance {
  @JsonKey(name: 'user_id', defaultValue: '')
  final String userId;

  // Backend sends 'user_name' (snake_case)
  @JsonKey(name: 'user_name', defaultValue: '')
  final String username;

  // Backend may send null for full_name
  @JsonKey(name: 'full_name', defaultValue: '')
  final String fullName;

  // Backend may send null for role
  @JsonKey(defaultValue: '')
  final String role;

  // Handle both null and empty string from backend
  @JsonKey(name: 'shop_id', defaultValue: '')
  final String shopId;

  @JsonKey(name: 'shop_name', defaultValue: '')
  final String shopName;

  @JsonKey(name: 'current_balance', defaultValue: 0.0)
  final double currentBalance;

  @JsonKey(name: 'last_updated_at')
  final DateTime? lastUpdatedAt;

  TeamCashBalance({
    this.userId = '',
    this.username = '',
    this.fullName = '',
    this.role = '',
    this.shopId = '',
    this.shopName = '',
    this.currentBalance = 0.0,
    this.lastUpdatedAt,
  });

  factory TeamCashBalance.fromJson(Map<String, dynamic> json) =>
      _$TeamCashBalanceFromJson(json);
  Map<String, dynamic> toJson() => _$TeamCashBalanceToJson(this);

  // Helper getters for display
  String get displayName => fullName.isNotEmpty ? fullName : username;
  bool get hasShop => shopId.isNotEmpty;
}

// ══════════════════════════════════════════════════════════════════════════════
// Supporting Models
// ══════════════════════════════════════════════════════════════════════════════

/// Basic user info for related entities
@JsonSerializable()
class UserBasicInfo {
  final String id;
  final String name;
  final String? email;
  final String? phone;
  final String role;

  UserBasicInfo({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    required this.role,
  });

  /// Custom fromJson to handle backend's first_name + last_name format
  factory UserBasicInfo.fromJson(Map<String, dynamic> json) {
    // Backend sends first_name and last_name separately
    final firstName = json['first_name'] as String? ?? '';
    final lastName = json['last_name'] as String? ?? '';
    final combinedName = '$firstName $lastName'.trim();

    // Fallback to 'name' field if first/last names not present
    final name = combinedName.isNotEmpty
        ? combinedName
        : (json['name'] as String? ?? 'Unknown User');

    return UserBasicInfo(
      id: json['id'] as String,
      name: name,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      role: json['role'] as String,
    );
  }

  Map<String, dynamic> toJson() => _$UserBasicInfoToJson(this);
}

/// Basic shop info
@JsonSerializable()
class ShopBasicInfo {
  final String id;
  final String name;

  ShopBasicInfo({
    required this.id,
    required this.name,
  });

  factory ShopBasicInfo.fromJson(Map<String, dynamic> json) =>
      _$ShopBasicInfoFromJson(json);
  Map<String, dynamic> toJson() => _$ShopBasicInfoToJson(this);
}

/// Tenant User for cash request selection
/// Backend sends: id, username, full_name, first_name, last_name, email, phone, role, is_active, shop_id, shop_name, current_balance
@JsonSerializable()
class TenantUser {
  final String id;

  @JsonKey(defaultValue: '')
  final String username;

  @JsonKey(name: 'full_name', defaultValue: '')
  final String fullName;

  @JsonKey(name: 'first_name', defaultValue: '')
  final String firstName;

  @JsonKey(name: 'last_name', defaultValue: '')
  final String lastName;

  @JsonKey(defaultValue: '')
  final String email;

  @JsonKey(defaultValue: '')
  final String phone;

  final String role;

  @JsonKey(name: 'is_active', defaultValue: true)
  final bool isActive;

  @JsonKey(name: 'shop_id', defaultValue: '')
  final String shopId;

  @JsonKey(name: 'shop_name', defaultValue: '')
  final String shopName;

  /// User's current cash balance (added by backend)
  @JsonKey(name: 'current_balance', defaultValue: 0.0)
  final double currentBalance;

  TenantUser({
    required this.id,
    this.username = '',
    this.fullName = '',
    this.firstName = '',
    this.lastName = '',
    this.email = '',
    this.phone = '',
    required this.role,
    this.isActive = true,
    this.shopId = '',
    this.shopName = '',
    this.currentBalance = 0.0,
  });

  factory TenantUser.fromJson(Map<String, dynamic> json) =>
      _$TenantUserFromJson(json);
  Map<String, dynamic> toJson() => _$TenantUserToJson(this);

  // Helper getters
  String get displayName => fullName.isNotEmpty ? fullName : (username.isNotEmpty ? username : 'Unknown User');
  String get userId => id; // Backward compatibility
  String get userName => displayName; // Returns display name
}

// ══════════════════════════════════════════════════════════════════════════════
// Request DTOs
// ══════════════════════════════════════════════════════════════════════════════

/// Request to collect cash from a subordinate
@JsonSerializable()
class CollectCashRequest {
  @JsonKey(name: 'from_user_id')
  final String fromUserId;
  @JsonKey(name: 'to_user_id')
  final String toUserId;
  @JsonKey(name: 'shop_id')
  final String shopId;
  final double amount;
  final String? notes;

  CollectCashRequest({
    required this.fromUserId,
    required this.toUserId,
    required this.shopId,
    required this.amount,
    this.notes,
  });

  factory CollectCashRequest.fromJson(Map<String, dynamic> json) =>
      _$CollectCashRequestFromJson(json);
  Map<String, dynamic> toJson() => _$CollectCashRequestToJson(this);
}

/// Request to submit cash to bank
@JsonSerializable()
class SubmitCashRequest {
  @JsonKey(name: 'shop_id')
  final String shopId;
  @JsonKey(name: 'amount')  // Backend expects 'amount', not 'total_amount'
  final double totalAmount;
  @JsonKey(name: 'notes_500')
  final int notes500;
  @JsonKey(name: 'notes_200')
  final int notes200;
  @JsonKey(name: 'notes_100')
  final int notes100;
  @JsonKey(name: 'notes_50')
  final int notes50;
  @JsonKey(name: 'notes_20')
  final int notes20;
  @JsonKey(name: 'notes_10')
  final int notes10;
  @JsonKey(name: 'bank_account_id')
  final String? bankAccountId;
  @JsonKey(name: 'bank_slip_number')
  final String? bankSlipNumber;
  @JsonKey(name: 'deposit_date')
  @SimpleDateConverter()  // Backend expects YYYY-MM-DD format
  final DateTime depositDate;
  @JsonKey(name: 'receipt_photo_url')
  final String receiptPhotoUrl;
  final String? notes;

  SubmitCashRequest({
    required this.shopId,
    required this.totalAmount,
    required this.notes500,
    required this.notes200,
    required this.notes100,
    required this.notes50,
    required this.notes20,
    required this.notes10,
    this.bankAccountId,
    this.bankSlipNumber,
    required this.depositDate,
    required this.receiptPhotoUrl,
    this.notes,
  });

  factory SubmitCashRequest.fromJson(Map<String, dynamic> json) =>
      _$SubmitCashRequestFromJson(json);
  Map<String, dynamic> toJson() => _$SubmitCashRequestToJson(this);

  /// Calculate total from denominations
  double get calculatedTotal =>
      (notes500 * 500) +
      (notes200 * 200) +
      (notes100 * 100) +
      (notes50 * 50) +
      (notes20 * 20) +
      (notes10 * 10).toDouble();

  /// Validate that denomination breakdown matches total
  bool get isValid => (calculatedTotal - totalAmount).abs() < 0.01;
}

/// Request to approve/reject a submission
@JsonSerializable()
class ApprovalRequest {
  @JsonKey(name: 'reason')  // Backend expects 'reason', not 'rejection_reason'
  final String? rejectionReason;

  ApprovalRequest({this.rejectionReason});

  factory ApprovalRequest.fromJson(Map<String, dynamic> json) =>
      _$ApprovalRequestFromJson(json);
  Map<String, dynamic> toJson() => _$ApprovalRequestToJson(this);
}
