import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../../../core/utils/app_logger.dart';
import '../../sales/screens/multi_photo_stock_ocr_screen.dart';

/// Ready-to-use button for Multi-Photo OCR Stock Creation
/// Just add this widget to your inventory/stock screen!
///
/// Example usage:
/// ```dart
/// appBar: AppBar(
///   actions: [
///     MultiPhotoOCRButton(
///       shopId: currentShopId,
///       onSuccess: () => _refreshStock(),
///     ),
///   ],
/// ),
/// ```
class MultiPhotoOCRButton extends ConsumerWidget {
  /// The shop ID to add stock to (REQUIRED)
  final String? shopId;

  /// Callback when stock is successfully added
  final VoidCallback? onSuccess;

  /// Optional: Custom button style
  final ButtonStyle? style;

  /// Optional: Show as icon button (default: true)
  final bool iconButton;

  /// Optional: Button text (only used when iconButton = false)
  final String buttonText;

  const MultiPhotoOCRButton({
    super.key,
    required this.shopId,
    this.onSuccess,
    this.style,
    this.iconButton = true,
    this.buttonText = 'Smart Stock from Photos',
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (iconButton) {
      return IconButton(
        icon: const Icon(Icons.camera_enhance),
        tooltip: 'Smart Stock from Photos',
        onPressed: () => _openOCRScreen(context, ref),
      );
    }

    return ElevatedButton.icon(
      icon: const Icon(Icons.camera_enhance),
      label: Text(buttonText),
      onPressed: () => _openOCRScreen(context, ref),
      style: style,
    );
  }

  Future<void> _openOCRScreen(BuildContext context, WidgetRef ref) async {
    // Validate shop ID
    if (shopId == null || shopId!.isEmpty) {
      SnackbarHelper.showError(
        context,
        'Please select a shop first',
      );
      return;
    }

    try {
      // Navigate to Multi-Photo OCR Screen
      final result = await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(
          builder: (context) => MultiPhotoStockOCRScreen(
            shopId: shopId!,
          ),
        ),
      );

      // Handle result
      if (result != null) {
        _handleResult(context, result);
      }
    } catch (e, stackTrace) {
      AppLogger.error('Failed to open Multi-Photo OCR screen', e, stackTrace);

      if (context.mounted) {
        SnackbarHelper.showError(
          context,
          'Could not open smart stock feature',
        );
      }
    }
  }

  void _handleResult(BuildContext context, Map<String, dynamic> result) {
    final photosProcessed = result['photos_processed'] ?? 0;
    final itemsAdded = result['items_added'] ?? 0;
    final itemsFailed = result['items_failed'] ?? 0;

    // Show success message
    if (itemsAdded > 0) {
      SnackbarHelper.showSuccess(
        context,
        '✅ Success! Added $itemsAdded items from $photosProcessed photo${photosProcessed > 1 ? 's' : ''}',
      );

      // Call success callback
      onSuccess?.call();
    }

    // Show warning for failed items
    if (itemsFailed > 0 && itemsAdded > 0) {
      SnackbarHelper.showWarning(
        context,
        '⚠️ Note: $itemsFailed item${itemsFailed > 1 ? 's' : ''} could not be matched automatically',
      );
    }

    // Show error if nothing was added
    if (itemsAdded == 0 && itemsFailed > 0) {
      SnackbarHelper.showError(
        context,
        '❌ No items could be matched. Please check product catalog.',
      );
    }

    // Log result
    AppLogger.info(
      'Multi-Photo OCR completed: '
      '$photosProcessed photos, '
      '$itemsAdded added, '
      '$itemsFailed failed',
    );
  }
}

/// Floating Action Button variant
class MultiPhotoOCRFAB extends ConsumerWidget {
  final String? shopId;
  final VoidCallback? onSuccess;
  final String? label;
  final bool extended;

  const MultiPhotoOCRFAB({
    super.key,
    required this.shopId,
    this.onSuccess,
    this.label,
    this.extended = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (extended && label != null) {
      return FloatingActionButton.extended(
        icon: const Icon(Icons.camera_enhance),
        label: Text(label!),
        onPressed: () => MultiPhotoOCRButton(
          shopId: shopId,
          onSuccess: onSuccess,
        )._openOCRScreen(context, ref),
      );
    }

    return FloatingActionButton(
      tooltip: 'Smart Stock from Photos',
      onPressed: () => MultiPhotoOCRButton(
        shopId: shopId,
        onSuccess: onSuccess,
      )._openOCRScreen(context, ref),
      child: const Icon(Icons.camera_enhance),
    );
  }
}

/// List tile variant (for menus/drawers)
class MultiPhotoOCRListTile extends ConsumerWidget {
  final String? shopId;
  final VoidCallback? onSuccess;

  const MultiPhotoOCRListTile({
    super.key,
    required this.shopId,
    this.onSuccess,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const Icon(Icons.camera_enhance),
      title: const Text('Smart Stock from Photos'),
      subtitle: const Text('Scan receipts to add stock automatically'),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: () => MultiPhotoOCRButton(
        shopId: shopId,
        onSuccess: onSuccess,
      )._openOCRScreen(context, ref),
    );
  }
}

/// Quick action card variant (for dashboards)
class MultiPhotoOCRCard extends ConsumerWidget {
  final String? shopId;
  final VoidCallback? onSuccess;

  const MultiPhotoOCRCard({
    super.key,
    required this.shopId,
    this.onSuccess,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 4,
      child: InkWell(
        onTap: () => MultiPhotoOCRButton(
          shopId: shopId,
          onSuccess: onSuccess,
        )._openOCRScreen(context, ref),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.camera_enhance,
                  size: 32,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Smart Stock',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Scan up to 10 receipts',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
