/// Purcha Report Models
/// Models for the Purcha Report API response structure
///
/// API Endpoints:
/// - GET /api/reports/purcha/preview - JSON preview data
/// - GET /api/reports/purcha/pdf - PDF download
library;

/// Individual product item in the report
class PurchaReportItem {
  final int serialNo;
  final String productId;
  final String brandName;
  final String productName;
  final String size;
  final String categoryName;
  final int openingStock;
  final int receipt;
  final int total;
  final int sale;
  final double rate;
  final double amount;
  final int closingStock;

  const PurchaReportItem({
    required this.serialNo,
    required this.productId,
    required this.brandName,
    required this.productName,
    required this.size,
    required this.categoryName,
    required this.openingStock,
    required this.receipt,
    required this.total,
    required this.sale,
    required this.rate,
    required this.amount,
    required this.closingStock,
  });

  factory PurchaReportItem.fromJson(Map<String, dynamic> json) {
    return PurchaReportItem(
      serialNo: json['serial_no'] ?? 0,
      productId: json['product_id'] ?? '',
      brandName: json['brand_name'] ?? '',
      productName: json['product_name'] ?? '',
      size: json['size'] ?? '',
      categoryName: json['category_name'] ?? '',
      openingStock: json['opening_stock'] ?? 0,
      receipt: json['receipt'] ?? 0,
      total: json['total'] ?? 0,
      sale: json['sale'] ?? 0,
      rate: (json['rate'] ?? 0).toDouble(),
      amount: (json['amount'] ?? 0).toDouble(),
      closingStock: json['closing_stock'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'serial_no': serialNo,
    'product_id': productId,
    'brand_name': brandName,
    'product_name': productName,
    'size': size,
    'category_name': categoryName,
    'opening_stock': openingStock,
    'receipt': receipt,
    'total': total,
    'sale': sale,
    'rate': rate,
    'amount': amount,
    'closing_stock': closingStock,
  };
}

/// Category grouping with items and subtotals
class PurchaReportCategory {
  final String categoryName;
  final int sortOrder;
  final List<PurchaReportItem> items;
  final int totalOpening;
  final int totalReceipt;
  final int totalTotal;
  final int totalSale;
  final double totalAmount;
  final int totalClosing;

  const PurchaReportCategory({
    required this.categoryName,
    required this.sortOrder,
    required this.items,
    required this.totalOpening,
    required this.totalReceipt,
    required this.totalTotal,
    required this.totalSale,
    required this.totalAmount,
    required this.totalClosing,
  });

  factory PurchaReportCategory.fromJson(Map<String, dynamic> json) {
    return PurchaReportCategory(
      categoryName: json['category_name'] ?? '',
      sortOrder: json['sort_order'] ?? 0,
      items: (json['items'] as List<dynamic>?)
              ?.map((e) => PurchaReportItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      totalOpening: json['total_opening'] ?? 0,
      totalReceipt: json['total_receipt'] ?? 0,
      totalTotal: json['total_total'] ?? 0,
      totalSale: json['total_sale'] ?? 0,
      totalAmount: (json['total_amount'] ?? 0).toDouble(),
      totalClosing: json['total_closing'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'category_name': categoryName,
    'sort_order': sortOrder,
    'items': items.map((e) => e.toJson()).toList(),
    'total_opening': totalOpening,
    'total_receipt': totalReceipt,
    'total_total': totalTotal,
    'total_sale': totalSale,
    'total_amount': totalAmount,
    'total_closing': totalClosing,
  };
}

/// Page representing a specific size (90ML, 180ML, etc.)
class PurchaReportPage {
  final String size;
  final List<PurchaReportCategory> categories;
  final int grandOpening;
  final int grandReceipt;
  final int grandTotal;
  final int grandSale;
  final double grandAmount;
  final int grandClosing;

  const PurchaReportPage({
    required this.size,
    required this.categories,
    required this.grandOpening,
    required this.grandReceipt,
    required this.grandTotal,
    required this.grandSale,
    required this.grandAmount,
    required this.grandClosing,
  });

  factory PurchaReportPage.fromJson(Map<String, dynamic> json) {
    return PurchaReportPage(
      size: json['size'] ?? '',
      categories: (json['categories'] as List<dynamic>?)
              ?.map((e) => PurchaReportCategory.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      grandOpening: json['grand_opening'] ?? 0,
      grandReceipt: json['grand_receipt'] ?? 0,
      grandTotal: json['grand_total'] ?? 0,
      grandSale: json['grand_sale'] ?? 0,
      grandAmount: (json['grand_amount'] ?? 0).toDouble(),
      grandClosing: json['grand_closing'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'size': size,
    'categories': categories.map((e) => e.toJson()).toList(),
    'grand_opening': grandOpening,
    'grand_receipt': grandReceipt,
    'grand_total': grandTotal,
    'grand_sale': grandSale,
    'grand_amount': grandAmount,
    'grand_closing': grandClosing,
  };
}

/// Main Purcha Report model
class PurchaReport {
  final String shopId;
  final String shopName;
  final DateTime reportDate;
  final DateTime generatedAt;
  final String categoryFilter;
  final String viewMode;
  final bool showOpening;
  final List<PurchaReportPage> pages;
  final int totalOpening;
  final int totalReceipt;
  final int totalTotal;
  final int totalSale;
  final double totalAmount;
  final int totalClosing;

  const PurchaReport({
    required this.shopId,
    required this.shopName,
    required this.reportDate,
    required this.generatedAt,
    required this.categoryFilter,
    required this.viewMode,
    required this.showOpening,
    required this.pages,
    required this.totalOpening,
    required this.totalReceipt,
    required this.totalTotal,
    required this.totalSale,
    required this.totalAmount,
    required this.totalClosing,
  });

  factory PurchaReport.fromJson(Map<String, dynamic> json) {
    return PurchaReport(
      shopId: json['shop_id'] ?? '',
      shopName: json['shop_name'] ?? '',
      reportDate: json['report_date'] != null
          ? DateTime.parse(json['report_date'])
          : DateTime.now(),
      generatedAt: json['generated_at'] != null
          ? DateTime.parse(json['generated_at'])
          : DateTime.now(),
      categoryFilter: json['category_filter'] ?? 'non_beer',
      viewMode: json['view_mode'] ?? 'category',
      showOpening: json['show_opening'] ?? true,
      pages: (json['pages'] as List<dynamic>?)
              ?.map((e) => PurchaReportPage.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      totalOpening: json['total_opening'] ?? 0,
      totalReceipt: json['total_receipt'] ?? 0,
      totalTotal: json['total_total'] ?? 0,
      totalSale: json['total_sale'] ?? 0,
      totalAmount: (json['total_amount'] ?? 0).toDouble(),
      totalClosing: json['total_closing'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'shop_id': shopId,
    'shop_name': shopName,
    'report_date': reportDate.toIso8601String(),
    'generated_at': generatedAt.toIso8601String(),
    'category_filter': categoryFilter,
    'view_mode': viewMode,
    'show_opening': showOpening,
    'pages': pages.map((e) => e.toJson()).toList(),
    'total_opening': totalOpening,
    'total_receipt': totalReceipt,
    'total_total': totalTotal,
    'total_sale': totalSale,
    'total_amount': totalAmount,
    'total_closing': totalClosing,
  };

  /// Get all available sizes from pages
  List<String> get availableSizes => pages.map((p) => p.size).toList();

  /// Check if report has data
  bool get hasData => pages.isNotEmpty && pages.any((p) => p.categories.isNotEmpty);
}

/// Enum for view mode
enum PurchaViewMode { category, flat }

/// Enum for category filter
enum PurchaCategoryFilter { all, beer, nonBeer }

/// Extension to convert enum to API string
extension PurchaViewModeExtension on PurchaViewMode {
  String toApiString() {
    switch (this) {
      case PurchaViewMode.category:
        return 'category';
      case PurchaViewMode.flat:
        return 'flat';
    }
  }
}

extension PurchaCategoryFilterExtension on PurchaCategoryFilter {
  String toApiString() {
    switch (this) {
      case PurchaCategoryFilter.all:
        return 'all';
      case PurchaCategoryFilter.beer:
        return 'beer';
      case PurchaCategoryFilter.nonBeer:
        return 'non_beer';
    }
  }

  String get displayName {
    switch (this) {
      case PurchaCategoryFilter.all:
        return 'All';
      case PurchaCategoryFilter.beer:
        return 'Beer';
      case PurchaCategoryFilter.nonBeer:
        return 'Non-Beer';
    }
  }
}
