import 'package:flutter/material.dart';
import '../../../core/constants/app_text_styles.dart';
import '../models/product.dart' as models;

/// Product card matching JSX ProductCard pixel-for-pixel.
/// JSX: dark gradient image (140deg), MRP badge top-LEFT, "BP" price label,
/// bottle silhouette, 3-dot vertical menu, category-size grey pill,
/// green stock indicator, stepper with blue + button, closing stock with 📦.
class SalesmanProductCard extends StatelessWidget {
  final models.Product product;
  final int currentStock;
  final int quantity;
  final VoidCallback? onIncrement;
  final VoidCallback? onDecrement;
  final VoidCallback? onMenuTap;

  const SalesmanProductCard({
    super.key,
    required this.product,
    this.currentStock = 0,
    this.quantity = 0,
    this.onIncrement,
    this.onDecrement,
    this.onMenuTap,
  });

  @override
  Widget build(BuildContext context) {
    final inStock = currentStock > 0;
    final closingStock = currentStock - quantity;

    // JSX: padding "16px 20px", borderBottom "1px solid #F0F1F4"
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF0F1F4))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildImageArea(),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name + 3-dot menu (JSX: fontSize 15, fontWeight 700)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        product.name,
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: const Color(0xFF1A1A2E),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: onMenuTap,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 3, left: 4),
                        child: Column(
                          children: List.generate(3, (_) => Container(
                            width: 3.5, height: 3.5,
                            margin: const EdgeInsets.only(bottom: 2.5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.grey.shade400,
                            ),
                          )),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),

                // Tags row (JSX: grey bg #F0F1F4, green stock text)
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F1F4),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        '${product.categoryName ?? 'N/A'} - ${product.size}',
                        style: AppTextStyles.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                          color: const Color(0xFF666666),
                        ),
                      ),
                    ),
                    Text(
                      '${inStock ? "\u{1F7E2}" : "\u{1F534}"} $currentStock in stock',
                      style: AppTextStyles.caption.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: inStock ? const Color(0xFF1B7A2D) : const Color(0xFFD32F2F),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),

                // Price + stepper row (JSX: "₹ 500" fontSize 17 fontWeight 900, "BP" label)
                Row(
                  children: [
                    Text(
                      '\u20B9 ${product.sellingPrice.toStringAsFixed(0)}',
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                        color: const Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'BP',
                      style: AppTextStyles.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: const Color(0xFF999999),
                      ),
                    ),
                    const Spacer(),
                    _buildStepper(),
                  ],
                ),

                // Closing stock (JSX: always shown, 📦, fontSize 12, color #999)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    '\u{1F4E6} $closingStock closing stock',
                    style: AppTextStyles.caption.copyWith(
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                      color: const Color(0xFF999999),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// JSX: 85x85, gradient(140deg, #0d1a30 → #1a1030 → #3a1a10 → #d4700a),
  /// MRP badge TOP-LEFT green #1B7A2D, bottle silhouette shapes
  Widget _buildImageArea() {
    return SizedBox(
      width: 85,
      height: 85,
      child: Stack(
        children: [
          Container(
            width: 85,
            height: 85,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                colors: [Color(0xFF0D1A30), Color(0xFF1A1030), Color(0xFF3A1A10), Color(0xFFD4700A)],
                stops: [0.0, 0.4, 0.7, 1.0],
                begin: Alignment(-0.7, -0.7),
                end: Alignment(0.7, 0.7),
              ),
            ),
            child: product.imageUrl.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(product.imageUrl, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildBottleSilhouette()),
                  )
                : _buildBottleSilhouette(),
          ),
          // MRP badge TOP-LEFT (JSX: green #1B7A2D, "MRP" + price vertically)
          Positioned(
            top: 5,
            left: 5,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF1B7A2D),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('MRP', style: TextStyle(
                    fontSize: 7, fontWeight: FontWeight.w700, color: Colors.white,
                    fontFamily: AppTextStyles.bodyMedium.fontFamily,
                  )),
                  Text('\u20B9 ${product.sellingPrice.toStringAsFixed(0)}', style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white,
                    fontFamily: AppTextStyles.bodyMedium.fontFamily,
                  )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Bottle silhouette shapes matching JSX
  Widget _buildBottleSilhouette() {
    return Stack(
      children: [
        // Body
        Positioned(
          right: 14,
          bottom: 8,
          child: Container(
            width: 18,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(3),
                bottom: Radius.circular(2),
              ),
            ),
          ),
        ),
        // Neck
        Positioned(
          right: 17,
          bottom: 46,
          child: Container(
            width: 12,
            height: 10,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
            ),
          ),
        ),
      ],
    );
  }

  /// JSX stepper: minus has border 1.8px #D0D5DD radius "7px 0 0 7px",
  /// count has top/bottom border, plus is #0D47A1 radius "0 7px 7px 0"
  Widget _buildStepper() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Minus
        GestureDetector(
          onTap: quantity > 0 ? onDecrement : null,
          child: Container(
            width: 32, height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFD0D5DD), width: 1.8),
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(7)),
              color: Colors.white,
            ),
            child: Text('\u2212', style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w700, color: const Color(0xFF555555),
              fontFamily: AppTextStyles.bodyMedium.fontFamily,
            )),
          ),
        ),
        // Count
        Container(
          width: 34, height: 32,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            border: Border.symmetric(
              horizontal: BorderSide(color: Color(0xFFD0D5DD), width: 1.8),
            ),
            color: Colors.white,
          ),
          child: Text(
            '$quantity',
            style: AppTextStyles.bodyMedium.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: const Color(0xFF1A1A2E),
            ),
          ),
        ),
        // Plus
        GestureDetector(
          onTap: onIncrement,
          child: Container(
            width: 32, height: 32,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFF0D47A1),
              borderRadius: BorderRadius.horizontal(right: Radius.circular(7)),
            ),
            child: Text('+', style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white,
              fontFamily: AppTextStyles.bodyMedium.fontFamily,
            )),
          ),
        ),
      ],
    );
  }
}
