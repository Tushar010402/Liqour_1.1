import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../shared/widgets/custom_app_bar.dart';

/// Backup & Restore Screen - Data backup and recovery management
class BackupRestoreScreen extends StatefulWidget {
  const BackupRestoreScreen({super.key});

  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen> {
  bool _isLoading = false;
  bool _autoBackupEnabled = true;
  String _autoBackupFrequency = 'daily'; // daily/weekly/monthly
  bool _cloudBackupEnabled = false;
  bool _isBackingUp = false;
  double _backupProgress = 0.0;

  final List<Map<String, dynamic>> _backupHistory = [
    {
      'id': 'backup_001',
      'date': 'Jan 15, 2025 10:30 AM',
      'type': 'Automatic',
      'size': '45.2 MB',
      'location': 'Cloud Storage',
      'status': 'completed',
    },
    {
      'id': 'backup_002',
      'date': 'Jan 14, 2025 11:00 PM',
      'type': 'Automatic',
      'size': '44.8 MB',
      'location': 'Local Device',
      'status': 'completed',
    },
    {
      'id': 'backup_003',
      'date': 'Jan 13, 2025 09:15 AM',
      'type': 'Manual',
      'size': '43.5 MB',
      'location': 'Cloud Storage',
      'status': 'completed',
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadBackupSettings();
  }

  Future<void> _loadBackupSettings() async {
    setState(() => _isLoading = true);
    // TODO: Load backup settings from API - GET /api/settings/backup
    await Future.delayed(const Duration(seconds: 1));
    setState(() => _isLoading = false);
  }

  Future<void> _createBackup({bool isManual = true}) async {
    setState(() {
      _isBackingUp = true;
      _backupProgress = 0.0;
    });

    // Simulate backup progress
    for (int i = 0; i <= 100; i += 10) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) {
        setState(() => _backupProgress = i / 100);
      }
    }

    // TODO: Create backup - POST /api/backup/create
    await Future.delayed(const Duration(seconds: 1));

    if (mounted) {
      setState(() => _isBackingUp = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Backup created successfully'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<void> _restoreBackup(Map<String, dynamic> backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore Backup'),
        content: const Text(
          'Are you sure you want to restore this backup? '
          'All current data will be replaced with the backup data. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Show progress dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Restoring backup...'),
                ],
              ),
            ),
          ),
        ),
      );

      // TODO: Restore backup - POST /api/backup/restore
      await Future.delayed(const Duration(seconds: 3));

      if (mounted) {
        Navigator.pop(context); // Close progress dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Backup restored successfully. Please restart the app.'),
            backgroundColor: AppColors.success,
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _deleteBackup(Map<String, dynamic> backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Backup'),
        content: Text('Are you sure you want to delete this backup from ${backup['date']}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // TODO: Delete backup - DELETE /api/backup/:id
      setState(() {
        _backupHistory.remove(backup);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Backup deleted successfully'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    }
  }

  Future<void> _downloadBackup(Map<String, dynamic> backup) async {
    // TODO: Download backup - GET /api/backup/:id/download
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Downloading backup...'),
        backgroundColor: AppColors.info,
      ),
    );
  }

  Future<void> _uploadBackup() async {
    // TODO: Show file picker and upload backup - POST /api/backup/upload
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Select a backup file to upload'),
        backgroundColor: AppColors.info,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(
        title: 'Backup & Restore',
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Backup Now Section
                  Card(
                    color: AppColors.primary.withOpacity(0.1),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Icon(
                            Icons.backup,
                            size: 64,
                            color: AppColors.primary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Create Backup',
                            style: AppTextStyles.h5,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Back up your data to keep it safe',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.textSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          if (_isBackingUp) ...[
                            LinearProgressIndicator(
                              value: _backupProgress,
                              backgroundColor: AppColors.textSecondary.withOpacity(0.2),
                              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '${(_backupProgress * 100).toInt()}% Complete',
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ] else
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _createBackup,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                ),
                                icon: const Icon(Icons.backup),
                                label: const Text('Create Backup Now'),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Auto Backup Settings
                  Text('Automatic Backup', style: AppTextStyles.h5),
                  const SizedBox(height: 12),
                  Card(
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: const Text('Enable Auto Backup'),
                          subtitle: const Text('Automatically backup your data'),
                          value: _autoBackupEnabled,
                          activeColor: AppColors.primary,
                          onChanged: (value) {
                            setState(() => _autoBackupEnabled = value);
                            // TODO: Update setting - PATCH /api/settings/backup
                          },
                        ),
                        if (_autoBackupEnabled) ...[
                          const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Backup Frequency',
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                SegmentedButton<String>(
                                  segments: const [
                                    ButtonSegment(
                                      value: 'daily',
                                      label: Text('Daily'),
                                      icon: Icon(Icons.calendar_today, size: 16),
                                    ),
                                    ButtonSegment(
                                      value: 'weekly',
                                      label: Text('Weekly'),
                                      icon: Icon(Icons.calendar_view_week, size: 16),
                                    ),
                                    ButtonSegment(
                                      value: 'monthly',
                                      label: Text('Monthly'),
                                      icon: Icon(Icons.calendar_month, size: 16),
                                    ),
                                  ],
                                  selected: {_autoBackupFrequency},
                                  onSelectionChanged: (Set<String> selected) {
                                    setState(() => _autoBackupFrequency = selected.first);
                                    // TODO: Update setting
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  Card(
                    child: SwitchListTile(
                      title: const Text('Cloud Backup'),
                      subtitle: const Text('Store backups in cloud storage'),
                      secondary: const Icon(Icons.cloud_upload),
                      value: _cloudBackupEnabled,
                      activeColor: AppColors.primary,
                      onChanged: (value) {
                        setState(() => _cloudBackupEnabled = value);
                        // TODO: Update setting - PATCH /api/settings/backup
                      },
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Backup History
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Backup History', style: AppTextStyles.h5),
                      TextButton.icon(
                        onPressed: _uploadBackup,
                        icon: const Icon(Icons.upload_file, size: 18),
                        label: const Text('Upload'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (_backupHistory.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.history,
                                size: 64,
                                color: AppColors.textSecondary.withOpacity(0.5),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No backups yet',
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _backupHistory.length,
                      itemBuilder: (context, index) {
                        final backup = _backupHistory[index];
                        return _buildBackupCard(backup);
                      },
                    ),
                  const SizedBox(height: 24),

                  // Info Section
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.info.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.info.withOpacity(0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.info_outline, color: AppColors.info, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Backup Information',
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontWeight: FontWeight.w600,
                                color: AppColors.info,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '• Backups include all your business data (products, sales, customers, etc.)\n'
                          '• Automatic backups run at midnight in your timezone\n'
                          '• Cloud backups are encrypted for security\n'
                          '• Keep at least 3 recent backups for safety\n'
                          '• Restore will overwrite all current data',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildBackupCard(Map<String, dynamic> backup) {
    final isAutomatic = backup['type'] == 'Automatic';
    final isCloud = backup['location'] == 'Cloud Storage';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isCloud ? Icons.cloud_done : Icons.storage,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        backup['date'],
                        style: AppTextStyles.bodyLarge.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: (isAutomatic ? AppColors.primary : AppColors.info)
                                  .withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              backup['type'],
                              style: AppTextStyles.bodySmall.copyWith(
                                color: isAutomatic ? AppColors.primary : AppColors.info,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.storage,
                            size: 14,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            backup['size'],
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _restoreBackup(backup),
                    icon: const Icon(Icons.restore, size: 18),
                    label: const Text('Restore'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _downloadBackup(backup),
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('Download'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.info,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => _deleteBackup(backup),
                  icon: const Icon(Icons.delete),
                  color: AppColors.error,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
