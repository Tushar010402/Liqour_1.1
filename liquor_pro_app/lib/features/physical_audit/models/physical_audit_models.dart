/// Physical Audit Models - Cash and Inventory Verification
/// Supports scheduled audits, cash counting, and inventory verification
library;

/// Audit schedule configuration
class AuditSchedule {
  final String id;
  final String shopId;
  final String shopName;
  final AuditType type;
  final AuditFrequency frequency;
  final String? dayOfWeek; // For weekly: 'monday', 'tuesday', etc.
  final int? dayOfMonth; // For monthly: 1-31
  final String timeOfDay; // '09:00', '18:00'
  final bool isActive;
  final DateTime? nextScheduledAt;
  final DateTime createdAt;
  final DateTime? updatedAt;

  AuditSchedule({
    required this.id,
    required this.shopId,
    required this.shopName,
    required this.type,
    required this.frequency,
    this.dayOfWeek,
    this.dayOfMonth,
    required this.timeOfDay,
    this.isActive = true,
    this.nextScheduledAt,
    required this.createdAt,
    this.updatedAt,
  });

  factory AuditSchedule.fromJson(Map<String, dynamic> json) {
    return AuditSchedule(
      id: json['id'] ?? '',
      shopId: json['shop_id'] ?? '',
      shopName: json['shop_name'] ?? '',
      type: AuditType.fromString(json['type'] ?? 'cash'),
      frequency: AuditFrequency.fromString(json['frequency'] ?? 'daily'),
      dayOfWeek: json['day_of_week'],
      dayOfMonth: json['day_of_month'],
      timeOfDay: json['time_of_day'] ?? '18:00',
      isActive: json['is_active'] ?? true,
      nextScheduledAt: json['next_scheduled_at'] != null
          ? DateTime.parse(json['next_scheduled_at'])
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'shop_id': shopId,
        'shop_name': shopName,
        'type': type.value,
        'frequency': frequency.value,
        'day_of_week': dayOfWeek,
        'day_of_month': dayOfMonth,
        'time_of_day': timeOfDay,
        'is_active': isActive,
        'next_scheduled_at': nextScheduledAt?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt?.toIso8601String(),
      };
}

/// Audit types
enum AuditType {
  cash,
  inventory,
  combined;

  static AuditType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'cash':
        return AuditType.cash;
      case 'inventory':
        return AuditType.inventory;
      case 'combined':
        return AuditType.combined;
      default:
        return AuditType.cash;
    }
  }

  String get value {
    switch (this) {
      case AuditType.cash:
        return 'cash';
      case AuditType.inventory:
        return 'inventory';
      case AuditType.combined:
        return 'combined';
    }
  }

  String get displayName {
    switch (this) {
      case AuditType.cash:
        return 'Cash Audit';
      case AuditType.inventory:
        return 'Inventory Audit';
      case AuditType.combined:
        return 'Combined Audit';
    }
  }
}

/// Audit frequency
enum AuditFrequency {
  daily,
  weekly,
  biWeekly,
  monthly,
  quarterly;

  static AuditFrequency fromString(String value) {
    switch (value.toLowerCase()) {
      case 'daily':
        return AuditFrequency.daily;
      case 'weekly':
        return AuditFrequency.weekly;
      case 'bi_weekly':
      case 'biweekly':
        return AuditFrequency.biWeekly;
      case 'monthly':
        return AuditFrequency.monthly;
      case 'quarterly':
        return AuditFrequency.quarterly;
      default:
        return AuditFrequency.daily;
    }
  }

  String get value {
    switch (this) {
      case AuditFrequency.daily:
        return 'daily';
      case AuditFrequency.weekly:
        return 'weekly';
      case AuditFrequency.biWeekly:
        return 'bi_weekly';
      case AuditFrequency.monthly:
        return 'monthly';
      case AuditFrequency.quarterly:
        return 'quarterly';
    }
  }

