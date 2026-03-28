import 'package:flutter/foundation.dart';

import '../../../core/utils/app_logger.dart';
import '../models/batch_ocr_models.dart';

/// Utility for filtering garbage items from OCR extraction
///
/// Excludes obvious non-brand items like:
/// - Total/subtotal lines ("grand total", "amount")
/// - Header/footer text ("s.no", "closing", "receipt")
/// - OCR errors (excessive special characters)
/// - Invalid patterns (mostly numbers, too short/long)
///
/// Smart exceptions:
/// - Always keeps items with match_confidence > 0 (matched to existing brands)
/// - Always keeps items with stock > 0 if they pass basic validation
class BrandNameFilter {
  // Keywords that indicate non-brand items (case-insensitive)
  static final _excludeKeywords = [
    'total',
    'grand total',
    'sub total',
    'subtotal',
    'amount',
    'balance',
    'closing',
    'opening',
    'shop',
    'date',
    'receipt',
    'invoice',
    's.no',
    'sno',
    'sr.no',
    'qty',
    'quantity',
    'price',
    'rate',
    'column',
    'description',
    'particulars',
    'cgst',
    'sgst',
    'gst',
    'tax',
    'discount',
  ];

  /// Filter garbage items from deduplicated OCR results
  ///
  /// Returns a map with:
  /// - 'clean': List of legitimate brand items
  /// - 'garbage': List of filtered garbage items
  /// - 'summary': String summary of filtering results
  static Map<String, dynamic> filterItems(List<DeduplicatedItem> items) {
    if (items.isEmpty) {
      return {
        'clean': <DeduplicatedItem>[],
        'garbage': <DeduplicatedItem>[],
        'summary': 'No items to filter',
      };
    }

    final cleanItems = <DeduplicatedItem>[];
    final garbageItems = <DeduplicatedItem>[];
    final filterReasons = <String, int>{}; // Track why items were filtered

    for (int index = 0; index < items.length; index++) {
      final item = items[index];
      final filterResult = _shouldFilter(item);

      if (filterResult.shouldFilter) {
        garbageItems.add(item);

        // Track filter reason
        final reason = filterResult.reason;
        filterReasons[reason] = (filterReasons[reason] ?? 0) + 1;
      } else {
        cleanItems.add(item);
      }
    }

    // Build summary
    final summary = _buildSummary(
      originalCount: items.length,
      cleanCount: cleanItems.length,
      garbageCount: garbageItems.length,
      filterReasons: filterReasons,
    );

    if (kDebugMode) {
      debugPrint('[BrandFilter] ${cleanItems.length}/${items.length} items kept, ${garbageItems.length} filtered');
    }

    AppLogger.info('[BrandFilter] Results:');
    AppLogger.info('   Clean items: ${cleanItems.length}');
    AppLogger.info('   Filtered: ${garbageItems.length}');

    return {
      'clean': cleanItems,
      'garbage': garbageItems,
      'summary': summary,
    };
  }

