import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_darwin/local_auth_darwin.dart';
import 'app_logger.dart';
import 'snackbar_helper.dart';

/// Biometric Helper - Best Practice Biometric Authentication
/// Centralized biometric authentication with error handling

class BiometricHelper {
  // Private constructor to prevent instantiation
  BiometricHelper._();

  static final LocalAuthentication _localAuth = LocalAuthentication();

  // ==================== Biometric Availability ====================

  /// Check if device supports biometrics
  static Future<bool> isDeviceSupported() async {
    try {
      final isSupported = await _localAuth.isDeviceSupported();
      AppLogger.info('Biometric device support: $isSupported');
      return isSupported;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Check Biometric Device Support',
      );
      return false;
    }
  }

  /// Check if biometrics are available (enrolled)
  static Future<bool> canCheckBiometrics() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      AppLogger.info('Can check biometrics: $canCheck');
      return canCheck;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Can Check Biometrics',
      );
      return false;
    }
  }

  /// Check if biometrics are enrolled
  static Future<bool> isBiometricEnrolled() async {
    try {
      final availableBiometrics = await getAvailableBiometrics();
      final isEnrolled = availableBiometrics.isNotEmpty;
      AppLogger.info('Biometric enrolled: $isEnrolled');
      return isEnrolled;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Check Biometric Enrollment',
      );
      return false;
    }
  }

  /// Get available biometric types
  static Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      final availableBiometrics = await _localAuth.getAvailableBiometrics();
      AppLogger.info('Available biometrics: $availableBiometrics');
      return availableBiometrics;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Get Available Biometrics',
      );
      return [];
    }
  }

  // ==================== Authentication ====================

  /// Authenticate with biometrics
  static Future<bool> authenticate({
    BuildContext? context,
    String? reason,
    bool useErrorDialogs = true,
    bool stickyAuth = true,
    bool biometricOnly = false,
  }) async {
    try {
      // Check device support
      if (!await isDeviceSupported()) {
        AppLogger.warning('Biometric authentication not supported');
        if (context != null) {
          SnackbarHelper.showError(context, 'Biometric authentication not supported');
        }
        return false;
      }

      // Check if biometrics are available
      if (!await canCheckBiometrics()) {
        AppLogger.warning('Biometrics not available');
        if (context != null) {
          SnackbarHelper.showError(context, 'Please set up biometric authentication');
        }
        return false;
      }

      AppLogger.info('Starting biometric authentication');

      final authenticated = await _localAuth.authenticate(
        localizedReason: reason ?? 'Authenticate to continue',
        options: AuthenticationOptions(
          useErrorDialogs: useErrorDialogs,
          stickyAuth: stickyAuth,
          biometricOnly: biometricOnly,
        ),
        authMessages: [
          const AndroidAuthMessages(
            signInTitle: 'Biometric Authentication',
            cancelButton: 'Cancel',
            biometricHint: '',
            biometricNotRecognized: 'Not recognized. Try again.',
            biometricSuccess: 'Success',
            deviceCredentialsRequiredTitle: 'Device credentials required',
            deviceCredentialsSetupDescription: 'Please set up biometric authentication',
          ),
          const IOSAuthMessages(
            cancelButton: 'Cancel',
            goToSettingsButton: 'Settings',
            goToSettingsDescription: 'Please set up biometric authentication',
            lockOut: 'Biometric authentication is disabled. Please lock and unlock your screen to enable it.',
          ),
        ],
      );

      if (authenticated) {
        AppLogger.info('Biometric authentication successful');
      } else {
        AppLogger.warning('Biometric authentication failed');
      }

      return authenticated;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Biometric Authentication',
      );

      if (context != null) {
        SnackbarHelper.showError(context, 'Authentication failed');
      }

      return false;
    }
  }

  /// Authenticate with custom messages
  static Future<bool> authenticateWithMessages({
    required BuildContext context,
    required String title,
    required String reason,
    String? cancelButton,
    bool biometricOnly = false,
  }) async {
    return await authenticate(
      context: context,
      reason: reason,
      biometricOnly: biometricOnly,
    );
  }

  // ==================== Predefined Authentication ====================

  /// Authenticate for login
  static Future<bool> authenticateForLogin(BuildContext context) async {
    return await authenticate(
      context: context,
      reason: 'Authenticate to log in',
      biometricOnly: false,
    );
  }

  /// Authenticate for payment
  static Future<bool> authenticateForPayment(BuildContext context) async {
    return await authenticate(
      context: context,
      reason: 'Authenticate to complete payment',
      biometricOnly: true,
      stickyAuth: true,
    );
  }

  /// Authenticate for sensitive data
  static Future<bool> authenticateForSensitiveData(BuildContext context) async {
    return await authenticate(
      context: context,
      reason: 'Authenticate to view sensitive information',
      biometricOnly: true,
    );
  }

  /// Authenticate for settings
  static Future<bool> authenticateForSettings(BuildContext context) async {
    return await authenticate(
      context: context,
      reason: 'Authenticate to change settings',
      biometricOnly: false,
    );
  }

  /// Authenticate for app unlock
  static Future<bool> authenticateForUnlock(BuildContext context) async {
    return await authenticate(
      context: context,
      reason: 'Unlock app with biometrics',
      biometricOnly: false,
      stickyAuth: true,
    );
  }

  // ==================== Biometric Info ====================

  /// Get biometric type string
  static Future<String> getBiometricTypeString() async {
    final biometrics = await getAvailableBiometrics();

    if (biometrics.isEmpty) {
      return 'None';
    }

    if (biometrics.contains(BiometricType.face)) {
      return 'Face ID';
    }

    if (biometrics.contains(BiometricType.fingerprint)) {
      return 'Fingerprint';
    }

    if (biometrics.contains(BiometricType.iris)) {
      return 'Iris';
    }

    if (biometrics.contains(BiometricType.strong)) {
      return 'Strong Biometric';
    }

    if (biometrics.contains(BiometricType.weak)) {
      return 'Weak Biometric';
    }

    return 'Biometric';
  }

  /// Get biometric icon
  static Future<IconData> getBiometricIcon() async {
    final biometrics = await getAvailableBiometrics();

    if (biometrics.isEmpty) {
      return Icons.lock;
    }

    if (biometrics.contains(BiometricType.face)) {
      return Icons.face;
    }

    if (biometrics.contains(BiometricType.fingerprint)) {
      return Icons.fingerprint;
    }

    return Icons.security;
  }

  // ==================== Helper Methods ====================

  /// Stop authentication
  static Future<void> stopAuthentication() async {
    try {
      await _localAuth.stopAuthentication();
      AppLogger.info('Biometric authentication stopped');
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Stop Biometric Authentication',
      );
    }
  }
}

