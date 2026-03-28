import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/responsive_utils.dart';
import '../../../core/utils/haptic_feedback.dart';
import '../../../core/widgets/responsive_container.dart';
import '../providers/auth_provider.dart';

/// Pre-Registration Screen - Collect email and full name for new user registration
/// When registrationToken is provided (from OTP verification), skips OTP and goes straight to registration form
class PreRegistrationScreen extends StatefulWidget {
  final String phoneNumber;
  final String? registrationToken;

  const PreRegistrationScreen({
    super.key,
    required this.phoneNumber,
    this.registrationToken,
  });

  @override
  State<PreRegistrationScreen> createState() => _PreRegistrationScreenState();
}

class _PreRegistrationScreenState extends State<PreRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _fullNameController = TextEditingController();
  bool _isLoading = false;
  bool _isValidatingEmail = false;
  bool? _isEmailAvailable;
  String? _emailError;

  @override
  void initState() {
    super.initState();
    // Only validate email availability if user is NOT coming from OTP flow
    // (the validate endpoint requires auth token which we don't have yet)
    if (widget.registrationToken == null) {
      _emailController.addListener(_validateEmailDebounced);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _fullNameController.dispose();
    super.dispose();
  }

  // Debounce timer for email validation
  int _emailDebounceTimer = 0;

  /// Validate email with debouncing
  void _validateEmailDebounced() {
    // Clear previous timer
    _emailDebounceTimer++;
    final currentTimer = _emailDebounceTimer;

    print('⏱️ [PreRegistration] Email changed - debounce timer: $currentTimer');

    // Wait 800ms before validating
    Future.delayed(const Duration(milliseconds: 800), () {
      if (currentTimer == _emailDebounceTimer && mounted) {
        print('✅ [PreRegistration] Debounce complete - validating email');
        _validateEmailAvailability();
      } else {
        print('⏭️ [PreRegistration] Debounce cancelled - timer mismatch');
      }
    });
  }

  /// Check if email is available using the backend API
  Future<void> _validateEmailAvailability() async {
    final email = _emailController.text.trim();

    print('📧 [PreRegistration] Validating email availability: "$email"');

    // Basic email validation first
    if (email.isEmpty) {
      print('⚠️ [PreRegistration] Email is empty - skipping validation');
      setState(() {
        _isEmailAvailable = null;
        _emailError = null;
        _isValidatingEmail = false;
      });
      return;
    }

    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(email)) {
      print('⚠️ [PreRegistration] Email format invalid');
      setState(() {
        _isEmailAvailable = false;
        _emailError = 'Please enter a valid email address';
        _isValidatingEmail = false;
      });
      return;
    }

    setState(() {
      _isValidatingEmail = true;
      _emailError = null;
    });

    print('🔄 [PreRegistration] Calling API to validate email...');

    try {
      final authProvider = context.read<AuthProvider>();
      final isAvailable = await authProvider.validateEmail(email);

      print('📥 [PreRegistration] Validation complete - available: $isAvailable');

      if (mounted) {
        setState(() {
          _isEmailAvailable = isAvailable;
          _emailError = isAvailable ? null : 'This email is already registered';
          _isValidatingEmail = false;
        });
      }
    } catch (e) {
      print('❌ [PreRegistration] Error during email validation: $e');
      if (mounted) {
        setState(() {
          _isEmailAvailable = null;
          _emailError = 'Unable to verify email availability';
          _isValidatingEmail = false;
        });
      }
    }
  }

  Future<void> _handleContinue() async {
    if (!_formKey.currentState!.validate()) return;

    // Skip email availability check when coming from OTP flow (no auth token)
    if (widget.registrationToken == null) {
      // Check if email validation is still in progress
      if (_isValidatingEmail) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please wait while we verify your email...'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Check if email is available
      if (_isEmailAvailable != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_emailError ?? 'This email is not available'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    if (!mounted) return;
    setState(() => _isLoading = true);

    // If we already have a registrationToken (from OTP verification),
    // skip OTP and go straight to registration form
    if (widget.registrationToken != null) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      context.pushNamed(
        'registration-form',
        extra: {
          'phone': widget.phoneNumber,
          'email': _emailController.text.trim(),
          'fullName': _fullNameController.text.trim(),
          'registrationToken': widget.registrationToken,
        },
      );
      return;
    }

    // Legacy flow: send OTP for registration (if check-user didn't already do it)
    final authProvider = context.read<AuthProvider>();

    final sendOtpResponse = await authProvider.sendOtpForRegistration(
      phone: widget.phoneNumber,
      email: _emailController.text.trim(),
      firstName: _fullNameController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (sendOtpResponse != null && mounted) {
      context.pushNamed(
        'otp-verification',
        extra: {
          'phone': widget.phoneNumber,
          'sessionId': sendOtpResponse.sessionId,
          'expiresAt': sendOtpResponse.expiresAt,
          'isRegistration': true,
          'email': _emailController.text.trim(),
          'fullName': _fullNameController.text.trim(),
        },
      );
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

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your email';
    }
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value)) {
      return 'Please enter a valid email';
    }
    // Show validation error if email is not available (only when not from OTP flow)
    if (widget.registrationToken == null && _emailError != null) {
      return _emailError;
    }
    return null;
  }

  String? _validateFullName(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your full name';
    }
    if (value.length < 2) {
      return 'Name must be at least 2 characters';
    }
    return null;
  }

  /// Build validation icon for email field
  Widget? _buildEmailValidationIcon() {
    // No validation icon when coming from OTP flow (no auth token for API)
    if (widget.registrationToken != null) return null;
    if (_emailController.text.isEmpty) {
      return null;
    }

    if (_isValidatingEmail) {
      return const Padding(
        padding: EdgeInsets.all(12.0),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
          ),
        ),
      );
    }

    if (_isEmailAvailable == true) {
      return const Icon(
        Icons.check_circle,
        color: Colors.green,
        size: 24,
      );
    }

    if (_emailError != null) {
      return const Icon(
        Icons.error,
        color: Colors.red,
        size: 24,
      );
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isTablet = context.isTablet;
    final isLargeScreen = context.isLargeScreen;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back,
            color: cs.onSurface,
            size: context.iconSize,
          ),
          onPressed: () {
            HapticFeedbackUtil.buttonPress();
            Navigator.pop(context);
          },
        ),
      ),
      body: SafeArea(
        child: ResponsiveScrollContainer(
          maxWidth: 600,
          padding: context.responsivePadding,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: isLargeScreen ? CrossAxisAlignment.center : CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),

                // Title
                Text(
                  'Create Account',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: isTablet ? 36 : null,
                  ),
                  textAlign: isLargeScreen ? TextAlign.center : TextAlign.left,
                ),

                const SizedBox(height: 8),

                Text(
                  'We need a few details to get started',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontSize: isTablet ? 18 : 16,
                  ),
                  textAlign: isLargeScreen ? TextAlign.center : TextAlign.left,
                ),

                SizedBox(height: context.responsiveSpacing * 2),

                // Full Name - Wrapped in ConstrainedBox for tablets
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isLargeScreen ? 400 : double.infinity,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Full Name',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: isTablet ? 16 : 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _fullNameController,
                        keyboardType: TextInputType.name,
                        textCapitalization: TextCapitalization.words,
                        style: TextStyle(
                          fontSize: isTablet ? 18 : 16,
                        ),
                        decoration: InputDecoration(
                          hintText: 'John Doe',
                          prefixIcon: Icon(Icons.person_outline,
                            size: context.iconSize,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(context.borderRadius),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(context.borderRadius),
                            borderSide: BorderSide(color: cs.outlineVariant),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(context.borderRadius),
                            borderSide: BorderSide(
                              color: cs.primary,
                              width: 2,
                            ),
                          ),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: isTablet ? 20 : 16,
                            vertical: isTablet ? 20 : 16,
                          ),
                        ),
                        validator: _validateFullName,
                        enabled: !_isLoading,
                        onTap: () => HapticFeedbackUtil.selection(),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: context.responsiveSpacing),

                // Email - Wrapped in ConstrainedBox for tablets
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isLargeScreen ? 400 : double.infinity,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Email',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: isTablet ? 16 : 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        style: TextStyle(
                          fontSize: isTablet ? 18 : 16,
                        ),
                        decoration: InputDecoration(
                          hintText: 'john@example.com',
                          prefixIcon: Icon(Icons.email_outlined,
                            size: context.iconSize,
                          ),
                          // Suffix icon to show validation status
                          suffixIcon: _buildEmailValidationIcon(),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(context.borderRadius),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(context.borderRadius),
                            borderSide: BorderSide(
                              color: _isEmailAvailable == true
                                  ? Colors.green
                                  : (_emailError != null
                                      ? Colors.red
                                      : cs.outlineVariant),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(context.borderRadius),
                            borderSide: BorderSide(
                              color: _isEmailAvailable == true
                                  ? Colors.green
                                  : (_emailError != null
                                      ? Colors.red
                                      : cs.primary),
                              width: 2,
                            ),
                          ),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: isTablet ? 20 : 16,
                            vertical: isTablet ? 20 : 16,
                          ),
                        ),
                        validator: _validateEmail,
                        enabled: !_isLoading,
                        onTap: () => HapticFeedbackUtil.selection(),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: context.responsiveSpacing),

                // Info box - Constrained for tablets
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isLargeScreen ? 400 : double.infinity,
                  ),
                  child: Container(
                    padding: EdgeInsets.all(isTablet ? 20 : 16),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha:0.1),
                      borderRadius: BorderRadius.circular(context.borderRadius),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: AppTheme.primaryColor,
                          size: isTablet ? 24 : 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            widget.registrationToken != null
                                ? 'Phone verified. Please complete your details to continue.'
                                : 'We\'ll send a verification code to your phone number',
                            style: TextStyle(
                              fontSize: isTablet ? 15 : 13,
                              color: AppTheme.primaryColor.withValues(alpha:0.8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: context.responsiveSpacing * 2),

                // Continue button - Constrained for tablets
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isLargeScreen ? 400 : double.infinity,
                  ),
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : () async {
                      await HapticFeedbackUtil.buttonPress();
                      _handleContinue();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                        vertical: isTablet ? 20 : 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(context.borderRadius),
                      ),
                      elevation: 0,
                      minimumSize: Size(double.infinity, context.buttonHeight),
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
                        : Text(
                            widget.registrationToken != null ? 'Continue' : 'Send OTP',
                            style: TextStyle(
                              fontSize: isTablet ? 18 : 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),

                const Spacer(),

                // Phone number display - Responsive
                Container(
                  padding: EdgeInsets.all(isTablet ? 16 : 12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(context.borderRadius * 0.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.phone,
                        size: isTablet ? 20 : 16,
                        color: cs.onSurfaceVariant
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.phoneNumber,
                        style: TextStyle(
                          fontSize: isTablet ? 16 : 14,
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
      ),
    );
  }
}
