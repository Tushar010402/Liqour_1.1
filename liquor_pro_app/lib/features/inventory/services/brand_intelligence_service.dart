import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Smart Brand Intelligence Service
/// Provides intelligent brand name correction, suggestions, and validation
class BrandIntelligenceService {
  // Common liquor brands database (expand this with actual data)
  static final List<String> knownBrands = [
    // Whiskey brands
    'Royal Stag',
    'Royal Challenge',
    'Royal Green',
    'Royal Reserve',
    'Blenders Pride',
    'Teachers Highland Cream',
    'Black Dog',
    '8PM',
    '8 P.M.',
    '8 P.M. Black',
    'McDowell No.1',
    'McDowell\'s No.1',
    'Antiquity Blue',
    'Antiquity',
    'Officers Choice',
    'Signature',
    'Imperial Blue',
    'Bagpiper',
    'Royal Deluxe',
    'RS Barrel',
    'R.S. Barrel',
    'Red Knight',
    'Director\'s Special',
    'DSP Black',
    'Original Choice',
    'All Seasons',
    // Beer brands
    'Kingfisher',
    'Kingfisher Premium',
    'Kingfisher Strong',
    'Kingfisher Ultra',
    'Budweiser',
    'Budweiser Magnum',
    'Tuborg',
    'Tuborg Strong',
    'Carlsberg',
    'Haywards 5000',
    'Haywards',
    'Hunter',
    'Knockout',
    'Thunderbolt',
    'Bullet',
    'London Pilsner',
    'Foster\'s',
    'Heineken',
    'Corona',
    'Hoegaarden',
    'Stella Artois',
    // Vodka brands
    'Smirnoff',
    'Romanov',
    'Magic Moments',
    'White Mischief',
    'Fuel',
    'Absolut',
    // Rum brands
    'Old Monk',
    'Bacardi',
    'McDowell\'s No.1 Rum',
    'Captain Morgan',
    'Malibu',
    // Gin brands
    'Blue Riband',
    'Aristocrat',
    'Bombay Sapphire',
    // Wine brands
    'Sula',
    'Four Seasons',
    'Grover Zampa',
    'Fratelli',
    'York',
    // Brandy
    'Mansion House',
    'Honey Bee',
    'McDowell\'s No.1 Brandy',
    'Morpheus',
  ];

  // Common size variations
  static final Map<String, String> sizeNormalizations = {
    '90ml': '90ml',
    '90 ml': '90ml',
    '90ML': '90ml',
    '90 ML': '90ml',
    '0.09L': '90ml',
    '0.09l': '90ml',
    '180ml': '180ml',
    '180 ml': '180ml',
    '180ML': '180ml',
    '180 ML': '180ml',
    '0.18L': '180ml',
    '0.18l': '180ml',
    '375ml': '375ml',
    '375 ml': '375ml',
    '375ML': '375ml',
    '375 ML': '375ml',
    '0.375L': '375ml',
    '0.375l': '375ml',
    '500ml': '500ml',
    '500 ml': '500ml',
    '500ML': '500ml',
    '500 ML': '500ml',
    '0.5L': '500ml',
    '0.5l': '500ml',
    '650ml': '650ml',
    '650 ml': '650ml',
    '650ML': '650ml',
    '650 ML': '650ml',
    '0.65L': '650ml',
    '0.65l': '650ml',
    '750ml': '750ml',
    '750 ml': '750ml',
    '750ML': '750ml',
    '750 ML': '750ml',
    '0.75L': '750ml',
    '0.75l': '750ml',
    '1000ml': '1L',
    '1000 ml': '1L',
    '1000ML': '1L',
    '1000 ML': '1L',
    '1L': '1L',
    '1l': '1L',
    '1 L': '1L',
    '1 l': '1L',
    '1.5L': '1.5L',
    '1.5l': '1.5L',
    '1500ml': '1.5L',
    '1500 ml': '1.5L',
    '2L': '2L',
    '2l': '2L',
    '2000ml': '2L',
    '2000 ml': '2L',
  };

