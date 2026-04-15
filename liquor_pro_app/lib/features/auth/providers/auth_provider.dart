import 'package:flutter/foundation.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../../../core/services/dio_api_service.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/device_info_service.dart';
import '../../../core/config/api_config.dart';
import '../../../core/config/environment_config.dart';
import '../../../core/utils/jwt_utils.dart';
import '../../../core/utils/logger.dart';
import '../../../core/utils/safe_casting.dart';
import '../../../core/services/analytics_service.dart';
import 'package:clarity_flutter/clarity_flutter.dart';
import '../models/user_model.dart';
import '../models/otp_models.dart';
import '../models/device_session_models.dart';

/// Authentication Provider
class AuthProvider extends ChangeNotifier {
  final DioApiService _apiService;
  final AuthService _authService;

  UserModel? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;

  AuthProvider({
    required DioApiService apiService,
    required AuthService authService,
  })  : _apiService = apiService,
        _authService = authService;

  /// Set Crashlytics user context for crash triage
  void _setCrashlyticsUserContext(String userId, String role, String? tenantId) {
    if (!EnvironmentConfig.enableCrashReporting) return;
    try {
      final crashlytics = FirebaseCrashlytics.instance;
      crashlytics.setUserIdentifier(userId);
      crashlytics.setCustomKey('user_role', role);
      crashlytics.setCustomKey('tenant_id', tenantId ?? 'none');
    } catch (_) {}
  }

  /// Force-clear user state when session expires (called from DioApiService).
  /// Unlike [logout], this skips the network call since the session is already invalid.
  void clearSessionState() {
    _currentUser = null;
    notifyListeners();
  }

  // Getters
  UserModel? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _currentUser != null;

  // Set loading state (don't notify listeners to avoid unmounting during async ops)
  void _setLoading(bool value) {
    _isLoading = value;
    // DON'T call notifyListeners() here - it causes navigation issues
  }

  // Set error message (don't notify listeners to avoid unmounting during async ops)
  void _setError(String? message) {
    _errorMessage = message;
    // DON'T call notifyListeners() here - it causes navigation issues
  }

