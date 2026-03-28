// =============================================================================
// THEFT DETECTION MODELS
// Z-Score Based Anomaly Detection for Liquor Inventory
// =============================================================================

import 'package:flutter/foundation.dart';

// =============================================================================
// ENUMS
// =============================================================================

/// Type of anomaly detected
enum AnomalyType {
  cashDiscrepancy,
  inventoryMismatch,
  salesPattern,
  returnAnomaly,
  priceManipulation,
  voidPattern,
  timeAnomaly,
  employeeBehavior,
}

extension AnomalyTypeX on AnomalyType {
  String get displayName {
    switch (this) {
      case AnomalyType.cashDiscrepancy:
        return 'Cash Discrepancy';
      case AnomalyType.inventoryMismatch:
        return 'Inventory Mismatch';
      case AnomalyType.salesPattern:
        return 'Unusual Sales Pattern';
      case AnomalyType.returnAnomaly:
        return 'Suspicious Returns';
      case AnomalyType.priceManipulation:
        return 'Price Manipulation';
      case AnomalyType.voidPattern:
        return 'Void Pattern';
      case AnomalyType.timeAnomaly:
        return 'Time-Based Anomaly';
      case AnomalyType.employeeBehavior:
        return 'Employee Behavior';
    }
  }

  String get icon {
    switch (this) {
      case AnomalyType.cashDiscrepancy:
        return '💰';
      case AnomalyType.inventoryMismatch:
        return '📦';
      case AnomalyType.salesPattern:
        return '📊';
      case AnomalyType.returnAnomaly:
        return '↩️';
      case AnomalyType.priceManipulation:
        return '💵';
      case AnomalyType.voidPattern:
        return '🚫';
      case AnomalyType.timeAnomaly:
        return '⏰';
      case AnomalyType.employeeBehavior:
        return '👤';
    }
  }
}

/// Severity level of the anomaly
enum SeverityLevel {
  low,
  medium,
  high,
  critical,
}

extension SeverityLevelX on SeverityLevel {
  String get displayName {
    switch (this) {
      case SeverityLevel.low:
        return 'Low';
      case SeverityLevel.medium:
        return 'Medium';
      case SeverityLevel.high:
        return 'High';
      case SeverityLevel.critical:
        return 'Critical';
    }
  }

  int get colorValue {
    switch (this) {
      case SeverityLevel.low:
        return 0xFF10B981; // Green
      case SeverityLevel.medium:
        return 0xFFF59E0B; // Yellow
      case SeverityLevel.high:
        return 0xFFF97316; // Orange
      case SeverityLevel.critical:
        return 0xFFEF4444; // Red
    }
  }
}

/// Status of an investigation
enum InvestigationStatus {
  open,
  inProgress,
  pendingReview,
  resolved,
  closed,
  escalated,
}

extension InvestigationStatusX on InvestigationStatus {
  String get displayName {
    switch (this) {
      case InvestigationStatus.open:
        return 'Open';
      case InvestigationStatus.inProgress:
        return 'In Progress';
      case InvestigationStatus.pendingReview:
        return 'Pending Review';
      case InvestigationStatus.resolved:
        return 'Resolved';
      case InvestigationStatus.closed:
        return 'Closed';
      case InvestigationStatus.escalated:
        return 'Escalated';
    }
  }

  int get colorValue {
    switch (this) {
      case InvestigationStatus.open:
        return 0xFFEF4444; // Red
      case InvestigationStatus.inProgress:
        return 0xFF3B82F6; // Blue
      case InvestigationStatus.pendingReview:
        return 0xFFF59E0B; // Yellow
      case InvestigationStatus.resolved:
        return 0xFF10B981; // Green
      case InvestigationStatus.closed:
        return 0xFF6B7280; // Gray
      case InvestigationStatus.escalated:
        return 0xFF8B5CF6; // Purple
    }
  }
}

