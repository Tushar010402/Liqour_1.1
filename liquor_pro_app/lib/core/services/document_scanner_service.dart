import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image/image.dart' as img;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/scanner_config.dart';
import '../models/scanner_result.dart';
import 'image_preprocessing_service.dart' show ImageFilter;
import 'debug_log_service.dart';

/// Industrial-Grade Document Scanner Service
///
/// Uses native platform APIs for professional document scanning:
/// - iOS: VisionKit VNDocumentCameraViewController (physical devices only)
/// - Android: Google ML Kit Document Scanner API (physical devices only)
///
/// Features:
/// - Automatic edge detection (physical devices)
/// - Perspective correction
/// - Auto-crop
/// - Image enhancement
/// - Multi-page scanning
/// - Fallback to ImagePicker + ImageCropper on simulators/emulators
///
/// Usage:
/// ```dart
/// final scanner = DocumentScannerService();
/// final result = await scanner.scanDocument(
///   config: DocumentScannerService.receiptConfig,
///   context: context,
/// );
/// if (result.success) {
///   // Use result.processedImages
/// }
/// ```
class DocumentScannerService {
  final ImagePicker _imagePicker = ImagePicker();

  /// Cache simulator detection result
  bool? _isSimulator;

  // ========== PREDEFINED CONFIGURATIONS ==========

  /// Receipt scanning - Daily sales entry
  /// Uses DOCUMENT ENHANCE filter for CamScanner-quality results
  /// - Whitens paper background
  /// - Darkens ink/text for readability
  /// - NO color distortion
  /// - Supports up to 10 pages per session
  static const ScannerConfig receiptConfig = ScannerConfig(
    mode: ScanMode.receipt,
    maxPages: 10,  // UPDATED: Support 10 images per session (was 5)
    maxWidth: 1920,
    jpegQuality: 95,
    filter: ImageFilter.documentEnhance,  // INDUSTRIAL-GRADE - CamScanner quality
    autoFillEmptyFields: false,
    showPreview: false,
    allowGalleryImport: true,
  );

  /// Bank slip - Single document for cash submission
  /// Uses DOCUMENT ENHANCE for clear, professional bank slip scanning
  static const ScannerConfig bankSlipConfig = ScannerConfig(
    mode: ScanMode.bankSlip,
    maxPages: 1,
    maxWidth: 1920,
    jpegQuality: 95,
    filter: ImageFilter.documentEnhance,  // INDUSTRIAL-GRADE - CamScanner quality
    autoFillEmptyFields: false,
    showPreview: false,
    allowGalleryImport: true,
  );

  /// Invoice scanning - Multi-page OCR optimized
  /// Uses DOCUMENT ENHANCE for printed invoices with handwritten notes
  static const ScannerConfig invoiceConfig = ScannerConfig(
    mode: ScanMode.invoice,
    maxPages: 10,
    maxWidth: 2048,
    jpegQuality: 95,
    filter: ImageFilter.documentEnhance,  // INDUSTRIAL-GRADE - CamScanner quality
    autoFillEmptyFields: true,
    showPreview: false,
    allowGalleryImport: true,
  );

  /// Product image - Single image capture
  /// Uses auto-enhance for product photos (NOT document enhancement)
  static const ScannerConfig productConfig = ScannerConfig(
    mode: ScanMode.product,
    maxPages: 1,
    maxWidth: 1024,
    jpegQuality: 90,
    filter: ImageFilter.autoEnhance,  // Product photos don't need document enhancement
    autoFillEmptyFields: false,
    showPreview: false,
    allowGalleryImport: true,
  );

  // ========== PERMISSION HANDLING ==========

  /// Check and request camera permission
  /// Returns true if permission granted, false otherwise
  Future<bool> _checkCameraPermission() async {
    try {
      DebugLogService.info('Scanner', 'Checking camera permission...');

      // Check current status
      var status = await Permission.camera.status;
      DebugLogService.debug('Scanner', 'Camera permission status: $status');

      if (status.isGranted) {
        DebugLogService.success('Scanner', 'Camera permission already granted');
        return true;
      }

      if (status.isPermanentlyDenied) {
        DebugLogService.warning('Scanner', 'Camera permission permanently denied - need to open settings');
        return false;
      }

      // Request permission
      DebugLogService.info('Scanner', 'Requesting camera permission...');
      status = await Permission.camera.request();
      DebugLogService.debug('Scanner', 'Permission request result: $status');

      if (status.isGranted) {
        DebugLogService.success('Scanner', 'Camera permission granted after request');
        return true;
      }

      DebugLogService.warning('Scanner', 'Camera permission denied by user');
      return false;
    } catch (e) {
      DebugLogService.error('Scanner', 'Error checking camera permission', error: e);
      return false;
    }
  }

