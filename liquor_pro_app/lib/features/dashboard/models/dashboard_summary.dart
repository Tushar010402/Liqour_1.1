/// Dashboard Summary Model
/// Matches backend response from GET /api/sales/dashboard/summary
class DashboardSummary {
  final DailySalesStats todaysSales;
  final DailyReturnsStats todaysReturns;
  final int pendingSales;
  final int pendingReturns;
  final double totalRevenue;
  final double totalDue;
  final double cashAmount;
  final double cardAmount;
  final double upiAmount;
  final double creditAmount;
  final List<ShopSummary> shopSummaries;
  final List<TopProductSummary> topProducts;
  final List<RecentSaleActivity> recentSales;
  final DateTime generatedAt;

  DashboardSummary({
    required this.todaysSales,
    required this.todaysReturns,
    required this.pendingSales,
    required this.pendingReturns,
    required this.totalRevenue,
    required this.totalDue,
    required this.cashAmount,
    required this.cardAmount,
    required this.upiAmount,
    required this.creditAmount,
    required this.shopSummaries,
    required this.topProducts,
    required this.recentSales,
    required this.generatedAt,
  });

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    return DashboardSummary(
      todaysSales: DailySalesStats.fromJson(json['todays_sales'] ?? {}),
      todaysReturns: DailyReturnsStats.fromJson(json['todays_returns'] ?? {}),
      pendingSales: json['pending_sales'] ?? 0,
      pendingReturns: json['pending_returns'] ?? 0,
      totalRevenue: (json['total_revenue'] ?? 0).toDouble(),
      totalDue: (json['total_due'] ?? 0).toDouble(),
      cashAmount: (json['cash_amount'] ?? 0).toDouble(),
      cardAmount: (json['card_amount'] ?? 0).toDouble(),
      upiAmount: (json['upi_amount'] ?? 0).toDouble(),
      creditAmount: (json['credit_amount'] ?? 0).toDouble(),
      shopSummaries: (json['shop_summaries'] as List<dynamic>?)
              ?.map((e) => ShopSummary.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      topProducts: (json['top_products'] as List<dynamic>?)
              ?.map((e) => TopProductSummary.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      recentSales: (json['recent_sales'] as List<dynamic>?)
              ?.map((e) => RecentSaleActivity.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      generatedAt: DateTime.parse(json['generated_at']),
    );
  }
}

/// Daily Sales Statistics
class DailySalesStats {
  final int totalSales;
  final double totalAmount;
  final int approvedSales;
  final double approvedAmount;
  final int pendingSales;
  final double pendingAmount;

  DailySalesStats({
    required this.totalSales,
    required this.totalAmount,
    required this.approvedSales,
    required this.approvedAmount,
    required this.pendingSales,
    required this.pendingAmount,
  });

  factory DailySalesStats.fromJson(Map<String, dynamic> json) {
    return DailySalesStats(
      totalSales: json['total_sales'] ?? 0,
      totalAmount: (json['total_amount'] ?? 0).toDouble(),
      approvedSales: json['approved_sales'] ?? 0,
      approvedAmount: (json['approved_amount'] ?? 0).toDouble(),
      pendingSales: json['pending_sales'] ?? 0,
      pendingAmount: (json['pending_amount'] ?? 0).toDouble(),
    );
  }
}

/// Daily Returns Statistics
class DailyReturnsStats {
  final int totalReturns;
  final double totalAmount;
  final int approvedReturns;
  final double approvedAmount;
  final int pendingReturns;
  final double pendingAmount;

  DailyReturnsStats({
    required this.totalReturns,
    required this.totalAmount,
    required this.approvedReturns,
    required this.approvedAmount,
    required this.pendingReturns,
    required this.pendingAmount,
  });

  factory DailyReturnsStats.fromJson(Map<String, dynamic> json) {
    return DailyReturnsStats(
      totalReturns: json['total_returns'] ?? 0,
      totalAmount: (json['total_amount'] ?? 0).toDouble(),
      approvedReturns: json['approved_returns'] ?? 0,
      approvedAmount: (json['approved_amount'] ?? 0).toDouble(),
      pendingReturns: json['pending_returns'] ?? 0,
      pendingAmount: (json['pending_amount'] ?? 0).toDouble(),
    );
  }
}

/// Shop Summary
class ShopSummary {
  final String shopId;
  final String shopName;
  final int totalSales;
  final double totalAmount;
  final int pendingSales;
  final double pendingAmount;

  ShopSummary({
    required this.shopId,
    required this.shopName,
    required this.totalSales,
    required this.totalAmount,
    required this.pendingSales,
    required this.pendingAmount,
  });

  factory ShopSummary.fromJson(Map<String, dynamic> json) {
    return ShopSummary(
      shopId: json['shop_id'] ?? '',
      shopName: json['shop_name'] ?? '',
      totalSales: json['total_sales'] ?? 0,
      totalAmount: (json['total_amount'] ?? 0).toDouble(),
      pendingSales: json['pending_sales'] ?? 0,
      pendingAmount: (json['pending_amount'] ?? 0).toDouble(),
    );
  }
}

/// Top Product Summary
class TopProductSummary {
  final String productId;
  final String productName;
  final String brandName;
  final String categoryName;
  final int totalQuantity;
  final double totalAmount;

  TopProductSummary({
    required this.productId,
    required this.productName,
    required this.brandName,
    required this.categoryName,
    required this.totalQuantity,
    required this.totalAmount,
  });

  factory TopProductSummary.fromJson(Map<String, dynamic> json) {
    return TopProductSummary(
      productId: json['product_id'] ?? '',
      productName: json['product_name'] ?? '',
      brandName: json['brand_name'] ?? '',
      categoryName: json['category_name'] ?? '',
      totalQuantity: json['total_quantity'] ?? 0,
      totalAmount: (json['total_amount'] ?? 0).toDouble(),
    );
  }
}

/// Recent Sale Activity
class RecentSaleActivity {
  final String id;
  final String type; // "sale", "return", "daily_record"
  final String number;
  final String shopName;
  final String salesmanName;
  final double amount;
  final String status;
  final DateTime createdAt;

  RecentSaleActivity({
    required this.id,
    required this.type,
    required this.number,
    required this.shopName,
    required this.salesmanName,
    required this.amount,
    required this.status,
    required this.createdAt,
  });

  factory RecentSaleActivity.fromJson(Map<String, dynamic> json) {
    return RecentSaleActivity(
      id: json['id'] ?? '',
      type: json['type'] ?? '',
      number: json['number'] ?? '',
      shopName: json['shop_name'] ?? '',
      salesmanName: json['salesman_name'] ?? '',
      amount: (json['amount'] ?? 0).toDouble(),
      status: json['status'] ?? '',
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}
