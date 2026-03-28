/// Receipt Validation Service
///
/// Validates receipt OCR results after capture.
/// Performs date, size, and shop validation with scoring.
///
/// Features:
/// - Date validation (format, range, position)
/// - Size value normalization and matching
/// - Shop name fuzzy matching
/// - Overall validation scoring
library;

import 'package:flutter/foundation.dart';
import '../models/scan_quality_models.dart';

/// Service for validating receipt OCR results
class ReceiptValidationService {
  // Known product sizes for matching
  static const Map<String, String> _sizePatterns = {
    '60': '60ML',
    '90': '90ML',
    '180': '180ML',
    '375': '375ML',
    '500': '500ML',
    '650': '650ML',
    '750': '750ML',
    '1000': '1000ML',
    '1L': '1000ML',
    '1.5L': '1500ML',
    '2L': '2000ML',
    'Q': 'QUARTER',
    'QTR': 'QUARTER',
    'QUARTER': 'QUARTER',
    'H': 'HALF',
    'HALF': 'HALF',
    'P': 'PINT',
    'PINT': 'PINT',
    'NIP': 'NIP',
    'BTL': 'BOTTLE',
    'BOTTLE': 'BOTTLE',
    'FULL': 'FULL',
  };

  // Date patterns for validation
  static final List<RegExp> _datePatterns = [
    RegExp(r'\b(\d{1,2})[\/\-\.](\d{1,2})[\/\-\.](\d{2,4})\b'),
    RegExp(r'\b(\d{1,2})\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+(\d{2,4})\b', caseSensitive: false),
    RegExp(r'\b(\d{4})[\/\-\.](\d{1,2})[\/\-\.](\d{1,2})\b'),
  ];

  static const Map<String, int> _monthNames = {
    'jan': 1, 'january': 1,
    'feb': 2, 'february': 2,
    'mar': 3, 'march': 3,
    'apr': 4, 'april': 4,
    'may': 5,
    'jun': 6, 'june': 6,
    'jul': 7, 'july': 7,
    'aug': 8, 'august': 8,
    'sep': 9, 'sept': 9, 'september': 9,
    'oct': 10, 'october': 10,
    'nov': 11, 'november': 11,
    'dec': 12, 'december': 12,
  };

  /// Validate the full receipt after OCR processing
  ReceiptValidationResult validateReceipt({
    required String ocrText,
    required String expectedShopName,
    int? expectedItemCount,
    DateTime? expectedDate,
  }) {
    final warnings = <String>[];
    final errors = <String>[];

    // 1. Validate date
    final dateValidation = _validateDate(ocrText, expectedDate);
    if (dateValidation == null) {
      warnings.add('Date not detected in receipt');
    } else if (!dateValidation.isInValidRange) {
      warnings.add('Date ${_formatDate(dateValidation.detectedDate)} is outside valid range');
    }

    // 2. Validate sizes
    final sizeValidations = _validateSizes(ocrText);
    if (sizeValidations.isEmpty) {
      warnings.add('No size values detected');
    }

    // 3. Validate shop name
    final shopValidation = _validateShopName(ocrText, expectedShopName);
    if (!shopValidation.isMatch) {
      if (shopValidation.matchConfidence > 0.5) {
        warnings.add('Shop name partially matched: ${shopValidation.detectedName}');
      } else {
        errors.add('Shop name not found in receipt');
      }
    }

    // Calculate overall score
    double score = 0;

    // Date contributes 30%
    if (dateValidation != null) {
      score += dateValidation.isValid ? 30 : 15;
    }

    // Sizes contribute 40%
    if (sizeValidations.isNotEmpty) {
      final avgConfidence = sizeValidations.fold(0.0, (sum, s) => sum + s.confidence) / sizeValidations.length;
      score += 40 * avgConfidence;
    }

    // Shop contributes 30%
    score += 30 * shopValidation.matchConfidence;

    final isValid = errors.isEmpty && score >= 50;

    return ReceiptValidationResult(
      isValid: isValid,
      overallScore: score.clamp(0, 100),
      dateValidation: dateValidation,
      sizeValidations: sizeValidations,
      shopValidation: shopValidation,
      warnings: warnings,
      errors: errors,
    );
  }

