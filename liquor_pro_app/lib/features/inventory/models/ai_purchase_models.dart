// Models for the Smart AI Purchase flow.
// Maps to the backend response from POST /api/inventory/purchases/smart-purchase/extract

/// Top-level result from the smart purchase extraction endpoint.
class SmartPurchaseResult {
  final String status; // success, partial, failed
  final String message;
  final DetectedVendor? detectedVendor;
  final String? invoiceNumber;
  final String? invoiceDate;
  final String? matchedVendorId;
  final String? matchedVendorName;
  final double vendorConfidence;
  final List<SmartPurchaseItem> items;
  final double subTotal;
  final double taxAmount;
  final double totalAmount;
  final SmartPurchaseProcessingDetails? processingDetails;
  final SmartPurchaseValidation? validation;

  const SmartPurchaseResult({
    required this.status,
    required this.message,
    this.detectedVendor,
    this.invoiceNumber,
    this.invoiceDate,
    this.matchedVendorId,
    this.matchedVendorName,
    this.vendorConfidence = 0.0,
    this.items = const [],
    this.subTotal = 0.0,
    this.taxAmount = 0.0,
    this.totalAmount = 0.0,
    this.processingDetails,
    this.validation,
  });

  factory SmartPurchaseResult.fromJson(Map<String, dynamic> json) {
    return SmartPurchaseResult(
      status: json['status'] ?? 'unknown',
      message: json['message'] ?? '',
      detectedVendor: json['detected_vendor'] != null
          ? DetectedVendor.fromJson(json['detected_vendor'])
          : null,
      invoiceNumber: json['invoice_number']?.toString(),
      invoiceDate: json['invoice_date']?.toString(),
      matchedVendorId: json['matched_vendor_id']?.toString(),
      matchedVendorName: json['matched_vendor_name']?.toString(),
      vendorConfidence: _parseDouble(json['vendor_confidence']),
      items: (json['items'] as List? ?? [])
          .map((e) => SmartPurchaseItem.fromJson(e))
          .toList(),
      subTotal: _parseDouble(json['sub_total']),
      taxAmount: _parseDouble(json['tax_amount']),
      totalAmount: _parseDouble(json['total_amount']),
      processingDetails: json['processing_details'] != null
          ? SmartPurchaseProcessingDetails.fromJson(json['processing_details'])
          : null,
      validation: json['validation'] != null
          ? SmartPurchaseValidation.fromJson(json['validation'])
          : null,
    );
  }

  bool get isSuccess => status == 'success';
  bool get isPartial => status == 'partial';
  bool get isFailed => status == 'failed';
}

/// A single item extracted from the purchase invoice.
class SmartPurchaseItem {
  final int rowNumber;
  final String brandName;
  final String size;
  final int sizeMl;
  final String category;
  final int quantityRaw;
  final String quantityUnit; // 'cases', 'bottles'
  final int bottlesPerCase;
  final int quantityBottles;
  final double ratePerBottle;
  final double ratePerCase;
  final double amount;
  final String? batchNumber;

  // Matching
  final String? productId;
  final String? matchedBrandName;
  final double matchConfidence;
  final String status; // matched, low_confidence, ambiguous, not_found
  final List<AlternativeMatch> alternativeMatches;
  final List<String> warnings;

  // Inventory context
  final double? dbCostPrice;
  final int? currentStock;

  // Gate pass duty (excise duty included in buying price — for compliance logging)
  final double dutyFee;
  final double dutyPerBottle;

  // User resolution state (frontend-only, not from backend)
  int userSelectedIndex; // -1 = not yet selected
  bool userSkipped;

  // User edit overrides (frontend-only, not from backend)
  double? userCostPrice;    // Override for ratePerBottle
  double? userDutyFee;      // Override for dutyPerBottle
  int? userQuantity;        // Override for quantityBottles

  // Receiving issues (frontend-only, tracked for audit)
  int userLeakage;          // Bottles damaged/leaked during transport
  int userShortReceived;    // Bottles short received vs invoice

  SmartPurchaseItem({
    this.rowNumber = 0,
    required this.brandName,
    required this.size,
    this.sizeMl = 0,
    this.category = '',
    this.quantityRaw = 0,
    this.quantityUnit = 'bottles',
    this.bottlesPerCase = 1,
    this.quantityBottles = 0,
    this.ratePerBottle = 0.0,
    this.ratePerCase = 0.0,
    this.amount = 0.0,
    this.batchNumber,
    this.productId,
    this.matchedBrandName,
    this.matchConfidence = 0.0,
    this.status = 'not_found',
    this.alternativeMatches = const [],
    this.warnings = const [],
    this.dbCostPrice,
    this.currentStock,
    this.dutyFee = 0.0,
    this.dutyPerBottle = 0.0,
    this.userSelectedIndex = -1,
    this.userSkipped = false,
    this.userCostPrice,
    this.userDutyFee,
    this.userQuantity,
    this.userLeakage = 0,
    this.userShortReceived = 0,
  });

