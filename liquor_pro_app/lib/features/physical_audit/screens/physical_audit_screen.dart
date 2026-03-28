import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/physical_audit_models.dart';
import '../providers/physical_audit_provider.dart';
import 'cash_audit_screen.dart';
import 'inventory_audit_screen.dart';
import 'audit_history_screen.dart';

/// Physical Audit Screen - Main dashboard for audits
class PhysicalAuditScreen extends ConsumerStatefulWidget {
  const PhysicalAuditScreen({super.key});

  @override
  ConsumerState<PhysicalAuditScreen> createState() => _PhysicalAuditScreenState();
}

class _PhysicalAuditScreenState extends ConsumerState<PhysicalAuditScreen>
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
    final pendingAudits = ref.watch(activePendingAuditsProvider);
    final activeAudit = ref.watch(activeAuditNotifierProvider);

    return Scaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      appBar: AppBar(
        title: const Text('Physical Audit'),
        backgroundColor: CupertinoColors.systemBackground,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.clock),
            onPressed: () => _showScheduleSheet(context),
            tooltip: 'Audit Schedules',
          ),
          IconButton(
            icon: const Icon(CupertinoIcons.doc_text),
            onPressed: () => Navigator.push(
              context,
              CupertinoPageRoute(
                builder: (context) => const AuditHistoryScreen(),
              ),
            ),
            tooltip: 'Audit History',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: CupertinoColors.activeBlue,
          unselectedLabelColor: CupertinoColors.systemGrey,
          indicatorColor: CupertinoColors.activeBlue,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Cash'),
            Tab(text: 'Inventory'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOverviewTab(pendingAudits, activeAudit),
          const CashAuditScreen(),
          const InventoryAuditScreen(),
        ],
      ),
      floatingActionButton: activeAudit.hasSession
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showStartAuditSheet(context),
              icon: const Icon(CupertinoIcons.add),
              label: const Text('Start Audit'),
              backgroundColor: CupertinoColors.activeBlue,
            ),
    );
  }

  Widget _buildOverviewTab(
    AsyncValue<List<AuditSchedule>> pendingAudits,
    ActiveAuditState activeAudit,
  ) {
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(activePendingAuditsProvider);
        ref.invalidate(activeAuditSessionsProvider);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Active Audit Banner
          if (activeAudit.hasSession) _buildActiveAuditBanner(activeAudit),

          // Pending Audits Section
          _buildSectionHeader('Pending Audits'),
          const SizedBox(height: 12),
          pendingAudits.when(
            data: (audits) => audits.isEmpty
                ? _buildEmptyState(
                    icon: CupertinoIcons.checkmark_seal,
                    title: 'All caught up!',
                    subtitle: 'No pending audits at this time',
                  )
                : Column(
                    children: audits.map((a) => _buildPendingAuditCard(a)).toList(),
                  ),
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: CupertinoActivityIndicator(),
              ),
            ),
            error: (e, _) => _buildErrorState(e.toString()),
          ),

          const SizedBox(height: 24),

          // Quick Actions
          _buildSectionHeader('Quick Actions'),
          const SizedBox(height: 12),
          _buildQuickActionsGrid(),

          const SizedBox(height: 24),

          // Recent Audits
          _buildSectionHeader('Recent Audits'),
          const SizedBox(height: 12),
          _buildRecentAuditsSection(),
        ],
      ),
    );
  }

  Widget _buildActiveAuditBanner(ActiveAuditState state) {
    final session = state.session!;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3B82F6).withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  CupertinoIcons.doc_text_search,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Audit In Progress',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      session.type.displayName,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (state.isSubmitting)
                const CupertinoActivityIndicator(color: Colors.white),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    if (session.type == AuditType.cash ||
                        session.type == AuditType.combined) {
                      _tabController.animateTo(1);
                    } else {
                      _tabController.animateTo(2);
                    }
                  },
                  icon: const Icon(CupertinoIcons.arrow_right,
                      color: Colors.white, size: 18),
                  label: const Text('Continue',
                      style: TextStyle(color: Colors.white)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: () => _showCancelAuditDialog(context),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.white70)),
              ),
            ],
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
        color: CupertinoColors.label,
      ),
    );
  }

  Widget _buildPendingAuditCard(AuditSchedule schedule) {
    final isOverdue = schedule.isOverdue;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground,
        borderRadius: BorderRadius.circular(12),
        border: isOverdue
            ? Border.all(color: CupertinoColors.systemRed.withValues(alpha: 0.5))
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _startAuditFromSchedule(schedule),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: schedule.type == AuditType.cash
                        ? const Color(0xFF10B981).withOpacity(0.1)
                        : schedule.type == AuditType.inventory
                            ? const Color(0xFF3B82F6).withOpacity(0.1)
                            : const Color(0xFF8B5CF6).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    schedule.type == AuditType.cash
                        ? CupertinoIcons.money_dollar
                        : schedule.type == AuditType.inventory
                            ? CupertinoIcons.cube_box
                            : CupertinoIcons.doc_text,
                    color: schedule.type == AuditType.cash
                        ? const Color(0xFF10B981)
                        : schedule.type == AuditType.inventory
                            ? const Color(0xFF3B82F6)
                            : const Color(0xFF8B5CF6),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        schedule.type.displayName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        schedule.shopName,
                        style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.secondaryLabel.resolveFrom(context),
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (isOverdue)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: CupertinoColors.systemRed.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'OVERDUE',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: CupertinoColors.systemRed,
                          ),
                        ),
                      )
                    else
                      Text(
                        schedule.formattedNextAudit,
                        style: TextStyle(
                          fontSize: 12,
                          color: CupertinoColors.secondaryLabel.resolveFrom(context),
                        ),
                      ),
                    const SizedBox(height: 4),
                    const Icon(
                      CupertinoIcons.chevron_right,
                      size: 16,
                      color: CupertinoColors.systemGrey,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActionsGrid() {
    return Row(
      children: [
        Expanded(
          child: _buildQuickActionCard(
            icon: CupertinoIcons.money_dollar,
            title: 'Cash Audit',
            color: const Color(0xFF10B981),
            onTap: () => _startQuickAudit(AuditType.cash),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildQuickActionCard(
            icon: CupertinoIcons.cube_box,
            title: 'Inventory',
            color: const Color(0xFF3B82F6),
            onTap: () => _startQuickAudit(AuditType.inventory),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildQuickActionCard(
            icon: CupertinoIcons.doc_text,
            title: 'Combined',
            color: const Color(0xFF8B5CF6),
            onTap: () => _startQuickAudit(AuditType.combined),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActionCard({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecentAuditsSection() {
    final sessions = ref.watch(activeAuditSessionsProvider);
    return sessions.when(
      data: (list) {
        if (list.isEmpty) {
          return _buildEmptyState(
            icon: CupertinoIcons.doc_text,
            title: 'No recent audits',
            subtitle: 'Start your first audit to see history here',
          );
        }
        return Column(
          children: list.take(5).map((s) => _buildAuditSessionCard(s)).toList(),
        );
      },
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CupertinoActivityIndicator(),
        ),
      ),
      error: (e, _) => _buildErrorState(e.toString()),
    );
  }

  Widget _buildAuditSessionCard(AuditSession session) {
    final dateFormat = DateFormat('MMM d, y h:mm a');
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showAuditDetails(session),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Color(session.statusColorValue),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            session.type.displayName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Color(session.statusColorValue)
                                  .withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              session.status.displayName,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: Color(session.statusColorValue),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dateFormat.format(session.startedAt ?? session.scheduledAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: CupertinoColors.secondaryLabel.resolveFrom(context),
                        ),
                      ),
                    ],
                  ),
                ),
                if (session.hasVariance)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: session.totalVariance < 0
                          ? CupertinoColors.systemRed.withValues(alpha: 0.1)
                          : CupertinoColors.systemOrange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      session.totalVariance < 0
                          ? '-₹${session.totalVariance.abs().toStringAsFixed(0)}'
                          : '+₹${session.totalVariance.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: session.totalVariance < 0
                            ? CupertinoColors.systemRed
                            : CupertinoColors.systemOrange,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                const Icon(
                  CupertinoIcons.chevron_right,
                  size: 16,
                  color: CupertinoColors.systemGrey,
                ),
              ],
            ),
          ),
        ),
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
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Container(
      padding: const EdgeInsets.all(20),
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
              style: const TextStyle(
                color: CupertinoColors.systemRed,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showStartAuditSheet(BuildContext context) {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => Container(
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
                'Start New Audit',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'Select the type of audit you want to perform',
                style: TextStyle(
                  fontSize: 14,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
              ),
              const SizedBox(height: 24),
              _buildAuditTypeOption(
                icon: CupertinoIcons.money_dollar,
                title: 'Cash Audit',
                subtitle: 'Count cash with denomination breakdown',
                color: const Color(0xFF10B981),
                onTap: () {
                  Navigator.pop(context);
                  _startQuickAudit(AuditType.cash);
                },
              ),
              const SizedBox(height: 12),
              _buildAuditTypeOption(
                icon: CupertinoIcons.cube_box,
                title: 'Inventory Audit',
                subtitle: 'Verify physical stock quantities',
                color: const Color(0xFF3B82F6),
                onTap: () {
                  Navigator.pop(context);
                  _startQuickAudit(AuditType.inventory);
                },
              ),
              const SizedBox(height: 12),
              _buildAuditTypeOption(
                icon: CupertinoIcons.doc_text,
                title: 'Combined Audit',
                subtitle: 'Complete cash and inventory audit',
                color: const Color(0xFF8B5CF6),
                onTap: () {
                  Navigator.pop(context);
                  _startQuickAudit(AuditType.combined);
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAuditTypeOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.secondaryLabel.resolveFrom(context),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  CupertinoIcons.chevron_right,
                  size: 18,
                  color: CupertinoColors.systemGrey,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showScheduleSheet(BuildContext context) {
    final schedules = ref.read(activeSchedulesProvider);
    showCupertinoModalPopup(
      context: context,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: CupertinoColors.systemBackground,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Audit Schedules',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  child: const Icon(CupertinoIcons.add_circled),
                  onPressed: () {
                    Navigator.pop(context);
                    _showCreateScheduleSheet(context);
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: schedules.when(
                data: (list) => list.isEmpty
                    ? Center(
                        child: _buildEmptyState(
                          icon: CupertinoIcons.calendar,
                          title: 'No schedules',
                          subtitle: 'Create a schedule to automate audits',
                        ),
                      )
                    : ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (context, index) =>
                            _buildScheduleListItem(list[index]),
                      ),
                loading: () =>
                    const Center(child: CupertinoActivityIndicator()),
                error: (e, _) => Center(child: _buildErrorState(e.toString())),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleListItem(AuditSchedule schedule) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            schedule.type == AuditType.cash
                ? CupertinoIcons.money_dollar
                : schedule.type == AuditType.inventory
                    ? CupertinoIcons.cube_box
                    : CupertinoIcons.doc_text,
            color: CupertinoColors.activeBlue,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  schedule.type.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  '${schedule.frequency.displayName} at ${schedule.timeOfDay}',
                  style: TextStyle(
                    fontSize: 12,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: schedule.isActive,
            onChanged: (value) {
              ref.read(auditScheduleNotifierProvider.notifier).updateSchedule(
                schedule.id,
                {'is_active': value},
              );
            },
          ),
        ],
      ),
    );
  }

  void _showCreateScheduleSheet(BuildContext context) {
    // Simplified schedule creation - in production, add proper form
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Schedule creation form - Coming soon')),
    );
  }

  void _startQuickAudit(AuditType type) async {
    // Get current shop - in production, show shop selector if multiple shops
    final shopId = ref.read(auditShopIdProvider);
    if (shopId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a shop first')),
      );
      return;
    }

    final request = StartAuditRequest(
      shopId: shopId,
      type: type,
    );

    final success =
        await ref.read(activeAuditNotifierProvider.notifier).startAudit(request);

    if (success) {
      if (type == AuditType.cash || type == AuditType.combined) {
        _tabController.animateTo(1);
      } else {
        _tabController.animateTo(2);
      }
    } else {
      final error = ref.read(activeAuditNotifierProvider).error;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error ?? 'Failed to start audit')),
        );
      }
    }
  }

  void _startAuditFromSchedule(AuditSchedule schedule) async {
    final request = StartAuditRequest(
      shopId: schedule.shopId,
      type: schedule.type,
      scheduleId: schedule.id,
    );

    final success =
        await ref.read(activeAuditNotifierProvider.notifier).startAudit(request);

    if (success) {
      if (schedule.type == AuditType.cash || schedule.type == AuditType.combined) {
        _tabController.animateTo(1);
      } else {
        _tabController.animateTo(2);
      }
    }
  }

  void _showCancelAuditDialog(BuildContext context) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Cancel Audit?'),
        content: const Text(
          'Are you sure you want to cancel this audit? All progress will be lost.',
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Keep Auditing'),
            onPressed: () => Navigator.pop(context),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.pop(context);
              await ref
                  .read(activeAuditNotifierProvider.notifier)
                  .cancelAudit('User cancelled');
            },
            child: const Text('Cancel Audit'),
          ),
        ],
      ),
    );
  }

  void _showAuditDetails(AuditSession session) {
    // Navigate to detailed audit view
    showCupertinoModalPopup(
      context: context,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: CupertinoColors.systemBackground,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
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
            Text(
              '${session.type.displayName} Audit',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              session.startedAt != null
                  ? DateFormat('MMMM d, y at h:mm a').format(session.startedAt!)
                  : 'Date not available',
              style: TextStyle(
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
            const SizedBox(height: 24),
            // Add audit details here
            if (session.cashData != null) ...[
              _buildDetailRow('Expected Cash', '₹${session.cashData!.expectedAmount.toStringAsFixed(0)}'),
              _buildDetailRow('Actual Cash', '₹${session.cashData!.actualAmount.toStringAsFixed(0)}'),
              _buildDetailRow(
                'Variance',
                session.cashData!.variance < 0
                    ? '-₹${session.cashData!.variance.abs().toStringAsFixed(0)}'
                    : '+₹${session.cashData!.variance.toStringAsFixed(0)}',
                valueColor: session.cashData!.variance < 0
                    ? CupertinoColors.systemRed
                    : session.cashData!.variance > 0
                        ? CupertinoColors.systemOrange
                        : CupertinoColors.systemGreen,
              ),
            ],
            if (session.inventoryData != null) ...[
              const SizedBox(height: 16),
              _buildDetailRow('Items Checked', '${session.inventoryData!.itemsChecked}'),
              _buildDetailRow('Items with Variance', '${session.inventoryData!.itemsWithVariance}'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
