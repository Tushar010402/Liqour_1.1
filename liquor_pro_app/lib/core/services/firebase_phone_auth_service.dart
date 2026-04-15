import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../utils/logger.dart';

/// Firebase Phone Auth Service
/// Handles OTP delivery via Firebase instead of Dr. Dang SMS service.
/// After getting a Firebase ID token, the app sends it to our backend
/// for JWT-based authentication.
class FirebasePhoneAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? _verificationId;
  int? _resendToken;

  String? get verificationId => _verificationId;

  /// Send OTP to phone number via Firebase
  /// Note: appVerificationDisabledForTesting is set in main.dart during Firebase init
  Future<FirebasePhoneAuthResult> verifyPhoneNumber(
    String phoneNumber, {
    int? forceResendingToken,
  }) async {
    final completer = Completer<FirebasePhoneAuthResult>();

    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: const Duration(seconds: 60),
      forceResendingToken: forceResendingToken ?? _resendToken,

      // Auto-verification on Android (SMS auto-read)
      verificationCompleted: (PhoneAuthCredential credential) async {
        Logger.info('[FirebasePhoneAuth] Auto-verification completed');
        try {
          final userCredential = await _auth.signInWithCredential(credential);
          final idToken = await userCredential.user?.getIdToken();
          if (idToken != null) {
            if (!completer.isCompleted) {
              completer.complete(FirebasePhoneAuthResult(
                status: FirebasePhoneAuthStatus.autoVerified,
                idToken: idToken,
              ));
            }
          }
        } catch (e) {
          Logger.error('[FirebasePhoneAuth] Auto-verify sign-in failed: $e');
          if (!completer.isCompleted) {
            completer.complete(FirebasePhoneAuthResult(
              status: FirebasePhoneAuthStatus.error,
              errorMessage: _mapFirebaseError(e),
            ));
          }
        }
      },

      verificationFailed: (FirebaseAuthException e) {
        Logger.error('[FirebasePhoneAuth] Verification failed: ${e.code} - ${e.message}');
        if (!completer.isCompleted) {
          completer.complete(FirebasePhoneAuthResult(
            status: FirebasePhoneAuthStatus.error,
            errorMessage: _mapFirebaseError(e),
          ));
        }
      },

      codeSent: (String verificationId, int? resendToken) {
        Logger.info('[FirebasePhoneAuth] Code sent, verificationId: ${verificationId.substring(0, 10)}...');
        _verificationId = verificationId;
        _resendToken = resendToken;
        if (!completer.isCompleted) {
          completer.complete(FirebasePhoneAuthResult(
            status: FirebasePhoneAuthStatus.codeSent,
            verificationId: verificationId,
            resendToken: resendToken,
          ));
        }
      },

      codeAutoRetrievalTimeout: (String verificationId) {
        Logger.info('[FirebasePhoneAuth] Auto-retrieval timeout');
        _verificationId = verificationId;
        // Don't complete here — codeSent already completed it
      },
    );

    return completer.future;
  }

  /// Verify SMS code entered by user and get Firebase ID token
  Future<String> signInWithSmsCode(String verificationId, String smsCode) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );

    final userCredential = await _auth.signInWithCredential(credential);
    final idToken = await userCredential.user?.getIdToken();

    if (idToken == null) {
      throw Exception('Failed to get Firebase ID token');
    }

    return idToken;
  }

  /// Get current user's ID token (if signed in)
  Future<String?> getIdToken() async {
    return await _auth.currentUser?.getIdToken();
  }

  /// Sign out of Firebase
  /// We don't use Firebase sessions — only the backend JWT matters
  Future<void> signOut() async {
    try {
      await _auth.signOut();
      Logger.info('[FirebasePhoneAuth] Signed out of Firebase');
    } catch (e) {
      Logger.error('[FirebasePhoneAuth] Sign out error: $e');
    }
  }

  /// Reset state for new verification attempt
  void reset() {
    _verificationId = null;
    _resendToken = null;
  }

  /// Map Firebase error codes to user-friendly messages
  String _mapFirebaseError(dynamic error) {
    String code = '';
    if (error is FirebaseAuthException) {
      code = error.code;
    } else if (error is FirebaseException) {
      code = error.code;
    } else {
      return error.toString();
    }

    switch (code) {
      case 'invalid-phone-number':
        return 'Please enter a valid 10-digit mobile number';
      case 'too-many-requests':
        return 'Too many attempts. Please try again after some time';
      case 'invalid-verification-code':
        return 'Invalid OTP. Please check and try again';
      case 'session-expired':
      case 'code-expired':
        return 'OTP expired. Please request a new one';
      case 'network-request-failed':
        return 'Network error. Please check your connection';
      case 'quota-exceeded':
        return 'SMS limit reached. Please try again later';
      case 'user-disabled':
        return 'This account has been disabled';
      case 'operation-not-allowed':
        return 'Phone authentication is not enabled';
      case 'invalid-verification-id':
        return 'Verification session expired. Please request a new OTP';
      case 'missing-client-identifier':
        return 'App verification failed. Please update the app or try again';
      case 'app-not-authorized':
        return 'App not authorized for phone auth. Please contact support';
      case 'captcha-check-failed':
        return 'Verification check failed. Please try again';
      case 'web-context-cancelled':
        return 'Verification cancelled. Please try again';
      case 'invalid-credential':
        return 'Invalid OTP. Please check and try again';
      default:
        return 'Verification failed ($code). Please try again';
    }
  }
}

/// Result of a Firebase phone auth operation
class FirebasePhoneAuthResult {
  final FirebasePhoneAuthStatus status;
  final String? idToken;
  final String? verificationId;
  final int? resendToken;
  final String? errorMessage;

  FirebasePhoneAuthResult({
    required this.status,
    this.idToken,
    this.verificationId,
    this.resendToken,
    this.errorMessage,
  });
}

/// Status of Firebase phone auth operation
enum FirebasePhoneAuthStatus {
  codeSent,
  autoVerified,
  error,
}
