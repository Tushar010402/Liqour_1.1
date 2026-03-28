import 'package:flutter/material.dart';
import '../../../core/theme/ios_design_tokens.dart';
import '../../../core/utils/responsive_utils.dart';

/// UserListSkeleton - Shimmer loading state for user list
///
/// Matches the AdaptiveUserCard layout for smooth transitions.
///
/// Usage:
/// ```dart
/// if (isLoading) {
///   return UserListSkeleton(itemCount: 8);
/// }
/// ```
class UserListSkeleton extends StatefulWidget {
  /// Number of skeleton items to show
  final int itemCount;

  /// Whether to show inside a ListView (true) or Column (false)
  final bool scrollable;

  const UserListSkeleton({
    super.key,
    this.itemCount = 8,
    this.scrollable = true,
  });

  @override
  State<UserListSkeleton> createState() => _UserListSkeletonState();
}

class _UserListSkeletonState extends State<UserListSkeleton>
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
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPhone = ResponsiveUtils.isPhone(context);

    if (widget.scrollable) {
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: widget.itemCount,
        itemBuilder: (context, index) => _buildSkeletonCard(isPhone, index),
      );
    }

    return Column(
      children: List.generate(
        widget.itemCount,
        (index) => _buildSkeletonCard(isPhone, index),
      ),
    );
  }

  Widget _buildSkeletonCard(bool isPhone, int index) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: EdgeInsets.all(isPhone ? 12 : 16),
          decoration: BoxDecoration(
            color: iOSDesignTokens.neutralWhite,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: iOSDesignTokens.neutralBlack.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Avatar skeleton
              _ShimmerBox(
                width: isPhone ? 44 : 56,
                height: isPhone ? 44 : 56,
                borderRadius: BorderRadius.circular(isPhone ? 22 : 28),
                animation: _animation,
                delay: index * 0.1,
              ),
              SizedBox(width: isPhone ? 12 : 16),

              // Content skeleton
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _ShimmerBox(
                            height: 16,
                            width: 140,
                            animation: _animation,
                            delay: index * 0.1 + 0.1,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _ShimmerBox(
                          height: 20,
                          width: 60,
                          borderRadius: BorderRadius.circular(10),
                          animation: _animation,
                          delay: index * 0.1 + 0.2,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _ShimmerBox(
                      height: 12,
                      width: 200,
                      animation: _animation,
                      delay: index * 0.1 + 0.15,
                    ),
                    if (!isPhone) ...[
                      const SizedBox(height: 6),
                      _ShimmerBox(
                        height: 12,
                        width: 120,
                        animation: _animation,
                        delay: index * 0.1 + 0.2,
                      ),
                    ],
                  ],
                ),
              ),

              // Role badge skeleton
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _ShimmerBox(
                    height: isPhone ? 24 : 28,
                    width: isPhone ? 70 : 90,
                    borderRadius: BorderRadius.circular(14),
                    animation: _animation,
                    delay: index * 0.1 + 0.25,
                  ),
                  if (!isPhone) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ShimmerBox(
                          height: 32,
                          width: 32,
                          borderRadius: BorderRadius.circular(8),
                          animation: _animation,
                          delay: index * 0.1 + 0.3,
                        ),
                        const SizedBox(width: 4),
                        _ShimmerBox(
                          height: 32,
                          width: 32,
                          borderRadius: BorderRadius.circular(8),
                          animation: _animation,
                          delay: index * 0.1 + 0.35,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ShimmerBox extends StatelessWidget {
  final double? width;
  final double height;
  final BorderRadius? borderRadius;
  final Animation<double> animation;
  final double delay;

  const _ShimmerBox({
    this.width,
    required this.height,
    this.borderRadius,
    required this.animation,
    this.delay = 0,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final shimmerValue = (animation.value + delay) % 4 - 2;
        final opacity = (1 - shimmerValue.abs() / 2).clamp(0.3, 0.7);

        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: borderRadius ?? BorderRadius.circular(4),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                iOSDesignTokens.neutralGray200.withOpacity(opacity),
                iOSDesignTokens.neutralGray100.withOpacity(opacity + 0.2),
                iOSDesignTokens.neutralGray200.withOpacity(opacity),
              ],
              stops: [
                0.0,
                (shimmerValue + 2) / 4,
                1.0,
              ],
            ),
          ),
        );
      },
    );
  }
}

/// UserGridSkeleton - Grid version of skeleton for tablet/desktop
class UserGridSkeleton extends StatelessWidget {
  final int itemCount;
  final int columns;

  const UserGridSkeleton({
    super.key,
    this.itemCount = 6,
    this.columns = 2,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 2.5,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) => _GridSkeletonCard(index: index),
    );
  }
}

class _GridSkeletonCard extends StatefulWidget {
  final int index;

  const _GridSkeletonCard({required this.index});

  @override
  State<_GridSkeletonCard> createState() => _GridSkeletonCardState();
}

class _GridSkeletonCardState extends State<_GridSkeletonCard>
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
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: iOSDesignTokens.neutralWhite,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: iOSDesignTokens.neutralBlack.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          _ShimmerBox(
            width: 56,
            height: 56,
            borderRadius: BorderRadius.circular(28),
            animation: _animation,
            delay: widget.index * 0.1,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ShimmerBox(
                  height: 16,
                  width: 140,
                  animation: _animation,
                  delay: widget.index * 0.1 + 0.1,
                ),
                const SizedBox(height: 8),
                _ShimmerBox(
                  height: 12,
                  width: 180,
                  animation: _animation,
                  delay: widget.index * 0.1 + 0.15,
                ),
                const SizedBox(height: 6),
                _ShimmerBox(
                  height: 12,
                  width: 100,
                  animation: _animation,
                  delay: widget.index * 0.1 + 0.2,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ShimmerBox(
                height: 28,
                width: 90,
                borderRadius: BorderRadius.circular(14),
                animation: _animation,
                delay: widget.index * 0.1 + 0.25,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                  3,
                  (i) => Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: _ShimmerBox(
                      height: 32,
                      width: 32,
                      borderRadius: BorderRadius.circular(8),
                      animation: _animation,
                      delay: widget.index * 0.1 + 0.3 + i * 0.05,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
