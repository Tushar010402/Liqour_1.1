import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/theme/ios_design_tokens.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../../core/services/logout_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../admin/screens/shops_screen.dart';
import '../../admin/screens/user_management_screen.dart';
import '../../admin/models/user_management_models.dart';
import '../../inventory/screens/brand_onboarding_setup_screen.dart';
import '../../inventory/screens/ai_stock_setup_screen.dart';
import '../../finance/screens/vendors_screen.dart';
import '../../finance/screens/bank_accounts_modern_screen.dart';
import '../../finance/screens/expenses_screen.dart';
import 'security_screen.dart';
import 'linked_devices_screen.dart';
import 'help_support_screen.dart';
import 'expense_headers_screen.dart';
import 'debug_logs_screen.dart';
import 'logging_dashboard_screen.dart';
import '../widgets/about_dialog.dart';
import '../../finance_matrix/screens/finance_matrix_screen.dart';
import '../../theft_detection/screens/theft_detection_screen.dart';
import '../../tips/screens/tips_screen.dart';
import '../../physical_audit/screens/physical_audit_screen.dart';
import '../../notifications/screens/notification_preferences_screen.dart';
import '../../reports/screens/purcha_report_screen.dart';
import '../../profile/screens/delete_account_screen.dart';

/// Settings Screen - App settings, profile, shops
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _handleLogout(BuildContext context) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.error,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      // Centralized logout: resets ALL providers, clears caches, unregisters FCM, logs out
      await LogoutService.resetAllState(context);
      if (context.mounted) {
        context.go('/phone-login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: const CustomAppBar(
        title: 'Settings',
      ),
      body: ListView(
        padding: EdgeInsets.all(iOSDesignTokens.space16),
        children: [
          // Profile Section — JSX style white card
          Consumer<AuthProvider>(
            builder: (context, authProvider, _) {
              final user = authProvider.currentUser;
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFEAEDF1)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: const BoxDecoration(
                        color: Color(0xFF0D47A1),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        (user?.displayName ?? 'U')
                            .substring(0, 1)
                            .toUpperCase(),
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 22),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user?.displayName ?? 'User',
                              style: AppTextStyles.h5.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF1A1A2E))),
                          const SizedBox(height: 4),
                          if (user != null && user.email.isNotEmpty)
                            Text(user.email,
                                style: AppTextStyles.bodySmall
                                    .copyWith(color: const Color(0xFF888888), fontWeight: FontWeight.w500)),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0D47A1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              (user?.role ?? 'User').replaceAll('_', ' '),
                              style: AppTextStyles.caption.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded,
                        color: Color(0xFFCCCCCC)),
                  ],
                ),
              );
            },
          ),
          SizedBox(height: iOSDesignTokens.space20),

          // Theme Picker
          _buildSectionHeader('Appearance'),
          SizedBox(height: iOSDesignTokens.space8),
          _buildThemePicker(context),
          SizedBox(height: iOSDesignTokens.space20),

          // Settings Options
          _buildSectionHeader('General'),
          SizedBox(height: iOSDesignTokens.space8),

          // Manage Shops - Hidden for salesman
          Consumer<AuthProvider>(
            builder: (context, authProvider, _) {
              final userRole = (authProvider.currentUser?.role ?? '').toLowerCase();
              if (userRole == 'salesman') {
                return const SizedBox.shrink();
              }
              return _buildSettingTile(
                icon: Icons.store_outlined,
                title: 'Manage Shops',
                subtitle: 'Add or manage your shop locations',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ShopsScreen(),
                    ),
                  );
                },
              );
            },
          ),

          // User Management - Only for Admin and Manager
          Consumer<AuthProvider>(
            builder: (context, authProvider, _) {
              final userRole = authProvider.currentUser?.role ?? '';
              final canManageUsers = UserRole.canManageUsers(userRole);

              if (!canManageUsers) {
                return const SizedBox.shrink();
              }

              return _buildSettingTile(
                icon: Icons.people_outlined,
                title: 'User Management',
                subtitle: 'Manage users and their roles',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const UserManagementScreen(),
                    ),
                  );
                },
              );
            },
          ),

          // Expense Headers - Only for Admin, Manager, and Assistant Manager
          Consumer<AuthProvider>(
            builder: (context, authProvider, _) {
              final userRole = (authProvider.currentUser?.role ?? '').toLowerCase();
              // Only show for Admin, Manager, and Assistant Manager
              if (!['admin', 'manager', 'assistant_manager'].contains(userRole)) {
                return const SizedBox.shrink();
              }

              return _buildSettingTile(
                icon: Icons.receipt_long_outlined,
                title: 'Expense Headers',
                subtitle: 'Manage expense categories for daily sales',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ExpenseHeadersScreen(),
                    ),
                  );
                },
              );
            },
          ),

          // Brand Onboarding - Available for all roles
          _buildSettingTile(
            icon: Icons.local_bar_outlined,
            title: 'Brand Onboarding',
            subtitle: 'Add brands and products to your shop inventory',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const BrandOnboardingSetupScreen(),
                ),
              );
            },
          ),

          // AI Stock Setup
          _buildSettingTile(
            icon: Icons.auto_awesome,
            title: 'AI Stock Setup',
            subtitle: 'Set opening stock from register photo using AI',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AiStockSetupScreen(),
                ),
              );
            },
          ),

          // Vendor Management - Hidden for salesman
          Consumer<AuthProvider>(
            builder: (context, authProvider, _) {
              final userRole = (authProvider.currentUser?.role ?? '').toLowerCase();
              if (userRole == 'salesman') {
                return const SizedBox.shrink();
              }
              return _buildSettingTile(
                icon: Icons.business_center_outlined,
                title: 'Godam Management',
                subtitle: 'Manage godams and track payments',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const VendorsScreen(),
                    ),
                  );
                },
              );
            },
          ),

          // Bank Accounts - Only for Admin and Manager
          Consumer<AuthProvider>(
            builder: (context, authProvider, _) {
              final userRole = authProvider.currentUser?.role ?? '';
              final canManageFinance = userRole == 'admin' || userRole == 'manager';

              if (!canManageFinance) {
                return const SizedBox.shrink();
              }

              return _buildSettingTile(
                icon: Icons.account_balance_outlined,
                title: 'Bank Accounts',
                subtitle: 'Manage bank accounts for deposits',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const BankAccountsModernScreen(),
                    ),
                  );
                },
              );
            },
          ),

          // Expenses - Only for Admin and Manager
          Consumer<AuthProvider>(
            builder: (context, authProvider, _) {
              final userRole = authProvider.currentUser?.role ?? '';
              final canManageFinance = userRole == 'admin' || userRole == 'manager';

              if (!canManageFinance) {
                return const SizedBox.shrink();
              }

              return _buildSettingTile(
                icon: Icons.receipt_long_outlined,
                title: 'Expenses',
                subtitle: 'Track and manage business expenses',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ExpensesScreen(),
                    ),
                  );
                },
              );
            },
          ),

          _buildSettingTile(
            icon: Icons.notifications_outlined,
            title: 'Notifications',
            subtitle: 'Manage notification preferences',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const NotificationPreferencesScreen(),
                ),
              );
            },
          ),

          _buildSettingTile(
            icon: Icons.security_outlined,
            title: 'Security',
            subtitle: 'Change password and security settings',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SecurityScreen(),
                ),
              );
            },
          ),

          _buildSettingTile(
            icon: Icons.devices_outlined,
            title: 'Linked Devices',
            subtitle: 'Manage logged in devices',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const LinkedDevicesScreen(),
                ),
              );
            },
          ),

          // Advanced Features section
          Consumer<AuthProvider>(
            builder: (context, authProvider, _) {
              final userRole = (authProvider.currentUser?.role ?? '').toLowerCase();
              final isSalesman = userRole == 'salesman';

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: iOSDesignTokens.space20),
                  _buildSectionHeader('Advanced Features'),
                  SizedBox(height: iOSDesignTokens.space8),

                  // Finance Matrix - Hidden for salesman
                  if (!isSalesman)
                    _buildSettingTile(
                      icon: Icons.dashboard_customize_outlined,
                      title: 'Finance Matrix',
                      subtitle: 'Unified financial dashboard',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const FinanceMatrixScreen(),
                          ),
                        );
                      },
                    ),

                  // Tips Management - Hidden for salesman
                  if (!isSalesman)
                    _buildSettingTile(
                      icon: Icons.volunteer_activism_outlined,
                      title: 'Tips Management',
                      subtitle: 'Manage tips and payouts',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const TipsScreen(),
                          ),
                        );
                      },
                    ),

                  // Purcha Report - Available for all roles
                  _buildSettingTile(
                    icon: Icons.assessment_rounded,
                    title: 'Purcha Report',
                    subtitle: 'Daily stock report with opening, receipt, sale & closing',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const PurchaReportScreen(),
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),

          // Physical Audit - Manager/Admin only
          Consumer<AuthProvider>(
            builder: (context, authProvider, _) {
              final userRole = authProvider.currentUser?.role ?? '';
              final isManagerOrAdmin = userRole == 'admin' || userRole == 'manager';

              if (!isManagerOrAdmin) {
                return const SizedBox.shrink();
              }

              return _buildSettingTile(
                icon: Icons.fact_check_outlined,
                title: 'Physical Audit',
                subtitle: 'Cash counting and inventory verification',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const PhysicalAuditScreen(),
                    ),
                  );
                },
              );
            },
          ),

          // Theft Detection - Manager/Admin only
          Consumer<AuthProvider>(
            builder: (context, authProvider, _) {
              final userRole = authProvider.currentUser?.role ?? '';
              final isManagerOrAdmin = userRole == 'admin' || userRole == 'manager';

              if (!isManagerOrAdmin) {
                return const SizedBox.shrink();
              }

              return _buildSettingTile(
                icon: Icons.security_outlined,
                title: 'Theft Detection',
                subtitle: 'Anomaly alerts and investigations',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const TheftDetectionScreen(),
                    ),
                  );
                },
              );
            },
          ),

          SizedBox(height: iOSDesignTokens.space20),
          _buildSectionHeader('About'),
          SizedBox(height: iOSDesignTokens.space8),

          _buildSettingTile(
            icon: Icons.info_outlined,
            title: 'About LiquorPro',
            subtitle: 'Version 1.0.0',
            onTap: () {
              showAboutAppDialog(context);
            },
          ),

          _buildSettingTile(
            icon: Icons.help_outline,
            title: 'Help & Support',
            subtitle: 'Get help with using the app',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const HelpSupportScreen(),
                ),
              );
            },
          ),

          // Debug Logs - For troubleshooting on any device
          _buildSettingTile(
            icon: Icons.bug_report_outlined,
            title: 'Debug Logs',
            subtitle: 'View and share app logs for troubleshooting',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DebugLogsScreen(),
                ),
              );
            },
          ),

          // Logging Dashboard - Industrial-grade monitoring
          _buildSettingTile(
            icon: Icons.analytics_outlined,
            title: 'Logging Dashboard',
            subtitle: 'Industrial monitoring: logs, network, sync',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const LoggingDashboardScreen(),
                ),
              );
            },
          ),

          const SizedBox(height: 32),

          // Logout Button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _handleLogout(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              icon: const Icon(Icons.logout),
              label: const Text('Logout'),
            ),
          ),

          // Danger Zone - Delete Account (Apple App Store Guideline 5.1.1(v))
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Danger Zone',
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.error,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Once you delete your account, there is no going back. Please be certain.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.error,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DeleteAccountScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.delete_forever, color: AppColors.error),
                    label: const Text('Delete Account'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, {BuildContext? ctx}) {
    return Builder(
      builder: (context) {
        return Row(
          children: [
            Container(
              width: 3,
              height: 14,
              decoration: BoxDecoration(
                color: const Color(0xFF0D47A1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(width: iOSDesignTokens.space8),
            Text(title,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: const Color(0xFF666666),
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                )),
          ],
        );
      },
    );
  }

  Widget _buildThemePicker(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final current = themeProvider.themeKey;

    return Row(
      children: [
        _buildThemeOption(
          context: context,
          label: 'Warm White',
          key: 'warm_white',
          selected: current == 'warm_white',
          colors: [const Color(0xFFFFF8EE), const Color(0xFFE8E0D4)],
          icon: Icons.wb_sunny_rounded,
          iconColor: const Color(0xFFF59E0B),
        ),
        SizedBox(width: iOSDesignTokens.space8),
        _buildThemeOption(
          context: context,
          label: 'Cool White',
          key: 'light',
          selected: current == 'light',
          colors: [const Color(0xFFF0F7FF), const Color(0xFFDAE5F2)],
          icon: Icons.ac_unit_rounded,
          iconColor: const Color(0xFF3B82F6),
        ),
        SizedBox(width: iOSDesignTokens.space8),
        _buildThemeOption(
          context: context,
          label: 'Dark',
          key: 'dark',
          selected: current == 'dark',
          colors: [const Color(0xFF0F172A), const Color(0xFF1E293B)],
          icon: Icons.dark_mode_rounded,
          iconColor: const Color(0xFF818CF8),
        ),
      ],
    );
  }

  Widget _buildThemeOption({
    required BuildContext context,
    required String label,
    required String key,
    required bool selected,
    required List<Color> colors,
    required IconData icon,
    required Color iconColor,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: GestureDetector(
        onTap: () => context.read<ThemeProvider>().setTheme(key),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.all(iOSDesignTokens.space12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: colors,
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius:
                BorderRadius.circular(iOSDesignTokens.radiusMedium),
            border: Border.all(
              color: selected
                  ? cs.primary
                  : cs.outline.withValues(alpha: 0.3),
              width: selected ? 2 : 1,
            ),
            boxShadow: const [],
          ),
          child: Column(
            children: [
              Icon(icon, color: iconColor, size: 22),
              SizedBox(height: iOSDesignTokens.space6),
              Text(label,
                  style: AppTextStyles.caption.copyWith(
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w500,
                    color: key == 'dark'
                        ? Colors.white.withValues(alpha: 0.9)
                        : const Color(0xFF1E293B),
                    fontSize: 11,
                  )),
              if (selected) ...[
                SizedBox(height: iOSDesignTokens.space4),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return Builder(
      builder: (context) {
        final color = iconColor ?? const Color(0xFF0D47A1);
        return Padding(
          padding: EdgeInsets.only(bottom: iOSDesignTokens.space6),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFEAEDF1)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: color, size: 20),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: AppTextStyles.bodyMedium.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: const Color(0xFF1A1A2E))),
                          const SizedBox(height: 2),
                          Text(subtitle,
                              style: AppTextStyles.caption.copyWith(
                                  color: const Color(0xFF888888),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded,
                        color: Color(0xFFCCCCCC), size: 20),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
