import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../../shared/widgets/empty_state_widget.dart';

/// Daily Sales Summary Screen
class DailySalesScreen extends StatefulWidget {
  const DailySalesScreen({super.key});

  @override
  State<DailySalesScreen> createState() => _DailySalesScreenState();
}

class _DailySalesScreenState extends State<DailySalesScreen> {
  bool _isLoading = false;
  DateTime _selectedDate = DateTime.now();
  final Map<String, dynamic> _dailySummary = {};

  @override
  void initState() {
    super.initState();
    _loadDailySales();
  }

  Future<void> _loadDailySales() async {
    setState(() => _isLoading = true);
    // TODO: Load from API - GET /api/sales/daily?date=${_selectedDate}
    await Future.delayed(const Duration(seconds: 1));
    setState(() => _isLoading = false);
  }

  Future<void> _selectDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (date != null && date != _selectedDate) {
      setState(() => _selectedDate = date);
      _loadDailySales();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(
        title: 'Daily Sales Summary',
      ),
      body: RefreshIndicator(
        onRefresh: _loadDailySales,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Date Selector
            Card(
              child: ListTile(
                leading: const Icon(Icons.calendar_today, color: AppColors.primary),
                title: const Text('Select Date'),
                subtitle: Text(
                  Formatters.date(_selectedDate),
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _selectDate,
              ),
            ),
            const SizedBox(height: 24),

            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_dailySummary.isEmpty)
              const EmptyStateWidget(
                icon: Icons.today_outlined,
                title: 'No Sales',
                message: 'No sales recorded for this date',
              )
            else ...[
              // Sales Summary
              Text(
                'Sales Overview',
                style: AppTextStyles.h5,
              ),
              const SizedBox(height: 12),

              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.3,
                children: [
                  _buildSummaryCard(
                    title: 'Total Sales',
                    value: Formatters.currency(_dailySummary['total_sales'] ?? 0),
                    icon: Icons.attach_money,
                    color: AppColors.success,
                  ),
                  _buildSummaryCard(
                    title: 'Transactions',
                    value: '${_dailySummary['total_transactions'] ?? 0}',
                    icon: Icons.receipt_long,
                    color: AppColors.primary,
                  ),
                  _buildSummaryCard(
                    title: 'Items Sold',
                    value: '${_dailySummary['total_items'] ?? 0}',
                    icon: Icons.inventory_2,
                    color: AppColors.accent,
                  ),
                  _buildSummaryCard(
                    title: 'Avg. Sale',
                    value: Formatters.currency(_dailySummary['average_sale'] ?? 0),
                    icon: Icons.trending_up,
                    color: AppColors.info,
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Payment Methods
              Text(
                'Payment Methods',
                style: AppTextStyles.h5,
              ),
              const SizedBox(height: 12),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildPaymentRow(
                        'Cash',
                        _dailySummary['cash_sales'] ?? 0,
                        Icons.money,
                      ),
                      const Divider(height: 24),
                      _buildPaymentRow(
                        'Card',
                        _dailySummary['card_sales'] ?? 0,
                        Icons.credit_card,
                      ),
                      const Divider(height: 24),
                      _buildPaymentRow(
                        'UPI',
                        _dailySummary['upi_sales'] ?? 0,
                        Icons.qr_code,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Top Products
              Text(
                'Top Selling Products',
                style: AppTextStyles.h5,
              ),
              const SizedBox(height: 12),

              ...(_dailySummary['top_products'] as List? ?? []).map((product) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.local_bar,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      product['name'] ?? '',
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      '${product['quantity']} units sold',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    trailing: Text(
                      Formatters.currency(product['total'] ?? 0),
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.success,
                      ),
                    ),
                  ),
                );
              }),

              const SizedBox(height: 24),

              // Hourly Breakdown
              Text(
                'Sales by Hour',
                style: AppTextStyles.h5,
              ),
              const SizedBox(height: 12),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildHourlyRow('Morning (6 AM - 12 PM)', 0),
                      const Divider(height: 24),
                      _buildHourlyRow('Afternoon (12 PM - 6 PM)', 0),
                      const Divider(height: 24),
                      _buildHourlyRow('Evening (6 PM - 12 AM)', 0),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Shop-wise Breakdown
              if (_dailySummary['shop_sales'] != null) ...[
                Text(
                  'Shop-wise Sales',
                  style: AppTextStyles.h5,
                ),
                const SizedBox(height: 12),

                ...(_dailySummary['shop_sales'] as List? ?? []).map((shop) {
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(
                        Icons.store,
                        color: AppColors.primary,
                      ),
                      title: Text(
                        shop['name'] ?? '',
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        '${shop['transactions']} transactions',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      trailing: Text(
                        Formatters.currency(shop['total'] ?? 0),
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    color: color,
                    size: 20,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: AppTextStyles.h4.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentRow(String method, double amount, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            method,
            style: AppTextStyles.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          Formatters.currency(amount),
          style: AppTextStyles.bodyLarge.copyWith(
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildHourlyRow(String period, double amount) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          period,
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        Text(
          Formatters.currency(amount),
          style: AppTextStyles.bodyMedium.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
