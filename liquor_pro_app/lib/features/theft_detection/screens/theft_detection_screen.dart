import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/theft_models.dart';
import '../providers/theft_detection_provider.dart';

class TheftDetectionScreen extends ConsumerStatefulWidget {
  const TheftDetectionScreen({super.key});

  @override
  ConsumerState<TheftDetectionScreen> createState() =>
      _TheftDetectionScreenState();
}

class _TheftDetectionScreenState extends ConsumerState<TheftDetectionScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final summaryAsync = ref.watch(activeTheftSummaryProvider);
    final unreadCountAsync = ref.watch(unreadAlertsCountProvider);

    return Scaffold(
      backgroundColor: isDark ? Colors.black : const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black : const Color(0xFFF2F2F7),
        elevation: 0,
        title: const Text(
          'Theft Detection',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          // Alerts badge
          unreadCountAsync.when(
            data: (count) => Stack(
              children: [
                IconButton(
                  icon: const Icon(CupertinoIcons.bell),
                  onPressed: () => _showAlerts(),
                ),
                if (count > 0)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        count > 9 ? '9+' : count.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            loading: () => const IconButton(
              icon: Icon(CupertinoIcons.bell),
              onPressed: null,
            ),
            error: (_, __) => IconButton(
              icon: const Icon(CupertinoIcons.bell),
              onPressed: () => _showAlerts(),
            ),
          ),
          IconButton(
            icon: const Icon(CupertinoIcons.slider_horizontal_3),
            onPressed: () => _showSettings(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Theme.of(context).primaryColor,
          unselectedLabelColor: cs.onSurfaceVariant,
          indicatorColor: Theme.of(context).primaryColor,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Anomalies'),
            Tab(text: 'Investigations'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOverviewTab(summaryAsync),
          _buildAnomaliesTab(),
          _buildInvestigationsTab(),
        ],
      ),
    );
  }

  // ===========================================================================
  // OVERVIEW TAB
  // ===========================================================================

  Widget _buildOverviewTab(AsyncValue<TheftSummary?> summaryAsync) {
    return RefreshIndicator(
      onRefresh: () async {
        ref.read(theftDetectionNotifierProvider.notifier).refresh();
      },
      child: summaryAsync.when(
        data: (summary) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Summary Cards
              _buildSummarySection(summary),
              const SizedBox(height: 24),

              // Critical Anomalies
              _buildCriticalAnomaliesSection(),
              const SizedBox(height: 24),

              // High Risk Section
              _buildHighRiskSection(),
              const SizedBox(height: 24),

              // Quick Actions
              _buildQuickActionsSection(),
              const SizedBox(height: 100),
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Error: $e'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.refresh(activeTheftSummaryProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummarySection(TheftSummary? summary) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.red.shade400,
            Colors.red.shade600,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Detection Summary',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _currencyFormat.format(summary?.totalEstimatedLoss ?? 0),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Text(
            'Estimated Loss (This Period)',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _buildSummaryItem(
                'Active Anomalies',
                '${summary?.activeAnomalies ?? 0}',
                CupertinoIcons.exclamationmark_triangle,
              ),
              const SizedBox(width: 24),
              _buildSummaryItem(
                'Open Cases',
                '${summary?.openInvestigations ?? 0}',
                CupertinoIcons.doc_text_search,
              ),
              const SizedBox(width: 24),
              _buildSummaryItem(
                'Recovered',
                _currencyFormat.format(summary?.totalRecovered ?? 0),
                CupertinoIcons.arrow_counterclockwise,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, IconData icon) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white70, size: 14),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCriticalAnomaliesSection() {
    final criticalAsync = ref.watch(criticalAnomaliesProvider);
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Critical Anomalies',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextButton(
              onPressed: () {
                _tabController.animateTo(1);
              },
              child: const Text('See All'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        criticalAsync.when(
          data: (anomalies) {
            if (anomalies.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Column(
                    children: [
                      const Icon(
                        CupertinoIcons.checkmark_shield,
                        size: 48,
                        color: Colors.green,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'No Critical Anomalies',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        'All systems operating normally',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return Column(
              children: anomalies.take(3).map((anomaly) {
                return _buildAnomalyCard(anomaly);
              }).toList(),
            );
          },
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (e, _) => Center(child: Text('Error: $e')),
        ),
      ],
    );
  }

  Widget _buildHighRiskSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'High Risk Indicators',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildHighRiskEmployeesCard()),
            const SizedBox(width: 12),
            Expanded(child: _buildHighRiskProductsCard()),
          ],
        ),
      ],
    );
  }

  Widget _buildHighRiskEmployeesCard() {
    final cs = Theme.of(context).colorScheme;
    final employeesAsync = ref.watch(highRiskEmployeesProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  CupertinoIcons.person_2,
                  color: Colors.orange,
                  size: 20,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Employees',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          employeesAsync.when(
            data: (employees) {
              if (employees.isEmpty) {
                return Text(
                  'No high-risk employees',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 12,
                  ),
                );
              }

              return Column(
                children: employees.take(3).map((emp) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            emp.employeeName,
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${emp.anomalyCount}',
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
            loading: () => const SizedBox(
              height: 50,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (_, __) => Text(
              'Error loading',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHighRiskProductsCard() {
    final cs = Theme.of(context).colorScheme;
    final productsAsync = ref.watch(highRiskProductsProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  CupertinoIcons.cube_box,
                  color: Colors.purple,
                  size: 20,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Products',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          productsAsync.when(
            data: (products) {
              if (products.isEmpty) {
                return Text(
                  'No high-risk products',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 12,
                  ),
                );
              }

              return Column(
                children: products.take(3).map((prod) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            prod.productName,
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${prod.unitsAffected}',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
            loading: () => const SizedBox(
              height: 50,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (_, __) => Text(
              'Error loading',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildActionCard(
                'Run Detection',
                'Analyze recent transactions',
                CupertinoIcons.play_circle,
                Colors.blue,
                () => _runDetection(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionCard(
                'New Case',
                'Open investigation',
                CupertinoIcons.plus_circle,
                Colors.green,
                () => _createInvestigation(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionCard(
    String title,
    String subtitle,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // ANOMALIES TAB
  // ===========================================================================

  Widget _buildAnomaliesTab() {
    final anomaliesAsync = ref.watch(activeAnomaliesProvider);
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        // Filters
        _buildAnomalyFilters(),

        // Anomalies List
        Expanded(
          child: anomaliesAsync.when(
            data: (anomalies) {
              if (anomalies.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        CupertinoIcons.checkmark_shield,
                        size: 64,
                        color: Colors.green,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No Anomalies Detected',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'All transactions look normal',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(activeAnomaliesProvider);
                },
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: anomalies.length,
                  itemBuilder: (context, index) {
                    return _buildAnomalyCard(anomalies[index]);
                  },
                ),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
          ),
        ),
      ],
    );
  }

  Widget _buildAnomalyFilters() {
    final selectedType = ref.watch(theftTypeFilterProvider);
    final selectedSeverity = ref.watch(theftSeverityFilterProvider);
    final showAcknowledged = ref.watch(showAcknowledgedProvider);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // Type filter
          _buildFilterChip(
            label: selectedType?.displayName ?? 'All Types',
            isSelected: selectedType != null,
            onTap: () => _showTypeFilter(),
          ),
          const SizedBox(width: 8),

          // Severity filter
          _buildFilterChip(
            label: selectedSeverity?.displayName ?? 'All Severity',
            isSelected: selectedSeverity != null,
            onTap: () => _showSeverityFilter(),
          ),
          const SizedBox(width: 8),

          // Show acknowledged toggle
          _buildFilterChip(
            label: 'Show Resolved',
            isSelected: showAcknowledged,
            onTap: () {
              ref.read(showAcknowledgedProvider.notifier).state =
                  !showAcknowledged;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).primaryColor
              : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : null,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildAnomalyCard(Anomaly anomaly) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => _showAnomalyDetails(anomaly),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Color(anomaly.severity.colorValue).withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color:
                        Color(anomaly.severity.colorValue).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    anomaly.type.icon,
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        anomaly.type.displayName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      if (anomaly.shopName != null)
                        Text(
                          anomaly.shopName!,
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                _buildSeverityBadge(anomaly.severity),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              anomaly.description,
              style: const TextStyle(fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                // Z-Score
                _buildStatChip(
                  'Z-Score',
                  anomaly.zScore.toStringAsFixed(2),
                  Colors.blue,
                ),
                const SizedBox(width: 8),
                // Value
                _buildStatChip(
                  'Value',
                  _currencyFormat.format(anomaly.value),
                  Colors.orange,
                ),
                const Spacer(),
                Text(
                  _formatTimeAgo(anomaly.detectedAt),
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            if (!anomaly.isAcknowledged) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _dismissAnomaly(anomaly),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      child: const Text('Dismiss'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _acknowledgeAnomaly(anomaly),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      child: const Text(
                        'Investigate',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSeverityBadge(SeverityLevel severity) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Color(severity.colorValue).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        severity.displayName,
        style: TextStyle(
          color: Color(severity.colorValue),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildStatChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              color: color.withOpacity(0.7),
              fontSize: 11,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // INVESTIGATIONS TAB
  // ===========================================================================

  Widget _buildInvestigationsTab() {
    final investigationsAsync = ref.watch(activeInvestigationsProvider);
    final statusFilter = ref.watch(investigationStatusFilterProvider);

    return Column(
      children: [
        // Status filter
        _buildInvestigationFilters(statusFilter),

        // List
        Expanded(
          child: investigationsAsync.when(
            data: (investigations) {
              if (investigations.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        CupertinoIcons.doc_text_search,
                        size: 64,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No Investigations',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Create one from an anomaly',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(activeInvestigationsProvider);
                },
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: investigations.length,
                  itemBuilder: (context, index) {
                    return _buildInvestigationCard(investigations[index]);
                  },
                ),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
          ),
        ),
      ],
    );
  }

  Widget _buildInvestigationFilters(InvestigationStatus? selected) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _buildStatusFilterChip(null, selected),
          const SizedBox(width: 8),
          _buildStatusFilterChip(InvestigationStatus.open, selected),
          const SizedBox(width: 8),
          _buildStatusFilterChip(InvestigationStatus.inProgress, selected),
          const SizedBox(width: 8),
          _buildStatusFilterChip(InvestigationStatus.resolved, selected),
        ],
      ),
    );
  }

  Widget _buildStatusFilterChip(
    InvestigationStatus? status,
    InvestigationStatus? selected,
  ) {
    final isSelected = status == selected;
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () {
        ref.read(investigationStatusFilterProvider.notifier).state = status;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).primaryColor
              : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          status?.displayName ?? 'All',
          style: TextStyle(
            color: isSelected ? Colors.white : null,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildInvestigationCard(Investigation investigation) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => _showInvestigationDetails(investigation),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        investigation.caseNumber,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        investigation.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildInvestigationStatusBadge(investigation.status),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              investigation.description,
              style: const TextStyle(fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (investigation.assigneeName != null) ...[
                  Icon(CupertinoIcons.person, size: 14, color: cs.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    investigation.assigneeName!,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
                Icon(CupertinoIcons.money_dollar_circle,
                    size: 14, color: cs.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  _currencyFormat.format(investigation.estimatedLoss),
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                if (investigation.isOverdue)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Overdue',
                      style: TextStyle(
                        color: Colors.red,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInvestigationStatusBadge(InvestigationStatus status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Color(status.colorValue).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.displayName,
        style: TextStyle(
          color: Color(status.colorValue),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ===========================================================================
  // ACTIONS
  // ===========================================================================

  void _showAlerts() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AlertsSheet(),
    );
  }

  void _showSettings() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Detection settings coming soon')),
    );
  }

  void _runDetection() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Running detection analysis...')),
    );
    // TODO: Implement run detection
  }

  void _createInvestigation() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Create investigation coming soon')),
    );
    // TODO: Implement create investigation
  }

  void _showTypeFilter() {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Filter by Type'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              ref.read(theftTypeFilterProvider.notifier).state = null;
              Navigator.pop(context);
            },
            child: const Text('All Types'),
          ),
          ...AnomalyType.values.map((type) => CupertinoActionSheetAction(
                onPressed: () {
                  ref.read(theftTypeFilterProvider.notifier).state = type;
                  Navigator.pop(context);
                },
                child: Text('${type.icon} ${type.displayName}'),
              )),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _showSeverityFilter() {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Filter by Severity'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              ref.read(theftSeverityFilterProvider.notifier).state = null;
              Navigator.pop(context);
            },
            child: const Text('All Severity'),
          ),
          ...SeverityLevel.values.map((severity) => CupertinoActionSheetAction(
                onPressed: () {
                  ref.read(theftSeverityFilterProvider.notifier).state =
                      severity;
                  Navigator.pop(context);
                },
                child: Text(severity.displayName),
              )),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _showAnomalyDetails(Anomaly anomaly) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AnomalyDetailsSheet(anomaly: anomaly),
    );
  }

  void _showInvestigationDetails(Investigation investigation) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Case: ${investigation.caseNumber}')),
    );
    // TODO: Navigate to investigation details screen
  }

  Future<void> _acknowledgeAnomaly(Anomaly anomaly) async {
    final success = await ref
        .read(theftDetectionNotifierProvider.notifier)
        .acknowledgeAnomaly(anomaly.id);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(success ? 'Anomaly acknowledged' : 'Failed to acknowledge'),
        ),
      );
    }
  }

  Future<void> _dismissAnomaly(Anomaly anomaly) async {
    final result = await showCupertinoDialog<String>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Dismiss Anomaly'),
        content: Column(
          children: [
            const SizedBox(height: 8),
            const Text('Are you sure this is a false positive?'),
            const SizedBox(height: 16),
            CupertinoTextField(
              placeholder: 'Reason (optional)',
              onChanged: (value) {},
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, 'dismissed'),
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );

    if (result == 'dismissed') {
      final success = await ref
          .read(theftDetectionNotifierProvider.notifier)
          .dismissAnomaly(anomaly.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Anomaly dismissed' : 'Failed to dismiss'),
          ),
        );
      }
    }
  }

  String _formatTimeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return DateFormat('MMM d').format(dateTime);
    }
  }
}

// =============================================================================
// ALERTS SHEET
// =============================================================================

class _AlertsSheet extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final alertsAsync = ref.watch(unreadAlertsProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Alerts',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      ref
                          .read(theftDetectionNotifierProvider.notifier)
                          .markAllAlertsRead();
                    },
                    child: const Text('Mark All Read'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: alertsAsync.when(
                data: (alerts) {
                  if (alerts.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            CupertinoIcons.bell_slash,
                            size: 48,
                            color: cs.onSurfaceVariant,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'No Unread Alerts',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: alerts.length,
                    itemBuilder: (context, index) {
                      final alert = alerts[index];
                      return _buildAlertTile(context, ref, alert, cs);
                    },
                  );
                },
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertTile(
    BuildContext context,
    WidgetRef ref,
    TheftAlert alert,
    ColorScheme cs,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(
            color: Color(alert.priority.colorValue),
            width: 4,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            alert.anomalyType.icon,
            style: const TextStyle(fontSize: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  alert.message,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 12,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(CupertinoIcons.xmark, size: 16),
            onPressed: () {
              ref
                  .read(theftDetectionNotifierProvider.notifier)
                  .dismissAlert(alert.id);
            },
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// ANOMALY DETAILS SHEET
// =============================================================================

class _AnomalyDetailsSheet extends StatelessWidget {
  final Anomaly anomaly;

  const _AnomalyDetailsSheet({required this.anomaly});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 0);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Header
              Row(
                children: [
                  Text(
                    anomaly.type.icon,
                    style: const TextStyle(fontSize: 32),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          anomaly.type.displayName,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          anomaly.shopName ?? 'Unknown Shop',
                          style: TextStyle(color: cs.onSurfaceVariant),
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
                      color: Color(anomaly.severity.colorValue).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      anomaly.severity.displayName,
                      style: TextStyle(
                        color: Color(anomaly.severity.colorValue),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Description
              Text(
                anomaly.description,
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 24),

              // Stats
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _buildStatRow('Z-Score', anomaly.zScore.toStringAsFixed(3)),
                    const Divider(),
                    _buildStatRow('Actual Value',
                        currencyFormat.format(anomaly.value)),
                    const Divider(),
                    _buildStatRow('Expected Value',
                        currencyFormat.format(anomaly.expectedValue)),
                    const Divider(),
                    _buildStatRow('Variance',
                        '${anomaly.deviationPercent.toStringAsFixed(1)}%'),
                    const Divider(),
                    _buildStatRow(
                      'Detected',
                      DateFormat('MMM d, yyyy h:mm a').format(anomaly.detectedAt),
                    ),
                  ],
                ),
              ),

              if (anomaly.employeeName != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(CupertinoIcons.person, color: Colors.orange),
                      const SizedBox(width: 12),
                      Text(
                        'Employee: ${anomaly.employeeName}',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ],

              if (anomaly.productName != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(CupertinoIcons.cube_box, color: Colors.purple),
                      const SizedBox(width: 12),
                      Text(
                        'Product: ${anomaly.productName}',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Builder(
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              Text(
                value,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        );
      },
    );
  }
}
