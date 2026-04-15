import 'product.dart';
import 'brand.dart';

/// ProductWithStock - Combines tenant-wide Product with shop-specific Stock
///
/// This model is used for UI display where we need both product information
/// and stock quantities together.
///
/// Architecture:
/// - Product: Tenant-wide (shared across all shops)
/// - Stock: Shop-specific (each shop has its own stock levels)
/// - ProductWithStock: UI model that joins both for display
class ProductWithStock {
  final Product product;
  final Stock? stock;

  ProductWithStock({
    required this.product,
    this.stock,
  });

  /// Product ID (pass-through)
  String get id => product.id;

  /// Product name (pass-through)
  String get name => product.name;

  /// Clean display name
  String get cleanName => product.cleanName;

  /// Product size (pass-through)
  String get size => product.size;

  /// Product barcode (pass-through)
  String get barcode => product.barcode;

  /// Cost price (pass-through)
  double get costPrice => product.costPrice;

  /// Selling price (pass-through)
  double get sellingPrice => product.sellingPrice;

  /// Category (pass-through)
  Category? get category => product.category;

  /// Subcategory (pass-through)
  Subcategory? get subcategory => product.subcategory;

  /// Brand (pass-through)
  Brand? get brand => product.brand;

  /// Is active (pass-through)
  bool get isActive => product.isActive;

  /// Alcohol content (pass-through)
  double get alcoholContent => product.alcoholContent;

  /// Alcohol percentage (same as alcoholContent)
  double get alcoholPercentage => product.alcoholContent;

  /// HSN Code (barcode serves as HSN code for now)
  String get hsnCode => product.sku; // Use SKU as HSN code

  /// MRP (from backend, fallback to selling price)
  double get mrp => product.mrp > 0 ? product.mrp : product.sellingPrice;

  /// Buying Price (pass-through)
  double get buyingPrice => product.costPrice; // costPrice is buying price

  /// Government Duty (pass-through from API)
  double get governmentDuty => product.dutyFee;

  /// Image URL (prioritize stock's imageUrl from backend, fallback to product's imageUrl)
  String get imageUrl => stock?.imageUrl ?? product.imageUrl;

  /// Current stock quantity (from Stock model or Product's stockQuantity)
  int get currentStock {
    return stock?.quantity ?? product.stockQuantity ?? 0;
  }

  /// Reserved quantity (from Stock model)
  int get reservedQuantity => stock?.reservedQuantity ?? 0;

  /// Available quantity (total - reserved)
  int get availableQuantity => stock?.availableQuantity ?? 0;

  /// Minimum stock level (from Stock model)
  int get minimumLevel => stock?.minimumLevel ?? 10;

  /// Maximum stock level (from Stock model)
  int get maximumLevel => stock?.maximumLevel ?? 1000;

  /// Check if stock is low (at or below minimum)
  bool get isLowStock => currentStock <= minimumLevel;

  /// Check if stock is out
  bool get isOutOfStock => currentStock <= 0;

  /// Check if stock is critical (≤ 10 units)
  bool get isCriticalStock => currentStock <= 10;

  /// Check if stock is healthy (> minimum level)
  bool get isHealthyStock => currentStock > minimumLevel;

  /// Stock color indicator
  /// - Red: Critical (≤10)
  /// - Orange: Low (≤50)
  /// - Green: Healthy (>50)
  StockLevel get stockLevel {
    if (currentStock <= 10) return StockLevel.critical;
    if (currentStock <= 50) return StockLevel.low;
    return StockLevel.healthy;
  }

  /// Create from JSON (with optional stock data)
  factory ProductWithStock.fromJson(Map<String, dynamic> json) {
    return ProductWithStock(
      product: Product.fromJson(json['product'] ?? json),
      stock: json['stock'] != null
          ? Stock.fromJson(json['stock'] as Map<String, dynamic>)
          : null,
    );
  }

  /// Create from separate Product and Stock
  factory ProductWithStock.combine({
    required Product product,
    Stock? stock,
  }) {
    return ProductWithStock(
      product: product,
      stock: stock,
    );
  }

  /// Create list from products and stock map
  static List<ProductWithStock> combineList({
    required List<Product> products,
    required Map<String, Stock> stockMap,
  }) {
    return products.map((product) {
      final stock = stockMap[product.id];
      return ProductWithStock(
        product: product,
        stock: stock,
      );
    }).toList();
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'product': product.toJson(),
      if (stock != null) 'stock': {
        'quantity': stock!.quantity,
        'reserved_quantity': stock!.reservedQuantity,
        'minimum_level': stock!.minimumLevel,
        'maximum_level': stock!.maximumLevel,
      },
    };
  }

  /// Create a copy with updated stock
  ProductWithStock copyWithStock(Stock newStock) {
    return ProductWithStock(
      product: product,
      stock: newStock,
    );
  }

  /// Create a copy with updated quantity
  ProductWithStock copyWithQuantity(int newQuantity) {
    if (stock == null) {
      // Create new stock with this quantity
      return ProductWithStock(
        product: product,
        stock: Stock(
          id: '',
          shopId: '',
          productId: product.id,
          quantity: newQuantity,
          reservedQuantity: 0,
          minimumLevel: 10,
          maximumLevel: 1000,
          averageCost: product.costPrice,
          lastPurchasePrice: product.costPrice,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
    }

    // Update existing stock's quantity
    // Note: In real implementation, this would be done via API
    return this; // Placeholder
  }
}

/// Stock level enum for easy color coding
enum StockLevel {
  critical, // ≤10 units (Red)
  low,      // ≤50 units (Orange)
  healthy,  // >50 units (Green)
}

/// Extension to get color from stock level
extension StockLevelColor on StockLevel {
  /// Get color for this stock level
  /// Usage: stockLevel.color (requires material.dart import in calling code)
  String get colorName {
    switch (this) {
      case StockLevel.critical:
        return 'error'; // Red
      case StockLevel.low:
        return 'orange'; // Orange
      case StockLevel.healthy:
        return 'success'; // Green
    }
  }
}
