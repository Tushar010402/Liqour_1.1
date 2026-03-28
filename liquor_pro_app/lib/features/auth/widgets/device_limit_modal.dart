import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../models/device_session_models.dart';

/// Modal shown when login fails due to device limit (409 error)
/// Allows user to select a device to logout or force login
class DeviceLimitModal extends StatefulWidget {
  final DeviceLimitError error;
  final Function(String sessionId) onLogoutDevice;
  final VoidCallback onForceLogin;
  final VoidCallback onCancel;

  const DeviceLimitModal({
    super.key,
    required this.error,
    required this.onLogoutDevice,
    required this.onForceLogin,
    required this.onCancel,
  });

  @override
  State<DeviceLimitModal> createState() => _DeviceLimitModalState();

  /// Show the device limit modal as a bottom sheet
  static Future<void> show({
    required BuildContext context,
    required DeviceLimitError error,
    required Function(String sessionId) onLogoutDevice,
    required VoidCallback onForceLogin,
    required VoidCallback onCancel,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => DeviceLimitModal(
        error: error,
        onLogoutDevice: onLogoutDevice,
        onForceLogin: onForceLogin,
        onCancel: onCancel,
      ),
    );
  }
}

class _DeviceLimitModalState extends State<DeviceLimitModal> {
  String? _selectedSessionId;
  bool _isLoading = false;

  /// Get devices that can be logged out (excludes current device)
  List<DeviceSession> get _removableDevices {
    return widget.error.activeDevices
        .where((device) => !device.isCurrent)
        .toList();
  }

  /// Check if there are removable devices available
  bool get _hasRemovableDevices => _removableDevices.isNotEmpty;

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
      return DateFormat('MMM d').format(lastActive);
    }
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
    }
    return Icons.devices;
  }

  Future<void> _handleLogoutDevice() async {
    if (_selectedSessionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a device to logout'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await widget.onLogoutDevice(_selectedSessionId!);
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

  Future<void> _handleForceLogin() async {
    setState(() => _isLoading = true);
    try {
      widget.onForceLogin();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to login: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha:0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.devices_other,
                      color: AppColors.warning,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Device Limit Reached',
                          style: AppTextStyles.h5.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'You\'re logged in on ${widget.error.maxDevices} devices',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _isLoading ? null : widget.onCancel,
                    icon: const Icon(Icons.close),
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Message
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: AppColors.info,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.error.message,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.info,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Devices List
              if (_hasRemovableDevices) ...[
                Text(
                  'Select a device to logout:',
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),

                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.35,
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _removableDevices.length,
                    itemBuilder: (context, index) {
                      final device = _removableDevices[index];
                      final isSelected = _selectedSessionId == device.id;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: isSelected
                              ? BorderSide(color: cs.primary, width: 2)
                              : BorderSide.none,
                        ),
                        child: InkWell(
                          onTap: _isLoading
                              ? null
                              : () {
                                  setState(() {
                                    _selectedSessionId = device.id;
                                  });
                                },
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                // Radio
                                Radio<String>(
                                  value: device.id,
                                  groupValue: _selectedSessionId,
                                  onChanged: _isLoading
                                      ? null
                                      : (value) {
                                          setState(() {
                                            _selectedSessionId = value;
                                          });
                                        },
                                  activeColor: cs.primary,
                                ),
                                const SizedBox(width: 8),

                                // Device Icon
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: cs.primary.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    _getDeviceIcon(device),
                                    color: cs.primary,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),

                                // Device Info
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        device.deviceName,
                                        style: AppTextStyles.bodyMedium.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${device.osName} ${device.osVersion} • ${_formatLastActive(device.lastActiveAt)}',
                                        style: AppTextStyles.caption.copyWith(
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ] else ...[
                // No removable devices - stale session scenario
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.sync_problem_rounded,
                        color: AppColors.warning,
                        size: 40,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Session Sync Issue',
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your previous session on this device appears to be stale. Tap "Force Login" below to clear the old session and continue.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Action Buttons - Different layout based on whether there are removable devices
              if (_hasRemovableDevices) ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isLoading ? null : widget.onCancel,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.all(16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _isLoading || _selectedSessionId == null
                            ? null
                            : _handleLogoutDevice,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.all(16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          backgroundColor: cs.primary,
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Logout & Continue',
                                style: TextStyle(color: Colors.white),
                              ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Force Login Option
                Center(
                  child: TextButton(
                    onPressed: _isLoading ? null : _handleForceLogin,
                    child: Text(
                      'Force login (logout oldest device automatically)',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: cs.onSurfaceVariant,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ] else ...[
                // No removable devices - show Force Login as primary action
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleForceLogin,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      backgroundColor: cs.primary,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Clear Old Session & Login',
                            style: TextStyle(color: Colors.white),
                          ),
                  ),
                ),

                const SizedBox(height: 12),

                // Cancel Option
                Center(
                  child: TextButton(
                    onPressed: _isLoading ? null : widget.onCancel,
                    child: Text(
                      'Cancel',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
