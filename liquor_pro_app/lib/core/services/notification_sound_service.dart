import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'fcm_service.dart';

/// Notification Sound Service Provider
final notificationSoundServiceProvider = Provider<NotificationSoundService>((ref) {
  return NotificationSoundService(ref);
});

/// ============================================================================
/// NOTIFICATION SOUND SERVICE
/// ============================================================================
/// A helper service for managing and testing custom notification sounds.
///
/// This service provides:
/// 1. Easy-to-use methods for triggering notifications with specific sounds
/// 2. Predefined notification templates for common business scenarios
/// 3. Test methods for verifying sound configuration
///
/// Industrial Best Practices:
/// - Separate sound channels for different urgency levels
/// - Consistent sound mapping across iOS and Android
/// - User-configurable sound preferences (future enhancement)
/// ============================================================================
class NotificationSoundService {
  final Ref _ref;

  NotificationSoundService(this._ref);

  FCMService get _fcmService => _ref.read(fcmServiceProvider);

  // ==========================================================================
  // BUSINESS NOTIFICATION METHODS
  // ==========================================================================

  /// Show a general information notification (standard sound)
  Future<void> showInfoNotification({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    await _fcmService.showLocalNotification(
      title: title,
      body: body,
      data: data,
      soundType: NotificationSoundType.standard,
    );
  }

  /// Show an order notification (alert sound)
  Future<void> showOrderNotification({
    required String orderId,
    required String message,
    Map<String, dynamic>? data,
  }) async {
    await _fcmService.showLocalNotification(
      title: 'New Order #$orderId',
      body: message,
      data: {
        'type': 'order',
        'order_id': orderId,
        ...?data,
      },
      soundType: NotificationSoundType.alert,
    );
  }

  /// Show a stock alert notification (alert sound)
  Future<void> showStockAlertNotification({
    required String productName,
    required int currentStock,
    required int threshold,
    Map<String, dynamic>? data,
  }) async {
    await _fcmService.showLocalNotification(
      title: 'Low Stock Alert',
      body: '$productName is running low ($currentStock remaining)',
      data: {
        'type': 'stock',
        'product_name': productName,
        'current_stock': currentStock,
        'threshold': threshold,
        ...?data,
      },
      soundType: NotificationSoundType.alert,
    );
  }

  /// Show a critical stock alert (critical sound)
  Future<void> showCriticalStockNotification({
    required String productName,
    required int currentStock,
    Map<String, dynamic>? data,
  }) async {
    await _fcmService.showLocalNotification(
      title: 'Critical Stock Warning',
      body: '$productName is critically low! Only $currentStock left.',
      data: {
        'type': 'critical',
        'priority': 'critical',
        'product_name': productName,
        'current_stock': currentStock,
        ...?data,
      },
      soundType: NotificationSoundType.critical,
    );
  }

  /// Show an approval request notification (critical sound)
  Future<void> showApprovalNotification({
    required String requestType,
    required String requesterName,
    required String requestId,
    Map<String, dynamic>? data,
  }) async {
    await _fcmService.showLocalNotification(
      title: 'Approval Required',
      body: '$requesterName needs approval for $requestType',
      data: {
        'type': 'approval',
        'priority': 'critical',
        'request_type': requestType,
        'request_id': requestId,
        ...?data,
      },
      soundType: NotificationSoundType.critical,
    );
  }

  /// Show a cash request approval notification (critical sound)
  Future<void> showCashRequestNotification({
    required double amount,
    required String shopName,
    required String requestId,
    Map<String, dynamic>? data,
  }) async {
    await _fcmService.showLocalNotification(
      title: 'Cash Request Pending',
      body: '$shopName requested \u20B9${amount.toStringAsFixed(0)} approval',
      data: {
        'type': 'cash_request',
        'priority': 'critical',
        'amount': amount,
        'shop_name': shopName,
        'request_id': requestId,
        ...?data,
      },
      soundType: NotificationSoundType.critical,
    );
  }

  /// Show a daily sales reminder notification (alert sound)
  Future<void> showDailySalesReminder({
    required String shopName,
    Map<String, dynamic>? data,
  }) async {
    await _fcmService.showLocalNotification(
      title: 'Daily Sales Reminder',
      body: 'Don\'t forget to submit daily sales for $shopName',
      data: {
        'type': 'reminder',
        'shop_name': shopName,
        ...?data,
      },
      soundType: NotificationSoundType.alert,
    );
  }

  /// Show a sync notification (silent)
  Future<void> showSyncNotification({
    required String message,
    Map<String, dynamic>? data,
  }) async {
    await _fcmService.showLocalNotification(
      title: 'Sync Complete',
      body: message,
      data: {
        'type': 'sync',
        'silent': 'true',
        ...?data,
      },
      soundType: NotificationSoundType.silent,
    );
  }

  // ==========================================================================
  // TEST METHODS - For verifying sound configuration
  // ==========================================================================

  /// Test all notification sounds
  ///
  /// Sends 4 test notifications with 3-second delay between each:
  /// 1. Standard sound
  /// 2. Alert sound
  /// 3. Critical sound
  /// 4. Silent notification
  Future<void> testAllSounds() async {
    if (kDebugMode) {
      debugPrint('🔔 [NotificationSoundService] Testing all notification sounds...');
    }

    // Test standard sound
    await _fcmService.showLocalNotification(
      title: 'Test: Standard Sound',
      body: 'This is the default notification sound (Glass)',
      data: {'test': 'standard'},
      soundType: NotificationSoundType.standard,
    );

    await Future.delayed(const Duration(seconds: 3));

    // Test alert sound
    await _fcmService.showLocalNotification(
      title: 'Test: Alert Sound',
      body: 'This is the alert notification sound (Ping)',
      data: {'test': 'alert'},
      soundType: NotificationSoundType.alert,
    );

    await Future.delayed(const Duration(seconds: 3));

    // Test critical sound
    await _fcmService.showLocalNotification(
      title: 'Test: Critical Sound',
      body: 'This is the critical notification sound (Hero)',
      data: {'test': 'critical'},
      soundType: NotificationSoundType.critical,
    );

    await Future.delayed(const Duration(seconds: 3));

    // Test silent
    await _fcmService.showLocalNotification(
      title: 'Test: Silent Notification',
      body: 'This notification has no sound',
      data: {'test': 'silent'},
      soundType: NotificationSoundType.silent,
    );

    if (kDebugMode) {
      debugPrint('🔔 [NotificationSoundService] All sound tests complete!');
    }
  }

  /// Test a specific sound type
  Future<void> testSound(NotificationSoundType soundType) async {
    final soundNames = {
      NotificationSoundType.standard: 'Standard (Glass)',
      NotificationSoundType.alert: 'Alert (Ping)',
      NotificationSoundType.critical: 'Critical (Hero)',
      NotificationSoundType.silent: 'Silent',
    };

    await _fcmService.showLocalNotification(
      title: 'Sound Test',
      body: 'Playing: ${soundNames[soundType]}',
      data: {'test': soundType.name},
      soundType: soundType,
    );
  }

  /// Test smart notification sound detection
  Future<void> testSmartSoundDetection() async {
    if (kDebugMode) {
      debugPrint('🔔 [NotificationSoundService] Testing smart sound detection...');
    }

    // Test with priority: critical
    await _fcmService.showSmartNotification(
      title: 'Smart Test 1',
      body: 'Testing priority: critical',
      data: {'priority': 'critical'},
    );

    await Future.delayed(const Duration(seconds: 3));

    // Test with type: order
    await _fcmService.showSmartNotification(
      title: 'Smart Test 2',
      body: 'Testing type: order',
      data: {'type': 'order'},
    );

    await Future.delayed(const Duration(seconds: 3));

    // Test with silent: true
    await _fcmService.showSmartNotification(
      title: 'Smart Test 3',
      body: 'Testing silent: true',
      data: {'silent': 'true'},
    );

    if (kDebugMode) {
      debugPrint('🔔 [NotificationSoundService] Smart detection tests complete!');
    }
  }
}

// =============================================================================
// EXTENSION: Notification Type Mapping
// =============================================================================
/// Extension providing convenient mapping from business notification types
/// to sound types for backend integration
extension NotificationTypeMapping on String {
  /// Map backend notification type to sound type
  NotificationSoundType toSoundType() {
    switch (toLowerCase()) {
      // Critical sounds
      case 'critical':
      case 'urgent':
      case 'error':
      case 'approval':
      case 'cash_request':
      case 'low_stock_critical':
        return NotificationSoundType.critical;

      // Alert sounds
      case 'alert':
      case 'warning':
      case 'order':
      case 'stock':
      case 'low_stock':
      case 'reminder':
      case 'payment':
        return NotificationSoundType.alert;

      // Silent
      case 'sync':
      case 'background':
      case 'silent':
        return NotificationSoundType.silent;

      // Standard (default)
      default:
        return NotificationSoundType.standard;
    }
  }
}