/// Resolution type for an investigation
enum ResolutionType {
  confirmed,
  falsePositive,
  inconclusive,
  recovered,
  disciplinaryAction,
  termination,
  legalAction,
}

extension ResolutionTypeX on ResolutionType {
  String get displayName {
    switch (this) {
      case ResolutionType.confirmed:
        return 'Confirmed Theft';
      case ResolutionType.falsePositive:
        return 'False Positive';
      case ResolutionType.inconclusive:
        return 'Inconclusive';
      case ResolutionType.recovered:
        return 'Recovered';
      case ResolutionType.disciplinaryAction:
        return 'Disciplinary Action';
      case ResolutionType.termination:
        return 'Termination';
      case ResolutionType.legalAction:
        return 'Legal Action';
    }
  }
}

/// Alert priority
enum AlertPriority {
  low,
  normal,
  high,
  urgent,
}

extension AlertPriorityX on AlertPriority {
  String get displayName {
    switch (this) {
      case AlertPriority.low:
        return 'Low';
      case AlertPriority.normal:
        return 'Normal';
      case AlertPriority.high:
        return 'High';
      case AlertPriority.urgent:
        return 'Urgent';
    }
  }

  int get colorValue {
    switch (this) {
      case AlertPriority.low:
        return 0xFF6B7280; // Gray
      case AlertPriority.normal:
        return 0xFF3B82F6; // Blue
      case AlertPriority.high:
        return 0xFFF97316; // Orange
      case AlertPriority.urgent:
        return 0xFFEF4444; // Red
    }
  }
}

// =============================================================================
// MODELS
// =============================================================================

/// Detected anomaly with Z-score statistics
@immutable
class Anomaly {
  final String id;
  final String tenantId;
  final String shopId;
  final String? shopName;
  final AnomalyType type;
  final SeverityLevel severity;
  final double zScore;
  final double value;
  final double expectedValue;
  final double standardDeviation;
  final double variance;
  final String description;
  final Map<String, dynamic> metadata;
  final String? employeeId;
  final String? employeeName;
  final String? productId;
  final String? productName;
  final String? transactionId;
  final DateTime detectedAt;
  final bool isAcknowledged;
  final String? acknowledgedBy;
  final DateTime? acknowledgedAt;
  final String? investigationId;
  final DateTime createdAt;

  const Anomaly({
    required this.id,
    required this.tenantId,
    required this.shopId,
    this.shopName,
    required this.type,
    required this.severity,
    required this.zScore,
    required this.value,
    required this.expectedValue,
    required this.standardDeviation,
    required this.variance,
    required this.description,
    this.metadata = const {},
    this.employeeId,
    this.employeeName,
    this.productId,
    this.productName,
    this.transactionId,
    required this.detectedAt,
    this.isAcknowledged = false,
    this.acknowledgedBy,
    this.acknowledgedAt,
    this.investigationId,
    required this.createdAt,
  });

  factory Anomaly.fromJson(Map<String, dynamic> json) {
    return Anomaly(
      id: json['id'] ?? '',
      tenantId: json['tenant_id'] ?? '',
      shopId: json['shop_id'] ?? '',
      shopName: json['shop_name'],
      type: _parseAnomalyType(json['type']),
      severity: _parseSeverity(json['severity']),
      zScore: (json['z_score'] ?? 0).toDouble(),
      value: (json['value'] ?? 0).toDouble(),
      expectedValue: (json['expected_value'] ?? 0).toDouble(),
      standardDeviation: (json['standard_deviation'] ?? 0).toDouble(),
      variance: (json['variance'] ?? 0).toDouble(),
      description: json['description'] ?? '',
      metadata: json['metadata'] ?? {},
      employeeId: json['employee_id'],
      employeeName: json['employee_name'],
      productId: json['product_id'],
      productName: json['product_name'],
      transactionId: json['transaction_id'],
      detectedAt: DateTime.tryParse(json['detected_at'] ?? '') ?? DateTime.now(),
      isAcknowledged: json['is_acknowledged'] ?? false,
      acknowledgedBy: json['acknowledged_by'],
      acknowledgedAt: json['acknowledged_at'] != null
          ? DateTime.tryParse(json['acknowledged_at'])
          : null,
      investigationId: json['investigation_id'],
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
    );
  }

