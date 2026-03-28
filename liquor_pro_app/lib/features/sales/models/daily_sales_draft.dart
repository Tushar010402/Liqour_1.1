/// Daily Sales Draft Model
/// Persists form state to prevent data loss on navigation/app restart
///
/// Storage Strategy: Hive-based local persistence
/// Scope: Per shop + date combination (separate drafts per shop/date)
/// TTL: 3 days (auto-cleanup on app start)
///
/// Used by: DailySalesDraftService + DailySalesProvider
library;

import '../../../core/utils/date_time_helper.dart';

/// Complete product item for draft persistence
/// Stores ALL product details needed for full UI restoration
class DraftProductItem {
  final String productId;
  final String productName;
  final String brandName;
  final String categoryName;
  final String subcategoryName;
  final String size;
  final int quantity;
  final double unitPrice;
  final double mrp;
  final double totalAmount;

  const DraftProductItem({
    required this.productId,
    required this.productName,
    required this.brandName,
    required this.categoryName,
    this.subcategoryName = '',
    required this.size,
    required this.quantity,
    required this.unitPrice,
    required this.mrp,
    required this.totalAmount,
  });

  /// JSON serialization for Hive storage
  Map<String, dynamic> toJson() {
    return {
      'productId': productId,
      'productName': productName,
      'brandName': brandName,
      'categoryName': categoryName,
      'subcategoryName': subcategoryName,
      'size': size,
      'quantity': quantity,
      'unitPrice': unitPrice,
      'mrp': mrp,
      'totalAmount': totalAmount,
    };
  }

  /// JSON deserialization from Hive storage
  factory DraftProductItem.fromJson(Map<String, dynamic> json) {
    return DraftProductItem(
      productId: json['productId'] ?? '',
      productName: json['productName'] ?? '',
      brandName: json['brandName'] ?? '',
      categoryName: json['categoryName'] ?? '',
      subcategoryName: json['subcategoryName'] ?? '',
      size: json['size'] ?? '',
      quantity: json['quantity'] ?? 0,
      unitPrice: (json['unitPrice'] ?? 0).toDouble(),
      mrp: (json['mrp'] ?? 0).toDouble(),
      totalAmount: (json['totalAmount'] ?? 0).toDouble(),
    );
  }

  /// Create copy with updated quantity
  DraftProductItem copyWith({
    String? productId,
    String? productName,
    String? brandName,
    String? categoryName,
    String? subcategoryName,
    String? size,
    int? quantity,
    double? unitPrice,
    double? mrp,
    double? totalAmount,
  }) {
    return DraftProductItem(
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      brandName: brandName ?? this.brandName,
      categoryName: categoryName ?? this.categoryName,
      subcategoryName: subcategoryName ?? this.subcategoryName,
      size: size ?? this.size,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      mrp: mrp ?? this.mrp,
      totalAmount: totalAmount ?? this.totalAmount,
    );
  }

  @override
  String toString() {
    return 'DraftProductItem($brandName $productName $size x$quantity = ₹$totalAmount)';
  }
}

class DailySalesDraft {
  /// Map of product ID to quantity (legacy - kept for backward compatibility)
  final Map<String, int> productQuantities;

  /// Complete product items with all details (NEW - for full UI restoration)
  /// This is the primary source of truth for product data
  final List<DraftProductItem> productItems;

  /// Payment breakdown
  final double cashAmount;
  final double cardAmount;
  final double upiAmount;
  final double creditAmount;
  final double expenseAmount;

  /// Expense breakdown by header (NEW - Expense Table Feature)
  final Map<String, double> expenses;

  /// Form fields
  final String notes;
  final DateTime recordDate;
  final String shopId;

  /// UI state
  final int currentStep; // 0 = Products, 1 = Payment
  final String searchQuery;
  final String? selectedCategoryName;
  final String? selectedSubcategoryName;
  final String? selectedSize; // NEW: Size filter state for restoration

