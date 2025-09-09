import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../constants/app_colors.dart';

class LazyLoadingWidget<T> extends StatefulWidget {
  final Future<List<T>> Function(int page, int limit) loadData;
  final Widget Function(T item, int index) itemBuilder;
  final Widget Function()? placeholderBuilder;
  final Widget Function()? emptyBuilder;
  final Widget Function(String error)? errorBuilder;
  final int itemsPerPage;
  final bool shrinkWrap;
  final ScrollPhysics? physics;
  final EdgeInsets? padding;
  final double itemSpacing;
  final Axis scrollDirection;
  final bool enablePullToRefresh;
  final VoidCallback? onRefresh;
  final String? emptyMessage;
  final Widget? loadingIndicator;

  const LazyLoadingWidget({
    super.key,
    required this.loadData,
    required this.itemBuilder,
    this.placeholderBuilder,
    this.emptyBuilder,
    this.errorBuilder,
    this.itemsPerPage = 20,
    this.shrinkWrap = false,
    this.physics,
    this.padding,
    this.itemSpacing = 8,
    this.scrollDirection = Axis.vertical,
    this.enablePullToRefresh = true,
    this.onRefresh,
    this.emptyMessage,
    this.loadingIndicator,
  });

  @override
  State<LazyLoadingWidget<T>> createState() => _LazyLoadingWidgetState<T>();
}

class _LazyLoadingWidgetState<T> extends State<LazyLoadingWidget<T>> {
  final ScrollController _scrollController = ScrollController();
  final List<T> _items = [];
  int _currentPage = 0;
  bool _isLoading = false;
  bool _hasMore = true;
  String? _error;
  bool _isInitialLoading = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitialData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      if (!_isLoading && _hasMore) {
        _loadMoreData();
      }
    }
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isInitialLoading = true;
      _error = null;
    });

    try {
      final newItems = await widget.loadData(0, widget.itemsPerPage);
      
      if (mounted) {
        setState(() {
          _items.clear();
          _items.addAll(newItems);
          _currentPage = 1;
          _hasMore = newItems.length >= widget.itemsPerPage;
          _isInitialLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isInitialLoading = false;
        });
      }
    }
  }

  Future<void> _loadMoreData() async {
    if (_isLoading || !_hasMore) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final newItems = await widget.loadData(_currentPage, widget.itemsPerPage);
      
      if (mounted) {
        setState(() {
          _items.addAll(newItems);
          _currentPage++;
          _hasMore = newItems.length >= widget.itemsPerPage;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleRefresh() async {
    if (widget.onRefresh != null) {
      widget.onRefresh!();
    }
    await _loadInitialData();
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitialLoading) {
      return _buildLoadingState();
    }

    if (_error != null && _items.isEmpty) {
      return _buildErrorState();
    }

    if (_items.isEmpty) {
      return _buildEmptyState();
    }

    Widget listView = ListView.separated(
      controller: _scrollController,
      shrinkWrap: widget.shrinkWrap,
      physics: widget.physics,
      padding: widget.padding,
      scrollDirection: widget.scrollDirection,
      itemCount: _items.length + (_hasMore || _isLoading ? 1 : 0),
      separatorBuilder: (context, index) => SizedBox(
        height: widget.scrollDirection == Axis.vertical ? widget.itemSpacing : 0,
        width: widget.scrollDirection == Axis.horizontal ? widget.itemSpacing : 0,
      ),
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          return _buildLoadMoreIndicator();
        }
        return widget.itemBuilder(_items[index], index);
      },
    );

    if (widget.enablePullToRefresh) {
      return RefreshIndicator(
        onRefresh: _handleRefresh,
        color: AppColors.primary,
        backgroundColor: AppColors.cardBackground,
        child: listView,
      );
    }

    return listView;
  }

  Widget _buildLoadingState() {
    if (widget.placeholderBuilder != null) {
      return widget.placeholderBuilder!();
    }

    if (widget.loadingIndicator != null) {
      return Center(child: widget.loadingIndicator!);
    }

    return _buildShimmerLoading();
  }

  Widget _buildShimmerLoading() {
    return Shimmer.fromColors(
      baseColor: AppColors.shimmerBase,
      highlightColor: AppColors.shimmerHighlight,
      child: ListView.separated(
        shrinkWrap: widget.shrinkWrap,
        physics: const NeverScrollableScrollPhysics(),
        padding: widget.padding ?? const EdgeInsets.all(16),
        itemCount: 8,
        separatorBuilder: (context, index) => SizedBox(height: widget.itemSpacing),
        itemBuilder: (context, index) => _buildShimmerItem(),
      ),
    );
  }

  Widget _buildShimmerItem() {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  height: 16,
                  width: double.infinity,
                  margin: const EdgeInsets.only(right: 16),
                  color: Colors.white,
                ),
                const SizedBox(height: 8),
                Container(
                  height: 12,
                  width: 120,
                  color: Colors.white,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    if (widget.errorBuilder != null) {
      return widget.errorBuilder!(_error!);
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: AppColors.error.withOpacity(0.6),
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load data',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadInitialData,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    if (widget.emptyBuilder != null) {
      return widget.emptyBuilder!();
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 64,
              color: AppColors.textSecondary.withOpacity(0.6),
            ),
            const SizedBox(height: 16),
            Text(
              widget.emptyMessage ?? 'No items found',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try adjusting your filters or refresh to see new content.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            if (widget.enablePullToRefresh) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: _handleRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLoadMoreIndicator() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            strokeWidth: 2,
          ),
        ),
      );
    }

    if (!_hasMore) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            'No more items to load',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

