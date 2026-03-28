import 'package:flutter/foundation.dart';
import '../../../core/config/api_config.dart';
import '../../../core/services/dio_api_service.dart';
import '../../../core/models/api_response.dart';
import '../../../core/utils/safe_casting.dart';
import '../models/notification_models.dart';

/// Notification Service - Handles all notification API operations
/// Supports: In-app, Push (FCM), Email, SMS, WhatsApp
class NotificationService {
  final DioApiService _apiService;

  // === THROTTLING FOR UNREAD COUNT ===
  DateTime? _lastUnreadCountCall;
  int _cachedUnreadCount = 0;
  bool _isFetchingUnreadCount = false;
  static const _unreadCountMinInterval = Duration(seconds: 10);

  NotificationService(this._apiService);

  // =========================================================================
  // NOTIFICATIONS
  // =========================================================================

  /// Get all notifications with optional filters
  Future<ApiResponse<NotificationListResponse>> getNotifications({
    String? type,
    bool? unreadOnly,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('🔔 NotificationService: Fetching notifications');
        debugPrint('   - Type: ${type ?? "all"}');
        debugPrint('   - Unread only: $unreadOnly');
        debugPrint('   - Limit: $limit, Offset: $offset');
      }

      final queryParams = <String, dynamic>{
        'limit': limit.toString(),
        'offset': offset.toString(),
      };
      if (type != null) queryParams['type'] = type;
      if (unreadOnly != null) queryParams['unread_only'] = unreadOnly.toString();

      final response = await _apiService.get(
        ApiConfig.notifications,
        queryParams: queryParams,
      );

      if (response.success && response.data != null) {
        final listResponse = NotificationListResponse.fromJson(
          SafeCast.toMap<String, dynamic>(response.data),
        );
        if (kDebugMode) {
          debugPrint('✅ NotificationService: Fetched ${listResponse.notifications.length} notifications');
          debugPrint('   - Unread: ${listResponse.unreadCount}');
        }
        return ApiResponse<NotificationListResponse>(
          success: true,
          data: listResponse,
        );
      }

      return ApiResponse<NotificationListResponse>(
        success: false,
        message: response.message ?? 'Failed to fetch notifications',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ NotificationService: Error fetching notifications - $e');
      return ApiResponse<NotificationListResponse>(
        success: false,
        message: 'Error fetching notifications: $e',
      );
    }
  }

