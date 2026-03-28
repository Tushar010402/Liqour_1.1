import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';

/// Widget for previewing captured receipt image - CamScanner-style
///
/// Features:
/// - Document fills the screen (auto-cropped, no black borders)
/// - Smooth pinch-to-zoom with momentum
/// - Double-tap to zoom in/out
/// - Pan and scroll support
class ReceiptPreviewWidget extends StatefulWidget {
  final File imageFile;
  final VoidCallback onRetake;

  const ReceiptPreviewWidget({
    super.key,
    required this.imageFile,
    required this.onRetake,
  });

  @override
  State<ReceiptPreviewWidget> createState() => _ReceiptPreviewWidgetState();
}

class _ReceiptPreviewWidgetState extends State<ReceiptPreviewWidget>
    with SingleTickerProviderStateMixin {
  final TransformationController _transformationController =
      TransformationController();
  late AnimationController _animationController;
  Animation<Matrix4>? _animation;
  bool _showZoomHint = true;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    // Hide zoom hint after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _showZoomHint = false);
      }
    });
  }

  @override
  void dispose() {
    _transformationController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  /// Double-tap to zoom in/out (CamScanner-style)
  void _onDoubleTapDown(TapDownDetails details) {
    final position = details.localPosition;
    final currentScale = _transformationController.value.getMaxScaleOnAxis();

    Matrix4 endMatrix;
    if (currentScale > 1.5) {
      // Zoom out to fit
      endMatrix = Matrix4.identity();
    } else {
      // Zoom in to 2.5x at the tap position
      endMatrix = Matrix4.identity()
        ..translate(-position.dx * 1.5, -position.dy * 1.5)
        ..scale(2.5);
    }

    _animation = Matrix4Tween(
      begin: _transformationController.value,
      end: endMatrix,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));

    _animationController.forward(from: 0).then((_) {
      _transformationController.value = endMatrix;
    });

    _animation!.addListener(() {
      _transformationController.value = _animation!.value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Image display - CamScanner-style full-screen with zoom
          GestureDetector(
            onDoubleTapDown: _onDoubleTapDown,
            onDoubleTap: () {}, // Required for onDoubleTapDown to work
            child: InteractiveViewer(
              transformationController: _transformationController,
              minScale: 0.5,
              maxScale: 5.0,
              panEnabled: true,
              scaleEnabled: true,
              boundaryMargin: const EdgeInsets.all(20),
              child: Container(
                color: Colors.black,
                child: Center(
                  child: Image.file(
                    widget.imageFile,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
            ),
          ),

          // Top toolbar with gradient overlay
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 8,
                left: 8,
                right: 8,
                bottom: 16,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.7),
                    Colors.black.withOpacity(0.3),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                children: [
                  // Close/Back button
                  IconButton(
                    onPressed: widget.onRetake,
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Title
                  Expanded(
                    child: Text(
                      'Review Receipt',
                      style: AppTextStyles.h5.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  // Quality indicator
                  _buildQualityIndicator(),
                ],
              ),
            ),
          ),

          // Zoom hint - fades out after 3 seconds
          if (_showZoomHint)
            Positioned(
              bottom: 120,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                opacity: _showZoomHint ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.pinch_outlined,
                          color: Colors.white.withOpacity(0.9),
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Pinch to zoom',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: Colors.white.withOpacity(0.9),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQualityIndicator() {
    // Check image quality (simplified - in production, implement actual quality check)
    final fileSize = widget.imageFile.lengthSync();
    final quality = _calculateQuality(fileSize);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _getQualityColor(quality).withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _getQualityColor(quality).withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getQualityIcon(quality),
            color: Colors.white,
            size: 16,
          ),
          const SizedBox(width: 6),
          Text(
            _getQualityText(quality),
            style: AppTextStyles.bodySmall.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _getQualityText(double quality) {
    if (quality >= 0.8) return 'Excellent';
    if (quality >= 0.6) return 'Good';
    if (quality >= 0.4) return 'Fair';
    return 'Poor';
  }

  IconData _getQualityIcon(double quality) {
    if (quality >= 0.8) return Icons.check_circle;
    if (quality >= 0.6) return Icons.check;
    if (quality >= 0.4) return Icons.warning_amber;
    return Icons.error_outline;
  }

  Color _getQualityColor(double quality) {
    if (quality >= 0.8) return AppColors.success;
    if (quality >= 0.6) return AppColors.info;
    if (quality >= 0.4) return AppColors.warning;
    return AppColors.error;
  }

  double _calculateQuality(int fileSize) {
    // Simple heuristic based on file size
    // Ideal size is between 500KB and 2MB
    if (fileSize < 100000) return 0.2; // Less than 100KB - too small
    if (fileSize < 500000) return 0.5; // 100KB - 500KB
    if (fileSize < 2000000) return 0.9; // 500KB - 2MB - ideal
    if (fileSize < 5000000) return 0.7; // 2MB - 5MB
    return 0.4; // Over 5MB - too large
  }

  void _showImageInfo(BuildContext context) {
    final fileSize = widget.imageFile.lengthSync();
    final fileSizeInKB = (fileSize / 1024).toStringAsFixed(0);
    final fileSizeInMB = (fileSize / (1024 * 1024)).toStringAsFixed(2);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Image Information'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('File Size',
              fileSize < 1024 * 1024
                ? '$fileSizeInKB KB'
                : '$fileSizeInMB MB'
            ),
            _buildInfoRow('Path', widget.imageFile.path.split('/').last),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              'Quality Tips:',
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            _buildTip('• Ensure text is clearly visible'),
            _buildTip('• Avoid blurry or dark images'),
            _buildTip('• Keep receipt flat and straight'),
            _buildTip('• Include all items in frame'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: AppTextStyles.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTip(String text) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        text,
        style: AppTextStyles.bodySmall.copyWith(
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}