// Grid version for lazy loading
class LazyLoadingGrid<T> extends StatefulWidget {
  final Future<List<T>> Function(int page, int limit) loadData;
  final Widget Function(T item, int index) itemBuilder;
  final int crossAxisCount;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final double childAspectRatio;
  final int itemsPerPage;
  final EdgeInsets? padding;
  final bool enablePullToRefresh;
  final Widget Function()? emptyBuilder;
  final Widget Function(String error)? errorBuilder;

  const LazyLoadingGrid({
    super.key,
    required this.loadData,
    required this.itemBuilder,
    this.crossAxisCount = 2,
    this.crossAxisSpacing = 8,
    this.mainAxisSpacing = 8,
    this.childAspectRatio = 1.0,
    this.itemsPerPage = 20,
    this.padding,
    this.enablePullToRefresh = true,
    this.emptyBuilder,
    this.errorBuilder,
  });

  @override
  State<LazyLoadingGrid<T>> createState() => _LazyLoadingGridState<T>();
}

class _LazyLoadingGridState<T> extends State<LazyLoadingGrid<T>> {
  final ScrollController _scrollController = ScrollController();
  final List<T> _items = [];
  int _currentPage = 0;
  bool _isLoading = false;
  bool _hasMore = true;
  String? _error;
  bool _isInitialLoading = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitialData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      if (!_isLoading && _hasMore) {
        _loadMoreData();
      }
    }
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isInitialLoading = true;
      _error = null;
    });

    try {
      final newItems = await widget.loadData(0, widget.itemsPerPage);
      
      if (mounted) {
        setState(() {
          _items.clear();
          _items.addAll(newItems);
          _currentPage = 1;
          _hasMore = newItems.length >= widget.itemsPerPage;
          _isInitialLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isInitialLoading = false;
        });
      }
    }
  }

  Future<void> _loadMoreData() async {
    if (_isLoading || !_hasMore) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final newItems = await widget.loadData(_currentPage, widget.itemsPerPage);
      
      if (mounted) {
        setState(() {
          _items.addAll(newItems);
          _currentPage++;
          _hasMore = newItems.length >= widget.itemsPerPage;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleRefresh() async {
    await _loadInitialData();
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitialLoading) {
      return _buildShimmerGrid();
    }

    if (_error != null && _items.isEmpty) {
      return _buildErrorState();
    }

    if (_items.isEmpty) {
      return _buildEmptyState();
    }

    Widget gridView = CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverPadding(
          padding: widget.padding ?? const EdgeInsets.all(16),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: widget.crossAxisCount,
              crossAxisSpacing: widget.crossAxisSpacing,
              mainAxisSpacing: widget.mainAxisSpacing,
              childAspectRatio: widget.childAspectRatio,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => widget.itemBuilder(_items[index], index),
              childCount: _items.length,
            ),
          ),
        ),
        if (_isLoading || _hasMore)
          SliverToBoxAdapter(
            child: _buildLoadMoreIndicator(),
          ),
      ],
    );

    if (widget.enablePullToRefresh) {
      return RefreshIndicator(
        onRefresh: _handleRefresh,
        color: AppColors.primary,
        backgroundColor: AppColors.cardBackground,
        child: gridView,
      );
    }

    return gridView;
  }

  Widget _buildShimmerGrid() {
    return Shimmer.fromColors(
      baseColor: AppColors.shimmerBase,
      highlightColor: AppColors.shimmerHighlight,
      child: GridView.builder(
        padding: widget.padding ?? const EdgeInsets.all(16),
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: widget.crossAxisCount,
          crossAxisSpacing: widget.crossAxisSpacing,
          mainAxisSpacing: widget.mainAxisSpacing,
          childAspectRatio: widget.childAspectRatio,
        ),
        itemCount: 8,
        itemBuilder: (context, index) => Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    if (widget.errorBuilder != null) {
      return widget.errorBuilder!(_error!);
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: AppColors.error.withOpacity(0.6),
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load data',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadInitialData,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    if (widget.emptyBuilder != null) {
      return widget.emptyBuilder!();
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 64,
              color: AppColors.textSecondary.withOpacity(0.6),
            ),
            const SizedBox(height: 16),
            Text(
              'No items found',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadMoreIndicator() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
      );
    }

    if (!_hasMore) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            'No more items to load',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}