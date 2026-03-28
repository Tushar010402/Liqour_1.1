import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../providers/product_provider.dart';
import '../models/brand.dart';
import 'brand_import_screen.dart';

/// Modern Brand Gallery Screen with Professional UI/UX
class ModernBrandsGallery extends StatefulWidget {
  const ModernBrandsGallery({super.key});

  @override
  State<ModernBrandsGallery> createState() => _ModernBrandsGalleryState();
}

class _ModernBrandsGalleryState extends State<ModernBrandsGallery>
    with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  late AnimationController _animationController;
  late AnimationController _fabController;
  String _selectedCategory = 'All';
  String _viewMode = 'gallery'; // gallery, list, or card

  final List<String> _categories = [
    'All',
    'Whiskey',
    'Beer',
    'Wine',
    'Vodka',
    'Rum',
    'Gin',
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fabController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadBrands();
      _animationController.forward();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _animationController.dispose();
    _fabController.dispose();
    super.dispose();
  }

  Future<void> _loadBrands() async {
    if (!mounted) return;
    await context.read<ProductProvider>().loadBrands();
  }

  List<Brand> _getFilteredBrands(List<Brand> brands) {
    var filtered = brands;

    // Apply search filter
    if (_searchController.text.isNotEmpty) {
      final query = _searchController.text.toLowerCase();
      filtered = filtered.where((brand) {
        return brand.name.toLowerCase().contains(query) ||
            brand.description.toLowerCase().contains(query);
      }).toList();
    }

    // Apply category filter
    if (_selectedCategory != 'All') {
      filtered = filtered.where((brand) {
        return brand.category?.toLowerCase() == _selectedCategory.toLowerCase();
      }).toList();
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            expandedHeight: 200,
            floating: true,
            pinned: true,
            elevation: 0,
            backgroundColor: cs.primary,
            flexibleSpace: FlexibleSpaceBar(
              title: const Text(
                'Brand Gallery',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      cs.primary,
                      cs.primary.withValues(alpha: 0.7),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    // Animated background pattern
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _BackgroundPatternPainter(
                          animation: _animationController,
                        ),
                      ),
                    ),
                    // Statistics overlay
                    Positioned(
                      bottom: 60,
                      left: 16,
                      right: 16,
                      child: Consumer<ProductProvider>(
                        builder: (context, provider, _) {
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildStatistic('Total Brands',
                                  '${provider.brands.length}', Icons.local_offer),
                              _buildStatistic('Categories',
                                  '${_categories.length - 1}', Icons.category),
                              _buildStatistic('Active',
                                  '${provider.brands.where((b) => b.isActive).length}',
                                  Icons.check_circle),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              // View Mode Toggle
              IconButton(
                icon: Icon(
                  _viewMode == 'gallery'
                      ? Icons.view_list
                      : _viewMode == 'list'
                          ? Icons.grid_view
                          : Icons.view_module,
                  color: Colors.white,
                ),
                onPressed: () {
                  setState(() {
                    if (_viewMode == 'gallery') {
                      _viewMode = 'list';
                    } else if (_viewMode == 'list') {
                      _viewMode = 'card';
                    } else {
                      _viewMode = 'gallery';
                    }
                  });
                  HapticFeedback.lightImpact();
                },
              ),
              // Import Button
              IconButton(
                icon: const Icon(Icons.file_upload, color: Colors.white),
                onPressed: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const BrandImportScreen(),
                    ),
                  );
                  if (result == true) {
                    _loadBrands();
                  }
                },
              ),
              const SizedBox(width: 8),
            ],
          ),
        ],
        body: Consumer<ProductProvider>(
          builder: (context, provider, child) {
            final brands = _getFilteredBrands(provider.brands);

            return Column(
              children: [
                // Search Bar
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Search Field
                      Container(
                        decoration: BoxDecoration(
                          color: cs.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: cs.outline.withValues(alpha: 0.2),
                          ),
                        ),
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Search brands...',
                            hintStyle: TextStyle(
                              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                            ),
                            prefixIcon: Icon(
                              Icons.search,
                              color: cs.onSurfaceVariant,
                            ),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: Icon(
                                      Icons.clear,
                                      color: cs.onSurfaceVariant,
                                    ),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {});
                                    },
                                  )
                                : null,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                          onChanged: (value) => setState(() {}),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Category Chips
                      SizedBox(
                        height: 36,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _categories.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final category = _categories[index];
                            final isSelected = _selectedCategory == category;
                            return InkWell(
                              onTap: () {
                                setState(() {
                                  _selectedCategory = category;
                                });
                                HapticFeedback.selectionClick();
                              },
                              borderRadius: BorderRadius.circular(20),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  gradient: isSelected
                                      ? LinearGradient(
                                          colors: [
                                            cs.primary,
                                            cs.primary.withValues(alpha: 0.8),
                                          ],
                                        )
                                      : null,
                                  color: isSelected ? null : Colors.transparent,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isSelected
                                        ? Colors.transparent
                                        : cs.outline,
                                  ),
                                ),
                                child: Text(
                                  category,
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : cs.onSurface,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                // Brands Display
                Expanded(
                  child: provider.isBrandsLoading && provider.brands.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : brands.isEmpty
                          ? _buildEmptyState()
                          : RefreshIndicator(
                              onRefresh: _loadBrands,
                              child: _buildBrandsView(brands),
                            ),
                ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: _buildFloatingActionButton(),
    );
  }

  Widget _buildStatistic(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white.withValues(alpha: 0.9), size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.8),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  cs.primary.withValues(alpha: 0.1),
                  cs.primary.withValues(alpha: 0.05),
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.local_offer_outlined,
              size: 60,
              color: cs.primary.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No Brands Found',
            style: AppTextStyles.h5.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Import brands from Excel to get started',
            style: AppTextStyles.bodyMedium.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const BrandImportScreen(),
                ),
              );
              if (result == true) {
                _loadBrands();
              }
            },
            icon: const Icon(Icons.file_upload),
            label: const Text('Import Brands'),
            style: ElevatedButton.styleFrom(
              backgroundColor: cs.primary,
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrandsView(List<Brand> brands) {
    switch (_viewMode) {
      case 'list':
        return _buildListView(brands);
      case 'card':
        return _buildCardView(brands);
      case 'gallery':
      default:
        return _buildGalleryView(brands);
    }
  }

  Widget _buildGalleryView(List<Brand> brands) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.85,
      ),
      itemCount: brands.length,
      itemBuilder: (context, index) {
        final brand = brands[index];
        return _BrandGalleryCard(
          brand: brand,
          onTap: () => _navigateToBrandDetail(brand),
          onEdit: () => _showEditBrandDialog(brand),
          onDelete: () => _showDeleteBrandDialog(brand),
        );
      },
    );
  }

  Widget _buildListView(List<Brand> brands) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: brands.length,
      itemBuilder: (context, index) {
        final brand = brands[index];
        return _BrandListTile(
          brand: brand,
          onTap: () => _navigateToBrandDetail(brand),
          onEdit: () => _showEditBrandDialog(brand),
          onDelete: () => _showDeleteBrandDialog(brand),
        );
      },
    );
  }

  Widget _buildCardView(List<Brand> brands) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: brands.length,
      itemBuilder: (context, index) {
        final brand = brands[index];
        return _BrandExpandableCard(
          brand: brand,
          onTap: () => _navigateToBrandDetail(brand),
          onEdit: () => _showEditBrandDialog(brand),
          onDelete: () => _showDeleteBrandDialog(brand),
        );
      },
    );
  }

  Widget _buildFloatingActionButton() {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _fabController,
      builder: (context, child) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            // Import from Excel
            Transform.translate(
              offset: Offset(0, _fabController.value * -120),
              child: ScaleTransition(
                scale: _fabController,
                child: FloatingActionButton(
                  heroTag: 'import',
                  mini: true,
                  onPressed: () async {
                    _fabController.reverse();
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const BrandImportScreen(),
                      ),
                    );
                    if (result == true) {
                      _loadBrands();
                    }
                  },
                  backgroundColor: AppColors.success,
                  child: const Icon(Icons.file_upload, color: Colors.white),
                ),
              ),
            ),
            // Add Manual
            Transform.translate(
              offset: Offset(0, _fabController.value * -60),
              child: ScaleTransition(
                scale: _fabController,
                child: FloatingActionButton(
                  heroTag: 'manual',
                  mini: true,
                  onPressed: () {
                    _fabController.reverse();
                    _showAddBrandDialog();
                  },
                  backgroundColor: AppColors.warning,
                  child: const Icon(Icons.edit, color: Colors.white),
                ),
              ),
            ),
            // Main FAB
            FloatingActionButton(
              heroTag: 'main',
              onPressed: () {
                if (_fabController.isCompleted) {
                  _fabController.reverse();
                } else {
                  _fabController.forward();
                }
                HapticFeedback.mediumImpact();
              },
              backgroundColor: cs.primary,
              child: AnimatedBuilder(
                animation: _fabController,
                builder: (context, child) {
                  return Transform.rotate(
                    angle: _fabController.value * math.pi / 4,
                    child: const Icon(Icons.add, color: Colors.white),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  void _navigateToBrandDetail(Brand brand) {
    // TODO: BrandDetailScreen expects SaasBrand, not Brand
    // For now, show a snackbar with brand details
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Brand: ${brand.name}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showAddBrandDialog() {
    // Implement add brand dialog
  }

  void _showEditBrandDialog(Brand brand) {
    // Implement edit brand dialog
  }

  void _showDeleteBrandDialog(Brand brand) {
    // Implement delete brand dialog
  }
}

// Gallery Card Widget
class _BrandGalleryCard extends StatelessWidget {
  final Brand brand;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _BrandGalleryCard({
    required this.brand,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Brand Header
                Container(
                  height: 120,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        cs.primary.withValues(alpha: 0.8),
                        cs.primary,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                  ),
                  child: Center(
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          brand.name.substring(0, 2).toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Brand Info
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          brand.name,
                          style: AppTextStyles.bodyLarge.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          brand.description.isNotEmpty
                              ? brand.description
                              : 'Premium Brand',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: cs.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                brand.category ?? 'General',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: cs.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const Spacer(),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: brand.isActive
                                    ? AppColors.success
                                    : AppColors.error,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            // Options Menu
            Positioned(
              top: 8,
              right: 8,
              child: PopupMenuButton<String>(
                icon: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.more_vert,
                    size: 16,
                    color: cs.onSurface,
                  ),
                ),
                onSelected: (value) {
                  if (value == 'edit') {
                    onEdit();
                  } else if (value == 'delete') {
                    onDelete();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit, size: 18),
                        SizedBox(width: 8),
                        Text('Edit'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 18, color: AppColors.error),
                        SizedBox(width: 8),
                        Text('Delete', style: TextStyle(color: AppColors.error)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// List Tile Widget
class _BrandListTile extends StatelessWidget {
  final Brand brand;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _BrandListTile({
    required this.brand,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.all(12),
        leading: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                cs.primary.withValues(alpha: 0.8),
                cs.primary,
              ],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              brand.name.substring(0, 1).toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        title: Text(
          brand.name,
          style: AppTextStyles.bodyLarge.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          brand.description.isNotEmpty
              ? brand.description
              : 'Premium Brand',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: brand.isActive
                    ? AppColors.success.withValues(alpha: 0.1)
                    : AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                brand.isActive ? 'Active' : 'Inactive',
                style: TextStyle(
                  fontSize: 11,
                  color: brand.isActive ? AppColors.success : AppColors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'edit') {
                  onEdit();
                } else if (value == 'delete') {
                  onDelete();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 18),
                      SizedBox(width: 8),
                      Text('Edit'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, size: 18, color: AppColors.error),
                      SizedBox(width: 8),
                      Text('Delete', style: TextStyle(color: AppColors.error)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Expandable Card Widget
class _BrandExpandableCard extends StatefulWidget {
  final Brand brand;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _BrandExpandableCard({
    required this.brand,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_BrandExpandableCard> createState() => _BrandExpandableCardState();
}

class _BrandExpandableCardState extends State<_BrandExpandableCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      elevation: 4,
      child: InkWell(
        onTap: () {
          setState(() {
            _isExpanded = !_isExpanded;
          });
        },
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      cs.primary.withValues(alpha: 0.05),
                      cs.surface,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                cs.primary.withValues(alpha: 0.8),
                                cs.primary,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              widget.brand.name.substring(0, 2).toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.brand.name,
                                style: AppTextStyles.h6.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.brand.description.isNotEmpty
                                    ? widget.brand.description
                                    : 'Premium Brand',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          _isExpanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          color: cs.onSurfaceVariant,
                        ),
                      ],
                    ),
                    AnimatedCrossFade(
                      firstChild: const SizedBox.shrink(),
                      secondChild: Column(
                        children: [
                          const SizedBox(height: 16),
                          const Divider(),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildInfoTile(
                                'Category',
                                widget.brand.category ?? 'General',
                                Icons.category,
                              ),
                              _buildInfoTile(
                                'Status',
                                widget.brand.isActive ? 'Active' : 'Inactive',
                                Icons.power_settings_new,
                                color: widget.brand.isActive
                                    ? AppColors.success
                                    : AppColors.error,
                              ),
                              _buildInfoTile(
                                'Origin',
                                'Imported',
                                Icons.file_download,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: widget.onEdit,
                                  icon: const Icon(Icons.edit, size: 18),
                                  label: const Text('Edit'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: widget.onTap,
                                  icon: const Icon(Icons.visibility, size: 18),
                                  label: const Text('View'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: widget.onDelete,
                                  icon: Icon(
                                    Icons.delete,
                                    size: 18,
                                    color: AppColors.error,
                                  ),
                                  label: Text(
                                    'Delete',
                                    style: TextStyle(color: AppColors.error),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: AppColors.error),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      crossFadeState: _isExpanded
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
                      duration: const Duration(milliseconds: 300),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoTile(String label, String value, IconData icon,
      {Color? color}) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Icon(
          icon,
          size: 20,
          color: color ?? cs.primary,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: color ?? cs.onSurface,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// Background Pattern Painter
class _BackgroundPatternPainter extends CustomPainter {
  final Animation<double> animation;

  _BackgroundPatternPainter({required this.animation})
      : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..style = PaintingStyle.fill;

    for (var i = 0; i < 5; i++) {
      final offset = animation.value * size.width;
      canvas.drawCircle(
        Offset((i * 100 + offset) % size.width, size.height * 0.3),
        30,
        paint,
      );
      canvas.drawCircle(
        Offset((i * 100 - offset) % size.width, size.height * 0.7),
        20,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BackgroundPatternPainter oldDelegate) => true;
}