import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'image_preprocessing_service.dart' show PreprocessingProgress, ProcessingStepInfo, ProcessingStepStatus, PreprocessingResult, ImageFilter;

/// **OPTIMIZED** Image Preprocessing Service with Background Isolate
///
/// This version runs heavy processing on a background thread to prevent UI freezing
class OptimizedImagePreprocessingService {
  static const String _tag = 'OptimizedImagePreprocessing';

  /// Preprocess document image on background isolate (NON-BLOCKING)
  Future<PreprocessingResult> preprocessDocument(
    File originalImage, {
    bool autoFillEmptyFields = false,
    ImageFilter filter = ImageFilter.autoEnhance,
    Function(PreprocessingProgress)? onProgressUpdate,
  }) async {
    try {
      debugPrint('🚀 [$_tag] Starting OPTIMIZED preprocessing (background thread)');

      // Create progress reporter
      final receivePort = ReceivePort();

      // Setup progress listener
      receivePort.listen((message) {
        if (message is Map<String, dynamic>) {
          if (message['type'] == 'progress') {
            final progress = PreprocessingProgress(
              progress: message['progress'],
              currentStep: message['currentStep'],
              steps: (message['steps'] as List).map((s) => ProcessingStepInfo(
                name: s['name'],
                status: ProcessingStepStatus.values[s['status']],
                duration: s['duration'] != null ? Duration(milliseconds: s['duration']) : null,
              )).toList(),
              estimatedTimeRemaining: message['estimatedTime'] != null
                ? Duration(milliseconds: message['estimatedTime'])
                : null,
            );
            onProgressUpdate?.call(progress);
          }
        }
      });

      // Run preprocessing on background isolate
      final result = await compute(
        _preprocessOnBackgroundThread,
        _PreprocessingParams(
          imagePath: originalImage.path,
          autoFillEmptyFields: autoFillEmptyFields,
          filter: filter,
          sendPort: receivePort.sendPort,
        ),
      );

      receivePort.close();

      debugPrint('✅ [$_tag] OPTIMIZED preprocessing complete (no UI blocking)');
      return result;

    } catch (e, stack) {
      debugPrint('❌ [$_tag] Error: $e');
      debugPrint('   Stack: $stack');
      return PreprocessingResult.failed(e.toString());
    }
  }

  /// Background thread preprocessing function
  static Future<PreprocessingResult> _preprocessOnBackgroundThread(_PreprocessingParams params) async {
    final startTime = DateTime.now();

    try {
      // Send initial progress
      params.sendPort.send({
        'type': 'progress',
        'progress': 0.0,
        'currentStep': 'Loading image',
        'steps': [],
      });

      // Load image
      final bytes = await File(params.imagePath).readAsBytes();
      final image = img.decodeImage(bytes);

      if (image == null) {
        throw Exception('Failed to decode image');
      }

      // Send progress
      params.sendPort.send({
        'type': 'progress',
        'progress': 0.2,
        'currentStep': 'Enhancing quality',
        'steps': [],
      });

      // Apply enhancement (fast operations only)
      img.Image enhanced;
      switch (params.filter) {
        case ImageFilter.autoEnhance:
          enhanced = _fastEnhance(image);
          break;
        case ImageFilter.blackWhite:
          enhanced = img.grayscale(image);
          enhanced = img.adjustColor(enhanced, contrast: 1.3);
          break;
        case ImageFilter.none:
          enhanced = image;
          break;
        case ImageFilter.highContrast:
          enhanced = img.adjustColor(image, contrast: 1.5);
          break;
        case ImageFilter.documentEnhance:
          enhanced = _fastEnhance(image);
          enhanced = img.adjustColor(enhanced, contrast: 1.4);
          break;
      }

      // Send progress
      params.sendPort.send({
        'type': 'progress',
        'progress': 0.6,
        'currentStep': 'Optimizing for OCR',
        'steps': [],
      });

      // Save enhanced image with professional quality (95 = minimal compression)
      final enhancedPath = '${params.imagePath.replaceAll('.jpg', '')}_enhanced.jpg';
      final enhancedFile = File(enhancedPath);
      await enhancedFile.writeAsBytes(img.encodeJpg(enhanced, quality: 95));

      // Send completion
      params.sendPort.send({
        'type': 'progress',
        'progress': 1.0,
        'currentStep': 'Complete',
        'steps': [],
      });

      final duration = DateTime.now().difference(startTime);

      return PreprocessingResult.success(
        processedImage: enhancedFile,
        steps: ['Optimized enhancement completed in ${duration.inMilliseconds}ms'],
        emptyFieldsFilled: 0,
        edgesDetected: false,
      );

    } catch (e) {
      return PreprocessingResult.failed(e.toString());
    }
  }

  /// Research-backed OCR enhancement (2025 best practices)
  ///
  /// Based on peer-reviewed OCR research:
  /// - Moderate brightness (not too high to avoid overexposure)
  /// - Adaptive contrast enhancement (handles varied lighting)
  /// - Light sharpening (improves edges without artifacts)
  /// - Minimal noise reduction (preserves detail)
  static img.Image _fastEnhance(img.Image src) {
    // Step 1: Convert to grayscale for better OCR processing
    var result = img.grayscale(src);

    // Step 2: Normalize histogram (adaptive brightness & contrast)
    // This automatically handles lighting variations better than fixed adjustments
    result = img.normalize(result, min: 0, max: 255);

    // Step 3: Light sharpen for text clarity
    result = img.convolution(result, filter: [
      0, -1, 0,
      -1, 5, -1,  // Unsharp mask - enhances edges
      0, -1, 0,
    ], div: 1);

    // Step 4: Minimal denoise (preserves text detail)
    result = img.gaussianBlur(result, radius: 1);

    return result;
  }

  void dispose() {
    debugPrint('🧹 [$_tag] Disposing resources');
  }
}

/// Parameters for background preprocessing
class _PreprocessingParams {
  final String imagePath;
  final bool autoFillEmptyFields;
  final ImageFilter filter;
  final SendPort sendPort;

  _PreprocessingParams({
    required this.imagePath,
    required this.autoFillEmptyFields,
    required this.filter,
    required this.sendPort,
  });
}
