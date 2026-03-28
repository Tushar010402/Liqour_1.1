import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/physical_audit_models.dart';
import '../providers/physical_audit_provider.dart';

/// Audit History Screen - View past audit sessions
class AuditHistoryScreen extends ConsumerStatefulWidget {
  const AuditHistoryScreen({super.key});

  @override
  ConsumerState<AuditHistoryScreen> createState() => _AuditHistoryScreenState();
}

class _AuditHistoryScreenState extends ConsumerState<AuditHistoryScreen> {
  AuditType? _filterType;
  AuditStatus? _filterStatus;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      appBar: AppBar(
        title: const Text('Audit History'),
        backgroundColor: CupertinoColors.systemBackground,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.arrow_down_doc),
            onPressed: _exportReport,
            tooltip: 'Export Report',
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Chips
          _buildFilterBar(),

          // Sessions List
          Expanded(
            child: _buildSessionsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: CupertinoColors.systemBackground,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Type Filters
            _buildFilterChip(
              label: 'All Types',
              isSelected: _filterType == null,
              onTap: () => setState(() => _filterType = null),
            ),
            const SizedBox(width: 8),
            _buildFilterChip(
              label: 'Cash',
              isSelected: _filterType == AuditType.cash,
              onTap: () => setState(() => _filterType = AuditType.cash),
              color: const Color(0xFF10B981),
            ),
            const SizedBox(width: 8),
            _buildFilterChip(
              label: 'Inventory',
              isSelected: _filterType == AuditType.inventory,
              onTap: () => setState(() => _filterType = AuditType.inventory),
              color: const Color(0xFF3B82F6),
            ),
            const SizedBox(width: 8),
            _buildFilterChip(
              label: 'Combined',
              isSelected: _filterType == AuditType.combined,
              onTap: () => setState(() => _filterType = AuditType.combined),
              color: const Color(0xFF8B5CF6),
            ),
            const SizedBox(width: 16),
            Container(
              width: 1,
              height: 24,
              color: CupertinoColors.separator,
            ),
            const SizedBox(width: 16),
            // Status Filters
            _buildFilterChip(
              label: 'All Status',
              isSelected: _filterStatus == null,
              onTap: () => setState(() => _filterStatus = null),
            ),
            const SizedBox(width: 8),
            _buildFilterChip(
              label: 'Completed',
              isSelected: _filterStatus == AuditStatus.completed,
              onTap: () => setState(() => _filterStatus = AuditStatus.completed),
            ),
            const SizedBox(width: 8),
            _buildFilterChip(
              label: 'Cancelled',
              isSelected: _filterStatus == AuditStatus.cancelled,
              onTap: () => setState(() => _filterStatus = AuditStatus.cancelled),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    Color? color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? (color ?? CupertinoColors.activeBlue)
              : CupertinoColors.systemGrey6,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isSelected
                ? CupertinoColors.white
                : CupertinoColors.label.resolveFrom(context),
          ),
        ),
      ),
    );
  }

  Widget _buildSessionsList() {
    // Create query with filters
    final query = AuditQuery(
      shopId: ref.watch(auditShopIdProvider),
      type: _filterType,
      status: _filterStatus,
    );

    final sessionsAsync = ref.watch(auditSessionsProvider(query));

    return sessionsAsync.when(
      data: (sessions) {
        if (sessions.isEmpty) {
          return _buildEmptyState();
        }

        // Group by date
        final grouped = _groupByDate(sessions);

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(auditSessionsProvider(query));
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: grouped.length,
            itemBuilder: (context, index) {
              final date = grouped.keys.elementAt(index);
              final dateSessions = grouped[date]!;
              return _buildDateGroup(date, dateSessions);
            },
          ),
        );
      },
      loading: () => const Center(child: CupertinoActivityIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              CupertinoIcons.exclamationmark_triangle,
              size: 48,
              color: CupertinoColors.systemRed,
            ),
            const SizedBox(height: 16),
            Text(
              'Error loading history',
              style: TextStyle(
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
            const SizedBox(height: 8),
            CupertinoButton(
              child: const Text('Retry'),
              onPressed: () => ref.invalidate(auditSessionsProvider(query)),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, List<AuditSession>> _groupByDate(List<AuditSession> sessions) {
    final grouped = <String, List<AuditSession>>{};
    final dateFormat = DateFormat('MMMM d, y');

    for (final session in sessions) {
      final dateKey = dateFormat.format(session.startedAt ?? session.scheduledAt);
      grouped.putIfAbsent(dateKey, () => []).add(session);
    }

    return grouped;
  }

  Widget _buildDateGroup(String date, List<AuditSession> sessions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12, top: 8),
          child: Text(
            date,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ...sessions.map((s) => _buildSessionCard(s)),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildSessionCard(AuditSession session) {
    final timeFormat = DateFormat('h:mm a');
    final hasVariance = session.hasVariance;

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
          onTap: () => _showSessionDetails(session),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Row
                Row(
                  children: [
                    // Type Icon
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _getTypeColor(session.type).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _getTypeIcon(session.type),
                        color: _getTypeColor(session.type),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            session.type.displayName,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${timeFormat.format(session.startedAt ?? session.scheduledAt)} - ${session.completedAt != null ? timeFormat.format(session.completedAt!) : "In Progress"}',
                            style: TextStyle(
                              fontSize: 12,
                              color: CupertinoColors.secondaryLabel
                                  .resolveFrom(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Status Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Color(session.statusColorValue).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        session.status.displayName,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(session.statusColorValue),
                        ),
                      ),
                    ),
                  ],
                ),

                // Divider
                if (session.status == AuditStatus.completed) ...[
                  const SizedBox(height: 14),
                  Container(
                    height: 1,
                    color: CupertinoColors.separator.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 14),

                  // Details Row
                  Row(
                    children: [
                      // Cash Info
                      if (session.cashData != null) ...[
                        Expanded(
                          child: _buildDetailColumn(
                            'Cash Variance',
                            session.cashData!.variance >= 0
                                ? '+₹${session.cashData!.variance.toStringAsFixed(0)}'
                                : '-₹${session.cashData!.variance.abs().toStringAsFixed(0)}',
                            session.cashData!.variance != 0
                                ? (session.cashData!.variance < 0
                                    ? CupertinoColors.systemRed
                                    : CupertinoColors.systemOrange)
                                : const Color(0xFF10B981),
                          ),
                        ),
                      ],

                      // Inventory Info
                      if (session.inventoryData != null) ...[
                        Expanded(
                          child: _buildDetailColumn(
                            'Items Checked',
                            '${session.inventoryData!.itemsChecked}',
                            CupertinoColors.label,
                          ),
                        ),
                        Expanded(
                          child: _buildDetailColumn(
                            'Variances',
                            '${session.inventoryData!.itemsWithVariance}',
                            session.inventoryData!.itemsWithVariance > 0
                                ? CupertinoColors.systemOrange
                                : const Color(0xFF10B981),
                          ),
                        ),
                      ],

                      // Conducted By
                      if (session.conductedByName != null)
                        Expanded(
                          child: _buildDetailColumn(
                            'Conducted By',
                            session.conductedByName!,
                            CupertinoColors.label,
                          ),
                        ),
                    ],
                  ),
                ],

                // Variance Alert
                if (hasVariance) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: CupertinoColors.systemOrange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          CupertinoIcons.exclamationmark_triangle,
                          size: 16,
                          color: CupertinoColors.systemOrange,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Variance detected: ₹${session.totalVariance.abs().toStringAsFixed(0)} ${session.totalVariance < 0 ? "short" : "over"}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: CupertinoColors.systemOrange,
                            ),
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
      ),
    );
  }

  Widget _buildDetailColumn(String label, String value, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            CupertinoIcons.doc_text,
            size: 64,
            color: CupertinoColors.systemGrey,
          ),
          const SizedBox(height: 16),
          const Text(
            'No Audit History',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Completed audits will appear here',
            style: TextStyle(
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
        ],
      ),
    );
  }

  Color _getTypeColor(AuditType type) {
    switch (type) {
      case AuditType.cash:
        return const Color(0xFF10B981);
      case AuditType.inventory:
        return const Color(0xFF3B82F6);
      case AuditType.combined:
        return const Color(0xFF8B5CF6);
    }
  }

  IconData _getTypeIcon(AuditType type) {
    switch (type) {
      case AuditType.cash:
        return CupertinoIcons.money_dollar;
      case AuditType.inventory:
        return CupertinoIcons.cube_box;
      case AuditType.combined:
        return CupertinoIcons.doc_text;
    }
  }

  void _showSessionDetails(AuditSession session) {
    final dateFormat = DateFormat('MMMM d, y');
    final timeFormat = DateFormat('h:mm a');

    showCupertinoModalPopup(
      context: context,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: const BoxDecoration(
          color: CupertinoColors.systemBackground,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle
            Padding(
              padding: const EdgeInsets.all(12),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: CupertinoColors.systemGrey4,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${session.type.displayName} Audit',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${dateFormat.format(session.startedAt ?? session.scheduledAt)} at ${timeFormat.format(session.startedAt ?? session.scheduledAt)}',
                          style: TextStyle(
                            color: CupertinoColors.secondaryLabel
                                .resolveFrom(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Color(session.statusColorValue).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      session.status.displayName,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(session.statusColorValue),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Content
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  // Cash Data
                  if (session.cashData != null) ...[
                    _buildSection(
                      title: 'Cash Audit',
                      icon: CupertinoIcons.money_dollar,
                      color: const Color(0xFF10B981),
                      children: [
                        _buildInfoRow('Expected', '₹${session.cashData!.expectedAmount.toStringAsFixed(0)}'),
                        _buildInfoRow('Actual', '₹${session.cashData!.actualAmount.toStringAsFixed(0)}'),
                        _buildInfoRow(
                          'Variance',
                          session.cashData!.variance >= 0
                              ? '+₹${session.cashData!.variance.toStringAsFixed(0)}'
                              : '-₹${session.cashData!.variance.abs().toStringAsFixed(0)}',
                          valueColor: session.cashData!.variance < 0
                              ? CupertinoColors.systemRed
                              : session.cashData!.variance > 0
                                  ? CupertinoColors.systemOrange
                                  : const Color(0xFF10B981),
                        ),
                        if (session.cashData!.denominations.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          const Text(
                            'Denominations',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: session.cashData!.denominations.entries
                                .where((e) => e.value > 0)
                                .map((e) => Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: CupertinoColors.systemGrey6,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '₹${e.key} x ${e.value}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ))
                                .toList(),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Inventory Data
                  if (session.inventoryData != null) ...[
                    _buildSection(
                      title: 'Inventory Audit',
                      icon: CupertinoIcons.cube_box,
                      color: const Color(0xFF3B82F6),
                      children: [
                        _buildInfoRow('Items Checked', '${session.inventoryData!.itemsChecked}'),
                        _buildInfoRow(
                          'Items with Variance',
                          '${session.inventoryData!.itemsWithVariance}',
                          valueColor: session.inventoryData!.itemsWithVariance > 0
                              ? CupertinoColors.systemOrange
                              : null,
                        ),
                        _buildInfoRow(
                          'Expected Value',
                          '₹${session.inventoryData!.totalExpectedValue.toStringAsFixed(0)}',
                        ),
                        _buildInfoRow(
                          'Actual Value',
                          '₹${session.inventoryData!.totalActualValue.toStringAsFixed(0)}',
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Notes
                  if (session.notes != null && session.notes!.isNotEmpty) ...[
                    _buildSection(
                      title: 'Notes',
                      icon: CupertinoIcons.doc_text,
                      color: CupertinoColors.systemGrey,
                      children: [
                        Text(
                          session.notes!,
                          style: TextStyle(
                            color: CupertinoColors.secondaryLabel
                                .resolveFrom(context),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Audit Info
                  _buildSection(
                    title: 'Audit Details',
                    icon: CupertinoIcons.info_circle,
                    color: CupertinoColors.systemGrey,
                    children: [
                      if (session.conductedByName != null)
                        _buildInfoRow('Conducted By', session.conductedByName!),
                      _buildInfoRow('Shop', session.shopName),
                      if (session.completedAt != null && session.startedAt != null)
                        _buildInfoRow(
                          'Duration',
                          _formatDuration(session.completedAt!
                              .difference(session.startedAt!)),
                        ),
                    ],
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
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

  String _formatDuration(Duration duration) {
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
    }
    if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m';
    }
    return '${duration.inSeconds}s';
  }

  void _exportReport() async {
    final shopId = ref.read(auditShopIdProvider);
    if (shopId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a shop first')),
      );
      return;
    }

    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Export Audit Report'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _doExport('pdf');
            },
            child: const Text('Export as PDF'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _doExport('excel');
            },
            child: const Text('Export as Excel'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _doExport('csv');
            },
            child: const Text('Export as CSV'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _doExport(String format) async {
    final service = ref.read(physicalAuditServiceProvider);
    final shopId = ref.read(auditShopIdProvider)!;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Exporting $format report...')),
    );

    final result = await service.exportReport(
      shopId: shopId,
      format: format,
    );

    if (result.success && result.data != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Report ready for download'),
          action: SnackBarAction(
            label: 'Open',
            onPressed: () {
              // Open download URL
            },
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message ?? 'Failed to export report'),
          backgroundColor: CupertinoColors.systemRed,
        ),
      );
    }
  }
}
