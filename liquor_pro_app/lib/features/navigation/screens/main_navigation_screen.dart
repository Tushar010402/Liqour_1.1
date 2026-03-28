import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart' as provider_pkg;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/haptic_feedback.dart';
import '../../../core/utils/connectivity_helper.dart';
import '../../../core/services/offline_queue_service.dart';
import '../../../core/widgets/offline_queue_indicator.dart';
import '../../../core/providers/shop_selection_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../inventory/screens/inventory_screen.dart';
import '../../sales/widgets/sales_options_sheet.dart';
import '../../settings/screens/settings_screen.dart';
import '../../finance/screens/cash_dashboard_screen.dart';
import '../../finance/providers/cash_provider.dart';
import '../../notifications/providers/notification_provider.dart';
import '../../profile/screens/profile_screen.dart';
import 'salesman_home_screen.dart';
import 'executive_home_screen.dart';
import 'assistant_manager_home_screen.dart';
import 'manager_home_screen.dart';
import 'admin_home_screen.dart';

/// Main Navigation Screen with Bottom Navigation Bar
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  MainNavigationScreenState createState() => MainNavigationScreenState();
}

class MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  /// Switch to a specific tab index (used by child screens like Inventory back button)
  void switchToTab(int index) {
    setState(() => _currentIndex = index);
  }

  /// Determine navigation mode based on role:
  /// - salesman: 3-tab bottom nav (Home, Inventory, Profile)
  /// - executive: no bottom nav (home screen only)
  /// - others: full 5-tab bottom nav
  String _getNavMode(BuildContext context) {
    final authProvider = provider_pkg.Provider.of<AuthProvider>(context, listen: false);
    final userRole = (authProvider.currentUser?.role ?? 'salesman').toLowerCase();
    if (userRole == 'salesman') return 'salesman';
    if (userRole == 'executive') return 'executive';
    return 'full';
  }

  /// Role-based home screen routing
  Widget _getHomeScreen(String role) => switch (role) {
    'salesman'          => const SalesmanHomeScreen(),
    'executive'         => const ExecutiveHomeScreen(),
    'assistant_manager' => const AssistantManagerHomeScreen(),
    'manager'           => const ManagerHomeScreen(),
    'admin' || 'owner'  => const AdminHomeScreen(),
    _                   => const SalesmanHomeScreen(),
  };

  /// Returns screens based on user role
  List<Widget> _getScreens(String role) => [
    _getHomeScreen(role),
    const InventoryScreen(),
    Container(), // Empty placeholder for Sales (shows modal instead)
    const _CashManagementWrapper(),
    const SettingsScreen(),
  ];

  final List<NavigationItem> _navItems = const [
    NavigationItem(
      icon: Icons.dashboard_rounded,
      activeIcon: Icons.dashboard_rounded,
      label: 'Dashboard',
      svgPath: 'assets/icons/home_indicator.svg',
    ),
    NavigationItem(
      icon: Icons.inventory_2_rounded,
      activeIcon: Icons.inventory_2_rounded,
      label: 'Inventory',
      svgPath: 'assets/icons/inventory_green.svg',
    ),
    NavigationItem(
      icon: Icons.point_of_sale_rounded,
      activeIcon: Icons.point_of_sale_rounded,
      label: 'Sales',
    ),
    NavigationItem(
      icon: Icons.account_balance_wallet_rounded,
      activeIcon: Icons.account_balance_wallet_rounded,
      label: 'Cash',
    ),
    NavigationItem(
      icon: Icons.settings_rounded,
      activeIcon: Icons.settings_rounded,
      label: 'Settings',
    ),
  ];

  /// Salesman 3-tab screens
  List<Widget> _getSalesmanScreens(String role) => [
    _getHomeScreen(role),
    const InventoryScreen(),
    const ProfileScreen(),
  ];

  static const List<NavigationItem> _salesmanNavItems = [
    NavigationItem(
      icon: Icons.dashboard_rounded,
      activeIcon: Icons.dashboard_rounded,
      label: 'Home',
      svgPath: 'assets/icons/home_indicator.svg',
    ),
    NavigationItem(
      icon: Icons.inventory_2_rounded,
      activeIcon: Icons.inventory_2_rounded,
      label: 'Inventory',
      svgPath: 'assets/icons/inventory_green.svg',
    ),
    NavigationItem(
      icon: Icons.person_rounded,
      activeIcon: Icons.person_rounded,
      label: 'Profile',
      svgPath: 'assets/icons/circle_user.svg',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    // Get offline queue service from provider
    final offlineQueue = provider_pkg.Provider.of<OfflineQueueService>(context, listen: false);

    // Get user role for role-based routing
    final authProvider = provider_pkg.Provider.of<AuthProvider>(context, listen: false);
    final userRole = (authProvider.currentUser?.role ?? 'salesman').toLowerCase();
    final navMode = _getNavMode(context);

    // Executive: home screen only, no bottom nav
    if (navMode == 'executive') {
      return Scaffold(
        body: Column(
          children: [
            const ConnectivityIndicator(showWhenOnline: false),
            OfflineQueueIndicator(offlineQueue: offlineQueue, showWhenEmpty: false),
            Expanded(child: _getHomeScreen(userRole)),
          ],
        ),
      );
    }

    // Salesman: 3-tab bottom nav
    if (navMode == 'salesman') {
      final salesmanScreens = _getSalesmanScreens(userRole);
      return Scaffold(
        body: Column(
          children: [
            const ConnectivityIndicator(showWhenOnline: false),
            OfflineQueueIndicator(offlineQueue: offlineQueue, showWhenEmpty: false),
            Expanded(
              child: IndexedStack(index: _currentIndex.clamp(0, 2), children: salesmanScreens),
            ),
          ],
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.15),
                blurRadius: 12,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: SafeArea(
            bottom: false,
            child: BottomNavigationBar(
              currentIndex: _currentIndex.clamp(0, 2),
              onTap: (index) async {
                await HapticFeedbackUtil.navigate();
                setState(() => _currentIndex = index);
              },
              type: BottomNavigationBarType.fixed,
              backgroundColor: Theme.of(context).colorScheme.surface,
              selectedItemColor: const Color(0xFF0D47A1),
              unselectedItemColor: const Color(0xFFB0B5BE),
              selectedFontSize: 12,
              unselectedFontSize: 11,
              selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
              iconSize: 24,
              elevation: 0,
              items: _salesmanNavItems.map((item) {
                return BottomNavigationBarItem(
                  icon: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: item.svgPath != null
                        ? SvgPicture.asset(item.svgPath!, width: 24, height: 24,
                            colorFilter: const ColorFilter.mode(Color(0xFFB0B5BE), BlendMode.srcIn))
                        : Icon(item.icon),
                  ),
                  activeIcon: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: item.svgPath != null
                        ? SvgPicture.asset(item.svgPath!, width: 28, height: 28,
                            colorFilter: const ColorFilter.mode(Color(0xFF0D47A1), BlendMode.srcIn))
                        : Icon(item.activeIcon, size: 28),
                  ),
                  label: item.label,
                );
              }).toList(),
            ),
          ),
        ),
      );
    }

    // Full 5-tab nav for manager/admin
    final screens = _getScreens(userRole);

    return Scaffold(
      body: Column(
        children: [
          const ConnectivityIndicator(showWhenOnline: false),
          OfflineQueueIndicator(offlineQueue: offlineQueue, showWhenEmpty: false),
          Expanded(
            child: IndexedStack(index: _currentIndex, children: screens),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.15),
              blurRadius: 12,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: SafeArea(
          bottom: false,
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) async {
              await HapticFeedbackUtil.navigate();

              if (index == 2) {
                showSalesOptionsSheet(context);
                return;
              }

              setState(() {
                _currentIndex = index;
              });
            },
            type: BottomNavigationBarType.fixed,
            backgroundColor: Theme.of(context).colorScheme.surface,
            selectedItemColor: Theme.of(context).colorScheme.primary,
            unselectedItemColor: Theme.of(context).colorScheme.onSurfaceVariant,
            selectedFontSize: 12,
            unselectedFontSize: 11,
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
            iconSize: 24,
            elevation: 0,
            items: _navItems.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;

              if (index == 3) {
                return BottomNavigationBarItem(
                  icon: _PendingApprovalBadge(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Icon(item.icon),
                    ),
                  ),
                  activeIcon: _PendingApprovalBadge(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Icon(item.activeIcon, size: 28),
                    ),
                  ),
                  label: item.label,
                );
              }

              if (index == 4) {
                return BottomNavigationBarItem(
                  icon: _NotificationBadge(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Icon(item.icon),
                    ),
                  ),
                  activeIcon: _NotificationBadge(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Icon(item.activeIcon, size: 28),
                    ),
                  ),
                  label: item.label,
                );
              }

              return BottomNavigationBarItem(
                icon: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: item.svgPath != null
                      ? SvgPicture.asset(item.svgPath!, width: 24, height: 24,
                          colorFilter: ColorFilter.mode(Theme.of(context).colorScheme.onSurfaceVariant, BlendMode.srcIn))
                      : Icon(item.icon),
                ),
                activeIcon: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: item.svgPath != null
                      ? SvgPicture.asset(item.svgPath!, width: 28, height: 28,
                          colorFilter: ColorFilter.mode(Theme.of(context).colorScheme.primary, BlendMode.srcIn))
                      : Icon(item.activeIcon, size: 28),
                ),
                label: item.label,
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class NavigationItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String? svgPath;

  const NavigationItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.svgPath,
  });
}

