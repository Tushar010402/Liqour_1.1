import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:crypto/crypto.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../constants/app_constants.dart';
import '../utils/logger.dart';
import '../api/api_client.dart';
import '../api/api_exceptions.dart';
import '../models/user_model.dart';
import '../models/auth_models.dart';

/// Comprehensive authentication service with biometric support
class AuthService {
  static AuthService? _instance;
  static AuthService get instance => _instance ??= AuthService._internal();
  
  AuthService._internal();
  
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final LocalAuthentication _localAuth = LocalAuthentication();
  final ApiClient _apiClient = ApiClient.instance;
  
  // Stream controllers for auth state
  final StreamController<AuthState> _authStateController = StreamController<AuthState>.broadcast();
  final StreamController<UserModel?> _userController = StreamController<UserModel?>.broadcast();
  
  // Current state
  AuthState _currentAuthState = AuthState.initial;
  UserModel? _currentUser;
  Timer? _tokenRefreshTimer;
  Timer? _sessionTimer;
  
  // Getters
  Stream<AuthState> get authStateStream => _authStateController.stream;
  Stream<UserModel?> get userStream => _userController.stream;
  AuthState get authState => _currentAuthState;
  UserModel? get currentUser => _currentUser;
  bool get isAuthenticated => _currentAuthState == AuthState.authenticated;
  bool get isLoading => _currentAuthState == AuthState.loading;
  
  /// Initialize authentication service
  Future<void> initialize() async {
    try {
      AppLogger.info('🔐 Initializing AuthService...');
      
      // Check if user has valid stored session
      await _checkStoredAuthentication();
      
      // Setup session monitoring
      _setupSessionMonitoring();
      
      AppLogger.info('✅ AuthService initialized successfully');
      
    } catch (error, stackTrace) {
      AppLogger.error('❌ AuthService initialization failed', error, stackTrace);
      _updateAuthState(AuthState.unauthenticated);
    }
  }
  
  /// Check stored authentication credentials
  Future<void> _checkStoredAuthentication() async {
    try {
      final token = await _secureStorage.read(key: AppConstants.authTokenKey);
      final userDataJson = await _secureStorage.read(key: AppConstants.userDataKey);
      
      if (token != null && userDataJson != null) {
        // Validate token
        if (!_isTokenExpired(token)) {
          final userData = json.decode(userDataJson);
          _currentUser = UserModel.fromJson(userData);
          _updateAuthState(AuthState.authenticated);
          
          // Setup automatic token refresh
          _scheduleTokenRefresh(token);
          
          AppLogger.info('🔓 User authenticated from stored credentials');
          return;
        } else {
          AppLogger.info('🔒 Stored token expired, attempting refresh...');
          await _refreshToken();
          return;
        }
      }
      
      _updateAuthState(AuthState.unauthenticated);
      
    } catch (error) {
      AppLogger.warning('Failed to check stored authentication', error);
      await _clearAuthData();
      _updateAuthState(AuthState.unauthenticated);
    }
  }
  
