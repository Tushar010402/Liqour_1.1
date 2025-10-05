import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/logger.dart';
import '../providers/auth_provider.dart';
import 'otp_verification_screen.dart';

/// Phone Input Screen - First step in authentication
class PhoneInputScreen extends StatefulWidget {
  const PhoneInputScreen({super.key});

  @override
  State<PhoneInputScreen> createState() => _PhoneInputScreenState();
}

class _PhoneInputScreenState extends State<PhoneInputScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  String _formatPhoneNumber(String phone) {
    // Remove all non-digit characters
    String digitsOnly = phone.replaceAll(RegExp(r'\D'), '');

    // If it starts with 91, add + prefix
    if (digitsOnly.startsWith('91') && digitsOnly.length > 10) {
      return '+$digitsOnly';
    }

    // If it's 10 digits, add +91 prefix
    if (digitsOnly.length == 10) {
      return '+91$digitsOnly';
    }

    // If it already has +, return as-is
    if (phone.startsWith('+')) {
      return phone;
    }

    // Otherwise return with + prefix
    return '+$digitsOnly';
  }

  Future<void> _handleContinue() async {
    if (!_formKey.currentState!.validate()) return;

    if (!mounted) return;
    setState(() => _isLoading = true);

    final authProvider = context.read<AuthProvider>();
    final phone = _formatPhoneNumber(_phoneController.text.trim());

    Logger.debug('Phone input: ${_phoneController.text.trim()}');
    Logger.debug('Formatted phone: $phone');

    // Step 1: Check if user exists
    Logger.info('Checking if user exists');
    final checkResponse = await authProvider.checkUser(phone);
    Logger.debug('Check response', checkResponse);

    try {
      if (!mounted) {
        Logger.warning('Widget unmounted after checkUser');
        return;
      }
      setState(() => _isLoading = false);

      if (checkResponse == null) {
        // Error occurred - show error from provider
        Logger.error('Check user response is null');
        if (mounted && authProvider.errorMessage != null) {
          _showError(authProvider.errorMessage!);
        }
        return;
      }

      Logger.debug('User exists: ${checkResponse.exists}');
      if (checkResponse.exists) {
      // Existing user - send OTP for login
      Logger.info('User exists, sending OTP');
      if (!mounted) return;
      setState(() => _isLoading = true);
      final sendOtpResponse = await authProvider.sendOtp(phone);
      Logger.debug('Send OTP response', sendOtpResponse);
      if (!mounted) return;
      setState(() => _isLoading = false);

      if (sendOtpResponse != null && mounted) {
        Logger.info('OTP sent, navigating to verification');
        // Navigate to OTP verification for login
        context.pushNamed(
          'otp-verification',
          extra: {
            'phone': phone,
            'sessionId': sendOtpResponse.sessionId,
            'expiresAt': sendOtpResponse.expiresAt,
            'isRegistration': false,
          },
        );
      } else if (mounted && authProvider.errorMessage != null) {
        Logger.error('OTP send failed', authProvider.errorMessage);
        _showError(authProvider.errorMessage!);
      } else {
        Logger.warning('No response and no error message');
      }
    } else {
      // New user - navigate to pre-registration to get email and name
      if (mounted) {
        context.pushNamed(
          'pre-registration',
          extra: {'phone': phone},
        );
      }
    }
    } catch (e, stackTrace) {
      Logger.error('Exception in phone input continue', e, stackTrace);
      if (mounted) {
        setState(() => _isLoading = false);
        _showError('An error occurred: $e');
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String? _validatePhone(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your phone number';
    }
    // Remove any non-digit characters for validation
    final digitsOnly = value.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.length < 10) {
      return 'Please enter a valid phone number';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 60),

                // Logo/Title
                Text(
                  'LiquorPro',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryColor,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 8),

                Text(
                  'Welcome back',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 60),

                // Phone input
                Text(
                  'Enter your phone number',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 16),

                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    hintText: '+91 98765 43210',
                    prefixIcon: const Icon(Icons.phone_android_rounded),
                    suffixIcon: Icon(Icons.check_circle_rounded, color: Colors.grey[300]),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                        color: AppTheme.primaryColor,
                        width: 2,
                      ),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                  ),
                  validator: _validatePhone,
                  enabled: !_isLoading,
                ),

                const SizedBox(height: 24),

                // Continue button
                ElevatedButton(
                  onPressed: _isLoading ? null : _handleContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Text(
                          'Continue',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),

                const Spacer(),

                // Terms and conditions
                Text(
                  'By continuing, you agree to our Terms of Service and Privacy Policy',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
