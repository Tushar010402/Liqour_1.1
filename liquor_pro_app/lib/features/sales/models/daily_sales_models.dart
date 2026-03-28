/// Daily Sales Models - For bulk daily entry (UP workflow)
library;

import '../../../core/config/api_config.dart';
import '../../../core/utils/date_time_helper.dart';
import 'expense_header.dart';

/// Helper to normalize image URLs
/// Backend may return relative paths like "/uploads/..." which need to be
/// converted to full URLs for CachedNetworkImage to work
String _normalizeImageUrl(String url) {
  if (url.isEmpty) return url;
  if (url.startsWith('http://') || url.startsWith('https://')) {
    return url; // Already a full URL
  }
  if (url.startsWith('/')) {
    return '${ApiConfig.baseUrl}$url'; // Prepend base URL
  }
  return url;
}

// ============================================================================
// AI VALIDATION MODELS (Enhanced with AI Summary & Insights)
// ============================================================================

/// AI Summary from validation - top-level overview
class AISummary {
  final double overallAccuracy;
  final int criticalCount;
  final int warningCount;
  final int matchedCount;
  final int missingCount;
  final String recommendation;
  final String confidenceLevel; // 'high' | 'medium' | 'low'
  final String recommendedAction; // 'approve' | 'review' | 'reject'

  // NEW: Issue type breakdown for accurate Hinglish messages
  final int missingEntryCount;      // Items in receipt but NOT entered by salesman
  final int quantityMismatchCount;  // Sale quantity differences
  final int priceMismatchCount;     // Price/rate differences
  final int stockMismatchCount;     // Opening/closing stock differences
  final int notInReceiptCount;      // Items entered but NOT found in receipt

  const AISummary({
    this.overallAccuracy = 0.0,
    this.criticalCount = 0,
    this.warningCount = 0,
    this.matchedCount = 0,
    this.missingCount = 0,
    this.recommendation = '',
    this.confidenceLevel = 'low',
    this.recommendedAction = 'review',
    // NEW fields
    this.missingEntryCount = 0,
    this.quantityMismatchCount = 0,
    this.priceMismatchCount = 0,
    this.stockMismatchCount = 0,
    this.notInReceiptCount = 0,
  });

  /// Get color for accuracy level
  bool get isHighAccuracy => overallAccuracy >= 80;
  bool get isMediumAccuracy => overallAccuracy >= 50 && overallAccuracy < 80;
  bool get isLowAccuracy => overallAccuracy < 50;

  /// Get total issues count
  int get totalIssues => criticalCount + warningCount;

