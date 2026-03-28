import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/config/api_config.dart';
import '../models/daily_sales_models.dart';
import '../services/daily_sales_service.dart';
import 'daily_sales_entry_screen.dart';

/// Normalize image URL to ensure it has a host
String _normalizeImageUrl(String url) {
  if (url.isEmpty) return url;
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  if (url.startsWith('/')) return '${ApiConfig.baseUrl}$url';
  return url;
}

/// Salesman's personal sales history - Industrial Grade Implementation
/// Features: Image gallery, Edit/Cancel for pending, Full details view
class SalesmanSalesHistoryScreen extends StatefulWidget {
  const SalesmanSalesHistoryScreen({super.key});

  @override
  State<SalesmanSalesHistoryScreen> createState() => _SalesmanSalesHistoryScreenState();
}

class _SalesmanSalesHistoryScreenState extends State<SalesmanSalesHistoryScreen> {
  _TimePeriod _selectedPeriod = _TimePeriod.sevenDays;
  bool _isLoading = false;
  List<DailySalesRecord> _records = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMyRecords());
  }

  Future<void> _loadMyRecords() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authService = context.read<AuthService>();
      final service = DailySalesService(authService);
      final dateRange = _getDateRange();

      final response = await service.getDailySalesRecords(
        startDate: dateRange.start,
        endDate: dateRange.end,
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
          if (response.success && response.data != null) {
            _records = response.data!;
          } else {
            _errorMessage = response.error ?? 'Failed to load records';
            _records = [];
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Error: $e';
          _records = [];
        });
      }
    }
  }

  _DateRange _getDateRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    switch (_selectedPeriod) {
      case _TimePeriod.today:
        return _DateRange(
          start: today,
          end: today.add(const Duration(days: 1)),
        );
      case _TimePeriod.sevenDays:
        return _DateRange(
          start: today.subtract(const Duration(days: 6)),
          end: today.add(const Duration(days: 1)),
        );
      case _TimePeriod.fifteenDays:
        return _DateRange(
          start: today.subtract(const Duration(days: 14)),
          end: today.add(const Duration(days: 1)),
        );
      case _TimePeriod.oneMonth:
        return _DateRange(
          start: DateTime(now.year, now.month - 1, now.day),
          end: today.add(const Duration(days: 1)),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: cs.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'My Sales History',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 18,
            color: cs.onSurface,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          _buildPeriodFilter(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadMyRecords,
              color: cs.primary,
              child: _buildContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodFilter() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.calendar, color: cs.primary, size: 18),
              const SizedBox(width: 8),
              Text(
                'Time Period',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _TimePeriod.values.map((period) {
                final isSelected = _selectedPeriod == period;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _buildFilterChip(
                    label: period.label,
                    isSelected: isSelected,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedPeriod = period);
                      _loadMyRecords();
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? cs.primary : cs.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? cs.primary : cs.outlineVariant,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected ? Colors.white : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) return _buildLoadingState();
    if (_errorMessage != null) return _buildErrorState();
    if (_records.isEmpty) return _buildEmptyState();
    return _buildRecordsList();
  }

  Widget _buildLoadingState() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(cs.primary)),
          const SizedBox(height: 16),
          Text('Loading your sales...', style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(CupertinoIcons.exclamationmark_circle, size: 64, color: AppColors.error.withValues(alpha: 0.7)),
            const SizedBox(height: 16),
            Text('Oops! Something went wrong', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: cs.onSurface)),
            const SizedBox(height: 8),
            Text(_errorMessage ?? 'Unknown error', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadMyRecords,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.2),
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: Icon(CupertinoIcons.doc_text, size: 40, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)),
              ),
              const SizedBox(height: 20),
              Text('No Sales Records', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
              const SizedBox(height: 8),
              Text(
                'You haven\'t submitted any sales\nfor ${_selectedPeriod.label.toLowerCase()}',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.4),
              ),
              const SizedBox(height: 24),
              TextButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Create New Sale'),
                style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.primary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRecordsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _records.length,
      itemBuilder: (context, index) => _buildRecordCard(_records[index]),
    );
  }

  Widget _buildRecordCard(DailySalesRecord record) {
    final cs = Theme.of(context).colorScheme;
    final isPending = record.status.toLowerCase() == 'pending';
    final isRejected = record.status.toLowerCase() == 'rejected';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          // Main Card Content
          InkWell(
            onTap: () => _showRecordDetails(record),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: _getStatusColor(record.status).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(_getStatusIcon(record.status), color: _getStatusColor(record.status), size: 20),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                Formatters.dateOnly(record.recordDate),
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: cs.onSurface),
                              ),
                              const SizedBox(height: 2),
                              Text(record.shopName ?? 'Shop', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                            ],
                          ),
                        ],
                      ),
                      _buildStatusBadge(record.status),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Image Preview (if images exist)
                  if (record.hasImages) _buildImagePreview(record.imageUrls),

                  // Stats Row
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      children: [
                        Expanded(child: _buildStatItem(icon: CupertinoIcons.cube_box, label: 'Items', value: '${record.items.length}')),
                        Container(height: 30, width: 1, color: cs.outlineVariant),
                        Expanded(
                          child: _buildStatItem(
                            icon: CupertinoIcons.money_dollar_circle,
                            label: 'Total',
                            value: Formatters.currency(record.totalSalesAmount),
                            valueColor: AppColors.success,
                          ),
                        ),
                        if (record.hasImages) ...[
                          Container(height: 30, width: 1, color: cs.outlineVariant),
                          Expanded(
                            child: _buildStatItem(
                              icon: CupertinoIcons.photo,
                              label: 'Images',
                              value: '${record.imageUrls.length}',
                              valueColor: AppColors.info,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Rejection reason
                  if (isRejected && record.rejectionReason != null && record.rejectionReason!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          Icon(CupertinoIcons.exclamationmark_triangle, size: 16, color: AppColors.error),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              record.rejectionReason!,
                              style: TextStyle(fontSize: 12, color: AppColors.error),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
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

          // Action Buttons Row (for pending records)
          if (isPending) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => _showRecordDetails(record),
                      icon: const Icon(Icons.visibility_outlined, size: 18),
                      label: const Text('View'),
                      style: TextButton.styleFrom(foregroundColor: cs.onSurface),
                    ),
                  ),
                  Container(height: 24, width: 1, color: cs.outlineVariant),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => _editRecord(record),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit'),
                      style: TextButton.styleFrom(foregroundColor: cs.primary),
                    ),
                  ),
                  Container(height: 24, width: 1, color: cs.outlineVariant),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => _cancelRecord(record),
                      icon: const Icon(Icons.cancel_outlined, size: 18),
                      label: const Text('Cancel'),
                      style: TextButton.styleFrom(foregroundColor: AppColors.error),
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

  Widget _buildImagePreview(List<String> imageUrls) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      height: 60,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: imageUrls.length > 4 ? 4 : imageUrls.length,
        itemBuilder: (context, index) {
          final isLast = index == 3 && imageUrls.length > 4;
          final imageUrl = _getFullImageUrl(imageUrls[index]);

          return Container(
            margin: const EdgeInsets.only(right: 8),
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    placeholder: (ctx, url) => Container(
                      color: cs.surfaceContainerHighest,
                      child: const Center(child: CupertinoActivityIndicator()),
                    ),
                    errorWidget: (ctx, url, error) => Container(
                      color: cs.surfaceContainerHighest,
                      child: Icon(Icons.broken_image, color: cs.onSurfaceVariant, size: 24),
                    ),
                  ),
                  if (isLast)
                    Container(
                      color: Colors.black54,
                      child: Center(
                        child: Text(
                          '+${imageUrls.length - 3}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _getFullImageUrl(String imageUrl) {
    if (imageUrl.startsWith('http')) return imageUrl;
    return '${ApiConfig.baseUrl}$imageUrl';
  }

  Widget _buildStatItem({required IconData icon, required String label, required String value, Color? valueColor}) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: cs.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: valueColor ?? cs.onSurface)),
      ],
    );
  }

  Widget _buildStatusBadge(String status) {
    final color = _getStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color, letterSpacing: 0.5),
      ),
    );
  }

  Color _getStatusColor(String status) {
    final cs = Theme.of(context).colorScheme;
    switch (status.toLowerCase()) {
      case 'approved':
        return AppColors.success;
      case 'pending':
        return AppColors.warning;
      case 'rejected':
        return AppColors.error;
      case 'cancelled':
        return cs.onSurfaceVariant;
      default:
        return cs.onSurfaceVariant;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return CupertinoIcons.check_mark_circled_solid;
      case 'pending':
        return CupertinoIcons.clock_fill;
      case 'rejected':
        return CupertinoIcons.xmark_circle_fill;
      case 'cancelled':
        return CupertinoIcons.minus_circle_fill;
      default:
        return CupertinoIcons.doc_text_fill;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EDIT RECORD - Navigate to DailySalesEntryScreen with pre-filled data
  // ═══════════════════════════════════════════════════════════════════════════
  void _editRecord(DailySalesRecord record) {
    HapticFeedback.mediumImpact();

    // Navigate to edit screen with the record data
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DailySalesEntryScreen(
          showHeader: true,
          editRecord: record,
        ),
      ),
    ).then((_) {
      // Refresh list when returning from edit
      _loadMyRecords();
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CANCEL RECORD - Show confirmation and cancel pending record
  // ═══════════════════════════════════════════════════════════════════════════
  Future<void> _cancelRecord(DailySalesRecord record) async {
    HapticFeedback.mediumImpact();

    // Show confirmation dialog
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Cancel Sales Record?'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            'This will cancel your sales record for ${Formatters.dateOnly(record.recordDate)}.\n\nThis action cannot be undone.',
            style: const TextStyle(fontSize: 14),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep It'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel Record'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Show loading
    _showLoadingDialog('Cancelling record...');

    try {
      final authService = context.read<AuthService>();
      final service = DailySalesService(authService);

      // Use delete endpoint or update status to cancelled
      final result = await service.deleteDailySalesRecord(record.id!);

      // Close loading dialog
      if (mounted) Navigator.of(context).pop();

      if (result.success) {
        // Remove from local list
        setState(() {
          _records.removeWhere((r) => r.id == record.id);
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Record cancelled successfully'),
                ],
              ),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      } else {
        _showErrorSnackBar(result.error ?? 'Failed to cancel record');
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      _showErrorSnackBar('Error: $e');
    }
  }

  void _showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final dlgCs = Theme.of(ctx).colorScheme;
        return Center(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: dlgCs.surface, borderRadius: BorderRadius.circular(12)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(message),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SHOW RECORD DETAILS - Full details modal with images
  // ═══════════════════════════════════════════════════════════════════════════
  void _showRecordDetails(DailySalesRecord record) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(2)),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _getStatusColor(record.status).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(_getStatusIcon(record.status), color: _getStatusColor(record.status), size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Daily Sales Record', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          Text(Formatters.dateTime(record.recordDate), style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    _buildStatusBadge(record.status),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Images Section (if available)
                    if (record.hasImages) ...[
                      _buildImageGallerySection(record.imageUrls),
                      const SizedBox(height: 16),
                    ],

                    // Sales Summary
                    _buildDetailSection(
                      'Sales Summary',
                      CupertinoIcons.money_dollar_circle,
                      cs.primary,
                      [
                        _buildDetailRow('Total Amount', Formatters.currency(record.totalSalesAmount)),
                        _buildDetailRow('Items', '${record.items.length} products'),
                        _buildDetailRow('Shop', record.shopName ?? record.shopId),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Payment Breakdown
                    _buildDetailSection(
                      'Payment Breakdown',
                      CupertinoIcons.creditcard,
                      AppColors.info,
                      [
                        _buildDetailRow('Cash', Formatters.currency(record.totalCashAmount)),
                        _buildDetailRow('Card', Formatters.currency(record.totalCardAmount)),
                        _buildDetailRow('UPI', Formatters.currency(record.totalUpiAmount)),
                        _buildDetailRow('Credit', Formatters.currency(record.totalCreditAmount)),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Expense Breakdown (if any expenses recorded)
                    if (record.hasExpenses) ...[
                      _buildDetailSection(
                        'Expenses',
                        CupertinoIcons.money_dollar_circle,
                        AppColors.warning,
                        [
                          if (record.expenses.isNotEmpty)
                            ...record.expenses.map((e) => _buildDetailRow(e.headerName, Formatters.currency(e.amount)))
                          else
                            _buildDetailRow('Total Expense', Formatters.currency(record.totalExpenseAmount)),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Items List
                    if (record.items.isNotEmpty) ...[
                      const Text('Items Sold', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      ...record.items.map((item) => _buildItemCard(item)),
                    ],

                    // Location info
                    if (record.hasLocation) ...[
                      const SizedBox(height: 16),
                      _buildDetailSection(
                        'Sale Location',
                        Icons.location_on,
                        AppColors.success,
                        [
                          _buildDetailRow('Latitude', '${record.latitude?.toStringAsFixed(6)}'),
                          _buildDetailRow('Longitude', '${record.longitude?.toStringAsFixed(6)}'),
                        ],
                        trailing: TextButton.icon(
                          onPressed: () => _openInMaps(record.latitude!, record.longitude!),
                          icon: const Icon(Icons.map_outlined, size: 18),
                          label: const Text('Open in Maps'),
                          style: TextButton.styleFrom(foregroundColor: AppColors.success),
                        ),
                      ),
                    ],

                    // Approval Info
                    if (record.status == 'approved' && record.approvedByName != null) ...[
                      const SizedBox(height: 16),
                      _buildDetailSection(
                        'Approval Info',
                        CupertinoIcons.check_mark_circled,
                        AppColors.success,
                        [
                          _buildDetailRow('Approved by', record.approvedByName!),
                          if (record.approvedAt != null) _buildDetailRow('Approved at', Formatters.dateTime(record.approvedAt!)),
                        ],
                      ),
                    ],

                    // Rejection Info
                    if (record.status == 'rejected') ...[
                      const SizedBox(height: 16),
                      _buildRejectionSection(record),
                    ],

                    // Notes
                    if (record.notes.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildDetailSection(
                        'Notes',
                        CupertinoIcons.doc_text,
                        cs.onSurfaceVariant,
                        [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(record.notes, style: const TextStyle(fontSize: 14)),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
      },
    );
  }

  Widget _buildImageGallerySection(List<String> imageUrls) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(CupertinoIcons.photo_on_rectangle, size: 18, color: cs.primary),
            const SizedBox(width: 8),
            Text(
              'Attached Images (${imageUrls.length})',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.primary),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: imageUrls.length,
            itemBuilder: (context, index) {
              final imageUrl = _getFullImageUrl(imageUrls[index]);
              return GestureDetector(
                onTap: () => _showFullScreenImage(imageUrls, index),
                child: Container(
                  margin: const EdgeInsets.only(right: 12),
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (ctx, url) => Container(
                        color: cs.surfaceContainerHighest,
                        child: const Center(child: CupertinoActivityIndicator()),
                      ),
                      errorWidget: (ctx, url, error) => Container(
                        color: cs.surfaceContainerHighest,
                        child: Icon(Icons.broken_image, color: cs.onSurfaceVariant, size: 40),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showFullScreenImage(List<String> imageUrls, int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullScreenImageViewer(
          imageUrls: imageUrls.map((url) => _getFullImageUrl(url)).toList(),
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  Widget _buildItemCard(DailySalesItem item) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.productName ?? 'Product', style: const TextStyle(fontWeight: FontWeight.w500)),
                if (item.brandName != null || item.size != null)
                  Text(
                    '${item.brandName ?? ""} ${item.size ?? ""}'.trim(),
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                if (item.openingStock > 0 || item.closingStock > 0)
                  Text(
                    'Stock: ${item.openingStock} → ${item.closingStock}',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('x${item.quantity}', style: const TextStyle(fontWeight: FontWeight.w500)),
              Text(
                Formatters.currency(item.totalAmount),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.success),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRejectionSection(DailySalesRecord record) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.xmark_circle_fill, color: AppColors.error, size: 20),
              const SizedBox(width: 8),
              Text('Rejection Details', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.error)),
            ],
          ),
          const SizedBox(height: 12),
          if (record.rejectedByName != null)
            _buildDetailRow('Rejected by', record.rejectedByName!, valueColor: AppColors.error),
          if (record.rejectedAt != null)
            _buildDetailRow('Rejected at', Formatters.dateTime(record.rejectedAt!), valueColor: AppColors.error),
          if (record.rejectionReason != null && record.rejectionReason!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Reason:', style: TextStyle(fontSize: 12, color: AppColors.error, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Text(record.rejectionReason!, style: TextStyle(fontSize: 14, color: AppColors.error)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _copyRejectedRecord(context, record),
              icon: const Icon(CupertinoIcons.doc_on_doc, size: 18),
              label: const Text('Copy to New Draft'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailSection(String title, IconData icon, Color color, List<Widget> children, {Widget? trailing}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
              if (trailing != null) ...[const Spacer(), trailing],
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? valueColor}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: valueColor ?? cs.onSurface)),
        ],
      ),
    );
  }

  Future<void> _openInMaps(double lat, double lng) async {
    final googleMapsUrl = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    final appleMapsUrl = Uri.parse('https://maps.apple.com/?q=$lat,$lng');

    try {
      if (await canLaunchUrl(googleMapsUrl)) {
        await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
      } else if (await canLaunchUrl(appleMapsUrl)) {
        await launchUrl(appleMapsUrl, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      _showErrorSnackBar('Could not open maps: $e');
    }
  }

  Future<void> _copyRejectedRecord(BuildContext modalContext, DailySalesRecord record) async {
    if (record.id == null) {
      _showErrorSnackBar('Cannot copy record: Record ID is missing');
      return;
    }

    _showLoadingDialog('Creating new draft...');

    try {
      final authService = context.read<AuthService>();
      final service = DailySalesService(authService);
      final result = await service.copyDailySalesRecord(record.id!);

      if (mounted) Navigator.of(context).pop();

      if (result.success && result.data != null) {
        if (mounted) Navigator.of(modalContext).pop();
        _loadMyRecords();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [Icon(CupertinoIcons.check_mark_circled, color: Colors.white), SizedBox(width: 8), Text('Record copied! New draft created.')],
              ),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      } else {
        _showErrorSnackBar(result.error ?? 'Failed to copy record');
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      _showErrorSnackBar('Error: $e');
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// FULL SCREEN IMAGE VIEWER
// ══════════════════════════════════════════════════════════════════════════════

class _FullScreenImageViewer extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;

  const _FullScreenImageViewer({required this.imageUrls, required this.initialIndex});

  @override
  State<_FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<_FullScreenImageViewer> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_currentIndex + 1} / ${widget.imageUrls.length}'),
        centerTitle: true,
      ),
      body: PageView.builder(
        controller: _pageController,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemCount: widget.imageUrls.length,
        itemBuilder: (context, index) {
          return InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: Center(
              child: CachedNetworkImage(
                imageUrl: widget.imageUrls[index],
                fit: BoxFit.contain,
                placeholder: (ctx, url) => const Center(child: CircularProgressIndicator(color: Colors.white)),
                errorWidget: (ctx, url, error) => const Icon(Icons.broken_image, color: Colors.white54, size: 64),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Local Data Models
// ══════════════════════════════════════════════════════════════════════════════

enum _TimePeriod {
  today('Today'),
  sevenDays('7 Days'),
  fifteenDays('15 Days'),
  oneMonth('1 Month');

  final String label;
  const _TimePeriod(this.label);
}

class _DateRange {
  final DateTime start;
  final DateTime end;

  _DateRange({required this.start, required this.end});
}