/// Biometric Guard Widget - Protects content with biometric authentication
class BiometricGuard extends StatefulWidget {
  final Widget child;
  final String? reason;
  final VoidCallback? onAuthenticationFailed;
  final bool biometricOnly;

  const BiometricGuard({
    super.key,
    required this.child,
    this.reason,
    this.onAuthenticationFailed,
    this.biometricOnly = false,
  });

  @override
  State<BiometricGuard> createState() => _BiometricGuardState();
}

class _BiometricGuardState extends State<BiometricGuard> {
  bool _isAuthenticated = false;
  bool _isAuthenticating = false;

  @override
  void initState() {
    super.initState();
    _authenticate();
  }

  Future<void> _authenticate() async {
    if (_isAuthenticating) return;

    setState(() {
      _isAuthenticating = true;
    });

    final authenticated = await BiometricHelper.authenticate(
      context: context,
      reason: widget.reason ?? 'Authenticate to continue',
      biometricOnly: widget.biometricOnly,
    );

    setState(() {
      _isAuthenticated = authenticated;
      _isAuthenticating = false;
    });

    if (!authenticated) {
      widget.onAuthenticationFailed?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isAuthenticating) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (!_isAuthenticated) {
      final cs = Theme.of(context).colorScheme;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock,
              size: 64,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            const Text(
              'Authentication Required',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Please authenticate to view this content',
              style: TextStyle(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _authenticate,
              icon: const Icon(Icons.fingerprint),
              label: const Text('Authenticate'),
            ),
          ],
        ),
      );
    }

    return widget.child;
  }
}

/// Biometric Button - Button with biometric authentication
class BiometricButton extends StatelessWidget {
  final VoidCallback onAuthenticated;
  final String? reason;
  final String label;
  final IconData? icon;
  final bool biometricOnly;

  const BiometricButton({
    super.key,
    required this.onAuthenticated,
    this.reason,
    this.label = 'Authenticate',
    this.icon,
    this.biometricOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: () async {
        final authenticated = await BiometricHelper.authenticate(
          context: context,
          reason: reason ?? 'Authenticate to continue',
          biometricOnly: biometricOnly,
        );

        if (authenticated) {
          onAuthenticated();
        }
      },
      icon: Icon(icon ?? Icons.fingerprint),
      label: Text(label),
    );
  }
}