  factory AISummary.fromJson(Map<String, dynamic> json) {
    return AISummary(
      overallAccuracy: (json['overall_accuracy'] ?? 0.0).toDouble(),
      criticalCount: json['critical_count'] ?? 0,
      warningCount: json['warning_count'] ?? 0,
      matchedCount: json['matched_count'] ?? 0,
      missingCount: json['missing_count'] ?? 0,
      recommendation: json['recommendation']?.toString() ?? '',
      confidenceLevel: json['confidence_level']?.toString() ?? 'low',
      recommendedAction: json['recommended_action']?.toString() ?? 'review',
      // NEW: Parse issue type breakdown
      missingEntryCount: json['missing_entry_count'] ?? 0,
      quantityMismatchCount: json['quantity_mismatch_count'] ?? 0,
      priceMismatchCount: json['price_mismatch_count'] ?? 0,
      stockMismatchCount: json['stock_mismatch_count'] ?? 0,
      notInReceiptCount: json['not_in_receipt_count'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'overall_accuracy': overallAccuracy,
    'critical_count': criticalCount,
    'warning_count': warningCount,
    'matched_count': matchedCount,
    'missing_count': missingCount,
    'recommendation': recommendation,
    'confidence_level': confidenceLevel,
    'recommended_action': recommendedAction,
    // NEW fields
    'missing_entry_count': missingEntryCount,
    'quantity_mismatch_count': quantityMismatchCount,
    'price_mismatch_count': priceMismatchCount,
    'stock_mismatch_count': stockMismatchCount,
    'not_in_receipt_count': notInReceiptCount,
  };
}

/// Individual issue within a product insight
class AIIssue {
  final String type; // 'quantity' | 'price' | 'brand' | 'missing'
  final String severity; // 'critical' | 'warning' | 'info'
  final String field;
  final String enteredValue;
  final String ocrValue;
  final String message;
  final String suggestion;
  final bool autoFixable;

  const AIIssue({
    required this.type,
    required this.severity,
    this.field = '',
    this.enteredValue = '',
    this.ocrValue = '',
    this.message = '',
    this.suggestion = '',
    this.autoFixable = false,
  });

  bool get isCritical => severity == 'critical';
  bool get isWarning => severity == 'warning';

  factory AIIssue.fromJson(Map<String, dynamic> json) {
    return AIIssue(
      type: json['type']?.toString() ?? 'unknown',
      severity: json['severity']?.toString() ?? 'warning',
      field: json['field']?.toString() ?? '',
      enteredValue: json['entered_value']?.toString() ?? '',
      ocrValue: json['ocr_value']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      suggestion: json['suggestion']?.toString() ?? '',
      autoFixable: json['auto_fixable'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'severity': severity,
    'field': field,
    'entered_value': enteredValue,
    'ocr_value': ocrValue,
    'message': message,
    'suggestion': suggestion,
    'auto_fixable': autoFixable,
  };
}

/// Per-item insight with issues
class ItemInsight {
  final String productId;
  final String productName;
  final String status; // 'matched' | 'warning' | 'critical'
  final int issueCount;
  final List<AIIssue> issues;
  final double matchConfidence;

  const ItemInsight({
    required this.productId,
    required this.productName,
    this.status = 'matched',
    this.issueCount = 0,
    this.issues = const [],
    this.matchConfidence = 100.0,
  });

  bool get isMatched => status == 'matched';
  bool get hasIssues => issueCount > 0 || issues.isNotEmpty;
  bool get isCritical => status == 'critical';
  bool get isWarning => status == 'warning';

  factory ItemInsight.fromJson(Map<String, dynamic> json) {
    return ItemInsight(
      productId: json['product_id']?.toString() ?? '',
      productName: json['product_name']?.toString() ?? 'Unknown Product',
      status: json['status']?.toString() ?? 'matched',
      issueCount: json['issue_count'] ?? 0,
      issues: (json['issues'] as List<dynamic>?)
              ?.map((i) => AIIssue.fromJson(i))
              .toList() ??
          [],
      matchConfidence: (json['match_confidence'] ?? 100.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'product_id': productId,
    'product_name': productName,
    'status': status,
    'issue_count': issueCount,
    'issues': issues.map((i) => i.toJson()).toList(),
    'match_confidence': matchConfidence,
  };
}

/// Missing item from receipt not found in entries
class MissingItem {
  final String brand;
  final String size;
  final int ocrQuantity;
  final double ocrPrice;

  const MissingItem({
    this.brand = '',
    this.size = '',
    this.ocrQuantity = 0,
    this.ocrPrice = 0.0,
  });

  factory MissingItem.fromJson(Map<String, dynamic> json) {
    return MissingItem(
      brand: json['brand']?.toString() ?? '',
      size: json['size']?.toString() ?? '',
      ocrQuantity: json['ocr_quantity'] ?? json['quantity'] ?? 0,
      ocrPrice: (json['ocr_price'] ?? json['price'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'brand': brand,
    'size': size,
    'ocr_quantity': ocrQuantity,
    'ocr_price': ocrPrice,
  };
}

/// Missing items grouped by severity
class MissingItemGroup {
  final String severity; // 'critical' | 'warning'
  final int count;
  final List<MissingItem> items;

  const MissingItemGroup({
    required this.severity,
    this.count = 0,
    this.items = const [],
  });

  bool get isCritical => severity == 'critical';

  factory MissingItemGroup.fromJson(Map<String, dynamic> json) {
    return MissingItemGroup(
      severity: json['severity']?.toString() ?? 'warning',
      count: json['count'] ?? 0,
      items: (json['items'] as List<dynamic>?)
              ?.map((i) => MissingItem.fromJson(i))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
    'severity': severity,
    'count': count,
    'items': items.map((i) => i.toJson()).toList(),
  };
}

/// Result of AI validation comparing entered data vs OCR-extracted data
class AIValidationResult {
  final String status; // 'pending' | 'processing' | 'verified' | 'mismatches_found' | 'failed'
  final int totalItems;
  final int matchedCount;
  final int mismatchCount;
  final List<AIValidationMismatch> mismatches;
  final double confidenceScore;
  final String? ocrSessionId;
  final DateTime? validatedAt;

  // NEW: Enhanced AI validation fields from backend
  final AISummary? aiSummary;
  final List<ItemInsight> perItemInsights;
  final List<MissingItemGroup> missingItemsGrouped;

  const AIValidationResult({
    required this.status,
    this.totalItems = 0,
    this.matchedCount = 0,
    this.mismatchCount = 0,
    this.mismatches = const [],
    this.confidenceScore = 0.0,
    this.ocrSessionId,
    this.validatedAt,
    // NEW fields
    this.aiSummary,
    this.perItemInsights = const [],
    this.missingItemsGrouped = const [],
  });

  /// Check if validation is complete
  bool get isComplete => status == 'verified' || status == 'mismatches_found';

  /// Check if validation passed
  bool get isVerified => status == 'verified';

  /// Check if there are mismatches
  bool get hasMismatches => status == 'mismatches_found' || mismatchCount > 0;

  /// Check if enhanced AI data is available
  bool get hasAISummary => aiSummary != null;

  /// Get overall accuracy from AI summary or calculate from counts
  double get overallAccuracy {
    if (aiSummary != null) return aiSummary!.overallAccuracy;
    if (totalItems == 0) return 0.0;
    return (matchedCount / totalItems) * 100;
  }

  /// Get critical issues count
  int get criticalCount => aiSummary?.criticalCount ??
      perItemInsights.where((i) => i.isCritical).length;

  /// Get warning issues count
  int get warningCount => aiSummary?.warningCount ??
      perItemInsights.where((i) => i.isWarning).length;

  /// Get items with issues
  List<ItemInsight> get itemsWithIssues =>
      perItemInsights.where((i) => i.hasIssues).toList();

  factory AIValidationResult.fromJson(Map<String, dynamic> json) {
    // Backend may send 'overall_status' or 'status' - handle both
    final status = json['overall_status']?.toString() ??
                   json['status']?.toString() ??
                   'pending';

    // Backend may send 'mismatches_count' or 'mismatch_count' - handle both
    final mismatchCount = json['mismatches_count'] ??
                          json['mismatch_count'] ??
                          0;

    return AIValidationResult(
      status: status,
      totalItems: json['total_items'] ?? 0,
      matchedCount: json['matched_count'] ?? 0,
      mismatchCount: mismatchCount,
      mismatches: (json['mismatches'] as List<dynamic>?)
              ?.map((m) => AIValidationMismatch.fromJson(m))
              .toList() ??
          [],
      confidenceScore: (json['confidence_score'] ?? 0.0).toDouble(),
      ocrSessionId: json['ocr_session_id']?.toString(),
      validatedAt: DateTimeHelper.parseIsoToLocal(json['validated_at']),
      // NEW: Parse enhanced AI validation fields
      aiSummary: json['ai_summary'] != null
          ? AISummary.fromJson(json['ai_summary'])
          : null,
      perItemInsights: (json['per_item_insights'] as List<dynamic>?)
              ?.map((i) => ItemInsight.fromJson(i))
              .toList() ??
          [],
      missingItemsGrouped: (json['missing_items_grouped'] as List<dynamic>?)
              ?.map((g) => MissingItemGroup.fromJson(g))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
    'status': status,
    'total_items': totalItems,
    'matched_count': matchedCount,
    'mismatch_count': mismatchCount,
    'mismatches': mismatches.map((m) => m.toJson()).toList(),
    'confidence_score': confidenceScore,
    'ocr_session_id': ocrSessionId,
    'validated_at': validatedAt?.toIso8601String(),
    // NEW fields
    if (aiSummary != null) 'ai_summary': aiSummary!.toJson(),
    'per_item_insights': perItemInsights.map((i) => i.toJson()).toList(),
    'missing_items_grouped': missingItemsGrouped.map((g) => g.toJson()).toList(),
  };

  AIValidationResult copyWith({
    String? status,
    int? totalItems,
    int? matchedCount,
    int? mismatchCount,
    List<AIValidationMismatch>? mismatches,
    double? confidenceScore,
    String? ocrSessionId,
    DateTime? validatedAt,
    AISummary? aiSummary,
    List<ItemInsight>? perItemInsights,
    List<MissingItemGroup>? missingItemsGrouped,
  }) {
    return AIValidationResult(
      status: status ?? this.status,
      totalItems: totalItems ?? this.totalItems,
      matchedCount: matchedCount ?? this.matchedCount,
      mismatchCount: mismatchCount ?? this.mismatchCount,
      mismatches: mismatches ?? this.mismatches,
      confidenceScore: confidenceScore ?? this.confidenceScore,
      ocrSessionId: ocrSessionId ?? this.ocrSessionId,
      validatedAt: validatedAt ?? this.validatedAt,
      aiSummary: aiSummary ?? this.aiSummary,
      perItemInsights: perItemInsights ?? this.perItemInsights,
      missingItemsGrouped: missingItemsGrouped ?? this.missingItemsGrouped,
    );
  }
}

/// Individual mismatch between entered and OCR data
class AIValidationMismatch {
  final String mismatchType; // 'brand' | 'quantity' | 'price' | 'missing_entry' | 'missing_receipt'
  final String? enteredBrand;
  final int? enteredQuantity;
  final double? enteredPrice;
  final String? ocrBrand;
  final int? ocrQuantity;
  final double? ocrPrice;
  final String? productId;
  final String? size;
  final double matchConfidence;
  final String? notes;

  const AIValidationMismatch({
    required this.mismatchType,
    this.enteredBrand,
    this.enteredQuantity,
    this.enteredPrice,
    this.ocrBrand,
    this.ocrQuantity,
    this.ocrPrice,
    this.productId,
    this.size,
    this.matchConfidence = 0.0,
    this.notes,
  });

  /// Get human-readable description of the mismatch
  String get description {
    switch (mismatchType) {
      case 'quantity':
        return 'Quantity mismatch: Entered $enteredQuantity, Receipt shows $ocrQuantity';
      case 'price':
        return 'Price mismatch: Entered \u20B9$enteredPrice, Receipt shows \u20B9$ocrPrice';
      case 'brand':
        return 'Brand mismatch: Entered "$enteredBrand", Receipt shows "$ocrBrand"';
      case 'missing_entry':
        return 'Found in receipt but not entered: $ocrBrand';
      case 'missing_receipt':
        return 'Entered but not found in receipt: $enteredBrand';
      default:
        return notes ?? 'Unknown mismatch';
    }
  }

  factory AIValidationMismatch.fromJson(Map<String, dynamic> json) {
    return AIValidationMismatch(
      mismatchType: json['mismatch_type']?.toString() ?? json['type']?.toString() ?? 'unknown',
      enteredBrand: json['entered_brand']?.toString(),
      enteredQuantity: json['entered_quantity'] ?? json['entered_qty'],
      enteredPrice: (json['entered_price'] ?? 0.0).toDouble(),
      ocrBrand: json['ocr_brand']?.toString(),
      ocrQuantity: json['ocr_quantity'] ?? json['ocr_qty'],
      ocrPrice: (json['ocr_price'] ?? 0.0).toDouble(),
      productId: json['product_id']?.toString(),
      size: json['size']?.toString(),
      matchConfidence: (json['match_confidence'] ?? 0.0).toDouble(),
      notes: json['notes']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'mismatch_type': mismatchType,
    'entered_brand': enteredBrand,
    'entered_quantity': enteredQuantity,
    'entered_price': enteredPrice,
    'ocr_brand': ocrBrand,
    'ocr_quantity': ocrQuantity,
    'ocr_price': ocrPrice,
    'product_id': productId,
    'size': size,
    'match_confidence': matchConfidence,
    'notes': notes,
  };
}

// ============================================================================
// DAILY SALES MODELS
// ============================================================================

class DailySalesRecord {
  final String? id;
  final DateTime recordDate;
  final String shopId;
  final String? shopName;
  final String? salesmanId;
  final String? salesmanName;
  final double totalSalesAmount;
  final double totalCashAmount;
  final double totalCardAmount;
  final double totalUpiAmount;
  final double totalCreditAmount;
  final String status;
  final DateTime? approvedAt;
  final String? approvedByName;
  final String? createdByName;
  final String notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<DailySalesItem> items;
  final int totalItems;

  // Location fields (for review/monitoring)
  final double? latitude;
  final double? longitude;
  final String? locationAccuracy;

  // Rejection tracking
  final String? rejectedByName;
  final DateTime? rejectedAt;
  final String? rejectionReason;

  // Resubmission tracking
  final String? resubmittedByName;
  final DateTime? resubmittedAt;
  final int resubmitCount;

  // Image attachments (uploaded receipts/photos)
  final List<String> imageUrls;

  // Expense tracking (NEW - Expense Table Feature)
  final double totalExpenseAmount;
  final List<ExpenseEntry> expenses;

  // AI Validation fields (NEW - Automatic OCR validation)
  final String? ocrSessionId;
  final String? validationStatus; // 'pending' | 'processing' | 'verified' | 'mismatches_found' | 'failed'
  final AIValidationResult? validationResult;
  final DateTime? validatedAt;

  DailySalesRecord({
    this.id,
    required this.recordDate,
    required this.shopId,
    this.shopName,
    this.salesmanId,
    this.salesmanName,
    required this.totalSalesAmount,
    required this.totalCashAmount,
    required this.totalCardAmount,
    required this.totalUpiAmount,
    required this.totalCreditAmount,
    this.status = 'pending',
    this.approvedAt,
    this.approvedByName,
    this.createdByName,
    this.notes = '',
    this.createdAt,
    this.updatedAt,
    this.items = const [],
    this.totalItems = 0,
    // Location fields
    this.latitude,
    this.longitude,
    this.locationAccuracy,
    // Rejection tracking
    this.rejectedByName,
    this.rejectedAt,
    this.rejectionReason,
    // Resubmission tracking
    this.resubmittedByName,
    this.resubmittedAt,
    this.resubmitCount = 0,
    // Image attachments
    this.imageUrls = const [],
    // Expense tracking
    this.totalExpenseAmount = 0.0,
    this.expenses = const [],
    // AI Validation fields
    this.ocrSessionId,
    this.validationStatus,
    this.validationResult,
    this.validatedAt,
  });

  /// Check if AI validation is available for this record
  bool get hasValidation => validationStatus != null;

  /// Check if AI validation shows mismatches
  bool get hasValidationMismatches =>
      validationStatus == 'mismatches_found' ||
      (validationResult?.hasMismatches ?? false);

  /// Check if AI validation passed
  bool get isValidationVerified => validationStatus == 'verified';

  /// Check if AI validation is still processing
  bool get isValidationPending =>
      validationStatus == 'pending' || validationStatus == 'processing';

  /// Check if location was captured for this record
  bool get hasLocation => latitude != null && longitude != null;

  /// Check if images were attached to this record
  bool get hasImages => imageUrls.isNotEmpty;

  factory DailySalesRecord.fromJson(Map<String, dynamic> json) {
    // Debug: Log expense data from backend
    final expenseAmount = (json['total_expense_amount'] ?? 0).toDouble();
    final expensesList = json['expenses'] as List<dynamic>?;
    if (expenseAmount > 0 || (expensesList != null && expensesList.isNotEmpty)) {
      print('💰 [DailySalesRecord] Parsing expenses for ${json['id']}:');
      print('   total_expense_amount: $expenseAmount');
      print('   expenses count: ${expensesList?.length ?? 0}');
      if (expensesList != null) {
        for (var i = 0; i < expensesList.length; i++) {
          print('   [$i]: ${expensesList[i]}');
        }
      }
    }
    return DailySalesRecord(
      id: json['id'],
      recordDate: DateTimeHelper.parseIsoToLocal(json['record_date']) ?? DateTime.now(),
      shopId: json['shop_id'],
      shopName: json['shop_name'],
      salesmanId: json['salesman_id'],
      salesmanName: json['salesman_name'],
      totalSalesAmount: (json['total_sales_amount'] ?? 0).toDouble(),
      totalCashAmount: (json['total_cash_amount'] ?? 0).toDouble(),
      totalCardAmount: (json['total_card_amount'] ?? 0).toDouble(),
      totalUpiAmount: (json['total_upi_amount'] ?? 0).toDouble(),
      totalCreditAmount: (json['total_credit_amount'] ?? 0).toDouble(),
      status: json['status'] ?? 'pending',
      approvedAt: DateTimeHelper.parseIsoToLocal(json['approved_at']),
      approvedByName: json['approved_by_name'],
      createdByName: json['created_by_name'],
      notes: json['notes'] ?? '',
      createdAt: DateTimeHelper.parseIsoToLocal(json['created_at']),
      updatedAt: DateTimeHelper.parseIsoToLocal(json['updated_at']),
      items: (json['items'] as List<dynamic>?)
              ?.map((item) => DailySalesItem.fromJson(item))
              .toList() ??
          [],
      totalItems: json['total_items'] ?? 0,
      // Parse location fields from backend
      latitude: json['latitude'] != null ? (json['latitude'] as num).toDouble() : null,
      longitude: json['longitude'] != null ? (json['longitude'] as num).toDouble() : null,
      locationAccuracy: json['location_accuracy']?.toString(),
      // Parse rejection tracking fields
      rejectedByName: json['rejected_by_name'],
      rejectedAt: DateTimeHelper.parseIsoToLocal(json['rejected_at']),
      rejectionReason: json['rejection_reason'],
      // Parse resubmission tracking fields
      resubmittedByName: json['resubmitted_by_name'],
      resubmittedAt: DateTimeHelper.parseIsoToLocal(json['resubmitted_at']),
      resubmitCount: json['resubmit_count'] ?? 0,
      // Parse image URLs from backend - normalize to full URLs for CachedNetworkImage
      imageUrls: (json['image_urls'] as List<dynamic>?)
              ?.map((url) => _normalizeImageUrl(url.toString()))
              .toList() ??
          [],
      // Parse expense tracking fields
      totalExpenseAmount: (json['total_expense_amount'] ?? 0).toDouble(),
      expenses: (json['expenses'] as List<dynamic>?)
              ?.map((e) => ExpenseEntry.fromJson(e))
              .toList() ??
          [],
      // Parse AI validation fields
      ocrSessionId: json['ocr_session_id']?.toString(),
      validationStatus: json['validation_status']?.toString(),
      validationResult: json['validation_result'] != null
          ? AIValidationResult.fromJson(json['validation_result'])
          : null,
      validatedAt: DateTimeHelper.parseIsoToLocal(json['validated_at']),
    );
  }

  /// Check if expenses were recorded
  bool get hasExpenses => totalExpenseAmount > 0 || expenses.isNotEmpty;

  Map<String, dynamic> toJson() {
    return {
      'record_date': recordDate.toIso8601String(),
      'shop_id': shopId,
      'salesman_id': salesmanId,
      'total_sales_amount': totalSalesAmount,
      'total_cash_amount': totalCashAmount,
      'total_card_amount': totalCardAmount,
      'total_upi_amount': totalUpiAmount,
      'total_credit_amount': totalCreditAmount,
      'notes': notes,
      'items': items.map((item) => item.toJson()).toList(),
    };
  }

  DailySalesRecord copyWith({
    String? id,
    DateTime? recordDate,
    String? shopId,
    String? shopName,
    String? salesmanId,
    String? salesmanName,
    double? totalSalesAmount,
    double? totalCashAmount,
    double? totalCardAmount,
    double? totalUpiAmount,
    double? totalCreditAmount,
    String? status,
    DateTime? approvedAt,
    String? approvedByName,
    String? createdByName,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<DailySalesItem>? items,
    int? totalItems,
    double? latitude,
    double? longitude,
    String? locationAccuracy,
    String? rejectedByName,
    DateTime? rejectedAt,
    String? rejectionReason,
    String? resubmittedByName,
    DateTime? resubmittedAt,
    int? resubmitCount,
    List<String>? imageUrls,
    double? totalExpenseAmount,
    List<ExpenseEntry>? expenses,
    String? ocrSessionId,
    String? validationStatus,
    AIValidationResult? validationResult,
    DateTime? validatedAt,
  }) {
    return DailySalesRecord(
      id: id ?? this.id,
      recordDate: recordDate ?? this.recordDate,
      shopId: shopId ?? this.shopId,
      shopName: shopName ?? this.shopName,
      salesmanId: salesmanId ?? this.salesmanId,
      salesmanName: salesmanName ?? this.salesmanName,
      totalSalesAmount: totalSalesAmount ?? this.totalSalesAmount,
      totalCashAmount: totalCashAmount ?? this.totalCashAmount,
      totalCardAmount: totalCardAmount ?? this.totalCardAmount,
      totalUpiAmount: totalUpiAmount ?? this.totalUpiAmount,
      totalCreditAmount: totalCreditAmount ?? this.totalCreditAmount,
      status: status ?? this.status,
      approvedAt: approvedAt ?? this.approvedAt,
      approvedByName: approvedByName ?? this.approvedByName,
      createdByName: createdByName ?? this.createdByName,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      items: items ?? this.items,
      totalItems: totalItems ?? this.totalItems,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      locationAccuracy: locationAccuracy ?? this.locationAccuracy,
      rejectedByName: rejectedByName ?? this.rejectedByName,
      rejectedAt: rejectedAt ?? this.rejectedAt,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      resubmittedByName: resubmittedByName ?? this.resubmittedByName,
      resubmittedAt: resubmittedAt ?? this.resubmittedAt,
      resubmitCount: resubmitCount ?? this.resubmitCount,
      imageUrls: imageUrls ?? this.imageUrls,
      totalExpenseAmount: totalExpenseAmount ?? this.totalExpenseAmount,
      expenses: expenses ?? this.expenses,
      ocrSessionId: ocrSessionId ?? this.ocrSessionId,
      validationStatus: validationStatus ?? this.validationStatus,
      validationResult: validationResult ?? this.validationResult,
      validatedAt: validatedAt ?? this.validatedAt,
    );
  }
}

class DailySalesItem {
  final String? id;
  final String productId;
  final String? productName;
  final String? brandName;
  final String? categoryName;
  final String? size;
  final int quantity;
  final double unitPrice;
  final double totalAmount;
  final double cashAmount;
  final double cardAmount;
  final double upiAmount;
  final double creditAmount;

  // Stock audit fields - for inventory tracking and mismatch detection
  final int openingStock; // Stock BEFORE this sale was recorded
  final int closingStock; // Stock AFTER this sale (opening - quantity)

  DailySalesItem({
    this.id,
    required this.productId,
    this.productName,
    this.brandName,
    this.categoryName,
    this.size,
    required this.quantity,
    required this.unitPrice,
    required this.totalAmount,
    this.cashAmount = 0,
    this.cardAmount = 0,
    this.upiAmount = 0,
    this.creditAmount = 0,
    this.openingStock = 0,
    this.closingStock = 0,
  });

  factory DailySalesItem.fromJson(Map<String, dynamic> json) {
    return DailySalesItem(
      id: json['id'],
      productId: json['product_id'],
      productName: json['product_name'],
      brandName: json['brand_name'],
      categoryName: json['category_name'],
      size: json['size'],
      quantity: json['quantity'] ?? 0,
      unitPrice: (json['unit_price'] ?? 0).toDouble(),
      totalAmount: (json['total_amount'] ?? 0).toDouble(),
      cashAmount: (json['cash_amount'] ?? 0).toDouble(),
      cardAmount: (json['card_amount'] ?? 0).toDouble(),
      upiAmount: (json['upi_amount'] ?? 0).toDouble(),
      creditAmount: (json['credit_amount'] ?? 0).toDouble(),
      // Stock audit fields - parsed from backend (default 0 if not provided)
      openingStock: json['opening_stock'] ?? 0,
      closingStock: json['closing_stock'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'product_id': productId,
      'quantity': quantity,
      'unit_price': unitPrice,
      'total_amount': totalAmount,
      'cash_amount': cashAmount,
      'card_amount': cardAmount,
      'upi_amount': upiAmount,
      'credit_amount': creditAmount,
    };
  }

  DailySalesItem copyWith({
    String? id,
    String? productId,
    String? productName,
    String? brandName,
    String? categoryName,
    String? size,
    int? quantity,
    double? unitPrice,
    double? totalAmount,
    double? cashAmount,
    double? cardAmount,
    double? upiAmount,
    double? creditAmount,
    int? openingStock,
    int? closingStock,
  }) {
    return DailySalesItem(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      brandName: brandName ?? this.brandName,
      categoryName: categoryName ?? this.categoryName,
      size: size ?? this.size,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      totalAmount: totalAmount ?? this.totalAmount,
      cashAmount: cashAmount ?? this.cashAmount,
      cardAmount: cardAmount ?? this.cardAmount,
      upiAmount: upiAmount ?? this.upiAmount,
      creditAmount: creditAmount ?? this.creditAmount,
      openingStock: openingStock ?? this.openingStock,
      closingStock: closingStock ?? this.closingStock,
    );
  }
}

/// Request model for creating/updating daily sales record
class DailySalesRecordRequest {
  final DateTime recordDate;
  final String shopId;
  final String? salesmanId;
  final double totalSalesAmount;
  final double totalCashAmount;
  final double totalCardAmount;
  final double totalUpiAmount;
  final double totalCreditAmount;
  final String notes;
  final List<DailySalesItemRequest> items;

  // Expense tracking (NEW - Expense Table Feature)
  final double totalExpenseAmount;
  final List<ExpenseEntry> expenses;

  // Location tracking (optional - for monitoring/analytics)
  final double? latitude;
  final double? longitude;
  final String? locationAccuracy;

  // Image attachments (mandatory - uploaded to backend storage)
  final List<String> imageUrls;

  DailySalesRecordRequest({
    required this.recordDate,
    required this.shopId,
    this.salesmanId,
    required this.totalSalesAmount,
    required this.totalCashAmount,
    required this.totalCardAmount,
    required this.totalUpiAmount,
    required this.totalCreditAmount,
    this.notes = '',
    required this.items,
    // Expense fields (NEW)
    this.totalExpenseAmount = 0.0,
    this.expenses = const [],
    // Location fields (optional)
    this.latitude,
    this.longitude,
    this.locationAccuracy,
    // Image URLs (mandatory)
    this.imageUrls = const [],
  });

  Map<String, dynamic> toJson() {
    // IMPORTANT: Send record_date as UTC midnight for the LOCAL date
    // This ensures if user is on Oct 14 local time, backend stores Oct 14 (not Oct 13)
    final utcDateOnly = DateTime.utc(recordDate.year, recordDate.month, recordDate.day);

    return {
      'record_date': utcDateOnly.toIso8601String(),
      'shop_id': shopId,
      if (salesmanId != null) 'salesman_id': salesmanId,
      'total_sales_amount': totalSalesAmount,
      'total_cash_amount': totalCashAmount,
      'total_card_amount': totalCardAmount,
      'total_upi_amount': totalUpiAmount,
      'total_credit_amount': totalCreditAmount,
      // Expense data (NEW - Expense Table Feature)
      'total_expense_amount': totalExpenseAmount,
      if (expenses.isNotEmpty) 'expenses': expenses.map((e) => e.toJson()).toList(),
      'notes': notes,
      'items': items.map((item) => item.toJson()).toList(),
      // Include location only if captured (optional)
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (locationAccuracy != null) 'location_accuracy': locationAccuracy,
      // Include image URLs (mandatory for new submissions)
      if (imageUrls.isNotEmpty) 'image_urls': imageUrls,
    };
  }
}

class DailySalesItemRequest {
  final String productId;
  final int quantity;
  final double unitPrice;
  final double totalAmount;
  final double cashAmount;
  final double cardAmount;
  final double upiAmount;
  final double creditAmount;

  DailySalesItemRequest({
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    required this.totalAmount,
    this.cashAmount = 0,
    this.cardAmount = 0,
    this.upiAmount = 0,
    this.creditAmount = 0,
  });

  Map<String, dynamic> toJson() {
    return {
      'product_id': productId,
      'quantity': quantity,
      'unit_price': unitPrice,
      'total_amount': totalAmount,
      'cash_amount': cashAmount,
      'card_amount': cardAmount,
      'upi_amount': upiAmount,
      'credit_amount': creditAmount,
    };
  }
}
