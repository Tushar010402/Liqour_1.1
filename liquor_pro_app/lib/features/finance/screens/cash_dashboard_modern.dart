import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../providers/cash_provider.dart';
import '../models/cash_models.dart';
import 'request_cash_screen.dart';
import 'send_money_screen.dart';
import 'cash_history_screen.dart';
import 'approvals_screen.dart';
import 'submit_cash_screen.dart';

/// Modern UPI-Style Cash Management Dashboard
/// Clean, intuitive interface inspired by Google Pay, PhonePe, and Paytm
class CashDashboardModern extends ConsumerStatefulWidget {
  final String shopId;
  final String userRole;
  final String? userId;  // Current user ID for filtering submissions

  const CashDashboardModern({
    super.key,
    required this.shopId,
    required this.userRole,
    this.userId,
  });

  @override
  ConsumerState<CashDashboardModern> createState() =>
      _CashDashboardModernState();
}

class _CashDashboardModernState extends ConsumerState<CashDashboardModern>
    with SingleTickerProviderStateMixin {
  late AnimationController _balanceAnimationController;
  late Animation<double> _balanceAnimation;
  double _previousBalance = 0;

  @override
  void initState() {
    super.initState();
    _balanceAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _balanceAnimation = CurvedAnimation(
      parent: _balanceAnimationController,
      curve: Curves.elasticOut,
    );
    _balanceAnimationController.forward();
  }

  @override
  void dispose() {
    _balanceAnimationController.dispose();
    super.dispose();
  }

  void _refreshData() {
    // Haptic feedback on pull to refresh
    HapticFeedback.mediumImpact();
    ref.invalidate(cashBalanceProvider);
    ref.invalidate(cashHistoryProvider);
    _balanceAnimationController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;
    final balanceAsync = ref.watch(cashBalanceProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: RefreshIndicator(
        onRefresh: () async {
          _refreshData();
          await Future.delayed(const Duration(seconds: 1));
        },
        color: AppColors.success,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Modern App Bar with Glass Effect
            SliverAppBar(
              expandedHeight: size.height * 0.28,
              floating: false,
              pinned: true,
              backgroundColor: Colors.transparent,
              elevation: 0,
              flexibleSpace: FlexibleSpaceBar(
                background: _buildBalanceCard(balanceAsync),
              ),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.history, color: Colors.white),
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

            // Quick Actions Section
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                child: _buildQuickActions(),
              ),
            ),

            // Pending Approvals Card (Manager/Admin only)
            if (_isManagerOrAdmin())
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildPendingApprovalsCard(),
                ),
              ),

            // My Submissions Card (All users)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: _buildMySubmissionsCard(),
              ),
            ),

            // Recent Transactions Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Recent Transactions',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CashHistoryScreen(shopId: widget.shopId),
                          ),
                        );
                      },
                      child: const Text(
                        'View All',
                        style: TextStyle(
                          color: AppColors.success,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Recent Transactions List
            SliverToBoxAdapter(
              child: _buildRecentTransactions(),
            ),

            // Bottom Padding
            const SliverToBoxAdapter(
              child: SizedBox(height: 100),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceCard(AsyncValue<double> balanceAsync) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.success,
            AppColors.success.withOpacity(0.8),
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
          Positioned(
            bottom: -30,
            left: -30,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.05),
              ),
            ),
          ),

          // Content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Available Balance',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: balanceAsync.when(
                      data: (balance) {
                        if (balance != _previousBalance) {
                          _previousBalance = balance;
                          _balanceAnimationController.forward(from: 0);
                        }
                        return AnimatedBuilder(
                          animation: _balanceAnimation,
                          builder: (context, child) {
                            return Transform.scale(
                              scale: 0.9 + (_balanceAnimation.value * 0.1),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  Formatters.currency(balance * _balanceAnimation.value),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 40,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                      loading: () => const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      ),
                      error: (_, __) => Text(
                        '₹0.00',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 40,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.verified,
                          color: Colors.white,
                          size: 14,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Updated ${_formatTime(DateTime.now())}',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Row(
      children: [
        Expanded(
          child: _buildActionCard(
            icon: Icons.call_made,
            label: 'Request',
            subtitle: 'Money',
            color: AppColors.success,
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const RequestCashScreen(),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildActionCard(
            icon: Icons.call_received,
            label: 'Send',
            subtitle: 'Money',
            color: const Color(0xFF5B69FF),
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SendMoneyScreen(shopId: widget.shopId),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              top: -20,
              right: -20,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withOpacity(0.05),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  const Spacer(),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: cs.onSurfaceVariant,
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

  Widget _buildRecentTransactions() {
    final historyAsync = ref.watch(
      cashHistoryProvider(const HistoryQuery(limit: 5)),
    );

    return historyAsync.when(
      data: (transactions) {
        if (transactions.isEmpty) {
          return _buildEmptyTransactions();
        }

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          itemCount: transactions.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            return _buildModernTransactionTile(transactions[index]);
          },
        );
      },
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(color: AppColors.success),
        ),
      ),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Text('Unable to load transactions'),
        ),
      ),
    );
  }

  Widget _buildModernTransactionTile(CashTransaction tx) {
    final cs = Theme.of(context).colorScheme;
    final isIncoming = tx.amount > 0;
    final icon = _getModernTransactionIcon(tx.transactionType);
    final color = isIncoming ? AppColors.success : Colors.orange;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: cs.onSurfaceVariant.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
          _getModernTransactionLabel(tx.transactionType, tx.description),
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
        subtitle: Text(
          _formatRelativeTime(tx.transactionDate ?? DateTime.now()),
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 13,
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${isIncoming ? '+' : '-'} ${Formatters.currency(tx.amount.abs())}',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            if (tx.transactionType.contains('pending'))
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Pending',
                  style: TextStyle(
                    color: Colors.orange,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyTransactions() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: cs.onSurfaceVariant.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.receipt_long_outlined,
              size: 40,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No Transactions Yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your transactions will appear here',
            style: TextStyle(
              fontSize: 14,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getModernTransactionIcon(String type) {
    switch (type) {
      case 'request_received':
        return Icons.call_received;
      case 'request_given':
        return Icons.call_made;
      case 'sale':
        return Icons.shopping_cart_outlined;
      default:
        return Icons.swap_horiz;
    }
  }

  String _getModernTransactionLabel(String type, String description) {
    // Extract name from description if possible
    if (description.contains('from')) {
      final parts = description.split('from');
      if (parts.length > 1) {
        final name = parts[1].split('(')[0].trim();
        return 'Received from $name';
      }
    }
    if (description.contains('for')) {
      final parts = description.split('for');
      if (parts.length > 1) {
        final name = parts[1].split('(')[0].trim();
        return 'Sent to $name';
      }
    }

    // Default labels
    switch (type) {
      case 'request_received':
        return 'Money Received';
      case 'request_given':
        return 'Money Sent';
      case 'sale':
        return 'Sale Transaction';
      default:
        return description;
    }
  }

  String _formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      if (difference.inDays == 1) return 'Yesterday';
      if (difference.inDays < 7) return '${difference.inDays} days ago';
      return DateFormat('dd MMM').format(dateTime);
    }
    if (difference.inHours > 0) {
      return '${difference.inHours} ${difference.inHours == 1 ? "hour" : "hours"} ago';
    }
    if (difference.inMinutes > 0) {
      return '${difference.inMinutes} ${difference.inMinutes == 1 ? "minute" : "minutes"} ago';
    }
    return 'Just now';
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inSeconds < 60) {
      return 'just now';
    }
    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    }
    return DateFormat('HH:mm').format(dateTime);
  }

  /// Check if current user is manager or admin
  bool _isManagerOrAdmin() {
    final role = widget.userRole.toLowerCase();
    return role == 'manager' || role == 'admin' || role == 'owner';
  }

  /// Build Pending Approvals Card for Manager/Admin
  Widget _buildPendingApprovalsCard() {
    // Watch all pending providers
    final pendingSubmissionsAsync = ref.watch(pendingSubmissionsProvider(null));
    final pendingCollectionsAsync = ref.watch(pendingCollectionsProvider(widget.shopId));
    final pendingRequestsAsync = ref.watch(pendingCashRequestsProvider(widget.shopId));

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.orange.shade400,
            Colors.orange.shade600,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ApprovalsScreen(shopId: widget.shopId),
              ),
            );
          },
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                // Icon container
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.approval,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),

                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Pending Approvals',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Builder(builder: (context) {
                        // Calculate total pending count
                        int totalPending = 0;
                        double totalAmount = 0;

                        if (pendingSubmissionsAsync.hasValue) {
                          totalPending += pendingSubmissionsAsync.value?.length ?? 0;
                          for (final s in pendingSubmissionsAsync.value ?? []) {
                            totalAmount += s.totalAmount;
                          }
                        }
                        if (pendingCollectionsAsync.hasValue) {
                          totalPending += pendingCollectionsAsync.value?.length ?? 0;
                        }
                        if (pendingRequestsAsync.hasValue) {
                          totalPending += pendingRequestsAsync.value?.length ?? 0;
                        }

                        if (totalPending == 0) {
                          return Text(
                            'All caught up!',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 14,
                            ),
                          );
                        }

                        return Text(
                          '$totalPending items · ${Formatters.currency(totalAmount)} in deposits',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 14,
                          ),
                        );
                      }),
                    ],
                  ),
                ),

                // Arrow
                Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white.withOpacity(0.7),
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Build My Submissions Card - shows user's pending bank deposits
  Widget _buildMySubmissionsCard() {
    final cs = Theme.of(context).colorScheme;
    // Filter by current user ID to show only their submissions
    final mySubmissionsAsync = ref.watch(
      submissionsProvider(SubmissionsQuery(
        userId: widget.userId,
        status: 'pending',
        limit: 3,
      )),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'My Bank Deposits',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            TextButton.icon(
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SubmitCashScreen(shopId: widget.shopId),
                  ),
                );
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.success,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Submissions list
        mySubmissionsAsync.when(
          data: (submissions) {
            if (submissions.isEmpty) {
              return _buildEmptySubmissionsCard();
            }

            return Column(
              children: submissions.map((submission) {
                return _buildSubmissionTile(submission);
              }).toList(),
            );
          },
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(color: AppColors.success),
            ),
          ),
          error: (error, _) => _buildEmptySubmissionsCard(),
        ),
      ],
    );
  }

  Widget _buildEmptySubmissionsCard() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: cs.onSurfaceVariant.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.account_balance,
              color: Colors.blue[600],
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No Pending Deposits',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Submit cash to bank when ready',
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmissionTile(CashSubmission submission) {
    final cs = Theme.of(context).colorScheme;
    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (submission.status.toLowerCase()) {
      case 'pending':
        statusColor = Colors.orange;
        statusIcon = Icons.hourglass_empty;
        statusText = 'Pending Approval';
        break;
      case 'approved':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusText = 'Approved';
        break;
      case 'rejected':
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        statusText = submission.rejectionReason ?? 'Rejected';
        break;
      default:
        statusColor = cs.onSurfaceVariant;
        statusIcon = Icons.help_outline;
        statusText = submission.status;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: statusColor.withOpacity(0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: cs.onSurfaceVariant.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            // If rejected, allow re-submission
            if (submission.status.toLowerCase() == 'rejected') {
              HapticFeedback.lightImpact();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SubmitCashScreen(
                    shopId: widget.shopId,
                    resubmitFrom: submission,
                  ),
                ),
              );
            }
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Amount display
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.account_balance,
                    color: Colors.blue[600],
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),

                // Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        Formatters.currency(submission.totalAmount),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        submission.depositDate != null
                            ? 'Deposit: ${DateFormat('dd MMM yyyy').format(submission.depositDate!)}'
                            : 'Submitted ${_formatRelativeTime(submission.createdAt ?? DateTime.now())}',
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),

                // Status
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(statusIcon, color: statusColor, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            submission.status.toLowerCase() == 'pending'
                                ? 'Pending'
                                : submission.status.toLowerCase() == 'approved'
                                    ? 'Approved'
                                    : 'Rejected',
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (submission.status.toLowerCase() == 'rejected')
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Tap to re-submit',
                          style: TextStyle(
                            color: Colors.blue[600],
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
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
}