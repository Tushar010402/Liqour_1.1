/// Vendor Management Models
///
/// Complete data structures for vendor/supplier management including:
/// - Vendor master data
/// - Bank account information
/// - Transaction history (purchases/payments)
library;

class Vendor {
  final String id;
  final String name;
  final String? contactPerson;
  final String? email;
  final String? phone;
  final String? address;
  final String? city;
  final String? state;
  final String? country;
  final String? postalCode;
  final String? taxId;
  final double creditLimit;
  final String? paymentTerms;
  final bool isActive;
  final double totalPurchases;
  final double outstandingBalance;
  final List<VendorBankAccount> bankAccounts;
  final DateTime createdAt;
  final DateTime updatedAt;

  Vendor({
    required this.id,
    required this.name,
    this.contactPerson,
    this.email,
    this.phone,
    this.address,
    this.city,
    this.state,
    this.country,
    this.postalCode,
    this.taxId,
    this.creditLimit = 0.0,
    this.paymentTerms,
    this.isActive = true,
    this.totalPurchases = 0.0,
    this.outstandingBalance = 0.0,
    this.bankAccounts = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  factory Vendor.fromJson(Map<String, dynamic> json) {
    return Vendor(
      id: json['id'] as String,
      name: json['name'] as String,
      contactPerson: json['contact_person'] as String?,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      address: json['address'] as String?,
      city: json['city'] as String?,
      state: json['state'] as String?,
      country: json['country'] as String?,
      postalCode: json['postal_code'] as String?,
      taxId: json['tax_id'] as String?,
      creditLimit: (json['credit_limit'] ?? 0).toDouble(),
      paymentTerms: json['payment_terms'] as String?,
      isActive: json['is_active'] ?? true,
      totalPurchases: (json['total_purchases'] ?? 0).toDouble(),
      outstandingBalance: (json['outstanding_balance'] ?? 0).toDouble(),
      bankAccounts: (json['bank_accounts'] as List?)
              ?.map((e) => VendorBankAccount.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'contact_person': contactPerson,
      'email': email,
      'phone': phone,
      'address': address,
      'city': city,
      'state': state,
      'country': country,
      'postal_code': postalCode,
      'tax_id': taxId,
      'credit_limit': creditLimit,
      'payment_terms': paymentTerms,
      'is_active': isActive,
    };
  }

  Vendor copyWith({
    String? id,
    String? name,
    String? contactPerson,
    String? email,
    String? phone,
    String? address,
    String? city,
    String? state,
    String? country,
    String? postalCode,
    String? taxId,
    double? creditLimit,
    String? paymentTerms,
    bool? isActive,
    double? totalPurchases,
    double? outstandingBalance,
    List<VendorBankAccount>? bankAccounts,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Vendor(
      id: id ?? this.id,
      name: name ?? this.name,
      contactPerson: contactPerson ?? this.contactPerson,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      city: city ?? this.city,
      state: state ?? this.state,
      country: country ?? this.country,
      postalCode: postalCode ?? this.postalCode,
      taxId: taxId ?? this.taxId,
      creditLimit: creditLimit ?? this.creditLimit,
      paymentTerms: paymentTerms ?? this.paymentTerms,
      isActive: isActive ?? this.isActive,
      totalPurchases: totalPurchases ?? this.totalPurchases,
      outstandingBalance: outstandingBalance ?? this.outstandingBalance,
      bankAccounts: bankAccounts ?? this.bankAccounts,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // Helper getters
  String get displayAddress {
    final parts = [address, city, state, postalCode]
        .where((part) => part != null && part.isNotEmpty)
        .toList();
    return parts.isEmpty ? 'No address' : parts.join(', ');
  }

  bool get hasOutstanding => outstandingBalance > 0;

  String get statusText => isActive ? 'Active' : 'Inactive';
}

/// Vendor Bank Account Model
class VendorBankAccount {
  final String id;
  final String bankName;
  final String accountNumber;
  final String accountHolder;
  final String? branchCode;
  final String? swiftCode;
  final bool isDefault;
  final DateTime createdAt;

  VendorBankAccount({
    required this.id,
    required this.bankName,
    required this.accountNumber,
    required this.accountHolder,
    this.branchCode,
    this.swiftCode,
    this.isDefault = false,
    required this.createdAt,
  });

  factory VendorBankAccount.fromJson(Map<String, dynamic> json) {
    return VendorBankAccount(
      id: json['id'] as String,
      bankName: json['bank_name'] as String,
      accountNumber: json['account_number'] as String,
      accountHolder: json['account_holder'] as String,
      branchCode: json['branch_code'] as String?,
      swiftCode: json['swift_code'] as String?,
      isDefault: json['is_default'] ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'bank_name': bankName,
      'account_number': accountNumber,
      'account_holder': accountHolder,
      'branch_code': branchCode,
      'swift_code': swiftCode,
      'is_default': isDefault,
    };
  }

  // Masked account number for display (e.g., "****1234")
  String get maskedAccountNumber {
    if (accountNumber.length <= 4) return accountNumber;
    return '****${accountNumber.substring(accountNumber.length - 4)}';
  }
}

/// Vendor Transaction Model - Tracks payments and purchases
class VendorTransaction {
  final String id;
  final String vendorId;
  final String vendorName;
  final String transactionType; // 'purchase' or 'payment'
  final double amount;
  final String description;
  final String? referenceNo;
  final String? paymentMethod;
  final String createdBy;
  final String? createdByName;
  final String? createdByRole;
  final DateTime createdAt;

  // Receipt information (from linked stock purchase)
  final String? stockPurchaseId;
  final String? receiptImageUrl;
  final String? receiptNumber;
  final DateTime? receiptDate;

  // Shop information
  final String? shopId;
  final String? shopName;

  // Items (for purchase transactions)
  final List<VendorTransactionItem> items;

  // Calculated totals
  final double? subtotal;
  final double? tdsAmount;
  final String? status;

  VendorTransaction({
    required this.id,
    required this.vendorId,
    required this.vendorName,
    required this.transactionType,
    required this.amount,
    required this.description,
    this.referenceNo,
    this.paymentMethod,
    required this.createdBy,
    this.createdByName,
    this.createdByRole,
    required this.createdAt,
    this.stockPurchaseId,
    this.receiptImageUrl,
    this.receiptNumber,
    this.receiptDate,
    this.shopId,
    this.shopName,
    this.items = const [],
    this.subtotal,
    this.tdsAmount,
    this.status,
  });

  factory VendorTransaction.fromJson(Map<String, dynamic> json) {
    // Parse items if available
    List<VendorTransactionItem> items = [];
    if (json['items'] != null && json['items'] is List) {
      items = (json['items'] as List)
          .map((e) => VendorTransactionItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    return VendorTransaction(
      id: json['id'] as String,
      vendorId: json['vendor_id'] as String,
      vendorName: json['vendor_name'] as String? ?? '',
      transactionType: json['transaction_type'] as String,
      amount: (json['amount']).toDouble(),
      description: json['description'] as String? ?? '',
      referenceNo: json['reference_no'] as String?,
      paymentMethod: json['payment_method'] as String?,
      createdBy: json['created_by'] as String? ?? '',
      createdByName: json['created_by_name'] as String?,
      createdByRole: json['created_by_role'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      // Receipt fields
      stockPurchaseId: json['stock_purchase_id'] as String?,
      receiptImageUrl: json['receipt_image_url'] as String?,
      receiptNumber: json['receipt_number'] as String?,
      receiptDate: json['receipt_date'] != null
          ? DateTime.parse(json['receipt_date'] as String)
          : null,
      // Shop fields
      shopId: json['shop_id'] as String?,
      shopName: json['shop_name'] as String?,
      // Items and totals
      items: items,
      subtotal: json['subtotal'] != null ? (json['subtotal']).toDouble() : null,
      tdsAmount: json['tds_amount'] != null ? (json['tds_amount']).toDouble() : null,
      status: json['status'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'vendor_id': vendorId,
      'transaction_type': transactionType,
      'amount': amount,
      'description': description,
      'reference_no': referenceNo,
      'payment_method': paymentMethod,
    };
  }

  bool get isPurchase => transactionType == 'purchase';
  bool get isPayment => transactionType == 'payment';

  String get typeDisplay => isPurchase ? 'Purchase' : 'Payment';

  /// Check if this transaction has a receipt attached
  bool get hasReceipt => receiptImageUrl != null && receiptImageUrl!.isNotEmpty;

  /// Get total item count
  int get totalItemCount => items.fold(0, (sum, item) => sum + item.quantity);

  /// Get display name for created by
  String get createdByDisplay {
    if (createdByName != null && createdByName!.isNotEmpty) {
      if (createdByRole != null && createdByRole!.isNotEmpty) {
        return '$createdByName ($createdByRole)';
      }
      return createdByName!;
    }
    if (createdByRole != null && createdByRole!.isNotEmpty) {
      return createdByRole!;
    }
    return createdBy.isNotEmpty ? createdBy : 'User';
  }

  /// Calculated subtotal (amount before TDS)
  double get calculatedSubtotal => subtotal ?? amount;

  /// Calculated TDS
  double get calculatedTds => tdsAmount ?? (calculatedSubtotal * 0.01);

  /// Get status color-friendly status
  String get displayStatus => status?.toUpperCase() ?? (isPurchase ? 'APPROVED' : 'COMPLETED');
}

/// Vendor Transaction Item Model - Individual items in a purchase transaction
class VendorTransactionItem {
  final String id;
  final String? productId;
  final String productName;
  final String? brandName;
  final String size;
  final int quantity;
  final double unitPrice;
  final double totalAmount;

  VendorTransactionItem({
    required this.id,
    this.productId,
    required this.productName,
    this.brandName,
    required this.size,
    required this.quantity,
    required this.unitPrice,
    required this.totalAmount,
  });

  factory VendorTransactionItem.fromJson(Map<String, dynamic> json) {
    return VendorTransactionItem(
      id: json['id'] as String? ?? '',
      productId: json['product_id'] as String?,
      productName: json['product_name'] as String? ?? json['name'] as String? ?? '',
      brandName: json['brand_name'] as String?,
      size: json['size'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0.0,
      totalAmount: (json['total_amount'] as num?)?.toDouble() ??
                   (json['total'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'product_id': productId,
      'product_name': productName,
      'brand_name': brandName,
      'size': size,
      'quantity': quantity,
      'unit_price': unitPrice,
      'total_amount': totalAmount,
    };
  }

  /// Clean product name (remove size suffix if present)
  String get displayName {
    String name = productName;
    if (size.isNotEmpty) {
      final sizePattern = RegExp(r'\s*[-–]\s*' + RegExp.escape(size) + r'$', caseSensitive: false);
      name = name.replaceAll(sizePattern, '').trim();
      final sizeOnlyPattern = RegExp(r'\s+' + RegExp.escape(size) + r'$', caseSensitive: false);
      name = name.replaceAll(sizeOnlyPattern, '').trim();
    }
    return name;
  }
}

/// Request DTOs for creating/updating vendors
class VendorRequest {
  final String name;
  final String? contactPerson;
  final String? email;
  final String? phone;
  final String? address;
  final String? city;
  final String? state;
  final String? country;
  final String? postalCode;
  final String? taxId;
  final double? creditLimit;
  final String? paymentTerms;
  final bool? isActive;

  VendorRequest({
    required this.name,
    this.contactPerson,
    this.email,
    this.phone,
    this.address,
    this.city,
    this.state,
    this.country,
    this.postalCode,
    this.taxId,
    this.creditLimit,
    this.paymentTerms,
    this.isActive,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (contactPerson != null) 'contact_person': contactPerson,
      if (email != null) 'email': email,
      if (phone != null) 'phone': phone,
      if (address != null) 'address': address,
      if (city != null) 'city': city,
      if (state != null) 'state': state,
      if (country != null) 'country': country,
      if (postalCode != null) 'postal_code': postalCode,
      if (taxId != null) 'tax_id': taxId,
      if (creditLimit != null) 'credit_limit': creditLimit,
      if (paymentTerms != null) 'payment_terms': paymentTerms,
      if (isActive != null) 'is_active': isActive,
    };
  }
}

class VendorBankAccountRequest {
  final String bankName;
  final String accountNumber;
  final String accountHolder;
  final String? branchCode;
  final String? swiftCode;
  final bool? isDefault;

  VendorBankAccountRequest({
    required this.bankName,
    required this.accountNumber,
    required this.accountHolder,
    this.branchCode,
    this.swiftCode,
    this.isDefault,
  });

  Map<String, dynamic> toJson() {
    return {
      'bank_name': bankName,
      'account_number': accountNumber,
      'account_holder': accountHolder,
      if (branchCode != null) 'branch_code': branchCode,
      if (swiftCode != null) 'swift_code': swiftCode,
      if (isDefault != null) 'is_default': isDefault,
    };
  }
}

class VendorTransactionRequest {
  final String vendorId;
  final String transactionType;
  final double amount;
  final String description;
  final String? referenceNo;
  final String? paymentMethod;

  VendorTransactionRequest({
    required this.vendorId,
    required this.transactionType,
    required this.amount,
    required this.description,
    this.referenceNo,
    this.paymentMethod,
  });

  Map<String, dynamic> toJson() {
    return {
      'vendor_id': vendorId,
      'transaction_type': transactionType,
      'amount': amount,
      'description': description,
      if (referenceNo != null) 'reference_no': referenceNo,
      if (paymentMethod != null) 'payment_method': paymentMethod,
    };
  }
}
