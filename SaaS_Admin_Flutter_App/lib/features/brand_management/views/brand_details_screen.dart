import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/brand_model.dart';
import '../controllers/brand_provider.dart';
import 'brand_form_screen.dart';
import 'brand_variant_form_screen.dart';

class BrandDetailsScreen extends StatefulWidget {
  final Brand brand;

  const BrandDetailsScreen({super.key, required this.brand});

  @override
  State<BrandDetailsScreen> createState() => _BrandDetailsScreenState();
}

class _BrandDetailsScreenState extends State<BrandDetailsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BrandProvider>().loadBrandVariants(widget.brand.id);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGray,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.primaryBlack,
        title: Text(widget.brand.name),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => BrandFormScreen(brand: widget.brand),
              ),
            ),
            icon: const Icon(Icons.edit),
            tooltip: 'Edit Brand',
          ),
          PopupMenuButton<String>(
            onSelected: _handleMenuAction,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'add_variant',
                child: Row(
                  children: [
                    Icon(Icons.add, size: 20),
                    SizedBox(width: 8),
                    Text('Add Variant'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'assign_tenant',
                child: Row(
                  children: [
                    Icon(Icons.assignment_ind, size: 20),
                    SizedBox(width: 8),
                    Text('Assign to Tenant'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, size: 20, color: AppColors.error),
                    SizedBox(width: 8),
                    Text('Delete', style: TextStyle(color: AppColors.error)),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primaryRed,
          labelColor: AppColors.primaryRed,
          unselectedLabelColor: AppColors.mediumGray,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Variants'),
          ],
        ),
      ),
      body: Consumer<BrandProvider>(
        builder: (context, provider, child) {
          return TabBarView(
            controller: _tabController,
            children: [
              _buildOverviewTab(),
              _buildVariantsTab(provider),
            ],
          );
        },
      ),
      floatingActionButton: _tabController.index == 1
          ? AnimatedScale(
              scale: _tabController.index == 1 ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: FloatingActionButton.extended(
                onPressed: () => _navigateToAddVariant(),
                backgroundColor: AppColors.primaryRed,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.add),
                label: const Text('Add Variant'),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBrandHeader(),
          const SizedBox(height: 24),
          _buildBrandInfo(),
          const SizedBox(height: 24),
          _buildBrandStats(),
        ],
      ),
    );
  }

  Widget _buildBrandHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.primaryRed.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: widget.brand.picture.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      widget.brand.picture,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                          Icons.local_drink,
                          color: AppColors.primaryRed,
                          size: 40),
                    ),
                  )
                : const Icon(Icons.local_drink,
                    color: AppColors.primaryRed, size: 40),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.brand.name,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryBlack,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.brand.description,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.mediumGray,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: widget.brand.isActive
                            ? AppColors.success.withOpacity(0.1)
                            : AppColors.error.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        widget.brand.isActive ? 'Active' : 'Inactive',
                        style: TextStyle(
                          fontSize: 12,
                          color: widget.brand.isActive
                              ? AppColors.success
                              : AppColors.error,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Sort Order: ${widget.brand.sortOrder}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.mediumGray,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrandInfo() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline, color: AppColors.primaryRed),
              SizedBox(width: 8),
              Text(
                'Brand Information',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryBlack,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoRow('Brand ID', widget.brand.id),
          _buildInfoRow('Created', widget.brand.createdAt ?? 'N/A'),
          _buildInfoRow('Last Updated', widget.brand.updatedAt ?? 'N/A'),
          _buildInfoRow(
              'Total Variants', '${widget.brand.brandVariants?.length ?? 0}'),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: AppColors.mediumGray,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.primaryBlack,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrandStats() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.analytics_outlined, color: AppColors.primaryRed),
              SizedBox(width: 8),
              Text(
                'Statistics',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryBlack,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Variants',
                  '${widget.brand.brandVariants?.length ?? 0}',
                  Icons.view_list,
                  AppColors.primaryBlue,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatCard(
                  'Active Variants',
                  '${widget.brand.brandVariants?.where((v) => v.isActive).length ?? 0}',
                  Icons.check_circle,
                  AppColors.success,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.mediumGray,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVariantsTab(BrandProvider provider) {
    if (provider.isLoading && provider.currentBrandVariants.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final variants = provider.currentBrandVariants;

    if (variants.isEmpty) {
      return _buildEmptyVariantsState();
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: variants.length,
      itemBuilder: (context, index) => _buildVariantCard(variants[index]),
    );
  }

  Widget _buildEmptyVariantsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppColors.lightGray,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              size: 64,
              color: AppColors.mediumGray,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'No Variants Found',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryBlack,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add variants to ${widget.brand.name}',
            style: const TextStyle(
              color: AppColors.mediumGray,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _showAddVariantDialog(),
            icon: const Icon(Icons.add),
            label: const Text('Add Variant'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryRed,
              foregroundColor: AppColors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVariantCard(BrandVariant variant) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: variant.isActive
              ? AppColors.success.withOpacity(0.2)
              : AppColors.error.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _navigateToEditVariant(variant),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Hero(
                      tag: 'variant_${variant.id}',
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.primaryBlue.withOpacity(0.1),
                              AppColors.primaryBlue.withOpacity(0.2),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.primaryBlue.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: variant.picture.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  variant.picture,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Icon(
                                    Icons.inventory_2,
                                    color: AppColors.primaryBlue,
                                    size: 30,
                                  ),
                                ),
                              )
                            : const Icon(
                                Icons.inventory_2,
                                color: AppColors.primaryBlue,
                                size: 30,
                              ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  variant.size,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primaryBlack,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: variant.isActive
                                      ? AppColors.success
                                      : AppColors.error,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      variant.isActive
                                          ? Icons.check_circle
                                          : Icons.cancel,
                                      color: Colors.white,
                                      size: 12,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      variant.isActive ? 'Active' : 'Inactive',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          if (variant.description.isNotEmpty)
                            Text(
                              variant.description,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.mediumGray,
                                height: 1.3,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.primaryBlue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${variant.alcoholContent}% Alcohol',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.primaryBlue,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (value) => _handleVariantAction(value, variant),
                      icon: Icon(
                        Icons.more_vert,
                        color: AppColors.mediumGray,
                        size: 20,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: ListTile(
                            leading: Icon(Icons.edit, size: 18),
                            title: Text('Edit Variant'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: ListTile(
                            leading: Icon(Icons.delete, size: 18, color: AppColors.error),
                            title: Text('Delete Variant',
                                style: TextStyle(color: AppColors.error)),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          _buildEnhancedVariantDetail(
                            'MRP',
                            '₹${variant.mrp.toStringAsFixed(2)}',
                            Icons.currency_rupee,
                            AppColors.primaryRed,
                          ),
                          _buildEnhancedVariantDetail(
                            'Selling',
                            '₹${variant.sellingPrice.toStringAsFixed(2)}',
                            Icons.sell,
                            AppColors.success,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _buildEnhancedVariantDetail(
                            'Buying',
                            '₹${variant.buyingPrice.toStringAsFixed(2)}',
                            Icons.shopping_cart,
                            AppColors.primaryBlue,
                          ),
                          if (variant.barcode.isNotEmpty)
                            _buildEnhancedVariantDetail(
                              'Barcode',
                              variant.barcode,
                              Icons.qr_code,
                              AppColors.charcoalGray,
                            )
                          else if (variant.hsnCode.isNotEmpty)
                            _buildEnhancedVariantDetail(
                              'HSN',
                              variant.hsnCode,
                              Icons.numbers,
                              AppColors.charcoalGray,
                            )
                          else
                            const Expanded(child: SizedBox()),
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
  }

  Widget _buildVariantDetail(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.mediumGray,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.primaryBlack,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnhancedVariantDetail(
      String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.2)),
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
                  style: TextStyle(
                    fontSize: 11,
                    color: color.withOpacity(0.8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: color,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  void _handleMenuAction(String action) {
    switch (action) {
      case 'add_variant':
        _showAddVariantDialog();
        break;
      case 'assign_tenant':
        // TODO: Navigate to tenant assignment
        break;
      case 'delete':
        _showDeleteConfirmation();
        break;
    }
  }

  void _handleVariantAction(String action, BrandVariant variant) {
    switch (action) {
      case 'edit':
        _navigateToEditVariant(variant);
        break;
      case 'delete':
        _showVariantDeleteConfirmation(variant);
        break;
    }
  }

  void _navigateToEditVariant(BrandVariant variant) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => BrandVariantFormScreen(
          brand: widget.brand,
          variant: variant,
        ),
      ),
    );
  }

  void _showAddVariantDialog() {
    _navigateToAddVariant();
  }

  void _navigateToAddVariant() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => BrandVariantFormScreen(brand: widget.brand),
      ),
    );
  }

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning, color: AppColors.error),
            SizedBox(width: 12),
            Text('Delete Brand'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${widget.brand.name}"? This will also delete all variants.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              final provider = context.read<BrandProvider>();
              final success = await provider.deleteBrand(widget.brand.id);
              if (success && mounted) {
                if (mounted)
                  Navigator.of(context).pop(); // Close details screen
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Brand "${widget.brand.name}" deleted successfully'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showVariantDeleteConfirmation(BrandVariant variant) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Variant'),
        content: Text('Are you sure you want to delete variant "${variant.size}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              final provider = context.read<BrandProvider>();
              final success = await provider.deleteBrandVariant(variant.id);
              if (mounted) {
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Variant "${variant.size}" deleted successfully'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(provider.error ?? 'Failed to delete variant'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
