import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../shared/widgets/custom_app_bar.dart';

/// Notifications Settings Screen
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  // Notification preferences
  bool _salesNotifications = true;
  bool _inventoryNotifications = true;
  bool _lowStockAlerts = true;
  bool _expenseNotifications = false;
  bool _dailyReports = true;
  bool _weeklyReports = false;
  bool _emailNotifications = true;
  bool _pushNotifications = true;
  bool _smsNotifications = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(
        title: 'Notifications',
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Sales Notifications
          Text(
            'Sales & Orders',
            style: AppTextStyles.h5,
          ),
          const SizedBox(height: 12),
          _buildNotificationTile(
            title: 'Sales Notifications',
            subtitle: 'Get notified when a sale is completed',
            value: _salesNotifications,
            onChanged: (value) {
              setState(() => _salesNotifications = value);
              _savePreferences();
            },
          ),
          const SizedBox(height: 24),

          // Inventory Notifications
          Text(
            'Inventory',
            style: AppTextStyles.h5,
          ),
          const SizedBox(height: 12),
          _buildNotificationTile(
            title: 'Inventory Updates',
            subtitle: 'Stock additions and adjustments',
            value: _inventoryNotifications,
            onChanged: (value) {
              setState(() => _inventoryNotifications = value);
              _savePreferences();
            },
          ),
          _buildNotificationTile(
            title: 'Low Stock Alerts',
            subtitle: 'Critical stock level warnings',
            value: _lowStockAlerts,
            onChanged: (value) {
              setState(() => _lowStockAlerts = value);
              _savePreferences();
            },
          ),
          const SizedBox(height: 24),

          // Financial Notifications
          Text(
            'Financial',
            style: AppTextStyles.h5,
          ),
          const SizedBox(height: 12),
          _buildNotificationTile(
            title: 'Expense Notifications',
            subtitle: 'New expenses and payments',
            value: _expenseNotifications,
            onChanged: (value) {
              setState(() => _expenseNotifications = value);
              _savePreferences();
            },
          ),
          const SizedBox(height: 24),

          // Reports
          Text(
            'Reports',
            style: AppTextStyles.h5,
          ),
          const SizedBox(height: 12),
          _buildNotificationTile(
            title: 'Daily Reports',
            subtitle: 'Receive daily sales summary',
            value: _dailyReports,
            onChanged: (value) {
              setState(() => _dailyReports = value);
              _savePreferences();
            },
          ),
          _buildNotificationTile(
            title: 'Weekly Reports',
            subtitle: 'Receive weekly performance reports',
            value: _weeklyReports,
            onChanged: (value) {
              setState(() => _weeklyReports = value);
              _savePreferences();
            },
          ),
          const SizedBox(height: 24),

          // Notification Channels
          Text(
            'Notification Channels',
            style: AppTextStyles.h5,
          ),
          const SizedBox(height: 12),
          _buildNotificationTile(
            title: 'Email Notifications',
            subtitle: 'Receive notifications via email',
            value: _emailNotifications,
            onChanged: (value) {
              setState(() => _emailNotifications = value);
              _savePreferences();
            },
            icon: Icons.email_outlined,
          ),
          _buildNotificationTile(
            title: 'Push Notifications',
            subtitle: 'In-app push notifications',
            value: _pushNotifications,
            onChanged: (value) {
              setState(() => _pushNotifications = value);
              _savePreferences();
            },
            icon: Icons.notifications_outlined,
          ),
          _buildNotificationTile(
            title: 'SMS Notifications',
            subtitle: 'Receive SMS for critical alerts',
            value: _smsNotifications,
            onChanged: (value) {
              setState(() => _smsNotifications = value);
              _savePreferences();
            },
            icon: Icons.message_outlined,
          ),
          const SizedBox(height: 24),

          // Quick Actions
          Card(
            color: AppColors.primary.withOpacity(0.1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: AppColors.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Quick Actions',
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _enableAll,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                          ),
                          child: const Text('Enable All'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _disableAll,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                          ),
                          child: const Text('Disable All'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    IconData? icon,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: SwitchListTile(
        title: Text(
          title,
          style: AppTextStyles.bodyMedium.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        secondary: Icon(
          icon ?? Icons.notifications_outlined,
          color: value ? AppColors.primary : AppColors.textSecondary,
        ),
        value: value,
        onChanged: onChanged,
        activeColor: AppColors.primary,
      ),
    );
  }

  void _savePreferences() {
    // TODO: Save notification preferences to backend or local storage
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Notification preferences saved'),
        backgroundColor: AppColors.success,
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _enableAll() {
    setState(() {
      _salesNotifications = true;
      _inventoryNotifications = true;
      _lowStockAlerts = true;
      _expenseNotifications = true;
      _dailyReports = true;
      _weeklyReports = true;
      _emailNotifications = true;
      _pushNotifications = true;
      _smsNotifications = true;
    });
    _savePreferences();
  }

  void _disableAll() {
    setState(() {
      _salesNotifications = false;
      _inventoryNotifications = false;
      _lowStockAlerts = false;
      _expenseNotifications = false;
      _dailyReports = false;
      _weeklyReports = false;
      _emailNotifications = false;
      _pushNotifications = false;
      _smsNotifications = false;
    });
    _savePreferences();
  }
}
