import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../models/finance_matrix_models.dart';
import '../providers/finance_matrix_provider.dart';

/// Finance Matrix Screen - AI-Powered Unified Financial Dashboard
/// USP Feature: All-in-one view of Sales + Cash + Inventory + Expenses
class FinanceMatrixScreen extends ConsumerStatefulWidget {
  const FinanceMatrixScreen({super.key});

  @override
  ConsumerState<FinanceMatrixScreen> createState() => _FinanceMatrixScreenState();
}

class _FinanceMatrixScreenState extends ConsumerState<FinanceMatrixScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matrixAsync = ref.watch(activeFinanceMatrixProvider);
    final selectedPeriod = ref.watch(matrixPeriodProvider);

    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: CustomAppBar(
        title: 'Finance Matrix',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(financeMatrixNotifierProvider.notifier).refresh(),
          ),
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            onPressed: () => _showExportOptions(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // Period Selector
          _buildPeriodSelector(selectedPeriod),

          // Main Content
          Expanded(
            child: matrixAsync.when(
              data: (dashboard) => _buildDashboard(dashboard),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _buildErrorState(e.toString()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodSelector(MatrixPeriod selectedPeriod) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: MatrixPeriod.values
            .where((p) => p != MatrixPeriod.custom)
            .map((period) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(period.displayName),
                    selected: selectedPeriod == period,
                    onSelected: (selected) {
                      if (selected) {
                        ref.read(financeMatrixNotifierProvider.notifier).setPeriod(period);
                      }
                    },
                    selectedColor: cs.primary.withValues(alpha: 0.2),
                    labelStyle: TextStyle(
                      color: selectedPeriod == period
                          ? cs.primary
                          : cs.onSurfaceVariant,
                      fontWeight:
                          selectedPeriod == period ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildDashboard(FinanceMatrixDashboard dashboard) {
    return RefreshIndicator(
      onRefresh: () async {
        ref.read(financeMatrixNotifierProvider.notifier).refresh();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Health Score Card
            _buildHealthScoreCard(dashboard),
            const SizedBox(height: 16),

            // Quick Stats Grid
            _buildQuickStatsGrid(dashboard),
            const SizedBox(height: 16),

            // Insights Section
            if (dashboard.insights.isNotEmpty) ...[
              _buildInsightsSection(dashboard.insights),
              const SizedBox(height: 16),
            ],

            // Tab View for Details
            _buildDetailsTabs(dashboard),
          ],
        ),
      ),
    );
  }

  Widget _buildHealthScoreCard(FinanceMatrixDashboard dashboard) {
    final healthColor = Color(dashboard.healthColorValue);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: healthColor.withValues(alpha: 0.3)),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              healthColor.withValues(alpha: 0.1),
              healthColor.withValues(alpha: 0.05),
            ],
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            // Health Score Circle
            SizedBox(
              width: 80,
              height: 80,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: dashboard.healthScore / 100,
                    strokeWidth: 8,
                    backgroundColor: Theme.of(context).colorScheme.outlineVariant,
                    valueColor: AlwaysStoppedAnimation<Color>(healthColor),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        dashboard.healthScore.toStringAsFixed(0),
                        style: AppTextStyles.h4.copyWith(
                          color: healthColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '%',
                        style: AppTextStyles.caption.copyWith(color: healthColor),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            // Health Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Business Health',
                    style: AppTextStyles.h5.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    dashboard.healthStatus,
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: healthColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Based on sales, cash, inventory & expenses',
                    style: AppTextStyles.caption.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStatsGrid(FinanceMatrixDashboard dashboard) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.15,
      children: [
        _buildStatCard(
          'Sales',
          dashboard.sales.formattedTotal,
          Icons.trending_up,
          AppColors.success,
          '${dashboard.sales.transactionCount} transactions',
          dashboard.sales.growthPercent,
        ),
        _buildStatCard(
          'Cash Balance',
          '₹${_formatNumber(dashboard.cash.actualBalance)}',
          Icons.account_balance_wallet,
          dashboard.cash.hasVariance ? AppColors.warning : AppColors.primary,
          dashboard.cash.varianceStatus == 'balanced'
              ? 'Reconciled'
              : 'Variance: ${dashboard.cash.formattedVariance}',
          null,
        ),
        _buildStatCard(
          'Inventory',
          '${dashboard.inventory.totalItems} Items',
          Icons.inventory_2,
          dashboard.inventory.outOfStockCount > 0 ? AppColors.error : AppColors.info,
          dashboard.inventory.totalAlerts > 0
              ? '${dashboard.inventory.totalAlerts} alerts'
              : 'All stocked',
          null,
        ),
        _buildStatCard(
          'Expenses',
          dashboard.expenses.formattedTotal,
          Icons.receipt_long,
          dashboard.expenses.isOverBudget ? AppColors.error : AppColors.warning,
          dashboard.expenses.budgeted > 0
              ? '${dashboard.expenses.budgetUsedPercent.toStringAsFixed(0)}% of budget'
              : 'No budget set',
          dashboard.expenses.changePercent,
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
    String subtitle,
    double? changePercent,
  ) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const Spacer(),
                if (changePercent != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: (changePercent >= 0 ? AppColors.success : AppColors.error)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${changePercent >= 0 ? '+' : ''}${changePercent.toStringAsFixed(1)}%',
                      style: AppTextStyles.caption.copyWith(
                        color: changePercent >= 0 ? AppColors.success : AppColors.error,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
            const Spacer(),
            Text(
              title,
              style: AppTextStyles.caption.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: AppTextStyles.h5.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: AppTextStyles.caption.copyWith(color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInsightsSection(List<MatrixInsight> insights) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.lightbulb, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Text('AI Insights', style: AppTextStyles.h5),
            const Spacer(),
            Text(
              '${insights.length} insights',
              style: AppTextStyles.caption.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...insights.take(3).map((insight) => _buildInsightCard(insight)),
      ],
    );
  }

  Widget _buildInsightCard(MatrixInsight insight) {
    Color severityColor;
    IconData severityIcon;

    switch (insight.severity) {
      case 'critical':
        severityColor = AppColors.error;
        severityIcon = Icons.error;
        break;
      case 'warning':
        severityColor = AppColors.warning;
        severityIcon = Icons.warning;
        break;
      case 'success':
        severityColor = AppColors.success;
        severityIcon = Icons.check_circle;
        break;
      default:
        severityColor = AppColors.info;
        severityIcon = Icons.info;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: severityColor.withValues(alpha: 0.3)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: severityColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(severityIcon, color: severityColor),
        ),
        title: Text(
          insight.title,
          style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w500),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            insight.description,
            style: AppTextStyles.caption.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: insight.actionLabel != null
            ? TextButton(
                onPressed: () => _handleInsightAction(insight),
                child: Text(insight.actionLabel!),
              )
            : IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => _dismissInsight(insight),
              ),
      ),
    );
  }

  Widget _buildDetailsTabs(FinanceMatrixDashboard dashboard) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: AppColors.primary,
          unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'Sales'),
            Tab(text: 'Cash'),
            Tab(text: 'Inventory'),
            Tab(text: 'Expenses'),
          ],
        ),
        SizedBox(
          height: 300,
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildSalesDetails(dashboard.sales),
              _buildCashDetails(dashboard.cash),
              _buildInventoryDetails(dashboard.inventory),
              _buildExpensesDetails(dashboard.expenses),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSalesDetails(SalesSummary sales) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Target Progress
          if (sales.target > 0) ...[
            Text('Target Progress', style: AppTextStyles.bodyMedium),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: (sales.targetProgress / 100).clamp(0.0, 1.0),
              backgroundColor: Theme.of(context).colorScheme.outlineVariant,
              valueColor: AlwaysStoppedAnimation<Color>(
                sales.isAboveTarget ? AppColors.success : AppColors.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${sales.targetProgress.toStringAsFixed(1)}% of ₹${_formatNumber(sales.target)}',
              style: AppTextStyles.caption.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
          ],

          // Top Product
          if (sales.topProduct.isNotEmpty) ...[
            Card(
              elevation: 0,
              child: ListTile(
                leading: const Icon(Icons.star, color: AppColors.warning),
                title: const Text('Top Selling Product'),
                subtitle: Text('${sales.topProduct} (${sales.topProductCount} units)'),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Category Breakdown
          if (sales.categoryBreakdown.isNotEmpty) ...[
            Text('By Category', style: AppTextStyles.bodyMedium),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: sales.categoryBreakdown.length,
                itemBuilder: (context, index) {
                  final cat = sales.categoryBreakdown[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(cat.category),
                        ),
                        Expanded(
                          flex: 4,
                          child: LinearProgressIndicator(
                            value: cat.percentage / 100,
                            backgroundColor: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 80,
                          child: Text(
                            '₹${_formatNumber(cat.amount)}',
                            textAlign: TextAlign.end,
                            style: AppTextStyles.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCashDetails(CashSummary cash) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cash Flow Summary
          Row(
            children: [
              Expanded(
                child: _buildCashFlowCard(
                  'Opening',
                  cash.openingBalance,
                  Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildCashFlowCard(
                  'Received',
                  cash.totalReceived,
                  AppColors.success,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildCashFlowCard(
                  'Paid',
                  cash.totalPaid,
                  AppColors.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Variance Alert
          if (cash.hasVariance)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (cash.isShort ? AppColors.error : AppColors.success)
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: (cash.isShort ? AppColors.error : AppColors.success)
                      .withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    cash.isShort ? Icons.warning : Icons.info,
                    color: cash.isShort ? AppColors.error : AppColors.success,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Cash is ${cash.isShort ? "short" : "over"} by ${cash.formattedVariance}',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: cash.isShort ? AppColors.error : AppColors.success,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 16),

          // Recent Transactions
          if (cash.recentTransactions.isNotEmpty) ...[
            Text('Recent Transactions', style: AppTextStyles.bodyMedium),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: cash.recentTransactions.length,
                itemBuilder: (context, index) {
                  final tx = cash.recentTransactions[index];
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      tx.type == 'in' ? Icons.arrow_downward : Icons.arrow_upward,
                      color: tx.type == 'in' ? AppColors.success : AppColors.error,
                    ),
                    title: Text(tx.description),
                    trailing: Text(
                      '${tx.type == 'in' ? '+' : '-'}₹${_formatNumber(tx.amount)}',
                      style: TextStyle(
                        color: tx.type == 'in' ? AppColors.success : AppColors.error,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCashFlowCard(String label, double amount, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: AppTextStyles.caption.copyWith(color: color),
          ),
          const SizedBox(height: 4),
          Text(
            '₹${_formatNumber(amount)}',
            style: AppTextStyles.bodySmall.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInventoryDetails(InventorySummary inventory) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stock Status Summary
          Row(
            children: [
              Expanded(
                child: _buildStockStatusCard(
                  'In Stock',
                  inventory.totalItems - inventory.lowStockCount - inventory.outOfStockCount,
                  AppColors.success,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStockStatusCard(
                  'Low Stock',
                  inventory.lowStockCount,
                  AppColors.warning,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStockStatusCard(
                  'Out of Stock',
                  inventory.outOfStockCount,
                  AppColors.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Alerts
          if (inventory.alerts.isNotEmpty) ...[
            Text('Stock Alerts', style: AppTextStyles.bodyMedium),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: inventory.alerts.length,
                itemBuilder: (context, index) {
                  final alert = inventory.alerts[index];
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      alert.alertType == 'out_of_stock'
                          ? Icons.error
                          : Icons.warning,
                      color: alert.alertType == 'out_of_stock'
                          ? AppColors.error
                          : AppColors.warning,
                    ),
                    title: Text(alert.productName),
                    subtitle: Text(
                      alert.alertType == 'out_of_stock'
                          ? 'Out of stock'
                          : '${alert.currentStock}/${alert.minimumStock} remaining',
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStockStatusCard(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            count.toString(),
            style: AppTextStyles.h5.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTextStyles.caption.copyWith(color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildExpensesDetails(ExpensesSummary expenses) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Budget Progress
          if (expenses.budgeted > 0) ...[
            Text('Budget Usage', style: AppTextStyles.bodyMedium),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: (expenses.budgetUsedPercent / 100).clamp(0.0, 1.0),
              backgroundColor: Theme.of(context).colorScheme.outlineVariant,
              valueColor: AlwaysStoppedAnimation<Color>(
                expenses.isOverBudget ? AppColors.error : AppColors.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '₹${_formatNumber(expenses.totalSpent)} of ₹${_formatNumber(expenses.budgeted)} (₹${_formatNumber(expenses.remaining)} remaining)',
              style: AppTextStyles.caption.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
          ],

          // Categories
          if (expenses.categories.isNotEmpty) ...[
            Text('By Category', style: AppTextStyles.bodyMedium),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: expenses.categories.length,
                itemBuilder: (context, index) {
                  final cat = expenses.categories[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(cat.name),
                        ),
                        Expanded(
                          flex: 4,
                          child: LinearProgressIndicator(
                            value: cat.percentage / 100,
                            backgroundColor: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 80,
                          child: Text(
                            '₹${_formatNumber(cat.amount)}',
                            textAlign: TextAlign.end,
                            style: AppTextStyles.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: AppColors.error),
          const SizedBox(height: 16),
          Text('Failed to load dashboard', style: AppTextStyles.bodyMedium),
          const SizedBox(height: 8),
          Text(
            error,
            style: AppTextStyles.caption.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => ref.read(financeMatrixNotifierProvider.notifier).refresh(),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  void _handleInsightAction(MatrixInsight insight) {
    // Navigate based on action URL or type
    // For now, just show a snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Action: ${insight.actionLabel}')),
    );
  }

  void _dismissInsight(MatrixInsight insight) {
    ref.read(financeMatrixNotifierProvider.notifier).dismissInsight(insight.id);
  }

  void _showExportOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf),
              title: const Text('Export as PDF'),
              onTap: () {
                Navigator.pop(context);
                _exportReport('pdf');
              },
            ),
            ListTile(
              leading: const Icon(Icons.table_chart),
              title: const Text('Export as Excel'),
              onTap: () {
                Navigator.pop(context);
                _exportReport('excel');
              },
            ),
            ListTile(
              leading: const Icon(Icons.text_snippet),
              title: const Text('Export as CSV'),
              onTap: () {
                Navigator.pop(context);
                _exportReport('csv');
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportReport(String format) async {
    final query = ref.read(matrixQueryProvider);
    final url = await ref.read(financeMatrixNotifierProvider.notifier).exportReport(
          query: query,
          format: format,
        );

    if (mounted) {
      if (url != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report exported successfully'),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to export report'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  String _formatNumber(double value) {
    if (value >= 10000000) {
      return '${(value / 10000000).toStringAsFixed(2)}Cr';
    } else if (value >= 100000) {
      return '${(value / 100000).toStringAsFixed(2)}L';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    }
    return value.toStringAsFixed(0);
  }
}
