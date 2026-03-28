import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as provider;
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/theme/ios_design_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../../../core/widgets/sale_details_modal.dart';
import '../../sales/services/daily_sales_service.dart';
import '../../../core/services/auth_service.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../providers/cash_provider.dart';
import '../models/cash_models.dart';
import 'cash_history_screen.dart';
import 'approvals_screen.dart';
import 'cash_requests_screen.dart';
import 'unified_bank_submissions_screen.dart';
import '../services/cash_service.dart';
import '../../../core/services/dio_api_service.dart';
import '../widgets/bulk_reset_sheet.dart';

/// Cash Dashboard - Settings-style layout with uniform icon treatment
class CashDashboardScreen extends ConsumerStatefulWidget {
  final String shopId;
  final String userRole;

  const CashDashboardScreen({
    super.key,
    required this.shopId,
    required this.userRole,
  });

  @override
  ConsumerState<CashDashboardScreen> createState() =>
      _CashDashboardScreenState();
}

class _CashDashboardScreenState extends ConsumerState<CashDashboardScreen>
    with WidgetsBindingObserver {
  bool _showTeamView = false;
  bool _isInitialLoad = true;
  String? _currentUserId;

  bool get _canCollectCash => [
        'executive',
        'assistant_manager',
        'manager',
        'admin',
      ].contains(widget.userRole);

  bool get _canApprove =>
      ['manager', 'admin', 'owner'].contains(widget.userRole.toLowerCase());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isInitialLoad = false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_currentUserId == null) _loadCurrentUserId();
    if (!_isInitialLoad && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refreshData();
      });
    }
  }

  Future<void> _loadCurrentUserId() async {
    final authService =
        provider.Provider.of<AuthService>(context, listen: false);
    final userId = await authService.getUserId();
    if (mounted && _currentUserId == null) {
      setState(() => _currentUserId = userId);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) _refreshData();
  }

  void _refreshData() {
    ref.invalidate(cashBalanceProvider);
    ref.invalidate(teamBalancesProvider);
    ref.invalidate(cashHistoryProvider);
    ref.invalidate(pendingSubmissionsProvider);
    ref.invalidate(submissionsProvider);
    if (_canApprove) {
      ref.invalidate(pendingCollectionsProvider);
      ref.invalidate(pendingCashRequestsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: CustomAppBar(
        title: 'Cash Management',
        actions: [
          if (_canApprove) _buildApprovalButton(),
          IconButton(
            icon: const Icon(Icons.history_outlined, color: Colors.white),
            tooltip: 'History',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CashHistoryScreen(shopId: widget.shopId),
                ),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(cashBalanceProvider);
          ref.invalidate(teamBalancesProvider);
          ref.invalidate(cashHistoryProvider);
        },
        color: cs.primary,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(iOSDesignTokens.space16),
          children: [
            // ── Balance Card ─────────────────────────────────────
            _buildBalanceSection(),
            SizedBox(height: iOSDesignTokens.space20),

            // ── Quick Actions ────────────────────────────────────
            _buildSectionHeader('Quick Actions'),
            SizedBox(height: iOSDesignTokens.space8),
            _buildSettingTile(
              icon: Icons.send_outlined,
              title: 'Cash Requests',
              subtitle: 'Request & track cash from team',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        CashRequestsScreen(shopId: widget.shopId),
                  ),
                );
              },
            ),
            _buildSettingTile(
              icon: Icons.account_balance_outlined,
              title: 'Bank Submissions',
              subtitle: 'Submit cash to bank & view history',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        UnifiedBankSubmissionsScreen(shopId: widget.shopId),
                  ),
                );
              },
            ),
            if (_canApprove)
              _buildSettingTile(
                icon: Icons.check_circle_outlined,
                title: 'Approvals',
                subtitle: 'Review pending cash & deposit requests',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ApprovalsScreen(shopId: widget.shopId),
                    ),
                  );
                },
              ),
            _buildSettingTile(
              icon: Icons.history_outlined,
              title: 'Cash History',
              subtitle: 'Full transaction history & audit trail',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        CashHistoryScreen(shopId: widget.shopId),
                  ),
                );
              },
            ),

            // ── Toggle + Content ─────────────────────────────────
            if (_canCollectCash) ...[
              SizedBox(height: iOSDesignTokens.space20),
              _buildSectionHeader('Overview'),
              SizedBox(height: iOSDesignTokens.space8),
              _buildSegmentedControl(),
              SizedBox(height: iOSDesignTokens.space12),
            ] else ...[
              SizedBox(height: iOSDesignTokens.space20),
              _buildSectionHeader('Recent Transactions'),
              SizedBox(height: iOSDesignTokens.space8),
            ],

            if (_canCollectCash && _showTeamView)
              _buildTeamBalances()
            else
              _buildRecentTransactions(),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ── Settings-style section header (accent bar + label) ───────────────

  Widget _buildSectionHeader(String title) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: cs.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        SizedBox(width: iOSDesignTokens.space8),
        Text(
          title,
          style: AppTextStyles.bodyMedium.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ── Settings-style tile (icon + title/subtitle + chevron) ────────────

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    final color = cs.primary;
    return Padding(
      padding: EdgeInsets.only(bottom: iOSDesignTokens.space6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius:
              BorderRadius.circular(iOSDesignTokens.radiusMedium),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: iOSDesignTokens.space12,
              vertical: iOSDesignTokens.space12,
            ),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius:
                  BorderRadius.circular(iOSDesignTokens.radiusMedium),
              border:
                  Border.all(color: cs.outline.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        color.withValues(alpha: 0.15),
                        color.withValues(alpha: 0.06),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                SizedBox(width: iOSDesignTokens.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppTextStyles.caption
                            .copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Approval button with badge ───────────────────────────────────────

  Widget _buildApprovalButton() {
    return Consumer(
      builder: (context, ref, child) {
        final pendingCollectionsCount = ref
                .watch(pendingCollectionsProvider(widget.shopId))
                .whenOrNull(data: (c) => c.length) ??
            0;
        final pendingRequestsCount = ref
                .watch(pendingCashRequestsProvider(widget.shopId))
                .whenOrNull(data: (r) => r.length) ??
            0;
        final totalPending = pendingCollectionsCount + pendingRequestsCount;

        return Badge(
          isLabelVisible: totalPending > 0,
          label: Text(
            totalPending > 9 ? '9+' : '$totalPending',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          backgroundColor: AppColors.error,
          child: IconButton(
            icon: const Icon(Icons.check_circle_outlined, color: Colors.white),
            tooltip: 'Approvals',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ApprovalsScreen(shopId: widget.shopId),
                ),
              );
            },
          ),
        );
      },
    );
  }

  // ── Balance Section ──────────────────────────────────────────────────

  Widget _buildBalanceSection() {
    final teamBalancesAsync = ref.watch(teamBalancesProvider);
    final cs = Theme.of(context).colorScheme;

    return teamBalancesAsync.when(
      data: (balances) {
        double myBalance = 0.0;
        double othersTotal = 0.0;
        int othersCount = 0;

        for (final member in balances) {
          if (_currentUserId != null && member.userId == _currentUserId) {
            myBalance = member.currentBalance;
          } else {
            othersTotal += member.currentBalance;
            othersCount++;
          }
        }

        return Container(
          padding: EdgeInsets.all(iOSDesignTokens.space16),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(iOSDesignTokens.radiusCard),
            border: Border.all(color: cs.primary.withValues(alpha: 0.12)),
            boxShadow: [
              BoxShadow(
                color: cs.primary.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          cs.primary,
                          cs.primary.withValues(alpha: 0.8),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: cs.primary.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_outlined,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  SizedBox(width: iOSDesignTokens.space12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'My Cash Holdings',
                          style: AppTextStyles.caption.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(height: iOSDesignTokens.space4),
                        Text(
                          Formatters.currency(myBalance),
                          style: AppTextStyles.h4.copyWith(
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (_canCollectCash && othersCount > 0) ...[
                Padding(
                  padding:
                      EdgeInsets.symmetric(vertical: iOSDesignTokens.space12),
                  child: Divider(
                    height: 1,
                    color: cs.outline.withValues(alpha: 0.15),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            cs.primary.withValues(alpha: 0.15),
                            cs.primary.withValues(alpha: 0.06),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.people_outlined,
                        color: cs.primary,
                        size: 20,
                      ),
                    ),
                    SizedBox(width: iOSDesignTokens.space12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Team Total',
                            style: AppTextStyles.caption
                                .copyWith(color: cs.onSurfaceVariant),
                          ),
                          Text(
                            Formatters.currency(othersTotal),
                            style: AppTextStyles.bodyLarge.copyWith(
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            cs.primary,
                            cs.primary.withValues(alpha: 0.8),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$othersCount member${othersCount == 1 ? '' : 's'}',
                        style: AppTextStyles.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
      loading: () => Container(
        height: 100,
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(iOSDesignTokens.radiusCard),
          border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
        ),
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (error, _) => Container(
        padding: EdgeInsets.all(iOSDesignTokens.space16),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(iOSDesignTokens.radiusCard),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: AppColors.error, size: 22),
            SizedBox(width: iOSDesignTokens.space12),
            Expanded(
              child: Text(
                'Failed to load balances. Pull to refresh.',
                style: AppTextStyles.bodySmall
                    .copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Segmented Control ────────────────────────────────────────────────

  Widget _buildSegmentedControl() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          _buildSegment(
            label: 'My Transactions',
            isSelected: !_showTeamView,
            onTap: () => setState(() => _showTeamView = false),
          ),
          _buildSegment(
            label: 'Team Cash',
            isSelected: _showTeamView,
            onTap: () => setState(() => _showTeamView = true),
          ),
        ],
      ),
    );
  }

  Widget _buildSegment({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: iOSDesignTokens.durationMedium,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? cs.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: cs.shadow.withValues(alpha: 0.08),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected ? cs.onSurface : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  // ── Team Balances ────────────────────────────────────────────────────

  Widget _buildTeamBalances() {
    final teamBalancesAsync = ref.watch(teamBalancesProvider);
    final cs = Theme.of(context).colorScheme;

    return teamBalancesAsync.when(
      data: (balances) {
        if (balances.isEmpty) {
          return _buildEmptyState('No team members found');
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Team Cash Holdings',
                  style: AppTextStyles.bodySmall.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                SizedBox(width: iOSDesignTokens.space8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${balances.length}',
                    style: AppTextStyles.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                      fontSize: 11,
                    ),
                  ),
                ),
                const Spacer(),
                if (widget.userRole.toLowerCase() == 'admin')
                  GestureDetector(
                    onTap: () => _showBulkResetSheet(balances),
                    child: Text(
                      'Reset',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(height: iOSDesignTokens.space8),
            ...balances.map((member) => _buildTeamMemberTile(member)),
          ],
        );
      },
      loading: () => _buildLoadingState(),
      error: (error, _) => _buildErrorState(error.toString()),
    );
  }

  Widget _buildTeamMemberTile(TeamCashBalance member) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: iOSDesignTokens.space6),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: iOSDesignTokens.space12,
          vertical: iOSDesignTokens.space12,
        ),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
          border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    cs.primary.withValues(alpha: 0.15),
                    cs.primary.withValues(alpha: 0.06),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  member.displayName.isNotEmpty
                      ? member.displayName[0].toUpperCase()
                      : '?',
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                  ),
                ),
              ),
            ),
            SizedBox(width: iOSDesignTokens.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatRole(member.role),
                    style: AppTextStyles.caption.copyWith(
                      color: cs.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  Formatters.currency(member.currentBalance),
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  member.lastUpdatedAt != null
                      ? _formatTime(member.lastUpdatedAt!)
                      : 'Never',
                  style: AppTextStyles.caption.copyWith(
                    color: cs.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Recent Transactions ──────────────────────────────────────────────

  Widget _buildRecentTransactions() {
    final historyAsync =
        ref.watch(cashHistoryProvider(const HistoryQuery(limit: 10)));

    return historyAsync.when(
      data: (transactions) {
        if (transactions.isEmpty) {
          return _buildEmptyState('No transactions yet');
        }
        final items = transactions.take(5).toList();
        return Column(
          children: items.map((tx) => _buildTransactionTile(tx)).toList(),
        );
      },
      loading: () => _buildLoadingState(),
      error: (error, _) => _buildErrorState(error.toString()),
    );
  }

  Widget _buildTransactionTile(CashTransaction tx) {
    final cs = Theme.of(context).colorScheme;
    final isIncoming = _isIncomingTransaction(tx.transactionType);
    final amountColor = isIncoming ? AppColors.success : AppColors.error;

    return Padding(
      padding: EdgeInsets.only(bottom: iOSDesignTokens.space6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showTransactionDetails(context, tx),
          borderRadius:
              BorderRadius.circular(iOSDesignTokens.radiusMedium),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: iOSDesignTokens.space12,
              vertical: iOSDesignTokens.space12,
            ),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius:
                  BorderRadius.circular(iOSDesignTokens.radiusMedium),
              border:
                  Border.all(color: cs.outline.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        cs.primary.withValues(alpha: 0.15),
                        cs.primary.withValues(alpha: 0.06),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      tx.avatarInitial,
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.primary,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: iOSDesignTokens.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tx.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatTransactionType(tx.transactionType),
                        style: AppTextStyles.caption
                            .copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${isIncoming ? '+' : '-'}${Formatters.currency(tx.amount.abs())}',
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        color: amountColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatTime(tx.transactionDate ?? DateTime.now()),
                      style: AppTextStyles.caption.copyWith(
                        color: cs.onSurfaceVariant,
                        fontSize: 11,
                      ),
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

  // ── Common states ────────────────────────────────────────────────────

  Widget _buildEmptyState(String message) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: iOSDesignTokens.space32),
      child: Column(
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 48,
            color: cs.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          SizedBox(height: iOSDesignTokens.space12),
          Text(
            message,
            style: AppTextStyles.bodyMedium
                .copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: iOSDesignTokens.space32),
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.all(iOSDesignTokens.space16),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: AppColors.error, size: 20),
          SizedBox(width: iOSDesignTokens.space12),
          Expanded(
            child: Text(
              error,
              style: AppTextStyles.bodySmall
                  .copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  // ── Transaction Detail Modal ─────────────────────────────────────────

  Future<void> _showTransactionDetails(
      BuildContext context, CashTransaction tx) async {
    final isSaleTransaction = tx.transactionType == 'sale' &&
        tx.relatedEntityType == 'daily_sales' &&
        tx.relatedEntityId != null;

    if (isSaleTransaction) {
      await _showSaleDetails(context, tx.relatedEntityId!);
      return;
    }

    final isIncoming = _isIncomingTransaction(tx.transactionType);
    final amountColor = isIncoming ? AppColors.success : AppColors.error;
    final cs = Theme.of(context).colorScheme;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.4,
        maxChildSize: 0.85,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(iOSDesignTokens.radiusSheet)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                width: 36,
                height: 5,
                decoration: BoxDecoration(
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.all(iOSDesignTokens.space24),
                  children: [
                    Center(
                      child: Column(
                        children: [
                          Text(
                            '${isIncoming ? '+' : '-'}${Formatters.currency(tx.amount.abs())}',
                            style: AppTextStyles.h3.copyWith(
                              fontWeight: FontWeight.w700,
                              color: amountColor,
                              letterSpacing: -1,
                            ),
                          ),
                          SizedBox(height: iOSDesignTokens.space8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: amountColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              isIncoming ? 'Money Received' : 'Money Sent',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: amountColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: iOSDesignTokens.space24),
                    Divider(
                        color: cs.outline.withValues(alpha: 0.15)),
                    SizedBox(height: iOSDesignTokens.space16),
                    _buildDetailRow(
                      icon: Icons.person_outlined,
                      label: isIncoming ? 'Received From' : 'Sent To',
                      value: tx.counterpartyName ?? 'N/A',
                    ),
                    _buildDetailRow(
                      icon: Icons.label_outlined,
                      label: 'Type',
                      value: _formatTransactionType(tx.transactionType),
                    ),
                    _buildDetailRow(
                      icon: Icons.calendar_today_outlined,
                      label: 'Date & Time',
                      value: DateFormat('MMM dd, yyyy \u2022 hh:mm a')
                          .format((tx.transactionDate ?? DateTime.now())
                              .toLocal()),
                    ),
                    _buildDetailRow(
                      icon: Icons.account_balance_wallet_outlined,
                      label: 'Balance Change',
                      value:
                          '${Formatters.currency(tx.previousBalance)} \u2192 ${Formatters.currency(tx.newBalance)}',
                    ),
                    if (tx.description.isNotEmpty)
                      _buildDetailRow(
                        icon: Icons.notes_outlined,
                        label: 'Description',
                        value: tx.description,
                      ),
                    SizedBox(height: iOSDesignTokens.space24),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                                iOSDesignTokens.radiusButton),
                          ),
                          backgroundColor:
                              cs.onSurface.withValues(alpha: 0.05),
                        ),
                        child: Text(
                          'Done',
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                            color: cs.primary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: iOSDesignTokens.space16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: cs.onSurfaceVariant),
          SizedBox(width: iOSDesignTokens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.caption
                      .copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showSaleDetails(BuildContext context, String saleId) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) =>
            const Center(child: CircularProgressIndicator()),
      );

      final authService =
          provider.Provider.of<AuthService>(context, listen: false);
      final dailySalesService = DailySalesService(authService);
      final response =
          await dailySalesService.getDailySalesRecordById(saleId);

      if (context.mounted) Navigator.pop(context);

      if (response.success && response.data != null) {
        if (context.mounted) {
          await SaleDetailsModal.show(context, response.data!);
        }
      } else {
        if (context.mounted) {
          SnackbarHelper.showError(
              context, response.error ?? 'Failed to load sale details');
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        SnackbarHelper.showError(context, 'Error loading sale details: $e');
      }
    }
  }

  // ── Bulk Reset Sheet ─────────────────────────────────────────────────

  void _showBulkResetSheet(List<TeamCashBalance> balances) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => BulkResetSheet(
        teamBalances: balances,
        onConfirm: (userIds, newBalance, reason, notes) async {
          Navigator.pop(context);
          try {
            final cashService = CashService(
              provider.Provider.of<DioApiService>(context, listen: false),
            );
            final affectedCount = await cashService.adminBulkReset(
              userIds: userIds,
              newBalance: newBalance,
              reason: reason,
              notes: notes,
            );
            if (mounted) {
              SnackbarHelper.showSuccess(
                this.context,
                '$affectedCount user(s) reset to \u20B9${newBalance.toStringAsFixed(0)}',
              );
              _refreshData();
            }
          } catch (e) {
            if (mounted) {
              SnackbarHelper.showError(this.context, 'Error: $e');
            }
          }
        },
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  bool _isIncomingTransaction(String transactionType) {
    switch (transactionType.toLowerCase()) {
      case 'collection_received':
      case 'request_received':
      case 'sale':
      case 'opening_balance':
      case 'adjustment_credit':
        return true;
      case 'collection_sent':
      case 'collection_given':
      case 'request_given':
      case 'submission':
      case 'expense':
      case 'return':
      case 'adjustment_debit':
        return false;
      default:
        return true;
    }
  }

  String _formatRole(String role) {
    return role.replaceAll('_', ' ').toUpperCase();
  }

  String _formatTransactionType(String type) {
    const friendlyLabels = {
      'request_given': 'Money Sent',
      'request_received': 'Money Received',
      'collection_given': 'Cash Submitted',
      'collection_received': 'Cash Collected',
      'sale': 'Sale',
      'return': 'Return',
      'expense': 'Expense',
      'adjustment': 'Adjustment',
      'opening_balance': 'Opening Balance',
      'closing_balance': 'Closing Balance',
    };
    return friendlyLabels[type] ??
        type
            .split('_')
            .map((w) => w[0].toUpperCase() + w.substring(1))
            .join(' ');
  }

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d').format(date);
  }
}
