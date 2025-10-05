import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/custom_app_bar.dart';

/// Sales Invoice Screen - Detailed invoice view and generation
class SalesInvoiceScreen extends StatefulWidget {
  final String invoiceId;

  const SalesInvoiceScreen({
    super.key,
    required this.invoiceId,
  });

  @override
  State<SalesInvoiceScreen> createState() => _SalesInvoiceScreenState();
}

class _SalesInvoiceScreenState extends State<SalesInvoiceScreen> {
  bool _isLoading = false;
  Map<String, dynamic>? _invoice;

  @override
  void initState() {
    super.initState();
    _loadInvoice();
  }

  Future<void> _loadInvoice() async {
    setState(() => _isLoading = true);
    // TODO: Load invoice from API - GET /api/sales/invoices/:id
    await Future.delayed(const Duration(seconds: 1));

    // Sample invoice data
    setState(() {
      _invoice = {
        'id': widget.invoiceId,
        'invoice_number': 'INV-2025-001',
        'date': 'Jan 15, 2025',
        'time': '10:30 AM',
        'status': 'paid',
        'customer': {
          'name': 'John Doe',
          'email': 'john@example.com',
          'phone': '+91 9876543210',
          'gstin': '29ABCDE1234F1Z5',
          'address': '123 Main Street, Mumbai, Maharashtra 400001',
        },
        'shop': {
          'name': 'LiquorPro Store - Main Branch',
          'address': '456 Shop Street, Mumbai, Maharashtra 400002',
          'phone': '+91 9876543210',
          'gstin': '27ABCDE5678F2Z9',
          'email': 'store@liquorpro.com',
        },
        'items': [
          {
            'id': '1',
            'name': 'Johnnie Walker Black Label',
            'sku': 'JW-BL-750',
            'hsn': '2208',
            'quantity': 2,
            'unit_price': 3000,
            'discount': 100,
            'taxable_amount': 5800,
            'cgst_rate': 9,
            'cgst_amount': 522,
            'sgst_rate': 9,
            'sgst_amount': 522,
            'total': 6844,
          },
          {
            'id': '2',
            'name': 'Royal Challenge Whisky',
            'sku': 'RC-W-750',
            'hsn': '2208',
            'quantity': 3,
            'unit_price': 1200,
            'discount': 0,
            'taxable_amount': 3600,
            'cgst_rate': 9,
            'cgst_amount': 324,
            'sgst_rate': 9,
            'sgst_amount': 324,
            'total': 4248,
          },
        ],
        'subtotal': 9400,
        'discount': 100,
        'taxable_amount': 9400,
        'cgst': 846,
        'sgst': 846,
        'igst': 0,
        'total_tax': 1692,
        'grand_total': 11092,
        'payment_method': 'UPI',
        'notes': 'Thank you for your business!',
        'terms': 'All sales are final. No returns without valid reason.',
      };
      _isLoading = false;
    });
  }

