import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:pinput/pinput.dart';
import '../../auth/providers/auth_provider.dart';

/// Delete Account Screen - Apple App Store Guideline 5.1.1(v) Compliance
/// Provides OTP-verified account deletion with clear warnings
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  // Step 1: Warning, Step 2: OTP Verification, Step 3: Confirmation
  int _currentStep = 1;
  bool _isLoading = false;
  bool _canResend = false;
  int _remainingSeconds = 0;
  Timer? _timer;
  String _otpCode = '';
  String? _sessionId;
  String? _errorMessage;
  final FocusNode _pinFocusNode = FocusNode();

  @override
  void dispose() {
    _timer?.cancel();
    _pinFocusNode.dispose();
    super.dispose();
  }

  void _startTimer() {
    _remainingSeconds = 600; // 10 minutes
    _canResend = false;

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
        } else {
          _canResend = true;
          timer.cancel();
        }
      });
    });
  }

  String get _timerText {
    final minutes = _remainingSeconds ~/ 60;
    final seconds = _remainingSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _sendOtp() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final authProvider = context.read<AuthProvider>();
    final response = await authProvider.requestDeleteAccountOtp();

    if (!mounted) return;

    if (response != null) {
      setState(() {
        _sessionId = response.sessionId;
        _currentStep = 2;
        _isLoading = false;
      });
      _startTimer();

      // Auto-focus OTP input
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pinFocusNode.requestFocus();
      });
    } else {
      setState(() {
        _errorMessage = authProvider.errorMessage ?? 'Failed to send OTP';
        _isLoading = false;
      });
    }
  }

  Future<void> _verifyAndDelete() async {
    if (_otpCode.length != 6) {
      setState(() => _errorMessage = 'Please enter a valid 6-digit OTP');
      return;
    }

    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.deleteAccount(
      otp: _otpCode,
      sessionId: _sessionId ?? '',
    );

    if (!mounted) return;

    if (success) {
      setState(() {
        _currentStep = 3;
        _isLoading = false;
      });

      // Navigate to login after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          context.goNamed('phone-input');
        }
      });
    } else {
      setState(() {
        _errorMessage = authProvider.errorMessage ?? 'Failed to delete account';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Delete Account'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: cs.onSurface,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_currentStep == 1) _buildWarningStep(),
              if (_currentStep == 2) _buildOtpStep(),
              if (_currentStep == 3) _buildSuccessStep(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWarningStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Warning Icon
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.warning_amber_rounded,
            size: 48,
            color: Colors.red.shade700,
          ),
        ),
        const SizedBox(height: 24),

        // Title
        Text(
          'Delete Your Account?',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.red.shade700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),

        // Warning message
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This action cannot be undone',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              _buildWarningItem('All your data will be permanently deleted'),
              _buildWarningItem('You will lose access to your account'),
              _buildWarningItem('All inventory, sales, and reports will be removed'),
              _buildWarningItem('You cannot recover your data after deletion'),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // What happens next
        Text(
          'What happens when you delete your account:',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),

        _buildInfoCard(Icons.phone_outlined, 'OTP Verification',
            'We will send an OTP to your registered phone number'),
        const SizedBox(height: 8),
        _buildInfoCard(Icons.timer_outlined, 'Immediate Deletion',
            'Your account will be deleted immediately after verification'),
        const SizedBox(height: 8),
        _buildInfoCard(Icons.logout_outlined, 'Automatic Logout',
            'You will be logged out from all devices'),

        const SizedBox(height: 32),

        // Error message
        if (_errorMessage != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: Colors.red.shade700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Continue button
        ElevatedButton(
          onPressed: _isLoading ? null : _sendOtp,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text(
                  'Continue with Deletion',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
        const SizedBox(height: 12),

        // Cancel button
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _buildOtpStep() {
    final cs = Theme.of(context).colorScheme;
    final authProvider = context.watch<AuthProvider>();
    final phone = authProvider.currentUser?.phone ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Icon
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.sms_outlined,
            size: 48,
            color: Colors.orange.shade700,
          ),
        ),
        const SizedBox(height: 24),

        // Title
        Text(
          'Verify Your Identity',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),

        // Subtitle
        Text(
          'Enter the 6-digit code sent to',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: cs.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          phone,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: cs.primary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),

        // OTP Input
        Pinput(
          length: 6,
          focusNode: _pinFocusNode,
          autofocus: true,
          keyboardType: TextInputType.number,
          defaultPinTheme: PinTheme(
            width: 48,
            height: 56,
            textStyle: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outlineVariant),
            ),
          ),
          focusedPinTheme: PinTheme(
            width: 48,
            height: 56,
            textStyle: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange, width: 2),
            ),
          ),
          onCompleted: (code) {
            if (mounted) {
              setState(() => _otpCode = code);
            }
          },
          onChanged: (value) {
            if (mounted) {
              setState(() => _otpCode = value);
            }
          },
          enabled: !_isLoading,
        ),
        const SizedBox(height: 16),

        // Timer
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!_canResend) ...[
              Icon(Icons.timer_outlined, size: 20, color: cs.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(
                'Resend code in $_timerText',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 14,
                ),
              ),
            ] else ...[
              TextButton(
                onPressed: _isLoading ? null : _sendOtp,
                child: Text(
                  'Resend OTP',
                  style: TextStyle(
                    color: cs.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 24),

        // Error message
        if (_errorMessage != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: Colors.red.shade700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Delete button
        ElevatedButton(
          onPressed: _isLoading ? null : _verifyAndDelete,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text(
                  'Delete My Account',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
        const SizedBox(height: 12),

        // Cancel button
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _buildSuccessStep() {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 48),

        // Success Icon
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.check_circle_outline,
            size: 64,
            color: Colors.green.shade700,
          ),
        ),
        const SizedBox(height: 32),

        // Title
        Text(
          'Account Deleted',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.green.shade700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),

        // Message
        Text(
          'Your account has been successfully deleted.\nYou will be redirected to the login screen.',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: cs.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),

        // Progress indicator
        const Center(
          child: CircularProgressIndicator(),
        ),
      ],
    );
  }

  Widget _buildWarningItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.close, size: 18, color: Colors.red.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.red.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(IconData icon, String title, String subtitle) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: cs.onSurface),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