  String get displayName {
    switch (this) {
      case AuditFrequency.daily:
        return 'Daily';
      case AuditFrequency.weekly:
        return 'Weekly';
      case AuditFrequency.biWeekly:
        return 'Bi-Weekly';
      case AuditFrequency.monthly:
        return 'Monthly';
      case AuditFrequency.quarterly:
        return 'Quarterly';
    }
  }
}

/// Individual audit session
class AuditSession {
  final String id;
  final String shopId;
  final String shopName;
  final AuditType type;
  final AuditStatus status;
  final String? auditorId;
  final String? auditorName;
  final DateTime scheduledAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final CashAuditData? cashAudit;
  final InventoryAuditData? inventoryAudit;
  final String? notes;
  final List<String>? photoUrls;
  final DateTime createdAt;

  AuditSession({
    required this.id,
    required this.shopId,
    required this.shopName,
    required this.type,
    required this.status,
    this.auditorId,
    this.auditorName,
    required this.scheduledAt,
    this.startedAt,
    this.completedAt,
    this.cashAudit,
    this.inventoryAudit,
    this.notes,
    this.photoUrls,
    required this.createdAt,
  });

  factory AuditSession.fromJson(Map<String, dynamic> json) {
    return AuditSession(
      id: json['id'] ?? '',
      shopId: json['shop_id'] ?? '',
      shopName: json['shop_name'] ?? '',
      type: AuditType.fromString(json['type'] ?? 'cash'),
      status: AuditStatus.fromString(json['status'] ?? 'pending'),
      auditorId: json['auditor_id'],
      auditorName: json['auditor_name'],
      scheduledAt: json['scheduled_at'] != null
          ? DateTime.parse(json['scheduled_at'])
          : DateTime.now(),
      startedAt: json['started_at'] != null
          ? DateTime.parse(json['started_at'])
          : null,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'])
          : null,
      cashAudit: json['cash_audit'] != null
          ? CashAuditData.fromJson(json['cash_audit'])
          : null,
      inventoryAudit: json['inventory_audit'] != null
          ? InventoryAuditData.fromJson(json['inventory_audit'])
          : null,
      notes: json['notes'],
      photoUrls: json['photo_urls'] != null
          ? List<String>.from(json['photo_urls'])
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'shop_id': shopId,
        'shop_name': shopName,
        'type': type.value,
        'status': status.value,
        'auditor_id': auditorId,
        'auditor_name': auditorName,
        'scheduled_at': scheduledAt.toIso8601String(),
        'started_at': startedAt?.toIso8601String(),
        'completed_at': completedAt?.toIso8601String(),
        'cash_audit': cashAudit?.toJson(),
        'inventory_audit': inventoryAudit?.toJson(),
        'notes': notes,
        'photo_urls': photoUrls,
        'created_at': createdAt.toIso8601String(),
      };

  Duration? get duration {
    if (startedAt != null && completedAt != null) {
      return completedAt!.difference(startedAt!);
    }
    return null;
  }

  // ==================== Backward-Compatible Alias Getters ====================

  /// Alias for cashAudit (backward compatibility)
  CashAuditData? get cashData => cashAudit;

  /// Alias for inventoryAudit (backward compatibility)
  InventoryAuditData? get inventoryData => inventoryAudit;

  /// Alias for auditorName (backward compatibility)
  String? get conductedByName => auditorName;

  /// Check if any variance exists in audit
  bool get hasVariance {
    if (cashAudit != null && cashAudit!.variance != 0) return true;
    if (inventoryAudit != null && inventoryAudit!.itemsWithVariance > 0) return true;
    return false;
  }

  /// Get status color as int value for Color()
  int get statusColorValue {
    switch (status) {
      case AuditStatus.completed:
        return 0xFF10B981; // Green
      case AuditStatus.inProgress:
        return 0xFF3B82F6; // Blue
      case AuditStatus.pending:
        return 0xFFF59E0B; // Amber
      case AuditStatus.cancelled:
        return 0xFFEF4444; // Red
      case AuditStatus.missed:
        return 0xFF9CA3AF; // Gray
    }
  }
}

/// Audit status
enum AuditStatus {
  pending,
  inProgress,
  completed,
  cancelled,
  missed;

