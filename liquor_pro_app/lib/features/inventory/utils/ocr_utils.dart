/// Utility functions for OCR data processing
library;

/// Normalizes size strings to a consistent format
///
/// Handles variations like:
/// - "90ml", "90 ml", "90ML", "90 Ml" → "90ml"
/// - "750 ML", "750ml", "750 Ml" → "750ml"
/// - "1L", "1 L", "1 Ltr" → "1L"
/// - "180ML", "180 ml" → "180ml"
///
/// Returns normalized size string in lowercase with no spaces
String normalizeSize(String size) {
  // Remove all whitespace
  String normalized = size.replaceAll(RegExp(r'\s+'), '');

  // Convert to lowercase
  normalized = normalized.toLowerCase();

  // Handle common liquor size variations
  // Liters
  normalized = normalized.replaceAll(RegExp(r'ltr$'), 'l');
  normalized = normalized.replaceAll(RegExp(r'litre$'), 'l');
  normalized = normalized.replaceAll(RegExp(r'liter$'), 'l');

  // Milliliters (already handled by lowercase)
  // Just ensure consistency

  return normalized;
}

/// Checks if two sizes are equivalent after normalization
///
/// Example:
/// ```dart
/// areSizesEquivalent("90 ml", "90ML") // true
/// areSizesEquivalent("750ml", "750 ML") // true
/// areSizesEquivalent("90ml", "180ml") // false
/// ```
bool areSizesEquivalent(String size1, String size2) {
  return normalizeSize(size1) == normalizeSize(size2);
}

/// Extracts numeric value from size string
///
/// Example:
/// ```dart
/// extractSizeValue("90ml") // 90.0
/// extractSizeValue("750 ML") // 750.0
/// extractSizeValue("1L") // 1.0
/// ```
double? extractSizeValue(String size) {
  final normalized = normalizeSize(size);
  final match = RegExp(r'(\d+\.?\d*)').firstMatch(normalized);
  if (match != null) {
    return double.tryParse(match.group(1)!);
  }
  return null;
}

/// Extracts unit from size string
///
/// Example:
/// ```dart
/// extractSizeUnit("90ml") // "ml"
/// extractSizeUnit("750 ML") // "ml"
/// extractSizeUnit("1L") // "l"
/// ```
String? extractSizeUnit(String size) {
  final normalized = normalizeSize(size);
  final match = RegExp(r'[a-z]+$').firstMatch(normalized);
  return match?.group(0);
}

/// Formats size for display with proper capitalization
///
/// Example:
/// ```dart
/// formatSizeForDisplay("90ml") // "90 ML"
/// formatSizeForDisplay("750ML") // "750 ML"
/// formatSizeForDisplay("1l") // "1 L"
/// ```
String formatSizeForDisplay(String size) {
  final value = extractSizeValue(size);
  final unit = extractSizeUnit(size);

  if (value == null || unit == null) {
    return size; // Return original if can't parse
  }

  // Format unit to uppercase
  final formattedUnit = unit.toUpperCase();

  // Format value (remove unnecessary decimals)
  final formattedValue = value == value.toInt()
      ? value.toInt().toString()
      : value.toString();

  return '$formattedValue $formattedUnit';
}

/// Detects if price seems unusually different from expected range
///
/// Useful for flagging potential data entry errors.
/// Returns true if price is outside normal range for liquor products.
bool isPriceSuspicious(double price, {
  double minExpected = 50.0,
  double maxExpected = 10000.0,
}) {
  return price < minExpected || price > maxExpected;
}

/// Calculates price difference percentage between two prices
///
/// Example:
/// ```dart
/// priceDifferencePercent(100.0, 110.0) // 10.0 (10% increase)
/// priceDifferencePercent(100.0, 90.0) // -10.0 (10% decrease)
/// ```
double priceDifferencePercent(double price1, double price2) {
  if (price1 == 0) return 0.0;
  return ((price2 - price1) / price1) * 100;
}

/// Checks if price difference is significant enough to warrant review
///
/// Returns true if prices differ by more than threshold percentage
bool isSignificantPriceDifference(
  double price1,
  double price2, {
  double thresholdPercent = 20.0,
}) {
  final difference = priceDifferencePercent(price1, price2).abs();
  return difference > thresholdPercent;
}

/// Cleans brand name for comparison
///
/// Removes extra spaces, special characters, and normalizes case
/// for better brand matching across receipts.
///
/// Example:
/// ```dart
/// cleanBrandName("Royal  Stag") // "royal stag"
/// cleanBrandName("Mc.Dowell No.1") // "mcdowell no1"
/// ```
String cleanBrandName(String brandName) {
  String cleaned = brandName.toLowerCase();

  // Remove extra spaces
  cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');

  // Remove periods (for names like "Mc.Dowell")
  cleaned = cleaned.replaceAll('.', '');

  // Trim
  cleaned = cleaned.trim();

  return cleaned;
}

/// Checks if two brand names are likely the same despite spelling variations
///
/// Uses simple similarity check for common variations.
/// Not perfect, but helps catch obvious duplicates.
bool areBrandsLikelySame(String brand1, String brand2) {
  final clean1 = cleanBrandName(brand1);
  final clean2 = cleanBrandName(brand2);

  // Exact match after cleaning
  if (clean1 == clean2) return true;

  // One is substring of other (handles "8 P.M." vs "8 P.M. Black")
  if (clean1.contains(clean2) || clean2.contains(clean1)) {
    // But they should be similar enough in length
    final lengthRatio = clean1.length / clean2.length;
    if (lengthRatio > 0.5 && lengthRatio < 2.0) {
      return true;
    }
  }

  return false;
}
