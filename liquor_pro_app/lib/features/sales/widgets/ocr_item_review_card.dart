import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../models/ocr_models.dart';

/// Card widget for reviewing OCR extracted items
class OCRItemReviewCard extends StatelessWidget {
  final OCRExtractedItem item;
  final VoidCallback onConfirm;
  final VoidCallback onEdit;
  final VoidCallback onReject;

  const OCRItemReviewCard({
    super.key,
    required this.item,
    required this.onConfirm,
    required this.onEdit,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _getBorderColor(),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header with confidence indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _getHeaderColor(),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10),
              ),
            ),
            child: Row(
              children: [
                // Confidence indicator
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _getConfidenceColor().withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      '${item.matchConfidence.toInt()}%',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: _getConfidenceColor(),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Item details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getProductName(),
                        style: AppTextStyles.bodyLarge.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _getMatchStatus(),
                        style: AppTextStyles.bodySmall.copyWith(
                          color: _getConfidenceColor(),
                        ),
                      ),
                    ],
                  ),
                ),
                // Status icon
                _buildStatusIcon(),
              ],
            ),
          ),

          // Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Extracted text
                _buildExtractedText(),
                const SizedBox(height: 12),

                // Parsed details
                _buildParsedDetails(),
                const SizedBox(height: 12),

                // Action buttons
                _buildActionButtons(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExtractedText() {
    return Builder(builder: (context) {
      final cs = Theme.of(context).colorScheme;
      return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: cs.outline,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Extracted Text',
            style: AppTextStyles.bodySmall.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.extractedText,
            style: AppTextStyles.bodyMedium,
          ),
        ],
      ),
    );
    });
  }

  Widget _buildParsedDetails() {
    return Row(
      children: [
        // Brand
        if (item.brandText != null)
          Expanded(
            child: _buildDetailChip(
              icon: Icons.label_outline,
              label: 'Brand',
              value: item.brandText!,
            ),
          ),
        if (item.brandText != null && item.sizeText != null)
          const SizedBox(width: 8),

        // Size
        if (item.sizeText != null)
          Expanded(
            child: _buildDetailChip(
              icon: Icons.local_drink_outlined,
              label: 'Size',
              value: item.sizeText!,
            ),
          ),
      ],
    );
  }

  Widget _buildDetailChip({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Builder(builder: (context) {
      final cs = Theme.of(context).colorScheme;
      return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: cs.primary.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: cs.primary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: cs.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
                Text(
                  value,
                  style: AppTextStyles.bodySmall.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    });
  }

  Widget _buildActionButtons() {
    // If already confirmed or rejected, show status
    if (item.isConfirmed) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle,
              color: AppColors.success,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              'Confirmed',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.success,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    if (item.isRejected) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cancel,
              color: AppColors.error,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              'Rejected',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    // Show action buttons
    return Row(
      children: [
        // Reject button
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onReject,
            icon: const Icon(Icons.close, size: 18),
            label: const Text('Reject'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: BorderSide(color: AppColors.error),
              padding: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Edit button
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.info,
              side: BorderSide(color: AppColors.info),
              padding: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Confirm button
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: onConfirm,
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Confirm'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusIcon() {
    if (item.isConfirmed) {
      return Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.check,
          color: AppColors.success,
          size: 16,
        ),
      );
    }

    if (item.isRejected) {
      return Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.close,
          color: AppColors.error,
          size: 16,
        ),
      );
    }

    if (item.matchedProductId != null) {
      return Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: _getConfidenceColor().withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.link,
          color: _getConfidenceColor(),
          size: 16,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.2),
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.help_outline,
        color: AppColors.warning,
        size: 16,
      ),
    );
  }

  String _getProductName() {
    if (item.matchedProduct != null) {
      return item.matchedProduct!.name;
    }
    if (item.brandText != null) {
      return '${item.brandText} ${item.sizeText ?? ''}';
    }
    return 'Unmatched Item';
  }

  String _getMatchStatus() {
    if (item.matchedProductId == null) {
      return 'No match found';
    }

    switch (item.matchMethod) {
      case 'exact':
        return 'Exact match';
      case 'fuzzy':
        return 'Fuzzy match';
      case 'alias':
        return 'Matched by alias';
      case 'pattern':
        return 'Pattern match';
      default:
        return 'Matched';
    }
  }

  Color _getBorderColor() {
    if (item.isConfirmed) return AppColors.success;
    if (item.isRejected) return AppColors.error;
    if (item.matchedProductId == null) return AppColors.warning;
    if (item.matchConfidence >= 95) return AppColors.success;
    if (item.matchConfidence >= 75) return AppColors.info;
    return AppColors.warning;
  }

  Color _getHeaderColor() {
    if (item.isConfirmed) return AppColors.success.withValues(alpha: 0.1);
    if (item.isRejected) return AppColors.error.withValues(alpha: 0.1);
    if (item.matchedProductId == null) return AppColors.warning.withValues(alpha: 0.1);
    if (item.matchConfidence >= 95) return AppColors.success.withValues(alpha: 0.1);
    if (item.matchConfidence >= 75) return AppColors.info.withValues(alpha: 0.1);
    return AppColors.warning.withValues(alpha: 0.1);
  }

  Color _getConfidenceColor() {
    if (item.matchConfidence >= 95) return AppColors.success;
    if (item.matchConfidence >= 75) return AppColors.info;
    if (item.matchConfidence >= 50) return AppColors.warning;
    return AppColors.error;
  }
}