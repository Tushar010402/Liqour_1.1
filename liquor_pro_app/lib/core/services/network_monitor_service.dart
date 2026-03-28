import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import '../utils/app_logger.dart';

/// Network Monitoring Service - Tracks connectivity status
/// Provides real-time network status updates and offline handling
class NetworkMonitorService {
  static final NetworkMonitorService _instance = NetworkMonitorService._internal();
  factory NetworkMonitorService() => _instance;
  NetworkMonitorService._internal();

  final Connectivity _connectivity = Connectivity();
  final StreamController<NetworkStatus> _statusController = StreamController<NetworkStatus>.broadcast();

  NetworkStatus _currentStatus = NetworkStatus.online;
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  /// Stream of network status changes
  Stream<NetworkStatus> get statusStream => _statusController.stream;

  /// Current network status
  NetworkStatus get currentStatus => _currentStatus;

  /// Is currently online
  bool get isOnline => _currentStatus == NetworkStatus.online;

  /// Is currently offline
  bool get isOffline => _currentStatus == NetworkStatus.offline;

  /// Initialize network monitoring
  Future<void> initialize() async {
    try {
      // Check initial connectivity
      final results = await _connectivity.checkConnectivity();
      _updateStatus(results);

      // Listen for connectivity changes
      _subscription = _connectivity.onConnectivityChanged.listen(
        _updateStatus,
        onError: (error) {
          AppLogger.error('Network monitoring error: $error');
        },
      );

      AppLogger.info('✅ Network monitoring initialized');
    } catch (e) {
      AppLogger.error('Failed to initialize network monitoring: $e');
    }
  }

  /// Update network status based on connectivity results
  void _updateStatus(List<ConnectivityResult> results) {
    final wasOnline = _currentStatus == NetworkStatus.online;

    // Check if any connection is available
    final hasConnection = results.any((result) =>
        result == ConnectivityResult.wifi ||
        result == ConnectivityResult.mobile ||
        result == ConnectivityResult.ethernet);

    _currentStatus = hasConnection ? NetworkStatus.online : NetworkStatus.offline;

    // Log status changes
    if (wasOnline && !hasConnection) {
      AppLogger.warning('📡 Network: OFFLINE');
    } else if (!wasOnline && hasConnection) {
      AppLogger.info('📡 Network: ONLINE');
    }

    // Notify listeners
    _statusController.add(_currentStatus);
  }

  /// Dispose resources
  Future<void> dispose() async {
    await _subscription?.cancel();
    await _statusController.close();
  }
}

/// Network status enum
enum NetworkStatus {
  online,
  offline,
}

/// Network Status Widget - Shows banner when offline
/// Usage: Wrap your MaterialApp with NetworkStatusWidget
class NetworkStatusListener extends StatefulWidget {
  final Widget child;

  const NetworkStatusListener({super.key, required this.child});

  @override
  State<NetworkStatusListener> createState() => _NetworkStatusListenerState();
}

class _NetworkStatusListenerState extends State<NetworkStatusListener> {
  final _networkMonitor = NetworkMonitorService();
  NetworkStatus _status = NetworkStatus.online;
  StreamSubscription<NetworkStatus>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = _networkMonitor.statusStream.listen((status) {
      setState(() => _status = status);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Offline banner
        if (_status == NetworkStatus.offline)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8),
            color: Colors.red.shade600,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.wifi_off, color: Colors.white, size: 16),
                SizedBox(width: 8),
                Text(
                  'No internet connection',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

        // Main content
        Expanded(child: widget.child),
      ],
    );
  }
}
