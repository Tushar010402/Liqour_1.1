import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/excise_provider.dart';
import 'compliance_dashboard_screen.dart';
import 'license_list_screen.dart';
import 'daily_report_list_screen.dart';
import 'security_code_scanner_screen.dart';
import 'excise_analytics_screen.dart';
import 'excise_settings_screen.dart';

class ExciseHomeScreen extends StatefulWidget {
  const ExciseHomeScreen({super.key});

  @override
  State<ExciseHomeScreen> createState() => _ExciseHomeScreenState();
}

class _ExciseHomeScreenState extends State<ExciseHomeScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = const [
    ComplianceDashboardScreen(),
    LicenseListScreen(),
    DailyReportListScreen(),
    SecurityCodeScannerScreen(),
    ExciseAnalyticsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ExciseProvider>().refreshAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _screens[_selectedIndex],
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
      drawer: _buildDrawer(),
    );
  }

  Widget _buildBottomNavigationBar() {
    return NavigationBar(
      selectedIndex: _selectedIndex,
      onDestinationSelected: (index) {
        setState(() => _selectedIndex = index);
      },
      elevation: 0,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard),
          label: 'Dashboard',
        ),
        NavigationDestination(
          icon: Icon(Icons.verified_user_outlined),
          selectedIcon: Icon(Icons.verified_user),
          label: 'Licenses',
        ),
        NavigationDestination(
          icon: Icon(Icons.description_outlined),
          selectedIcon: Icon(Icons.description),
          label: 'Reports',
        ),
        NavigationDestination(
          icon: Icon(Icons.qr_code_scanner_outlined),
          selectedIcon: Icon(Icons.qr_code_scanner),
          label: 'Scanner',
        ),
        NavigationDestination(
          icon: Icon(Icons.analytics_outlined),
          selectedIcon: Icon(Icons.analytics),
          label: 'Analytics',
        ),
      ],
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _buildDrawerHeader(),
          _buildDrawerItem(
            icon: Icons.dashboard,
            title: 'Dashboard',
            subtitle: 'Compliance overview',
            onTap: () {
              Navigator.pop(context);
              setState(() => _selectedIndex = 0);
            },
          ),
          _buildDrawerItem(
            icon: Icons.verified_user,
            title: 'Licenses',
            subtitle: 'Manage licenses',
            onTap: () {
              Navigator.pop(context);
              setState(() => _selectedIndex = 1);
            },
          ),
          _buildDrawerItem(
            icon: Icons.description,
            title: 'Daily Reports',
            subtitle: 'Generate & upload',
            onTap: () {
              Navigator.pop(context);
              setState(() => _selectedIndex = 2);
            },
          ),
          _buildDrawerItem(
            icon: Icons.qr_code_scanner,
            title: 'Security Codes',
            subtitle: 'Scan & manage',
            onTap: () {
              Navigator.pop(context);
              setState(() => _selectedIndex = 3);
            },
          ),
          _buildDrawerItem(
            icon: Icons.analytics,
            title: 'Analytics',
            subtitle: 'Insights & trends',
            onTap: () {
              Navigator.pop(context);
              setState(() => _selectedIndex = 4);
            },
          ),
          const Divider(height: 1),
          _buildDrawerItem(
            icon: Icons.payment,
            title: 'Payments',
            subtitle: 'Fee payments',
            onTap: () {
              Navigator.pop(context);
              // Navigate to payments screen
            },
          ),
          _buildDrawerItem(
            icon: Icons.notifications,
            title: 'Notifications',
            subtitle: 'Alerts & reminders',
            onTap: () {
              Navigator.pop(context);
              // Navigate to notifications screen
            },
          ),
          _buildDrawerItem(
            icon: Icons.help,
            title: 'Help & Support',
            subtitle: 'Get assistance',
            onTap: () {
              Navigator.pop(context);
              // Navigate to help screen
            },
          ),
          const Divider(height: 1),
          _buildDrawerItem(
            icon: Icons.settings,
            title: 'Settings',
            subtitle: 'App configuration',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ExciseSettingsScreen(),
                ),
              );
            },
          ),
          _buildDrawerItem(
            icon: Icons.info,
            title: 'About',
            subtitle: 'Version 1.0.0',
            onTap: () {
              Navigator.pop(context);
              _showAboutDialog();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerHeader() {
    return Consumer<ExciseProvider>(
      builder: (context, provider, child) {
        final dashboard = provider.dashboard;

        return DrawerHeader(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.blue[700]!,
                Colors.blue[500]!,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.local_police,
                  size: 32,
                  color: Colors.blue[700],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'UP Excise',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                dashboard != null
                    ? 'Compliance: ${dashboard.complianceScore.toInt()}%'
                    : 'Loading...',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }

  void _showAboutDialog() {
    showAboutDialog(
      context: context,
      applicationName: 'UP Excise Compliance',
      applicationVersion: '1.0.0',
      applicationIcon: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.blue[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.local_police, size: 32, color: Colors.blue[700]),
      ),
      children: [
        const Text(
          'Complete UP Excise compliance management solution for liquor shops.',
        ),
        const SizedBox(height: 16),
        const Text(
          'Features:\n'
          '• License Management\n'
          '• Auto-Generate Daily Reports\n'
          '• Security Code Tracking\n'
          '• Compliance Monitoring\n'
          '• Portal Integration',
        ),
      ],
    );
  }
}
