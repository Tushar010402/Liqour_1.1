import 'brand.dart';

/// Product Model - Matches backend Product structure
class Product {
  final String id;
  final String name;
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
  final DateTime createdAt;
  final DateTime updatedAt;

  Product({
    required this.id,
    required this.name,
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
    required this.createdAt,
    required this.updatedAt,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      categoryId: json['category_id'] ?? '',
      category: json['category'] != null
          ? Category.fromJson(json['category'] as Map<String, dynamic>)
          : null,
      subcategoryId: json['subcategory_id'],
      subcategory: json['subcategory'] != null
          ? Subcategory.fromJson(json['subcategory'] as Map<String, dynamic>)
          : null,
      brandId: json['brand_id'] ?? '',
      brand: json['brand'] != null
          ? Brand.fromJson(json['brand'] as Map<String, dynamic>)
          : null,
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
}

/// Category Model
class Category {
  final String id;
  final String name;
  final String description;
  final bool isActive;
  final int sortOrder;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Category({
    required this.id,
    required this.name,
    required this.description,
    required this.isActive,
    required this.sortOrder,
    this.createdAt,
    this.updatedAt,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      isActive: json['is_active'] ?? true,
      sortOrder: json['sort_order'] ?? 0,
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
    return Stock(
      id: json['id'] ?? '',
      shopId: json['shop_id'] ?? '',
      productId: json['product_id'] ?? '',
      quantity: json['quantity'] ?? 0,
      reservedQuantity: json['reserved_quantity'] ?? 0,
      minimumLevel: json['minimum_level'] ?? 0,
      maximumLevel: json['maximum_level'] ?? 0,
      averageCost: (json['average_cost'] ?? 0).toDouble(),
      lastPurchasePrice: (json['last_purchase_price'] ?? 0).toDouble(),
      lastPurchaseDate: json['last_purchase_date'] != null
          ? DateTime.parse(json['last_purchase_date'])
          : null,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  /// Check if stock is low
  bool get isLowStock => quantity <= minimumLevel;

  /// Check if stock is out
  bool get isOutOfStock => quantity <= 0;

  /// Available quantity (total - reserved)
  int get availableQuantity => quantity - reservedQuantity;
}
