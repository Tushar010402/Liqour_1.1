import 'package:flutter/foundation.dart';
import '../../../core/services/dio_api_service.dart';
import '../models/device_session_models.dart';
import '../models/user_model.dart';

/// Service for managing device sessions
/// Provides APIs to view, logout, and manage device sessions (Swiggy/Zomato style)
class DeviceSessionService {
  final DioApiService _apiService;

  DeviceSessionService(this._apiService);

  /// Get all active sessions for the current user
  /// Returns list of devices with login details
  Future<DeviceSessionsResponse> getActiveSessions() async {
    try {
      if (kDebugMode) {
        print('[DeviceSessionService] Fetching active sessions...');
      }

      final response = await _apiService.get<Map<String, dynamic>>(
        '/api/auth/sessions',
        fromJson: (data) => data as Map<String, dynamic>,
      );

      if (!response.success) {
        throw Exception(response.message ?? 'Failed to fetch sessions');
      }

      if (response.data == null) {
        // Return empty response if no data
        return const DeviceSessionsResponse();
      }

      final sessionsResponse = DeviceSessionsResponse.fromJson(response.data!);

      if (kDebugMode) {
        print('[DeviceSessionService] Found ${sessionsResponse.sessions.length} sessions');
      }

      return sessionsResponse;
    } catch (e) {
      if (kDebugMode) {
        print('[DeviceSessionService] Error fetching sessions: $e');
      }
      rethrow;
    }
  }

  /// Logout a specific device by session ID
  /// Removes the session from active sessions
  Future<void> logoutDevice(String sessionId) async {
    try {
      if (kDebugMode) {
        print('[DeviceSessionService] Logging out session: $sessionId');
      }

      final response = await _apiService.delete<Map<String, dynamic>>(
        '/api/auth/sessions/$sessionId',
      );

      if (!response.success) {
        throw Exception(response.message ?? 'Failed to logout device');
      }

      if (kDebugMode) {
        print('[DeviceSessionService] Session logged out successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[DeviceSessionService] Error logging out device: $e');
      }
      rethrow;
    }
  }

  /// Logout all devices except the current one
  /// Useful for "Logout from all other devices" feature
  Future<void> logoutAllDevices({bool excludeCurrent = true}) async {
    try {
      if (kDebugMode) {
        print('[DeviceSessionService] Logging out all devices (excludeCurrent: $excludeCurrent)');
      }

      // Include query params in the endpoint URL since delete() doesn't support queryParams
      final endpoint = '/api/auth/sessions?exclude_current=${excludeCurrent.toString()}';
      final response = await _apiService.delete<Map<String, dynamic>>(
        endpoint,
      );

      if (!response.success) {
        throw Exception(response.message ?? 'Failed to logout devices');
      }

      if (kDebugMode) {
        print('[DeviceSessionService] All devices logged out successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[DeviceSessionService] Error logging out all devices: $e');
      }
      rethrow;
    }
  }

  /// Force login by automatically logging out the oldest device
  /// Used when user chooses "Continue anyway" on device limit modal
  Future<LoginResponse> forceLogin(DeviceInfo deviceInfo) async {
    try {
      if (kDebugMode) {
        print('[DeviceSessionService] Force login requested');
      }

      final response = await _apiService.post<Map<String, dynamic>>(
        '/api/auth/sessions/force-login',
        body: deviceInfo.toJson(),
        fromJson: (data) => data as Map<String, dynamic>,
      );

      if (!response.success || response.data == null) {
        throw Exception(response.message ?? 'Force login failed');
      }

      if (kDebugMode) {
        print('[DeviceSessionService] Force login successful');
      }

      return LoginResponse.fromJson(response.data!);
    } catch (e) {
      if (kDebugMode) {
        print('[DeviceSessionService] Error during force login: $e');
      }
      rethrow;
    }
  }

  /// Logout a specific device then retry login
  /// Used in device limit modal workflow
  Future<void> logoutDeviceAndRetry(String sessionId) async {
    await logoutDevice(sessionId);
    // The caller will handle retry logic
  }
}
