import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Authentication Service
class AuthService {
  final FlutterSecureStorage _secureStorage;
  final SharedPreferences _prefs;

  // iOS Keychain Options - ensures tokens persist across app restarts on physical devices
  static const _iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
    accountName: 'com.liquorproapp.store',
  );

  // Android Options - ensures encrypted shared preferences work correctly
  static const _androidOptions = AndroidOptions(
    encryptedSharedPreferences: true,
  );

  // Storage keys
  static const String _keyToken = 'auth_token';
  static const String _keyRefreshToken = 'refresh_token';
  static const String _keyUserId = 'user_id';
  static const String _keyTenantId = 'tenant_id';
  static const String _keyUserName = 'user_name';
  static const String _keyUserEmail = 'user_email';
  static const String _keyUserRole = 'user_role';
  static const String _keyUserPhone = 'user_phone';
  static const String _keySessionId = 'session_id';  // For device management

  AuthService({
    required FlutterSecureStorage secureStorage,
    required SharedPreferences prefs,
  })  : _secureStorage = secureStorage,
        _prefs = prefs;

  // Get platform-specific options for secure storage
  IOSOptions? get _platformIosOptions => Platform.isIOS ? _iosOptions : null;
  AndroidOptions? get _platformAndroidOptions => Platform.isAndroid ? _androidOptions : null;

  // Save authentication data
  Future<void> saveAuthData({
    required String token,
    String? refreshToken,
    required String userId,
    required String? tenantId,
    required String userName,
    required String email,
    required String role,
    String? phone,
  }) async {
    await _secureStorage.write(
      key: _keyToken,
      value: token,
      iOptions: _platformIosOptions,
      aOptions: _platformAndroidOptions,
    );
    if (refreshToken != null) {
      await _secureStorage.write(
        key: _keyRefreshToken,
        value: refreshToken,
        iOptions: _platformIosOptions,
        aOptions: _platformAndroidOptions,
      );
    }

    await _prefs.setString(_keyUserId, userId);
    if (tenantId != null) {
      await _prefs.setString(_keyTenantId, tenantId);
    }
    await _prefs.setString(_keyUserName, userName);
    await _prefs.setString(_keyUserEmail, email);
    await _prefs.setString(_keyUserRole, role);
    if (phone != null) {
      await _prefs.setString(_keyUserPhone, phone);
    }
  }

  // Get token
  Future<String?> getToken() async {
    final token = await _secureStorage.read(
      key: _keyToken,
      iOptions: _platformIosOptions,
      aOptions: _platformAndroidOptions,
    );
    return token;
  }

  // Get refresh token
  Future<String?> getRefreshToken() async {
    return await _secureStorage.read(
      key: _keyRefreshToken,
      iOptions: _platformIosOptions,
      aOptions: _platformAndroidOptions,
    );
  }

  // Get user ID
  Future<String?> getUserId() async {
    return _prefs.getString(_keyUserId);
  }

  // Get tenant ID
  Future<String?> getTenantId() async {
    return _prefs.getString(_keyTenantId);
  }

  // Get user name
  Future<String?> getUserName() async {
    return _prefs.getString(_keyUserName);
  }

  // Get user email
  Future<String?> getUserEmail() async {
    return _prefs.getString(_keyUserEmail);
  }

  // Get user role
  Future<String?> getUserRole() async {
    return _prefs.getString(_keyUserRole);
  }

  // Get user phone
  Future<String?> getUserPhone() async {
    return _prefs.getString(_keyUserPhone);
  }

  // Save session ID (for device management - identifying current session)
  Future<void> saveSessionId(String sessionId) async {
    await _prefs.setString(_keySessionId, sessionId);
    print('[AuthService] Session ID saved: $sessionId');
  }

  // Get session ID
  Future<String?> getSessionId() async {
    return _prefs.getString(_keySessionId);
  }

  // Check if user is authenticated
  Future<bool> isAuthenticated() async {
    final token = await getToken();
    final isAuth = token != null && token.isNotEmpty;
    print('🔐 [AuthService] isAuthenticated check: $isAuth');
    return isAuth;
  }

  // Logout
  Future<void> logout() async {
    await _secureStorage.delete(
      key: _keyToken,
      iOptions: _platformIosOptions,
      aOptions: _platformAndroidOptions,
    );
    await _secureStorage.delete(
      key: _keyRefreshToken,
      iOptions: _platformIosOptions,
      aOptions: _platformAndroidOptions,
    );
    await _prefs.remove(_keyUserId);
    await _prefs.remove(_keyTenantId);
    await _prefs.remove(_keyUserName);
    await _prefs.remove(_keyUserEmail);
    await _prefs.remove(_keyUserRole);
    await _prefs.remove(_keyUserPhone);
    await _prefs.remove(_keySessionId);  // Clear session ID for device management
  }

  // Clear all data
  Future<void> clearAll() async {
    await _secureStorage.deleteAll(
      iOptions: _platformIosOptions,
      aOptions: _platformAndroidOptions,
    );
    await _prefs.clear();
  }
}