/// Wrapper widget to provide shop and role context to Cash Dashboard
class _CashManagementWrapper extends StatelessWidget {
  const _CashManagementWrapper();

  @override
  Widget build(BuildContext context) {
    final shopProvider = provider_pkg.Provider.of<ShopSelectionProvider>(context);
    final authProvider = provider_pkg.Provider.of<AuthProvider>(context);

    final shopId = shopProvider.selectedShopId;
    final userRole = authProvider.currentUser?.role ?? 'salesman';

    if (shopId == null) {
      final cs = Theme.of(context).colorScheme;
      return Scaffold(
        appBar: AppBar(title: const Text('Cash Management')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.store_outlined, size: 64, color: cs.onSurfaceVariant),
                const SizedBox(height: 16),
                Text(
                  'Please select a shop to view cash management',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return CashDashboardScreen(shopId: shopId, userRole: userRole);
  }
}

/// Badge widget that shows pending approval count using Riverpod
/// Uses Consumer widget to access Riverpod providers from a non-Riverpod context
class _PendingApprovalBadge extends ConsumerWidget {
  final Widget child;

  const _PendingApprovalBadge({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Get shop from Provider context
    final shopProvider = provider_pkg.Provider.of<ShopSelectionProvider>(context, listen: false);
    final authProvider = provider_pkg.Provider.of<AuthProvider>(context, listen: false);
    final shopId = shopProvider.selectedShopId;
    final userRole = authProvider.currentUser?.role ?? 'salesman';

    // Only show badge for managers and admins
    final isManagerOrAdmin = userRole.toLowerCase() == 'manager' ||
        userRole.toLowerCase() == 'admin' ||
        userRole.toLowerCase() == 'owner';

    if (!isManagerOrAdmin || shopId == null) {
      return child;
    }

    // Watch pending counts from Riverpod providers
    final pendingSubmissions = ref.watch(pendingSubmissionsProvider(null));
    final pendingCollections = ref.watch(pendingCollectionsProvider(shopId));
    final pendingRequests = ref.watch(pendingCashRequestsProvider(shopId));

    // Calculate total pending count
    int totalPending = 0;

    if (pendingSubmissions.hasValue) {
      totalPending += pendingSubmissions.value?.length ?? 0;
    }
    if (pendingCollections.hasValue) {
      totalPending += pendingCollections.value?.length ?? 0;
    }
    if (pendingRequests.hasValue) {
      totalPending += pendingRequests.value?.length ?? 0;
    }

    if (totalPending == 0) {
      return child;
    }

    return Badge(
      label: Text(
        totalPending > 99 ? '99+' : totalPending.toString(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      backgroundColor: Colors.red,
      child: child,
    );
  }
}

/// Badge widget that shows unread notification count using Riverpod
/// Uses Consumer widget to access Riverpod providers from a non-Riverpod context
class _NotificationBadge extends ConsumerWidget {
  final Widget child;

  const _NotificationBadge({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch unread notification count from Riverpod provider
    final unreadCountAsync = ref.watch(unreadCountProvider);

    return unreadCountAsync.when(
      data: (count) {
        if (count == 0) {
          return child;
        }

        return Badge(
          label: Text(
            count > 99 ? '99+' : count.toString(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
          child: child,
        );
      },
      loading: () => child,
      error: (_, __) => child,
    );
  }
}
