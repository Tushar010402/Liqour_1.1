import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/excise_models.dart';
import '../providers/excise_provider.dart';

class LicenseDetailScreen extends StatelessWidget {
  final ExciseLicense license;

  const LicenseDetailScreen({
    Key? key,
    required this.license,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('License Details'),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              // Navigate to edit license screen
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Header
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    license.statusColor,
                    license.statusColor.withOpacity(0.7),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.verified_user,
                    size: 64,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    license.licenseType.displayName,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    license.licenseNumber,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      license.statusText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // License Information
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSection(
                    context,
                    title: 'License Information',
                    children: [
                      _buildInfoRow(
                        context,
                        'License Type',
                        license.licenseType.displayName,
                      ),
                      _buildInfoRow(
                        context,
                        'License Number',
                        license.licenseNumber,
                      ),
                      _buildInfoRow(
                        context,
                        'Issuing Authority',
                        license.issuingAuthority ?? 'Unknown',
                      ),
                      _buildInfoRow(
                        context,
                        'Issue Date',
                        _formatDate(license.issuedDate),
                      ),
                      _buildInfoRow(
                        context,
                        'Expiry Date',
                        _formatDate(license.expiryDate),
                        valueColor: license.statusColor,
                      ),
                      if (license.isExpiringSoon || license.isExpired)
                        _buildInfoRow(
                          context,
                          'Days Until Expiry',
                          '${license.daysUntilExpiry} days',
                          valueColor: license.statusColor,
                        ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  _buildSection(
                    context,
                    title: 'Financial Information',
                    children: [
                      _buildInfoRow(
                        context,
                        'Monthly License Fee',
                        '₹${license.monthlyFee.toStringAsFixed(0)}',
                      ),
                      _buildInfoRow(
                        context,
                        'Annual Fee',
                        '₹${(license.monthlyFee * 12).toStringAsFixed(0)}',
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  _buildSection(
                    context,
                    title: 'Permitted Categories',
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _getPermittedCategories(license.licenseType)
                              .map((category) => Chip(
                                    label: Text(category),
                                    backgroundColor:
                                        license.licenseType.color.withOpacity(0.1),
                                    labelStyle: TextStyle(
                                      color: license.licenseType.color,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ))
                              .toList(),
                        ),
                      ),
                    ],
                  ),

                  if (license.isExpiringSoon || license.isExpired) ...[
                    const SizedBox(height: 16),
                    _buildAlertCard(context),
                  ],

                  const SizedBox(height: 24),

                  // Action Buttons
                  if (license.isExpiringSoon || license.isExpired)
                    _buildRenewButton(context),

                  const SizedBox(height: 12),
                  _buildPayFeeButton(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 2,
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
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[600],
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

  Widget _buildAlertCard(BuildContext context) {
    return Card(
      elevation: 2,
      color: license.statusColor.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              license.isExpired ? Icons.error : Icons.warning_amber_rounded,
              color: license.statusColor,
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    license.isExpired
                        ? 'License Expired'
                        : 'License Expiring Soon',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: license.statusColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    license.isExpired
                        ? 'This license has expired. Please renew immediately to avoid penalties.'
                        : 'This license will expire in ${license.daysUntilExpiry} days. Please renew before expiry.',
                    style: TextStyle(
                      fontSize: 13,
                      color: license.statusColor.withOpacity(0.8),
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

  Widget _buildRenewButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () {
          _showRenewDialog(context);
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: const Icon(Icons.autorenew),
        label: const Text('Renew License'),
      ),
    );
  }

  Widget _buildPayFeeButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () {
          _showPayFeeDialog(context);
        },
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: const Icon(Icons.payment),
        label: const Text('Pay Monthly Fee'),
      ),
    );
  }

  void _showRenewDialog(BuildContext context) {
    final newExpiryController = TextEditingController();
    final oneYear = license.expiryDate.add(const Duration(days: 365));
    newExpiryController.text = _formatDate(oneYear);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renew License'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current expiry: ${_formatDate(license.expiryDate)}'),
            const SizedBox(height: 16),
            TextField(
              controller: newExpiryController,
              decoration: const InputDecoration(
                labelText: 'New Expiry Date',
                hintText: 'DD/MM/YYYY',
                border: OutlineInputBorder(),
              ),
              readOnly: true,
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: oneYear,
                  firstDate: license.expiryDate,
                  lastDate: DateTime.now().add(const Duration(days: 3650)),
                );
                if (date != null) {
                  newExpiryController.text = _formatDate(date);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              // Parse date and renew
              final parts = newExpiryController.text.split('/');
              if (parts.length == 3) {
                final newDate = DateTime(
                  int.parse(parts[2]),
                  int.parse(parts[1]),
                  int.parse(parts[0]),
                );

                final provider = context.read<ExciseProvider>();
                final success = await provider.renewLicense(
                  id: license.id,
                  newExpiryDate: newDate,
                );

                if (success && context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('License renewed successfully'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              }
            },
            child: const Text('Renew'),
          ),
        ],
      ),
    );
  }

  void _showPayFeeDialog(BuildContext context) {
    final amountController =
        TextEditingController(text: license.monthlyFee.toStringAsFixed(0));
    final transactionRefController = TextEditingController();
    String paymentMethod = 'cash';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pay Monthly Fee'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: '₹',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: paymentMethod,
              decoration: const InputDecoration(
                labelText: 'Payment Method',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('Cash')),
                DropdownMenuItem(value: 'upi', child: Text('UPI')),
                DropdownMenuItem(value: 'card', child: Text('Card')),
                DropdownMenuItem(value: 'bank_transfer', child: Text('Bank Transfer')),
              ],
              onChanged: (value) {
                if (value != null) paymentMethod = value;
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: transactionRefController,
              decoration: const InputDecoration(
                labelText: 'Transaction Reference',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final provider = context.read<ExciseProvider>();
              final success = await provider.payLicenseFee(
                licenseId: license.id,
                amount: double.parse(amountController.text),
                paymentMethod: paymentMethod,
                transactionRef: transactionRefController.text,
              );

              if (success && context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Payment recorded successfully'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: const Text('Pay'),
          ),
        ],
      ),
    );
  }

  List<String> _getPermittedCategories(LicenseType type) {
    switch (type) {
      case LicenseType.fl2a:
        return ['IMFL', 'Beer', 'Wine'];
      case LicenseType.fl17:
        return ['Country Liquor', 'Beer'];
      case LicenseType.cl2:
        return ['Wholesale Depot'];
      case LicenseType.composite:
        return ['Country Liquor', 'IMFL', 'Beer', 'Wine'];
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
