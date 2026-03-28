import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../models/excise_models.dart';
import '../providers/excise_provider.dart';
import '../widgets/compliance_score_card.dart';
import '../widgets/license_status_card.dart';
import '../widgets/report_status_card.dart';
import '../widgets/security_code_stats_card.dart';
import 'license_list_screen.dart';
import 'daily_report_list_screen.dart';
import 'security_code_scanner_screen.dart';

class ComplianceDashboardScreen extends StatefulWidget {
  const ComplianceDashboardScreen({super.key});

  @override
  State<ComplianceDashboardScreen> createState() => _ComplianceDashboardScreenState();
}

class _ComplianceDashboardScreenState extends State<ComplianceDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    final provider = context.read<ExciseProvider>();
    await Future.wait([
      provider.loadDashboard(),
      provider.loadLicenses(),
      provider.loadDailyReports(),
      provider.loadSecurityCodeStats(),
    ]);
  }

  Future<void> _refreshData() async {
    final provider = context.read<ExciseProvider>();
    await provider.refreshAll();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'UP Excise Compliance',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshData,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              // Navigate to settings
            },
            tooltip: 'Settings',
          ),
        ],
      ),
      body: Consumer<ExciseProvider>(
        builder: (context, provider, child) {
          if (provider.isDashboardLoading && provider.dashboard == null) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (provider.error != null) {
            return Center(
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
                    'Error loading dashboard',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      provider.error!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _loadData,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final dashboard = provider.dashboard;

          return RefreshIndicator(
            onRefresh: _refreshData,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Compliance Score Card (Hero)
                  if (dashboard != null)
                    ComplianceScoreCard(dashboard: dashboard),

                  const SizedBox(height: 16),

                  // Quick Stats Grid
                  _buildQuickStatsGrid(provider),

                  const SizedBox(height: 24),

                  // Alerts Section
                  if (provider.expiringLicenses.isNotEmpty ||
                      provider.expiredLicenses.isNotEmpty ||
                      provider.pendingReports.isNotEmpty)
                    _buildAlertsSection(provider),

                  const SizedBox(height: 24),

                  // Quick Actions
                  _buildQuickActionsSection(context),

                  const SizedBox(height: 24),

                  // Recent Activity
                  if (dashboard != null)
                    _buildRecentActivitySection(dashboard),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildQuickStatsGrid(ExciseProvider provider) {
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.5,
      children: [
        LicenseStatusCard(
          totalLicenses: provider.licenses.length,
          activeLicenses: provider.licenses.where((l) => !l.isExpired).length,
          expiringLicenses: provider.expiringLicenses.length,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const LicenseListScreen(),
              ),
            );
          },
        ),
        ReportStatusCard(
          totalReports: provider.dailyReports.length,
          pendingReports: provider.pendingReports.length,
          uploadedReports:
              provider.dailyReports.where((r) => r.uploadedToPortal).length,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const DailyReportListScreen(),
              ),
            );
          },
        ),
        if (provider.codeStats != null)
          SecurityCodeStatsCard(
            stats: provider.codeStats!,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SecurityCodeScannerScreen(),
                ),
              );
            },
          ),
        _buildConsiderationFeeCard(provider),
      ],
    );
  }

  Widget _buildConsiderationFeeCard(ExciseProvider provider) {
    final cs = Theme.of(context).colorScheme;
    final soldCodes = provider.codeStats?.totalSold ?? 0;
    final feePerBottle = 50.0;
    final totalFee = soldCodes * feePerBottle;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: InkWell(
        onTap: () {
          // Navigate to consideration fees detail
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.currency_rupee,
                      color: Colors.green[700],
                      size: 20,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
              const Spacer(),
              Text(
                '₹${totalFee.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Consideration Fees',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface,
                ),
              ),
              Text(
                '$soldCodes bottles × ₹$feePerBottle',
                style: TextStyle(
                  fontSize: 10,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAlertsSection(ExciseProvider provider) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange[700]),
                const SizedBox(width: 8),
                Text(
                  'Alerts & Notifications',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const Divider(height: 24),
            if (provider.expiredLicenses.isNotEmpty)
              _buildAlertItem(
                icon: Icons.error,
                color: Colors.red,
                title: 'Expired Licenses',
                subtitle:
                    '${provider.expiredLicenses.length} license(s) have expired',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const LicenseListScreen(),
                    ),
                  );
                },
              ),
            if (provider.expiringLicenses.isNotEmpty)
              _buildAlertItem(
                icon: Icons.warning,
                color: Colors.orange,
                title: 'Expiring Soon',
                subtitle:
                    '${provider.expiringLicenses.length} license(s) expiring in 30 days',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const LicenseListScreen(),
                    ),
                  );
                },
              ),
            if (provider.pendingReports.isNotEmpty)
              _buildAlertItem(
                icon: Icons.upload_file,
                color: Colors.blue,
                title: 'Pending Reports',
                subtitle:
                    '${provider.pendingReports.length} report(s) need to be uploaded',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const DailyReportListScreen(),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertItem({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Actions',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildQuickActionButton(
                context: context,
                icon: Icons.auto_awesome,
                label: 'Auto-Generate Report',
                color: Colors.blue,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const DailyReportListScreen(),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildQuickActionButton(
                context: context,
                icon: Icons.qr_code_scanner,
                label: 'Scan Security Code',
                color: Colors.purple,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SecurityCodeScannerScreen(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickActionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentActivitySection(ComplianceDashboard dashboard) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Compliance Summary',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const Divider(height: 24),
            _buildSummaryRow('Total Licenses', dashboard.totalLicenses.toString()),
            _buildSummaryRow('Active Licenses', dashboard.activeLicenses.toString()),
            _buildSummaryRow('Pending Reports', dashboard.pendingReports.toString()),
            _buildSummaryRow(
              'Last Updated',
              _formatDateTime(dashboard.lastUpdated ?? DateTime.now()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 14,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
  }
}
