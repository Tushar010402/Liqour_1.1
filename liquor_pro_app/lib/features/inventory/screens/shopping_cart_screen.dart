import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../models/saas_brand.dart';
import '../providers/brand_selection_provider.dart';
import '../widgets/variant_picker_sheet.dart';
import 'onboarding_progress_screen.dart';

/// Shopping cart view for reviewing brand/variant selections
/// Organized by category with swipe-to-delete functionality
class ShoppingCartScreen extends StatefulWidget {
  const ShoppingCartScreen({super.key});

  @override
  State<ShoppingCartScreen> createState() => _ShoppingCartScreenState();
}

class _ShoppingCartScreenState extends State<ShoppingCartScreen> {
  final TextEditingController _searchController = TextEditingController();
  final Map<String, bool> _expandedCategories = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showClearAllDialog(BrandSelectionProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Selections?'),
        content: const Text(
          'This will remove all selected brands and variants from your cart.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              provider.clearAll();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }

  void _startOnboarding(BrandSelectionProvider provider) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const OnboardingProgressScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BrandSelectionProvider>(
      builder: (context, provider, _) {
        final groupedBrands = provider.getGroupedByCategory();
        final totalCount = provider.totalSelectedCount;
        final searchQuery = _searchController.text.toLowerCase();

        // Filter brands by search
        final filteredGroups = searchQuery.isEmpty
            ? groupedBrands
            : Map.fromEntries(
                groupedBrands.entries
                    .map((entry) {
                      final filteredBrands = entry.value
                          .where((brand) =>
                              brand.name.toLowerCase().contains(searchQuery))
                          .toList();
                      return MapEntry(entry.key, filteredBrands);
                    })
                    .where((entry) => entry.value.isNotEmpty),
              );

        final cs = Theme.of(context).colorScheme;
        return Scaffold(
          backgroundColor: cs.surface,
          appBar: CustomAppBar(
            title: 'Selection Cart',
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              if (totalCount > 0)
                TextButton(
                  onPressed: () => _showClearAllDialog(provider),
                  child: const Text(
                    'Clear All',
                    style: TextStyle(
                      color: AppColors.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          body: totalCount == 0
              ? _buildEmptyState()
              : Column(
                  children: [
                    // Summary card
                    Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            cs.primary,
                            cs.primary.withValues(alpha: 0.8),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: cs.primary.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.shopping_cart,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Ready to Onboard',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '$totalCount variants across ${groupedBrands.length} categories',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.9),
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Search bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search in cart...',
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
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        onChanged: (value) => setState(() {}),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Category sections
                    Expanded(
                      child: filteredGroups.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.search_off,
                                    size: 64,
                                    color: cs.onSurfaceVariant,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No brands match your search',
                                    style: AppTextStyles.bodyLarge.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: filteredGroups.length,
                              itemBuilder: (context, index) {
                                final entry = filteredGroups.entries.elementAt(index);
                                final categoryName = entry.key;
                                final brands = entry.value;

                                // Auto-expand first category or searched results
                                _expandedCategories.putIfAbsent(
                                  categoryName,
                                  () => index == 0 || searchQuery.isNotEmpty,
                                );

                                return _buildCategorySection(
                                  provider,
                                  categoryName,
                                  brands,
                                );
                              },
                            ),
                    ),
                  ],
                ),
          bottomNavigationBar: totalCount > 0
              ? Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 10,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => _startOnboarding(provider),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.cloud_upload),
                            const SizedBox(width: 8),
                            Text(
                              'Onboard $totalCount Variants',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              : null,
        );
      },
    );
  }

  Widget _buildCategorySection(
    BrandSelectionProvider provider,
    String categoryName,
    List<SaasBrand> brands,
  ) {
    final cs = Theme.of(context).colorScheme;
    final isExpanded = _expandedCategories[categoryName] ?? false;
    final totalVariants = brands.fold<int>(
      0,
      (sum, brand) => sum + provider.getSelectedVariantCount(brand.id),
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          // Category header
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                setState(() {
                  _expandedCategories[categoryName] = !isExpanded;
                });
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Expand icon
                    Icon(
                      isExpanded ? Icons.expand_more : Icons.chevron_right,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),

                    // Category info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            categoryName,
                            style: AppTextStyles.h6,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${brands.length} brands • $totalVariants variants',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$totalVariants',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Brand list (collapsible)
          if (isExpanded)
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: brands.length,
              separatorBuilder: (context, index) => const Divider(height: 1, indent: 16),
              itemBuilder: (context, index) {
                return _buildBrandItem(provider, brands[index]);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildBrandItem(BrandSelectionProvider provider, SaasBrand brand) {
    final cs = Theme.of(context).colorScheme;
    final selectedVariants = provider.getSelectedVariantIds(brand.id);
    final selectedCount = selectedVariants.length;

    return Dismissible(
      key: Key(brand.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        return await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Remove Brand?'),
            content: Text(
              'Remove "${brand.name}" and all its variants from your selection?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Remove'),
              ),
            ],
          ),
        );
      },
      onDismissed: (direction) {
        provider.toggleBrand(brand.id, brand.variants);
      },
      background: Container(
        color: AppColors.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(
          Icons.delete,
          color: Colors.white,
          size: 32,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: brand.picture.isNotEmpty
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  brand.picture,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          brand.categoryNameFromVariant?.substring(0, 1).toUpperCase() ?? '🍾',
                          style: const TextStyle(fontSize: 24),
                        ),
                      ),
                    );
                  },
                ),
              )
            : Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    brand.categoryNameFromVariant?.substring(0, 1).toUpperCase() ?? '🍾',
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
              ),
        title: Text(
          brand.name,
          style: AppTextStyles.bodyLarge.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          '$selectedCount of ${brand.variants.length} variants selected',
          style: AppTextStyles.bodySmall.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, size: 20),
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => VariantPickerSheet(brand: brand),
                );
              },
              tooltip: 'Edit variants',
            ),
            Icon(
              Icons.drag_indicator,
              color: cs.onSurfaceVariant,
            ),
          ],
        ),
      ),
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
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.shopping_cart_outlined,
                size: 64,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Your Cart is Empty',
              style: AppTextStyles.h5,
            ),
            const SizedBox(height: 12),
            Text(
              'Start selecting brands and variants to onboard them to your inventory',
              style: AppTextStyles.bodyMedium.copyWith(
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Browse Brands'),
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