  /// Validate date from OCR text
  DateValidation? _validateDate(String text, DateTime? expectedDate) {
    // Split text into lines to check position
    final lines = text.split('\n');
    final totalLines = lines.length;

    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final line = lines[lineIndex];

      for (final pattern in _datePatterns) {
        final match = pattern.firstMatch(line);
        if (match != null) {
          try {
            final rawString = match.group(0) ?? '';
            final date = _parseDate(match, pattern);

            if (date != null) {
              final positionY = totalLines > 0 ? lineIndex / totalLines : 0.0;
              final isInExpectedPosition = positionY < 0.3; // Top 30%

              final now = DateTime.now();
              final isInValidRange = date.isBefore(now.add(const Duration(days: 1))) &&
                  date.isAfter(now.subtract(const Duration(days: 30)));

              // Calculate confidence based on position and format
              double confidence = 0.7;
              if (isInExpectedPosition) confidence += 0.2;
              if (isInValidRange) confidence += 0.1;

              return DateValidation(
                detectedDate: date,
                rawString: rawString,
                isInValidRange: isInValidRange,
                isInExpectedPosition: isInExpectedPosition,
                confidence: confidence.clamp(0, 1),
                positionY: positionY,
              );
            }
          } catch (e) {
            debugPrint('❌ [ReceiptValidation] Date parse error: $e');
          }
        }
      }
    }

