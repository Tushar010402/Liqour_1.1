/// Live Content Validator Service
///
/// Uses ML Kit Text Recognition to run real-time OCR on camera frames
/// for validating receipt content during camera preview.
///
/// Features:
/// - Date detection with regex patterns (DD/MM/YYYY, DD-MM-YY, etc.)
/// - Shop name matching with fuzzy string comparison
/// - Size value extraction (180ml, 750, Q, H, BOTTLE, etc.)
/// - Throttled processing (1 frame per second to avoid performance issues)
library;

import 'dart:async';
import 'dart:ui' show Size;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/scan_quality_models.dart';

/// Service for real-time content validation during camera preview
class LiveContentValidator {
  /// ML Kit text recognizer instance
  final TextRecognizer _textRecognizer = TextRecognizer();

  /// Timer for throttling frame processing
  Timer? _throttleTimer;

  /// Last validation result
  LiveValidationResult _lastResult = LiveValidationResult.empty();

  /// Whether currently processing a frame
  bool _isProcessing = false;

  /// Callback when validation result updates
  Function(LiveValidationResult)? onValidationUpdate;

  /// Minimum interval between frame processing (milliseconds)
  static const int _throttleIntervalMs = 1000; // 1 second

  /// Date regex patterns
  static final List<RegExp> _datePatterns = [
    // DD/MM/YYYY or DD-MM-YYYY (with flexible separators)
    RegExp(r'(\d{1,2})\s*[\/\-]\s*(\d{1,2})\s*[\/\-]\s*(\d{2,4})'),
    // DD.MM.YYYY (dot notation - common in India)
    RegExp(r'(\d{1,2})\.(\d{1,2})\.(\d{2,4})'),
    // DD MMM YYYY (e.g., 15 Jan 2026)
    RegExp(r'(\d{1,2})\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+(\d{2,4})', caseSensitive: false),
    // YYYY/MM/DD or YYYY-MM-DD
    RegExp(r'(\d{4})\s*[\/\-]\s*(\d{1,2})\s*[\/\-]\s*(\d{1,2})'),
  ];

  /// Month name to number mapping
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

  /// Valid liquor bottle sizes in ML for validation
  static const Set<String> _validLiquorSizes = {
    '30', '60', '90', '180', '375', '500', '650', '750', '1000', '1500', '2000',
  };

  /// Size patterns for detection - STRICT patterns to prevent false positives
  /// Single letters (Q, H, P) are NO LONGER matched standalone - they require quantity context
  static final List<RegExp> _sizePatterns = [
    // Explicit ML patterns: 180ml, 375 ml, 750ML (REQUIRED unit)
    RegExp(r'(\d+)\s*(ml|ML|mL|Ml)\b'),
    // Litre patterns: 1L, 1.5 ltr, 2 litre (REQUIRED unit)
    RegExp(r'(\d+(?:\.\d+)?)\s*(ltr|LTR|litre|LITRE|liter|LITER)\b'),
    // Full word abbreviations ONLY (not single letters): QUARTER, HALF, PINT, BOTTLE, NIP, FULL
    // These are long enough to not cause false positives
    RegExp(r'\b(QTR|QUARTER|HALF|PINT|BTL|BOTTLE|NIP|FULL)\b', caseSensitive: false),
    // Single letter abbreviations ONLY with quantity context (strict patterns)
    // Pattern: "Q-10", "H:5", "Q=10", "P-5" (letter followed by separator and number)
    RegExp(r'\b([QHP])\s*[-:=]\s*(\d+)\b', caseSensitive: false),
    // Pattern: "10Q", "5H", "3P" (number immediately followed by letter, no space)
    RegExp(r'\b(\d+)([QHP])\b', caseSensitive: false),
    // Pattern: "10 Q", "5 H" (number space letter at word boundary - strict)
    RegExp(r'\b(\d+)\s+([QHP])\s*(?:[,.\s]|$)', caseSensitive: false),
    // Size numbers ONLY when preceded by 'x' (like "5 x 180") - contextual match
    RegExp(r'[x×X]\s*(180|375|500|650|750|1000)\b'),
    // Size numbers ONLY when followed by context words (bottles, cases, pcs)
    RegExp(r'\b(180|375|500|650|750|1000)\s*(bottles?|cases?|pcs?|pieces?|nos?|units?)', caseSensitive: false),
  ];

