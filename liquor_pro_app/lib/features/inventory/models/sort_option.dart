import 'package:flutter/material.dart';
import '../models/product_with_stock.dart';

/// Sort options for inventory
enum SortOption {
  sizeHighToLow,  // Default: Size (High to Low) then Price
  sizeLowToHigh,
  nameAsc,
  nameDesc,
  priceLowToHigh,
  priceHighToLow,
  stockLowToHigh,
  stockHighToLow,
  recentlyAdded,
  category;

  String get label {
    switch (this) {
      case SortOption.sizeHighToLow:
        return 'Size: High to Low';
      case SortOption.sizeLowToHigh:
        return 'Size: Low to High';
      case SortOption.nameAsc:
        return 'Name (A-Z)';
      case SortOption.nameDesc:
        return 'Name (Z-A)';
      case SortOption.priceLowToHigh:
        return 'Price: Low to High';
      case SortOption.priceHighToLow:
        return 'Price: High to Low';
      case SortOption.stockLowToHigh:
        return 'Stock: Low to High';
      case SortOption.stockHighToLow:
        return 'Stock: High to Low';
      case SortOption.recentlyAdded:
        return 'Recently Added';
      case SortOption.category:
        return 'Category';
    }
  }

  IconData get icon {
    switch (this) {
      case SortOption.sizeHighToLow:
        return Icons.straighten;
      case SortOption.sizeLowToHigh:
        return Icons.straighten;
      case SortOption.nameAsc:
        return Icons.sort_by_alpha;
      case SortOption.nameDesc:
        return Icons.sort_by_alpha;
      case SortOption.priceLowToHigh:
        return Icons.attach_money;
      case SortOption.priceHighToLow:
        return Icons.attach_money;
      case SortOption.stockLowToHigh:
        return Icons.inventory_2;
      case SortOption.stockHighToLow:
        return Icons.inventory_2;
      case SortOption.recentlyAdded:
        return Icons.schedule;
      case SortOption.category:
        return Icons.category;
    }
  }

  /// Extract numeric value from size string (e.g., "650ML" -> 650)
  static int _extractSizeValue(String size) {
    final numStr = size.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(numStr) ?? 0;
  }

  /// Apply sorting to a list of products
  List<ProductWithStock> apply(List<ProductWithStock> products) {
    final sorted = List<ProductWithStock>.from(products);

    switch (this) {
      case SortOption.sizeHighToLow:
        // Sort by size (high to low), then by price (low to high) for same size
        sorted.sort((a, b) {
          final sizeA = _extractSizeValue(a.size);
          final sizeB = _extractSizeValue(b.size);
          if (sizeA != sizeB) return sizeB.compareTo(sizeA); // High to low
          return a.sellingPrice.compareTo(b.sellingPrice); // Then by price
        });
        break;
      case SortOption.sizeLowToHigh:
        // Sort by size (low to high), then by price (low to high) for same size
        sorted.sort((a, b) {
          final sizeA = _extractSizeValue(a.size);
          final sizeB = _extractSizeValue(b.size);
          if (sizeA != sizeB) return sizeA.compareTo(sizeB); // Low to high
          return a.sellingPrice.compareTo(b.sellingPrice); // Then by price
        });
        break;
      case SortOption.nameAsc:
        sorted.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case SortOption.nameDesc:
        sorted.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
        break;
      case SortOption.priceLowToHigh:
        sorted.sort((a, b) => a.sellingPrice.compareTo(b.sellingPrice));
        break;
      case SortOption.priceHighToLow:
        sorted.sort((a, b) => b.sellingPrice.compareTo(a.sellingPrice));
        break;
      case SortOption.stockLowToHigh:
        sorted.sort((a, b) => a.currentStock.compareTo(b.currentStock));
        break;
      case SortOption.stockHighToLow:
        sorted.sort((a, b) => b.currentStock.compareTo(a.currentStock));
        break;
      case SortOption.recentlyAdded:
        // Already sorted by ID desc from backend
        break;
      case SortOption.category:
        sorted.sort((a, b) {
          final catA = a.category?.name ?? '';
          final catB = b.category?.name ?? '';
          if (catA != catB) return catA.compareTo(catB);
          return a.name.compareTo(b.name);
        });
        break;
    }

    return sorted;
  }
}
