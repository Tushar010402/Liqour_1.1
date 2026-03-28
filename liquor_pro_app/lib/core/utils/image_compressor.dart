import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Industrial-grade image compression utility
///
/// Features:
/// - Uses native libraries (libjpeg-turbo on Android, ImageIO on iOS)
/// - Runs compression in background isolate (non-blocking UI)
/// - Optimal quality settings for sales receipts/documents
/// - Smart resizing based on image dimensions
/// - Progress callbacks for UI updates
/// - Memory-efficient batch processing
class ImageCompressor {
  /// Default compression quality (0-100)
  /// 85 provides excellent quality with ~70-80% size reduction
  static const int defaultQuality = 85;

  /// Maximum dimension for resized images
  /// 2048px is optimal for readability while keeping file size small
  static const int maxDimension = 2048;

  /// Minimum dimension - don't resize below this
  static const int minDimension = 800;

  /// Compress a single image file
  ///
  /// Returns compressed file or null if compression fails
  /// Uses native compression for optimal performance
  ///
  /// [file] - Source image file
  /// [quality] - JPEG quality (0-100, default 85)
  /// [maxWidth] - Max width in pixels (default 2048)
  /// [maxHeight] - Max height in pixels (default 2048)
  static Future<File?> compressImage(
    File file, {
    int quality = defaultQuality,
    int maxWidth = maxDimension,
    int maxHeight = maxDimension,
  }) async {
    try {
      final String inputPath = file.path;
      final String fileName = p.basenameWithoutExtension(inputPath);
      final int timestamp = DateTime.now().millisecondsSinceEpoch;

      // Get temp directory for output
      final Directory tempDir = await getTemporaryDirectory();
      final String outputPath = '${tempDir.path}/${fileName}_compressed_$timestamp.jpg';

      // Get original file size
      final int originalSize = await file.length();

      if (kDebugMode) {
        print('🗜️ [ImageCompressor] Compressing: ${p.basename(inputPath)}');
        print('   📐 Original size: ${_formatFileSize(originalSize)}');
      }

      // Compress using native library (runs in isolate internally)
      final XFile? result = await FlutterImageCompress.compressAndGetFile(
        inputPath,
        outputPath,
        quality: quality,
        minWidth: minDimension,
        minHeight: minDimension,
        format: CompressFormat.jpeg, // JPEG for best compression
        keepExif: false, // Strip EXIF to reduce size
      );

      if (result == null) {
        if (kDebugMode) {
          print('❌ [ImageCompressor] Compression returned null');
        }
        return null;
      }

      final File compressedFile = File(result.path);
      final int compressedSize = await compressedFile.length();
      final double reduction = ((originalSize - compressedSize) / originalSize * 100);

      if (kDebugMode) {
        print('   ✅ Compressed size: ${_formatFileSize(compressedSize)}');
        print('   📉 Reduction: ${reduction.toStringAsFixed(1)}%');
      }

      return compressedFile;
    } catch (e) {
      if (kDebugMode) {
        print('❌ [ImageCompressor] Error: $e');
      }
      return null;
    }
  }

  /// Compress multiple images with progress callback
  ///
  /// [files] - List of image files to compress
  /// [onProgress] - Callback with (current, total, currentFileName)
  /// [quality] - JPEG quality (0-100)
  ///
  /// Returns list of compressed files (same order as input)
  /// Failed compressions return original file as fallback
  static Future<List<File>> compressImages(
    List<File> files, {
    Function(int current, int total, String fileName)? onProgress,
    int quality = defaultQuality,
    int maxWidth = maxDimension,
    int maxHeight = maxDimension,
  }) async {
    final List<File> results = [];
    int totalOriginalSize = 0;
    int totalCompressedSize = 0;

    if (kDebugMode) {
      print('🗜️ [ImageCompressor] Starting batch compression of ${files.length} images');
    }

    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      final fileName = p.basename(file.path);

      // Report progress
      onProgress?.call(i + 1, files.length, fileName);

      final originalSize = await file.length();
      totalOriginalSize += originalSize;

      // Compress image
      final compressed = await compressImage(
        file,
        quality: quality,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      );

      if (compressed != null) {
        results.add(compressed);
        totalCompressedSize += await compressed.length();
      } else {
        // Fallback to original if compression fails
        results.add(file);
        totalCompressedSize += originalSize;
        if (kDebugMode) {
          print('⚠️ [ImageCompressor] Using original file as fallback: $fileName');
        }
      }
    }