  /// Quantity with size patterns for extraction (e.g., "5 x 180ml", "Q-10", "H:5")
  static final List<RegExp> _quantityWithSizePatterns = [
    // Pattern: "5 x 180ml", "10x750ml", "3 × 375"
    RegExp(r'\b(\d+)\s*[x×X]\s*(\d+)\s*(ml|ML|mL|Ml)?\b'),
    // Pattern: "180ml x 5", "750ml×10"
    RegExp(r'\b(\d+)\s*(ml|ML|mL|Ml)\s*[x×X]\s*(\d+)\b'),
    // Pattern: "Q-10", "H:5", "Q 10", "Q=5"
    RegExp(r'\b(Q|QTR|QUARTER|H|HALF|P|PINT|F|FULL|NIP)\s*[-:=\s]\s*(\d+)\b', caseSensitive: false),
    // Pattern: "10 Q", "5 H" (quantity before size abbreviation)
    RegExp(r'\b(\d+)\s*(Q|QTR|QUARTER|H|HALF|P|PINT|F|FULL|NIP)\b', caseSensitive: false),
  ];

  /// Known size mappings for normalization
  static const Map<String, String> _sizeNormalizations = {
    // ML sizes
    '60': '60ML',
    '90': '90ML',
    '180': '180ML',
    '375': '375ML',
    '500': '500ML',
    '650': '650ML',
    '750': '750ML',
    '1000': '1000ML',

    // Quarter variations
    'q': 'QUARTER',
    'qtr': 'QUARTER',
    'quarter': 'QUARTER',

    // Half variations
    'h': 'HALF',
    'half': 'HALF',

    // Pint variations
    'p': 'PINT',
    'pint': 'PINT',

    // Bottle variations
    'btl': 'BOTTLE',
    'bottle': 'BOTTLE',
    'full': 'FULL',

    // Nip
    'nip': 'NIP',
  };

  /// Common garbage patterns that indicate non-receipt content
  static final List<RegExp> _garbagePatterns = [
    // iOS/macOS UI elements
    RegExp(r'Simulator', caseSensitive: false),
    RegExp(r'MacBook', caseSensitive: false),
    RegExp(r'iPhone', caseSensitive: false),
    RegExp(r'iPad', caseSensitive: false),
    RegExp(r'caps\s*lock', caseSensitive: false),
    RegExp(r'control\s*option\s*command', caseSensitive: false),
    RegExp(r'shift\s*control', caseSensitive: false),
    // Keyboard keys pattern (multiple single letters with spaces)
    RegExp(r'\b[A-Z]\s+[A-Z]\s+[A-Z]\s+[A-Z]\b'),
    // Code-like patterns
    RegExp(r'daily_sales_', caseSensitive: false),
    RegExp(r'_screen', caseSensitive: false),
    RegExp(r'\.dart\b'),
    RegExp(r'package:'),
    // Terminal/console patterns
    RegExp(r'Terminal\s*Shell', caseSensitive: false),
    RegExp(r'ssh\s*connect', caseSensitive: false),
    // Google/browser content
    RegExp(r'Google\s*(Chrome|Quantum|Search)', caseSensitive: false),
    RegExp(r'Website\s*-\s*Google', caseSensitive: false),
    // Debug prefixes
    RegExp(r'\[API\]'),
    RegExp(r'\[DioAPI\]'),
    RegExp(r'\[DEBUG\]'),
    RegExp(r'\[INFO\]'),
    RegExp(r'flutter:'),
  ];

