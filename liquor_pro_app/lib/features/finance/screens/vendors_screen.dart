import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/empty_state_widget.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../providers/vendor_provider.dart';
import '../models/vendor_model.dart';
import 'vendor_form_screen.dart';
import 'vendor_detail_screen.dart';

/// Modern Vendors Management Screen - Settings-style UI
///
/// Features:
/// - Financial summary banner with bordered container
/// - iOS-style search bar
/// - Skeleton loading states
/// - Color-coded outstanding balance badges
/// - Pull-to-refresh
/// - Modern card design
class VendorsScreen extends StatefulWidget {
  const VendorsScreen({super.key});

  @override
  State<VendorsScreen> createState() => _VendorsScreenState();
}

class _VendorsScreenState extends State<VendorsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _showInactive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadVendors();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadVendors() async {
    final provider = context.read<VendorProvider>();
    await provider.loadVendors(includeInactive: _showInactive);
  }

  List<Vendor> _getFilteredVendors(List<Vendor> vendors) {
    if (_searchQuery.isEmpty) return vendors;

    return vendors.where((vendor) {
      final query = _searchQuery.toLowerCase();
      return vendor.name.toLowerCase().contains(query) ||
             (vendor.contactPerson?.toLowerCase().contains(query) ?? false) ||
             (vendor.phone?.contains(_searchQuery) ?? false) ||
             (vendor.email?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: CustomAppBar(
        title: 'Godams',
        actions: [
          IconButton(
            icon: Icon(_showInactive ? Icons.visibility : Icons.visibility_off),
            onPressed: () {
              setState(() {
                _showInactive = !_showInactive;
              });
              _loadVendors();
            },
            tooltip: _showInactive ? 'Hide Inactive' : 'Show Inactive',
          ),
        ],
      ),
      body: Consumer<VendorProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.vendors.isEmpty) {
            return _buildSkeletonLoader();
          }

          if (provider.errorMessage != null && provider.vendors.isEmpty) {
            return _buildErrorState(provider.errorMessage!);
          }

          final filteredVendors = _getFilteredVendors(provider.vendors);

          return Column(
            children: [
              // Financial Summary Banner
              _buildFinancialSummary(provider),

              // Search Bar
              _buildSearchBar(),

              // Vendors List
              Expanded(
                child: filteredVendors.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _loadVendors,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: filteredVendors.length,
                          itemBuilder: (context, index) {
                            return _buildVendorCard(filteredVendors[index]);
                          },
                        ),
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _navigateToForm(),
        backgroundColor: cs.primary,
        icon: const Icon(Icons.add_business, color: Colors.white),
        label: const Text('Add Vendor', style: TextStyle(color: Colors.white)),
      ),
    );
  }

  Widget _buildFinancialSummary(VendorProvider provider) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildSummaryItem(
              'Active Vendors',
              provider.activeVendorCount.toString(),
              Icons.business_outlined,
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: cs.outline.withValues(alpha: 0.2),
          ),
          Expanded(
            child: _buildSummaryItem(
              'Total Outstanding',
              Formatters.currency(provider.totalOutstanding),
              Icons.account_balance_wallet_outlined,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [cs.primary, cs.primary.withValues(alpha: 0.7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: CupertinoSearchTextField(
        controller: _searchController,
        placeholder: 'Search vendors...',
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
          });
        },
        style: TextStyle(color: cs.onSurface),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.outlineVariant),
        ),
      ),
    );
  }

  Widget _buildVendorCard(Vendor vendor) {
    final cs = Theme.of(context).colorScheme;
    final hasOutstanding = vendor.outstandingBalance > 0;
    final isHighOutstanding = vendor.outstandingBalance > vendor.creditLimit * 0.8;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: InkWell(
        onTap: () => _navigateToDetail(vendor),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                children: [
                  // Vendor Icon
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: vendor.isActive
                          ? cs.primary.withValues(alpha: 0.1)
                          : cs.outlineVariant,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.business,
                      color: vendor.isActive ? cs.primary : cs.onSurfaceVariant,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Vendor Name and Status
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          vendor.name,
                          style: AppTextStyles.bodyLarge.copyWith(
                            fontWeight: FontWeight.w600,
                            color: vendor.isActive ? cs.onSurface : cs.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: vendor.isActive
                                    ? Colors.green[50]
                                    : cs.outlineVariant,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                vendor.statusText,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: vendor.isActive
                                      ? Colors.green[700]
                                      : cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                            if (isHighOutstanding) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.orange[50],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.warning_amber, size: 12, color: Colors.orange[700]),
                                    const SizedBox(width: 4),
                                    Text(
                                      'High Outstanding',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.orange[700],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Outstanding Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: hasOutstanding
                          ? Colors.orange[50]
                          : Colors.green[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          Formatters.currency(vendor.outstandingBalance),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: hasOutstanding
                                ? Colors.orange[700]
                                : Colors.green[700],
                          ),
                        ),
                        Text(
                          'Outstanding',
                          style: TextStyle(
                            fontSize: 10,
                            color: hasOutstanding
                                ? Colors.orange[600]
                                : Colors.green[600],
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

              // Contact Info
              Row(
                children: [
                  if (vendor.phone != null) ...[
                    Icon(Icons.phone_outlined, size: 16, color: cs.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text(
                      vendor.phone!,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                  if (vendor.email != null && vendor.phone != null) ...[
                    const SizedBox(width: 16),
                    Text('•', style: TextStyle(color: cs.onSurfaceVariant)),
                    const SizedBox(width: 16),
                  ],
                  if (vendor.email != null) ...[
                    Icon(Icons.email_outlined, size: 16, color: cs.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        vendor.email!,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: cs.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),

              // Financial Summary
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildFinancialMetric(
                      'Total Purchases',
                      Formatters.currency(vendor.totalPurchases),
                      cs.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildFinancialMetric(
                      'Credit Limit',
                      Formatters.currency(vendor.creditLimit),
                      cs.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFinancialMetric(String label, String value, Color color) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonLoader() {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        // Skeleton Summary Banner
        Container(
          margin: const EdgeInsets.all(16),
          height: 100,
          decoration: BoxDecoration(
            color: cs.outlineVariant,
            borderRadius: BorderRadius.circular(16),
          ),
        ),

        // Skeleton Search Bar
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          height: 44,
          decoration: BoxDecoration(
            color: cs.outlineVariant,
            borderRadius: BorderRadius.circular(10),
          ),
        ),

        // Skeleton Cards
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: 5,
            itemBuilder: (context, index) {
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                height: 160,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return EmptyStateWidget(
      icon: Icons.business_outlined,
      title: _searchQuery.isEmpty ? 'No Vendors' : 'No Results',
      message: _searchQuery.isEmpty
          ? 'Add your first vendor to get started'
          : 'No vendors found matching "$_searchQuery"',
    );
  }

  Widget _buildErrorState(String error) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red[300],
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to Load Vendors',
              style: AppTextStyles.bodyLarge.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: AppTextStyles.bodyMedium.copyWith(
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadVendors,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToForm({Vendor? vendor}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VendorFormScreen(vendor: vendor),
      ),
    ).then((_) => _loadVendors());
  }

  void _navigateToDetail(Vendor vendor) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VendorDetailScreen(vendorId: vendor.id),
      ),
    ).then((_) => _loadVendors());
  }
}
