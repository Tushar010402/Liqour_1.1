import 'dart:async';
import 'dart:io';
import '../config/environment_config.dart';
import '../config/debug_performance_config.dart';
import '../utils/logger.dart';

/// Connectivity Service - Network status monitoring
/// Monitors internet connectivity and notifies listeners
class ConnectivityService {
  static ConnectivityService? _instance;

  /// Stream controller for connectivity changes
  final _connectivityController = StreamController<bool>.broadcast();

  /// Current connectivity status
  bool _isConnected = true;

  /// Connectivity check timer
  Timer? _connectivityTimer;

  /// Check interval — relaxed in debug to reduce simulator CPU load.
  static final Duration _checkInterval = DebugPerformanceConfig.connectivityCheckInterval;

  ConnectivityService._();

  /// Singleton instance
  static ConnectivityService get instance {
    _instance ??= ConnectivityService._();
    return _instance!;
  }

  /// Stream of connectivity changes
  Stream<bool> get connectivityStream => _connectivityController.stream;

  /// Current connectivity status
  bool get isConnected => _isConnected;

  /// Initialize connectivity monitoring
  Future<void> init() async {
    Logger.info('Initializing connectivity service');

    // Check initial connectivity
    await _checkConnectivity();

    // Start periodic connectivity checks
    _connectivityTimer = Timer.periodic(_checkInterval, (_) {
      _checkConnectivity();
    });
  }

  /// Check connectivity status
  /// Tries Google DNS first, then falls back to the actual API host
  Future<bool> _checkConnectivity() async {
    try {
      // Try to resolve a reliable host (Google DNS)
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));

      final wasConnected = _isConnected;
      _isConnected = result.isNotEmpty && result[0].rawAddress.isNotEmpty;

      // Notify listeners if status changed
      if (wasConnected != _isConnected) {
        _notifyConnectivityChange();
      }

      return _isConnected;
    } catch (_) {
      // Google DNS failed — try our actual API endpoint as fallback
      // (iOS Simulator may fail DNS for google.com but still reach our API)
      try {
        final apiUri = Uri.parse(EnvironmentConfig.apiBaseUrl);
        final apiResult = await InternetAddress.lookup(apiUri.host)
            .timeout(const Duration(seconds: 3));

        final wasConnected = _isConnected;
        _isConnected = apiResult.isNotEmpty && apiResult[0].rawAddress.isNotEmpty;

        if (wasConnected != _isConnected) {
          _notifyConnectivityChange();
        }

        return _isConnected;
      } catch (_) {
        final wasConnected = _isConnected;
        _isConnected = false;

        if (wasConnected != _isConnected) {
          _notifyConnectivityChange();
        }

        return false;
      }
    }
  }

  /// Notify listeners of connectivity change
  void _notifyConnectivityChange() {
    Logger.info('Connectivity changed: ${_isConnected ? "Connected" : "Disconnected"}');
    _connectivityController.add(_isConnected);
  }

  /// Force check connectivity now
  Future<bool> checkNow() async {
    return await _checkConnectivity();
  }

  /// Wait for connectivity (with timeout)
  Future<bool> waitForConnection({Duration timeout = const Duration(seconds: 30)}) async {
    if (_isConnected) return true;

    try {
      await _connectivityController.stream
          .firstWhere((connected) => connected)
          .timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    }
  }

  /// Dispose resources
  void dispose() {
    _connectivityTimer?.cancel();
    _connectivityController.close();
  }
}

/// Connectivity-aware widget mixin
mixin ConnectivityAware {
  StreamSubscription<bool>? _connectivitySubscription;

  /// Called when connectivity changes
  void onConnectivityChanged(bool isConnected);

  /// Start listening to connectivity changes
  void startConnectivityListener() {
    _connectivitySubscription = ConnectivityService.instance.connectivityStream.listen(
      onConnectivityChanged,
    );
  }

  /// Stop listening to connectivity changes
  void stopConnectivityListener() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
  }
}

/// Connectivity utility functions
class ConnectivityUtils {
  /// Execute operation only when connected
  static Future<T?> whenConnected<T>(Future<T> Function() operation) async {
    final service = ConnectivityService.instance;

    if (!service.isConnected) {
      Logger.warning('Operation skipped: No internet connection');
      return null;
    }

    return await operation();
  }

  /// Execute operation with connectivity retry
  static Future<T?> withConnectivityRetry<T>({
    required Future<T> Function() operation,
    int maxRetries = 3,
    Duration retryDelay = const Duration(seconds: 2),
  }) async {
    final service = ConnectivityService.instance;

    for (var attempt = 0; attempt < maxRetries; attempt++) {
      if (service.isConnected) {
        try {
          return await operation();
        } catch (e) {
          if (e is SocketException || e is TimeoutException) {
            Logger.warning('Network error on attempt ${attempt + 1}: $e');
            if (attempt < maxRetries - 1) {
              await Future.delayed(retryDelay);
              continue;
            }
          }
          rethrow;
        }
      } else {
        Logger.warning('No connection on attempt ${attempt + 1}, waiting...');
        final connected = await service.waitForConnection(
          timeout: Duration(seconds: retryDelay.inSeconds),
        );

        if (!connected && attempt < maxRetries - 1) {
          await Future.delayed(retryDelay);
        }
      }
    }

    throw Exception('Operation failed after $maxRetries attempts: No internet connection');
  }
}

/// Offline queue for pending operations
class OfflineQueue<T> {
  final List<T> _queue = [];
  final Future<void> Function(T item) _processor;

  OfflineQueue({required Future<void> Function(T item) processor})
      : _processor = processor;

  /// Add item to queue
  void enqueue(T item) {
    _queue.add(item);
    Logger.info('Item added to offline queue (${_queue.length} items)');
  }

  /// Process all queued items
  Future<void> processQueue() async {
    if (_queue.isEmpty) return;

    final service = ConnectivityService.instance;
    if (!service.isConnected) {
      Logger.warning('Cannot process queue: No internet connection');
      return;
    }

    Logger.info('Processing offline queue (${_queue.length} items)');

    final items = List<T>.from(_queue);
    _queue.clear();

    for (final item in items) {
      try {
        await _processor(item);
      } catch (e) {
        Logger.error('Failed to process queue item', e);
        // Re-queue failed item
        _queue.add(item);
      }
    }

    if (_queue.isNotEmpty) {
      Logger.warning('${_queue.length} items failed to process');
    } else {
      Logger.info('All queue items processed successfully');
    }
  }

  /// Get queue size
  int get length => _queue.length;

  /// Check if queue is empty
  bool get isEmpty => _queue.isEmpty;

  /// Clear queue
  void clear() {
    _queue.clear();
    Logger.info('Offline queue cleared');
  }
}
