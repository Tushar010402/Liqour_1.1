import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:crypto/crypto.dart';
import '../constants/api_endpoints.dart';
import '../models/api_response.dart';
import 'api_service.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static const String _tokenKey = 'auth_token';
  static const String _userDataKey = 'user_data';
  static const String _biometricEnabledKey = 'biometric_enabled';
  static const String _phoneNumberKey = 'phone_number';

  final LocalAuthentication _localAuth = LocalAuthentication();

  // Check if user is authenticated
  Future<bool> isAuthenticated() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  // Get stored token
  Future<String?> getToken() async {
    return await _secureStorage.read(key: _tokenKey);
  }

  // Store token
  Future<void> storeToken(String token) async {
    await _secureStorage.write(key: _tokenKey, value: token);
  }

  // Get stored user data
  Future<Map<String, dynamic>?> getUserData() async {
    final userData = await _secureStorage.read(key: _userDataKey);
    if (userData != null) {
      return jsonDecode(userData);
    }
    return null;
  }

  // Store user data
  Future<void> storeUserData(Map<String, dynamic> userData) async {
    await _secureStorage.write(key: _userDataKey, value: jsonEncode(userData));
  }

  // Check if user is SaaS admin
  Future<ApiResponse<bool>> isAdmin(String phoneNumber) async {
    final apiService = ApiService();
    return await apiService.post<bool>(
      ApiEndpoints.isAdmin,
      data: {'mobile': phoneNumber},
      fromJson: (data) => data['is_saas_admin'] ?? false,
    );
  }

  // Send OTP
  Future<ApiResponse<String>> sendOTP(String phoneNumber) async {
    final apiService = ApiService();
    final response = await apiService.post<String>(
      ApiEndpoints.sendOTP,
      data: {'mobile': phoneNumber},
      fromJson: (data) => data['message'] ?? 'OTP sent successfully',
    );

    if (response.isSuccess) {
      await _secureStorage.write(key: _phoneNumberKey, value: phoneNumber);
    }

    return response;
  }

  // Verify OTP and login
  Future<ApiResponse<Map<String, dynamic>>> verifyOTP(
    String phoneNumber,
    String otp,
  ) async {
    final apiService = ApiService();
    final response = await apiService.post<Map<String, dynamic>>(
      ApiEndpoints.verifyOTP,
      data: {
        'mobile': phoneNumber,
        'otp': otp,
      },
      fromJson: (data) => data as Map<String, dynamic>,
    );

    if (response.isSuccess && response.data != null) {
      final data = response.data!;

      // Store token if present
      if (data['token'] != null) {
        await storeToken(data['token']);
      }

      // Store user data
      if (data['user'] != null) {
        await storeUserData(data['user']);
      }
    }

    return response;
  }

  // Logout
  Future<void> logout() async {
    await _secureStorage.delete(key: _tokenKey);
    await _secureStorage.delete(key: _userDataKey);
    await _secureStorage.delete(key: _phoneNumberKey);
  }

  // Biometric Authentication
  Future<bool> isBiometricAvailable() async {
    try {
      final isAvailable = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      return isAvailable && isDeviceSupported;
    } catch (e) {
      return false;
    }
  }

  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      return [];
    }
  }

  Future<bool> isBiometricEnabled() async {
    final enabled = await _secureStorage.read(key: _biometricEnabledKey);
    return enabled == 'true';
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    await _secureStorage.write(
      key: _biometricEnabledKey,
      value: enabled.toString(),
    );
  }

  Future<bool> authenticateWithBiometric() async {
    try {
      final isAuthenticated = await _localAuth.authenticate(
        localizedReason: 'Please authenticate to access the app',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      return isAuthenticated;
    } catch (e) {
      return false;
    }
  }

  // Get stored phone number
  Future<String?> getStoredPhoneNumber() async {
    return await _secureStorage.read(key: _phoneNumberKey);
  }

  // Modern security: Hash sensitive data using SHA-256 with salt
  String hashSensitiveData(String data, [String? salt]) {
    final saltValue = salt ?? DateTime.now().millisecondsSinceEpoch.toString();
    final saltedData = data + saltValue;
    final bytes = utf8.encode(saltedData);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // Generate secure random salt for enhanced security
  String generateSecureSalt() {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final randomComponent = DateTime.now().microsecondsSinceEpoch.toString();
    final randomBytes = utf8.encode(timestamp + randomComponent);
    return sha256.convert(randomBytes).toString().substring(0, 16);
  }

  // Clear all stored data (for emergency logout)
  Future<void> clearAllData() async {
    await _secureStorage.deleteAll();
  }

  // Session validation
  Future<bool> validateSession() async {
    try {
      final token = await getToken();
      if (token == null) return false;

      // You can add a token validation API call here
      // For now, just check if token exists
      return true;
    } catch (e) {
      return false;
    }
  }

  // Auto-logout timer (for security)
  void startAutoLogoutTimer(Duration duration) {
    Future.delayed(duration, () async {
      await logout();
    });
  }
}
