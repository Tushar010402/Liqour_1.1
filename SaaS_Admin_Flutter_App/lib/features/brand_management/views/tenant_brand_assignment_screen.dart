import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/brand_model.dart';
import '../controllers/brand_provider.dart';
import '../../tenant_management/controllers/tenant_provider.dart';

class TenantBrandAssignmentScreen extends StatefulWidget {
  final Brand? selectedBrand;

  const TenantBrandAssignmentScreen({super.key, this.selectedBrand});

  @override
  State<TenantBrandAssignmentScreen> createState() =>
      _TenantBrandAssignmentScreenState();
}

class _TenantBrandAssignmentScreenState
    extends State<TenantBrandAssignmentScreen> {
  String? _selectedTenantId;
  final Set<String> _selectedBrandIds = <String>{};
  final Set<String> _selectedVariantIds = <String>{};

  @override
  void initState() {
    super.initState();
    if (widget.selectedBrand != null) {
      _selectedBrandIds.add(widget.selectedBrand!.id);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BrandProvider>().initialize();
      context.read<TenantProvider>().loadTenants();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGray,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.primaryBlack,
        title: const Text('Assign Brands to Tenant'),
        actions: [
          TextButton(
            onPressed: _canAssign() ? _assignBrands : null,
            child: Text(
              'Assign',
              style: TextStyle(
                color:
                    _canAssign() ? AppColors.primaryRed : AppColors.mediumGray,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: Consumer2<BrandProvider, TenantProvider>(
        builder: (context, brandProvider, tenantProvider, child) {
          if (brandProvider.isLoading || tenantProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          return Column(
            children: [
              _buildTenantSelection(tenantProvider),
              if (_selectedTenantId != null) ...[
                _buildBrandSelection(brandProvider),
                _buildAssignmentSummary(),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildTenantSelection(TenantProvider tenantProvider) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(
          bottom: BorderSide(color: AppColors.borderGray, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.business, color: AppColors.primaryRed),
              SizedBox(width: 8),
              Text(
                'Select Tenant',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryBlack,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _selectedTenantId,
            hint: const Text('Choose a tenant to assign brands'),
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            ),
            items: tenantProvider.tenants.map((tenant) {
              return DropdownMenuItem(
                value: tenant.id,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tenant.name,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    if (tenant.email.isNotEmpty)
                      Text(
                        tenant.email,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.mediumGray,
                        ),
                      ),
                  ],
                ),
              );
            }).toList(),
            onChanged: (value) {
              setState(() {
                _selectedTenantId = value;
                _selectedBrandIds.clear();
                _selectedVariantIds.clear();
                if (widget.selectedBrand != null) {
                  _selectedBrandIds.add(widget.selectedBrand!.id);
                }
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBrandSelection(BrandProvider brandProvider) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.local_drink, color: AppColors.primaryRed),
                const SizedBox(width: 8),
                const Text(
                  'Select Brands',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryBlack,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_selectedBrandIds.length} selected',
                  style: const TextStyle(
                    color: AppColors.mediumGray,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: brandProvider.brands.length,
                itemBuilder: (context, index) {
                  final brand = brandProvider.brands[index];
                  final isSelected = _selectedBrandIds.contains(brand.id);

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: isSelected
                            ? AppColors.primaryRed
                            : AppColors.borderGray,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: CheckboxListTile(
                      value: isSelected,
                      onChanged: widget.selectedBrand?.id == brand.id
                          ? null // Disable checkbox for pre-selected brand
                          : (selected) {
                              setState(() {
                                if (selected == true) {
                                  _selectedBrandIds.add(brand.id);
                                } else {
                                  _selectedBrandIds.remove(brand.id);
                                  // Remove all variants of this brand
                                  brand.brandVariants?.forEach((variant) {
                                    _selectedVariantIds.remove(variant.id);
                                  });
                                }
                              });
                            },
                      activeColor: AppColors.primaryRed,
                      title: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppColors.primaryRed.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: brand.picture.isNotEmpty
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image.network(
                                      brand.picture,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              const Icon(Icons.local_drink,
                                                  color: AppColors.primaryRed,
                                                  size: 20),
                                    ),
                                  )
                                : const Icon(Icons.local_drink,
                                    color: AppColors.primaryRed, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  brand.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (brand.description.isNotEmpty)
                                  Text(
                                    brand.description,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.mediumGray,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                Text(
                                  '${brand.brandVariants?.length ?? 0} variants',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.mediumGray,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      subtitle: isSelected &&
                              (brand.brandVariants?.isNotEmpty ?? false)
                          ? _buildVariantSelection(brand)
                          : null,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVariantSelection(Brand brand) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.lightGray,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Select Variants (Optional):',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.mediumGray,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: brand.brandVariants!
                .where((variant) => variant.isActive)
                .map((variant) {
              final isSelected = _selectedVariantIds.contains(variant.id);
              return FilterChip(
                label: Text(
                  variant.size,
                  style: TextStyle(
                    fontSize: 10,
                    color:
                        isSelected ? AppColors.white : AppColors.primaryBlack,
                  ),
                ),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedVariantIds.add(variant.id);
                    } else {
                      _selectedVariantIds.remove(variant.id);
                    }
                  });
                },
                backgroundColor: AppColors.white,
                selectedColor: AppColors.primaryRed,
                checkmarkColor: AppColors.white,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildAssignmentSummary() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(
          top: BorderSide(color: AppColors.borderGray, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Assignment Summary',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryBlack,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildSummaryItem('Brands', _selectedBrandIds.length.toString(),
                  Icons.local_drink),
              const SizedBox(width: 24),
              _buildSummaryItem('Variants',
                  _selectedVariantIds.length.toString(), Icons.inventory_2),
            ],
          ),
          if (_selectedBrandIds.isEmpty)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber, color: AppColors.warning, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Select at least one brand to assign',
                    style: TextStyle(
                      color: AppColors.warning,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String count, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primaryRed, size: 20),
        const SizedBox(width: 6),
        Text(
          '$count $label',
          style: const TextStyle(
            fontWeight: FontWeight.w500,
            color: AppColors.primaryBlack,
          ),
        ),
      ],
    );
  }

  bool _canAssign() {
    return _selectedTenantId != null && _selectedBrandIds.isNotEmpty;
  }

  Future<void> _assignBrands() async {
    if (!_canAssign()) return;

    final brandProvider = context.read<BrandProvider>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Assigning brands...'),
          ],
        ),
      ),
    );

    try {
      final request = TenantBrandAssignmentRequest(
        tenantId: _selectedTenantId!,
        brandIds: _selectedBrandIds.toList(),
        variantIds: _selectedVariantIds.toList(),
      );

      final success = await brandProvider.assignBrandsToTenant(request);

      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog

        if (success) {
          Navigator.of(context).pop(); // Close assignment screen
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Successfully assigned ${_selectedBrandIds.length} brand(s) to tenant',
              ),
              backgroundColor: AppColors.success,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(brandProvider.error ?? 'Failed to assign brands'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}