  /// Show dialog to open app settings when permission is permanently denied
  Future<void> _showPermissionDeniedDialog(BuildContext context) async {
    await showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Camera Permission Required'),
        content: const Text(
          'LiquorPro needs camera access to scan documents. '
          'Please enable camera permission in Settings.',
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('Open Settings'),
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
          ),
        ],
      ),
    );
  }

  // ========== SIMULATOR/EMULATOR DETECTION ==========

  /// Check if running on iOS Simulator or Android Emulator
  Future<bool> _checkIsSimulator() async {
    if (_isSimulator != null) return _isSimulator!;

    try {
      final deviceInfo = DeviceInfoPlugin();

      if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        _isSimulator = !iosInfo.isPhysicalDevice;
        DebugLogService.info('Scanner', 'iOS Physical Device: ${iosInfo.isPhysicalDevice}');
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        _isSimulator = !androidInfo.isPhysicalDevice;
        DebugLogService.info('Scanner', 'Android Physical Device: ${androidInfo.isPhysicalDevice}, Model: ${androidInfo.model}');
      } else {
        _isSimulator = false;
      }
    } catch (e) {
      DebugLogService.warning('Scanner', 'Could not detect device type: $e');
      _isSimulator = false;
    }

    return _isSimulator!;
  }

  // ========== CORE SCANNING METHODS ==========

  /// Scan documents - Shows action sheet with Camera/Gallery options
  /// On physical devices: Uses native VisionKit/ML Kit for auto edge detection
  /// On simulators: Uses ImagePicker fallback with manual crop
  Future<ScannerResult> scanDocument({
    required ScannerConfig config,
    required BuildContext context,
    Function(String step)? onProgress,
  }) async {
    // Check if running on simulator
    final isSimulator = await _checkIsSimulator();

    if (isSimulator) {
      DebugLogService.info('Scanner', 'Running on SIMULATOR - showing options sheet');
      // On simulator, show action sheet to choose camera or gallery
      return _showScanOptionsSheet(config: config, context: context, onProgress: onProgress);
    }

    // On physical device, try native scanner first
    DebugLogService.info('Scanner', 'Starting native scan on physical device');
    return _nativeScan(config: config, context: context, onProgress: onProgress);
  }

  /// Show iOS-style action sheet for scan options
  Future<ScannerResult> _showScanOptionsSheet({
    required ScannerConfig config,
    required BuildContext context,
    Function(String step)? onProgress,
  }) async {
    final result = await showCupertinoModalPopup<String>(
      context: context,
      builder: (BuildContext context) => CupertinoActionSheet(
        title: const Text('Scan Document'),
        message: const Text('Choose how you want to capture the document'),
        actions: <CupertinoActionSheetAction>[
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'camera'),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.camera_fill, color: CupertinoColors.activeBlue),
                SizedBox(width: 12),
                Text('Take Photo'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'gallery'),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.photo_fill, color: CupertinoColors.activeBlue),
                SizedBox(width: 12),
                Text('Choose from Gallery'),
              ],
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(context, 'cancel'),
          child: const Text('Cancel'),
        ),
      ),
    );

    switch (result) {
      case 'camera':
        return _fallbackScan(config: config, context: context, onProgress: onProgress);
      case 'gallery':
        return importFromGallery(config: config, context: context, onProgress: onProgress);
      default:
        return ScannerResult.cancelled();
    }
  }

  /// Native scan using VisionKit (iOS) or ML Kit (Android)
  /// Only works on physical devices with cameras
  Future<ScannerResult> _nativeScan({
    required ScannerConfig config,
    required BuildContext context,
    Function(String step)? onProgress,
  }) async {
    // Use platform-specific implementation
    if (Platform.isAndroid) {
      return _androidCameraScan(config: config, context: context, onProgress: onProgress);
    } else {
      return _iosCameraScan(config: config, context: context, onProgress: onProgress);
    }
  }

  /// Android camera scan using Google ML Kit Document Scanner
  /// ML Kit already provides:
  /// - Smart edge detection
  /// - Perspective correction
  /// - Document filters
  /// - Auto-crop
  /// So we skip heavy post-processing for speed
  Future<ScannerResult> _androidCameraScan({
    required ScannerConfig config,
    required BuildContext context,
    Function(String step)? onProgress,
  }) async {
    try {
      DebugLogService.info('Scanner', 'Starting Android ML Kit scanner (smart document detection)');

      onProgress?.call('Opening scanner...');

      final stopwatch = Stopwatch()..start();

      // ML Kit provides native document scanning with:
      // - Real-time edge detection
      // - Perspective correction
      // - Built-in filters (grayscale, color, etc.)
      // - Smart cropping
      final documentScannerOptions = DocumentScannerOptions(
        documentFormat: DocumentFormat.jpeg,
        mode: ScannerMode.full, // Full mode with edge detection & filters
        pageLimit: config.maxPages,
        isGalleryImport: false,
      );

      final documentScanner = DocumentScanner(options: documentScannerOptions);

      DocumentScanningResult result;
      try {
        result = await documentScanner.scanDocument();
      } catch (e) {
        final errorStr = e.toString().toLowerCase();
        if (errorStr.contains('cancel') || errorStr.contains('operation')) {
          DebugLogService.info('Scanner', 'User cancelled');
          await documentScanner.close();
          return ScannerResult.cancelled();
        }
        rethrow;
      }

      await documentScanner.close();

      if (result.images.isEmpty) {
        return ScannerResult.cancelled();
      }

      DebugLogService.success('Scanner', 'ML Kit returned ${result.images.length} document(s)');

      // ML Kit already provides professional document processing:
      // - Edge detection, perspective correction, auto-crop
      // - Built-in enhancement filters
      // NO additional enhancement needed - it makes images darker!
      onProgress?.call('Processing ${result.images.length} document(s)...');
      final processedImages = <File>[];
      final originalImages = <File>[];

      for (int i = 0; i < result.images.length; i++) {
        final imagePath = result.images[i];
        final imageFile = File(imagePath);

        if (!await imageFile.exists()) {
          DebugLogService.error('Scanner', 'File not found: $imagePath');
          continue;
        }

        originalImages.add(imageFile);

        // Use ML Kit output directly - it's already professionally processed
        processedImages.add(imageFile);
        final fileSize = await imageFile.length();
        DebugLogService.debug('Scanner', 'Page ${i + 1}: ${(fileSize / 1024).toStringAsFixed(0)}KB');
      }

      stopwatch.stop();

      if (processedImages.isEmpty) {
        return _fallbackScan(config: config, context: context, onProgress: onProgress);
      }

      DebugLogService.success('Scanner', 'Scan complete: ${processedImages.length} pages in ${stopwatch.elapsedMilliseconds}ms');

      return ScannerResult.success(
        processedImages: processedImages,
        originalImages: originalImages,
        metadata: ScannerMetadata(
          totalPages: processedImages.length,
          processingTime: stopwatch.elapsed,
          appliedEnhancements: [
            'ML Kit smart edge detection',
            'Auto perspective correction',
            'Document straightening',
          ],
          edgesDetected: true,
          needsEnhancement: false,
        ),
      );
    } catch (e, stackTrace) {
      DebugLogService.error('Scanner', 'Android scan failed', error: e, stackTrace: stackTrace);
      return _fallbackScan(config: config, context: context, onProgress: onProgress);
    }
  }

  /// iOS camera scan using CunningDocumentScanner (proper VisionKit integration)
  /// This package properly returns CROPPED documents with edge detection
  /// Unlike flutter_doc_scanner which returns raw camera captures
  Future<ScannerResult> _iosCameraScan({
    required ScannerConfig config,
    required BuildContext context,
    Function(String step)? onProgress,
  }) async {
    try {
      DebugLogService.info('Scanner', 'Opening iOS document scanner (cunning_document_scanner)');
      onProgress?.call('Opening scanner...');

      final stopwatch = Stopwatch()..start();

      // CunningDocumentScanner properly uses VisionKit and returns:
      // - Edge-detected documents (not raw camera captures)
      // - Perspective-corrected images
      // - Auto-cropped to document boundaries
      // - Smaller file sizes (processed JPEGs, not raw PNGs)
      final List<String>? scannedImages = await CunningDocumentScanner.getPictures(
        noOfPages: config.maxPages,
        isGalleryImportAllowed: config.allowGalleryImport,
      );

      if (scannedImages == null || scannedImages.isEmpty) {
        DebugLogService.info('Scanner', 'User cancelled or no documents scanned');
        return ScannerResult.cancelled();
      }

      DebugLogService.success('Scanner', 'Scanned ${scannedImages.length} document(s) with edge detection');

      // Process scanned documents
      onProgress?.call('Processing ${scannedImages.length} document(s)...');
      final processedImages = <File>[];
      final originalImages = <File>[];

      for (int i = 0; i < scannedImages.length; i++) {
        final imagePath = scannedImages[i];
        final imageFile = File(imagePath);

        if (!await imageFile.exists()) {
          DebugLogService.error('Scanner', 'File not found: $imagePath');
          continue;
        }

        originalImages.add(imageFile);

        // Use document scanner output directly - already cropped and corrected
        processedImages.add(imageFile);
        final fileSize = await imageFile.length();
        DebugLogService.debug('Scanner', 'Page ${i + 1}: ${(fileSize / 1024).toStringAsFixed(0)}KB (edge-detected)');
      }

      stopwatch.stop();

      if (processedImages.isEmpty) {
        DebugLogService.warning('Scanner', 'No valid documents, falling back to ImagePicker');
        return _fallbackScan(config: config, context: context, onProgress: onProgress);
      }

      DebugLogService.success('Scanner', 'Done: ${processedImages.length} pages in ${stopwatch.elapsedMilliseconds}ms');

      return ScannerResult.success(
        processedImages: processedImages,
        originalImages: originalImages,
        metadata: ScannerMetadata(
          totalPages: processedImages.length,
          processingTime: stopwatch.elapsed,
          appliedEnhancements: [
            'VisionKit edge detection',
            'Perspective correction',
            'Auto-crop',
          ],
          edgesDetected: true,
        ),
      );
    } catch (e, stackTrace) {
      DebugLogService.error('Scanner', 'iOS scan failed', error: e, stackTrace: stackTrace);
      return _fallbackScan(config: config, context: context, onProgress: onProgress);
    }
  }

  /// CamScanner-style document enhancement (runs in isolate for speed)
  /// - Strong contrast for crisp black text
  /// - White background enhancement
  /// - Optimized JPEG output
  Future<File> _applyDocumentEnhancement(File inputFile, {int quality = 92}) async {
    try {
      final bytes = await inputFile.readAsBytes();
      final outputDir = inputFile.parent.path;
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      // Run heavy processing in isolate for speed
      final enhancedBytes = await compute(
        _enhanceDocumentIsolate,
        _EnhanceParams(bytes: bytes, quality: quality),
      );

      if (enhancedBytes == null) return inputFile;

      // Save enhanced image
      final jpegPath = '$outputDir/enhanced_$timestamp.jpg';
      final jpegFile = File(jpegPath);
      await jpegFile.writeAsBytes(enhancedBytes);

      return jpegFile;
    } catch (e) {
      DebugLogService.warning('Scanner', 'Enhancement failed: $e');
      return inputFile;
    }
  }

  /// Isolate function for document enhancement (CamScanner-quality)
  static List<int>? _enhanceDocumentIsolate(_EnhanceParams params) {
    try {
      var image = img.decodeImage(params.bytes);
      if (image == null) return null;

      // Resize if too large (max 1600px for faster processing)
      if (image.width > 1600 || image.height > 1600) {
        final scale = 1600 / (image.width > image.height ? image.width : image.height);
        image = img.copyResize(
          image,
          width: (image.width * scale).round(),
          height: (image.height * scale).round(),
          interpolation: img.Interpolation.linear,
        );
      }

      // ═══════════════════════════════════════════════════════════════
      // CAMSCANNER-STYLE ENHANCEMENT (FIXED PARAMETERS)
      // ═══════════════════════════════════════════════════════════════

      // 1. Moderate contrast (25% boost - not 50%!)
      image = img.adjustColor(image, contrast: 1.25);

      // 2. Strong brightness for white paper (15% - was only 8%!)
      image = img.adjustColor(image, brightness: 1.15);

      // 3. Gamma > 1.0 LIGHTENS mid-tones (0.9 was DARKENING!)
      // CRITICAL FIX: gamma < 1.0 darkens, gamma > 1.0 lightens
      image = img.adjustColor(image, gamma: 1.08);

      // 4. Slight saturation reduction for document look
      image = img.adjustColor(image, saturation: 0.92);

      // NO SHARPENING - causes text fragmentation and artifacts
      // VisionKit/ML Kit already provide sharp output, OCR handles edges

      // Encode as high-quality JPEG
      return img.encodeJpg(image, quality: params.quality);
    } catch (e) {
      return null;
    }
  }

  /// Import from gallery with professional document scanning
  /// - Android: Uses Google ML Kit Document Scanner with native edge detection
  /// - iOS: Uses ImagePicker + ImageCropper (VisionKit doesn't support gallery)
  Future<ScannerResult> importFromGallery({
    required ScannerConfig config,
    required BuildContext context,
    Function(String step)? onProgress,
  }) async {
    try {
      DebugLogService.info('Scanner', 'Starting GALLERY import - Mode: ${config.mode}');

      // On Android, use ML Kit Document Scanner with gallery import
      // This gives the SAME edge detection experience as camera
      if (Platform.isAndroid) {
        return _androidGalleryImport(config: config, context: context, onProgress: onProgress);
      }

      // On iOS, fall back to manual crop (VisionKit doesn't support gallery images)
      return _iosGalleryImport(config: config, context: context, onProgress: onProgress);
    } catch (e) {
      DebugLogService.error('Scanner', 'Gallery import FAILED', error: e);
      return _handleError(e);
    }
  }

  /// Android gallery import using Google ML Kit Document Scanner
  /// This provides the SAME edge detection as camera scanning!
  Future<ScannerResult> _androidGalleryImport({
    required ScannerConfig config,
    required BuildContext context,
    Function(String step)? onProgress,
  }) async {
    try {
      DebugLogService.info('Scanner', 'Using ML Kit Document Scanner with GALLERY import (Android)');
      onProgress?.call('Opening gallery scanner...');

      final stopwatch = Stopwatch()..start();

      // Create ML Kit document scanner with gallery import ENABLED
      final documentScannerOptions = DocumentScannerOptions(
        documentFormat: DocumentFormat.jpeg,
        mode: ScannerMode.full, // Full mode with edge detection & filters
        pageLimit: config.maxPages,
        isGalleryImport: true, // THIS enables gallery with edge detection!
      );

      final documentScanner = DocumentScanner(options: documentScannerOptions);

      DebugLogService.debug('Scanner', 'Starting ML Kit scanner with gallery=true...');

      DocumentScanningResult result;
      try {
        result = await documentScanner.scanDocument();
      } catch (e) {
        // ML Kit throws error when user cancels - this is NOT a real error
        final errorStr = e.toString().toLowerCase();
        if (errorStr.contains('cancel') || errorStr.contains('operation')) {
          DebugLogService.info('Scanner', 'User cancelled ML Kit gallery scanner');
          await documentScanner.close();
          return ScannerResult.cancelled();
        }
        rethrow;
      }

      // Close the scanner
      await documentScanner.close();

      DebugLogService.debug('Scanner', 'ML Kit result: ${result.images.length} images, paths: ${result.images}');

      if (result.images.isEmpty) {
        DebugLogService.info('Scanner', 'ML Kit returned empty images - user may have cancelled');
        return ScannerResult.cancelled();
      }

      DebugLogService.success('Scanner', 'ML Kit returned ${result.images.length} document(s)');

      // FAST PATH: ML Kit already did edge detection & enhancement
      onProgress?.call('Saving ${result.images.length} document(s)...');
      final processedImages = <File>[];
      final originalImages = <File>[];

      for (int i = 0; i < result.images.length; i++) {
        final imagePath = result.images[i];
        final imageFile = File(imagePath);

        if (!await imageFile.exists()) {
          // Try alternative path
          final altPath = imagePath.startsWith('/') ? imagePath : '/$imagePath';
          final altFile = File(altPath);
          if (await altFile.exists()) {
            originalImages.add(altFile);
            processedImages.add(altFile);
          }
          continue;
        }

        final fileSize = await imageFile.length();
        DebugLogService.debug('Scanner', 'Page ${i + 1}: ${(fileSize / 1024).toStringAsFixed(0)}KB');

        originalImages.add(imageFile);
        processedImages.add(imageFile); // ML Kit output is already optimized
      }

      stopwatch.stop();

      if (processedImages.isEmpty) {
        return _iosGalleryImport(config: config, context: context, onProgress: onProgress);
      }

      DebugLogService.success('Scanner', 'Import complete: ${processedImages.length} pages in ${stopwatch.elapsedMilliseconds}ms');

      return ScannerResult.success(
        processedImages: processedImages,
        originalImages: originalImages,
        metadata: ScannerMetadata(
          totalPages: processedImages.length,
          processingTime: stopwatch.elapsed,
          appliedEnhancements: [
            'ML Kit smart edge detection',
            'Auto perspective correction',
          ],
          edgesDetected: true,
          needsEnhancement: false,
        ),
      );
    } catch (e, stackTrace) {
      DebugLogService.error('Scanner', 'Android gallery import FAILED', error: e, stackTrace: stackTrace);
      // Fall back to simple gallery import with manual crop
      DebugLogService.warning('Scanner', 'Falling back to ImagePicker + Cropper...');
      return _iosGalleryImport(config: config, context: context, onProgress: onProgress);
    }
  }

  /// iOS gallery import using ImagePicker + ImageCropper
  /// Simple and fast - just crop the selected image
  Future<ScannerResult> _iosGalleryImport({
    required ScannerConfig config,
    required BuildContext context,
    Function(String step)? onProgress,
  }) async {
    try {
      DebugLogService.info('Scanner', 'Gallery import (ImagePicker + Cropper)');
      onProgress?.call('Opening gallery...');

      final stopwatch = Stopwatch()..start();

      // Pick image from gallery
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: config.jpegQuality,
      );

      if (image == null) {
        return ScannerResult.cancelled();
      }

      DebugLogService.debug('Scanner', 'Selected: ${image.path.split('/').last}');

      // Crop the image
      onProgress?.call('Crop document...');
      final croppedFile = await _cropImage(image.path, config);

      if (croppedFile == null) {
        return ScannerResult.cancelled();
      }

      final fileSize = await croppedFile.length();
      DebugLogService.debug('Scanner', 'Cropped: ${(fileSize / 1024).toStringAsFixed(0)}KB');

      stopwatch.stop();
      DebugLogService.success('Scanner', 'Import complete in ${stopwatch.elapsedMilliseconds}ms');

      return ScannerResult.success(
        processedImages: [croppedFile],
        originalImages: [File(image.path)],
        metadata: ScannerMetadata(
          totalPages: 1,
          processingTime: stopwatch.elapsed,
          appliedEnhancements: ['Manual crop'],
          edgesDetected: false,
          needsEnhancement: false,
        ),
      );
    } catch (e) {
      DebugLogService.error('Scanner', 'Gallery import failed', error: e);
      return _handleError(e);
    }
  }

  /// Fallback scan using ImagePicker + ImageCropper
  /// Used when native scanner is unavailable
  /// Note: ImagePicker handles its own permission prompts
  Future<ScannerResult> _fallbackScan({
    required ScannerConfig config,
    required BuildContext context,
    Function(String step)? onProgress,
  }) async {
    try {
      DebugLogService.info('Scanner', 'Starting FALLBACK camera scan');

      // Check camera permission status first
      final cameraStatus = await Permission.camera.status;
      DebugLogService.info('Scanner', 'Camera permission status: $cameraStatus');

      if (cameraStatus.isDenied || cameraStatus.isPermanentlyDenied) {
        DebugLogService.warning('Scanner', 'Camera permission denied, requesting...');
        final result = await Permission.camera.request();
        DebugLogService.info('Scanner', 'Permission request result: $result');

        if (!result.isGranted) {
          DebugLogService.error('Scanner', 'Camera permission not granted after request');
          if (result.isPermanentlyDenied && context.mounted) {
            await _showPermissionDeniedDialog(context);
          }
          return ScannerResult.error('Camera permission required. Please enable in Settings.');
        }
      }

      onProgress?.call('Opening camera...');

      final stopwatch = Stopwatch()..start();

      // Capture image with camera
      DebugLogService.debug('Scanner', 'Opening camera picker (ImagePicker)...');

      XFile? image;
      try {
        image = await _imagePicker.pickImage(
          source: ImageSource.camera,
          imageQuality: config.jpegQuality,
          maxWidth: config.maxWidth.toDouble(),
          preferredCameraDevice: CameraDevice.rear,
        );
        DebugLogService.debug('Scanner', 'ImagePicker returned: ${image?.path ?? "null"}');
      } catch (e) {
        DebugLogService.error('Scanner', 'ImagePicker.pickImage failed', error: e);
        return ScannerResult.error('Failed to open camera: $e');
      }

      if (image == null) {
        DebugLogService.info('Scanner', 'User cancelled camera (ImagePicker returned null)');
        return ScannerResult.cancelled();
      }

      DebugLogService.success('Scanner', 'Photo captured: ${image.path.split('/').last}');

      // Crop the image
      onProgress?.call('Crop document...');
      DebugLogService.debug('Scanner', 'Opening crop UI...');
      final croppedFile = await _cropImage(image.path, config);

      if (croppedFile == null) {
        DebugLogService.info('Scanner', 'User cancelled cropping');
        return ScannerResult.cancelled();
      }

      DebugLogService.success('Scanner', 'Image cropped: ${croppedFile.path.split('/').last}');

      // MODERN UX: Return IMMEDIATELY without enhancement
      // The preview screen will handle enhancement with a beautiful loading animation
      final originalImages = <File>[File(image.path)];

      stopwatch.stop();

      DebugLogService.success('Scanner', 'Fallback scan COMPLETED in ${stopwatch.elapsedMilliseconds}ms');

      return ScannerResult.success(
        processedImages: [croppedFile], // Return cropped but UN-enhanced image
        originalImages: originalImages,
        metadata: ScannerMetadata(
          totalPages: 1,
          processingTime: stopwatch.elapsed,
          appliedEnhancements: ['Manual crop'],
          edgesDetected: false,
          needsEnhancement: true, // Flag that preview screen should enhance
        ),
      );
    } catch (e) {
      DebugLogService.error('Scanner', 'Fallback scan FAILED', error: e);
      return _handleError(e);
    }
  }

  /// Crop image using ImageCropper with document-optimized settings
  Future<File?> _cropImage(String sourcePath, ScannerConfig config) async {
    try {
      DebugLogService.debug('Scanner', 'ImageCropper starting...');
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: sourcePath,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Document',
            toolbarColor: Colors.black,
            toolbarWidgetColor: Colors.white,
            backgroundColor: Colors.black,
            activeControlsWidgetColor: Colors.green,
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false,
            hideBottomControls: false,
          ),
          IOSUiSettings(
            title: 'Crop Document',
            doneButtonTitle: 'Done',
            cancelButtonTitle: 'Cancel',
            aspectRatioLockEnabled: false,
            resetAspectRatioEnabled: true,
            rotateButtonsHidden: false,
            rotateClockwiseButtonHidden: true,
          ),
        ],
        compressQuality: config.jpegQuality,
        maxWidth: config.maxWidth,
      );

      if (croppedFile != null) {
        DebugLogService.debug('Scanner', 'ImageCropper returned: ${croppedFile.path}');
        return File(croppedFile.path);
      }
      DebugLogService.debug('Scanner', 'ImageCropper returned null');
      return null;
    } catch (e) {
      DebugLogService.error('Scanner', 'Crop error', error: e);
      return null;
    }
  }

  /// Handle errors with user-friendly messages
  ScannerResult _handleError(dynamic e) {
    final errorMessage = e.toString().toLowerCase();
    ScannerErrorType errorType = ScannerErrorType.unknown;
    String userMessage;

    if (errorMessage.contains('permission')) {
      errorType = ScannerErrorType.permissionDenied;
      userMessage = 'Camera permission required. Please enable in Settings.';
    } else if (errorMessage.contains('camera')) {
      errorType = ScannerErrorType.cameraUnavailable;
      userMessage = 'Camera unavailable. Please try again.';
    } else if (errorMessage.contains('memory')) {
      errorType = ScannerErrorType.outOfMemory;
      userMessage = 'Not enough memory. Close other apps and try again.';
    } else {
      userMessage = 'Scanner error. Please try again.';
    }

    return ScannerResult.error(userMessage, type: errorType);
  }

  // ========== CONVENIENCE METHODS ==========

  Future<ScannerResult> scanSingleDocument({
    required ScannerConfig config,
    required BuildContext context,
    Function(String step)? onProgress,
  }) async {
    return scanDocument(
      config: config.copyWith(maxPages: 1),
      context: context,
      onProgress: onProgress,
    );
  }

  Future<ScannerResult> scanReceipt(BuildContext context) async {
    return scanDocument(config: receiptConfig, context: context);
  }

  Future<ScannerResult> scanBankSlip(BuildContext context) async {
    return scanSingleDocument(config: bankSlipConfig, context: context);
  }

  Future<ScannerResult> scanInvoice(BuildContext context) async {
    return scanDocument(config: invoiceConfig, context: context);
  }

  Future<ScannerResult> scanFromCamera({
    required ScannerConfig config,
    required BuildContext context,
    Function(String step)? onProgress,
  }) async {
    return scanDocument(config: config, context: context, onProgress: onProgress);
  }

  void dispose() {
    debugPrint('🧹 [DocumentScanner] Disposed');
  }

  // ========== CAMSCANNER-STYLE PROFESSIONAL SCANNING ==========

  /// Open CamScanner-style professional document scanner
  ///
  /// Uses platform-specific native APIs:
  /// - iOS: VisionKit VNDocumentCameraViewController (via flutter_doc_scanner)
  /// - Android: Google ML Kit Document Scanner API (direct integration)
  ///
  /// Features:
  /// - Real-time edge detection
  /// - Auto-capture when document is stable
  /// - Perspective correction
  /// - Multi-page scanning support (up to maxPages)
  ///
  /// Returns scanned images or cancelled result
  Future<ScannerResult> scanWithCamScannerStyle({
    required BuildContext context,
    String? shopId,
    int maxPages = 5,
    Function(String step)? onProgress,
  }) async {
    try {
      DebugLogService.info('Scanner', 'Opening CamScanner-style scanner (maxPages: $maxPages)');

      // Create config with specified maxPages
      final config = ScannerConfig(
        mode: ScanMode.receipt,
        maxPages: maxPages,
        maxWidth: 1920,
        jpegQuality: 95,
        filter: ImageFilter.documentEnhance,
        autoFillEmptyFields: false,
        showPreview: false,
        allowGalleryImport: true,
      );

      // CRITICAL FIX: Route to platform-specific implementations
      // Previously used flutter_doc_scanner for both platforms which fails on some Android devices
      // Now properly uses:
      // - Android: google_mlkit_document_scanner (direct, reliable)
      // - iOS: flutter_doc_scanner (VisionKit wrapper)
      if (Platform.isAndroid) {
        DebugLogService.info('Scanner', 'Using Android ML Kit Document Scanner (direct integration)');
        return _androidCameraScan(config: config, context: context, onProgress: onProgress);
      } else {
        DebugLogService.info('Scanner', 'Using iOS VisionKit via flutter_doc_scanner');
        return _iosCameraScan(config: config, context: context, onProgress: onProgress);
      }
    } catch (e, stackTrace) {
      DebugLogService.error('Scanner', 'CamScanner-style scan FAILED', error: e, stackTrace: stackTrace);
      return _handleError(e);
    }
  }

  /// Scan receipt using CamScanner-style interface
  Future<ScannerResult> scanReceiptProfessional(BuildContext context) async {
    return scanWithCamScannerStyle(
      context: context,
      maxPages: 5,
    );
  }

  /// Scan invoice using CamScanner-style interface
  Future<ScannerResult> scanInvoiceProfessional(BuildContext context) async {
    return scanWithCamScannerStyle(
      context: context,
      maxPages: 10,
    );
  }
}

/// Parameters for isolate enhancement
/// Used to pass data to compute() function for background processing
class _EnhanceParams {
  final Uint8List bytes;
  final int quality;

  _EnhanceParams({required this.bytes, required this.quality});
}
