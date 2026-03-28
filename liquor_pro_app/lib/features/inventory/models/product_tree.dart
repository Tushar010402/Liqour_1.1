import 'product.dart';

/// Hierarchical product tree structure for organized inventory display
/// Tree: Brand → Category → Subcategory → Size Variants

/// Brand level - Top of the tree
class ProductBrandNode {
  final String brandId;
  final String brandName;
  final Map<String, ProductCategoryNode> categories; // categoryId -> node
  bool isExpanded;

  ProductBrandNode({
    required this.brandId,
    required this.brandName,
    Map<String, ProductCategoryNode>? categories,
    this.isExpanded = false,
  }) : categories = categories ?? {};

  /// Get all products under this brand
  List<Product> get allProducts {
    return categories.values
        .expand((category) => category.allProducts)
        .toList();
  }

  /// Get total quantity across all variants
  /// TODO: Integrate with Stock model for accurate quantities
  int get totalQuantity {
    // return allProducts.fold(0, (sum, product) => sum + (product.stockQuantity ?? 0));
    return 0; // Placeholder until Stock model integration
  }

  /// Get total value
  /// TODO: Integrate with Stock model for accurate value calculation
  double get totalValue {
    // return allProducts.fold(0.0, (sum, product) =>
    //   sum + ((product.stockQuantity ?? 0) * product.sellingPrice));
    return 0.0; // Placeholder until Stock model integration
  }
}

/// Category level
class ProductCategoryNode {
  final String categoryId;
  final String categoryName;
  final Map<String, ProductSubcategoryNode> subcategories; // subcategoryId -> node
  bool isExpanded;

  ProductCategoryNode({
    required this.categoryId,
    required this.categoryName,
    Map<String, ProductSubcategoryNode>? subcategories,
    this.isExpanded = false,
  }) : subcategories = subcategories ?? {};

  /// Get all products under this category
  List<Product> get allProducts {
    return subcategories.values
        .expand((subcategory) => subcategory.products)
        .toList();
  }

  /// Get total quantity
  /// TODO: Integrate with Stock model for accurate quantities
  int get totalQuantity {
    // return allProducts.fold(0, (sum, product) => sum + (product.stockQuantity ?? 0));
    return 0; // Placeholder until Stock model integration
  }
}

/// Subcategory level
class ProductSubcategoryNode {
  final String subcategoryId;
  final String subcategoryName;
  final List<Product> products; // Size variants
  bool isExpanded;

  ProductSubcategoryNode({
    required this.subcategoryId,
    required this.subcategoryName,
    List<Product>? products,
    this.isExpanded = false,
  }) : products = products ?? [];

  /// Get total quantity
  /// TODO: Integrate with Stock model for accurate quantities
  int get totalQuantity {
    // return products.fold(0, (sum, product) => sum + (product.stockQuantity ?? 0));
    return 0; // Placeholder until Stock model integration
  }

  /// Sort products by size
  void sortProductsBySize() {
    products.sort((a, b) {
      // Extract numeric value from size (e.g., "750ml" -> 750)
      final aValue = _extractSizeValue(a.size ?? '');
      final bValue = _extractSizeValue(b.size ?? '');
      return aValue.compareTo(bValue);
    });
  }

  int _extractSizeValue(String size) {
    final match = RegExp(r'(\d+)').firstMatch(size);
    return match != null ? int.parse(match.group(1)!) : 0;
  }
}

/// Tree builder utility
class ProductTreeBuilder {
  /// Build tree from flat product list
  static Map<String, ProductBrandNode> buildTree(List<Product> products) {
    final Map<String, ProductBrandNode> tree = {};

    for (final product in products) {
      final brandId = product.brand?.id ?? 'unknown';
      final brandName = product.brand?.name ?? 'Unknown Brand';
      final categoryId = product.category?.id ?? 'unknown';
      final categoryName = product.category?.name ?? 'Unknown Category';
      final subcategoryId = product.subcategory?.id ?? 'unknown';
      final subcategoryName = product.subcategory?.name ?? 'Uncategorized';

      // Get or create brand node
      tree.putIfAbsent(
        brandId,
        () => ProductBrandNode(brandId: brandId, brandName: brandName),
      );

      // Get or create category node
      tree[brandId]!.categories.putIfAbsent(
        categoryId,
        () => ProductCategoryNode(
          categoryId: categoryId,
          categoryName: categoryName,
        ),
      );

      // Get or create subcategory node
      tree[brandId]!.categories[categoryId]!.subcategories.putIfAbsent(
        subcategoryId,
        () => ProductSubcategoryNode(
          subcategoryId: subcategoryId,
          subcategoryName: subcategoryName,
        ),
      );

      // Add product to subcategory
      tree[brandId]!
          .categories[categoryId]!
          .subcategories[subcategoryId]!
          .products
          .add(product);
    }

    // Sort products within each subcategory
    for (final brand in tree.values) {
      for (final category in brand.categories.values) {
        for (final subcategory in category.subcategories.values) {
          subcategory.sortProductsBySize();
        }
      }
    }

    return tree;
  }

  /// Expand/collapse all nodes
  static void toggleAllNodes(Map<String, ProductBrandNode> tree, bool expand) {
    for (final brand in tree.values) {
      brand.isExpanded = expand;
      for (final category in brand.categories.values) {
        category.isExpanded = expand;
        for (final subcategory in category.subcategories.values) {
          subcategory.isExpanded = expand;
        }
      }
    }
  }

  /// Search products in tree
  static List<Product> searchInTree(
    Map<String, ProductBrandNode> tree,
    String query,
  ) {
    if (query.isEmpty) return [];

    final lowerQuery = query.toLowerCase();
    final results = <Product>[];

    for (final brand in tree.values) {
      for (final product in brand.allProducts) {
        if (product.name.toLowerCase().contains(lowerQuery) ||
            (product.barcode.toLowerCase().contains(lowerQuery) ?? false) ||
            brand.brandName.toLowerCase().contains(lowerQuery)) {
          results.add(product);
        }
      }
    }

    return results;
  }
}
