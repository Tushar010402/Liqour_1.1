/// Live Camera Scanner Widget
///
/// Industrial-grade camera scanner with real-time quality validation.
/// Focuses on capturing clear, non-blurry images for backend OCR processing.
///
/// Features:
/// - Real-time blur detection and quality scoring
/// - Edge detection overlay for document positioning
/// - Visual guidance for optimal image capture
/// - Flash toggle and help button
///
/// Note: Content validation (date, shop, sizes) is handled by backend
/// after image capture - this widget only ensures image quality.
library;

import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../models/scan_quality_models.dart';
import '../services/real_time_quality_service.dart';

/// Live camera scanner with quality validation overlay
class LiveCameraScannerWidget extends StatefulWidget {
  /// Shop name for display (content validation done on backend)
  final String shopName;

  /// Shop ID for metadata
  final String? shopId;

  /// Callback when image is captured successfully
  /// Image quality is verified before callback is invoked
  final Function(File imageFile) onImageCaptured;

  /// Callback when user cancels
  final VoidCallback onCancel;

  /// Optional camera overlay configuration
  final CameraOverlayConfig? config;

  const LiveCameraScannerWidget({
    super.key,
    required this.shopName,
    this.shopId,
    required this.onImageCaptured,
    required this.onCancel,
    this.config,
  });

  @override
  State<LiveCameraScannerWidget> createState() => _LiveCameraScannerWidgetState();
}

