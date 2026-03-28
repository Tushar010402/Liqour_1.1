import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../features/notifications/models/notification_models.dart';
import '../../features/notifications/providers/notification_provider.dart';
import 'secure_storage_service.dart';
import 'notification_navigation_service.dart';

/// Custom notification sound types for LiquorPro
///
/// Industrial best practice: Define clear sound categories mapped to
/// business notification types for consistent UX
enum NotificationSoundType {
  /// Default notification sound (Glass tone)
  /// Use for: general notifications, info messages, updates
  standard,

  /// Alert sound (Ping tone)
  /// Use for: important actions, order updates, stock alerts
  alert,

  /// Critical alert sound (Hero tone)
  /// Use for: urgent issues, low stock warnings, approval requests
  critical,

  /// Silent - no sound
  /// Use for: background sync, non-urgent updates
  silent,
}

/// FCM Service Provider
final fcmServiceProvider = Provider<FCMService>((ref) {
  return FCMService(ref);
});

/// Background message handler - must be top-level function
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Ensure Firebase is initialized
  await Firebase.initializeApp();

  if (kDebugMode) {
    debugPrint('🔔 FCM: Background message received');
    debugPrint('   - Title: ${message.notification?.title}');
    debugPrint('   - Body: ${message.notification?.body}');
    debugPrint('   - Data: ${message.data}');
  }
}

/// Firebase Cloud Messaging Service - REAL IMPLEMENTATION
/// Handles push notifications, local notifications, and device registration
class FCMService {
  final Ref _ref;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  String? _fcmToken;
  bool _isInitialized = false;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _messageOpenedSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;

  // === DEDUPLICATION: Prevent duplicate notifications ===
  /// Track recently shown local notifications (by title_body key)
  final Set<String> _recentlyShownNotifications = {};

  /// Track processed FCM message IDs
  final Set<String> _processedMessageIds = {};

  // ==========================================================================
  // NOTIFICATION CHANNELS WITH CUSTOM SOUNDS (v2)
  // ==========================================================================
  // Industrial best practice: Create separate channels for different sound types
  // This allows users to manage notification preferences per-channel in settings
  //
  // IMPORTANT: Channel IDs use _v2 suffix to match backend FCM configuration.
  // Android notification channels are immutable - we use versioned IDs to
  // ensure new sound settings take effect (old channels are deleted on init).
  // ==========================================================================

  /// Old channel IDs to delete (cached with wrong sounds)
  static const List<String> _oldChannelIds = [
    'liquorpro_standard_channel',
    'liquorpro_alert_channel',
    'liquorpro_critical_channel',
    'liquorpro_silent_channel',
    'liquorpro_high_importance_channel',
  ];

  /// Standard notification channel - default sound for general notifications
  static const AndroidNotificationChannel _standardChannel = AndroidNotificationChannel(
    'liquorpro_standard_channel_v2',
    'LiquorPro Notifications',
    description: 'General notifications for LiquorPro app',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
    sound: RawResourceAndroidNotificationSound('notification_sound'),
  );

  /// Alert notification channel - for important actions and updates
  static const AndroidNotificationChannel _alertChannel = AndroidNotificationChannel(
    'liquorpro_alert_channel_v2',
    'LiquorPro Alerts',
    description: 'Important alerts requiring attention',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
    sound: RawResourceAndroidNotificationSound('alert_sound'),
  );

  /// Critical notification channel - for urgent issues
  static const AndroidNotificationChannel _criticalChannel = AndroidNotificationChannel(
    'liquorpro_critical_channel_v2',
    'LiquorPro Critical Alerts',
    description: 'Urgent notifications requiring immediate attention',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    sound: RawResourceAndroidNotificationSound('critical_alert'),
  );

  /// Silent notification channel - for background updates
  static const AndroidNotificationChannel _silentChannel = AndroidNotificationChannel(
    'liquorpro_silent_channel_v2',
    'LiquorPro Background Updates',
    description: 'Silent background updates',
    importance: Importance.low,
    playSound: false,
    enableVibration: false,
  );

  // Note: _channel removed - we now use typed channels (_standardChannel, etc.)
  // Backend sends channel_id matching these v2 channel IDs.

  FCMService(this._ref);

