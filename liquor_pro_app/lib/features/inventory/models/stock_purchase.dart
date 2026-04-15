/// Stock Purchase Models - Industrial Grade with Approval Workflow
///
/// Designed following best practices from Swiggy/Zomato-style platforms:
/// - Complete audit trail (who created, who approved, when)
/// - Role-based approval workflow
/// - Status tracking with timestamps
library;

/// Stock Purchase Request Status
enum StockPurchaseStatus {
  pending,
  approved,
  rejected,
  cancelled;

  static StockPurchaseStatus fromString(String value) {
    switch (value.toLowerCase()) {
      case 'approved':
        return StockPurchaseStatus.approved;
      case 'rejected':
        return StockPurchaseStatus.rejected;
      case 'cancelled':
        return StockPurchaseStatus.cancelled;
      default:
        return StockPurchaseStatus.pending;
    }
  }

  String get displayName {
    switch (this) {
      case StockPurchaseStatus.pending:
        return 'Pending Approval';
      case StockPurchaseStatus.approved:
        return 'Approved';
      case StockPurchaseStatus.rejected:
        return 'Rejected';
      case StockPurchaseStatus.cancelled:
        return 'Cancelled';
    }
  }

  bool get isPending => this == StockPurchaseStatus.pending;
  bool get isApproved => this == StockPurchaseStatus.approved;
  bool get isRejected => this == StockPurchaseStatus.rejected;
}

/// Individual item in a stock purchase request
class StockPurchaseItem {
  final String productId;
  final String productName;
  final String? brandName;
  final String size;
  final int quantity;
  final double costPrice;
  final double totalAmount;
  final double dutyFee; // Excise duty from gate pass (included in buying price)

  StockPurchaseItem({
    required this.productId,
    required this.productName,
    this.brandName,
    required this.size,
    required this.quantity,
    required this.costPrice,
    required this.totalAmount,
    this.dutyFee = 0.0,
  });

