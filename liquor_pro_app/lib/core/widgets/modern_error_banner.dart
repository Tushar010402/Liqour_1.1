import 'package:flutter/material.dart';

/// Modern error banner that appears at the top of screens
/// Non-intrusive way to show errors with action button
class ModernErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onDismiss;
  final VoidCallback? onAction;
  final String? actionLabel;
  final Color? backgroundColor;
  final IconData icon;

  const ModernErrorBanner({
    super.key,
    required this.message,
    this.onDismiss,
    this.onAction,
    this.actionLabel,
    this.backgroundColor,
    this.icon = Icons.error_outline_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor ?? Colors.red.shade50,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              Icon(
                icon,
                color: Colors.red.shade700,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.red.shade900,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (onAction != null && actionLabel != null) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  child: Text(
                    actionLabel!,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
              if (onDismiss != null)
                IconButton(
                  onPressed: onDismiss,
                  icon: Icon(Icons.close_rounded, size: 20, color: Colors.red.shade700),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Warning banner variant
class ModernWarningBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onDismiss;
  final VoidCallback? onAction;
  final String? actionLabel;

  const ModernWarningBanner({
    super.key,
    required this.message,
    this.onDismiss,
    this.onAction,
    this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    return ModernErrorBanner(
      message: message,
      onDismiss: onDismiss,
      onAction: onAction,
      actionLabel: actionLabel,
      backgroundColor: Colors.orange.shade50,
      icon: Icons.warning_amber_rounded,
    );
  }
}

/// Info banner variant
class ModernInfoBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onDismiss;
  final VoidCallback? onAction;
  final String? actionLabel;

  const ModernInfoBanner({
    super.key,
    required this.message,
    this.onDismiss,
    this.onAction,
    this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    return ModernErrorBanner(
      message: message,
      onDismiss: onDismiss,
      onAction: onAction,
      actionLabel: actionLabel,
      backgroundColor: Colors.blue.shade50,
      icon: Icons.info_outline_rounded,
    );
  }
}
