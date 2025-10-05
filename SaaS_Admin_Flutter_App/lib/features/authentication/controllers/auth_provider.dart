import 'package:flutter/foundation.dart';
import '../../../core/services/auth_service.dart';

enum AuthState {
  initial,
  loading,
  authenticated,
  unauthenticated,
  error,
}

class AuthProvider with ChangeNotifier {
  final AuthService _authService = AuthService();

  AuthState _authState = AuthState.initial;
  String? _errorMessage;
  Map<String, dynamic>? _userData;
  bool _biometricEnabled = false;
  String? _phoneNumber;

  // Getters
  AuthState get authState => _authState;
  String? get errorMessage => _errorMessage;
  Map<String, dynamic>? get userData => _userData;
  bool get biometricEnabled => _biometricEnabled;
  String? get phoneNumber => _phoneNumber;

  bool get isAuthenticated => _authState == AuthState.authenticated;
  bool get isLoading => _authState == AuthState.loading;
  bool get hasError => _authState == AuthState.error;

  // Initialize authentication state
  Future<void> initialize() async {
    _setAuthState(AuthState.loading);

    try {
      // Add timeout to prevent hanging
      final isAuth = await _authService.isAuthenticated().timeout(
            const Duration(seconds: 3),
            onTimeout: () => false,
          );

      if (isAuth) {
        // Load user data with timeout
        try {
          _userData = await _authService.getUserData().timeout(
                const Duration(seconds: 2),
                onTimeout: () => null,
              );
          _phoneNumber = await _authService.getStoredPhoneNumber().timeout(
                const Duration(seconds: 2),
                onTimeout: () => null,
              );
          _biometricEnabled = await _authService.isBiometricEnabled().timeout(
                const Duration(seconds: 2),
                onTimeout: () => false,
              );
        } catch (e) {
          debugPrint('Warning: Failed to load user data: $e');
        }

        _setAuthState(AuthState.authenticated);
      } else {
        _setAuthState(AuthState.unauthenticated);
      }
    } catch (e) {
      debugPrint('Auth initialization failed: $e');
      // If initialization fails, assume unauthenticated to allow app to continue
      _setAuthState(AuthState.unauthenticated);
    }
  }

  // Check if user is admin
  Future<bool> checkIsAdmin(String phoneNumber) async {
    _setAuthState(AuthState.loading);

    try {
      final response = await _authService.isAdmin(phoneNumber);

      if (response.isSuccess && response.data == true) {
        _phoneNumber = phoneNumber;
        notifyListeners();
        return true;
      } else {
        _setError(response.error ?? 'You are not authorized as SaaS admin');
        return false;
      }
    } catch (e) {
      _setError('Failed to verify admin status: ${e.toString()}');
      return false;
    }
  }

  // Send OTP
  Future<bool> sendOTP(String phoneNumber) async {
    _setAuthState(AuthState.loading);

    try {
      final response = await _authService.sendOTP(phoneNumber);

      if (response.isSuccess) {
        _phoneNumber = phoneNumber;
        _setAuthState(AuthState.unauthenticated);
        return true;
      } else {
        _setError(response.error ?? 'Failed to send OTP');
        return false;
      }
    } catch (e) {
      _setError('Failed to send OTP: ${e.toString()}');
      return false;
    }
  }

  // Verify OTP and login
  Future<bool> verifyOTP(String phoneNumber, String otp) async {
    _setAuthState(AuthState.loading);

    try {
      final response = await _authService.verifyOTP(phoneNumber, otp);

      if (response.isSuccess && response.data != null) {
        _userData = response.data!['user'];
        _phoneNumber = phoneNumber;
        _setAuthState(AuthState.authenticated);
        return true;
      } else {
        _setError(response.error ?? 'Invalid OTP');
        return false;
      }
    } catch (e) {
      _setError('Failed to verify OTP: ${e.toString()}');
      return false;
    }
  }

  // Biometric authentication
  Future<bool> authenticateWithBiometric() async {
    try {
      final isAvailable = await _authService.isBiometricAvailable();
      if (!isAvailable) {
        _setError('Biometric authentication is not available');
        return false;
      }

      final authenticated = await _authService.authenticateWithBiometric();
      if (authenticated) {
        // Load user data
        _userData = await _authService.getUserData();
        _phoneNumber = await _authService.getStoredPhoneNumber();
        _setAuthState(AuthState.authenticated);
        return true;
      } else {
        _setError('Biometric authentication failed');
        return false;
      }
    } catch (e) {
      _setError('Biometric authentication error: ${e.toString()}');
      return false;
    }
  }

  // Enable/disable biometric authentication
  Future<void> setBiometricEnabled(bool enabled) async {
    try {
      await _authService.setBiometricEnabled(enabled);
      _biometricEnabled = enabled;
      notifyListeners();
    } catch (e) {
      _setError('Failed to update biometric settings: ${e.toString()}');
    }
  }

  // Check biometric availability
  Future<bool> checkBiometricAvailability() async {
    try {
      final isAvailable = await _authService.isBiometricAvailable();
      return isAvailable;
    } catch (e) {
      return false;
    }
  }

  // Logout
  Future<void> logout() async {
    try {
      await _authService.logout();
      _userData = null;
      _phoneNumber = null;
      _biometricEnabled = false;
      _errorMessage = null;
      _setAuthState(AuthState.unauthenticated);
    } catch (e) {
      _setError('Failed to logout: ${e.toString()}');
    }
  }

  // Clear error
  void clearError() {
    _errorMessage = null;
    if (_authState == AuthState.error) {
      _setAuthState(AuthState.unauthenticated);
    }
  }

  // Update user data
  void updateUserData(Map<String, dynamic> userData) {
    _userData = userData;
    notifyListeners();
  }

  // Private methods
  void _setAuthState(AuthState state) {
    _authState = state;
    notifyListeners();
  }

  void _setError(String error) {
    _errorMessage = error;
    _authState = AuthState.error;
    notifyListeners();
  }

  // Session validation
  Future<bool> validateSession() async {
    try {
      final isValid = await _authService.validateSession();
      if (!isValid) {
        await logout();
      }
      return isValid;
    } catch (e) {
      await logout();
      return false;
    }
  }

  // Auto-logout timer
  void startAutoLogout({Duration duration = const Duration(hours: 8)}) {
    _authService.startAutoLogoutTimer(duration);
  }
}