  Future<void> _printInvoice() async {
    // TODO: Print invoice - POST /api/sales/invoices/:id/print
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Preparing invoice for printing...'),
        backgroundColor: AppColors.info,
      ),
    );
  }

  Future<void> _shareInvoice() async {
    // TODO: Share invoice - POST /api/sales/invoices/:id/share
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sharing invoice...'),
        backgroundColor: AppColors.info,
      ),
    );
  }

  Future<void> _downloadPDF() async {
    // TODO: Download PDF - GET /api/sales/invoices/:id/pdf
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Downloading invoice PDF...'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  Future<void> _sendEmail() async {
    final customer = _invoice?['customer'];
    if (customer?['email'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No email address found for customer'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    // TODO: Send email - POST /api/sales/invoices/:id/email
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Sending invoice to ${customer['email']}...'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Invoice Details',
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'print':
                  _printInvoice();
                  break;
                case 'share':
                  _shareInvoice();
                  break;
                case 'pdf':
                  _downloadPDF();
                  break;
                case 'email':
                  _sendEmail();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'print',
                child: Row(
                  children: [
                    Icon(Icons.print, size: 20),
                    SizedBox(width: 12),
                    Text('Print'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'share',
                child: Row(
                  children: [
                    Icon(Icons.share, size: 20),
                    SizedBox(width: 12),
                    Text('Share'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'pdf',
                child: Row(
                  children: [
                    Icon(Icons.picture_as_pdf, size: 20),
                    SizedBox(width: 12),
                    Text('Download PDF'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'email',
                child: Row(
                  children: [
                    Icon(Icons.email, size: 20),
                    SizedBox(width: 12),
                    Text('Send Email'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _invoice == null
              ? const Center(child: Text('Invoice not found'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Invoice Header Card
                      Card(
                        color: AppColors.primary.withOpacity(0.05),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'TAX INVOICE',
                                        style: AppTextStyles.h3.copyWith(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _invoice!['invoice_number'],
                                        style: AppTextStyles.h5.copyWith(
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.success.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      _invoice!['status'].toString().toUpperCase(),
                                      style: AppTextStyles.bodyMedium.copyWith(
                                        color: AppColors.success,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Icon(Icons.calendar_today, size: 16, color: AppColors.textSecondary),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${_invoice!['date']} at ${_invoice!['time']}',
                                    style: AppTextStyles.bodyMedium,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Shop and Customer Details
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _buildAddressCard(
                              'From',
                              _invoice!['shop'],
                              Icons.store,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildAddressCard(
                              'Bill To',
                              _invoice!['customer'],
                              Icons.person,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Items Section
                      Text('Items', style: AppTextStyles.h5),
                      const SizedBox(height: 12),
                      Card(
                        child: Column(
                          children: [
                            // Table Header
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.05),
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(12),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Expanded(
                                    flex: 3,
                                    child: Text(
                                      'Item',
                                      style: TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      'Qty',
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      'Amount',
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                      textAlign: TextAlign.right,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Items
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: (_invoice!['items'] as List).length,
                              separatorBuilder: (context, index) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final item = _invoice!['items'][index];
                                return _buildInvoiceItem(item);
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Totals Section
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              _buildTotalRow('Subtotal', _invoice!['subtotal']),
                              if (_invoice!['discount'] > 0) ...[
                                const SizedBox(height: 8),
                                _buildTotalRow(
                                  'Discount',
                                  _invoice!['discount'],
                                  color: AppColors.success,
                                  prefix: '- ',
                                ),
                              ],
                              const SizedBox(height: 8),
                              _buildTotalRow('Taxable Amount', _invoice!['taxable_amount']),
                              const Divider(height: 24),
                              if (_invoice!['cgst'] > 0) ...[
                                _buildTotalRow('CGST', _invoice!['cgst'], color: AppColors.info),
                                const SizedBox(height: 8),
                              ],
                              if (_invoice!['sgst'] > 0) ...[
                                _buildTotalRow('SGST', _invoice!['sgst'], color: AppColors.info),
                                const SizedBox(height: 8),
                              ],
                              if (_invoice!['igst'] > 0) ...[
                                _buildTotalRow('IGST', _invoice!['igst'], color: AppColors.info),
                                const SizedBox(height: 8),
                              ],
                              _buildTotalRow('Total Tax', _invoice!['total_tax'], color: AppColors.warning),
                              const Divider(height: 24),
                              _buildTotalRow(
                                'Grand Total',
                                _invoice!['grand_total'],
                                color: AppColors.primary,
                                isBold: true,
                                isLarge: true,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Payment Method
                      Card(
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.success.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.payment, color: AppColors.success),
                          ),
                          title: const Text('Payment Method'),
                          subtitle: Text(_invoice!['payment_method']),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Notes and Terms
                      if (_invoice!['notes'] != null) ...[
                        Text('Notes', style: AppTextStyles.h5),
                        const SizedBox(height: 8),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              _invoice!['notes'],
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      if (_invoice!['terms'] != null) ...[
                        Text('Terms & Conditions', style: AppTextStyles.h5),
                        const SizedBox(height: 8),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              _invoice!['terms'],
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
      bottomNavigationBar: _invoice == null
          ? null
          : Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _shareInvoice,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        foregroundColor: AppColors.primary,
                      ),
                      icon: const Icon(Icons.share, size: 20),
                      label: const Text('Share'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _printInvoice,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.print, size: 20),
                      label: const Text('Print Invoice'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildAddressCard(String title, Map<String, dynamic> data, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            Text(
              data['name'],
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            if (data['email'] != null) ...[
              Text(
                data['email'],
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              data['phone'],
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            if (data['gstin'] != null) ...[
              const SizedBox(height: 4),
              Text(
                'GSTIN: ${data['gstin']}',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            if (data['address'] != null) ...[
              const SizedBox(height: 8),
              Text(
                data['address'],
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInvoiceItem(Map<String, dynamic> item) {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      childrenPadding: const EdgeInsets.all(12),
      title: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['name'],
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'SKU: ${item['sku']} | HSN: ${item['hsn']}',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Text(
              '${item['quantity']}',
              style: AppTextStyles.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              Formatters.currency(item['total']),
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              _buildItemDetailRow('Unit Price', item['unit_price']),
              if (item['discount'] > 0) ...[
                const SizedBox(height: 8),
                _buildItemDetailRow('Discount', item['discount'], isNegative: true),
              ],
              const SizedBox(height: 8),
              _buildItemDetailRow('Taxable Amount', item['taxable_amount']),
              const Divider(height: 16),
              _buildItemDetailRow('CGST @ ${item['cgst_rate']}%', item['cgst_amount']),
              const SizedBox(height: 8),
              _buildItemDetailRow('SGST @ ${item['sgst_rate']}%', item['sgst_amount']),
              const Divider(height: 16),
              _buildItemDetailRow(
                'Item Total',
                item['total'],
                isBold: true,
                color: AppColors.primary,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildItemDetailRow(String label, num value, {bool isNegative = false, bool isBold = false, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        Text(
          '${isNegative ? '- ' : ''}${Formatters.currency(value)}',
          style: AppTextStyles.bodySmall.copyWith(
            fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildTotalRow(String label, num value, {Color? color, String prefix = '', bool isBold = false, bool isLarge = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: (isLarge ? AppTextStyles.h5 : AppTextStyles.bodyMedium).copyWith(
            fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        Text(
          '$prefix${Formatters.currency(value)}',
          style: (isLarge ? AppTextStyles.h4 : AppTextStyles.bodyMedium).copyWith(
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: color ?? AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