  static AuditStatus fromString(String value) {
    switch (value.toLowerCase()) {
      case 'pending':
        return AuditStatus.pending;
      case 'in_progress':
        return AuditStatus.inProgress;
      case 'completed':
        return AuditStatus.completed;
      case 'cancelled':
        return AuditStatus.cancelled;
      case 'missed':
        return AuditStatus.missed;
      default:
        return AuditStatus.pending;
    }
  }

  String get value {
    switch (this) {
      case AuditStatus.pending:
        return 'pending';
      case AuditStatus.inProgress:
        return 'in_progress';
      case AuditStatus.completed:
        return 'completed';
      case AuditStatus.cancelled:
        return 'cancelled';
      case AuditStatus.missed:
        return 'missed';
    }
  }

  String get displayName {
    switch (this) {
      case AuditStatus.pending:
        return 'Pending';
      case AuditStatus.inProgress:
        return 'In Progress';
      case AuditStatus.completed:
        return 'Completed';
      case AuditStatus.cancelled:
        return 'Cancelled';
      case AuditStatus.missed:
        return 'Missed';
    }
  }
}

/// Cash audit data with denomination counting
class CashAuditData {
  final double expectedAmount;
  final double actualAmount;
  final double variance;
  final Map<String, int> denominations;
  final String? varianceReason;
  final String? notes;
  final bool isReconciled;

  CashAuditData({
    required this.expectedAmount,
    required this.actualAmount,
    required this.variance,
    required this.denominations,
    this.varianceReason,
    this.notes,
    this.isReconciled = false,
  });