  static AnomalyType _parseAnomalyType(String? type) {
    switch (type?.toLowerCase()) {
      case 'cash_discrepancy':
        return AnomalyType.cashDiscrepancy;
      case 'inventory_mismatch':
        return AnomalyType.inventoryMismatch;
      case 'sales_pattern':
        return AnomalyType.salesPattern;
      case 'return_anomaly':
        return AnomalyType.returnAnomaly;
      case 'price_manipulation':
        return AnomalyType.priceManipulation;
      case 'void_pattern':
        return AnomalyType.voidPattern;
      case 'time_anomaly':
        return AnomalyType.timeAnomaly;
      case 'employee_behavior':
        return AnomalyType.employeeBehavior;
      default:
        return AnomalyType.salesPattern;
    }
  }

  static SeverityLevel _parseSeverity(String? severity) {
    switch (severity?.toLowerCase()) {
      case 'low':
        return SeverityLevel.low;
      case 'medium':
        return SeverityLevel.medium;
      case 'high':
        return SeverityLevel.high;
      case 'critical':
        return SeverityLevel.critical;
      default:
        return SeverityLevel.medium;
    }
  }

  /// Percentage deviation from expected
  double get deviationPercent {
    if (expectedValue == 0) return 0;
    return ((value - expectedValue) / expectedValue) * 100;
  }
}