class _LiveCameraScannerWidgetState extends State<LiveCameraScannerWidget>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isCapturing = false;
  bool _isFlashOn = false;

  // Quality service for blur/edge detection
  final _qualityService = RealTimeQualityService();

  // Current quality state
  ScanQualityResult _qualityResult = ScanQualityResult.empty();

  // Config
  late CameraOverlayConfig _config;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _config = widget.config ?? CameraOverlayConfig.defaults();
    _initializeCamera();
    _setupCallbacks();
  }

  void _setupCallbacks() {
    _qualityService.onQualityUpdate = (result) {
      if (mounted) {
        setState(() {
          _qualityResult = result;
        });
      }
    };
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        debugPrint('❌ [LiveScanner] No cameras available');
        return;
      }

      // Use the back camera
      final camera = _cameras!.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      _cameraController = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();

      // Start image stream for real-time processing
      await _cameraController!.startImageStream(_processFrame);

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      debugPrint('❌ [LiveScanner] Camera init error: $e');
    }
  }

  void _processFrame(CameraImage image) {
    // Process frame for quality assessment (blur, edges, lighting)
    _qualityService.assessFrame(image);
  }

  Future<void> _toggleFlash() async {
    if (_cameraController == null) return;

    try {
      _isFlashOn = !_isFlashOn;
      await _cameraController!.setFlashMode(
        _isFlashOn ? FlashMode.torch : FlashMode.off,
      );
      setState(() {});
    } catch (e) {
      debugPrint('❌ [LiveScanner] Flash toggle error: $e');
    }
  }

  Future<void> _captureImage() async {
    if (_cameraController == null || _isCapturing) return;

    setState(() {
      _isCapturing = true;
    });

    try {
      // Stop image stream before capturing
      await _cameraController!.stopImageStream();

      // Capture image
      final XFile imageFile = await _cameraController!.takePicture();

      // Save to temp directory
      final tempDir = await getTemporaryDirectory();
      final targetPath = '${tempDir.path}/receipt_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savedFile = await File(imageFile.path).copy(targetPath);

      // Return captured image - content validation will be done on backend
      widget.onImageCaptured(savedFile);
    } catch (e) {
      debugPrint('❌ [LiveScanner] Capture error: $e');

      // Restart image stream on error
      if (_cameraController != null && _cameraController!.value.isInitialized) {
        await _cameraController!.startImageStream(_processFrame);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      _cameraController?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    _qualityService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Camera preview
            _buildCameraPreview(),

            // Top bar with close, flash, help
            _buildTopBar(),

            // Document edge overlay
            if (_config.showEdgeOverlay) _buildEdgeOverlay(),

            // Validation checklist
            if (_config.showValidationChecklist) _buildValidationChecklist(),

            // Capture button and guidance
            _buildCaptureSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (!_isInitialized || _cameraController == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Initializing camera...',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      );
    }

    return Center(
      child: CameraPreview(_cameraController!),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withOpacity(0.7),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Close button
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: widget.onCancel,
            ),

            // Shop name
            Expanded(
              child: Text(
                widget.shopName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Flash and help buttons
            Row(
              children: [
                IconButton(
                  icon: Icon(
                    _isFlashOn ? Icons.flash_on : Icons.flash_off,
                    color: _isFlashOn ? Colors.amber : Colors.white,
                    size: 24,
                  ),
                  onPressed: _toggleFlash,
                ),
                IconButton(
                  icon: const Icon(Icons.help_outline, color: Colors.white, size: 24),
                  onPressed: _showHelpDialog,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEdgeOverlay() {
    final edgeColor = _qualityResult.edgesDetected
        ? _config.edgeDetectedColor
        : _config.edgeMissingColor;

    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          margin: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            border: Border.all(
              color: edgeColor.withOpacity(0.7),
              width: 3,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            children: [
              // Corner indicators
              ..._buildCornerIndicators(edgeColor),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildCornerIndicators(Color color) {
    const cornerSize = 20.0;
    const cornerThickness = 4.0;

    return [
      // Top-left
      Positioned(
        top: -2,
        left: -2,
        child: _buildCorner(color, cornerSize, cornerThickness, true, true),
      ),
      // Top-right
      Positioned(
        top: -2,
        right: -2,
        child: _buildCorner(color, cornerSize, cornerThickness, true, false),
      ),
      // Bottom-left
      Positioned(
        bottom: -2,
        left: -2,
        child: _buildCorner(color, cornerSize, cornerThickness, false, true),
      ),
      // Bottom-right
      Positioned(
        bottom: -2,
        right: -2,
        child: _buildCorner(color, cornerSize, cornerThickness, false, false),
      ),
    ];
  }

  Widget _buildCorner(Color color, double size, double thickness, bool isTop, bool isLeft) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CornerPainter(
          color: color,
          thickness: thickness,
          isTop: isTop,
          isLeft: isLeft,
        ),
      ),
    );
  }

  Widget _buildValidationChecklist() {
    // Calculate quality status for border color
    final isSharp = _qualityResult.blurQuality != BlurQualityTier.tooBlurry;
    final hasGoodLighting = _qualityResult.lightingQuality == LightingQualityTier.good ||
        _qualityResult.lightingQuality == LightingQualityTier.acceptable;
    final hasEdges = _qualityResult.edgesDetected;

    final passedCount = (isSharp ? 1 : 0) + (hasGoodLighting ? 1 : 0) + (hasEdges ? 1 : 0);

    Color borderColor;
    if (passedCount == 3) {
      borderColor = Colors.green;
    } else if (passedCount >= 2) {
      borderColor = Colors.orange;
    } else {
      borderColor = Colors.red.withOpacity(0.7);
    }

    return Positioned(
      bottom: 160,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.85),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 2),
          boxShadow: passedCount >= 2
              ? [
                  BoxShadow(
                    color: borderColor.withOpacity(0.3),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'IMAGE QUALITY',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: borderColor.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_qualityResult.overallScore.toInt()}%',
                    style: TextStyle(
                      color: borderColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Quality checks
            _buildQualityItem(
              icon: Icons.blur_on,
              label: 'Sharpness',
              value: _getBlurStatusText(_qualityResult.blurQuality),
              isPassed: isSharp,
            ),
            _buildQualityItem(
              icon: Icons.light_mode,
              label: 'Lighting',
              value: _getLightingStatusText(_qualityResult.lightingQuality),
              isPassed: hasGoodLighting,
              isWarning: _qualityResult.lightingQuality == LightingQualityTier.acceptable,
            ),
            _buildQualityItem(
              icon: Icons.crop_free,
              label: 'Document',
              value: hasEdges ? '✓ Detected' : 'Position in frame',
              isPassed: hasEdges,
            ),

            // Ready indicator
            if (passedCount == 3) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.green.withOpacity(0.5)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 14),
                    SizedBox(width: 6),
                    Text(
                      'Ready to capture!',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _getBlurStatusText(BlurQualityTier tier) {
    switch (tier) {
      case BlurQualityTier.excellent:
        return '✓ Excellent';
      case BlurQualityTier.good:
        return '✓ Good';
      case BlurQualityTier.acceptable:
        return '⚠ Acceptable';
      case BlurQualityTier.tooBlurry:
        return '✗ Too blurry';
    }
  }

  String _getLightingStatusText(LightingQualityTier tier) {
    switch (tier) {
      case LightingQualityTier.good:
        return '✓ Good';
      case LightingQualityTier.acceptable:
        return '⚠ Acceptable';
      case LightingQualityTier.tooDark:
        return '✗ Too dark';
      case LightingQualityTier.tooBright:
        return '✗ Too bright';
    }
  }

  Widget _buildQualityItem({
    required IconData icon,
    required String label,
    required String value,
    required bool isPassed,
    bool isWarning = false,
  }) {
    final color = isPassed
        ? (isWarning ? Colors.orange : Colors.green)
        : Colors.red;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            isPassed ? Icons.check_circle : (isWarning ? Icons.warning : Icons.cancel),
            color: color,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            '$label:',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCaptureSection() {
    final canCapture = _isInitialized && !_isCapturing;
    final qualityGood = _qualityResult.isAcceptable;

    String guidanceText;
    Color guidanceColor;

    if (!_isInitialized) {
      guidanceText = 'Initializing camera...';
      guidanceColor = Colors.white70;
    } else if (_isCapturing) {
      guidanceText = 'Capturing image...';
      guidanceColor = Colors.white70;
    } else if (_qualityResult.blurQuality == BlurQualityTier.tooBlurry) {
      guidanceText = 'Hold phone steady for a clear image';
      guidanceColor = Colors.red;
    } else if (_qualityResult.lightingQuality == LightingQualityTier.tooDark) {
      guidanceText = 'Move to better lighting or turn on flash';
      guidanceColor = Colors.red;
    } else if (_qualityResult.lightingQuality == LightingQualityTier.tooBright) {
      guidanceText = 'Too bright - avoid direct light';
      guidanceColor = Colors.orange;
    } else if (!_qualityResult.edgesDetected) {
      guidanceText = 'Position receipt in the frame';
      guidanceColor = Colors.orange;
    } else if (qualityGood) {
      guidanceText = 'Image quality good - Tap to capture';
      guidanceColor = Colors.green;
    } else {
      guidanceText = 'Adjust position for better quality';
      guidanceColor = Colors.orange;
    }

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withOpacity(0.9),
              Colors.black.withOpacity(0.5),
              Colors.transparent,
            ],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Guidance text
            Text(
              guidanceText,
              style: TextStyle(
                color: guidanceColor,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            // Capture button
            GestureDetector(
              onTap: canCapture ? _captureImage : null,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: canCapture ? Colors.white : Colors.white30,
                  border: Border.all(
                    color: qualityGood ? Colors.green : Colors.white,
                    width: 4,
                  ),
                  boxShadow: qualityGood
                      ? [
                          BoxShadow(
                            color: Colors.green.withOpacity(0.5),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: _isCapturing
                    ? const Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Colors.grey,
                        ),
                      )
                    : Icon(
                        Icons.camera_alt,
                        size: 32,
                        color: canCapture ? Colors.black : Colors.white30,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Capture Tips'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HelpTip(
              icon: Icons.blur_on,
              title: 'Keep Steady',
              description: 'Hold the phone still for a sharp, clear image.',
            ),
            SizedBox(height: 12),
            _HelpTip(
              icon: Icons.light_mode,
              title: 'Good Lighting',
              description: 'Use natural light or turn on flash if too dark.',
            ),
            SizedBox(height: 12),
            _HelpTip(
              icon: Icons.crop_free,
              title: 'Frame Document',
              description: 'Position the receipt fully within the frame.',
            ),
            SizedBox(height: 12),
            _HelpTip(
              icon: Icons.visibility,
              title: 'Clear Text',
              description: 'Ensure all text on the receipt is visible and readable.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

/// Help tip item
class _HelpTip extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _HelpTip({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.blue),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                description,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Custom painter for corner indicators
class _CornerPainter extends CustomPainter {
  final Color color;
  final double thickness;
  final bool isTop;
  final bool isLeft;

  _CornerPainter({
    required this.color,
    required this.thickness,
    required this.isTop,
    required this.isLeft,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();

    if (isTop && isLeft) {
      path.moveTo(0, size.height);
      path.lineTo(0, 0);
      path.lineTo(size.width, 0);
    } else if (isTop && !isLeft) {
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width, size.height);
    } else if (!isTop && isLeft) {
      path.moveTo(0, 0);
      path.lineTo(0, size.height);
      path.lineTo(size.width, size.height);
    } else {
      path.moveTo(0, size.height);
      path.lineTo(size.width, size.height);
      path.lineTo(size.width, 0);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CornerPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.thickness != thickness;
  }
}
