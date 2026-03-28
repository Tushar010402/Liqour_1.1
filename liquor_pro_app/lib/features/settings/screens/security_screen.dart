import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../../../shared/widgets/custom_button.dart';
import 'my_devices_screen.dart';

/// Security Settings Screen
class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  bool _biometricEnabled = false;
  bool _twoFactorEnabled = false;
  bool _sessionTimeout = true;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _handleChangePassword() async {
    if (!_formKey.currentState!.validate()) return;

    // TODO: Call API to change password

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password changed successfully'),
          backgroundColor: AppColors.success,
        ),
      );

      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const CustomAppBar(
        title: 'Security',
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Change Password Section
          Text(
            'Change Password',
            style: AppTextStyles.h5,
          ),
          const SizedBox(height: 16),

          Form(
            key: _formKey,
            child: Column(
              children: [
                CustomTextField(
                  label: 'Current Password',
                  controller: _currentPasswordController,
                  obscureText: _obscureCurrentPassword,
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureCurrentPassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () {
                      setState(() => _obscureCurrentPassword = !_obscureCurrentPassword);
                    },
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter current password';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                CustomTextField(
                  label: 'New Password',
                  controller: _newPasswordController,
                  obscureText: _obscureNewPassword,
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureNewPassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () {
                      setState(() => _obscureNewPassword = !_obscureNewPassword);
                    },
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter new password';
                    }
                    if (value.length < 8) {
                      return 'Password must be at least 8 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                CustomTextField(
                  label: 'Confirm New Password',
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmPassword,
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirmPassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () {
                      setState(() => _obscureConfirmPassword = !_obscureConfirmPassword);
                    },
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please confirm password';
                    }
                    if (value != _newPasswordController.text) {
                      return 'Passwords do not match';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                CustomButton(
                  text: 'Change Password',
                  onPressed: _handleChangePassword,
                  icon: Icons.check,
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 24),

          // My Devices Section
          Text(
            'Device Management',
            style: AppTextStyles.h5,
          ),
          const SizedBox(height: 16),

          Card(
            child: ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.devices_outlined,
                  color: cs.primary,
                ),
              ),
              title: Text(
                'My Devices',
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                'Manage logged-in devices',
                style: AppTextStyles.bodySmall.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              trailing: Icon(
                Icons.chevron_right,
                color: cs.onSurfaceVariant,
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const MyDevicesScreen(),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 24),

          // Security Options
          Text(
            'Security Options',
            style: AppTextStyles.h5,
          ),
          const SizedBox(height: 16),

          Card(
            child: SwitchListTile(
              title: Text(
                'Biometric Authentication',
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                'Use fingerprint or face ID to login',
                style: AppTextStyles.bodySmall.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              secondary: Icon(
                Icons.fingerprint,
                color: cs.primary,
              ),
              value: _biometricEnabled,
              onChanged: (value) {
                setState(() => _biometricEnabled = value);
                // TODO: Enable/disable biometric authentication
              },
              activeThumbColor: cs.primary,
            ),
          ),
          const SizedBox(height: 8),

          Card(
            child: SwitchListTile(
              title: Text(
                'Two-Factor Authentication',
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                'Add an extra layer of security',
                style: AppTextStyles.bodySmall.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              secondary: Icon(
                Icons.security,
                color: cs.primary,
              ),
              value: _twoFactorEnabled,
              onChanged: (value) {
                setState(() => _twoFactorEnabled = value);
                // TODO: Enable/disable 2FA
              },
              activeThumbColor: cs.primary,
            ),
          ),
          const SizedBox(height: 8),

          Card(
            child: SwitchListTile(
              title: Text(
                'Auto Logout',
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                'Automatically logout after 30 minutes of inactivity',
                style: AppTextStyles.bodySmall.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              secondary: Icon(
                Icons.timer_outlined,
                color: cs.primary,
              ),
              value: _sessionTimeout,
              onChanged: (value) {
                setState(() => _sessionTimeout = value);
                // TODO: Enable/disable session timeout
              },
              activeThumbColor: cs.primary,
            ),
          ),

          const SizedBox(height: 24),

          // Password Requirements Info
          Card(
            color: cs.primary.withValues(alpha:0.1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: cs.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Password Requirements',
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildRequirement('At least 8 characters'),
                  _buildRequirement('Mix of uppercase and lowercase letters'),
                  _buildRequirement('Include numbers'),
                  _buildRequirement('Include special characters (!@#\$%^&*)'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequirement(String text) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 16,
            color: cs.primary,
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: AppTextStyles.bodySmall.copyWith(
              color: cs.primary,
            ),
          ),
        ],
      ),
    );
  }
}