  /// Filter out invalid OCR text that likely comes from debug logs, UI elements, or garbage
  /// Returns true if the text is valid receipt content, false if it should be ignored
  bool _isValidOcrText(String text) {
    // Reject very short text
    if (text.length < 15) return false;

    // Check for garbage patterns
    for (final pattern in _garbagePatterns) {
      if (pattern.hasMatch(text)) {
        return false;
      }
    }

    // Reject text that looks like code or stack traces
    if (text.contains('Exception:') || text.contains('Error:')) return false;
    if (text.contains('debugPrint') || text.contains('print(')) return false;

    // Reject text with too many special characters (likely garbled)
    final specialCharCount = text.split('').where((c) =>
      !RegExp(r'[a-zA-Z0-9\s\.\,\-\/\:\₹\$\%\(\)]').hasMatch(c)).length;
    if (specialCharCount > text.length * 0.25) return false;

    // Reject text with too many underscores (likely code variable names)
    final underscoreCount = '_'.allMatches(text).length;
    if (underscoreCount > 3) return false;

    // Check for blur indicators: too many single-character "words" indicates garbled text
    final words = text.split(RegExp(r'\s+'));
    final singleCharWords = words.where((w) => w.length == 1).length;
    if (words.length > 5 && singleCharWords > words.length * 0.4) return false;

    // Check for repetitive patterns (like "daily_sales_" repeated)
    final uniqueWords = words.toSet();
    if (words.length > 10 && uniqueWords.length < words.length * 0.3) return false;

    return true;
  }

  /// Calculate a quality score for the OCR text (0.0 = garbage, 1.0 = high quality)
  /// This helps determine if the image is blurry or the text is garbled
  double _calculateTextQuality(String text) {
    if (text.isEmpty) return 0.0;

    double score = 1.0;

    // Penalize short text
    if (text.length < 50) score -= 0.2;
    if (text.length < 20) score -= 0.3;

    // Penalize high ratio of special characters
    final specialCharCount = text.split('').where((c) =>
      !RegExp(r'[a-zA-Z0-9\s\.\,\-\/\:]').hasMatch(c)).length;
    score -= (specialCharCount / text.length) * 0.5;

    // Penalize too many single-character words (blur indicator)
    final words = text.split(RegExp(r'\s+'));
    if (words.isNotEmpty) {
      final singleCharRatio = words.where((w) => w.length == 1).length / words.length;
      score -= singleCharRatio * 0.4;
    }

    // Penalize repetitive content
    final uniqueWords = words.toSet();
    if (words.length > 5) {
      final repetitionRatio = 1 - (uniqueWords.length / words.length);
      score -= repetitionRatio * 0.3;
    }

    // Bonus for receipt-like content
    if (RegExp(r'\d{1,2}[\/\-\.]\d{1,2}[\/\-\.]\d{2,4}').hasMatch(text)) score += 0.1; // Date
    if (RegExp(r'₹\s*\d+|Rs\.?\s*\d+', caseSensitive: false).hasMatch(text)) score += 0.1; // Price
    if (RegExp(r'\d+\s*(ml|ML|ltr|LTR)', caseSensitive: false).hasMatch(text)) score += 0.1; // Size

    return score.clamp(0.0, 1.0);
  }

