import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';

/// Premium card widget with enhanced styling and animations
class PremiumCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final Color? backgroundColor;
  final List<BoxShadow>? boxShadow;
  final BorderRadiusGeometry? borderRadius;
  final Border? border;
  final Gradient? gradient;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isInteractive;
  final bool showHoverEffect;
  final PremiumCardVariant variant;
  final double elevation;
  final Clip clipBehavior;
  final AlignmentGeometry? alignment;

  const PremiumCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.backgroundColor,
    this.boxShadow,
    this.borderRadius,
    this.border,
    this.gradient,
    this.onTap,
    this.onLongPress,
    this.isInteractive = false,
    this.showHoverEffect = true,
    this.variant = PremiumCardVariant.elevated,
    this.elevation = 4.0,
    this.clipBehavior = Clip.none,
    this.alignment,
  });

  const PremiumCard.elevated({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.backgroundColor,
    this.boxShadow,
    this.borderRadius,
    this.border,
    this.gradient,
    this.onTap,
    this.onLongPress,
    this.isInteractive = false,
    this.showHoverEffect = true,
    this.elevation = 4.0,
    this.clipBehavior = Clip.none,
    this.alignment,
  }) : variant = PremiumCardVariant.elevated;

  const PremiumCard.outlined({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.backgroundColor,
    this.boxShadow,
    this.borderRadius,
    this.border,
    this.gradient,
    this.onTap,
    this.onLongPress,
    this.isInteractive = false,
    this.showHoverEffect = true,
    this.elevation = 0.0,
    this.clipBehavior = Clip.none,
    this.alignment,
  }) : variant = PremiumCardVariant.outlined;

  const PremiumCard.filled({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.backgroundColor,
    this.boxShadow,
    this.borderRadius,
    this.border,
    this.gradient,
    this.onTap,
    this.onLongPress,
    this.isInteractive = false,
    this.showHoverEffect = true,
    this.elevation = 0.0,
    this.clipBehavior = Clip.none,
    this.alignment,
  }) : variant = PremiumCardVariant.filled;

  const PremiumCard.glass({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.backgroundColor,
    this.boxShadow,
    this.borderRadius,
    this.border,
    this.gradient,
    this.onTap,
    this.onLongPress,
    this.isInteractive = false,
    this.showHoverEffect = true,
    this.elevation = 0.0,
    this.clipBehavior = Clip.antiAlias,
    this.alignment,
  }) : variant = PremiumCardVariant.glass;

  @override
  State<PremiumCard> createState() => _PremiumCardState();
}

class _PremiumCardState extends State<PremiumCard> with TickerProviderStateMixin {
  late AnimationController _hoverController;
  late AnimationController _tapController;
  late Animation<double> _hoverAnimation;
  late Animation<double> _tapAnimation;
  late Animation<double> _elevationAnimation;

  bool _isHovered = false;
  bool _isTapped = false;

  @override
  void initState() {
    super.initState();

    _hoverController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _tapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );

