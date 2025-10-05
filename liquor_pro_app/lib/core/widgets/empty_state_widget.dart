import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Empty State Widget - Best Practice Empty Views
/// Reusable empty state component with consistent design

class EmptyStateWidget extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color? iconColor;
  final double iconSize;

  const EmptyStateWidget({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.iconColor,
    this.iconSize = 80,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            Icon(
              icon,
              size: iconSize,
              color: iconColor ?? Colors.grey[400],
            ).animate().fadeIn(duration: 400.ms).scale(delay: 100.ms),

            const SizedBox(height: 24),

            // Title
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
              textAlign: TextAlign.center,
            ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.2, end: 0),

            if (message != null) ...[
              const SizedBox(height: 12),
              Text(
                message!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                textAlign: TextAlign.center,
              ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.2, end: 0),
            ],

            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add),
                label: Text(actionLabel!),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ).animate().fadeIn(delay: 400.ms).scale(delay: 400.ms),
            ],
          ],
        ),
      ),
    );
  }
}

/// Predefined Empty States
class EmptyStates {
  EmptyStates._();

  /// No items found
  static Widget noItems({
    String title = 'No Items Found',
    String? message,
    VoidCallback? onAdd,
  }) {
    return EmptyStateWidget(
      icon: Icons.inventory_2_outlined,
      title: title,
      message: message ?? 'Start by adding your first item',
      actionLabel: onAdd != null ? 'Add Item' : null,
      onAction: onAdd,
    );
  }

  /// No search results
  static Widget noSearchResults({
    String title = 'No Results Found',
    String? message,
  }) {
    return EmptyStateWidget(
      icon: Icons.search_off,
      title: title,
      message: message ?? 'Try adjusting your search terms',
      iconColor: Colors.orange[300],
    );
  }

  /// No brands
  static Widget noBrands({
    String title = 'No Brands Available',
    String? message,
    VoidCallback? onRefresh,
  }) {
    return EmptyStateWidget(
      icon: Icons.local_drink_outlined,
      title: title,
      message: message ?? 'No brands found in the catalog',
      actionLabel: onRefresh != null ? 'Refresh' : null,
      onAction: onRefresh,
      iconColor: Colors.blue[300],
    );
  }

  /// No categories
  static Widget noCategories({
    String title = 'No Categories',
    String? message,
  }) {
    return EmptyStateWidget(
      icon: Icons.category_outlined,
      title: title,
      message: message ?? 'No categories available',
      iconColor: Colors.purple[300],
    );
  }

  /// No data
  static Widget noData({
    String title = 'No Data',
    String? message,
    VoidCallback? onRetry,
  }) {
    return EmptyStateWidget(
      icon: Icons.data_usage_outlined,
      title: title,
      message: message ?? 'No data available at the moment',
      actionLabel: onRetry != null ? 'Retry' : null,
      onAction: onRetry,
    );
  }

  /// Network error
  static Widget networkError({
    String title = 'Connection Error',
    String? message,
    VoidCallback? onRetry,
  }) {
    return EmptyStateWidget(
      icon: Icons.wifi_off,
      title: title,
      message: message ?? 'Please check your internet connection',
      actionLabel: onRetry != null ? 'Retry' : null,
      onAction: onRetry,
      iconColor: Colors.red[300],
    );
  }

  /// Error state
  static Widget error({
    String title = 'Something Went Wrong',
    String? message,
    VoidCallback? onRetry,
  }) {
    return EmptyStateWidget(
      icon: Icons.error_outline,
      title: title,
      message: message ?? 'An unexpected error occurred',
      actionLabel: onRetry != null ? 'Try Again' : null,
      onAction: onRetry,
      iconColor: Colors.red[400],
    );
  }

  /// Coming soon
  static Widget comingSoon({
    String title = 'Coming Soon',
    String? message,
  }) {
    return EmptyStateWidget(
      icon: Icons.upcoming_outlined,
      title: title,
      message: message ?? 'This feature is under development',
      iconColor: Colors.green[300],
    );
  }

  /// No selection
  static Widget noSelection({
    String title = 'No Items Selected',
    String? message,
  }) {
    return EmptyStateWidget(
      icon: Icons.check_box_outline_blank,
      title: title,
      message: message ?? 'Select items to continue',
      iconColor: Colors.grey[400],
    );
  }
}
