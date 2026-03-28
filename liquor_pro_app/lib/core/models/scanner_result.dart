import 'dart:io';

/// Error types for scanner operations
enum ScannerErrorType {
  /// Camera or storage permission denied
  permissionDenied,

  /// Camera hardware unavailable or in-use
  cameraUnavailable,

  /// Image processing failed
  processingFailed,

  /// Out of memory during processing
  outOfMemory,

  /// User cancelled the operation
  cancelled,

  /// Unknown error
  unknown,
}

/// Metadata about the scanning session
class ScannerMetadata {
  /// Total number of pages scanned
  final int totalPages;

  /// Time taken for processing
  final Duration? processingTime;

  /// List of enhancements applied
  final List<String> appliedEnhancements;

  /// Whether edge detection was successfully applied
  final bool edgesDetected;

  /// Original image dimensions
  final Size? originalSize;

  /// Processed image dimensions
  final Size? processedSize;

  /// Whether the image still needs enhancement (for modern UX pattern)
  /// When true, the preview screen should apply enhancement with loading animation
  final bool needsEnhancement;

  const ScannerMetadata({
    required this.totalPages,
    this.processingTime,
    this.appliedEnhancements = const [],
    this.edgesDetected = true,
    this.originalSize,
    this.processedSize,
    this.needsEnhancement = false,
  });

  @override
  String toString() {
    return 'ScannerMetadata(pages: $totalPages, edges: $edgesDetected, enhancements: ${appliedEnhancements.length})';
  }
}

/// Simple size class for image dimensions
class Size {
  final int width;
  final int height;

  const Size(this.width, this.height);

  @override
  String toString() => '${width}x$height';
}

/// Result of a document scanning operation
///
/// Contains:
/// - Success/failure status
/// - Processed images (if successful)
/// - Error information (if failed)
/// - Metadata about the scan
class ScannerResult {
  /// Whether the scan was successful
  final bool success;

  /// Whether the user cancelled the operation
  final bool cancelled;

  /// List of processed image files
  final List<File> processedImages;

  /// List of original (unprocessed) image files
  final List<File> originalImages;

  /// Error message if scan failed
  final String? error;

  /// Error type for recovery handling
  final ScannerErrorType? errorType;

  /// Metadata about the scanning session
  final ScannerMetadata? metadata;

  const ScannerResult._({
    required this.success,
    this.cancelled = false,
    this.processedImages = const [],
    this.originalImages = const [],
    this.error,
    this.errorType,
    this.metadata,
  });

  /// Create a successful result
  factory ScannerResult.success({
    required List<File> processedImages,
    List<File>? originalImages,
    ScannerMetadata? metadata,
  }) {
    return ScannerResult._(
      success: true,
      processedImages: processedImages,
      originalImages: originalImages ?? [],
      metadata: metadata,
    );
  }

  /// Create a cancelled result (user backed out)
  factory ScannerResult.cancelled() {
    return const ScannerResult._(
      success: false,
      cancelled: true,
      errorType: ScannerErrorType.cancelled,
    );
  }

  /// Create an error result
  factory ScannerResult.error(
    String message, {
    ScannerErrorType type = ScannerErrorType.unknown,
  }) {
    return ScannerResult._(
      success: false,
      error: message,
      errorType: type,
    );
  }

  /// Create a permission denied result
  factory ScannerResult.permissionDenied([String? message]) {
    return ScannerResult._(
      success: false,
      error: message ?? 'Camera or storage permission denied',
      errorType: ScannerErrorType.permissionDenied,
    );
  }

  /// Whether the error is recoverable (user can retry)
  bool get isRecoverable =>
      errorType != ScannerErrorType.permissionDenied &&
      errorType != ScannerErrorType.cameraUnavailable;

  /// Whether any images were captured
  bool get hasImages => processedImages.isNotEmpty;

  /// Number of images captured
  int get imageCount => processedImages.length;

  /// Get the first processed image (for single-document scans)
  File? get firstImage => processedImages.isNotEmpty ? processedImages.first : null;

  @override
  String toString() {
    if (success) {
      return 'ScannerResult.success(images: ${processedImages.length})';
    } else if (cancelled) {
      return 'ScannerResult.cancelled()';
    } else {
      return 'ScannerResult.error($error)';
    }
  }
}
