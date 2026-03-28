import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/product_with_stock.dart';
import '../screens/product_detail_bottom_sheet.dart';

/// Dense Product List Tile - REDESIGNED (Professional UX)
///
/// Interaction Design:
/// - TAP CARD -> Select/Deselect product
/// - TAP (+) ICON -> Quick add stock adjustment
/// - TAP (i) ICON -> View product details
///
/// Layout: 40% image | 60% info | 130px height
class DenseProductListTile extends StatelessWidget {
  final ProductWithStock product;
  final bool isSelected;
  final VoidCallback? onSelectionToggle;

  const DenseProductListTile({
    super.key,
    required this.product,
    this.isSelected = false,
    this.onSelectionToggle,
  });

  Color _stockColor(ColorScheme cs) {
    if (product.currentStock <= 10) return const Color(0xFFD32F2F);
    if (product.currentStock <= 50) return const Color(0xFFF59E0B);
    return const Color(0xFF1B7A2D);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      label: '${product.name}, ${product.size}, Stock: ${product.currentStock}, Price: \u20B9${product.sellingPrice.toStringAsFixed(0)}',
      hint: 'Tap to select, plus to add stock, info to view details',
      button: true,
      child: Card(
        elevation: isSelected ? 4 : 1,
        shadowColor: isSelected ? cs.primary.withOpacity(0.3) : Colors.black12,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isSelected ? cs.primary : cs.outlineVariant,
            width: isSelected ? 2.5 : 1,
          ),
        ),
        child: InkWell(
          // TAP CARD -> SELECT PRODUCT
          onTap: onSelectionToggle != null
              ? () {
                  HapticFeedback.lightImpact();
                  onSelectionToggle!();
                }
              : () {
                  // If no selection callback, show product details
                  ProductDetailBottomSheet.show(context, product);
                },
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 120, // Reduced from 130 to prevent overflow
            child: Row(
              children: [
                // LEFT: 40% Image section with + icon and stock badge
                _buildImageSection(context),

                // RIGHT: 60% Product info with (i) icon
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Row 1: Name + Info icon
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Product Name (cleaned - same logic as Daily Sales Entry)
                            Expanded(
                              child: Text(
                                _cleanProductName(product.name),
                                style: AppTextStyles.bodyLarge.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: cs.onSurface,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),

                            const SizedBox(width: 6),

                            // INFO (i) ICON -> VIEW PRODUCT DETAILS
                            GestureDetector(
                              onTap: () {
                                HapticFeedback.mediumImpact();
                                ProductDetailBottomSheet.show(context, product);
                              },
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(7),
                                  border: Border.all(
                                    color: cs.outlineVariant,
                                    width: 1,
                                  ),
                                ),
                                child: Icon(
                                  Icons.info_outline_rounded,
                                  size: 16,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),

                        // Row 2: Category + Size chips
                        Row(
                          children: [
                            // Category chip
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.local_bar,
                                    size: 11,
                                    color: cs.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    product.category?.name ?? 'Custom',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: cs.onSurfaceVariant,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(width: 6),

                            // Size badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: cs.secondary.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                product.size.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: cs.secondary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),

                        // Row 3: Price + Selection indicator
                        Row(
                          children: [
                            // Price
                            Text(
                              '\u20B9${product.sellingPrice.toStringAsFixed(0)}',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: cs.primary,
                              ),
                            ),

                            const Spacer(),

                            // Low stock warning
                            if (product.isLowStock)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.error.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.warning_amber_rounded,
                                      size: 11,
                                      color: AppColors.error,
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      'Low',
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: AppColors.error,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            // Selection checkmark (shows when selected)
                            if (isSelected) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  color: cs.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check,
                                  size: 12,
                                  color: Colors.white,
                                ),
                              ),
                            ],

                            // Tap hint (shows when not selected)
                            if (!isSelected)
                              Icon(
                                Icons.touch_app_outlined,
                                size: 16,
                                color: cs.onSurfaceVariant,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Builds the left 40% image section with overlays
  Widget _buildImageSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 130,
      height: double.infinity,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          bottomLeft: Radius.circular(16),
        ),
        color: cs.surfaceContainerHighest,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Product Image
          ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              bottomLeft: Radius.circular(16),
            ),
            child: product.imageUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: product.imageUrl,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: cs.surfaceContainerHighest,
                      child: Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.primary,
                        ),
                      ),
                    ),
                    errorWidget: (context, url, error) => _buildPlaceholderImage(cs),
                  )
                : _buildPlaceholderImage(cs),
          ),

          // Selection overlay (tint when selected)
          if (isSelected)
            Container(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
                color: cs.primary.withOpacity(0.25),
              ),
            ),

          // PLUS (+) ICON -> QUICK ADD STOCK (top-right)
          // Only visible to Admin, Manager, Assistant Manager (NOT Salesman/Executive)
          Consumer<AuthProvider>(
            builder: (context, authProvider, _) {
              final userRole = (authProvider.currentUser?.role ?? '').toLowerCase();
              // Salesman and Executive cannot adjust stock
              final canAdjustStock = userRole != 'salesman' && userRole != 'executive';

              if (!canAdjustStock) {
                return const SizedBox.shrink(); // Hide for Salesman/Executive
              }

              return Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    // Show iOS-style modal bottom sheet instead of full page navigation
                    ProductDetailBottomSheet.show(
                      context,
                      product,
                      initialTab: 'stock_adjustment',
                    );
                  },
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: cs.primary.withOpacity(0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.add,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              );
            },
          ),

          // STOCK BADGE (bottom-right)
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _stockColor(cs),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: _stockColor(cs).withOpacity(0.4),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.inventory_2,
                    size: 12,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${product.currentStock}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // SELECTED CHECKMARK (bottom-left when selected)
          if (isSelected)
            Positioned(
              bottom: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: cs.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: cs.primary.withOpacity(0.4),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.check,
                  color: Colors.white,
                  size: 14,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderImage(ColorScheme cs) {
    return Container(
      color: cs.surfaceContainerHighest,
      child: Icon(
        Icons.liquor,
        size: 48,
        color: cs.onSurfaceVariant,
      ),
    );
  }

  /// Clean product name by removing size - SAME LOGIC AS DAILY SALES ENTRY
  /// This ensures consistent product name display across all screens
  String _cleanProductName(String name) {
    // Remove size patterns like "- 330ML", "- 500ml", "- 650 ML", "- 1LTR"
    String cleanName = name
        .replaceAll(RegExp(r'\s*-\s*\d+(?:\.\d+)?\s*(?:ml|ML|ltr|LTR|L)\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\d+(?:\.\d+)?\s*(?:ml|ML|ltr|LTR|L)\b', caseSensitive: false), '')
        .trim();

    // Remove trailing dash if present
    if (cleanName.endsWith('-')) {
      cleanName = cleanName.substring(0, cleanName.length - 1).trim();
    }

    return cleanName.isNotEmpty ? cleanName : name;
  }
}
