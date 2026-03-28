import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:photo_view/photo_view.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/image_preprocessing_service.dart';
import '../widgets/image_quality_indicator.dart';

/// Modern Image Enhancement Preview Screen
///
/// INDUSTRIAL-GRADE UX:
/// 1. Shows original image IMMEDIATELY (no wait)
/// 2. Displays smooth processing animation overlay
/// 3. Seamlessly cross-fades to enhanced image
/// 4. Before/after comparison with swipe gesture
/// 5. Pinch-to-zoom support
///
/// This is like CamScanner/DocScanner - instant feedback, smooth animations
class ImageEnhancementPreviewScreen extends StatefulWidget {
  /// Original captured image - shown immediately
  final File originalImage;

  /// Pre-processed image (optional - if already processed)
  final File? processedImage;

  /// Preprocessing result with metadata (optional)
  final PreprocessingResult? result;

  /// Filter to apply (default: documentEnhance for best quality)
  final ImageFilter filter;

  /// Whether to auto-process on load
  final bool autoProcess;

  const ImageEnhancementPreviewScreen({
    super.key,
    required this.originalImage,
    this.processedImage,
    this.result,
    this.filter = ImageFilter.documentEnhance,
    this.autoProcess = true,
  });

  @override
  State<ImageEnhancementPreviewScreen> createState() =>
      _ImageEnhancementPreviewScreenState();
}

