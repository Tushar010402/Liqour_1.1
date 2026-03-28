import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../providers/excise_provider.dart';

class ExciseAnalyticsScreen extends StatefulWidget {
  const ExciseAnalyticsScreen({super.key});

  @override
  State<ExciseAnalyticsScreen> createState() => _ExciseAnalyticsScreenState();
}

class _ExciseAnalyticsScreenState extends State<ExciseAnalyticsScreen> {
  String _selectedPeriod = 'month';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAnalytics();
    });
  }

  Future<void> _loadAnalytics() async {
    final provider = context.read<ExciseProvider>();
    await Future.wait([
      provider.loadDashboard(),
      provider.loadLicenses(),
      provider.loadDailyReports(),
      provider.loadSecurityCodeStats(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Analytics & Insights',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAnalytics,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAnalytics,
        child: Consumer<ExciseProvider>(
          builder: (context, provider, child) {
            if (provider.isDashboardLoading && provider.dashboard == null) {
              return const Center(child: CircularProgressIndicator());
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Period Selector
                  _buildPeriodSelector(),

                  const SizedBox(height: 16),

                  // Compliance Trend Card
                  _buildComplianceTrendCard(provider),

                  const SizedBox(height: 16),

                  // License Analytics
                  _buildLicenseAnalytics(provider),

                  const SizedBox(height: 16),

                  // Report Analytics
                  _buildReportAnalytics(provider),

                  const SizedBox(height: 16),

                  // Security Code Analytics
                  _buildSecurityCodeAnalytics(provider),

                  const SizedBox(height: 16),

                  // Financial Analytics
                  _buildFinancialAnalytics(provider),

                  const SizedBox(height: 16),

                  // Performance Metrics
                  _buildPerformanceMetrics(provider),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPeriodSelector() {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: cs.outline.withValues(alpha: 0.2))),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: SegmentedButton<String>(
          selected: {_selectedPeriod},
          onSelectionChanged: (Set<String> selected) {
            setState(() => _selectedPeriod = selected.first);
          },
          segments: const [
            ButtonSegment(
              value: 'week',
              label: Text('Week'),
              icon: Icon(Icons.calendar_view_week),
            ),
            ButtonSegment(
              value: 'month',
              label: Text('Month'),
              icon: Icon(Icons.calendar_month),
            ),
            ButtonSegment(
              value: 'year',
              label: Text('Year'),
              icon: Icon(Icons.calendar_today),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComplianceTrendCard(ExciseProvider provider) {
    final dashboard = provider.dashboard;
    if (dashboard == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: cs.outline.withValues(alpha: 0.2))),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              dashboard.scoreColor,
              dashboard.scoreColor.withValues(alpha:0.7),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Compliance Trend',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha:0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        dashboard.complianceScore >= 90
                            ? Icons.trending_up
                            : Icons.trending_flat,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${dashboard.complianceScore >= 90 ? '+' : ''}${(dashboard.complianceScore - 85).toInt()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildTrendMetric('Current', '${dashboard.complianceScore.toInt()}', Colors.white),
                _buildTrendMetric('Average', '85', Colors.white70),
                _buildTrendMetric('Target', '95', Colors.white70),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendMetric(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: color.withValues(alpha:0.8),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildLicenseAnalytics(ExciseProvider provider) {
    final licenses = provider.licenses;
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: cs.outline.withValues(alpha: 0.2))),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified_user, color: Colors.blue[700]),
                const SizedBox(width: 8),
                Text(
                  'License Analytics',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const Divider(height: 24),
            _buildAnalyticsRow(
              'Total Licenses',
              licenses.length.toString(),
              Colors.blue,
            ),
            _buildAnalyticsRow(
              'Active Licenses',
              licenses.where((l) => !l.isExpired).length.toString(),
              Colors.green,
            ),
            _buildAnalyticsRow(
              'Expiring Soon',
              provider.expiringLicenses.length.toString(),
              Colors.orange,
            ),
            _buildAnalyticsRow(
              'Expired',
              provider.expiredLicenses.length.toString(),
              Colors.red,
            ),
            const Divider(height: 16),
            _buildProgressBar(
              'Compliance Rate',
              licenses.isEmpty ? 0 : (licenses.where((l) => !l.isExpired).length / licenses.length * 100),
              Colors.blue,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportAnalytics(ExciseProvider provider) {
    final reports = provider.dailyReports;
    final uploadedCount = reports.where((r) => r.uploadedToPortal).length;
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: cs.outline.withValues(alpha: 0.2))),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.description, color: Colors.teal[700]),
                const SizedBox(width: 8),
                Text(
                  'Report Analytics',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const Divider(height: 24),
            _buildAnalyticsRow(
              'Total Reports',
              reports.length.toString(),
              Colors.teal,
            ),
            _buildAnalyticsRow(
              'Uploaded',
              uploadedCount.toString(),
              Colors.green,
            ),
            _buildAnalyticsRow(
              'Pending Upload',
              provider.pendingReports.length.toString(),
              Colors.orange,
            ),
            const Divider(height: 16),
            _buildProgressBar(
              'Upload Rate',
              reports.isEmpty ? 0 : (uploadedCount / reports.length * 100),
              Colors.teal,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecurityCodeAnalytics(ExciseProvider provider) {
    final stats = provider.codeStats;
    if (stats == null) return const SizedBox.shrink();

    final utilizationRate = stats.totalCodes == 0
        ? 0.0
        : (stats.totalSold / stats.totalCodes * 100);
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: cs.outline.withValues(alpha: 0.2))),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.qr_code, color: Colors.purple[700]),
                const SizedBox(width: 8),
                Text(
                  'Security Code Analytics',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const Divider(height: 24),
            _buildAnalyticsRow(
              'Total Codes',
              stats.totalCodes.toString(),
              Colors.purple,
            ),
            _buildAnalyticsRow(
              'In Stock',
              stats.totalInStock.toString(),
              Colors.green,
            ),
            _buildAnalyticsRow(
              'Sold',
              stats.totalSold.toString(),
              Colors.blue,
            ),
            _buildAnalyticsRow(
              'Damaged',
              stats.totalDamaged.toString(),
              Colors.red,
            ),
            const Divider(height: 16),
            _buildProgressBar(
              'Utilization Rate',
              utilizationRate,
              Colors.purple,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFinancialAnalytics(ExciseProvider provider) {
    final stats = provider.codeStats;
    final licenses = provider.licenses;

    final monthlyLicenseFees = licenses.fold<double>(
      0,
      (sum, license) => sum + license.monthlyFee,
    );
    final considerationFees = (stats?.totalSold ?? 0) * 50.0;
    final totalFees = monthlyLicenseFees + considerationFees;
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: cs.outline.withValues(alpha: 0.2))),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.currency_rupee, color: Colors.green[700]),
                const SizedBox(width: 8),
                Text(
                  'Financial Analytics',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const Divider(height: 24),
            _buildFinancialRow(
              'Monthly License Fees',
              monthlyLicenseFees,
              Colors.blue,
            ),
            _buildFinancialRow(
              'Consideration Fees',
              considerationFees,
              Colors.green,
            ),
            _buildFinancialRow(
              'Total Fees',
              totalFees,
              Colors.orange,
              isTotal: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPerformanceMetrics(ExciseProvider provider) {
    final dashboard = provider.dashboard;
    if (dashboard == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: cs.outline.withValues(alpha: 0.2))),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.speed, color: Colors.indigo[700]),
                const SizedBox(width: 8),
                Text(
                  'Performance Metrics',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const Divider(height: 24),
            GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.8,
              children: [
                _buildMetricCard(
                  'Compliance',
                  '${dashboard.complianceScore.toInt()}%',
                  Icons.check_circle,
                  dashboard.scoreColor,
                ),
                _buildMetricCard(
                  'Active Licenses',
                  dashboard.activeLicenses.toString(),
                  Icons.verified_user,
                  Colors.blue,
                ),
                _buildMetricCard(
                  'Pending Reports',
                  dashboard.pendingReports.toString(),
                  Icons.pending_actions,
                  Colors.orange,
                ),
                _buildMetricCard(
                  'Total Licenses',
                  dashboard.totalLicenses.toString(),
                  Icons.assignment,
                  Colors.purple,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyticsRow(String label, String value, Color color) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(String label, double percentage, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '${percentage.toInt()}%',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: percentage / 100,
            backgroundColor: color.withValues(alpha:0.2),
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 8,
          ),
        ),
      ],
    );
  }

  Widget _buildFinancialRow(String label, double amount, Color color, {bool isTotal = false}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: isTotal ? null : cs.onSurfaceVariant,
            ),
          ),
          Text(
            '₹${amount.toStringAsFixed(0)}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(String label, String value, IconData icon, Color color) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: cs.outline.withValues(alpha: 0.2))),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
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
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
