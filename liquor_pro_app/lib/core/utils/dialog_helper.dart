import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'haptic_feedback_helper.dart';

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
    HapticFeedbackHelper.medium();

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
                color: isDangerous ? Colors.red : confirmColor ?? Theme.of(context).primaryColor,
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
            color: Colors.grey[700],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              HapticFeedbackHelper.light();
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
              HapticFeedbackHelper.medium();
              Navigator.of(context).pop(true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isDangerous
                  ? Colors.red
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
    HapticFeedbackHelper.warning();

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
    HapticFeedbackHelper.light();

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
                color: Colors.blue,
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
            color: Colors.grey[700],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              HapticFeedbackHelper.light();
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
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
    HapticFeedbackHelper.error();

    return _showBaseDialog(
      context: context,
      content: AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            const Icon(
              Icons.error_outline,
              color: Colors.red,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.red,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey[700],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              HapticFeedbackHelper.light();
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
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
    HapticFeedbackHelper.success();

    return _showBaseDialog(
      context: context,
      content: AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            const Icon(
              Icons.check_circle_outline,
              color: Colors.green,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.green,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey[700],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              HapticFeedbackHelper.light();
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
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
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
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
    HapticFeedbackHelper.light();

    return showModalBottomSheet<T>(
      context: context,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
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
    HapticFeedbackHelper.light();

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
                HapticFeedbackHelper.light();
                Navigator.of(context).pop(option);
              },
            );
          }).toList(),
        ),
      ),
    );
  }
}
