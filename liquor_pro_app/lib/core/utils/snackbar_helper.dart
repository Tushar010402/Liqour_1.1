import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'haptic_feedback_helper.dart';

/// Snackbar Helper - Best Practice Notifications
/// Centralized snackbar/toast management for consistent UX
class SnackbarHelper {
  // Private constructor to prevent instantiation
  SnackbarHelper._();

  /// Default duration for snackbars
  static const Duration _defaultDuration = Duration(seconds: 3);

  /// Base method for showing snackbars
  static void _showSnackbar({
    required BuildContext context,
    required String message,
    required Color backgroundColor,
    required IconData icon,
    Color? iconColor,
    Duration? duration,
    SnackBarAction? action,
    VoidCallback? onTap,
  }) {
    final snackBar = SnackBar(
      content: Row(
        children: [
          Icon(
            icon,
            color: iconColor ?? Colors.white,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      backgroundColor: backgroundColor,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      margin: const EdgeInsets.all(16),
      duration: duration ?? _defaultDuration,
      action: action,
    );

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(snackBar);

    if (onTap != null) {
      onTap();
    }
  }

  /// Success snackbar - For successful operations
  static void success({
    required BuildContext context,
    required String message,
    Duration? duration,
    SnackBarAction? action,
  }) {
    HapticFeedbackHelper.success();
    _showSnackbar(
      context: context,
      message: message,
      backgroundColor: Colors.green.shade600,
      icon: Icons.check_circle,
      duration: duration,
      action: action,
    );
  }

  /// Error snackbar - For errors and failures
  static void error({
    required BuildContext context,
    required String message,
    Duration? duration,
    SnackBarAction? action,
  }) {
    HapticFeedbackHelper.error();
    _showSnackbar(
      context: context,
      message: message,
      backgroundColor: Colors.red.shade600,
      icon: Icons.error,
      duration: duration,
      action: action,
    );
  }

  /// Warning snackbar - For warnings and alerts
  static void warning({
    required BuildContext context,
    required String message,
    Duration? duration,
    SnackBarAction? action,
  }) {
    HapticFeedbackHelper.warning();
    _showSnackbar(
      context: context,
      message: message,
      backgroundColor: Colors.orange.shade600,
      icon: Icons.warning,
      duration: duration,
      action: action,
    );
  }

  /// Info snackbar - For general information
  static void info({
    required BuildContext context,
    required String message,
    Duration? duration,
    SnackBarAction? action,
  }) {
    HapticFeedbackHelper.light();
    _showSnackbar(
      context: context,
      message: message,
      backgroundColor: Colors.blue.shade600,
      icon: Icons.info,
      duration: duration,
      action: action,
    );
  }

  /// Loading snackbar - For ongoing operations
  static void loading({
    required BuildContext context,
    required String message,
  }) {
    final snackBar = SnackBar(
      content: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      backgroundColor: Colors.grey.shade800,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      margin: const EdgeInsets.all(16),
      duration: const Duration(days: 1), // Keep visible until dismissed
    );

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(snackBar);
  }

  /// Hide current snackbar
  static void hide(BuildContext context) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  /// Custom snackbar - For custom use cases
  static void custom({
    required BuildContext context,
    required String message,
    required Color backgroundColor,
    required IconData icon,
    Color? iconColor,
    Duration? duration,
    SnackBarAction? action,
  }) {
    _showSnackbar(
      context: context,
      message: message,
      backgroundColor: backgroundColor,
      icon: icon,
      iconColor: iconColor,
      duration: duration,
      action: action,
    );
  }

  /// Show snackbar with action button
  static void withAction({
    required BuildContext context,
    required String message,
    required String actionLabel,
    required VoidCallback onActionPressed,
    Color? backgroundColor,
    IconData? icon,
  }) {
    HapticFeedbackHelper.light();
    _showSnackbar(
      context: context,
      message: message,
      backgroundColor: backgroundColor ?? Colors.grey.shade800,
      icon: icon ?? Icons.notifications,
      action: SnackBarAction(
        label: actionLabel,
        textColor: Colors.white,
        onPressed: onActionPressed,
      ),
    );
  }

  /// Network error snackbar with retry action
  static void networkError({
    required BuildContext context,
    String message = 'No internet connection',
    VoidCallback? onRetry,
  }) {
    HapticFeedbackHelper.error();
    _showSnackbar(
      context: context,
      message: message,
      backgroundColor: Colors.red.shade600,
      icon: Icons.wifi_off,
      duration: const Duration(seconds: 5),
      action: onRetry != null
          ? SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: onRetry,
            )
          : null,
    );
  }

  /// Validation error snackbar
  static void validationError({
    required BuildContext context,
    required String message,
  }) {
    HapticFeedbackHelper.warning();
    _showSnackbar(
      context: context,
      message: message,
      backgroundColor: Colors.orange.shade600,
      icon: Icons.error_outline,
      duration: const Duration(seconds: 4),
    );
  }

  /// Deletion confirmation snackbar with undo
  static void deletedWithUndo({
    required BuildContext context,
    required String itemName,
    required VoidCallback onUndo,
  }) {
    HapticFeedbackHelper.heavy();
    _showSnackbar(
      context: context,
      message: '$itemName deleted',
      backgroundColor: Colors.grey.shade800,
      icon: Icons.delete,
      duration: const Duration(seconds: 4),
      action: SnackBarAction(
        label: 'Undo',
        textColor: Colors.white,
        onPressed: onUndo,
      ),
    );
  }

  /// Saved/Updated confirmation
  static void saved({
    required BuildContext context,
    String message = 'Changes saved successfully',
  }) {
    HapticFeedbackHelper.success();
    _showSnackbar(
      context: context,
      message: message,
      backgroundColor: Colors.green.shade600,
      icon: Icons.check_circle,
      duration: const Duration(seconds: 2),
    );
  }

  /// Copied to clipboard confirmation
  static void copied({
    required BuildContext context,
    String message = 'Copied to clipboard',
  }) {
    HapticFeedbackHelper.light();
    _showSnackbar(
      context: context,
      message: message,
      backgroundColor: Colors.grey.shade800,
      icon: Icons.content_copy,
      duration: const Duration(seconds: 2),
    );
  }
}
