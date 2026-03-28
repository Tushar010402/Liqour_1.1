import '../../inventory/models/product.dart';

/// Cart Item Model
class CartItem {
  final Product product;
  int quantity;
  double discount;

  CartItem({
    required this.product,
    this.quantity = 1,
    this.discount = 0,
  });

  double get totalPrice => (product.sellingPrice * quantity) - discount;
  double get totalCost => product.costPrice * quantity;
  double get totalProfit => totalPrice - totalCost;

  Map<String, dynamic> toJson() {
    return {
      'product_id': product.id,
      'quantity': quantity,
      'unit_price': product.sellingPrice,
      'total_price': totalPrice,
    };
  }
}
