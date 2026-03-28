import 'package:flutter/material.dart';

/// Modern empty state widget with icon, title, and optional action
/// Features:
/// - Customizable icon with animation support
/// - Title and subtitle
/// - Optional action button
/// - Fade-in animation on mount
class ModernEmptyState extends StatefulWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color? iconColor;
  final double iconSize;
  final bool animated;

  const ModernEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.iconColor,
    this.iconSize = 80,
    this.animated = true,
  });

  @override
  State<ModernEmptyState> createState() => _ModernEmptyStateState();
}

class _ModernEmptyStateState extends State<ModernEmptyState>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    ));

    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.2, 0.8, curve: Curves.easeOutBack),
    ));

    if (widget.animated) {
      _controller.forward();
    } else {
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = widget.iconColor ?? theme.colorScheme.primary.withOpacity(0.3);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: child,
          ),
        );
      },
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon with circular background
              Container(
                width: widget.iconSize + 40,
                height: widget.iconSize + 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: iconColor.withOpacity(0.1),
                  border: Border.all(
                    color: iconColor.withOpacity(0.2),
                    width: 2,
                  ),
                ),
                child: Icon(
                  widget.icon,
                  size: widget.iconSize,
                  color: iconColor,
                ),
              ),

              const SizedBox(height: 24),

              // Title
              Text(
                widget.title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.textTheme.bodyLarge?.color,
                ),
                textAlign: TextAlign.center,
              ),

              if (widget.subtitle != null) ...[
                const SizedBox(height: 8),
                Text(
                  widget.subtitle!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],

              if (widget.actionLabel != null && widget.onAction != null) ...[
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: widget.onAction,
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: Text(widget.actionLabel!),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Specialized empty states for common scenarios
class EmptyStates {
  /// No items found in search/filter
  static Widget noResults({
    required BuildContext context,
    String? searchQuery,
    VoidCallback? onClear,
  }) {
    return ModernEmptyState(
      icon: Icons.search_off_rounded,
      title: 'No Results Found',
      subtitle: searchQuery != null
          ? 'No items match "$searchQuery"'
          : 'Try adjusting your filters',
      actionLabel: onClear != null ? 'Clear Filters' : null,
      onAction: onClear,
    );
  }

  /// No items in list
  static Widget noItems({
    required BuildContext context,
    required String itemType,
    VoidCallback? onCreate,
  }) {
    return ModernEmptyState(
      icon: Icons.inventory_2_outlined,
      title: 'No $itemType Yet',
      subtitle: 'Get started by adding your first $itemType',
      actionLabel: onCreate != null ? 'Add $itemType' : null,
      onAction: onCreate,
    );
  }

  /// Network error
  static Widget networkError({
    required BuildContext context,
    required VoidCallback onRetry,
  }) {
    return ModernEmptyState(
      icon: Icons.cloud_off_rounded,
      title: 'Connection Error',
      subtitle: 'Please check your internet connection',
      actionLabel: 'Retry',
      onAction: onRetry,
      iconColor: Theme.of(context).colorScheme.error,
    );
  }

  /// Generic error
  static Widget error({
    required BuildContext context,
    required String message,
    VoidCallback? onRetry,
  }) {
    return ModernEmptyState(
      icon: Icons.error_outline_rounded,
      title: 'Something Went Wrong',
      subtitle: message,
      actionLabel: onRetry != null ? 'Try Again' : null,
      onAction: onRetry,
      iconColor: Theme.of(context).colorScheme.error,
    );
  }

  /// Loading state
  static Widget loading({
    required BuildContext context,
    String? message,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.color
                        ?.withOpacity(0.6),
                  ),
            ),
          ],
        ],
      ),
    );
  }
}