class _ImageEnhancementPreviewScreenState
    extends State<ImageEnhancementPreviewScreen>
    with SingleTickerProviderStateMixin {

  final ImagePreprocessingService _preprocessingService = ImagePreprocessingService();

  // Processing state
  bool _isProcessing = false;
  bool _processingComplete = false;
  String _processingStep = 'Enhancing image...';
  double _processingProgress = 0.0;
  File? _processedImage;
  PreprocessingResult? _result;

  // Blur detection state
  bool _isAnalyzingBlur = false;
  BlurScoreResult? _blurScore;

  // UI state
  bool _showComparison = false;
  bool _showOriginal = false;
  final bool _showEnhancementControls = false;

  // Animation controller for crossfade
  late AnimationController _crossfadeController;
  late Animation<double> _crossfadeAnimation;

  @override
  void initState() {
    super.initState();

    // Setup crossfade animation
    _crossfadeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _crossfadeAnimation = CurvedAnimation(
      parent: _crossfadeController,
      curve: Curves.easeInOut,
    );

    // Check if already processed
    if (widget.processedImage != null && widget.result != null) {
      _processedImage = widget.processedImage;
      _result = widget.result;
      _processingComplete = true;
      _crossfadeController.value = 1.0; // Show processed image
    } else if (widget.autoProcess) {
      // Start processing after the screen is built
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startProcessing();
        _analyzeBlurQuality(); // Also analyze blur quality
      });
    } else {
      // Just analyze blur if not auto-processing
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _analyzeBlurQuality();
      });
    }
  }

  /// Analyze blur quality of the original image
  Future<void> _analyzeBlurQuality() async {
    if (_isAnalyzingBlur) return;

    setState(() {
      _isAnalyzingBlur = true;
    });

    try {
      final result = await _preprocessingService.calculateBlurScoreFromFile(widget.originalImage);
      if (mounted) {
        setState(() {
          _blurScore = result;
          _isAnalyzingBlur = false;
        });

        // If image is too blurry, show warning
        if (result.quality == BlurQuality.tooBlurry) {
          _showBlurWarning();
        }
      }
    } catch (e) {
      debugPrint('❌ [ImagePreview] Blur analysis error: $e');
      if (mounted) {
        setState(() {
          _isAnalyzingBlur = false;
        });
      }
    }
  }

  /// Show warning dialog for blurry images
  void _showBlurWarning() {
    if (!mounted) return;

    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning_amber, color: AppColors.warning, size: 24),
            const SizedBox(width: 8),
            const Text('Blurry Image'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Text(
              _blurScore?.message ?? 'This image appears to be blurry.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'OCR accuracy may be affected. Would you like to retake?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              Navigator.of(context).pop(); // Close dialog
              Navigator.of(context).pop(false); // Return to scanner
            },
            child: const Text('Retake Photo'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Use Anyway'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _crossfadeController.dispose();
    _preprocessingService.dispose();
    super.dispose();
  }

  /// Start the image enhancement process in background
  Future<void> _startProcessing() async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _processingProgress = 0.0;
      _processingStep = 'Analyzing document...';
    });

    // Animate progress for visual feedback
    _animateProgress();

    try {
      final result = await _preprocessingService.preprocessDocument(
        widget.originalImage,
        filter: widget.filter,
        onProgress: (step) {
          if (mounted) {
            setState(() {
              _processingStep = step;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _isProcessing = false;
          _processingComplete = true;
          _processedImage = result.processedImage;
          _result = result;
          _processingProgress = 1.0;
        });

        // Crossfade to enhanced image
        _crossfadeController.forward();
      }
    } catch (e) {
      debugPrint('❌ [ImagePreview] Processing error: $e');
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _processingStep = 'Enhancement failed';
        });
      }
    }
  }

  /// Animate the progress indicator for visual feedback
  void _animateProgress() async {
    // Smooth progress animation
    for (int i = 0; i <= 90 && _isProcessing && mounted; i += 3) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (mounted && _isProcessing) {
        setState(() {
          _processingProgress = i / 100;
          if (i < 30) {
            _processingStep = 'Analyzing document...';
          } else if (i < 60) {
            _processingStep = 'Enhancing colors...';
          } else {
            _processingStep = 'Optimizing for OCR...';
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Main content
          Column(
            children: [
              // Modern app bar
              _buildModernAppBar(),

              // Quality indicator (shown when blur detected)
              _buildQualityIndicator(),

              // Image preview with crossfade
              Expanded(
                child: _showComparison
                    ? _buildComparisonView()
                    : _buildImagePreview(),
              ),

              // Bottom actions
              _buildBottomActions(),
            ],
          ),

          // Processing overlay (only shown when processing)
          if (_isProcessing)
            _buildProcessingOverlay(),
        ],
      ),
    );
  }

  Widget _buildModernAppBar() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 8,
        right: 8,
        bottom: 8,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black,
            Colors.black.withOpacity(0.8),
            Colors.transparent,
          ],
          stops: const [0.0, 0.7, 1.0],
        ),
      ),
      child: Row(
        children: [
          // Close button
          IconButton(
            onPressed: () => Navigator.of(context).pop(false),
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 20),
            ),
          ),

          // Title and status
          Expanded(
            child: Column(
              children: [
                Text(
                  _processingComplete ? 'Enhanced Image' : 'Preview',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_processingComplete && _result != null)
                  Text(
                    _result!.summaryMessage,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),

          // Compare toggle
          IconButton(
            onPressed: _processingComplete
                ? () => setState(() => _showComparison = !_showComparison)
                : null,
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _showComparison
                    ? const Color(0xFF667EEA)
                    : Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _showComparison ? Icons.compare : Icons.compare_arrows,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build quality indicator section shown below app bar
  Widget _buildQualityIndicator() {
    if (_blurScore == null && !_isAnalyzingBlur) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ImageQualityIndicator(
        blurScore: _blurScore,
        isAnalyzing: _isAnalyzingBlur,
        showScore: true,
        showMessage: true,
        onRetake: () => Navigator.of(context).pop(false),
        size: ImageQualityIndicatorSize.normal,
      ),
    );
  }

  Widget _buildImagePreview() {
    return GestureDetector(
      onLongPressStart: _processingComplete
          ? (_) => setState(() => _showOriginal = true)
          : null,
      onLongPressEnd: _processingComplete
          ? (_) => setState(() => _showOriginal = false)
          : null,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Original image (always visible initially, fades out)
          Opacity(
            opacity: 1 - _crossfadeAnimation.value,
            child: PhotoView(
              imageProvider: FileImage(widget.originalImage),
              backgroundDecoration: const BoxDecoration(color: Colors.black),
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 3,
            ),
          ),

          // Processed image (fades in when ready)
          if (_processedImage != null)
            AnimatedBuilder(
              animation: _crossfadeAnimation,
              builder: (context, child) => Opacity(
                opacity: _showOriginal ? 0 : _crossfadeAnimation.value,
                child: child,
              ),
              child: PhotoView(
                imageProvider: FileImage(_processedImage!),
                backgroundDecoration: const BoxDecoration(color: Colors.black),
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 3,
              ),
            ),

          // Instructions overlay
          if (_processingComplete && !_showOriginal)
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedOpacity(
                  opacity: 1.0,
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.touch_app, color: Colors.white70, size: 16),
                        SizedBox(width: 8),
                        Text(
                          'Long press to see original',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // "Original" badge when showing original
          if (_showOriginal)
            Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                    ),
                    borderRadius: BorderRadius.circular(25),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF667EEA).withOpacity(0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history, color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Original Image',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProcessingOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.7),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Modern circular progress
            Stack(
              alignment: Alignment.center,
              children: [
                // Background circle
                SizedBox(
                  width: 100,
                  height: 100,
                  child: CircularProgressIndicator(
                    value: 1.0,
                    strokeWidth: 4,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.white.withOpacity(0.1),
                    ),
                  ),
                ),
                // Progress circle
                SizedBox(
                  width: 100,
                  height: 100,
                  child: CircularProgressIndicator(
                    value: _processingProgress,
                    strokeWidth: 4,
                    strokeCap: StrokeCap.round,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF667EEA),
                    ),
                  ),
                ),
                // Percentage text
                Text(
                  '${(_processingProgress * 100).round()}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Processing step
            Text(
              _processingStep,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 8),

            // Tip text
            Text(
              'Optimizing for best OCR accuracy',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComparisonView() {
    return Row(
      children: [
        // Before (Original)
        Expanded(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.error.withValues(alpha: 0.3),
                      AppColors.error.withValues(alpha: 0.1),
                    ],
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.history, color: Colors.white, size: 16),
                    SizedBox(width: 8),
                    Text(
                      'BEFORE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PhotoView(
                  imageProvider: FileImage(widget.originalImage),
                  backgroundDecoration: const BoxDecoration(color: Colors.black),
                  minScale: PhotoViewComputedScale.contained,
                  maxScale: PhotoViewComputedScale.covered * 2,
                ),
              ),
            ],
          ),
        ),

        // Divider
        Container(
          width: 3,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
            ),
          ),
        ),

        // After (Processed)
        Expanded(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.success.withValues(alpha: 0.3),
                      AppColors.success.withValues(alpha: 0.1),
                    ],
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.auto_awesome, color: Colors.white, size: 16),
                    SizedBox(width: 8),
                    Text(
                      'AFTER',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PhotoView(
                  imageProvider: FileImage(_processedImage ?? widget.originalImage),
                  backgroundDecoration: const BoxDecoration(color: Colors.black),
                  minScale: PhotoViewComputedScale.contained,
                  maxScale: PhotoViewComputedScale.covered * 2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomActions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withOpacity(0.8),
            Colors.black,
          ],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Retake button
            Expanded(
              child: CupertinoButton(
                onPressed: () => Navigator.of(context).pop(false),
                padding: const EdgeInsets.symmetric(vertical: 14),
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(CupertinoIcons.refresh, size: 20, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'Retake',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(width: 12),

            // Accept button
            Expanded(
              flex: 2,
              child: CupertinoButton(
                onPressed: _processingComplete
                    ? () => Navigator.of(context).pop(true)
                    : null,
                padding: const EdgeInsets.symmetric(vertical: 14),
                color: _processingComplete
                    ? const Color(0xFF667EEA)
                    : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _processingComplete
                          ? CupertinoIcons.checkmark_circle_fill
                          : CupertinoIcons.time,
                      size: 22,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _processingComplete ? 'Accept & Continue' : 'Processing...',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
