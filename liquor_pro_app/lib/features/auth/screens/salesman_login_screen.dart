import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../models/device_session_models.dart';
import '../providers/auth_provider.dart';
import '../widgets/device_limit_modal.dart';

/// Combined Phone + OTP Login Screen — pixel-matched to JSX Screen_Login.
/// Hero shrinks smoothly when OTP fields appear, auto-scrolls to show OTP.
class SalesmanLoginScreen extends StatefulWidget {
  const SalesmanLoginScreen({super.key});

  @override
  State<SalesmanLoginScreen> createState() => _SalesmanLoginScreenState();
}

enum _LoginState { idle, otpSent, verifying }

class _SalesmanLoginScreenState extends State<SalesmanLoginScreen>
    with TickerProviderStateMixin {
  final _phoneController = TextEditingController();
  final _scrollController = ScrollController();
  final List<TextEditingController> _otpControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocusNodes = List.generate(6, (_) => FocusNode());

  _LoginState _state = _LoginState.idle;
  String? _sessionId;
  String? _errorMessage;
  bool _isLoading = false;

  late AnimationController _otpAnimController;
  late Animation<double> _otpRevealAnimation;
  late AnimationController _heroAnimController;
  late Animation<double> _heroShrinkAnimation;

  @override
  void initState() {
    super.initState();
    _otpAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _otpRevealAnimation = CurvedAnimation(
      parent: _otpAnimController,
      curve: Curves.easeOutCubic,
    );
    _heroAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _heroShrinkAnimation = CurvedAnimation(
      parent: _heroAnimController,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _scrollController.dispose();
    for (final c in _otpControllers) { c.dispose(); }
    for (final n in _otpFocusNodes) { n.dispose(); }
    _otpAnimController.dispose();
    _heroAnimController.dispose();
    super.dispose();
  }

  String get _fullOtp => _otpControllers.map((c) => c.text).join();

  String _formatPhone(String raw) {
    final digitsOnly = raw.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.startsWith('91') && digitsOnly.length > 10) return '+$digitsOnly';
    if (digitsOnly.length == 10) return '+91$digitsOnly';
    if (raw.startsWith('+')) return raw;
    return '+91$digitsOnly';
  }

  void _showOtpSection() {
    setState(() {
      _state = _LoginState.otpSent;
      _isLoading = false;
    });
    // Animate: shrink hero + reveal OTP + scroll down
    _heroAnimController.forward();
    _otpAnimController.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Smooth scroll to show OTP fields
      Future.delayed(const Duration(milliseconds: 200), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
          );
        }
      });
      // Focus first OTP box
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) _otpFocusNodes[0].requestFocus();
      });
    });
  }

  Future<void> _handleSendOtp() async {
    final rawPhone = _phoneController.text.trim();
    if (rawPhone.length < 10) {
      setState(() => _errorMessage = 'Enter a valid 10-digit phone number');
      return;
    }
    final phone = _formatPhone(rawPhone);

    setState(() { _isLoading = true; _errorMessage = null; });

    final authProvider = context.read<AuthProvider>();
    final checkResult = await authProvider.checkUser(phone);
    if (!mounted) return;

    if (checkResult == null) {
      setState(() { _isLoading = false; _errorMessage = authProvider.errorMessage ?? 'Failed to check user'; });
      return;
    }

    // Security: don't use exists field — always proceed to OTP.
    // Login vs registration is determined after verify-otp.
    if (checkResult.sessionId != null) {
      _sessionId = checkResult.sessionId;
      _showOtpSection();
      return;
    }

    final otpResult = await authProvider.sendOtp(phone);
    if (!mounted) return;

    if (otpResult != null) {
      _sessionId = otpResult.sessionId;
      _showOtpSection();
    } else {
      setState(() { _isLoading = false; _errorMessage = authProvider.errorMessage ?? 'Failed to send OTP'; });
    }
  }

  Future<void> _handleVerifyOtp() async {
    final otp = _fullOtp;
    if (otp.length != 6) {
      setState(() => _errorMessage = 'Enter the complete 6-digit OTP');
      return;
    }
    setState(() { _state = _LoginState.verifying; _isLoading = true; _errorMessage = null; });

    final authProvider = context.read<AuthProvider>();
    try {
      final result = await authProvider.verifyOtp(
        mobile: _formatPhone(_phoneController.text.trim()),
        otp: otp,
        sessionId: _sessionId,
      );
      if (!mounted) return;

      if (result != null) {
        if (result.isLogin) {
          context.go('/home');
        } else if (result.needsRegistration) {
          // New user — redirect to registration
          context.go('/pre-registration', extra: {
            'phone': _formatPhone(_phoneController.text.trim()),
            'registrationToken': result.registrationToken,
          });
        } else {
          setState(() { _state = _LoginState.otpSent; _isLoading = false; _errorMessage = 'Unexpected response. Please try again.'; });
        }
      } else {
        setState(() { _state = _LoginState.otpSent; _isLoading = false; _errorMessage = authProvider.errorMessage ?? 'Invalid OTP'; });
      }
    } on DeviceLimitException catch (e) {
      if (!mounted) return;
      setState(() { _state = _LoginState.otpSent; _isLoading = false; });
      _showDeviceLimitModal(e.error);
    } catch (e) {
      if (!mounted) return;
      setState(() { _state = _LoginState.otpSent; _isLoading = false; _errorMessage = e.toString(); });
    }
  }

  /// Show device limit modal — lets user pick which device to log out
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

  /// Force login by removing another device session
  Future<void> _handleForceLogin(String sessionIdToRemove) async {
    if (!mounted) return;
    final otp = _fullOtp;
    if (otp.length != 6) {
      setState(() => _errorMessage = 'Please enter the 6-digit code first');
      return;
    }

    setState(() { _isLoading = true; _errorMessage = null; });

    final authProvider = context.read<AuthProvider>();
    try {
      final result = await authProvider.forceLoginOtp(
        mobile: _formatPhone(_phoneController.text.trim()),
        otp: otp,
        sessionIdToRemove: sessionIdToRemove,
        sessionId: _sessionId,
      );
      if (!mounted) return;

      if (result != null) {
        context.go('/home');
      } else {
        setState(() { _isLoading = false; _errorMessage = authProvider.errorMessage ?? 'Login failed. Please try again.'; });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _isLoading = false; _errorMessage = 'Login failed: ${e.toString()}'; });
    }
  }

  Future<void> _handleResendOtp() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    final authProvider = context.read<AuthProvider>();
    final otpResult = await authProvider.sendOtp(_formatPhone(_phoneController.text.trim()));
    if (!mounted) return;
    if (otpResult != null) {
      _sessionId = otpResult.sessionId;
      for (final c in _otpControllers) { c.clear(); }
      setState(() => _isLoading = false);
      _otpFocusNodes[0].requestFocus();
    } else {
      setState(() { _isLoading = false; _errorMessage = authProvider.errorMessage ?? 'Failed to resend OTP'; });
    }
  }

  void _onOtpChanged(int index, String value) {
    if (value.length == 1 && index < 5) _otpFocusNodes[index + 1].requestFocus();
    if (value.isEmpty && index > 0) _otpFocusNodes[index - 1].requestFocus();
    if (_fullOtp.length == 6) _handleVerifyOtp();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          children: [
            _buildHeroSection(),
            _buildFormSection(),
          ],
        ),
      ),
    );
  }

  /// Hero section — animates from full height (360) to compact (180) when OTP shows
  Widget _buildHeroSection() {
    return AnimatedBuilder(
      animation: _heroShrinkAnimation,
      builder: (context, child) {
        // Lerp from 360 -> 180 as OTP animates in
        final height = 360.0 - (180.0 * _heroShrinkAnimation.value);
        return Container(
          width: double.infinity,
          height: height,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF2979D6), Color(0xFF1565C0), Color(0xFF0D47A1), Color(0xFF0A3B87)],
              stops: [0.0, 0.3, 0.6, 1.0],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(30),
              bottomRight: Radius.circular(30),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned.fill(child: CustomPaint(painter: _GridPatternPainter())),
              // Content fades as hero shrinks
              SafeArea(
                child: Opacity(
                  opacity: 1.0 - (_heroShrinkAnimation.value * 0.7),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                    child: _heroShrinkAnimation.value < 0.5
                        ? SizedBox(
                            height: 270,
                            child: Stack(
                              children: [
                                Positioned(left: 0, bottom: 0, child: SizedBox(width: 120, height: 220, child: CustomPaint(painter: _PersonPainter()))),
                                Positioned(right: 5, top: 5, child: _buildPhoneMockup()),
                                Positioned(
                                  right: -2, top: -12,
                                  child: Container(
                                    width: 50, height: 50,
                                    decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.1)),
                                    child: Icon(Icons.lock_rounded, color: Colors.white.withValues(alpha: 0.4), size: 26),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.lock_rounded, color: Colors.white.withValues(alpha: 0.6), size: 28),
                                const SizedBox(width: 12),
                                Text('LiquorPro', style: AppTextStyles.h3.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                              ],
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPhoneMockup() {
    return Container(
      width: 150,
      decoration: BoxDecoration(
        color: const Color(0xFFD8DDE4),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 48, offset: const Offset(0, 16))],
      ),
      padding: const EdgeInsets.all(5),
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
        padding: const EdgeInsets.fromLTRB(14, 24, 14, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 44, height: 5, margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: const Color(0xFF333333), borderRadius: BorderRadius.circular(3))),
            Container(width: 34, height: 34, margin: const EdgeInsets.only(bottom: 14),
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFE3EBF5)),
              child: const Icon(Icons.person, color: Color(0xFF0D47A1), size: 18)),
            Container(height: 8, width: 120, margin: const EdgeInsets.only(bottom: 8), decoration: BoxDecoration(color: const Color(0xFF0D47A1), borderRadius: BorderRadius.circular(4))),
            Container(height: 8, width: 94, margin: const EdgeInsets.only(bottom: 8), decoration: BoxDecoration(color: const Color(0xFF0D47A1), borderRadius: BorderRadius.circular(4))),
            Container(height: 8, width: 60, margin: const EdgeInsets.only(bottom: 14), decoration: BoxDecoration(color: const Color(0xFF0D47A1), borderRadius: BorderRadius.circular(4))),
            Wrap(spacing: 3.5, runSpacing: 3.5, children: List.generate(9, (_) => Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF0D47A1))))),
            const SizedBox(height: 16),
            Container(width: 75, padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(color: const Color(0xFF0D47A1), borderRadius: BorderRadius.circular(6)),
              child: Text('Login', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, fontFamily: AppTextStyles.bodyMedium.fontFamily))),
          ],
        ),
      ),
    );
  }

  Widget _buildFormSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 30, 26, 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Phone icon + label
          Row(
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF1565C0), width: 2)),
                child: const Icon(Icons.phone, color: Color(0xFF1565C0), size: 16),
              ),
              const SizedBox(width: 12),
              Text('Phone No.', style: AppTextStyles.h4.copyWith(color: const Color(0xFF0D47A1), fontWeight: FontWeight.w800, fontSize: 22)),
            ],
          ),
          const SizedBox(height: 16),

          // Phone input
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            maxLength: 10,
            enabled: _state == _LoginState.idle,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: AppTextStyles.bodyLarge.copyWith(fontSize: 16),
            decoration: InputDecoration(
              hintText: 'Enter',
              hintStyle: AppTextStyles.bodyLarge.copyWith(color: const Color(0xFFAAAAAA), fontWeight: FontWeight.w500),
              counterText: '',
              filled: true,
              fillColor: const Color(0xFFECEEF3),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            ),
          ),

          // OTP section (animated reveal)
          SizeTransition(
            sizeFactor: _otpRevealAnimation,
            axisAlignment: -1.0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 28),
                Text(
                  'OTP sent to your email and mobile. Enter it to continue.',
                  style: AppTextStyles.bodyMedium.copyWith(color: const Color(0xFF0D47A1), fontWeight: FontWeight.w600, fontSize: 18, height: 1.45),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(6, (i) {
                    return SizedBox(
                      width: 48, height: 48,
                      child: TextField(
                        controller: _otpControllers[i],
                        focusNode: _otpFocusNodes[i],
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        maxLength: 1,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: AppTextStyles.h5.copyWith(fontWeight: FontWeight.w700, fontSize: 22),
                        decoration: InputDecoration(
                          counterText: '',
                          filled: true,
                          fillColor: const Color(0xFFF8FAFF),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFC5D4EB), width: 2)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFC5D4EB), width: 2)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF0D47A1), width: 2)),
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: (v) => _onOtpChanged(i, v),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 22),
                Center(
                  child: GestureDetector(
                    onTap: _isLoading ? null : _handleResendOtp,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Resend', style: AppTextStyles.bodyMedium.copyWith(color: const Color(0xFF1565C0), fontWeight: FontWeight.w600, fontSize: 18)),
                        const SizedBox(width: 8),
                        const Icon(Icons.refresh_rounded, color: Color(0xFF1565C0), size: 20),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Error
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(_errorMessage!, style: AppTextStyles.bodySmall.copyWith(color: AppColors.error)),
          ],

          const SizedBox(height: 32),

          // Login button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _isLoading ? null : (_state == _LoginState.idle ? _handleSendOtp : _handleVerifyOtp),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0B2F6B),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFF0B2F6B).withValues(alpha: 0.6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _isLoading
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : Text(
                      _state == _LoginState.idle ? 'Send OTP' : 'Login',
                      style: AppTextStyles.h5.copyWith(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GridPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.05)..strokeWidth = 0.7;
    const spacing = 38.0;
    for (double x = 0; x < size.width; x += spacing) canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    for (double y = 0; y < size.height; y += spacing) canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PersonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 120;
    final face = Paint()..color = const Color(0xFFF0C8A0);
    canvas.drawOval(Rect.fromCenter(center: Offset(52*s, 38*s), width: 38*s, height: 46*s), face);
    final hair = Paint()..color = const Color(0xFF0A1628);
    canvas.drawPath(Path()..moveTo(34*s,30*s)..cubicTo(34*s,16*s,44*s,8*s,56*s,10*s)..cubicTo(68*s,12*s,72*s,24*s,70*s,34*s)..cubicTo(70*s,28*s,66*s,18*s,54*s,16*s)..cubicTo(42*s,14*s,36*s,22*s,34*s,30*s)..close(), hair);
    final shirt = Paint()..color = const Color(0xFF42A5F5);
    canvas.drawPath(Path()..moveTo(32*s,68*s)..cubicTo(32*s,66*s,40*s,64*s,52*s,64*s)..cubicTo(64*s,64*s,74*s,66*s,76*s,68*s)..lineTo(80*s,108*s)..cubicTo(80*s,112*s,28*s,112*s,26*s,108*s)..close(), shirt);
    canvas.drawPath(Path()..moveTo(34*s,108*s)..lineTo(32*s,176*s)..lineTo(44*s,176*s)..lineTo(52*s,128*s)..lineTo(60*s,176*s)..lineTo(72*s,176*s)..lineTo(70*s,108*s)..close(), hair);
    canvas.drawOval(Rect.fromCenter(center: Offset(38*s,180*s), width: 26*s, height: 11*s), shirt);
    canvas.drawOval(Rect.fromCenter(center: Offset(66*s,180*s), width: 26*s, height: 11*s), shirt);
    canvas.drawCircle(Offset(12*s, 60*s), 16*s, Paint()..color = Colors.white.withValues(alpha: 0.12));
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
