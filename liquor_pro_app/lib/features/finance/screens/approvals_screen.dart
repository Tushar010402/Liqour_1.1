import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/theme/ios_design_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../providers/cash_provider.dart';
import '../models/cash_models.dart';

/// Approvals Screen - Professional manager/admin view for approving bank submissions and collections
class ApprovalsScreen extends ConsumerStatefulWidget {
  final String shopId;

  const ApprovalsScreen({super.key, required this.shopId});

  @override
  ConsumerState<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends ConsumerState<ApprovalsScreen>
    with SingleTickerProviderStateMixin {
  final Set<String> _expandedCards = {};
  late TabController _tabController;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    // Start auto-refresh polling every 30 seconds
    _startAutoRefresh();
  }

  /// Start auto-refresh timer to poll for new approvals every 30 seconds
  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        // Refresh all pending providers
        ref.invalidate(pendingSubmissionsProvider);
        ref.invalidate(pendingCollectionsProvider);
        ref.invalidate(pendingCashRequestsProvider);
      }
    });
  }

  /// Manually refresh all data
  void _manualRefresh() {
    ref.invalidate(pendingSubmissionsProvider);
    ref.invalidate(pendingCollectionsProvider);
    ref.invalidate(pendingCashRequestsProvider);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: CustomAppBar(
        title: 'Pending Approvals',
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: cs.primary,
          indicatorWeight: 3,
          labelColor: cs.primary,
          unselectedLabelColor: cs.onSurfaceVariant,
          tabs: const [
            Tab(
              icon: Icon(Icons.call_received),
              text: 'Collections',
            ),
            Tab(
              icon: Icon(Icons.account_balance),
              text: 'Bank Deposits',
            ),
            Tab(
              icon: Icon(Icons.request_page),
              text: 'Cash Requests',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCollectionsTab(),
          _buildSubmissionsTab(),
          _buildCashRequestsTab(),
        ],
      ),
    );
  }

  Widget _buildCollectionsTab() {
    final pendingCollections =
        ref.watch(pendingCollectionsProvider(widget.shopId));

    return pendingCollections.when(
      data: (collections) {
        if (collections.isEmpty) {
          return _buildEmptyState('No Pending Collections',
              'All cash collection requests have been reviewed.');
        }
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(pendingCollectionsProvider);
          },
          color: Theme.of(context).colorScheme.primary,
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: collections.length,
            separatorBuilder: (_, __) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              return _buildCollectionCard(collections[index]);
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Text('Error: $error', style: AppTextStyles.bodyMedium),
      ),
    );
  }

  Widget _buildSubmissionsTab() {
    // Pass null to get ALL pending submissions across all shops for admin view
    // Backend handles role-based filtering - admins see all, managers see their shop's
    final pendingSubmissions =
        ref.watch(pendingSubmissionsProvider(null));

    return pendingSubmissions.when(
      data: (submissions) {
        if (submissions.isEmpty) {
          return _buildEmptyState('No Pending Bank Deposits',
              'All bank deposit submissions have been reviewed.');
        }
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(pendingSubmissionsProvider);
          },
          color: Theme.of(context).colorScheme.primary,
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: submissions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              return _buildSubmissionCard(submissions[index]);
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Text('Error: $error', style: AppTextStyles.bodyMedium),
      ),
    );
  }

  Widget _buildEmptyState(String title, String message) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 80,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(title, style: AppTextStyles.h4),
            const SizedBox(height: 8),
            Text(
              message,
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

  Widget _buildCollectionCard(CashCollection collection) {
    final cs = Theme.of(context).colorScheme;
    final isExpanded = _expandedCards.contains(collection.id);
    final timeRemaining = collection.timeRemaining;
    final isUrgent = timeRemaining != null && timeRemaining.inMinutes < 3;

    final initial = collection.fromUser?.name.substring(0, 1).toUpperCase() ?? 'U';

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
        border: Border.all(
          color: isUrgent
              ? AppColors.error
              : cs.outline.withValues(alpha: 0.2),
          width: isUrgent ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          // Header
          InkWell(
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedCards.remove(collection.id);
                } else {
                  _expandedCards.add(collection.id);
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isUrgent
                    ? AppColors.error.withOpacity(0.1)
                    : cs.primary.withOpacity(0.1),
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(iOSDesignTokens.radiusMedium),
                  bottom: isExpanded ? Radius.zero : Radius.circular(iOSDesignTokens.radiusMedium),
                ),
              ),
              child: Column(
                children: [
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
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            initial,
                            style: AppTextStyles.h6.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              collection.fromUser?.name ?? 'Unknown User',
                              style: AppTextStyles.bodyLarge.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              collection.fromUser?.role.toUpperCase() ??
                                  'UNKNOWN',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            Formatters.currency(collection.amount),
                            style: AppTextStyles.h5.copyWith(
                              fontWeight: FontWeight.bold,
                              color: isUrgent ? AppColors.error : null,
                            ),
                          ),
                          if (timeRemaining != null)
                            Text(
                              collection.timeRemainingFormatted ?? '',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: isUrgent
                                    ? AppColors.error
                                    : AppColors.warning,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  if (isUrgent) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'URGENT - Expiring Soon!',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Expandable content
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (collection.notes != null &&
                      collection.notes!.isNotEmpty) ...[
                    Text('Notes:', style: AppTextStyles.h6),
                    const SizedBox(height: 8),
                    Text(
                      collection.notes!,
                      style: AppTextStyles.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _handleRejectCollection(collection),
                          icon: const Icon(Icons.close, size: 18),
                          label: const Text('Reject', maxLines: 1, overflow: TextOverflow.ellipsis),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                            side: const BorderSide(color: AppColors.error),
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _handleApproveCollection(collection),
                          icon: const Icon(Icons.check, size: 18),
                          label: const Text('Approve', maxLines: 1, overflow: TextOverflow.ellipsis),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.success,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSubmissionCard(CashSubmission submission) {
    final cs = Theme.of(context).colorScheme;
    final isExpanded = _expandedCards.contains(submission.id);

    // Get display name from userName field (from created_by_name) or fallback
    final displayName = submission.userName.isNotEmpty
        ? submission.userName
        : (submission.user?.name ?? 'Unknown User');
    final displayInitial = displayName.isNotEmpty
        ? displayName.substring(0, 1).toUpperCase()
        : 'U';

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
        border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header - Always visible with key info
          InkWell(
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedCards.remove(submission.id);
                } else {
                  _expandedCards.add(submission.id);
                }
              });
            },
            borderRadius: BorderRadius.vertical(top: Radius.circular(iOSDesignTokens.radiusMedium)),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.1),
                borderRadius: BorderRadius.vertical(top: Radius.circular(iOSDesignTokens.radiusMedium)),
              ),
              child: Column(
                children: [
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
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            displayInitial,
                            style: AppTextStyles.h6.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              style: AppTextStyles.bodyLarge.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Row(
                              children: [
                                if (submission.shopName.isNotEmpty) ...[
                                  Icon(Icons.store, size: 12, color: cs.onSurfaceVariant),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      submission.shopName,
                                      style: AppTextStyles.bodySmall.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Icon(Icons.calendar_today, size: 12, color: cs.onSurfaceVariant),
                                const SizedBox(width: 4),
                                Text(
                                  DateFormat('MMM d, h:mm a')
                                      .format(submission.depositDate ?? DateTime.now()),
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            Formatters.currency(submission.totalAmount),
                            style: AppTextStyles.h5.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppColors.success,
                            ),
                          ),
                          if (submission.bankAccountName.isNotEmpty)
                            Text(
                              submission.bankAccountName.length > 15
                                  ? '${submission.bankAccountName.substring(0, 15)}...'
                                  : submission.bankAccountName,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Always visible: Approve/Reject Buttons
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              border: Border(
                top: BorderSide(color: cs.outlineVariant),
              ),
            ),
            child: Row(
              children: [
                // View Details Button
                Expanded(
                  flex: 1,
                  child: TextButton.icon(
                    onPressed: () {
                      setState(() {
                        if (isExpanded) {
                          _expandedCards.remove(submission.id);
                        } else {
                          _expandedCards.add(submission.id);
                        }
                      });
                    },
                    icon: Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                    ),
                    label: Text(isExpanded ? 'Less' : 'Details'),
                    style: TextButton.styleFrom(
                      foregroundColor: cs.onSurfaceVariant,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Reject Button
                Expanded(
                  flex: 3,
                  child: OutlinedButton.icon(
                    onPressed: () => _showRejectDialog(submission),
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Reject', maxLines: 1, overflow: TextOverflow.ellipsis),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Approve Button
                Expanded(
                  flex: 3,
                  child: ElevatedButton.icon(
                    onPressed: () => _handleApprove(submission),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Approve', maxLines: 1, overflow: TextOverflow.ellipsis),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Expandable content - Details only
          if (isExpanded) ...[
            const Divider(height: 1),

            // Denomination Breakdown
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Denomination Breakdown',
                    style: AppTextStyles.h6.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildDenominationRow('\u20B9500', submission.notes500, 500),
                  _buildDenominationRow('\u20B9200', submission.notes200, 200),
                  _buildDenominationRow('\u20B9100', submission.notes100, 100),
                  _buildDenominationRow('\u20B950', submission.notes50, 50),
                  _buildDenominationRow('\u20B920', submission.notes20, 20),
                  _buildDenominationRow('\u20B910', submission.notes10, 10),
                ],
              ),
            ),

            // Receipt Photo
            if (submission.receiptPhotoUrl.isNotEmpty) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bank Receipt',
                      style: AppTextStyles.h6.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        submission.receiptPhotoUrl,
                        height: 200,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Container(
                            height: 200,
                            alignment: Alignment.center,
                            child: CircularProgressIndicator(
                              value: loadingProgress.expectedTotalBytes != null
                                  ? loadingProgress.cumulativeBytesLoaded /
                                      loadingProgress.expectedTotalBytes!
                                  : null,
                            ),
                          );
                        },
                        errorBuilder: (_, __, ___) => Container(
                          height: 200,
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Icon(
                              Icons.broken_image,
                              size: 48,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Notes
            if (submission.notes != null && submission.notes!.isNotEmpty) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Notes',
                      style: AppTextStyles.h6.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      submission.notes!,
                      style: AppTextStyles.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildDenominationRow(String label, int count, int denomination) {
    if (count == 0) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;

    final subtotal = count * denomination;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outline),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getDenominationColor(denomination).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: _getDenominationColor(denomination).withOpacity(0.3),
                  ),
                ),
                child: Text(
                  label,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.bold,
                    color: _getDenominationColor(denomination),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$count notes',
                style: AppTextStyles.bodyMedium,
              ),
            ],
          ),
          Text(
            Formatters.currency(subtotal.toDouble()),
            style: AppTextStyles.bodyLarge.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleApprove(CashSubmission submission) async {
    try {
      final cashNotifier = ref.read(cashNotifierProvider.notifier);
      final success = await cashNotifier.approveSubmission(submission.id);

      if (success) {
        SnackbarHelper.showSuccess(context, 'Submission approved!');
        ref.invalidate(pendingSubmissionsProvider);
      } else {
        SnackbarHelper.showError(context, 'Failed to approve submission');
      }
    } catch (e) {
      SnackbarHelper.showError(context, e.toString());
    }
  }

  Future<void> _showRejectDialog(CashSubmission submission) async {
    final reasonController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Reject Submission', style: AppTextStyles.h5),
        content: TextField(
          controller: reasonController,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: 'Reason for rejection',
            hintText: 'Explain why this is being rejected...',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: AppTextStyles.button.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _handleReject(submission, reasonController.text);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleReject(CashSubmission submission, String reason) async {
    if (reason.trim().isEmpty) {
      SnackbarHelper.showError(context, 'Please provide a reason for rejection');
      return;
    }

    try {
      final cashNotifier = ref.read(cashNotifierProvider.notifier);
      final success = await cashNotifier.rejectSubmission(submission.id, reason);

      if (success) {
        SnackbarHelper.showSuccess(context, 'Submission rejected');
        ref.invalidate(pendingSubmissionsProvider);
      } else {
        SnackbarHelper.showError(context, 'Failed to reject submission');
      }
    } catch (e) {
      SnackbarHelper.showError(context, e.toString());
    }
  }

  // Collection-specific handlers
  Future<void> _handleApproveCollection(CashCollection collection) async {
    try {
      final cashNotifier = ref.read(cashNotifierProvider.notifier);
      final success = await cashNotifier.approveCollection(collection.id);

      if (success) {
        SnackbarHelper.showSuccess(context, 'Collection approved!');
        ref.invalidate(pendingCollectionsProvider);
      } else {
        SnackbarHelper.showError(context, 'Failed to approve collection');
      }
    } catch (e) {
      SnackbarHelper.showError(context, e.toString());
    }
  }

  Future<void> _handleRejectCollection(CashCollection collection) async {
    final reasonController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Reject Collection', style: AppTextStyles.h5),
        content: TextField(
          controller: reasonController,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: 'Reason for rejection',
            hintText: 'Explain why this is being rejected...',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style:
                  AppTextStyles.button.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _doRejectCollection(collection, reasonController.text);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }

  Future<void> _doRejectCollection(
      CashCollection collection, String reason) async {
    if (reason.trim().isEmpty) {
      SnackbarHelper.showError(
          context, 'Please provide a reason for rejection');
      return;
    }

    try {
      final cashNotifier = ref.read(cashNotifierProvider.notifier);
      final success = await cashNotifier.rejectCollection(collection.id, reason);

      if (success) {
        SnackbarHelper.showSuccess(context, 'Collection rejected');
        ref.invalidate(pendingCollectionsProvider);
      } else {
        SnackbarHelper.showError(context, 'Failed to reject collection');
      }
    } catch (e) {
      SnackbarHelper.showError(context, e.toString());
    }
  }

  Color _getDenominationColor(int denomination) {
    switch (denomination) {
      case 500:
        return AppColors.exciseColor;
      case 200:
        return AppColors.warning;
      case 100:
        return AppColors.info;
      case 50:
        return AppColors.success;
      case 20:
        return AppColors.error;
      case 10:
        return AppColors.neutral;
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // Cash Requests Tab (Users requesting cash from other users)
  // ══════════════════════════════════════════════════════════════════════════════

  Widget _buildCashRequestsTab() {
    final pendingRequests =
        ref.watch(pendingCashRequestsProvider(widget.shopId));

    return pendingRequests.when(
      data: (requests) {
        if (requests.isEmpty) {
          return _buildEmptyState('No Pending Cash Requests',
              'All cash requests have been reviewed.');
        }
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(pendingCashRequestsProvider);
          },
          color: Theme.of(context).colorScheme.primary,
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: requests.length,
            separatorBuilder: (_, __) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              return _buildCashRequestCard(requests[index]);
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Text('Error: $error', style: AppTextStyles.bodyMedium),
      ),
    );
  }

  Widget _buildCashRequestCard(CashRequest request) {
    final cs = Theme.of(context).colorScheme;
    final isExpanded = _expandedCards.contains(request.id);
    final timeRemaining = request.timeRemaining;
    final isUrgent = timeRemaining != null && timeRemaining.inMinutes < 3;

    final initial = request.requester?.name.substring(0, 1).toUpperCase() ?? 'U';

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
        border: Border.all(
          color: isUrgent
              ? AppColors.error
              : cs.outline.withValues(alpha: 0.2),
          width: isUrgent ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          // Header
          InkWell(
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedCards.remove(request.id);
                } else {
                  _expandedCards.add(request.id);
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isUrgent
                    ? AppColors.error.withOpacity(0.1)
                    : cs.primary.withOpacity(0.1),
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(iOSDesignTokens.radiusMedium),
                  bottom: isExpanded ? Radius.zero : Radius.circular(iOSDesignTokens.radiusMedium),
                ),
              ),
              child: Column(
                children: [
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
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            initial,
                            style: AppTextStyles.h6.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              request.requester?.name ?? 'Unknown User',
                              style: AppTextStyles.bodyLarge.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              request.requester?.role.toUpperCase() ??
                                  'UNKNOWN',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            Formatters.currency(request.amount),
                            style: AppTextStyles.h5.copyWith(
                              fontWeight: FontWeight.bold,
                              color: isUrgent ? AppColors.error : null,
                            ),
                          ),
                          if (timeRemaining != null)
                            Text(
                              request.timeRemainingFormatted ?? '',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: isUrgent
                                    ? AppColors.error
                                    : AppColors.warning,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  if (isUrgent) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'URGENT: Request expiring soon',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Expanded Details
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (request.reason != null && request.reason!.isNotEmpty) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.notes, size: 20, color: cs.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Reason:', style: AppTextStyles.bodySmall.copyWith(
                                color: cs.onSurfaceVariant,
                              )),
                              const SizedBox(height: 4),
                              Text(request.reason!, style: AppTextStyles.bodyMedium),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  Row(
                    children: [
                      Icon(Icons.schedule, size: 20, color: cs.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Text(
                        'Requested: ${DateFormat('MMM dd, yyyy HH:mm').format(request.requestDate)}',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Action Buttons or Expired Status
                  if (request.hasExpired)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.error.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.schedule_outlined, size: 20, color: AppColors.error),
                          const SizedBox(width: 8),
                          Text(
                            'This request has expired',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _showRejectCashRequestDialog(request),
                            icon: const Icon(Icons.close, size: 16),
                            label: const Text('Reject', maxLines: 1, overflow: TextOverflow.ellipsis),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.error,
                              side: BorderSide(color: AppColors.error),
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _approveCashRequest(request),
                            icon: const Icon(Icons.check, size: 16),
                            label: const Text('Approve', maxLines: 1, overflow: TextOverflow.ellipsis),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.success,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _approveCashRequest(CashRequest request) async {
    try {
      final cashNotifier = ref.read(cashNotifierProvider.notifier);
      final success = await cashNotifier.approveCashRequest(request.id);

      if (success && mounted) {
        SnackbarHelper.showSuccess(
          context,
          'Cash request approved successfully',
        );
        ref.invalidate(pendingCashRequestsProvider);
      } else if (mounted) {
        SnackbarHelper.showError(
          context,
          'Failed to approve cash request',
        );
      }
    } catch (e) {
      if (mounted) {
        SnackbarHelper.showError(
          context,
          'Error: ${e.toString()}',
        );
      }
    }
  }

  Future<void> _showRejectCashRequestDialog(CashRequest request) async {
    final reasonController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Cash Request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Are you sure you want to reject this request from ${request.requester?.name}?',
              style: AppTextStyles.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Rejection Reason (Required)',
                hintText: 'Enter reason for rejection...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (reasonController.text.trim().isEmpty) {
                SnackbarHelper.showError(
                  context,
                  'Please provide a reason for rejection',
                );
                return;
              }
              Navigator.pop(context, true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      try {
        final cashNotifier = ref.read(cashNotifierProvider.notifier);
        final success = await cashNotifier.rejectCashRequest(
          request.id,
          reasonController.text.trim(),
        );

        if (success && mounted) {
          SnackbarHelper.showSuccess(
            context,
            'Cash request rejected',
          );
          ref.invalidate(pendingCashRequestsProvider);
        } else if (mounted) {
          SnackbarHelper.showError(
            context,
            'Failed to reject cash request',
          );
        }
      } catch (e) {
        if (mounted) {
          SnackbarHelper.showError(
            context,
            'Error: ${e.toString()}',
          );
        }
      }
    }

    reasonController.dispose();
  }
}
