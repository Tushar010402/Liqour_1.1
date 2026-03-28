import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/dio_api_service.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../models/saas_brand.dart';
import '../services/brand_catalog_service.dart';
import '../providers/brand_selection_provider.dart';
import 'shopping_cart_screen.dart';
import '../widgets/variant_picker_sheet.dart';
import 'brand_detail_screen.dart';

/// Main brand selection interface with 3-column grid
/// Supports tap-to-view details and long-press (variant picker)
class BrandGridScreen extends StatefulWidget {
  final String? categoryId;
  final String categoryName;
  final String categoryIcon;

  const BrandGridScreen({
    super.key,
    required this.categoryId,
    required this.categoryName,
    required this.categoryIcon,
  });

  @override
  State<BrandGridScreen> createState() => _BrandGridScreenState();
}

class _BrandGridScreenState extends State<BrandGridScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final BrandCatalogService _brandService;

  List<SaasBrand> _brands = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _errorMessage;

  int _currentPage = 1;
  int _totalBrands = 0;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _brandService = BrandCatalogService(context.read<DioApiService>());
    _loadBrands();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadBrands({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _currentPage = 1;
        _brands.clear();
        _hasMore = true;
        _isLoading = true;
        _errorMessage = null;
      });
    } else {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final response = await _brandService.getBrandsPaginated(
        categoryId: widget.categoryId,
        search: _searchController.text.isNotEmpty ? _searchController.text : null,
        page: _currentPage,
        limit: 30,
      );

      setState(() {
        if (refresh) {
          _brands = response.brands;
        } else {
          _brands.addAll(response.brands);
        }
        _totalBrands = response.total;
        _hasMore = response.hasMore;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load brands: $e';
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _hasMore) {
        _loadMore();
      }
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _isLoadingMore) return;

    setState(() {
      _isLoadingMore = true;
      _currentPage++;
    });

    await _loadBrands();
  }

  void _onBrandTap(SaasBrand brand) {
    // Navigate to brand detail screen to view all variants and pricing
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BrandDetailScreen(brand: brand),
      ),
    );
  }

  void _onBrandLongPress(SaasBrand brand) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => VariantPickerSheet(brand: brand),
    );
  }

  void _navigateToCart() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ShoppingCartScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: CustomAppBar(
        title: widget.categoryName,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Consumer<BrandSelectionProvider>(
            builder: (context, selection, _) {
              final count = selection.totalSelectedCount;
              if (count == 0) return const SizedBox.shrink();

              return Center(
                child: Container(
                  margin: const EdgeInsets.only(right: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$count selected',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: _isLoading && _brands.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null && _brands.isEmpty
              ? _buildErrorState()
              : RefreshIndicator(
                  onRefresh: () => _loadBrands(refresh: true),
                  child: Column(
                    children: [
                      // Search Bar
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Search ${widget.categoryName.toLowerCase()}...',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _searchController.clear();
                                      _loadBrands(refresh: true);
                                    },
                                  )
                                : null,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: cs.surface,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                          onChanged: (value) {
                            // Debounce search
                          },
                          onSubmitted: (value) {
                            _loadBrands(refresh: true);
                          },
                        ),
                      ),

                      // Results Info
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Text(
                              widget.categoryIcon,
                              style: const TextStyle(fontSize: 20),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '$_totalBrands brands',
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const Spacer(),
                            Consumer<BrandSelectionProvider>(
                              builder: (context, selection, _) {
                                final selectedInCategory = _brands
                                    .where((b) => selection.isBrandSelected(b.id))
                                    .length;
                                if (selectedInCategory == 0) return const SizedBox.shrink();

                                return Text(
                                  '$selectedInCategory selected',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: cs.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Brand Grid
                      Expanded(
                        child: _brands.isEmpty
                            ? _buildEmptyState()
                            : GridView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                physics: const AlwaysScrollableScrollPhysics(),
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  childAspectRatio: 0.75,
                                ),
                                itemCount: _brands.length + (_hasMore ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index >= _brands.length) {
                                    return const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(16),
                                        child: CircularProgressIndicator(),
                                      ),
                                    );
                                  }

                                  return _buildBrandCard(_brands[index], index);
                                },
                              ),
                      ),
                    ],
                  ),
                ),
      floatingActionButton: Consumer<BrandSelectionProvider>(
        builder: (context, selection, _) {
          final count = selection.totalSelectedCount;
          if (count == 0) return const SizedBox.shrink();

          return FloatingActionButton.extended(
            onPressed: _navigateToCart,
            backgroundColor: cs.primary,
            icon: const Icon(Icons.shopping_cart),
            label: Text('View Cart ($count)'),
          );
        },
      ),
    );
  }

  Widget _buildBrandCard(SaasBrand brand, int index) {
    final cs = Theme.of(context).colorScheme;
    return Consumer<BrandSelectionProvider>(
      builder: (context, selection, _) {
        final isSelected = selection.isBrandSelected(brand.id);
        final selectedCount = selection.getSelectedVariantCount(brand.id);
        final totalCount = brand.variants.length;

        return TweenAnimationBuilder<double>(
          key: ValueKey(brand.id),
          tween: Tween(begin: 0.0, end: 1.0),
          duration: Duration(milliseconds: 300 + (index % 9 * 30)), // Stagger per row
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            return Transform.scale(
              scale: 0.8 + (value * 0.2),
              child: Opacity(
                opacity: value,
                child: child,
              ),
            );
          },
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _onBrandTap(brand),
              onLongPress: () => _onBrandLongPress(brand),
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? cs.primary : cs.outline,
                    width: isSelected ? 2 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isSelected
                          ? cs.primary.withValues(alpha:0.2)
                          : Colors.black.withValues(alpha:0.05),
                      blurRadius: isSelected ? 12 : 8,
                      offset: Offset(0, isSelected ? 4 : 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Selection Indicator
                    if (isSelected)
                      Container(
                        padding: const EdgeInsets.all(8),
                        alignment: Alignment.topRight,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: cs.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),

                    // Brand Image/Icon
                    Expanded(
                      child: Container(
                        padding: EdgeInsets.all(isSelected ? 12 : 16),
                        child: Center(
                          child: brand.picture.isNotEmpty
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    brand.picture,
                                    fit: BoxFit.contain,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Text(
                                        brand.categoryNameFromVariant?.substring(0, 1).toUpperCase() ?? '🍾',
                                        style: const TextStyle(fontSize: 40),
                                      );
                                    },
                                  ),
                                )
                              : Text(
                                  brand.categoryNameFromVariant?.substring(0, 1).toUpperCase() ?? '🍾',
                                  style: const TextStyle(fontSize: 40),
                                ),
                        ),
                      ),
                    ),

                    // Brand Info
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? cs.primary.withValues(alpha:0.05)
                            : Colors.transparent,
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(12),
                          bottomRight: Radius.circular(12),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Brand Name
                          Text(
                            brand.name,
                            style: AppTextStyles.bodySmall.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),

                          // Variant Count
                          Row(
                            children: [
                              Icon(
                                Icons.format_list_bulleted,
                                size: 12,
                                color: cs.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  isSelected
                                      ? '$selectedCount/$totalCount variants'
                                      : '$totalCount variants',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    fontSize: 10,
                                    color: isSelected
                                        ? cs.primary
                                        : cs.onSurfaceVariant,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              widget.categoryIcon,
              style: const TextStyle(fontSize: 64),
            ),
            const SizedBox(height: 16),
            Text(
              'No brands found',
              style: AppTextStyles.h5,
            ),
            const SizedBox(height: 8),
            Text(
              _searchController.text.isNotEmpty
                  ? 'Try adjusting your search'
                  : 'No brands available in this category',
              style: AppTextStyles.bodyMedium.copyWith(
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: AppColors.error,
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'An error occurred',
              style: AppTextStyles.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _loadBrands(refresh: true),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
