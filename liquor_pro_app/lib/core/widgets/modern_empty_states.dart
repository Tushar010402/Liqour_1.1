import 'package:flutter/material.dart';

/// Modern Empty State Widgets with Contextual Messages
/// Provides better UX than generic "No data" messages

enum EmptyStateType {
  noData,
  noResults,
  noInternet,
  error,
  noPermission,
  custom,
}

class ModernEmptyState extends StatelessWidget {
  final EmptyStateType type;
  final String? title;
  final String? message;
  final IconData? icon;
  final String? actionButtonText;
  final VoidCallback? onActionPressed;
  final String? secondaryButtonText;
  final VoidCallback? onSecondaryPressed;

  const ModernEmptyState({
    super.key,
    required this.type,
    this.title,
    this.message,
    this.icon,
    this.actionButtonText,
    this.onActionPressed,
    this.secondaryButtonText,
    this.onSecondaryPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final config = _getConfiguration(cs);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: config.color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon ?? config.icon,
                size: 64,
                color: config.color,
              ),
            ),
            const SizedBox(height: 24),

            // Title
            Text(
              title ?? config.title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),

            // Message
            Text(
              message ?? config.message,
              style: TextStyle(
                fontSize: 14,
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Action buttons
            if (actionButtonText != null && onActionPressed != null)
              ElevatedButton(
                onPressed: onActionPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: config.color,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  actionButtonText!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

            if (secondaryButtonText != null && onSecondaryPressed != null) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: onSecondaryPressed,
                child: Text(
                  secondaryButtonText!,
                  style: TextStyle(
                    color: config.color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  _EmptyStateConfig _getConfiguration(ColorScheme cs) {
    switch (type) {
      case EmptyStateType.noData:
        return _EmptyStateConfig(
          icon: Icons.inbox_outlined,
          title: 'No Data Available',
          message: 'There are no items to display yet. Start by adding some!',
          color: cs.primary,
        );

      case EmptyStateType.noResults:
        return _EmptyStateConfig(
          icon: Icons.search_off_outlined,
          title: 'No Results Found',
          message: 'Try adjusting your search or filters to find what you\'re looking for.',
          color: Colors.orange,
        );

      case EmptyStateType.noInternet:
        return _EmptyStateConfig(
          icon: Icons.wifi_off_outlined,
          title: 'No Internet Connection',
          message: 'Please check your connection and try again.',
          color: cs.onSurfaceVariant,
        );

      case EmptyStateType.error:
        return _EmptyStateConfig(
          icon: Icons.error_outline,
          title: 'Oops! Something Went Wrong',
          message: 'We encountered an error. Please try again.',
          color: Colors.red,
        );

      case EmptyStateType.noPermission:
        return _EmptyStateConfig(
          icon: Icons.lock_outline,
          title: 'Access Denied',
          message: 'You don\'t have permission to view this content.',
          color: Colors.amber,
        );

      case EmptyStateType.custom:
        return _EmptyStateConfig(
          icon: Icons.info_outline,
          title: 'Empty',
          message: 'No information available',
          color: cs.primary,
        );
    }
  }
}

class _EmptyStateConfig {
  final IconData icon;
  final String title;
  final String message;
  final Color color;

  _EmptyStateConfig({
    required this.icon,
    required this.title,
    required this.message,
    required this.color,
  });
}

/// Empty list state with refresh
class EmptyListState extends StatelessWidget {
  final String title;
  final String message;
  final IconData? icon;
  final VoidCallback? onRefresh;
  final VoidCallback? onAdd;

  const EmptyListState({
    super.key,
    required this.title,
    required this.message,
    this.icon,
    this.onRefresh,
    this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return ModernEmptyState(
      type: EmptyStateType.noData,
      title: title,
      message: message,
      icon: icon,
      actionButtonText: onAdd != null ? 'Add New' : null,
      onActionPressed: onAdd,
      secondaryButtonText: onRefresh != null ? 'Refresh' : null,
      onSecondaryPressed: onRefresh,
    );
  }
}

/// Empty search results
class EmptySearchState extends StatelessWidget {
  final String query;
  final VoidCallback? onClearSearch;

  const EmptySearchState({
    super.key,
    required this.query,
    this.onClearSearch,
  });

  @override
  Widget build(BuildContext context) {
    return ModernEmptyState(
      type: EmptyStateType.noResults,
      title: 'No Results for "$query"',
      message: 'Try using different keywords or check your spelling.',
      actionButtonText: 'Clear Search',
      onActionPressed: onClearSearch,
    );
  }
}

/// No internet connection state
class NoInternetState extends StatelessWidget {
  final VoidCallback? onRetry;

  const NoInternetState({super.key, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ModernEmptyState(
      type: EmptyStateType.noInternet,
      actionButtonText: 'Retry',
      onActionPressed: onRetry,
    );
  }
}

/// Generic error state
class ErrorState extends StatelessWidget {
  final String? message;
  final VoidCallback? onRetry;

  const ErrorState({super.key, this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ModernEmptyState(
      type: EmptyStateType.error,
      message: message,
      actionButtonText: 'Try Again',
      onActionPressed: onRetry,
    );
  }
}
