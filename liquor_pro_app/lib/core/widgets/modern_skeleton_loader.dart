import 'package:flutter/material.dart';

/// Modern skeleton loader with shimmer effect
/// Provides better UX than circular progress indicators
class SkeletonLoader extends StatefulWidget {
  final double? width;
  final double height;
  final BorderRadius? borderRadius;

  const SkeletonLoader({
    super.key,
    this.width,
    this.height = 16,
    this.borderRadius,
  });

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _animation = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius ?? BorderRadius.circular(4),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                cs.outline,
                cs.surfaceContainerHighest,
                cs.outline,
              ],
              stops: [
                _animation.value - 0.5,
                _animation.value,
                _animation.value + 0.5,
              ].map((e) => e.clamp(0.0, 1.0)).toList(),
            ),
          ),
        );
      },
    );
  }
}

/// Skeleton for list items
class ListItemSkeleton extends StatelessWidget {
  final bool hasAvatar;
  final bool hasTrailing;

  const ListItemSkeleton({
    super.key,
    this.hasAvatar = true,
    this.hasTrailing = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          if (hasAvatar)
            const SkeletonLoader(
              width: 48,
              height: 48,
              borderRadius: BorderRadius.all(Radius.circular(24)),
            ),
          if (hasAvatar) const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SkeletonLoader(width: double.infinity, height: 16),
                SizedBox(height: 8),
                SkeletonLoader(width: 200, height: 14),
              ],
            ),
          ),
          if (hasTrailing) ...[
            const SizedBox(width: 16),
            const SkeletonLoader(width: 60, height: 32),
          ],
        ],
      ),
    );
  }
}

/// Skeleton for card items
class CardSkeleton extends StatelessWidget {
  final double? height;

  const CardSkeleton({
    super.key,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      height: height ?? 160, // Increased from 120 to 160 to prevent overflow
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: const [
          SkeletonLoader(width: double.infinity, height: 20),
          SizedBox(height: 8),
          SkeletonLoader(width: 150, height: 14),
          SizedBox(height: 6),
          SkeletonLoader(width: 120, height: 14),
        ],
      ),
    );
  }
}

/// Product grid skeleton
class ProductGridSkeleton extends StatelessWidget {
  final int itemCount;

  const ProductGridSkeleton({
    super.key,
    this.itemCount = 6,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.75,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SkeletonLoader(
                width: double.infinity,
                height: 120,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SkeletonLoader(width: double.infinity, height: 16),
                    SizedBox(height: 8),
                    SkeletonLoader(width: 80, height: 14),
                    SizedBox(height: 8),
                    SkeletonLoader(width: 60, height: 18),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Generic skeleton list
class SkeletonList extends StatelessWidget {
  final int itemCount;
  final Widget Function(int index) itemBuilder;

  const SkeletonList({
    super.key,
    this.itemCount = 5,
    required this.itemBuilder,
  });

  factory SkeletonList.list({
    Key? key,
    int itemCount = 5,
    bool hasAvatar = true,
    bool hasTrailing = true,
  }) {
    return SkeletonList(
      key: key,
      itemCount: itemCount,
      itemBuilder: (index) => ListItemSkeleton(
        hasAvatar: hasAvatar,
        hasTrailing: hasTrailing,
      ),
    );
  }

  factory SkeletonList.cards({
    Key? key,
    int itemCount = 5,
    double? cardHeight,
  }) {
    return SkeletonList(
      key: key,
      itemCount: itemCount,
      itemBuilder: (index) => CardSkeleton(height: cardHeight),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: itemCount,
      itemBuilder: (context, index) => itemBuilder(index),
    );
  }
}
