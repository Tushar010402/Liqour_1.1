import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../routes/app_routes.dart';
import '../controllers/auth_provider.dart';

class OTPScreen extends StatefulWidget {
  final String phoneNumber;

  const OTPScreen({super.key, required this.phoneNumber});

  @override
  State<OTPScreen> createState() => _OTPScreenState();
}

class _OTPScreenState extends State<OTPScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _otpController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  Timer? _resendTimer;
  int _resendCountdown = 30;
  bool _canResend = false;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _startResendTimer();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
    ));

    _animationController.forward();
  }

  void _startResendTimer() {
    _canResend = false;
    _resendCountdown = 30;

    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_resendCountdown > 0) {
          _resendCountdown--;
        } else {
          _canResend = true;
          timer.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _resendTimer?.cancel();
    _otpController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGray,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: _buildContent(),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 40),

          // Header
          _buildHeader(),

          const SizedBox(height: 60),

          // OTP Input Form
          _buildOTPForm(),

          const SizedBox(height: 40),

          // Resend Option
          _buildResendOption(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        // Icon
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [AppColors.primaryShadow],
          ),
          child: const Icon(
            Icons.sms_outlined,
            size: 40,
            color: AppColors.white,
          ),
        ),

        const SizedBox(height: 24),

        // Title
        Text(
          AppStrings.verifyOTP,
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.primaryBlack,
              ),
        ),

        const SizedBox(height: 12),

        // Subtitle
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.mediumGray,
                ),
            children: [
              const TextSpan(text: AppStrings.enterOTP),
              const TextSpan(text: '\nsent to '),
              TextSpan(
                text: widget.phoneNumber,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryRed,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOTPForm() {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        return Card(
          elevation: 8,
          shadowColor: AppColors.primaryRed.withValues(alpha: 0.1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // OTP Input Field
                _buildSimpleOTPField(),

                const SizedBox(height: 32),

                // Verify Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: authProvider.isLoading ? null : _handleVerifyOTP,
                    child: authProvider.isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppColors.white,
                              ),
                            ),
                          )
                        : const Text(AppStrings.verifyOTP),
                  ),
                ),

                // Error Message
                if (authProvider.hasError) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.errorLight,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.error),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: AppColors.error,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            authProvider.errorMessage!,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppColors.error,
                                    ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSimpleOTPField() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextFormField(
        controller: _otpController,
        focusNode: _focusNode,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.visiblePassword, // Prevent Hindi number conversion
        autocorrect: false,
        enableSuggestions: false,
        enableInteractiveSelection: true,
        autofillHints: const <String>[],
        textCapitalization: TextCapitalization.none,
        maxLength: 6,
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.primaryBlack,
              letterSpacing: 8,
            ),
        decoration: InputDecoration(
          labelText: 'Enter OTP',
          hintText: '123456',
          hintStyle: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: AppColors.mediumGray.withValues(alpha: 0.5),
                letterSpacing: 8,
              ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.borderGray),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primaryRed, width: 2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.borderGray),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 20),
          counterText: '',
        ),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
        ],
        onChanged: _handleSimpleOTPChange,
        validator: (value) {
          if (value == null || value.length != 6) {
            return 'Please enter a valid 6-digit OTP';
          }
          return null;
        },
      ),
    );
  }

  Widget _buildResendOption() {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "Didn't receive OTP? ",
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.mediumGray,
                  ),
            ),
            TextButton(
              onPressed: _canResend && !authProvider.isLoading
                  ? _handleResendOTP
                  : null,
              child: Text(
                _canResend
                    ? AppStrings.resendOTP
                    : 'Resend in ${_resendCountdown}s',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color:
                      _canResend ? AppColors.primaryRed : AppColors.mediumGray,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _handleSimpleOTPChange(String value) {
    // Auto-verify when 6 digits are entered
    if (value.length == 6) {
      _focusNode.unfocus();
      _handleVerifyOTP();
    }
  }

  bool _isOTPComplete() {
    return _otpController.text.length == 6;
  }

  String _getOTP() {
    return _otpController.text;
  }

  void _handleVerifyOTP() async {
    if (!_isOTPComplete()) {
      _showSnackBar(AppStrings.invalidOTP);
      return;
    }

    final otp = _getOTP();
    final authProvider = context.read<AuthProvider>();

    final success = await authProvider.verifyOTP(widget.phoneNumber, otp);

    if (success && mounted) {
      context.go(AppRoutes.dashboard);
    }
  }

  void _handleResendOTP() async {
    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.sendOTP(widget.phoneNumber);

    if (success) {
      _startResendTimer();
      _clearOTPFields();
      _showSnackBar(AppStrings.otpSent);
    }
  }

  void _clearOTPFields() {
    _otpController.clear();
    _focusNode.requestFocus();
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.primaryRed,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
