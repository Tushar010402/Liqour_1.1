import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../constants/app_colors.dart';
import '../constants/app_strings.dart';
import '../../routes/app_routes.dart';
import '../../features/authentication/controllers/auth_provider.dart';

class SideDrawer extends StatelessWidget {
  const SideDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.white,
      child: Column(
        children: [
          _buildDrawerHeader(context),
          Expanded(
            child: _buildDrawerItems(context),
          ),
          _buildDrawerFooter(context),
        ],
      ),
    );
  }

  Widget _buildDrawerHeader(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        final userData = authProvider.userData;
        final userName = userData?['name'] ?? 'Admin User';
        final userInitial = userName.substring(0, 1).toUpperCase();

        return ClipRect(
          child: Container(
            decoration: const BoxDecoration(
              gradient: AppColors.primaryGradient,
            ),
            child: SafeArea(
              child: SizedBox(
                height: 60,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: AppColors.white.withValues(alpha: 0.2),
                        child: Text(
                          userInitial,
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          userName,
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 3, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: const Text(
                          'ADMIN',
                          style: TextStyle(
                            color: AppColors.white,
                            fontSize: 6,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDrawerItems(BuildContext context) {
    final currentLocation = GoRouterState.of(context).uri.path;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const SizedBox(height: 8),

        // Main Navigation
        _buildSectionHeader('Main'),
        _buildDrawerItem(
          context,
          icon: Icons.dashboard_outlined,
          selectedIcon: Icons.dashboard,
          title: 'Dashboard',
          route: AppRoutes.dashboard,
          isSelected: currentLocation == AppRoutes.dashboard,
        ),
        _buildDrawerItem(
          context,
          icon: Icons.local_drink_outlined,
          selectedIcon: Icons.local_drink,
          title: '🍺 Brand Management',
          route: AppRoutes.brands,
          isSelected: currentLocation == AppRoutes.brands,
          badge: '20',
        ),
        _buildDrawerItem(
          context,
          icon: Icons.category_outlined,
          selectedIcon: Icons.category,
          title: '📁 Categories',
          route: AppRoutes.categories,
          isSelected: currentLocation == AppRoutes.categories,
          badge: '10',
        ),

        // SaaS Management
        _buildSectionHeader('SaaS Management'),
        _buildDrawerItem(
          context,
          icon: Icons.business_outlined,
          selectedIcon: Icons.business,
          title: 'Tenants',
          route: AppRoutes.tenants,
          isSelected: currentLocation == AppRoutes.tenants,
          badge: '3',
        ),
        _buildDrawerItem(
          context,
          icon: Icons.subscriptions_outlined,
          selectedIcon: Icons.subscriptions,
          title: 'Subscriptions',
          route: AppRoutes.subscriptions,
          isSelected: currentLocation == AppRoutes.subscriptions,
          badge: '12',
        ),
        _buildDrawerItem(
          context,
          icon: Icons.assignment_outlined,
          selectedIcon: Icons.assignment,
          title: 'Plans',
          route: AppRoutes.plans,
          isSelected: currentLocation.startsWith('/plans'),
        ),
        _buildDrawerItem(
          context,
          icon: Icons.local_offer_outlined,
          selectedIcon: Icons.local_offer,
          title: 'Discounts',
          route: AppRoutes.discounts,
          isSelected: currentLocation == AppRoutes.discounts,
        ),

        // Analytics & Reports
        _buildSectionHeader('Analytics & Reports'),
        _buildDrawerItem(
          context,
          icon: Icons.analytics_outlined,
          selectedIcon: Icons.analytics,
          title: 'Analytics',
          route: AppRoutes.analytics,
          isSelected: currentLocation == AppRoutes.analytics,
        ),
        _buildDrawerItem(
          context,
          icon: Icons.bar_chart_outlined,
          selectedIcon: Icons.bar_chart,
          title: 'Usage Tracking',
          route: AppRoutes.usage,
          isSelected: currentLocation == AppRoutes.usage,
        ),
        _buildDrawerItem(
          context,
          icon: Icons.trending_up_outlined,
          selectedIcon: Icons.trending_up,
          title: 'Plan Transitions',
          route: AppRoutes.transitions,
          isSelected: currentLocation == AppRoutes.transitions,
        ),

        // System & Settings
        _buildSectionHeader('System & Settings'),
        _buildDrawerItem(
          context,
          icon: Icons.settings_outlined,
          selectedIcon: Icons.settings,
          title: 'Settings',
          route: AppRoutes.settings,
          isSelected: currentLocation == AppRoutes.settings,
        ),
        _buildDrawerItem(
          context,
          icon: Icons.security_outlined,
          selectedIcon: Icons.security,
          title: 'System Health',
          route: AppRoutes.system,
          isSelected: currentLocation == AppRoutes.system,
        ),

        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.mediumGray,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildDrawerItem(
    BuildContext context, {
    required IconData icon,
    required IconData selectedIcon,
    required String title,
    required String route,
    required bool isSelected,
    String? badge,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListTile(
        leading: Icon(
          isSelected ? selectedIcon : icon,
          color: isSelected ? AppColors.primaryRed : AppColors.mediumGray,
          size: 22,
        ),
        title: Text(
          title,
          style: TextStyle(
            color: isSelected ? AppColors.primaryRed : AppColors.primaryBlack,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            fontSize: 14,
          ),
        ),
        trailing: badge != null
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color:
                      isSelected ? AppColors.primaryRed : AppColors.mediumGray,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            : null,
        selected: isSelected,
        selectedTileColor: AppColors.lightRed,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        onTap: onTap ??
            () {
              Navigator.pop(context);
              context.go(route);
            },
      ),
    );
  }

  Widget _buildDrawerFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightGray,
        border: Border(
          top: BorderSide(
            color: AppColors.borderGray.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.help_outline,
                color: AppColors.mediumGray,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Need Help?',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    Text(
                      'Contact support',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.mediumGray,
                          ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () {
                  // Handle support contact
                },
                child: const Text(
                  'Contact',
                  style: TextStyle(
                    color: AppColors.primaryRed,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _handleLogout(context),
              icon: const Icon(
                Icons.logout,
                size: 18,
                color: AppColors.error,
              ),
              label: const Text(
                'Logout',
                style: TextStyle(
                  color: AppColors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.error),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Row(
          children: [
            Icon(Icons.logout, color: AppColors.error),
            SizedBox(width: 12),
            Text('Logout'),
          ],
        ),
        content: const Text(AppStrings.confirmLogout),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(AppStrings.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context); // Close drawer
              context.read<AuthProvider>().logout();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.white,
            ),
            child: const Text(AppStrings.logout),
          ),
        ],
      ),
    );
  }
}
