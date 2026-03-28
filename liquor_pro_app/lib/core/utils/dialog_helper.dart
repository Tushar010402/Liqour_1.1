import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import 'haptic_feedback.dart';

/// Dialog Helper - Best Practice Dialogs
/// Centralized dialog management for consistent UX
class DialogHelper {
  // Private constructor to prevent instantiation
  DialogHelper._();

  /// Base dialog builder
  static Future<T?> _showBaseDialog<T>({
    required BuildContext context,
    required Widget content,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (context) => content,
    );
  }

  /// Confirmation dialog - For user confirmations
  static Future<bool?> confirm({
    required BuildContext context,
    required String title,
    required String message,
    String confirmText = 'Confirm',
    String cancelText = 'Cancel',
    Color? confirmColor,
    IconData? icon,
    bool isDangerous = false,
  }) async {
    HapticFeedbackUtil.medium();
    final cs = Theme.of(context).colorScheme;

    return _showBaseDialog<bool>(
      context: context,
      content: AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                color: isDangerous ? AppColors.error : confirmColor ?? Theme.of(context).primaryColor,
                size: 28,
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: TextStyle(
            fontSize: 16,
            color: cs.onSurface,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              HapticFeedbackUtil.light();
              Navigator.of(context).pop(false);
            },
            child: Text(
              cancelText,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              HapticFeedbackUtil.medium();
              Navigator.of(context).pop(true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isDangerous
                  ? AppColors.error
                  : (confirmColor ?? Theme.of(context).primaryColor),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: Text(
              confirmText,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Delete confirmation dialog
  static Future<bool?> confirmDelete({
    required BuildContext context,
    required String itemName,
    String? message,
  }) {
    HapticFeedbackUtil.warning();

    return confirm(
      context: context,
      title: 'Delete $itemName?',
      message: message ?? 'This action cannot be undone. Are you sure you want to delete this item?',
      confirmText: 'Delete',
      cancelText: 'Cancel',
      icon: Icons.delete_outline,
      isDangerous: true,
    );
  }

  /// Info dialog - For information display
  static Future<void> info({
    required BuildContext context,
    required String title,
    required String message,
    String buttonText = 'OK',
    IconData? icon,
  }) {
    HapticFeedbackUtil.light();
    final cs = Theme.of(context).colorScheme;

    return _showBaseDialog(
      context: context,
      content: AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                color: AppColors.info,
                size: 28,
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: TextStyle(
            fontSize: 16,
            color: cs.onSurface,
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              HapticFeedbackUtil.light();
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.info,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: Text(
              buttonText,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Error dialog - For error display
  static Future<void> error({
    required BuildContext context,
    String title = 'Error',
    required String message,
    String buttonText = 'OK',
  }) {
    HapticFeedbackUtil.error();
    final cs = Theme.of(context).colorScheme;

    return _showBaseDialog(
      context: context,
      content: AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Icon(
              Icons.error_outline,
              color: AppColors.error,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppColors.error,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: TextStyle(
            fontSize: 16,
            color: cs.onSurface,
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              HapticFeedbackUtil.light();
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: Text(
              buttonText,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Success dialog - For success confirmation
  static Future<void> success({
    required BuildContext context,
    required String title,
    required String message,
    String buttonText = 'OK',
  }) {
    HapticFeedbackUtil.success();
    final cs = Theme.of(context).colorScheme;

    return _showBaseDialog(
      context: context,
      content: AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Icon(
              Icons.check_circle_outline,
              color: AppColors.success,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppColors.success,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: TextStyle(
            fontSize: 16,
            color: cs.onSurface,
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              HapticFeedbackUtil.light();
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: Text(
              buttonText,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Loading dialog - For ongoing operations
  static void showLoading({
    required BuildContext context,
    String message = 'Loading...',
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Hide loading dialog
  static void hideLoading(BuildContext context) {
    Navigator.of(context).pop();
  }

  /// Custom dialog - For custom content
  static Future<T?> custom<T>({
    required BuildContext context,
    required Widget child,
    bool barrierDismissible = true,
    EdgeInsets? padding,
  }) {
    return _showBaseDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      content: Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: padding ?? const EdgeInsets.all(24),
          child: child,
        ),
      ),
    );
  }

  /// Bottom sheet dialog - For actions from bottom
  static Future<T?> bottomSheet<T>({
    required BuildContext context,
    required Widget child,
    bool isDismissible = true,
    bool enableDrag = true,
  }) {
    HapticFeedbackUtil.light();
    final cs = Theme.of(context).colorScheme;

    return showModalBottomSheet<T>(
      context: context,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }

  /// Multiple choice dialog
  static Future<T?> choice<T>({
    required BuildContext context,
    required String title,
    required List<T> options,
    required String Function(T) optionLabel,
    IconData Function(T)? optionIcon,
  }) {
    HapticFeedbackUtil.light();

    return _showBaseDialog<T>(
      context: context,
      content: AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((option) {
            return ListTile(
              leading: optionIcon != null
                  ? Icon(optionIcon(option))
                  : null,
              title: Text(optionLabel(option)),
              onTap: () {
                HapticFeedbackUtil.light();
                Navigator.of(context).pop(option);
              },
            );
          }).toList(),
        ),
      ),
    );
  }
}
