import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:smart_auth/smart_auth.dart';

/// Cross-platform OTP Auto-fill Service
///
/// Platform-specific behavior:
/// - **iOS**: Uses AutofillHints.oneTimeCode in the Pinput widget for native
///   keyboard OTP suggestion. User taps to auto-fill.
/// - **Android**: Uses SMS Retriever API via smart_auth package to automatically
///   read OTP from SMS without user interaction.
///
/// For Android SMS auto-read to work, the SMS must contain:
/// 1. The 6-digit OTP code
/// 2. The app signature hash (printed to console on init)
///
/// Example SMS format:
/// ```
/// Your LiquorPro verification code is: 123456
///
/// FA+9qCX9VSu
/// ```
class OTPAutoFillService {
  static final OTPAutoFillService _instance = OTPAutoFillService._internal();
  factory OTPAutoFillService() => _instance;
  OTPAutoFillService._internal();

  final SmartAuth _smartAuth = SmartAuth();
  String? _appSignature;
  bool _isListening = false;
  bool _isInitialized = false;

  final _otpController = StreamController<String>.broadcast();

  /// Get the app signature hash for SMS template (Android only)
  /// Returns null on iOS
  String? get appSignature => _appSignature;

  /// Check if service is actively listening
  bool get isListening => _isListening;

  /// Initialize the service
  /// Call this when the app starts or before OTP screen
  Future<void> initialize() async {
    if (_isInitialized) return;

    if (Platform.isAndroid) {
      try {
        // Get app signature for SMS template
        final signature = await _smartAuth.getAppSignature();
        _appSignature = signature;

        debugPrint('[OTPAutoFill] Initialized (Android) signature: $signature');

        _isInitialized = true;
      } catch (e) {
        debugPrint('Failed to initialize OTPAutoFillService: $e');
      }
    } else if (Platform.isIOS) {
      debugPrint('[OTPAutoFill] Initialized (iOS) — native keyboard autofill');
      _isInitialized = true;
    }
  }

  /// Start listening for OTP from SMS (Android only)
  /// iOS uses native keyboard autofill which is handled by Pinput widget
  ///
  /// Returns a stream that emits the OTP code when detected
  Stream<String> listenForOTP() {
    if (Platform.isAndroid && !_isListening) {
      _startAndroidSmsListener();
    } else if (Platform.isIOS) {
      debugPrint('[OTPAutoFill] iOS uses native keyboard suggestion');
      debugPrint('[OTPAutoFill] No SMS listening required');
    }

    return _otpController.stream;
  }

  /// Start Android SMS Retriever listener
  void _startAndroidSmsListener() async {
    _isListening = true;
    debugPrint('[OTPAutoFill] Starting Android SMS listener...');

    try {
      // Use SMS User Consent API - shows system dialog to user
      // More reliable than SMS Retriever API
      final result = await _smartAuth.getSmsCode(
        matcher: r'\d{6}', // Match exactly 6 digits
        useUserConsentApi: true, // Shows confirmation dialog
      );

      if (result.succeed && result.code != null) {
        final code = result.code!;
        debugPrint('[OTPAutoFill] SMS code detected: $code');

        if (!_otpController.isClosed) {
          _otpController.add(code);
        }
      } else {
        debugPrint('[OTPAutoFill] No SMS code found or user cancelled');
      }
    } catch (e) {
      debugPrint('[OTPAutoFill] Error reading SMS: $e');
    }

    _isListening = false;
  }

  /// Manually trigger SMS reading (Android only)
  /// Call this when entering OTP screen
  /// Uses User Consent API (shows confirmation dialog)
  Future<String?> requestSmsCode() async {
    if (!Platform.isAndroid) {
      return null;
    }

    debugPrint('[OTPAutoFill] Requesting SMS code...');

    try {
      final result = await _smartAuth.getSmsCode(
        matcher: r'\d{6}',
        useUserConsentApi: true,
      );

      if (result.succeed && result.code != null) {
        debugPrint('[OTPAutoFill] Got SMS code: ${result.code}');
        return result.code;
      }
    } catch (e) {
      debugPrint('[OTPAutoFill] Error requesting SMS: $e');
    }

    return null;
  }

  /// Alternative: Use SMS Retriever API (no user interaction needed)
  /// Requires proper app signature in SMS
  Future<String?> requestSmsCodeSilent() async {
    if (!Platform.isAndroid) {
      return null;
    }

    debugPrint('[OTPAutoFill] Requesting SMS code silently...');

    try {
      final result = await _smartAuth.getSmsCode(
        matcher: r'\d{6}',
        useUserConsentApi: false, // Silent - no dialog
      );

      if (result.succeed && result.code != null) {
        debugPrint('[OTPAutoFill] Got SMS code silently: ${result.code}');
        return result.code;
      }
    } catch (e) {
      debugPrint('[OTPAutoFill] Silent SMS request failed: $e');
    }

    return null;
  }

  /// Stop listening for SMS
  void stopListening() {
    debugPrint('[OTPAutoFill] Stopping listener');
    _isListening = false;
    _smartAuth.removeSmsListener();
  }

  /// Dispose resources
  void dispose() {
    stopListening();
    if (!_otpController.isClosed) {
      _otpController.close();
    }
    _isInitialized = false;
  }
}
