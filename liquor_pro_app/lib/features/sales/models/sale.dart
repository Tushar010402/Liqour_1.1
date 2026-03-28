import '../../../core/utils/date_time_helper.dart';

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

  // Rejection tracking
  final String? rejectionReason;
  final String? rejectedBy;
  final DateTime? rejectedAt;
  final String? rejectedById;

  // Location tracking (for review/monitoring)
  final double? latitude;
  final double? longitude;
  final String? locationAccuracy;

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
    this.rejectionReason,
    this.rejectedBy,
    this.rejectedAt,
    this.rejectedById,
    this.latitude,
    this.longitude,
    this.locationAccuracy,
    required this.createdAt,
    required this.updatedAt,
    this.items,
  });

  /// Check if location was captured for this sale
  bool get hasLocation => latitude != null && longitude != null;

  factory Sale.fromJson(Map<String, dynamic> json) {
    return Sale(
      id: json['id'] as String? ?? '',
      saleNumber: json['sale_number'] as String? ?? '',
      shopId: json['shop_id'] as String? ?? '',
      salesmanId: json['salesman_id'] as String?,
      saleDate: DateTimeHelper.parseIsoToLocal(json['sale_date']) ?? DateTime.now(),
      customerName: json['customer_name'] as String?,
      customerPhone: json['customer_phone'] as String?,
      subTotal: (json['sub_total'] as num?)?.toDouble() ?? 0,
      discountAmount: (json['discount_amount'] as num?)?.toDouble() ?? 0,
      taxAmount: (json['tax_amount'] as num?)?.toDouble() ?? 0,
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0,
      paidAmount: (json['paid_amount'] as num?)?.toDouble() ?? 0,
      dueAmount: (json['due_amount'] as num?)?.toDouble() ?? 0,
      paymentMethod: json['payment_method'] as String? ?? 'cash',
      paymentStatus: json['payment_status'] as String? ?? 'pending',
      status: json['status'] as String? ?? 'pending',
      approvedAt: DateTimeHelper.parseIsoToLocal(json['approved_at']),
      approvedById: json['approved_by_id'] as String?,
      rejectionReason: json['rejection_reason'] as String?,
      rejectedBy: json['rejected_by'] as String?,
      rejectedAt: DateTimeHelper.parseIsoToLocal(json['rejected_at']),
      rejectedById: json['rejected_by_id'] as String?,
      // Parse location fields from backend
      latitude: json['latitude'] != null ? (json['latitude'] as num).toDouble() : null,
      longitude: json['longitude'] != null ? (json['longitude'] as num).toDouble() : null,
      locationAccuracy: json['location_accuracy']?.toString(),
      createdAt: DateTimeHelper.parseIsoToLocal(json['created_at']) ?? DateTime.now(),
      updatedAt: DateTimeHelper.parseIsoToLocal(json['updated_at']) ?? DateTime.now(),
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
      'rejection_reason': rejectionReason,
      'rejected_by': rejectedBy,
      'rejected_at': rejectedAt?.toIso8601String(),
      'rejected_by_id': rejectedById,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (locationAccuracy != null) 'location_accuracy': locationAccuracy,
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
  final String? brandName;
  final String? categoryName;
  final String? size; // ML values like "750ml", "180ml"
  final String? sku;
  final int quantity;
  final double unitPrice;
  final double totalPrice;
  final double? discountAmount;
  final int openingStock; // Stock BEFORE sale
  final int closingStock; // Stock AFTER sale

  SaleItem({
    required this.id,
    required this.saleId,
    required this.productId,
    this.productName,
    this.brandName,
    this.categoryName,
    this.size,
    this.sku,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
    this.discountAmount,
    this.openingStock = 0,
    this.closingStock = 0,
  });

  factory SaleItem.fromJson(Map<String, dynamic> json) {
    return SaleItem(
      id: json['id'] as String? ?? '',
      saleId: json['sale_id'] as String? ?? '',
      productId: json['product_id'] as String? ?? '',
      productName: json['product_name'] as String?,
      brandName: json['brand_name'] as String?,
      categoryName: json['category_name'] as String?,
      size: json['size'] as String?,
      sku: json['sku'] as String?,
      quantity: json['quantity'] as int? ?? 0,
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0,
      totalPrice: (json['total_price'] as num?)?.toDouble() ?? 0,
      discountAmount: (json['discount_amount'] as num?)?.toDouble(),
      openingStock: json['opening_stock'] as int? ?? 0,
      closingStock: json['closing_stock'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sale_id': saleId,
      'product_id': productId,
      'product_name': productName,
      'brand_name': brandName,
      'category_name': categoryName,
      'size': size,
      'sku': sku,
      'quantity': quantity,
      'unit_price': unitPrice,
      'total_price': totalPrice,
      'discount_amount': discountAmount,
      'opening_stock': openingStock,
      'closing_stock': closingStock,
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
      returnDate: DateTimeHelper.parseIsoToLocal(json['return_date']) ?? DateTime.now(),
      reason: json['reason'] as String,
      returnAmount: (json['return_amount'] as num).toDouble(),
      status: json['status'] as String? ?? 'pending',
      approvedAt: DateTimeHelper.parseIsoToLocal(json['approved_at']),
      createdAt: DateTimeHelper.parseIsoToLocal(json['created_at']) ?? DateTime.now(),
      updatedAt: DateTimeHelper.parseIsoToLocal(json['updated_at']) ?? DateTime.now(),
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
      recordDate: DateTimeHelper.parseIsoToLocal(json['record_date']) ?? DateTime.now(),
      totalSales: (json['total_sales'] as num).toDouble(),
      totalReturns: (json['total_returns'] as num?)?.toDouble() ?? 0,
      netSales: (json['net_sales'] as num).toDouble(),
      salesCount: json['sales_count'] as int,
      returnsCount: json['returns_count'] as int? ?? 0,
      status: json['status'] as String? ?? 'pending',
      approvedAt: DateTimeHelper.parseIsoToLocal(json['approved_at']),
      createdAt: DateTimeHelper.parseIsoToLocal(json['created_at']) ?? DateTime.now(),
      updatedAt: DateTimeHelper.parseIsoToLocal(json['updated_at']) ?? DateTime.now(),
    );
  }

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
}

// ==================== REVERT OTP MODELS ====================

/// Response when requesting OTP for sale revert
class RevertOtpResponse {
  final String saleId;
  final String message;
  final bool emailSent;
  final bool phoneSent;
  final DateTime expiresAt;

  RevertOtpResponse({
    required this.saleId,
    required this.message,
    required this.emailSent,
    required this.phoneSent,
    required this.expiresAt,
  });

  factory RevertOtpResponse.fromJson(Map<String, dynamic> json) {
    return RevertOtpResponse(
      saleId: json['sale_id'] as String? ?? '',
      message: json['message'] as String? ?? 'OTP sent successfully',
      emailSent: json['email_sent'] as bool? ?? true,
      phoneSent: json['phone_sent'] as bool? ?? true,
      // Use DateTimeHelper to properly handle timezone conversion
      expiresAt: json['expires_at'] != null
          ? DateTimeHelper.parseIsoToLocal(json['expires_at'] as String) ?? DateTime.now().add(const Duration(minutes: 10))
          : DateTime.now().add(const Duration(minutes: 10)),
    );
  }

  /// Extract masked email from message (e.g., "OTPs sent to ad***@domain.com and ***1234")
  String get maskedEmail {
    final match = RegExp(r'([a-z]+\*+@[a-z]+\.[a-z]+)').firstMatch(message);
    return match?.group(1) ?? '***@***.com';
  }

  /// Extract masked phone from message
  String get maskedPhone {
    final match = RegExp(r'\*+\d{4}').firstMatch(message);
    return match?.group(0) ?? '******1234';
  }

  /// Check if OTP has expired
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Get remaining time in seconds (10 minutes = 600 seconds)
  int get remainingSeconds {
    final diff = expiresAt.difference(DateTime.now()).inSeconds;
    return diff > 0 ? diff : 0;
  }
}
