import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../models/bank_models.dart';
import '../providers/bank_provider.dart';
import 'bank_account_form_modern_screen.dart';
import 'record_transaction_form_screen.dart';

/// Modern Bank Account Detail Screen
/// Shows account details with modern Material Design
/// Uses reactive provider for real-time balance updates
class BankAccountDetailModernScreen extends ConsumerWidget {
  final String accountId;

  const BankAccountDetailModernScreen({
    super.key,
    required this.accountId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final accountAsync = ref.watch(bankAccountProvider(accountId));
    final summaryAsync = ref.watch(bankAccountSummaryProvider(accountId));
    final transactionsAsync = ref.watch(bankTransactionsProvider(accountId));
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: cs.surface,
      body: accountAsync.when(
        data: (account) => CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Modern App Bar with Account Header
            SliverAppBar(
              expandedHeight: size.height * 0.38,
              floating: false,
              pinned: true,
              backgroundColor: Colors.transparent,
              elevation: 0,
              flexibleSpace: FlexibleSpaceBar(
                background: _buildAccountHeader(account),
              ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  onPressed: () => _showOptionsMenu(context, ref, account),
                ),
              ],
          ),

          // Summary Stats
          SliverToBoxAdapter(
            child: summaryAsync.when(
              data: (summary) => Padding(
                padding: const EdgeInsets.all(16),
                child: _buildSummaryStats(context, account, summary),
              ),
              loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.info),
                ),
              ),
              error: (error, stack) => const SizedBox.shrink(),
            ),
          ),

          // Transactions Section Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Recent Transactions',
                    style: AppTextStyles.h5.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _showRecordTransactionSheet(context, ref, account),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Record'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.info,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Transactions List
          transactionsAsync.when(
            data: (transactions) {
              if (transactions.isEmpty) {
                return SliverToBoxAdapter(
                  child: _buildEmptyTransactions(cs),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildTransactionCard(transactions[index], cs),
                      );
                    },
                    childCount: transactions.length > 10 ? 10 : transactions.length,
                  ),
                ),
              );
            },
            loading: () => const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.info),
                ),
              ),
            ),
            error: (error, stack) => SliverToBoxAdapter(
              child: _buildErrorState(error.toString(), cs),
            ),
          ),

            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        ),
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.info),
        ),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 16),
              Text(
                'Error loading account',
                style: AppTextStyles.h6.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  error.toString(),
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Go Back'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.info,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAccountHeader(TenantBankAccount account) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.info,
            AppColors.info.withOpacity(0.8),
          ],
        ),
      ),
      child: Stack(
        children: [
          // Background Pattern
          Positioned(
            top: -50,
            right: -50,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.1),
              ),
            ),
          ),

          // Content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              account.bankName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              account.accountHolderName,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (account.isDefault)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.white, width: 1),
                          ),
                          child: const Text(
                            'DEFAULT',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // Account Number & IFSC
                  Text(
                    account.accountNumber.isNotEmpty ? account.accountNumber : '****',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'IFSC: ${account.ifscCode.isNotEmpty ? account.ifscCode : 'N/A'}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 12,
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Total Available Balance - compute if not provided by backend
                  Text(
                    'Total Available',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      Formatters.currency(
                        account.totalAvailableBalance > 0
                            ? account.totalAvailableBalance
                            : account.currentBalance + account.availableOd,
                      ),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Balance Breakdown
                  Row(
                    children: [
                      Expanded(
                        child: _buildBalanceChip(
                          'Balance',
                          account.currentBalance,
                        ),
                      ),
                      if (account.odLimit > 0) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildBalanceChip(
                            'OD Available',
                            account.availableOd,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceChip(String label, double amount) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              Formatters.currency(amount),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryStats(
      BuildContext context, TenantBankAccount account, BankAccountSummaryResponse summary) {
    final cs = Theme.of(context).colorScheme;
    final odUtilization = summary.odUtilizationPercent;
    Color odColor = AppColors.success;
    if (odUtilization > 80) {
      odColor = AppColors.error;
    } else if (odUtilization > 50) {
      odColor = AppColors.warning;
    }

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This Month Summary',
            style: AppTextStyles.h6.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Deposits',
                  summary.totalDepositsThisMonth,
                  Icons.arrow_downward,
                  AppColors.success,
                  cs: cs,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Withdrawals',
                  summary.totalWithdrawalsThisMonth,
                  Icons.arrow_upward,
                  AppColors.error,
                  cs: cs,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Transactions',
                  summary.transactionCount.toDouble(),
                  Icons.receipt_long,
                  AppColors.info,
                  isCount: true,
                  cs: cs,
                ),
              ),
              if (account.odLimit > 0) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    'OD Usage',
                    odUtilization,
                    Icons.pie_chart,
                    odColor,
                    isPercentage: true,
                    cs: cs,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String label,
    double value,
    IconData icon,
    Color color, {
    bool isCount = false,
    bool isPercentage = false,
    ColorScheme? cs,
  }) {
    String valueText;
    if (isCount) {
      valueText = value.toInt().toString();
    } else if (isPercentage) {
      valueText = '${value.toStringAsFixed(1)}%';
    } else {
      valueText = Formatters.currency(value);
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const Spacer(),
              Text(
                valueText,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: cs?.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionCard(BankTransaction transaction, ColorScheme cs) {
    final isDeposit = transaction.transactionType == 'deposit' ||
        transaction.transactionType == 'od_repayment';
    final color = isDeposit ? AppColors.success : AppColors.error;
    final icon = isDeposit ? Icons.arrow_downward : Icons.arrow_upward;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        title: Text(
          _getTransactionTitle(transaction.transactionType),
          style: AppTextStyles.bodyLarge.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (transaction.description != null) ...[
              const SizedBox(height: 4),
              Text(
                transaction.description!,
                style: AppTextStyles.bodySmall.copyWith(
                  color: cs.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 4),
            Text(
              Formatters.date(transaction.transactionDate ?? DateTime.now()),
              style: AppTextStyles.bodySmall.copyWith(
                color: cs.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${isDeposit ? '+' : '-'}${Formatters.currency(transaction.amount)}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Bal: ${Formatters.currency(transaction.balanceAfter)}',
              style: AppTextStyles.bodySmall.copyWith(
                color: cs.onSurfaceVariant,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getTransactionTitle(String type) {
    switch (type) {
      case 'deposit':
        return 'Deposit';
      case 'withdrawal':
        return 'Withdrawal';
      case 'od_usage':
        return 'OD Usage';
      case 'od_repayment':
        return 'OD Repayment';
      case 'interest_charge':
        return 'Interest Charge';
      case 'bank_charges':
        return 'Bank Charges';
      case 'adjustment':
        return 'Adjustment';
      default:
        return type;
    }
  }

  Widget _buildEmptyTransactions(ColorScheme cs) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.info.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.receipt_long_outlined,
              size: 40,
              color: AppColors.info,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No Transactions Yet',
            style: AppTextStyles.bodyLarge.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Transactions will appear here',
            style: AppTextStyles.bodySmall.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error, ColorScheme cs) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.error_outline,
            size: 48,
            color: AppColors.error,
          ),
          const SizedBox(height: 16),
          Text(
            'Error Loading Transactions',
            style: AppTextStyles.bodyLarge.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _showOptionsMenu(BuildContext context, WidgetRef ref, TenantBankAccount account) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Account Options',
              style: AppTextStyles.h6.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.add_circle_outline, color: AppColors.info),
              title: const Text('Record Transaction'),
              onTap: () {
                Navigator.pop(context);
                _showRecordTransactionSheet(context, ref, account);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: AppColors.warning),
              title: const Text('Edit Account'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BankAccountFormModernScreen(account: account),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.sync_outlined, color: AppColors.success),
              title: const Text('Bank Reconciliation'),
              onTap: () {
                Navigator.pop(context);
                // TODO: Navigate to reconciliation
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  void _showRecordTransactionSheet(BuildContext context, WidgetRef ref, TenantBankAccount account) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Record Transaction',
              style: AppTextStyles.h6.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.arrow_downward, color: AppColors.success),
              ),
              title: const Text('Deposit'),
              subtitle: const Text('Add money to account'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RecordTransactionFormScreen(
                      accountId: account.id,
                      transactionType: 'deposit',
                      account: account,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.arrow_upward, color: AppColors.error),
              ),
              title: const Text('Withdrawal'),
              subtitle: const Text('Remove money from account'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RecordTransactionFormScreen(
                      accountId: account.id,
                      transactionType: 'withdrawal',
                      account: account,
                    ),
                  ),
                );
              },
            ),
            if (account.odLimit > 0) ...[
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.replay, color: AppColors.warning),
                ),
                title: const Text('OD Repayment'),
                subtitle: const Text('Repay overdraft amount'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RecordTransactionFormScreen(
                        accountId: account.id,
                        transactionType: 'od_repayment',
                        account: account,
                      ),
                    ),
                  );
                },
              ),
            ],
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}