/// Investigation case for anomalies
@immutable
class Investigation {
  final String id;
  final String tenantId;
  final String shopId;
  final String? shopName;
  final String caseNumber;
  final String title;
  final String description;
  final InvestigationStatus status;
  final SeverityLevel priority;
  final List<String> anomalyIds;
  final List<Anomaly>? anomalies;
  final String? assigneeId;
  final String? assigneeName;
  final String createdById;
  final String? createdByName;
  final double estimatedLoss;
  final double? actualLoss;
  final double? recoveredAmount;
  final ResolutionType? resolution;
  final String? resolutionNotes;
  final List<InvestigationNote> notes;
  final List<InvestigationEvidence> evidence;
  final DateTime? dueDate;
  final DateTime? resolvedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Investigation({
    required this.id,
    required this.tenantId,
    required this.shopId,
    this.shopName,
    required this.caseNumber,
    required this.title,
    required this.description,
    required this.status,
    required this.priority,
    this.anomalyIds = const [],
    this.anomalies,
    this.assigneeId,
    this.assigneeName,
    required this.createdById,
    this.createdByName,
    this.estimatedLoss = 0,
    this.actualLoss,
    this.recoveredAmount,
    this.resolution,
    this.resolutionNotes,
    this.notes = const [],
    this.evidence = const [],
    this.dueDate,
    this.resolvedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Investigation.fromJson(Map<String, dynamic> json) {
    return Investigation(
      id: json['id'] ?? '',
      tenantId: json['tenant_id'] ?? '',
      shopId: json['shop_id'] ?? '',
      shopName: json['shop_name'],
      caseNumber: json['case_number'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      status: _parseStatus(json['status']),
      priority: Anomaly._parseSeverity(json['priority']),
      anomalyIds: List<String>.from(json['anomaly_ids'] ?? []),
      anomalies: (json['anomalies'] as List<dynamic>?)
          ?.map((e) => Anomaly.fromJson(e))
          .toList(),
      assigneeId: json['assignee_id'],
      assigneeName: json['assignee_name'],
      createdById: json['created_by_id'] ?? '',
      createdByName: json['created_by_name'],
      estimatedLoss: (json['estimated_loss'] ?? 0).toDouble(),
      actualLoss: json['actual_loss']?.toDouble(),
      recoveredAmount: json['recovered_amount']?.toDouble(),
      resolution: _parseResolution(json['resolution']),
      resolutionNotes: json['resolution_notes'],
      notes: (json['notes'] as List<dynamic>?)
              ?.map((e) => InvestigationNote.fromJson(e))
              .toList() ??
          [],
      evidence: (json['evidence'] as List<dynamic>?)
              ?.map((e) => InvestigationEvidence.fromJson(e))
              .toList() ??
          [],
      dueDate: json['due_date'] != null
          ? DateTime.tryParse(json['due_date'])
          : null,
      resolvedAt: json['resolved_at'] != null
          ? DateTime.tryParse(json['resolved_at'])
          : null,
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
    );
  }

  static InvestigationStatus _parseStatus(String? status) {
    switch (status?.toLowerCase()) {
      case 'open':
        return InvestigationStatus.open;
      case 'in_progress':
        return InvestigationStatus.inProgress;
      case 'pending_review':
        return InvestigationStatus.pendingReview;
      case 'resolved':
        return InvestigationStatus.resolved;
      case 'closed':
        return InvestigationStatus.closed;
      case 'escalated':
        return InvestigationStatus.escalated;
      default:
        return InvestigationStatus.open;
    }
  }

  static ResolutionType? _parseResolution(String? resolution) {
    if (resolution == null) return null;
    switch (resolution.toLowerCase()) {
      case 'confirmed':
        return ResolutionType.confirmed;
      case 'false_positive':
        return ResolutionType.falsePositive;
      case 'inconclusive':
        return ResolutionType.inconclusive;
      case 'recovered':
        return ResolutionType.recovered;
      case 'disciplinary_action':
        return ResolutionType.disciplinaryAction;
      case 'termination':
        return ResolutionType.termination;
      case 'legal_action':
        return ResolutionType.legalAction;
      default:
        return null;
    }
  }

  /// Days since investigation opened
  int get daysOpen => DateTime.now().difference(createdAt).inDays;

  /// Days until due date
  int? get daysUntilDue {
    if (dueDate == null) return null;
    return dueDate!.difference(DateTime.now()).inDays;
  }

  /// Is overdue
  bool get isOverdue {
    if (dueDate == null) return false;
    return DateTime.now().isAfter(dueDate!) &&
        status != InvestigationStatus.resolved &&
        status != InvestigationStatus.closed;
  }
}

/// Note on an investigation
@immutable
class InvestigationNote {
  final String id;
  final String investigationId;
  final String content;
  final String createdById;
  final String? createdByName;
  final bool isInternal;
  final DateTime createdAt;

  const InvestigationNote({
    required this.id,
    required this.investigationId,
    required this.content,
    required this.createdById,
    this.createdByName,
    this.isInternal = false,
    required this.createdAt,
  });

  factory InvestigationNote.fromJson(Map<String, dynamic> json) {
    return InvestigationNote(
      id: json['id'] ?? '',
      investigationId: json['investigation_id'] ?? '',
      content: json['content'] ?? '',
      createdById: json['created_by_id'] ?? '',
      createdByName: json['created_by_name'],
      isInternal: json['is_internal'] ?? false,
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
    );
  }
}

/// Evidence attached to an investigation
@immutable
class InvestigationEvidence {
  final String id;
  final String investigationId;
  final String type; // image, document, video, audio
  final String name;
  final String url;
  final String? description;
  final String uploadedById;
  final String? uploadedByName;
  final DateTime createdAt;

  const InvestigationEvidence({
    required this.id,
    required this.investigationId,
    required this.type,
    required this.name,
    required this.url,
    this.description,
    required this.uploadedById,
    this.uploadedByName,
    required this.createdAt,
  });

  factory InvestigationEvidence.fromJson(Map<String, dynamic> json) {
    return InvestigationEvidence(
      id: json['id'] ?? '',
      investigationId: json['investigation_id'] ?? '',
      type: json['type'] ?? 'document',
      name: json['name'] ?? '',
      url: json['url'] ?? '',
      description: json['description'],
      uploadedById: json['uploaded_by_id'] ?? '',
      uploadedByName: json['uploaded_by_name'],
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
    );
  }
}

/// Real-time alert for theft detection
@immutable
class TheftAlert {
  final String id;
  final String tenantId;
  final String shopId;
  final String? shopName;
  final AlertPriority priority;
  final String title;
  final String message;
  final AnomalyType anomalyType;
  final String? anomalyId;
  final String? investigationId;
  final double? value;
  final bool isRead;
  final bool isDismissed;
  final DateTime createdAt;
  final DateTime? readAt;

  const TheftAlert({
    required this.id,
    required this.tenantId,
    required this.shopId,
    this.shopName,
    required this.priority,
    required this.title,
    required this.message,
    required this.anomalyType,
    this.anomalyId,
    this.investigationId,
    this.value,
    this.isRead = false,
    this.isDismissed = false,
    required this.createdAt,
    this.readAt,
  });

  factory TheftAlert.fromJson(Map<String, dynamic> json) {
    return TheftAlert(
      id: json['id'] ?? '',
      tenantId: json['tenant_id'] ?? '',
      shopId: json['shop_id'] ?? '',
      shopName: json['shop_name'],
      priority: _parsePriority(json['priority']),
      title: json['title'] ?? '',
      message: json['message'] ?? '',
      anomalyType: Anomaly._parseAnomalyType(json['anomaly_type']),
      anomalyId: json['anomaly_id'],
      investigationId: json['investigation_id'],
      value: json['value']?.toDouble(),
      isRead: json['is_read'] ?? false,
      isDismissed: json['is_dismissed'] ?? false,
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      readAt: json['read_at'] != null ? DateTime.tryParse(json['read_at']) : null,
    );
  }

  static AlertPriority _parsePriority(String? priority) {
    switch (priority?.toLowerCase()) {
      case 'low':
        return AlertPriority.low;
      case 'normal':
        return AlertPriority.normal;
      case 'high':
        return AlertPriority.high;
      case 'urgent':
        return AlertPriority.urgent;
      default:
        return AlertPriority.normal;
    }
  }
}

/// Summary statistics for theft detection
@immutable
class TheftSummary {
  final int totalAnomalies;
  final int activeAnomalies;
  final int acknowledgedAnomalies;
  final int openInvestigations;
  final int resolvedInvestigations;
  final double totalEstimatedLoss;
  final double totalRecovered;
  final int unreadAlerts;
  final Map<String, int> anomaliesByType;
  final Map<String, int> anomaliesBySeverity;
  final List<AnomalyTrend> trends;
  final List<HighRiskEmployee> highRiskEmployees;
  final List<HighRiskProduct> highRiskProducts;
  final DateTime periodStart;
  final DateTime periodEnd;

  const TheftSummary({
    this.totalAnomalies = 0,
    this.activeAnomalies = 0,
    this.acknowledgedAnomalies = 0,
    this.openInvestigations = 0,
    this.resolvedInvestigations = 0,
    this.totalEstimatedLoss = 0,
    this.totalRecovered = 0,
    this.unreadAlerts = 0,
    this.anomaliesByType = const {},
    this.anomaliesBySeverity = const {},
    this.trends = const [],
    this.highRiskEmployees = const [],
    this.highRiskProducts = const [],
    required this.periodStart,
    required this.periodEnd,
  });

  factory TheftSummary.fromJson(Map<String, dynamic> json) {
    return TheftSummary(
      totalAnomalies: json['total_anomalies'] ?? 0,
      activeAnomalies: json['active_anomalies'] ?? 0,
      acknowledgedAnomalies: json['acknowledged_anomalies'] ?? 0,
      openInvestigations: json['open_investigations'] ?? 0,
      resolvedInvestigations: json['resolved_investigations'] ?? 0,
      totalEstimatedLoss: (json['total_estimated_loss'] ?? 0).toDouble(),
      totalRecovered: (json['total_recovered'] ?? 0).toDouble(),
      unreadAlerts: json['unread_alerts'] ?? 0,
      anomaliesByType: Map<String, int>.from(json['anomalies_by_type'] ?? {}),
      anomaliesBySeverity:
          Map<String, int>.from(json['anomalies_by_severity'] ?? {}),
      trends: (json['trends'] as List<dynamic>?)
              ?.map((e) => AnomalyTrend.fromJson(e))
              .toList() ??
          [],
      highRiskEmployees: (json['high_risk_employees'] as List<dynamic>?)
              ?.map((e) => HighRiskEmployee.fromJson(e))
              .toList() ??
          [],
      highRiskProducts: (json['high_risk_products'] as List<dynamic>?)
              ?.map((e) => HighRiskProduct.fromJson(e))
              .toList() ??
          [],
      periodStart:
          DateTime.tryParse(json['period_start'] ?? '') ?? DateTime.now(),
      periodEnd: DateTime.tryParse(json['period_end'] ?? '') ?? DateTime.now(),
    );
  }

  /// Recovery rate percentage
  double get recoveryRate {
    if (totalEstimatedLoss == 0) return 0;
    return (totalRecovered / totalEstimatedLoss) * 100;
  }
}

/// Trend data for anomalies over time
@immutable
class AnomalyTrend {
  final DateTime date;
  final int count;
  final double value;

  const AnomalyTrend({
    required this.date,
    required this.count,
    required this.value,
  });

  factory AnomalyTrend.fromJson(Map<String, dynamic> json) {
    return AnomalyTrend(
      date: DateTime.tryParse(json['date'] ?? '') ?? DateTime.now(),
      count: json['count'] ?? 0,
      value: (json['value'] ?? 0).toDouble(),
    );
  }
}

/// High-risk employee summary
@immutable
class HighRiskEmployee {
  final String employeeId;
  final String employeeName;
  final String? shopId;
  final String? shopName;
  final int anomalyCount;
  final double riskScore;
  final double totalValue;

  const HighRiskEmployee({
    required this.employeeId,
    required this.employeeName,
    this.shopId,
    this.shopName,
    required this.anomalyCount,
    required this.riskScore,
    required this.totalValue,
  });

  factory HighRiskEmployee.fromJson(Map<String, dynamic> json) {
    return HighRiskEmployee(
      employeeId: json['employee_id'] ?? '',
      employeeName: json['employee_name'] ?? '',
      shopId: json['shop_id'],
      shopName: json['shop_name'],
      anomalyCount: json['anomaly_count'] ?? 0,
      riskScore: (json['risk_score'] ?? 0).toDouble(),
      totalValue: (json['total_value'] ?? 0).toDouble(),
    );
  }
}

/// High-risk product summary
@immutable
class HighRiskProduct {
  final String productId;
  final String productName;
  final String? brandName;
  final int anomalyCount;
  final double totalVariance;
  final int unitsAffected;

  const HighRiskProduct({
    required this.productId,
    required this.productName,
    this.brandName,
    required this.anomalyCount,
    required this.totalVariance,
    required this.unitsAffected,
  });

  factory HighRiskProduct.fromJson(Map<String, dynamic> json) {
    return HighRiskProduct(
      productId: json['product_id'] ?? '',
      productName: json['product_name'] ?? '',
      brandName: json['brand_name'],
      anomalyCount: json['anomaly_count'] ?? 0,
      totalVariance: (json['total_variance'] ?? 0).toDouble(),
      unitsAffected: json['units_affected'] ?? 0,
    );
  }
}

/// Detection settings/thresholds
@immutable
class DetectionSettings {
  final String shopId;
  final double zScoreThreshold; // Default 2.0
  final bool cashDiscrepancyEnabled;
  final double cashDiscrepancyThreshold;
  final bool inventoryMismatchEnabled;
  final double inventoryMismatchThreshold;
  final bool salesPatternEnabled;
  final double salesPatternThreshold;
  final bool returnAnomalyEnabled;
  final double returnAnomalyThreshold;
  final bool priceManipulationEnabled;
  final bool voidPatternEnabled;
  final int voidPatternLimit; // Max voids per day
  final bool timeAnomalyEnabled;
  final List<String> businessHoursStart; // e.g., ["09:00"]
  final List<String> businessHoursEnd; // e.g., ["22:00"]
  final bool employeeBehaviorEnabled;
  final List<String> alertRecipients;
  final bool instantAlertsEnabled;
  final bool dailySummaryEnabled;

  const DetectionSettings({
    required this.shopId,
    this.zScoreThreshold = 2.0,
    this.cashDiscrepancyEnabled = true,
    this.cashDiscrepancyThreshold = 500,
    this.inventoryMismatchEnabled = true,
    this.inventoryMismatchThreshold = 5,
    this.salesPatternEnabled = true,
    this.salesPatternThreshold = 2.5,
    this.returnAnomalyEnabled = true,
    this.returnAnomalyThreshold = 3,
    this.priceManipulationEnabled = true,
    this.voidPatternEnabled = true,
    this.voidPatternLimit = 10,
    this.timeAnomalyEnabled = true,
    this.businessHoursStart = const ['09:00'],
    this.businessHoursEnd = const ['22:00'],
    this.employeeBehaviorEnabled = true,
    this.alertRecipients = const [],
    this.instantAlertsEnabled = true,
    this.dailySummaryEnabled = true,
  });

  factory DetectionSettings.fromJson(Map<String, dynamic> json) {
    return DetectionSettings(
      shopId: json['shop_id'] ?? '',
      zScoreThreshold: (json['z_score_threshold'] ?? 2.0).toDouble(),
      cashDiscrepancyEnabled: json['cash_discrepancy_enabled'] ?? true,
      cashDiscrepancyThreshold:
          (json['cash_discrepancy_threshold'] ?? 500).toDouble(),
      inventoryMismatchEnabled: json['inventory_mismatch_enabled'] ?? true,
      inventoryMismatchThreshold:
          (json['inventory_mismatch_threshold'] ?? 5).toDouble(),
      salesPatternEnabled: json['sales_pattern_enabled'] ?? true,
      salesPatternThreshold:
          (json['sales_pattern_threshold'] ?? 2.5).toDouble(),
      returnAnomalyEnabled: json['return_anomaly_enabled'] ?? true,
      returnAnomalyThreshold:
          (json['return_anomaly_threshold'] ?? 3).toDouble(),
      priceManipulationEnabled: json['price_manipulation_enabled'] ?? true,
      voidPatternEnabled: json['void_pattern_enabled'] ?? true,
      voidPatternLimit: json['void_pattern_limit'] ?? 10,
      timeAnomalyEnabled: json['time_anomaly_enabled'] ?? true,
      businessHoursStart:
          List<String>.from(json['business_hours_start'] ?? ['09:00']),
      businessHoursEnd:
          List<String>.from(json['business_hours_end'] ?? ['22:00']),
      employeeBehaviorEnabled: json['employee_behavior_enabled'] ?? true,
      alertRecipients: List<String>.from(json['alert_recipients'] ?? []),
      instantAlertsEnabled: json['instant_alerts_enabled'] ?? true,
      dailySummaryEnabled: json['daily_summary_enabled'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'shop_id': shopId,
      'z_score_threshold': zScoreThreshold,
      'cash_discrepancy_enabled': cashDiscrepancyEnabled,
      'cash_discrepancy_threshold': cashDiscrepancyThreshold,
      'inventory_mismatch_enabled': inventoryMismatchEnabled,
      'inventory_mismatch_threshold': inventoryMismatchThreshold,
      'sales_pattern_enabled': salesPatternEnabled,
      'sales_pattern_threshold': salesPatternThreshold,
      'return_anomaly_enabled': returnAnomalyEnabled,
      'return_anomaly_threshold': returnAnomalyThreshold,
      'price_manipulation_enabled': priceManipulationEnabled,
      'void_pattern_enabled': voidPatternEnabled,
      'void_pattern_limit': voidPatternLimit,
      'time_anomaly_enabled': timeAnomalyEnabled,
      'business_hours_start': businessHoursStart,
      'business_hours_end': businessHoursEnd,
      'employee_behavior_enabled': employeeBehaviorEnabled,
      'alert_recipients': alertRecipients,
      'instant_alerts_enabled': instantAlertsEnabled,
      'daily_summary_enabled': dailySummaryEnabled,
    };
  }
}

// =============================================================================
// REQUEST MODELS
// =============================================================================

/// Query parameters for anomalies
class AnomalyQuery {
  final String? shopId;
  final AnomalyType? type;
  final SeverityLevel? severity;
  final bool? isAcknowledged;
  final DateTime? startDate;
  final DateTime? endDate;
  final int? limit;
  final int? offset;

  const AnomalyQuery({
    this.shopId,
    this.type,
    this.severity,
    this.isAcknowledged,
    this.startDate,
    this.endDate,
    this.limit,
    this.offset,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnomalyQuery &&
          runtimeType == other.runtimeType &&
          shopId == other.shopId &&
          type == other.type &&
          severity == other.severity &&
          isAcknowledged == other.isAcknowledged &&
          startDate == other.startDate &&
          endDate == other.endDate;

  @override
  int get hashCode =>
      shopId.hashCode ^
      type.hashCode ^
      severity.hashCode ^
      isAcknowledged.hashCode ^
      startDate.hashCode ^
      endDate.hashCode;
}

/// Request to create an investigation
class CreateInvestigationRequest {
  final String shopId;
  final String title;
  final String description;
  final SeverityLevel priority;
  final List<String> anomalyIds;
  final String? assigneeId;
  final DateTime? dueDate;

  const CreateInvestigationRequest({
    required this.shopId,
    required this.title,
    required this.description,
    required this.priority,
    this.anomalyIds = const [],
    this.assigneeId,
    this.dueDate,
  });

  Map<String, dynamic> toJson() {
    return {
      'shop_id': shopId,
      'title': title,
      'description': description,
      'priority': priority.name,
      'anomaly_ids': anomalyIds,
      if (assigneeId != null) 'assignee_id': assigneeId,
      if (dueDate != null) 'due_date': dueDate!.toIso8601String(),
    };
  }
}

/// Request to update investigation status
class UpdateInvestigationRequest {
  final InvestigationStatus? status;
  final String? assigneeId;
  final double? actualLoss;
  final double? recoveredAmount;
  final ResolutionType? resolution;
  final String? resolutionNotes;

  const UpdateInvestigationRequest({
    this.status,
    this.assigneeId,
    this.actualLoss,
    this.recoveredAmount,
    this.resolution,
    this.resolutionNotes,
  });

  Map<String, dynamic> toJson() {
    return {
      if (status != null) 'status': status!.name,
      if (assigneeId != null) 'assignee_id': assigneeId,
      if (actualLoss != null) 'actual_loss': actualLoss,
      if (recoveredAmount != null) 'recovered_amount': recoveredAmount,
      if (resolution != null) 'resolution': resolution!.name,
      if (resolutionNotes != null) 'resolution_notes': resolutionNotes,
    };
  }
}

/// Request to add a note to investigation
class AddNoteRequest {
  final String content;
  final bool isInternal;

  const AddNoteRequest({
    required this.content,
    this.isInternal = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'content': content,
      'is_internal': isInternal,
    };
  }
}