  // Calculate Levenshtein distance for fuzzy matching
  static int levenshteinDistance(String s1, String s2) {
    final m = s1.length;
    final n = s2.length;

    if (m == 0) return n;
    if (n == 0) return m;

    // Create a matrix to store distances
    final List<List<int>> dp = List.generate(
      m + 1,
      (_) => List.filled(n + 1, 0),
    );

    // Initialize first row and column
    for (int i = 0; i <= m; i++) {
      dp[i][0] = i;
    }
    for (int j = 0; j <= n; j++) {
      dp[0][j] = j;
    }

    // Fill the matrix
    for (int i = 1; i <= m; i++) {
      for (int j = 1; j <= n; j++) {
        if (s1[i - 1] == s2[j - 1]) {
          dp[i][j] = dp[i - 1][j - 1];
        } else {
          dp[i][j] = 1 +
              [
                dp[i - 1][j], // Deletion
                dp[i][j - 1], // Insertion
                dp[i - 1][j - 1], // Substitution
              ].reduce(min);
        }
      }
    }

    return dp[m][n];
  }

  // Calculate similarity score (0.0 to 1.0)
  static double getSimilarityScore(String s1, String s2) {
    final distance = levenshteinDistance(
      s1.toLowerCase(),
      s2.toLowerCase(),
    );
    final maxLength = max(s1.length, s2.length);

    if (maxLength == 0) return 1.0;

    return 1.0 - (distance / maxLength);
  }

  // Get brand suggestions based on input
  static List<BrandSuggestion> getSuggestions(String input) {
    if (input.isEmpty) return [];

    final cleanInput = _cleanBrandName(input);
    final suggestions = <BrandSuggestion>[];

    for (final brand in knownBrands) {
      final cleanBrand = _cleanBrandName(brand);
      final similarity = getSimilarityScore(cleanInput, cleanBrand);

      // Include if similarity is above threshold
      if (similarity >= 0.5) {
        suggestions.add(BrandSuggestion(
          originalName: brand,
          confidence: similarity,
          isExactMatch: similarity == 1.0,
          isPartialMatch: cleanInput.contains(cleanBrand) || cleanBrand.contains(cleanInput),
        ));
      }
    }

    // Sort by confidence (highest first)
    suggestions.sort((a, b) => b.confidence.compareTo(a.confidence));

    // Return top 5 suggestions
    return suggestions.take(5).toList();
  }

