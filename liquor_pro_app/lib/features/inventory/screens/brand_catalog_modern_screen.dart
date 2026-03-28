import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/haptic_feedback.dart';
import '../../../core/utils/dialog_helper.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../models/saas_brand.dart';
import '../providers/brand_onboarding_provider.dart';
import '../widgets/expandable_brand_card.dart';
import '../widgets/modern_fab.dart';
import '../widgets/advanced_filter_sheet.dart';

/// Modern single-screen brand catalog with iOS-style design
class BrandCatalogModernScreen extends StatefulWidget {
  const BrandCatalogModernScreen({super.key});

  @override
  State<BrandCatalogModernScreen> createState() =>
      _BrandCatalogModernScreenState();
}

class _BrandCatalogModernScreenState extends State<BrandCatalogModernScreen> {
  String _searchQuery = '';
  String? _selectedCategoryName;
  String? _selectedSubcategoryName;
  final Set<String> _selectedSizes = {};
  BrandFilterConfig _advancedFilters = BrandFilterConfig();
  bool _hideOnboardedBrands = false; // Toggle to show only brands not yet added

  @override
  void initState() {
    super.initState();
    print('🎯 ═══════════════════════════════════════════════════════════');
    print('🎯 SCREEN OPENED: BrandCatalogModernScreen (iOS Style Import)');
    print('🎯 FILE: brand_catalog_modern_screen.dart');
    print('🎯 ═══════════════════════════════════════════════════════════');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadBrands();
    });
  }

  Future<void> _loadBrands() async {
    final provider = context.read<BrandOnboardingProvider>();
    await provider.loadAvailableBrands();
  }

  Future<void> _refreshBrands() async {
    HapticFeedbackUtil.selection();
    await _loadBrands();
  }

  void _onSearch(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
    });
  }

  void _onCategorySelected(String categoryName) {
    setState(() {
      _selectedCategoryName = _selectedCategoryName == categoryName
          ? null
          : categoryName;
      _selectedSubcategoryName = null; // Reset subcategory
    });
    HapticFeedbackUtil.selection();
  }

  void _onSubcategorySelected(String subcategoryName) {
    setState(() {
      _selectedSubcategoryName = _selectedSubcategoryName == subcategoryName
          ? null
          : subcategoryName;
    });
    HapticFeedbackUtil.selection();
  }

  void _onSizeToggled(String size) {
    setState(() {
      if (_selectedSizes.contains(size)) {
        _selectedSizes.remove(size);
      } else {
        _selectedSizes.add(size);
      }
    });
    HapticFeedbackUtil.selection();
  }

  void _openAdvancedFilters() async {
    final provider = context.read<BrandOnboardingProvider>();

    // Prepare filter options from unique brand categories
    final uniqueCategories = _getUniqueCategories(provider.availableBrands);
    final categories = uniqueCategories
        .map(
          (categoryName) => FilterOption(
            id: categoryName,
            label: categoryName,
            icon: _getCategoryEmoji(categoryName),
          ),
        )
        .toList();

    final uniqueSubcategories = _selectedCategoryName != null
        ? _getUniqueSubcategories(
            provider.availableBrands,
            _selectedCategoryName!,
          )
        : <String>[];
    final subcategories = uniqueSubcategories
        .map(
          (subcategoryName) =>
              FilterOption(id: subcategoryName, label: subcategoryName),
        )
        .toList();

    final result = await AdvancedFilterSheet.show(
      context,
      initialConfig: _advancedFilters,
      categories: categories,
      subcategories: subcategories,
      availableSizes: _getAvailableSizes(provider.availableBrands),
      minPriceLimit: 0,
      maxPriceLimit: 10000,
    );

    if (result != null && mounted) {
      setState(() {
        _advancedFilters = result;
        // Apply advanced filters to local state
        if (result.selectedCategoryIds.length == 1) {
          _selectedCategoryName = result.selectedCategoryIds.first;
        }
        if (result.selectedSubcategoryIds.length == 1) {
          _selectedSubcategoryName = result.selectedSubcategoryIds.first;
        }
        _selectedSizes.clear();
        _selectedSizes.addAll(result.selectedSizes);
      });
    }
  }

  List<String> _getAvailableSizes(List<SaasBrand> brands) {
    final sizes = <String>{};
    for (var brand in brands) {
      for (var variant in brand.variants) {
        sizes.add(variant.size);
      }
    }
    return sizes.toList()..sort();
  }

  List<String> _getUniqueCategories(List<SaasBrand> brands) {
    final categories = <String>{};
    for (var brand in brands) {
      final categoryName = brand.categoryNameFromVariant;
      if (categoryName != null && categoryName.isNotEmpty) {
        categories.add(categoryName);
      }
    }
    return categories.toList()..sort();
  }

  List<String> _getUniqueSubcategories(
    List<SaasBrand> brands,
    String categoryName,
  ) {
    final subcategories = <String>{};
    for (var brand in brands) {
      if (brand.categoryNameFromVariant == categoryName) {
        final subcategoryName = brand.subcategoryNameFromVariant;
        if (subcategoryName != null && subcategoryName.isNotEmpty) {
          subcategories.add(subcategoryName);
        }
      }
    }
    return subcategories.toList()..sort();
  }

  String _getCategoryEmoji(String categoryName) {
    final lower = categoryName.toLowerCase();
    switch (lower) {
      case 'beer':
        return '🍺';
      case 'whiskey':
      case 'whisky':
        return '🥃';
      case 'wine':
        return '🍷';
      case 'vodka':
        return '🍸';
      case 'rum':
        return '🥃';
      case 'gin':
        return '🍸';
      default:
        return '🍾';
    }
  }

  List<SaasBrand> _filterBrands(List<SaasBrand> brands) {
    var filtered = brands;

    // HIDE ONBOARDED: Filter out already-added brands when toggle is on
    if (_hideOnboardedBrands) {
      filtered = filtered.where((brand) => brand.isOnboarded != true).toList();
    }

    // Search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((brand) {
        return brand.name.toLowerCase().contains(_searchQuery) ||
            brand.categoryNameFromVariant?.toLowerCase().contains(
                  _searchQuery,
                ) ==
                true;
      }).toList();
    }

    // Category filter
    if (_selectedCategoryName != null) {
      filtered = filtered.where((brand) {
        return brand.categoryNameFromVariant == _selectedCategoryName;
      }).toList();
    }

    // Subcategory filter
    if (_selectedSubcategoryName != null) {
      filtered = filtered.where((brand) {
        return brand.subcategoryNameFromVariant == _selectedSubcategoryName;
      }).toList();
    }

    // Size filter
    if (_selectedSizes.isNotEmpty) {
      filtered = filtered.where((brand) {
        return brand.variants.any(
          (variant) => _selectedSizes.contains(variant.size),
        );
      }).toList();
    }

    // Advanced filters - price range
    if (_advancedFilters.minPrice != null ||
        _advancedFilters.maxPrice != null) {
      filtered = filtered.where((brand) {
        return brand.variants.any((variant) {
          final price = variant.sellingPrice;
          final minOk =
              _advancedFilters.minPrice == null ||
              price >= _advancedFilters.minPrice!;
          final maxOk =
              _advancedFilters.maxPrice == null ||
              price <= _advancedFilters.maxPrice!;
          return minOk && maxOk;
        });
      }).toList();
    }

    // Show onboarded filter
    if (!_advancedFilters.showOnboarded) {
      filtered = filtered.where((brand) {
        return brand.isOnboarded != true;
      }).toList();
    }

    // Sort
    switch (_advancedFilters.sortBy) {
      case 'name_asc':
        filtered.sort((a, b) => a.name.compareTo(b.name));
        break;
      case 'name_desc':
        filtered.sort((a, b) => b.name.compareTo(a.name));
        break;
      case 'price_asc':
        filtered.sort((a, b) {
          final priceA = a.variants.isNotEmpty
              ? a.variants.first.sellingPrice
              : 0.0;
          final priceB = b.variants.isNotEmpty
              ? b.variants.first.sellingPrice
              : 0.0;
          return priceA.compareTo(priceB);
        });
        break;
      case 'price_desc':
        filtered.sort((a, b) {
          final priceA = a.variants.isNotEmpty
              ? a.variants.first.sellingPrice
              : 0.0;
          final priceB = b.variants.isNotEmpty
              ? b.variants.first.sellingPrice
              : 0.0;
          return priceB.compareTo(priceA);
        });
        break;
    }

    return filtered;
  }

  Future<void> _onboardSelectedBrands() async {
    final provider = context.read<BrandOnboardingProvider>();

    if (provider.selectedVariantIds.isEmpty) {
      SnackbarHelper.error(
        context,
        'Please select at least one variant to onboard',
      );
      return;
    }

    // Show confirmation dialog
    final confirmed = await DialogHelper.confirm(
      context: context,
      title: 'Onboard Brands?',
      message:
          'You are about to onboard ${provider.selectedBrandIds.length} brands with ${provider.selectedVariantIds.length} variants.',
      confirmText: 'Onboard',
      cancelText: 'Cancel',
    );

    if (confirmed != true) return;

    // Perform onboarding
    final success = await provider.onboardSelectedBrands();

    if (!mounted) return;

    if (success) {
      // Show success with detailed stats
      final result = provider.lastOnboardingResult;
      final message = result != null
          ? 'Successfully onboarded ${result.brandsOnboarded} brands with ${result.productsCreated} products'
          : 'Successfully onboarded ${provider.selectedBrandIds.length} brands';

      SnackbarHelper.success(context, message);
      Navigator.pop(context, true);
    } else {
      // Show detailed error dialog
      final errorMessage = provider.errorMessage ?? 'Unknown error occurred';

      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.error_outline, color: AppColors.error, size: 28),
              const SizedBox(width: 12),
              const Text('Onboarding Failed'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'The following issues prevented brand onboarding:',
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    errorMessage,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Possible reasons:',
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                _buildErrorReasonItem(
                  'Brand variants may not have complete data',
                ),
                _buildErrorReasonItem('Required fields might be missing'),
                _buildErrorReasonItem('Database constraints may have failed'),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.info.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: AppColors.info, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This is a backend data issue. Please contact support or try creating a custom brand instead.',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.info,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildErrorReasonItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '• ',
            style: AppTextStyles.bodyMedium.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.bodyMedium.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Consumer<BrandOnboardingProvider>(
          builder: (context, provider, child) {
            final filteredBrands = _filterBrands(provider.availableBrands);

            return Stack(
              children: [
                Column(
                  children: [
                    // Header
                    _buildHeader(provider),

                    // Search Bar + Filter Button + Hide Added Toggle
                    _buildSearchAndFilterBar(provider),

                    // Brand List - FULL SCREEN SCROLLABLE
                    Expanded(child: _buildBrandList(provider, filteredBrands)),
                  ],
                ),

                // Floating Action Button
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: ModernFAB(
                    selectedBrandCount: provider.selectedBrandIds.length,
                    selectedVariantCount: provider.selectedVariantIds.length,
                    onPressed: _onboardSelectedBrands,
                    isLoading: provider.isOnboarding,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Search bar with Filter button and Hide Added toggle
  Widget _buildSearchAndFilterBar(BrandOnboardingProvider provider) {
    // Count active filters
    int activeFilterCount = 0;
    if (_selectedCategoryName != null) activeFilterCount++;
    if (_selectedSubcategoryName != null) activeFilterCount++;
    activeFilterCount += _selectedSizes.length;

    final totalBrands = provider.availableBrands.length;
    final onboardedBrands = provider.availableBrands.where((b) => b.isOnboarded == true).length;

    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant, width: 1),
        ),
      ),
      child: Column(
        children: [
          // Search Row
          Row(
            children: [
              // Search Field
              Expanded(
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: TextField(
                    onChanged: _onSearch,
                    decoration: InputDecoration(
                      hintText: 'Search brands...',
                      hintStyle: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 15,
                      ),
                      prefixIcon: Icon(
                        CupertinoIcons.search,
                        color: cs.onSurfaceVariant,
                        size: 20,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
              ),

              const SizedBox(width: 10),

              // Filter Button
              GestureDetector(
                onTap: () => _showFilterBottomSheet(provider),
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: activeFilterCount > 0
                        ? cs.primary.withValues(alpha: 0.1)
                        : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                    border: activeFilterCount > 0
                        ? Border.all(color: cs.primary, width: 1)
                        : null,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        CupertinoIcons.slider_horizontal_3,
                        color: activeFilterCount > 0
                            ? cs.primary
                            : cs.onSurfaceVariant,
                        size: 18,
                      ),
                      if (activeFilterCount > 0) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: cs.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$activeFilterCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Status Row: Hide Added Toggle + Counts
          Row(
            children: [
              // Hide Added Toggle
              GestureDetector(
                onTap: () {
                  setState(() {
                    _hideOnboardedBrands = !_hideOnboardedBrands;
                  });
                  HapticFeedbackUtil.selection();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _hideOnboardedBrands
                        ? cs.primary
                        : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _hideOnboardedBrands
                          ? cs.primary
                          : cs.outlineVariant,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _hideOnboardedBrands
                            ? CupertinoIcons.eye_slash_fill
                            : CupertinoIcons.eye_fill,
                        size: 14,
                        color: _hideOnboardedBrands
                            ? Colors.white
                            : cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _hideOnboardedBrands ? 'Show Added' : 'Hide Added',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _hideOnboardedBrands
                              ? Colors.white
                              : cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const Spacer(),

              // Status Counts
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, size: 14, color: AppColors.success),
                    const SizedBox(width: 4),
                    Text(
                      '$onboardedBrands Added',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${totalBrands - onboardedBrands} remaining',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Show filter bottom sheet
  void _showFilterBottomSheet(BrandOnboardingProvider provider) {
    final filteredBrands = _filterBrands(provider.availableBrands);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final cs = Theme.of(context).colorScheme;
          return Container(
            height: MediaQuery.of(context).size.height * 0.7,
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    children: [
                      const Text(
                        'Filters',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      if (_selectedCategoryName != null ||
                          _selectedSubcategoryName != null ||
                          _selectedSizes.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedCategoryName = null;
                              _selectedSubcategoryName = null;
                              _selectedSizes.clear();
                            });
                            setModalState(() {});
                            HapticFeedbackUtil.selection();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.error.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Clear All',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.error,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                const Divider(),

                // Filter Content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Categories
                        Text(
                          'CATEGORIES',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _getUniqueCategories(provider.availableBrands)
                              .map((categoryName) {
                            final isSelected = _selectedCategoryName == categoryName;
                            final count = provider.availableBrands
                                .where((b) => b.categoryNameFromVariant == categoryName)
                                .length;
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedCategoryName = isSelected ? null : categoryName;
                                  _selectedSubcategoryName = null;
                                });
                                setModalState(() {});
                                HapticFeedbackUtil.selection();
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? cs.primary
                                      : cs.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isSelected
                                        ? cs.primary
                                        : cs.outlineVariant,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _getCategoryEmoji(categoryName),
                                      style: const TextStyle(fontSize: 16),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      categoryName,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: isSelected ? Colors.white : cs.onSurface,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? Colors.white.withValues(alpha: 0.3)
                                            : cs.outlineVariant,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        '$count',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: isSelected ? Colors.white : cs.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),

                        // Subcategories (if category selected)
                        if (_selectedCategoryName != null) ...[
                          const SizedBox(height: 24),
                          Text(
                            'SUBCATEGORIES',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurfaceVariant,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _getUniqueSubcategories(
                              provider.availableBrands,
                              _selectedCategoryName!,
                            ).map((subcategoryName) {
                              final isSelected = _selectedSubcategoryName == subcategoryName;
                              return GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedSubcategoryName = isSelected ? null : subcategoryName;
                                  });
                                  setModalState(() {});
                                  HapticFeedbackUtil.selection();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? cs.primary
                                        : cs.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: isSelected
                                          ? cs.primary
                                          : cs.outlineVariant,
                                    ),
                                  ),
                                  child: Text(
                                    subcategoryName,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: isSelected ? Colors.white : cs.onSurface,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],

                        // Sizes
                        const SizedBox(height: 24),
                        Text(
                          'SIZES',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _getAvailableSizes(provider.availableBrands)
                              .map((size) {
                            final isSelected = _selectedSizes.contains(size);
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  if (isSelected) {
                                    _selectedSizes.remove(size);
                                  } else {
                                    _selectedSizes.add(size);
                                  }
                                });
                                setModalState(() {});
                                HapticFeedbackUtil.selection();
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? cs.primary
                                      : cs.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isSelected
                                        ? cs.primary
                                        : cs.outlineVariant,
                                  ),
                                ),
                                child: Text(
                                  size,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected ? Colors.white : cs.onSurface,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),

                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),

                // Apply Button
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, -5),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cs.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Apply Filters',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(BrandOnboardingProvider provider) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Back Button
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.pop(context),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.chevron_back,
                  color: cs.primary,
                  size: 28,
                ),
                const SizedBox(width: 4),
                Text(
                  'Back',
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: cs.primary,
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // Title
          Expanded(
            flex: 3,
            child: Text(
              'Brand Catalogs',
              style: AppTextStyles.h3.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          const Spacer(),

          // Advanced Filter Button
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: _openAdvancedFilters,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  CupertinoIcons.slider_horizontal_3,
                  color: _advancedFilters.hasActiveFilters
                      ? cs.primary
                      : cs.onSurfaceVariant,
                  size: 28,
                ),
                if (_advancedFilters.hasActiveFilters)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${_advancedFilters.activeFilterCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrandList(
    BrandOnboardingProvider provider,
    List<SaasBrand> filteredBrands,
  ) {
    final cs = Theme.of(context).colorScheme;
    // Loading State
    if (provider.isLoading) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
        ),
      );
    }

    // Error State
    if (provider.errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.exclamationmark_triangle,
              size: 64,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Error Loading Brands',
              style: AppTextStyles.h3.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                provider.errorMessage!,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: cs.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            CupertinoButton(
              color: cs.primary,
              onPressed: _loadBrands,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    // Empty State
    if (filteredBrands.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('🔍', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No brands found'
                  : 'No brands available',
              style: AppTextStyles.h3.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _searchQuery.isNotEmpty
                    ? 'Try adjusting your search or filters'
                    : 'No brands are available in the catalog yet',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: cs.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    // Brand List with Pull-to-Refresh
    return RefreshIndicator(
      onRefresh: _refreshBrands,
      color: cs.primary,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        itemCount: filteredBrands.length,
        itemBuilder: (context, index) {
          final brand = filteredBrands[index];
          final isBrandSelected = provider.selectedBrandIds.contains(brand.id);

          return ExpandableBrandCard(
            key: ValueKey(brand.id),
            brand: brand,
            isSelected: isBrandSelected,
            selectedVariantIds: provider.selectedVariantIds,
            onBrandToggle: (brandId) {
              provider.toggleBrand(brandId);
              HapticFeedbackUtil.selection();
            },
            onVariantToggle: (brandId, variantId) {
              provider.toggleVariant(brandId, variantId);
              HapticFeedbackUtil.selection();
            },
          );
        },
      ),
    );
  }
}
