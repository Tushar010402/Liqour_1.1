/// Tips Management Models
/// Individual tips, pooled tips, distribution methods, and payouts
library;

// =============================================================================
// ENUMS
// =============================================================================

/// Tip pool type
enum TipPoolType {
  individual,
  pooled,
  hybrid;

  String get displayName {
    switch (this) {
      case TipPoolType.individual:
        return 'Individual Tips';
      case TipPoolType.pooled:
        return 'Pooled Tips';
      case TipPoolType.hybrid:
        return 'Hybrid';
    }
  }

  String get apiValue => name;

  static TipPoolType fromString(String value) {
    return TipPoolType.values.firstWhere(
      (e) => e.name.toLowerCase() == value.toLowerCase(),
      orElse: () => TipPoolType.individual,
    );
  }
}

/// Distribution method for pooled tips
enum DistributionMethod {
  equal,
  hoursWorked,
  salesBased,
  pointsBased;

  String get displayName {
    switch (this) {
      case DistributionMethod.equal:
        return 'Equal Split';
      case DistributionMethod.hoursWorked:
        return 'Hours Worked';
      case DistributionMethod.salesBased:
        return 'Sales Based';
      case DistributionMethod.pointsBased:
        return 'Points Based';
    }
  }

  String get description {
    switch (this) {
      case DistributionMethod.equal:
        return 'Tips are split equally among all eligible employees';
      case DistributionMethod.hoursWorked:
        return 'Tips are distributed based on hours worked';
      case DistributionMethod.salesBased:
        return 'Tips are distributed based on sales performance';
      case DistributionMethod.pointsBased:
        return 'Tips are distributed based on assigned points';
    }
  }

  String get apiValue => name;

  static DistributionMethod fromString(String value) {
    return DistributionMethod.values.firstWhere(
      (e) => e.name.toLowerCase() == value.toLowerCase(),
      orElse: () => DistributionMethod.equal,
    );
  }
}

/// Tip payout status
enum PayoutStatus {
  pending,
  approved,
  processing,
  paid,
  cancelled;

  String get displayName {
    switch (this) {
      case PayoutStatus.pending:
        return 'Pending';
      case PayoutStatus.approved:
        return 'Approved';
      case PayoutStatus.processing:
        return 'Processing';
      case PayoutStatus.paid:
        return 'Paid';
      case PayoutStatus.cancelled:
        return 'Cancelled';
    }
  }

  String get apiValue => name;

  static PayoutStatus fromString(String value) {
    return PayoutStatus.values.firstWhere(
      (e) => e.name.toLowerCase() == value.toLowerCase(),
      orElse: () => PayoutStatus.pending,
    );
  }
}

/// Payout frequency
enum PayoutFrequency {
  daily,
  weekly,
  biWeekly,
  monthly;

  String get displayName {
    switch (this) {
      case PayoutFrequency.daily:
        return 'Daily';
      case PayoutFrequency.weekly:
        return 'Weekly';
      case PayoutFrequency.biWeekly:
        return 'Bi-Weekly';
      case PayoutFrequency.monthly:
        return 'Monthly';
    }
  }

  String get apiValue => name;

  static PayoutFrequency fromString(String value) {
    return PayoutFrequency.values.firstWhere(
      (e) => e.name.toLowerCase() == value.toLowerCase(),
      orElse: () => PayoutFrequency.weekly,
    );
  }
}

// =============================================================================
// TIP ENTRY
// =============================================================================

/// Individual tip entry record
class TipEntry {
  final String id;
  final String shopId;
  final String? employeeId;
  final String? employeeName;
  final double amount;
  final DateTime createdAt;
  final String? saleId;
  final String? customerId;
  final String? customerName;
  final String? notes;
  final bool isPooled;
  final String? poolId;
  final String createdBy;

  const TipEntry({
    required this.id,
    required this.shopId,
    this.employeeId,
    this.employeeName,
    required this.amount,
    required this.createdAt,
    this.saleId,
    this.customerId,
    this.customerName,
    this.notes,
    this.isPooled = false,
    this.poolId,
    required this.createdBy,
  });

