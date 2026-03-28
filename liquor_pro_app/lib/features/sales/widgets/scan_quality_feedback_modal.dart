/// Scan Quality Feedback Modal
///
/// Shows when captured image quality is poor and provides:
/// - Quality score and issues list
/// - Issue-specific tips for improvement
/// - Options to retry or use anyway
library;

import 'dart:io';
import 'package:flutter/material.dart';
import '../models/scan_quality_models.dart';

/// Shows quality feedback with tips and retry option
class ScanQualityFeedbackModal extends StatelessWidget {
  /// The captured image file
  final File imageFile;

  /// Quality assessment result
  final ScanQualityResult qualityResult;

  /// Callback when user chooses to retry
  final VoidCallback onRetry;

  /// Callback when user chooses to use anyway
  final VoidCallback onUseAnyway;

  /// Callback when user cancels
  final VoidCallback onCancel;

  const ScanQualityFeedbackModal({
    super.key,
    required this.imageFile,
    required this.qualityResult,
    required this.onRetry,
    required this.onUseAnyway,
    required this.onCancel,
  });

  /// Show as a bottom sheet
  static Future<void> show({
    required BuildContext context,
    required File imageFile,
    required ScanQualityResult qualityResult,
    required VoidCallback onRetry,
    required VoidCallback onUseAnyway,
    required VoidCallback onCancel,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => ScanQualityFeedbackModal(
        imageFile: imageFile,
        qualityResult: qualityResult,
        onRetry: () {
          Navigator.pop(context);
          onRetry();
        },
        onUseAnyway: () {
          Navigator.pop(context);
          onUseAnyway();
        },
        onCancel: () {
          Navigator.pop(context);
          onCancel();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final issues = qualityResult.issues;
    final score = qualityResult.overallScore.round();

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header with warning icon
            _buildHeader(score),

            // Image preview with score overlay
            _buildImagePreview(),

            // Issues list with tips
            if (issues.isNotEmpty) _buildIssuesList(issues),

            // Action buttons
            _buildActionButtons(context),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(int score) {
    return Builder(builder: (context) {
      final cs = Theme.of(context).colorScheme;
      return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.warning_amber_rounded,
              color: Colors.orange[700],
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Image Quality Issue',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                ),
                Text(
                  'Score: $score/100 - ${qualityResult.overallQuality.name}',
                  style: TextStyle(
                    fontSize: 14,
                    color: _getScoreColor(score),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: cs.onSurfaceVariant),
            onPressed: onCancel,
          ),
        ],
      ),
    );
    });
  }

  Widget _buildImagePreview() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      height: 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              imageFile,
              fit: BoxFit.cover,
            ),
            // Score badge
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _getScoreColor(qualityResult.overallScore.round()),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.speed, color: Colors.white, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      '${qualityResult.overallScore.round()}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Issue badges
            Positioned(
              bottom: 8,
              left: 8,
              right: 8,
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: qualityResult.issues.map((issue) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          issue.icon,
                          color: Colors.white,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          issue.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIssuesList(List<QualityIssue> issues) {
    return Builder(builder: (context) {
      final cs = Theme.of(context).colorScheme;
      return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tips_and_updates, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                'Tips to improve:',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...issues.expand((issue) {
            return issue.tips.take(2).map((tip) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        tip,
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            });
          }),
        ],
      ),
    );
    });
  }

  Widget _buildActionButtons(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          // Try Again button (primary)
          Expanded(
            flex: 3,
            child: ElevatedButton.icon(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.camera_alt, size: 20),
              label: const Text(
                'Try Again',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Use Anyway button (secondary)
          Expanded(
            flex: 2,
            child: OutlinedButton(
              onPressed: onUseAnyway,
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.onSurfaceVariant,
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: BorderSide(color: cs.outline),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Use Anyway',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getScoreColor(int score) {
    if (score >= 60) return Colors.green;
    if (score >= 40) return Colors.amber[700]!;
    if (score >= 20) return Colors.orange;
    return Colors.red;
  }
}

/// Extension to get quality tier name
extension QualityTierName on QualityTier {
  String get name {
    switch (this) {
      case QualityTier.excellent:
        return 'Excellent';
      case QualityTier.good:
        return 'Good';
      case QualityTier.acceptable:
        return 'Acceptable';
      case QualityTier.poor:
        return 'Poor';
    }
  }
}

/// Extension to get blur quality tier name
extension BlurQualityTierName on BlurQualityTier {
  String get name {
    switch (this) {
      case BlurQualityTier.excellent:
        return 'Sharp';
      case BlurQualityTier.good:
        return 'Good';
      case BlurQualityTier.acceptable:
        return 'OK';
      case BlurQualityTier.tooBlurry:
        return 'Blurry';
    }
  }
}
