import 'package:flutter/material.dart';
import '../../../core/services/auth_service.dart';

/// Sales Navigation Controller - Role-Based Navigation
///
/// Determines which screen should be displayed first based on user role,
/// and controls tab visibility and permissions.
class SalesNavigationController {
  final AuthService _authService;

  SalesNavigationController(this._authService);

  /// User roles (matching backend)
  static const String roleSaasAdmin =
      'saas_admin'; // SaaS platform administrator
  static const String roleTenantAdmin = 'admin';
  static const String roleManager = 'manager';
  static const String roleAssistantManager = 'assistant_manager';
  static const String roleExecutive = 'executive';
  static const String roleSalesman = 'salesman';

  /// Tab indices
  static const int tabDailyEntry = 0;
  static const int tabHistory = 1;
  static const int tabDailyReport = 2;

  /// Get user's role
  Future<String> getUserRole() async {
    final role = await _authService.getUserRole();
    return role?.toLowerCase() ?? roleExecutive; // Default to executive
  }

  /// Determine default tab index based on user role
  Future<int> getDefaultTabIndex() async {
    final role = await getUserRole();

    switch (role) {
      case roleSaasAdmin:
      case roleTenantAdmin:
        // SaaS Admin / Tenant Admin → Daily Report (analytics dashboard)
        return tabDailyReport;

      case roleManager:
      case roleAssistantManager:
        // Manager/Assistant Manager → History (monitoring)
        return tabHistory;

      case roleExecutive:
      case roleSalesman:
      default:
        // Executive/Salesman → Daily Entry (data capture)
        return tabDailyEntry;
    }
  }

  /// Get list of available tabs for the user's role
  Future<List<SalesTab>> getAvailableTabs() async {
    final role = await getUserRole();

    final List<SalesTab> allTabs = [
      SalesTab(
        index: tabDailyEntry,
        title: 'Daily Entry',
        icon: Icons.edit_document,
        roles: [
          roleExecutive,
          roleSalesman,
          roleManager,
          roleAssistantManager,
          roleTenantAdmin,
          roleSaasAdmin,
        ],
      ),
      SalesTab(
        index: tabHistory,
        title: 'History',
        icon: Icons.history,
        roles: [
          roleManager,
          roleAssistantManager,
          roleTenantAdmin,
          roleExecutive,
          roleSalesman,
          roleSaasAdmin,
        ],
      ),
      SalesTab(
        index: tabDailyReport,
        title: 'Daily Report',
        icon: Icons.analytics,
        roles: [
          roleTenantAdmin,
          roleManager,
          roleAssistantManager,
          roleSaasAdmin,
        ],
      ),
    ];

    // Filter tabs based on role permissions
    return allTabs.where((tab) => tab.roles.contains(role)).toList();
  }

  /// Check if user has permission to access a specific tab
  Future<bool> canAccessTab(int tabIndex) async {
    final availableTabs = await getAvailableTabs();
    return availableTabs.any((tab) => tab.index == tabIndex);
  }

  /// Get tab priority for the user's role
  /// Higher priority tabs should be shown more prominently
  Future<Map<int, int>> getTabPriorities() async {
    final role = await getUserRole();

    switch (role) {
      case roleSaasAdmin:
      case roleTenantAdmin:
        return {
          tabDailyReport: 1, // Highest priority
          tabHistory: 2,
          tabDailyEntry: 3,
        };

      case roleManager:
      case roleAssistantManager:
        return {
          tabHistory: 1, // Highest priority
          tabDailyReport: 2,
          tabDailyEntry: 3,
        };

      case roleExecutive:
      case roleSalesman:
      default:
        return {
          tabDailyEntry: 1, // Highest priority
          tabHistory: 2,
          // Daily Report hidden or low priority
        };
    }
  }

  /// Get tab configuration (order, visibility) for the user
  Future<TabConfiguration> getTabConfiguration() async {
    final role = await getUserRole();
    final availableTabs = await getAvailableTabs();
    final defaultIndex = await getDefaultTabIndex();
    final priorities = await getTabPriorities();

    // Sort tabs by priority
    availableTabs.sort((a, b) {
      final priorityA = priorities[a.index] ?? 99;
      final priorityB = priorities[b.index] ?? 99;
      return priorityA.compareTo(priorityB);
    });

    return TabConfiguration(
      role: role,
      tabs: availableTabs,
      defaultTabIndex: defaultIndex,
      showDailyReport: [
        roleSaasAdmin,
        roleTenantAdmin,
        roleManager,
        roleAssistantManager,
      ].contains(role),
    );
  }

