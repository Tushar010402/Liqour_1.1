import 'package:flutter/material.dart';
import '../../../core/services/image_preprocessing_service.dart';

/// Real-time image quality indicator widget
///
/// Displays quality score with color-coded badge:
/// - Green: Excellent (60+) - Sharp image, perfect for OCR
/// - Yellow: Good (40-59) - Good clarity, OCR will work well
/// - Orange: Acceptable (20-39) - Minor blur, OCR may have issues
/// - Red: Too Blurry (<20) - Recommend retaking
///
/// Usage:
/// ```dart
/// ImageQualityIndicator(
///   blurScore: blurScoreResult,
///   showScore: true,
///   onRetake: () => _retakePhoto(),
/// )
/// ```
class ImageQualityIndicator extends StatelessWidget {
  /// The blur score result from image analysis
  final BlurScoreResult? blurScore;

  /// Whether quality is being analyzed
  final bool isAnalyzing;

  /// Whether to show the numeric score
  final bool showScore;

  /// Whether to show the quality message
  final bool showMessage;

  /// Callback when user wants to retake photo
  final VoidCallback? onRetake;

  /// Size variant: compact, normal, or expanded
  final ImageQualityIndicatorSize size;

  const ImageQualityIndicator({
    super.key,
    this.blurScore,
    this.isAnalyzing = false,
    this.showScore = true,
    this.showMessage = true,
    this.onRetake,
    this.size = ImageQualityIndicatorSize.normal,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (isAnalyzing) {
      return _buildAnalyzingState(cs);
    }

    if (blurScore == null) {
      return const SizedBox.shrink();
    }

    switch (size) {
      case ImageQualityIndicatorSize.compact:
        return _buildCompactIndicator();
      case ImageQualityIndicatorSize.normal:
        return _buildNormalIndicator(cs);
      case ImageQualityIndicatorSize.expanded:
        return _buildExpandedIndicator(cs);
    }
  }

  Widget _buildAnalyzingState(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Analyzing...',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactIndicator() {
    final score = blurScore!;
    final color = Color(score.quality.colorValue);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getQualityIcon(score.quality),
            size: 14,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            score.quality.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNormalIndicator(ColorScheme cs) {
    final score = blurScore!;
    final color = Color(score.quality.colorValue);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _getQualityIcon(score.quality),
              size: 20,
              color: color,
            ),
          ),
          const SizedBox(width: 12),

          // Text content
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    score.quality.label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  if (showScore) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        score.scorePercentage,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (showMessage) ...[
                const SizedBox(height: 2),
                Text(
                  score.message,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),

          // Retake button for blurry images
          if (onRetake != null && score.quality == BlurQuality.tooBlurry) ...[
            const SizedBox(width: 12),
            IconButton(
              onPressed: onRetake,
              icon: const Icon(Icons.refresh),
              color: color,
              tooltip: 'Retake photo',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExpandedIndicator(ColorScheme cs) {
    final score = blurScore!;
    final color = Color(score.quality.colorValue);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Quality circle
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  color.withOpacity(0.8),
                  color,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _getQualityIcon(score.quality),
                    size: 32,
                    color: Colors.white,
                  ),
                  if (showScore)
                    Text(
                      score.scorePercentage,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Quality label
          Text(
            score.quality.label,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 4),

          // Message
          if (showMessage)
            Text(
              score.message,
              style: TextStyle(
                fontSize: 14,
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),

          // Retake button for blurry images
          if (onRetake != null && score.quality == BlurQuality.tooBlurry) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetake,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Retake Photo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  IconData _getQualityIcon(BlurQuality quality) {
    switch (quality) {
      case BlurQuality.excellent:
        return Icons.check_circle;
      case BlurQuality.good:
        return Icons.check_circle_outline;
      case BlurQuality.acceptable:
        return Icons.warning_amber;
      case BlurQuality.tooBlurry:
        return Icons.error_outline;
    }
  }
}

/// Size variants for the quality indicator
enum ImageQualityIndicatorSize {
  /// Small badge - just icon and label
  compact,

  /// Standard size - icon, label, score, message
  normal,

  /// Large card - full details with prominent display
  expanded,
}

/// Quality badge widget for thumbnails
///
/// Shows a small colored badge in the corner of image thumbnails
/// to indicate the image quality at a glance.
class ImageQualityBadge extends StatelessWidget {
  final BlurQuality quality;
  final double size;

  const ImageQualityBadge({
    super.key,
    required this.quality,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(quality.colorValue);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Icon(
          _getIcon(),
          size: size * 0.6,
          color: Colors.white,
        ),
      ),
    );
  }

  IconData _getIcon() {
    switch (quality) {
      case BlurQuality.excellent:
      case BlurQuality.good:
        return Icons.check;
      case BlurQuality.acceptable:
        return Icons.remove;
      case BlurQuality.tooBlurry:
        return Icons.close;
    }
  }
}
