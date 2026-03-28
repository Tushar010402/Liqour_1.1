import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../../core/services/image_preprocessing_service.dart';

/// Full-screen document preview with Accept/Retake actions
///
/// MODERN UX PATTERN:
/// - Shows original image IMMEDIATELY (instant feedback)
/// - Processes enhancement in background with smooth loading overlay
/// - Crossfades to enhanced image when processing completes
/// - User sees progress, not a blank waiting screen
///
/// Returns:
/// - true: User accepted the image
/// - false: User wants to retake
/// - null: User cancelled (back button)
class DocumentPreviewScreen extends StatefulWidget {
  final File imageFile;
  final String title;

  /// Whether this image needs enhancement (modern UX pattern)
  /// If true, will process in background with loading animation
  final bool needsEnhancement;

  /// Filter to apply during enhancement
  final ImageFilter filter;

  const DocumentPreviewScreen({
    super.key,
    required this.imageFile,
    this.title = 'Review Document',
    this.needsEnhancement = true,
    this.filter = ImageFilter.documentEnhance,
  });

  @override
  State<DocumentPreviewScreen> createState() => _DocumentPreviewScreenState();
}

class _DocumentPreviewScreenState extends State<DocumentPreviewScreen>
    with SingleTickerProviderStateMixin {

  final ImagePreprocessingService _preprocessingService = ImagePreprocessingService();

  // Processing state
  bool _isProcessing = false;
  bool _processingComplete = false;
  double _processingProgress = 0.0;
  String _processingStep = 'Preparing...';

  // Images
  File? _enhancedImage;

  // Animation for crossfade
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

    // Start enhancement in background if needed
    if (widget.needsEnhancement) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startBackgroundEnhancement();
      });
    }
  }

  @override
  void dispose() {
    _crossfadeController.dispose();
    _preprocessingService.dispose();
    super.dispose();
  }

  /// Start enhancement in background with SMOOTH progress animation
  /// Uses a timer to animate progress while isolate processes
  Future<void> _startBackgroundEnhancement() async {
    if (!mounted) return;

    setState(() {
      _isProcessing = true;
      _processingProgress = 0.0;
      _processingStep = 'Analyzing document...';
    });

    // Start smooth progress animation in parallel with actual processing
    bool processingDone = false;

    // Progress animation task - runs independently
    Future<void> animateProgress() async {
      final steps = [
        (0.05, 'Analyzing document...'),
        (0.15, 'Detecting content...'),
        (0.25, 'Processing pixels...'),
        (0.35, 'Enhancing contrast...'),
        (0.45, 'Whitening paper...'),
        (0.55, 'Darkening text...'),
        (0.65, 'Optimizing colors...'),
        (0.75, 'Sharpening details...'),
        (0.85, 'Final touches...'),
      ];

      for (final step in steps) {
        if (processingDone || !mounted) break;
        await _updateProgress(step.$1, step.$2);
        // Delay between steps - total ~4.5 seconds for all steps
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // If still processing, keep animating slowly from 85% to 95%
      double slowProgress = 0.85;
      while (!processingDone && mounted && slowProgress < 0.95) {
        slowProgress += 0.01;
        await _updateProgress(slowProgress, 'Almost done...');
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }

    try {
      // Start animation in background (non-blocking)
      final animationFuture = animateProgress();

      // Actual processing (runs in isolate)
      final result = await _preprocessingService.preprocessDocument(
        widget.imageFile,
        filter: widget.filter,
      );

      // Signal that processing is done
      processingDone = true;

      // Quick completion animation
      await _updateProgress(0.95, 'Finalizing...');
      await Future.delayed(const Duration(milliseconds: 100));
      await _updateProgress(1.0, 'Complete!');
      await Future.delayed(const Duration(milliseconds: 200));

      if (!mounted) return;

      if (result.success && result.processedImage != null) {
        setState(() {
          _enhancedImage = result.processedImage;
          _processingComplete = true;
          _isProcessing = false;
        });

        // Trigger crossfade animation
        _crossfadeController.forward();

        debugPrint('✅ [DocumentPreview] Enhancement complete!');
      } else {
        // Enhancement failed - use original
        setState(() {
          _enhancedImage = widget.imageFile;
          _processingComplete = true;
          _isProcessing = false;
        });
        debugPrint('⚠️ [DocumentPreview] Enhancement failed, using original');
      }
    } catch (e) {
      processingDone = true;
      debugPrint('❌ [DocumentPreview] Enhancement error: $e');
      if (mounted) {
        setState(() {
          _enhancedImage = widget.imageFile;
          _processingComplete = true;
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _updateProgress(double progress, String step) async {
    if (!mounted) return;
    setState(() {
      _processingProgress = progress;
      _processingStep = step;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Determine which image to show
    final File displayImage = _processingComplete && _enhancedImage != null
        ? _enhancedImage!
        : widget.imageFile;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Image layer with crossfade
          _buildImageLayer(displayImage),

          // Processing overlay (if processing)
          if (_isProcessing) _buildProcessingOverlay(),

          // Top bar with gradient
          _buildTopBar(),

          // Zoom hint
          if (!_isProcessing) _buildZoomHint(),

          // Bottom action buttons
          _buildBottomActions(),
        ],
      ),
    );
  }

  Widget _buildImageLayer(File imageFile) {
    if (!_processingComplete) {
      // Show original image while processing
      return InteractiveViewer(
        minScale: 0.5,
        maxScale: 4.0,
        child: Center(
          child: Image.file(
            widget.imageFile,
            fit: BoxFit.contain,
          ),
        ),
      );
    }

    // After processing, show crossfade animation
    return AnimatedBuilder(
      animation: _crossfadeAnimation,
      builder: (context, child) {
        return InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Center(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Original image (fading out)
                Opacity(
                  opacity: 1.0 - _crossfadeAnimation.value,
                  child: Image.file(
                    widget.imageFile,
                    fit: BoxFit.contain,
                  ),
                ),
                // Enhanced image (fading in)
                if (_enhancedImage != null)
                  Opacity(
                    opacity: _crossfadeAnimation.value,
                    child: Image.file(
                      _enhancedImage!,
                      fit: BoxFit.contain,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProcessingOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.7),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Circular progress with percentage
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 100,
                  height: 100,
                  child: CircularProgressIndicator(
                    value: _processingProgress,
                    strokeWidth: 4,
                    strokeCap: StrokeCap.round,
                    backgroundColor: Colors.white.withOpacity(0.2),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF667EEA),
                    ),
                  ),
                ),
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
            Text(
              _processingStep,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Enhancing for best quality',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 8,
          left: 8,
          right: 16,
          bottom: 16,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withOpacity(0.8),
              Colors.black.withOpacity(0.4),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          children: [
            // Close button
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(
                CupertinoIcons.xmark,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 8),
            // Title
            Expanded(
              child: Text(
                widget.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // Status badge
            _buildStatusBadge(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge() {
    if (_isProcessing) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF667EEA).withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF667EEA).withOpacity(0.5)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667EEA)),
              ),
            ),
            SizedBox(width: 6),
            Text(
              'Enhancing',
              style: TextStyle(
                color: Color(0xFF667EEA),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    // Show quality badge after processing
    final displayImage = _enhancedImage ?? widget.imageFile;
    final fileSize = displayImage.lengthSync();
    final quality = _getQualityFromSize(fileSize);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: quality.color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: quality.color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            quality.icon,
            color: quality.color,
            size: 14,
          ),
          const SizedBox(width: 4),
          Text(
            quality.label,
            style: TextStyle(
              color: quality.color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildZoomHint() {
    return Positioned(
      bottom: 140,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.6),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.zoom_in,
                color: Colors.white70,
                size: 16,
              ),
              SizedBox(width: 6),
              Text(
                'Pinch to zoom',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomActions() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).padding.bottom + 20,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withOpacity(0.9),
              Colors.black.withOpacity(0.6),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          children: [
            // Retake button
            Expanded(
              child: _ActionButton(
                label: 'Retake',
                icon: CupertinoIcons.camera,
                color: Theme.of(context).colorScheme.onSurface,
                onTap: () => Navigator.pop(context, false),
              ),
            ),
            const SizedBox(width: 16),
            // Accept button
            Expanded(
              flex: 2,
              child: _ActionButton(
                label: _isProcessing ? 'Processing...' : 'Accept',
                icon: _isProcessing
                    ? CupertinoIcons.hourglass
                    : CupertinoIcons.checkmark_alt,
                color: _isProcessing ? Theme.of(context).colorScheme.onSurfaceVariant : Colors.green,
                onTap: _isProcessing
                    ? null  // Disable during processing
                    : () => Navigator.pop(context, true),
              ),
            ),
          ],
        ),
      ),
    );
  }

  _ImageQuality _getQualityFromSize(int bytes) {
    final kb = bytes / 1024;
    if (kb > 500) {
      return _ImageQuality('Excellent', Colors.green, CupertinoIcons.checkmark_seal_fill);
    } else if (kb > 200) {
      return _ImageQuality('Good', Colors.blue, CupertinoIcons.checkmark_circle_fill);
    } else if (kb > 100) {
      return _ImageQuality('Fair', Colors.orange, CupertinoIcons.exclamationmark_circle_fill);
    } else {
      return _ImageQuality('Low', Colors.red, CupertinoIcons.xmark_circle_fill);
    }
  }
}

class _ImageQuality {
  final String label;
  final Color color;
  final IconData icon;

  _ImageQuality(this.label, this.color, this.icon);
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: onTap == null ? 0.5 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
            boxShadow: onTap == null ? null : [
              BoxShadow(
                color: color.withOpacity(0.4),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
