import 'dart:async';
import 'package:flutter/foundation.dart';

/// OTP Timer States
enum OTPTimerState {
  active,       // OTP is valid, waiting for user to enter
  expired,      // OTP has expired (10 minutes passed)
  cooldown,     // Resend cooldown active (30 seconds after send)
  canResend,    // User can resend OTP now
}

/// OTP Timer Service - Handles OTP expiry and resend cooldown
class OTPTimerService {
  static final OTPTimerService _instance = OTPTimerService._internal();
  factory OTPTimerService() => _instance;
  OTPTimerService._internal();

  // Configuration
  static const Duration otpExpiryDuration = Duration(minutes: 10);
  static const Duration resendCooldownDuration = Duration(seconds: 30);

  // State
  Timer? _expiryTimer;
  Timer? _cooldownTimer;
  Timer? _tickTimer;

  DateTime? _otpSentAt;
  DateTime? _otpExpiresAt;
  DateTime? _lastResendAt;

  int _remainingSeconds = 0;
  int _cooldownSeconds = 0;

  OTPTimerState _state = OTPTimerState.active;

  // Stream controllers for reactive UI
  final _stateController = StreamController<OTPTimerState>.broadcast();
  final _expiryController = StreamController<int>.broadcast();
  final _cooldownController = StreamController<int>.broadcast();

  /// Initialize timer when OTP is sent
  void startTimer({DateTime? expiresAt}) {
    debugPrint('⏱️  [OTPTimer] Starting timer...');

    _otpSentAt = DateTime.now();
    _otpExpiresAt = expiresAt ?? _otpSentAt!.add(otpExpiryDuration);
    _lastResendAt = _otpSentAt;

    _state = OTPTimerState.cooldown;
    _stateController.add(_state);

    _calculateRemainingTime();
    _startExpiryTimer();
    _startCooldownTimer();
    _startTickTimer();

    debugPrint('⏱️  [OTPTimer] Timer started. Expires at: $_otpExpiresAt');
  }

  /// Calculate remaining seconds until expiry
  void _calculateRemainingTime() {
    if (_otpExpiresAt == null) {
      _remainingSeconds = 0;
      return;
    }

    final now = DateTime.now();
    final difference = _otpExpiresAt!.difference(now);

    _remainingSeconds = difference.inSeconds;

    if (_remainingSeconds < 0) {
      _remainingSeconds = 0;
    }

    _expiryController.add(_remainingSeconds);
  }

  /// Calculate remaining cooldown seconds
  void _calculateCooldownTime() {
    if (_lastResendAt == null) {
      _cooldownSeconds = 0;
      return;
    }

    final now = DateTime.now();
    final elapsed = now.difference(_lastResendAt!);
    final remaining = resendCooldownDuration - elapsed;

    _cooldownSeconds = remaining.inSeconds;

    if (_cooldownSeconds < 0) {
      _cooldownSeconds = 0;
    }

    _cooldownController.add(_cooldownSeconds);
  }

  /// Start expiry countdown timer
  void _startExpiryTimer() {
    _expiryTimer?.cancel();

    _expiryTimer = Timer(otpExpiryDuration, () {
      debugPrint('⏱️  [OTPTimer] ⏰ OTP EXPIRED');
      _state = OTPTimerState.expired;
      _stateController.add(_state);
      _tickTimer?.cancel();
    });
  }

  /// Start resend cooldown timer
  void _startCooldownTimer() {
    _cooldownTimer?.cancel();

    _cooldownTimer = Timer(resendCooldownDuration, () {
      debugPrint('⏱️  [OTPTimer] ✅ Cooldown complete - can resend now');
      if (_state != OTPTimerState.expired) {
        _state = OTPTimerState.canResend;
        _stateController.add(_state);
      }
    });
  }

  /// Start tick timer for UI updates (every second)
  void _startTickTimer() {
    _tickTimer?.cancel();

    _tickTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _calculateRemainingTime();
      _calculateCooldownTime();

      // Check if expired
      if (_remainingSeconds <= 0 && _state != OTPTimerState.expired) {
        _state = OTPTimerState.expired;
        _stateController.add(_state);
        timer.cancel();
      }
    });
  }

  /// Handle resend OTP
  void onResendOTP() {
    debugPrint('⏱️  [OTPTimer] 🔄 Resending OTP...');

    _lastResendAt = DateTime.now();
    _state = OTPTimerState.cooldown;
    _stateController.add(_state);

    _startCooldownTimer();
    _calculateCooldownTime();
  }

  /// Handle cooldown error from backend
  /// Backend returns: "Please wait X seconds before requesting another OTP"
  void handleCooldownError(int waitSeconds) {
    debugPrint('⏱️  [OTPTimer] ⚠️  Backend cooldown: $waitSeconds seconds');

    _cooldownSeconds = waitSeconds;
    _lastResendAt = DateTime.now().subtract(
      Duration(seconds: resendCooldownDuration.inSeconds - waitSeconds),
    );

    _state = OTPTimerState.cooldown;
    _stateController.add(_state);
    _cooldownController.add(_cooldownSeconds);

    _startCooldownTimer();
  }

  /// Format remaining time as MM:SS
  String formatRemainingTime() {
    final minutes = _remainingSeconds ~/ 60;
    final seconds = _remainingSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Format cooldown time as "Resend in Xs"
  String formatCooldown() {
    return 'Resend in ${_cooldownSeconds}s';
  }

  /// Check if OTP is expired
  bool get isExpired => _state == OTPTimerState.expired;

  /// Check if can resend
  bool get canResend => _state == OTPTimerState.canResend;

  /// Check if in cooldown
  bool get isInCooldown => _state == OTPTimerState.cooldown;

  /// Get current state
  OTPTimerState get state => _state;

  /// Get remaining seconds
  int get remainingSeconds => _remainingSeconds;

  /// Get cooldown seconds
  int get cooldownSeconds => _cooldownSeconds;

  /// Stream for state changes
  Stream<OTPTimerState> get stateStream => _stateController.stream;

  /// Stream for expiry countdown
  Stream<int> get expiryStream => _expiryController.stream;

  /// Stream for cooldown countdown
  Stream<int> get cooldownStream => _cooldownController.stream;

  /// Stop all timers
  void stopTimer() {
    debugPrint('⏱️  [OTPTimer] Stopping timer');
    _expiryTimer?.cancel();
    _cooldownTimer?.cancel();
    _tickTimer?.cancel();
  }

  /// Reset service
  void reset() {
    debugPrint('⏱️  [OTPTimer] Resetting timer');
    stopTimer();
    _otpSentAt = null;
    _otpExpiresAt = null;
    _lastResendAt = null;
    _remainingSeconds = 0;
    _cooldownSeconds = 0;
    _state = OTPTimerState.active;
  }

  /// Dispose resources
  void dispose() {
    stopTimer();
    _stateController.close();
    _expiryController.close();
    _cooldownController.close();
  }
}
