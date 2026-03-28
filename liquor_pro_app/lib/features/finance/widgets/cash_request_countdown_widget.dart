import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../models/cash_models.dart';

/// Industrial-Grade Real-Time Countdown Timer for Cash Request Expiration
///
/// Features:
/// - Updates every second using Timer.periodic
/// - Proper lifecycle management (cancels timer in dispose)
/// - Visual urgency indicators (color changes at thresholds)
/// - Auto-refresh callback when expired
/// - Memory-safe with mounted checks
/// - Optimized: only rebuilds countdown widget, not parent
class CashRequestCountdownWidget extends StatefulWidget {
  final CashRequest request;
  final VoidCallback? onExpired;

  const CashRequestCountdownWidget({
    super.key,
    required this.request,
    this.onExpired,
  });

  @override
  State<CashRequestCountdownWidget> createState() => _CashRequestCountdownWidgetState();
}

class _CashRequestCountdownWidgetState extends State<CashRequestCountdownWidget> {
  Timer? _timer;
  Duration? _remaining;
  bool _hasExpired = false;

  @override
  void initState() {
    super.initState();
    _updateRemaining();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  void _updateRemaining() {
    if (!mounted) return;

    setState(() {
      _remaining = widget.request.timeRemaining;
      _hasExpired = widget.request.hasExpired;
    });

    // Trigger callback when expired
    if (_hasExpired && widget.onExpired != null) {
      // Use post-frame callback to avoid calling setState during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onExpired?.call();
      });
    }
  }

  void _startTimer() {
    // Update every second
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      _updateRemaining();

      // Stop timer if expired
      if (_hasExpired) {
        _timer?.cancel();
        _timer = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Show expired state
    if (_remaining == null || _hasExpired) {
      return _buildExpiredIndicator();
    }

    final minutes = _remaining!.inMinutes;
    final seconds = _remaining!.inSeconds % 60;
    final isUrgent = minutes < 3; // Less than 3 minutes = urgent
    final isCritical = minutes < 1; // Less than 1 minute = critical

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: (isCritical
                ? AppColors.error
                : isUrgent
                    ? AppColors.warning
                    : AppColors.info)
            .withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: (isCritical
                  ? AppColors.error
                  : isUrgent
                      ? AppColors.warning
                      : AppColors.info)
              .withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.timer,
            size: 16,
            color: isCritical
                ? AppColors.error
                : isUrgent
                    ? AppColors.warning
                    : AppColors.info,
          ),
          const SizedBox(width: 8),
          Text(
            'Expires in: ${minutes}m ${seconds}s',
            style: AppTextStyles.bodySmall.copyWith(
              color: isCritical
                  ? AppColors.error
                  : isUrgent
                      ? AppColors.warning
                      : AppColors.info,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace', // Fixed-width for stable display
            ),
          ),
          if (isUrgent) ...[
            const SizedBox(width: 8),
            Icon(
              Icons.warning_amber,
              size: 16,
              color: isCritical ? AppColors.error : AppColors.warning,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExpiredIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.neutral.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.neutral.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_off, size: 16, color: AppColors.neutral),
          const SizedBox(width: 8),
          Text(
            'EXPIRED',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.neutral,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
