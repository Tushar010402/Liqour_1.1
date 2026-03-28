import 'dart:ui';
import 'package:flutter/material.dart';

/// Floating header with glassmorphic blur effect that shows/hides on scroll
/// Features:
/// - Auto-hide on scroll down
/// - Auto-show on scroll up
/// - Smooth fade and slide animations
/// - Blur backdrop effect
class FloatingBlurHeader extends StatefulWidget {
  final Widget child;
  final ScrollController scrollController;
  final double height;
  final Color? backgroundColor;
  final double blurSigma;
  final bool pinned;

  const FloatingBlurHeader({
    super.key,
    required this.child,
    required this.scrollController,
    this.height = 60,
    this.backgroundColor,
    this.blurSigma = 10,
    this.pinned = false,
  });

  @override
  State<FloatingBlurHeader> createState() => _FloatingBlurHeaderState();
}

class _FloatingBlurHeaderState extends State<FloatingBlurHeader>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _slideAnimation;
  late Animation<double> _opacityAnimation;

  double _lastScrollOffset = 0;
  bool _isVisible = true;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
      value: 1.0, // Start visible
    );

    _slideAnimation = Tween<double>(
      begin: -widget.height,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));

    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));

    if (!widget.pinned) {
      widget.scrollController.addListener(_onScroll);
    }
  }

  void _onScroll() {
    final currentOffset = widget.scrollController.offset;
    final delta = currentOffset - _lastScrollOffset;

    // Show header when scrolling up or at top
    if (delta < -5 || currentOffset < 50) {
      if (!_isVisible) {
        setState(() {
          _isVisible = true;
        });
        _animationController.forward();
      }
    }
    // Hide header when scrolling down
    else if (delta > 5 && currentOffset > 50) {
      if (_isVisible) {
        setState(() {
          _isVisible = false;
        });
        _animationController.reverse();
      }
    }

    _lastScrollOffset = currentOffset;
  }

  @override
  void dispose() {
    if (!widget.pinned) {
      widget.scrollController.removeListener(_onScroll);
    }
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundColor = widget.backgroundColor ??
        theme.colorScheme.surface.withOpacity(0.8);

    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, widget.pinned ? 0 : _slideAnimation.value),
          child: Opacity(
            opacity: widget.pinned ? 1.0 : _opacityAnimation.value,
            child: Container(
              height: widget.height,
              decoration: BoxDecoration(
                color: backgroundColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: widget.blurSigma,
                    sigmaY: widget.blurSigma,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}
