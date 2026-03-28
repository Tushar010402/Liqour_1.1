// Models for the Smart AI Stock Setup flow.
// Maps to the backend response from POST /api/inventory/stocks/smart-setup/extract

/// Top-level result from the smart stock setup extraction endpoint.
class SmartStockResult {
  final String status; // success, partial, failed
  final String message;
  final List<SmartStockItem> items;
  final SmartStockProcessingDetails? processingDetails;
  final SmartStockValidation? validation;
  final String? detectedShopName;
  final String? stockColumn; // "opening", "total", "closing"
  final String? suggestedStockColumn;
  final StockSetupFilterContext? filterContext;
  final List<StockSetupProductInfo> allProducts;

  const SmartStockResult({
    required this.status,
    required this.message,
    this.items = const [],
    this.processingDetails,
    this.validation,
    this.detectedShopName,
    this.stockColumn,
    this.suggestedStockColumn,
    this.filterContext,
    this.allProducts = const [],
  });

  factory SmartStockResult.fromJson(Map<String, dynamic> json) {
    return SmartStockResult(
      status: json['status'] ?? 'unknown',
      message: json['message'] ?? '',
      items: (json['items'] as List? ?? [])
          .map((e) => SmartStockItem.fromJson(e))
          .toList(),
      processingDetails: json['processing_details'] != null
          ? SmartStockProcessingDetails.fromJson(json['processing_details'])
          : null,
      validation: json['validation'] != null
          ? SmartStockValidation.fromJson(json['validation'])
          : null,
      detectedShopName: json['detected_shop_name']?.toString(),
      stockColumn: json['stock_column']?.toString(),
      suggestedStockColumn: json['suggested_stock_column']?.toString(),
      filterContext: json['filter_context'] != null
          ? StockSetupFilterContext.fromJson(json['filter_context'])
          : null,
      allProducts: (json['all_products'] as List? ?? [])
          .map((e) => StockSetupProductInfo.fromJson(e))
          .toList(),
    );
  }

  bool get isSuccess => status == 'success';
  bool get isPartial => status == 'partial';
  bool get isFailed => status == 'failed';
}

/// A single item extracted from the stock register.
class SmartStockItem {
  final int rowNumber;
  final String brandName;
  final String size;
  final int sizeMl;
  final String category;

  // Register values (all columns from the stock register)
  final int opening;
  final int receipt;
  final int total;
  final int sale;
  final int closingStock;
  int stockQuantity; // The selected stock value (mutable — changes with column selection)
  final double rate;
  final double amount;

  // Matching
  final String? productId;
  final String? matchedBrandName;
  final double matchConfidence;
  final String status; // matched, low_confidence, ambiguous, not_found
  final List<StockAlternativeMatch> alternativeMatches;
  final List<String> warnings;

  // Official brand (AI-identified canonical name)
  final String? officialBrandName;

  // Auto-creation
  final bool autoCreated;
  final String? createdBrandId;
  final String? createdProductId;
  final String creationStatus; // "created", "existing_brand_new_product", ""

  // Review flags (from backend)
  final bool needsReviewFlag; // backend needs_review field
  final String? reviewReason; // backend review_reason field

  // Inventory context
  final int? currentStock;

  // User resolution state (frontend-only)
  int userSelectedIndex;
  bool userSkipped;

  SmartStockItem({
    this.rowNumber = 0,
    required this.brandName,
    required this.size,
    this.sizeMl = 0,
    this.category = '',
    this.opening = 0,
    this.receipt = 0,
    this.total = 0,
    this.sale = 0,
    this.closingStock = 0,
    this.stockQuantity = 0,
    this.rate = 0.0,
    this.amount = 0.0,
    this.productId,
    this.matchedBrandName,
    this.matchConfidence = 0.0,
    this.status = 'not_found',
    this.alternativeMatches = const [],
    this.warnings = const [],
    this.officialBrandName,
    this.autoCreated = false,
    this.createdBrandId,
    this.createdProductId,
    this.creationStatus = '',
    this.needsReviewFlag = false,
    this.reviewReason,
    this.currentStock,
    this.userSelectedIndex = -1,
    this.userSkipped = false,
  });

