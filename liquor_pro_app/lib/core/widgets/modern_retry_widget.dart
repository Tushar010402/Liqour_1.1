import 'package:flutter/material.dart';

/// Modern retry widget with good UX
/// Shows error message with retry button
class ModernRetryWidget extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final String? errorDetails;
  final IconData icon;

  const ModernRetryWidget({
    super.key,
    required this.message,
    required this.onRetry,
    this.errorDetails,
    this.icon = Icons.error_outline_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Error icon
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 48,
                color: Colors.red.shade400,
              ),
            ),
            const SizedBox(height: 24),

            // Error message
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),

            // Error details (if provided)
            if (errorDetails != null) ...[
              const SizedBox(height: 8),
              Text(
                errorDetails!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],

            const SizedBox(height: 32),

            // Retry button
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact inline retry button
class InlineRetryButton extends StatelessWidget {
  final VoidCallback onRetry;
  final String label;

  const InlineRetryButton({
    super.key,
    required this.onRetry,
    this.label = 'Retry',
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onRetry,
      icon: const Icon(Icons.refresh_rounded, size: 18),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: Theme.of(context).primaryColor,
      ),
    );
  }
}
