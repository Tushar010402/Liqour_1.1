/// Scan Quality Models for Industrial-Grade Image Scanning
///
/// Data structures for real-time validation, quality assessment,
/// and OCR confirmation in the daily sales entry flow.
library;

import 'dart:ui';

import 'package:flutter/material.dart';

/// Result of live camera frame validation (runs during preview)
class LiveValidationResult {
  /// Detected date from receipt (null if not found)
  final DateTime? dateFound;

  /// Raw date string as detected
  final String? rawDateString;

  /// Whether shop name was matched in the frame
  final bool shopMatched;

  /// Matched shop name confidence (0.0 - 1.0)
  final double shopMatchConfidence;

  /// Detected shop name from OCR (even if not matched)
  final String? detectedShopName;

  /// List of size values detected (e.g., "180ml", "750", "Q")
  final List<String> sizesFound;

  /// Raw OCR text from the frame
  final String rawText;

  /// Timestamp of validation
  final DateTime timestamp;

  /// Whether all required fields are detected
  bool get allFieldsDetected =>
      dateFound != null && shopMatched && sizesFound.isNotEmpty;

  /// Number of checks passed (out of 3: date, shop, sizes)
  int get checksPassedCount {
    int count = 0;
    if (dateFound != null) count++;
    if (shopMatched) count++;
    if (sizesFound.isNotEmpty) count++;
    return count;
  }

  /// Overall validation status
  ValidationStatus get status {
    if (checksPassedCount == 3) return ValidationStatus.allPassed;
    if (checksPassedCount >= 1) return ValidationStatus.partiallyPassed;
    return ValidationStatus.failed;
  }