  // Clean brand name for comparison
  static String _cleanBrandName(String brand) {
    return brand
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '') // Remove special characters
        .replaceAll(RegExp(r'\s+'), ' ') // Normalize spaces
        .trim();
  }

  // Normalize size string
  static String normalizeSize(String size) {
    return sizeNormalizations[size] ?? size;
  }

  // Validate price based on brand and size
  static PriceValidation validatePrice({
    required String brand,
    required String size,
    required double price,
  }) {
    // Price ranges based on size (approximate)
    final Map<String, PriceRange> priceRanges = {
      '90ml': PriceRange(50, 400),
      '180ml': PriceRange(100, 800),
      '375ml': PriceRange(200, 1500),
      '500ml': PriceRange(150, 1000),
      '650ml': PriceRange(200, 1200),
      '750ml': PriceRange(400, 3000),
      '1L': PriceRange(500, 4000),
      '1.5L': PriceRange(800, 6000),
      '2L': PriceRange(1000, 8000),
    };

    final normalizedSize = normalizeSize(size);
    final range = priceRanges[normalizedSize];

    if (range == null) {
      return PriceValidation(
        isValid: true,
        confidence: 0.5,
        message: 'Unable to validate price for size: $size',
      );
    }

    if (price < range.min) {
      return PriceValidation(
        isValid: false,
        suggestedPrice: range.min.toDouble(),
        confidence: 0.8,
        message: 'Price seems too low for $brand $normalizedSize',
        reason: PriceIssueReason.tooLow,
      );
    }

    if (price > range.max) {
      return PriceValidation(
        isValid: false,
        suggestedPrice: range.max.toDouble(),
        confidence: 0.8,
        message: 'Price seems too high for $brand $normalizedSize',
        reason: PriceIssueReason.tooHigh,
      );
    }

    return PriceValidation(
      isValid: true,
      confidence: 0.9,
      message: 'Price is within expected range',
    );
  }

  // Check if a brand name looks suspicious
  static bool isSuspiciousBrandName(String brand) {
    final cleaned = _cleanBrandName(brand);

    // Check if too short
    if (cleaned.length < 2) return true;

    // Check if contains too many numbers
    final numberCount = RegExp(r'\d').allMatches(cleaned).length;
    if (numberCount > cleaned.length / 2) return true;

    // Check if contains gibberish (no vowels)
    final vowelCount = RegExp(r'[aeiou]').allMatches(cleaned).length;
    if (vowelCount == 0 && cleaned.length > 3) return true;

    return false;
  }

  // Get data quality score for an item
  static DataQualityScore calculateDataQuality({
    required String brandText,
    required String sizeText,
    double? price,
    int? quantity,
  }) {
    double score = 1.0;
    final issues = <String>[];

    // Check brand name
    if (isSuspiciousBrandName(brandText)) {
      score -= 0.3;
      issues.add('Suspicious brand name');
    } else {
      final suggestions = getSuggestions(brandText);
      if (suggestions.isEmpty || suggestions.first.confidence < 0.7) {
        score -= 0.2;
        issues.add('Unknown brand');
      }
    }

    // Check size
    final normalizedSize = normalizeSize(sizeText);
    if (normalizedSize == sizeText && !sizeNormalizations.containsKey(sizeText)) {
      score -= 0.2;
      issues.add('Non-standard size format');
    }

    // Check price
    if (price != null) {
      final priceValidation = validatePrice(
        brand: brandText,
        size: sizeText,
        price: price,
      );
      if (!priceValidation.isValid) {
        score -= 0.2;
        issues.add(priceValidation.message);
      }
    }

    // Check quantity
    if (quantity != null && quantity < 0) {
      score -= 0.1;
      issues.add('Invalid quantity');
    }

    return DataQualityScore(
      score: score.clamp(0.0, 1.0),
      issues: issues,
      canAutoFix: issues.length <= 2,
    );
  }

  // Auto-fix common issues
  static AutoFixResult autoFixItem({
    required String brandText,
    required String sizeText,
    double? price,
  }) {
    String fixedBrand = brandText;
    String fixedSize = sizeText;
    double? fixedPrice = price;
    final fixes = <String>[];

    // Fix brand name
    final suggestions = getSuggestions(brandText);
    if (suggestions.isNotEmpty && suggestions.first.confidence >= 0.8) {
      fixedBrand = suggestions.first.originalName;
      fixes.add('Brand corrected to: ${suggestions.first.originalName}');
    }

    // Fix size
    final normalizedSize = normalizeSize(sizeText);
    if (normalizedSize != sizeText) {
      fixedSize = normalizedSize;
      fixes.add('Size normalized to: $normalizedSize');
    }

    // Fix price
    if (price != null) {
      final priceValidation = validatePrice(
        brand: fixedBrand,
        size: fixedSize,
        price: price,
      );
      if (!priceValidation.isValid && priceValidation.suggestedPrice != null) {
        fixedPrice = priceValidation.suggestedPrice;
        fixes.add('Price adjusted to: ₹${priceValidation.suggestedPrice}');
      }
    }

    return AutoFixResult(
      brandText: fixedBrand,
      sizeText: fixedSize,
      price: fixedPrice,
      fixes: fixes,
      hasChanges: fixes.isNotEmpty,
    );
  }
}

// Data models

class BrandSuggestion {
  final String originalName;
  final double confidence; // 0.0 to 1.0
  final bool isExactMatch;
  final bool isPartialMatch;

  BrandSuggestion({
    required this.originalName,
    required this.confidence,
    this.isExactMatch = false,
    this.isPartialMatch = false,
  });
}

class PriceRange {
  final double min;
  final double max;

  PriceRange(this.min, this.max);
}

class PriceValidation {
  final bool isValid;
  final double? suggestedPrice;
  final double confidence;
  final String message;
  final PriceIssueReason? reason;

  PriceValidation({
    required this.isValid,
    this.suggestedPrice,
    required this.confidence,
    required this.message,
    this.reason,
  });
}

enum PriceIssueReason {
  tooLow,
  tooHigh,
  suspicious,
}

class DataQualityScore {
  final double score; // 0.0 to 1.0
  final List<String> issues;
  final bool canAutoFix;

  DataQualityScore({
    required this.score,
    required this.issues,
    required this.canAutoFix,
  });

  String get grade {
    if (score >= 0.9) return 'A';
    if (score >= 0.8) return 'B';
    if (score >= 0.7) return 'C';
    if (score >= 0.6) return 'D';
    return 'F';
  }
}

class AutoFixResult {
  final String brandText;
  final String sizeText;
  final double? price;
  final List<String> fixes;
  final bool hasChanges;

  AutoFixResult({
    required this.brandText,
    required this.sizeText,
    this.price,
    required this.fixes,
    required this.hasChanges,
  });
}

// Provider for dependency injection
final brandIntelligenceProvider = Provider<BrandIntelligenceService>((ref) {
  return BrandIntelligenceService();
});