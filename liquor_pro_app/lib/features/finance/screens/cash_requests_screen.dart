import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/theme/ios_design_tokens.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../providers/cash_provider.dart';
import '../models/cash_models.dart';
import '../widgets/cash_request_countdown_widget.dart';
import 'request_cash_screen.dart';

/// Cash Requests Management Screen - Industrial Grade Request Tracking
/// Two tabs: Sent Requests (by me) and Received Requests (from others to me)
class CashRequestsScreen extends ConsumerStatefulWidget {
  final String? shopId;

  const CashRequestsScreen({super.key, this.shopId});

  @override
  ConsumerState<CashRequestsScreen> createState() => _CashRequestsScreenState();
}

class _CashRequestsScreenState extends ConsumerState<CashRequestsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedStatus = 'all'; // 'all', 'pending', 'approved', 'rejected'

  // Auto-refresh timer for real-time updates
  Timer? _autoRefreshTimer;
  static const _refreshInterval = Duration(seconds: 10);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _startAutoRefresh();
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(_refreshInterval, (_) {
      if (mounted) {
        // Silently refresh data - provider will update UI automatically
        ref.invalidate(cashRequestsProvider);
      }
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  /// Show the Request Cash form in a modern bottom sheet modal
  void _showRequestCashBottomSheet() {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
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
                      'Request Cash',
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
              // Request Cash Form - embedded as scrollable content
              Expanded(
                child: RequestCashScreen(
                  scrollController: scrollController,
                  isEmbedded: true,
                  onSuccess: () {
                    Navigator.pop(context);
                    ref.invalidate(cashRequestsProvider);
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
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: CustomAppBar(
        title: 'Cash Requests',
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.filter_list, color: cs.onSurface),
            onSelected: (value) => setState(() => _selectedStatus = value),
            itemBuilder: (context) => [
              _buildFilterMenuItem('all', 'All Requests', Icons.all_inclusive),
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
          tabs: const [
            Tab(
              icon: Icon(Icons.send_outlined),
              text: 'Sent Requests',
            ),
            Tab(
              icon: Icon(Icons.inbox_outlined),
              text: 'Received Requests',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSentRequestsTab(),
          _buildReceivedRequestsTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showRequestCashBottomSheet,
        backgroundColor: cs.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text(
          'New Request',
          style: AppTextStyles.bodyMedium.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        elevation: 4,
      ),
    );
  }

  PopupMenuItem<String> _buildFilterMenuItem(
      String value, String label, IconData icon) {
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
            Icon(Icons.check, color: cs.primary, size: 18),
          ],
        ],
      ),
    );
  }

  Widget _buildSentRequestsTab() {
    final query = CashRequestsQuery(
      shopId: null, // Show all requests across all shops
      status: _selectedStatus == 'all' ? null : _selectedStatus,
      filterType: 'sent', // Only requests sent by current user
    );

    final requestsAsync = ref.watch(cashRequestsProvider(query));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(cashRequestsProvider(query));
      },
      child: requestsAsync.when(
        data: (requests) {
          if (requests.isEmpty) {
            return _buildEmptyState(
              icon: Icons.send_outlined,
              title: 'No Sent Requests',
              message: _selectedStatus == 'all'
                  ? 'You haven\'t sent any cash requests yet.\nTap the button below to request cash from your team.'
                  : 'No $_selectedStatus requests found.',
            );
          }
          return _buildRequestsList(requests, isSentTab: true);
        },
        // Don't show loading spinner on auto-refresh, show subtle indicator
        loading: () => _buildLoadingWithIndicator(),
        error: (error, _) => _buildErrorState(error.toString(), query),
      ),
    );
  }

  Widget _buildReceivedRequestsTab() {
    final query = CashRequestsQuery(
      shopId: null, // Show all requests across all shops
      status: _selectedStatus == 'all' ? null : _selectedStatus,
      filterType: 'received', // Only requests received by current user
    );

    final requestsAsync = ref.watch(cashRequestsProvider(query));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(cashRequestsProvider(query));
      },
      child: requestsAsync.when(
        data: (requests) {
          if (requests.isEmpty) {
            return _buildEmptyState(
              icon: Icons.inbox_outlined,
              title: 'No Received Requests',
              message: _selectedStatus == 'all'
                  ? 'You don\'t have any cash requests from your team yet.'
                  : 'No $_selectedStatus requests found.',
            );
          }
          return _buildRequestsList(requests, isSentTab: false);
        },
        // Don't show loading spinner on auto-refresh, show subtle indicator
        loading: () => _buildLoadingWithIndicator(),
        error: (error, _) => _buildErrorState(error.toString(), query),
      ),
    );
  }

  Widget _buildLoadingWithIndicator() {
    return Column(
      children: [
        // Show auto-refresh indicator at top
        _buildAutoRefreshIndicator(),
        // Show loading content
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text(
                  'Loading requests...',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRequestsList(List<CashRequest> requests, {required bool isSentTab}) {
    return Column(
      children: [
        // Auto-refresh indicator at the top
        _buildAutoRefreshIndicator(),
        // List of requests
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: requests.length,
            itemBuilder: (context, index) {
              final request = requests[index];
              return _buildRequestCard(request, isSentTab: isSentTab);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAutoRefreshIndicator() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: cs.primary.withValues(alpha: 0.05),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.sync,
            size: 14,
            color: cs.primary.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 6),
          Text(
            'Live updates every 10s',
            style: AppTextStyles.bodySmall.copyWith(
              color: cs.primary.withValues(alpha: 0.7),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: AppColors.success,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.success.withOpacity(0.5),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestCard(CashRequest request, {required bool isSentTab}) {
    final cs = Theme.of(context).colorScheme;
    // Compute the actual display status (prioritize "expired" if time has passed)
    final displayStatus = _getDisplayStatus(request);
    final isPending = displayStatus.toLowerCase() == 'pending';
    final isApproved = displayStatus.toLowerCase() == 'approved';
    final isRejected = displayStatus.toLowerCase() == 'rejected';
    final isExpired = displayStatus.toLowerCase() == 'expired';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
        border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Avatar + Name + Status
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [cs.primary, cs.primary.withValues(alpha: 0.7)],
                    ),
                    borderRadius: BorderRadius.circular(iOSDesignTokens.radiusSmall),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    isSentTab
                        ? (request.requestedFrom?.name ?? 'U').substring(0, 1).toUpperCase()
                        : (request.requester?.name ?? 'U').substring(0, 1).toUpperCase(),
                    style: AppTextStyles.h6.copyWith(
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isSentTab
                            ? 'To: ${request.requestedFrom?.name ?? 'Unknown'}'
                            : 'From: ${request.requester?.name ?? 'Unknown'}',
                        style: AppTextStyles.bodyLarge.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.store, size: 14, color: cs.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text(
                            'Shop Request',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                _buildStatusChip(displayStatus),
              ],
            ),

            const Divider(height: 24),

            // Amount
            Row(
              children: [
                Icon(Icons.currency_rupee, color: cs.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Amount:',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '₹${NumberFormat('#,##,##0.00').format(request.amount)}',
                  style: AppTextStyles.h5.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            // Reason (if provided)
            if (request.reason != null && request.reason!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.note_outlined, size: 16, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        request.reason!,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: cs.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Timestamps
            _buildTimestampRow('Created', request.createdAt),
            if (isPending && request.expiresAt != null) ...[
              const SizedBox(height: 8),
              CashRequestCountdownWidget(
                request: request,
                onExpired: () {
                  // Refresh the requests list when countdown expires
                  ref.invalidate(cashRequestsProvider);
                },
              ),
            ],
            if (isApproved && request.approvedAt != null) ...[
              const SizedBox(height: 8),
              _buildTimestampRow('Approved', request.approvedAt!),
            ],
            if (isRejected && request.rejectedAt != null) ...[
              const SizedBox(height: 8),
              _buildTimestampRow('Rejected', request.rejectedAt!),
              if (request.rejectReason != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.error.withOpacity(0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 16, color: AppColors.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Reason: ${request.rejectReason}',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],

            // Action Buttons (only for received requests that are pending and not expired)
            if (!isSentTab && isPending && !isExpired && !request.hasExpired) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _handleApprove(request),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.check_circle, size: 20),
                      label: Text('Approve', style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _handleReject(request),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.cancel, size: 20),
                      label: Text('Reject', style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ],

            // Show expired message ONLY for pending requests that expired
            // (not for approved/rejected requests)
            if (!isSentTab && isExpired) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
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
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    final color = _getStatusColor(status);
    final icon = _getStatusIcon(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            status.toUpperCase(),
            style: AppTextStyles.bodySmall.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimestampRow(String label, DateTime timestamp) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.schedule, size: 14, color: cs.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          '$label:',
          style: AppTextStyles.bodySmall.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          DateFormat('MMM dd, yyyy • hh:mm a').format(timestamp.toLocal()),
          style: AppTextStyles.bodySmall.copyWith(
            color: cs.onSurface,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String message,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 80, color: cs.onSurfaceVariant),
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

  Widget _buildErrorState(String error, CashRequestsQuery query) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 80, color: AppColors.error),
            const SizedBox(height: 16),
            Text('Error Loading Requests', style: AppTextStyles.h4),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => ref.invalidate(cashRequestsProvider(query)),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleApprove(CashRequest request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve Cash Request'),
        content: Text(
          'Are you sure you want to approve this request for ₹${NumberFormat('#,##,##0.00').format(request.amount)} from ${request.requester?.name ?? 'Unknown'}?',
          style: AppTextStyles.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
            ),
            child: const Text('Approve'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final cashNotifier = ref.read(cashNotifierProvider.notifier);
      final success = await cashNotifier.approveCashRequest(request.id);

      if (success && mounted) {
        SnackbarHelper.showSuccess(
          context,
          'Cash request approved successfully!',
        );
        // Refresh both tabs
        ref.invalidate(cashRequestsProvider);
      }
    } catch (e) {
      if (mounted) {
        SnackbarHelper.showError(context, e.toString());
      }
    }
  }

  Future<void> _handleReject(CashRequest request) async {
    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Cash Request'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Reject request for ₹${NumberFormat('#,##,##0.00').format(request.amount)} from ${request.requester?.name ?? 'Unknown'}?',
                style: AppTextStyles.bodyMedium,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: reasonController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Rejection Reason',
                  hintText: 'Please provide a reason for rejection',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please provide a reason';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, true);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

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
        // Refresh both tabs
        ref.invalidate(cashRequestsProvider);
      }
    } catch (e) {
      if (mounted) {
        SnackbarHelper.showError(context, e.toString());
      }
    } finally {
      reasonController.dispose();
    }
  }

  /// Get the display status for a request
  /// Only show "EXPIRED" for pending requests that passed the deadline
  /// If approved/rejected, always show that status (action was taken)
  String _getDisplayStatus(CashRequest request) {
    final status = request.status.toLowerCase();

    // If already approved or rejected, show that status (action was taken)
    if (status == 'approved' || status == 'rejected') {
      return request.status;
    }

    // If pending and expired, show "expired" (no action was taken)
    if (status == 'pending' && request.hasExpired) {
      return 'expired';
    }

    // Otherwise, show the backend status
    return request.status;
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return AppColors.warning;
      case 'approved':
        return AppColors.success;
      case 'rejected':
        return AppColors.error;
      case 'expired':
        return AppColors.neutral;
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Icons.pending_outlined;
      case 'approved':
        return Icons.check_circle;
      case 'rejected':
        return Icons.cancel;
      case 'expired':
        return Icons.timer_off;
      default:
        return Icons.help_outline;
    }
  }
}
