import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

class SystemScreen extends StatefulWidget {
  const SystemScreen({super.key});

  @override
  State<SystemScreen> createState() => _SystemScreenState();
}

class _SystemScreenState extends State<SystemScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGray,
      appBar: _buildAppBar(),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 16),
            _buildSystemStatus(),
            const SizedBox(height: 16),
            _buildSystemMetrics(),
            const SizedBox(height: 16),
            _buildServiceStatus(),
            const SizedBox(height: 16),
            _buildSystemLogs(),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text('System Management'),
      backgroundColor: AppColors.white,
      elevation: 0,
      foregroundColor: AppColors.primaryBlack,
      actions: [
        IconButton(
          icon: const Icon(Icons.settings_backup_restore),
          onPressed: () => _showBackupDialog(),
          tooltip: 'System Backup',
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => _refreshSystemStatus(),
          tooltip: 'Refresh',
        ),
      ],
    );
  }

  Widget _buildSystemStatus() {
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
          Row(
            children: [
              const Text(
                'System Status',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: AppColors.primaryBlack,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle,
                        size: 16, color: AppColors.success),
                    SizedBox(width: 4),
                    Text(
                      'All Systems Operational',
                      style: TextStyle(
                        color: AppColors.success,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
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
                  child: _buildStatusCard(
                      'CPU Usage', '65%', Icons.memory, AppColors.warning)),
              const SizedBox(width: 12),
              Expanded(
                  child: _buildStatusCard(
                      'Memory', '78%', Icons.storage, AppColors.primaryBlue)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: _buildStatusCard('Disk Space', '45%', Icons.sd_storage,
                      AppColors.success)),
              const SizedBox(width: 12),
              Expanded(
                  child: _buildStatusCard('Network', '99.9%',
                      Icons.network_check, AppColors.success)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(
      String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: AppColors.primaryBlack,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemMetrics() {
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
          const Text(
            'Performance Metrics',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: AppColors.primaryBlack,
            ),
          ),
          const SizedBox(height: 16),
          ..._buildMetricsList(),
        ],
      ),
    );
  }

  List<Widget> _buildMetricsList() {
    final metrics = [
      {
        'title': 'Average Response Time',
        'value': '245ms',
        'trend': 'up',
        'color': AppColors.success
      },
      {
        'title': 'Database Connections',
        'value': '125/200',
        'trend': 'stable',
        'color': AppColors.primaryBlue
      },
      {
        'title': 'Cache Hit Rate',
        'value': '94.2%',
        'trend': 'up',
        'color': AppColors.success
      },
      {
        'title': 'Error Rate',
        'value': '0.02%',
        'trend': 'down',
        'color': AppColors.success
      },
      {
        'title': 'Uptime',
        'value': '99.98%',
        'trend': 'stable',
        'color': AppColors.success
      },
    ];

    return metrics
        .map((metric) => _buildMetricItem(
              metric['title'] as String,
              metric['value'] as String,
              metric['trend'] as String,
              metric['color'] as Color,
            ))
        .toList();
  }

  Widget _buildMetricItem(
      String title, String value, String trend, Color color) {
    IconData trendIcon;
    switch (trend) {
      case 'up':
        trendIcon = Icons.trending_up;
        break;
      case 'down':
        trendIcon = Icons.trending_down;
        break;
      default:
        trendIcon = Icons.trending_flat;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.lightGray,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
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
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          Icon(trendIcon, color: color, size: 20),
        ],
      ),
    );
  }

  Widget _buildServiceStatus() {
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
          const Text(
            'Service Status',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: AppColors.primaryBlack,
            ),
          ),
          const SizedBox(height: 16),
          ..._buildServicesList(),
        ],
      ),
    );
  }

  List<Widget> _buildServicesList() {
    final services = [
      {
        'name': 'Auth Service',
        'status': 'Operational',
        'port': '8090',
        'uptime': '15d 6h'
      },
      {
        'name': 'SaaS Service',
        'status': 'Operational',
        'port': '8095',
        'uptime': '15d 6h'
      },
      {
        'name': 'Inventory Service',
        'status': 'Operational',
        'port': '8092',
        'uptime': '15d 6h'
      },
      {
        'name': 'Gateway Service',
        'status': 'Operational',
        'port': '8080',
        'uptime': '15d 6h'
      },
      {
        'name': 'Database',
        'status': 'Operational',
        'port': '5432',
        'uptime': '30d 12h'
      },
    ];

    return services.map((service) => _buildServiceItem(service)).toList();
  }

  Widget _buildServiceItem(Map<String, String> service) {
    Color statusColor = service['status'] == 'Operational'
        ? AppColors.success
        : AppColors.error;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.lightGray,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service['name']!,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryBlack,
                  ),
                ),
                Text(
                  'Port: ${service['port']} • Uptime: ${service['uptime']}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.mediumGray,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              service['status']!,
              style: TextStyle(
                color: statusColor,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemLogs() {
    return Container(
      margin: const EdgeInsets.all(16),
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
          Row(
            children: [
              const Text(
                'Recent System Logs',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: AppColors.primaryBlack,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => _showFullLogs(),
                child: const Text('View All'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            height: 200,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const SingleChildScrollView(
              child: Text(
                '''[2024-01-24 10:30:15] INFO: SaaS service started successfully
[2024-01-24 10:30:16] INFO: Database connection established
[2024-01-24 10:30:17] INFO: Cache initialized
[2024-01-24 10:45:23] INFO: User authenticated: admin@liquorpro.com
[2024-01-24 11:12:45] INFO: New tenant registered: TechCorp Solutions
[2024-01-24 11:25:30] WARNING: High CPU usage detected: 85%
[2024-01-24 11:26:15] INFO: CPU usage normalized: 65%
[2024-01-24 12:00:00] INFO: Daily backup completed successfully
[2024-01-24 12:15:20] INFO: Cache cleared and rebuilt
[2024-01-24 12:30:45] INFO: System health check passed''',
                style: TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 10,
                  color: AppColors.primaryBlack,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showBackupDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.backup, color: AppColors.primaryBlue),
            SizedBox(width: 12),
            Text('System Backup'),
          ],
        ),
        content: const Text('Would you like to create a system backup now?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _startBackup();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: AppColors.white,
            ),
            child: const Text('Start Backup'),
          ),
        ],
      ),
    );
  }

  void _startBackup() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('System backup started...'),
        backgroundColor: AppColors.primaryBlue,
      ),
    );
  }

  void _refreshSystemStatus() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('System status refreshed'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  void _showFullLogs() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Full logs view will be implemented'),
      ),
    );
  }
}