    _hoverAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _hoverController,
      curve: Curves.easeInOut,
    ));

    _tapAnimation = Tween<double>(
      begin: 1.0,
      end: 0.97,
    ).animate(CurvedAnimation(
      parent: _tapController,
      curve: Curves.easeInOut,
    ));

    _elevationAnimation = Tween<double>(
      begin: widget.elevation,
      end: widget.elevation + 4.0,
    ).animate(CurvedAnimation(
      parent: _hoverController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _hoverController.dispose();
    _tapController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    if (!widget.isInteractive) return;
    setState(() => _isTapped = true);
    _tapController.forward();
  }

  void _onTapUp(TapUpDetails details) {
    if (!widget.isInteractive) return;
    setState(() => _isTapped = false);
    _tapController.reverse();
  }

  void _onTapCancel() {
    setState(() => _isTapped = false);
    _tapController.reverse();
  }

  void _onMouseEnter(PointerEnterEvent event) {
    if (!widget.showHoverEffect) return;
    setState(() => _isHovered = true);
    _hoverController.forward();
  }

  void _onMouseExit(PointerExitEvent event) {
    if (!widget.showHoverEffect) return;
    setState(() => _isHovered = false);
    _hoverController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_hoverAnimation, _tapAnimation]),
      builder: (context, child) {
        return Transform.scale(
          scale: _tapAnimation.value,
          child: Container(
            width: widget.width,
            height: widget.height,
            margin: widget.margin,
            alignment: widget.alignment,
            child: MouseRegion(
              onEnter: _onMouseEnter,
              onExit: _onMouseExit,
              child: GestureDetector(
                onTap: widget.onTap,
                onLongPress: widget.onLongPress,
                onTapDown: _onTapDown,
                onTapUp: _onTapUp,
                onTapCancel: _onTapCancel,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: _getDecoration(),
                  clipBehavior: widget.clipBehavior,
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      padding: widget.padding ?? const EdgeInsets.all(16.0),
                      child: widget.child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  BoxDecoration _getDecoration() {
    switch (widget.variant) {
      case PremiumCardVariant.elevated:
        return BoxDecoration(
          color: widget.backgroundColor ?? AppColors.cardGrey,
          borderRadius: widget.borderRadius ?? BorderRadius.circular(16.0),
          border: widget.border,
          gradient: widget.gradient,
          boxShadow: widget.boxShadow ?? [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: _elevationAnimation.value,
              offset: Offset(0, _elevationAnimation.value / 2),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: _elevationAnimation.value * 2,
              offset: Offset(0, _elevationAnimation.value),
            ),
          ],
        );

      case PremiumCardVariant.outlined:
        return BoxDecoration(
          color: widget.backgroundColor ?? Colors.transparent,
          borderRadius: widget.borderRadius ?? BorderRadius.circular(16.0),
          border: widget.border ?? Border.all(
            color: _isHovered 
                ? AppColors.premiumGold.withOpacity(0.5)
                : AppColors.borderGrey,
            width: _isHovered ? 2.0 : 1.0,
          ),
          gradient: widget.gradient,
          boxShadow: widget.boxShadow,
        );

      case PremiumCardVariant.filled:
        return BoxDecoration(
          color: widget.backgroundColor ?? AppColors.inputGrey,
          borderRadius: widget.borderRadius ?? BorderRadius.circular(16.0),
          border: widget.border,
          gradient: widget.gradient,
          boxShadow: widget.boxShadow,
        );

      case PremiumCardVariant.glass:
        return BoxDecoration(
          color: widget.backgroundColor ?? AppColors.glassBackground,
          borderRadius: widget.borderRadius ?? BorderRadius.circular(16.0),
          border: widget.border ?? Border.all(
            color: AppColors.glassBorder,
            width: 1.0,
          ),
          gradient: widget.gradient,
          boxShadow: widget.boxShadow ?? [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        );
    }
  }
}

enum PremiumCardVariant {
  elevated,
  outlined,
  filled,
  glass,
}

/// Specialized card widgets
class ProductCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? imageUrl;
  final String price;
  final String? originalPrice;
  final bool isOnSale;
  final double? rating;
  final int? reviewCount;
  final List<String>? tags;
  final VoidCallback? onTap;
  final VoidCallback? onFavorite;
  final VoidCallback? onAddToCart;
  final bool isFavorite;
  final bool isInStock;

  const ProductCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.imageUrl,
    required this.price,
    this.originalPrice,
    this.isOnSale = false,
    this.rating,
    this.reviewCount,
    this.tags,
    this.onTap,
    this.onFavorite,
    this.onAddToCart,
    this.isFavorite = false,
    this.isInStock = true,
  });

  @override
  Widget build(BuildContext context) {
    return PremiumCard.elevated(
      onTap: onTap,
      isInteractive: true,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildImage(),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 8),
                _buildTitle(),
                const SizedBox(height: 4),
                _buildSubtitle(),
                if (rating != null || tags != null) ...[
                  const SizedBox(height: 8),
                  _buildMetadata(),
                ],
                const SizedBox(height: 12),
                _buildFooter(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImage() {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        color: AppColors.inputGrey,
        image: imageUrl != null
            ? DecorationImage(
                image: NetworkImage(imageUrl!),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: Stack(
        children: [
          if (imageUrl == null)
            const Center(
              child: Icon(
                Icons.local_drink,
                size: 48,
                color: AppColors.mutedWhite,
              ),
            ),
          if (isOnSale)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.errorRed,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'SALE',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.primaryWhite,
                  ),
                ),
              ),
            ),
          if (!isInStock)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.disabledGrey,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'OUT OF STOCK',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.primaryWhite,
                  ),
                ),
              ),
            ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              onPressed: onFavorite,
              icon: Icon(
                isFavorite ? Icons.favorite : Icons.favorite_border,
                color: isFavorite ? AppColors.errorRed : AppColors.primaryWhite,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    if (tags == null || tags!.isEmpty) return const SizedBox.shrink();
    
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: tags!.take(2).map((tag) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.premiumGold.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            tag,
            style: AppTypography.captionSmall.copyWith(
              color: AppColors.premiumGold,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTitle() {
    return Text(
      title,
      style: AppTypography.titleMedium,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildSubtitle() {
    return Text(
      subtitle,
      style: AppTypography.bodySmall.copyWith(
        color: AppColors.mutedWhite,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildMetadata() {
    return Row(
      children: [
        if (rating != null) ...[
          Icon(
            Icons.star,
            size: 16,
            color: AppColors.warningAmber,
          ),
          const SizedBox(width: 4),
          Text(
            rating!.toStringAsFixed(1),
            style: AppTypography.captionMedium.copyWith(
              color: AppColors.lightGrey,
            ),
          ),
          if (reviewCount != null) ...[
            const SizedBox(width: 2),
            Text(
              '($reviewCount)',
              style: AppTypography.captionSmall.copyWith(
                color: AppColors.mutedWhite,
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildFooter() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    price,
                    style: AppTypography.titleLarge.copyWith(
                      color: AppColors.premiumGold,
                    ),
                  ),
                  if (originalPrice != null && isOnSale) ...[
                    const SizedBox(width: 8),
                    Text(
                      originalPrice!,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.mutedWhite,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        if (isInStock && onAddToCart != null)
          SizedBox(
            width: 40,
            height: 40,
            child: IconButton(
              onPressed: onAddToCart,
              style: IconButton.styleFrom(
                backgroundColor: AppColors.premiumGold,
                foregroundColor: AppColors.premiumBlack,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.add_shopping_cart, size: 20),
            ),
          ),
      ],
    );
  }
}

/// Stats card widget
class StatsCard extends StatelessWidget {
  final String title;
  final String value;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final String? trend;
  final bool isPositiveTrend;
  final VoidCallback? onTap;

  const StatsCard({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.trend,
    this.isPositiveTrend = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PremiumCard.elevated(
      onTap: onTap,
      isInteractive: onTap != null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (iconColor ?? AppColors.premiumGold).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: iconColor ?? AppColors.premiumGold,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.lightGrey,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: AppTypography.numberLarge,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: AppTypography.captionMedium.copyWith(
                color: AppColors.mutedWhite,
              ),
            ),
          ],
          if (trend != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  isPositiveTrend ? Icons.trending_up : Icons.trending_down,
                  size: 16,
                  color: isPositiveTrend ? AppColors.successGreen : AppColors.errorRed,
                ),
                const SizedBox(width: 4),
                Text(
                  trend!,
                  style: AppTypography.captionMedium.copyWith(
                    color: isPositiveTrend ? AppColors.successGreen : AppColors.errorRed,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}