  // Login
  Future<bool> login({
    required String email,
    required String password,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final request = LoginRequest(email: email, password: password);

      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConfig.login,
        body: request.toJson(),
        fromJson: (data) => SafeCast.toMap<String, dynamic>(data),
      );

      if (response.isSuccess && response.data != null) {
        final loginResponse = LoginResponse.fromJson(response.data!);

        // Save auth data
        await _authService.saveAuthData(
          token: loginResponse.token,
          refreshToken: loginResponse.refreshToken,
          userId: loginResponse.user.id,
          tenantId: loginResponse.user.tenantId,
          userName: loginResponse.user.displayName,
          email: loginResponse.user.email,
          role: loginResponse.user.role,
        );

        // CRITICAL FIX: Wait for secure storage to fully persist
        // This prevents race conditions where subsequent API calls
        // try to read the token before it's fully written to disk
        await Future.delayed(const Duration(milliseconds: 300));

        // ✅ CRITICAL: Force refresh DioApiService token cache
        await _apiService.forceRefreshToken();

        Logger.info('[AuthProvider] Login complete - Token saved and cache refreshed');

        _currentUser = loginResponse.user;

        // Wire analytics user context
        AnalyticsService.setUserId(loginResponse.user.id);
        AnalyticsService.setUserProperties({
          'role': loginResponse.user.role,
          'tenant_id': loginResponse.user.tenantId ?? 'none',
        });
        AnalyticsService.trackLogin(method: 'email');
        _setCrashlyticsUserContext(
          loginResponse.user.id,
          loginResponse.user.role,
          loginResponse.user.tenantId,
        );
        if (!kDebugMode) {
          Clarity.setCustomUserId(loginResponse.user.id);
        }

        _setLoading(false);
        return true;
      } else {
        _setError(response.message ?? 'Login failed');
        _setLoading(false);
        return false;
      }
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      return false;
    }
  }

  // Load current user
  Future<void> loadCurrentUser() async {
    try {
      if (kDebugMode) {
        Logger.debug('[AuthProvider] loadCurrentUser called');
      }

      final isAuth = await _authService.isAuthenticated();
      if (!isAuth) {
        if (kDebugMode) {
          Logger.warning('[AuthProvider] Not authenticated - clearing user');
        }
        _currentUser = null;
        notifyListeners();
        return;
      }

      // Check if token is expired
      final token = await _authService.getToken();
      if (token != null && JwtUtils.isTokenExpired(token)) {
        if (kDebugMode) {
          Logger.warning('[AuthProvider] Token expired during loadCurrentUser - logging out');
        }
        await logout();
        return;
      }

      final userId = await _authService.getUserId();
      final tenantId = await _authService.getTenantId();
      final userName = await _authService.getUserName();
      final userEmail = await _authService.getUserEmail();
      final userRole = await _authService.getUserRole();
      final userPhone = await _authService.getUserPhone();

      if (userId != null &&
          userName != null &&
          userEmail != null &&
          userRole != null) {
        // Parse name into first and last
        final nameParts = userName.split(' ');
        final firstName = nameParts.isNotEmpty ? nameParts[0] : '';
        final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';

        _currentUser = UserModel(
          id: userId,
          username: userEmail.split('@')[0], // Generate username from email
          email: userEmail,
          firstName: firstName,
          lastName: lastName,
          role: userRole,
          tenantId: tenantId,
          phone: userPhone,
        );

        // Re-set monitoring context on session restore
        AnalyticsService.setUserId(userId);
        _setCrashlyticsUserContext(userId, userRole, tenantId);

        notifyListeners();
      } else {
        // Missing required user data - clear auth state
        if (kDebugMode) {
          Logger.warning('[AuthProvider] Incomplete user data - clearing auth state');
        }
        _currentUser = null;
        notifyListeners();
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        Logger.error('[AuthProvider] Error loading current user: $e');
        Logger.error('Stack trace: $stackTrace');
      }
      // On error, clear user state but don't crash the app
      _currentUser = null;
      notifyListeners();
      rethrow; // Re-throw to let SplashScreen handle it
    }
  }

  // Logout
  Future<void> logout() async {
    if (kDebugMode) {
      Logger.info('[AuthProvider] LOGOUT CALLED');
      Logger.debug('   Stack trace: ${StackTrace.current}');
    }

    // WebSocket is lazy-loaded only when OCR is needed, so no need to disconnect here
    // Attempting to create WebSocketService() when it's not initialized can cause crashes
    // The WebSocket will be garbage collected if it was ever created

    try {
      await _authService.logout();
    } catch (e) {
      if (kDebugMode) {
        Logger.error('[AuthProvider] Error during logout: $e');
      }
    }

    // Clear DioApiService in-memory token cache immediately
    _apiService.resetSessionExpired();
    _apiService.clearHttpCache();

    _currentUser = null;
    _currentSessionId = null;
    AnalyticsService.trackLogout();

    // Add a small delay before notifyListeners to allow any pending navigation to complete
    // This prevents navigation race conditions when logout is triggered during session expiration
    await Future.delayed(const Duration(milliseconds: 100));

    if (kDebugMode) {
      Logger.debug('[AuthProvider] Calling notifyListeners after logout');
    }
    notifyListeners();
  }

  /// @Deprecated - WebSocket connection is now lazy-loaded only when needed for OCR
  /// This method is no longer needed as WebSocket will be initialized on-demand
  /// when the user accesses OCR functionality, improving app startup performance
  /// and reducing unnecessary network connections
  Future<void> connectRealTimeUpdates() async {
    // Method deprecated - WebSocket is now connected lazily when OCR is needed
    // No-op to maintain backward compatibility
    Logger.info('[AuthProvider] connectRealTimeUpdates is deprecated - WebSocket will connect lazily when OCR is used');
  }

  // Clear error
  void clearError() {
    _setError(null);
  }

  // ==================== FIREBASE PHONE AUTH ====================

  /// Verify Firebase ID token with backend
  /// Returns VerifyOtpResponse (same structure — login or registration)
  Future<VerifyOtpResponse?> verifyFirebaseToken({
    required String firebaseIdToken,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      // Get device info for device management
      final deviceInfo = await DeviceInfoService.getDeviceInfo();

      final requestBody = {
        'firebase_id_token': firebaseIdToken,
        ...deviceInfo.toJson(),
      };

      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConfig.verifyFirebaseToken,
        body: requestBody,
        fromJson: (data) => SafeCast.toMap<String, dynamic>(data),
      );

      // Handle 409 Conflict - Device Limit Reached
      if (response.statusCode == 409) {
        _setLoading(false);
        final errorData = response.data ?? {};
        final deviceLimitError = DeviceLimitError.fromJson(errorData);
        throw DeviceLimitException(deviceLimitError);
      }

      if (response.isSuccess && response.data != null) {
        Logger.debug('[AuthProvider] Firebase token verified: ${response.data}');
        final verifyResponse = VerifyOtpResponse.fromJson(response.data!);

        // If this is a login (has token and user), save auth data
        if (verifyResponse.isLogin) {
          final userData = verifyResponse.user!;
          final tenantData = verifyResponse.tenant;

          if (tenantData != null && tenantData['id'] != null) {
            userData['tenant_id'] = SafeCast.toStringValue(tenantData['id']);
            userData['tenant_name'] = SafeCast.toStringOrNull(tenantData['name']);
          }

          final user = UserModel.fromJson(userData);
          final phone = userData['phone'] as String? ?? '';

          await _authService.saveAuthData(
            token: verifyResponse.token!,
            refreshToken: verifyResponse.refreshToken,
            userId: user.id,
            tenantId: user.tenantId,
            userName: user.displayName,
            email: user.email,
            role: user.role,
            phone: phone,
          );

          if (verifyResponse.sessionId != null) {
            await _authService.saveSessionId(verifyResponse.sessionId!);
          }

          await Future.delayed(const Duration(milliseconds: 300));
          await _apiService.forceRefreshToken();

          Logger.info('[AuthProvider] Firebase auth complete - Token saved');

          _currentUser = user.copyWith(phone: phone);

          AnalyticsService.setUserId(user.id);
          AnalyticsService.setUserProperties({
            'role': user.role,
            'tenant_id': user.tenantId ?? 'none',
          });
          AnalyticsService.trackLogin(method: 'firebase_phone');
          _setCrashlyticsUserContext(user.id, user.role, user.tenantId);
          if (!kDebugMode) {
            Clarity.setCustomUserId(user.id);
          }
        }

        _setLoading(false);
        return verifyResponse;
      } else {
        _setError(response.message ?? 'Verification failed');
        _setLoading(false);
        return null;
      }
    } on DeviceLimitException {
      _setLoading(false);
      rethrow;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      return null;
    }
  }

  // ==================== OTP AUTHENTICATION (Legacy - Dr. Dang SMS) ====================

  /// Check if user exists by phone number
  Future<CheckUserResponse?> checkUser(String mobile) async {
    _setLoading(true);
    _setError(null);

    try {
      final request = CheckUserRequest(mobile: mobile);

      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConfig.checkUser,
        body: request.toJson(),
        fromJson: (data) => SafeCast.toMap<String, dynamic>(data),
      );

      _setLoading(false);

      if (kDebugMode) {
        Logger.debug('[AuthProvider] checkUser raw response:');
        Logger.debug('   isSuccess: ${response.isSuccess}');
        Logger.debug('   statusCode: ${response.statusCode}');
        Logger.debug('   data: ${response.data}');
        Logger.debug('   message: ${response.message}');
      }

      if (response.isSuccess && response.data != null) {
        return CheckUserResponse.fromJson(response.data!);
      } else {
        _setError(response.message ?? 'Failed to check user');
        return null;
      }
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      return null;
    }
  }

  /// Send OTP to existing user for login
  Future<SendOtpResponse?> sendOtp(String mobile) async {
    _setLoading(true);
    _setError(null);

    try {
      final request = SendOtpRequest(mobile: mobile);

      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConfig.sendOtp,
        body: request.toJson(),
        fromJson: (data) => SafeCast.toMap<String, dynamic>(data),
      );

      _setLoading(false);

      if (response.isSuccess && response.data != null) {
        return SendOtpResponse.fromJson(response.data!);
      } else {
        _setError(response.message ?? 'Failed to send OTP');
        return null;
      }
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      return null;
    }
  }

  /// Send OTP for new user registration
  Future<SendOtpResponse?> sendOtpForRegistration({
    required String phone,
    required String email,
    required String firstName,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final request = SendOtpForRegistrationRequest(
        phone: phone,
        email: email,
        firstName: firstName,
      );

      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConfig.sendOtpRegistration,
        body: request.toJson(),
        fromJson: (data) => SafeCast.toMap<String, dynamic>(data),
      );

      _setLoading(false);

      if (response.isSuccess && response.data != null) {
        return SendOtpResponse.fromJson(response.data!);
      } else {
        _setError(response.message ?? 'Failed to send OTP');
        return null;
      }
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      return null;
    }
  }

  /// Verify OTP and login/continue registration
  /// Includes device info for multi-device management (Swiggy/Zomato style)
  /// Throws DeviceLimitException if device limit (409) is reached
  Future<VerifyOtpResponse?> verifyOtp({
    required String mobile,
    required String otp,
    String? sessionId,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      // Get device info for device management
      final deviceInfo = await DeviceInfoService.getDeviceInfo();
      if (kDebugMode) {
        Logger.debug('[AuthProvider] Device info collected: ${deviceInfo.deviceName}');
      }

      final request = VerifyOtpRequest(
        mobile: mobile,
        otp: otp,
        sessionId: sessionId,
      );

      // Include device info in request body
      final requestBody = {
        ...request.toJson(),
        ...deviceInfo.toJson(),
      };

      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConfig.verifyOtp,
        body: requestBody,
        fromJson: (data) => SafeCast.toMap<String, dynamic>(data),
      );

      // Handle 409 Conflict - Device Limit Reached
      if (response.statusCode == 409) {
        if (kDebugMode) {
          Logger.warning('[AuthProvider] Device limit reached (409)');
          Logger.debug('[AuthProvider] 409 Response data: ${response.data}');
        }
        _setLoading(false);
        final errorData = response.data ?? {};
        if (kDebugMode) {
          Logger.debug('[AuthProvider] Error data type: ${errorData.runtimeType}');
          Logger.debug('[AuthProvider] Error data keys: ${errorData.keys}');
          if (errorData['active_sessions'] != null) {
            Logger.debug('[AuthProvider] active_sessions: ${errorData['active_sessions']}');
          }
          if (errorData['active_devices'] != null) {
            Logger.debug('[AuthProvider] active_devices: ${errorData['active_devices']}');
          }
        }
        final deviceLimitError = DeviceLimitError.fromJson(errorData);
        if (kDebugMode) {
          Logger.debug('[AuthProvider] Parsed DeviceLimitError:');
          Logger.debug('   - activeDevices count: ${deviceLimitError.activeDevices.length}');
          Logger.debug('   - maxDevices: ${deviceLimitError.maxDevices}');
          Logger.debug('   - message: ${deviceLimitError.message}');
        }
        throw DeviceLimitException(deviceLimitError);
      }

      if (response.isSuccess && response.data != null) {
        Logger.debug('[AuthProvider] Raw verify-otp response: ${response.data}');
        final verifyResponse = VerifyOtpResponse.fromJson(response.data!);
        Logger.debug('[AuthProvider] Parsed VerifyOtpResponse:');
        Logger.debug('  - token: ${verifyResponse.token != null ? "present" : "null"}');
        Logger.debug('  - user: ${verifyResponse.user != null ? "present" : "null"}');
        Logger.debug('  - message: ${verifyResponse.message}');
        Logger.debug('  - purpose: ${verifyResponse.purpose}');
        Logger.debug('  - isLogin: ${verifyResponse.isLogin}');
        Logger.debug('  - needsRegistration: ${verifyResponse.needsRegistration}');

        // If this is a login (has token and user), save auth data
        if (verifyResponse.isLogin) {
          final userData = verifyResponse.user!;
          final tenantData = verifyResponse.tenant;

          // Add tenant_id to user data
          if (tenantData != null && tenantData['id'] != null) {
            userData['tenant_id'] = SafeCast.toStringValue(tenantData['id']);
            userData['tenant_name'] = SafeCast.toStringOrNull(tenantData['name']);
          }

          final user = UserModel.fromJson(userData);

          await _authService.saveAuthData(
            token: verifyResponse.token!,
            refreshToken: verifyResponse.refreshToken,
            userId: user.id,
            tenantId: user.tenantId,
            userName: user.displayName,
            email: user.email,
            role: user.role,
            phone: mobile,
          );

          // Save session ID for device management
          if (verifyResponse.sessionId != null) {
            await _authService.saveSessionId(verifyResponse.sessionId!);
          }

          // CRITICAL FIX: Wait for secure storage to fully persist
          // This prevents race conditions where subsequent API calls
          // try to read the token before it's fully written to disk
          await Future.delayed(const Duration(milliseconds: 300));

          // CRITICAL: Force refresh DioApiService token cache
          // Without this, DioApiService still has null/old cached token
          // and all subsequent API calls get 401 "Invalid token"
          await _apiService.forceRefreshToken();

          Logger.info('[AuthProvider] OTP verified - Token saved and cache refreshed');

          _currentUser = user.copyWith(phone: mobile);

          // Wire analytics user context
          AnalyticsService.setUserId(user.id);
          AnalyticsService.setUserProperties({
            'role': user.role,
            'tenant_id': user.tenantId ?? 'none',
          });
          AnalyticsService.trackLogin(method: 'phone_otp');
          _setCrashlyticsUserContext(user.id, user.role, user.tenantId);
          if (!kDebugMode) {
            Clarity.setCustomUserId(user.id);
          }
        }

        _setLoading(false);
        return verifyResponse;
      } else {
        _setError(response.message ?? 'Invalid OTP');
        _setLoading(false);
        return null;
      }
    } on DeviceLimitException {
      // Re-throw device limit exceptions so UI can handle them
      _setLoading(false);
      rethrow;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      return null;
    }
  }

  /// Force login OTP - Used when device limit is reached
  /// Logs out the selected session and logs in on this device
  /// This is the Swiggy/Zomato style device replacement flow
  Future<VerifyOtpResponse?> forceLoginOtp({
    required String mobile,
    required String otp,
    required String sessionIdToRemove,
    String? sessionId,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      // Get device info for device management
      final deviceInfo = await DeviceInfoService.getDeviceInfo();
      if (kDebugMode) {
        Logger.debug('[AuthProvider] Force login - Device: ${deviceInfo.deviceName}');
        Logger.debug('[AuthProvider] Session to remove: $sessionIdToRemove');
      }

      // Build request body with session_id_to_remove
      final requestBody = {
        'mobile': mobile,
        'otp': otp,
        'session_id': sessionId,
        'session_id_to_remove': sessionIdToRemove,
        ...deviceInfo.toJson(),
      };

      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConfig.forceLoginOtp,
        body: requestBody,
        fromJson: (data) => SafeCast.toMap<String, dynamic>(data),
      );

      if (response.isSuccess && response.data != null) {
        if (kDebugMode) {
          Logger.info('[AuthProvider] Force login successful');
        }
        final verifyResponse = VerifyOtpResponse.fromJson(response.data!);

        // If this is a login (has token and user), save auth data
        if (verifyResponse.isLogin) {
          final userData = verifyResponse.user!;
          final tenantData = verifyResponse.tenant;

          // Add tenant_id to user data
          if (tenantData != null && tenantData['id'] != null) {
            userData['tenant_id'] = SafeCast.toStringValue(tenantData['id']);
            userData['tenant_name'] = SafeCast.toStringOrNull(tenantData['name']);
          }

          final user = UserModel.fromJson(userData);

          await _authService.saveAuthData(
            token: verifyResponse.token!,
            refreshToken: verifyResponse.refreshToken,
            userId: user.id,
            tenantId: user.tenantId,
            userName: user.displayName,
            email: user.email,
            role: user.role,
          );

          // Save session ID for device management
          if (verifyResponse.sessionId != null) {
            await _authService.saveSessionId(verifyResponse.sessionId!);
          }

          // CRITICAL FIX: Wait for secure storage to fully persist
          await Future.delayed(const Duration(milliseconds: 300));

          Logger.info('[AuthProvider] Force login OTP verified - Token saved and ready');

          _currentUser = user;
        }

        _setLoading(false);
        return verifyResponse;
      } else {
        _setError(response.message ?? 'Force login failed');
        _setLoading(false);
        return null;
      }
    } catch (e) {
      if (kDebugMode) {
        Logger.error('[AuthProvider] Force login error: $e');
      }
      _setError(e.toString());
      _setLoading(false);
      return null;
    }
  }

  /// Complete registration after OTP verification
  Future<bool> register({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String phone,
    required String tenantName,
    required String companyName,
    required String registrationToken,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final request = RegistrationRequest(
        email: email,
        password: password,
        firstName: firstName,
        lastName: lastName,
        phone: phone,
        tenantName: tenantName,
        companyName: companyName,
        registrationToken: registrationToken,
      );

      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConfig.register,
        body: request.toJson(),
        fromJson: (data) => SafeCast.toMap<String, dynamic>(data),
      );

      if (response.isSuccess && response.data != null) {
        final loginResponse = LoginResponse.fromJson(response.data!);

        // Save auth data
        await _authService.saveAuthData(
          token: loginResponse.token,
          refreshToken: loginResponse.refreshToken,
          userId: loginResponse.user.id,
          tenantId: loginResponse.user.tenantId,
          userName: loginResponse.user.displayName,
          email: loginResponse.user.email,
          role: loginResponse.user.role,
        );

        // CRITICAL FIX: Wait for secure storage to fully persist
        // This prevents race conditions where subsequent API calls
        // try to read the token before it's fully written to disk
        await Future.delayed(const Duration(milliseconds: 300));

        // ✅ CRITICAL: Force refresh DioApiService token cache
        // After registration, the new token is in storage but DioApiService
        // still has the old token cached. Force refresh to use the new token.
        await _apiService.forceRefreshToken();

        Logger.info('[AuthProvider] Registration complete - Token saved and cache refreshed');

        _currentUser = loginResponse.user;
        _setLoading(false);
        return true;
      } else {
        _setError(response.message ?? 'Registration failed');
        _setLoading(false);
        return false;
      }
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      return false;
    }
  }

  /// Validate if a tenant name is available
  Future<bool> validateTenantName(String tenantName) async {
    try {
      if (kDebugMode) {
        Logger.debug('[AuthProvider] Validating tenant name: "$tenantName"');
      }

      final response = await _apiService.get<Map<String, dynamic>>(
        '/api/admin/validate/tenant',
        queryParams: {'name': tenantName},
        fromJson: (data) => SafeCast.toMap<String, dynamic>(data),
      );

      if (kDebugMode) {
        Logger.debug('[AuthProvider] Tenant validation response:');
        Logger.debug('   Success: ${response.isSuccess}');
        Logger.debug('   Data: ${response.data}');
        Logger.debug('   Message: ${response.message}');
      }

      if (response.isSuccess) {
        // Backend returns {available: true/false}
        final available = response.data?['available'] ?? false;
        if (kDebugMode) {
          Logger.info('[AuthProvider] Tenant "$tenantName" available: $available');
        }
        return available;
      }

      if (kDebugMode) {
        Logger.warning('[AuthProvider] Tenant validation failed: ${response.message}');
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        Logger.error('[AuthProvider] Error validating tenant name: $e');
      }
      return false;
    }
  }

  /// Validate if an email is available for registration
  Future<bool> validateEmail(String email) async {
    try {
      if (kDebugMode) {
        Logger.debug('[AuthProvider] Validating email: "$email"');
      }

      final response = await _apiService.get<Map<String, dynamic>>(
        '/api/admin/validate/email',
        queryParams: {'email': email},
        fromJson: (data) => SafeCast.toMap<String, dynamic>(data),
      );

      if (kDebugMode) {
        Logger.debug('[AuthProvider] Email validation response:');
        Logger.debug('   Success: ${response.isSuccess}');
        Logger.debug('   Data: ${response.data}');
        Logger.debug('   Message: ${response.message}');
      }

      if (response.isSuccess) {
        // Backend returns {available: true/false}
        final available = response.data?['available'] ?? false;
        if (kDebugMode) {
          Logger.info('[AuthProvider] Email "$email" available: $available');
        }
        return available;
      }

      if (kDebugMode) {
        Logger.warning('[AuthProvider] Email validation failed: ${response.message}');
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        Logger.error('[AuthProvider] Error validating email: $e');
      }
      return false;
    }
  }

  // ==================== ACCOUNT DELETION ====================
  // Required by Apple App Store Guideline 5.1.1(v)

  /// Request OTP for account deletion verification
  Future<SendOtpResponse?> requestDeleteAccountOtp() async {
    final phone = _currentUser?.phone;
    if (phone == null) {
      _setError('User phone not found');
      return null;
    }
    return await sendOtp(phone);
  }

  /// Delete account with OTP verification
  /// This permanently deletes the user's account and all associated data
  Future<bool> deleteAccount({
    required String otp,
    required String sessionId,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final phone = _currentUser?.phone;
      if (phone == null) {
        throw Exception('User phone not found');
      }

      if (kDebugMode) {
        Logger.info('[AuthProvider] Initiating account deletion for: $phone');
      }

      // Use POST for account deletion since it requires a body with OTP verification
      final response = await _apiService.post<Map<String, dynamic>>(
        '/api/auth/account/delete',
        body: {
          'mobile': phone,
          'otp': otp,
          'session_id': sessionId,
        },
      );

      if (response.isSuccess) {
        if (kDebugMode) {
          Logger.info('[AuthProvider] Account deleted successfully');
        }

        // Clear all local data
        await _authService.clearAll();
        _currentUser = null;

        _setLoading(false);
        notifyListeners();
        return true;
      } else {
        _setError(response.message ?? 'Failed to delete account');
        _setLoading(false);
        return false;
      }
    } catch (e) {
      if (kDebugMode) {
        Logger.error('[AuthProvider] Error deleting account: $e');
      }
      _setError(e.toString());
      _setLoading(false);
      return false;
    }
  }

  // ==================== SESSION MANAGEMENT (WhatsApp style Linked Devices) ====================

  /// Get current session ID from storage
  String? _currentSessionId;

  String? get currentSessionId => _currentSessionId;

  /// Load current session ID from storage
  Future<void> loadCurrentSessionId() async {
    _currentSessionId = await _authService.getSessionId();
  }

  /// Get all active sessions for current user (WhatsApp style)
  Future<DeviceSessionsResponse> getActiveSessions() async {
    try {
      if (kDebugMode) {
        Logger.debug('[AuthProvider] Fetching active sessions...');
      }

      // Load current session ID if not already loaded
      if (_currentSessionId == null) {
        await loadCurrentSessionId();
      }

      final response = await _apiService.get<Map<String, dynamic>>(
        ApiConfig.sessions,
        fromJson: (data) => SafeCast.toMap<String, dynamic>(data),
      );

      if (response.isSuccess && response.data != null) {
        if (kDebugMode) {
          Logger.debug('[AuthProvider] Sessions fetched: ${response.data}');
        }
        return DeviceSessionsResponse.fromJson(response.data!);
      } else {
        if (kDebugMode) {
          print('❌ [AuthProvider] Failed to fetch sessions: ${response.message}');
        }
        throw Exception(response.message ?? 'Failed to fetch sessions');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ [AuthProvider] Error fetching sessions: $e');
      }
      rethrow;
    }
  }

  /// Logout a specific device by session ID
  Future<bool> logoutDevice(String sessionId) async {
    _setLoading(true);
    _setError(null);

    try {
      if (kDebugMode) {
        print('🔄 [AuthProvider] Logging out device: $sessionId');
      }

      final response = await _apiService.delete<Map<String, dynamic>>(
        '${ApiConfig.sessionLogout}/$sessionId',
        fromJson: (data) => SafeCast.toMap<String, dynamic>(data),
      );

      _setLoading(false);

      if (response.isSuccess) {
        if (kDebugMode) {
          print('✅ [AuthProvider] Device logged out successfully');
        }
        return true;
      } else {
        _setError(response.message ?? 'Failed to logout device');
        if (kDebugMode) {
          print('❌ [AuthProvider] Failed to logout device: ${response.message}');
        }
        return false;
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ [AuthProvider] Error logging out device: $e');
      }
      _setError(e.toString());
      _setLoading(false);
      return false;
    }
  }

  /// Logout all other devices except current one
  Future<bool> logoutAllOtherDevices() async {
    _setLoading(true);
    _setError(null);

    try {
      if (kDebugMode) {
        print('🔄 [AuthProvider] Logging out all other devices...');
      }

      final response = await _apiService.delete<Map<String, dynamic>>(
        ApiConfig.sessions,
        fromJson: (data) => SafeCast.toMap<String, dynamic>(data),
      );

      _setLoading(false);

      if (response.isSuccess) {
        if (kDebugMode) {
          print('✅ [AuthProvider] All other devices logged out successfully');
        }
        return true;
      } else {
        _setError(response.message ?? 'Failed to logout devices');
        if (kDebugMode) {
          print('❌ [AuthProvider] Failed to logout all devices: ${response.message}');
        }
        return false;
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ [AuthProvider] Error logging out all devices: $e');
      }
      _setError(e.toString());
      _setLoading(false);
      return false;
    }
  }
}
