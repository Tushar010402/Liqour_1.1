import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/dio_api_service.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../models/category_summary.dart';
import '../services/brand_catalog_service.dart';
import '../providers/brand_selection_provider.dart';
import 'brand_grid_screen.dart';
import 'custom_brand_form_screen.dart';

/// Category-first entry point for brand onboarding
/// Reduces cognitive load by showing 10-15 categories instead of 250+ brands
class CategorySelectionScreen extends StatefulWidget {
  const CategorySelectionScreen({super.key});

  @override
  State<CategorySelectionScreen> createState() => _CategorySelectionScreenState();
}

class _CategorySelectionScreenState extends State<CategorySelectionScreen> {
  final TextEditingController _searchController = TextEditingController();
  late final BrandCatalogService _brandService;

  List<CategorySummary> _categories = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _brandService = BrandCatalogService(context.read<DioApiService>());
    _loadCategories();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final categories = await _brandService.getCategories();

      // Sort: popular first, then by sort order
      categories.sort((a, b) {
        if (a.isPopular && !b.isPopular) return -1;
        if (!a.isPopular && b.isPopular) return 1;
        return a.sortOrder.compareTo(b.sortOrder);
      });

      setState(() {
        _categories = categories;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load categories: $e';
        _isLoading = false;
      });
    }
  }

  List<CategorySummary> get _popularCategories {
    return _categories.where((c) => c.isPopular).take(6).toList();
  }

  List<CategorySummary> get _allCategories {
    return _categories;
  }

  void _navigateToBrandGrid(CategorySummary category) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BrandGridScreen(
          categoryId: category.id,
          categoryName: category.name,
          categoryIcon: category.icon,
        ),
      ),
    );
  }

  void _navigateToAllBrands() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BrandGridScreen(
          categoryId: null, // null = all brands
          categoryName: 'All Brands',
          categoryIcon: '🍾',
        ),
      ),
    );
  }

  void _navigateToCustomBrandForm() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CustomBrandFormScreen(),
      ),
    );

    // Reload if brand was created
    if (result == true && mounted) {
      // Optionally refresh or show confirmation
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Brand created! You can now add products to it.'),
          backgroundColor: AppColors.success,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: CustomAppBar(
        title: 'Brand Onboarding',
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildErrorState()
              : RefreshIndicator(
                  onRefresh: _loadCategories,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Info Card
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha:0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: cs.primary.withValues(alpha:0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: cs.primary,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Select a category to browse brands. ${_categories.fold(0, (sum, c) => sum + c.brandCount)} brands available.',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: cs.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Search Bar
                        TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Search all brands...',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {});
                                    },
                                  )
                                : null,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: cs.surface,
                          ),
                          onChanged: (value) => setState(() {}),
                          onSubmitted: (value) {
                            if (value.isNotEmpty) {
                              // Navigate to all brands with search
                              _navigateToAllBrands();
                            }
                          },
                        ),

                        const SizedBox(height: 24),

                        // Custom Brand Creation Card
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: InkWell(
                            onTap: _navigateToCustomBrandForm,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    AppColors.success.withValues(alpha: 0.1),
                                    AppColors.success.withValues(alpha: 0.05),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppColors.success.withValues(alpha: 0.3),
                                  width: 2,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: AppColors.success,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(
                                      Icons.add_business,
                                      color: Colors.white,
                                      size: 28,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Create Custom Brand',
                                          style: AppTextStyles.bodyLarge.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.success,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Brand not in catalog? Create your own',
                                          style: AppTextStyles.bodySmall.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.arrow_forward_ios,
                                    color: AppColors.success,
                                    size: 20,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Popular Categories
                        if (_popularCategories.isNotEmpty) ...[
                          Text(
                            'Popular Categories',
                            style: AppTextStyles.h5,
                          ),
                          const SizedBox(height: 12),
                          _buildPopularCategoriesGrid(),
                          const SizedBox(height: 32),
                        ],

                        // All Categories
                        Text(
                          'All Categories',
                          style: AppTextStyles.h5,
                        ),
                        const SizedBox(height: 12),
                        _buildAllCategoriesList(),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildPopularCategoriesGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.0,
      ),
      itemCount: _popularCategories.length,
      itemBuilder: (context, index) {
        return _buildCategoryCard(_popularCategories[index], index);
      },
    );
  }

  Widget _buildCategoryCard(CategorySummary category, int index) {
    final cs = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      key: ValueKey(category.id),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 300 + (index * 50)), // Stagger
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: Opacity(
            opacity: value,
            child: child,
          ),
        );
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _navigateToBrandGrid(category),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: cs.outline,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha:0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon
                Text(
                  category.icon,
                  style: const TextStyle(fontSize: 32),
                ),
                const SizedBox(height: 8),

                // Category Name
                Text(
                  category.name,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),

                // Brand Count Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${category.brandCount}',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAllCategoriesList() {
    final cs = Theme.of(context).colorScheme;
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _allCategories.length,
      itemBuilder: (context, index) {
        final category = _allCategories[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Text(
              category.icon,
              style: const TextStyle(fontSize: 28),
            ),
            title: Text(
              category.name,
              style: AppTextStyles.bodyLarge.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              '${category.brandCount} brands',
              style: AppTextStyles.bodySmall.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _navigateToBrandGrid(category),
          ),
        );
      },
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
              onPressed: _loadCategories,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
