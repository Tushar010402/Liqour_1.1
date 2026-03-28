import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../models/batch_ocr_models.dart';
import 'confidence_badge.dart';

/// Modern brand card for OCR Accept Screen
///
/// Features:
/// - Confidence percentage badge
/// - Matched brand indicator
/// - Individual selection checkbox
/// - Stock quantity display
/// - Swipe-to-delete gesture
/// - Edit quick action
class ModernOCRBrandCard extends StatefulWidget {
  final DeduplicatedItem item;
  final bool isSelected;
  final bool showCheckbox;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;
  final ValueChanged<bool>? onSelectionChanged;

  const ModernOCRBrandCard({
    super.key,
    required this.item,
    this.isSelected = false,
    this.showCheckbox = true,
    this.onTap,
    this.onEdit,
    this.onRemove,
    this.onSelectionChanged,
  });

  @override
  State<ModernOCRBrandCard> createState() => _ModernOCRBrandCardState();
}

class _ModernOCRBrandCardState extends State<ModernOCRBrandCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.98).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    setState(() => _isPressed = true);
    _controller.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    setState(() => _isPressed = false);
    _controller.reverse();
  }

  void _handleTapCancel() {
    setState(() => _isPressed = false);
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasMatch = widget.item.matchedBrandId != null;
    final confidence = widget.item.matchConfidence;
    final hasStock = widget.item.totalStock > 0;

    return ScaleTransition(
      scale: _scaleAnimation,
      child: GestureDetector(
        onTapDown: _handleTapDown,
        onTapUp: _handleTapUp,
        onTapCancel: _handleTapCancel,
        onTap: () {
          HapticFeedback.selectionClick();
          if (widget.showCheckbox && widget.onSelectionChanged != null) {
            widget.onSelectionChanged!(!widget.isSelected);
          } else if (widget.onTap != null) {
            widget.onTap!();
          }
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.isSelected
                  ? cs.primary
                  : cs.outlineVariant,
              width: widget.isSelected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.isSelected
                    ? cs.primary.withValues(alpha: 0.2)
                    : Colors.black.withValues(alpha: 0.06),
                blurRadius: widget.isSelected ? 12 : 8,
                offset: Offset(0, widget.isSelected ? 4 : 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Main content
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      // Checkbox (if enabled)
                      if (widget.showCheckbox) ...[
                        _buildCheckbox(cs),
                        const SizedBox(width: 12),
                      ],

                      // Brand icon
                      _buildBrandIcon(hasStock),
                      const SizedBox(width: 16),

                      // Brand details
                      Expanded(
                        child: _buildBrandDetails(cs, hasMatch, confidence),
                      ),

                      // Stock badge
                      const SizedBox(width: 12),
                      _buildStockBadge(cs, hasStock),
                    ],
                  ),
                ),

                // Matched brand indicator (if matched)
                if (hasMatch) _buildMatchedIndicator(),

                // Bottom action buttons
                _buildActionButtons(cs),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCheckbox(ColorScheme cs) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: widget.isSelected
            ? cs.primary
            : Colors.transparent,
        border: Border.all(
          color: widget.isSelected
              ? cs.primary
              : cs.outlineVariant,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: widget.isSelected
          ? const Icon(
              Icons.check,
              size: 16,
              color: Colors.white,
            )
          : null,
    );
  }

  Widget _buildBrandIcon(bool hasStock) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: hasStock
              ? [
                  AppColors.success,
                  AppColors.success.withValues(alpha: 0.8),
                ]
              : [
                  AppColors.neutral,
                  AppColors.neutral.withValues(alpha: 0.6),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: hasStock
                ? AppColors.success.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Icon(
        Icons.local_drink_rounded,
        color: Colors.white,
        size: 28,
      ),
    );
  }

  Widget _buildBrandDetails(ColorScheme cs, bool hasMatch, double? confidence) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Brand name with confidence badge
        Row(
          children: [
            Expanded(
              child: Text(
                widget.item.brandText,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                  letterSpacing: -0.3,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            ConfidenceBadge(
              confidence: confidence,
              size: BadgeSize.small,
              showIcon: false,
            ),
          ],
        ),
        const SizedBox(height: 6),

        // Size and category
        Row(
          children: [
            Icon(
              Icons.straighten_rounded,
              size: 14,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              widget.item.sizeText,
              style: TextStyle(
                fontSize: 15,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (widget.item.categoryId != null) ...[
              const SizedBox(width: 8),
              Text(
                '\u2022',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                _getCategoryIcon(),
                size: 14,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _getCategoryName(),
                  style: TextStyle(
                    fontSize: 15,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildStockBadge(ColorScheme cs, bool hasStock) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: hasStock
            ? LinearGradient(
                colors: [
                  AppColors.success,
                  AppColors.success.withValues(alpha: 0.8),
                ],
              )
            : LinearGradient(
                colors: [
                  cs.onSurfaceVariant.withValues(alpha: 0.2),
                  cs.onSurfaceVariant.withValues(alpha: 0.1),
                ],
              ),
        borderRadius: BorderRadius.circular(10),
        border: hasStock
            ? null
            : Border.all(
                color: cs.outlineVariant,
                width: 1,
              ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasStock ? Icons.inventory : Icons.inventory_2_outlined,
            size: 20,
            color: hasStock ? Colors.white : cs.onSurfaceVariant,
          ),
          const SizedBox(height: 4),
          Text(
            '${widget.item.totalStock}',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: hasStock ? Colors.white : cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMatchedIndicator() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              size: 16,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Smart Match Found',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Matched to existing brand in catalog',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: cs.outlineVariant,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Edit button
          Expanded(
            child: InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                widget.onEdit?.call();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.edit_outlined,
                      size: 18,
                      color: cs.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Edit Details',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: cs.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Divider
          Container(
            width: 1,
            height: 40,
            color: cs.outlineVariant,
          ),

          // Remove button
          Expanded(
            child: InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                widget.onRemove?.call();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: AppColors.error,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Remove',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.error,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getCategoryIcon() {
    // You can enhance this with actual category icons
    return Icons.category_rounded;
  }

  String _getCategoryName() {
    // This would be populated from actual category data
    // For now, show a placeholder
    return 'Liquor';
  }
}
