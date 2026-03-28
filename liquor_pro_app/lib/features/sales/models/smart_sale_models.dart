/// Smart Sale Models
///
/// Models for AI-powered automated sales entry feature
library;

/// Result from Smart Sale processing
class SmartSaleResult {
  /// Processing status: 'success', 'partial', 'failed', 'pending'
  final String status;

  /// Human-readable message about the result
  final String message;

  /// List of items extracted from images
  final List<SmartSaleExtractedItem> extractedItems;

  /// Total sale amount calculated
  final double totalAmount;

  /// Created daily sales record ID (if successful)
  final String? saleRecordId;

  /// Validation summary
  final SmartSaleValidation? validation;

  /// Processing details (timing, confidence, etc.)
  final SmartSaleProcessingDetails? processingDetails;

  /// Error details if any
  final String? errorDetails;

  /// Image URLs uploaded to backend
  final List<String> imageUrls;

  /// Detected shop name from image header
  final String? detectedShopName;

  /// Detected size from image header (e.g., "375ML")
  final String? detectedSize;

  /// Detected size in ML (e.g., 375)
  final int? detectedSizeML;

  const SmartSaleResult({
    required this.status,
    required this.message,
    this.extractedItems = const [],
    this.totalAmount = 0.0,
    this.saleRecordId,
    this.validation,
    this.processingDetails,
    this.errorDetails,
    this.imageUrls = const [],
    this.detectedShopName,
    this.detectedSize,
    this.detectedSizeML,
  });

  factory SmartSaleResult.fromJson(Map<String, dynamic> json) {
    return SmartSaleResult(
      status: json['status'] ?? 'unknown',
      message: json['message'] ?? '',
      extractedItems: (json['extracted_items'] as List? ?? [])
          .map((item) => SmartSaleExtractedItem.fromJson(item))
          .toList(),
      totalAmount: _parseDouble(json['total_amount']),
      saleRecordId: json['sale_record_id']?.toString(),
      validation: json['validation'] != null
          ? SmartSaleValidation.fromJson(json['validation'])
          : null,
      processingDetails: json['processing_details'] != null
          ? SmartSaleProcessingDetails.fromJson(json['processing_details'])
          : null,
      errorDetails: json['error_details']?.toString(),
      imageUrls: (json['image_urls'] as List? ?? [])
          .map((url) => url.toString())
          .toList(),
      detectedShopName: json['detected_shop_name']?.toString(),
      detectedSize: json['detected_size']?.toString(),
      detectedSizeML: _parseInt(json['detected_size_ml']),
    );
  }

  /// Helper to safely parse int from dynamic (handles String, int, double, null)
  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  /// Helper to safely parse double from dynamic
  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  bool get isSuccess => status == 'success';
  bool get isPartial => status == 'partial';
  bool get isFailed => status == 'failed';
  bool get isPending => status == 'pending';

  int get validItemCount =>
      extractedItems.where((item) => item.isValid).length;
  int get invalidItemCount =>
      extractedItems.where((item) => !item.isValid).length;
}

/// Individual item extracted from receipt/invoice
class SmartSaleExtractedItem {
  /// Product ID matched from inventory
  final String? productId;

  /// Brand name extracted from image
  final String brandName;

  /// Size extracted (e.g., '180ML', '750ML')
  final String? size;

  /// Category detected ('beer' or 'non_beer')
  final String category;

  /// Quantity extracted (sale quantity)
  final int quantity;

  /// Rate/price per unit extracted
  final double rate;

  /// Total amount for this item (quantity * rate)
  final double amount;

  /// Whether this item passed validation
  final bool isValid;

  /// Validation status details
  final String validationStatus;

  /// Available stock in inventory (opening stock)
  final int? availableStock;

  /// Opening stock (same as availableStock, explicitly named)
  final int? openingStock;

  /// Receipt quantity (items received today)
  final int? receipt;

  /// Total stock (opening + receipt)
  final int? totalStock;

  /// Closing stock after sale (opening - quantity)
  final int? closingStock;

  /// Database stock (for comparison with OCR opening)
  final int? dbStock;

  /// Expected amount (rate × quantity for verification)
  final double? expectedAmount;

  /// Rate in inventory (for comparison)
  final double? inventoryRate;

