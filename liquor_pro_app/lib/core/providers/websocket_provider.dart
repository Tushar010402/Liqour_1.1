import 'package:flutter/foundation.dart';
import 'dart:async';
import '../services/websocket_service.dart';
import '../services/auth_service.dart';
import '../utils/app_logger.dart';
import '../utils/jwt_utils.dart';

/// WebSocket Provider - Manages WebSocket connection and real-time events
class WebSocketProvider extends ChangeNotifier {
  final WebSocketService _wsService;
  final AuthService _authService;

  StreamSubscription? _eventSubscription;
  StreamSubscription? _connectionSubscription;

  bool _isConnected = false;
  Map<String, dynamic>? _lastEvent;
  final List<String> _subscribedChannels = [];

  // Event handlers by channel
  final Map<String, List<Function(Map<String, dynamic>)>> _eventHandlers = {};

  WebSocketProvider({
    required WebSocketService wsService,
    required AuthService authService,
  })  : _wsService = wsService,
        _authService = authService {
    _initialize();
  }

  // Getters
  bool get isConnected => _isConnected;
  Map<String, dynamic>? get lastEvent => _lastEvent;
  List<String> get subscribedChannels => _subscribedChannels;

  /// Initialize WebSocket listeners
  void _initialize() {
    // Initialize WebSocketService with auth support
    _wsService.initialize(
      authService: _authService,
      onAuthRequired: () {
        AppLogger.warning('🔐 [WebSocketProvider] Authentication expired - re-login required');
        // This will trigger logout and navigation to login screen
        // The actual logout is handled by DioApiService's onSessionExpired callback
        _authService.logout();
      },
    );

    // Listen to connection status changes
    _connectionSubscription = _wsService.connectionStatus.listen((connected) {
      _isConnected = connected;
      notifyListeners();

      if (connected) {
        AppLogger.info('✅ [WebSocketProvider] Connected to real-time updates');
        _resubscribeToChannels();
      } else {
        AppLogger.warning('⚠️ [WebSocketProvider] Disconnected from real-time updates');
      }
    });

    // Listen to incoming events
    _eventSubscription = _wsService.events.listen((event) {
      _lastEvent = event;
      _handleEvent(event);
      notifyListeners();
    });
  }

  /// Connect to WebSocket server
  Future<void> connect() async {
    try {
      final token = await _authService.getToken();
      final tenantId = await _authService.getTenantId();

      if (token == null) {
        AppLogger.warning('[WebSocketProvider] Cannot connect - no auth token');
        return;
      }

      // Check if token is expired before attempting connection
      if (JwtUtils.isTokenExpired(token)) {
        AppLogger.warning('[WebSocketProvider] Token is expired - triggering re-authentication');
        await _authService.logout();
        return;
      }

      AppLogger.info('[WebSocketProvider] Connecting to WebSocket...');
      await _wsService.connect(token: token, tenantId: tenantId);
    } catch (e) {
      AppLogger.error('[WebSocketProvider] Connection failed: $e');
    }
  }

  /// Disconnect from WebSocket server
  Future<void> disconnect() async {
    AppLogger.info('[WebSocketProvider] Disconnecting from WebSocket...');
    _subscribedChannels.clear();
    await _wsService.disconnect();
  }

  /// Subscribe to a channel
  void subscribe(String channel, {Function(Map<String, dynamic>)? onEvent}) {
    if (!_subscribedChannels.contains(channel)) {
      _wsService.subscribe(channel);
      _subscribedChannels.add(channel);
      AppLogger.info('[WebSocketProvider] Subscribed to channel: $channel');
    }

    // Register event handler if provided
    if (onEvent != null) {
      registerEventHandler(channel, onEvent);
    }

    notifyListeners();
  }

  /// Unsubscribe from a channel
  void unsubscribe(String channel) {
    if (_subscribedChannels.contains(channel)) {
      _wsService.unsubscribe(channel);
      _subscribedChannels.remove(channel);
      _eventHandlers.remove(channel);
      AppLogger.info('[WebSocketProvider] Unsubscribed from channel: $channel');
      notifyListeners();
    }
  }

  /// Register event handler for a specific channel
  void registerEventHandler(String channel, Function(Map<String, dynamic>) handler) {
    if (!_eventHandlers.containsKey(channel)) {
      _eventHandlers[channel] = [];
    }
    _eventHandlers[channel]!.add(handler);
  }

  /// Remove event handler
  void removeEventHandler(String channel, Function(Map<String, dynamic>) handler) {
    _eventHandlers[channel]?.remove(handler);
  }

  /// Handle incoming event
  void _handleEvent(Map<String, dynamic> event) {
    final channel = event['channel'] as String?;
    final eventType = event['event_type'] as String?;

    AppLogger.debug('[WebSocketProvider] Event received: $eventType on $channel');

    if (channel != null && _eventHandlers.containsKey(channel)) {
      for (final handler in _eventHandlers[channel]!) {
        try {
          handler(event);
        } catch (e) {
          AppLogger.error('[WebSocketProvider] Event handler error: $e');
        }
      }
    }

    // Emit specific events based on type
    _emitSpecificEvents(event);
  }

  /// Emit specific events for common actions
  void _emitSpecificEvents(Map<String, dynamic> event) {
    final eventType = event['event_type'] as String?;

    switch (eventType) {
      case KafkaEventTypes.inventoryUpdated:
        AppLogger.info('📦 Inventory updated - refreshing stock data');
        break;

      case KafkaEventTypes.saleCreated:
        AppLogger.info('💰 New sale created - refreshing sales data');
        break;

      case KafkaEventTypes.saleUpdated:
        AppLogger.info('💰 Sale updated - refreshing sales data');
        break;

      case KafkaEventTypes.stockLow:
        final productName = event['data']?['product_name'] as String?;
        AppLogger.warning('⚠️ Low stock alert: $productName');
        break;

      case KafkaEventTypes.paymentProcessed:
        AppLogger.info('💳 Payment processed - refreshing cashflow data');
        break;

      case KafkaEventTypes.notificationSend:
        final message = event['data']?['message'] as String?;
        AppLogger.info('🔔 Notification: $message');
        break;

      default:
        AppLogger.debug('📨 Unhandled event type: $eventType');
    }
  }

  /// Resubscribe to all channels after reconnection
  void _resubscribeToChannels() {
    final channels = List<String>.from(_subscribedChannels);
    _subscribedChannels.clear();

    for (final channel in channels) {
      subscribe(channel);
    }
  }

  /// Subscribe to standard channels based on user role
  Future<void> subscribeToStandardChannels() async {
    final role = await _authService.getUserRole();

    // All users get these channels
    subscribe(WebSocketChannels.inventory);
    subscribe(WebSocketChannels.sales);
    subscribe(WebSocketChannels.dashboard);

    // Finance channels for managers and above
    if (role == 'admin' || role == 'manager' || role == 'executive') {
      subscribe(WebSocketChannels.cashflow);
    }

    AppLogger.info('[WebSocketProvider] Subscribed to standard channels for role: $role');
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _connectionSubscription?.cancel();
    _eventHandlers.clear();
    disconnect();
    super.dispose();
  }
}
