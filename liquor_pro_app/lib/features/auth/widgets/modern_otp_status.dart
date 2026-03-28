import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/app_theme.dart';

/// Modern OTP status states
enum OTPState {
  idle,        // Waiting for user input - no visual indicator
  smsDetected, // SMS received (Android) - brief success indicator
  verifying,   // API call in progress - spinner
  success,     // Verified successfully - checkmark
  error,       // Wrong code - error message
  expired,     // Timer ran out - expired message
}

/// Modern OTP Status indicator - minimal inline design
/// Replaces the old boxy colored containers with subtle inline indicators
class ModernOtpStatus extends StatelessWidget {
  final OTPState state;
  final String? customMessage;

  const ModernOtpStatus({
    super.key,
    required this.state,
    this.customMessage,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.2),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: _buildStatusContent(),
    );
  }

  Widget _buildStatusContent() {
    switch (state) {
      case OTPState.idle:
        // No visual indicator when idle
        return const SizedBox.shrink(key: ValueKey('idle'));

      case OTPState.smsDetected:
        return _InlineStatus(
          key: const ValueKey('smsDetected'),
          icon: Icons.sms_outlined,
          text: 'Code detected',
          color: AppTheme.successColor,
        ).animate().fadeIn(duration: 200.ms).slideY(begin: 0.3, end: 0);

      case OTPState.verifying:
        return Row(
          key: const ValueKey('verifying'),
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Verifying...',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );

      case OTPState.success:
        return _SuccessCheckmark(key: const ValueKey('success'));

      case OTPState.error:
        return _InlineStatus(
          key: const ValueKey('error'),
          icon: Icons.error_outline_rounded,
          text: customMessage ?? 'Invalid code. Please try again.',
          color: AppTheme.errorColor,
        ).animate().shake(hz: 3, rotation: 0.02, duration: 400.ms);

      case OTPState.expired:
        return _InlineStatus(
          key: const ValueKey('expired'),
          icon: Icons.timer_off_outlined,
          text: 'Code expired. Please request a new one.',
          color: AppTheme.errorColor,
        );
    }
  }
}

/// Simple inline status indicator with icon and text
class _InlineStatus extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _InlineStatus({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Success checkmark with elastic animation
class _SuccessCheckmark extends StatelessWidget {
  const _SuccessCheckmark({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: AppTheme.successColor.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.check_rounded,
        color: AppTheme.successColor,
        size: 36,
      ),
    )
        .animate()
        .scale(
          begin: const Offset(0, 0),
          end: const Offset(1, 1),
          curve: Curves.elasticOut,
          duration: 600.ms,
        )
        .then(delay: 200.ms)
        .shimmer(
          duration: 400.ms,
          color: AppTheme.successColor.withOpacity(0.3),
        );
  }
}

/// Floating toast for SMS detection (Android)
/// Shows briefly when OTP is auto-detected from SMS
class OtpDetectedToast extends StatelessWidget {
  const OtpDetectedToast({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.successColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppTheme.successColor.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sms_outlined, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          const Text(
            'OTP detected',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    )
        .animate()
        .slideY(begin: 1, end: 0, duration: 300.ms, curve: Curves.easeOut)
        .then(delay: 1500.ms)
        .fadeOut(duration: 300.ms);
  }
}