  factory SmartPurchaseItem.fromJson(Map<String, dynamic> json) {
    return SmartPurchaseItem(
      rowNumber: _parseInt(json['row_number']) ?? 0,
      brandName: json['brand_name']?.toString() ?? 'Unknown',
      size: json['size']?.toString() ?? '',
      sizeMl: _parseInt(json['size_ml']) ?? 0,
      category: json['category']?.toString() ?? '',
      quantityRaw: _parseInt(json['quantity_raw']) ?? 0,
      quantityUnit: json['quantity_unit']?.toString() ?? 'bottles',
      bottlesPerCase: _parseInt(json['bottles_per_case']) ?? 1,
      quantityBottles: _parseInt(json['quantity_bottles']) ?? _parseInt(json['quantity']) ?? 0,
      ratePerBottle: _parseDouble(json['rate_per_bottle']),
      ratePerCase: _parseDouble(json['rate_per_case']),
      amount: _parseDouble(json['amount']),
      batchNumber: json['batch_number']?.toString(),
      productId: json['product_id']?.toString(),
      matchedBrandName: json['matched_brand_name']?.toString(),
      matchConfidence: _parseDouble(json['match_confidence']),
      status: json['status']?.toString() ?? 'not_found',
      alternativeMatches: (json['alternative_matches'] as List? ?? [])
          .map((e) => AlternativeMatch.fromJson(e))
          .toList(),
      warnings: (json['warnings'] as List? ?? [])
          .map((w) => w.toString())
          .toList(),
      dbCostPrice: _parseDoubleNullable(json['db_cost_price']),
      currentStock: _parseInt(json['current_stock']),
      dutyFee: _parseDouble(json['duty_fee']),
      dutyPerBottle: _parseDouble(json['duty_per_bottle']),
    );
  }

  /// Whether this item is confidently matched (safe to auto-fill).
  bool get isMatched => status == 'matched';

  /// Whether this item needs user review.
  bool get needsReview => status == 'low_confidence' || status == 'ambiguous';

  /// Whether this item has no match at all.
  bool get isNotFound => status == 'not_found';

  /// Whether the user has resolved this item (selected or skipped).
  bool get isResolved => userSelectedIndex >= 0 || userSkipped;

  /// The resolved product ID — user-selected alternative or the backend match.
  String? get resolvedProductId {
    if (userSkipped) return null;
    if (userSelectedIndex >= 0 && userSelectedIndex < alternativeMatches.length) {
      return alternativeMatches[userSelectedIndex].productId;
    }
    return productId;
  }

  /// The resolved brand name for display.
  String get resolvedBrandName {
    if (userSkipped) return brandName;
    if (userSelectedIndex >= 0 && userSelectedIndex < alternativeMatches.length) {
      return alternativeMatches[userSelectedIndex].brandName;
    }
    return matchedBrandName ?? brandName;
  }

  /// Whether rate differs from DB cost price.
  bool get hasRateMismatch {
    if (dbCostPrice == null || dbCostPrice == 0 || ratePerBottle == 0) return false;
    final diff = (ratePerBottle - dbCostPrice!).abs();
    return (diff / dbCostPrice!) > 0.01;
  }

  /// Whether matched brand name differs from invoice brand name.
  bool get hasNameMismatch {
    if (matchedBrandName == null) return false;
    final invoiceLower = brandName.toLowerCase().replaceAll(RegExp(r'[\s\-]+'), '');
    final matchedLower = matchedBrandName!.toLowerCase().replaceAll(RegExp(r'[\s\-]+'), '');
    return !matchedLower.contains(invoiceLower) && !invoiceLower.contains(matchedLower);
  }

  /// Effective cost price — user override or AI-extracted rate
  double get effectiveCostPrice => userCostPrice ?? ratePerBottle;

  /// Effective duty fee — user override or gate pass duty
  double get effectiveDutyFee => userDutyFee ?? dutyPerBottle;

  /// Effective quantity in bottles — user override or AI-extracted
  int get effectiveQuantity => userQuantity ?? quantityBottles;

