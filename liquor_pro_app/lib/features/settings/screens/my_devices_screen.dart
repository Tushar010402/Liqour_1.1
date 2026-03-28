import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/dio_api_service.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../auth/models/device_session_models.dart';
import '../../auth/services/device_session_service.dart';
import 'package:get_it/get_it.dart';

/// My Devices Screen - Swiggy/Zomato style device management
/// Shows all active sessions with ability to logout devices remotely
class MyDevicesScreen extends StatefulWidget {
  const MyDevicesScreen({super.key});

  @override
  State<MyDevicesScreen> createState() => _MyDevicesScreenState();
}

class _MyDevicesScreenState extends State<MyDevicesScreen> {
  late DeviceSessionService _sessionService;
  bool _isLoading = true;
  String? _error;
  DeviceSessionsResponse? _sessionsResponse;

  @override
  void initState() {
    super.initState();
    _sessionService = DeviceSessionService(GetIt.I<DioApiService>());
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await _sessionService.getActiveSessions();
      if (mounted) {
        setState(() {
          _sessionsResponse = response;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _logoutDevice(DeviceSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout Device?'),
        content: Text(
          'Are you sure you want to logout from "${session.deviceName}"?\n\n'
          'This device will need to login again to access the app.',
        ),
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

    if (confirmed != true) return;

    try {
      setState(() => _isLoading = true);
      await _sessionService.logoutDevice(session.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${session.deviceName} has been logged out'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadSessions();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to logout device: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _logoutAllOtherDevices() async {
    final otherDevices = _sessionsResponse?.sessions
            .where((s) => !s.isCurrent)
            .length ?? 0;

    if (otherDevices == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No other devices to logout'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout All Other Devices?'),
        content: Text(
          'Are you sure you want to logout from $otherDevices other device(s)?\n\n'
          'Those devices will need to login again to access the app.',
        ),
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
            child: const Text('Logout All'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      setState(() => _isLoading = true);
      await _sessionService.logoutAllDevices(excludeCurrent: true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$otherDevices device(s) have been logged out'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadSessions();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to logout devices: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  String _formatLastActive(DateTime? lastActive) {
    if (lastActive == null) return 'Unknown';

    final now = DateTime.now();
    final difference = now.difference(lastActive);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return DateFormat('MMM d, yyyy').format(lastActive);
    }
  }

  String _formatLoginDate(DateTime? loginAt) {
    if (loginAt == null) return 'Unknown';
    return DateFormat('MMM d, yyyy \'at\' h:mm a').format(loginAt);
  }

  IconData _getDeviceIcon(DeviceSession session) {
    final osName = session.osName.toLowerCase();
    final deviceType = session.deviceType.toLowerCase();

    if (osName.contains('ios') || osName.contains('macos')) {
      if (deviceType.contains('tablet')) {
        return Icons.tablet_mac;
      }
      return Icons.phone_iphone;
    } else if (osName.contains('android')) {
      if (deviceType.contains('tablet')) {
        return Icons.tablet_android;
      }
      return Icons.phone_android;
    } else if (deviceType.contains('desktop') || osName.contains('windows') || osName.contains('linux')) {
      return Icons.computer;
    } else if (deviceType.contains('web')) {
      return Icons.language;
    }
    return Icons.devices;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(
        title: 'My Devices',
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: AppColors.error.withValues(alpha:0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load devices',
              style: AppTextStyles.h5,
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: AppTextStyles.bodySmall.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadSessions,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final sessions = _sessionsResponse?.sessions ?? [];

    return RefreshIndicator(
      onRefresh: _loadSessions,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header Info
          _buildInfoCard(),
          const SizedBox(height: 24),

          // Devices List
          Text(
            'Active Sessions (${sessions.length}/${_sessionsResponse?.maxDevices ?? 2})',
            style: AppTextStyles.h5,
          ),
          const SizedBox(height: 16),

          if (sessions.isEmpty)
            _buildEmptyState()
          else
            ...sessions.map((session) => _buildDeviceCard(session)),

          const SizedBox(height: 24),

          // Logout All Button
          if (sessions.where((s) => !s.isCurrent).isNotEmpty)
            OutlinedButton.icon(
              onPressed: _logoutAllOtherDevices,
              icon: const Icon(Icons.logout, color: AppColors.error),
              label: Text(
                'Logout All Other Devices',
                style: TextStyle(color: AppColors.error),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppColors.error.withValues(alpha:0.5)),
                padding: const EdgeInsets.all(16),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.primary.withValues(alpha:0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              Icons.info_outline,
              color: cs.primary,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Device Limit',
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'You can be logged in on up to ${_sessionsResponse?.maxDevices ?? 2} devices at a time. Logout from a device to login on a new one.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: cs.primary,
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

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.devices_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha:0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No Active Sessions',
              style: AppTextStyles.h5,
            ),
            const SizedBox(height: 8),
            Text(
              'You are not logged in on any devices.',
              style: AppTextStyles.bodySmall.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceCard(DeviceSession session) {
    final cs = Theme.of(context).colorScheme;
    final isCurrentDevice = session.isCurrent;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isCurrentDevice
            ? BorderSide(color: AppColors.success.withValues(alpha:0.5), width: 1.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Device Icon
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isCurrentDevice
                        ? AppColors.success.withValues(alpha:0.1)
                        : cs.primary.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _getDeviceIcon(session),
                    color: isCurrentDevice ? AppColors.success : cs.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),

                // Device Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              session.deviceName,
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isCurrentDevice) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.success.withValues(alpha:0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'This Device',
                                style: AppTextStyles.caption.copyWith(
                                  color: AppColors.success,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${session.osName} ${session.osVersion}',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),

                // Logout Button (not for current device)
                if (!isCurrentDevice)
                  IconButton(
                    onPressed: () => _logoutDevice(session),
                    icon: const Icon(Icons.logout),
                    color: AppColors.error,
                    tooltip: 'Logout this device',
                  ),
              ],
            ),

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // Additional Info
            Row(
              children: [
                _buildInfoChip(
                  icon: Icons.access_time,
                  label: 'Last active',
                  value: _formatLastActive(session.lastActiveAt),
                ),
                const SizedBox(width: 16),
                _buildInfoChip(
                  icon: Icons.login,
                  label: 'Logged in',
                  value: _formatLoginDate(session.loginAt),
                ),
              ],
            ),

            // Location/IP (if available)
            if (session.loginLocation != null || session.ipAddress != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    size: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      session.loginLocation ??
                        (session.ipAddress != null ? 'IP: ${session.ipAddress}' : 'Unknown location'),
                      style: AppTextStyles.caption.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],

            // App Version
            if (session.appVersion.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'App v${session.appVersion}',
                    style: AppTextStyles.caption.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Expanded(
      child: Row(
        children: [
          Icon(
            icon,
            size: 14,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.caption.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
                Text(
                  value,
                  style: AppTextStyles.caption.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
