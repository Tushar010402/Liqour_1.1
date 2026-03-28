import 'package:flutter/material.dart';

/// SliverPersistentHeader delegate for sticky search bar and filters
/// Provides a sticky header that remains visible while scrolling
class SearchFilterHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;

  SearchFilterHeaderDelegate({
    required this.child,
    required this.height,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final cs = Theme.of(context).colorScheme;
    // Smooth elevation transition (Swiggy/Zomato style)
    // Elevation increases when overlapping content
    final elevation = overlapsContent ? 2.0 : 0.0;

    return Material(
      elevation: elevation,
      color: cs.surface,
      child: child,
    );
  }

  @override
  bool shouldRebuild(SearchFilterHeaderDelegate oldDelegate) {
    return oldDelegate.child != child || oldDelegate.height != height;
  }
}
