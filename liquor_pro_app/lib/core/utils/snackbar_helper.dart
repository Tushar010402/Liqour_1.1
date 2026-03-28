import 'package:flutter/material.dart';
import 'error_parser.dart';

/// Snackbar Helper - Provides consistent snackbar notifications
/// with enhanced error display and action buttons
class SnackbarHelper {
  // Private constructor to prevent instantiation
  SnackbarHelper._();

  /// Show success message
  static void showSuccess(BuildContext context, String message) {
    _showSnackbar(
      context: context,
      message: message,
      backgroundColor: Colors.green,
      icon: Icons.check_circle_outline,
    );
  }

  /// Show error message
  static void showError(BuildContext context, String message) {
    _showSnackbar(
      context: context,
      message: message,
      backgroundColor: Colors.red,
      icon: Icons.error_outline,
    );
  }

  /// Show info message
  static void showInfo(BuildContext context, String message) {
    _showSnackbar(
      context: context,
      message: message,
      backgroundColor: Colors.blue,
      icon: Icons.info_outline,
    );
  }

  /// Show warning message
  static void showWarning(BuildContext context, String message) {
    _showSnackbar(
      context: context,
      message: message,
      backgroundColor: Colors.orange,
      icon: Icons.warning_amber_outlined,
    );
  }

  /// Show parsed error with user-friendly message
  /// Automatically parses backend errors into readable format
  static void showParsedError(BuildContext context, dynamic error) {
    final errorInfo = ErrorParser.parse(error);

    _showSnackbar(
      context: context,
      message: errorInfo.userMessage,
      backgroundColor: _getBackgroundColorForErrorIcon(errorInfo.icon),
      icon: _getIconDataForErrorIcon(errorInfo.icon),
      duration: const Duration(seconds: 5),
    );
  }

  /// Show error with action button
  static void showErrorWithAction({
    required BuildContext context,
    required String message,
    required String actionLabel,
    required VoidCallback onAction,
    Duration duration = const Duration(seconds: 4),
  }) {
    try {
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) {
        debugPrint('⚠️ [SnackbarHelper] Context no longer valid, skipping: $message');
        return;
      }

      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
          duration: duration,
          action: SnackBarAction(
            label: actionLabel,
            textColor: Colors.white,
            onPressed: onAction,
          ),
        ),
      );
    } catch (e) {
      debugPrint('⚠️ [SnackbarHelper] Failed to show snackbar with action: $e');
    }
  }

  /// Show balance error with available balance info
  static void showBalanceError({
    required BuildContext context,
    required double requested,
    required double available,
    VoidCallback? onRequestMax,
  }) {
    final message = '💰 Insufficient Balance\n'
        'Requested: ₹${_formatCurrency(requested)} | Available: ₹${_formatCurrency(available)}\n\n'
        '💡 ${available > 0 ? "Try requesting less" : "Contact your manager for cash"}';

    if (onRequestMax != null && available > 0) {
      showErrorWithAction(
        context: context,
        message: message,
        actionLabel: 'Request Max',
        onAction: onRequestMax,
        duration: const Duration(seconds: 6),
      );
    } else {
      _showSnackbar(
        context: context,
        message: message,
        backgroundColor: Colors.orange.shade700,
        icon: Icons.account_balance_wallet_outlined,
        duration: const Duration(seconds: 5),
      );
    }
  }

  /// Show validation error
  static void showValidationError(BuildContext context, String field, String issue) {
    _showSnackbar(
      context: context,
      message: '⚠️ Validation Error\n$field: $issue',
      backgroundColor: Colors.orange,
      icon: Icons.warning_amber_outlined,
      duration: const Duration(seconds: 4),
    );
  }

  /// Show network error with retry option
  static void showNetworkError({
    required BuildContext context,
    VoidCallback? onRetry,
  }) {
    final message = '📡 Network Error\n'
        'Unable to connect to server. Check your connection.';

    if (onRetry != null) {
      showErrorWithAction(
        context: context,
        message: message,
        actionLabel: 'Retry',
        onAction: onRetry,
      );
    } else {
      _showSnackbar(
        context: context,
        message: message,
        backgroundColor: Colors.red.shade700,
        icon: Icons.wifi_off,
        duration: const Duration(seconds: 4),
      );
    }
  }

  /// Show loading snackbar (dismissable)
  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? showLoading(
    BuildContext context,
    String message,
  ) {
    try {
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) {
        debugPrint('⚠️ [SnackbarHelper] Context no longer valid, skipping loading: $message');
        return null;
      }

      return messenger.showSnackBar(
        SnackBar(
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
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.blue.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
          duration: const Duration(days: 1), // Long duration, dismiss manually
        ),
      );
    } catch (e) {
      debugPrint('⚠️ [SnackbarHelper] Failed to show loading snackbar: $e');
      return null;
    }
  }

  /// Hide current snackbar
  static void hide(BuildContext context) {
    try {
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.hideCurrentSnackBar();
    } catch (e) {
      debugPrint('⚠️ [SnackbarHelper] Failed to hide snackbar: $e');
    }
  }

  // Alias methods for backward compatibility (positional args)
  static void error(BuildContext context, String message) => showError(context, message);
  static void success(BuildContext context, String message) => showSuccess(context, message);
  static void info(BuildContext context, String message) => showInfo(context, message);
  static void warning(BuildContext context, String message) => showWarning(context, message);
  static void copied(BuildContext context, [String message = 'Copied to clipboard']) => showSuccess(context, message);

  /// Base method for showing snackbars
  static void _showSnackbar({
    required BuildContext context,
    required String message,
    required Color backgroundColor,
    required IconData icon,
    Duration duration = const Duration(seconds: 3),
  }) {
    // CRITICAL: Check if context is still mounted to prevent "deactivated widget" errors
    // This happens when async operations complete after the widget is disposed
    try {
      // Check if the context is still valid by testing if we can find ScaffoldMessenger
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) {
        // Context is no longer valid, silently skip showing snackbar
        debugPrint('⚠️ [SnackbarHelper] Context no longer valid, skipping: $message');
        return;
      }

      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: backgroundColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
          duration: duration,
        ),
      );
    } catch (e) {
      // Silently handle any errors when showing snackbar on deactivated widget
      debugPrint('⚠️ [SnackbarHelper] Failed to show snackbar: $e');
    }
  }

  /// Get background color for error icon
  static Color _getBackgroundColorForErrorIcon(ErrorIcon icon) {
    switch (icon) {
      case ErrorIcon.balance:
        return Colors.orange.shade700;
      case ErrorIcon.network:
        return Colors.red.shade700;
      case ErrorIcon.validation:
        return Colors.orange;
      case ErrorIcon.unauthorized:
        return Colors.red.shade900;
      case ErrorIcon.server:
        return Colors.red.shade800;
      case ErrorIcon.error:
      default:
        return Colors.red;
    }
  }

  /// Get icon data for error icon
  static IconData _getIconDataForErrorIcon(ErrorIcon icon) {
    switch (icon) {
      case ErrorIcon.balance:
        return Icons.account_balance_wallet_outlined;
      case ErrorIcon.network:
        return Icons.wifi_off;
      case ErrorIcon.validation:
        return Icons.warning_amber_outlined;
      case ErrorIcon.unauthorized:
        return Icons.lock_outline;
      case ErrorIcon.server:
        return Icons.cloud_off;
      case ErrorIcon.error:
      default:
        return Icons.error_outline;
    }
  }

  /// Format currency for display
  static String _formatCurrency(double amount) {
    return amount.toStringAsFixed(2);
  }
}