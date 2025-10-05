import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/excise_models.dart';
import '../providers/excise_provider.dart';
import 'license_detail_screen.dart';
import 'add_license_screen.dart';

class LicenseListScreen extends StatefulWidget {
  const LicenseListScreen({Key? key}) : super(key: key);

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
      appBar: AppBar(
        title: const Text('Excise Licenses'),
        centerTitle: true,
        elevation: 0,
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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.verified_user_outlined,
              size: 64,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 16),
            Text(
              'No licenses found',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.grey[600],
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
    Key? key,
    required this.license,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: license.isExpired
              ? Colors.red
              : license.isExpiringSoon
                  ? Colors.orange
                  : Colors.transparent,
          width: license.isExpired || license.isExpiringSoon ? 2 : 0,
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
                      color: license.licenseType.color.withOpacity(0.1),
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
                            color: Colors.grey[600],
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
                      color: license.statusColor.withOpacity(0.1),
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
                      icon: Icons.calendar_today,
                      label: 'Issued',
                      value: _formatDate(license.issuedDate),
                    ),
                  ),
                  Expanded(
                    child: _buildInfoItem(
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
                      icon: Icons.business,
                      label: 'Authority',
                      value: license.issuingAuthority ?? 'Unknown',
                    ),
                  ),
                  Expanded(
                    child: _buildInfoItem(
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
                    color: license.statusColor.withOpacity(0.1),
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

  Widget _buildInfoItem({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[400]),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey[600],
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
