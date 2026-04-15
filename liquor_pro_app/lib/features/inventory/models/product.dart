import 'brand.dart';

/// Product Model - Matches backend Product structure
class Product {
  final String id;
  final String name;
  final String displayName;
  final String categoryId;
  final Category? category;
  final String? subcategoryId;
  final Subcategory? subcategory;
  final String brandId;
  final Brand? brand;
  final String? templateId;
  final String size;
  final double alcoholContent;
  final String description;
  final String barcode;
  final String sku;
  final String imageUrl;
  final bool isActive;
  final double costPrice;
  final double dutyFee;
  final double totalCost;
  final double sellingPrice;
  final double mrp;
  final int? stockQuantity;
  final DateTime createdAt;
  final DateTime updatedAt;

  Product({
    required this.id,
    required this.name,
    this.displayName = '',
    required this.categoryId,
    this.category,
    this.subcategoryId,
    this.subcategory,
    required this.brandId,
    this.brand,
    this.templateId,
    required this.size,
    required this.alcoholContent,
    required this.description,
    required this.barcode,
    required this.sku,
    required this.imageUrl,
    required this.isActive,
    required this.costPrice,
    required this.dutyFee,
    required this.totalCost,
    required this.sellingPrice,
    required this.mrp,
    this.stockQuantity,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    final stockFromCurrentStock = json['current_stock'];
    final stockFromStockQuantity = json['stock_quantity'];
    final finalStock = stockFromCurrentStock ?? stockFromStockQuantity;

    // Create Brand object from flat brand_name if nested brand doesn't exist
    Brand? brand;
    if (json['brand'] != null) {
      brand = Brand.fromJson(json['brand'] as Map<String, dynamic>);
    } else if (json['brand_name'] != null && json['brand_id'] != null) {
      // API returns flat fields - create Brand object from them
      brand = Brand(
        id: json['brand_id'] ?? '',
        name: json['brand_name'] ?? '',
        description: '',
        isActive: true,
      );
    }

    // Create Category object from flat category_name if nested category doesn't exist
    Category? category;
    if (json['category'] != null) {
      category = Category.fromJson(json['category'] as Map<String, dynamic>);
    } else if (json['category_name'] != null && json['category_id'] != null) {
      // API returns flat fields - create Category object from them
      category = Category(
        id: json['category_id'] ?? '',
        name: json['category_name'] ?? '',
        description: '',
        isActive: true,
        sortOrder: 0,
      );
    }

    return Product(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      displayName: json['display_name'] ?? '',
      categoryId: json['category_id'] ?? '',
      category: category,
      subcategoryId: json['subcategory_id'],
      subcategory: json['subcategory'] != null
          ? Subcategory.fromJson(json['subcategory'] as Map<String, dynamic>)
          : null,
      brandId: json['brand_id'] ?? '',
      brand: brand,
      templateId: json['template_id'],
      size: json['size'] ?? '',
      alcoholContent: (json['alcohol_content'] ?? 0).toDouble(),
      description: json['description'] ?? '',
      barcode: json['barcode'] ?? '',
      sku: json['sku'] ?? '',
      imageUrl: json['image_url'] ?? '',
      isActive: json['is_active'] ?? true,
      costPrice: (json['cost_price'] ?? 0).toDouble(),
      dutyFee: (json['duty_fee'] ?? 0).toDouble(),
      totalCost: (json['total_cost'] ?? 0).toDouble(),
      sellingPrice: (json['selling_price'] ?? 0).toDouble(),
      mrp: (json['mrp'] ?? 0).toDouble(),
      stockQuantity: finalStock,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'category_id': categoryId,
      'subcategory_id': subcategoryId,
      'brand_id': brandId,
      'template_id': templateId,
      'size': size,
      'alcohol_content': alcoholContent,
      'description': description,
      'barcode': barcode,
      'sku': sku,
      'image_url': imageUrl,
      'is_active': isActive,
      'cost_price': costPrice,
      'duty_fee': dutyFee,
      'total_cost': totalCost,
      'selling_price': sellingPrice,
      'mrp': mrp,
    };
  }

  // ==================== Backward-Compatible Getters ====================

  /// Get clean display name — uses display_name if set, otherwise strips size from name
  String get cleanName {
    if (displayName.isNotEmpty) return displayName;
    // Strip " - XXXML" suffix from name
    return name
        .replaceAll(RegExp(r'\s*-\s*\d+(?:\.\d+)?\s*(?:ml|ML|ltr|LTR|L)\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\d+(?:\.\d+)?\s*(?:ml|ML|ltr|LTR|L)\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*-\s*$'), '')
        .trim();
  }

  /// Get brand name (backward compatible)
  String? get brandName => brand?.name;

  /// Get category name as string (backward compatible)
  String? get categoryName => category?.name;

  /// Get stock quantity (alias for stockQuantity)
  int get stock => stockQuantity ?? 0;

  /// Check if low stock
  bool get isLowStock => stock > 0 && stock <= 10;

  /// Check if out of stock
  bool get isOutOfStock => stock <= 0;
}

/// SizeWithCount Model - For displaying size filters with product counts AND stock totals
/// Industrial Best Practice: Backend returns aggregated counts for efficient filtering UX
/// Enhanced: Now includes totalStockQuantity for showing actual stock on size filter chips
class SizeWithCount {
  final String size;
  final int productCount;
  final int totalStockQuantity; // Sum of stock for all products of this size