  factory StockPurchaseItem.fromJson(Map<String, dynamic> json) {
    // Debug: Log the raw JSON to see what backend sends
    print('📦 [StockPurchaseItem] Raw JSON: $json');
    print('📦 [StockPurchaseItem] Keys: ${json.keys.toList()}');

    final quantity = (json['quantity'] ?? 0) is int
        ? (json['quantity'] ?? 0) as int
        : (json['quantity'] ?? 0).toInt();

    // Extract nested product info if available
    final product = json['product'] as Map<String, dynamic>?;
    print('📦 [StockPurchaseItem] Product nested object: $product');

    // Extract size - check nested product first, then flat fields
    String size = '';
    if (product != null) {
      size = product['size']?.toString() ?? '';
    }
    if (size.isEmpty) {
      size = json['size']?.toString() ??
             json['pack_size']?.toString() ??
             json['product_size']?.toString() ?? '';
    }

    // Extract product name - check nested product first
    String productName = '';
    if (product != null) {
      productName = product['name']?.toString() ?? '';
    }
    if (productName.isEmpty) {
      productName = json['product_name']?.toString() ??
                    json['productName']?.toString() ?? '';
    }

    // Extract brand name - check nested product.brand first
    String? brandName;
    if (product != null) {
      final brand = product['brand'] as Map<String, dynamic>?;
      if (brand != null) {
        brandName = brand['name']?.toString();
      }
      brandName ??= product['brand_name']?.toString();
    }
    brandName ??= json['brand_name']?.toString() ?? json['brandName']?.toString();

    // Backend sends unit_cost, frontend expects cost_price - handle both
    // Also check nested product.cost_price as fallback
    double costPrice = 0;
    costPrice = (json['cost_price'] ??
                 json['costPrice'] ??
                 json['unit_cost'] ??
                 json['unitCost'] ??
                 json['unit_price'] ??
                 json['unitPrice'] ?? 0).toDouble();

    // If still 0, try getting from nested product
    if (costPrice == 0 && product != null) {
      costPrice = (product['cost_price'] ??
                   product['costPrice'] ??
                   product['selling_price'] ??
                   product['sellingPrice'] ??
                   product['mrp'] ?? 0).toDouble();
    }

    // Backend sends total_cost/total_price - handle all variations
    final totalAmount = (json['total_amount'] ??
                         json['totalAmount'] ??
                         json['total_cost'] ??
                         json['totalCost'] ??
                         json['total_price'] ??
                         json['totalPrice'] ??
                         (quantity * costPrice)).toDouble();

    return StockPurchaseItem(
      productId: json['product_id']?.toString() ?? json['productId']?.toString() ?? '',
      productName: productName,
      brandName: brandName,
      size: size,
      quantity: quantity,
      costPrice: costPrice,
      totalAmount: totalAmount,
      dutyFee: (json['duty_fee'] ?? json['dutyFee'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'product_id': productId,
      'product_name': productName,
      'brand_name': brandName,
      'size': size,
      'quantity': quantity,
      'cost_price': costPrice,
      'total_amount': totalAmount,
      if (dutyFee > 0) 'duty_fee': dutyFee,
    };
  }

  /// Create from UI selection (used when creating new purchase)
  factory StockPurchaseItem.fromSelection({
    required String productId,
    required String productName,
    String? brandName,
    required String size,
    required int quantity,
    required double costPrice,
    double dutyFee = 0.0,
  }) {
    return StockPurchaseItem(
      productId: productId,
      productName: productName,
      brandName: brandName,
      size: size,
      quantity: quantity,
      costPrice: costPrice,
      totalAmount: quantity * costPrice,
      dutyFee: dutyFee,
    );
  }
}

/// Complete Stock Purchase Request with Approval Workflow
class StockPurchase {
  final String id;
  final String shopId;
  final String shopName;
  final String vendorId;
  final String vendorName;
  final List<StockPurchaseItem> items;
  final double subtotal;
  final double tcsAmount; // Tax Collected at Source (2%)
  final double roundOff; // Round-off adjustment to make total a whole number
  final double totalAmount;
  final StockPurchaseStatus status;
  final String? notes;

  // Audit: Created By
  final String createdById;
  final String createdByName;
  final String createdByRole;
  final DateTime createdAt;

  // Audit: Approved/Rejected By
  final String? approvedById;
  final String? approvedByName;
  final String? approvedByRole;
  final DateTime? approvedAt;

  // Rejection details
  final String? rejectionReason;
  final DateTime? rejectedAt;

  // Receipt Information
  final String? receiptNumber;
  final DateTime? receiptDate;
  final String? receiptImageUrl;
  final List<String>? receiptImages;
  final String? receiptNotes;

  StockPurchase({
    required this.id,
    required this.shopId,
    required this.shopName,
    required this.vendorId,
    required this.vendorName,
    required this.items,
    required this.subtotal,
    required this.tcsAmount,
    this.roundOff = 0.0,
    required this.totalAmount,
    required this.status,
    this.notes,
    required this.createdById,
    required this.createdByName,
    required this.createdByRole,
    required this.createdAt,
    this.approvedById,
    this.approvedByName,
    this.approvedByRole,
    this.approvedAt,
    this.rejectionReason,
    this.rejectedAt,
    this.receiptNumber,
    this.receiptDate,
    this.receiptImageUrl,
    this.receiptImages,
    this.receiptNotes,
  });

  factory StockPurchase.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List?)
            ?.map((item) => StockPurchaseItem.fromJson(item as Map<String, dynamic>))
            .toList() ??
        [];

    // Calculate subtotal from items (source of truth)
    final calculatedSubtotal = items.fold(0.0, (sum, item) => sum + item.totalAmount);

    // Backend sends sub_total, frontend expects subtotal - handle both
    // Use ?? for null check, but also check if value is 0 (backend might send 0)
    final rawSubtotal = json['subtotal'] ?? json['sub_total'] ?? json['subTotal'];
    final subtotal = (rawSubtotal != null && rawSubtotal != 0)
        ? (rawSubtotal as num).toDouble()
        : calculatedSubtotal;

    // Calculate TCS (2% of subtotal) - Tax Collected at Source
    final calculatedTcs = subtotal * 0.02;

    // Backend sends tax_amount - handle all variations for backward compat
    final rawTcs = json['tax_amount'] ?? json['taxAmount'] ?? json['tcs_amount'] ?? json['tcsAmount'] ?? json['tds_amount'] ?? json['tdsAmount'];
    final tcsAmount = (rawTcs != null && rawTcs != 0)
        ? (rawTcs as num).toDouble()
        : calculatedTcs;

    // Parse round_off from backend
    final rawRoundOff = json['round_off'] ?? json['roundOff'];
    final roundOff = (rawRoundOff != null) ? (rawRoundOff as num).toDouble() : 0.0;

    // Always calculate total from components to ensure accuracy
    // Formula: Subtotal + TCS (2%) + Round Off = Total
    // Don't trust backend total as it may be incorrect
    final totalAmount = subtotal + tcsAmount + roundOff;

    // Extract shop info - handle nested object or flat fields
    String shopId = '';
    String shopName = '';
    if (json['shop'] is Map<String, dynamic>) {
      final shop = json['shop'] as Map<String, dynamic>;
      shopId = shop['id']?.toString() ?? '';
      shopName = shop['name']?.toString() ?? '';
    }
    shopId = json['shop_id']?.toString() ?? json['shopId']?.toString() ?? shopId;
    shopName = json['shop_name']?.toString() ?? json['shopName']?.toString() ?? shopName;

    // Extract vendor info - handle nested object or flat fields
    String vendorId = '';
    String vendorName = '';
    if (json['vendor'] is Map<String, dynamic>) {
      final vendor = json['vendor'] as Map<String, dynamic>;
      vendorId = vendor['id']?.toString() ?? '';
      vendorName = vendor['name']?.toString() ?? '';
    }
    vendorId = json['vendor_id']?.toString() ?? json['vendorId']?.toString() ?? vendorId;
    vendorName = json['vendor_name']?.toString() ?? json['vendorName']?.toString() ?? vendorName;

    // Extract created_by info - handle nested object or flat fields
    String createdById = '';
    String createdByName = '';
    String createdByRole = '';
    if (json['created_by_user'] is Map<String, dynamic>) {
      final user = json['created_by_user'] as Map<String, dynamic>;
      createdById = user['id']?.toString() ?? '';
      // Try multiple name field combinations
      createdByName = user['full_name']?.toString() ??
                      user['name']?.toString() ?? '';
      // If no full_name, try first_name + last_name
      if (createdByName.isEmpty) {
        final firstName = user['first_name']?.toString() ?? '';
        final lastName = user['last_name']?.toString() ?? '';
        if (firstName.isNotEmpty || lastName.isNotEmpty) {
          createdByName = '$firstName $lastName'.trim();
        }
      }
      createdByRole = user['role']?.toString() ?? '';
    }
    createdById = json['created_by_id']?.toString() ??
                  json['createdById']?.toString() ??
                  json['created_by']?.toString() ??
                  createdById;
    // Check flat fields for name - try multiple variations
    if (createdByName.isEmpty) {
      createdByName = json['created_by_name']?.toString() ??
                      json['createdByName']?.toString() ??
                      json['creator_name']?.toString() ??
                      '';
    }
    createdByRole = json['created_by_role']?.toString() ??
                    json['createdByRole']?.toString() ??
                    createdByRole;

    return StockPurchase(
      id: json['id']?.toString() ?? '',
      shopId: shopId,
      shopName: shopName,
      vendorId: vendorId,
      vendorName: vendorName,
      items: items,
      subtotal: subtotal,
      tcsAmount: tcsAmount,
      roundOff: roundOff,
      totalAmount: totalAmount,
      status: StockPurchaseStatus.fromString(json['status'] ?? 'pending'),
      notes: json['notes']?.toString(),
      createdById: createdById,
      createdByName: createdByName,
      createdByRole: createdByRole,
      // Backend sends IST timestamps - parse and convert to local for display
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'].toString()).toLocal()
          : DateTime.now(),
      approvedById: json['approved_by_id']?.toString() ?? json['approvedById']?.toString(),
      approvedByName: json['approved_by_name']?.toString() ?? json['approvedByName']?.toString(),
      approvedByRole: json['approved_by_role']?.toString() ?? json['approvedByRole']?.toString(),
      // Backend sends IST timestamps - parse and convert to local
      approvedAt: json['approved_at'] != null
          ? DateTime.parse(json['approved_at'].toString()).toLocal()
          : (json['received_at'] != null ? DateTime.parse(json['received_at'].toString()).toLocal() : null),
      rejectionReason: json['rejection_reason']?.toString() ?? json['rejectionReason']?.toString(),
      // Backend sends IST timestamps - parse and convert to local
      rejectedAt: json['rejected_at'] != null
          ? DateTime.parse(json['rejected_at'].toString()).toLocal()
          : null,
      // Receipt Information
      receiptNumber: json['receipt_number']?.toString() ?? json['receiptNumber']?.toString(),
      receiptDate: json['receipt_date'] != null
          ? DateTime.parse(json['receipt_date'].toString()).toLocal()
          : (json['receiptDate'] != null ? DateTime.parse(json['receiptDate'].toString()).toLocal() : null),
      receiptImageUrl: json['receipt_image_url']?.toString() ?? json['receiptImageUrl']?.toString(),
      receiptImages: (json['receipt_images'] as List?)?.map((e) => e.toString()).toList(),
      receiptNotes: json['receipt_notes']?.toString() ?? json['receiptNotes']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'shop_id': shopId,
      'shop_name': shopName,
      'vendor_id': vendorId,
      'vendor_name': vendorName,
      'items': items.map((item) => item.toJson()).toList(),
      'subtotal': subtotal,
      'tax_amount': tcsAmount,
      'round_off': roundOff,
      'total_amount': totalAmount,
      'status': status.name,
      'notes': notes,
      'created_by_id': createdById,
      'created_by_name': createdByName,
      'created_by_role': createdByRole,
      'created_at': createdAt.toIso8601String(),
      'approved_by_id': approvedById,
      'approved_by_name': approvedByName,
      'approved_by_role': approvedByRole,
      'approved_at': approvedAt?.toIso8601String(),
      'rejection_reason': rejectionReason,
      'rejected_at': rejectedAt?.toIso8601String(),
      // Receipt Information
      if (receiptNumber != null) 'receipt_number': receiptNumber,
      if (receiptDate != null) 'receipt_date': receiptDate!.toUtc().toIso8601String(),
      if (receiptImageUrl != null) 'receipt_image_url': receiptImageUrl,
      if (receiptImages != null && receiptImages!.isNotEmpty) 'receipt_images': receiptImages,
      if (receiptNotes != null) 'receipt_notes': receiptNotes,
    };
  }

