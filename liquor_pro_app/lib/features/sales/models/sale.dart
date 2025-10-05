/// Sale model matching backend structure
class Sale {
  final String id;
  final String saleNumber;
  final String shopId;
  final String? salesmanId;
  final DateTime saleDate;
  final String? customerName;
  final String? customerPhone;

  // Financial details
  final double subTotal;
  final double discountAmount;
  final double taxAmount;
  final double totalAmount;
  final double paidAmount;
  final double dueAmount;

  // Payment details
  final String paymentMethod;
  final String paymentStatus; // pending, partial, paid

  // Status and approval
  final String status; // pending, approved, rejected, returned
  final DateTime? approvedAt;
  final String? approvedById;

  // Metadata
  final DateTime createdAt;
  final DateTime updatedAt;

  // Related data
  final List<SaleItem>? items;

  Sale({
    required this.id,
    required this.saleNumber,
    required this.shopId,
    this.salesmanId,
    required this.saleDate,
    this.customerName,
    this.customerPhone,
    required this.subTotal,
    this.discountAmount = 0,
    this.taxAmount = 0,
    required this.totalAmount,
    this.paidAmount = 0,
    this.dueAmount = 0,
    this.paymentMethod = 'cash',
    this.paymentStatus = 'pending',
    this.status = 'pending',
    this.approvedAt,
    this.approvedById,
    required this.createdAt,
    required this.updatedAt,
    this.items,
  });

  factory Sale.fromJson(Map<String, dynamic> json) {
    return Sale(
      id: json['id'] as String,
      saleNumber: json['sale_number'] as String,
      shopId: json['shop_id'] as String,
      salesmanId: json['salesman_id'] as String?,
      saleDate: DateTime.parse(json['sale_date'] as String),
      customerName: json['customer_name'] as String?,
      customerPhone: json['customer_phone'] as String?,
      subTotal: (json['sub_total'] as num).toDouble(),
      discountAmount: (json['discount_amount'] as num?)?.toDouble() ?? 0,
      taxAmount: (json['tax_amount'] as num?)?.toDouble() ?? 0,
      totalAmount: (json['total_amount'] as num).toDouble(),
      paidAmount: (json['paid_amount'] as num?)?.toDouble() ?? 0,
      dueAmount: (json['due_amount'] as num?)?.toDouble() ?? 0,
      paymentMethod: json['payment_method'] as String? ?? 'cash',
      paymentStatus: json['payment_status'] as String? ?? 'pending',
      status: json['status'] as String? ?? 'pending',
      approvedAt: json['approved_at'] != null
          ? DateTime.parse(json['approved_at'] as String)
          : null,
      approvedById: json['approved_by_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      items: json['items'] != null
          ? (json['items'] as List)
              .map((item) => SaleItem.fromJson(item as Map<String, dynamic>))
              .toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sale_number': saleNumber,
      'shop_id': shopId,
      'salesman_id': salesmanId,
      'sale_date': saleDate.toIso8601String(),
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'sub_total': subTotal,
      'discount_amount': discountAmount,
      'tax_amount': taxAmount,
      'total_amount': totalAmount,
      'paid_amount': paidAmount,
      'due_amount': dueAmount,
      'payment_method': paymentMethod,
      'payment_status': paymentStatus,
      'status': status,
      'approved_at': approvedAt?.toIso8601String(),
      'approved_by_id': approvedById,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      if (items != null) 'items': items!.map((item) => item.toJson()).toList(),
    };
  }

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
  bool get isReturned => status == 'returned';

  bool get isFullyPaid => paymentStatus == 'paid';
  bool get isPartiallyPaid => paymentStatus == 'partial';
  bool get hasOutstanding => dueAmount > 0;
}

/// Sale Item model
class SaleItem {
  final String id;
  final String saleId;
  final String productId;
  final String? productName;
  final int quantity;
  final double unitPrice;
  final double totalPrice;
  final double? discountAmount;

  SaleItem({
    required this.id,
    required this.saleId,
    required this.productId,
    this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
    this.discountAmount,
  });

  factory SaleItem.fromJson(Map<String, dynamic> json) {
    return SaleItem(
      id: json['id'] as String,
      saleId: json['sale_id'] as String,
      productId: json['product_id'] as String,
      productName: json['product_name'] as String?,
      quantity: json['quantity'] as int,
      unitPrice: (json['unit_price'] as num).toDouble(),
      totalPrice: (json['total_price'] as num).toDouble(),
      discountAmount: (json['discount_amount'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sale_id': saleId,
      'product_id': productId,
      'product_name': productName,
      'quantity': quantity,
      'unit_price': unitPrice,
      'total_price': totalPrice,
      'discount_amount': discountAmount,
    };
  }
}

/// Sale Return model
class SaleReturn {
  final String id;
  final String saleId;
  final String shopId;
  final DateTime returnDate;
  final String reason;
  final double returnAmount;
  final String status; // pending, approved, rejected
  final DateTime? approvedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  SaleReturn({
    required this.id,
    required this.saleId,
    required this.shopId,
    required this.returnDate,
    required this.reason,
    required this.returnAmount,
    this.status = 'pending',
    this.approvedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SaleReturn.fromJson(Map<String, dynamic> json) {
    return SaleReturn(
      id: json['id'] as String,
      saleId: json['sale_id'] as String,
      shopId: json['shop_id'] as String,
      returnDate: DateTime.parse(json['return_date'] as String),
      reason: json['reason'] as String,
      returnAmount: (json['return_amount'] as num).toDouble(),
      status: json['status'] as String? ?? 'pending',
      approvedAt: json['approved_at'] != null
          ? DateTime.parse(json['approved_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sale_id': saleId,
      'shop_id': shopId,
      'return_date': returnDate.toIso8601String(),
      'reason': reason,
      'return_amount': returnAmount,
      'status': status,
      'approved_at': approvedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
}

/// Daily Sales Record model
class DailySalesRecord {
  final String id;
  final String shopId;
  final DateTime recordDate;
  final double totalSales;
  final double totalReturns;
  final double netSales;
  final int salesCount;
  final int returnsCount;
  final String status;
  final DateTime? approvedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  DailySalesRecord({
    required this.id,
    required this.shopId,
    required this.recordDate,
    required this.totalSales,
    this.totalReturns = 0,
    required this.netSales,
    required this.salesCount,
    this.returnsCount = 0,
    this.status = 'pending',
    this.approvedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DailySalesRecord.fromJson(Map<String, dynamic> json) {
    return DailySalesRecord(
      id: json['id'] as String,
      shopId: json['shop_id'] as String,
      recordDate: DateTime.parse(json['record_date'] as String),
      totalSales: (json['total_sales'] as num).toDouble(),
      totalReturns: (json['total_returns'] as num?)?.toDouble() ?? 0,
      netSales: (json['net_sales'] as num).toDouble(),
      salesCount: json['sales_count'] as int,
      returnsCount: json['returns_count'] as int? ?? 0,
      status: json['status'] as String? ?? 'pending',
      approvedAt: json['approved_at'] != null
          ? DateTime.parse(json['approved_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
}
