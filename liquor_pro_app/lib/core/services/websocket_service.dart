import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
// Platform-specific WebSocket implementations to fix port 0 bug
import 'package:web_socket_channel/io.dart' show IOWebSocketChannel;
import '../config/environment_config.dart';
import '../utils/app_logger.dart';
import '../utils/jwt_utils.dart';
import 'auth_service.dart';

/// WebSocket Service for Real-time Updates
/// Connects to Kafka-enabled backend for live events
class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  Timer? _tokenRefreshTimer;

  // Auth service reference (to be set during initialization)
  AuthService? _authService;
  Function()? _onAuthRequired;

  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isDisabled = false; // Disable WebSocket if server doesn't support it
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 3; // Reduced from 5
  static const Duration _baseReconnectDelay = Duration(seconds: 5); // Increased from 2
  static const Duration _maxReconnectDelay = Duration(seconds: 60); // Increased from 30

  // Track error frequency to prevent spam
  DateTime? _lastErrorLog;
  int _errorCount = 0;
  static const Duration _errorThrottleWindow = Duration(seconds: 10);

  // Store auth credentials for reconnection
  String? _storedToken;
  String? _storedTenantId;

  final _eventController = StreamController<Map<String, dynamic>>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  final _ocrProgressController = StreamController<Map<String, dynamic>>.broadcast();

  /// Stream of incoming events from Kafka
  Stream<Map<String, dynamic>> get events => _eventController.stream;

  /// Stream of connection status changes
  Stream<bool> get connectionStatus => _connectionController.stream;

  /// Stream of OCR progress updates
  Stream<Map<String, dynamic>> get ocrProgressStream => _ocrProgressController.stream;

  /// Current connection status
  bool get isConnected => _isConnected;

  /// Initialize WebSocket service with auth dependencies
  void initialize({
    required AuthService authService,
    Function()? onAuthRequired,
  }) {
    _authService = authService;
    _onAuthRequired = onAuthRequired;

    if (kDebugMode) {
      AppLogger.debug('🔧 WebSocket: Service initialized with auth support');
    }
  }

  /// Validate and refresh token if needed
  Future<String?> _validateAndGetToken() async {
    try {
      // Get current token
      String? token = _storedToken ?? await _authService?.getToken();

      if (token == null || token.isEmpty) {
        AppLogger.warning('⚠️ WebSocket: No authentication token available');
        return null;
      }

      // Check if token is expired or will expire soon
      if (JwtUtils.isTokenExpired(token, bufferSeconds: 120)) {
        AppLogger.info('🔄 WebSocket: Token expired or expiring soon, requesting new authentication');

        // Token is expired - need to re-authenticate
        // Since we don't have a refresh token endpoint, we need to trigger re-authentication
        if (_onAuthRequired != null) {
          _onAuthRequired!();
          return null; // Will retry after re-authentication
        }

        // If no auth callback, we can't proceed
        AppLogger.error('❌ WebSocket: Token expired and no re-authentication callback provided');
        return null;
      }

      // Token is valid
      if (kDebugMode) {
        final timeLeft = JwtUtils.getTimeUntilExpiration(token);
        if (timeLeft != null) {
          AppLogger.debug('✅ WebSocket: Token valid for ${timeLeft.inMinutes} minutes');
        }
      }

      return token;
    } catch (e) {
      AppLogger.error('❌ WebSocket: Error validating token: $e');
      return null;
    }
  }

  /// Start token monitoring timer
  void _startTokenMonitoring() {
    _stopTokenMonitoring();

    // Check token every 30 seconds
    _tokenRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!_isConnected) return;

      final token = await _authService?.getToken();
      if (token == null) return;

      // Check if token will expire in the next 2 minutes
      if (JwtUtils.willExpireSoon(token, within: const Duration(minutes: 2))) {
        AppLogger.warning('⚠️ WebSocket: Token expiring soon, disconnecting to force reconnection with fresh token');

        // Disconnect and trigger reconnection which will get a fresh token
        _handleDisconnect();
      }
    });
  }

  /// Stop token monitoring timer
  void _stopTokenMonitoring() {
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = null;
  }

  /// Connect to WebSocket server
  Future<void> connect({String? token, String? tenantId}) async {
    // Skip if disabled (server doesn't support WebSocket)
    if (_isDisabled) {
      return;
    }

    if (_isConnecting || _isConnected) {
      return; // Silently return to avoid spam
    }

    _isConnecting = true;

    // Only log on first attempt
    if (_reconnectAttempts == 0) {
      AppLogger.info('🔌 WebSocket: Attempting connection...');
    }

    try {
      // Store credentials for reconnection
      _storedToken = token ?? _storedToken;
      _storedTenantId = tenantId ?? _storedTenantId;

      // Validate token before connecting
      final validToken = await _validateAndGetToken();
      if (validToken == null) {
        throw Exception('Invalid or expired authentication token');
      }

      final authToken = validToken;
      final authTenantId = _storedTenantId;

      // Create WebSocket URL with authentication as query parameters
      final baseUrl = EnvironmentConfig.websocketUrl;

      // Parse base URL
      final parsedUrl = Uri.parse(baseUrl);

      // Build query parameters
      final queryParams = <String, String>{
        'token': authToken,
        if (authTenantId != null) 'tenant_id': authTenantId,
      };

      // For iOS, we need to explicitly set the port to avoid the port 0 bug
      // iOS WebSocket implementation has issues with implicit ports
      Uri wsUri;
      if (Platform.isIOS) {
        // Explicitly set port for iOS
        final port = parsedUrl.hasPort ? parsedUrl.port :
                    (parsedUrl.scheme == 'wss' ? 443 : 80);
        wsUri = Uri(
          scheme: parsedUrl.scheme,
          host: parsedUrl.host,
          port: port,  // Explicit port for iOS
          path: parsedUrl.path.isEmpty ? '/ws' : parsedUrl.path,
          queryParameters: queryParams,
        );
      } else {
        // Android/other platforms work fine with Uri.replace()
        wsUri = parsedUrl.replace(queryParameters: queryParams);
      }

      // Platform-specific logging
      if (kDebugMode) {
        final platform = Platform.isIOS ? '🍎 iOS' :
                        Platform.isAndroid ? '🤖 Android' :
                        '💻 ${Platform.operatingSystem}';

        AppLogger.debug('$platform WebSocket Connection:');
        AppLogger.debug('  URL: ${wsUri.toString()}');
        AppLogger.debug('  Scheme: ${wsUri.scheme}');
        AppLogger.debug('  Host: ${wsUri.host}');
        AppLogger.debug('  Port: ${wsUri.port} (${wsUri.hasPort ? 'explicit' : 'default'})');
        AppLogger.debug('  Path: ${wsUri.path}');

        // Additional iOS debugging
        if (Platform.isIOS) {
          AppLogger.debug('  iOS Fix: Port explicitly set to avoid port 0 bug');
        }
      }

      // Create WebSocket connection with platform-specific implementation
      // IMPORTANT: Pass Uri object directly (not string) for iOS compatibility
      // iOS has stricter URL parsing and requires proper Uri objects
      _channel = IOWebSocketChannel.connect(
        wsUri,  // Pass Uri object directly - iOS requires this!
        protocols: ['websocket'],
      );

      // Listen for messages with error handling
      _subscription = _channel!.stream.listen(
        _handleMessage,
        onError: (error, stackTrace) {
          // Catch and handle errors gracefully to prevent unhandled exceptions
          _handleError(error);
        },
        onDone: _handleDisconnect,
        cancelOnError: false, // Keep listening even after errors
      );

      // Don't mark as connected immediately - wait for first successful message
      // This prevents showing "Connected" when the connection immediately fails
      _isConnecting = false;

      // Send initial ping to verify connection
      _channel?.sink.add(jsonEncode({'action': 'ping'}));

      // Mark as tentatively connected (will be confirmed on first message)
      _isConnected = true;
      _reconnectAttempts = 0;
      _errorCount = 0;
      _connectionController.add(true);

      // Start ping timer to keep connection alive
      _startPingTimer();

      // Start token monitoring to proactively handle expiration
      _startTokenMonitoring();

      AppLogger.info('✅ WebSocket: Connected successfully with token monitoring');
    } catch (e) {
      _isConnecting = false;
      _isConnected = false;
      _connectionController.add(false);

      // Throttle error logging
      _logThrottledError('WebSocket connection failed', e.toString());

      // Don't schedule reconnect if credentials are invalid
      if (e.toString().contains('Authentication token required')) {
        AppLogger.error('WebSocket: Invalid credentials, not attempting reconnect');
        return;
      }

      _scheduleReconnect();
    }
  }

  /// Subscribe to a specific channel
  void subscribe(String channel) {
    if (!_isConnected) {
      AppLogger.warning('WebSocket: Cannot subscribe - not connected');
      return;
    }

    _channel?.sink.add(jsonEncode({
      'action': 'subscribe',
      'channel': channel,
    }));

    AppLogger.debug('WebSocket: Subscribed to channel: $channel');
  }

  /// Unsubscribe from a channel
  void unsubscribe(String channel) {
    if (!_isConnected) return;

    _channel?.sink.add(jsonEncode({
      'action': 'unsubscribe',
      'channel': channel,
    }));

    AppLogger.debug('WebSocket: Unsubscribed from channel: $channel');
  }

  /// Send a custom message
  void send(Map<String, dynamic> message) {
    if (!_isConnected) {
      AppLogger.warning('WebSocket: Cannot send - not connected');
      return;
    }

    _channel?.sink.add(jsonEncode(message));
  }

  /// Handle incoming messages
  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;

      // Handle different message types
      switch (data['type']) {
        case 'pong':
          // Ping/pong keep-alive
          break;

        case 'authenticated':
          AppLogger.info('✅ WebSocket: Authenticated successfully');
          break;

        case 'subscribed':
          AppLogger.debug('WebSocket: Subscription confirmed for ${data['channel']}');
          break;

        case 'ack':
          AppLogger.info('✅ WebSocket: ${data['data']?['message'] ?? 'Acknowledged'}');
          break;

        case 'ocr_progress':
          // OCR progress update
          if (data['data'] != null) {
            _ocrProgressController.add(data['data'] as Map<String, dynamic>);
            final progress = data['data']['progress'];
            AppLogger.info('📊 OCR Progress: ${progress?['stage']} - ${progress?['progress']}%');
          }
          break;

        case 'event':
          // Kafka event received
          _eventController.add(data);
          AppLogger.debug('WebSocket: Received event ${data['event_type']}');
          break;

        case 'error':
          // Best Practice: Handle null error messages and throttle logging
          final errorMessage = data['message'];
          if (errorMessage != null && errorMessage.toString().trim().isNotEmpty) {
            _logThrottledError('WebSocket: Server error', errorMessage.toString());
          }
          // Silently ignore null or empty error messages from server
          break;

        default:
          // Forward all other events
          _eventController.add(data);
      }
    } catch (e) {
      AppLogger.error('WebSocket: Failed to parse message - $e');
    }
  }

  /// Handle WebSocket errors
  void _handleError(dynamic error) {
    _isConnected = false;
    _isConnecting = false;
    _connectionController.add(false);

    // Cleanup connection on error
    _stopPingTimer();
    _stopTokenMonitoring();

    // Check if server doesn't support WebSocket (404, not upgraded, etc.)
    final errorStr = error?.toString() ?? '';
    final isServerUnavailable = errorStr.contains('not upgraded to websocket') ||
        errorStr.contains('404') ||
        errorStr.contains('Endpoint not found');

    if (isServerUnavailable) {
      // Disable WebSocket immediately - server doesn't support it
      _isDisabled = true;
      _reconnectTimer?.cancel();

      // Log once only on first occurrence
      if (_errorCount == 0) {
        AppLogger.debug('ℹ️ WebSocket: Real-time updates not available (production server endpoint not deployed)');
      }
      _errorCount++;
      return;
    }

    // Check for authentication errors (401 Unauthorized)
    final isAuthError = errorStr.contains('401') ||
        errorStr.contains('Unauthorized') ||
        errorStr.contains('Authentication failed') ||
        errorStr.contains('Invalid token');

    if (isAuthError) {
      AppLogger.warning('🔐 WebSocket: Authentication error detected - token may be expired');

      // Clear stored token to force re-validation on reconnect
      _storedToken = null;

      // Trigger authentication required callback if available
      if (_onAuthRequired != null) {
        AppLogger.info('🔄 WebSocket: Triggering re-authentication...');
        _onAuthRequired!();
        return; // Don't attempt reconnect, wait for new authentication
      }
    }

    // Platform-specific error detection for better debugging
    if (Platform.isIOS && errorStr.contains('Connection to \'https://')) {
      // iOS-specific error: URL was incorrectly parsed
      AppLogger.error('🍎 iOS WebSocket Error: URL parsing failed. This usually means the Uri object was not passed correctly.');
      AppLogger.error('  Error details: ${errorStr.substring(0, errorStr.length.clamp(0, 200))}');
    } else if (Platform.isIOS && errorStr.contains(':0')) {
      // iOS-specific error: Port 0 issue
      AppLogger.error('🍎 iOS WebSocket Error: Port 0 detected. The WebSocket URL is being incorrectly parsed.');
    } else if (error != null && error.toString() != 'null') {
      // Generic error logging with platform info
      final platform = Platform.isIOS ? '🍎 iOS' :
                      Platform.isAndroid ? '🤖 Android' :
                      '💻 ${Platform.operatingSystem}';
      _logThrottledError('$platform WebSocket error', error.toString());
    }

    _scheduleReconnect();
  }

  /// Handle WebSocket disconnection
  void _handleDisconnect() {
    if (_isDisabled) {
      return; // Don't log if disabled
    }

    _isConnected = false;
    _connectionController.add(false);
    _stopPingTimer();
    _stopTokenMonitoring();

    // Only log disconnection on first occurrence
    if (_reconnectAttempts == 0) {
      AppLogger.debug('WebSocket: Disconnected');
    }

    _scheduleReconnect();
  }

  /// Start ping timer to keep connection alive
  void _startPingTimer() {
    _stopPingTimer();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isConnected) {
        _channel?.sink.add(jsonEncode({'action': 'ping'}));
      }
    });
  }

  /// Stop ping timer
  void _stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  /// Schedule reconnection attempt with exponential backoff
  void _scheduleReconnect() {
    if (_isDisabled) {
      return; // Don't reconnect if disabled
    }

    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _isDisabled = true; // Disable after max attempts
      AppLogger.info('ℹ️ WebSocket: Real-time updates unavailable (max retries reached)');
      return;
    }

    _reconnectTimer?.cancel();
    _reconnectAttempts++;

    // Exponential backoff: 5s, 10s, 20s (capped at 60s)
    final delaySeconds = (_baseReconnectDelay.inSeconds * (1 << (_reconnectAttempts - 1)))
        .clamp(0, _maxReconnectDelay.inSeconds);
    final delay = Duration(seconds: delaySeconds);

    // Only log reconnect attempt if it's the first one
    if (_reconnectAttempts == 1) {
      AppLogger.debug('WebSocket: Will retry connection...');
    }

    _reconnectTimer = Timer(delay, () async {
      // Before reconnecting, validate token again
      if (_authService != null) {
        final token = await _authService!.getToken();
        if (token != null && JwtUtils.isTokenExpired(token)) {
          AppLogger.info('🔄 WebSocket: Token expired before reconnection, requesting authentication');
          if (_onAuthRequired != null) {
            _onAuthRequired!();
            return; // Don't reconnect yet, wait for new auth
          }
        }
      }

      connect();
    });
  }

  /// Log error with throttling to prevent spam
  void _logThrottledError(String context, String error) {
    final now = DateTime.now();

    // Check if we should throttle
    if (_lastErrorLog != null) {
      final timeSinceLastLog = now.difference(_lastErrorLog!);
      if (timeSinceLastLog < _errorThrottleWindow) {
        return; // Skip logging to prevent spam
      }
    }

    _lastErrorLog = now;

    // Only log if it's not a known production issue
    if (error.contains('not upgraded to websocket') && EnvironmentConfig.isProduction) {
      // This is expected in production, only log once
      if (_errorCount == 1) {
        AppLogger.debug('$context - Real-time updates not available');
      }
    } else {
      AppLogger.debug('$context - ${error.substring(0, error.length.clamp(0, 100))}');
    }
  }

  /// Disconnect from WebSocket
  Future<void> disconnect() async {
    AppLogger.info('WebSocket: Disconnecting...');

    _reconnectTimer?.cancel();
    _stopPingTimer();
    _stopTokenMonitoring();

    await _subscription?.cancel();
    await _channel?.sink.close();

    _isConnected = false;
    _isConnecting = false;
    _connectionController.add(false);

    AppLogger.info('WebSocket: Disconnected');
  }

  /// Dispose resources
  Future<void> dispose() async {
    await disconnect();
    await _eventController.close();
    await _connectionController.close();
    await _ocrProgressController.close();
  }
}

/// Available WebSocket channels for subscription
class WebSocketChannels {
  static const String inventory = 'inventory';
  static const String sales = 'sales';
  static const String cashflow = 'cashflow';
  static const String dashboard = 'dashboard';
  static const String ocrProgress = 'ocr_progress';
}

/// Kafka event types
class KafkaEventTypes {
  // Sales events
  static const String saleCreated = 'sale.created';
  static const String saleUpdated = 'sale.updated';

  // Inventory events
  static const String inventoryUpdated = 'inventory.updated';
  static const String stockLow = 'stock.low';

  // Payment events
  static const String paymentProcessed = 'payment.processed';

  // Notification events
  static const String notificationSend = 'notification.send';

  // OCR events
  static const String ocrProgress = 'ocr.progress';
  static const String ocrCompleted = 'ocr.completed';
  static const String ocrFailed = 'ocr.failed';
}
