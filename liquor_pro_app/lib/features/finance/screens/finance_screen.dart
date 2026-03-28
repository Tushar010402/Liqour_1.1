import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/theme/ios_design_tokens.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../../core/providers/shop_selection_provider.dart';
import '../../auth/providers/auth_provider.dart';
import 'expenses_screen.dart';
import 'vendors_screen.dart';
import 'assistant_managers_screen.dart';
import 'cash_dashboard_modern.dart';
import 'bank_accounts_modern_screen.dart';
// New Premium Feature Modules
import '../../finance_matrix/screens/finance_matrix_screen.dart';
import '../../tips/screens/tips_screen.dart';
import '../../theft_detection/screens/theft_detection_screen.dart';
import '../../physical_audit/screens/physical_audit_screen.dart';

/// Finance Hub Screen - Access all finance features
class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key});

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {

  @override
  void initState() {
    super.initState();
    _loadFinanceData();
  }

  Future<void> _loadFinanceData() async {
    // TODO: Load finance summary from API
    await Future.delayed(const Duration(seconds: 1));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const CustomAppBar(
        title: 'Finance',
      ),
      body: RefreshIndicator(
        onRefresh: _loadFinanceData,
        child: ListView(
          padding: EdgeInsets.all(iOSDesignTokens.space16),
          children: [
            // Summary Cards
            _buildSectionHeader('Financial Overview'),
            SizedBox(height: iOSDesignTokens.space8),

            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.3,
              children: [
                _buildSummaryCard(
                  title: 'Total Expenses',
                  value: '₹0',
                  subtitle: 'This Month',
                  icon: Icons.trending_down,
                  color: AppColors.error,
                ),
                _buildSummaryCard(
                  title: 'Godams',
                  value: '0',
                  subtitle: 'Active',
                  icon: Icons.business,
                  color: cs.primary,
                ),
                _buildSummaryCard(
                  title: 'Staff',
                  value: '0',
                  subtitle: 'Employees',
                  icon: Icons.badge,
                  color: AppColors.accent,
                ),
                _buildSummaryCard(
                  title: 'Payroll',
                  value: '₹0',
                  subtitle: 'Monthly',
                  icon: Icons.payments,
                  color: AppColors.warning,
                ),
              ],
            ),

            SizedBox(height: iOSDesignTokens.space20),

            // Finance Options
            _buildSectionHeader('Finance Management'),
            SizedBox(height: iOSDesignTokens.space8),

            _buildOptionCard(
              icon: Icons.account_balance_wallet,
              title: 'Cash Management',
              subtitle: 'Track and manage hierarchical cash flow',
              color: Colors.green,
              onTap: () {
                final shopProvider = context.read<ShopSelectionProvider>();
                final authProvider = context.read<AuthProvider>();

                final shopId = shopProvider.selectedShopId;
                final userRole = authProvider.currentUser?.role ?? 'salesman';

                if (shopId != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CashDashboardModern(
                        shopId: shopId,
                        userRole: userRole,
                      ),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please select a shop first'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
              },
            ),

            _buildOptionCard(
              icon: Icons.account_balance,
              title: 'Bank Accounts',
              subtitle: 'Manage bank accounts and transactions',
              color: Colors.blue,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const BankAccountsModernScreen(),
                  ),
                );
              },
            ),

            _buildOptionCard(
              icon: Icons.receipt_long,
              title: 'Expenses',
              subtitle: 'Track and manage all expenses',
              color: AppColors.error,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ExpensesScreen(),
                  ),
                );
              },
            ),

            _buildOptionCard(
              icon: Icons.business,
              title: 'Godams',
              subtitle: 'Manage godam information',
              color: cs.primary,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const VendorsScreen(),
                  ),
                );
              },
            ),

            _buildOptionCard(
              icon: Icons.badge,
              title: 'Assistant Managers',
              subtitle: 'Manage staff and payroll',
              color: AppColors.accent,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AssistantManagersScreen(),
                  ),
                );
              },
            ),

            SizedBox(height: iOSDesignTokens.space20),

            // Premium Features Section
            _buildSectionHeader('Premium Features'),
            SizedBox(height: iOSDesignTokens.space8),

            _buildPremiumFeatureCard(
              icon: Icons.dashboard,
              title: 'Finance Matrix',
              subtitle: 'AI-powered unified dashboard combining all metrics',
              gradient: [Colors.purple.shade400, Colors.blue.shade400],
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const FinanceMatrixScreen(),
                  ),
                );
              },
            ),

            _buildPremiumFeatureCard(
              icon: Icons.security,
              title: 'Theft Detection',
              subtitle: 'Z-score anomaly detection with real-time alerts',
              gradient: [Colors.red.shade400, Colors.orange.shade400],
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const TheftDetectionScreen(),
                  ),
                );
              },
            ),

            _buildPremiumFeatureCard(
              icon: Icons.volunteer_activism,
              title: 'Tips Management',
              subtitle: 'Track tips with multiple distribution methods',
              gradient: [Colors.green.shade400, Colors.teal.shade400],
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const TipsScreen(),
                  ),
                );
              },
            ),

            _buildPremiumFeatureCard(
              icon: Icons.fact_check,
              title: 'Physical Audit',
              subtitle: 'Cash counting and inventory verification',
              gradient: [Colors.amber.shade400, Colors.orange.shade400],
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PhysicalAuditScreen(),
                  ),
                );
              },
            ),

            SizedBox(height: iOSDesignTokens.space20),

            // Quick Stats
            Builder(
              builder: (context) {
                final cs = Theme.of(context).colorScheme;
                return Container(
                  padding: EdgeInsets.all(iOSDesignTokens.space16),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
                    border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: cs.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'This Month Summary',
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontWeight: FontWeight.w600,
                              color: cs.primary,
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      _buildStatRow('Total Expenses', '₹0'),
                      const SizedBox(height: 8),
                      _buildStatRow('Godam Payments', '₹0'),
                      const SizedBox(height: 8),
                      _buildStatRow('Staff Salaries', '₹0'),
                      const SizedBox(height: 8),
                      _buildStatRow('Other Costs', '₹0'),
                      const Divider(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Net Expenses',
                            style: AppTextStyles.bodyLarge.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '₹0',
                            style: AppTextStyles.h5.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.all(iOSDesignTokens.space12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
        border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
      ),
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
                  style: AppTextStyles.caption.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      cs.primary.withValues(alpha: 0.15),
                      cs.primary.withValues(alpha: 0.06),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: cs.primary, size: 20),
              ),
            ],
          ),
          SizedBox(height: iOSDesignTokens.space8),
          Text(
            value,
            style: AppTextStyles.h4.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: iOSDesignTokens.space4),
          Text(
            subtitle,
            style: AppTextStyles.caption.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: iOSDesignTokens.space6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
          child: Container(
            padding: EdgeInsets.symmetric(
                horizontal: iOSDesignTokens.space12,
                vertical: iOSDesignTokens.space12),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
              border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
            ),
            child: Row(
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
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: cs.primary, size: 20),
                ),
                SizedBox(width: iOSDesignTokens.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: AppTextStyles.bodyMedium.copyWith(
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: AppTextStyles.caption
                              .copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.5), size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTextStyles.bodyMedium.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: AppTextStyles.bodyMedium.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: cs.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        SizedBox(width: iOSDesignTokens.space8),
        Text(title,
            style: AppTextStyles.bodyMedium.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            )),
      ],
    );
  }

  Widget _buildPremiumFeatureCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: iOSDesignTokens.space6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
          child: Container(
            padding: EdgeInsets.symmetric(
                horizontal: iOSDesignTokens.space12,
                vertical: iOSDesignTokens.space12),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
              border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
            ),
            child: Row(
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
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: cs.primary, size: 20),
                ),
                SizedBox(width: iOSDesignTokens.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: AppTextStyles.bodyMedium.copyWith(
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: AppTextStyles.caption
                              .copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.5), size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
