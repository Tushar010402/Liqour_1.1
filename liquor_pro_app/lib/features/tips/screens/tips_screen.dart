import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/tips_models.dart';
import '../providers/tips_provider.dart';

/// Tips Management Screen
class TipsScreen extends ConsumerStatefulWidget {
  const TipsScreen({super.key});

  @override
  ConsumerState<TipsScreen> createState() => _TipsScreenState();
}

class _TipsScreenState extends ConsumerState<TipsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

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
    final summary = ref.watch(activeTipsSummaryProvider);

    return Scaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      appBar: AppBar(
        title: const Text('Tips Management'),
        backgroundColor: CupertinoColors.systemBackground,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.gear),
            onPressed: () => _showSettingsSheet(context),
            tooltip: 'Settings',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: CupertinoColors.activeBlue,
          unselectedLabelColor: CupertinoColors.systemGrey,
          indicatorColor: CupertinoColors.activeBlue,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Pools'),
            Tab(text: 'Payouts'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOverviewTab(summary),
          _buildPoolsTab(),
          _buildPayoutsTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddTipSheet(context),
        icon: const Icon(CupertinoIcons.add),
        label: const Text('Add Tip'),
        backgroundColor: CupertinoColors.activeBlue,
      ),
    );
  }

  // ===========================================================================
  // OVERVIEW TAB
  // ===========================================================================

  Widget _buildOverviewTab(AsyncValue<TipsSummary?> summaryAsync) {
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(activeTipsSummaryProvider);
        ref.invalidate(activeTipsProvider);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Summary Card
          summaryAsync.when(
            data: (summary) => summary != null
                ? _buildSummaryCard(summary)
                : _buildNoShopSelected(),
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: CupertinoActivityIndicator(),
              ),
            ),
            error: (e, _) => _buildErrorCard(e.toString()),
          ),

          const SizedBox(height: 24),

          // Recent Tips
          _buildSectionHeader('Recent Tips'),
          const SizedBox(height: 12),
          _buildRecentTips(),

          const SizedBox(height: 24),

          // By Employee
          if (summaryAsync.value != null &&
              summaryAsync.value!.byEmployee.isNotEmpty) ...[
            _buildSectionHeader('By Employee'),
            const SizedBox(height: 12),
            _buildEmployeeBreakdown(summaryAsync.value!.byEmployee),
          ],

          const SizedBox(height: 80), // Space for FAB
        ],
      ),
    );
  }

  Widget _buildSummaryCard(TipsSummary summary) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B5CF6).withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            '₹${summary.totalTips.toStringAsFixed(0)}',
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Total Tips This Period',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildMiniStat(
                  'Pooled',
                  '₹${summary.pooledTips.toStringAsFixed(0)}',
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: Colors.white.withOpacity(0.3),
              ),
              Expanded(
                child: _buildMiniStat(
                  'Individual',
                  '₹${summary.individualTips.toStringAsFixed(0)}',
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: Colors.white.withOpacity(0.3),
              ),
              Expanded(
                child: _buildMiniStat(
                  'Entries',
                  '${summary.totalEntries}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  CupertinoIcons.clock,
                  size: 16,
                  color: Colors.white,
                ),
                const SizedBox(width: 8),
                Text(
                  'Pending: ₹${summary.pendingPayouts.toStringAsFixed(0)} | Paid: ₹${summary.paidPayouts.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withOpacity(0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildNoShopSelected() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Icon(
            CupertinoIcons.building_2_fill,
            size: 48,
            color: CupertinoColors.systemGrey,
          ),
          const SizedBox(height: 16),
          const Text(
            'Select a Shop',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Choose a shop to view tip statistics',
            style: TextStyle(
              fontSize: 13,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(String error) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CupertinoColors.systemRed.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(CupertinoIcons.exclamationmark_triangle,
              color: CupertinoColors.systemRed),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              error,
              style: const TextStyle(color: CupertinoColors.systemRed),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildRecentTips() {
    final tipsAsync = ref.watch(activeTipsProvider);

    return tipsAsync.when(
      data: (tips) {
        if (tips.isEmpty) {
          return _buildEmptyState(
            icon: CupertinoIcons.money_dollar,
            title: 'No tips yet',
            subtitle: 'Add a tip to get started',
          );
        }

        return Column(
          children: tips.take(5).map((t) => _buildTipCard(t)).toList(),
        );
      },
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CupertinoActivityIndicator(),
        ),
      ),
      error: (e, _) => _buildErrorCard(e.toString()),
    );
  }

  Widget _buildTipCard(TipEntry tip) {
    final dateFormat = DateFormat('MMM d, h:mm a');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: tip.isPooled
                ? const Color(0xFF8B5CF6).withOpacity(0.1)
                : const Color(0xFF10B981).withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            tip.isPooled
                ? CupertinoIcons.person_3_fill
                : CupertinoIcons.person_fill,
            color: tip.isPooled
                ? const Color(0xFF8B5CF6)
                : const Color(0xFF10B981),
            size: 20,
          ),
        ),
        title: Text(
          '₹${tip.amount.toStringAsFixed(0)}',
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        subtitle: Text(
          tip.employeeName ?? dateFormat.format(tip.createdAt),
          style: TextStyle(
            fontSize: 12,
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: tip.isPooled
                ? const Color(0xFF8B5CF6).withOpacity(0.1)
                : const Color(0xFF10B981).withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            tip.isPooled ? 'Pooled' : 'Individual',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: tip.isPooled
                  ? const Color(0xFF8B5CF6)
                  : const Color(0xFF10B981),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmployeeBreakdown(List<EmployeeTipSummary> employees) {
    return Column(
      children: employees.map((e) => _buildEmployeeRow(e)).toList(),
    );
  }

  Widget _buildEmployeeRow(EmployeeTipSummary employee) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground,
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
          CircleAvatar(
            backgroundColor: const Color(0xFF3B82F6).withOpacity(0.1),
            radius: 20,
            child: Text(
              employee.employeeName.isNotEmpty
                  ? employee.employeeName[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                color: Color(0xFF3B82F6),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  employee.employeeName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${employee.tipCount} tips',
                  style: TextStyle(
                    fontSize: 12,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
              ],
            ),
          ),
          Text(
            '₹${employee.totalEarned.toStringAsFixed(0)}',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF10B981),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, size: 48, color: CupertinoColors.systemGrey),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // POOLS TAB
  // ===========================================================================

  Widget _buildPoolsTab() {
    final shopId = ref.watch(tipsShopIdProvider);
    final poolsAsync = ref.watch(activePoolsProvider(shopId));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Active Pools
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionHeader('Active Pools'),
            CupertinoButton(
              padding: EdgeInsets.zero,
              child: const Text('+ Create Pool'),
              onPressed: () => _showCreatePoolSheet(context),
            ),
          ],
        ),
        const SizedBox(height: 12),
        poolsAsync.when(
          data: (pools) {
            if (pools.isEmpty) {
              return _buildEmptyState(
                icon: CupertinoIcons.person_3_fill,
                title: 'No active pools',
                subtitle: 'Create a pool to start pooling tips',
              );
            }
            return Column(
              children: pools.map((p) => _buildPoolCard(p)).toList(),
            );
          },
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: CupertinoActivityIndicator(),
            ),
          ),
          error: (e, _) => _buildErrorCard(e.toString()),
        ),

        const SizedBox(height: 80), // Space for FAB
      ],
    );
  }

  Widget _buildPoolCard(TipPool pool) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground,
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
        children: [
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                CupertinoIcons.person_3_fill,
                color: Color(0xFF8B5CF6),
                size: 20,
              ),
            ),
            title: Text(
              pool.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${pool.distributionMethod.displayName} - ${pool.employees.length} employees',
              style: TextStyle(
                fontSize: 12,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
            trailing: Text(
              '₹${pool.totalAmount.toStringAsFixed(0)}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF8B5CF6),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _showDistributionPreview(pool),
                    child: const Text('Preview'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _closePool(pool),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8B5CF6),
                    ),
                    child: const Text('Close Pool',
                        style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // PAYOUTS TAB
  // ===========================================================================

  Widget _buildPayoutsTab() {
    final shopId = ref.watch(tipsShopIdProvider);
    final payoutsAsync = ref.watch(payoutsProvider(shopId));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionHeader('Payouts'),
            CupertinoButton(
              padding: EdgeInsets.zero,
              child: const Text('+ Create Payout'),
              onPressed: () => _showCreatePayoutSheet(context),
            ),
          ],
        ),
        const SizedBox(height: 12),
        payoutsAsync.when(
          data: (payouts) {
            if (payouts.isEmpty) {
              return _buildEmptyState(
                icon: CupertinoIcons.creditcard,
                title: 'No payouts yet',
                subtitle: 'Create a payout batch to distribute tips',
              );
            }
            return Column(
              children: payouts.map((p) => _buildPayoutCard(p)).toList(),
            );
          },
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: CupertinoActivityIndicator(),
            ),
          ),
          error: (e, _) => _buildErrorCard(e.toString()),
        ),

        const SizedBox(height: 80), // Space for FAB
      ],
    );
  }

  Widget _buildPayoutCard(TipPayout payout) {
    final dateFormat = DateFormat('MMM d, y');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground,
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
        children: [
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Color(payout.statusColorValue).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                CupertinoIcons.creditcard,
                color: Color(payout.statusColorValue),
                size: 20,
              ),
            ),
            title: Row(
              children: [
                Text(
                  '₹${payout.totalAmount.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Color(payout.statusColorValue).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    payout.status.displayName,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(payout.statusColorValue),
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Text(
              '${payout.employeeCount} employees - ${dateFormat.format(payout.periodStart)} to ${dateFormat.format(payout.periodEnd)}',
              style: TextStyle(
                fontSize: 12,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
          ),
          if (payout.canApprove || payout.canMarkPaid)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  if (payout.canCancel)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _cancelPayout(payout),
                        child: const Text('Cancel'),
                      ),
                    ),
                  if (payout.canCancel) const SizedBox(width: 12),
                  if (payout.canApprove)
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _approvePayout(payout),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: CupertinoColors.activeBlue,
                        ),
                        child: const Text('Approve',
                            style: TextStyle(color: Colors.white)),
                      ),
                    ),
                  if (payout.canMarkPaid)
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _markPaid(payout),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                        ),
                        child: const Text('Mark Paid',
                            style: TextStyle(color: Colors.white)),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ===========================================================================
  // ACTIONS
  // ===========================================================================

  void _showAddTipSheet(BuildContext context) {
    final amountController = TextEditingController();
    bool addToPool = true;

    showCupertinoModalPopup(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: CupertinoColors.systemBackground,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: CupertinoColors.systemGrey4,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Add Tip',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 20),
                CupertinoTextField(
                  controller: amountController,
                  placeholder: 'Amount',
                  keyboardType: TextInputType.number,
                  prefix: const Padding(
                    padding: EdgeInsets.only(left: 12),
                    child: Text('₹'),
                  ),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Add to Pool'),
                    CupertinoSwitch(
                      value: addToPool,
                      onChanged: (v) => setSheetState(() => addToPool = v),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      final amount = double.tryParse(amountController.text);
                      if (amount != null && amount > 0) {
                        Navigator.pop(context);
                        _createTip(amount, addToPool);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: CupertinoColors.activeBlue,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Add Tip',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _createTip(double amount, bool addToPool) async {
    final shopId = ref.read(tipsShopIdProvider);
    if (shopId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a shop')),
      );
      return;
    }

    final request = CreateTipRequest(
      shopId: shopId,
      amount: amount,
      addToPool: addToPool,
    );

    final tip = await ref.read(tipsNotifierProvider.notifier).createTip(request);
    if (tip != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Tip of ₹${amount.toStringAsFixed(0)} added!'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    }
  }

  void _showCreatePoolSheet(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Create Pool - Coming soon')),
    );
  }

  void _showCreatePayoutSheet(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Create Payout - Coming soon')),
    );
  }

  void _showSettingsSheet(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings - Coming soon')),
    );
  }

  void _showDistributionPreview(TipPool pool) {
    final previewAsync = ref.read(distributionPreviewProvider(pool.id));
    // Show preview modal
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Preview for ${pool.name}')),
    );
  }

  void _closePool(TipPool pool) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Close Pool?'),
        content: Text(
          'This will finalize the pool "${pool.name}" and prepare tips for distribution.',
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context, false),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Close Pool'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success =
          await ref.read(tipsNotifierProvider.notifier).closePool(pool.id);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pool closed successfully!'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    }
  }

  void _approvePayout(TipPayout payout) async {
    final success =
        await ref.read(tipsNotifierProvider.notifier).approvePayout(payout.id);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payout approved!'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    }
  }

  void _markPaid(TipPayout payout) async {
    final success =
        await ref.read(tipsNotifierProvider.notifier).markPaid(payout.id);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payout marked as paid!'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    }
  }

  void _cancelPayout(TipPayout payout) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Cancel Payout?'),
        content: const Text('This will cancel the pending payout.'),
        actions: [
          CupertinoDialogAction(
            child: const Text('Keep'),
            onPressed: () => Navigator.pop(context, false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel Payout'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await ref
          .read(tipsNotifierProvider.notifier)
          .cancelPayout(payout.id, 'User cancelled');
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payout cancelled')),
        );
      }
    }
  }
}
