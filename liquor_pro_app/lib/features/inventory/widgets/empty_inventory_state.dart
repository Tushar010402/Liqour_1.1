import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';

/// Modern Empty Inventory State Widget
/// iOS 16-inspired design with gradient cards, animations, and smart guidance
class EmptyInventoryState extends StatelessWidget {
  final EmptyStateType type;
  final VoidCallback? onAction;
  final VoidCallback? onBrowseCatalog;
  final VoidCallback? onCreateCustom;
  final VoidCallback? onScanInvoice;
  final VoidCallback? onExcelImport;
  final int availableBrandsCount;

  const EmptyInventoryState({
    super.key,
    required this.type,
    this.onAction,
    this.onBrowseCatalog,
    this.onCreateCustom,
    this.onScanInvoice,
    this.onExcelImport,
    this.availableBrandsCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    // For no products, show modern action cards
    if (type == EmptyStateType.noProducts || type == EmptyStateType.brandsReadyToOnboard) {
      return _buildNoProductsState(context);
    }

    // For other states, show simple centered message
    return _buildSimpleState(context);
  }

  Widget _buildNoProductsState(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    print('🎨 [EmptyInventoryState] Building no products state');
    return Container(
      color: cs.surface,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
          const SizedBox(height: 40),

          // Large animated icon
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  cs.primary.withValues(alpha: 0.1),
                  cs.primary.withValues(alpha: 0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: cs.primary.withValues(alpha: 0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Icon(
              Icons.inventory_2_outlined,
              size: 70,
              color: cs.primary.withValues(alpha: 0.7),
            ),
          )
              .animate()
              .fadeIn(duration: 400.ms)
              .scale(delay: 100.ms, duration: 300.ms),

          const SizedBox(height: 32),

          // Title
          Text(
            type == EmptyStateType.brandsReadyToOnboard
                ? '$availableBrandsCount Brands Ready!'
                : 'No Products Yet',
            style: AppTextStyles.h4.copyWith(
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
            ),
            textAlign: TextAlign.center,
          )
              .animate()
              .fadeIn(delay: 200.ms, duration: 400.ms)
              .slideY(begin: 0.2, end: 0),

          const SizedBox(height: 12),

          // Subtitle
          Text(
            type == EmptyStateType.brandsReadyToOnboard
                ? 'You have brands in the catalog ready to onboard.\nBrowse and add them to your inventory!'
                : 'Let\'s build your inventory!\nChoose how you want to add products:',
            style: AppTextStyles.bodyMedium.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          )
              .animate()
              .fadeIn(delay: 300.ms, duration: 400.ms)
              .slideY(begin: 0.2, end: 0),

          const SizedBox(height: 40),

          // Action Cards
          _buildActionCard(
            context: context,
            icon: Icons.storefront,
            title: 'Brand Onboarding',
            description: type == EmptyStateType.brandsReadyToOnboard
                ? 'Onboard $availableBrandsCount brands from catalog'
                : 'Browse 1600+ brands and add to your shop',
            gradient: const LinearGradient(
              colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            onTap: onBrowseCatalog,
            isPrimary: true,
          ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.3, end: 0),

          const SizedBox(height: 16),

          _buildActionCard(
            context: context,
            icon: Icons.add_business,
            title: 'Create Custom Brand',
            description: 'Add your own brands with custom variants',
            gradient: const LinearGradient(
              colors: [Color(0xFFA855F7), Color(0xFFEC4899)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            onTap: onCreateCustom,
          ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.3, end: 0),

          const SizedBox(height: 16),

          _buildActionCard(
            context: context,
            icon: Icons.upload_file,
            title: 'Bulk Import (Excel)',
            description: 'Import multiple brands from Excel file',
            gradient: const LinearGradient(
              colors: [Color(0xFF10B981), Color(0xFF34D399)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            onTap: onExcelImport,
          ).animate().fadeIn(delay: 700.ms).slideY(begin: 0.3, end: 0),

          const SizedBox(height: 32),

          // Pro Tip
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.info.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  color: AppColors.info,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Tip: Use the Quick Actions button below for faster access!',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.info,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(delay: 800.ms),

          const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String description,
    required Gradient gradient,
    required VoidCallback? onTap,
    bool isPrimary = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: gradient.colors.first.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: isPrimary ? 32 : 28,
                ),
              ),

              const SizedBox(width: 16),

              // Text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: isPrimary ? 17 : 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),

              // Arrow
              Icon(
                Icons.arrow_forward_ios,
                color: Colors.white.withValues(alpha: 0.8),
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSimpleState(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: _getIconColor(type, cs).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _getIcon(type),
                size: 60,
                color: _getIconColor(type, cs).withValues(alpha: 0.6),
              ),
            )
                .animate()
                .fadeIn(duration: 400.ms)
                .scale(delay: 100.ms),

            const SizedBox(height: 24),

            // Title
            Text(
              _getTitle(type),
              style: AppTextStyles.h5.copyWith(
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
              textAlign: TextAlign.center,
            )
                .animate()
                .fadeIn(delay: 200.ms)
                .slideY(begin: 0.2, end: 0),

            const SizedBox(height: 12),

            // Description
            Text(
              _getDescription(type),
              style: AppTextStyles.bodyMedium.copyWith(
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            )
                .animate()
                .fadeIn(delay: 300.ms)
                .slideY(begin: 0.2, end: 0),

            if (_getActionLabel(type) != null && onAction != null) ...[
              const SizedBox(height: 24),

              // Action Button
              ElevatedButton.icon(
                onPressed: onAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: cs.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                icon: Icon(_getActionIcon(type)),
                label: Text(
                  _getActionLabel(type)!,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ).animate().fadeIn(delay: 400.ms).scale(delay: 400.ms),
            ],
          ],
        ),
      ),
    );
  }

  // Helper methods for simple states
  IconData _getIcon(EmptyStateType type) {
    switch (type) {
      case EmptyStateType.noProducts:
      case EmptyStateType.brandsReadyToOnboard:
        return Icons.inventory_2_outlined;
      case EmptyStateType.noSearchResults:
        return Icons.search_off;
      case EmptyStateType.noFilterResults:
        return Icons.filter_alt_off;
      case EmptyStateType.error:
        return Icons.error_outline;
    }
  }

  Color _getIconColor(EmptyStateType type, ColorScheme cs) {
    switch (type) {
      case EmptyStateType.noProducts:
      case EmptyStateType.brandsReadyToOnboard:
        return cs.primary;
      case EmptyStateType.noSearchResults:
        return AppColors.warning;
      case EmptyStateType.noFilterResults:
        return AppColors.info;
      case EmptyStateType.error:
        return AppColors.error;
    }
  }

  String _getTitle(EmptyStateType type) {
    switch (type) {
      case EmptyStateType.noProducts:
      case EmptyStateType.brandsReadyToOnboard:
        return 'No Products Yet';
      case EmptyStateType.noSearchResults:
        return 'No Results Found';
      case EmptyStateType.noFilterResults:
        return 'No Matching Products';
      case EmptyStateType.error:
        return 'Something Went Wrong';
    }
  }

  String _getDescription(EmptyStateType type) {
    switch (type) {
      case EmptyStateType.noProducts:
        return 'Start building your inventory by browsing our catalog or creating custom products.';
      case EmptyStateType.brandsReadyToOnboard:
        return 'You have $availableBrandsCount brands available in the catalog. Browse and onboard them to your inventory!';
      case EmptyStateType.noSearchResults:
        return 'Try a different search term or check your spelling.';
      case EmptyStateType.noFilterResults:
        return 'Try adjusting or clearing your filters to see more products.';
      case EmptyStateType.error:
        return 'We encountered an error while loading your products. Please try again.';
    }
  }

  String? _getActionLabel(EmptyStateType type) {
    switch (type) {
      case EmptyStateType.noProducts:
      case EmptyStateType.brandsReadyToOnboard:
        return null; // Uses action cards instead
      case EmptyStateType.noSearchResults:
        return null;
      case EmptyStateType.noFilterResults:
        return 'Clear Filters';
      case EmptyStateType.error:
        return 'Try Again';
    }
  }

  IconData _getActionIcon(EmptyStateType type) {
    switch (type) {
      case EmptyStateType.noFilterResults:
        return Icons.clear_all;
      case EmptyStateType.error:
        return Icons.refresh;
      default:
        return Icons.add;
    }
  }
}

/// Empty state types
enum EmptyStateType {
  noProducts,
  brandsReadyToOnboard, // NEW: User has brands in catalog but not onboarded
  noSearchResults,
  noFilterResults,
  error,
}