  LiveValidationResult({
    this.dateFound,
    this.rawDateString,
    this.shopMatched = false,
    this.shopMatchConfidence = 0.0,
    this.detectedShopName,
    this.sizesFound = const [],
    this.rawText = '',
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Empty/default result
  factory LiveValidationResult.empty() {
    return LiveValidationResult(
      rawText: '',
      sizesFound: [],
    );
  }

  /// Create from another result with updates
  LiveValidationResult copyWith({
    DateTime? dateFound,
    String? rawDateString,
    bool? shopMatched,
    double? shopMatchConfidence,
    String? detectedShopName,
    List<String>? sizesFound,
    String? rawText,
  }) {
    return LiveValidationResult(
      dateFound: dateFound ?? this.dateFound,
      rawDateString: rawDateString ?? this.rawDateString,
      shopMatched: shopMatched ?? this.shopMatched,
      shopMatchConfidence: shopMatchConfidence ?? this.shopMatchConfidence,
      detectedShopName: detectedShopName ?? this.detectedShopName,
      sizesFound: sizesFound ?? this.sizesFound,
      rawText: rawText ?? this.rawText,
    );
  }
}

/// Overall validation status enum
enum ValidationStatus {
  /// All checks passed - ready to capture
  allPassed,

  /// Some checks passed - capture with warning
  partiallyPassed,

  /// No checks passed - block capture with tips
  failed,
}

/// Image quality assessment result
class ScanQualityResult {
  /// Blur score (0-100, higher = sharper)
  final double blurScore;

  /// Blur quality tier
  final BlurQualityTier blurQuality;

  /// Lighting score (0-100, 50 = ideal)
  final double lightingScore;

  /// Lighting quality tier
  final LightingQualityTier lightingQuality;

  /// Whether document edges were detected
  final bool edgesDetected;

  /// Number of document corners detected (0-4)
  final int cornersDetected;

  /// Document area ratio (0.0 - 1.0, percentage of frame)
  final double documentAreaRatio;

  /// Overall quality score (0-100)
  double get overallScore {
    double score = 0;

    // Blur contributes 40%
    score += blurScore * 0.4;

    // Lighting contributes 30%
    score += lightingScore * 0.3;

    // Edge detection contributes 20%
    if (edgesDetected) score += 20;

    // Document area contributes 10%
    score += (documentAreaRatio * 100).clamp(0, 10);

    return score.clamp(0, 100);
  }

  /// Overall quality tier
  QualityTier get overallQuality {
    final score = overallScore;
    if (score >= 60) return QualityTier.excellent;
    if (score >= 40) return QualityTier.good;
    if (score >= 20) return QualityTier.acceptable;
    return QualityTier.poor;
  }

  /// Whether quality is acceptable for capture
  bool get isAcceptable => overallQuality != QualityTier.poor;

  /// List of issues found (for tips display)
  List<QualityIssue> get issues {
    final issues = <QualityIssue>[];

    if (blurQuality == BlurQualityTier.tooBlurry) {
      issues.add(QualityIssue.blurry);
    }

    if (lightingQuality == LightingQualityTier.tooDark) {
      issues.add(QualityIssue.tooDark);
    } else if (lightingQuality == LightingQualityTier.tooBright) {
      issues.add(QualityIssue.tooBright);
    }

    if (!edgesDetected || cornersDetected < 3) {
      issues.add(QualityIssue.noEdges);
    }

    if (documentAreaRatio < 0.1) {
      issues.add(QualityIssue.tooSmall);
    }

    return issues;
  }

  ScanQualityResult({
    required this.blurScore,
    required this.blurQuality,
    required this.lightingScore,
    required this.lightingQuality,
    this.edgesDetected = false,
    this.cornersDetected = 0,
    this.documentAreaRatio = 0.0,
  });

  /// Default/empty result
  factory ScanQualityResult.empty() {
    return ScanQualityResult(
      blurScore: 50,
      blurQuality: BlurQualityTier.good,
      lightingScore: 50,
      lightingQuality: LightingQualityTier.good,
    );
  }
}

/// Blur quality tiers
enum BlurQualityTier {
  /// Score >= 60: Sharp and clear
  excellent,

  /// Score 40-59: Minor blur, acceptable
  good,

  /// Score 20-39: Noticeable blur, may affect OCR
  acceptable,

  /// Score < 20: Too blurry for reliable OCR
  tooBlurry,
}

/// Lighting quality tiers
enum LightingQualityTier {
  /// Well-lit, even lighting
  good,

  /// Slightly over/under exposed
  acceptable,

  /// Too dark, shadows may affect OCR
  tooDark,

  /// Overexposed, may wash out text
  tooBright,
}

/// Overall quality tiers
enum QualityTier {
  /// Score >= 60: Ready for OCR
  excellent,

  /// Score 40-59: Good enough
  good,

  /// Score 20-39: Usable with warnings
  acceptable,

  /// Score < 20: Should retry
  poor,
}

/// Quality issues for tips display
enum QualityIssue {
  /// Image is too blurry
  blurry,

  /// Image is too dark
  tooDark,

  /// Image is overexposed
  tooBright,

  /// No document edges detected
  noEdges,

  /// Document too small in frame
  tooSmall,
}

/// Extension for quality issue tips
extension QualityIssueTips on QualityIssue {
  /// Get tips for this issue
  List<String> get tips {
    switch (this) {
      case QualityIssue.blurry:
        return [
          'Hold phone steady with both hands',
          'Rest phone on a surface',
          'Wait for autofocus before capturing',
        ];
      case QualityIssue.tooDark:
        return [
          'Move to a brighter area',
          'Turn on the flash',
          'Position near a window or light source',
        ];
      case QualityIssue.tooBright:
        return [
          'Move away from direct light',
          'Turn off the flash',
          'Avoid reflective surfaces',
        ];
      case QualityIssue.noEdges:
        return [
          'Position document fully in frame',
          'Use a contrasting background',
          'Ensure document is flat',
        ];
      case QualityIssue.tooSmall:
        return [
          'Move closer to the document',
          'Fill at least 50% of the frame',
          'Ensure all text is visible',
        ];
    }
  }

  /// Icon for this issue
  IconData get icon {
    switch (this) {
      case QualityIssue.blurry:
        return Icons.blur_on;
      case QualityIssue.tooDark:
        return Icons.brightness_low;
      case QualityIssue.tooBright:
        return Icons.wb_sunny;
      case QualityIssue.noEdges:
        return Icons.crop_free;
      case QualityIssue.tooSmall:
        return Icons.zoom_in;
    }
  }

  /// Short label for this issue
  String get label {
    switch (this) {
      case QualityIssue.blurry:
        return 'Blurry';
      case QualityIssue.tooDark:
        return 'Too Dark';
      case QualityIssue.tooBright:
        return 'Too Bright';
      case QualityIssue.noEdges:
        return 'No Edges';
      case QualityIssue.tooSmall:
        return 'Too Small';
    }
  }
}

/// Receipt validation result (after OCR processing)
class ReceiptValidationResult {
  /// Whether overall validation passed
  final bool isValid;

  /// Overall validation score (0-100)
  final double overallScore;

  /// Date validation result
  final DateValidation? dateValidation;

  /// List of size validations
  final List<SizeValidation> sizeValidations;

  /// Shop validation result
  final ShopValidation? shopValidation;

  /// Warning messages (non-blocking)
  final List<String> warnings;

  /// Error messages (blocking)
  final List<String> errors;

  ReceiptValidationResult({
    required this.isValid,
    required this.overallScore,
    this.dateValidation,
    this.sizeValidations = const [],
    this.shopValidation,
    this.warnings = const [],
    this.errors = const [],
  });

  /// Empty/default result
  factory ReceiptValidationResult.empty() {
    return ReceiptValidationResult(
      isValid: false,
      overallScore: 0,
    );
  }
}

/// Date validation details
class DateValidation {
  /// Detected date
  final DateTime detectedDate;

  /// Raw date string from OCR
  final String rawString;

  /// Whether date is in valid range (not future, not too old)
  final bool isInValidRange;

  /// Whether date was found in top 20% of document
  final bool isInExpectedPosition;

  /// Confidence score (0.0 - 1.0)
  final double confidence;

  /// Position in document (normalized 0.0 - 1.0 from top)
  final double positionY;

  DateValidation({
    required this.detectedDate,
    required this.rawString,
    required this.isInValidRange,
    required this.isInExpectedPosition,
    required this.confidence,
    required this.positionY,
  });

  /// Whether date validation passed
  bool get isValid => isInValidRange && confidence >= 0.7;
}

/// Size value validation details
class SizeValidation {
  /// Detected size string (e.g., "180ml", "750", "Q")
  final String detectedSize;

  /// Normalized size value (e.g., "180ML", "750ML", "QUARTER")
  final String normalizedSize;

  /// Whether size was matched to a known product size
  final bool isKnownSize;

  /// Matched product size constant (if known)
  final String? matchedProductSize;

  /// Quantity detected alongside this size
  final int? quantity;

  /// Confidence score (0.0 - 1.0)
  final double confidence;

  SizeValidation({
    required this.detectedSize,
    required this.normalizedSize,
    required this.isKnownSize,
    this.matchedProductSize,
    this.quantity,
    required this.confidence,
  });
}

/// Shop name validation details
class ShopValidation {
  /// Detected shop name from OCR
  final String detectedName;

  /// Expected shop name
  final String expectedName;

  /// Whether names match (fuzzy matching)
  final bool isMatch;

  /// Match confidence (0.0 - 1.0)
  final double matchConfidence;

  /// Similarity score (0.0 - 1.0)
  final double similarityScore;

  ShopValidation({
    required this.detectedName,
    required this.expectedName,
    required this.isMatch,
    required this.matchConfidence,
    required this.similarityScore,
  });
}

/// OCR extracted item for confirmation
class ExtractedItem {
  /// Unique identifier
  final String id;

  /// Brand name detected
  final String brandName;

  /// Size detected (e.g., "180ml")
  final String size;

  /// Quantity detected
  final int quantity;

  /// Price detected (if available)
  final double? price;

  /// Total amount (quantity * price)
  final double? totalAmount;

  /// Whether item was verified by user
  bool isVerified;

  /// Whether item was edited by user
  bool isEdited;

  /// Confidence score from OCR (0.0 - 1.0)
  final double confidence;

  /// Bounding box in image (normalized coordinates)
  final Rect? boundingBox;

  ExtractedItem({
    required this.id,
    required this.brandName,
    required this.size,
    required this.quantity,
    this.price,
    this.totalAmount,
    this.isVerified = false,
    this.isEdited = false,
    required this.confidence,
    this.boundingBox,
  });

  /// Create a copy with updates
  ExtractedItem copyWith({
    String? brandName,
    String? size,
    int? quantity,
    double? price,
    double? totalAmount,
    bool? isVerified,
    bool? isEdited,
  }) {
    return ExtractedItem(
      id: id,
      brandName: brandName ?? this.brandName,
      size: size ?? this.size,
      quantity: quantity ?? this.quantity,
      price: price ?? this.price,
      totalAmount: totalAmount ?? this.totalAmount,
      isVerified: isVerified ?? this.isVerified,
      isEdited: isEdited ?? this.isEdited,
      confidence: confidence,
      boundingBox: boundingBox,
    );
  }
}

/// OCR extraction result for confirmation modal
class OCRExtractionResult {
  /// Detected date
  final DateTime? date;

  /// Raw date string
  final String? rawDateString;

  /// Detected shop name
  final String? shopName;

  /// Whether shop name matched expected
  final bool shopMatched;

  /// List of extracted items
  final List<ExtractedItem> items;

  /// Overall confidence score (0.0 - 1.0)
  final double overallConfidence;

  /// Number of items verified
  int get verifiedCount => items.where((item) => item.isVerified).length;

  /// Whether all items are verified
  bool get allVerified => items.isNotEmpty && items.every((item) => item.isVerified);

  /// Total quantity across all items
  int get totalQuantity => items.fold(0, (sum, item) => sum + item.quantity);

  /// Total amount across all items
  double get totalAmount => items.fold(0.0, (sum, item) => sum + (item.totalAmount ?? 0));

  OCRExtractionResult({
    this.date,
    this.rawDateString,
    this.shopName,
    this.shopMatched = false,
    this.items = const [],
    this.overallConfidence = 0.0,
  });

  /// Empty/default result
  factory OCRExtractionResult.empty() {
    return OCRExtractionResult();
  }
}

/// Camera overlay configuration
class CameraOverlayConfig {
  /// Whether to show blur indicator
  final bool showBlurIndicator;

  /// Whether to show edge detection overlay
  final bool showEdgeOverlay;

  /// Whether to show content validation checklist
  final bool showValidationChecklist;

  /// Whether to show capture guidance
  final bool showCaptureGuidance;

  /// Color for detected edges (document found)
  final Color edgeDetectedColor;

  /// Color for missing edges (no document)
  final Color edgeMissingColor;

  /// Minimum blur score to allow capture
  final double minBlurScore;

  /// Target document area ratio
  final double targetDocumentRatio;

  CameraOverlayConfig({
    this.showBlurIndicator = true,
    this.showEdgeOverlay = true,
    this.showValidationChecklist = true,
    this.showCaptureGuidance = true,
    this.edgeDetectedColor = const Color(0xFF4CAF50), // Green
    this.edgeMissingColor = const Color(0xFFF44336), // Red
    this.minBlurScore = 20.0,
    this.targetDocumentRatio = 0.5,
  });

  /// Default configuration
  factory CameraOverlayConfig.defaults() {
    return CameraOverlayConfig();
  }
}
