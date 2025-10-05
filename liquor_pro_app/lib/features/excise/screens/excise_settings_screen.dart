import 'package:flutter/material.dart';

class ExciseSettingsScreen extends StatefulWidget {
  const ExciseSettingsScreen({Key? key}) : super(key: key);

  @override
  State<ExciseSettingsScreen> createState() => _ExciseSettingsScreenState();
}

class _ExciseSettingsScreenState extends State<ExciseSettingsScreen> {
  bool _autoGenerateReports = true;
  bool _enableNotifications = true;
  bool _uploadReportsAutomatically = false;
  bool _biometricAuth = false;
  String _reportGenerationTime = '23:00';
  String _selectedLanguage = 'English';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: true,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection(
            title: 'General Settings',
            icon: Icons.settings,
            children: [
              _buildSwitchTile(
                title: 'Enable Notifications',
                subtitle: 'Receive alerts for compliance updates',
                value: _enableNotifications,
                onChanged: (value) {
                  setState(() => _enableNotifications = value);
                },
              ),
              _buildSwitchTile(
                title: 'Biometric Authentication',
                subtitle: 'Use fingerprint or face ID',
                value: _biometricAuth,
                onChanged: (value) {
                  setState(() => _biometricAuth = value);
                },
              ),
              _buildListTile(
                title: 'Language',
                subtitle: _selectedLanguage,
                icon: Icons.language,
                onTap: () => _showLanguageDialog(),
              ),
            ],
          ),

          const SizedBox(height: 16),

          _buildSection(
            title: 'Report Settings',
            icon: Icons.description,
            children: [
              _buildSwitchTile(
                title: 'Auto-Generate Daily Reports',
                subtitle: 'Generate reports automatically at scheduled time',
                value: _autoGenerateReports,
                onChanged: (value) {
                  setState(() => _autoGenerateReports = value);
                },
              ),
              _buildListTile(
                title: 'Report Generation Time',
                subtitle: _reportGenerationTime,
                icon: Icons.schedule,
                onTap: () => _selectTime(),
              ),
              _buildSwitchTile(
                title: 'Auto-Upload Reports',
                subtitle: 'Upload reports to portal automatically',
                value: _uploadReportsAutomatically,
                onChanged: (value) {
                  setState(() => _uploadReportsAutomatically = value);
                },
              ),
            ],
          ),

          const SizedBox(height: 16),

          _buildSection(
            title: 'License Alerts',
            icon: Icons.verified_user,
            children: [
              _buildListTile(
                title: 'Expiry Alert Period',
                subtitle: '30 days before expiry',
                icon: Icons.notifications_active,
                onTap: () => _showExpiryAlertDialog(),
              ),
              _buildListTile(
                title: 'Fee Payment Reminders',
                subtitle: 'Remind 7 days before due date',
                icon: Icons.payment,
                onTap: () => _showPaymentReminderDialog(),
              ),
            ],
          ),

          const SizedBox(height: 16),

          _buildSection(
            title: 'Data & Storage',
            icon: Icons.storage,
            children: [
              _buildListTile(
                title: 'Clear Cache',
                subtitle: 'Free up storage space',
                icon: Icons.cleaning_services,
                onTap: () => _showClearCacheDialog(),
              ),
              _buildListTile(
                title: 'Backup Data',
                subtitle: 'Create a backup of your data',
                icon: Icons.backup,
                onTap: () => _showBackupDialog(),
              ),
              _buildListTile(
                title: 'Export Reports',
                subtitle: 'Export reports as PDF or Excel',
                icon: Icons.download,
                onTap: () => _showExportDialog(),
              ),
            ],
          ),

          const SizedBox(height: 16),

          _buildSection(
            title: 'Portal Integration',
            icon: Icons.cloud,
            children: [
              _buildListTile(
                title: 'Portal Configuration',
                subtitle: 'Configure UP Excise Portal settings',
                icon: Icons.settings_ethernet,
                onTap: () => _showPortalConfigDialog(),
              ),
              _buildListTile(
                title: 'Test Connection',
                subtitle: 'Test connection to portal',
                icon: Icons.wifi,
                onTap: () => _testPortalConnection(),
              ),
            ],
          ),

          const SizedBox(height: 16),

          _buildSection(
            title: 'Security',
            icon: Icons.security,
            children: [
              _buildListTile(
                title: 'Change Password',
                subtitle: 'Update your account password',
                icon: Icons.lock,
                onTap: () => _showChangePasswordDialog(),
              ),
              _buildListTile(
                title: 'Session Timeout',
                subtitle: '30 minutes',
                icon: Icons.timer,
                onTap: () => _showSessionTimeoutDialog(),
              ),
            ],
          ),

          const SizedBox(height: 16),