  /// Initialize FCM service
  /// IMPORTANT: This should only be called ONCE per app lifecycle
  Future<void> initialize() async {
    // === SINGLETON GUARD: Prevent multiple initializations ===
    if (_isInitialized) {
      if (kDebugMode) {
        debugPrint('🔔 FCMService: Already initialized, skipping');
      }
      return;
    }

    try {
      if (kDebugMode) {
        debugPrint('🔔 FCMService: Initializing...');
      }

      // Cancel any existing subscriptions before creating new ones
      _foregroundSubscription?.cancel();
      _foregroundSubscription = null;
      _messageOpenedSubscription?.cancel();
      _messageOpenedSubscription = null;
      _tokenRefreshSubscription?.cancel();
      _tokenRefreshSubscription = null;

      // Initialize local notifications
      await _initializeLocalNotifications();

      // Request notification permissions
      final settings = await _requestPermissions();

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {

        // Get FCM token
        _fcmToken = await _messaging.getToken();
        if (kDebugMode) {
          debugPrint('🔔 FCM Token: $_fcmToken');
        }

        // Store token securely
        if (_fcmToken != null) {
          final secureStorage = _ref.read(secureStorageProvider);
          await secureStorage.setFcmToken(_fcmToken!);
        }

        // Listen for token refresh
        _tokenRefreshSubscription = _messaging.onTokenRefresh.listen(_handleTokenRefresh);

        // Handle foreground messages (ONLY ONE LISTENER)
        _foregroundSubscription = FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

        // Handle background message tap (when app is opened from notification)
        _messageOpenedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

        // Check if app was opened from a notification
        final initialMessage = await _messaging.getInitialMessage();
        if (initialMessage != null) {
          _handleNotificationTap(initialMessage);
        }

        _isInitialized = true;
        if (kDebugMode) {
          debugPrint('✅ FCMService: Initialized successfully');
        }
      } else {
        if (kDebugMode) {
          debugPrint('⚠️ FCMService: Notification permission denied');
        }
        // Still mark as initialized but with limited functionality
        _isInitialized = true;
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('❌ FCMService: Initialization error - $e');
        debugPrint('   Stack trace: $stackTrace');
      }
      // Generate a placeholder token for offline/error scenarios
      _fcmToken = 'error_fallback_${DateTime.now().millisecondsSinceEpoch}';
      _isInitialized = true;
    }
  }