  SizeWithCount({
    required this.size,
    required this.productCount,
    this.totalStockQuantity = 0,
  });

  factory SizeWithCount.fromJson(Map<String, dynamic> json) {
    return SizeWithCount(
      size: _normalizeSize((json['SIZE'] ?? json['size'] ?? '').toString()),
      productCount: _parseInt(json['PRODUCT_COUNT'] ?? json['product_count'] ?? json['count']) ?? 0,
      totalStockQuantity: _parseInt(json['TOTAL_STOCK'] ?? json['total_stock'] ?? json['stock_total']) ?? 0,
    );
  }

  /// Normalize size — keep range labels as-is, uppercase raw sizes
  static String _normalizeSize(String size) {
    size = size.trim();
    if (size.contains('(') || size.contains('Below') || size.contains('Bulk') || size.contains('Large')) return size;
    return size.toUpperCase();
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  /// Display label with product count (e.g., "90ML (2)")
  String get displayLabel => '$size ($productCount)';

  /// Display label with stock total (e.g., "90ML • 180 units")
  String get displayLabelWithStock => totalStockQuantity > 0 ? '$size • $totalStockQuantity' : size;

  /// Create a copy with updated stock quantity
  SizeWithCount copyWithStockQuantity(int stockQty) {
    return SizeWithCount(
      size: size,
      productCount: productCount,
      totalStockQuantity: stockQty,
    );
  }
}

/// Category Model
class Category {
  final String id;
  final String name;
  final String description;
  final bool isActive;
  final int sortOrder;
  final int? productCount; // Product count for filter badge display
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Category({
    required this.id,
    required this.name,
    required this.description,
    required this.isActive,
    required this.sortOrder,
    this.productCount,
    this.createdAt,
    this.updatedAt,
  });

  /// Display label with count (e.g., "Whisky (80)")
  String get displayLabel => productCount != null && productCount! > 0
      ? '$name ($productCount)'
      : name;

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      isActive: json['is_active'] ?? true,
      sortOrder: json['sort_order'] ?? 0,
      productCount: json['product_count'] ?? json['PRODUCT_COUNT'],
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'is_active': isActive,
      'sort_order': sortOrder,
    };
  }
}

/// Subcategory Model
class Subcategory {
  final String id;
  final String name;
  final String categoryId;
  final String priceRange;
  final String description;
  final int sortOrder;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Subcategory({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.priceRange,
    required this.description,
    required this.sortOrder,
    required this.isActive,
    this.createdAt,
    this.updatedAt,
  });

