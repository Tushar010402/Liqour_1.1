import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/app_theme.dart';
import '../services/otp_timer_service.dart';

/// Modern OTP Timer widget - elegant inline countdown
/// Replaces the old boxy colored timer container
class ModernOtpTimer extends StatelessWidget {
  final OTPTimerService timerService;
  final VoidCallback onResend;
  final bool isLoading;

  const ModernOtpTimer({
    super.key,
    required this.timerService,
    required this.onResend,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: timerService.expiryStream,
      initialData: timerService.remainingSeconds,
      builder: (context, snapshot) {
        final remaining = snapshot.data ?? 0;
        final minutes = remaining ~/ 60;
        final seconds = remaining % 60;
        final timeString =
            '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

        // Color based on urgency
        Color timerColor;
        bool shouldPulse = false;

        if (remaining <= 0) {
          timerColor = AppTheme.errorColor;
        } else if (remaining <= 60) {
          // Last minute - red with pulse
          timerColor = AppTheme.errorColor;
          shouldPulse = true;
        } else if (remaining <= 120) {
          // Last 2 minutes - orange
          timerColor = AppTheme.warningColor;
        } else {
          // Normal - subtle gray
          timerColor = AppTheme.textSecondary;
        }

        if (remaining <= 0) {
          // Expired - show prominent resend button
          return _ExpiredView(
            onResend: onResend,
            isLoading: isLoading,
          );
        }

        // Active timer view
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Timer countdown
            _TimerDisplay(
              timeString: timeString,
              color: timerColor,
              shouldPulse: shouldPulse,
            ),

            const SizedBox(height: 8),

            // Resend link
            _ResendLink(
              timerService: timerService,
              onResend: onResend,
              isLoading: isLoading,
            ),
          ],
        );
      },
    );
  }
}

/// Timer display with optional pulse animation
class _TimerDisplay extends StatelessWidget {
  final String timeString;
  final Color color;
  final bool shouldPulse;

  const _TimerDisplay({
    required this.timeString,
    required this.color,
    required this.shouldPulse,
  });

  @override
  Widget build(BuildContext context) {
    Widget timer = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.schedule_rounded,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 6),
        Text(
          timeString,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: color,
            letterSpacing: 1,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );

    if (shouldPulse) {
      return timer
          .animate(onPlay: (controller) => controller.repeat(reverse: true))
          .scale(
            begin: const Offset(1, 1),
            end: const Offset(1.05, 1.05),
            duration: 600.ms,
          )
          .tint(color: color.withOpacity(0.1), duration: 600.ms);
    }

    return timer;
  }
}

/// Resend link with cooldown support
class _ResendLink extends StatelessWidget {
  final OTPTimerService timerService;
  final VoidCallback onResend;
  final bool isLoading;

  const _ResendLink({
    required this.timerService,
    required this.onResend,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<OTPTimerState>(
      stream: timerService.stateStream,
      initialData: timerService.state,
      builder: (context, stateSnapshot) {
        final state = stateSnapshot.data ?? OTPTimerState.active;

        if (state == OTPTimerState.cooldown) {
          // Show cooldown timer
          return StreamBuilder<int>(
            stream: timerService.cooldownStream,
            initialData: timerService.cooldownSeconds,
            builder: (context, cooldownSnapshot) {
              final cooldown = cooldownSnapshot.data ?? 0;
              return Text(
                'Resend in ${cooldown}s',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary.withOpacity(0.6),
                ),
              );
            },
          );
        }

        // Show resend button
        return GestureDetector(
          onTap: isLoading ? null : onResend,
          child: Text(
            'Resend code',
            style: TextStyle(
              fontSize: 13,
              color: isLoading
                  ? AppTheme.textSecondary.withOpacity(0.5)
                  : AppTheme.primaryColor,
              fontWeight: FontWeight.w500,
              decoration: TextDecoration.underline,
              decorationColor: AppTheme.primaryColor.withOpacity(0.5),
            ),
          ),
        );
      },
    );
  }
}

/// Expired view with prominent resend button
class _ExpiredView extends StatelessWidget {
  final VoidCallback onResend;
  final bool isLoading;

  const _ExpiredView({
    required this.onResend,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Expired message
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.timer_off_outlined,
              size: 16,
              color: AppTheme.errorColor,
            ),
            const SizedBox(width: 6),
            Text(
              'Code expired',
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.errorColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Resend button
        TextButton.icon(
          onPressed: isLoading ? null : onResend,
          icon: isLoading
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor),
                  ),
                )
              : const Icon(Icons.refresh_rounded, size: 18),
          label: Text(isLoading ? 'Sending...' : 'Request new code'),
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.primaryColor,
            backgroundColor: AppTheme.primaryColor.withOpacity(0.1),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ).animate().fadeIn().scale(begin: const Offset(0.9, 0.9)),
      ],
    );
  }
}