  /// Confidence score from AI (0.0 to 1.0)
  final double confidence;

  /// Validation warnings (non-blocking issues like stock discrepancy)
  final List<String> warnings;

  /// Validation errors (blocking issues)
  final List<String> errors;

  /// Serial number from original receipt (if detected)
  final int? serialNumber;

  /// Original OCR text before matching (e.g., "Roford" before → "The Rockford Reserve Fine Whisky")
  final String? ocrText;

  /// Match confidence (how well the product matched, separate from OCR confidence)
  final double matchConfidence;

  /// Match status: matched, low_confidence, ambiguous, not_found
  final String matchStatus;

  /// Whether this item needs user review
  final bool needsReview;

  /// Reason for needing review
  final String? reviewReason;

  /// Whether this is a zero-quantity item
  final bool isZeroQuantity;

  /// Alternative product matches (top 3 candidates)
  final List<AlternativeMatch> alternativeMatches;

  const SmartSaleExtractedItem({
    this.productId,
    required this.brandName,
    this.size,
    required this.category,
    required this.quantity,
    required this.rate,
    required this.amount,
    this.isValid = false,
    this.validationStatus = 'unknown',
    this.availableStock,
    this.openingStock,
    this.receipt,
    this.totalStock,
    this.closingStock,
    this.dbStock,
    this.expectedAmount,
    this.inventoryRate,
    this.confidence = 0.0,
    this.warnings = const [],
    this.errors = const [],
    this.serialNumber,
    this.ocrText,
    this.matchConfidence = 0.0,
    this.matchStatus = 'unknown',
    this.needsReview = false,
    this.reviewReason,
    this.isZeroQuantity = false,
    this.alternativeMatches = const [],
  });