  factory TipEntry.fromJson(Map<String, dynamic> json) {
    return TipEntry(
      id: json['id'] as String? ?? '',
      shopId: json['shop_id'] as String? ?? '',
      employeeId: json['employee_id'] as String?,
      employeeName: json['employee_name'] as String?,
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      saleId: json['sale_id'] as String?,
      customerId: json['customer_id'] as String?,
      customerName: json['customer_name'] as String?,
      notes: json['notes'] as String?,
      isPooled: json['is_pooled'] as bool? ?? false,
      poolId: json['pool_id'] as String?,
      createdBy: json['created_by'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'shop_id': shopId,
      if (employeeId != null) 'employee_id': employeeId,
      if (employeeName != null) 'employee_name': employeeName,
      'amount': amount,
      'created_at': createdAt.toIso8601String(),
      if (saleId != null) 'sale_id': saleId,
      if (customerId != null) 'customer_id': customerId,
      if (customerName != null) 'customer_name': customerName,
      if (notes != null) 'notes': notes,
      'is_pooled': isPooled,
      if (poolId != null) 'pool_id': poolId,
      'created_by': createdBy,
    };
  }
}

// =============================================================================
// TIP POOL
// =============================================================================

/// Tip pool configuration
class TipPool {
  final String id;
  final String shopId;
  final String name;
  final TipPoolType type;
  final DistributionMethod distributionMethod;
  final double totalAmount;
  final DateTime periodStart;
  final DateTime periodEnd;
  final bool isClosed;
  final DateTime? closedAt;
  final String? closedBy;
  final DateTime createdAt;
  final List<TipPoolEmployee> employees;
  final List<TipEntry> entries;

  const TipPool({
    required this.id,
    required this.shopId,
    required this.name,
    required this.type,
    required this.distributionMethod,
    required this.totalAmount,
    required this.periodStart,
    required this.periodEnd,
    this.isClosed = false,
    this.closedAt,
    this.closedBy,
    required this.createdAt,
    this.employees = const [],
    this.entries = const [],
  });