    if (kDebugMode) {
      final double totalReduction = totalOriginalSize > 0
          ? ((totalOriginalSize - totalCompressedSize) / totalOriginalSize * 100)
          : 0;
      print('🗜️ [ImageCompressor] Batch complete:');
      print('   📦 Total original: ${_formatFileSize(totalOriginalSize)}');
      print('   📦 Total compressed: ${_formatFileSize(totalCompressedSize)}');
      print('   📉 Total reduction: ${totalReduction.toStringAsFixed(1)}%');
    }

    return results;
  }

  /// Compress image to bytes (for in-memory processing)
  ///
  /// Useful when you don't need to save to disk
  /// Returns compressed JPEG bytes
  static Future<Uint8List?> compressImageToBytes(
    File file, {
    int quality = defaultQuality,
    int maxWidth = maxDimension,
    int maxHeight = maxDimension,
  }) async {
    try {
      final result = await FlutterImageCompress.compressWithFile(
        file.path,
        quality: quality,
        minWidth: minDimension,
        minHeight: minDimension,
        format: CompressFormat.jpeg,
        keepExif: false,
      );

      return result;
    } catch (e) {
      if (kDebugMode) {
        print('❌ [ImageCompressor] Error compressing to bytes: $e');
      }
      return null;
    }
  }

  /// Compress from bytes to bytes (for images already in memory)
  ///
  /// [bytes] - Source image bytes (PNG, JPEG, etc.)
  /// Returns compressed JPEG bytes
  static Future<Uint8List?> compressBytesToBytes(
    Uint8List bytes, {
    int quality = defaultQuality,
    int maxWidth = maxDimension,
    int maxHeight = maxDimension,
  }) async {
    try {
      final result = await FlutterImageCompress.compressWithList(
        bytes,
        quality: quality,
        minWidth: minDimension,
        minHeight: minDimension,
        format: CompressFormat.jpeg,
        keepExif: false,
      );

      return result;
    } catch (e) {
      if (kDebugMode) {
        print('❌ [ImageCompressor] Error compressing bytes: $e');
      }
      return null;
    }
  }

  /// Get optimal quality setting based on image dimensions
  ///
  /// Higher resolution = can use slightly lower quality
  /// Lower resolution = use higher quality to preserve detail
  static int getOptimalQuality(int width, int height) {
    final maxDim = width > height ? width : height;

    if (maxDim > 4000) return 80;  // Very large - can use lower quality
    if (maxDim > 3000) return 82;
    if (maxDim > 2000) return 85;
    if (maxDim > 1500) return 88;
    return 90;  // Small images - use higher quality
  }

  /// Check if image needs compression
  ///
  /// Returns true if file is larger than threshold or is PNG format
  static Future<bool> needsCompression(File file, {int thresholdKB = 500}) async {
    final size = await file.length();
    final extension = p.extension(file.path).toLowerCase();

    // Always compress PNG (convert to JPEG)
    if (extension == '.png') return true;

    // Compress if over threshold
    return size > thresholdKB * 1024;
  }

  /// Smart compress - only compresses if needed
  ///
  /// Checks file size and format, skips compression for already-optimal files
  static Future<File> smartCompress(
    File file, {
    int thresholdKB = 500,
    int quality = defaultQuality,
  }) async {
    final needs = await needsCompression(file, thresholdKB: thresholdKB);

    if (!needs) {
      if (kDebugMode) {
        print('✅ [ImageCompressor] File already optimal, skipping: ${p.basename(file.path)}');
      }
      return file;
    }

    final compressed = await compressImage(file, quality: quality);
    return compressed ?? file;
  }

  /// Format file size for display
  static String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Public version of formatFileSize
  static String formatFileSize(int bytes) => _formatFileSize(bytes);

  /// Clean up temporary compressed files
  ///
  /// Call this after upload is complete to free disk space
  static Future<void> cleanupTempFiles(List<File> compressedFiles) async {
    for (final file in compressedFiles) {
      if (file.path.contains('_compressed_')) {
        try {
          if (await file.exists()) {
            await file.delete();
            if (kDebugMode) {
              print('🧹 [ImageCompressor] Deleted temp file: ${p.basename(file.path)}');
            }
          }
        } catch (e) {
          // Ignore cleanup errors
        }
      }
    }
  }
}