  factory SmartStockItem.fromJson(Map<String, dynamic> json) {
    // stock_quantity with fallback to quantity_bottles or quantity
    final stockQty = _parseInt(json['stock_quantity'])
        ?? _parseInt(json['quantity_bottles'])
        ?? _parseInt(json['quantity'])
        ?? 0;

    return SmartStockItem(
      rowNumber: _parseInt(json['row_number']) ?? 0,
      brandName: json['brand_name']?.toString() ?? 'Unknown',
      size: json['size']?.toString() ?? '',
      sizeMl: _parseInt(json['size_ml']) ?? 0,
      category: json['category']?.toString() ?? '',
      opening: _parseInt(json['opening']) ?? 0,
      receipt: _parseInt(json['receipt']) ?? 0,
      total: _parseInt(json['total']) ?? 0,
      sale: _parseInt(json['sale']) ?? 0,
      closingStock: _parseInt(json['closing_stock']) ?? 0,
      stockQuantity: stockQty,
      rate: _parseDouble(json['rate']),
      amount: _parseDouble(json['amount']),
      productId: json['product_id']?.toString(),
      matchedBrandName: json['matched_brand_name']?.toString(),
      matchConfidence: _parseDouble(json['match_confidence']),
      status: json['status']?.toString() ?? 'not_found',
      alternativeMatches: (json['alternative_matches'] as List? ?? [])
          .map((e) => StockAlternativeMatch.fromJson(e))
          .toList(),
      warnings: (json['warnings'] as List? ?? [])
          .map((w) => w.toString())
          .toList(),
      officialBrandName: json['official_brand_name']?.toString(),
      autoCreated: json['auto_created'] == true,
      createdBrandId: json['created_brand_id']?.toString(),
      createdProductId: json['created_product_id']?.toString(),
      creationStatus: json['creation_status']?.toString() ?? '',
      needsReviewFlag: json['needs_review'] == true,
      reviewReason: json['review_reason']?.toString(),
      currentStock: _parseInt(json['current_stock']),
    );
  }

  /// Legacy: quantity getter for backward compat
  int get quantity => stockQuantity;

  /// Whether this item is confidently matched.
  bool get isMatched => status == 'matched';

  /// Whether this item needs user review.
  bool get needsReview => needsReviewFlag || status == 'low_confidence' || status == 'ambiguous';

  /// Whether this item has no match at all.
  bool get isNotFound => status == 'not_found';

  /// Whether the user has resolved this item (selected or skipped).
  bool get isResolved => userSelectedIndex >= 0 || userSkipped;

  /// Display name — prefer official brand name, then matched, then raw
  String get displayName => officialBrandName ?? matchedBrandName ?? brandName;

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

  /// Whether existing stock will be overwritten.
  bool get hasExistingStock => (currentStock ?? 0) > 0;

  /// Get stock value for a given column
  int getStockForColumn(String column) {
    switch (column) {
      case 'opening': return opening;
      case 'closing': return closingStock;
      case 'total':
      default: return total > 0 ? total : opening;
    }
  }
}

/// An alternative product match suggested by the backend.
class StockAlternativeMatch {
  final String productId;
  final String brandName;
  final String size;
  final double confidence;
  final int? currentStock;

  const StockAlternativeMatch({
    required this.productId,
    required this.brandName,
    this.size = '',
    this.confidence = 0.0,
    this.currentStock,
  });

  factory StockAlternativeMatch.fromJson(Map<String, dynamic> json) {
    return StockAlternativeMatch(
      productId: json['product_id']?.toString() ?? '',
      brandName: json['brand_name']?.toString() ?? '',
      size: json['size']?.toString() ?? '',
      confidence: _parseDouble(json['confidence']),
      currentStock: _parseInt(json['current_stock']),
    );
  }
}

