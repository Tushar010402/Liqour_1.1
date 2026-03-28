import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as provider_pkg;
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/theme/ios_design_tokens.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../providers/cash_provider.dart';
import '../models/cash_models.dart';
import '../services/cash_service.dart';
import '../widgets/submit_cash_form_widget.dart';

/// Unified Bank Submissions Screen - FAB + List Pattern (matches Cash Requests)
/// Two tabs: My Submissions (by me) and Awaiting Approval (for admins/managers)
class UnifiedBankSubmissionsScreen extends ConsumerStatefulWidget {
  final String shopId;

  const UnifiedBankSubmissionsScreen({super.key, required this.shopId});

  @override
  ConsumerState<UnifiedBankSubmissionsScreen> createState() => _UnifiedBankSubmissionsScreenState();
}

class _UnifiedBankSubmissionsScreenState extends ConsumerState<UnifiedBankSubmissionsScreen>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;
  String? _currentUserId;
  String? _currentUserRole;
  String _selectedStatus = 'all'; // 'all', 'pending', 'approved', 'rejected'

  // Auto-refresh timer for real-time updates
  Timer? _autoRefreshTimer;
  static const _refreshInterval = Duration(seconds: 10);

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _startAutoRefresh();
  }

  Future<void> _loadUserInfo() async {
    final authService = provider_pkg.Provider.of<AuthService>(context, listen: false);
    final userId = await authService.getUserId();
    final role = await authService.getUserRole();
    if (mounted) {
      setState(() {
        _currentUserId = userId;
        _currentUserRole = role;
        // Create TabController after knowing if user can approve
        final canApprove = role == 'admin' || role == 'manager';
        _tabController = TabController(length: canApprove ? 2 : 1, vsync: this);
      });
    }
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(_refreshInterval, (_) {
      if (mounted) {
        // Silently refresh data - provider will update UI automatically
        ref.invalidate(submissionsProvider);
        ref.invalidate(pendingSubmissionsProvider);
      }
    });
  }

  bool get _canApprove => _currentUserRole == 'admin' || _currentUserRole == 'manager';

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _tabController?.dispose();
    super.dispose();
  }

  void _refreshData() {
    HapticFeedback.lightImpact();
    ref.invalidate(submissionsProvider);
    ref.invalidate(pendingSubmissionsProvider);
  }

  /// Show the Submit to Bank form in a modern bottom sheet modal
  void _showSubmitCashBottomSheet() {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Close button and title
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox(width: 48),
                    Text(
                      'Submit to Bank',
                      style: AppTextStyles.h5.copyWith(fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                      color: cs.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
              const Divider(),
              // Submit Cash Form - embedded as scrollable content
              Expanded(
                child: SubmitCashFormWidget(
                  shopId: widget.shopId,
                  onSubmitSuccess: () {
                    Navigator.pop(context);
                    _refreshData();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Show loading until user info is loaded
    if (_tabController == null) {
      return Scaffold(
        backgroundColor: cs.surface,
        appBar: const CustomAppBar(title: 'Bank Submissions'),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // Watch pending count for badge (for admins/managers)
    final pendingAsync = ref.watch(pendingSubmissionsProvider(widget.shopId));
    final pendingCount = pendingAsync.maybeWhen(
      data: (list) => list.length,
      orElse: () => 0,
    );

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: CustomAppBar(
        title: 'Bank Submissions',
        actions: [
          // Status filter menu
          PopupMenuButton<String>(
            icon: Icon(Icons.filter_list, color: cs.onSurface),
            onSelected: (value) => setState(() => _selectedStatus = value),
            itemBuilder: (context) => [
              _buildFilterMenuItem('all', 'All Submissions', Icons.all_inclusive),
              _buildFilterMenuItem('pending', 'Pending', Icons.pending_outlined),
              _buildFilterMenuItem('approved', 'Approved', Icons.check_circle_outline),
              _buildFilterMenuItem('rejected', 'Rejected', Icons.cancel_outlined),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: cs.primary,
          unselectedLabelColor: cs.onSurfaceVariant,
          indicatorColor: cs.primary,
          indicatorWeight: 3,
          tabs: [
            const Tab(
              icon: Icon(Icons.send_outlined),
              text: 'My Submissions',
            ),
            if (_canApprove)
              Tab(
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.approval_outlined),
                    if (pendingCount > 0)
                      Positioned(
                        right: -8,
                        top: -4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.error,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$pendingCount',
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
                text: 'To Approve',
              ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: My Submissions
          _buildMySubmissionsTab(),
          // Tab 2: Awaiting Approval (for admins/managers)
          if (_canApprove) _buildAwaitingApprovalTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showSubmitCashBottomSheet,
        backgroundColor: cs.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text(
          'New Deposit',
          style: AppTextStyles.bodyMedium.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        elevation: 4,
      ),
    );
  }

  PopupMenuItem<String> _buildFilterMenuItem(String value, String label, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = _selectedStatus == value;
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(
            icon,
            color: isSelected ? cs.primary : cs.onSurfaceVariant,
            size: 20,
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: AppTextStyles.bodyMedium.copyWith(
              color: isSelected ? cs.primary : cs.onSurface,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          if (isSelected) ...[
            const Spacer(),
            Icon(Icons.check, color: cs.primary, size: 20),
          ],
        ],
      ),
    );
  }

  Widget _buildMySubmissionsTab() {
    // Filter by selected status
    final status = _selectedStatus == 'all' ? null : _selectedStatus;

    final submissionsAsync = ref.watch(
      submissionsProvider(SubmissionsQuery(
        userId: _currentUserId,
        status: status,
        limit: 100,
      )),
    );

    return submissionsAsync.when(
      data: (submissions) {
        if (submissions.isEmpty) {
          return _buildEmptyState(isMySubmissions: true);
        }

        final cs = Theme.of(context).colorScheme;
        return RefreshIndicator(
          onRefresh: () async => _refreshData(),
          color: cs.primary,
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: submissions.length,
            itemBuilder: (context, index) {
              return _SubmissionCard(
                submission: submissions[index],
                canApprove: false, // Can't approve own submissions
                onRefresh: _refreshData,
                cashService: ref.read(cashServiceProvider),
              );
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _buildErrorState(error.toString()),
    );
  }

  Widget _buildAwaitingApprovalTab() {
    // Always show pending submissions from all users (excluding current user)
    final submissionsAsync = ref.watch(pendingSubmissionsProvider(widget.shopId));

    return submissionsAsync.when(
      data: (submissions) {
        // Filter out own submissions
        final filteredSubmissions = submissions
            .where((s) => s.userId != _currentUserId)
            .toList();

        if (filteredSubmissions.isEmpty) {
          return _buildEmptyState(isMySubmissions: false);
        }

        final cs = Theme.of(context).colorScheme;
        return RefreshIndicator(
          onRefresh: () async => _refreshData(),
          color: cs.primary,
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: filteredSubmissions.length,
            itemBuilder: (context, index) {
              return _SubmissionCard(
                submission: filteredSubmissions[index],
                canApprove: true,
                onRefresh: _refreshData,
                cashService: ref.read(cashServiceProvider),
              );
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _buildErrorState(error.toString()),
    );
  }

  Widget _buildEmptyState({required bool isMySubmissions}) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isMySubmissions ? Icons.receipt_long_outlined : Icons.approval_outlined,
                size: 48,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isMySubmissions
                ? 'No submissions yet'
                : 'No pending approvals',
              style: AppTextStyles.h5.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Text(
              isMySubmissions
                ? 'Tap "New Deposit" to submit cash to bank'
                : 'All bank deposits have been reviewed',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            if (isMySubmissions) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _showSubmitCashBottomSheet,
                icon: const Icon(Icons.add),
                label: const Text('New Deposit'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: cs.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              'Failed to load submissions',
              style: AppTextStyles.bodyLarge.copyWith(color: cs.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              error.split(':').last.trim(),
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _refreshData,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Individual submission card with approve/reject capabilities
class _SubmissionCard extends StatefulWidget {
  final CashSubmission submission;
  final bool canApprove;
  final VoidCallback onRefresh;
  final CashService cashService;

  const _SubmissionCard({
    required this.submission,
    required this.canApprove,
    required this.onRefresh,
    required this.cashService,
  });

  @override
  State<_SubmissionCard> createState() => _SubmissionCardState();
}

class _SubmissionCardState extends State<_SubmissionCard> {
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final submission = widget.submission;
    final isPending = submission.status.toLowerCase() == 'pending';
    final showActions = widget.canApprove && isPending;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
        border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.vertical(top: Radius.circular(iOSDesignTokens.radiusMedium)),
            onTap: () => _showSubmissionDetails(context),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header: Amount and Status
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        Formatters.currency(submission.totalAmount),
                        style: AppTextStyles.h4.copyWith(
                          fontWeight: FontWeight.bold,
                          color: cs.onSurface,
                        ),
                      ),
                      _buildStatusBadge(),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // User info (for admin view)
                  if (submission.userName.isNotEmpty && widget.canApprove)
                    _buildInfoRow(
                      icon: Icons.person_outline,
                      label: 'Submitted by',
                      value: submission.userName,
                    ),

                  // Shop name
                  if (submission.shopName.isNotEmpty)
                    _buildInfoRow(
                      icon: Icons.store_outlined,
                      label: 'Shop',
                      value: submission.shopName,
                    ),

                  // Deposit date
                  if (submission.depositDate != null)
                    _buildInfoRow(
                      icon: Icons.calendar_today_outlined,
                      label: 'Deposit Date',
                      value: DateFormat('MMM dd, yyyy').format(submission.depositDate!),
                    ),

                  // Bank slip number
                  if (submission.bankSlipNumber != null && submission.bankSlipNumber!.isNotEmpty)
                    _buildInfoRow(
                      icon: Icons.receipt_outlined,
                      label: 'Slip #',
                      value: submission.bankSlipNumber!,
                    ),

                  // Receipt indicator
                  if (submission.receiptPhotoUrl.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.image, size: 14, color: AppColors.success),
                          const SizedBox(width: 4),
                          Text(
                            'Receipt Attached',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.success,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Rejection reason
                  if (submission.status == 'rejected' && submission.rejectionReason != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline, size: 16, color: AppColors.error),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Rejection Reason',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.error,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  submission.rejectionReason!,
                                  style: TextStyle(fontSize: 13, color: AppColors.error),
                                ),
                              ],
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

          // Action buttons for pending submissions
          if (showActions) ...[
            Divider(height: 1, color: cs.outline.withValues(alpha: 0.2)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(iOSDesignTokens.radiusMedium)),
              ),
              child: _isProcessing
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: TextButton.icon(
                            onPressed: () => _showSubmissionDetails(context),
                            icon: const Icon(Icons.visibility_outlined, size: 18),
                            label: const Text('Details'),
                            style: TextButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _showRejectDialog(context),
                            icon: const Icon(Icons.close, size: 18),
                            label: const Text('Reject'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.error,
                              side: BorderSide(color: AppColors.error),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _handleApprove(context),
                            icon: const Icon(Icons.check, size: 18),
                            label: const Text('Approve'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.success,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusBadge() {
    Color bgColor;
    Color textColor;
    IconData icon;

    switch (widget.submission.status.toLowerCase()) {
      case 'approved':
        bgColor = AppColors.success.withOpacity(0.15);
        textColor = AppColors.success;
        icon = Icons.check_circle;
        break;
      case 'rejected':
        bgColor = AppColors.error.withOpacity(0.15);
        textColor = AppColors.error;
        icon = Icons.cancel;
        break;
      default:
        bgColor = AppColors.warning.withOpacity(0.15);
        textColor = AppColors.warning;
        icon = Icons.pending;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 4),
          Text(
            widget.submission.status.toUpperCase(),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textColor),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({required IconData icon, required String label, required String value}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Text('$label: ', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 13, color: cs.onSurface, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleApprove(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.check_circle, color: AppColors.success),
            const SizedBox(width: 12),
            const Text('Approve Submission'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Are you sure you want to approve this deposit?'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Text('Amount: '),
                  Text(
                    Formatters.currency(widget.submission.totalAmount),
                    style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.success, fontSize: 18),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.check),
            label: const Text('Approve'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isProcessing = true);
    HapticFeedback.mediumImpact();

    try {
      await widget.cashService.approveSubmission(widget.submission.id);

      if (mounted) {
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('Submission approved successfully'),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
        widget.onRefresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('Failed: ${e.toString().split(':').last.trim()}')),
              ],
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showRejectDialog(BuildContext context) {
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.cancel, color: AppColors.error),
            const SizedBox(width: 12),
            const Text('Reject Submission'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Text('Amount: '),
                  Text(
                    Formatters.currency(widget.submission.totalAmount),
                    style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.error, fontSize: 18),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Rejection Reason *',
                hintText: 'Please provide a reason...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton.icon(
            onPressed: () {
              final reason = reasonController.text.trim();
              if (reason.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please provide a rejection reason'), backgroundColor: Colors.orange),
                );
                return;
              }
              Navigator.pop(ctx, reason);
            },
            icon: const Icon(Icons.close),
            label: const Text('Reject'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
          ),
        ],
      ),
    ).then((reason) {
      if (reason != null && reason is String && reason.isNotEmpty) {
        _handleReject(context, reason);
      }
    });
  }

  Future<void> _handleReject(BuildContext context, String reason) async {
    setState(() => _isProcessing = true);
    HapticFeedback.mediumImpact();

    try {
      await widget.cashService.rejectSubmission(widget.submission.id, reason);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.info, color: Colors.white),
                SizedBox(width: 12),
                Text('Submission rejected'),
              ],
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
        widget.onRefresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('Failed: ${e.toString().split(':').last.trim()}')),
              ],
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showSubmissionDetails(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final submission = widget.submission;
    final isPending = submission.status.toLowerCase() == 'pending';
    final showActions = widget.canApprove && isPending;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.3,
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
                decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text('Submission Details', style: AppTextStyles.h5),
                    const Spacer(),
                    _buildStatusBadge(),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildDetailSection('Amount', Formatters.currency(submission.totalAmount)),
                    if (submission.userName.isNotEmpty) _buildDetailSection('Submitted By', submission.userName),
                    _buildDetailSection('Shop', submission.shopName),
                    if (submission.depositDate != null)
                      _buildDetailSection('Deposit Date', DateFormat('MMMM dd, yyyy').format(submission.depositDate!)),
                    if (submission.bankSlipNumber != null) _buildDetailSection('Bank Slip #', submission.bankSlipNumber!),
                    _buildDetailSection('Status', submission.status.toUpperCase()),
                    if (submission.notes != null && submission.notes!.isNotEmpty)
                      _buildDetailSection('Notes', submission.notes!),
                    if (submission.rejectionReason != null && submission.rejectionReason!.isNotEmpty)
                      _buildDetailSection('Rejection Reason', submission.rejectionReason!),

                    // Receipt image
                    if (submission.receiptPhotoUrl.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text('Bank Receipt', style: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurfaceVariant)),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: () => _showFullScreenImage(context, submission.receiptPhotoUrl),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            submission.receiptPhotoUrl,
                            height: 200,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (c, e, s) => Container(
                              height: 200,
                              color: cs.outlineVariant,
                              child: const Center(child: Icon(Icons.broken_image, size: 48)),
                            ),
                          ),
                        ),
                      ),
                    ],

                    // Denomination breakdown
                    const SizedBox(height: 20),
                    Text('Denomination Breakdown', style: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurfaceVariant)),
                    const SizedBox(height: 12),
                    _buildDenominationTable(),

                    // Actions
                    if (showActions) ...[
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(sheetContext);
                                _showRejectDialog(context);
                              },
                              icon: const Icon(Icons.close),
                              label: const Text('Reject'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.error,
                                side: BorderSide(color: AppColors.error, width: 2),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(sheetContext);
                                _handleApprove(context);
                              },
                              icon: const Icon(Icons.check),
                              label: const Text('Approve'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.success,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailSection(String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  void _showFullScreenImage(BuildContext context, String imageUrl) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: const Text('Bank Receipt'),
          ),
          body: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: Center(
              child: Image.network(imageUrl, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDenominationTable() {
    final cs = Theme.of(context).colorScheme;
    final submission = widget.submission;
    final denominations = [
      ('₹500', submission.notes500, submission.notes500 * 500),
      ('₹200', submission.notes200, submission.notes200 * 200),
      ('₹100', submission.notes100, submission.notes100 * 100),
      ('₹50', submission.notes50, submission.notes50 * 50),
      ('₹20', submission.notes20, submission.notes20 * 20),
      ('₹10', submission.notes10, submission.notes10 * 10),
    ];

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: cs.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
            ),
            child: const Row(
              children: [
                Expanded(flex: 2, child: Text('Note', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                Expanded(child: Text('Count', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                Expanded(flex: 2, child: Text('Value', textAlign: TextAlign.end, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
              ],
            ),
          ),
          const Divider(height: 1),
          ...denominations.where((d) => d.$2 > 0).map((denom) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Expanded(flex: 2, child: Text(denom.$1)),
                    Expanded(child: Text('×${denom.$2}', textAlign: TextAlign.center)),
                    Expanded(flex: 2, child: Text(Formatters.currency(denom.$3.toDouble()), textAlign: TextAlign.end)),
                  ],
                ),
              )),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(7)),
            ),
            child: Row(
              children: [
                const Expanded(flex: 2, child: Text('Total', style: TextStyle(fontWeight: FontWeight.bold))),
                const Expanded(child: SizedBox()),
                Expanded(
                  flex: 2,
                  child: Text(
                    Formatters.currency(submission.totalAmount),
                    textAlign: TextAlign.end,
                    style: TextStyle(fontWeight: FontWeight.bold, color: cs.primary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