    return null;
  }

  /// Parse date from regex match
  DateTime? _parseDate(RegExpMatch match, RegExp pattern) {
    try {
      if (pattern == _datePatterns[0]) {
        // DD/MM/YYYY
        final day = int.parse(match.group(1)!);
        final month = int.parse(match.group(2)!);
        var year = int.parse(match.group(3)!);
        if (year < 100) year += 2000;
        return DateTime(year, month, day);
      }

      if (pattern == _datePatterns[1]) {
        // DD MMM YYYY
        final day = int.parse(match.group(1)!);
        final monthStr = match.group(2)!.toLowerCase();
        final month = _monthNames[monthStr] ?? 1;
        var year = int.parse(match.group(3)!);
        if (year < 100) year += 2000;
        return DateTime(year, month, day);
      }

      if (pattern == _datePatterns[2]) {
        // YYYY/MM/DD
        final year = int.parse(match.group(1)!);
        final month = int.parse(match.group(2)!);
        final day = int.parse(match.group(3)!);
        return DateTime(year, month, day);
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  /// Validate sizes from OCR text
  List<SizeValidation> _validateSizes(String text) {
    final validations = <SizeValidation>[];
    final upperText = text.toUpperCase();

    // ML patterns
    final mlPattern = RegExp(r'\b(\d+)\s*(ML|M\.L\.?)\b');
    for (final match in mlPattern.allMatches(upperText)) {
      final value = match.group(1)!;
      final normalized = '${value}ML';
      final isKnown = _sizePatterns.containsValue(normalized);

      validations.add(SizeValidation(
        detectedSize: match.group(0)!,
        normalizedSize: normalized,
        isKnownSize: isKnown,
        matchedProductSize: isKnown ? normalized : null,
        confidence: isKnown ? 0.95 : 0.7,
      ));
    }

    // Litre patterns
    final litrePattern = RegExp(r'\b(\d+(?:\.\d+)?)\s*(L|LTR|LITRE|LITER)\b');
    for (final match in litrePattern.allMatches(upperText)) {
      final value = double.tryParse(match.group(1)!) ?? 0;
      final normalized = '${(value * 1000).round()}ML';
      final isKnown = _sizePatterns.containsValue(normalized);

      validations.add(SizeValidation(
        detectedSize: match.group(0)!,
        normalizedSize: normalized,
        isKnownSize: isKnown,
        matchedProductSize: isKnown ? normalized : null,
        confidence: isKnown ? 0.9 : 0.65,
      ));
    }

    // Common abbreviated sizes (Q, H, P, etc.)
    for (final entry in _sizePatterns.entries) {
      final pattern = RegExp('\\b${entry.key}\\b', caseSensitive: false);
      if (pattern.hasMatch(upperText)) {
        // Avoid duplicates
        final normalized = entry.value;
        if (!validations.any((v) => v.normalizedSize == normalized)) {
          validations.add(SizeValidation(
            detectedSize: entry.key,
            normalizedSize: normalized,
            isKnownSize: true,
            matchedProductSize: normalized,
            confidence: 0.85,
          ));
        }
      }
    }

    // Numeric sizes without units (context-dependent)
    final numericPattern = RegExp(r'\b(60|90|180|375|500|650|750|1000)\b');
    for (final match in numericPattern.allMatches(upperText)) {
      final value = match.group(1)!;
      final normalized = _sizePatterns[value] ?? '${value}ML';

      // Avoid duplicates
      if (!validations.any((v) => v.normalizedSize == normalized)) {
        validations.add(SizeValidation(
          detectedSize: value,
          normalizedSize: normalized,
          isKnownSize: true,
          matchedProductSize: normalized,
          confidence: 0.75, // Lower confidence for units-less
        ));
      }
    }

    return validations;
  }

  /// Validate shop name from OCR text
  ShopValidation _validateShopName(String text, String expectedName) {
    if (expectedName.isEmpty) {
      return ShopValidation(
        detectedName: '',
        expectedName: expectedName,
        isMatch: false,
        matchConfidence: 0,
        similarityScore: 0,
      );
    }

    final normalizedText = text.toLowerCase();
    final normalizedExpected = expectedName.toLowerCase();

    // Direct match
    if (normalizedText.contains(normalizedExpected)) {
      return ShopValidation(
        detectedName: expectedName,
        expectedName: expectedName,
        isMatch: true,
        matchConfidence: 1.0,
        similarityScore: 1.0,
      );
    }

    // Word-by-word matching
    final expectedWords = normalizedExpected.split(RegExp(r'\s+'));
    final textWords = normalizedText.split(RegExp(r'\s+'));

    int matchedWords = 0;
    String? bestMatch;
    double bestSimilarity = 0;

    for (final expectedWord in expectedWords) {
      if (expectedWord.length < 3) continue;

      for (final textWord in textWords) {
        if (textWord.length < 3) continue;

        final similarity = _calculateSimilarity(expectedWord, textWord);
        if (similarity > 0.7) {
          matchedWords++;
          if (similarity > bestSimilarity) {
            bestSimilarity = similarity;
            bestMatch = textWord;
          }
          break;
        }

        // Check for substring match
        if (textWord.contains(expectedWord) || expectedWord.contains(textWord)) {
          matchedWords++;
          final subSimilarity = expectedWord.length > textWord.length
              ? textWord.length / expectedWord.length
              : expectedWord.length / textWord.length;
          if (subSimilarity > bestSimilarity) {
            bestSimilarity = subSimilarity;
            bestMatch = textWord;
          }
          break;
        }
      }
    }

    final relevantWords = expectedWords.where((w) => w.length >= 3).length;
    final matchConfidence = relevantWords > 0 ? matchedWords / relevantWords : 0.0;
    final isMatch = matchConfidence >= 0.7;

    return ShopValidation(
      detectedName: bestMatch ?? '',
      expectedName: expectedName,
      isMatch: isMatch,
      matchConfidence: matchConfidence.clamp(0, 1),
      similarityScore: bestSimilarity.clamp(0, 1),
    );
  }

  /// Calculate string similarity
  double _calculateSimilarity(String a, String b) {
    if (a == b) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;

    final longer = a.length > b.length ? a : b;
    final shorter = a.length > b.length ? b : a;

    // Quick substring check
    if (longer.contains(shorter)) {
      return shorter.length / longer.length;
    }

    // Character overlap
    final aChars = a.split('').toSet();
    final bChars = b.split('').toSet();
    final commonChars = aChars.intersection(bChars).length;

    return commonChars / longer.length;
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  /// Normalize a size string to standard format
  String normalizeSize(String size) {
    final upper = size.toUpperCase().replaceAll(RegExp(r'\s+'), '');

    if (_sizePatterns.containsKey(upper)) {
      return _sizePatterns[upper]!;
    }

    // Try to extract ML value
    final mlMatch = RegExp(r'^(\d+)(ML)?$').firstMatch(upper);
    if (mlMatch != null) {
      final value = mlMatch.group(1)!;
      return '${value}ML';
    }

    return upper;
  }

  /// Check if a size is known/valid
  bool isKnownSize(String size) {
    final normalized = normalizeSize(size);
    return _sizePatterns.containsValue(normalized);
  }

  /// Get all known sizes
  List<String> getAllKnownSizes() {
    return _sizePatterns.values.toSet().toList()..sort();
  }
}