  /// Check if an item should be filtered
  static _FilterResult _shouldFilter(DeduplicatedItem item) {
    // Clean up common OCR artifacts
    var brandText = item.brandText.trim();
    // Remove leading pipe or other common OCR artifacts
    brandText = brandText.replaceAll(RegExp(r'^[|/\\]+'), '').trim();

    // EXCEPTION: Always keep items matched to existing brands
    if (item.matchConfidence > 0) {
      return _FilterResult(
        shouldFilter: false,
        reason: 'Matched brand (confidence: ${item.matchConfidence})',
      );
    }

    // EXCEPTION: Known liquor brand patterns (allow these even if they trigger other filters)
    final upperText = brandText.toUpperCase();
    if (RegExp(r'^[0-9]+\s*P\.?M\.?$').hasMatch(upperText) || // Matches "8 PM", "8 P.M.", etc.
        RegExp(r'^B[0-9]+$').hasMatch(upperText) || // Matches "B7", "B9", etc.
        RegExp(r'^[0-9]+\s+PIPER').hasMatch(upperText) || // Matches "100 Pipers"
        brandText.contains('.') && brandText.length >= 4) { // Allow dots in brand names
      return _FilterResult(
        shouldFilter: false,
        reason: 'Known liquor brand pattern',
      );
    }

    // Check 1: Empty or very short text (Allow 2+ chars for brands like "B7")
    if (brandText.isEmpty) {
      return _FilterResult(shouldFilter: true, reason: 'Empty brand name');
    }
    if (brandText.length < 2) {
      return _FilterResult(shouldFilter: true, reason: 'Too short (<2 chars)');
    }

    // Check 2: Very long text (likely OCR error or paragraph)
    if (brandText.length > 60) {
      return _FilterResult(shouldFilter: true, reason: 'Too long (>60 chars)');
    }

    // Check 3: Keyword exclusions (case-insensitive)
    final lowerText = brandText.toLowerCase();
    for (final keyword in _excludeKeywords) {
      if (lowerText.contains(keyword)) {
        return _FilterResult(
          shouldFilter: true,
          reason: 'Contains keyword: "$keyword"',
        );
      }
    }

    // Check 4: Character composition analysis
    final charAnalysis = _analyzeCharacters(brandText);

    // Mostly numeric (>70% - Allow brands with numbers like "8 PM", "100 Pipers")
    if (charAnalysis.numericPercent > 70) {
      return _FilterResult(
        shouldFilter: true,
        reason: 'Mostly numbers (${charAnalysis.numericPercent.toStringAsFixed(0)}%)',
      );
    }

    // Excessive special characters (>50% - Allow dots/periods in brand names like "8 P.M.")
    if (charAnalysis.specialPercent > 50) {
      return _FilterResult(
        shouldFilter: true,
        reason: 'Too many special chars (${charAnalysis.specialPercent.toStringAsFixed(0)}%)',
      );
    }

    // Check 5: Pure numbers or pure special characters
    if (charAnalysis.alphaPercent < 20) {
      return _FilterResult(
        shouldFilter: true,
        reason: 'Too few letters (${charAnalysis.alphaPercent.toStringAsFixed(0)}%)',
      );
    }

    // EXCEPTION: Items with stock > 0 that passed basic validation are likely legitimate
    if (item.totalStock > 0) {
      return _FilterResult(
        shouldFilter: false,
        reason: 'Has stock (${item.totalStock} units)',
      );
    }

    // Zero stock items that passed all checks are also kept
    return _FilterResult(shouldFilter: false, reason: 'Passed validation');
  }

  /// Analyze character composition of text
  static _CharacterAnalysis _analyzeCharacters(String text) {
    if (text.isEmpty) {
      return _CharacterAnalysis(
        alphaPercent: 0,
        numericPercent: 0,
        specialPercent: 0,
      );
    }

    int alphaCount = 0;
    int numericCount = 0;
    int specialCount = 0;

    for (final char in text.runes) {
      final str = String.fromCharCode(char);

      if (RegExp(r'[a-zA-Z]').hasMatch(str)) {
        alphaCount++;
      } else if (RegExp(r'[0-9]').hasMatch(str)) {
        numericCount++;
      } else if (str != ' ') {
        // Count non-space special characters
        specialCount++;
      }
    }

    final totalChars = text.length;

    return _CharacterAnalysis(
      alphaPercent: (alphaCount / totalChars) * 100,
      numericPercent: (numericCount / totalChars) * 100,
      specialPercent: (specialCount / totalChars) * 100,
    );
  }

  /// Build human-readable summary
  static String _buildSummary({
    required int originalCount,
    required int cleanCount,
    required int garbageCount,
    required Map<String, int> filterReasons,
  }) {
    if (garbageCount == 0) {
      return 'All $originalCount items are valid brands';
    }

    final buffer = StringBuffer();
    buffer.write('$cleanCount valid brands found. ');
    buffer.write('$garbageCount items filtered');

    if (filterReasons.isNotEmpty) {
      buffer.write(' (');
      final reasonList = filterReasons.entries
          .map((e) => '${e.value} ${e.key}')
          .join(', ');
      buffer.write(reasonList);
      buffer.write(')');
    }

    return buffer.toString();
  }
}

/// Result of filter check
class _FilterResult {
  final bool shouldFilter;
  final String reason;

  _FilterResult({
    required this.shouldFilter,
    required this.reason,
  });
}

/// Character composition analysis
class _CharacterAnalysis {
  final double alphaPercent;
  final double numericPercent;
  final double specialPercent;

  _CharacterAnalysis({
    required this.alphaPercent,
    required this.numericPercent,
    required this.specialPercent,
  });
}
