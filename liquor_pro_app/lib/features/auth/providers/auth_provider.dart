import 'package:flutter/foundation.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/config/api_config.dart';
import '../../../core/models/api_response.dart';
import '../models/user_model.dart';
import '../models/otp_models.dart';

/// Authentication Provider
class AuthProvider extends ChangeNotifier {
  final ApiService _apiService;
  final AuthService _authService;

  UserModel? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;

  AuthProvider({
    required ApiService apiService,
    required AuthService authService,
  })  : _apiService = apiService,
        _authService = authService;

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
        fromJson: (data) => data as Map<String, dynamic>,
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

        _currentUser = loginResponse.user;
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
    final isAuth = await _authService.isAuthenticated();
    if (!isAuth) {
      _currentUser = null;
      notifyListeners();
      return;
    }

    final userId = await _authService.getUserId();
    final tenantId = await _authService.getTenantId();
    final userName = await _authService.getUserName();
    final userEmail = await _authService.getUserEmail();
    final userRole = await _authService.getUserRole();

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
      );
      notifyListeners();
    }
  }

  // Logout
  Future<void> logout() async {
    await _authService.logout();
    _currentUser = null;
    notifyListeners();
  }

  // Clear error
  void clearError() {
    _setError(null);
  }

  // ==================== OTP AUTHENTICATION ====================

  /// Check if user exists by phone number
  Future<CheckUserResponse?> checkUser(String mobile) async {
    _setLoading(true);
    _setError(null);

    try {
      final request = CheckUserRequest(mobile: mobile);

      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConfig.checkUser,
        body: request.toJson(),
        fromJson: (data) => data as Map<String, dynamic>,
      );

      _setLoading(false);

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
        fromJson: (data) => data as Map<String, dynamic>,
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
        fromJson: (data) => data as Map<String, dynamic>,
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
  Future<VerifyOtpResponse?> verifyOtp({
    required String mobile,
    required String otp,
    String? sessionId,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final request = VerifyOtpRequest(
        mobile: mobile,
        otp: otp,
        sessionId: sessionId,
      );

      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConfig.verifyOtp,
        body: request.toJson(),
        fromJson: (data) => data as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        final verifyResponse = VerifyOtpResponse.fromJson(response.data!);

        // If this is a login (has token and user), save auth data
        if (verifyResponse.isLogin) {
          final userData = verifyResponse.user!;
          final tenantData = verifyResponse.tenant;

          // Add tenant_id to user data
          if (tenantData != null && tenantData['id'] != null) {
            userData['tenant_id'] = tenantData['id'] as String;
            userData['tenant_name'] = tenantData['name'] as String?;
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

          _currentUser = user;
        }

        _setLoading(false);
        return verifyResponse;
      } else {
        _setError(response.message ?? 'Invalid OTP');
        _setLoading(false);
        return null;
      }
    } catch (e) {
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
      );

      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConfig.register,
        body: request.toJson(),
        fromJson: (data) => data as Map<String, dynamic>,
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
}