  /// Net receivable quantity — after deducting leakage and short receiving
  int get netReceivableQuantity => effectiveQuantity - userLeakage - userShortReceived;

  /// Whether there are receiving issues
  bool get hasReceivingIssues => userLeakage > 0 || userShortReceived > 0;
}

/// An alternative product match suggested by the backend.
class AlternativeMatch {
  final String productId;
  final String brandName;
  final String size;
  final double costPrice;
  final double confidence;
  final int? currentStock;

  const AlternativeMatch({
    required this.productId,
    required this.brandName,
    this.size = '',
    this.costPrice = 0.0,
    this.confidence = 0.0,
    this.currentStock,
  });

  factory AlternativeMatch.fromJson(Map<String, dynamic> json) {
    return AlternativeMatch(
      productId: json['product_id']?.toString() ?? '',
      brandName: json['brand_name']?.toString() ?? '',
      size: json['size']?.toString() ?? '',
      costPrice: _parseDouble(json['cost_price']),
      confidence: _parseDouble(json['confidence']),
      currentStock: _parseInt(json['current_stock']),
    );
  }
}

/// Vendor detected from the invoice.
class DetectedVendor {
  final String name;
  final String? gstNumber;
  final String? address;

  const DetectedVendor({
    required this.name,
    this.gstNumber,
    this.address,
  });

  factory DetectedVendor.fromJson(Map<String, dynamic> json) {
    return DetectedVendor(
      name: json['name']?.toString() ?? '',
      gstNumber: json['gst_number']?.toString(),
      address: json['address']?.toString(),
    );
  }
}

/// Processing timing details.
class SmartPurchaseProcessingDetails {
  final int ocrTimeMs;
  final int matchingTimeMs;
  final int totalTimeMs;
  final int imagesProcessed;
  final String? aiModel;

  const SmartPurchaseProcessingDetails({
    this.ocrTimeMs = 0,
    this.matchingTimeMs = 0,
    this.totalTimeMs = 0,
    this.imagesProcessed = 0,
    this.aiModel,
  });

  factory SmartPurchaseProcessingDetails.fromJson(Map<String, dynamic> json) {
    return SmartPurchaseProcessingDetails(
      ocrTimeMs: _parseInt(json['ocr_time_ms']) ?? 0,
      matchingTimeMs: _parseInt(json['matching_time_ms']) ?? 0,
      totalTimeMs: _parseInt(json['total_time_ms']) ?? 0,
      imagesProcessed: _parseInt(json['images_processed']) ?? 0,
      aiModel: json['ai_model']?.toString(),
    );
  }
}

/// Validation summary.
class SmartPurchaseValidation {
  final int totalItems;
  final int matchedItems;
  final int lowConfidenceItems;
  final int notFoundItems;
  final List<String> warnings;

  const SmartPurchaseValidation({
    this.totalItems = 0,
    this.matchedItems = 0,
    this.lowConfidenceItems = 0,
    this.notFoundItems = 0,
    this.warnings = const [],
  });

  factory SmartPurchaseValidation.fromJson(Map<String, dynamic> json) {
    return SmartPurchaseValidation(
      totalItems: _parseInt(json['total_items']) ?? 0,
      matchedItems: _parseInt(json['matched_items']) ?? 0,
      lowConfidenceItems: _parseInt(json['low_confidence_items']) ?? 0,
      notFoundItems: _parseInt(json['not_found_items']) ?? 0,
      warnings: (json['warnings'] as List? ?? [])
          .map((w) => w.toString())
          .toList(),
    );
  }
}

/// Metadata passed to PurchaseEntryScreen for AI-filled items.
class AIPurchaseItemMeta {
  final double confidence;
  final double aiRate;
  final String aiBrandName;
  final String aiSize;
  final int quantityBottles;
  final String quantityUnit;
  final int bottlesPerCase;
  final double dutyFee; // Excise duty per bottle
  final int leakage;       // Bottles leaked/damaged
  final int shortReceived; // Bottles short received
  final List<String> warnings;

  const AIPurchaseItemMeta({
    required this.confidence,
    required this.aiRate,
    required this.aiBrandName,
    required this.aiSize,
    this.quantityBottles = 0,
    this.quantityUnit = 'bottles',
    this.bottlesPerCase = 1,
    this.dutyFee = 0.0,
    this.leakage = 0,
    this.shortReceived = 0,
    this.warnings = const [],
  });
}

// ── Shared parse helpers ──

int? _parseInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

double _parseDouble(dynamic value) {
  if (value == null) return 0.0;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0.0;
  return 0.0;
}

double? _parseDoubleNullable(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}
