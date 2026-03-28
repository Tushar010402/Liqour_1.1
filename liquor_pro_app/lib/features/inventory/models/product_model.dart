/// Product Model
class Product {
  final String id;
  final String name;
  final String? description;
  final String categoryId;
  final String brandId;
  final String? categoryName;
  final String? brandName;
  final double costPrice;
  final double sellingPrice;
  final double? mrp;
  final String? barcode;
  final String? sku;
  final int? minStockLevel;
  final double? alcoholPercentage;
  final String? size;
  final double? volume;
  final double? alcoholContent;
  final int? stockQuantity;
  final double? dutyFee;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Product({
    required this.id,
    required this.name,
    this.description,
    required this.categoryId,
    required this.brandId,
    this.categoryName,
    this.brandName,
    required this.costPrice,
    required this.sellingPrice,
    this.mrp,
    this.barcode,
    this.sku,
    this.minStockLevel,
    this.alcoholPercentage,
    this.size,
    this.volume,
    this.alcoholContent,
    this.stockQuantity,
    this.dutyFee,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      description: json['description'],
      categoryId: json['category_id']?.toString() ?? '',
      brandId: json['brand_id']?.toString() ?? '',
      categoryName: json['category_name'],
      brandName: json['brand_name'],
      costPrice: (json['cost_price'] ?? 0).toDouble(),
      sellingPrice: (json['selling_price'] ?? 0).toDouble(),
      mrp: json['mrp']?.toDouble(),
      barcode: json['barcode'],
      sku: json['sku'],
      minStockLevel: json['min_stock_level'],
      alcoholPercentage: json['alcohol_percentage']?.toDouble(),
      size: json['size'],
      volume: json['volume']?.toDouble(),
      alcoholContent: json['alcohol_content']?.toDouble(),
      stockQuantity: json['current_stock'] ?? json['stock_quantity'],
      dutyFee: json['duty_fee']?.toDouble() ?? json['government_duty']?.toDouble(),
      isActive: json['is_active'] ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'category_id': categoryId,
      'brand_id': brandId,
      'cost_price': costPrice,
      'selling_price': sellingPrice,
      'mrp': mrp,
      'barcode': barcode,
      'sku': sku,
      'min_stock_level': minStockLevel,
      'alcohol_percentage': alcoholPercentage,
      'size': size,
      'volume': volume,
      'alcohol_content': alcoholContent,
      'is_active': isActive,
    };
  }

  double get profit => sellingPrice - costPrice;
  double get profitMargin => costPrice > 0 ? (profit / costPrice) * 100 : 0;
}
