/// Finance Matrix Models - AI-Powered Unified Financial Dashboard
/// USP Feature: All-in-one view of Sales + Cash + Inventory + Expenses
library;

/// Complete Finance Matrix Dashboard Data
class FinanceMatrixDashboard {
  final SalesSummary sales;
  final CashSummary cash;
  final InventorySummary inventory;
  final ExpensesSummary expenses;
  final List<MatrixInsight> insights;
  final DateTime generatedAt;
  final String period;
  final String? shopId;

  FinanceMatrixDashboard({
    required this.sales,
    required this.cash,
    required this.inventory,
    required this.expenses,
    required this.insights,
    required this.generatedAt,
    required this.period,
    this.shopId,
  });

  factory FinanceMatrixDashboard.fromJson(Map<String, dynamic> json) {
    return FinanceMatrixDashboard(
      sales: SalesSummary.fromJson(json['sales'] ?? {}),
      cash: CashSummary.fromJson(json['cash'] ?? {}),
      inventory: InventorySummary.fromJson(json['inventory'] ?? {}),
      expenses: ExpensesSummary.fromJson(json['expenses'] ?? {}),
      insights: (json['insights'] as List?)
              ?.map((e) => MatrixInsight.fromJson(e))
              .toList() ??
          [],
      generatedAt: json['generated_at'] != null
          ? DateTime.parse(json['generated_at'])
          : DateTime.now(),
      period: json['period'] ?? 'today',
      shopId: json['shop_id'],
    );
  }

  Map<String, dynamic> toJson() => {
        'sales': sales.toJson(),
        'cash': cash.toJson(),
        'inventory': inventory.toJson(),
        'expenses': expenses.toJson(),
        'insights': insights.map((e) => e.toJson()).toList(),
        'generated_at': generatedAt.toIso8601String(),
        'period': period,
        'shop_id': shopId,
      };

  /// Get overall health score (0-100)
  double get healthScore {
    // Weighted average of key metrics
    double score = 0;

    // Sales performance (30%)
    if (sales.target > 0) {
      score += (sales.totalAmount / sales.target * 100).clamp(0, 100) * 0.30;
    } else {
      score += 70 * 0.30; // Default if no target
    }

    // Cash reconciliation (25%)
    if (cash.expectedBalance > 0) {
      final cashAccuracy =
          (1 - (cash.variance.abs() / cash.expectedBalance)) * 100;
      score += cashAccuracy.clamp(0, 100) * 0.25;
    } else {
      score += 100 * 0.25;
    }

    // Inventory health (25%)
    if (inventory.totalItems > 0) {
      final stockHealthRatio =
          (inventory.totalItems - inventory.lowStockCount - inventory.outOfStockCount) /
              inventory.totalItems *
              100;
      score += stockHealthRatio.clamp(0, 100) * 0.25;
    } else {
      score += 80 * 0.25;
    }

    // Expense management (20%)
    if (expenses.budgeted > 0) {
      final expenseRatio = (expenses.budgeted - expenses.totalSpent) /
          expenses.budgeted *
          100;
      score += (50 + expenseRatio / 2).clamp(0, 100) * 0.20;
    } else {
      score += 80 * 0.20;
    }

    return score;
  }
}

/// Sales Summary for Matrix
class SalesSummary {
  final double totalAmount;
  final int transactionCount;
  final double averageTransaction;
  final double target;
  final double previousPeriod;
  final double growthPercent;
  final List<HourlyData> hourlyBreakdown;
  final List<CategoryBreakdown> categoryBreakdown;
  final String topProduct;
  final int topProductCount;

  SalesSummary({
    required this.totalAmount,
    required this.transactionCount,
    required this.averageTransaction,
    required this.target,
    required this.previousPeriod,
    required this.growthPercent,
    required this.hourlyBreakdown,
    required this.categoryBreakdown,
    required this.topProduct,
    required this.topProductCount,
  });

