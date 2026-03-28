import 'dart:async';
import 'dart:io';
import 'dart:math' show sin, pi;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
// Pinput removed — using native TextField for reliable keyboard handling
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as riverpod;
import '../../../core/theme/app_theme.dart';
import '../../../core/services/fcm_service.dart';
import '../providers/auth_provider.dart';
import '../models/device_session_models.dart';
import '../widgets/device_limit_modal.dart';
import '../services/otp_autofill_service.dart';
import '../services/otp_timer_service.dart';
import '../widgets/modern_otp_status.dart';
import '../widgets/modern_otp_timer.dart';

/// Modern OTP Verification Screen
///
/// Features:
/// - Cross-platform OTP auto-fill (iOS keyboard suggestion + Android SMS reading)
/// - Minimal, professional UI design
/// - Smooth animations using flutter_animate
/// - Industrial-grade polish
class OtpVerificationScreen extends StatefulWidget {
  final String phoneNumber;
  final String sessionId;
  final DateTime expiresAt;
  final bool isRegistration;
  final String? email;
  final String? fullName;

  const OtpVerificationScreen({
    super.key,
    required this.phoneNumber,
    required this.sessionId,
    required this.expiresAt,
    required this.isRegistration,
    this.email,
    this.fullName,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen>
    with SingleTickerProviderStateMixin {
  // Controllers
  final TextEditingController _pinController = TextEditingController();
  final FocusNode _pinFocusNode = FocusNode();

  // Services
  final _otpAutoFillService = OTPAutoFillService();
  final _otpTimerService = OTPTimerService();

  // Shake animation controller — keeps Pinput widget tree stable
  late final AnimationController _shakeController;

  // Auto-verify timer — gives user a moment to correct before verifying
  Timer? _autoVerifyTimer;

  // State
  String _otpCode = '';
  bool _isLoading = false;
  String? _newSessionId;
  OTPState _otpState = OTPState.idle;
  String? _errorMessage;
  bool _showSmsDetectedToast = false;
  int _attemptCount = 0; // Track wrong attempts
  static const int _maxAttempts = 5; // Max attempts before lockout

  // Subscriptions
  StreamSubscription? _otpSubscription;

  @override
  void initState() {
    super.initState();

    // Shake animation: 350ms, manually triggered on error
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    // Initialize OTP auto-fill service
    _otpAutoFillService.initialize();

    // Start OTP timer
    _otpTimerService.startTimer(expiresAt: widget.expiresAt);

    // Listen for timer expiry
    _otpTimerService.stateStream.listen((state) {
      if (state == OTPTimerState.expired && mounted) {
        setState(() => _otpState = OTPState.expired);
      }
    });

    // Rebuild digit boxes when focus changes (cursor visibility)
    _pinFocusNode.addListener(() {
      if (mounted) setState(() {});
    });

    // Start listening for SMS (Android only)
    _startSmsListener();

    // Auto-focus PIN input
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _pinFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _autoVerifyTimer?.cancel();
    _otpSubscription?.cancel();
    _otpAutoFillService.stopListening();
    _otpTimerService.stopTimer();
    _shakeController.dispose();
    _pinController.dispose();
    _pinFocusNode.dispose();
    super.dispose();
  }

  /// Start listening for OTP from SMS (Android only)
  void _startSmsListener() {
    if (!Platform.isAndroid) return;

    debugPrint('[OTP] Starting SMS listener...');

    _otpSubscription = _otpAutoFillService.listenForOTP().listen(
      (code) {
        debugPrint('[OTP] SMS code received: $code');

        if (!mounted) return;

        // Show toast
        setState(() {
          _showSmsDetectedToast = true;
          _otpState = OTPState.smsDetected;
        });

        // Auto-fill after brief delay
        Future.delayed(const Duration(milliseconds: 300), () {
          if (!mounted) return;

          _pinController.text = code;
          setState(() => _otpCode = code);

          // Hide toast after delay
          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted) {
              setState(() => _showSmsDetectedToast = false);
            }
          });

          // Auto-verify
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              _handleVerifyOtp();
            }
          });
        });
      },
      onError: (error) {
        debugPrint('[OTP] SMS listener error: $error');
      },
    );
  }

  /// Verify OTP with backend
  Future<void> _handleVerifyOtp() async {
    if (!mounted) return;

    // Cancel any pending auto-verify
    _autoVerifyTimer?.cancel();

    if (_otpCode.length != 6) {
      _showOtpError('Please enter a valid 6-digit code');
      return;
    }

    HapticFeedback.mediumImpact();

    setState(() {
      _isLoading = true;
      _otpState = OTPState.verifying;
      _errorMessage = null;
    });

    final authProvider = context.read<AuthProvider>();
    final sessionId = _newSessionId ?? widget.sessionId;

    try {
      final verifyResponse = await authProvider.verifyOtp(
        mobile: widget.phoneNumber,
        otp: _otpCode,
        sessionId: sessionId,
      );

      if (!mounted) return;

      if (verifyResponse == null) {
        // Parse and show user-friendly error
        _showOtpError(_parseErrorMessage(authProvider.errorMessage));
        return;
      }

      // Success!
      HapticFeedback.heavyImpact();
      setState(() {
        _isLoading = false;
        _otpState = OTPState.success;
        _attemptCount = 0; // Reset attempts on success
      });

      // Wait for success animation
      await Future.delayed(const Duration(milliseconds: 1000));

      if (!mounted) return;

      // Security: use verify-otp response to determine login vs registration
      // Do NOT rely on check-user's exists field — it always returns false now
      if (verifyResponse.isLogin) {
        // Login successful
        if (kDebugMode) {
          debugPrint('[OTP] Login successful - initializing FCM and navigating to home');
        }

        // ====== FCM INITIALIZATION (Best Practice) ======
        // Initialize FCM, force refresh token, and register device after successful login
        try {
          final container = riverpod.ProviderScope.containerOf(context);
          final fcmService = container.read(fcmServiceProvider);
          await fcmService.initialize();
          // IMPORTANT: Force refresh FCM token on login to avoid stale cached tokens
          await fcmService.forceRefreshToken();
          await fcmService.registerDevice();
          if (kDebugMode) {
            debugPrint('✅ [OTP] FCM initialized, token refreshed, and device registered');
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('⚠️ [OTP] FCM initialization error (non-critical): $e');
          }
          // Continue even if FCM fails - app should still work without notifications
        }

        await authProvider.connectRealTimeUpdates();
        if (mounted) {
          context.goNamed('home');
        }
      } else if (verifyResponse.needsRegistration) {
        // Registration flow - OTP verified, now collect user details
        debugPrint('[OTP] Registration verified - navigating to collect user details');
        debugPrint('[OTP] Registration token: ${verifyResponse.registrationToken != null ? "present" : "MISSING"}');
        context.goNamed(
          'pre-registration',
          extra: {
            'phone': widget.phoneNumber,
            'registrationToken': verifyResponse.registrationToken,
          },
        );
      } else {
        _showOtpError('Unexpected response. Please try again.');
      }
    } on DeviceLimitException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _otpState = OTPState.idle;
      });
      _showDeviceLimitModal(e.error);
    } catch (e) {
      if (!mounted) return;
      _showOtpError(_parseErrorMessage(e.toString()));
    }
  }

  /// Show OTP error with shake animation and auto-clear
  void _showOtpError(String message) {
    if (!mounted) return;

    // Double haptic for emphasis
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 100), () {
      HapticFeedback.mediumImpact();
    });

    // Capture current code to detect if user starts retyping
    final codeAtError = _pinController.text;

    setState(() {
      _isLoading = false;
      _otpState = OTPState.error;
      _errorMessage = message;
      _attemptCount++;
    });

    // Trigger shake animation (does NOT recreate Pinput widget tree)
    _shakeController.forward(from: 0);

    // Auto-clear OTP input after shake completes and re-enable input
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && _pinController.text == codeAtError) {
        _pinController.clear();
        setState(() {
          _otpCode = '';
          // Reset error state so input is re-enabled for retry
          _otpState = OTPState.idle;
          if (_attemptCount >= _maxAttempts) {
            _errorMessage = 'Too many attempts. Please request a new code.';
          } else {
            _errorMessage = null;
          }
        });
        _pinFocusNode.requestFocus();
      }
    });
  }

  /// Parse error messages to be user-friendly
  String _parseErrorMessage(String? error) {
    if (error == null) return 'Verification failed. Please try again.';

    final errorStr = error.toLowerCase();

    if (errorStr.contains('invalid otp') || errorStr.contains('wrong code') || errorStr.contains('incorrect')) {
      return 'Incorrect code. Please try again.';
    }
    if (errorStr.contains('expired')) {
      return 'Code expired. Please request a new one.';
    }
    if (errorStr.contains('too many attempts') || errorStr.contains('rate limit')) {
      return 'Too many attempts. Please wait and try again.';
    }
    if (errorStr.contains('network') || errorStr.contains('connection')) {
      return 'Network error. Please check your connection.';
    }

    return 'Verification failed. Please try again.';
  }

  /// Resend OTP
  Future<void> _handleResendOtp() async {
    if (_otpTimerService.isInCooldown) {
      return;
    }

    setState(() => _isLoading = true);

    final authProvider = context.read<AuthProvider>();

    // Resend OTP - works for both login and registration flows
    final sendOtpResponse = await authProvider.sendOtp(widget.phoneNumber);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (sendOtpResponse != null) {
      setState(() {
        _newSessionId = sendOtpResponse.sessionId;
        _otpState = OTPState.idle;
        _errorMessage = null;
        _otpCode = '';
        _attemptCount = 0; // Reset attempts on new OTP
      });

      _pinController.clear();
      _otpTimerService.startTimer(expiresAt: sendOtpResponse.expiresAt);

      // Restart SMS listener
      _otpSubscription?.cancel();
      _startSmsListener();

      _showSuccessSnackbar('New code sent');
    } else if (authProvider.errorMessage != null) {
      final errorMessage = authProvider.errorMessage!;
      final cooldownMatch =
          RegExp(r'wait (\d+) second').firstMatch(errorMessage);

      if (cooldownMatch != null) {
        final waitSeconds = int.parse(cooldownMatch.group(1)!);
        _otpTimerService.handleCooldownError(waitSeconds);
      }

      _showErrorSnackbar(errorMessage);
    }
  }

  /// Show device limit modal
  void _showDeviceLimitModal(DeviceLimitError error) {
    DeviceLimitModal.show(
      context: context,
      error: error,
      onLogoutDevice: (sessionIdToRemove) async {
        Navigator.pop(context);
        await _handleForceLogin(sessionIdToRemove);
      },
      onForceLogin: () async {
        Navigator.pop(context);
        if (error.activeDevices.isNotEmpty) {
          await _handleForceLogin(error.activeDevices.first.id);
        }
      },
      onCancel: () => Navigator.pop(context),
    );
  }

  /// Force login by removing another device
  Future<void> _handleForceLogin(String sessionIdToRemove) async {
    if (!mounted) return;

    // Check if OTP is entered
    if (_otpCode.isEmpty || _otpCode.length != 6) {
      _showErrorSnackbar('Please enter the 6-digit code first');
      return;
    }

    setState(() {
      _isLoading = true;
      _otpState = OTPState.verifying;
    });

    final authProvider = context.read<AuthProvider>();
    final sessionId = _newSessionId ?? widget.sessionId;

    try {
      final verifyResponse = await authProvider.forceLoginOtp(
        mobile: widget.phoneNumber,
        otp: _otpCode,
        sessionIdToRemove: sessionIdToRemove,
        sessionId: sessionId,
      );

      if (!mounted) return;

      if (verifyResponse == null) {
        // Parse the error message for better UX
        final errorMsg = authProvider.errorMessage ?? 'Login failed';
        final isExpired = errorMsg.toLowerCase().contains('expired') ||
            errorMsg.toLowerCase().contains('401') ||
            errorMsg.toLowerCase().contains('invalid');

        setState(() {
          _isLoading = false;
          _otpState = OTPState.error;
          _errorMessage = isExpired
              ? 'Code expired or invalid. Please request a new code.'
              : errorMsg;
        });

        // If OTP is expired, offer to resend
        if (isExpired) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              _pinController.clear();
              setState(() => _otpCode = '');
            }
          });
        }
        return;
      }

      HapticFeedback.heavyImpact();
      setState(() {
        _isLoading = false;
        _otpState = OTPState.success;
      });

      await Future.delayed(const Duration(milliseconds: 1000));

      if (!mounted) return;

      if (verifyResponse.isLogin) {
        // ====== FCM INITIALIZATION (Best Practice) ======
        try {
          final container = riverpod.ProviderScope.containerOf(context);
          final fcmService = container.read(fcmServiceProvider);
          await fcmService.initialize();
          await fcmService.forceRefreshToken();
          await fcmService.registerDevice();
        } catch (e) {
          if (kDebugMode) {
            debugPrint('⚠️ [OTP] FCM initialization error (non-critical): $e');
          }
        }

        await authProvider.connectRealTimeUpdates();
        if (mounted) {
          context.goNamed('home');
        }
      }
    } catch (e) {
      if (!mounted) return;

      // Better error parsing
      final errorStr = e.toString().toLowerCase();
      final isExpired = errorStr.contains('expired') ||
          errorStr.contains('401') ||
          errorStr.contains('invalid');

      setState(() {
        _isLoading = false;
        _otpState = OTPState.error;
        _errorMessage = isExpired
            ? 'Code expired. Please request a new code and try again.'
            : 'Failed to login. Please try again.';
      });

      // Clear OTP if expired
      if (isExpired) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _pinController.clear();
            setState(() => _otpCode = '');
          }
        });
      }
    }
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.errorColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.successColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          color: cs.onSurface,
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.pop(context);
          },
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            // Main content
            SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 16),

                  // Header
                  _buildHeader(),

                  const SizedBox(height: 40),

                  // OTP Input
                  _buildOtpInput(),

                  const SizedBox(height: 16),

                  // Status indicator (only when not idle)
                  if (_otpState != OTPState.idle)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: ModernOtpStatus(
                        state: _otpState,
                        customMessage: _errorMessage,
                      ).animate().fadeIn(duration: 200.ms),
                    ),

                  // Attempt counter (show after first wrong attempt)
                  if (_attemptCount > 0 && _attemptCount < _maxAttempts)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: _attemptCount >= 3
                              ? AppTheme.errorColor.withOpacity(0.1)
                              : Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_maxAttempts - _attemptCount} ${_maxAttempts - _attemptCount == 1 ? 'attempt' : 'attempts'} remaining',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _attemptCount >= 3
                                ? AppTheme.errorColor
                                : Colors.orange[700],
                          ),
                        ),
                      ),
                    ).animate().fadeIn(duration: 200.ms).scale(begin: const Offset(0.9, 0.9)),

                  const SizedBox(height: 28),

                  // Timer and resend
                  ModernOtpTimer(
                    timerService: _otpTimerService,
                    onResend: _handleResendOtp,
                    isLoading: _isLoading,
                  ),

                  const SizedBox(height: 28),

                  // Verify button
                  _buildVerifyButton(),

                  const SizedBox(height: 24),

                  // Help text
                  _buildHelpText(),

                  const SizedBox(height: 32),
                ],
              ),
            ),

            // SMS detected toast (Android)
            if (_showSmsDetectedToast)
              Positioned(
                bottom: 100,
                left: 0,
                right: 0,
                child: Center(child: OtpDetectedToast()),
              ),
          ],
        ),
      ),
    );
  }

  /// Header with icon, title and phone number - Premium iOS style
  Widget _buildHeader() {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        // OTP Icon with gradient background
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.primaryColor.withOpacity(0.15),
                AppTheme.primaryColor.withOpacity(0.05),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Icon(
            Icons.lock_outline_rounded,
            size: 36,
            color: AppTheme.primaryColor,
          ),
        )
            .animate()
            .fadeIn(delay: 50.ms, duration: 400.ms)
            .scale(begin: const Offset(0.8, 0.8), end: const Offset(1, 1)),

        const SizedBox(height: 24),

        // Title
        Text(
          'Enter Verification Code',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
            letterSpacing: -0.5,
          ),
        )
            .animate()
            .fadeIn(delay: 100.ms, duration: 400.ms)
            .slideY(begin: 0.15, end: 0),

        const SizedBox(height: 12),

        // Subtitle with phone number
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: TextStyle(
              fontSize: 15,
              color: cs.onSurfaceVariant,
              height: 1.5,
            ),
            children: [
              const TextSpan(text: 'We sent a 6-digit code to\n'),
              TextSpan(
                text: widget.phoneNumber,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primaryColor,
                  fontSize: 17,
                ),
              ),
            ],
          ),
        )
            .animate()
            .fadeIn(delay: 200.ms, duration: 400.ms)
            .slideY(begin: 0.15, end: 0),
      ],
    );
  }

  /// OTP Input — clean native implementation
  ///
  /// Uses a single hidden TextField for all keyboard handling (backspace,
  /// delete, paste, autofill all work perfectly). Renders 6 styled digit
  /// boxes on top that read from the controller. No third-party widget
  /// tree instability.
  Widget _buildOtpInput() {
    final cs = Theme.of(context).colorScheme;
    final hasError = _otpState == OTPState.error;
    final isSuccess = _otpState == OTPState.success;
    final isDisabled = _isLoading || isSuccess;
    final text = _pinController.text;
    final hasFocus = _pinFocusNode.hasFocus;

    // Build the 6 digit boxes
    final digitBoxes = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (i) {
        final hasDigit = i < text.length;
        final digit = hasDigit ? text[i] : '';
        final isCurrentIndex = i == text.length && hasFocus && !isDisabled;

        // Determine box state for styling
        Color borderColor;
        double borderWidth;
        Color bgColor;
        Color textColor;

        if (hasError) {
          borderColor = AppTheme.errorColor;
          borderWidth = 2;
          bgColor = AppTheme.errorColor.withValues(alpha: 0.06);
          textColor = AppTheme.errorColor;
        } else if (isSuccess) {
          borderColor = Colors.green;
          borderWidth = 2;
          bgColor = Colors.green.withValues(alpha: 0.06);
          textColor = Colors.green.shade700;
        } else if (isCurrentIndex) {
          borderColor = AppTheme.primaryColor;
          borderWidth = 2.5;
          bgColor = cs.surface;
          textColor = AppTheme.primaryColor;
        } else if (hasDigit) {
          borderColor = AppTheme.primaryColor.withValues(alpha: 0.4);
          borderWidth = 1.5;
          bgColor = AppTheme.primaryColor.withValues(alpha: 0.05);
          textColor = AppTheme.primaryColor;
        } else {
          borderColor = cs.outlineVariant;
          borderWidth = 1.5;
          bgColor = cs.surfaceContainerHighest;
          textColor = cs.onSurface;
        }

        return Container(
          width: 48,
          height: 56,
          margin: EdgeInsets.only(left: i > 0 ? 8 : 0),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: borderWidth),
            boxShadow: isCurrentIndex
                ? [
                    BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: hasDigit
              ? Text(
                  digit,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                    letterSpacing: 0,
                  ),
                )
              : isCurrentIndex
                  ? _buildCursor()
                  : null,
        );
      }),
    );

    // Stack: hidden TextField underneath, digit boxes on top
    final inputWidget = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: GestureDetector(
        onTap: () {
          if (!isDisabled) {
            _pinFocusNode.requestFocus();
          }
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Hidden TextField — handles all keyboard input natively
            Opacity(
              opacity: 0,
              child: SizedBox(
                height: 56,
                child: AutofillGroup(
                  child: TextField(
                    controller: _pinController,
                    focusNode: _pinFocusNode,
                    autofocus: true,
                    enabled: !isDisabled,
                    maxLength: 6,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    showCursor: false,
                    decoration: const InputDecoration(
                      counterText: '',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (value) {
                      // Cancel pending auto-verify
                      _autoVerifyTimer?.cancel();

                      if (value.length > _otpCode.length) {
                        HapticFeedback.selectionClick();
                      }

                      setState(() {
                        _otpCode = value;
                        // Clear error when user starts retyping
                        if (_otpState == OTPState.error) {
                          _otpState = OTPState.idle;
                          _errorMessage = null;
                        }
                      });

                      // Auto-verify when 6 digits entered
                      if (value.length == 6) {
                        HapticFeedback.heavyImpact();
                        _autoVerifyTimer?.cancel();
                        _autoVerifyTimer = Timer(
                          const Duration(milliseconds: 800),
                          () {
                            if (mounted && _otpCode.length == 6 && !_isLoading) {
                              _handleVerifyOtp();
                            }
                          },
                        );
                      }
                    },
                  ),
                ),
              ),
            ),

            // Visible digit boxes
            digitBoxes,
          ],
        ),
      ),
    );

    // AnimatedBuilder for shake — preserves child across animation frames
    return AnimatedBuilder(
      animation: _shakeController,
      child: inputWidget,
      builder: (context, child) {
        if (!_shakeController.isAnimating) return child!;
        final offset = sin(_shakeController.value * pi * 5) * 10;
        return Transform.translate(
          offset: Offset(offset, 0),
          child: child,
        );
      },
    );
  }

  /// Blinking cursor for the active OTP box
  Widget _buildCursor() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 600),
      builder: (context, value, _) {
        // Blink: visible for first 60% of cycle, hidden for last 40%
        final visible = (value * 2).floor() % 2 == 0;
        return AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 100),
          child: Container(
            width: 2,
            height: 26,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        );
      },
      onEnd: () {
        // Restart blink cycle
        if (mounted) setState(() {});
      },
    );
  }

  /// Verify button - Premium gradient style
  Widget _buildVerifyButton() {
    final cs = Theme.of(context).colorScheme;
    final isDisabled = _isLoading || _otpState == OTPState.success;
    final isComplete = _otpCode.length == 6;

    return SizedBox(
      width: double.infinity,
      height: 58,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: isComplete && !isDisabled
              ? LinearGradient(
                  colors: [
                    AppTheme.primaryColor,
                    AppTheme.primaryColor.withBlue(255),
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : null,
          color: !isComplete || isDisabled
              ? cs.outlineVariant
              : null,
          boxShadow: isComplete && !isDisabled
              ? [
                  BoxShadow(
                    color: AppTheme.primaryColor.withOpacity(0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: ElevatedButton(
          onPressed: isDisabled || !isComplete ? null : _handleVerifyOtp,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.transparent,
            disabledForegroundColor: cs.onSurfaceVariant,
            elevation: 0,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Verify Code',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                        color: isComplete ? Colors.white : cs.onSurfaceVariant,
                      ),
                    ),
                    if (isComplete) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward_rounded, size: 20),
                    ],
                  ],
                ),
        ),
      ),
    )
        .animate()
        .fadeIn(delay: 400.ms, duration: 400.ms)
        .slideY(begin: 0.15, end: 0);
  }

  /// Help text at bottom - with icon
  Widget _buildHelpText() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              "Code expires in 10 minutes. Check SMS inbox.",
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 500.ms, duration: 400.ms);
  }
}
