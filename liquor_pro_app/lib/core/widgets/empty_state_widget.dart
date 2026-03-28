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
    final cs = Theme.of(context).colorScheme;
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
              color: iconColor ?? cs.onSurfaceVariant,
            ).animate().fadeIn(duration: 400.ms).scale(delay: 100.ms),

            const SizedBox(height: 24),

            // Title
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
              textAlign: TextAlign.center,
            ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.2, end: 0),

            if (message != null) ...[
              const SizedBox(height: 12),
              Text(
                message!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
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
      // iconColor defaults to cs.onSurfaceVariant (theme-aware)
    );
  }

  /// No products - Inventory specific
  static Widget noProducts({
    String title = 'No Products Yet',
    String? message,
    VoidCallback? onAddBrands,
  }) {
    return EmptyStateWidget(
      icon: Icons.inventory_2_outlined,
      title: title,
      message: message ??
          'Get started by adding brands to your inventory.\n\nImport products from our catalog to begin managing your stock.',
      actionLabel: onAddBrands != null ? 'Add Brands' : null,
      onAction: onAddBrands,
      iconColor: Colors.blue[300],
      iconSize: 100,
    );
  }

  /// Low stock alert
  static Widget lowStockAlert({
    required int count,
    VoidCallback? onView,
  }) {
    return EmptyStateWidget(
      icon: Icons.warning_amber_rounded,
      title: '$count Items Low on Stock',
      message:
          'Some products are running low and need restocking.\n\nReview and update your inventory to avoid stockouts.',
      actionLabel: onView != null ? 'View Low Stock' : null,
      onAction: onView,
      iconColor: Colors.orange[600],
      iconSize: 100,
    );
  }

  /// All brands onboarded
  static Widget allBrandsOnboarded({
    VoidCallback? onViewInventory,
  }) {
    return EmptyStateWidget(
      icon: Icons.celebration,
      title: '🎉 All Brands Added!',
      message:
          'You\'ve successfully onboarded all available brands.\n\nCheck back later for new additions to our catalog.',
      actionLabel: onViewInventory != null ? 'View Inventory' : null,
      onAction: onViewInventory,
      iconColor: Colors.green[400],
      iconSize: 100,
    );
  }

  /// No stock set
  static Widget noStockSet({
    VoidCallback? onSetStock,
  }) {
    return EmptyStateWidget(
      icon: Icons.inventory_outlined,
      title: 'Set Initial Stock',
      message:
          'You have products but no stock quantities set.\n\nSet your initial stock levels to start tracking inventory.',
      actionLabel: onSetStock != null ? 'Set Stock Now' : null,
      onAction: onSetStock,
      iconColor: Colors.orange[300],
      iconSize: 100,
    );
  }
}
