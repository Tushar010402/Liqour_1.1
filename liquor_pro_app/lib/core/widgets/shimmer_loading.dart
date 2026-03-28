import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Reusable Shimmer Loading Widgets - Best Practice Loading States
/// Centralized loading components for consistent UX

class ShimmerLoading {
  ShimmerLoading._();

  // Theme-aware default colors (require context)
  static Color _defaultBaseColor(BuildContext context) =>
      Theme.of(context).colorScheme.outline;
  static Color _defaultHighlightColor(BuildContext context) =>
      Theme.of(context).colorScheme.surfaceContainerHighest;

  /// Generic shimmer container
  static Widget container({
    required double width,
    required double height,
    BorderRadius? borderRadius,
    Color? baseColor,
    Color? highlightColor,
  }) {
    return Builder(builder: (context) => Shimmer.fromColors(
      baseColor: baseColor ?? _defaultBaseColor(context),
      highlightColor: highlightColor ?? _defaultHighlightColor(context),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: borderRadius ?? BorderRadius.circular(8),
        ),
      ),
    ));
  }

  /// Shimmer for card
  static Widget card({
    double? width,
    double height = 200,
    BorderRadius? borderRadius,
  }) {
    return Builder(builder: (context) => Shimmer.fromColors(
      baseColor: _defaultBaseColor(context),
      highlightColor: _defaultHighlightColor(context),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: borderRadius ?? BorderRadius.circular(16),
        ),
      ),
    ));
  }

  /// Shimmer for list tile
  static Widget listTile() {
    return Builder(builder: (context) => Shimmer.fromColors(
      baseColor: _defaultBaseColor(context),
      highlightColor: _defaultHighlightColor(context),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(width: 16),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    height: 16,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 200,
                    height: 12,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 150,
                    height: 12,
                    color: Colors.white,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ));
  }

  /// Shimmer for text line
  static Widget text({
    double width = double.infinity,
    double height = 16,
    BorderRadius? borderRadius,
  }) {
    return Builder(builder: (context) => Shimmer.fromColors(
      baseColor: _defaultBaseColor(context),
      highlightColor: _defaultHighlightColor(context),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: borderRadius ?? BorderRadius.circular(4),
        ),
      ),
    ));
  }

  /// Shimmer for circular avatar
  static Widget circle({
    double size = 60,
  }) {
    return Builder(builder: (context) => Shimmer.fromColors(
      baseColor: _defaultBaseColor(context),
      highlightColor: _defaultHighlightColor(context),
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
      ),
    ));
  }

  /// Shimmer for grid item
  static Widget gridItem({
    double? width,
    double height = 200,
  }) {
    return Builder(builder: (context) => Shimmer.fromColors(
      baseColor: _defaultBaseColor(context),
      highlightColor: _defaultHighlightColor(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: width,
            height: height * 0.7,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: width,
            height: 16,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: width != null ? width * 0.6 : 100,
            height: 12,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    ));
  }

  /// Shimmer for stat card
  static Widget statCard({
    double width = 140,
    double height = 100,
  }) {
    return Builder(builder: (context) => Shimmer.fromColors(
      baseColor: _defaultBaseColor(context),
      highlightColor: _defaultHighlightColor(context),
      child: Container(
        width: width,
        height: height,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    ));
  }

  /// Shimmer for product card (inventory)
  static Widget productCard() {
    return Builder(builder: (context) => Shimmer.fromColors(
      baseColor: _defaultBaseColor(context),
      highlightColor: _defaultHighlightColor(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 120,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    height: 16,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 100,
                    height: 12,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        width: 60,
                        height: 14,
                        color: Colors.white,
                      ),
                      Container(
                        width: 60,
                        height: 14,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ));
  }

  /// Shimmer for app bar
  static Widget appBar({
    double height = 56,
  }) {
    return Builder(builder: (context) => Shimmer.fromColors(
      baseColor: _defaultBaseColor(context),
      highlightColor: _defaultHighlightColor(context),
      child: Container(
        height: height,
        color: Colors.white,
      ),
    ));
  }

  /// Custom shimmer widget
  static Widget custom({
    required Widget child,
    Color? baseColor,
    Color? highlightColor,
  }) {
    return Builder(builder: (context) => Shimmer.fromColors(
      baseColor: baseColor ?? _defaultBaseColor(context),
      highlightColor: highlightColor ?? _defaultHighlightColor(context),
      child: child,
    ));
  }
}