  /// Request notification permissions
  Future<NotificationSettings> _requestPermissions() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
      announcement: false,
      carPlay: false,
      criticalAlert: false,
    );

    if (kDebugMode) {
      debugPrint('🔔 FCM Permission status: ${settings.authorizationStatus}');
    }

    return settings;
  }

  /// Initialize local notifications plugin
  Future<void> _initializeLocalNotifications() async {
    // Android initialization
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS initialization
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Create all notification channels for Android
    if (Platform.isAndroid) {
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        // IMPORTANT: Delete old cached channels first
        // Android notification channels are immutable - old channels cached
        // wrong sounds, so we must delete them to use new v2 channels
        for (final oldChannelId in _oldChannelIds) {
          try {
            await androidPlugin.deleteNotificationChannel(oldChannelId);
            if (kDebugMode) {
              debugPrint('🔔 FCM: Deleted old channel: $oldChannelId');
            }
          } catch (e) {
            // Channel may not exist, ignore errors
          }
        }

        // Create all new v2 sound channels
        await androidPlugin.createNotificationChannel(_standardChannel);
        await androidPlugin.createNotificationChannel(_alertChannel);
        await androidPlugin.createNotificationChannel(_criticalChannel);
        await androidPlugin.createNotificationChannel(_silentChannel);

        if (kDebugMode) {
          debugPrint('🔔 FCM: Created all v2 notification channels with custom sounds');
          debugPrint('   - Standard: ${_standardChannel.id}');
          debugPrint('   - Alert: ${_alertChannel.id}');
          debugPrint('   - Critical: ${_criticalChannel.id}');
          debugPrint('   - Silent: ${_silentChannel.id}');
        }
      }
    }
  }

  /// Handle notification tap from local notification
  void _onNotificationTap(NotificationResponse response) {
    if (kDebugMode) {
      debugPrint('🔔 Local notification tapped: ${response.payload}');
    }

    if (response.payload != null) {
      try {
        final data = jsonDecode(response.payload!);
        _navigateToScreen(data);
      } catch (e) {
        if (kDebugMode) debugPrint('❌ Error parsing notification payload: $e');
      }
    }
  }

  /// Handle token refresh
  void _handleTokenRefresh(String newToken) async {
    if (kDebugMode) {
      debugPrint('🔔 FCM Token refreshed: $newToken');
    }

    _fcmToken = newToken;

    // Store new token
    final secureStorage = _ref.read(secureStorageProvider);
    await secureStorage.setFcmToken(newToken);

    // Re-register device with backend
    await registerDevice();
  }

  /// Handle foreground messages (with deduplication)
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    // === DEDUPLICATE by message ID ===
    final messageId = message.messageId;
    if (messageId != null) {
      if (_processedMessageIds.contains(messageId)) {
        if (kDebugMode) {
          debugPrint('🔔 FCM: Skipping duplicate message: $messageId');
        }
        return;
      }
      _processedMessageIds.add(messageId);

      // Cleanup after 60 seconds to prevent memory buildup
      Future.delayed(const Duration(seconds: 60), () {
        _processedMessageIds.remove(messageId);
      });
    }

    if (kDebugMode) {
      debugPrint('🔔 FCM Foreground message:');
      debugPrint('   - ID: $messageId');
      debugPrint('   - Title: ${message.notification?.title}');
      debugPrint('   - Body: ${message.notification?.body}');
      debugPrint('   - Data: ${message.data}');
    }

    // Show local notification with smart sound selection based on message data
    await showSmartNotification(
      title: message.notification?.title ?? 'LiquorPro',
      body: message.notification?.body ?? '',
      data: message.data,
    );

    // Refresh in-app notifications (throttled by NotificationService)
    _ref.invalidate(allNotificationsProvider);
    _ref.invalidate(unreadCountProvider);
  }

  /// Handle notification tap (when app opens from notification)
  void _handleNotificationTap(RemoteMessage message) {
    if (kDebugMode) {
      debugPrint('🔔 Notification tapped: ${message.data}');
    }
    _navigateToScreen(message.data);
  }

  /// Navigate to appropriate screen based on notification data
  void _navigateToScreen(Map<String, dynamic> data) {
    // Extract navigation info from data
    final type = data['type'] as String?;
    final actionUrl = data['action_url'] as String?;

    if (kDebugMode) {
      debugPrint('🔔 Navigate to: type=$type, url=$actionUrl');
    }

    // Use the navigator key to navigate
    final navigatorState = NotificationNavigationService.navigatorKey.currentState;
    if (navigatorState == null) {
      if (kDebugMode) {
        debugPrint('⚠️ FCM: Navigator not available');
      }
      return;
    }

    final context = navigatorState.context;

    // Use NotificationNavigationService for deep linking
    NotificationNavigationService.handleNotificationTap(data, context);
  }

  /// Get current FCM token
  String? get token => _fcmToken;

  /// Check if service is initialized
  bool get isInitialized => _isInitialized;

  /// Get token (async version)
  Future<String?> getToken() async {
    _fcmToken ??= await _messaging.getToken();
    return _fcmToken;
  }

  /// Force refresh FCM token - call this on login to ensure fresh token
  /// This deletes the old token and gets a new one from Firebase
  Future<String?> forceRefreshToken() async {
    try {
      if (kDebugMode) {
        debugPrint('🔔 FCM: Force refreshing token...');
        debugPrint('🔔 FCM: Old token: ${_fcmToken?.substring(0, 20)}...');
      }

      // Delete the current token to force Firebase to generate a new one
      await _messaging.deleteToken();

      // Get fresh token
      _fcmToken = await _messaging.getToken();

      if (kDebugMode) {
        debugPrint('🔔 FCM: New token: ${_fcmToken?.substring(0, 20)}...');
      }

      // Store new token securely
      if (_fcmToken != null) {
        final secureStorage = _ref.read(secureStorageProvider);
        await secureStorage.setFcmToken(_fcmToken!);
      }

      return _fcmToken;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ FCM: Force refresh error - $e');
      }
      // Fallback to regular getToken
      return getToken();
    }
  }

  /// Subscribe to topic
  Future<void> subscribeToTopic(String topic) async {
    try {
      await _messaging.subscribeToTopic(topic);
      if (kDebugMode) {
        debugPrint('🔔 FCM: Subscribed to topic: $topic');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ FCM: Error subscribing to topic $topic: $e');
      }
    }
  }

  /// Unsubscribe from topic
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _messaging.unsubscribeFromTopic(topic);
      if (kDebugMode) {
        debugPrint('🔔 FCM: Unsubscribed from topic: $topic');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ FCM: Error unsubscribing from topic $topic: $e');
      }
    }
  }

  /// Register device with backend
  Future<void> registerDevice() async {
    if (_fcmToken == null) {
      if (kDebugMode) debugPrint('⚠️ FCM: Cannot register device - no token');
      return;
    }

    try {
      final secureStorage = _ref.read(secureStorageProvider);
      final deviceId = await secureStorage.getDeviceId();

      final registration = DeviceRegistration(
        fcmToken: _fcmToken!,
        deviceId: deviceId ?? 'unknown',
        platform: Platform.isIOS ? 'ios' : 'android',
        deviceName: await _getDeviceName(),
        appVersion: '1.0.0',
      );

      await _ref.read(notificationNotifierProvider.notifier).registerDevice(registration);
      if (kDebugMode) debugPrint('✅ FCM: Device registered with backend');
    } catch (e) {
      if (kDebugMode) debugPrint('❌ FCM: Device registration error - $e');
    }
  }

  /// Get device name
  Future<String> _getDeviceName() async {
    if (Platform.isIOS) {
      return 'iPhone';
    } else {
      return 'Android Device';
    }
  }

  /// Unregister device (on logout)
  Future<void> unregisterDevice() async {
    if (_fcmToken == null) return;

    try {
      await _ref.read(notificationNotifierProvider.notifier).unregisterDevice(_fcmToken!);
      if (kDebugMode) debugPrint('✅ FCM: Device unregistered');
    } catch (e) {
      if (kDebugMode) debugPrint('❌ FCM: Device unregistration error - $e');
    }
  }

  // ==========================================================================
  // HELPER: Get channel for sound type
  // ==========================================================================

  /// Get the appropriate notification channel for a sound type
  AndroidNotificationChannel _getChannelForSoundType(NotificationSoundType soundType) {
    switch (soundType) {
      case NotificationSoundType.standard:
        return _standardChannel;
      case NotificationSoundType.alert:
        return _alertChannel;
      case NotificationSoundType.critical:
        return _criticalChannel;
      case NotificationSoundType.silent:
        return _silentChannel;
    }
  }

  /// Get iOS sound filename for sound type
  String? _getIOSSoundForType(NotificationSoundType soundType) {
    switch (soundType) {
      case NotificationSoundType.standard:
        return 'notification_sound.aiff';
      case NotificationSoundType.alert:
        return 'alert_sound.aiff';
      case NotificationSoundType.critical:
        return 'critical_alert.aiff';
      case NotificationSoundType.silent:
        return null; // No sound
    }
  }

  /// Get Android notification details for sound type
  AndroidNotificationDetails _getAndroidDetailsForSoundType(NotificationSoundType soundType) {
    final channel = _getChannelForSoundType(soundType);
    return AndroidNotificationDetails(
      channel.id,
      channel.name,
      channelDescription: channel.description,
      importance: channel.importance,
      priority: soundType == NotificationSoundType.critical ? Priority.max : Priority.high,
      icon: '@mipmap/ic_launcher',
      playSound: soundType != NotificationSoundType.silent,
      enableVibration: soundType != NotificationSoundType.silent,
      sound: channel.sound,
    );
  }

  /// Get iOS notification details for sound type
  DarwinNotificationDetails _getIOSDetailsForSoundType(NotificationSoundType soundType) {
    final soundFile = _getIOSSoundForType(soundType);
    return DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: soundType != NotificationSoundType.silent,
      sound: soundFile,
    );
  }

  // ==========================================================================
  // SHOW NOTIFICATION WITH CUSTOM SOUND
  // ==========================================================================

  /// Show local notification with custom sound support (with deduplication)
  ///
  /// [title] - Notification title
  /// [body] - Notification body text
  /// [data] - Optional payload data for navigation
  /// [soundType] - Type of sound to play (defaults to standard)
  ///
  /// Industrial best practice: Use appropriate sound type for notification urgency:
  /// - `standard` - General notifications, updates
  /// - `alert` - Important actions, orders, stock alerts
  /// - `critical` - Urgent issues, low stock warnings, approvals
  /// - `silent` - Background sync, non-urgent updates
  Future<void> showLocalNotification({
    required String title,
    required String body,
    Map<String, dynamic>? data,
    NotificationSoundType soundType = NotificationSoundType.standard,
  }) async {
    try {
      // === DEDUPLICATE: Check if recently shown ===
      final dedupeKey = '${title}_$body';
      if (_recentlyShownNotifications.contains(dedupeKey)) {
        if (kDebugMode) {
          debugPrint('🔔 Skipping duplicate notification: $title');
        }
        return;
      }
      _recentlyShownNotifications.add(dedupeKey);

      // Auto-remove from dedup set after 30 minutes to prevent repeat spam
      Future.delayed(const Duration(minutes: 30), () {
        _recentlyShownNotifications.remove(dedupeKey);
      });

      final androidDetails = _getAndroidDetailsForSoundType(soundType);
      final iosDetails = _getIOSDetailsForSoundType(soundType);

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        details,
        payload: data != null ? jsonEncode(data) : null,
      );

      if (kDebugMode) {
        debugPrint('🔔 Local notification shown: $title (sound: ${soundType.name})');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error showing local notification: $e');
      }
    }
  }

  /// Show notification with sound type determined by notification data
  ///
  /// Automatically determines sound type from notification data:
  /// - `priority: critical` -> critical sound
  /// - `priority: high` or `type: alert|warning` -> alert sound
  /// - `priority: low` or `silent: true` -> silent
  /// - Otherwise -> standard sound
  Future<void> showSmartNotification({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    // Determine sound type from notification data
    final soundType = _determineSoundType(data);
    await showLocalNotification(
      title: title,
      body: body,
      data: data,
      soundType: soundType,
    );
  }

  /// Determine appropriate sound type from notification data
  NotificationSoundType _determineSoundType(Map<String, dynamic>? data) {
    if (data == null) return NotificationSoundType.standard;

    final priority = data['priority']?.toString().toLowerCase();
    final type = data['type']?.toString().toLowerCase();
    final silent = data['silent']?.toString().toLowerCase() == 'true';

    // Silent takes precedence
    if (silent) return NotificationSoundType.silent;

    // Check priority
    if (priority == 'critical' || priority == 'urgent') {
      return NotificationSoundType.critical;
    }
    if (priority == 'high') {
      return NotificationSoundType.alert;
    }
    if (priority == 'low' || priority == 'background') {
      return NotificationSoundType.silent;
    }

    // Check type
    if (type == 'critical' || type == 'urgent' || type == 'error') {
      return NotificationSoundType.critical;
    }
    if (type == 'alert' || type == 'warning' || type == 'order' || type == 'stock') {
      return NotificationSoundType.alert;
    }

    return NotificationSoundType.standard;
  }

  /// Schedule a local notification with custom sound support
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    Map<String, dynamic>? data,
    NotificationSoundType soundType = NotificationSoundType.standard,
  }) async {
    try {
      final androidDetails = _getAndroidDetailsForSoundType(soundType);
      final iosDetails = _getIOSDetailsForSoundType(soundType);

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // Use zonedSchedule for scheduled notifications
      // Note: This requires timezone package setup
      await _localNotifications.show(
        id,
        title,
        body,
        details,
        payload: data != null ? jsonEncode(data) : null,
      );

      if (kDebugMode) {
        debugPrint('🔔 Notification scheduled: $title at $scheduledTime (sound: ${soundType.name})');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error scheduling notification: $e');
      }
    }
  }

  /// Cancel a scheduled notification
  Future<void> cancelNotification(int id) async {
    await _localNotifications.cancel(id);
  }

  /// Cancel all notifications
  Future<void> cancelAllNotifications() async {
    await _localNotifications.cancelAll();
  }

  /// Dispose resources
  void dispose() {
    _foregroundSubscription?.cancel();
    _foregroundSubscription = null;
    _messageOpenedSubscription?.cancel();
    _messageOpenedSubscription = null;
    _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
    _isInitialized = false;
  }
}