  /// Get total item count
  int get totalItemCount => items.fold(0, (sum, item) => sum + item.quantity);

  /// Get formatted total amount
  String get formattedTotal => '₹${totalAmount.toStringAsFixed(2)}';

  /// Check if purchase can be approved by a given role
  ///
  /// Approval Rules:
  /// - Admin can approve ANY purchase (including from other admins)
  /// - Manager can approve purchases from assistant_manager and below
  /// - Assistant Manager can approve from executive and below
  /// - Only pending purchases can be approved
  bool canBeApprovedBy(String userRole) {
    if (!status.isPending) return false;

    final role = userRole.toLowerCase();

    // Admin and Manager can approve ANY pending purchase
    if (role == 'admin' || role == 'manager') {
      return true;
    }

    // Role hierarchy for other roles
    const roleHierarchy = {
      'assistant_manager': 3,
      'executive': 2,
      'salesman': 1,
    };

    final approverLevel = roleHierarchy[role] ?? 0;
    final creatorLevel = roleHierarchy[createdByRole.toLowerCase()] ?? 0;

    // Approver must be at least one level above creator
    // (Assistant Manager can approve executive/salesman purchases)
    return approverLevel > creatorLevel && approverLevel >= 3;
  }

  /// Check if this purchase needs approval
  /// NOTE: Backend updated - ALL purchases now require approval
  bool get needsApproval => true;

