import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _emailNotifications = true;
  bool _pushNotifications = false;
  bool _maintenanceMode = false;
  bool _debugMode = false;
  String _selectedTheme = 'System';
  String _selectedTimezone = 'UTC';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGray,
      appBar: _buildAppBar(),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 16),
            _buildGeneralSettings(),
            const SizedBox(height: 16),
            _buildNotificationSettings(),
            const SizedBox(height: 16),
            _buildSystemSettings(),
            const SizedBox(height: 16),
            _buildSecuritySettings(),
            const SizedBox(height: 16),
            _buildAdvancedSettings(),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text('Settings'),
      backgroundColor: AppColors.white,
      elevation: 0,
      foregroundColor: AppColors.primaryBlack,
      actions: [
        IconButton(
          icon: const Icon(Icons.save),
          onPressed: () => _saveSettings(),
          tooltip: 'Save Settings',
        ),
        IconButton(
          icon: const Icon(Icons.restore),
          onPressed: () => _resetSettings(),
          tooltip: 'Reset to Defaults',
        ),
      ],
    );
  }

  Widget _buildGeneralSettings() {
    return _buildSettingsSection(
      title: 'General Settings',
      children: [
        _buildDropdownSetting(
          'Theme',
          _selectedTheme,
          ['System', 'Light', 'Dark'],
          (value) => setState(() => _selectedTheme = value),
          Icons.palette,
        ),
        _buildDropdownSetting(
          'Timezone',
          _selectedTimezone,
          ['UTC', 'EST', 'PST', 'IST', 'GMT'],
          (value) => setState(() => _selectedTimezone = value),
          Icons.schedule,
        ),
        _buildTextSetting(
          'Application Name',
          'LiquorPro SaaS Admin',
          Icons.business,
        ),
        _buildTextSetting(
          'Version',
          '1.0.0 (Build 123)',
          Icons.info_outline,
        ),
      ],
    );
  }

  Widget _buildNotificationSettings() {
    return _buildSettingsSection(
      title: 'Notifications',
      children: [
        _buildSwitchSetting(
          'Email Notifications',
          'Receive notifications via email',
          _emailNotifications,
          (value) => setState(() => _emailNotifications = value),
          Icons.email,
        ),
        _buildSwitchSetting(
          'Push Notifications',
          'Receive push notifications in the app',
          _pushNotifications,
          (value) => setState(() => _pushNotifications = value),
          Icons.notifications,
        ),
        _buildButtonSetting(
          'Configure Email Templates',
          'Customize notification email templates',
          Icons.email,
          () => _configureEmailTemplates(),
        ),
        _buildButtonSetting(
          'Test Notifications',
          'Send test notifications to verify setup',
          Icons.send,
          () => _testNotifications(),
        ),
      ],
    );
  }

  Widget _buildSystemSettings() {
    return _buildSettingsSection(
      title: 'System Settings',
      children: [
        _buildSwitchSetting(
          'Maintenance Mode',
          'Enable maintenance mode for system updates',
          _maintenanceMode,
          (value) => setState(() => _maintenanceMode = value),
          Icons.build,
        ),
        _buildSwitchSetting(
          'Debug Mode',
          'Enable detailed logging for debugging',
          _debugMode,
          (value) => setState(() => _debugMode = value),
          Icons.bug_report,
        ),
        _buildButtonSetting(
          'Database Settings',
          'Configure database connections and settings',
          Icons.storage,
          () => _configureDatabaseSettings(),
        ),
        _buildButtonSetting(
          'Cache Management',
          'Clear cache and configure cache settings',
          Icons.cached,
          () => _manageCacheSettings(),
        ),
      ],
    );
  }

  Widget _buildSecuritySettings() {
    return _buildSettingsSection(
      title: 'Security Settings',
      children: [
        _buildButtonSetting(
          'JWT Configuration',
          'Configure JWT token settings and expiry',
          Icons.security,
          () => _configureJWTSettings(),
        ),
        _buildButtonSetting(
          'API Rate Limiting',
          'Configure API rate limiting rules',
          Icons.speed,
          () => _configureRateLimiting(),
        ),
        _buildButtonSetting(
          'Encryption Settings',
          'Manage data encryption and security keys',
          Icons.lock,
          () => _configureEncryption(),
        ),
        _buildButtonSetting(
          'Audit Logs',
          'View and configure system audit logs',
          Icons.history,
          () => _viewAuditLogs(),
        ),
      ],
    );
  }

  Widget _buildAdvancedSettings() {
    return _buildSettingsSection(
      title: 'Advanced Settings',
      children: [
        _buildButtonSetting(
          'Environment Variables',
          'Manage system environment variables',
          Icons.settings_applications,
          () => _manageEnvironmentVariables(),
        ),
        _buildButtonSetting(
          'API Endpoints',
          'Configure and manage API endpoints',
          Icons.api,
          () => _configureAPIEndpoints(),
        ),
        _buildButtonSetting(
          'Backup & Restore',
          'Configure automated backups and restore options',
          Icons.backup,
          () => _configureBackupRestore(),
        ),
        _buildButtonSetting(
          'Integration Settings',
          'Manage third-party integrations and webhooks',
          Icons.integration_instructions,
          () => _configureIntegrations(),
        ),
        _buildDangerButtonSetting(
          'Factory Reset',
          'Reset all settings to factory defaults',
          Icons.restore,
          () => _showFactoryResetDialog(),
        ),
      ],
    );
  }

  Widget _buildSettingsSection(
      {required String title, required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: AppColors.primaryBlack,
            ),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildSwitchSetting(String title, String subtitle, bool value,
      ValueChanged<bool> onChanged, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.lightGray,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primaryRed, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.primaryBlack,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.mediumGray,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.primaryRed,
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownSetting(String title, String value, List<String> options,
      ValueChanged<String> onChanged, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.lightGray,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primaryRed, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.primaryBlack,
              ),
            ),
          ),
          DropdownButton<String>(
            value: value,
            onChanged: (newValue) => onChanged(newValue!),
            items: options.map((String option) {
              return DropdownMenuItem<String>(
                value: option,
                child: Text(option),
              );
            }).toList(),
            underline: Container(),
          ),
        ],
      ),
    );
  }

  Widget _buildTextSetting(String title, String value, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.lightGray,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primaryRed, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.primaryBlack,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.mediumGray,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButtonSetting(
      String title, String subtitle, IconData icon, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.lightGray,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.primaryRed, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.primaryBlack,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.mediumGray,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios,
                  color: AppColors.mediumGray, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDangerButtonSetting(
      String title, String subtitle, IconData icon, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.error, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.error,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.error.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios,
                  color: AppColors.error.withValues(alpha: 0.7), size: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _saveSettings() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Settings saved successfully'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  void _resetSettings() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.restore, color: AppColors.warning),
            SizedBox(width: 12),
            Text('Reset Settings'),
          ],
        ),
        content: const Text(
            'Are you sure you want to reset all settings to their default values?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _emailNotifications = true;
                _pushNotifications = false;
                _maintenanceMode = false;
                _debugMode = false;
                _selectedTheme = 'System';
                _selectedTimezone = 'UTC';
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Settings reset to defaults'),
                  backgroundColor: AppColors.success,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
              foregroundColor: AppColors.white,
            ),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  void _configureEmailTemplates() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Email templates configuration will be implemented')),
    );
  }

  void _testNotifications() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Test notification sent')),
    );
  }

  void _configureDatabaseSettings() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Database settings will be implemented')),
    );
  }

  void _manageCacheSettings() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cache management will be implemented')),
    );
  }

  void _configureJWTSettings() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('JWT configuration will be implemented')),
    );
  }

  void _configureRateLimiting() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Rate limiting configuration will be implemented')),
    );
  }

  void _configureEncryption() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Encryption settings will be implemented')),
    );
  }

  void _viewAuditLogs() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Audit logs will be implemented')),
    );
  }

  void _manageEnvironmentVariables() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content:
              Text('Environment variables management will be implemented')),
    );
  }

  void _configureAPIEndpoints() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('API endpoints configuration will be implemented')),
    );
  }

  void _configureBackupRestore() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Backup & restore configuration will be implemented')),
    );
  }

  void _configureIntegrations() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Integration settings will be implemented')),
    );
  }

  void _showFactoryResetDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning, color: AppColors.error),
            SizedBox(width: 12),
            Text('Factory Reset'),
          ],
        ),
        content: const Text(
          'This will reset ALL system settings to factory defaults. This action cannot be undone. Are you sure you want to continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content:
                      Text('Factory reset functionality will be implemented'),
                  backgroundColor: AppColors.error,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.white,
            ),
            child: const Text('Factory Reset'),
          ),
        ],
      ),
    );
  }
}
