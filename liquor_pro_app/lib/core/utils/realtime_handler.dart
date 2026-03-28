import 'package:flutter/foundation.dart';
import '../services/websocket_service.dart';
import '../providers/websocket_provider.dart';
import 'app_logger.dart';

/// Real-time Event Handler
/// Provides utilities for providers to react to WebSocket events
class RealTimeHandler {
  /// Subscribe to inventory updates and refresh callback
  static void subscribeToInventoryUpdates(
    WebSocketProvider wsProvider,
    VoidCallback onUpdate,
  ) {
    wsProvider.subscribe(
      WebSocketChannels.inventory,
      onEvent: (event) {
        final eventType = event['event_type'] as String?;

        if (eventType == KafkaEventTypes.inventoryUpdated ||
            eventType == KafkaEventTypes.stockLow) {
          AppLogger.info('[RealTime] Inventory event received - triggering refresh');
          onUpdate();
        }
      },
    );
  }

  /// Subscribe to sales updates and refresh callback
  static void subscribeToSalesUpdates(
    WebSocketProvider wsProvider,
    VoidCallback onUpdate,
  ) {
    wsProvider.subscribe(
      WebSocketChannels.sales,
      onEvent: (event) {
        final eventType = event['event_type'] as String?;

        if (eventType == KafkaEventTypes.saleCreated ||
            eventType == KafkaEventTypes.saleUpdated) {
          AppLogger.info('[RealTime] Sales event received - triggering refresh');
          onUpdate();
        }
      },
    );
  }

  /// Subscribe to cashflow updates and refresh callback
  static void subscribeToCashflowUpdates(
    WebSocketProvider wsProvider,
    VoidCallback onUpdate,
  ) {
    wsProvider.subscribe(
      WebSocketChannels.cashflow,
      onEvent: (event) {
        final eventType = event['event_type'] as String?;

        if (eventType == KafkaEventTypes.paymentProcessed) {
          AppLogger.info('[RealTime] Cashflow event received - triggering refresh');
          onUpdate();
        }
      },
    );
  }

  /// Subscribe to dashboard updates and refresh callback
  static void subscribeToDashboardUpdates(
    WebSocketProvider wsProvider,
    VoidCallback onUpdate,
  ) {
    wsProvider.subscribe(
      WebSocketChannels.dashboard,
      onEvent: (event) {
        AppLogger.info('[RealTime] Dashboard event received - triggering refresh');
        onUpdate();
      },
    );
  }

  /// Subscribe to specific product stock updates
  static void subscribeToProductStock(
    WebSocketProvider wsProvider,
    String productId,
    Function(Map<String, dynamic>) onUpdate,
  ) {
    wsProvider.subscribe(
      WebSocketChannels.inventory,
      onEvent: (event) {
        final eventType = event['event_type'] as String?;
        final data = event['data'] as Map<String, dynamic>?;

        if (eventType == KafkaEventTypes.inventoryUpdated &&
            data?['product_id'] == productId) {
          AppLogger.info('[RealTime] Product $productId stock updated');
          onUpdate(data ?? {});
        }
      },
    );
  }

  /// Subscribe to low stock alerts
  static void subscribeToLowStockAlerts(
    WebSocketProvider wsProvider,
    Function(String productName, int quantity) onLowStock,
  ) {
    wsProvider.subscribe(
      WebSocketChannels.inventory,
      onEvent: (event) {
        final eventType = event['event_type'] as String?;
        final data = event['data'] as Map<String, dynamic>?;

        if (eventType == KafkaEventTypes.stockLow && data != null) {
          final productName = data['product_name'] as String? ?? 'Unknown';
          final quantity = data['quantity'] as int? ?? 0;

          AppLogger.warning('[RealTime] Low stock alert: $productName ($quantity)');
          onLowStock(productName, quantity);
        }
      },
    );
  }

  /// Subscribe to notifications
  static void subscribeToNotifications(
    WebSocketProvider wsProvider,
    Function(String message, String? type) onNotification,
  ) {
    wsProvider.registerEventHandler('notifications', (event) {
      final eventType = event['event_type'] as String?;
      final data = event['data'] as Map<String, dynamic>?;

      if (eventType == KafkaEventTypes.notificationSend && data != null) {
        final message = data['message'] as String? ?? '';
        final type = data['type'] as String?;

        AppLogger.info('[RealTime] Notification: $message');
        onNotification(message, type);
      }
    });
  }
}

/// Mixin for providers that need real-time updates
mixin RealTimeProviderMixin on ChangeNotifier {
  WebSocketProvider? _wsProvider;

  /// Initialize real-time updates
  void initializeRealTime(WebSocketProvider wsProvider) {
    _wsProvider = wsProvider;
    onRealTimeInitialized();
  }

  /// Override this to setup subscriptions
  void onRealTimeInitialized() {}

  /// Subscribe to a channel with automatic refresh
  void subscribeWithAutoRefresh(String channel, VoidCallback refreshCallback) {
    _wsProvider?.subscribe(
      channel,
      onEvent: (_) => refreshCallback(),
    );
  }

  /// Check if WebSocket is connected
  bool get isRealTimeConnected => _wsProvider?.isConnected ?? false;
}