  /// Get time since creation
  Duration get timeSinceCreation => DateTime.now().difference(createdAt);

  /// Get formatted time ago string
  String get timeAgo {
    final diff = timeSinceCreation;
    if (diff.inDays > 0) {
      return '${diff.inDays}d ago';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}h ago';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  /// Get formatted date string (e.g., "03 Dec 2025, 11:30 PM")
  String get formattedDate {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final day = createdAt.day.toString().padLeft(2, '0');
    final month = months[createdAt.month - 1];
    final year = createdAt.year;
    final hour = createdAt.hour > 12 ? createdAt.hour - 12 : (createdAt.hour == 0 ? 12 : createdAt.hour);
    final minute = createdAt.minute.toString().padLeft(2, '0');
    final period = createdAt.hour >= 12 ? 'PM' : 'AM';
    return '$day $month $year, $hour:$minute $period';
  }
}

/// Request DTO for creating a new stock purchase
class CreateStockPurchaseRequest {
  final String shopId;
  final String vendorId;
  final List<StockPurchaseItem> items;
  final String? notes;
  final double? roundOff; // Round-off adjustment (auto-calculated or manual)
  // Receipt Information
  final String? receiptNumber;
  final DateTime? receiptDate;
  final String? receiptImageUrl;
  final List<String>? receiptImages;
  final String? receiptNotes;

