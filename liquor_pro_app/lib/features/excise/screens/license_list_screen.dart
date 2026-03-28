import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../models/excise_models.dart';
import '../providers/excise_provider.dart';
import 'license_detail_screen.dart';
import 'add_license_screen.dart';

class LicenseListScreen extends StatefulWidget {
  const LicenseListScreen({super.key});

  @override
  State<LicenseListScreen> createState() => _LicenseListScreenState();
}

class _LicenseListScreenState extends State<LicenseListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ExciseProvider>().loadLicenses();
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
      appBar: CustomAppBar(
        title: 'Excise Licenses',
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Expiring Soon'),
            Tab(text: 'Expired'),
          ],
        ),
      ),
      body: Consumer<ExciseProvider>(
        builder: (context, provider, child) {
          if (provider.isLicensesLoading && provider.licenses.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (provider.error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                  const SizedBox(height: 16),
                  Text(
                    'Error loading licenses',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      provider.error!,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => provider.loadLicenses(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          return TabBarView(
            controller: _tabController,
            children: [
              _buildLicenseList(provider.licenses),
              _buildLicenseList(provider.expiringLicenses),
              _buildLicenseList(provider.expiredLicenses),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const AddLicenseScreen(),
            ),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Add License'),
      ),
    );
  }

  Widget _buildLicenseList(List<ExciseLicense> licenses) {
    if (licenses.isEmpty) {
      final cs = Theme.of(context).colorScheme;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.verified_user_outlined,
              size: 64,
              color: cs.outlineVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No licenses found',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: cs.onSurface,
                  ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => context.read<ExciseProvider>().loadLicenses(),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: licenses.length,
        itemBuilder: (context, index) {
          final license = licenses[index];
          return _LicenseCard(
            license: license,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => LicenseDetailScreen(license: license),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _LicenseCard extends StatelessWidget {
  final ExciseLicense license;
  final VoidCallback onTap;

  const _LicenseCard({
    required this.license,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: license.isExpired
              ? Colors.red
              : license.isExpiringSoon
                  ? Colors.orange
                  : cs.outline.withValues(alpha: 0.2),
          width: license.isExpired || license.isExpiringSoon ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: license.licenseType.color.withValues(alpha:0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.verified_user,
                      color: license.licenseType.color,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          license.licenseType.displayName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          license.licenseNumber,
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: license.statusColor.withValues(alpha:0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      license.statusText,
                      style: TextStyle(
                        color: license.statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildInfoItem(
                      context,
                      icon: Icons.calendar_today,
                      label: 'Issued',
                      value: _formatDate(license.issuedDate),
                    ),
                  ),
                  Expanded(
                    child: _buildInfoItem(
                      context,
                      icon: Icons.event,
                      label: 'Expires',
                      value: _formatDate(license.expiryDate),
                      valueColor: license.statusColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildInfoItem(
                      context,
                      icon: Icons.business,
                      label: 'Authority',
                      value: license.issuingAuthority ?? 'Unknown',
                    ),
                  ),
                  Expanded(
                    child: _buildInfoItem(
                      context,
                      icon: Icons.currency_rupee,
                      label: 'Monthly Fee',
                      value: '₹${license.monthlyFee.toStringAsFixed(0)}',
                    ),
                  ),
                ],
              ),
              if (license.isExpiringSoon || license.isExpired) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: license.statusColor.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        license.isExpired
                            ? Icons.error
                            : Icons.warning_amber_rounded,
                        color: license.statusColor,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          license.isExpired
                              ? 'License has expired. Please renew immediately.'
                              : 'License expiring in ${license.daysUntilExpiry} days',
                          style: TextStyle(
                            color: license.statusColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: valueColor,
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