  factory SalesSummary.fromJson(Map<String, dynamic> json) {
    return SalesSummary(
      totalAmount: (json['total_amount'] ?? 0).toDouble(),
      transactionCount: json['transaction_count'] ?? 0,
      averageTransaction: (json['average_transaction'] ?? 0).toDouble(),
      target: (json['target'] ?? 0).toDouble(),
      previousPeriod: (json['previous_period'] ?? 0).toDouble(),
      growthPercent: (json['growth_percent'] ?? 0).toDouble(),
      hourlyBreakdown: (json['hourly_breakdown'] as List?)
              ?.map((e) => HourlyData.fromJson(e))
              .toList() ??
          [],
      categoryBreakdown: (json['category_breakdown'] as List?)
              ?.map((e) => CategoryBreakdown.fromJson(e))
              .toList() ??
          [],
      topProduct: json['top_product'] ?? '',
      topProductCount: json['top_product_count'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'total_amount': totalAmount,
        'transaction_count': transactionCount,
        'average_transaction': averageTransaction,
        'target': target,
        'previous_period': previousPeriod,
        'growth_percent': growthPercent,
        'hourly_breakdown': hourlyBreakdown.map((e) => e.toJson()).toList(),
        'category_breakdown': categoryBreakdown.map((e) => e.toJson()).toList(),
        'top_product': topProduct,
        'top_product_count': topProductCount,
      };

  double get targetProgress =>
      target > 0 ? (totalAmount / target * 100).clamp(0, 150) : 0;
}

/// Hourly data for charts
class HourlyData {
  final int hour;
  final double value;
  final int count;

  HourlyData({
    required this.hour,
    required this.value,
    required this.count,
  });

  factory HourlyData.fromJson(Map<String, dynamic> json) {
    return HourlyData(
      hour: json['hour'] ?? 0,
      value: (json['value'] ?? 0).toDouble(),
      count: json['count'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'hour': hour,
        'value': value,
        'count': count,
      };

  String get hourLabel {
    if (hour == 0) return '12 AM';
    if (hour == 12) return '12 PM';
    if (hour > 12) return '${hour - 12} PM';
    return '$hour AM';
  }
}

/// Category breakdown for pie charts
class CategoryBreakdown {
  final String category;
  final double amount;
  final int count;
  final double percentage;

  CategoryBreakdown({
    required this.category,
    required this.amount,
    required this.count,
    required this.percentage,
  });

  factory CategoryBreakdown.fromJson(Map<String, dynamic> json) {
    return CategoryBreakdown(
      category: json['category'] ?? '',
      amount: (json['amount'] ?? 0).toDouble(),
      count: json['count'] ?? 0,
      percentage: (json['percentage'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'category': category,
        'amount': amount,
        'count': count,
        'percentage': percentage,
      };
}

/// Cash Summary for Matrix
class CashSummary {
  final double openingBalance;
  final double totalReceived;
  final double totalPaid;
  final double expectedBalance;
  final double actualBalance;
  final double variance;
  final List<CashFlowEntry> recentTransactions;
  final CashBreakdown breakdown;
  final String lastReconciliationStatus;

  CashSummary({
    required this.openingBalance,
    required this.totalReceived,
    required this.totalPaid,
    required this.expectedBalance,
    required this.actualBalance,
    required this.variance,
    required this.recentTransactions,
    required this.breakdown,
    required this.lastReconciliationStatus,
  });

  factory CashSummary.fromJson(Map<String, dynamic> json) {
    return CashSummary(
      openingBalance: (json['opening_balance'] ?? 0).toDouble(),
      totalReceived: (json['total_received'] ?? 0).toDouble(),
      totalPaid: (json['total_paid'] ?? 0).toDouble(),
      expectedBalance: (json['expected_balance'] ?? 0).toDouble(),
      actualBalance: (json['actual_balance'] ?? 0).toDouble(),
      variance: (json['variance'] ?? 0).toDouble(),
      recentTransactions: (json['recent_transactions'] as List?)
              ?.map((e) => CashFlowEntry.fromJson(e))
              .toList() ??
          [],
      breakdown: CashBreakdown.fromJson(json['breakdown'] ?? {}),
      lastReconciliationStatus: json['last_reconciliation_status'] ?? 'pending',
    );
  }

  Map<String, dynamic> toJson() => {
        'opening_balance': openingBalance,
        'total_received': totalReceived,
        'total_paid': totalPaid,
        'expected_balance': expectedBalance,
        'actual_balance': actualBalance,
        'variance': variance,
        'recent_transactions': recentTransactions.map((e) => e.toJson()).toList(),
        'breakdown': breakdown.toJson(),
        'last_reconciliation_status': lastReconciliationStatus,
      };

  bool get hasVariance => variance.abs() > 0.01;
  bool get isShort => variance < -0.01;
  bool get isOver => variance > 0.01;
}

/// Cash flow entry
class CashFlowEntry {
  final String id;
  final String type; // 'in' or 'out'
  final String description;
  final double amount;
  final DateTime timestamp;
  final String? reference;

  CashFlowEntry({
    required this.id,
    required this.type,
    required this.description,
    required this.amount,
    required this.timestamp,
    this.reference,
  });

  factory CashFlowEntry.fromJson(Map<String, dynamic> json) {
    return CashFlowEntry(
      id: json['id'] ?? '',
      type: json['type'] ?? 'in',
      description: json['description'] ?? '',
      amount: (json['amount'] ?? 0).toDouble(),
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
      reference: json['reference'],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'description': description,
        'amount': amount,
        'timestamp': timestamp.toIso8601String(),
        'reference': reference,
      };
}

/// Cash denomination breakdown
class CashBreakdown {
  final Map<String, int> denominations; // "2000" -> 5, "500" -> 10, etc.
  final double totalCounted;

  CashBreakdown({
    required this.denominations,
    required this.totalCounted,
  });

  factory CashBreakdown.fromJson(Map<String, dynamic> json) {
    final denoms = <String, int>{};
    if (json['denominations'] != null) {
      (json['denominations'] as Map<String, dynamic>).forEach((key, value) {
        denoms[key] = value as int;
      });
    }
    return CashBreakdown(
      denominations: denoms,
      totalCounted: (json['total_counted'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'denominations': denominations,
        'total_counted': totalCounted,
      };
}

/// Inventory Summary for Matrix
class InventorySummary {
  final int totalItems;
  final double totalValue;
  final int lowStockCount;
  final int outOfStockCount;
  final int expiringCount;
  final List<StockAlert> alerts;
  final List<CategoryStock> categoryStocks;
  final double turnoverRate;

  InventorySummary({
    required this.totalItems,
    required this.totalValue,
    required this.lowStockCount,
    required this.outOfStockCount,
    required this.expiringCount,
    required this.alerts,
    required this.categoryStocks,
    required this.turnoverRate,
  });

  factory InventorySummary.fromJson(Map<String, dynamic> json) {
    return InventorySummary(
      totalItems: json['total_items'] ?? 0,
      totalValue: (json['total_value'] ?? 0).toDouble(),
      lowStockCount: json['low_stock_count'] ?? 0,
      outOfStockCount: json['out_of_stock_count'] ?? 0,
      expiringCount: json['expiring_count'] ?? 0,
      alerts: (json['alerts'] as List?)
              ?.map((e) => StockAlert.fromJson(e))
              .toList() ??
          [],
      categoryStocks: (json['category_stocks'] as List?)
              ?.map((e) => CategoryStock.fromJson(e))
              .toList() ??
          [],
      turnoverRate: (json['turnover_rate'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'total_items': totalItems,
        'total_value': totalValue,
        'low_stock_count': lowStockCount,
        'out_of_stock_count': outOfStockCount,
        'expiring_count': expiringCount,
        'alerts': alerts.map((e) => e.toJson()).toList(),
        'category_stocks': categoryStocks.map((e) => e.toJson()).toList(),
        'turnover_rate': turnoverRate,
      };

  int get totalAlerts => lowStockCount + outOfStockCount + expiringCount;
}

/// Stock alert item
class StockAlert {
  final String productId;
  final String productName;
  final String alertType; // 'low_stock', 'out_of_stock', 'expiring'
  final int currentStock;
  final int minimumStock;
  final DateTime? expiryDate;
  final String severity; // 'low', 'medium', 'high', 'critical'

  StockAlert({
    required this.productId,
    required this.productName,
    required this.alertType,
    required this.currentStock,
    required this.minimumStock,
    this.expiryDate,
    required this.severity,
  });

  factory StockAlert.fromJson(Map<String, dynamic> json) {
    return StockAlert(
      productId: json['product_id'] ?? '',
      productName: json['product_name'] ?? '',
      alertType: json['alert_type'] ?? 'low_stock',
      currentStock: json['current_stock'] ?? 0,
      minimumStock: json['minimum_stock'] ?? 0,
      expiryDate: json['expiry_date'] != null
          ? DateTime.parse(json['expiry_date'])
          : null,
      severity: json['severity'] ?? 'medium',
    );
  }

  Map<String, dynamic> toJson() => {
        'product_id': productId,
        'product_name': productName,
        'alert_type': alertType,
        'current_stock': currentStock,
        'minimum_stock': minimumStock,
        'expiry_date': expiryDate?.toIso8601String(),
        'severity': severity,
      };
}

/// Category stock summary
class CategoryStock {
  final String category;
  final int itemCount;
  final double value;
  final int lowStockCount;

  CategoryStock({
    required this.category,
    required this.itemCount,
    required this.value,
    required this.lowStockCount,
  });

  factory CategoryStock.fromJson(Map<String, dynamic> json) {
    return CategoryStock(
      category: json['category'] ?? '',
      itemCount: json['item_count'] ?? 0,
      value: (json['value'] ?? 0).toDouble(),
      lowStockCount: json['low_stock_count'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'category': category,
        'item_count': itemCount,
        'value': value,
        'low_stock_count': lowStockCount,
      };
}

/// Expenses Summary for Matrix
class ExpensesSummary {
  final double totalSpent;
  final double budgeted;
  final double remaining;
  final List<ExpenseCategory> categories;
  final List<ExpenseEntry> recentExpenses;
  final double previousPeriod;
  final double changePercent;

  ExpensesSummary({
    required this.totalSpent,
    required this.budgeted,
    required this.remaining,
    required this.categories,
    required this.recentExpenses,
    required this.previousPeriod,
    required this.changePercent,
  });

  factory ExpensesSummary.fromJson(Map<String, dynamic> json) {
    return ExpensesSummary(
      totalSpent: (json['total_spent'] ?? 0).toDouble(),
      budgeted: (json['budgeted'] ?? 0).toDouble(),
      remaining: (json['remaining'] ?? 0).toDouble(),
      categories: (json['categories'] as List?)
              ?.map((e) => ExpenseCategory.fromJson(e))
              .toList() ??
          [],
      recentExpenses: (json['recent_expenses'] as List?)
              ?.map((e) => ExpenseEntry.fromJson(e))
              .toList() ??
          [],
      previousPeriod: (json['previous_period'] ?? 0).toDouble(),
      changePercent: (json['change_percent'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'total_spent': totalSpent,
        'budgeted': budgeted,
        'remaining': remaining,
        'categories': categories.map((e) => e.toJson()).toList(),
        'recent_expenses': recentExpenses.map((e) => e.toJson()).toList(),
        'previous_period': previousPeriod,
        'change_percent': changePercent,
      };

  double get budgetUsedPercent =>
      budgeted > 0 ? (totalSpent / budgeted * 100).clamp(0, 150) : 0;
  bool get isOverBudget => totalSpent > budgeted;
}

/// Expense category breakdown
class ExpenseCategory {
  final String name;
  final double amount;
  final double budget;
  final double percentage;

  ExpenseCategory({
    required this.name,
    required this.amount,
    required this.budget,
    required this.percentage,
  });

  factory ExpenseCategory.fromJson(Map<String, dynamic> json) {
    return ExpenseCategory(
      name: json['name'] ?? '',
      amount: (json['amount'] ?? 0).toDouble(),
      budget: (json['budget'] ?? 0).toDouble(),
      percentage: (json['percentage'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'amount': amount,
        'budget': budget,
        'percentage': percentage,
      };
}

/// Individual expense entry
class ExpenseEntry {
  final String id;
  final String category;
  final String description;
  final double amount;
  final DateTime date;
  final String? vendorName;
  final String status;

  ExpenseEntry({
    required this.id,
    required this.category,
    required this.description,
    required this.amount,
    required this.date,
    this.vendorName,
    required this.status,
  });

  factory ExpenseEntry.fromJson(Map<String, dynamic> json) {
    return ExpenseEntry(
      id: json['id'] ?? '',
      category: json['category'] ?? '',
      description: json['description'] ?? '',
      amount: (json['amount'] ?? 0).toDouble(),
      date: json['date'] != null ? DateTime.parse(json['date']) : DateTime.now(),
      vendorName: json['vendor_name'],
      status: json['status'] ?? 'pending',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category,
        'description': description,
        'amount': amount,
        'date': date.toIso8601String(),
        'vendor_name': vendorName,
        'status': status,
      };
}

/// AI-generated insight
class MatrixInsight {
  final String id;
  final String type; // 'sales', 'cash', 'inventory', 'expenses', 'correlation'
  final String title;
  final String description;
  final String severity; // 'info', 'warning', 'critical', 'success'
  final String? actionUrl;
  final String? actionLabel;
  final Map<String, dynamic>? metadata;
  final DateTime generatedAt;

  MatrixInsight({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.severity,
    this.actionUrl,
    this.actionLabel,
    this.metadata,
    required this.generatedAt,
  });

  factory MatrixInsight.fromJson(Map<String, dynamic> json) {
    return MatrixInsight(
      id: json['id'] ?? '',
      type: json['type'] ?? 'info',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      severity: json['severity'] ?? 'info',
      actionUrl: json['action_url'],
      actionLabel: json['action_label'],
      metadata: json['metadata'] != null
          ? Map<String, dynamic>.from(json['metadata'])
          : null,
      generatedAt: json['generated_at'] != null
          ? DateTime.parse(json['generated_at'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'title': title,
        'description': description,
        'severity': severity,
        'action_url': actionUrl,
        'action_label': actionLabel,
        'metadata': metadata,
        'generated_at': generatedAt.toIso8601String(),
      };
}

/// Time period for dashboard queries
enum MatrixPeriod {
  today,
  yesterday,
  thisWeek,
  lastWeek,
  thisMonth,
  lastMonth,
  custom;

  String get apiValue {
    switch (this) {
      case MatrixPeriod.today:
        return 'today';
      case MatrixPeriod.yesterday:
        return 'yesterday';
      case MatrixPeriod.thisWeek:
        return 'this_week';
      case MatrixPeriod.lastWeek:
        return 'last_week';
      case MatrixPeriod.thisMonth:
        return 'this_month';
      case MatrixPeriod.lastMonth:
        return 'last_month';
      case MatrixPeriod.custom:
        return 'custom';
    }
  }

  String get displayName {
    switch (this) {
      case MatrixPeriod.today:
        return 'Today';
      case MatrixPeriod.yesterday:
        return 'Yesterday';
      case MatrixPeriod.thisWeek:
        return 'This Week';
      case MatrixPeriod.lastWeek:
        return 'Last Week';
      case MatrixPeriod.thisMonth:
        return 'This Month';
      case MatrixPeriod.lastMonth:
        return 'Last Month';
      case MatrixPeriod.custom:
        return 'Custom Range';
    }
  }
}

/// Query parameters for finance matrix
class MatrixQuery {
  final MatrixPeriod period;
  final String? shopId;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool includeInsights;

  const MatrixQuery({
    this.period = MatrixPeriod.today,
    this.shopId,
    this.startDate,
    this.endDate,
    this.includeInsights = true,
  });

  Map<String, dynamic> toQueryParams() {
    final params = <String, dynamic>{
      'period': period.apiValue,
      'include_insights': includeInsights.toString(),
    };
    if (shopId != null) params['shop_id'] = shopId;
    if (startDate != null) params['start_date'] = startDate!.toIso8601String();
    if (endDate != null) params['end_date'] = endDate!.toIso8601String();
    return params;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MatrixQuery &&
          runtimeType == other.runtimeType &&
          period == other.period &&
          shopId == other.shopId &&
          startDate == other.startDate &&
          endDate == other.endDate &&
          includeInsights == other.includeInsights;

  @override
  int get hashCode =>
      period.hashCode ^
      shopId.hashCode ^
      startDate.hashCode ^
      endDate.hashCode ^
      includeInsights.hashCode;

  MatrixQuery copyWith({
    MatrixPeriod? period,
    String? shopId,
    DateTime? startDate,
    DateTime? endDate,
    bool? includeInsights,
  }) {
    return MatrixQuery(
      period: period ?? this.period,
      shopId: shopId ?? this.shopId,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      includeInsights: includeInsights ?? this.includeInsights,
    );
  }
}

/// Trend data for charts
class TrendData {
  final List<TrendPoint> points;
  final double average;
  final double min;
  final double max;
  final double trend; // Positive = upward, Negative = downward

  TrendData({
    required this.points,
    required this.average,
    required this.min,
    required this.max,
    required this.trend,
  });

  factory TrendData.fromJson(Map<String, dynamic> json) {
    return TrendData(
      points: (json['points'] as List?)
              ?.map((e) => TrendPoint.fromJson(e))
              .toList() ??
          [],
      average: (json['average'] ?? 0).toDouble(),
      min: (json['min'] ?? 0).toDouble(),
      max: (json['max'] ?? 0).toDouble(),
      trend: (json['trend'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'points': points.map((e) => e.toJson()).toList(),
        'average': average,
        'min': min,
        'max': max,
        'trend': trend,
      };

  bool get isUpward => trend > 0;
  bool get isDownward => trend < 0;
}

/// Single trend point
class TrendPoint {
  final DateTime date;
  final double value;
  final String label;

  TrendPoint({
    required this.date,
    required this.value,
    required this.label,
  });

  factory TrendPoint.fromJson(Map<String, dynamic> json) {
    return TrendPoint(
      date: json['date'] != null ? DateTime.parse(json['date']) : DateTime.now(),
      value: (json['value'] ?? 0).toDouble(),
      label: json['label'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'value': value,
        'label': label,
      };
}
