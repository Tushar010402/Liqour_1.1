import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Industrial-Grade Skeleton Loading Widgets
/// Best Practices:
/// - Improves perceived performance
/// - Matches actual content layout
/// - Smooth shimmer animation
/// - Configurable for different screen types

/// Base shimmer box widget
class ShimmerBox extends StatelessWidget {
  final double? width;
  final double? height;
  final double borderRadius;
  final EdgeInsetsGeometry? margin;

  const ShimmerBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius = 8,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// Shimmer wrapper with default colors
class ShimmerWrapper extends StatelessWidget {
  final Widget child;
  final Color? baseColor;
  final Color? highlightColor;

  const ShimmerWrapper({
    super.key,
    required this.child,
    this.baseColor,
    this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Shimmer.fromColors(
      baseColor: baseColor ?? cs.outline,
      highlightColor: highlightColor ?? cs.surfaceContainerHighest,
      child: child,
    );
  }
}

/// Dashboard skeleton loading
class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerWrapper(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with date picker
            Row(
              children: [
                ShimmerBox(width: 150, height: 32, borderRadius: 20),
                const Spacer(),
                ShimmerBox(width: 40, height: 40, borderRadius: 20),
              ],
            ),
            const SizedBox(height: 16),

            // Shop filter chips
            SizedBox(
              height: 36,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: 4,
                physics: const NeverScrollableScrollPhysics(),
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ShimmerBox(
                    width: i == 0 ? 50 : 80,
                    height: 36,
                    borderRadius: 18,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Stat cards - 2x2 grid
            Row(
              children: [
                Expanded(child: _buildStatCardSkeleton()),
                const SizedBox(width: 12),
                Expanded(child: _buildStatCardSkeleton()),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildStatCardSkeleton()),
                const SizedBox(width: 12),
                Expanded(child: _buildStatCardSkeleton()),
              ],
            ),
            const SizedBox(height: 24),

            // Quick Access section
            ShimmerBox(width: 120, height: 20),
            const SizedBox(height: 12),

            // Quick action buttons
            for (int i = 0; i < 3; i++) ...[
              _buildQuickActionSkeleton(),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatCardSkeleton() {
    return Container(
      height: 100,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ShimmerBox(width: 60, height: 14),
              ShimmerBox(width: 32, height: 32, borderRadius: 8),
            ],
          ),
          ShimmerBox(width: 80, height: 24),
          ShimmerBox(width: 50, height: 12),
        ],
      ),
    );
  }

  Widget _buildQuickActionSkeleton() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          ShimmerBox(width: 40, height: 40, borderRadius: 10),
          const SizedBox(width: 12),
          Expanded(child: ShimmerBox(height: 18)),
          ShimmerBox(width: 24, height: 24, borderRadius: 12),
        ],
      ),
    );
  }
}

/// List skeleton loading (for inventory, sales history, etc.)
class ListSkeleton extends StatelessWidget {
  final int itemCount;
  final double itemHeight;
  final bool hasImage;
  final EdgeInsetsGeometry padding;

  const ListSkeleton({
    super.key,
    this.itemCount = 6,
    this.itemHeight = 80,
    this.hasImage = true,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return ShimmerWrapper(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: padding,
        itemCount: itemCount,
        itemBuilder: (_, index) => _buildListItem(),
      ),
    );
  }

  Widget _buildListItem() {
    return Container(
      height: itemHeight,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          if (hasImage) ...[
            ShimmerBox(
              width: itemHeight - 24,
              height: itemHeight - 24,
              borderRadius: 8,
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ShimmerBox(width: double.infinity, height: 16),
                const SizedBox(height: 8),
                ShimmerBox(width: 120, height: 12),
                const SizedBox(height: 6),
                ShimmerBox(width: 80, height: 12),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ShimmerBox(width: 60, height: 18),
              const SizedBox(height: 6),
              ShimmerBox(width: 40, height: 12),
            ],
          ),
        ],
      ),
    );
  }
}

/// Grid skeleton loading (for products, brands, etc.)
class GridSkeleton extends StatelessWidget {
  final int itemCount;
  final int crossAxisCount;
  final double childAspectRatio;
  final EdgeInsetsGeometry padding;

