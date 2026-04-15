import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/providers/shop_selection_provider.dart';
import '../providers/product_provider.dart';
import '../models/product.dart';
import '../models/product_with_stock.dart';
import '../models/inventory_filters.dart';
import '../models/sort_option.dart';
import '../widgets/sort_menu.dart';
import '../widgets/compact_product_grid_card.dart';
import '../widgets/dense_product_list_tile.dart';
import '../widgets/empty_inventory_state.dart';
import 'brand_import_screen.dart';
import 'brand_catalog_modern_screen.dart';
import 'brand_onboarding_setup_screen.dart';
import 'custom_brand_form_screen.dart';
import 'invoice_ocr_screen.dart';
import '../../../core/widgets/modern_skeleton_loader.dart';
import '../../navigation/screens/main_navigation_screen.dart';
import '../../../core/widgets/modern_retry_widget.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/utils/logger.dart';
import '../../../core/constants/size_range_constants.dart';

/// Helper class to cache selected product's category and size info
/// Used to maintain selection counts even when switching tabs
class _SelectedProductInfo {
  final String? categoryId;
  final String size;

  _SelectedProductInfo({this.categoryId, required this.size});
}

/// Modern iOS 16-Inspired Inventory Screen
/// Features: Advanced filters, sorting, compact cards, search
///
/// Auto-Refresh Design:
/// - Automatically refreshes shop list on init (picks up newly created shops)
/// - No manual refresh button needed
/// - Provider pattern ensures all screens stay in sync
class ProductsGridScreen extends StatefulWidget {
  final bool isGridView;
  final VoidCallback? onToggleView;

  // Selection state for multi-select stock purchase
  final Set<String>? selectedProductIds;
  final Function(String productId)? onProductSelectionToggle;

  // Initial category/size from inventory setup flow
  final String? initialCategory;
  final String? initialSize;

  const ProductsGridScreen({
    super.key,
    this.isGridView = false,
    this.onToggleView,
    this.selectedProductIds,
    this.onProductSelectionToggle,
    this.initialCategory,
    this.initialSize,
  });

  @override
  State<ProductsGridScreen> createState() => _ProductsGridScreenState();
}