/// Processing timing details.
class SmartStockProcessingDetails {
  final int ocrTimeMs;
  final int matchingTimeMs;
  final int totalTimeMs;
  final int imagesProcessed;
  final String? aiModel;

  const SmartStockProcessingDetails({
    this.ocrTimeMs = 0,
    this.matchingTimeMs = 0,
    this.totalTimeMs = 0,
    this.imagesProcessed = 0,
    this.aiModel,
  });

  factory SmartStockProcessingDetails.fromJson(Map<String, dynamic> json) {
    return SmartStockProcessingDetails(
      ocrTimeMs: _parseInt(json['ocr_time_ms']) ?? 0,
      matchingTimeMs: _parseInt(json['matching_time_ms']) ?? 0,
      totalTimeMs: _parseInt(json['total_time_ms']) ?? 0,
      imagesProcessed: _parseInt(json['images_processed']) ?? 0,
      aiModel: json['ai_model']?.toString(),
    );
  }

  String get formattedTime {
    final secs = (totalTimeMs / 1000).toStringAsFixed(1);
    return '${secs}s';
  }
}

/// Validation summary.
class SmartStockValidation {
  final int totalItems;
  final int matchedItems;
  final int lowConfidenceItems;
  final int notFoundItems;
  final int autoCreatedItems;
  final List<String> warnings;

  const SmartStockValidation({
    this.totalItems = 0,
    this.matchedItems = 0,
    this.lowConfidenceItems = 0,
    this.notFoundItems = 0,
    this.autoCreatedItems = 0,
    this.warnings = const [],
  });

  factory SmartStockValidation.fromJson(Map<String, dynamic> json) {
    return SmartStockValidation(
      totalItems: _parseInt(json['total_items']) ?? 0,
      matchedItems: _parseInt(json['matched_items']) ?? 0,
      lowConfidenceItems: _parseInt(json['low_confidence_items']) ?? 0,
      notFoundItems: _parseInt(json['not_found_items']) ?? 0,
      autoCreatedItems: _parseInt(json['auto_created_items']) ?? 0,
      warnings: (json['warnings'] as List? ?? [])
          .map((w) => w.toString())
          .toList(),
    );
  }
}

/// Filter context — scope info returned when category_id + size were sent.
class StockSetupFilterContext {
  final String? categoryId;
  final String? categoryName;
  final String? size;
  final int? sizeMl;
  final int? productCount;

  const StockSetupFilterContext({
    this.categoryId,
    this.categoryName,
    this.size,
    this.sizeMl,
    this.productCount,
  });

  factory StockSetupFilterContext.fromJson(Map<String, dynamic> json) {
    return StockSetupFilterContext(
      categoryId: json['category_id']?.toString(),
      categoryName: json['category_name']?.toString(),
      size: json['size']?.toString(),
      sizeMl: _parseInt(json['size_ml']),
      productCount: _parseInt(json['product_count']),
    );
  }
}

/// Product info from the all_products array — complete product list for the scope.
class StockSetupProductInfo {
  final String productId;
  final String name;
  final String brandName;
  final String size;
  final int sizeMl;
  final double mrp;
  final int currentStock;

  const StockSetupProductInfo({
    required this.productId,
    required this.name,
    this.brandName = '',
    this.size = '',
    this.sizeMl = 0,
    this.mrp = 0.0,
    this.currentStock = 0,
  });

  factory StockSetupProductInfo.fromJson(Map<String, dynamic> json) {
    return StockSetupProductInfo(
      productId: json['product_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      brandName: json['brand_name']?.toString() ?? '',
      size: json['size']?.toString() ?? '',
      sizeMl: _parseInt(json['size_ml']) ?? 0,
      mrp: _parseDouble(json['mrp']),
      currentStock: _parseInt(json['current_stock']) ?? 0,
    );
  }
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
