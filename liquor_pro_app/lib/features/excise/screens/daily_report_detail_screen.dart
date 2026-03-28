import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../models/excise_models.dart';
import '../providers/excise_provider.dart';

class DailyReportDetailScreen extends StatelessWidget {
  final ExciseDailyReport report;

  const DailyReportDetailScreen({
    super.key,
    required this.report,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Daily Report',
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: report.uploadedToPortal
                      ? [Colors.green, Colors.green.shade600]
                      : [Colors.orange, Colors.orange.shade600],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    report.uploadedToPortal
                        ? Icons.cloud_done
                        : Icons.cloud_upload_outlined,
                    size: 64,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _formatDate(report.reportDate),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha:0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      report.uploadedToPortal ? 'Uploaded to Portal' : 'Pending Upload',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Stock Summary
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: cs.outline.withValues(alpha: 0.2)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Stock Summary',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const Divider(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildStockColumn(
                                context,
                                'Opening',
                                report.openingStock.totalBottles,
                                Colors.blue,
                              ),
                              Container(
                                width: 1,
                                height: 50,
                                color: cs.outlineVariant,
                              ),
                              _buildStockColumn(
                                context,
                                'Lifted',
                                report.liftedQuantity.totalBottles,
                                Colors.purple,
                              ),
                              Container(
                                width: 1,
                                height: 50,
                                color: cs.outlineVariant,
                              ),
                              _buildStockColumn(
                                context,
                                'Sales',
                                report.salesQuantity.totalBottles,
                                Colors.orange,
                              ),
                              Container(
                                width: 1,
                                height: 50,
                                color: cs.outlineVariant,
                              ),
                              _buildStockColumn(
                                context,
                                'Closing',
                                report.closingStock.totalBottles,
                                Colors.green,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Category Breakdown
                  _buildCategoryBreakdown(context, 'Opening Stock', report.openingStock),

                  const SizedBox(height: 16),

                  _buildCategoryBreakdown(context, 'Sales', report.salesQuantity),

                  const SizedBox(height: 16),

                  _buildCategoryBreakdown(context, 'Closing Stock', report.closingStock),

                  const SizedBox(height: 16),
                  _buildCategoryBreakdown(context, 'Lifted Quantity', report.liftedQuantity),

                  const SizedBox(height: 16),
                  _buildCategoryBreakdown(context, 'Returns', report.returnsQuantity),

                  const SizedBox(height: 16),

                  // Upload Status
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: cs.outline.withValues(alpha: 0.2)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Portal Upload',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const Divider(height: 24),
                          _buildInfoRow(
                            context,
                            'Status',
                            report.uploadedToPortal ? 'Uploaded' : 'Not Uploaded',
                            valueColor: report.uploadedToPortal ? Colors.green : Colors.orange,
                          ),
                          if (report.portalUploadedAt != null)
                            _buildInfoRow(
                              context,
                              'Uploaded At',
                              _formatDateTime(report.portalUploadedAt!),
                            ),
                          if (report.smsConfirmation != null)
                            _buildInfoRow(
                              context,
                              'SMS Confirmation',
                              report.smsConfirmation!,
                            ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Action Buttons
                  if (!report.uploadedToPortal)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _uploadReport(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.cloud_upload),
                        label: const Text('Upload to Portal'),
                      ),
                    ),

                  if (report.uploadedToPortal && report.portalUploadFailed) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _retryUpload(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry Upload'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStockColumn(BuildContext context, String label, int value, Color color) {
    return Column(
      children: [
        Text(
          value.toString(),
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryBreakdown(
    BuildContext context,
    String title,
    StockBreakdown breakdown,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const Divider(height: 24),
            _buildCategoryRow(context, 'Country Liquor', breakdown.countryLiquor.fold(0, (sum, e) => sum + e.quantity)),
            _buildCategoryRow(context, 'IMFL', breakdown.imfl.fold(0, (sum, e) => sum + e.quantity)),
            _buildCategoryRow(context, 'Beer', breakdown.beer.fold(0, (sum, e) => sum + e.quantity)),
            _buildCategoryRow(context, 'Wine', breakdown.wine.fold(0, (sum, e) => sum + e.quantity)),
            const Divider(height: 16),
            _buildCategoryRow(
              context,
              'Total',
              breakdown.totalBottles,
              isTotal: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryRow(BuildContext context, String label, int value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: isTotal ? null : Theme.of(context).colorScheme.onSurface,
            ),
          ),
          Text(
            value.toString(),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isTotal ? Colors.blue[700] : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 14,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  void _uploadReport(BuildContext context) async {
    final provider = context.read<ExciseProvider>();

    // Show confirmation
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Upload Report'),
        content: const Text(
          'Are you sure you want to upload this report to the UP Excise Portal?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Upload'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      // Show loading
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 12),
              Text('Uploading report...'),
            ],
          ),
          duration: Duration(seconds: 2),
        ),
      );

      // Upload
      final success = await provider.uploadReportToPortal(report.id);

      if (success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report uploaded successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(provider.error ?? 'Failed to upload report'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _retryUpload(BuildContext context) async {
    final provider = context.read<ExciseProvider>();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            SizedBox(width: 12),
            Text('Retrying upload...'),
          ],
        ),
        duration: Duration(seconds: 2),
      ),
    );

    final success = await provider.retryReportUpload(report.id);

    if (success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Report uploaded successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.error ?? 'Failed to upload report'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}
