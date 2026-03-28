import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/service_providers.dart';
import '../models/notification_models.dart';
import '../services/notification_service.dart';

// ============================================================================
// SERVICE PROVIDER
// ============================================================================

/// Provider for the NotificationService
final notificationServiceProvider = Provider<NotificationService>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  return NotificationService(apiService);
});

// ============================================================================
// NOTIFICATION PROVIDERS
// ============================================================================

/// Query object for fetching notifications
class NotificationQuery {
  final String? type;
  final bool? unreadOnly;
  final int limit;
  final int offset;

  const NotificationQuery({
    this.type,
    this.unreadOnly,
    this.limit = 50,
    this.offset = 0,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NotificationQuery &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          unreadOnly == other.unreadOnly &&
          limit == other.limit &&
          offset == other.offset;

  @override
  int get hashCode =>
      type.hashCode ^ unreadOnly.hashCode ^ limit.hashCode ^ offset.hashCode;

  NotificationQuery copyWith({
    String? type,
    bool? unreadOnly,
    int? limit,
    int? offset,
  }) {
    return NotificationQuery(
      type: type ?? this.type,
      unreadOnly: unreadOnly ?? this.unreadOnly,
      limit: limit ?? this.limit,
      offset: offset ?? this.offset,
    );
  }
}

/// Provider for notifications list
final notificationsProvider = FutureProvider.family<NotificationListResponse, NotificationQuery>(
  (ref, query) async {
    final service = ref.watch(notificationServiceProvider);
    final response = await service.getNotifications(
      type: query.type,
      unreadOnly: query.unreadOnly,
      limit: query.limit,
      offset: query.offset,
    );
    if (response.success && response.data != null) {
      return response.data!;
    }
    throw Exception(response.message ?? 'Failed to fetch notifications');
  },
);

/// Provider for all notifications (shorthand)
final allNotificationsProvider = FutureProvider<NotificationListResponse>((ref) async {
  return ref.watch(notificationsProvider(const NotificationQuery()).future);
});

/// Provider for unread count
/// Falls back to counting from notifications list if dedicated endpoint fails
final unreadCountProvider = FutureProvider<int>((ref) async {
  final service = ref.watch(notificationServiceProvider);

  // Try dedicated unread count endpoint first
  final response = await service.getUnreadCount();
  if (response.success && response.data != null) {
    return response.data!;
  }

  // Fallback: Get unread count from notifications list response
  if (kDebugMode) {
    debugPrint('🔔 [UnreadCount] Falling back to notifications list for unread count');
  }

  try {
    final notifResponse = await service.getNotifications(limit: 1, offset: 0);
    if (notifResponse.success && notifResponse.data != null) {
      final count = notifResponse.data!.unreadCount;
      if (kDebugMode) {
        debugPrint('🔔 [UnreadCount] Got unread count from list: $count');
      }
      return count;
    }
  } catch (e) {
    if (kDebugMode) {
      debugPrint('❌ [UnreadCount] Error getting fallback count: $e');
    }
  }

  return 0;
});

/// Provider for notification preferences
final notificationPrefsProvider = FutureProvider<NotificationPreferences>((ref) async {
  final service = ref.watch(notificationServiceProvider);
  final response = await service.getPreferences();
  if (response.success && response.data != null) {
    return response.data!;
  }
  return NotificationPreferences(); // Return defaults
});

/// Provider for channel status (Admin only)
final channelStatusProvider = FutureProvider<List<NotificationChannel>>((ref) async {
  final service = ref.watch(notificationServiceProvider);
  final response = await service.getChannelStatus();
  if (response.success && response.data != null) {
    return response.data!;
  }
  return [];
});

// ============================================================================
// NOTIFICATION NOTIFIER (MUTATIONS)
// ============================================================================

/// StateNotifier for notification mutations
class NotificationNotifier extends StateNotifier<AsyncValue<void>> {
  final NotificationService _service;
  final Ref _ref;

  NotificationNotifier(this._service, this._ref) : super(const AsyncValue.data(null));

  /// Mark a notification as read
  Future<bool> markAsRead(String notificationId) async {
    state = const AsyncValue.loading();
    try {
      final response = await _service.markAsRead(notificationId);
      if (response.success) {
        _invalidateAll();
        state = const AsyncValue.data(null);
        return true;
      }
      state = AsyncValue.error(response.message ?? 'Failed', StackTrace.current);
      return false;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// Mark all notifications as read
  Future<bool> markAllAsRead() async {
    state = const AsyncValue.loading();
    try {
      final response = await _service.markAllAsRead();
      if (response.success) {
        _invalidateAll();
        state = const AsyncValue.data(null);
        return true;
      }
      state = AsyncValue.error(response.message ?? 'Failed', StackTrace.current);
      return false;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// Delete a notification
  Future<bool> deleteNotification(String notificationId) async {
    state = const AsyncValue.loading();
    try {
      final response = await _service.deleteNotification(notificationId);
      if (response.success) {
        _invalidateAll();
        state = const AsyncValue.data(null);
        return true;
      }
      state = AsyncValue.error(response.message ?? 'Failed', StackTrace.current);
      return false;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// Clear all notifications
  Future<bool> clearAll() async {
    state = const AsyncValue.loading();
    try {
      final response = await _service.clearAll();
      if (response.success) {
        _invalidateAll();
        state = const AsyncValue.data(null);
        return true;
      }
      state = AsyncValue.error(response.message ?? 'Failed', StackTrace.current);
      return false;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// Update notification preferences
  Future<bool> updatePreferences(NotificationPreferences prefs) async {
    state = const AsyncValue.loading();
    try {
      final response = await _service.updatePreferences(prefs);
      if (response.success) {
        _ref.invalidate(notificationPrefsProvider);
        state = const AsyncValue.data(null);
        return true;
      }
      state = AsyncValue.error(response.message ?? 'Failed', StackTrace.current);
      return false;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// Register device for push notifications
  Future<bool> registerDevice(DeviceRegistration registration) async {
    try {
      final response = await _service.registerDevice(registration);
      return response.success;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ NotificationNotifier: Error registering device - $e');
      return false;
    }
  }

  /// Unregister device from push notifications
  Future<bool> unregisterDevice(String fcmToken) async {
    try {
      final response = await _service.unregisterDevice(fcmToken);
      return response.success;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ NotificationNotifier: Error unregistering device - $e');
      return false;
    }
  }

  /// Send notification (Admin only)
  Future<bool> sendNotification(SendNotificationRequest request) async {
    state = const AsyncValue.loading();
    try {
      final response = await _service.sendNotification(request);
      if (response.success) {
        state = const AsyncValue.data(null);
        return true;
      }
      state = AsyncValue.error(response.message ?? 'Failed', StackTrace.current);
      return false;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// Test notification channel (Admin only)
  Future<bool> testChannel(String channelName) async {
    try {
      final response = await _service.testChannel(channelName);
      if (response.success) {
        _ref.invalidate(channelStatusProvider);
        return true;
      }
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ NotificationNotifier: Error testing channel - $e');
      return false;
    }
  }

  /// Refresh notifications
  void refresh() {
    _invalidateAll();
  }

  void _invalidateAll() {
    _ref.invalidate(allNotificationsProvider);
    _ref.invalidate(unreadCountProvider);
  }
}

/// Provider for notification mutations
final notificationNotifierProvider =
    StateNotifierProvider<NotificationNotifier, AsyncValue<void>>((ref) {
  final service = ref.watch(notificationServiceProvider);
  return NotificationNotifier(service, ref);
});

// ============================================================================
// LOCAL STATE PROVIDERS (UI STATE)
// ============================================================================

/// Selected notification filter type
final selectedNotificationFilterProvider = StateProvider<String?>((ref) => null);

/// Show only unread toggle
final showOnlyUnreadProvider = StateProvider<bool>((ref) => false);

/// Current page for pagination
final notificationPageProvider = StateProvider<int>((ref) => 0);

/// Computed notifications query from UI state
final activeNotificationQueryProvider = Provider<NotificationQuery>((ref) {
  final filter = ref.watch(selectedNotificationFilterProvider);
  final unreadOnly = ref.watch(showOnlyUnreadProvider);
  final page = ref.watch(notificationPageProvider);

  return NotificationQuery(
    type: filter,
    unreadOnly: unreadOnly ? true : null,
    limit: 20,
    offset: page * 20,
  );
});

/// Active notifications based on current query
final activeNotificationsProvider = FutureProvider<NotificationListResponse>((ref) {
  final query = ref.watch(activeNotificationQueryProvider);
  return ref.watch(notificationsProvider(query).future);
});

// ============================================================================
// HELPER EXTENSIONS
// ============================================================================

extension NotificationListResponseX on NotificationListResponse {
  /// Get notifications grouped by date
  Map<String, List<AppNotification>> get groupedByDate {
    final grouped = <String, List<AppNotification>>{};
    for (final notification in notifications) {
      final date = _formatDate(notification.createdAt);
      grouped.putIfAbsent(date, () => []).add(notification);
    }
    return grouped;
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final notificationDate = DateTime(date.year, date.month, date.day);

    if (notificationDate == today) {
      return 'Today';
    } else if (notificationDate == yesterday) {
      return 'Yesterday';
    } else if (now.difference(notificationDate).inDays < 7) {
      const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
      return days[date.weekday % 7];
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}