  /// Get unread notification count (with throttling to prevent spam)
  Future<ApiResponse<int>> getUnreadCount() async {
    final now = DateTime.now();

    // THROTTLE: Prevent calls within 10 seconds - return cached value
    if (_lastUnreadCountCall != null &&
        now.difference(_lastUnreadCountCall!) < _unreadCountMinInterval) {
      if (kDebugMode) {
        debugPrint('🔔 [UnreadCount] Throttled (${now.difference(_lastUnreadCountCall!).inSeconds}s < 10s), returning cached: $_cachedUnreadCount');
      }
      return ApiResponse<int>(success: true, data: _cachedUnreadCount);
    }

    // PREVENT CONCURRENT: Skip if already fetching
    if (_isFetchingUnreadCount) {
      if (kDebugMode) {
        debugPrint('🔔 [UnreadCount] Already fetching, returning cached: $_cachedUnreadCount');
      }
      return ApiResponse<int>(success: true, data: _cachedUnreadCount);
    }

    _isFetchingUnreadCount = true;
    _lastUnreadCountCall = now;

    try {
      if (kDebugMode) debugPrint('🔔 NotificationService: Getting unread count');

      final response = await _apiService.get(ApiConfig.notificationUnreadCount);

      if (response.success && response.data != null) {
        final data = SafeCast.toMap<String, dynamic>(response.data);
        final count = data['count'] ?? data['unread_count'] ?? 0;
        _cachedUnreadCount = SafeCast.toInt(count);
        if (kDebugMode) debugPrint('✅ NotificationService: Unread count = $_cachedUnreadCount');
        return ApiResponse<int>(
          success: true,
          data: _cachedUnreadCount,
        );
      }

      // On failure, return cached value instead of error
      if (kDebugMode) debugPrint('⚠️ NotificationService: API failed, returning cached count: $_cachedUnreadCount');
      return ApiResponse<int>(
        success: true,
        data: _cachedUnreadCount,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ NotificationService: Error getting unread count - $e, returning cached: $_cachedUnreadCount');
      // Return cached value on error instead of propagating failure
      return ApiResponse<int>(
        success: true,
        data: _cachedUnreadCount,
      );
    } finally {
      _isFetchingUnreadCount = false;
    }
  }

  /// Force refresh unread count (bypasses throttle)
  Future<ApiResponse<int>> forceRefreshUnreadCount() async {
    _lastUnreadCountCall = null; // Reset throttle
    return getUnreadCount();
  }

  /// Mark a notification as read
  Future<ApiResponse<void>> markAsRead(String notificationId) async {
    try {
      if (kDebugMode) debugPrint('🔔 NotificationService: Marking as read - $notificationId');

      final response = await _apiService.patch(
        '${ApiConfig.notifications}/$notificationId/read',
        body: {},
      );

      if (response.success) {
        if (kDebugMode) debugPrint('✅ NotificationService: Marked as read');
        return ApiResponse<void>(success: true);
      }

      return ApiResponse<void>(
        success: false,
        message: response.message ?? 'Failed to mark as read',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ NotificationService: Error marking as read - $e');
      return ApiResponse<void>(
        success: false,
        message: 'Error marking as read: $e',
      );
    }
  }

  /// Mark all notifications as read
  Future<ApiResponse<void>> markAllAsRead() async {
    try {
      if (kDebugMode) debugPrint('🔔 NotificationService: Marking all as read');

      final response = await _apiService.post(
        ApiConfig.notificationMarkAllRead,
        body: {},
      );

      if (response.success) {
        if (kDebugMode) debugPrint('✅ NotificationService: All marked as read');
        return ApiResponse<void>(success: true);
      }

      return ApiResponse<void>(
        success: false,
        message: response.message ?? 'Failed to mark all as read',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ NotificationService: Error marking all as read - $e');
      return ApiResponse<void>(
        success: false,
        message: 'Error marking all as read: $e',
      );
    }
  }

  /// Delete a notification
  Future<ApiResponse<void>> deleteNotification(String notificationId) async {
    try {
      if (kDebugMode) debugPrint('🔔 NotificationService: Deleting - $notificationId');

      final response = await _apiService.delete('${ApiConfig.notifications}/$notificationId');

      if (response.success) {
        if (kDebugMode) debugPrint('✅ NotificationService: Deleted');
        return ApiResponse<void>(success: true);
      }

      return ApiResponse<void>(
        success: false,
        message: response.message ?? 'Failed to delete notification',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ NotificationService: Error deleting - $e');
      return ApiResponse<void>(
        success: false,
        message: 'Error deleting notification: $e',
      );
    }
  }

  /// Clear all notifications
  Future<ApiResponse<void>> clearAll() async {
    try {
      if (kDebugMode) debugPrint('🔔 NotificationService: Clearing all notifications');

      final response = await _apiService.delete(ApiConfig.notifications);

      if (response.success) {
        if (kDebugMode) debugPrint('✅ NotificationService: All cleared');
        return ApiResponse<void>(success: true);
      }

      return ApiResponse<void>(
        success: false,
        message: response.message ?? 'Failed to clear notifications',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ NotificationService: Error clearing all - $e');
      return ApiResponse<void>(
        success: false,
        message: 'Error clearing notifications: $e',
      );
    }
  }

  // =========================================================================
  // PREFERENCES
  // =========================================================================

  /// Get notification preferences
  Future<ApiResponse<NotificationPreferences>> getPreferences() async {
    try {
      if (kDebugMode) debugPrint('🔔 NotificationService: Getting preferences');

      final response = await _apiService.get(ApiConfig.notificationPreferences);

      if (response.success && response.data != null) {
        Map<String, dynamic>? prefsJson;

        // Handle different response formats
        if (response.data is List) {
          // Backend returns array - take first item or use defaults
          final list = SafeCast.toList<dynamic>(response.data);
          if (list.isNotEmpty && list.first is Map) {
            prefsJson = SafeCast.toMap<String, dynamic>(list.first);
            if (kDebugMode) debugPrint('📋 NotificationService: Parsed preferences from array (${list.length} items)');
          }
        } else if (response.data is Map) {
          prefsJson = SafeCast.toMap<String, dynamic>(response.data);

          // Check if wrapped in 'data' key (new backend format)
          if (prefsJson.containsKey('data') && prefsJson['data'] is Map) {
            prefsJson = SafeCast.toMap<String, dynamic>(prefsJson['data']);
            if (kDebugMode) debugPrint('📋 NotificationService: Unwrapped preferences from data key');
          }
          // Check if wrapped in 'preferences' key (legacy format)
          else if (prefsJson.containsKey('preferences') && prefsJson['preferences'] is Map) {
            prefsJson = SafeCast.toMap<String, dynamic>(prefsJson['preferences']);
            if (kDebugMode) debugPrint('📋 NotificationService: Unwrapped preferences from preferences key');
          }

          if (kDebugMode) debugPrint('📋 NotificationService: Parsed preferences from object');
        }

        if (prefsJson != null) {
          final prefs = NotificationPreferences.fromJson(prefsJson);
          if (kDebugMode) {
            debugPrint('✅ NotificationService: Got preferences');
            debugPrint('   - Channels: inApp=${prefs.channels.inApp}, push=${prefs.channels.push}, email=${prefs.channels.email}');
          }
          return ApiResponse<NotificationPreferences>(
            success: true,
            data: prefs,
          );
        }
      }

      // Return defaults if no preferences set
      if (kDebugMode) debugPrint('ℹ️ NotificationService: Using default preferences');
      return ApiResponse<NotificationPreferences>(
        success: true,
        data: NotificationPreferences(),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ NotificationService: Error getting preferences - $e');
      // Return defaults on error
      return ApiResponse<NotificationPreferences>(
        success: true,
        data: NotificationPreferences(),
      );
    }
  }

  /// Update notification preferences
  Future<ApiResponse<NotificationPreferences>> updatePreferences(
    NotificationPreferences prefs,
  ) async {
    try {
      if (kDebugMode) {
        debugPrint('🔔 NotificationService: Updating preferences');
        debugPrint('   - Payload: ${prefs.toJson()}');
      }

      final response = await _apiService.put(
        ApiConfig.notificationPreferences,
        body: prefs.toJson(),
      );

      if (response.success) {
        if (kDebugMode) debugPrint('✅ NotificationService: Preferences updated');

        // Parse response - handle different formats
        NotificationPreferences updatedPrefs = prefs;
        if (response.data != null) {
          Map<String, dynamic>? prefsJson;

          if (response.data is List) {
            final list = SafeCast.toList<dynamic>(response.data);
            if (list.isNotEmpty && list.first is Map) {
              prefsJson = SafeCast.toMap<String, dynamic>(list.first);
            }
          } else if (response.data is Map) {
            prefsJson = SafeCast.toMap<String, dynamic>(response.data);

            // Check if wrapped in 'data' key (new backend format)
            if (prefsJson.containsKey('data') && prefsJson['data'] is Map) {
              prefsJson = SafeCast.toMap<String, dynamic>(prefsJson['data']);
            }
            // Check if wrapped in 'preferences' key (legacy format)
            else if (prefsJson.containsKey('preferences') && prefsJson['preferences'] is Map) {
              prefsJson = SafeCast.toMap<String, dynamic>(prefsJson['preferences']);
            }
          }

          if (prefsJson != null) {
            updatedPrefs = NotificationPreferences.fromJson(prefsJson);
            if (kDebugMode) {
              debugPrint('   - Updated channels: inApp=${updatedPrefs.channels.inApp}, push=${updatedPrefs.channels.push}');
            }
          }
        }

        return ApiResponse<NotificationPreferences>(
          success: true,
          data: updatedPrefs,
        );
      }

      if (kDebugMode) debugPrint('❌ NotificationService: Update failed - ${response.message}');
      return ApiResponse<NotificationPreferences>(
        success: false,
        message: response.message ?? 'Failed to update preferences',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ NotificationService: Error updating preferences - $e');
      return ApiResponse<NotificationPreferences>(
        success: false,
        message: 'Error updating preferences: $e',
      );
    }
  }

  // =========================================================================
  // FCM DEVICE REGISTRATION
  // =========================================================================

  /// Register device for push notifications
  Future<ApiResponse<void>> registerDevice(DeviceRegistration registration) async {
    try {
      if (kDebugMode) {
        debugPrint('🔔 NotificationService: Registering device');
        debugPrint('   - Platform: ${registration.platform}');
        debugPrint('   - Device: ${registration.deviceName}');
      }

      final response = await _apiService.post(
        ApiConfig.notificationRegisterDevice,
        body: registration.toJson(),
      );

      if (response.success) {
        if (kDebugMode) debugPrint('✅ NotificationService: Device registered');
        return ApiResponse<void>(success: true);
      }

      return ApiResponse<void>(
        success: false,
        message: response.message ?? 'Failed to register device',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ NotificationService: Error registering device - $e');
      return ApiResponse<void>(
        success: false,
        message: 'Error registering device: $e',
      );
    }
  }

  /// Unregister device from push notifications
  /// Backend expects: DELETE /api/notifications/devices with body {"token": "..."}
  Future<ApiResponse<void>> unregisterDevice(String fcmToken) async {
    try {
      if (kDebugMode) debugPrint('🔔 NotificationService: Unregistering device');

      final response = await _apiService.delete(
        ApiConfig.notificationUnregisterDevice,
        body: {'token': fcmToken},  // Backend expects 'token' not 'fcm_token'
      );

      if (response.success) {
        if (kDebugMode) debugPrint('✅ NotificationService: Device unregistered');
        return ApiResponse<void>(success: true);
      }

      return ApiResponse<void>(
        success: false,
        message: response.message ?? 'Failed to unregister device',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ NotificationService: Error unregistering device - $e');
      return ApiResponse<void>(
        success: false,
        message: 'Error unregistering device: $e',
      );
    }
  }

  // =========================================================================
  // ADMIN FUNCTIONS
  // =========================================================================

  /// Send notification (Admin only)
  Future<ApiResponse<void>> sendNotification(SendNotificationRequest request) async {
    try {
      if (kDebugMode) {
        debugPrint('🔔 NotificationService: Sending notification (Admin)');
        debugPrint('   - Title: ${request.title}');
        debugPrint('   - Channels: ${request.channels}');
      }

      final response = await _apiService.post(
        ApiConfig.notificationSend,
        body: request.toJson(),
      );

      if (response.success) {
        if (kDebugMode) debugPrint('✅ NotificationService: Notification sent');
        return ApiResponse<void>(success: true);
      }

      return ApiResponse<void>(
        success: false,
        message: response.message ?? 'Failed to send notification',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ NotificationService: Error sending notification - $e');
      return ApiResponse<void>(
        success: false,
        message: 'Error sending notification: $e',
      );
    }
  }

  /// Get channel status (Admin only)
  Future<ApiResponse<List<NotificationChannel>>> getChannelStatus() async {
    try {
      if (kDebugMode) debugPrint('🔔 NotificationService: Getting channel status (Admin)');

      final response = await _apiService.get(ApiConfig.notificationChannels);

      if (response.success && response.data != null) {
        final channelsData = SafeCast.toList<dynamic>(response.data);
        final channels = channelsData
            .map((c) => NotificationChannel.fromJson(SafeCast.toMap<String, dynamic>(c)))
            .toList();
        if (kDebugMode) debugPrint('✅ NotificationService: Got ${channels.length} channels');
        return ApiResponse<List<NotificationChannel>>(
          success: true,
          data: channels,
        );
      }

      return ApiResponse<List<NotificationChannel>>(
        success: false,
        message: response.message ?? 'Failed to get channel status',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ NotificationService: Error getting channel status - $e');
      return ApiResponse<List<NotificationChannel>>(
        success: false,
        message: 'Error getting channel status: $e',
      );
    }
  }

  /// Test notification channel (Admin only)
  Future<ApiResponse<void>> testChannel(String channelName) async {
    try {
      if (kDebugMode) debugPrint('🔔 NotificationService: Testing channel - $channelName');

      final response = await _apiService.post(
        '${ApiConfig.notificationChannels}/$channelName/test',
        body: {},
      );

      if (response.success) {
        if (kDebugMode) debugPrint('✅ NotificationService: Channel test sent');
        return ApiResponse<void>(success: true);
      }

      return ApiResponse<void>(
        success: false,
        message: response.message ?? 'Failed to test channel',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ NotificationService: Error testing channel - $e');
      return ApiResponse<void>(
        success: false,
        message: 'Error testing channel: $e',
      );
    }
  }
}
