import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/image_preprocessing_service.dart';
import '../widgets/image_quality_indicator.dart';
import 'image_enhancement_preview_screen.dart';

/// Professional Document Scanner Screen
///
/// CamScanner-like experience with:
/// - Real-time edge detection
/// - Auto-capture when document stable
/// - Perspective correction
/// - Multi-page scanning support
///
/// Features:
/// - Camera opens with edge detection overlay
/// - Green box appears when document detected
/// - Auto-captures after document is stable
/// - Can scan up to 10 pages per session
/// - Gallery import also supported
class ProfessionalDocumentScannerScreen extends StatefulWidget {
  /// Shop ID for context
  final String? shopId;

  /// Maximum number of pages to scan (default: 10 for industrial use)
  final int maxPages;

  /// Whether to automatically fill empty fields
  final bool autoFillEmptyFields;

  const ProfessionalDocumentScannerScreen({
    super.key,
    this.shopId,
    this.maxPages = 10,  // Industrial standard: up to 10 pages
    this.autoFillEmptyFields = true,
  });

  @override
  State<ProfessionalDocumentScannerScreen> createState() =>
      _ProfessionalDocumentScannerScreenState();
}

class _ProfessionalDocumentScannerScreenState
    extends State<ProfessionalDocumentScannerScreen> {

  final ImagePreprocessingService _preprocessingService =
      ImagePreprocessingService();

  final List<File> _scannedImages = [];
  final Map<String, BlurScoreResult> _imageQualityScores = {};
  final bool _isProcessing = false;
  final String _processingStep = '';

  @override
  void initState() {
    super.initState();
    // Auto-open scanner when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openDocumentScanner();
    });
  }

  @override
  void dispose() {
    _preprocessingService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // This screen is mostly transparent - the camera is shown
    // If we're processing, show loading overlay
    if (_isProcessing) {
      return Scaffold(
        backgroundColor: Colors.black.withOpacity(0.8),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
              const SizedBox(height: 24),
              Text(
                _processingStep,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Default state: instructions
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            _buildHeader(),

            // Scanned images thumbnails (if any)
            if (_scannedImages.isNotEmpty)
              _buildScannedImagesThumbnails(),

            // Instructions
            Expanded(
              child: Center(
                child: _buildInstructions(),
              ),
            ),

            // Action buttons
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  /// Build thumbnails strip showing scanned images with quality badges
  Widget _buildScannedImagesThumbnails() {
    return Container(
      height: 110,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _scannedImages.length,
        itemBuilder: (context, index) {
          final image = _scannedImages[index];
          final qualityScore = _imageQualityScores[image.path];

          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Stack(
              children: [
                // Thumbnail image
                GestureDetector(
                  onTap: () => _showImagePreview(image),
                  child: Container(
                    width: 80,
                    height: 100,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: qualityScore != null
                            ? Color(qualityScore.quality.colorValue).withOpacity(0.5)
                            : Colors.white.withOpacity(0.2),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(
                        image,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),

                // Quality badge
                if (qualityScore != null)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: ImageQualityBadge(
                      quality: qualityScore.quality,
                      size: 20,
                    ),
                  ),

                // Index badge
                Positioned(
                  bottom: 4,
                  left: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),

                // Delete button
                Positioned(
                  top: 4,
                  left: 4,
                  child: GestureDetector(
                    onTap: () => _removeImage(index),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.9),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Remove an image from the scanned list
  void _removeImage(int index) {
    setState(() {
      final image = _scannedImages[index];
      _imageQualityScores.remove(image.path);
      _scannedImages.removeAt(index);
    });
  }

  /// Show full preview of a scanned image
  void _showImagePreview(File image) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ImageEnhancementPreviewScreen(
          originalImage: image,
          autoProcess: false, // Don't auto-process, just preview
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // Back button
          IconButton(
            onPressed: () {
              if (_scannedImages.isNotEmpty) {
                _showDiscardConfirmation();
              } else {
                Navigator.of(context).pop();
              }
            },
            icon: const Icon(Icons.close, color: Colors.white),
          ),

          // Title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Professional Scanner',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                if (_scannedImages.isNotEmpty)
                  Text(
                    '${_scannedImages.length}/${widget.maxPages} scanned',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.7),
                    ),
                  ),
              ],
            ),
          ),

          // Done button (if images scanned)
          if (_scannedImages.isNotEmpty)
            TextButton(
              onPressed: _completeScanning,
              child: const Text(
                'Done',
                style: TextStyle(
                  color: Color(0xFF667EEA),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInstructions() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF667EEA).withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: const Icon(
              Icons.document_scanner,
              size: 64,
              color: Colors.white,
            ),
          ),

          const SizedBox(height: 32),

          // Title
          const Text(
            'Scan Your Invoice',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),

          const SizedBox(height: 16),

          // Instructions
          Text(
            'Position your invoice in a well-lit area.\n'
            'The scanner will automatically detect edges and capture.',
            style: TextStyle(
              fontSize: 16,
              color: Colors.white.withOpacity(0.7),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 32),

          // Features list
          _buildFeatureRow(Icons.auto_awesome, 'Auto-detect document edges'),
          const SizedBox(height: 12),
          _buildFeatureRow(Icons.straighten, 'Auto-straighten tilted pages'),
          const SizedBox(height: 12),
          _buildFeatureRow(Icons.blur_off, 'Blur detection & quality check'),
          const SizedBox(height: 12),
          _buildFeatureRow(Icons.brightness_high, 'Enhance image quality'),
          const SizedBox(height: 12),
          _buildFeatureRow(Icons.filter_b_and_w, 'Optimize for OCR'),
        ],
      ),
    );
  }

  Widget _buildFeatureRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: const Color(0xFF667EEA),
        ),
        const SizedBox(width: 12),
        Text(
          text,
          style: TextStyle(
            fontSize: 14,
            color: Colors.white.withOpacity(0.8),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Scan button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _openDocumentScanner,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF667EEA),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.camera_alt, size: 24),
                  SizedBox(width: 12),
                  Text(
                    'Start Scanning',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Gallery import button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _importFromGallery,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withOpacity(0.3)),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.photo_library, size: 24),
                  SizedBox(width: 12),
                  Text(
                    'Import from Gallery',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // SCANNER METHODS
  // ==========================================

  /// Open document scanner with edge detection
  Future<void> _openDocumentScanner() async {
    try {
      debugPrint('📸 [ProfessionalScanner] Opening document scanner...');

      // Use flutter_doc_scanner - native VisionKit on iOS, ML Kit on Android
      final dynamic scannedResult = await FlutterDocScanner().getScannedDocumentAsImages(
        page: widget.maxPages - _scannedImages.length,
      );

      if (scannedResult != null) {
        // Handle result - can be single path or list
        List<String> pictures = [];
        if (scannedResult is List) {
          pictures = scannedResult.map((e) => e.toString()).toList();
        } else if (scannedResult is String) {
          pictures = [scannedResult];
        }

        if (pictures.isNotEmpty) {
          debugPrint('📸 [ProfessionalScanner] Captured ${pictures.length} images');

          // Process each scanned image
          for (final picturePath in pictures) {
            await _processScannedImage(File(picturePath));
          }

          // If all images processed, complete scanning
          if (_scannedImages.isNotEmpty) {
            _completeScanning();
          }
        } else {
          debugPrint('📸 [ProfessionalScanner] No images captured');
          if (mounted) Navigator.of(context).pop();
        }
      } else {
        debugPrint('📸 [ProfessionalScanner] User cancelled');
        if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('❌ [ProfessionalScanner] Scanner error: $e');
      _showError('Failed to open scanner: ${e.toString()}');
    }
  }

  /// Import from gallery
  Future<void> _importFromGallery() async {
    try {
      debugPrint('📁 [ProfessionalScanner] Opening gallery...');

      // Use flutter_doc_scanner
      final dynamic scannedResult = await FlutterDocScanner().getScannedDocumentAsImages(
        page: widget.maxPages - _scannedImages.length,
      );

      if (scannedResult != null) {
        List<String> pictures = [];
        if (scannedResult is List) {
          pictures = scannedResult.map((e) => e.toString()).toList();
        } else if (scannedResult is String) {
          pictures = [scannedResult];
        }

        for (final picturePath in pictures) {
          await _processScannedImage(File(picturePath));
        }

        if (_scannedImages.isNotEmpty) {
          _completeScanning();
        }
      }
    } catch (e) {
      debugPrint('❌ [ProfessionalScanner] Gallery import error: $e');
      _showError('Failed to import from gallery');
    }
  }

  /// Process a single scanned image
  ///
  /// MODERN UX: Navigate to preview IMMEDIATELY, let preview screen handle processing
  /// This gives instant visual feedback - no waiting on a loading screen
  Future<void> _processScannedImage(File imageFile) async {
    try {
      debugPrint('📸 [ProfessionalScanner] Opening preview for: ${imageFile.path}');

      // Navigate IMMEDIATELY to preview screen - it will handle processing internally
      // This is the modern UX pattern used by CamScanner, DocScanner, etc.
      if (mounted) {
        final accepted = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (context) => ImageEnhancementPreviewScreen(
              originalImage: imageFile,
              // Don't pass processedImage - let preview screen handle it
              // with smooth animations and progress feedback
              filter: ImageFilter.documentEnhance, // Best quality
              autoProcess: true, // Start processing automatically
            ),
          ),
        );

        if (accepted == true) {
          // User accepted the image - add to scanned list
          // The preview screen processed it, we can use the original path
          // or get the processed image from the service
          setState(() {
            _scannedImages.add(imageFile);
          });

          // Analyze blur quality in background for thumbnail badge
          _analyzeImageQuality(imageFile);

          // Show success message
          _showSnackbar(
            'Image ${_scannedImages.length} captured successfully',
            icon: Icons.check_circle,
            color: AppColors.success,
          );

          // If max pages reached, complete scanning
          if (_scannedImages.length >= widget.maxPages) {
            _completeScanning();
          }
        }
      }
    } catch (e) {
      debugPrint('❌ [ProfessionalScanner] Error: $e');
      _showError('Failed to open preview: ${e.toString()}');
    }
  }

  /// Analyze blur quality of an image and store the result
  Future<void> _analyzeImageQuality(File imageFile) async {
    try {
      debugPrint('🔍 [ProfessionalScanner] Analyzing quality for: ${imageFile.path}');
      final result = await _preprocessingService.calculateBlurScoreFromFile(imageFile);

      if (mounted) {
        setState(() {
          _imageQualityScores[imageFile.path] = result;
        });
        debugPrint('🔍 [ProfessionalScanner] Quality: ${result.quality.name} (${result.score.toStringAsFixed(1)})');
      }
    } catch (e) {
      debugPrint('❌ [ProfessionalScanner] Quality analysis error: $e');
    }
  }

  /// Complete scanning and return results
  void _completeScanning() {
    debugPrint('✅ [ProfessionalScanner] Completing with ${_scannedImages.length} images');

    if (_scannedImages.isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    // Return scanned images to caller
    Navigator.of(context).pop(_scannedImages);
  }

  // ==========================================
  // UI HELPERS
  // ==========================================

  void _showDiscardConfirmation() {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Discard Scanned Images?'),
        content: Text('You have ${_scannedImages.length} scanned images. Discard them?'),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.of(context).pop(); // Close dialog
              Navigator.of(context).pop(); // Close scanner
            },
            child: const Text('Discard'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;

    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showSnackbar(String message, {IconData? icon, Color? color}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.white),
              const SizedBox(width: 12),
            ],
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: color ?? Colors.black87,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
