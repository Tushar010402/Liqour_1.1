import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'app_logger.dart';
import 'snackbar_helper.dart';

/// Connectivity Helper - Best Practice Network Connectivity
/// Centralized connectivity monitoring and checking

class ConnectivityHelper {
  // Private constructor to prevent instantiation
  ConnectivityHelper._();

  static final Connectivity _connectivity = Connectivity();
  static StreamSubscription<List<ConnectivityResult>>? _subscription;
  static final List<Function(ConnectivityStatus)> _listeners = [];

  // ==================== Connectivity Check ====================

  /// Check if device has internet connection
  static Future<bool> hasConnection() async {
    try {
      final result = await _connectivity.checkConnectivity();
      final hasConnection = !result.contains(ConnectivityResult.none);

      AppLogger.info('Has connection: $hasConnection');
      return hasConnection;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Check Connection',
      );
      return false;
    }
  }

  /// Check if connected to WiFi
  static Future<bool> isConnectedToWifi() async {
    try {
      final result = await _connectivity.checkConnectivity();
      final isWifi = result.contains(ConnectivityResult.wifi);

      AppLogger.info('Connected to WiFi: $isWifi');
      return isWifi;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Check WiFi Connection',
      );
      return false;
    }
  }

  /// Check if connected to mobile data
  static Future<bool> isConnectedToMobile() async {
    try {
      final result = await _connectivity.checkConnectivity();
      final isMobile = result.contains(ConnectivityResult.mobile);

      AppLogger.info('Connected to Mobile: $isMobile');
      return isMobile;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Check Mobile Connection',
      );
      return false;
    }
  }

  /// Get current connectivity status
  static Future<ConnectivityStatus> getStatus() async {
    try {
      final result = await _connectivity.checkConnectivity();

      if (result.contains(ConnectivityResult.wifi)) {
        return ConnectivityStatus.wifi;
      } else if (result.contains(ConnectivityResult.mobile)) {
        return ConnectivityStatus.mobile;
      } else if (result.contains(ConnectivityResult.ethernet)) {
        return ConnectivityStatus.ethernet;
      } else {
        return ConnectivityStatus.none;
      }
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Get Connectivity Status',
      );
      return ConnectivityStatus.none;
    }
  }

  // ==================== Connectivity Monitoring ====================

  /// Start monitoring connectivity changes
  static void startMonitoring({
    Function(ConnectivityStatus)? onChanged,
  }) {
    if (_subscription != null) {
      AppLogger.warning('Connectivity monitoring already started');
      return;
    }

    AppLogger.info('Starting connectivity monitoring');

    if (onChanged != null) {
      _listeners.add(onChanged);
    }

    _subscription = _connectivity.onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        ConnectivityStatus status;

        if (results.contains(ConnectivityResult.wifi)) {
          status = ConnectivityStatus.wifi;
        } else if (results.contains(ConnectivityResult.mobile)) {
          status = ConnectivityStatus.mobile;
        } else if (results.contains(ConnectivityResult.ethernet)) {
          status = ConnectivityStatus.ethernet;
        } else {
          status = ConnectivityStatus.none;
        }

        AppLogger.info('Connectivity changed: $status');

        // Notify all listeners
        for (final listener in _listeners) {
          listener(status);
        }
      },
      onError: (e, stackTrace) {
        AppLogger.exception(
          exception: e,
          stackTrace: stackTrace,
          context: 'Connectivity Monitoring',
        );
      },
    );
  }

  /// Stop monitoring connectivity changes
  static void stopMonitoring() {
    AppLogger.info('Stopping connectivity monitoring');

    _subscription?.cancel();
    _subscription = null;
    _listeners.clear();
  }

  /// Add listener for connectivity changes
  static void addListener(Function(ConnectivityStatus) listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
      AppLogger.debug('Connectivity listener added');
    }
  }

  /// Remove listener
  static void removeListener(Function(ConnectivityStatus) listener) {
    _listeners.remove(listener);
    AppLogger.debug('Connectivity listener removed');
  }

  // ==================== Connection Required ====================

  /// Execute action if connected, show error if not
  static Future<T?> requireConnection<T>({
    required BuildContext context,
    required Future<T> Function() action,
    String? errorMessage,
  }) async {
    if (!await hasConnection()) {
      AppLogger.warning('No connection available');

      SnackbarHelper.error(
        context: context,
        message: errorMessage ?? 'No internet connection',
      );

      return null;
    }

    return await action();
  }

  /// Execute action if connected to WiFi, show error if not
  static Future<T?> requireWifi<T>({
    required BuildContext context,
    required Future<T> Function() action,
    String? errorMessage,
  }) async {
    if (!await isConnectedToWifi()) {
      AppLogger.warning('WiFi not available');

      SnackbarHelper.error(
        context: context,
        message: errorMessage ?? 'WiFi connection required',
      );

      return null;
    }

    return await action();
  }

  // ==================== Utility Methods ====================

  /// Get connectivity status string
  static String getStatusString(ConnectivityStatus status) {
    switch (status) {
      case ConnectivityStatus.wifi:
        return 'WiFi';
      case ConnectivityStatus.mobile:
        return 'Mobile Data';
      case ConnectivityStatus.ethernet:
        return 'Ethernet';
      case ConnectivityStatus.none:
        return 'No Connection';
    }
  }

  /// Get connectivity status icon
  static IconData getStatusIcon(ConnectivityStatus status) {
    switch (status) {
      case ConnectivityStatus.wifi:
        return Icons.wifi;
      case ConnectivityStatus.mobile:
        return Icons.signal_cellular_alt;
      case ConnectivityStatus.ethernet:
        return Icons.settings_ethernet;
      case ConnectivityStatus.none:
        return Icons.signal_wifi_off;
    }
  }

  /// Get connectivity status color
  static Color getStatusColor(ConnectivityStatus status) {
    switch (status) {
      case ConnectivityStatus.wifi:
        return Colors.green;
      case ConnectivityStatus.mobile:
        return Colors.blue;
      case ConnectivityStatus.ethernet:
        return Colors.green;
      case ConnectivityStatus.none:
        return Colors.red;
    }
  }
}