class _ProductsGridScreenState extends State<ProductsGridScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ScrollController _categoryFilterScrollController = ScrollController(keepScrollOffset: true); // For category filter auto-scroll
  final ScrollController _sizeFilterScrollController = ScrollController(keepScrollOffset: true); // For size filter auto-scroll

  // Track pending scroll to restore after rebuild
  int? _pendingSizeScrollIndex;
  int? _pendingSizeScrollTotal;
  int? _pendingCategoryScrollIndex;
  int? _pendingCategoryScrollTotal;
  Timer? _searchDebounce;
  bool _isLoadingMore = false;
  bool _isSearchExpanded = false; // For inline search in header

  InventoryFilters _filters = const InventoryFilters();
  SortOption _currentSort = SortOption.sizeHighToLow; // Default: Size High to Low, then Price
  String _searchQuery = '';

  // Inline filter state (like Daily Sales Entry)
  // Backend filtering: category_id passed to API for accurate results across all pages
  String? _selectedCategoryId;          // Category ID for backend filtering
  String? _selectedCategoryName;        // Category name for display
  String? _selectedSize;                // Single-select size (client-side filtering)
  bool _showInStockOnly = true;        // Toggle: show only products with stock > 0
  bool _hasSetDefaultCategory = false;  // Track if default category was set
  bool _hasSetDefaultSize = false;      // Track if default size was set
  bool _hasRestoredFilters = false;     // Track if filters have been restored from provider
  bool _isInitialLoad = true;           // Track if initial load in initState is complete
  bool get _isSetupFlowMode => widget.initialCategory != null; // Setup flow provides category+size

  // Cache for selected products' metadata (persists across tab switches)
  // Key: productId, Value: {categoryId, size}
  final Map<String, _SelectedProductInfo> _selectedProductsCache = {};

  // Priority order for categories (case-insensitive matching)
  static const List<String> _categoryPriority = ['whisky', 'beer', 'rum', 'vodka', 'wine', 'gin'];

  // Combined category groups - "English" = Whisky + Rum + Vodka
  // Note: Include both 'whisky' and 'whiskey' spellings for compatibility
  static const String _englishGroupName = 'English';
  static const List<String> _englishCategories = ['whisky', 'whiskey', 'rum', 'vodka'];

  // Track if combined "English" filter is selected
  bool _isEnglishFilterSelected = false;
  List<String> _selectedCategoryIds = []; // For combined category filtering

  /// Get category IDs for the "English" combined filter (Whisky + Rum + Vodka)
  List<String> _getEnglishCategoryIds(List<Category> categories) {
    return categories
        .where((c) => _englishCategories.any((e) => c.name.toLowerCase().contains(e)))
        .map((c) => c.id)
        .toList();
  }

  /// Get total product count for "English" combined categories
  int _getEnglishProductCount(List<Category> categories) {
    return categories
        .where((c) => _englishCategories.any((e) => c.name.toLowerCase().contains(e)))
        .fold(0, (sum, c) => sum + (c.productCount ?? 0));
  }

  /// Check if a category is part of the "English" group
  bool _isEnglishCategory(Category category) {
    return _englishCategories.any((e) => category.name.toLowerCase().contains(e));
  }

  /// Sort categories with priority: Whisky first, then Beer, then others alphabetically
  List<Category> _getSortedCategories(List<Category> categories) {
    final activeCategories = categories.where((c) => c.isActive).toList();

    activeCategories.sort((a, b) {
      final aLower = a.name.toLowerCase();
      final bLower = b.name.toLowerCase();

      final aIndex = _categoryPriority.indexWhere((p) => aLower.contains(p));
      final bIndex = _categoryPriority.indexWhere((p) => bLower.contains(p));

      // Both have priority - sort by priority index
      if (aIndex != -1 && bIndex != -1) return aIndex.compareTo(bIndex);
      // Only a has priority - a comes first
      if (aIndex != -1) return -1;
      // Only b has priority - b comes first
      if (bIndex != -1) return 1;
      // Neither has priority - sort alphabetically
      return aLower.compareTo(bLower);
    });

    return activeCategories;
  }

  /// Get default category based on priority (Whisky > Beer > first available)
  Category? _getDefaultCategory(List<Category> categories) {
    final sorted = _getSortedCategories(categories);
    if (sorted.isEmpty) return null;

    // Return first category (already sorted by priority)
    return sorted.first;
  }

  /// Update cache when products are loaded - store category/size info for selected products
  /// This ensures selection counts persist when switching tabs
  void _updateSelectedProductsCache(List<ProductWithStock> products) {
    for (final product in products) {
      if (widget.selectedProductIds?.contains(product.id) ?? false) {
        _selectedProductsCache[product.id] = _SelectedProductInfo(
          categoryId: product.category?.id,
          size: product.size.toUpperCase(),
        );
      }
    }
    // Clean up cache: remove products that are no longer selected
    _selectedProductsCache.removeWhere(
      (id, _) => !(widget.selectedProductIds?.contains(id) ?? false),
    );
  }

  /// Calculate how many selected products belong to a specific category
  /// Uses cache to maintain counts even when products are not in current view
  int _getSelectionCountForCategory(String categoryId) {
    if (widget.selectedProductIds == null || widget.selectedProductIds!.isEmpty) {
      return 0;
    }
    return _selectedProductsCache.values
        .where((info) => info.categoryId == categoryId)
        .length;
  }

  /// Calculate how many selected products belong to a specific size
  /// Uses cache to maintain counts even when products are not in current view
  int _getSelectionCountForSize(String size) {
    if (widget.selectedProductIds == null || widget.selectedProductIds!.isEmpty) {
      return 0;
    }
    return _selectedProductsCache.values
        .where((info) => info.size == size.toUpperCase())
        .length;
  }

  /// Calculate total selection count (for "All" chip)
  int _getTotalSelectionCount() {
    return widget.selectedProductIds?.length ?? 0;
  }

  /// Restore filters from provider (called on navigation back)
  /// Always re-syncs from provider to handle cases where another screen
  /// (e.g., Daily Sales Entry) modified the provider's filter state
  void _restoreFiltersFromProvider() {
    final provider = context.read<ProductProvider>();
    final shopProvider = context.read<ShopSelectionProvider>();

    final providerCategoryId = provider.selectedCategoryId;
    final providerCategoryName = provider.selectedCategoryName;
    final providerSize = provider.selectedSize;

    // Check if provider state differs from local state
    final hasChanged = _selectedCategoryId != providerCategoryId ||
        _selectedCategoryName != providerCategoryName ||
        _selectedSize != providerSize;

    // Only restore if provider has values AND state has changed (avoid unnecessary rebuilds)
    if (providerCategoryName != null || providerSize != null) {
      if (hasChanged || !_hasRestoredFilters) {
        setState(() {
          _selectedCategoryId = providerCategoryId;
          _selectedCategoryName = providerCategoryName;
          _selectedSize = providerSize;
          _hasRestoredFilters = true;
          if (_selectedCategoryName != null) _hasSetDefaultCategory = true;
          if (_selectedSize != null) _hasSetDefaultSize = true;
        });
        Logger.info('🔄 [ProductsGridScreen] Restored filters from provider: category=$_selectedCategoryName, size=$_selectedSize');

        // CRITICAL FIX: Load sizes when restoring filters
        // Otherwise size filter row won't show because availableSizesWithCounts is empty
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            provider.loadAvailableSizes(
              categoryId: _selectedCategoryId,
              shopId: shopProvider.selectedShopId,
            );
          }
        });
      }
    } else if (_hasRestoredFilters && hasChanged) {
      // Provider filters were cleared (e.g., by another screen) - reset local state too
      // This prevents stale filter chips from showing when provider has no filters
      setState(() {
        _selectedCategoryId = null;
        _selectedCategoryName = null;
        _selectedSize = null;
        _hasRestoredFilters = false;
        _hasSetDefaultCategory = false;
        _hasSetDefaultSize = false;
      });
      Logger.info('🔄 [ProductsGridScreen] Provider filters cleared - resetting local state');
    }
  }

  /// Sync local filter state to provider (for persistence)
  void _syncFiltersToProvider() {
    final provider = context.read<ProductProvider>();
    provider.setSelectedCategory(_selectedCategoryId, _selectedCategoryName);
    provider.setSelectedSize(_selectedSize);
    Logger.info('💾 [ProductsGridScreen] Synced filters to provider: category=$_selectedCategoryName, size=$_selectedSize');
  }

  /// Scroll category filter chips to show the selected category
  /// Uses estimated chip width to calculate scroll offset
  void _scrollToSelectedCategory(int selectedIndex, int totalCount) {
    if (!_categoryFilterScrollController.hasClients) return;
    if (selectedIndex < 0 || totalCount <= 0) return;

    // Estimated chip width (label + count badge + padding + margin)
    // Average category chip is approximately 80-100 pixels wide
    const estimatedChipWidth = 90.0;
    const chipMargin = 8.0; // Right margin

    // Calculate target offset to center the selected chip
    final screenWidth = MediaQuery.of(context).size.width;
    final targetOffset = (selectedIndex * (estimatedChipWidth + chipMargin)) - (screenWidth / 2) + (estimatedChipWidth / 2);

    // Clamp to valid scroll range
    final maxScroll = _categoryFilterScrollController.position.maxScrollExtent;
    final clampedOffset = targetOffset.clamp(0.0, maxScroll);

    // Smooth scroll animation
    _categoryFilterScrollController.animateTo(
      clampedOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
    Logger.debug('📍 [ProductsGridScreen] Auto-scrolled category filter to index $selectedIndex (offset: $clampedOffset)');
  }

  /// Scroll to show active category and size filters on screen
  /// Called after initialization to ensure selected filters are visible
  /// Uses double post-frame callback for reliable scrolling after ListView renders
  void _scrollToActiveFilters(List<dynamic> categories, List<dynamic> sizes) {
    // Get sorted categories to find the correct index
    final sortedCategories = _getSortedCategories(categories.cast());

    // Calculate and store pending scroll indices
    if (_selectedCategoryId != null && !_isEnglishFilterSelected) {
      final categoryIndex = sortedCategories.indexWhere((c) => c.id == _selectedCategoryId);
      if (categoryIndex >= 0) {
        _pendingCategoryScrollIndex = categoryIndex + 1; // +1 for English chip
        _pendingCategoryScrollTotal = sortedCategories.length + 1;
      }
    } else if (_isEnglishFilterSelected) {
      _pendingCategoryScrollIndex = 0;
      _pendingCategoryScrollTotal = sortedCategories.length + 1;
    }

    if (_selectedSize != null && sizes.isNotEmpty) {
      final sizeIndex = sizes.indexWhere((s) {
        if (s is String) return s.toUpperCase() == _selectedSize?.toUpperCase();
        return s.size?.toString().toUpperCase() == _selectedSize?.toUpperCase();
      });
      if (sizeIndex >= 0) {
        _pendingSizeScrollIndex = sizeIndex;
        _pendingSizeScrollTotal = sizes.length;
      }
    }

    // First callback: wait for widget tree to build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Second callback: wait for ListView to render and have scroll extent
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        // Scroll to active category
        if (_pendingCategoryScrollIndex != null) {
          if (_pendingCategoryScrollIndex == 0) {
            // English is index 0, scroll to beginning
            if (_categoryFilterScrollController.hasClients) {
              _categoryFilterScrollController.animateTo(0.0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
              );
            }
          } else {
            _scrollToSelectedCategory(
              _pendingCategoryScrollIndex!,
              _pendingCategoryScrollTotal ?? 1,
            );
          }
          _pendingCategoryScrollIndex = null;
          _pendingCategoryScrollTotal = null;
        }

        // Scroll to active size
        if (_pendingSizeScrollIndex != null) {
          _scrollToSelectedSize(
            _pendingSizeScrollIndex!,
            _pendingSizeScrollTotal ?? 1,
          );
          _pendingSizeScrollIndex = null;
          _pendingSizeScrollTotal = null;
        }

        Logger.debug('📍 [ProductsGridScreen] Auto-scrolled to active filters - Category: $_selectedCategoryName, Size: $_selectedSize');
      });
    });
  }

  /// Scroll size filter chips to show the selected size
  /// Uses estimated chip width to calculate scroll offset
  void _scrollToSelectedSize(int selectedIndex, int totalCount) {
    if (!_sizeFilterScrollController.hasClients) return;
    if (selectedIndex < 0 || totalCount <= 0) return;

    // Estimated chip width (label + stock badge + padding + margin)
    // Average size chip is approximately 100-120 pixels wide
    const estimatedChipWidth = 110.0;
    const chipMargin = 8.0; // Right margin

    // Calculate target offset to center the selected chip
    final screenWidth = MediaQuery.of(context).size.width;
    final targetOffset = (selectedIndex * (estimatedChipWidth + chipMargin)) - (screenWidth / 2) + (estimatedChipWidth / 2);

    // Clamp to valid scroll range
    final maxScroll = _sizeFilterScrollController.position.maxScrollExtent;
    final clampedOffset = targetOffset.clamp(0.0, maxScroll);

    // Smooth scroll animation
    _sizeFilterScrollController.animateTo(
      clampedOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
    Logger.debug('📍 [ProductsGridScreen] Auto-scrolled size filter to index $selectedIndex (offset: $clampedOffset)');
  }

  @override
  void initState() {
    super.initState();
    Logger.info('🎯 ═══════════════════════════════════════════════════════════');
    Logger.info('🎯 SCREEN OPENED: ProductsGridScreen (Modern iOS 16 Inventory)');
    Logger.info('🎯 FILE: products_grid_screen.dart');
    Logger.info('🎯 ═══════════════════════════════════════════════════════════');

    // Setup infinite scroll listener
    _scrollController.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      Logger.debug('📦 [ProductsGridScreen] Initializing...');
      final shopProvider = context.read<ShopSelectionProvider>();
      final productProvider = context.read<ProductProvider>();

      // Always refresh shops to get newly created ones
      Logger.debug('📦 [ProductsGridScreen] Refreshing shops list...');
      await shopProvider.refreshShops();

      while (shopProvider.isLoading) {
        await Future.delayed(const Duration(milliseconds: 100));
      }

      final shopId = shopProvider.selectedShopId;
      Logger.debug('📦 [ProductsGridScreen] Initial shop ID: $shopId');
      Logger.debug('📦 [ProductsGridScreen] Available shops: ${shopProvider.shops.length}');
      if (shopProvider.shops.isNotEmpty) {
        Logger.debug('📦 [ProductsGridScreen] Shop names: ${shopProvider.shops.map((s) => s.name).join(", ")}');
      }

      // Load categories first
      Logger.debug('📦 [ProductsGridScreen] Loading categories with shopId: $shopId');
      await productProvider.loadCategories(shopId: shopId);

      // ── SETUP FLOW MODE: Use initial category + size from inventory setup ──
      if (_isSetupFlowMode && mounted) {
        Logger.debug('📦 [ProductsGridScreen] SETUP FLOW: category=${widget.initialCategory}, size=${widget.initialSize}');
        final isEnglish = widget.initialCategory == 'English';
        final isBeer = widget.initialCategory == 'Beer';

        if (isEnglish) {
          final englishIds = _getEnglishCategoryIds(productProvider.categories);
          setState(() {
            _isEnglishFilterSelected = true;
            _selectedCategoryIds = englishIds;
            _selectedCategoryName = 'English';
            _selectedSize = widget.initialSize;
            _hasSetDefaultCategory = true;
            _hasSetDefaultSize = widget.initialSize != null;
          });
          await productProvider.loadAvailableSizes(categoryIds: englishIds, shopId: shopId);
          await productProvider.loadProducts(shopId: shopId, categoryIds: englishIds, size: widget.initialSize);
        } else if (isBeer) {
          final beerCat = productProvider.categories.where((c) => c.name.toLowerCase().contains('beer')).firstOrNull;
          if (beerCat != null) {
            setState(() {
              _isEnglishFilterSelected = false;
              _selectedCategoryId = beerCat.id;
              _selectedCategoryName = beerCat.name;
              _selectedCategoryIds = [beerCat.id];
              _selectedSize = widget.initialSize;
              _hasSetDefaultCategory = true;
              _hasSetDefaultSize = true;
            });
            await productProvider.loadAvailableSizes(categoryId: beerCat.id, shopId: shopId);
            await productProvider.loadProducts(shopId: shopId, categoryId: beerCat.id, size: widget.initialSize);
          }
        }
        await productProvider.loadStock(shopId: shopId);
        if (mounted) setState(() => _isInitialLoad = false);
        return; // Skip default logic
      }

      // ── DEFAULT MODE: Auto-select category + size ──
      if (!_hasSetDefaultCategory && productProvider.categories.isNotEmpty) {
        final defaultCategory = _getDefaultCategory(productProvider.categories);
        if (defaultCategory != null && mounted) {
          setState(() {
            _isEnglishFilterSelected = false; // Ensure English is not selected
            _selectedCategoryId = defaultCategory.id;
            _selectedCategoryName = defaultCategory.name;
            _selectedCategoryIds = [defaultCategory.id]; // Set single category in list
            _hasSetDefaultCategory = true;
          });
          _syncFiltersToProvider(); // Persist to provider for navigation
          Logger.debug('📦 [ProductsGridScreen] Default category set: ${defaultCategory.name} (ID: ${defaultCategory.id})');

          // Load sizes and WAIT for them, then auto-select first size and load products
          await productProvider.loadAvailableSizes(categoryId: defaultCategory.id, shopId: shopId);

          // Auto-select first size and load products with both category and size filters
          if (mounted && productProvider.availableSizesWithCounts.isNotEmpty) {
            final firstSize = productProvider.availableSizesWithCounts.first;
            setState(() {
              _selectedSize = firstSize.size;
              _hasSetDefaultSize = true;
            });
            _syncFiltersToProvider();
            Logger.debug('📏 [ProductsGridScreen] Auto-selected first size: ${firstSize.displayLabel}');
            await productProvider.loadProducts(
              shopId: shopId,
              categoryId: defaultCategory.id,
              size: firstSize.size,
            );

            // Auto-scroll to show active category and size filters
            if (mounted) {
              _scrollToActiveFilters(
                productProvider.categories,
                productProvider.availableSizesWithCounts,
              );
            }
          } else {
            // No sizes available — clear any stale size filter, load products with just category
            Logger.debug('📦 [ProductsGridScreen] No sizes available, clearing size filter and loading with category only');
            setState(() {
              _selectedSize = null;
              _hasSetDefaultSize = false;
            });
            _syncFiltersToProvider();
            await productProvider.loadProducts(shopId: shopId, categoryId: defaultCategory.id);

            // Auto-scroll to show active category filter
            if (mounted) {
              _scrollToActiveFilters(productProvider.categories, []);
            }
          }
        } else {
          // No categories available, load all products and sizes
          productProvider.loadProducts(shopId: shopId);
          productProvider.loadAvailableSizes(shopId: shopId);
        }
      } else if (_hasSetDefaultCategory && _selectedCategoryId != null) {
        // CRITICAL FIX: If category was restored from provider, still load sizes for it
        Logger.debug('📦 [ProductsGridScreen] Category already set (restored): $_selectedCategoryName, loading sizes');
        await productProvider.loadAvailableSizes(categoryId: _selectedCategoryId, shopId: shopId);

        // Auto-select first size if not already set
        if (!_hasSetDefaultSize && productProvider.availableSizesWithCounts.isNotEmpty && mounted) {
          final firstSize = productProvider.availableSizesWithCounts.first;
          setState(() {
            _selectedSize = firstSize.size;
            _hasSetDefaultSize = true;
          });
          _syncFiltersToProvider();
          Logger.debug('📏 [ProductsGridScreen] Auto-selected first size (restored): ${firstSize.displayLabel}');
        } else if (productProvider.availableSizesWithCounts.isEmpty && _selectedSize != null && mounted) {
          // Sizes unavailable — clear stale size filter to avoid ghost filtering
          Logger.debug('📦 [ProductsGridScreen] Sizes empty (restored path), clearing stale size filter: $_selectedSize');
          setState(() {
            _selectedSize = null;
            _hasSetDefaultSize = false;
          });
          _syncFiltersToProvider();
        }

        // Load products with restored/auto-selected filters
        await productProvider.loadProducts(shopId: shopId, categoryId: _selectedCategoryId, size: _selectedSize);

        // Auto-scroll to show active category and size filters
        if (mounted) {
          _scrollToActiveFilters(
            productProvider.categories,
            productProvider.availableSizesWithCounts,
          );
        }
      } else {
        // Load all products if no categories
        productProvider.loadProducts(shopId: shopId);
        productProvider.loadAvailableSizes(shopId: shopId);
      }

      productProvider.loadBrands();
      _isInitialLoad = false;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Restore filters from provider (persisted across navigation)
    _restoreFiltersFromProvider();
    // Auto-refresh when screen becomes visible (after navigation back)
    // Provider's refreshProducts() uses stored filters for correct loading
    if (!_isInitialLoad && mounted) {
      final shopProvider = context.read<ShopSelectionProvider>();
      final productProvider = context.read<ProductProvider>();
      productProvider.loadProducts(
        shopId: shopProvider.selectedShopId,
        categoryId: _selectedCategoryId,
        size: _selectedSize,
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _categoryFilterScrollController.dispose(); // Dispose category filter scroll controller
    _sizeFilterScrollController.dispose(); // Dispose size filter scroll controller
    _searchDebounce?.cancel();
    super.dispose();
  }

  /// Instagram-style infinite scroll - auto-load when near bottom
  void _onScroll() {
    if (_isLoadingMore) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    final threshold = 200.0; // Load more when 200px from bottom

    if (currentScroll >= maxScroll - threshold) {
      final productProvider = context.read<ProductProvider>();
      final shopProvider = context.read<ShopSelectionProvider>();

      if (productProvider.hasMore && !productProvider.isLoading) {
        Logger.debug('📜 [InfiniteScroll] Loading more products... (categoryId: $_selectedCategoryId, size: $_selectedSize)');
        setState(() => _isLoadingMore = true);

        productProvider.loadProducts(
          shopId: shopProvider.selectedShopId,
          categoryId: _selectedCategoryId, // Pass category filter to backend
          size: _selectedSize, // ✅ FIX: Pass size filter to backend
          page: productProvider.currentPage + 1,
          append: true,
        ).then((_) {
          if (mounted) {
            setState(() => _isLoadingMore = false);
          }
        });
      }
    }
  }

  /// Debounced search to prevent excessive rebuilds
  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      setState(() => _searchQuery = value);
    });
  }

  /// Extract unique sizes from products
  List<String> _getUniqueSizes(List<Product> products) {
    final sizes = products.map((p) => p.size).toSet().toList();
    sizes.sort();
    return sizes;
  }

  /// Get unique category names from products (for inline filter chips)
  List<String> _getAvailableCategories(List<Product> products) {
    final categories = <String>{};
    for (var product in products) {
      if (product.category != null && product.category!.name.isNotEmpty) {
        categories.add(product.category!.name);
      }
    }
    return categories.toList()..sort();
  }

  /// Get unique sizes from products (normalized to uppercase)
  /// DYNAMIC: Only shows sizes for products in the selected category
  List<String> _getAvailableSizes(List<Product> products) {
    // Filter products by selected category first (like Daily Sales Entry)
    final filteredProducts = _selectedCategoryName != null
        ? products.where((p) => p.category?.name == _selectedCategoryName).toList()
        : products;

    final sizes = <String>{};
    for (var product in filteredProducts) {
      if (product.size.isNotEmpty) {
        sizes.add(product.size.toUpperCase());
      }
    }
    // Sort by numeric value
    final sizeList = sizes.toList();
    sizeList.sort((a, b) {
      final aNum = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      final bNum = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      return aNum.compareTo(bNum);
    });
    return sizeList;
  }

  /// Clear inline filters
  void _clearInlineFilters() {
    setState(() {
      _selectedCategoryId = null;
      _selectedCategoryName = null;
      _selectedSize = null;
    });
    _syncFiltersToProvider(); // Persist to provider
    Logger.info('🧹 [ProductsGridScreen] All inline filters cleared');
  }

  /// Show shop selector modal (like Daily Sales Entry)
  void _showShopSelectorModal(ShopSelectionProvider shopProvider, ProductProvider productProvider) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.store, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                const Text(
                  'Select Shop',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            ...shopProvider.shops.map((shop) {
              final isSelected = shop.id == shopProvider.selectedShopId;
              return ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                        : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.store,
                    color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                title: Text(
                  shop.name,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                subtitle: shop.address.isNotEmpty
                    ? Text(shop.address, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant))
                    : null,
                trailing: isSelected
                    ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () async {
                  shopProvider.selectShop(shop);
                  Navigator.pop(context);

                  // ═══════════════════════════════════════════════════════════════
                  // SHOP CHANGE - Clear all local state and reload for new shop
                  // CRITICAL: Must await all async operations for proper UI update
                  // Auto-selects default category (Whisky) and first size
                  // ═══════════════════════════════════════════════════════════════
                  Logger.info('🔄 [ProductsGridScreen] Shop changed to: ${shop.name} (${shop.id})');

                  // Clear filters and reset default category flag
                  setState(() {
                    _isEnglishFilterSelected = false;
                    _selectedCategoryId = null;
                    _selectedCategoryName = null;
                    _selectedCategoryIds = [];
                    _selectedSize = null;
                    _hasSetDefaultCategory = false;
                    _hasSetDefaultSize = false;
                    _hasRestoredFilters = false;
                  });

                  // Clear provider filters when shop changes
                  productProvider.clearAllFilters();
                  Logger.debug('🔄 [ProductsGridScreen] Filters cleared, loading data for new shop...');

                  // Load categories first
                  await productProvider.loadCategories(shopId: shop.id);

                  // Set default category for new shop (Whisky > Beer > first)
                  if (productProvider.categories.isNotEmpty && mounted) {
                    final defaultCategory = _getDefaultCategory(productProvider.categories);
                    if (defaultCategory != null) {
                      setState(() {
                        _isEnglishFilterSelected = false;
                        _selectedCategoryId = defaultCategory.id;
                        _selectedCategoryName = defaultCategory.name;
                        _selectedCategoryIds = [defaultCategory.id];
                        _hasSetDefaultCategory = true;
                      });
                      Logger.debug('🏷️ [ProductsGridScreen] Default category: ${defaultCategory.name} (ID: ${defaultCategory.id})');

                      // Load available sizes and WAIT for them
                      await productProvider.loadAvailableSizes(
                        categoryId: defaultCategory.id,
                        shopId: shop.id,
                      );

                      // Auto-select first size and load products with BOTH filters
                      if (mounted && productProvider.availableSizesWithCounts.isNotEmpty) {
                        final firstSize = productProvider.availableSizesWithCounts.first;
                        setState(() {
                          _selectedSize = firstSize.size;
                          _hasSetDefaultSize = true;
                        });
                        _syncFiltersToProvider();
                        Logger.debug('📏 [ProductsGridScreen] Auto-selected size: ${firstSize.size}');

                        // Auto-scroll size filter to beginning (first size selected)
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (_sizeFilterScrollController.hasClients) {
                            _sizeFilterScrollController.animateTo(
                              0.0,
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeOut,
                            );
                          }
                        });

                        // Load products with both category AND size
                        await productProvider.loadProducts(
                          shopId: shop.id,
                          categoryId: defaultCategory.id,
                          size: firstSize.size,
                        );
                      } else {
                        // No sizes, load with category only
                        _syncFiltersToProvider();
                        await productProvider.loadProducts(
                          shopId: shop.id,
                          categoryId: defaultCategory.id,
                        );
                      }
                      Logger.info('✅ [ProductsGridScreen] Products loaded for ${shop.name}');
                    } else {
                      // No category - load all products for shop
                      await productProvider.loadProducts(shopId: shop.id, categoryId: null);
                      await productProvider.loadAvailableSizes(shopId: shop.id);
                    }
                  } else {
                    // No categories available - load all products for shop
                    await productProvider.loadProducts(shopId: shop.id, categoryId: null);
                    await productProvider.loadAvailableSizes(shopId: shop.id);
                  }

                  // Force UI rebuild after all data loaded
                  if (mounted) {
                    setState(() {});
                    Logger.info('✅ [ProductsGridScreen] Shop change complete, UI refreshed');
                  }
                },
              );
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// Apply filters and search to products
  List<ProductWithStock> _getFilteredProducts(ProductProvider provider) {
    var products = provider.productsWithStock;

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      products = products.where((p) {
        return p.name.toLowerCase().contains(query) ||
            p.barcode.toLowerCase().contains(query) ||
            (p.brand?.name.toLowerCase().contains(query) ?? false) ||
            (p.category?.name.toLowerCase().contains(query) ?? false);
      }).toList();
    }

    // NOTE: Category filtering is now handled by backend via loadProducts(categoryId: ...)
    // No client-side category filtering needed - backend returns only matching products

    // NOTE: Size filtering is now handled by backend via loadProducts(size: ...)
    // Backend accepts range labels and filters by ML range server-side
    // No client-side size filtering needed

    // Apply "In Stock Only" toggle filter (show only products with stock > 0)
    if (_showInStockOnly) {
      products = products.where((p) => p.currentStock > 0).toList();
    }

    // Apply category filter (from modal)
    if (_filters.selectedCategoryIds.isNotEmpty) {
      products = products.where((p) {
        return _filters.selectedCategoryIds.contains(p.product.categoryId);
      }).toList();
    }

    // Apply subcategory filter
    if (_filters.selectedSubcategoryIds.isNotEmpty) {
      products = products.where((p) {
        return p.product.subcategoryId != null &&
            _filters.selectedSubcategoryIds.contains(p.product.subcategoryId);
      }).toList();
    }

    // Apply brand filter
    if (_filters.selectedBrandIds.isNotEmpty) {
      products = products.where((p) {
        return _filters.selectedBrandIds.contains(p.product.brandId);
      }).toList();
    }

    // Apply size filter
    if (_filters.selectedSizes.isNotEmpty) {
      products = products.where((p) {
        return _filters.selectedSizes.any((size) =>
            p.size.toLowerCase().contains(size.toLowerCase()));
      }).toList();
    }

    // Apply stock status filter
    if (_filters.stockStatus != StockStatusFilter.all) {
      products = products.where((p) {
        switch (_filters.stockStatus) {
          case StockStatusFilter.healthy:
            return p.currentStock > 50;
          case StockStatusFilter.low:
            return p.currentStock > 10 && p.currentStock <= 50;
          case StockStatusFilter.critical:
            return p.currentStock > 0 && p.currentStock <= 10;
          case StockStatusFilter.outOfStock:
            return p.currentStock == 0;
          case StockStatusFilter.all:
            return true;
        }
      }).toList();
    }

    // Apply price range filter
    if (_filters.priceRange != null) {
      products = products.where((p) {
        return p.sellingPrice >= _filters.priceRange!.min &&
            p.sellingPrice <= _filters.priceRange!.max;
      }).toList();
    }

    // Apply active status filter
    if (_filters.isActive != null) {
      products = products.where((p) {
        return p.isActive == _filters.isActive;
      }).toList();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SORTING LOGIC: Match Daily Sales Entry screen behavior EXACTLY
    // Daily Sales Entry default: Price (low→high) → Brand (alphabetical) → Size (larger first)
    // When "English" filter is active: Use same sorting as Daily Sales Entry
    // Otherwise: Use default sort option selected by user
    // ═══════════════════════════════════════════════════════════════════════════
    List<ProductWithStock> sortedProducts;

    if (_isEnglishFilterSelected) {
      // Match Daily Sales Entry sorting EXACTLY:
      // Sort by: Price (low→high) → Brand Name (alphabetical) → Size (larger first)
      sortedProducts = List<ProductWithStock>.from(products);
      sortedProducts.sort((a, b) {
        // 1. Sort by price (low to high) - primary sort
        final priceCompare = a.sellingPrice.compareTo(b.sellingPrice);
        if (priceCompare != 0) return priceCompare;

        // 2. Same price - sort by brand name (alphabetical)
        final brandA = a.brand?.name ?? '';
        final brandB = b.brand?.name ?? '';
        final brandCompare = brandA.compareTo(brandB);
        if (brandCompare != 0) return brandCompare;

        // 3. Same brand - sort by size (larger first)
        final sizeA = _extractSizeValue(a.size);
        final sizeB = _extractSizeValue(b.size);
        return sizeB.compareTo(sizeA);
      });
    } else {
      // Use default sort option for non-English filters
      sortedProducts = _currentSort.apply(products);
    }

    return sortedProducts;
  }

  /// Extract numeric value from size string (e.g., "650ML" -> 650)
  int _extractSizeValue(String size) {
    final numStr = size.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(numStr) ?? 0;
  }

  Future<void> _refreshData() async {
    final shopProvider = context.read<ShopSelectionProvider>();
    final productProvider = context.read<ProductProvider>();

    // Refresh shops list
    await shopProvider.refreshShops();

    // Reload products (preserving category AND size filter) and categories for the selected shop
    final shopId = shopProvider.selectedShopId;
    await Future.wait([
      productProvider.loadProducts(
        shopId: shopId,
        categoryId: _selectedCategoryId, // Preserve current category filter
        size: _selectedSize, // ✅ FIX: Preserve current size filter
      ),
      productProvider.loadCategories(shopId: shopId),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ProductProvider>(
      builder: (context, provider, _) {
        // Auto-reload sizes if they got cleared by another screen (e.g. brand onboarding)
        if (provider.availableSizesWithCounts.isEmpty &&
            !provider.isSizesLoading &&
            _selectedCategoryId != null &&
            _hasSetDefaultCategory &&
            provider.hasInitializedProducts) {
          final shopId = context.read<ShopSelectionProvider>().selectedShopId;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              provider.loadAvailableSizes(categoryId: _selectedCategoryId, shopId: shopId);
            }
          });
        }

        // Modern skeleton loader - show during loading OR before first load completes
        if (provider.isLoading || !provider.hasInitializedProducts) {
          return const ProductGridSkeleton(itemCount: 8);
        }

        // Modern error retry widget
        if (provider.errorMessage != null) {
          return ModernRetryWidget(
            message: 'Failed to load products',
            errorDetails: provider.errorMessage,
            onRetry: () => provider.refreshProducts(),
          );
        }

        // Only show empty state AFTER products have been loaded at least once
        // This prevents showing empty state during initial load before API responds
        if (provider.products.isEmpty && provider.hasInitializedProducts) {
          Logger.debug('📦 [ProductsGridScreen] Showing empty state - products: ${provider.products.length}, initialized: ${provider.hasInitializedProducts}');
          return EmptyInventoryState(
            type: EmptyStateType.noProducts,
            onBrowseCatalog: () async {
              // Navigate to brand catalog
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const BrandOnboardingSetupScreen(),
                ),
              );

              // Refresh if brands were onboarded
              if (result == true && mounted) {
                await _refreshData();
              }
            },
            onCreateCustom: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CustomBrandFormScreen(),
                ),
              );
            },
            onScanInvoice: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const InvoiceOCRScreen(),
                ),
              );
            },
            onExcelImport: () async {
              // Navigate to Excel import
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const BrandImportScreen(),
                ),
              );

              // Refresh if import was successful
              if (result == true && mounted) {
                await _refreshData();
              }
            },
          );
        }

        final filteredProducts = _getFilteredProducts(provider);

        // Update cache with current products' category/size info for selection badges
        // This ensures selection counts persist when switching category/size tabs
        _updateSelectedProductsCache(provider.productsWithStock);

        return RefreshIndicator(
          onRefresh: _refreshData,
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              // Header — setup flow gets clean daily-sales-entry style; normal gets full toolbar
              if (_isSetupFlowMode)
                SliverAppBar(
                  pinned: true,
                  elevation: 0,
                  backgroundColor: Colors.white,
                  surfaceTintColor: Colors.transparent,
                  toolbarHeight: 48,
                  automaticallyImplyLeading: false,
                  titleSpacing: 0,
                  bottom: PreferredSize(
                    preferredSize: const Size.fromHeight(1),
                    child: Container(height: 1, color: const Color(0xFFEAEDF1)),
                  ),
                  title: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        // Back button — blue circle with chevron (matches daily sales entry)
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: const BoxDecoration(
                              color: Color(0xFF1349B8),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.chevron_left, color: Colors.white, size: 22),
                          ),
                        ),
                        // Centered title
                        Expanded(
                          child: Text(
                            'Inventory',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.montserratAlternates(
                              fontSize: 19,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF18181B),
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                        // Search icon (right side)
                        GestureDetector(
                          onTap: () => setState(() => _isSearchExpanded = !_isSearchExpanded),
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: const BoxDecoration(
                              color: Color(0xFFEBF1FA),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _isSearchExpanded ? Icons.close : Icons.search,
                              size: 18,
                              color: const Color(0xFF18181B),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
              SliverAppBar(
                pinned: true,
                floating: false,
                elevation: 1,
                backgroundColor: Theme.of(context).colorScheme.surface,
                toolbarHeight: 56,
                automaticallyImplyLeading: false,
                titleSpacing: 0,
                title: Consumer<ShopSelectionProvider>(
                  builder: (context, shopProvider, _) {
                    return Padding(
                      padding: const EdgeInsets.only(left: 4, right: 12),
                      child: Row(
                        children: [
                          // Back Button - Only show for salesman role
                          // Non-salesman users (manager, admin, owner) navigate via bottom nav
                          Consumer<AuthProvider>(
                            builder: (context, authProvider, _) {
                              final userRole = authProvider.currentUser?.role.toLowerCase() ?? '';
                              final isSalesman = userRole == 'salesman';

                              if (!isSalesman) {
                                // Add some left padding when back button is hidden
                                return const SizedBox(width: 8);
                              }

                              return IconButton(
                                onPressed: () {
                                  // Switch to Home tab via parent MainNavigationScreen
                                  final navState = context.findAncestorStateOfType<MainNavigationScreenState>();
                                  if (navState != null) {
                                    navState.switchToTab(0);
                                  } else if (context.canPop()) {
                                    context.pop();
                                  } else {
                                    context.go('/home');
                                  }
                                },
                                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                                color: Theme.of(context).colorScheme.onSurface,
                                iconSize: 22,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                              );
                            },
                          ),

                          // Expandable Search OR Shop Selector
                          if (_isSearchExpanded) ...[
                            // Expanded Search Field
                            Expanded(
                              child: Container(
                                height: 38,
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: TextField(
                                  controller: _searchController,
                                  autofocus: true,
                                  style: const TextStyle(fontSize: 14),
                                  decoration: InputDecoration(
                                    hintText: 'Search products...',
                                    hintStyle: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                    prefixIcon: Icon(Icons.search, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                    suffixIcon: IconButton(
                                      icon: Icon(Icons.close, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() {
                                          _searchQuery = '';
                                          _isSearchExpanded = false;
                                        });
                                      },
                                    ),
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                                  ),
                                  onChanged: _onSearchChanged,
                                ),
                              ),
                            ),
                          ] else ...[
                            // Shop Selector (compact like Daily Sales)
                            Expanded(
                              child: GestureDetector(
                                onTap: () => _showShopSelectorModal(shopProvider, provider),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.store, size: 16, color: Theme.of(context).colorScheme.primary),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          shopProvider.selectedShop?.name ?? 'Select Shop',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Theme.of(context).colorScheme.onSurface,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(Icons.keyboard_arrow_down, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Search Icon Button
                            IconButton(
                              icon: Icon(Icons.search, color: Theme.of(context).colorScheme.onSurface, size: 22),
                              onPressed: () => setState(() => _isSearchExpanded = true),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                            ),
                          ],

                          // Sort Menu (always visible)
                          SortMenu(
                            currentSort: _currentSort,
                            onSortChanged: (sort) {
                              setState(() => _currentSort = sort);
                            },
                          ),

                          // Modern "In Stock" Toggle - compact pill design
                          if (!_isSearchExpanded)
                            GestureDetector(
                              onTap: () => setState(() => _showInStockOnly = !_showInStockOnly),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _showInStockOnly
                                      ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: _showInStockOnly
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context).colorScheme.outlineVariant,
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _showInStockOnly
                                          ? Icons.inventory_2
                                          : Icons.inventory_2_outlined,
                                      size: 14,
                                      color: _showInStockOnly
                                          ? Theme.of(context).colorScheme.primary
                                          : Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Stock',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: _showInStockOnly
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                        color: _showInStockOnly
                                            ? Theme.of(context).colorScheme.primary
                                            : Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          // View Toggle
                          if (widget.onToggleView != null && !_isSearchExpanded) ...[
                            IconButton(
                              icon: Icon(
                                widget.isGridView ? Icons.view_list : Icons.grid_view,
                                color: Theme.of(context).colorScheme.primary,
                                size: 22,
                              ),
                              onPressed: widget.onToggleView,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),

              // Inline Category Filter Chips — hidden in setup flow mode (setup already selected category)
              if (!_isSetupFlowMode && (provider.categories.isNotEmpty || provider.isCategoriesLoading))
                SliverToBoxAdapter(
                  child: Container(
                    color: Theme.of(context).colorScheme.surface,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: SizedBox(
                      height: 36,
                      child: provider.isCategoriesLoading
                          ? Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            )
                          : Builder(
                              builder: (context) {
                                final sortedCategories = _getSortedCategories(provider.categories);
                                final englishCategoryIds = _getEnglishCategoryIds(provider.categories);
                                final englishProductCount = _getEnglishProductCount(provider.categories);
                                // Total chips = 1 (English) + individual categories
                                final totalChipCount = 1 + sortedCategories.length;

                                return ListView(
                                  controller: _categoryFilterScrollController, // Auto-scroll controller
                                  scrollDirection: Axis.horizontal,
                                  children: [
                                    // ═══════════════════════════════════════════════════════════════
                                    // COMBINED "ENGLISH" CHIP - Shows Whisky + Rum + Vodka together
                                    // First chip, always visible at the start
                                    // ═══════════════════════════════════════════════════════════════
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: _buildCompactChip(
                                        label: _englishGroupName,
                                        isSelected: _isEnglishFilterSelected,
                                        count: englishProductCount,
                                        selectionCount: null,
                                        onTap: () async {
                                          if (_isEnglishFilterSelected) {
                                            Logger.info('🏷️ [ProductsGridScreen] English already selected, ignoring tap');
                                            return;
                                          }

                                          final shopProvider = context.read<ShopSelectionProvider>();

                                          // PRESERVE current size to try to keep it selected
                                          final previousSize = _selectedSize;

                                          setState(() {
                                            _isEnglishFilterSelected = true;
                                            _selectedCategoryId = null; // Clear single category
                                            _selectedCategoryName = _englishGroupName;
                                            _selectedCategoryIds = englishCategoryIds;
                                            _selectedSize = null;
                                            _hasSetDefaultSize = false;
                                          });
                                          Logger.info('🏷️ [ProductsGridScreen] English filter selected (${englishCategoryIds.length} categories)');

                                          // Auto-scroll to beginning (English is first)
                                          WidgetsBinding.instance.addPostFrameCallback((_) {
                                            if (_categoryFilterScrollController.hasClients) {
                                              _categoryFilterScrollController.animateTo(0.0,
                                                duration: const Duration(milliseconds: 200),
                                                curve: Curves.easeOut,
                                              );
                                            }
                                          });

                                          // Load sizes for combined categories
                                          await provider.loadAvailableSizes(
                                            categoryIds: englishCategoryIds,
                                            shopId: shopProvider.selectedShopId,
                                          );

                                          // UX ENHANCEMENT: Try to keep the same size selected if it exists
                                          if (mounted && provider.availableSizesWithCounts.isNotEmpty) {
                                            String selectedSize;
                                            int selectedSizeIndex = 0;

                                            // Check if previous size exists in new category
                                            if (previousSize != null) {
                                              final matchingIndex = provider.availableSizesWithCounts.indexWhere(
                                                (s) => s.size.toUpperCase() == previousSize.toUpperCase()
                                              );
                                              if (matchingIndex >= 0) {
                                                selectedSize = provider.availableSizesWithCounts[matchingIndex].size;
                                                selectedSizeIndex = matchingIndex;
                                                Logger.debug('📏 [ProductsGridScreen] Preserved size: $selectedSize');
                                              } else {
                                                selectedSize = provider.availableSizesWithCounts.first.size;
                                                selectedSizeIndex = 0;
                                                Logger.debug('📏 [ProductsGridScreen] Size $previousSize not available, defaulting to: $selectedSize');
                                              }
                                            } else {
                                              selectedSize = provider.availableSizesWithCounts.first.size;
                                              selectedSizeIndex = 0;
                                              Logger.debug('📏 [ProductsGridScreen] Auto-selected first size: $selectedSize');
                                            }

                                            setState(() {
                                              _selectedSize = selectedSize;
                                              _hasSetDefaultSize = true;
                                            });
                                            _syncFiltersToProvider();

                                            // Auto-scroll to show the selected size
                                            WidgetsBinding.instance.addPostFrameCallback((_) {
                                              _scrollToSelectedSize(selectedSizeIndex, provider.availableSizesWithCounts.length);
                                            });

                                            // Load products with combined category IDs
                                            provider.loadProducts(
                                              shopId: shopProvider.selectedShopId,
                                              categoryIds: englishCategoryIds,
                                              size: selectedSize,
                                            );
                                          } else {
                                            _syncFiltersToProvider();
                                            provider.loadProducts(
                                              shopId: shopProvider.selectedShopId,
                                              categoryIds: englishCategoryIds,
                                            );
                                          }
                                        },
                                        selectedColor: Theme.of(context).colorScheme.primary,
                                      ),
                                    ),

                                    // ═══════════════════════════════════════════════════════════════
                                    // INDIVIDUAL CATEGORY CHIPS - One MUST always be selected
                                    // Clicking already-selected category does nothing
                                    // Auto-selects first available size when category changes
                                    // Auto-scrolls to show selected category
                                    // ═══════════════════════════════════════════════════════════════
                                    ...sortedCategories.asMap().entries.map((entry) {
                                      final index = entry.key + 1; // +1 for English chip
                                      final category = entry.value;
                                      final selectionCount = _getSelectionCountForCategory(category.id);
                                      // Check if this category is selected
                                      // Must NOT be English filter AND must match selected category ID
                                      final isSelected = !_isEnglishFilterSelected &&
                                          _selectedCategoryId != null &&
                                          _selectedCategoryId == category.id;

                                      // Debug: Log first category's selection state on each build
                                      if (index == 1) {
                                        Logger.debug('🏷️ [CategoryChip] First category: ${category.name}, id: ${category.id}');
                                        Logger.info('   _selectedCategoryId: $_selectedCategoryId');
                                        Logger.info('   _isEnglishFilterSelected: $_isEnglishFilterSelected');
                                        Logger.info('   isSelected: $isSelected');
                                      }
                                      return Padding(
                                        padding: const EdgeInsets.only(right: 8),
                                        child: _buildCompactChip(
                                          label: category.name,
                                          isSelected: isSelected,
                                          count: category.productCount,
                                          selectionCount: selectionCount,
                                          onTap: () async {
                                            if (isSelected) {
                                              Logger.info('🏷️ [ProductsGridScreen] Category already selected, ignoring tap');
                                              return;
                                            }

                                            final shopProvider = context.read<ShopSelectionProvider>();

                                            // PRESERVE current size to try to keep it selected in new category
                                            final previousSize = _selectedSize;

                                            setState(() {
                                              _isEnglishFilterSelected = false; // Clear English filter
                                              _selectedCategoryId = category.id;
                                              _selectedCategoryName = category.name;
                                              _selectedCategoryIds = [category.id];
                                              _selectedSize = null;
                                              _hasSetDefaultSize = false;
                                            });
                                            Logger.debug('🏷️ [ProductsGridScreen] Category selected: ${category.name}');

                                            // Store pending scroll indices for category
                                            _pendingCategoryScrollIndex = index;
                                            _pendingCategoryScrollTotal = totalChipCount;

                                            // Immediately scroll to selected category
                                            _scrollToSelectedCategory(index, totalChipCount);

                                            // Load available sizes for new category
                                            await provider.loadAvailableSizes(
                                              categoryId: category.id,
                                              shopId: shopProvider.selectedShopId,
                                            );

                                            // UX ENHANCEMENT: Try to keep the same size selected if it exists in new category
                                            // This provides better UX - user doesn't have to re-select 375ML when switching from Whisky to Rum
                                            if (mounted && provider.availableSizesWithCounts.isNotEmpty) {
                                              String selectedSize;
                                              int selectedSizeIndex = 0;

                                              // Check if previous size exists in new category
                                              if (previousSize != null) {
                                                final matchingIndex = provider.availableSizesWithCounts.indexWhere(
                                                  (s) => s.size.toUpperCase() == previousSize.toUpperCase()
                                                );
                                                if (matchingIndex >= 0) {
                                                  // Previous size exists - keep it selected
                                                  selectedSize = provider.availableSizesWithCounts[matchingIndex].size;
                                                  selectedSizeIndex = matchingIndex;
                                                  Logger.debug('📏 [ProductsGridScreen] Preserved size: $selectedSize (was $previousSize)');
                                                } else {
                                                  // Previous size doesn't exist - fall back to first size
                                                  selectedSize = provider.availableSizesWithCounts.first.size;
                                                  selectedSizeIndex = 0;
                                                  Logger.debug('📏 [ProductsGridScreen] Size $previousSize not available, defaulting to: $selectedSize');
                                                }
                                              } else {
                                                // No previous size - select first
                                                selectedSize = provider.availableSizesWithCounts.first.size;
                                                selectedSizeIndex = 0;
                                                Logger.debug('📏 [ProductsGridScreen] Auto-selected first size: $selectedSize');
                                              }

                                              setState(() {
                                                _selectedSize = selectedSize;
                                                _hasSetDefaultSize = true;
                                              });
                                              _syncFiltersToProvider();

                                              // Store pending scroll for size
                                              _pendingSizeScrollIndex = selectedSizeIndex;
                                              _pendingSizeScrollTotal = provider.availableSizesWithCounts.length;

                                              // Immediately scroll to selected size
                                              _scrollToSelectedSize(selectedSizeIndex, provider.availableSizesWithCounts.length);

                                              await provider.loadProducts(
                                                shopId: shopProvider.selectedShopId,
                                                categoryId: category.id,
                                                size: selectedSize,
                                              );

                                              // Scroll again after load to maintain position
                                              if (mounted) {
                                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                                  if (_pendingCategoryScrollIndex != null) {
                                                    _scrollToSelectedCategory(_pendingCategoryScrollIndex!, _pendingCategoryScrollTotal ?? totalChipCount);
                                                    _pendingCategoryScrollIndex = null;
                                                    _pendingCategoryScrollTotal = null;
                                                  }
                                                  if (_pendingSizeScrollIndex != null) {
                                                    _scrollToSelectedSize(_pendingSizeScrollIndex!, _pendingSizeScrollTotal ?? 1);
                                                    _pendingSizeScrollIndex = null;
                                                    _pendingSizeScrollTotal = null;
                                                  }
                                                });
                                              }
                                            } else {
                                              // No sizes available for this category — clear stale size filter
                                              setState(() {
                                                _selectedSize = null;
                                                _hasSetDefaultSize = false;
                                              });
                                              _syncFiltersToProvider();
                                              await provider.loadProducts(
                                                shopId: shopProvider.selectedShopId,
                                                categoryId: category.id,
                                              );

                                              // Scroll to category after load
                                              if (mounted && _pendingCategoryScrollIndex != null) {
                                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                                  _scrollToSelectedCategory(_pendingCategoryScrollIndex!, _pendingCategoryScrollTotal ?? totalChipCount);
                                                  _pendingCategoryScrollIndex = null;
                                                  _pendingCategoryScrollTotal = null;
                                                });
                                              }
                                            }
                                          },
                                      selectedColor: Theme.of(context).colorScheme.primary,
                                    ),
                                  );
                                    }),
                                    // NOTE: "All" chip REMOVED - one category must always be selected
                                  ],
                                );
                              },
                            ),
                    ),
                  ),
                ),

              // Setup flow: search bar (when expanded) + compact filter bar + sort/stock/view controls
              if (_isSetupFlowMode) ...[
                // Expandable search bar
                if (_isSearchExpanded)
                  SliverToBoxAdapter(
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      child: Container(
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: TextField(
                          controller: _searchController,
                          autofocus: true,
                          style: const TextStyle(fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Search products...',
                            hintStyle: const TextStyle(fontSize: 14, color: Color(0xFF94A3B8)),
                            prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF94A3B8)),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.close, size: 18, color: Color(0xFF94A3B8)),
                              onPressed: () {
                                _searchController.clear();
                                setState(() { _searchQuery = ''; _isSearchExpanded = false; });
                              },
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          onChanged: _onSearchChanged,
                        ),
                      ),
                    ),
                  ),
                // Filter badge + sort/stock/view row
                SliverToBoxAdapter(
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.fromLTRB(16, 6, 12, 8),
                    child: Row(
                      children: [
                        // Category + size filter badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3855B3),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            [
                              widget.initialCategory == 'English' ? 'Whisky & Spirits' : widget.initialCategory,
                              if (widget.initialSize != null && widget.initialSize!.isNotEmpty) widget.initialSize,
                            ].join(' · '),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('${provider.products.length} products', style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                        const Spacer(),
                        // Sort
                        SortMenu(
                          currentSort: _currentSort,
                          onSortChanged: (sort) => setState(() => _currentSort = sort),
                        ),
                        // In Stock toggle
                        GestureDetector(
                          onTap: () => setState(() => _showInStockOnly = !_showInStockOnly),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _showInStockOnly ? const Color(0xFF1349B8).withOpacity(0.1) : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _showInStockOnly ? const Color(0xFF1349B8) : const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _showInStockOnly ? Icons.inventory_2 : Icons.inventory_2_outlined,
                                  size: 14,
                                  color: _showInStockOnly ? const Color(0xFF1349B8) : const Color(0xFF94A3B8),
                                ),
                                const SizedBox(width: 4),
                                Text('Stock', style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: _showInStockOnly ? FontWeight.w600 : FontWeight.w500,
                                  color: _showInStockOnly ? const Color(0xFF1349B8) : const Color(0xFF94A3B8),
                                )),
                              ],
                            ),
                          ),
                        ),
                        // View toggle
                        if (widget.onToggleView != null)
                          IconButton(
                            icon: Icon(
                              widget.isGridView ? Icons.view_list : Icons.grid_view,
                              color: const Color(0xFF1349B8),
                              size: 20,
                            ),
                            onPressed: widget.onToggleView,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          ),
                      ],
                    ),
                  ),
                ),
              ],

              // Inline Size Filter Chips — hidden in setup flow mode
              if (!_isSetupFlowMode && (provider.availableSizesWithCounts.isNotEmpty || provider.isSizesLoading))
                SliverToBoxAdapter(
                  child: Container(
                    color: Theme.of(context).colorScheme.surface,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: SizedBox(
                      height: 38, // Standard height for inline stock display
                      child: provider.isSizesLoading
                          ? Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            )
                          : ListView(
                                  controller: _sizeFilterScrollController, // Auto-scroll controller
                                  scrollDirection: Axis.horizontal,
                                  children: [
                                    // ═══════════════════════════════════════════════════════════════
                                    // SIZE CHIPS - One MUST always be selected (no deselect)
                                    // Shows total inventory for each size category
                                    // Clicking already-selected size does nothing
                                    // Auto-scrolls to show selected size
                                    // ═══════════════════════════════════════════════════════════════
                                    ...provider.availableSizesWithCounts.asMap().entries.map((entry) {
                                      final index = entry.key;
                                      final sizeWithCount = entry.value;
                                      final isSelected = _selectedSize == sizeWithCount.size;
                                      final selectionCount = _getSelectionCountForSize(sizeWithCount.size);
                                      return Padding(
                                        padding: const EdgeInsets.only(right: 8),
                                        child: _buildSizeChipWithStock(
                                          label: sizeWithCount.size,
                                          stockQuantity: sizeWithCount.totalStockQuantity > 0
                                              ? sizeWithCount.totalStockQuantity
                                              : sizeWithCount.productCount,
                                          isSelected: isSelected,
                                          selectionCount: selectionCount, // Red badge on top-right
                                          onTap: () async {
                                            // CRITICAL: Cannot deselect - one size must always be selected
                                            if (isSelected) {
                                              Logger.debug('📏 [ProductsGridScreen] Size already selected, ignoring tap');
                                              return; // Do nothing if already selected
                                            }

                                            // Capture the index before any async operations
                                            final selectedIndex = index;
                                            final totalSizes = provider.availableSizesWithCounts.length;

                                            // Track pending scroll to restore after any rebuilds
                                            _pendingSizeScrollIndex = selectedIndex;
                                            _pendingSizeScrollTotal = totalSizes;

                                            // Select new size - reload with size filter from backend
                                            final shopProvider = context.read<ShopSelectionProvider>();
                                            setState(() {
                                              _selectedSize = sizeWithCount.size;
                                              _hasSetDefaultSize = true;
                                            });
                                            _syncFiltersToProvider(); // Persist to provider
                                            Logger.debug('📏 [ProductsGridScreen] Size selected: ${sizeWithCount.size}, stock: ${sizeWithCount.totalStockQuantity}');

                                            // Immediately scroll to the selected size (before products load)
                                            _scrollToSelectedSize(selectedIndex, totalSizes);

                                            // Load products with category + size filter
                                            await provider.loadProducts(
                                              shopId: shopProvider.selectedShopId,
                                              categoryId: _isEnglishFilterSelected ? null : _selectedCategoryId,
                                              categoryIds: _isEnglishFilterSelected ? _selectedCategoryIds : null,
                                              size: sizeWithCount.size,
                                            );

                                            // Scroll again AFTER products load to ensure position is maintained
                                            if (mounted) {
                                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                                if (_pendingSizeScrollIndex != null) {
                                                  _scrollToSelectedSize(_pendingSizeScrollIndex!, _pendingSizeScrollTotal ?? totalSizes);
                                                  _pendingSizeScrollIndex = null;
                                                  _pendingSizeScrollTotal = null;
                                                }
                                              });
                                            }
                                          },
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                    ),
                  ),
                ),

              // Products Grid/List or Empty State
              if (filteredProducts.isEmpty)
                SliverFillRemaining(
                  child: EmptyInventoryState(
                    type: _searchQuery.isNotEmpty
                        ? EmptyStateType.noSearchResults
                        : EmptyStateType.noFilterResults,
                    onAction: _filters.hasActiveFilters
                        ? () {
                            setState(() {
                              _filters = _filters.clear();
                              _searchController.clear();
                              _searchQuery = '';
                            });
                          }
                        : null,
                  ),
                )
              else if (widget.isGridView)
                _buildSliverGrid(filteredProducts)
              else
                _buildSliverList(filteredProducts),
            ],
          ),
        );
      },
    );
  }


  /// Build compact filter chip with fixed height (no overflow)
  /// Supports optional count badge for showing product counts (e.g., "90ML (2)")
  /// Supports optional selection badge on top-right corner (red circle with white text)
  Widget _buildCompactChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required Color selectedColor,
    int? count, // Optional product count for badge display
    int? selectionCount, // Optional: how many selected products in this category/size
  }) {
    final cs = Theme.of(context).colorScheme;
    // Build display text with optional count
    final displayText = count != null && count > 0 ? '$label ($count)' : label;

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? selectedColor : Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isSelected ? selectedColor : Theme.of(context).colorScheme.outlineVariant,
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: selectedColor.withOpacity(0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              displayText,
              style: TextStyle(
                color: isSelected ? Colors.white : Theme.of(context).colorScheme.onSurface,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
          // Selection count badge on top-right corner
          if (selectionCount != null && selectionCount > 0)
            Positioned(
              top: -6,
              right: -6,
              child: Container(
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  shape: BoxShape.circle,
                  border: Border.all(color: cs.surface, width: 1.5),
                ),
                child: Center(
                  child: Text(
                    selectionCount > 99 ? '99+' : '$selectionCount',
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
    );
  }

  /// Build size filter chip with STOCK QUANTITY displayed inline
  /// Shows total inventory for each size (e.g., "180ML • 999+")
  /// Color-coded chip background based on stock level
  Widget _buildSizeChipWithStock({
    required String label,
    required int stockQuantity,
    required bool isSelected,
    required VoidCallback onTap,
    int? selectionCount, // Optional: how many selected products in this size
  }) {
    final cs = Theme.of(context).colorScheme;
    // Color coding based on stock level
    final isOutOfStock = stockQuantity <= 0;
    final isLowStock = stockQuantity > 0 && stockQuantity <= 50;

    // Determine chip colors based on stock and selection
    Color chipBgColor;
    Color chipBorderColor;
    Color textColor;
    Color stockTextColor;

    if (isSelected) {
      chipBgColor = cs.primary;
      chipBorderColor = cs.primary;
      textColor = Colors.white;
      stockTextColor = Colors.white.withOpacity(0.9);
    } else if (isOutOfStock) {
      chipBgColor = Theme.of(context).colorScheme.surfaceContainerHighest;
      chipBorderColor = Theme.of(context).colorScheme.outlineVariant;
      textColor = Theme.of(context).colorScheme.onSurfaceVariant;
      stockTextColor = AppColors.error;
    } else if (isLowStock) {
      chipBgColor = AppColors.warning.withValues(alpha: 0.1);
      chipBorderColor = AppColors.warning.withValues(alpha: 0.3);
      textColor = Theme.of(context).colorScheme.onSurface;
      stockTextColor = AppColors.warning;
    } else {
      chipBgColor = cs.primary.withOpacity(0.1);
      chipBorderColor = cs.primary.withOpacity(0.3);
      textColor = Theme.of(context).colorScheme.onSurface;
      stockTextColor = cs.primary;
    }

    // Format stock text - show up to 4 digits (9999), then show 9999+
    final stockText = stockQuantity > 9999 ? '9999+' : '$stockQuantity';

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Main chip with inline stock display
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: chipBgColor,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isSelected ? chipBorderColor : chipBorderColor,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Size label
                Text(
                  label,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 6),
                // Stock indicator (inline)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.white.withOpacity(0.2)
                        : (isOutOfStock ? AppColors.error : (isLowStock ? AppColors.warning : cs.primary)).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.inventory_2_outlined,
                        size: 10,
                        color: isSelected ? Colors.white.withOpacity(0.9) : stockTextColor,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        stockText,
                        style: TextStyle(
                          color: isSelected ? Colors.white.withOpacity(0.9) : stockTextColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Selection count badge on top-right corner (red badge for selected products)
          if (selectionCount != null && selectionCount > 0)
            Positioned(
              top: -6,
              right: -6,
              child: Container(
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  shape: BoxShape.circle,
                  border: Border.all(color: cs.surface, width: 1.5),
                ),
                child: Center(
                  child: Text(
                    selectionCount > 99 ? '99+' : '$selectionCount',
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
    );
  }

  Widget _buildSliverGrid(List<ProductWithStock> products) {
    return Consumer<ProductProvider>(
      builder: (context, provider, _) {
        return SliverMainAxisGroup(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.62,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final product = products[index];
                    final isSelected = widget.selectedProductIds?.contains(product.id) ?? false;

                    return CompactProductGridCard(
                      product: product,
                      isSelected: isSelected,
                      onSelectionToggle: widget.onProductSelectionToggle != null
                          ? () {
                              // Cache product info when selected (for selection badges)
                              if (!isSelected) {
                                // Will be selected - add to cache
                                _selectedProductsCache[product.id] = _SelectedProductInfo(
                                  categoryId: product.category?.id,
                                  size: product.size.toUpperCase(),
                                );
                              } else {
                                // Will be deselected - remove from cache
                                _selectedProductsCache.remove(product.id);
                              }
                              widget.onProductSelectionToggle!(product.id);
                              setState(() {}); // Refresh badges
                            }
                          : null,
                    );
                  },
                  childCount: products.length,
                ),
              ),
            ),
            // Instagram-style loading indicator when fetching more
            if (_isLoadingMore || provider.hasMore)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 180),
                  child: _buildLoadingIndicator(provider),
                ),
              ),
            // Bottom padding when no more items
            if (!provider.hasMore && !_isLoadingMore)
              const SliverPadding(
                padding: EdgeInsets.only(bottom: 164),
                sliver: SliverToBoxAdapter(child: SizedBox.shrink()),
              ),
          ],
        );
      },
    );
  }

  Widget _buildSliverList(List<ProductWithStock> products) {
    // Check if selection mode is active
    final hasSelection = (widget.selectedProductIds?.isNotEmpty ?? false);

    return Consumer<ProductProvider>(
      builder: (context, provider, _) {
        // Total items = products + separators + (optional loading indicator)
        final showLoadingIndicator = _isLoadingMore || provider.hasMore;
        final totalItems = products.length * 2 - 1 + (showLoadingIndicator ? 2 : 0);

        return SliverPadding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, hasSelection ? 100 : 180),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                // Loading indicator at the end
                if (showLoadingIndicator && index == totalItems - 1) {
                  return _buildLoadingIndicator(provider);
                }
                // Extra separator before loading indicator
                if (showLoadingIndicator && index == totalItems - 2) {
                  return const SizedBox(height: 16);
                }

                if (index.isOdd && index < products.length * 2 - 1) {
                  return const SizedBox(height: 12); // Separator
                }
                final productIndex = index ~/ 2;
                if (productIndex >= products.length) return const SizedBox.shrink();

                final product = products[productIndex];
                final isSelected = widget.selectedProductIds?.contains(product.id) ?? false;

                return DenseProductListTile(
                  product: product,
                  isSelected: isSelected,
                  onSelectionToggle: widget.onProductSelectionToggle != null
                      ? () {
                          // Cache product info when selected (for selection badges)
                          if (!isSelected) {
                            // Will be selected - add to cache
                            _selectedProductsCache[product.id] = _SelectedProductInfo(
                              categoryId: product.category?.id,
                              size: product.size.toUpperCase(),
                            );
                          } else {
                            // Will be deselected - remove from cache
                            _selectedProductsCache.remove(product.id);
                          }
                          widget.onProductSelectionToggle!(product.id);
                          setState(() {}); // Refresh badges
                        }
                      : null,
                );
              },
              childCount: totalItems,
            ),
          ),
        );
      },
    );
  }

  /// Instagram-style loading indicator for infinite scroll
  Widget _buildLoadingIndicator(ProductProvider provider) {
    if (_isLoadingMore) {
      // Show spinning indicator while loading
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Loading more...',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Show subtle indicator that more items exist (scroll down to load)
    if (provider.hasMore) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.arrow_downward,
                size: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
              ),
              const SizedBox(width: 4),
              Text(
                'Scroll for more',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