  /// Metadata
  final DateTime savedAt;
  final int version; // For future schema migrations

  const DailySalesDraft({
    required this.productQuantities,
    this.productItems = const [],
    required this.cashAmount,
    required this.cardAmount,
    required this.upiAmount,
    required this.creditAmount,
    required this.expenseAmount,
    this.expenses = const {},
    required this.notes,
    required this.recordDate,
    required this.shopId,
    required this.currentStep,
    this.searchQuery = '',
    this.selectedCategoryName,
    this.selectedSubcategoryName,
    this.selectedSize,
    required this.savedAt,
    this.version = 3, // Bumped version for selectedSize field
  });

  /// Create empty draft
  factory DailySalesDraft.empty({
    required String shopId,
    required DateTime recordDate,
  }) {
    return DailySalesDraft(
      productQuantities: {},
      cashAmount: 0,
      cardAmount: 0,
      upiAmount: 0,
      creditAmount: 0,
      expenseAmount: 0,
      notes: '',
      recordDate: recordDate,
      shopId: shopId,
      currentStep: 0,
      savedAt: DateTime.now(),
    );
  }

  /// Check if draft has any data
  bool get isEmpty {
    return productQuantities.isEmpty &&
        productItems.isEmpty &&
        cashAmount == 0 &&
        cardAmount == 0 &&
        upiAmount == 0 &&
        creditAmount == 0 &&
        expenseAmount == 0 &&
        notes.trim().isEmpty;
  }

  /// Check if draft has any data
  bool get isNotEmpty => !isEmpty;

  /// Total number of products with quantities
  /// Prefers productItems (new format) over productQuantities (legacy)
  int get productCount => productItems.isNotEmpty ? productItems.length : productQuantities.length;

  /// Total products amount from productItems (if available)
  double get totalProductsAmount => productItems.fold(0.0, (sum, item) => sum + item.totalAmount);

  /// Total payment amount
  double get totalPayment => cashAmount + cardAmount + upiAmount + creditAmount;

  /// Age of draft
  Duration get age => DateTime.now().difference(savedAt);

  /// Human-readable age (e.g., "5 mins ago")
  String get ageText {
    final minutes = age.inMinutes;
    if (minutes < 1) return 'just now';
    if (minutes == 1) return '1 min ago';
    if (minutes < 60) return '$minutes mins ago';

    final hours = age.inHours;
    if (hours == 1) return '1 hour ago';
    if (hours < 24) return '$hours hours ago';

    final days = age.inDays;
    if (days == 1) return '1 day ago';
    return '$days days ago';
  }

  /// JSON serialization for Hive storage
  Map<String, dynamic> toJson() {
    return {
      'productQuantities': productQuantities,
      'productItems': productItems.map((item) => item.toJson()).toList(),
      'cashAmount': cashAmount,
      'cardAmount': cardAmount,
      'upiAmount': upiAmount,
      'creditAmount': creditAmount,
      'expenseAmount': expenseAmount,
      'expenses': expenses,
      'notes': notes,
      'recordDate': recordDate.toIso8601String(),
      'shopId': shopId,
      'currentStep': currentStep,
      'searchQuery': searchQuery,
      'selectedCategoryName': selectedCategoryName,
      'selectedSubcategoryName': selectedSubcategoryName,
      'selectedSize': selectedSize,
      'savedAt': savedAt.toIso8601String(),
      'version': version,
    };
  }