  /// Validate a camera frame
  ///
  /// This method is throttled to run at most once per second.
  /// [image] - Camera image to process
  /// [shopName] - Expected shop name for matching
  Future<void> validateFrame(CameraImage image, String shopName) async {
    // Skip if already processing or throttled
    if (_isProcessing) return;

    // Apply throttling
    if (_throttleTimer?.isActive ?? false) return;

    _isProcessing = true;
    _throttleTimer = Timer(const Duration(milliseconds: _throttleIntervalMs), () {});

    try {
      // Convert camera image to InputImage
      final inputImage = _convertCameraImage(image);
      if (inputImage == null) {
        _isProcessing = false;
        return;
      }

      // Run text recognition
      final recognizedText = await _textRecognizer.processImage(inputImage);
      final fullText = recognizedText.text;

      // Filter out debug/console text
      if (!_isValidOcrText(fullText)) {
        debugPrint('🚫 [LiveValidator] Rejected: garbage/debug text detected');
        _isProcessing = false;
        return;
      }

      // Calculate text quality score
      final qualityScore = _calculateTextQuality(fullText);
      if (qualityScore < 0.3) {
        debugPrint('🚫 [LiveValidator] Rejected: low quality score (${(qualityScore * 100).toInt()}%) - likely blurry');
        _isProcessing = false;
        return;
      }

      debugPrint('📝 [LiveValidator] Processing (quality: ${(qualityScore * 100).toInt()}%)');

      // Extract and validate content
      final dateResult = _extractDate(fullText);
      final shopResult = _matchShopName(fullText, shopName);
      final sizesResult = _extractSizes(fullText);

      // Update result
      _lastResult = LiveValidationResult(
        dateFound: dateResult.$1,
        rawDateString: dateResult.$2,
        shopMatched: shopResult.$1,
        shopMatchConfidence: shopResult.$2,
        detectedShopName: shopResult.$3,
        sizesFound: sizesResult,
        rawText: fullText,
      );

      // Detailed logging for what was found
      final dateStatus = dateResult.$1 != null ? '✅ ${dateResult.$2}' : '❌ not found';
      final shopStatus = shopResult.$1 ? '✅ matched (${(shopResult.$2 * 100).toInt()}%)' : '❌ not matched';
      final sizeStatus = sizesResult.isNotEmpty ? '✅ ${sizesResult.join(", ")}' : '❌ none';

      debugPrint('📊 [LiveValidator] Results:');
      debugPrint('   📅 Date: $dateStatus');
      debugPrint('   🏪 Shop: $shopStatus');
      debugPrint('   📏 Sizes: $sizeStatus');

      // Notify callback
      onValidationUpdate?.call(_lastResult);
    } catch (e) {
      debugPrint('❌ [LiveValidator] Error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  /// Validate from InputImage directly (for use with ML Kit Document Scanner)
  Future<LiveValidationResult> validateInputImage(InputImage inputImage, String shopName) async {
    try {
      final recognizedText = await _textRecognizer.processImage(inputImage);
      final fullText = recognizedText.text;

      // Filter out debug/console text
      if (!_isValidOcrText(fullText)) {
        return LiveValidationResult.empty();
      }

      final dateResult = _extractDate(fullText);
      final shopResult = _matchShopName(fullText, shopName);
      final sizesResult = _extractSizes(fullText);

      return LiveValidationResult(
        dateFound: dateResult.$1,
        rawDateString: dateResult.$2,
        shopMatched: shopResult.$1,
        shopMatchConfidence: shopResult.$2,
        detectedShopName: shopResult.$3,
        sizesFound: sizesResult,
        rawText: fullText,
      );
    } catch (e) {
      debugPrint('❌ [LiveValidator] Error validating image: $e');
      return LiveValidationResult.empty();
    }
  }

  /// Validate from raw text (for testing or when text is already available)
  LiveValidationResult validateText(String text, String shopName) {
    final dateResult = _extractDate(text);
    final shopResult = _matchShopName(text, shopName);
    final sizesResult = _extractSizes(text);

    return LiveValidationResult(
      dateFound: dateResult.$1,
      rawDateString: dateResult.$2,
      shopMatched: shopResult.$1,
      shopMatchConfidence: shopResult.$2,
      detectedShopName: shopResult.$3,
      sizesFound: sizesResult,
      rawText: text,
    );
  }

  /// Convert CameraImage to InputImage for ML Kit
  InputImage? _convertCameraImage(CameraImage image) {
    try {
      // Get rotation based on device orientation
      // For simplicity, we'll use rotation0 - in production, get from sensor orientation
      const rotation = InputImageRotation.rotation0deg;

      // Convert to InputImage format
      final format = InputImageFormatValue.fromRawValue(image.format.raw);
      if (format == null) return null;

      final plane = image.planes.first;

      return InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
    } catch (e) {
      debugPrint('❌ [LiveValidator] Error converting camera image: $e');
      return null;
    }
  }

  /// Extract date from OCR text
  /// Returns (DateTime?, rawString?)
  (DateTime?, String?) _extractDate(String text) {
    for (final pattern in _datePatterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        try {
          final rawString = match.group(0) ?? '';
          final date = _parseDate(match, pattern);
          if (date != null && _isValidDate(date)) {
            return (date, rawString);
          }
        } catch (e) {
          // Continue to next pattern
        }
      }
    }
    return (null, null);
  }

  /// Parse date from regex match
  DateTime? _parseDate(RegExpMatch match, RegExp pattern) {
    try {
      // DD/MM/YYYY or DD-MM-YYYY (flexible separators)
      if (pattern == _datePatterns[0]) {
        final day = int.parse(match.group(1)!);
        final month = int.parse(match.group(2)!);
        var year = int.parse(match.group(3)!);
        if (year < 100) year += 2000; // Handle 2-digit years
        return DateTime(year, month, day);
      }

      // DD.MM.YYYY (dot notation)
      if (pattern == _datePatterns[1]) {
        final day = int.parse(match.group(1)!);
        final month = int.parse(match.group(2)!);
        var year = int.parse(match.group(3)!);
        if (year < 100) year += 2000; // Handle 2-digit years
        return DateTime(year, month, day);
      }

      // DD MMM YYYY
      if (pattern == _datePatterns[2]) {
        final day = int.parse(match.group(1)!);
        final monthStr = match.group(2)!.toLowerCase();
        final month = _monthNames[monthStr] ?? 1;
        var year = int.parse(match.group(3)!);
        if (year < 100) year += 2000;
        return DateTime(year, month, day);
      }

      // YYYY/MM/DD or YYYY-MM-DD
      if (pattern == _datePatterns[3]) {
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

  /// Check if date is valid (not future, not too old)
  /// Extended to 365 days to handle older receipts and various business scenarios
  bool _isValidDate(DateTime date) {
    final now = DateTime.now();
    final oneYearAgo = now.subtract(const Duration(days: 365));

    // Date should be between 365 days ago and tomorrow (allow slight future dates for timezone issues)
    return date.isBefore(now.add(const Duration(days: 1))) && date.isAfter(oneYearAgo);
  }

  /// Minimum word length for shop name matching (skip "No", "The", etc.)
  static const int _minWordLength = 4;

  /// Minimum similarity threshold for word matching (raised from 0.7 to 0.85)
  static const double _wordSimilarityThreshold = 0.85;

  /// Minimum confidence for shop name match (raised from 0.7 to 0.85)
  static const double _shopMatchConfidenceThreshold = 0.85;

  /// Match shop name in OCR text
  /// Returns (isMatch, confidence, detectedName)
  (bool, double, String?) _matchShopName(String text, String expectedName) {
    if (expectedName.isEmpty) return (false, 0.0, null);

    final normalizedText = text.toLowerCase();
    final normalizedExpected = expectedName.toLowerCase();

    // Direct match
    if (normalizedText.contains(normalizedExpected)) {
      return (true, 1.0, expectedName);
    }

    // Split into words and try to match
    final expectedWords = normalizedExpected.split(RegExp(r'\s+'));
    final textWords = normalizedText.split(RegExp(r'\s+'));

    // Filter to significant words (length >= _minWordLength)
    final significantExpectedWords = expectedWords.where((w) => w.length >= _minWordLength).toList();

    // If no significant words, require exact substring match
    if (significantExpectedWords.isEmpty) return (false, 0.0, null);

    // Count matching words with proper Levenshtein similarity
    int matchedWords = 0;
    final matchedTextWords = <String>[];

    for (final expectedWord in significantExpectedWords) {
      bool foundMatch = false;
      for (final textWord in textWords) {
        // Skip very short text words (likely noise)
        if (textWord.length < _minWordLength) continue;

        // Check for high-confidence similarity match
        final similarity = _calculateSimilarity(expectedWord, textWord);
        if (similarity >= _wordSimilarityThreshold) {
          matchedWords++;
          matchedTextWords.add(textWord);
          foundMatch = true;
          break;
        }
      }
      // Also check if expected word is contained exactly in any text word
      if (!foundMatch) {
        for (final textWord in textWords) {
          if (textWord.length >= expectedWord.length && textWord.contains(expectedWord)) {
            matchedWords++;
            matchedTextWords.add(textWord);
            break;
          }
        }
      }
    }

    // Require at least 2 significant words to match (or all if fewer than 2 expected)
    final minRequiredMatches = significantExpectedWords.length >= 2 ? 2 : significantExpectedWords.length;
    if (matchedWords < minRequiredMatches) return (false, 0.0, null);

    final confidence = matchedWords / significantExpectedWords.length;
    final isMatch = confidence >= _shopMatchConfidenceThreshold;

    // Try to find the detected shop name in text
    String? detectedName;
    if (matchedWords > 0 && matchedTextWords.isNotEmpty) {
      // Look for consecutive words that match
      for (var i = 0; i < textWords.length; i++) {
        if (matchedTextWords.contains(textWords[i])) {
          // Found a match, grab surrounding words
          final start = (i - 1).clamp(0, textWords.length - 1);
          final end = (i + 3).clamp(0, textWords.length);
          detectedName = textWords.sublist(start, end).join(' ');
          break;
        }
      }
    }

    return (isMatch, confidence, detectedName);
  }

  /// Calculate string similarity using proper Levenshtein distance
  /// This replaces the broken character overlap algorithm that caused false positives
  double _calculateSimilarity(String a, String b) {
    if (a == b) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;

    final longer = a.length > b.length ? a : b;
    final shorter = a.length > b.length ? b : a;

    // Quick rejection: if length difference > 50%, similarity is low
    if (shorter.length < longer.length * 0.5) return 0.0;

    // Compute Levenshtein distance using dynamic programming
    final d = List.generate(
      shorter.length + 1,
      (i) => List.generate(longer.length + 1, (j) => 0),
    );

    // Initialize base cases
    for (int i = 0; i <= shorter.length; i++) {
      d[i][0] = i;
    }
    for (int j = 0; j <= longer.length; j++) {
      d[0][j] = j;
    }

    // Fill in the distance matrix
    for (int i = 1; i <= shorter.length; i++) {
      for (int j = 1; j <= longer.length; j++) {
        final cost = shorter[i - 1] == longer[j - 1] ? 0 : 1;
        d[i][j] = _minOfThree(
          d[i - 1][j] + 1, // deletion
          d[i][j - 1] + 1, // insertion
          d[i - 1][j - 1] + cost, // substitution
        );
      }
    }

    // Convert distance to similarity ratio
    final maxLen = longer.length;
    final distance = d[shorter.length][longer.length];
    return (maxLen - distance) / maxLen;
  }

  /// Helper to find minimum of three integers
  int _minOfThree(int a, int b, int c) {
    if (a <= b && a <= c) return a;
    if (b <= c) return b;
    return c;
  }

  /// Extract size values from OCR text
  /// Only returns valid liquor bottle sizes with proper context
  /// STRICT: Single letters are only extracted when they have quantity context
  List<String> _extractSizes(String text) {
    final sizes = <String>{};

    for (int i = 0; i < _sizePatterns.length; i++) {
      final pattern = _sizePatterns[i];
      final matches = pattern.allMatches(text);

      for (final match in matches) {
        final detected = match.group(0) ?? '';

        // For patterns 3, 4, 5 (single letter with quantity context), extract the letter part
        // These patterns are: "Q-10", "10Q", "10 Q"
        String toNormalize = detected;
        if (i >= 3 && i <= 5) {
          // Extract just the letter abbreviation from context patterns
          final letterMatch = RegExp(r'[QHP]', caseSensitive: false).firstMatch(detected);
          if (letterMatch != null) {
            toNormalize = letterMatch.group(0)!;
          }
        }

        final normalized = _normalizeSize(toNormalize);

        // For single-letter patterns (i >= 3 && i <= 5), we validate the full word equivalent
        if (i >= 3 && i <= 5) {
          // Single letter was extracted with quantity context - it's valid
          // Normalize to full word: Q->QUARTER, H->HALF, P->PINT
          final fullWord = _singleLetterToFullWord(normalized);
          if (fullWord.isNotEmpty) {
            sizes.add(fullWord);
          }
        } else if (normalized.isNotEmpty && _isValidLiquorSize(normalized)) {
          sizes.add(normalized);
        }
      }
    }

    return sizes.toList();
  }

  /// Convert single letter size abbreviation to full word
  String _singleLetterToFullWord(String letter) {
    switch (letter.toUpperCase()) {
      case 'Q':
        return 'QUARTER';
      case 'H':
        return 'HALF';
      case 'P':
        return 'PINT';
      default:
        return '';
    }
  }

  /// Validate if a normalized size is a known valid liquor bottle size
  /// STRICT: Single letters (Q, H, P) are NOT valid on their own - they need quantity context
  bool _isValidLiquorSize(String normalizedSize) {
    if (normalizedSize.isEmpty) return false;

    final upper = normalizedSize.toUpperCase().trim();

    // Check for ML sizes
    final mlMatch = RegExp(r'^(\d+)ML$').firstMatch(upper);
    if (mlMatch != null) {
      return _validLiquorSizes.contains(mlMatch.group(1));
    }

    // REJECT single letters - they must have been matched with quantity context
    // The patterns that match "Q-10", "5H", etc. will extract full context
    if (upper.length == 1) {
      return false; // Single letters like Q, H, P are NOT valid without context
    }

    // Check for known FULL WORD abbreviations (not single letters)
    const validAbbreviations = {
      'QUARTER', 'QTR',  // Full words for Quarter
      'HALF',            // Full word for Half
      'PINT',            // Full word for Pint
      'BOTTLE', 'BTL',   // Full words for Bottle
      'NIP',             // Nip
      'FULL',            // Full
    };
    return validAbbreviations.contains(upper);
  }

  /// Extract sizes with associated quantities from OCR text
  /// Returns a map of normalized size -> quantity
  /// e.g., {"180ML": 5, "QUARTER": 10, "750ML": 3}
  Map<String, int> extractSizesWithQuantities(String text) {
    final sizeQuantities = <String, int>{};

    for (final pattern in _quantityWithSizePatterns) {
      final matches = pattern.allMatches(text);
      for (final match in matches) {
        try {
          final fullMatch = match.group(0) ?? '';

          // Pattern: "5 x 180ml" - quantity first, then size
          if (pattern.pattern.contains(r'(\d+)\s*[x×X]\s*(\d+)')) {
            final quantityStr = match.group(1);
            final sizeStr = match.group(2);
            if (quantityStr != null && sizeStr != null) {
              final quantity = int.tryParse(quantityStr) ?? 1;
              final normalized = _normalizeSize(sizeStr);
              if (normalized.isNotEmpty) {
                sizeQuantities[normalized] = (sizeQuantities[normalized] ?? 0) + quantity;
              }
            }
          }
          // Pattern: "180ml x 5" - size first, then quantity
          else if (pattern.pattern.contains(r'(\d+)\s*(ml|ML|mL|Ml)\s*[x×X]\s*(\d+)')) {
            final sizeStr = match.group(1);
            final quantityStr = match.group(3);
            if (quantityStr != null && sizeStr != null) {
              final quantity = int.tryParse(quantityStr) ?? 1;
              final normalized = _normalizeSize('${sizeStr}ml');
              if (normalized.isNotEmpty) {
                sizeQuantities[normalized] = (sizeQuantities[normalized] ?? 0) + quantity;
              }
            }
          }
          // Pattern: "Q-10", "H:5" - size abbreviation with quantity
          else if (pattern.pattern.contains(r'(Q|QTR|QUARTER|H|HALF')) {
            final sizeStr = match.group(1);
            final quantityStr = match.group(2);
            if (sizeStr != null && quantityStr != null) {
              final quantity = int.tryParse(quantityStr) ?? 1;
              final normalized = _normalizeSize(sizeStr);
              if (normalized.isNotEmpty) {
                sizeQuantities[normalized] = (sizeQuantities[normalized] ?? 0) + quantity;
              }
            }
          }
          // Pattern: "10 Q", "5 H" - quantity before size abbreviation
          else if (fullMatch.contains(RegExp(r'\d+\s*[QHPFN]', caseSensitive: false))) {
            final numMatch = RegExp(r'(\d+)\s*([QHPFN])', caseSensitive: false).firstMatch(fullMatch);
            if (numMatch != null) {
              final quantityStr = numMatch.group(1);
              final sizeStr = numMatch.group(2);
              if (quantityStr != null && sizeStr != null) {
                final quantity = int.tryParse(quantityStr) ?? 1;
                final normalized = _normalizeSize(sizeStr);
                if (normalized.isNotEmpty) {
                  sizeQuantities[normalized] = (sizeQuantities[normalized] ?? 0) + quantity;
                }
              }
            }
          }
        } catch (e) {
          debugPrint('❌ [LiveValidator] Error extracting size with quantity: $e');
        }
      }
    }

    return sizeQuantities;
  }

  /// Normalize detected size to standard format
  String _normalizeSize(String detected) {
    final lower = detected.toLowerCase().replaceAll(RegExp(r'\s+'), '');

    // Check direct mappings
    if (_sizeNormalizations.containsKey(lower)) {
      return _sizeNormalizations[lower]!;
    }

    // Handle ML sizes (e.g., "180ml" -> "180ML")
    final mlMatch = RegExp(r'^(\d+)\s*(ml|ML|mL|Ml)$', caseSensitive: false).firstMatch(detected);
    if (mlMatch != null) {
      return '${mlMatch.group(1)}ML';
    }

    // Handle litre sizes (e.g., "1L" -> "1000ML", "1.5L" -> "1500ML")
    final litreMatch = RegExp(r'^(\d+(?:\.\d+)?)\s*(l|L|ltr|LTR|litre|LITRE|liter|LITER)$', caseSensitive: false).firstMatch(detected);
    if (litreMatch != null) {
      final value = double.tryParse(litreMatch.group(1)!) ?? 0;
      return '${(value * 1000).round()}ML';
    }

    // Check if it's a known standalone number
    final numMatch = RegExp(r'^(\d+)$').firstMatch(detected);
    if (numMatch != null && _sizeNormalizations.containsKey(numMatch.group(1))) {
      return _sizeNormalizations[numMatch.group(1)]!;
    }

    return detected.toUpperCase();
  }

  /// Get last validation result
  LiveValidationResult get lastResult => _lastResult;

  /// Reset validation state
  void reset() {
    _lastResult = LiveValidationResult.empty();
    _throttleTimer?.cancel();
    _isProcessing = false;
  }

  /// Dispose resources
  void dispose() {
    _throttleTimer?.cancel();
    _textRecognizer.close();
  }
}
