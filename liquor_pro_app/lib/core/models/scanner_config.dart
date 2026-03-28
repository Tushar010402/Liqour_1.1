import '../services/image_preprocessing_service.dart';

/// Scan mode for different document types
enum ScanMode {
  /// Daily sales receipts - multiple images, fast workflow
  receipt,

  /// Bank submission slips - single document, verification required
  bankSlip,

  /// Purchase invoices - multi-page OCR optimized
  invoice,

  /// Product images - flexible settings
  product,
}

/// Configuration for document scanner
///
/// Defines behavior for different scan scenarios:
/// - Receipt: Fast multi-page scanning for daily sales
/// - Bank Slip: Single document with preview verification
/// - Invoice: Multi-page OCR-optimized scanning
class ScannerConfig {
  /// Scan mode determining document type
  final ScanMode mode;

  /// Maximum number of pages to scan in one session
  final int maxPages;

  /// Maximum width for processed images (height auto-calculated)
  final int maxWidth;

  /// JPEG compression quality (0-100)
  final int jpegQuality;

  /// Image filter to apply during preprocessing
  final ImageFilter filter;

  /// Whether to detect and auto-fill empty form fields
  final bool autoFillEmptyFields;

  /// Whether to show preview screen after each capture
  final bool showPreview;

  /// Whether gallery import is allowed
  final bool allowGalleryImport;

  /// Minimum blur score required for acceptance (0-100)
  /// Images below this score will trigger quality feedback
  /// Set to 0 to disable quality validation
  final double minBlurScore;

  /// Whether to enable live camera quality validation (blur, lighting, edges)
  /// When true, uses the industrial-grade LiveCameraScannerWidget with
  /// real-time image quality feedback. Content validation (date, shop, sizes)
  /// is handled by backend after capture.
  final bool enableLiveValidation;

  const ScannerConfig({
    required this.mode,
    this.maxPages = 5,
    this.maxWidth = 1920,
    this.jpegQuality = 95,
    this.filter = ImageFilter.documentEnhance,  // Default: CamScanner-quality enhancement
    this.autoFillEmptyFields = false,
    this.showPreview = true,
    this.allowGalleryImport = true,
    this.minBlurScore = 20.0,  // Default: reject very blurry images
    this.enableLiveValidation = false,  // Default: use standard scanner
  });

  /// Create a copy with modified values
  ScannerConfig copyWith({
    ScanMode? mode,
    int? maxPages,
    int? maxWidth,
    int? jpegQuality,
    ImageFilter? filter,
    bool? autoFillEmptyFields,
    bool? showPreview,
    bool? allowGalleryImport,
    double? minBlurScore,
    bool? enableLiveValidation,
  }) {
    return ScannerConfig(
      mode: mode ?? this.mode,
      maxPages: maxPages ?? this.maxPages,
      maxWidth: maxWidth ?? this.maxWidth,
      jpegQuality: jpegQuality ?? this.jpegQuality,
      filter: filter ?? this.filter,
      autoFillEmptyFields: autoFillEmptyFields ?? this.autoFillEmptyFields,
      showPreview: showPreview ?? this.showPreview,
      allowGalleryImport: allowGalleryImport ?? this.allowGalleryImport,
      minBlurScore: minBlurScore ?? this.minBlurScore,
      enableLiveValidation: enableLiveValidation ?? this.enableLiveValidation,
    );
  }

  @override
  String toString() {
    return 'ScannerConfig(mode: $mode, maxPages: $maxPages, quality: $jpegQuality%, preview: $showPreview)';
  }
}