  factory Subcategory.fromJson(Map<String, dynamic> json) {
    return Subcategory(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      categoryId: json['category_id'] ?? '',
      priceRange: json['price_range'] ?? '',
      description: json['description'] ?? '',
      sortOrder: json['sort_order'] ?? 0,
      isActive: json['is_active'] ?? true,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'category_id': categoryId,
      'price_range': priceRange,
      'description': description,
      'sort_order': sortOrder,
      'is_active': isActive,
    };
  }
}

/// Stock Model (for displaying stock levels)
class Stock {
  final String id;
  final String shopId;
  final String productId;
  final String? productName;
  final String? imageUrl;
  final int quantity;
  final int reservedQuantity;
  final int minimumLevel;
  final int maximumLevel;
  final double averageCost;
  final double lastPurchasePrice;
  final DateTime? lastPurchaseDate;
  final DateTime createdAt;
  final DateTime updatedAt;

  Stock({
    required this.id,
    required this.shopId,
    required this.productId,
    this.productName,
    this.imageUrl,
    required this.quantity,
    required this.reservedQuantity,
    required this.minimumLevel,
    required this.maximumLevel,
    required this.averageCost,
    required this.lastPurchasePrice,
    this.lastPurchaseDate,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Stock.fromJson(Map<String, dynamic> json) {
    try {
      return Stock(
        id: json['id']?.toString() ?? '',
        shopId: json['shop_id']?.toString() ?? '',
        productId: json['product_id']?.toString() ?? '',
        productName: json['product_name']?.toString() ?? json['product']?['name']?.toString(),
        imageUrl: json['image_url']?.toString() ?? json['product']?['image_url']?.toString(),
        quantity: _parseInt(json['quantity']) ?? 0,
        reservedQuantity: _parseInt(json['reserved_quantity']) ?? 0,
        minimumLevel: _parseInt(json['minimum_level']) ?? 0,
        maximumLevel: _parseInt(json['maximum_level']) ?? 0,
        averageCost: _parseDouble(json['average_cost']) ?? 0.0,
        lastPurchasePrice: _parseDouble(json['last_purchase_price']) ?? 0.0,
        lastPurchaseDate: json['last_purchase_date'] != null
            ? DateTime.tryParse(json['last_purchase_date'].toString())
            : null,
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'].toString())
            : DateTime.now(),
        updatedAt: json['updated_at'] != null
            ? DateTime.parse(json['updated_at'].toString())
            : DateTime.now(),
      );
    } catch (e) {
      print('❌ Error parsing Stock from JSON: $e');
      print('JSON data: $json');
      rethrow;
    }
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  /// Check if stock is low
  bool get isLowStock => quantity <= minimumLevel;

  /// Check if stock is out
  bool get isOutOfStock => quantity <= 0;

  /// Available quantity (total - reserved)
  int get availableQuantity => quantity - reservedQuantity;

  /// Create a copy with updated fields
  Stock copyWith({
    String? id,
    String? shopId,
    String? productId,
    String? productName,
    String? imageUrl,
    int? quantity,
    int? reservedQuantity,
    int? minimumLevel,
    int? maximumLevel,
    double? averageCost,
    double? lastPurchasePrice,
    DateTime? lastPurchaseDate,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Stock(
      id: id ?? this.id,
      shopId: shopId ?? this.shopId,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      imageUrl: imageUrl ?? this.imageUrl,
      quantity: quantity ?? this.quantity,
      reservedQuantity: reservedQuantity ?? this.reservedQuantity,
      minimumLevel: minimumLevel ?? this.minimumLevel,
      maximumLevel: maximumLevel ?? this.maximumLevel,
      averageCost: averageCost ?? this.averageCost,
      lastPurchasePrice: lastPurchasePrice ?? this.lastPurchasePrice,
      lastPurchaseDate: lastPurchaseDate ?? this.lastPurchaseDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
