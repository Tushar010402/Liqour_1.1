import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/custom_app_bar.dart';

/// Tax/GST Reports Screen - For tax compliance and reporting
class TaxReportsScreen extends StatefulWidget {
  const TaxReportsScreen({super.key});

  @override
  State<TaxReportsScreen> createState() => _TaxReportsScreenState();
}

class _TaxReportsScreenState extends State<TaxReportsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;
  DateTimeRange? _selectedDateRange;
  String _selectedPeriod = 'this_month'; // this_month/last_month/quarter/custom

  final Map<String, dynamic> _gstSummary = {
    'total_sales': 1250000,
    'cgst_collected': 112500,
    'sgst_collected': 112500,
    'igst_collected': 0,
    'total_gst_collected': 225000,
    'input_tax_credit': 50000,
    'net_gst_payable': 175000,
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadTaxReports();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadTaxReports() async {
    setState(() => _isLoading = true);
    // TODO: Load tax reports from API - GET /api/reports/tax
    await Future.delayed(const Duration(seconds: 1));
    setState(() => _isLoading = false);
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _selectedDateRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDateRange = picked;
        _selectedPeriod = 'custom';
      });
      _loadTaxReports();
    }
  }

  Future<void> _exportReport(String format) async {
    // TODO: Export report - POST /api/reports/tax/export
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Exporting report as $format...'),
        backgroundColor: AppColors.info,
      ),
    );
  }

  Future<void> _downloadGSTR1() async {
    // TODO: Generate GSTR-1 - GET /api/reports/tax/gstr1
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Generating GSTR-1 report...'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  Future<void> _downloadGSTR3B() async {
    // TODO: Generate GSTR-3B - GET /api/reports/tax/gstr3b
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Generating GSTR-3B report...'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Tax & GST Reports',
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.download),
            onSelected: (value) {
              if (value == 'pdf') {
                _exportReport('PDF');
              } else if (value == 'excel') {
                _exportReport('Excel');
              } else if (value == 'gstr1') {
                _downloadGSTR1();
              } else if (value == 'gstr3b') {
                _downloadGSTR3B();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'pdf',
                child: Row(
                  children: [
                    Icon(Icons.picture_as_pdf, size: 20),
                    SizedBox(width: 12),
                    Text('Export as PDF'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'excel',
                child: Row(
                  children: [
                    Icon(Icons.table_chart, size: 20),
                    SizedBox(width: 12),
                    Text('Export as Excel'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'gstr1',
                child: Row(
                  children: [
                    Icon(Icons.file_download, size: 20),
                    SizedBox(width: 12),
                    Text('Download GSTR-1'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'gstr3b',
                child: Row(
                  children: [
                    Icon(Icons.file_download, size: 20),
                    SizedBox(width: 12),
                    Text('Download GSTR-3B'),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'Summary', icon: Icon(Icons.summarize, size: 20)),
            Tab(text: 'Breakdown', icon: Icon(Icons.analytics, size: 20)),
            Tab(text: 'Transactions', icon: Icon(Icons.receipt_long, size: 20)),
          ],
        ),
      ),
      body: Column(
        children: [
          // Period Selector
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.background,
              border: Border(
                bottom: BorderSide(
                  color: AppColors.textSecondary.withOpacity(0.2),
                ),
              ),
            ),
            child: Column(
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildPeriodChip('This Month', 'this_month'),
                      const SizedBox(width: 8),
                      _buildPeriodChip('Last Month', 'last_month'),
                      const SizedBox(width: 8),
                      _buildPeriodChip('This Quarter', 'quarter'),
                      const SizedBox(width: 8),
                      _buildPeriodChip('Custom Range', 'custom'),
                    ],
                  ),
                ),
                if (_selectedPeriod == 'custom' && _selectedDateRange != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    '${_formatDate(_selectedDateRange!.start)} - ${_formatDate(_selectedDateRange!.end)}',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Tab Views
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildSummaryTab(),
                      _buildBreakdownTab(),
                      _buildTransactionsTab(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodChip(String label, String value) {
    final isSelected = _selectedPeriod == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (value == 'custom') {
          _selectDateRange();
        } else {
          setState(() => _selectedPeriod = value);
          _loadTaxReports();
        }
      },
      selectedColor: AppColors.primary,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : AppColors.textPrimary,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }

  Widget _buildSummaryTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // GST Summary Cards
          Text('GST Summary', style: AppTextStyles.h5),
          const SizedBox(height: 12),

          Card(
            color: AppColors.success.withOpacity(0.1),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(Icons.account_balance_wallet, color: AppColors.success, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'Total Sales (Taxable)',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    Formatters.currency(_gstSummary['total_sales']),
                    style: AppTextStyles.h2.copyWith(
                      color: AppColors.success,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: _buildTaxCard(
                  'CGST Collected',
                  _gstSummary['cgst_collected'],
                  AppColors.info,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTaxCard(
                  'SGST Collected',
                  _gstSummary['sgst_collected'],
                  AppColors.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _buildTaxCard(
                  'IGST Collected',
                  _gstSummary['igst_collected'],
                  AppColors.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTaxCard(
                  'Total GST',
                  _gstSummary['total_gst_collected'],
                  AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ITC and Payable
          Text('Tax Calculation', style: AppTextStyles.h5),
          const SizedBox(height: 12),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildCalculationRow(
                    'Total GST Collected',
                    _gstSummary['total_gst_collected'],
                    AppColors.success,
                  ),
                  const Divider(height: 24),
                  _buildCalculationRow(
                    'Input Tax Credit (ITC)',
                    _gstSummary['input_tax_credit'],
                    AppColors.info,
                    isSubtraction: true,
                  ),
                  const Divider(height: 24),
                  _buildCalculationRow(
                    'Net GST Payable',
                    _gstSummary['net_gst_payable'],
                    AppColors.error,
                    isBold: true,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // HSN/SAC Summary
          Text('HSN/SAC Summary', style: AppTextStyles.h5),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildHSNRow('2208', 'Alcoholic Beverages', 890000, 160200),
                  const Divider(height: 16),
                  _buildHSNRow('2203', 'Beer', 360000, 64800),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreakdownTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tax Rate-wise Breakdown', style: AppTextStyles.h5),
          const SizedBox(height: 12),

          // GST Rate Cards
          _buildRateBreakdownCard('GST @ 18%', 850000, 153000),
          const SizedBox(height: 12),
          _buildRateBreakdownCard('GST @ 12%', 300000, 36000),
          const SizedBox(height: 12),
          _buildRateBreakdownCard('GST @ 5%', 100000, 5000),
          const SizedBox(height: 24),

          Text('State-wise GST Breakdown', style: AppTextStyles.h5),
          const SizedBox(height: 12),

          Card(
            child: Column(
              children: [
                _buildStateRow('Maharashtra', 750000, 135000, 0),
                const Divider(height: 1),
                _buildStateRow('Karnataka', 300000, 54000, 0),
                const Divider(height: 1),
                _buildStateRow('Delhi', 200000, 0, 36000),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Text('Monthly Trend', style: AppTextStyles.h5),
          const SizedBox(height: 12),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildMonthlyTrendRow('Jan 2025', 1250000, 225000),
                  const Divider(height: 16),
                  _buildMonthlyTrendRow('Dec 2024', 1180000, 212400),
                  const Divider(height: 16),
                  _buildMonthlyTrendRow('Nov 2024', 1090000, 196200),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionsTab() {
    final transactions = [
      {
        'id': 'INV-2025-001',
        'date': 'Jan 15, 2025',
        'customer': 'ABC Liquor Store',
        'amount': 25000,
        'cgst': 2250,
        'sgst': 2250,
        'igst': 0,
        'total_gst': 4500,
      },
      {
        'id': 'INV-2025-002',
        'date': 'Jan 15, 2025',
        'customer': 'XYZ Beverages',
        'amount': 15000,
        'cgst': 1350,
        'sgst': 1350,
        'igst': 0,
        'total_gst': 2700,
      },
    ];

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: transactions.length,
      itemBuilder: (context, index) {
        final txn = transactions[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ExpansionTile(
            leading: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.receipt, color: AppColors.primary),
            ),
            title: Text(
              txn['id'] as String,
              style: AppTextStyles.bodyLarge.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(txn['customer'] as String),
                const SizedBox(height: 4),
                Text(
                  txn['date'] as String,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  Formatters.currency(txn['amount'] as num),
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'GST: ${Formatters.currency(txn['total_gst'] as num)}',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.success,
                  ),
                ),
              ],
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildTaxDetailRow('CGST', txn['cgst'] as num),
                    const SizedBox(height: 8),
                    _buildTaxDetailRow('SGST', txn['sgst'] as num),
                    const SizedBox(height: 8),
                    _buildTaxDetailRow('IGST', txn['igst'] as num),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total GST',
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          Formatters.currency(txn['total_gst'] as num),
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTaxCard(String title, num amount, Color color) {
    return Card(
      color: color.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(Icons.currency_rupee, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              Formatters.currency(amount),
              style: AppTextStyles.h5.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalculationRow(String label, num amount, Color color, {bool isSubtraction = false, bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            if (isSubtraction) ...[
              const Icon(Icons.remove, size: 16, color: AppColors.error),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
        Text(
          Formatters.currency(amount),
          style: AppTextStyles.bodyMedium.copyWith(
            color: color,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildHSNRow(String hsn, String description, num taxable, num gst) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hsn,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Taxable',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                Formatters.currency(taxable),
                style: AppTextStyles.bodyMedium,
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'GST',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                Formatters.currency(gst),
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.success,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRateBreakdownCard(String title, num taxable, num gst) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: AppTextStyles.bodyLarge.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Taxable Amount',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        Formatters.currency(taxable),
                        style: AppTextStyles.bodyLarge,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'GST Amount',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        Formatters.currency(gst),
                        style: AppTextStyles.bodyLarge.copyWith(
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStateRow(String state, num taxable, num cgstSgst, num igst) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            state,
            style: AppTextStyles.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Taxable: ${Formatters.currency(taxable)}',
                style: AppTextStyles.bodySmall,
              ),
              if (cgstSgst > 0)
                Text(
                  'CGST+SGST: ${Formatters.currency(cgstSgst)}',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.success,
                  ),
                ),
              if (igst > 0)
                Text(
                  'IGST: ${Formatters.currency(igst)}',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.warning,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlyTrendRow(String month, num sales, num gst) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(month, style: AppTextStyles.bodyMedium),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              Formatters.currency(sales),
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              'GST: ${Formatters.currency(gst)}',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.success,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTaxDetailRow(String label, num amount) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTextStyles.bodyMedium),
        Text(
          Formatters.currency(amount),
          style: AppTextStyles.bodyMedium.copyWith(
            color: amount > 0 ? AppColors.success : AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}
