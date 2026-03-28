import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../services/otp_timer_service.dart';

/// Widget showing OTP expiry countdown (10 minutes)
class OTPExpiryTimer extends StatelessWidget {
  final OTPTimerService timerService;

  const OTPExpiryTimer({
    super.key,
    required this.timerService,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: timerService.expiryStream,
      initialData: timerService.remainingSeconds,
      builder: (context, snapshot) {
        final remaining = snapshot.data ?? 0;

        if (remaining <= 0) {
          // OTP expired
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.red[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red[300]!),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline_rounded, color: Colors.red[700], size: 20),
                const SizedBox(width: 8),
                Text(
                  'OTP Expired',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.red[700],
                  ),
                ),
              ],
            ),
          );
        }

        final minutes = remaining ~/ 60;
        final seconds = remaining % 60;
        final timeString = '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

        // Color coding based on remaining time
        Color backgroundColor;
        Color borderColor;
        Color textColor;
        Color iconColor;

        if (remaining > 300) {
          // > 5 minutes - Green
          backgroundColor = Colors.green[50]!;
          borderColor = Colors.green[200]!;
          textColor = Colors.green[700]!;
          iconColor = Colors.green[600]!;
        } else if (remaining > 120) {
          // > 2 minutes - Orange
          backgroundColor = Colors.orange[50]!;
          borderColor = Colors.orange[200]!;
          textColor = Colors.orange[700]!;
          iconColor = Colors.orange[600]!;
        } else {
          // <= 2 minutes - Red
          backgroundColor = Colors.red[50]!;
          borderColor = Colors.red[200]!;
          textColor = Colors.red[700]!;
          iconColor = Colors.red[600]!;
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.timer_outlined, color: iconColor, size: 20),
              const SizedBox(width: 8),
              Text(
                'OTP expires in $timeString',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Widget showing resend cooldown or "Resend OTP" button
class OTPResendButton extends StatelessWidget {
  final OTPTimerService timerService;
  final VoidCallback onResend;
  final bool isLoading;

  const OTPResendButton({
    super.key,
    required this.timerService,
    required this.onResend,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<OTPTimerState>(
      stream: timerService.stateStream,
      initialData: timerService.state,
      builder: (context, snapshot) {
        final state = snapshot.data ?? OTPTimerState.active;

        if (state == OTPTimerState.cooldown) {
          // Show cooldown timer
          return StreamBuilder<int>(
            stream: timerService.cooldownStream,
            initialData: timerService.cooldownSeconds,
            builder: (context, snapshot) {
              final cooldown = snapshot.data ?? 0;

              final cs = Theme.of(context).colorScheme;
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.timer_outlined, size: 18, color: cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text(
                    'Resend OTP in ${cooldown}s',
                    style: TextStyle(
                      fontSize: 14,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              );
            },
          );
        }

        if (state == OTPTimerState.expired) {
          // OTP expired - show resend button prominently
          return ElevatedButton.icon(
            onPressed: isLoading ? null : onResend,
            icon: isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.refresh_rounded, size: 20),
            label: Text(isLoading ? 'Sending...' : 'Resend OTP'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }

        // Can resend
        return TextButton.icon(
          onPressed: isLoading ? null : onResend,
          icon: isLoading
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                  ),
                )
              : const Icon(Icons.refresh_rounded, size: 20),
          label: Text(isLoading ? 'Sending...' : 'Resend OTP'),
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.primaryColor,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
        );
      },
    );
  }
}
