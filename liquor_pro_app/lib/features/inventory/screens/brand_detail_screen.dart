import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../models/saas_brand.dart';
import '../providers/product_provider.dart';
import '../providers/brand_onboarding_provider.dart';
import 'initial_stock_screen.dart';

/// Brand Detail Screen - Shows brand info, variants, and duty fees
/// Provides easy access to stock setup and onboarding
class BrandDetailScreen extends StatefulWidget {
  final SaasBrand brand;

  const BrandDetailScreen({
    super.key,
    required this.brand,
  });

  @override
  State<BrandDetailScreen> createState() => _BrandDetailScreenState();
}

class _BrandDetailScreenState extends State<BrandDetailScreen> {
  bool _showOnlyAvailable = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: CustomAppBar(
        title: widget.brand.name,
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              // TODO: Implement share functionality
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Share coming soon!')),
              );
            },
            tooltip: 'Share',
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Brand Header with Image
            _buildBrandHeader(cs),

            const SizedBox(height: 16),

            // Quick Stats
            _buildQuickStats(),

            const SizedBox(height: 24),

            // Filter Toggle
            _buildFilterToggle(),

            const SizedBox(height: 16),

            // Variants List
            _buildVariantsList(cs),

            const SizedBox(height: 80), // Space for FAB
          ],
        ),
      ),
      floatingActionButton: _buildFAB(),
    );
  }

  Widget _buildBrandHeader(ColorScheme cs) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primary.withValues(alpha: 0.1),
            cs.primary.withValues(alpha: 0.05),
          ],
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 24),
          // Brand Image
          if (widget.brand.picture.isNotEmpty)
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  widget.brand.picture,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.branding_watermark,
                    size: 60,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.branding_watermark,
                size: 60,
                color: cs.primary,
              ),
            ),

          const SizedBox(height: 16),

          // Brand Name
          Text(
            widget.brand.name,
            style: AppTextStyles.h4.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 8),

          // Category & Subcategory
          if (widget.brand.categoryNameFromVariant != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.category, size: 14, color: cs.primary),
                  const SizedBox(width: 4),
                  Text(
                    widget.brand.categoryNameFromVariant!,
                    style: AppTextStyles.caption.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (widget.brand.subcategoryNameFromVariant != null) ...[
                    Text(' • ', style: TextStyle(color: cs.primary)),
                    Text(
                      widget.brand.subcategoryNameFromVariant!,
                      style: AppTextStyles.caption.copyWith(
                        color: cs.primary,
                      ),
                    ),
                  ],
                ],
              ),
            ),

          const SizedBox(height: 16),

          // Description
          if (widget.brand.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                widget.brand.description,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: cs.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildQuickStats() {
    final cs = Theme.of(context).colorScheme;
    final totalVariants = widget.brand.variants.length;
    final onboardedVariants = widget.brand.onboardedVariantsCount;
    final availableVariants = totalVariants - onboardedVariants;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard(
              icon: Icons.inventory_2,
              label: 'Total Variants',
              value: totalVariants.toString(),
              color: cs.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              icon: Icons.check_circle,
              label: 'Onboarded',
              value: onboardedVariants.toString(),
              color: AppColors.success,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              icon: Icons.add_circle_outline,
              label: 'Available',
              value: availableVariants.toString(),
              color: AppColors.warning,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: AppTextStyles.h5.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTextStyles.caption.copyWith(color: color),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterToggle() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(
            'Variants (${_getFilteredVariants().length})',
            style: AppTextStyles.h6.copyWith(fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          FilterChip(
            label: const Text('Available Only'),
            selected: _showOnlyAvailable,
            onSelected: (value) => setState(() => _showOnlyAvailable = value),
            selectedColor: cs.primary.withValues(alpha: 0.2),
            checkmarkColor: cs.primary,
          ),
        ],
      ),
    );
  }

  List<SaasBrandVariant> _getFilteredVariants() {
    if (_showOnlyAvailable) {
      return widget.brand.variants.where((v) => v.isOnboarded != true).toList();
    }
    return widget.brand.variants;
  }

  Widget _buildVariantsList(ColorScheme cs) {
    final variants = _getFilteredVariants();

    if (variants.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            children: [
              Icon(Icons.check_circle, size: 64, color: AppColors.success),
              const SizedBox(height: 16),
              Text(
                'All variants onboarded!',
                style: AppTextStyles.h6.copyWith(color: AppColors.success),
              ),
              const SizedBox(height: 8),
              Text(
                'This brand is fully set up',
                style: AppTextStyles.bodySmall.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: variants.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return _buildVariantCard(variants[index], cs);
      },
    );
  }

  Widget _buildVariantCard(SaasBrandVariant variant, ColorScheme cs) {
    final isOnboarded = variant.isOnboarded == true;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isOnboarded
            ? BorderSide(color: AppColors.success.withValues(alpha: 0.3), width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: isOnboarded
            ? null
            : () => _showVariantDetailDialog(variant),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                children: [
                  // Variant Image
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: variant.picture.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              variant.picture,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(Icons.local_drink),
                            ),
                          )
                        : const Icon(Icons.local_drink),
                  ),

                  const SizedBox(width: 12),

                  // Variant Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                variant.size,
                                style: AppTextStyles.bodyLarge.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (isOnboarded)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.success.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.check_circle,
                                      size: 14,
                                      color: AppColors.success,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Onboarded',
                                      style: AppTextStyles.caption.copyWith(
                                        color: AppColors.success,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${variant.alcoholContent}% ABV',
                          style: AppTextStyles.caption.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // Price & Duty Information
              Row(
                children: [
                  Expanded(
                    child: _buildPriceInfo(
                      label: 'Buying Price',
                      value: '₹${variant.buyingPrice.toStringAsFixed(2)}',
                      icon: Icons.shopping_cart,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildPriceInfo(
                      label: 'Selling Price',
                      value: '₹${variant.sellingPrice.toStringAsFixed(2)}',
                      icon: Icons.sell,
                      color: AppColors.success,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              Row(
                children: [
                  Expanded(
                    child: _buildPriceInfo(
                      label: 'MRP',
                      value: '₹${variant.mrp.toStringAsFixed(2)}',
                      icon: Icons.local_offer,
                      color: AppColors.warning,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildPriceInfo(
                      label: 'Govt. Duty',
                      value: '₹${variant.governmentDuty.toStringAsFixed(2)}',
                      icon: Icons.account_balance,
                      color: AppColors.error,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Additional Info
              Row(
                children: [
                  _buildInfoChip(
                    icon: Icons.qr_code,
                    label: variant.barcode.isEmpty ? 'No Barcode' : variant.barcode,
                    cs: cs,
                  ),
                  const SizedBox(width: 8),
                  _buildInfoChip(
                    icon: Icons.numbers,
                    label: 'HSN: ${variant.hsnCode}',
                    cs: cs,
                  ),
                ],
              ),

              if (!isOnboarded) ...[
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () => _onboardVariant(variant),
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: const Text('Onboard This Variant'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 40),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPriceInfo({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: AppTextStyles.caption.copyWith(
                  color: color,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTextStyles.bodyMedium.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip({required IconData icon, required String label, required ColorScheme cs}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: cs.onSurfaceVariant),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.caption.copyWith(
                  color: cs.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFAB() {
    final cs = Theme.of(context).colorScheme;
    final availableCount = widget.brand.variants.where((v) => v.isOnboarded != true).length;

    if (availableCount == 0) {
      return FloatingActionButton.extended(
        onPressed: () => _navigateToStockSetup(),
        backgroundColor: AppColors.success,
        icon: const Icon(Icons.inventory, color: Colors.white),
        label: const Text(
          'Setup Stock',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      );
    }

    return FloatingActionButton.extended(
      onPressed: () => _onboardAllVariants(),
      backgroundColor: cs.primary,
      icon: const Icon(Icons.add_shopping_cart, color: Colors.white),
      label: Text(
        'Onboard All ($availableCount)',
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
  }

  void _showVariantDetailDialog(SaasBrandVariant variant) {
    final cs = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(variant.size),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('Size', variant.size, cs: cs),
              _buildDetailRow('Alcohol Content', '${variant.alcoholContent}%', cs: cs),
              _buildDetailRow('Barcode', variant.barcode, cs: cs),
              _buildDetailRow('HSN Code', variant.hsnCode, cs: cs),
              const Divider(height: 24),
              _buildDetailRow('Buying Price', '₹${variant.buyingPrice.toStringAsFixed(2)}', cs: cs),
              _buildDetailRow('Selling Price', '₹${variant.sellingPrice.toStringAsFixed(2)}', cs: cs),
              _buildDetailRow('MRP', '₹${variant.mrp.toStringAsFixed(2)}', cs: cs),
              _buildDetailRow(
                'Government Duty',
                '₹${variant.governmentDuty.toStringAsFixed(2)}',
                highlight: true,
                cs: cs,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _onboardVariant(variant);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: cs.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Onboard'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool highlight = false, required ColorScheme cs}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: AppTextStyles.bodyMedium.copyWith(
              fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
              color: highlight ? AppColors.error : cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onboardVariant(SaasBrandVariant variant) async {
    final cs = Theme.of(context).colorScheme;
    // Show confirmation
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Onboard Variant'),
        content: Text('Do you want to onboard ${variant.size}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: cs.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Onboard'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Onboard the variant using selection-based approach
    final provider = context.read<BrandOnboardingProvider>();

    // Clear previous selection and select this variant
    provider.clearSelection();
    provider.toggleVariant(widget.brand.id, variant.id);

    // Onboard
    final success = await provider.onboardSelectedBrands();

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Variant onboarded successfully!'),
          backgroundColor: AppColors.success,
        ),
      );

      // Refresh product list
      context.read<ProductProvider>().refreshProducts();

      setState(() {}); // Refresh UI
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.errorMessage ?? 'Failed to onboard variant'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _onboardAllVariants() async {
    final cs = Theme.of(context).colorScheme;
    final availableVariants = widget.brand.variants.where((v) => v.isOnboarded != true).toList();

    if (availableVariants.isEmpty) return;

    // Show confirmation
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Onboard All Variants'),
        content: Text('Do you want to onboard all ${availableVariants.length} variants?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: cs.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Onboard All'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Show progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Onboarding variants...'),
              ],
            ),
          ),
        ),
      ),
    );

    // Onboard all variants using selection-based approach
    final provider = context.read<BrandOnboardingProvider>();

    // Clear previous selection and select all available variants
    provider.clearSelection();
    for (final variant in availableVariants) {
      provider.toggleVariant(widget.brand.id, variant.id);
    }

    // Onboard all selected variants
    final success = await provider.onboardSelectedBrands();

    if (!mounted) return;

    Navigator.pop(context); // Close progress dialog

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${availableVariants.length} variants onboarded successfully!'),
          backgroundColor: AppColors.success,
        ),
      );

      // Refresh product list
      context.read<ProductProvider>().refreshProducts();

      setState(() {}); // Refresh UI
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.errorMessage ?? 'Failed to onboard variants'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _navigateToStockSetup() {
    // Get all products for this brand
    final productProvider = context.read<ProductProvider>();
    final brandProducts = productProvider.products
        .where((p) => p.brand?.id == widget.brand.id)
        .toList();

    if (brandProducts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No products found for this brand'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    // Navigate to Initial Stock Screen with product IDs
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => InitialStockScreen(
          productIds: brandProducts.map((p) => p.id).toList(),
        ),
      ),
    );
  }
}