/// Connectivity status enum
enum ConnectivityStatus {
  wifi,
  mobile,
  ethernet,
  none,
}

/// Connectivity Listener Widget - Listens to connectivity changes
class ConnectivityListener extends StatefulWidget {
  final Widget child;
  final Function(ConnectivityStatus)? onConnectivityChanged;
  final bool showSnackbar;

  const ConnectivityListener({
    super.key,
    required this.child,
    this.onConnectivityChanged,
    this.showSnackbar = true,
  });

  @override
  State<ConnectivityListener> createState() => _ConnectivityListenerState();
}

class _ConnectivityListenerState extends State<ConnectivityListener> {
  ConnectivityStatus? _previousStatus;

  @override
  void initState() {
    super.initState();
    ConnectivityHelper.startMonitoring(onChanged: _onConnectivityChanged);
  }

  @override
  void dispose() {
    ConnectivityHelper.stopMonitoring();
    super.dispose();
  }

  void _onConnectivityChanged(ConnectivityStatus status) {
    // Show snackbar on connectivity change
    if (widget.showSnackbar && _previousStatus != null && _previousStatus != status) {
      if (status == ConnectivityStatus.none) {
        SnackbarHelper.error(
          context: context,
          message: 'No internet connection',
        );
      } else if (_previousStatus == ConnectivityStatus.none) {
        SnackbarHelper.success(
          context: context,
          message: 'Internet connection restored',
        );
      }
    }

    _previousStatus = status;

    // Call callback
    widget.onConnectivityChanged?.call(status);
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// Connectivity Guard Widget - Shows error state when offline
class ConnectivityGuard extends StatefulWidget {
  final Widget child;
  final Widget? offlineWidget;
  final bool checkOnInit;

  const ConnectivityGuard({
    super.key,
    required this.child,
    this.offlineWidget,
    this.checkOnInit = true,
  });

  @override
  State<ConnectivityGuard> createState() => _ConnectivityGuardState();
}

class _ConnectivityGuardState extends State<ConnectivityGuard> {
  bool _isOnline = true;
  bool _isChecking = true;

  @override
  void initState() {
    super.initState();

    if (widget.checkOnInit) {
      _checkConnection();
    } else {
      setState(() {
        _isChecking = false;
      });
    }

    ConnectivityHelper.addListener(_onConnectivityChanged);
  }

  @override
  void dispose() {
    ConnectivityHelper.removeListener(_onConnectivityChanged);
    super.dispose();
  }

  Future<void> _checkConnection() async {
    final hasConnection = await ConnectivityHelper.hasConnection();

    if (mounted) {
      setState(() {
        _isOnline = hasConnection;
        _isChecking = false;
      });
    }
  }

  void _onConnectivityChanged(ConnectivityStatus status) {
    if (mounted) {
      setState(() {
        _isOnline = status != ConnectivityStatus.none;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (!_isOnline) {
      return widget.offlineWidget ?? _buildDefaultOfflineWidget();
    }

    return widget.child;
  }

  Widget _buildDefaultOfflineWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.signal_wifi_off,
            size: 64,
            color: Colors.grey,
          ),
          const SizedBox(height: 16),
          const Text(
            'No Internet Connection',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Please check your internet connection',
            style: TextStyle(
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _checkConnection,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

/// Connectivity Indicator Widget - Shows current connectivity status
class ConnectivityIndicator extends StatefulWidget {
  final bool showWhenOnline;

  const ConnectivityIndicator({
    super.key,
    this.showWhenOnline = false,
  });

  @override
  State<ConnectivityIndicator> createState() => _ConnectivityIndicatorState();
}

class _ConnectivityIndicatorState extends State<ConnectivityIndicator> {
  ConnectivityStatus _status = ConnectivityStatus.none;

  @override
  void initState() {
    super.initState();
    _checkStatus();
    ConnectivityHelper.addListener(_onConnectivityChanged);
  }

  @override
  void dispose() {
    ConnectivityHelper.removeListener(_onConnectivityChanged);
    super.dispose();
  }

  Future<void> _checkStatus() async {
    final status = await ConnectivityHelper.getStatus();

    if (mounted) {
      setState(() {
        _status = status;
      });
    }
  }

  void _onConnectivityChanged(ConnectivityStatus status) {
    if (mounted) {
      setState(() {
        _status = status;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showWhenOnline && _status != ConnectivityStatus.none) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: ConnectivityHelper.getStatusColor(_status),
      child: Row(
        children: [
          Icon(
            ConnectivityHelper.getStatusIcon(_status),
            color: Colors.white,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            ConnectivityHelper.getStatusString(_status),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