  /// Authenticate with email and password
  Future<AuthResult> signInWithEmail({
    required String email,
    required String password,
    bool rememberMe = false,
  }) async {
    try {
      _updateAuthState(AuthState.loading);
      AppLogger.info('🔐 Attempting email authentication for: $email');
      
      // Validate network connectivity
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity == ConnectivityResult.none) {
        throw NetworkException('No internet connection');
      }
      
      // Prepare request data
      final requestData = {
        'email': email.toLowerCase().trim(),
        'password': password,
        'device_info': await _getDeviceInfo(),
        'remember_me': rememberMe,
      };
      
      // Make API call
      final response = await _apiClient.post('/api/auth/login', data: requestData);
      
      if (response.statusCode == 200) {
        final responseData = response.data;
        
        // Extract authentication data
        final token = responseData['access_token'];
        final refreshToken = responseData['refresh_token'];
        final userData = responseData['user'];
        
        // Store authentication data
        await _storeAuthData(token, refreshToken, userData);
        
        // Update current user
        _currentUser = UserModel.fromJson(userData);
        _updateAuthState(AuthState.authenticated);
        
        // Setup session monitoring
        _scheduleTokenRefresh(token);
        _setupSessionTimer();
        
        // Log successful authentication
        AppLogger.security('User authenticated successfully', {
          'user_id': _currentUser?.id,
          'email': _currentUser?.email,
          'method': 'email_password',
        });
        
        return AuthResult.success('Authentication successful');
      }
      
      _updateAuthState(AuthState.unauthenticated);
      return AuthResult.failure('Authentication failed');
      
    } on ApiException catch (error) {
      AppLogger.error('Authentication API error', error);
      _updateAuthState(AuthState.unauthenticated);
      
      if (error is UnauthorizedException) {
        return AuthResult.failure('Invalid email or password');
      } else if (error is ValidationException) {
        return AuthResult.failure(error.getAllErrors().join(', '));
      } else if (error is NetworkException || error is TimeoutException) {
        return AuthResult.failure('Network error. Please check your connection.');
      }
      
      return AuthResult.failure(error.userMessage);
      
    } catch (error, stackTrace) {
      AppLogger.error('Unexpected authentication error', error, stackTrace);
      _updateAuthState(AuthState.unauthenticated);
      return AuthResult.failure('An unexpected error occurred. Please try again.');
    }
  }
  
  /// Authenticate with biometric
  Future<AuthResult> signInWithBiometric() async {
    try {
      _updateAuthState(AuthState.loading);
      AppLogger.info('🔐 Attempting biometric authentication');
      
      // Check if biometric auth is available and enrolled
      final isAvailable = await _localAuth.isDeviceSupported();
      if (!isAvailable) {
        _updateAuthState(AuthState.unauthenticated);
        return AuthResult.failure('Biometric authentication is not available on this device');
      }
      
      final isEnrolled = await _localAuth.canCheckBiometrics;
      if (!isEnrolled) {
        _updateAuthState(AuthState.unauthenticated);
        return AuthResult.failure('No biometric credentials enrolled. Please enroll fingerprint or face ID');
      }
      
      // Check if user has biometric auth enabled
      final biometricEnabled = await _secureStorage.read(key: AppConstants.biometricEnabledKey);
      if (biometricEnabled != 'true') {
        _updateAuthState(AuthState.unauthenticated);
        return AuthResult.failure('Biometric authentication is not enabled for this account');
      }
      
      // Get stored encrypted credentials
      final encryptedCredentials = await _secureStorage.read(key: AppConstants.biometricCredentialsKey);
      if (encryptedCredentials == null) {
        _updateAuthState(AuthState.unauthenticated);
        return AuthResult.failure('No biometric credentials stored');
      }
      
      // Perform biometric authentication
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Authenticate to access LiquorPro',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          sensitiveTransaction: true,
        ),
      );
      
      if (!authenticated) {
        _updateAuthState(AuthState.unauthenticated);
        return AuthResult.failure('Biometric authentication failed');
      }
      
      // Decrypt and use stored credentials
      final credentials = _decryptCredentials(encryptedCredentials);
      if (credentials != null) {
        return await signInWithEmail(
          email: credentials['email']!,
          password: credentials['password']!,
          rememberMe: true,
        );
      }
      
      _updateAuthState(AuthState.unauthenticated);
      return AuthResult.failure('Failed to decrypt stored credentials');
      
    } on PlatformException catch (error) {
      AppLogger.error('Biometric authentication platform error', error);
      _updateAuthState(AuthState.unauthenticated);
      
      switch (error.code) {
        case 'NotAvailable':
          return AuthResult.failure('Biometric authentication is not available');
        case 'NotEnrolled':
          return AuthResult.failure('No biometric credentials enrolled');
        case 'PasscodeNotSet':
          return AuthResult.failure('Please set up device passcode first');
        case 'BiometricOnly':
          return AuthResult.failure('Biometric authentication required');
        default:
          return AuthResult.failure('Biometric authentication failed: ${error.message}');
      }
      
    } catch (error, stackTrace) {
      AppLogger.error('Unexpected biometric authentication error', error, stackTrace);
      _updateAuthState(AuthState.unauthenticated);
      return AuthResult.failure('Biometric authentication failed');
    }
  }
  
  /// Register new user account
  Future<AuthResult> signUp({
    required String email,
    required String password,
    required String confirmPassword,
    required String firstName,
    required String lastName,
    String? phoneNumber,
    String? businessName,
  }) async {
    try {
      _updateAuthState(AuthState.loading);
      AppLogger.info('📝 Attempting user registration for: $email');
      
      // Validate passwords match
      if (password != confirmPassword) {
        _updateAuthState(AuthState.unauthenticated);
        return AuthResult.failure('Passwords do not match');
      }
      
      // Validate network connectivity
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity == ConnectivityResult.none) {
        throw NetworkException('No internet connection');
      }
      
      // Prepare request data
      final requestData = {
        'email': email.toLowerCase().trim(),
        'password': password,
        'password_confirmation': confirmPassword,
        'first_name': firstName.trim(),
        'last_name': lastName.trim(),
        'phone_number': phoneNumber?.trim(),
        'business_name': businessName?.trim(),
        'device_info': await _getDeviceInfo(),
      };
      
      // Make API call
      final response = await _apiClient.post('/api/auth/register', data: requestData);
      
      if (response.statusCode == 201) {
        _updateAuthState(AuthState.unauthenticated);
        
        AppLogger.info('✅ User registration successful');
        return AuthResult.success('Registration successful! Please check your email for verification.');
      }
      
      _updateAuthState(AuthState.unauthenticated);
      return AuthResult.failure('Registration failed');
      
    } on ApiException catch (error) {
      AppLogger.error('Registration API error', error);
      _updateAuthState(AuthState.unauthenticated);
      
      if (error is ValidationException) {
        return AuthResult.failure(error.getAllErrors().join(', '));
      } else if (error is BadRequestException) {
        return AuthResult.failure('Email address is already registered');
      } else if (error is NetworkException || error is TimeoutException) {
        return AuthResult.failure('Network error. Please check your connection.');
      }
      
      return AuthResult.failure(error.userMessage);
      
    } catch (error, stackTrace) {
      AppLogger.error('Unexpected registration error', error, stackTrace);
      _updateAuthState(AuthState.unauthenticated);
      return AuthResult.failure('Registration failed. Please try again.');
    }
  }
  
  /// Enable biometric authentication
  Future<AuthResult> enableBiometricAuth(String password) async {
    try {
      AppLogger.info('🔐 Enabling biometric authentication');
      
      if (!isAuthenticated || _currentUser == null) {
        return AuthResult.failure('User must be authenticated to enable biometric auth');
      }
      
      // Verify current password
      final verifyResult = await _verifyPassword(password);
      if (!verifyResult) {
        return AuthResult.failure('Invalid password. Please try again.');
      }
      
      // Check biometric availability
      final isAvailable = await _localAuth.isDeviceSupported();
      final canCheckBiometrics = await _localAuth.canCheckBiometrics;
      
      if (!isAvailable || !canCheckBiometrics) {
        return AuthResult.failure('Biometric authentication is not available on this device');
      }
      
      // Get available biometric types
      final availableBiometrics = await _localAuth.getAvailableBiometrics();
      if (availableBiometrics.isEmpty) {
        return AuthResult.failure('No biometric methods are enrolled on this device');
      }
      
      // Test biometric authentication
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Set up biometric authentication for LiquorPro',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      
      if (!authenticated) {
        return AuthResult.failure('Biometric authentication setup cancelled');
      }
      
      // Encrypt and store credentials
      final encryptedCredentials = _encryptCredentials(_currentUser!.email, password);
      await _secureStorage.write(key: AppConstants.biometricCredentialsKey, value: encryptedCredentials);
      await _secureStorage.write(key: AppConstants.biometricEnabledKey, value: 'true');
      
      AppLogger.security('Biometric authentication enabled', {'user_id': _currentUser?.id});
      return AuthResult.success('Biometric authentication enabled successfully');
      
    } catch (error, stackTrace) {
      AppLogger.error('Failed to enable biometric authentication', error, stackTrace);
      return AuthResult.failure('Failed to enable biometric authentication');
    }
  }
  
  /// Disable biometric authentication
  Future<AuthResult> disableBiometricAuth() async {
    try {
      await _secureStorage.delete(key: AppConstants.biometricCredentialsKey);
      await _secureStorage.write(key: AppConstants.biometricEnabledKey, value: 'false');
      
      AppLogger.security('Biometric authentication disabled', {'user_id': _currentUser?.id});
      return AuthResult.success('Biometric authentication disabled');
      
    } catch (error) {
      AppLogger.error('Failed to disable biometric authentication', error);
      return AuthResult.failure('Failed to disable biometric authentication');
    }
  }
  
  /// Sign out user
  Future<void> signOut() async {
    try {
      AppLogger.info('🚪 Signing out user');
      
      // Notify backend about logout
      if (isAuthenticated) {
        try {
          await _apiClient.post('/api/auth/logout');
        } catch (error) {
          AppLogger.warning('Backend logout failed', error);
        }
      }
      
      // Clear all auth data
      await _clearAuthData();
      
      // Cancel timers
      _tokenRefreshTimer?.cancel();
      _sessionTimer?.cancel();
      
      // Update state
      _currentUser = null;
      _updateAuthState(AuthState.unauthenticated);
      
      AppLogger.security('User signed out', {'timestamp': DateTime.now().toIso8601String()});
      
    } catch (error, stackTrace) {
      AppLogger.error('Sign out error', error, stackTrace);
      // Still clear local data even if backend call fails
      await _clearAuthData();
      _currentUser = null;
      _updateAuthState(AuthState.unauthenticated);
    }
  }
  
  /// Refresh authentication token
  Future<bool> _refreshToken() async {
    try {
      final refreshToken = await _secureStorage.read(key: AppConstants.refreshTokenKey);
      if (refreshToken == null) {
        throw AuthenticationException('No refresh token available', AuthErrorType.tokenInvalid);
      }
      
      final response = await _apiClient.post('/api/auth/refresh', data: {
        'refresh_token': refreshToken,
        'device_info': await _getDeviceInfo(),
      });
      
      if (response.statusCode == 200) {
        final responseData = response.data;
        final newToken = responseData['access_token'];
        final newRefreshToken = responseData['refresh_token'];
        
        await _secureStorage.write(key: AppConstants.authTokenKey, value: newToken);
        await _secureStorage.write(key: AppConstants.refreshTokenKey, value: newRefreshToken);
        
        _scheduleTokenRefresh(newToken);
        
        AppLogger.info('🔄 Token refreshed successfully');
        return true;
      }
      
      return false;
      
    } catch (error) {
      AppLogger.error('Token refresh failed', error);
      await _clearAuthData();
      _updateAuthState(AuthState.unauthenticated);
      return false;
    }
  }
  
  /// Verify password
  Future<bool> _verifyPassword(String password) async {
    try {
      final response = await _apiClient.post('/api/auth/verify-password', data: {
        'password': password,
      });
      
      return response.statusCode == 200;
    } catch (error) {
      AppLogger.error('Password verification failed', error);
      return false;
    }
  }
  
  /// Store authentication data securely
  Future<void> _storeAuthData(String token, String refreshToken, Map<String, dynamic> userData) async {
    await Future.wait([
      _secureStorage.write(key: AppConstants.authTokenKey, value: token),
      _secureStorage.write(key: AppConstants.refreshTokenKey, value: refreshToken),
      _secureStorage.write(key: AppConstants.userDataKey, value: json.encode(userData)),
    ]);
  }
  
  /// Clear all authentication data
  Future<void> _clearAuthData() async {
    await Future.wait([
      _secureStorage.delete(key: AppConstants.authTokenKey),
      _secureStorage.delete(key: AppConstants.refreshTokenKey),
      _secureStorage.delete(key: AppConstants.userDataKey),
      _secureStorage.delete(key: AppConstants.tenantDataKey),
    ]);
  }
  
  /// Update authentication state
  void _updateAuthState(AuthState newState) {
    _currentAuthState = newState;
    _authStateController.add(newState);
    _userController.add(_currentUser);
  }
  
  /// Check if token is expired
  bool _isTokenExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;
      
      final payload = json.decode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final exp = payload['exp'] as int?;
      
      if (exp == null) return true;
      
      final expiryTime = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
      return DateTime.now().isAfter(expiryTime.subtract(const Duration(minutes: 5))); // 5 minute buffer
      
    } catch (error) {
      AppLogger.warning('Failed to parse token expiry', error);
      return true;
    }
  }
  
  /// Schedule token refresh
  void _scheduleTokenRefresh(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return;
      
      final payload = json.decode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final exp = payload['exp'] as int?;
      
      if (exp != null) {
        final expiryTime = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
        final refreshTime = expiryTime.subtract(const Duration(minutes: 10));
        final now = DateTime.now();
        
        if (refreshTime.isAfter(now)) {
          _tokenRefreshTimer?.cancel();
          _tokenRefreshTimer = Timer(refreshTime.difference(now), () {
            _refreshToken();
          });
        }
      }
    } catch (error) {
      AppLogger.warning('Failed to schedule token refresh', error);
    }
  }
  
  /// Setup session monitoring
  void _setupSessionMonitoring() {
    _sessionTimer?.cancel();
    _sessionTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      if (isAuthenticated) {
        _checkTokenValidity();
      }
    });
  }
  
  /// Setup session timer for automatic logout
  void _setupSessionTimer() {
    _sessionTimer?.cancel();
    _sessionTimer = Timer(const Duration(hours: 8), () {
      AppLogger.info('Session timeout reached, signing out user');
      signOut();
    });
  }
  
  /// Check token validity
  Future<void> _checkTokenValidity() async {
    try {
      final token = await _secureStorage.read(key: AppConstants.authTokenKey);
      if (token == null || _isTokenExpired(token)) {
        final refreshed = await _refreshToken();
        if (!refreshed) {
          await signOut();
        }
      }
    } catch (error) {
      AppLogger.error('Token validity check failed', error);
    }
  }
  
  /// Get device information
  Future<Map<String, dynamic>> _getDeviceInfo() async {
    return {
      'platform': defaultTargetPlatform.name,
      'app_version': AppConstants.appVersion,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
  
  /// Encrypt credentials for biometric storage
  String _encryptCredentials(String email, String password) {
    final credentials = json.encode({'email': email, 'password': password});
    final bytes = utf8.encode(credentials);
    final digest = sha256.convert(bytes);
    return base64Url.encode(digest.bytes);
  }
  
  /// Decrypt credentials from biometric storage
  Map<String, String>? _decryptCredentials(String encryptedCredentials) {
    try {
      final bytes = base64Url.decode(encryptedCredentials);
      final decrypted = utf8.decode(bytes);
      final credentials = json.decode(decrypted) as Map<String, dynamic>;
      return credentials.cast<String, String>();
    } catch (error) {
      AppLogger.error('Failed to decrypt credentials', error);
      return null;
    }
  }
  
  /// Dispose resources
  void dispose() {
    _tokenRefreshTimer?.cancel();
    _sessionTimer?.cancel();
    _authStateController.close();
    _userController.close();
  }
}

/// Authentication states
enum AuthState {
  initial,
  loading,
  authenticated,
  unauthenticated,
  error,
}

/// Authentication result wrapper
class AuthResult {
  final bool success;
  final String message;
  final dynamic data;
  
  const AuthResult._(this.success, this.message, [this.data]);
  
  factory AuthResult.success(String message, [dynamic data]) =>
      AuthResult._(true, message, data);
      
  factory AuthResult.failure(String message) =>
      AuthResult._(false, message);
}