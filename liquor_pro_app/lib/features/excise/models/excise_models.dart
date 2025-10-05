// UP Excise Models
// Complete data models for UP Excise Compliance module

import 'package:flutter/material.dart';

/// Excise License Model
class ExciseLicense {
  final String id;
  final String tenantId;
  final String shopId;
  final String licenseNumber;
  final LicenseType licenseType;
  final DateTime issuedDate;
  final DateTime expiryDate;
  final bool isActive;
  final double monthlyFee;
  final String? bankAccountId;
  final Map<String, dynamic>? restrictions;
  final String? licenseConditions;
  final String? issuingAuthority;
  final String? licenseCategory;
  final DateTime createdAt;
  final DateTime updatedAt;

  ExciseLicense({
    required this.id,
    required this.tenantId,
    required this.shopId,
    required this.licenseNumber,
    required this.licenseType,
    required this.issuedDate,
    required this.expiryDate,
    required this.isActive,
    required this.monthlyFee,
    this.bankAccountId,
    this.restrictions,
    this.licenseConditions,
    this.issuingAuthority,
    this.licenseCategory,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ExciseLicense.fromJson(Map<String, dynamic> json) {
    return ExciseLicense(
      id: json['id'],
      tenantId: json['tenant_id'],
      shopId: json['shop_id'],
      licenseNumber: json['license_number'],
      licenseType: LicenseType.fromString(json['license_type']),
      issuedDate: DateTime.parse(json['issued_date'] ?? json['issue_date']),
      expiryDate: DateTime.parse(json['expiry_date']),
      isActive: json['is_active'] ?? true,
      monthlyFee: (json['monthly_fee'] as num).toDouble(),
      bankAccountId: json['bank_account_id'],
      restrictions: json['restrictions'],
      licenseConditions: json['license_conditions'],
      issuingAuthority: json['issuing_authority'],
      licenseCategory: json['license_category'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  // Helper methods
  bool get isExpiringSoon {
    final daysUntilExpiry = expiryDate.difference(DateTime.now()).inDays;
    return daysUntilExpiry <= 30 && daysUntilExpiry > 0;
  }

  bool get isExpired => DateTime.now().isAfter(expiryDate);

  int get daysUntilExpiry => expiryDate.difference(DateTime.now()).inDays;

  Color get statusColor {
    if (isExpired) return Colors.red;
    if (isExpiringSoon) return Colors.orange;
    return Colors.green;
  }

  String get statusText {
    if (isExpired) return 'Expired';
    if (isExpiringSoon) return 'Expiring Soon ($daysUntilExpiry days)';
    return 'Active';
  }

  IconData get statusIcon {
    if (isExpired) return Icons.error;
    if (isExpiringSoon) return Icons.warning;
    return Icons.check_circle;
  }
}

/// License Type Enum
enum LicenseType {
  fl2a,      // IMFL + Beer + Wine
  fl17,      // Country Liquor + Beer
  cl2,       // Godown License
  composite; // All categories

  static LicenseType fromString(String value) {
    switch (value.toUpperCase()) {
      case 'FL-2A':
      case 'FL2A':
        return LicenseType.fl2a;
      case 'FL-17':
      case 'FL17':
        return LicenseType.fl17;
      case 'CL-2':
      case 'CL2':
        return LicenseType.cl2;
      case 'COMPOSITE':
        return LicenseType.composite;
      default:
        return LicenseType.composite;
    }
  }
}

// Extension for LicenseType enum
extension LicenseTypeExtension on LicenseType {
  String get displayName {
    switch (this) {
      case LicenseType.fl2a:
        return 'FL-2A (IMFL + Beer + Wine)';
      case LicenseType.fl17:
        return 'FL-17 (Country Liquor + Beer)';
      case LicenseType.cl2:
        return 'CL-2 (Godown License)';
      case LicenseType.composite:
        return 'COMPOSITE (All Categories)';
    }
  }

  String get shortName {
    switch (this) {
      case LicenseType.fl2a:
        return 'FL-2A';
      case LicenseType.fl17:
        return 'FL-17';
      case LicenseType.cl2:
        return 'CL-2';
      case LicenseType.composite:
        return 'COMPOSITE';
    }
  }

  String get value => name;

  Color get color {
    switch (this) {
      case LicenseType.fl2a:
        return Colors.blue;
      case LicenseType.fl17:
        return Colors.green;
      case LicenseType.cl2:
        return Colors.purple;
      case LicenseType.composite:
        return Colors.orange;
    }
  }
}

/// Stock Entry Model
class StockEntry {
  final String productId;
  final String productName;
  final int quantity;
  final double value;

  StockEntry({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.value,
  });

  factory StockEntry.fromJson(Map<String, dynamic> json) {
    return StockEntry(
      productId: json['product_id'],
      productName: json['product_name'],
      quantity: json['quantity'],
      value: (json['value'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'product_id': productId,
      'product_name': productName,
      'quantity': quantity,
      'value': value,
    };
  }
}

/// Stock Breakdown Model
class StockBreakdown {
  final List<StockEntry> countryLiquor;
  final List<StockEntry> imfl;
  final List<StockEntry> beer;
  final List<StockEntry> wine;
  final List<StockEntry> lowAlcohol;

  StockBreakdown({
    required this.countryLiquor,
    required this.imfl,
    required this.beer,
    required this.wine,
    required this.lowAlcohol,
  });

  factory StockBreakdown.fromJson(Map<String, dynamic> json) {
    return StockBreakdown(
      countryLiquor: (json['country_liquor'] as List? ?? [])
          .map((e) => StockEntry.fromJson(e))
          .toList(),
      imfl: (json['imfl'] as List? ?? [])
          .map((e) => StockEntry.fromJson(e))
          .toList(),
      beer: (json['beer'] as List? ?? [])
          .map((e) => StockEntry.fromJson(e))
          .toList(),
      wine: (json['wine'] as List? ?? [])
          .map((e) => StockEntry.fromJson(e))
          .toList(),
      lowAlcohol: (json['low_alcohol'] as List? ?? [])
          .map((e) => StockEntry.fromJson(e))
          .toList(),
    );
  }

  int get totalQuantity {
    final total = countryLiquor.fold(0, (sum, e) => sum + e.quantity) +
        imfl.fold(0, (sum, e) => sum + e.quantity) +
        beer.fold(0, (sum, e) => sum + e.quantity) +
        wine.fold(0, (sum, e) => sum + e.quantity) +
        lowAlcohol.fold(0, (sum, e) => sum + e.quantity);
    return total.toInt();
  }

  int get totalBottles => totalQuantity;

  double get totalValue {
    return countryLiquor.fold(0.0, (sum, e) => sum + e.value) +
        imfl.fold(0.0, (sum, e) => sum + e.value) +
        beer.fold(0.0, (sum, e) => sum + e.value) +
        wine.fold(0.0, (sum, e) => sum + e.value) +
        lowAlcohol.fold(0.0, (sum, e) => sum + e.value);
  }
}

/// Excise Daily Report Model
class ExciseDailyReport {
  final String id;
  final String shopId;
  final String licenseId;
  final DateTime reportDate;
  final StockBreakdown openingStock;
  final StockBreakdown stockLifted;
  final StockBreakdown sales;
  final StockBreakdown returns;
  final StockBreakdown closingStock;
  final double considerationFeePaid;
  final bool uploadedToPortal;
  final int uploadAttempts;
  final DateTime? uploadTimestamp;
  final String? smsConfirmation;
  final String? portalResponse;

  ExciseDailyReport({
    required this.id,
    required this.shopId,
    required this.licenseId,
    required this.reportDate,
    required this.openingStock,
    required this.stockLifted,
    required this.sales,
    required this.returns,
    required this.closingStock,
    required this.considerationFeePaid,
    required this.uploadedToPortal,
    required this.uploadAttempts,
    this.uploadTimestamp,
    this.smsConfirmation,
    this.portalResponse,
  });

  factory ExciseDailyReport.fromJson(Map<String, dynamic> json) {
    return ExciseDailyReport(
      id: json['id'],
      shopId: json['shop_id'],
      licenseId: json['license_id'],
      reportDate: DateTime.parse(json['report_date']),
      openingStock: StockBreakdown.fromJson(json['opening_stock']),
      stockLifted: StockBreakdown.fromJson(json['stock_lifted']),
      sales: StockBreakdown.fromJson(json['sales']),
      returns: StockBreakdown.fromJson(json['returns']),
      closingStock: StockBreakdown.fromJson(json['closing_stock']),
      considerationFeePaid: (json['consideration_fee_paid'] as num).toDouble(),
      uploadedToPortal: json['uploaded_to_portal'] ?? false,
      uploadAttempts: json['upload_attempts'] ?? 0,
      uploadTimestamp: json['upload_timestamp'] != null
          ? DateTime.parse(json['upload_timestamp'])
          : null,
      smsConfirmation: json['sms_confirmation'],
      portalResponse: json['portal_response'],
    );
  }

  // Convenience getters for screens
  StockBreakdown get salesQuantity => sales;
  StockBreakdown get liftedQuantity => stockLifted;
  StockBreakdown get returnsQuantity => returns;
  DateTime? get portalUploadedAt => uploadTimestamp;
  bool get portalUploadFailed => uploadAttempts > 0 && !uploadedToPortal;

  Color get uploadStatusColor {
    if (uploadedToPortal) return Colors.green;
    if (uploadAttempts > 0) return Colors.orange;
    return Colors.grey;
  }

  IconData get uploadStatusIcon {
    if (uploadedToPortal) return Icons.cloud_done;
    if (uploadAttempts > 0) return Icons.cloud_upload;
    return Icons.cloud_off;
  }

  String get uploadStatusText {
    if (uploadedToPortal) return 'Uploaded';
    if (uploadAttempts > 0) return 'Upload Failed';
    return 'Pending Upload';
  }
}

/// Compliance Dashboard Model
class ComplianceDashboard {
  final String tenantId;
  final int totalShops;
  final int activeShops;
  final int activeLicenses;
  final int expiringLicenses;
  final int pendingReports;
  final int pendingLicenseFees;
  final double overdueFeesAmount;
  final double complianceScore;
  final String complianceStatus;
  final DateTime? lastReportDate;

  ComplianceDashboard({
    required this.tenantId,
    required this.totalShops,
    required this.activeShops,
    required this.activeLicenses,
    required this.expiringLicenses,
    required this.pendingReports,
    required this.pendingLicenseFees,
    required this.overdueFeesAmount,
    required this.complianceScore,
    required this.complianceStatus,
    this.lastReportDate,
  });

  factory ComplianceDashboard.fromJson(Map<String, dynamic> json) {
    return ComplianceDashboard(
      tenantId: json['tenant_id'],
      totalShops: json['total_shops'],
      activeShops: json['active_shops'],
      activeLicenses: json['active_licenses'],
      expiringLicenses: json['expiring_licenses'],
      pendingReports: json['pending_reports'],
      pendingLicenseFees: json['pending_license_fees'],
      overdueFeesAmount: (json['overdue_fees_amount'] as num).toDouble(),
      complianceScore: (json['compliance_score'] as num).toDouble(),
      complianceStatus: json['compliance_status'],
      lastReportDate: json['last_report_date'] != null
          ? DateTime.parse(json['last_report_date'])
          : null,
    );
  }

  int get totalLicenses => activeLicenses;
  DateTime? get lastUpdated => lastReportDate;

  Color get scoreColor {
    if (complianceScore >= 90) return Colors.green;
    if (complianceScore >= 70) return Colors.orange;
    return Colors.red;
  }

  IconData get scoreIcon {
    if (complianceScore >= 90) return Icons.check_circle;
    if (complianceScore >= 70) return Icons.warning;
    return Icons.error;
  }

  String get scoreGrade {
    if (complianceScore >= 90) return 'Excellent';
    if (complianceScore >= 70) return 'Good';
    if (complianceScore >= 50) return 'Needs Attention';
    return 'Critical';
  }

  List<ComplianceIssue> get issues {
    final List<ComplianceIssue> issuesList = [];

    if (pendingReports > 0) {
      issuesList.add(ComplianceIssue(
        title: 'Pending Daily Reports',
        count: pendingReports,
        severity: ComplianceSeverity.high,
        icon: Icons.description,
      ));
    }

    if (expiringLicenses > 0) {
      issuesList.add(ComplianceIssue(
        title: 'Expiring Licenses',
        count: expiringLicenses,
        severity: ComplianceSeverity.medium,
        icon: Icons.warning,
      ));
    }

    if (pendingLicenseFees > 0) {
      issuesList.add(ComplianceIssue(
        title: 'Pending License Fees',
        count: pendingLicenseFees,
        severity: ComplianceSeverity.high,
        icon: Icons.payment,
      ));
    }

    return issuesList;
  }
}

/// Compliance Issue Helper
class ComplianceIssue {
  final String title;
  final int count;
  final ComplianceSeverity severity;
  final IconData icon;

  ComplianceIssue({
    required this.title,
    required this.count,
    required this.severity,
    required this.icon,
  });

  Color get color {
    switch (severity) {
      case ComplianceSeverity.low:
        return Colors.blue;
      case ComplianceSeverity.medium:
        return Colors.orange;
      case ComplianceSeverity.high:
        return Colors.red;
    }
  }
}

enum ComplianceSeverity { low, medium, high }

/// Compliance Log Model
class ComplianceLog {
  final String id;
  final String tenantId;
  final String shopId;
  final String eventType;
  final String description;
  final ComplianceSeverity severity;
  final DateTime timestamp;
  final bool resolved;
  final DateTime? resolvedAt;
  final String? resolvedBy;
  final Map<String, dynamic>? metadata;

  ComplianceLog({
    required this.id,
    required this.tenantId,
    required this.shopId,
    required this.eventType,
    required this.description,
    required this.severity,
    required this.timestamp,
    required this.resolved,
    this.resolvedAt,
    this.resolvedBy,
    this.metadata,
  });

  factory ComplianceLog.fromJson(Map<String, dynamic> json) {
    return ComplianceLog(
      id: json['id'],
      tenantId: json['tenant_id'],
      shopId: json['shop_id'],
      eventType: json['event_type'],
      description: json['description'],
      severity: _parseSeverity(json['severity']),
      timestamp: DateTime.parse(json['timestamp']),
      resolved: json['resolved'] ?? false,
      resolvedAt: json['resolved_at'] != null
          ? DateTime.parse(json['resolved_at'])
          : null,
      resolvedBy: json['resolved_by'],
      metadata: json['metadata'],
    );
  }

  static ComplianceSeverity _parseSeverity(String? value) {
    switch (value?.toLowerCase()) {
      case 'low':
        return ComplianceSeverity.low;
      case 'medium':
        return ComplianceSeverity.medium;
      case 'high':
        return ComplianceSeverity.high;
      default:
        return ComplianceSeverity.medium;
    }
  }
}

/// Security Code Model
class SecurityCode {
  final String id;
  final String securityCode;
  final String productId;
  final SecurityCodeStatus status;
  final DateTime? receivedDate;
  final String? warehouseSource;
  final String? batchNumber;
  final bool verified;
  final DateTime? soldDate;
  final String? saleId;
  final String shopId;

  SecurityCode({
    required this.id,
    required this.securityCode,
    required this.productId,
    required this.status,
    this.receivedDate,
    this.warehouseSource,
    this.batchNumber,
    required this.verified,
    this.soldDate,
    this.saleId,
    required this.shopId,
  });

  factory SecurityCode.fromJson(Map<String, dynamic> json) {
    return SecurityCode(
      id: json['id'],
      securityCode: json['security_code'],
      productId: json['product_id'],
      status: SecurityCodeStatus.fromString(json['status']),
      receivedDate: json['received_date'] != null
          ? DateTime.parse(json['received_date'])
          : null,
      warehouseSource: json['warehouse_source'],
      batchNumber: json['batch_number'],
      verified: json['verified'] ?? false,
      soldDate: json['sold_date'] != null
          ? DateTime.parse(json['sold_date'])
          : null,
      saleId: json['sale_id'],
      shopId: json['shop_id'] ?? '',
    );
  }

  String get code => securityCode;
  Color get statusColor => status.color;
  IconData get statusIcon => status.icon;
  String get statusText => status.displayName;
}

/// Security Code Status
enum SecurityCodeStatus {
  inStock,
  sold,
  damaged,
  missing,
  returned;

  static SecurityCodeStatus fromString(String value) {
    switch (value.toLowerCase()) {
      case 'in_stock':
      case 'instock':
        return SecurityCodeStatus.inStock;
      case 'sold':
        return SecurityCodeStatus.sold;
      case 'damaged':
        return SecurityCodeStatus.damaged;
      case 'missing':
        return SecurityCodeStatus.missing;
      case 'returned':
        return SecurityCodeStatus.returned;
      default:
        return SecurityCodeStatus.inStock;
    }
  }
}

// Extension for SecurityCodeStatus enum
extension SecurityCodeStatusExtension on SecurityCodeStatus {
  String get displayName {
    switch (this) {
      case SecurityCodeStatus.inStock:
        return 'In Stock';
      case SecurityCodeStatus.sold:
        return 'Sold';
      case SecurityCodeStatus.damaged:
        return 'Damaged';
      case SecurityCodeStatus.missing:
        return 'Missing';
      case SecurityCodeStatus.returned:
        return 'Returned';
    }
  }

  Color get color {
    switch (this) {
      case SecurityCodeStatus.inStock:
        return Colors.green;
      case SecurityCodeStatus.sold:
        return Colors.blue;
      case SecurityCodeStatus.damaged:
        return Colors.red;
      case SecurityCodeStatus.missing:
        return Colors.orange;
      case SecurityCodeStatus.returned:
        return Colors.purple;
    }
  }

  IconData get icon {
    switch (this) {
      case SecurityCodeStatus.inStock:
        return Icons.inventory;
      case SecurityCodeStatus.sold:
        return Icons.shopping_cart;
      case SecurityCodeStatus.damaged:
        return Icons.broken_image;
      case SecurityCodeStatus.missing:
        return Icons.search_off;
      case SecurityCodeStatus.returned:
        return Icons.keyboard_return;
    }
  }

  String get value => name;
}

/// Security Code Stats Model
class SecurityCodeStats {
  final int totalCodes;
  final int inStock;
  final int sold;
  final int damaged;
  final int missing;
  final int returned;

  SecurityCodeStats({
    required this.totalCodes,
    required this.inStock,
    required this.sold,
    required this.damaged,
    required this.missing,
    required this.returned,
  });

  factory SecurityCodeStats.fromJson(Map<String, dynamic> json) {
    return SecurityCodeStats(
      totalCodes: json['total_codes'] ?? 0,
      inStock: json['in_stock'] ?? 0,
      sold: json['sold'] ?? 0,
      damaged: json['damaged'] ?? 0,
      missing: json['missing'] ?? 0,
      returned: json['returned'] ?? 0,
    );
  }

  int get totalSold => sold;
  int get totalInStock => inStock;
  int get totalDamaged => damaged;
  int get totalMissing => missing;

  List<StatsItem> get items {
    return [
      StatsItem('In Stock', inStock, Colors.green, Icons.inventory),
      StatsItem('Sold', sold, Colors.blue, Icons.shopping_cart),
      StatsItem('Damaged', damaged, Colors.red, Icons.broken_image),
      StatsItem('Missing', missing, Colors.orange, Icons.search_off),
      StatsItem('Returned', returned, Colors.purple, Icons.keyboard_return),
    ];
  }
}

class StatsItem {
  final String label;
  final int count;
  final Color color;
  final IconData icon;

  StatsItem(this.label, this.count, this.color, this.icon);

  double percentage(int total) {
    if (total == 0) return 0;
    return (count / total) * 100;
  }
}

/// Excise Notification Model
class ExciseNotification {
  final String id;
  final String tenantId;
  final String shopId;
  final String title;
  final String message;
  final NotificationType type;
  final NotificationPriority priority;
  final bool read;
  final DateTime createdAt;
  final DateTime? readAt;
  final String? actionUrl;
  final Map<String, dynamic>? metadata;

  ExciseNotification({
    required this.id,
    required this.tenantId,
    required this.shopId,
    required this.title,
    required this.message,
    required this.type,
    required this.priority,
    required this.read,
    required this.createdAt,
    this.readAt,
    this.actionUrl,
    this.metadata,
  });

  factory ExciseNotification.fromJson(Map<String, dynamic> json) {
    return ExciseNotification(
      id: json['id'],
      tenantId: json['tenant_id'],
      shopId: json['shop_id'],
      title: json['title'],
      message: json['message'],
      type: _parseNotificationType(json['type']),
      priority: _parseNotificationPriority(json['priority']),
      read: json['read'] ?? false,
      createdAt: DateTime.parse(json['created_at']),
      readAt: json['read_at'] != null ? DateTime.parse(json['read_at']) : null,
      actionUrl: json['action_url'],
      metadata: json['metadata'],
    );
  }

  static NotificationType _parseNotificationType(String? value) {
    switch (value?.toLowerCase()) {
      case 'license_expiry':
        return NotificationType.licenseExpiry;
      case 'pending_report':
        return NotificationType.pendingReport;
      case 'fee_due':
        return NotificationType.feeDue;
      case 'compliance_alert':
        return NotificationType.complianceAlert;
      case 'system':
        return NotificationType.system;
      default:
        return NotificationType.system;
    }
  }

  static NotificationPriority _parseNotificationPriority(String? value) {
    switch (value?.toLowerCase()) {
      case 'low':
        return NotificationPriority.low;
      case 'medium':
        return NotificationPriority.medium;
      case 'high':
        return NotificationPriority.high;
      case 'urgent':
        return NotificationPriority.urgent;
      default:
        return NotificationPriority.medium;
    }
  }
}

enum NotificationType {
  licenseExpiry,
  pendingReport,
  feeDue,
  complianceAlert,
  system,
}

enum NotificationPriority {
  low,
  medium,
  high,
  urgent,
}

/// Excise Payment Model
class ExcisePayment {
  final String id;
  final String tenantId;
  final String shopId;
  final String licenseId;
  final PaymentType paymentType;
  final double amount;
  final PaymentStatus status;
  final PaymentMethod method;
  final DateTime paymentDate;
  final String? transactionId;
  final String? receiptNumber;
  final DateTime? dueDate;
  final Map<String, dynamic>? metadata;

  ExcisePayment({
    required this.id,
    required this.tenantId,
    required this.shopId,
    required this.licenseId,
    required this.paymentType,
    required this.amount,
    required this.status,
    required this.method,
    required this.paymentDate,
    this.transactionId,
    this.receiptNumber,
    this.dueDate,
    this.metadata,
  });

  factory ExcisePayment.fromJson(Map<String, dynamic> json) {
    return ExcisePayment(
      id: json['id'],
      tenantId: json['tenant_id'],
      shopId: json['shop_id'],
      licenseId: json['license_id'],
      paymentType: _parsePaymentType(json['payment_type']),
      amount: (json['amount'] as num).toDouble(),
      status: _parsePaymentStatus(json['status']),
      method: _parsePaymentMethod(json['method']),
      paymentDate: DateTime.parse(json['payment_date']),
      transactionId: json['transaction_id'],
      receiptNumber: json['receipt_number'],
      dueDate: json['due_date'] != null ? DateTime.parse(json['due_date']) : null,
      metadata: json['metadata'],
    );
  }

  static PaymentType _parsePaymentType(String? value) {
    switch (value?.toLowerCase()) {
      case 'license_fee':
        return PaymentType.licenseFee;
      case 'consideration_fee':
        return PaymentType.considerationFee;
      case 'penalty':
        return PaymentType.penalty;
      case 'other':
        return PaymentType.other;
      default:
        return PaymentType.other;
    }
  }

  static PaymentStatus _parsePaymentStatus(String? value) {
    switch (value?.toLowerCase()) {
      case 'pending':
        return PaymentStatus.pending;
      case 'completed':
        return PaymentStatus.completed;
      case 'failed':
        return PaymentStatus.failed;
      case 'refunded':
        return PaymentStatus.refunded;
      default:
        return PaymentStatus.pending;
    }
  }

  static PaymentMethod _parsePaymentMethod(String? value) {
    switch (value?.toLowerCase()) {
      case 'cash':
        return PaymentMethod.cash;
      case 'card':
        return PaymentMethod.card;
      case 'upi':
        return PaymentMethod.upi;
      case 'bank_transfer':
        return PaymentMethod.bankTransfer;
      case 'cheque':
        return PaymentMethod.cheque;
      default:
        return PaymentMethod.cash;
    }
  }
}

enum PaymentType {
  licenseFee,
  considerationFee,
  penalty,
  other,
}

enum PaymentStatus {
  pending,
  completed,
  failed,
  refunded,
}

enum PaymentMethod {
  cash,
  card,
  upi,
  bankTransfer,
  cheque,
}

/// Excise Analytics Model
class ExciseAnalytics {
  final String tenantId;
  final DateTime startDate;
  final DateTime endDate;
  final double totalConsiderationFees;
  final double totalLicenseFees;
  final int totalReportsGenerated;
  final int totalReportsUploaded;
  final double averageComplianceScore;
  final Map<String, int> reportsByMonth;
  final Map<String, double> feesByMonth;
  final List<ComplianceTrend> trends;

  ExciseAnalytics({
    required this.tenantId,
    required this.startDate,
    required this.endDate,
    required this.totalConsiderationFees,
    required this.totalLicenseFees,
    required this.totalReportsGenerated,
    required this.totalReportsUploaded,
    required this.averageComplianceScore,
    required this.reportsByMonth,
    required this.feesByMonth,
    required this.trends,
  });

  factory ExciseAnalytics.fromJson(Map<String, dynamic> json) {
    return ExciseAnalytics(
      tenantId: json['tenant_id'],
      startDate: DateTime.parse(json['start_date']),
      endDate: DateTime.parse(json['end_date']),
      totalConsiderationFees: (json['total_consideration_fees'] as num).toDouble(),
      totalLicenseFees: (json['total_license_fees'] as num).toDouble(),
      totalReportsGenerated: json['total_reports_generated'],
      totalReportsUploaded: json['total_reports_uploaded'],
      averageComplianceScore: (json['average_compliance_score'] as num).toDouble(),
      reportsByMonth: Map<String, int>.from(json['reports_by_month'] ?? {}),
      feesByMonth: Map<String, double>.from(json['fees_by_month'] ?? {}),
      trends: (json['trends'] as List? ?? [])
          .map((e) => ComplianceTrend.fromJson(e))
          .toList(),
    );
  }
}

class ComplianceTrend {
  final DateTime date;
  final double score;
  final int issues;

  ComplianceTrend({
    required this.date,
    required this.score,
    required this.issues,
  });

  factory ComplianceTrend.fromJson(Map<String, dynamic> json) {
    return ComplianceTrend(
      date: DateTime.parse(json['date']),
      score: (json['score'] as num).toDouble(),
      issues: json['issues'] ?? 0,
    );
  }
}

/// Excise Settings Model
class ExciseSettings {
  final String tenantId;
  final bool autoGenerateReports;
  final bool autoUploadReports;
  final bool enableNotifications;
  final bool enableSecurityCodeTracking;
  final int reportGenerationTime; // Hour of day (0-23)
  final int licenseExpiryAlertDays;
  final Map<String, dynamic>? portalCredentials;
  final Map<String, dynamic>? preferences;

  ExciseSettings({
    required this.tenantId,
    required this.autoGenerateReports,
    required this.autoUploadReports,
    required this.enableNotifications,
    required this.enableSecurityCodeTracking,
    required this.reportGenerationTime,
    required this.licenseExpiryAlertDays,
    this.portalCredentials,
    this.preferences,
  });

  factory ExciseSettings.fromJson(Map<String, dynamic> json) {
    return ExciseSettings(
      tenantId: json['tenant_id'],
      autoGenerateReports: json['auto_generate_reports'] ?? true,
      autoUploadReports: json['auto_upload_reports'] ?? false,
      enableNotifications: json['enable_notifications'] ?? true,
      enableSecurityCodeTracking: json['enable_security_code_tracking'] ?? true,
      reportGenerationTime: json['report_generation_time'] ?? 23,
      licenseExpiryAlertDays: json['license_expiry_alert_days'] ?? 30,
      portalCredentials: json['portal_credentials'],
      preferences: json['preferences'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tenant_id': tenantId,
      'auto_generate_reports': autoGenerateReports,
      'auto_upload_reports': autoUploadReports,
      'enable_notifications': enableNotifications,
      'enable_security_code_tracking': enableSecurityCodeTracking,
      'report_generation_time': reportGenerationTime,
      'license_expiry_alert_days': licenseExpiryAlertDays,
      'portal_credentials': portalCredentials,
      'preferences': preferences,
    };
  }
}
