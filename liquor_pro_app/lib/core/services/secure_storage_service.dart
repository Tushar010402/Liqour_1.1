import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';

/// Provider for SecureStorageService
final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

/// Secure storage service for sensitive data
/// Uses flutter_secure_storage for encrypted key-value storage
class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  // Keys
  static const _keyDeviceId = 'device_id';
  static const _keyFcmToken = 'fcm_token';
  static const _keyAuthToken = 'auth_token';
  static const _keyRefreshToken = 'refresh_token';
  static const _keyUserId = 'user_id';
  static const _keyTenantId = 'tenant_id';

  /// Get device ID
  Future<String?> getDeviceId() async {
    try {
      return await _storage.read(key: _keyDeviceId);
    } catch (e) {
      if (kDebugMode) debugPrint('SecureStorage: Error reading device_id: $e');
      return null;
    }
  }

  /// Set device ID
  Future<void> setDeviceId(String deviceId) async {
    try {
      await _storage.write(key: _keyDeviceId, value: deviceId);
    } catch (e) {
      if (kDebugMode) debugPrint('SecureStorage: Error writing device_id: $e');
    }
  }

  /// Get FCM token
  Future<String?> getFcmToken() async {
    try {
      return await _storage.read(key: _keyFcmToken);
    } catch (e) {
      if (kDebugMode) debugPrint('SecureStorage: Error reading fcm_token: $e');
      return null;
    }
  }

  /// Set FCM token
  Future<void> setFcmToken(String token) async {
    try {
      await _storage.write(key: _keyFcmToken, value: token);
    } catch (e) {
      if (kDebugMode) debugPrint('SecureStorage: Error writing fcm_token: $e');
    }
  }

  /// Get auth token
  Future<String?> getAuthToken() async {
    try {
      return await _storage.read(key: _keyAuthToken);
    } catch (e) {
      if (kDebugMode) debugPrint('SecureStorage: Error reading auth_token: $e');
      return null;
    }
  }

  /// Set auth token
  Future<void> setAuthToken(String token) async {
    try {
      await _storage.write(key: _keyAuthToken, value: token);
    } catch (e) {
      if (kDebugMode) debugPrint('SecureStorage: Error writing auth_token: $e');
    }
  }

  /// Get refresh token
  Future<String?> getRefreshToken() async {
    try {
      return await _storage.read(key: _keyRefreshToken);
    } catch (e) {
      if (kDebugMode) debugPrint('SecureStorage: Error reading refresh_token: $e');
      return null;
    }
  }

  /// Set refresh token
  Future<void> setRefreshToken(String token) async {
    try {
      await _storage.write(key: _keyRefreshToken, value: token);
    } catch (e) {
      if (kDebugMode) debugPrint('SecureStorage: Error writing refresh_token: $e');
    }
  }

  /// Get user ID
  Future<String?> getUserId() async {
    try {
      return await _storage.read(key: _keyUserId);
    } catch (e) {
      if (kDebugMode) debugPrint('SecureStorage: Error reading user_id: $e');
      return null;
    }
  }

  /// Set user ID
  Future<void> setUserId(String userId) async {
    try {
      await _storage.write(key: _keyUserId, value: userId);
    } catch (e) {
      if (kDebugMode) debugPrint('SecureStorage: Error writing user_id: $e');
    }
  }

  /// Get tenant ID
  Future<String?> getTenantId() async {
    try {
      return await _storage.read(key: _keyTenantId);
    } catch (e) {
      if (kDebugMode) debugPrint('SecureStorage: Error reading tenant_id: $e');
      return null;
    }
  }

  /// Set tenant ID
  Future<void> setTenantId(String tenantId) async {
    try {
      await _storage.write(key: _keyTenantId, value: tenantId);
    } catch (e) {
      if (kDebugMode) debugPrint('SecureStorage: Error writing tenant_id: $e');
    }
  }

  /// Read a custom key
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      if (kDebugMode) debugPrint('SecureStorage: Error reading $key: $e');
      return null;
    }
  }

  /// Write a custom key-value pair
  Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      if (kDebugMode) debugPrint('SecureStorage: Error writing $key: $e');
    }
  }

  /// Delete a key
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
      if (kDebugMode) debugPrint('SecureStorage: Error deleting $key: $e');
    }
  }

  /// Clear all stored data
  Future<void> clearAll() async {
    try {
      await _storage.deleteAll();
      if (kDebugMode) debugPrint('SecureStorage: All data cleared');
    } catch (e) {
      if (kDebugMode) debugPrint('SecureStorage: Error clearing all: $e');
    }
  }

  /// Clear authentication data (on logout)
  Future<void> clearAuthData() async {
    try {
      await Future.wait([
        _storage.delete(key: _keyAuthToken),
        _storage.delete(key: _keyRefreshToken),
        _storage.delete(key: _keyUserId),
      ]);
      if (kDebugMode) debugPrint('SecureStorage: Auth data cleared');
    } catch (e) {
      if (kDebugMode) debugPrint('SecureStorage: Error clearing auth data: $e');
    }
  }
}
