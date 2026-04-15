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
  final double expenseAmount;
  final double purchaseAmount;
  final List<ShopSummary> shopSummaries;
  final List<TopProductSummary> topProducts;
  final List<RecentSaleActivity> recentSales;
  final DateTime generatedAt;
  final TeamSubmissionStatus? teamStatus;
  final RoleContext? roleContext;
  final MySubmissionStatus? myStatus;

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
    required this.expenseAmount,
    required this.purchaseAmount,
    required this.shopSummaries,
    required this.topProducts,
    required this.recentSales,
    required this.generatedAt,
    this.teamStatus,
    this.roleContext,
    this.myStatus,
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
      expenseAmount: (json['expense_amount'] ?? 0).toDouble(),
      purchaseAmount: (json['purchase_amount'] ?? 0).toDouble(),
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
      teamStatus: json['team_status'] != null
          ? TeamSubmissionStatus.fromJson(json['team_status'] as Map<String, dynamic>)
          : null,
      roleContext: json['role_context'] != null
          ? RoleContext.fromJson(json['role_context'] as Map<String, dynamic>)
          : null,
      myStatus: json['my_status'] != null
          ? MySubmissionStatus.fromJson(json['my_status'] as Map<String, dynamic>)
          : null,
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
  final double cashAmount;
  final double cardAmount;
  final double upiAmount;
  final double creditAmount;
  final String salesmanName;

  ShopSummary({
    required this.shopId,
    required this.shopName,
    required this.totalSales,
    required this.totalAmount,
    required this.pendingSales,
    required this.pendingAmount,
    required this.cashAmount,
    required this.cardAmount,
    required this.upiAmount,
    required this.creditAmount,
    required this.salesmanName,
  });

  factory ShopSummary.fromJson(Map<String, dynamic> json) {
    return ShopSummary(
      shopId: json['shop_id'] ?? '',
      shopName: json['shop_name'] ?? '',
      totalSales: json['total_sales'] ?? 0,
      totalAmount: (json['total_amount'] ?? 0).toDouble(),
      pendingSales: json['pending_sales'] ?? 0,
      pendingAmount: (json['pending_amount'] ?? 0).toDouble(),
      cashAmount: (json['cash_amount'] ?? 0).toDouble(),
      cardAmount: (json['card_amount'] ?? 0).toDouble(),
      upiAmount: (json['upi_amount'] ?? 0).toDouble(),
      creditAmount: (json['credit_amount'] ?? 0).toDouble(),
      salesmanName: json['salesman_name'] ?? '',
    );
  }
}

/// Top Product Summary
class TopProductSummary {
  final String productId;
  final String productName;
  final String? imageUrl;
  final String brandName;
  final String categoryName;
  final int totalQuantity;
  final double totalAmount;

  TopProductSummary({
    required this.productId,
    required this.productName,
    this.imageUrl,
    required this.brandName,
    required this.categoryName,
    required this.totalQuantity,
    required this.totalAmount,
  });

  factory TopProductSummary.fromJson(Map<String, dynamic> json) {
    return TopProductSummary(
      productId: json['product_id'] ?? '',
      productName: json['product_name'] ?? '',
      imageUrl: json['image_url'],
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

/// Team Submission Status — per-salesman tracking from backend
class TeamSubmissionStatus {
  final String date;
  final int totalSalesmen;
  final int totalSubmitted;
  final int totalMissing;
  final double submissionRate;
  final List<ShopSubmissionSummary> shops;

  TeamSubmissionStatus({
    required this.date,
    required this.totalSalesmen,
    required this.totalSubmitted,
    required this.totalMissing,
    required this.submissionRate,
    required this.shops,
  });

  factory TeamSubmissionStatus.fromJson(Map<String, dynamic> json) {
    return TeamSubmissionStatus(
      date: json['date'] ?? '',
      totalSalesmen: json['total_salesmen'] ?? 0,
      totalSubmitted: json['total_submitted'] ?? 0,
      totalMissing: json['total_missing'] ?? 0,
      submissionRate: (json['submission_rate'] ?? 0).toDouble(),
      shops: (json['shops'] as List<dynamic>?)
              ?.map((e) => ShopSubmissionSummary.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

/// Shop-level submission summary
class ShopSubmissionSummary {
  final String shopName;
  final int submittedCount;
  final int missingCount;
  final List<SalesmanSubmissionStatus> salesmen;

  ShopSubmissionSummary({
    required this.shopName,
    required this.submittedCount,
    required this.missingCount,
    required this.salesmen,
  });

  factory ShopSubmissionSummary.fromJson(Map<String, dynamic> json) {
    return ShopSubmissionSummary(
      shopName: json['shop_name'] ?? '',
      submittedCount: json['submitted_count'] ?? 0,
      missingCount: json['missing_count'] ?? 0,
      salesmen: (json['salesmen'] as List<dynamic>?)
              ?.map((e) => SalesmanSubmissionStatus.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

/// Individual salesman submission status
class SalesmanSubmissionStatus {
  final String salesmanName;
  final String status; // "submitted" or "missing"
  final String? recordStatus; // "pending", "approved", "rejected"
  final double totalAmount;

  SalesmanSubmissionStatus({
    required this.salesmanName,
    required this.status,
    this.recordStatus,
    required this.totalAmount,
  });

  factory SalesmanSubmissionStatus.fromJson(Map<String, dynamic> json) {
    return SalesmanSubmissionStatus(
      salesmanName: json['salesman_name'] ?? '',
      status: json['status'] ?? 'missing',
      recordStatus: json['record_status'],
      totalAmount: (json['total_amount'] ?? 0).toDouble(),
    );
  }
}

/// Role context from backend — tells Flutter what to show per role
class RoleContext {
  final String role;
  final String displayRole;
  final bool showAllShops;
  final bool showTeamTracker;
  final bool showApprovals;
  final bool canApprove;
  final bool canRevert;

  RoleContext({
    required this.role,
    required this.displayRole,
    required this.showAllShops,
    required this.showTeamTracker,
    required this.showApprovals,
    required this.canApprove,
    required this.canRevert,
  });

  factory RoleContext.fromJson(Map<String, dynamic> json) {
    return RoleContext(
      role: json['role'] ?? '',
      displayRole: json['display_role'] ?? '',
      showAllShops: json['show_all_shops'] ?? false,
      showTeamTracker: json['show_team_tracker'] ?? false,
      showApprovals: json['show_approvals'] ?? false,
      canApprove: json['can_approve'] ?? false,
      canRevert: json['can_revert'] ?? false,
    );
  }
}

/// My submission status (for salesman/executive view)
class MySubmissionStatus {
  final String salesmanName;
  final String status; // "submitted" or "missing"
  final String? recordStatus; // "pending", "approved", "rejected"
  final double totalAmount;
  final String? shopName;

  MySubmissionStatus({
    required this.salesmanName,
    required this.status,
    this.recordStatus,
    required this.totalAmount,
    this.shopName,
  });

  factory MySubmissionStatus.fromJson(Map<String, dynamic> json) {
    return MySubmissionStatus(
      salesmanName: json['salesman_name'] ?? '',
      status: json['status'] ?? 'missing',
      recordStatus: json['record_status'],
      totalAmount: (json['total_amount'] ?? 0).toDouble(),
      shopName: json['shop_name'],
    );
  }
}
