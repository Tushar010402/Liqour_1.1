import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utils/logger.dart';

/// Authentication Service
class AuthService {
  final FlutterSecureStorage _secureStorage;
  final SharedPreferences _prefs;

  // Storage keys
  static const String _keyToken = 'auth_token';
  static const String _keyRefreshToken = 'refresh_token';
  static const String _keyUserId = 'user_id';
  static const String _keyTenantId = 'tenant_id';
  static const String _keyUserName = 'user_name';
  static const String _keyUserEmail = 'user_email';
  static const String _keyUserRole = 'user_role';

  AuthService({
    required FlutterSecureStorage secureStorage,
    required SharedPreferences prefs,
  })  : _secureStorage = secureStorage,
        _prefs = prefs;

  // Save authentication data
  Future<void> saveAuthData({
    required String token,
    String? refreshToken,
    required String userId,
    required String? tenantId,
    required String userName,
    required String email,
    required String role,
  }) async {
    Logger.debug('💾 Saving auth data...');
    Logger.debug('💾 Token (first 20 chars): ${token.substring(0, 20)}...');
    Logger.debug('💾 User ID: $userId');
    Logger.debug('💾 Tenant ID: $tenantId');
    Logger.debug('💾 User Name: $userName');
    Logger.debug('💾 Email: $email');
    Logger.debug('💾 Role: $role');

    await _secureStorage.write(key: _keyToken, value: token);
    if (refreshToken != null) {
      await _secureStorage.write(key: _keyRefreshToken, value: refreshToken);
    }

    await _prefs.setString(_keyUserId, userId);
    if (tenantId != null) {
      await _prefs.setString(_keyTenantId, tenantId);
    }
    await _prefs.setString(_keyUserName, userName);
    await _prefs.setString(_keyUserEmail, email);
    await _prefs.setString(_keyUserRole, role);

    Logger.debug('✅ Auth data saved successfully');
  }

  // Get token
  Future<String?> getToken() async {
    final token = await _secureStorage.read(key: _keyToken);
    Logger.debug('🔑 AuthService.getToken() called - Token exists: ${token != null}, Length: ${token?.length}');
    return token;
  }

  // Get refresh token
  Future<String?> getRefreshToken() async {
    return await _secureStorage.read(key: _keyRefreshToken);
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

  // Check if user is authenticated
  Future<bool> isAuthenticated() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  // Logout
  Future<void> logout() async {
    await _secureStorage.delete(key: _keyToken);
    await _secureStorage.delete(key: _keyRefreshToken);
    await _prefs.remove(_keyUserId);
    await _prefs.remove(_keyTenantId);
    await _prefs.remove(_keyUserName);
    await _prefs.remove(_keyUserEmail);
    await _prefs.remove(_keyUserRole);
  }

  // Clear all data
  Future<void> clearAll() async {
    await _secureStorage.deleteAll();
    await _prefs.clear();
  }
}