  const GridSkeleton({
    super.key,
    this.itemCount = 6,
    this.crossAxisCount = 2,
    this.childAspectRatio = 0.75,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return ShimmerWrapper(
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: padding,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: childAspectRatio,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: itemCount,
        itemBuilder: (context, index) => _buildGridItem(context),
      ),
    );
  }

  Widget _buildGridItem(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image placeholder
          Expanded(
            flex: 3,
            child: Container(
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
            ),
          ),
          // Text content
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ShimmerBox(width: double.infinity, height: 14),
                  ShimmerBox(width: 80, height: 12),
                  ShimmerBox(width: 60, height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Card skeleton loading (for single cards like profile, settings)
class CardSkeleton extends StatelessWidget {
  final double height;
  final int lineCount;

  const CardSkeleton({
    super.key,
    this.height = 120,
    this.lineCount = 3,
  });

  @override
  Widget build(BuildContext context) {
    return ShimmerWrapper(
      child: Container(
        height: height,
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(
            lineCount,
            (index) => ShimmerBox(
              width: index == 0 ? 200 : (index == 1 ? 150 : 100),
              height: index == 0 ? 18 : 14,
            ),
          ),
        ),
      ),
    );
  }
}

/// Profile header skeleton
class ProfileHeaderSkeleton extends StatelessWidget {
  const ProfileHeaderSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerWrapper(
      child: Column(
        children: [
          const SizedBox(height: 20),
          // Avatar
          Container(
            width: 100,
            height: 100,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(height: 16),
          // Name
          ShimmerBox(width: 150, height: 24),
          const SizedBox(height: 8),
          // Role
          ShimmerBox(width: 100, height: 16),
          const SizedBox(height: 4),
          // Phone
          ShimmerBox(width: 120, height: 14),
        ],
      ),
    );
  }
}

/// Form skeleton loading
class FormSkeleton extends StatelessWidget {
  final int fieldCount;

  const FormSkeleton({
    super.key,
    this.fieldCount = 4,
  });

  @override
  Widget build(BuildContext context) {
    return ShimmerWrapper(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(
            fieldCount,
            (index) => Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShimmerBox(width: 80, height: 14),
                  const SizedBox(height: 8),
                  ShimmerBox(height: 52, borderRadius: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Table skeleton loading
class TableSkeleton extends StatelessWidget {
  final int rowCount;
  final int columnCount;

  const TableSkeleton({
    super.key,
    this.rowCount = 5,
    this.columnCount = 4,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ShimmerWrapper(
      child: Column(
        children: [
          // Header row
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            color: cs.surfaceContainerHighest,
            child: Row(
              children: List.generate(
                columnCount,
                (i) => Expanded(
                  child: ShimmerBox(
                    height: 14,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                ),
              ),
            ),
          ),
          // Data rows
          ...List.generate(
            rowCount,
            (rowIndex) => Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: cs.outlineVariant),
                ),
              ),
              child: Row(
                children: List.generate(
                  columnCount,
                  (colIndex) => Expanded(
                    child: ShimmerBox(
                      height: 16,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Chart skeleton loading
class ChartSkeleton extends StatelessWidget {
  final double height;

  const ChartSkeleton({
    super.key,
    this.height = 200,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ShimmerWrapper(
      child: Container(
        height: height,
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            ShimmerBox(width: 120, height: 18),
            const SizedBox(height: 16),
            // Chart area
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(
                  7,
                  (index) => Container(
                    width: 30,
                    height: (50 + (index * 15)).toDouble(),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // X-axis labels
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(
                7,
                (index) => ShimmerBox(width: 25, height: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Wrapper widget that shows skeleton while loading
class SkeletonLoader extends StatelessWidget {
  final bool isLoading;
  final Widget skeleton;
  final Widget child;
  final Duration fadeDuration;

  const SkeletonLoader({
    super.key,
    required this.isLoading,
    required this.skeleton,
    required this.child,
    this.fadeDuration = const Duration(milliseconds: 300),
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: fadeDuration,
      child: isLoading ? skeleton : child,
    );
  }
}