  factory SmartSaleExtractedItem.fromJson(Map<String, dynamic> json) {
    // DEBUG: Log raw JSON keys to see what backend returns
    // print('🔍 SmartSaleItem JSON keys: ${json.keys.toList()}');

    // Get opening stock from multiple possible fields (with safe parsing)
    final opening = _parseInt(json['opening_stock'] ?? json['available_stock'] ?? json['opening']);
    final closing = _parseInt(json['closing_stock'] ?? json['closing']);
    final qty = _parseInt(json['quantity'] ?? json['sale_qty'] ?? json['qty']) ?? 0;
    final rcpt = _parseInt(json['receipt']) ?? 0;
    final totalVal = _parseInt(json['total']);
    final total = totalVal ?? (opening != null ? opening + rcpt : null);

    // Try multiple possible field names for SYSTEM stock from database
    // Backend returns: system_opening (primary), db_stock, system_stock, etc.
    final systemStock = _parseInt(
      json['system_opening'] ??  // Primary field from backend
      json['db_stock'] ??
      json['system_stock'] ??
      json['inventory_stock'] ??
      json['database_stock'] ??
      json['current_stock'] ??
      json['db_opening'] ??
      json['actual_stock']
    );

    // Parse rates carefully:
    // - image_rate = rate extracted from OCR/image
    // - rate = could be system rate or OCR rate depending on backend
    // - system_rate = explicit system rate field
    final imageRate = _parseDoubleNullable(json['image_rate']);
    final regularRate = _parseDouble(json['rate'] ?? json['price'] ?? json['mrp']);
    // If image_rate exists, use it as OCR rate; otherwise use regular rate
    final ocrRate = imageRate ?? regularRate;

    // Normalize size: treat empty/whitespace-only strings as null
    final rawSize = json['size']?.toString().trim();
    final normalizedSize = (rawSize != null && rawSize.isNotEmpty) ? rawSize : null;

    return SmartSaleExtractedItem(
      productId: json['product_id']?.toString(),
      brandName: json['brand_name']?.toString() ?? json['name']?.toString() ?? json['brand']?.toString() ?? 'Unknown',
      size: normalizedSize,
      category: json['category']?.toString() ?? 'non_beer',
      quantity: qty,
      rate: ocrRate, // This is the OCR/image rate
      amount: _parseDouble(json['amount'] ?? json['sale_amount']),
      isValid: json['is_valid'] ?? json['valid'] ?? false,
      validationStatus: json['validation_status']?.toString() ?? json['status']?.toString() ?? 'unknown',
      availableStock: opening,
      openingStock: opening,
      receipt: rcpt,
      totalStock: total,
      closingStock: closing ?? (total != null ? total - qty : null),
      dbStock: systemStock,
      expectedAmount: _parseDoubleNullable(json['expected_amount']),
      // Try multiple possible field names for SYSTEM rate from database
      // Check each field individually and use first non-null, non-zero value
      inventoryRate: _parseSystemRate(json),
      confidence: _parseDouble(json['confidence']),
      warnings: (json['warnings'] as List? ?? [])
          .map((w) => w.toString())
          .toList(),
      errors: (json['errors'] as List? ?? [])
          .map((e) => e.toString())
          .toList(),
      serialNumber: _parseInt(json['serial_number'] ?? json['sno'] ?? json['s_no']),
      ocrText: json['ocr_text']?.toString() ?? json['ocr_brand_name']?.toString() ?? json['raw_brand_name']?.toString(),
      matchConfidence: _parseDouble(json['match_confidence']),
      matchStatus: json['match_status']?.toString() ?? json['status']?.toString() ?? 'unknown',
      needsReview: json['needs_review'] ?? false,
      reviewReason: json['review_reason']?.toString(),
      isZeroQuantity: json['is_zero_quantity'] ?? (qty == 0),
      alternativeMatches: (json['alternative_matches'] as List? ?? [])
          .map((m) => AlternativeMatch.fromJson(m as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Helper to safely parse int from dynamic (handles String, int, double, null)
  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  /// Helper to safely parse double from dynamic (returns 0.0 if null)
  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  /// Helper to safely parse nullable double from dynamic
  static double? _parseDoubleNullable(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  /// Helper to parse system rate from multiple possible field names
  /// Returns null only if all fields are null/zero/invalid
  static double? _parseSystemRate(Map<String, dynamic> json) {
    // Primary: system_rate is the main field from backend
    final systemRate = _parseDoubleNullable(json['system_rate']);
    if (systemRate != null && systemRate > 0) {
      return systemRate;
    }

    // Fallback field names
    final fieldNames = ['db_rate', 'inventory_rate', 'database_rate', 'actual_rate'];

    for (final fieldName in fieldNames) {
      final value = json[fieldName];
      if (value != null) {
        final parsed = _parseDoubleNullable(value);
        // Return if we got a valid non-zero rate
        if (parsed != null && parsed > 0) {
          return parsed;
        }
      }
    }

    // FALLBACK: If image_rate exists separately, then 'rate' might be the system rate
    // Backend pattern: image_rate=OCR, rate=system
    final imageRate = _parseDoubleNullable(json['image_rate']);
    final regularRate = _parseDoubleNullable(json['rate']);
    if (imageRate != null && imageRate > 0 && regularRate != null && regularRate > 0) {
      // If both exist and are different, 'rate' is likely the system rate
      if ((imageRate - regularRate).abs() > 0.01) {
        return regularRate;
      }
    }

    // FALLBACK 2: Calculate system rate from rate_difference
    // If backend provides rate_difference, we can calculate: system_rate = image_rate - rate_difference
    final rateDiff = _parseDoubleNullable(json['rate_difference']);
    if (rateDiff != null && imageRate != null && imageRate > 0) {
      final calculatedSystemRate = imageRate - rateDiff;
      if (calculatedSystemRate > 0) {
        return calculatedSystemRate;
      }
    }

    // FALLBACK 3: Try mrp/selling_price as system rate
    final mrp = _parseDoubleNullable(json['mrp']);
    if (mrp != null && mrp > 0) return mrp;
    final sellingPrice = _parseDoubleNullable(json['selling_price']);
    if (sellingPrice != null && sellingPrice > 0) return sellingPrice;

    return null;
  }

  /// Get calculated opening stock
  int get opening => openingStock ?? availableStock ?? 0;

  /// Get receipt quantity
  int get receiptQty => receipt ?? 0;

  /// Get total stock (opening + receipt)
  int get total => totalStock ?? (opening + receiptQty);

  /// Get calculated closing stock
  int get closing => closingStock ?? (total - quantity);

  /// Check if stock is sufficient
  bool get hasStockIssue => total < quantity;

  /// Check if rate differs from inventory
  bool get hasRateMismatch =>
      inventoryRate != null && (inventoryRate! - rate).abs() > 0.01;

  /// Check if there's a stock discrepancy (OCR opening vs DB stock)
  bool get hasStockDiscrepancy =>
      dbStock != null && openingStock != null && dbStock != openingStock;

  /// Get stock difference (OCR - DB)
  int get stockDifference =>
      (openingStock ?? 0) - (dbStock ?? openingStock ?? 0);

  /// Check if there's an amount mismatch (OCR amount vs Rate × Qty)
  bool get hasAmountMismatch =>
      expectedAmount != null && (expectedAmount! - amount).abs() > 0.01;

  /// Check if item has any warnings
  bool get hasWarnings => warnings.isNotEmpty || hasStockDiscrepancy || hasAmountMismatch;
}

/// Alternative product match candidate
class AlternativeMatch {
  final String productId;
  final String brandName;
  final double sellingPrice;
  final double confidence;

  const AlternativeMatch({
    required this.productId,
    required this.brandName,
    this.sellingPrice = 0,
    this.confidence = 0,
  });

  factory AlternativeMatch.fromJson(Map<String, dynamic> json) {
    return AlternativeMatch(
      productId: json['product_id']?.toString() ?? '',
      brandName: json['brand_name']?.toString() ?? json['name']?.toString() ?? '',
      sellingPrice: _parseDouble(json['selling_price'] ?? json['price'] ?? json['mrp']),
      confidence: _parseDouble(json['confidence'] ?? json['match_confidence']),
    );
  }

  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }
}

/// Validation summary for Smart Sale
class SmartSaleValidation {
  /// Whether the shop name on receipt matches selected shop
  final bool shopNameMatch;

  /// Expected shop name (user selected)
  final String? expectedShopName;

  /// Detected shop name from image
  final String? detectedShopName;

  /// Whether the date on receipt matches selected date
  final bool dateMatch;

  /// Expected date (user selected)
  final String? expectedDate;

  /// Detected date from image
  final String? detectedDate;

  /// Whether the size matches user-selected size
  final bool sizeMatch;

  /// Expected size (user selected)
  final String? expectedSize;

  /// Expected size in ML
  final int? expectedSizeML;

  /// Detected size from image
  final String? detectedSize;

  /// Detected size in ML
  final int? detectedSizeML;

  /// Overall validation passed
  final bool isValid;

  /// Total items extracted
  final int totalItems;

  /// Items that passed validation
  final int validItems;

  /// Items with stock discrepancies (OCR vs DB)
  final int stockDiscrepancies;

  /// Items with amount mismatches (Rate × Qty check)
  final int amountMismatches;

  /// Items with stock issues
  final int stockIssues;

  /// Items with rate mismatches
  final int rateMismatches;

  /// Items not found in inventory
  final int notFoundItems;

  /// Validation warnings (shop, date, size mismatches)
  final List<String> warnings;

  /// Validation messages
  final List<String> messages;

  const SmartSaleValidation({
    this.shopNameMatch = false,
    this.expectedShopName,
    this.detectedShopName,
    this.dateMatch = false,
    this.expectedDate,
    this.detectedDate,
    this.sizeMatch = false,
    this.expectedSize,
    this.expectedSizeML,
    this.detectedSize,
    this.detectedSizeML,
    this.isValid = false,
    this.totalItems = 0,
    this.validItems = 0,
    this.stockDiscrepancies = 0,
    this.amountMismatches = 0,
    this.stockIssues = 0,
    this.rateMismatches = 0,
    this.notFoundItems = 0,
    this.warnings = const [],
    this.messages = const [],
  });

  factory SmartSaleValidation.fromJson(Map<String, dynamic> json) {
    return SmartSaleValidation(
      shopNameMatch: json['shop_name_match'] ?? false,
      expectedShopName: json['expected_shop_name']?.toString(),
      detectedShopName: json['detected_shop_name']?.toString(),
      dateMatch: json['date_match'] ?? false,
      expectedDate: json['expected_date']?.toString(),
      detectedDate: json['detected_date']?.toString(),
      sizeMatch: json['size_match'] ?? false,
      expectedSize: json['expected_size']?.toString(),
      expectedSizeML: _parseInt(json['expected_size_ml']),
      detectedSize: json['detected_size']?.toString(),
      detectedSizeML: _parseInt(json['detected_size_ml']),
      isValid: json['is_valid'] ?? false,
      totalItems: _parseInt(json['total_items']) ?? 0,
      validItems: _parseInt(json['valid_items']) ?? 0,
      stockDiscrepancies: _parseInt(json['stock_discrepancies']) ?? 0,
      amountMismatches: _parseInt(json['amount_mismatches']) ?? 0,
      stockIssues: _parseInt(json['stock_issues']) ?? 0,
      rateMismatches: _parseInt(json['rate_mismatches']) ?? 0,
      notFoundItems: _parseInt(json['not_found_items']) ?? 0,
      warnings: (json['warnings'] as List? ?? [])
          .map((w) => w.toString())
          .toList(),
      messages: (json['messages'] as List? ?? [])
          .map((m) => m.toString())
          .toList(),
    );
  }

  /// Helper to safely parse int from dynamic
  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  /// Check if there are any validation warnings
  bool get hasWarnings => warnings.isNotEmpty || !shopNameMatch || !dateMatch || !sizeMatch;
}

/// Processing details for Smart Sale
class SmartSaleProcessingDetails {
  /// Time taken for OCR processing (milliseconds)
  final int ocrTimeMs;

  /// Time taken for validation (milliseconds)
  final int validationTimeMs;

  /// Time taken for sale creation (milliseconds)
  final int creationTimeMs;

  /// Total processing time (milliseconds)
  final int totalTimeMs;

  /// Number of images processed
  final int imagesProcessed;

  /// AI model used for OCR
  final String? aiModel;

  /// Average confidence score
  final double avgConfidence;

  const SmartSaleProcessingDetails({
    this.ocrTimeMs = 0,
    this.validationTimeMs = 0,
    this.creationTimeMs = 0,
    this.totalTimeMs = 0,
    this.imagesProcessed = 0,
    this.aiModel,
    this.avgConfidence = 0.0,
  });

  factory SmartSaleProcessingDetails.fromJson(Map<String, dynamic> json) {
    return SmartSaleProcessingDetails(
      ocrTimeMs: _parseInt(json['ocr_time_ms']) ?? 0,
      validationTimeMs: _parseInt(json['validation_time_ms']) ?? 0,
      creationTimeMs: _parseInt(json['creation_time_ms']) ?? 0,
      totalTimeMs: _parseInt(json['total_time_ms']) ?? 0,
      imagesProcessed: _parseInt(json['images_processed']) ?? 0,
      aiModel: json['ai_model']?.toString(),
      avgConfidence: _parseDouble(json['avg_confidence']),
    );
  }

  /// Helper to safely parse int from dynamic
  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  /// Helper to safely parse double from dynamic
  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }
}

/// Smart Sale history record
class SmartSaleRecord {
  final String id;
  final String shopId;
  final String shopName;
  final DateTime date;
  final String category;
  final String? size;
  final String status;
  final double totalAmount;
  final int itemCount;
  final String? saleRecordId;
  final DateTime createdAt;
  final List<String> imageUrls;

  const SmartSaleRecord({
    required this.id,
    required this.shopId,
    required this.shopName,
    required this.date,
    required this.category,
    this.size,
    required this.status,
    this.totalAmount = 0.0,
    this.itemCount = 0,
    this.saleRecordId,
    required this.createdAt,
    this.imageUrls = const [],
  });

  factory SmartSaleRecord.fromJson(Map<String, dynamic> json) {
    return SmartSaleRecord(
      id: json['id']?.toString() ?? '',
      shopId: json['shop_id']?.toString() ?? '',
      shopName: json['shop_name']?.toString() ?? '',
      date: DateTime.tryParse(json['date']?.toString() ?? '') ?? DateTime.now(),
      category: json['category']?.toString() ?? 'non_beer',
      size: json['size']?.toString(),
      status: json['status']?.toString() ?? 'unknown',
      totalAmount: _parseDouble(json['total_amount']),
      itemCount: _parseInt(json['item_count']) ?? 0,
      saleRecordId: json['sale_record_id']?.toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
      imageUrls: (json['image_urls'] as List? ?? [])
          .map((url) => url.toString())
          .toList(),
    );
  }

  /// Helper to safely parse int from dynamic
  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  /// Helper to safely parse double from dynamic
  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }
}