  CreateStockPurchaseRequest({
    required this.shopId,
    required this.vendorId,
    required this.items,
    this.notes,
    this.roundOff,
    this.receiptNumber,
    this.receiptDate,
    this.receiptImageUrl,
    this.receiptImages,
    this.receiptNotes,
  });

  Map<String, dynamic> toJson() {
    return {
      'shop_id': shopId,
      'vendor_id': vendorId,
      'items': items.map((item) {
        return <String, dynamic>{
          'product_id': item.productId,
          'quantity': item.quantity,
          'unit_price': item.costPrice,  // Backend expects unit_price
          'total_price': item.totalAmount,
          if (item.dutyFee > 0) 'duty_fee': item.dutyFee,
        };
      }).toList(),
      'total_amount': totalAmount, // Send total (subtotal + TCS + round-off) to backend
      if (notes != null) 'notes': notes,
      'round_off': roundOff ?? calculatedRoundOff, // Send round-off to backend
      // Receipt Information - backend expects 'receipt_no'
      if (receiptNumber != null) 'receipt_no': receiptNumber,
      if (receiptDate != null) 'receipt_date': receiptDate!.toUtc().toIso8601String(),
      if (receiptImageUrl != null) 'receipt_image_url': receiptImageUrl,
      if (receiptImages != null && receiptImages!.isNotEmpty) 'receipt_images': receiptImages,
      if (receiptNotes != null) 'receipt_notes': receiptNotes,
    };
  }

  double get subtotal => items.fold(0.0, (sum, item) => sum + item.totalAmount);
  double get tcsAmount => subtotal * 0.02; // 2% TCS (Tax Collected at Source)

  /// Auto-calculate round-off to make total a whole number
  double get calculatedRoundOff {
    final afterTds = subtotal + tcsAmount;
    final rounded = afterTds.round().toDouble();
    return rounded - afterTds;
  }

  /// Get effective round-off (use provided or calculate)
  double get effectiveRoundOff => roundOff ?? calculatedRoundOff;

  double get totalAmount => subtotal + tcsAmount + effectiveRoundOff;
}

/// Response wrapper for paginated purchase list
class StockPurchaseListResponse {
  final List<StockPurchase> purchases;
  final int total;
  final int page;
  final int limit;

  StockPurchaseListResponse({
    required this.purchases,
    required this.total,
    this.page = 1,
    this.limit = 20,
  });

  factory StockPurchaseListResponse.fromJson(Map<String, dynamic> json) {
    final purchasesList = (json['purchases'] as List?)
            ?.map((p) => StockPurchase.fromJson(p as Map<String, dynamic>))
            .toList() ??
        [];

    return StockPurchaseListResponse(
      purchases: purchasesList,
      total: json['total'] ?? purchasesList.length,
      page: json['page'] ?? 1,
      limit: json['limit'] ?? 20,
    );
  }

  bool get hasMore => purchases.length >= limit;
}