  factory TipPool.fromJson(Map<String, dynamic> json) {
    return TipPool(
      id: json['id'] as String? ?? '',
      shopId: json['shop_id'] as String? ?? '',
      name: json['name'] as String? ?? 'Tip Pool',
      type: TipPoolType.fromString(json['type'] as String? ?? 'pooled'),
      distributionMethod: DistributionMethod.fromString(
        json['distribution_method'] as String? ?? 'equal',
      ),
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0.0,
      periodStart: json['period_start'] != null
          ? DateTime.parse(json['period_start'] as String)
          : DateTime.now(),
      periodEnd: json['period_end'] != null
          ? DateTime.parse(json['period_end'] as String)
          : DateTime.now(),
      isClosed: json['is_closed'] as bool? ?? false,
      closedAt: json['closed_at'] != null
          ? DateTime.parse(json['closed_at'] as String)
          : null,
      closedBy: json['closed_by'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      employees: (json['employees'] as List<dynamic>?)
              ?.map((e) => TipPoolEmployee.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      entries: (json['entries'] as List<dynamic>?)
              ?.map((e) => TipEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'shop_id': shopId,
      'name': name,
      'type': type.apiValue,
      'distribution_method': distributionMethod.apiValue,
      'total_amount': totalAmount,
      'period_start': periodStart.toIso8601String(),
      'period_end': periodEnd.toIso8601String(),
      'is_closed': isClosed,
      if (closedAt != null) 'closed_at': closedAt!.toIso8601String(),
      if (closedBy != null) 'closed_by': closedBy,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

/// Employee in a tip pool
class TipPoolEmployee {
  final String id;
  final String poolId;
  final String employeeId;
  final String employeeName;
  final double points; // For points-based distribution
  final double hoursWorked; // For hours-based distribution
  final double salesAmount; // For sales-based distribution
  final double shareAmount; // Calculated share
  final bool isEligible;

  const TipPoolEmployee({
    required this.id,
    required this.poolId,
    required this.employeeId,
    required this.employeeName,
    this.points = 1.0,
    this.hoursWorked = 0.0,
    this.salesAmount = 0.0,
    this.shareAmount = 0.0,
    this.isEligible = true,
  });

  factory TipPoolEmployee.fromJson(Map<String, dynamic> json) {
    return TipPoolEmployee(
      id: json['id'] as String? ?? '',
      poolId: json['pool_id'] as String? ?? '',
      employeeId: json['employee_id'] as String? ?? '',
      employeeName: json['employee_name'] as String? ?? '',
      points: (json['points'] as num?)?.toDouble() ?? 1.0,
      hoursWorked: (json['hours_worked'] as num?)?.toDouble() ?? 0.0,
      salesAmount: (json['sales_amount'] as num?)?.toDouble() ?? 0.0,
      shareAmount: (json['share_amount'] as num?)?.toDouble() ?? 0.0,
      isEligible: json['is_eligible'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'pool_id': poolId,
      'employee_id': employeeId,
      'employee_name': employeeName,
      'points': points,
      'hours_worked': hoursWorked,
      'sales_amount': salesAmount,
      'share_amount': shareAmount,
      'is_eligible': isEligible,
    };
  }
}

// =============================================================================
// TIP PAYOUT
// =============================================================================

/// Tip payout batch
class TipPayout {
  final String id;
  final String shopId;
  final String? poolId;
  final PayoutStatus status;
  final double totalAmount;
  final int employeeCount;
  final DateTime periodStart;
  final DateTime periodEnd;
  final DateTime createdAt;
  final String createdBy;
  final String? createdByName;
  final DateTime? approvedAt;
  final String? approvedBy;
  final DateTime? paidAt;
  final String? paidBy;
  final String? notes;
  final List<TipPayoutItem> items;

  const TipPayout({
    required this.id,
    required this.shopId,
    this.poolId,
    required this.status,
    required this.totalAmount,
    required this.employeeCount,
    required this.periodStart,
    required this.periodEnd,
    required this.createdAt,
    required this.createdBy,
    this.createdByName,
    this.approvedAt,
    this.approvedBy,
    this.paidAt,
    this.paidBy,
    this.notes,
    this.items = const [],
  });

  factory TipPayout.fromJson(Map<String, dynamic> json) {
    return TipPayout(
      id: json['id'] as String? ?? '',
      shopId: json['shop_id'] as String? ?? '',
      poolId: json['pool_id'] as String?,
      status: PayoutStatus.fromString(json['status'] as String? ?? 'pending'),
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0.0,
      employeeCount: json['employee_count'] as int? ?? 0,
      periodStart: json['period_start'] != null
          ? DateTime.parse(json['period_start'] as String)
          : DateTime.now(),
      periodEnd: json['period_end'] != null
          ? DateTime.parse(json['period_end'] as String)
          : DateTime.now(),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      createdBy: json['created_by'] as String? ?? '',
      createdByName: json['created_by_name'] as String?,
      approvedAt: json['approved_at'] != null
          ? DateTime.parse(json['approved_at'] as String)
          : null,
      approvedBy: json['approved_by'] as String?,
      paidAt: json['paid_at'] != null
          ? DateTime.parse(json['paid_at'] as String)
          : null,
      paidBy: json['paid_by'] as String?,
      notes: json['notes'] as String?,
      items: (json['items'] as List<dynamic>?)
              ?.map((e) => TipPayoutItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'shop_id': shopId,
      if (poolId != null) 'pool_id': poolId,
      'status': status.apiValue,
      'total_amount': totalAmount,
      'employee_count': employeeCount,
      'period_start': periodStart.toIso8601String(),
      'period_end': periodEnd.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'created_by': createdBy,
      if (createdByName != null) 'created_by_name': createdByName,
      if (approvedAt != null) 'approved_at': approvedAt!.toIso8601String(),
      if (approvedBy != null) 'approved_by': approvedBy,
      if (paidAt != null) 'paid_at': paidAt!.toIso8601String(),
      if (paidBy != null) 'paid_by': paidBy,
      if (notes != null) 'notes': notes,
    };
  }
}

/// Individual payout item for an employee
class TipPayoutItem {
  final String id;
  final String payoutId;
  final String employeeId;
  final String employeeName;
  final double amount;
  final double hoursWorked;
  final double salesAmount;
  final double points;
  final bool isPaid;
  final DateTime? paidAt;
  final String? paymentMethod;

  const TipPayoutItem({
    required this.id,
    required this.payoutId,
    required this.employeeId,
    required this.employeeName,
    required this.amount,
    this.hoursWorked = 0.0,
    this.salesAmount = 0.0,
    this.points = 1.0,
    this.isPaid = false,
    this.paidAt,
    this.paymentMethod,
  });

  factory TipPayoutItem.fromJson(Map<String, dynamic> json) {
    return TipPayoutItem(
      id: json['id'] as String? ?? '',
      payoutId: json['payout_id'] as String? ?? '',
      employeeId: json['employee_id'] as String? ?? '',
      employeeName: json['employee_name'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      hoursWorked: (json['hours_worked'] as num?)?.toDouble() ?? 0.0,
      salesAmount: (json['sales_amount'] as num?)?.toDouble() ?? 0.0,
      points: (json['points'] as num?)?.toDouble() ?? 1.0,
      isPaid: json['is_paid'] as bool? ?? false,
      paidAt: json['paid_at'] != null
          ? DateTime.parse(json['paid_at'] as String)
          : null,
      paymentMethod: json['payment_method'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'payout_id': payoutId,
      'employee_id': employeeId,
      'employee_name': employeeName,
      'amount': amount,
      'hours_worked': hoursWorked,
      'sales_amount': salesAmount,
      'points': points,
      'is_paid': isPaid,
      if (paidAt != null) 'paid_at': paidAt!.toIso8601String(),
      if (paymentMethod != null) 'payment_method': paymentMethod,
    };
  }
}

// =============================================================================
// TIP SUMMARY
// =============================================================================

/// Summary of tips for a period
class TipsSummary {
  final double totalTips;
  final double pooledTips;
  final double individualTips;
  final int totalEntries;
  final double avgTipAmount;
  final double pendingPayouts;
  final double paidPayouts;
  final DateTime periodStart;
  final DateTime periodEnd;
  final List<EmployeeTipSummary> byEmployee;

  const TipsSummary({
    required this.totalTips,
    required this.pooledTips,
    required this.individualTips,
    required this.totalEntries,
    required this.avgTipAmount,
    required this.pendingPayouts,
    required this.paidPayouts,
    required this.periodStart,
    required this.periodEnd,
    this.byEmployee = const [],
  });

  factory TipsSummary.fromJson(Map<String, dynamic> json) {
    return TipsSummary(
      totalTips: (json['total_tips'] as num?)?.toDouble() ?? 0.0,
      pooledTips: (json['pooled_tips'] as num?)?.toDouble() ?? 0.0,
      individualTips: (json['individual_tips'] as num?)?.toDouble() ?? 0.0,
      totalEntries: json['total_entries'] as int? ?? 0,
      avgTipAmount: (json['avg_tip_amount'] as num?)?.toDouble() ?? 0.0,
      pendingPayouts: (json['pending_payouts'] as num?)?.toDouble() ?? 0.0,
      paidPayouts: (json['paid_payouts'] as num?)?.toDouble() ?? 0.0,
      periodStart: json['period_start'] != null
          ? DateTime.parse(json['period_start'] as String)
          : DateTime.now(),
      periodEnd: json['period_end'] != null
          ? DateTime.parse(json['period_end'] as String)
          : DateTime.now(),
      byEmployee: (json['by_employee'] as List<dynamic>?)
              ?.map((e) => EmployeeTipSummary.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

/// Tip summary per employee
class EmployeeTipSummary {
  final String employeeId;
  final String employeeName;
  final double totalEarned;
  final double individualTips;
  final double pooledShare;
  final int tipCount;
  final double pendingPayout;
  final double paidPayout;

  const EmployeeTipSummary({
    required this.employeeId,
    required this.employeeName,
    required this.totalEarned,
    required this.individualTips,
    required this.pooledShare,
    required this.tipCount,
    required this.pendingPayout,
    required this.paidPayout,
  });

  factory EmployeeTipSummary.fromJson(Map<String, dynamic> json) {
    return EmployeeTipSummary(
      employeeId: json['employee_id'] as String? ?? '',
      employeeName: json['employee_name'] as String? ?? '',
      totalEarned: (json['total_earned'] as num?)?.toDouble() ?? 0.0,
      individualTips: (json['individual_tips'] as num?)?.toDouble() ?? 0.0,
      pooledShare: (json['pooled_share'] as num?)?.toDouble() ?? 0.0,
      tipCount: json['tip_count'] as int? ?? 0,
      pendingPayout: (json['pending_payout'] as num?)?.toDouble() ?? 0.0,
      paidPayout: (json['paid_payout'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

// =============================================================================
// TIP SETTINGS
// =============================================================================

/// Shop tip settings
class TipSettings {
  final String shopId;
  final TipPoolType defaultPoolType;
  final DistributionMethod defaultDistributionMethod;
  final PayoutFrequency payoutFrequency;
  final bool autoCreatePools;
  final bool requireApproval;
  final double minimumPayout;
  final List<String> eligibleRoles;

  const TipSettings({
    required this.shopId,
    this.defaultPoolType = TipPoolType.pooled,
    this.defaultDistributionMethod = DistributionMethod.equal,
    this.payoutFrequency = PayoutFrequency.weekly,
    this.autoCreatePools = true,
    this.requireApproval = true,
    this.minimumPayout = 0.0,
    this.eligibleRoles = const ['salesman', 'manager'],
  });

  factory TipSettings.fromJson(Map<String, dynamic> json) {
    return TipSettings(
      shopId: json['shop_id'] as String? ?? '',
      defaultPoolType: TipPoolType.fromString(
        json['default_pool_type'] as String? ?? 'pooled',
      ),
      defaultDistributionMethod: DistributionMethod.fromString(
        json['default_distribution_method'] as String? ?? 'equal',
      ),
      payoutFrequency: PayoutFrequency.fromString(
        json['payout_frequency'] as String? ?? 'weekly',
      ),
      autoCreatePools: json['auto_create_pools'] as bool? ?? true,
      requireApproval: json['require_approval'] as bool? ?? true,
      minimumPayout: (json['minimum_payout'] as num?)?.toDouble() ?? 0.0,
      eligibleRoles: (json['eligible_roles'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          ['salesman', 'manager'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'shop_id': shopId,
      'default_pool_type': defaultPoolType.apiValue,
      'default_distribution_method': defaultDistributionMethod.apiValue,
      'payout_frequency': payoutFrequency.apiValue,
      'auto_create_pools': autoCreatePools,
      'require_approval': requireApproval,
      'minimum_payout': minimumPayout,
      'eligible_roles': eligibleRoles,
    };
  }
}

// =============================================================================
// REQUEST MODELS
// =============================================================================

/// Create tip entry request
class CreateTipRequest {
  final String shopId;
  final String? employeeId;
  final double amount;
  final String? saleId;
  final String? notes;
  final bool addToPool;

  const CreateTipRequest({
    required this.shopId,
    this.employeeId,
    required this.amount,
    this.saleId,
    this.notes,
    this.addToPool = true,
  });

  Map<String, dynamic> toJson() {
    return {
      'shop_id': shopId,
      if (employeeId != null) 'employee_id': employeeId,
      'amount': amount,
      if (saleId != null) 'sale_id': saleId,
      if (notes != null) 'notes': notes,
      'add_to_pool': addToPool,
    };
  }
}

/// Create tip pool request
class CreatePoolRequest {
  final String shopId;
  final String name;
  final DistributionMethod distributionMethod;
  final DateTime periodStart;
  final DateTime periodEnd;
  final List<String> employeeIds;

  const CreatePoolRequest({
    required this.shopId,
    required this.name,
    required this.distributionMethod,
    required this.periodStart,
    required this.periodEnd,
    required this.employeeIds,
  });

  Map<String, dynamic> toJson() {
    return {
      'shop_id': shopId,
      'name': name,
      'distribution_method': distributionMethod.apiValue,
      'period_start': periodStart.toIso8601String(),
      'period_end': periodEnd.toIso8601String(),
      'employee_ids': employeeIds,
    };
  }
}

/// Create payout request
class CreatePayoutRequest {
  final String shopId;
  final String? poolId;
  final DateTime periodStart;
  final DateTime periodEnd;
  final String? notes;

  const CreatePayoutRequest({
    required this.shopId,
    this.poolId,
    required this.periodStart,
    required this.periodEnd,
    this.notes,
  });

  Map<String, dynamic> toJson() {
    return {
      'shop_id': shopId,
      if (poolId != null) 'pool_id': poolId,
      'period_start': periodStart.toIso8601String(),
      'period_end': periodEnd.toIso8601String(),
      if (notes != null) 'notes': notes,
    };
  }
}

/// Tips query parameters
class TipsQuery {
  final String? shopId;
  final String? employeeId;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool? isPooled;
  final int limit;
  final int offset;

  const TipsQuery({
    this.shopId,
    this.employeeId,
    this.startDate,
    this.endDate,
    this.isPooled,
    this.limit = 50,
    this.offset = 0,
  });

  Map<String, String> toQueryParams() {
    return {
      if (shopId != null) 'shop_id': shopId!,
      if (employeeId != null) 'employee_id': employeeId!,
      if (startDate != null) 'start_date': startDate!.toIso8601String(),
      if (endDate != null) 'end_date': endDate!.toIso8601String(),
      if (isPooled != null) 'is_pooled': isPooled.toString(),
      'limit': limit.toString(),
      'offset': offset.toString(),
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TipsQuery &&
          runtimeType == other.runtimeType &&
          shopId == other.shopId &&
          employeeId == other.employeeId &&
          startDate == other.startDate &&
          endDate == other.endDate &&
          isPooled == other.isPooled &&
          limit == other.limit &&
          offset == other.offset;

  @override
  int get hashCode =>
      shopId.hashCode ^
      employeeId.hashCode ^
      startDate.hashCode ^
      endDate.hashCode ^
      isPooled.hashCode ^
      limit.hashCode ^
      offset.hashCode;
}
