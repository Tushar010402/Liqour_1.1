import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// OTP Status Types
enum OTPStatus {
  waiting,       // Waiting for SMS
  smsDetected,   // SMS received
  autoFilling,   // Auto-filling OTP
  verifying,     // Verifying OTP with backend
  success,       // OTP verified successfully
  error,         // OTP verification failed
}

/// Status indicator showing OTP auto-fill progress
class OTPStatusIndicator extends StatelessWidget {
  final OTPStatus status;
  final String? message;

  const OTPStatusIndicator({
    super.key,
    required this.status,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _getBackgroundColor(),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _getBorderColor()),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildIcon(),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              message ?? _getDefaultMessage(),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: _getTextColor(),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIcon() {
    switch (status) {
      case OTPStatus.waiting:
        return SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
          ),
        );

      case OTPStatus.smsDetected:
        return Icon(
          Icons.sms_rounded,
          color: Colors.blue[700],
          size: 20,
        );

      case OTPStatus.autoFilling:
        return SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[700]!),
          ),
        );

      case OTPStatus.verifying:
        return SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
          ),
        );

      case OTPStatus.success:
        return Icon(
          Icons.check_circle_rounded,
          color: Colors.green[700],
          size: 20,
        );

      case OTPStatus.error:
        return Icon(
          Icons.error_outline_rounded,
          color: Colors.red[700],
          size: 20,
        );
    }
  }

  Color _getBackgroundColor() {
    switch (status) {
      case OTPStatus.waiting:
        return Colors.blue[50]!;
      case OTPStatus.smsDetected:
        return Colors.blue[50]!;
      case OTPStatus.autoFilling:
        return Colors.blue[50]!;
      case OTPStatus.verifying:
        return AppTheme.primaryColor.withOpacity(0.1);
      case OTPStatus.success:
        return Colors.green[50]!;
      case OTPStatus.error:
        return Colors.red[50]!;
    }
  }

  Color _getBorderColor() {
    switch (status) {
      case OTPStatus.waiting:
        return Colors.blue[200]!;
      case OTPStatus.smsDetected:
        return Colors.blue[300]!;
      case OTPStatus.autoFilling:
        return Colors.blue[300]!;
      case OTPStatus.verifying:
        return AppTheme.primaryColor.withOpacity(0.3);
      case OTPStatus.success:
        return Colors.green[300]!;
      case OTPStatus.error:
        return Colors.red[300]!;
    }
  }

  Color _getTextColor() {
    switch (status) {
      case OTPStatus.waiting:
        return Colors.blue[700]!;
      case OTPStatus.smsDetected:
        return Colors.blue[800]!;
      case OTPStatus.autoFilling:
        return Colors.blue[800]!;
      case OTPStatus.verifying:
        return AppTheme.primaryColor;
      case OTPStatus.success:
        return Colors.green[700]!;
      case OTPStatus.error:
        return Colors.red[700]!;
    }
  }

  String _getDefaultMessage() {
    switch (status) {
      case OTPStatus.waiting:
        return '📱 Waiting for SMS...';
      case OTPStatus.smsDetected:
        return '📬 SMS received!';
      case OTPStatus.autoFilling:
        return '🔄 Auto-filling OTP...';
      case OTPStatus.verifying:
        return '🔐 Verifying OTP...';
      case OTPStatus.success:
        return '✅ OTP verified successfully!';
      case OTPStatus.error:
        return '❌ Invalid OTP. Please try again.';
    }
  }
}

/// Info banner explaining auto-fill feature
class OTPAutoFillInfoBanner extends StatelessWidget {
  const OTPAutoFillInfoBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: Colors.blue[700],
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'OTP will be filled automatically when SMS arrives',
              style: TextStyle(
                fontSize: 13,
                color: Colors.blue[800],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Success checkmark animation
class OTPSuccessAnimation extends StatefulWidget {
  const OTPSuccessAnimation({super.key});

  @override
  State<OTPSuccessAnimation> createState() => _OTPSuccessAnimationState();
}

class _OTPSuccessAnimationState extends State<OTPSuccessAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.elasticOut,
      ),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: Colors.green[50],
          shape: BoxShape.circle,
          border: Border.all(color: Colors.green[300]!, width: 3),
        ),
        child: Icon(
          Icons.check_rounded,
          color: Colors.green[700],
          size: 50,
        ),
      ),
    );
  }
}
