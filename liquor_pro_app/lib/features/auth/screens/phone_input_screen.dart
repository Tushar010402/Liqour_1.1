import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../core/utils/logger.dart';
import '../providers/auth_provider.dart';

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

    debugPrint('[PhoneInput] Raw input: "${_phoneController.text.trim()}"');
    debugPrint('[PhoneInput] Formatted phone: "$phone"');

    // Backend check-user now sends OTP and returns session info
    final checkResponse = await authProvider.checkUser(phone);

    try {
      if (!mounted) return;
      setState(() => _isLoading = false);

      debugPrint('[PhoneInput] checkUser response: sessionId=${checkResponse?.sessionId}, message="${checkResponse?.message}"');

      if (checkResponse == null) {
        if (mounted && authProvider.errorMessage != null) {
          _showError(authProvider.errorMessage!);
        }
        return;
      }

      if (!checkResponse.hasOtpSession) {
        _showError('Failed to send verification code. Please try again.');
        return;
      }

      // OTP sent — go to OTP screen. Don't pass isRegistration here;
      // the verify-otp response will tell us login vs registration.
      if (mounted) {
        context.pushNamed(
          'otp-verification',
          extra: {
            'phone': phone,
            'sessionId': checkResponse.sessionId,
            'expiresAt': checkResponse.expiresAt ?? DateTime.now().add(const Duration(minutes: 10)),
            'isRegistration': false, // Determined by verify-otp response, not check-user
          },
        );
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
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
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
                      color: cs.primary,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 8),

                  Text(
                    'Welcome back',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: cs.onSurfaceVariant,
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
                      hintText: '98765 43210',
                      prefixIcon: const Icon(Icons.phone_android_rounded),
                      suffixIcon: Icon(Icons.check_circle_rounded, color: cs.outlineVariant),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: cs.outlineVariant),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: cs.primary,
                          width: 2,
                        ),
                      ),
                      filled: true,
                      fillColor: cs.surfaceContainerHighest,
                    ),
                    validator: _validatePhone,
                    enabled: !_isLoading,
                  ),

                  const SizedBox(height: 24),

                  // Continue button
                  ElevatedButton(
                    onPressed: _isLoading ? null : _handleContinue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cs.primary,
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

                  const SizedBox(height: 40),

                  // Terms and conditions
                  Text(
                    'By continuing, you agree to our Terms of Service and Privacy Policy',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