  /// Get role display name
  String getRoleDisplayName(String role) {
    switch (role) {
      case roleSaasAdmin:
        return 'SaaS Administrator';
      case roleTenantAdmin:
        return 'Tenant Admin';
      case roleManager:
        return 'Manager';
      case roleAssistantManager:
        return 'Assistant Manager';
      case roleExecutive:
        return 'Executive';
      case roleSalesman:
        return 'Salesman';
      default:
        return 'User';
    }
  }

  /// Get role-specific welcome message
  String getWelcomeMessage(String role) {
    switch (role) {
      case roleSaasAdmin:
        return 'Monitor platform-wide sales and tenant performance';
      case roleTenantAdmin:
        return 'View comprehensive sales analytics and reports';
      case roleManager:
      case roleAssistantManager:
        return 'Monitor sales performance and team activity';
      case roleExecutive:
      case roleSalesman:
      default:
        return 'Record daily sales quickly and efficiently';
    }
  }

  /// Get recommended actions for role
  List<String> getRecommendedActions(String role) {
    switch (role) {
      case roleSaasAdmin:
        return [
          'Monitor all tenant sales',
          'Review platform analytics',
          'Check system health',
          'Manage tenant accounts',
        ];
      case roleTenantAdmin:
        return [
          'Review today\'s sales report',
          'Check shop performance',
          'Analyze payment trends',
          'Export monthly report',
        ];
      case roleManager:
      case roleAssistantManager:
        return [
          'Review sales history',
          'Check pending approvals',
          'Monitor team performance',
          'Process returns',
        ];
      case roleExecutive:
      case roleSalesman:
      default:
        return [
          'Enter daily sales',
          'Record product quantities',
          'Submit payment details',
          'View submission history',
        ];
    }
  }
}

/// Sales Tab Model
class SalesTab {
  final int index;
  final String title;
  final IconData icon;
  final List<String> roles; // Roles that can access this tab

  SalesTab({
    required this.index,
    required this.title,
    required this.icon,
    required this.roles,
  });
}

/// Tab Configuration Model
class TabConfiguration {
  final String role;
  final List<SalesTab> tabs;
  final int defaultTabIndex;
  final bool showDailyReport;

  TabConfiguration({
    required this.role,
    required this.tabs,
    required this.defaultTabIndex,
    required this.showDailyReport,
  });

  /// Get the actual tab controller index for a logical tab
  /// (since tabs are filtered, indices may not match)
  int? getControllerIndex(int logicalTabIndex) {
    for (int i = 0; i < tabs.length; i++) {
      if (tabs[i].index == logicalTabIndex) {
        return i;
      }
    }
    return null;
  }

  /// Get logical tab index from controller index
  int getLogicalIndex(int controllerIndex) {
    if (controllerIndex >= 0 && controllerIndex < tabs.length) {
      return tabs[controllerIndex].index;
    }
    return 0;
  }
}

/// Role Permission Helper
class RolePermissions {
  /// Check if role can create sales
  static bool canCreateSales(String role) {
    return [
      SalesNavigationController.roleExecutive,
      SalesNavigationController.roleSalesman,
      SalesNavigationController.roleManager,
      SalesNavigationController.roleAssistantManager,
      SalesNavigationController.roleSaasAdmin,
    ].contains(role);
  }

  /// Check if role can approve sales
  static bool canApproveSales(String role) {
    return [
      SalesNavigationController.roleManager,
      SalesNavigationController.roleAssistantManager,
      SalesNavigationController.roleTenantAdmin,
      SalesNavigationController.roleSaasAdmin,
    ].contains(role);
  }

  /// Check if role can view reports
  static bool canViewReports(String role) {
    return [
      SalesNavigationController.roleTenantAdmin,
      SalesNavigationController.roleManager,
      SalesNavigationController.roleAssistantManager,
      SalesNavigationController.roleSaasAdmin,
    ].contains(role);
  }

  /// Check if role can export data
  static bool canExportData(String role) {
    return [
      SalesNavigationController.roleTenantAdmin,
      SalesNavigationController.roleManager,
      SalesNavigationController.roleSaasAdmin,
    ].contains(role);
  }

  /// Check if role can manage shops
  static bool canManageShops(String role) {
    return [
      SalesNavigationController.roleTenantAdmin,
      SalesNavigationController.roleManager,
      SalesNavigationController.roleSaasAdmin,
    ].contains(role);
  }
}
