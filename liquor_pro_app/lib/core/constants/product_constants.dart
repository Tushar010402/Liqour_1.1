/// Product Constants
/// Provides size options for different liquor categories
/// IMPORTANT: All sizes use uppercase 'ML' suffix (e.g., '90ML', '180ML')
/// to match the backend database and existing inventory data
class ProductConstants {
  // Spirit sizes (Whisky, Vodka, Rum, Gin, etc.)
  // Sizes ordered from small to large for consistent display
  static const List<String> spiritSizes = [
    '90ML',
    '180ML',
    '375ML',
    '750ML',
    '1000ML',
    '1500ML',
  ];

  // Beer sizes
  static const List<String> beerSizes = [
    '330ML',
    '500ML',
    '650ML',
    '750ML',
  ];

  // Wine sizes
  static const List<String> wineSizes = [
    '187ML',
    '375ML',
    '750ML',
    '1500ML',
  ];

  /// Get sizes for a specific category
  /// Returns predefined sizes with uppercase 'ML' suffix
  static List<String> getSizesForCategory(String categoryName) {
    final lowerCategory = categoryName.toLowerCase();

    if (lowerCategory.contains('beer')) {
      return beerSizes;
    } else if (lowerCategory.contains('wine')) {
      return wineSizes;
    } else {
      // Default to spirit sizes for whisky, vodka, rum, gin, etc.
      return spiritSizes;
    }
  }

  /// Normalize a size string to uppercase ML format
  /// Examples: '180ml' -> '180ML', '750 ml' -> '750ML', '90' -> '90ML'
  static String normalizeSize(String size) {
    // Remove spaces and convert to uppercase
    String normalized = size.trim().toUpperCase().replaceAll(' ', '');

    // If it doesn't end with 'ML', add it
    if (!normalized.endsWith('ML')) {
      normalized = '${normalized}ML';
    }

    return normalized;
  }

  /// Check if a size is valid for a category
  static bool isValidSizeForCategory(String size, String categoryName) {
    final sizes = getSizesForCategory(categoryName);
    final normalized = normalizeSize(size);
    return sizes.contains(normalized);
  }
}
