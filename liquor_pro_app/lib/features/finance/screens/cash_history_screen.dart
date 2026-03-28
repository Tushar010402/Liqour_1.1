import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as provider;
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../../../core/widgets/sale_details_modal.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../sales/services/daily_sales_service.dart';
import '../../../core/services/auth_service.dart';
import '../providers/cash_provider.dart';
import '../models/cash_models.dart';

/// Cash History Screen - Professional timeline-based transaction history
class CashHistoryScreen extends ConsumerWidget {
  final String shopId;

  const CashHistoryScreen({super.key, required this.shopId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final historyAsync = ref.watch(cashHistoryProvider(
      HistoryQuery(shopId: shopId, limit: 100),
    ));

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: const CustomAppBar(
        title: 'Cash History',
      ),
      body: historyAsync.when(
        data: (transactions) {
          if (transactions.isEmpty) {
            return _buildEmptyState(cs);
          }

          // Group transactions by date
          final groupedTransactions = _groupByDate(transactions);

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(cashHistoryProvider);
            },
            color: cs.primary,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: groupedTransactions.length,
              itemBuilder: (context, index) {
                final date = groupedTransactions.keys.elementAt(index);
                final dayTransactions = groupedTransactions[date]!;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Date Header
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _formatDateHeader(date),
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontWeight: FontWeight.w600,
                                color: cs.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              height: 1,
                              color: cs.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Transactions for this date
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: dayTransactions.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, txIndex) {
                          return _buildTransactionTile(context, dayTransactions[txIndex], cs);
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                );
              },
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text('Error: $error', style: AppTextStyles.bodyMedium),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history_outlined,
              size: 80,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text('No Transactions', style: AppTextStyles.h4),
            const SizedBox(height: 8),
            Text(
              'No cash transactions to display yet.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionTile(BuildContext context, CashTransaction tx, ColorScheme cs) {
    final isIncoming = tx.amount > 0;
    final icon = _getTransactionIcon(tx.transactionType);
    final color = isIncoming ? AppColors.success : AppColors.error;
    final isSaleTransaction = tx.transactionType == 'sale' &&
                               tx.relatedEntityType == 'daily_sales' &&
                               tx.relatedEntityId != null;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      leading: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 24),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              _formatTransactionType(tx.transactionType),
              style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          if (isSaleTransaction)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: AppColors.info.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.visibility_outlined,
                    size: 10,
                    color: AppColors.info,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    'View',
                    style: AppTextStyles.bodySmall.copyWith(
                      fontSize: 9,
                      color: AppColors.info,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(
            tx.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 14,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  'Balance: ${Formatters.currency(tx.previousBalance)} → ${Formatters.currency(tx.newBalance)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${isIncoming ? '+' : ''}${Formatters.currency(tx.amount)}',
            style: AppTextStyles.h6.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                DateFormat('h:mm a').format(tx.transactionDate ?? DateTime.now()),
                style: AppTextStyles.bodySmall.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              if (isSaleTransaction) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
              ],
            ],
          ),
        ],
      ),
      onTap: isSaleTransaction ? () => _showSaleDetails(context, tx.relatedEntityId!) : null,
    );
  }

  Future<void> _showSaleDetails(BuildContext context, String saleId) async {
    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // Fetch the daily sales record
      final authService = provider.Provider.of<AuthService>(context, listen: false);
      final dailySalesService = DailySalesService(authService);
      final response = await dailySalesService.getDailySalesRecordById(saleId);

      // Close loading indicator
      if (context.mounted) {
        Navigator.pop(context);
      }

      if (response.success && response.data != null) {
        // Show the modal with sale details
        if (context.mounted) {
          await SaleDetailsModal.show(context, response.data!);
        }
      } else {
        if (context.mounted) {
          SnackbarHelper.showError(
            context,
            response.error ?? 'Failed to load sale details',
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        SnackbarHelper.showError(context, 'Error loading sale details: $e');
      }
    }
  }

  Map<DateTime, List<CashTransaction>> _groupByDate(
      List<CashTransaction> transactions) {
    final grouped = <DateTime, List<CashTransaction>>{};

    for (final tx in transactions) {
      final txDate = tx.transactionDate ?? DateTime.now();
      final date = DateTime(
        txDate.year,
        txDate.month,
        txDate.day,
      );

      if (!grouped.containsKey(date)) {
        grouped[date] = [];
      }
      grouped[date]!.add(tx);
    }

    return grouped;
  }

  String _formatDateHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    if (date == today) {
      return 'Today';
    } else if (date == yesterday) {
      return 'Yesterday';
    } else if (now.difference(date).inDays < 7) {
      return DateFormat('EEEE').format(date);
    } else {
      return DateFormat('MMMM d, yyyy').format(date);
    }
  }

  IconData _getTransactionIcon(String type) {
    switch (type) {
      case 'sale':
        return Icons.shopping_cart_outlined;
      case 'collection_received':
        return Icons.call_received;
      case 'collection_given':
        return Icons.call_made;
      case 'submission':
        return Icons.account_balance_outlined;
      case 'adjustment':
        return Icons.edit_outlined;
      default:
        return Icons.account_balance_wallet_outlined;
    }
  }

  String _formatTransactionType(String type) {
    final words = type.split('_');
    return words.map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
  }
}
