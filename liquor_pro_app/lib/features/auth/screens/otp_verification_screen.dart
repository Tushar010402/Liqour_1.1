import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';
import 'package:pin_code_fields/pin_code_fields.dart';

/// OTP Verification Screen - Verify 6-digit OTP
class OtpVerificationScreen extends StatefulWidget {
  final String phoneNumber;
  final String sessionId;
  final DateTime expiresAt;
  final bool isRegistration; // true for registration, false for login

  const OtpVerificationScreen({
    super.key,
    required this.phoneNumber,
    required this.sessionId,
    required this.expiresAt,
    required this.isRegistration,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  String _otpCode = '';
  bool _isLoading = false;
  bool _canResend = false;
  int _remainingSeconds = 0;
  Timer? _timer;
  String? _newSessionId; // Track session ID if OTP is resent

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _remainingSeconds = widget.expiresAt.difference(DateTime.now()).inSeconds;
    if (_remainingSeconds < 0) _remainingSeconds = 0;

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

  Future<void> _handleVerifyOtp() async {
    if (!mounted) return;

    if (_otpCode.length != 6) {
      _showError('Please enter a valid 6-digit OTP');
      return;
    }

    if (!mounted) return;
    setState(() => _isLoading = true);

    final authProvider = context.read<AuthProvider>();
    final sessionId = _newSessionId ?? widget.sessionId;

    final verifyResponse = await authProvider.verifyOtp(
      mobile: widget.phoneNumber,
      otp: _otpCode,
      sessionId: sessionId,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (verifyResponse == null) {
      // Error occurred - show error from provider
      if (mounted && authProvider.errorMessage != null) {
        _showError(authProvider.errorMessage!);
      }
      return;
    }

    if (verifyResponse.isLogin) {
      // User logged in successfully - navigate to home
      if (mounted) {
        context.goNamed('home');
      }
    } else if (verifyResponse.needsRegistration) {
      // OTP verified but needs to complete registration
      if (mounted) {
        context.goNamed(
          'registration-form',
          extra: {
            'phone': widget.phoneNumber,
            'message': verifyResponse.message,
          },
        );
      }
    } else {
      // Unexpected response
      if (mounted) {
        _showError('Unexpected response from server');
      }
    }
  }

  Future<void> _handleResendOtp() async {
    if (!_canResend) return;

    if (!mounted) return;
    setState(() => _isLoading = true);

    final authProvider = context.read<AuthProvider>();

    // Use appropriate endpoint based on flow type
    final sendOtpResponse = widget.isRegistration
        ? null // For registration, we need email and firstName - should not allow resend without that data
        : await authProvider.sendOtp(widget.phoneNumber);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (sendOtpResponse != null) {
      // Update session ID and restart timer
      if (!mounted) return;
      setState(() {
        _newSessionId = sendOtpResponse.sessionId;
        _canResend = false;
      });
      _startTimer();

      if (mounted) {
        _showSuccess('OTP sent successfully');
      }
    } else if (mounted && authProvider.errorMessage != null) {
      _showError(authProvider.errorMessage!);
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

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),

              // Title
              Text(
                'Verify OTP',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              // Phone number display
              Text(
                'Enter the 6-digit code sent to',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.phoneNumber,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primaryColor,
                ),
              ),

              const SizedBox(height: 40),

              // OTP Input
              PinCodeTextField(
                appContext: context,
                length: 6,
                keyboardType: TextInputType.number,
                animationType: AnimationType.fade,
                pinTheme: PinTheme(
                  shape: PinCodeFieldShape.box,
                  borderRadius: BorderRadius.circular(12),
                  fieldHeight: 56,
                  fieldWidth: 48,
                  activeFillColor: Colors.white,
                  inactiveFillColor: Colors.white,
                  selectedFillColor: Colors.white,
                  activeColor: AppTheme.primaryColor,
                  inactiveColor: Colors.grey[300]!,
                  selectedColor: AppTheme.primaryColor,
                ),
                animationDuration: const Duration(milliseconds: 200),
                backgroundColor: Colors.transparent,
                enableActiveFill: true,
                onCompleted: (code) {
                  if (mounted) {
                    setState(() => _otpCode = code);
                    _handleVerifyOtp();
                  }
                },
                onChanged: (value) {
                  if (mounted) {
                    setState(() => _otpCode = value);
                  }
                },
                enabled: !_isLoading,
                beforeTextPaste: (text) {
                  return true; // Allow paste
                },
              ),

              const SizedBox(height: 24),

              // Timer and resend
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!_canResend) ...[
                    Icon(Icons.timer_outlined, size: 20, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    Text(
                      'Resend code in $_timerText',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                  ] else ...[
                    TextButton(
                      onPressed: _isLoading ? null : _handleResendOtp,
                      child: const Text(
                        'Resend OTP',
                        style: TextStyle(
                          color: AppTheme.primaryColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 24),

              // Verify button
              ElevatedButton(
                onPressed: _isLoading ? null : _handleVerifyOtp,
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
                        'Verify OTP',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),

              const Spacer(),

              // Help text
              Text(
                'Didn\'t receive the code? Check your SMS or try resending',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
