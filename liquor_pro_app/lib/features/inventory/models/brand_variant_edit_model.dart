import 'product.dart';

/// Brand Variant Edit Model
///
/// Represents a brand variant (product) for editing
/// Matches SaaS Admin's brand variant structure
class BrandVariantEditModel {
  // Identification
  final String id;
  final String brandId;
  final String brandName;

  // Category Selection (from SaaS Brand Categories)
  String categoryId;
  String? subcategoryId;

  // Variant Details
  String size;             // From category sizes
  double alcoholContent;
  String description;
  String barcode;
  String hsnCode;
  String? imageUrl;

  // Pricing (matches SaaS Admin terminology)
  double governmentDuty;
  double buyingPrice;      // NOT "cost price"
  double sellingPrice;
  double mrp;

  // Status
  bool isActive;
  int sortOrder;

  BrandVariantEditModel({
    required this.id,
    required this.brandId,
    required this.brandName,
    required this.categoryId,
    this.subcategoryId,
    required this.size,
    required this.alcoholContent,
    required this.description,
    required this.barcode,
    required this.hsnCode,
    this.imageUrl,
    required this.governmentDuty,
    required this.buyingPrice,
    required this.sellingPrice,
    required this.mrp,
    this.isActive = true,
    this.sortOrder = 0,
  });

  /// Create from Product model
  factory BrandVariantEditModel.fromProduct(Product product) {
    return BrandVariantEditModel(
      id: product.id,
      brandId: product.brandId,
      brandName: product.brand?.name ?? product.name.split(' - ').first,
      categoryId: product.categoryId,
      subcategoryId: product.subcategoryId,
      size: product.size,
      alcoholContent: product.alcoholContent,
      description: product.description,
      barcode: product.barcode,
      hsnCode: '', // Product model doesn't have HSN, will be empty
      imageUrl: product.imageUrl.isNotEmpty ? product.imageUrl : null,
      governmentDuty: product.dutyFee,
      buyingPrice: product.costPrice, // Map cost price to buying price
      sellingPrice: product.sellingPrice,
      mrp: product.sellingPrice * 1.1, // Estimate MRP if not available
      isActive: product.isActive,
      sortOrder: 0,
    );
  }

  /// Convert to JSON for API update
  Map<String, dynamic> toJson() {
    return {
      'name': '$brandName - $size', // Backend expects full name
      'category_id': categoryId,
      if (subcategoryId != null) 'subcategory_id': subcategoryId,
      'brand_id': brandId,
      'size': size,
      'alcohol_content': alcoholContent,
      'description': description,
      'barcode': barcode,
      'sku': barcode, // Use barcode as SKU
      if (imageUrl != null) 'image_url': imageUrl,
      'is_active': isActive,
      'cost_price': buyingPrice, // Map buying price back to cost price
      'duty_fee': governmentDuty,
      'total_cost': buyingPrice, // Buying Price IS Total Cost (user request)
      'selling_price': sellingPrice,
    };
  }

  /// Create a copy with updated fields
  BrandVariantEditModel copyWith({
    String? id,
    String? brandId,
    String? brandName,
    String? categoryId,
    String? subcategoryId,
    String? size,
    double? alcoholContent,
    String? description,
    String? barcode,
    String? hsnCode,
    String? imageUrl,
    double? governmentDuty,
    double? buyingPrice,
    double? sellingPrice,
    double? mrp,
    bool? isActive,
    int? sortOrder,
  }) {
    return BrandVariantEditModel(
      id: id ?? this.id,
      brandId: brandId ?? this.brandId,
      brandName: brandName ?? this.brandName,
      categoryId: categoryId ?? this.categoryId,
      subcategoryId: subcategoryId ?? this.subcategoryId,
      size: size ?? this.size,
      alcoholContent: alcoholContent ?? this.alcoholContent,
      description: description ?? this.description,
      barcode: barcode ?? this.barcode,
      hsnCode: hsnCode ?? this.hsnCode,
      imageUrl: imageUrl ?? this.imageUrl,
      governmentDuty: governmentDuty ?? this.governmentDuty,
      buyingPrice: buyingPrice ?? this.buyingPrice,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      mrp: mrp ?? this.mrp,
      isActive: isActive ?? this.isActive,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  /// Validate the model
  List<String> validate() {
    final errors = <String>[];

    if (brandName.isEmpty) {
      errors.add('Brand name is required');
    }

    if (categoryId.isEmpty) {
      errors.add('Category is required');
    }

    if (size.isEmpty) {
      errors.add('Size is required');
    }

    // Alcohol content not displayed in UI - skip validation

    if (buyingPrice < 0) {
      errors.add('Buying price cannot be negative');
    }

    if (sellingPrice < 0) {
      errors.add('Selling price cannot be negative');
    }

    if (mrp < sellingPrice) {
      errors.add('MRP cannot be less than selling price');
    }

    // ✅ Barcode is now OPTIONAL (removed validation requirement)
    // Many SaaS brands don't have barcodes in database
    // if (barcode.isEmpty) {
    //   errors.add('Barcode is required');
    // }

    return errors;
  }

  /// Check if model is valid
  bool get isValid => validate().isEmpty;

  /// Total cost = Buying Price (user request)
  double get totalCost => buyingPrice;

  /// Calculate profit margin
  double get profitMargin => sellingPrice - totalCost;

  /// Calculate profit percentage
  double get profitPercentage =>
      totalCost > 0 ? ((profitMargin / totalCost) * 100) : 0.0;

  @override
  String toString() {
    return 'BrandVariantEditModel{id: $id, brand: $brandName, size: $size, '
        'category: $categoryId, buying: ₹$buyingPrice, selling: ₹$sellingPrice}';
  }
}
