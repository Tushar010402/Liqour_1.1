import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/product_with_stock.dart';
import '../screens/product_detail_bottom_sheet.dart';

/// Compact Product Grid Card - REDESIGNED
///
/// Interaction Design:
/// - TAP CARD -> Select/Deselect product
/// - TAP (i) ICON -> View product details in bottom sheet
/// - TAP (+) ICON -> Quick stock adjustment in bottom sheet
///
/// Aspect ratio: 0.62 (taller for better info display)
class CompactProductGridCard extends StatelessWidget {
  final ProductWithStock product;
  final bool isSelected;
  final VoidCallback? onSelectionToggle;

  const CompactProductGridCard({
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
      hint: 'Tap to select, info icon for details, plus for stock adjustment',
      button: true,
      child: Card(
        elevation: isSelected ? 4 : 0,
        shadowColor: isSelected ? cs.primary.withOpacity(0.3) : Colors.transparent,
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
                  // Fallback: show bottom sheet if no selection handler
                  ProductDetailBottomSheet.show(context, product);
                },
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product Image with overlays
              AspectRatio(
                aspectRatio: 1.0,
                child: Stack(
                  children: [
                    // Product Image
                    ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                      child: product.imageUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: product.imageUrl,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
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
                            topRight: Radius.circular(16),
                          ),
                          color: cs.primary.withOpacity(0.25),
                        ),
                      ),

                    // (i) INFO BUTTON - Top Left -> Opens Product Details
                    Positioned(
                      top: 8,
                      left: 8,
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          ProductDetailBottomSheet.show(context, product);
                        },
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: cs.surface.withOpacity(0.95),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.15),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.info_outline_rounded,
                            size: 18,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),

                    // Stock Badge - Top Right
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: _stockColor(cs),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.25),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                            BoxShadow(
                              color: _stockColor(cs).withOpacity(0.5),
                              blurRadius: 4,
                              spreadRadius: -2,
                            ),
                          ],
                          border: Border.all(
                            color: Colors.white.withOpacity(0.2),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.inventory_2, size: 13, color: Colors.white),
                            const SizedBox(width: 5),
                            Text(
                              '${product.currentStock}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Low Stock Warning - Bottom Left
                    if (product.isLowStock)
                      Positioned(
                        bottom: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.error,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.warning_amber, size: 10, color: Colors.white),
                              SizedBox(width: 2),
                              Text(
                                'Low',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Selection Checkmark - Bottom Right (when selected)
                    if (isSelected)
                      Positioned(
                        bottom: 8,
                        right: 8,
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
              ),

              // Product Info
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Brand Label (only if different from variant name)
                      Builder(
                        builder: (context) {
                          final variantName = product.name.contains(' - ')
                              ? product.name.split(' - ').first.toUpperCase()
                              : product.name.toUpperCase();
                          final brandName = product.brand?.name.toUpperCase() ?? '';
                          final showBrand = product.brand != null && brandName != variantName;

                          if (!showBrand) return const SizedBox.shrink();

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: cs.primary.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: cs.primary.withOpacity(0.3),
                                  width: 0.5,
                                ),
                              ),
                              child: Text(
                                product.brand!.name.toUpperCase(),
                                style: TextStyle(
                                  color: cs.primary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 10,
                                  letterSpacing: 0.5,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          );
                        },
                      ),

                      // Product Name (cleaned - same logic as Daily Sales Entry)
                      Flexible(
                        flex: 2,
                        fit: FlexFit.loose,
                        child: Text(
                          _cleanProductName(product.name),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            height: 1.2,
                            color: cs.onSurface,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),

                      const SizedBox(height: 3),

                      // Size Chip
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: cs.outlineVariant,
                            width: 0.5,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.straighten,
                              size: 9,
                              color: cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              product.size,
                              style: TextStyle(
                                fontSize: 10,
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 6),

                      // Price & Stock Badge Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Price
                          Text(
                            '\u20B9${product.sellingPrice.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: cs.primary,
                              fontSize: 14,
                            ),
                          ),
                          // Stock Badge at Bottom-Right (Color-coded)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _stockColor(cs),
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: _stockColor(cs).withOpacity(0.3),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.inventory_2, size: 12, color: Colors.white),
                                const SizedBox(width: 4),
                                Text(
                                  '${product.currentStock}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      // Quick Stock Adjustment Button (for authorized users)
                      // Only visible to Admin, Manager, Assistant Manager (NOT Salesman/Executive)
                      Consumer<AuthProvider>(
                        builder: (context, authProvider, _) {
                          final userRole = (authProvider.currentUser?.role ?? '').toLowerCase();
                          // Salesman and Executive cannot adjust stock
                          final canAdjustStock = userRole != 'salesman' && userRole != 'executive';

                          if (!canAdjustStock) {
                            return const SizedBox.shrink(); // Hide for Salesman/Executive
                          }

                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: SizedBox(
                              width: double.infinity,
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () {
                                    HapticFeedback.mediumImpact();
                                    // Open bottom sheet with stock adjustment tab
                                    ProductDetailBottomSheet.show(
                                      context,
                                      product,
                                      initialTab: 'stock_adjustment',
                                    );
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 6),
                                    decoration: BoxDecoration(
                                      color: cs.primary.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: cs.primary.withOpacity(0.3),
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.add_circle_outline,
                                          size: 14,
                                          color: cs.primary,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Adjust Stock',
                                          style: TextStyle(
                                            color: cs.primary,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholderImage(ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primary.withOpacity(0.1),
            cs.secondary.withOpacity(0.1),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.liquor,
          size: 48,
          color: cs.primary.withOpacity(0.3),
        ),
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