          _buildSection(
            title: 'Support',
            icon: Icons.help,
            children: [
              _buildListTile(
                title: 'Help Center',
                subtitle: 'Get help and support',
                icon: Icons.help_center,
                onTap: () => _showHelpCenter(),
              ),
              _buildListTile(
                title: 'Contact Support',
                subtitle: 'Reach out to our support team',
                icon: Icons.support_agent,
                onTap: () => _showContactSupport(),
              ),
              _buildListTile(
                title: 'Send Feedback',
                subtitle: 'Help us improve the app',
                icon: Icons.feedback,
                onTap: () => _showFeedbackDialog(),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // App Version
          Center(
            child: Column(
              children: [
                Icon(Icons.local_police, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 8),
                Text(
                  'UP Excise Compliance',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Version 1.0.0',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.blue[700]),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const Divider(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildListTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
    );
  }

  void _showLanguageDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Language'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<String>(
              title: const Text('English'),
              value: 'English',
              groupValue: _selectedLanguage,
              onChanged: (value) {
                setState(() => _selectedLanguage = value!);
                Navigator.pop(context);
              },
            ),
            RadioListTile<String>(
              title: const Text('हिन्दी (Hindi)'),
              value: 'Hindi',
              groupValue: _selectedLanguage,
              onChanged: (value) {
                setState(() => _selectedLanguage = value!);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.parse(_reportGenerationTime.split(':')[0]),
        minute: int.parse(_reportGenerationTime.split(':')[1]),
      ),
    );

    if (time != null) {
      setState(() {
        _reportGenerationTime = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
      });
    }
  }

  void _showExpiryAlertDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Expiry Alert Period'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Select when to receive license expiry alerts:'),
            const SizedBox(height: 16),
            ...['15 days', '30 days', '45 days', '60 days'].map((period) => RadioListTile<String>(
                  title: Text(period),
                  value: period,
                  groupValue: '30 days',
                  onChanged: (value) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Alert period set to $value')),
                    );
                  },
                )),
          ],
        ),
      ),
    );
  }

  void _showPaymentReminderDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Payment Reminders'),
        content: const Text('Configure when to receive payment reminders.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showClearCacheDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Cache'),
        content: const Text('This will clear all cached data. Do you want to continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Cache cleared successfully')),
              );
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _showBackupDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Backup Data'),
        content: const Text('Create a backup of your excise data?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Backup created successfully')),
              );
            },
            child: const Text('Backup'),
          ),
        ],
      ),
    );
  }

  void _showExportDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export Reports'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf),
              title: const Text('Export as PDF'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Exporting as PDF...')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.table_chart),
              title: const Text('Export as Excel'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Exporting as Excel...')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showPortalConfigDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Portal Configuration'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            TextField(
              decoration: InputDecoration(
                labelText: 'Portal URL',
                hintText: 'https://excise.up.gov.in',
              ),
            ),
            SizedBox(height: 16),
            TextField(
              decoration: InputDecoration(
                labelText: 'API Key',
                hintText: 'Enter your API key',
              ),
              obscureText: true,
            ),
          ],
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
                const SnackBar(content: Text('Configuration saved')),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _testPortalConnection() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Testing connection...'),
          ],
        ),
      ),
    );

    // Simulate connection test
    Future.delayed(const Duration(seconds: 2), () {
      Navigator.pop(context);
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text('Connection Successful'),
            ],
          ),
          content: const Text('Successfully connected to UP Excise Portal.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    });
  }

  void _showChangePasswordDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            TextField(
              decoration: InputDecoration(labelText: 'Current Password'),
              obscureText: true,
            ),
            SizedBox(height: 16),
            TextField(
              decoration: InputDecoration(labelText: 'New Password'),
              obscureText: true,
            ),
            SizedBox(height: 16),
            TextField(
              decoration: InputDecoration(labelText: 'Confirm Password'),
              obscureText: true,
            ),
          ],
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
                const SnackBar(content: Text('Password changed successfully')),
              );
            },
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }

  void _showSessionTimeoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Session Timeout'),
        content: const Text('Configure automatic logout time.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showHelpCenter() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Help Center')),
          body: const Center(child: Text('Help Center Coming Soon')),
        ),
      ),
    );
  }

  void _showContactSupport() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Contact Support'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('Email: support@excise.up.gov.in'),
            SizedBox(height: 8),
            Text('Phone: 1800-XXX-XXXX'),
            SizedBox(height: 8),
            Text('Hours: Mon-Fri, 9 AM - 6 PM'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showFeedbackDialog() {
    final feedbackController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send Feedback'),
        content: TextField(
          controller: feedbackController,
          decoration: const InputDecoration(
            hintText: 'Share your thoughts...',
            border: OutlineInputBorder(),
          ),
          maxLines: 5,
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
                const SnackBar(content: Text('Thank you for your feedback!')),
              );
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }
}
