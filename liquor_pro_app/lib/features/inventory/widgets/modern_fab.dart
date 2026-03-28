import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/haptic_feedback.dart';

/// Modern pill-shaped FAB with count badge and animations
class ModernFAB extends StatefulWidget {
  final int selectedBrandCount;
  final int selectedVariantCount;
  final VoidCallback onPressed;
  final bool isLoading;

  const ModernFAB({
    super.key,
    required this.selectedBrandCount,
    required this.selectedVariantCount,
    required this.onPressed,
    this.isLoading = false,
  });

  @override
  State<ModernFAB> createState() => _ModernFABState();
}

class _ModernFABState extends State<ModernFAB>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    if (_isEnabled) {
      _scaleController.forward();
      HapticFeedbackUtil.selection();
    }
  }

  void _handleTapUp(TapUpDetails details) {
    _scaleController.reverse();
  }

  void _handleTapCancel() {
    _scaleController.reverse();
  }

  bool get _isEnabled =>
      widget.selectedVariantCount > 0 && !widget.isLoading;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Slide in from bottom when items selected
    return AnimatedSlide(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      offset: _isEnabled ? Offset.zero : const Offset(0, 2),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: _isEnabled ? 1.0 : 0.0,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom + 16,
            right: 16,
          ),
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: GestureDetector(
              onTapDown: _handleTapDown,
              onTapUp: _handleTapUp,
              onTapCancel: _handleTapCancel,
              onTap: _isEnabled ? widget.onPressed : null,
              child: Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  gradient: _isEnabled
                      ? LinearGradient(
                          colors: [
                            cs.primary,
                            cs.primary.withValues(alpha: 0.8),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : LinearGradient(
                          colors: [
                            cs.outlineVariant,
                            cs.onSurfaceVariant,
                          ],
                        ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: _isEnabled
                      ? [
                          BoxShadow(
                            color: cs.primary.withValues(alpha: 0.4),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                          BoxShadow(
                            color: cs.primary.withValues(alpha: 0.2),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Loading or Icon
                    if (widget.isLoading)
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      )
                    else
                      const Icon(
                        CupertinoIcons.checkmark_alt,
                        color: Colors.white,
                        size: 22,
                      ),

                    const SizedBox(width: 12),

                    // Text Content
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              widget.isLoading ? 'Onboarding...' : 'Onboard',
                              style: AppTextStyles.bodyLarge.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                height: 1.2,
                              ),
                            ),
                            if (!widget.isLoading &&
                                widget.selectedBrandCount > 0) ...[
                              const SizedBox(width: 4),
                              // Count Badge
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${widget.selectedBrandCount}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (!widget.isLoading) ...[
                          const SizedBox(height: 2),
                          Text(
                            '${widget.selectedVariantCount} variant${widget.selectedVariantCount != 1 ? 's' : ''}',
                            style: AppTextStyles.caption.copyWith(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 12,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ],
                    ),

                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact circular FAB variant for limited space
class CompactFAB extends StatelessWidget {
  final int count;
  final VoidCallback onPressed;
  final IconData icon;
  final bool isLoading;

  const CompactFAB({
    super.key,
    required this.count,
    required this.onPressed,
    this.icon = CupertinoIcons.checkmark_alt,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isEnabled = count > 0 && !isLoading;

    return FloatingActionButton(
      onPressed: isEnabled ? onPressed : null,
      backgroundColor: isEnabled ? cs.primary : cs.onSurfaceVariant,
      elevation: isEnabled ? 8 : 2,
      child: isLoading
          ? SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Colors.white.withValues(alpha: 0.8),
                ),
              ),
            )
          : Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  icon,
                  color: Colors.white,
                  size: 28,
                ),
                if (count > 0)
                  Positioned(
                    right: -8,
                    top: -8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 20,
                        minHeight: 20,
                      ),
                      child: Text(
                        count > 99 ? '99+' : '$count',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