  factory CashAuditData.fromJson(Map<String, dynamic> json) {
    final denoms = <String, int>{};
    if (json['denominations'] != null) {
      (json['denominations'] as Map<String, dynamic>).forEach((key, value) {
        denoms[key] = value as int;
      });
    }
    return CashAuditData(
      expectedAmount: (json['expected_amount'] ?? 0).toDouble(),
      actualAmount: (json['actual_amount'] ?? 0).toDouble(),
      variance: (json['variance'] ?? 0).toDouble(),
      denominations: denoms,
      varianceReason: json['variance_reason'],
      notes: json['notes'],
      isReconciled: json['is_reconciled'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'expected_amount': expectedAmount,
        'actual_amount': actualAmount,
        'variance': variance,
        'denominations': denominations,
        'variance_reason': varianceReason,
        'notes': notes,
        'is_reconciled': isReconciled,
      };

  bool get hasVariance => variance.abs() > 0.01;
  bool get isShort => variance < -0.01;
  bool get isOver => variance > 0.01;

  /// Calculate total from denominations
  static double calculateTotal(Map<String, int> denoms) {
    double total = 0;
    denoms.forEach((denomination, count) {
      final value = double.tryParse(denomination) ?? 0;
      total += value * count;
    });
    return total;
  }
}

/// Indian currency denominations
class CurrencyDenominations {
  static const List<String> notes = ['2000', '500', '200', '100', '50', '20', '10'];
  static const List<String> coins = ['10', '5', '2', '1'];
  static const List<String> all = [
    '2000', '500', '200', '100', '50', '20', '10', // Notes
    '5', '2', '1', // Coins
  ];
}

/// Inventory audit data
class InventoryAuditData {
  final int totalItemsExpected;
  final int totalItemsCounted;
  final List<InventoryVariance> variances;
  final int matchingItems;
  final int missingItems;
  final int excessItems;
  final double accuracy;
  // Additional fields for provider compatibility
  final int itemsChecked;
  final int itemsWithVariance;
  final double totalExpectedValue;
  final double totalActualValue;
  final List<InventoryAuditItem> items;

  InventoryAuditData({
    this.totalItemsExpected = 0,
    this.totalItemsCounted = 0,
    this.variances = const [],
    this.matchingItems = 0,
    this.missingItems = 0,
    this.excessItems = 0,
    this.accuracy = 100.0,
    this.itemsChecked = 0,
    this.itemsWithVariance = 0,
    this.totalExpectedValue = 0,
    this.totalActualValue = 0,
    this.items = const [],
  });

  factory InventoryAuditData.fromJson(Map<String, dynamic> json) {
    return InventoryAuditData(
      totalItemsExpected: json['total_items_expected'] ?? 0,
      totalItemsCounted: json['total_items_counted'] ?? 0,
      variances: (json['variances'] as List?)
              ?.map((e) => InventoryVariance.fromJson(e))
              .toList() ??
          [],
      matchingItems: json['matching_items'] ?? 0,
      missingItems: json['missing_items'] ?? 0,
      excessItems: json['excess_items'] ?? 0,
      accuracy: (json['accuracy'] ?? 100).toDouble(),
      itemsChecked: json['items_checked'] ?? 0,
      itemsWithVariance: json['items_with_variance'] ?? 0,
      totalExpectedValue: (json['total_expected_value'] ?? 0).toDouble(),
      totalActualValue: (json['total_actual_value'] ?? 0).toDouble(),
      items: (json['items'] as List?)
              ?.map((e) => InventoryAuditItem.fromJson(e))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'total_items_expected': totalItemsExpected,
        'total_items_counted': totalItemsCounted,
        'variances': variances.map((e) => e.toJson()).toList(),
        'matching_items': matchingItems,
        'missing_items': missingItems,
        'excess_items': excessItems,
        'accuracy': accuracy,
        'items_checked': itemsChecked,
        'items_with_variance': itemsWithVariance,
        'total_expected_value': totalExpectedValue,
        'total_actual_value': totalActualValue,
        'items': items.map((e) => e.toJson()).toList(),
      };

  bool get hasPerfectMatch => missingItems == 0 && excessItems == 0;
}

/// Inventory item for audit (used in active audit session)
class InventoryAuditItem {
  final String productId;
  final String productName;
  final String? category;
  final String? sku;
  final int expectedQuantity;
  final int actualQuantity;
  final int variance;
  final double? unitPrice;
  final String? notes;
  final DateTime? countedAt;

  InventoryAuditItem({
    required this.productId,
    required this.productName,
    this.category,
    this.sku,
    required this.expectedQuantity,
    required this.actualQuantity,
    required this.variance,
    this.unitPrice,
    this.notes,
    this.countedAt,
  });

  factory InventoryAuditItem.fromJson(Map<String, dynamic> json) {
    return InventoryAuditItem(
      productId: json['product_id'] ?? '',
      productName: json['product_name'] ?? '',
      category: json['category'],
      sku: json['sku'],
      expectedQuantity: json['expected_quantity'] ?? 0,
      actualQuantity: json['actual_quantity'] ?? 0,
      variance: json['variance'] ?? 0,
      unitPrice: json['unit_price'] != null
          ? (json['unit_price'] as num).toDouble()
          : null,
      notes: json['notes'],
      countedAt: json['counted_at'] != null
          ? DateTime.parse(json['counted_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'product_id': productId,
        'product_name': productName,
        'category': category,
        'sku': sku,
        'expected_quantity': expectedQuantity,
        'actual_quantity': actualQuantity,
        'variance': variance,
        'unit_price': unitPrice,
        'notes': notes,
        'counted_at': countedAt?.toIso8601String(),
      };

  InventoryAuditItem copyWith({
    String? productId,
    String? productName,
    String? category,
    String? sku,
    int? expectedQuantity,
    int? actualQuantity,
    int? variance,
    double? unitPrice,
    String? notes,
    DateTime? countedAt,
  }) {
    return InventoryAuditItem(
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      category: category ?? this.category,
      sku: sku ?? this.sku,
      expectedQuantity: expectedQuantity ?? this.expectedQuantity,
      actualQuantity: actualQuantity ?? this.actualQuantity,
      variance: variance ?? this.variance,
      unitPrice: unitPrice ?? this.unitPrice,
      notes: notes ?? this.notes,
      countedAt: countedAt ?? this.countedAt,
    );
  }

  bool get hasVariance => variance != 0;
  bool get isMissing => variance < 0;
  bool get isExcess => variance > 0;
}

/// Individual inventory item variance
class InventoryVariance {
  final String productId;
  final String productName;
  final int expectedQuantity;
  final int actualQuantity;
  final int variance;
  final String? reason;

  InventoryVariance({
    required this.productId,
    required this.productName,
    required this.expectedQuantity,
    required this.actualQuantity,
    required this.variance,
    this.reason,
  });

  factory InventoryVariance.fromJson(Map<String, dynamic> json) {
    return InventoryVariance(
      productId: json['product_id'] ?? '',
      productName: json['product_name'] ?? '',
      expectedQuantity: json['expected_quantity'] ?? 0,
      actualQuantity: json['actual_quantity'] ?? 0,
      variance: json['variance'] ?? 0,
      reason: json['reason'],
    );
  }

  Map<String, dynamic> toJson() => {
        'product_id': productId,
        'product_name': productName,
        'expected_quantity': expectedQuantity,
        'actual_quantity': actualQuantity,
        'variance': variance,
        'reason': reason,
      };

  bool get isMissing => variance < 0;
  bool get isExcess => variance > 0;
}

/// Audit summary for dashboard
class AuditSummary {
  final int totalScheduled;
  final int completedToday;
  final int pendingToday;
  final int missedToday;
  final double overallCashAccuracy;
  final double overallInventoryAccuracy;
  final List<RecentAudit> recentAudits;

  AuditSummary({
    required this.totalScheduled,
    required this.completedToday,
    required this.pendingToday,
    required this.missedToday,
    required this.overallCashAccuracy,
    required this.overallInventoryAccuracy,
    required this.recentAudits,
  });

  factory AuditSummary.fromJson(Map<String, dynamic> json) {
    return AuditSummary(
      totalScheduled: json['total_scheduled'] ?? 0,
      completedToday: json['completed_today'] ?? 0,
      pendingToday: json['pending_today'] ?? 0,
      missedToday: json['missed_today'] ?? 0,
      overallCashAccuracy: (json['overall_cash_accuracy'] ?? 100).toDouble(),
      overallInventoryAccuracy: (json['overall_inventory_accuracy'] ?? 100).toDouble(),
      recentAudits: (json['recent_audits'] as List?)
              ?.map((e) => RecentAudit.fromJson(e))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'total_scheduled': totalScheduled,
        'completed_today': completedToday,
        'pending_today': pendingToday,
        'missed_today': missedToday,
        'overall_cash_accuracy': overallCashAccuracy,
        'overall_inventory_accuracy': overallInventoryAccuracy,
        'recent_audits': recentAudits.map((e) => e.toJson()).toList(),
      };
}

/// Recent audit for listing
class RecentAudit {
  final String id;
  final String shopName;
  final AuditType type;
  final AuditStatus status;
  final DateTime completedAt;
  final bool hasVariance;

  RecentAudit({
    required this.id,
    required this.shopName,
    required this.type,
    required this.status,
    required this.completedAt,
    required this.hasVariance,
  });

  factory RecentAudit.fromJson(Map<String, dynamic> json) {
    return RecentAudit(
      id: json['id'] ?? '',
      shopName: json['shop_name'] ?? '',
      type: AuditType.fromString(json['type'] ?? 'cash'),
      status: AuditStatus.fromString(json['status'] ?? 'completed'),
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'])
          : DateTime.now(),
      hasVariance: json['has_variance'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'shop_name': shopName,
        'type': type.value,
        'status': status.value,
        'completed_at': completedAt.toIso8601String(),
        'has_variance': hasVariance,
      };
}

/// Create schedule request
class CreateScheduleRequest {
  final String shopId;
  final AuditType type;
  final AuditFrequency frequency;
  final String? dayOfWeek;
  final int? dayOfMonth;
  final String timeOfDay;

  CreateScheduleRequest({
    required this.shopId,
    required this.type,
    required this.frequency,
    this.dayOfWeek,
    this.dayOfMonth,
    required this.timeOfDay,
  });

  Map<String, dynamic> toJson() => {
        'shop_id': shopId,
        'type': type.value,
        'frequency': frequency.value,
        'day_of_week': dayOfWeek,
        'day_of_month': dayOfMonth,
        'time_of_day': timeOfDay,
      };
}

/// Submit audit request
class SubmitAuditRequest {
  final String auditId;
  final CashAuditData? cashAudit;
  final InventoryAuditData? inventoryAudit;
  final String? notes;
  final List<String>? photoUrls;

  SubmitAuditRequest({
    required this.auditId,
    this.cashAudit,
    this.inventoryAudit,
    this.notes,
    this.photoUrls,
  });

  Map<String, dynamic> toJson() => {
        'audit_id': auditId,
        'cash_audit': cashAudit?.toJson(),
        'inventory_audit': inventoryAudit?.toJson(),
        'notes': notes,
        'photo_urls': photoUrls,
      };
}

/// Start audit request
class StartAuditRequest {
  final String shopId;
  final AuditType type;
  final String? scheduleId;
  final String? notes;

  StartAuditRequest({
    required this.shopId,
    required this.type,
    this.scheduleId,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
        'shop_id': shopId,
        'type': type.value,
        'schedule_id': scheduleId,
        'notes': notes,
      };
}

/// Audit list query
class AuditQuery {
  final String? shopId;
  final AuditType? type;
  final AuditStatus? status;
  final DateTime? fromDate;
  final DateTime? toDate;
  final int limit;
  final int offset;

  const AuditQuery({
    this.shopId,
    this.type,
    this.status,
    this.fromDate,
    this.toDate,
    DateTime? startDate,
    DateTime? endDate,
    this.limit = 20,
    this.offset = 0,
  });

  /// Named constructor with startDate/endDate (alias for provider compatibility)
  factory AuditQuery.withDates({
    String? shopId,
    AuditType? type,
    AuditStatus? status,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 20,
    int offset = 0,
  }) {
    return AuditQuery(
      shopId: shopId,
      type: type,
      status: status,
      fromDate: startDate,
      toDate: endDate,
      limit: limit,
      offset: offset,
    );
  }

  // Alias getters for provider compatibility
  DateTime? get startDate => fromDate;
  DateTime? get endDate => toDate;

  Map<String, dynamic> toQueryParams() {
    final params = <String, dynamic>{
      'limit': limit.toString(),
      'offset': offset.toString(),
    };
    if (shopId != null) params['shop_id'] = shopId;
    if (type != null) params['type'] = type!.value;
    if (status != null) params['status'] = status!.value;
    if (fromDate != null) params['from_date'] = fromDate!.toIso8601String();
    if (toDate != null) params['to_date'] = toDate!.toIso8601String();
    return params;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuditQuery &&
          runtimeType == other.runtimeType &&
          shopId == other.shopId &&
          type == other.type &&
          status == other.status &&
          fromDate == other.fromDate &&
          toDate == other.toDate &&
          limit == other.limit &&
          offset == other.offset;

  @override
  int get hashCode =>
      shopId.hashCode ^
      type.hashCode ^
      status.hashCode ^
      fromDate.hashCode ^
      toDate.hashCode ^
      limit.hashCode ^
      offset.hashCode;
}