  /// JSON deserialization from Hive storage
  factory DailySalesDraft.fromJson(Map<String, dynamic> json) {
    // Parse expenses map with proper type conversion
    Map<String, double> expensesMap = {};
    if (json['expenses'] != null) {
      final rawExpenses = json['expenses'] as Map<String, dynamic>;
      rawExpenses.forEach((key, value) {
        expensesMap[key] = (value as num).toDouble();
      });
    }

    // Parse productItems list (new format)
    List<DraftProductItem> productItemsList = [];
    if (json['productItems'] != null) {
      final rawItems = json['productItems'] as List<dynamic>;
      productItemsList = rawItems
          .map((item) => DraftProductItem.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    }

    return DailySalesDraft(
      productQuantities: Map<String, int>.from(json['productQuantities'] ?? {}),
      productItems: productItemsList,
      cashAmount: (json['cashAmount'] ?? 0).toDouble(),
      cardAmount: (json['cardAmount'] ?? 0).toDouble(),
      upiAmount: (json['upiAmount'] ?? 0).toDouble(),
      creditAmount: (json['creditAmount'] ?? 0).toDouble(),
      expenseAmount: (json['expenseAmount'] ?? 0).toDouble(),
      expenses: expensesMap,
      notes: json['notes'] ?? '',
      // Use DateTimeHelper to properly handle timezone conversion
      recordDate: DateTimeHelper.parseIsoToLocal(json['recordDate']) ?? DateTime.now(),
      shopId: json['shopId'],
      currentStep: json['currentStep'] ?? 0,
      searchQuery: json['searchQuery'] ?? '',
      selectedCategoryName: json['selectedCategoryName'],
      selectedSubcategoryName: json['selectedSubcategoryName'],
      selectedSize: json['selectedSize'],
      // Use DateTimeHelper to properly handle timezone conversion
      savedAt: DateTimeHelper.parseIsoToLocal(json['savedAt']) ?? DateTime.now(),
      version: json['version'] ?? 1,
    );
  }

  /// Create copy with updated fields
  DailySalesDraft copyWith({
    Map<String, int>? productQuantities,
    List<DraftProductItem>? productItems,
    double? cashAmount,
    double? cardAmount,
    double? upiAmount,
    double? creditAmount,
    double? expenseAmount,
    Map<String, double>? expenses,
    String? notes,
    DateTime? recordDate,
    String? shopId,
    int? currentStep,
    String? searchQuery,
    String? selectedCategoryName,
    String? selectedSubcategoryName,
    String? selectedSize,
    DateTime? savedAt,
    int? version,
  }) {
    return DailySalesDraft(
      productQuantities: productQuantities ?? this.productQuantities,
      productItems: productItems ?? this.productItems,
      cashAmount: cashAmount ?? this.cashAmount,
      cardAmount: cardAmount ?? this.cardAmount,
      upiAmount: upiAmount ?? this.upiAmount,
      creditAmount: creditAmount ?? this.creditAmount,
      expenseAmount: expenseAmount ?? this.expenseAmount,
      expenses: expenses ?? this.expenses,
      notes: notes ?? this.notes,
      recordDate: recordDate ?? this.recordDate,
      shopId: shopId ?? this.shopId,
      currentStep: currentStep ?? this.currentStep,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedCategoryName: selectedCategoryName ?? this.selectedCategoryName,
      selectedSubcategoryName: selectedSubcategoryName ?? this.selectedSubcategoryName,
      selectedSize: selectedSize ?? this.selectedSize,
      savedAt: savedAt ?? this.savedAt,
      version: version ?? this.version,
    );
  }

  @override
  String toString() {
    return 'DailySalesDraft(shop: $shopId, date: ${recordDate.toLocal()}, '
        'products: $productCount, total: ₹$totalPayment, age: $ageText)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is DailySalesDraft &&
        other.shopId == shopId &&
        other.recordDate == recordDate &&
        other.productQuantities == productQuantities &&
        other.cashAmount == cashAmount &&
        other.cardAmount == cardAmount &&
        other.upiAmount == upiAmount &&
        other.creditAmount == creditAmount &&
        other.expenseAmount == expenseAmount &&
        other.notes == notes;
  }

  @override
  int get hashCode {
    return Object.hash(
      shopId,
      recordDate,
      productQuantities,
      cashAmount,
      cardAmount,
      upiAmount,
      creditAmount,
      expenseAmount,
      notes,
    );
  }
}
