import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'app_logger.dart';

/// Network Helper - Best Practice Network Utilities
/// Centralized network status checking and monitoring

class NetworkHelper {
  // Private constructor to prevent instantiation
  NetworkHelper._();

  static final Connectivity _connectivity = Connectivity();

  // ==================== Network Status ====================

  /// Check if device is connected to internet
  static Future<bool> isConnected() async {
    try {
      final result = await _connectivity.checkConnectivity();

      if (result == ConnectivityResult.none) {
        AppLogger.debug('Network: No connection');
        return false;
      }

      // Additional check: Try to lookup a host
      final hasInternet = await hasInternetConnection();
      AppLogger.debug('Network: ${hasInternet ? "Connected" : "No internet"}');
      return hasInternet;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Network isConnected',
      );
      return false;
    }
  }

  /// Check actual internet connection (not just network)
  static Future<bool> hasInternetConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    } catch (e) {
      AppLogger.debug('Network: Internet check failed - $e');
      return false;
    }
  }

  /// Get current connectivity type
  static Future<List<ConnectivityResult>> getConnectivityType() async {
    try {
      final result = await _connectivity.checkConnectivity();
      AppLogger.debug('Network: Connectivity type - $result');
      return result;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Network getConnectivityType',
      );
      return [ConnectivityResult.none];
    }
  }

  /// Check if connected via WiFi
  static Future<bool> isWifi() async {
    final result = await getConnectivityType();
    return result.contains(ConnectivityResult.wifi);
  }

  /// Check if connected via Mobile data
  static Future<bool> isMobile() async {
    final result = await getConnectivityType();
    return result.contains(ConnectivityResult.mobile);
  }

  /// Check if connected via Ethernet
  static Future<bool> isEthernet() async {
    final result = await getConnectivityType();
    return result.contains(ConnectivityResult.ethernet);
  }

  // ==================== Network Monitoring ====================

  /// Stream of connectivity changes
  static Stream<List<ConnectivityResult>> get onConnectivityChanged {
    return _connectivity.onConnectivityChanged;
  }

  /// Listen to connectivity changes
  static void listenToConnectivity({
    required Function(bool isConnected) onChanged,
  }) {
    _connectivity.onConnectivityChanged.listen((result) async {
      final connected = !result.contains(ConnectivityResult.none);

      if (connected) {
        // Double check with actual internet connection
        final hasInternet = await hasInternetConnection();
        AppLogger.info('Network: Status changed - ${hasInternet ? "Connected" : "Disconnected"}');
        onChanged(hasInternet);
      } else {
        AppLogger.info('Network: Status changed - Disconnected');
        onChanged(false);
      }
    });
  }

  // ==================== Network Quality ====================

  /// Get network quality (wifi = good, mobile = medium, none = poor)
  static Future<NetworkQuality> getNetworkQuality() async {
    final type = await getConnectivityType();

    switch (type) {
      case ConnectivityResult.wifi:
      case ConnectivityResult.ethernet:
        return NetworkQuality.good;
      case ConnectivityResult.mobile:
        return NetworkQuality.medium;
      case ConnectivityResult.none:
        return NetworkQuality.poor;
      default:
        return NetworkQuality.unknown;
    }
  }

  /// Check if network is good enough for operation
  static Future<bool> isGoodEnoughFor(NetworkRequirement requirement) async {
    final quality = await getNetworkQuality();

    switch (requirement) {
      case NetworkRequirement.basic:
        return quality != NetworkQuality.poor;
      case NetworkRequirement.standard:
        return quality == NetworkQuality.good || quality == NetworkQuality.medium;
      case NetworkRequirement.high:
        return quality == NetworkQuality.good;
    }
  }

  // ==================== Error Handling ====================

  /// Check if error is network related
  static bool isNetworkError(dynamic error) {
    if (error is SocketException) return true;
    if (error is HttpException) return true;
    if (error is HandshakeException) return true;

    final errorString = error.toString().toLowerCase();
    return errorString.contains('network') ||
        errorString.contains('connection') ||
        errorString.contains('timeout') ||
        errorString.contains('socket') ||
        errorString.contains('failed host lookup');
  }

  /// Get user-friendly network error message
  static String getNetworkErrorMessage(dynamic error) {
    if (error is SocketException) {
      return 'No internet connection. Please check your network.';
    }

    if (error is HttpException) {
      return 'Server connection failed. Please try again.';
    }

    if (error is HandshakeException) {
      return 'Secure connection failed. Please check your network.';
    }

    final errorString = error.toString().toLowerCase();

    if (errorString.contains('timeout')) {
      return 'Request timed out. Please check your connection.';
    }

    if (errorString.contains('failed host lookup')) {
      return 'Cannot reach server. Please check your internet.';
    }

    return 'Network error occurred. Please try again.';
  }

  // ==================== Retry Logic ====================

  /// Execute function with retry on network failure
  static Future<T> withRetry<T>({
    required Future<T> Function() operation,
    int maxRetries = 3,
    Duration retryDelay = const Duration(seconds: 2),
    bool Function(dynamic error)? shouldRetry,
  }) async {
    int attempts = 0;

    while (true) {
      attempts++;

      try {
        AppLogger.debug('Network: Attempt $attempts/$maxRetries');
        final result = await operation();
        AppLogger.debug('Network: Operation succeeded on attempt $attempts');
        return result;
      } catch (e, stackTrace) {
        final isLastAttempt = attempts >= maxRetries;
        final shouldRetryError = shouldRetry?.call(e) ?? isNetworkError(e);

        if (isLastAttempt || !shouldRetryError) {
          AppLogger.error(
            'Network: Operation failed after $attempts attempts',
            e,
            stackTrace,
          );
          rethrow;
        }

        AppLogger.warning(
          'Network: Attempt $attempts failed, retrying in ${retryDelay.inSeconds}s',
          e,
        );

        await Future.delayed(retryDelay);
      }
    }
  }

  /// Execute function only if network is available
  static Future<T?> executeIfConnected<T>({
    required Future<T> Function() operation,
    String? errorMessage,
  }) async {
    if (await isConnected()) {
      return await operation();
    } else {
      final message = errorMessage ?? 'No internet connection';
      AppLogger.warning('Network: $message');
      throw NetworkException(message);
    }
  }

  // ==================== Bandwidth Estimation ====================

  /// Estimate if on metered connection (mobile data)
  static Future<bool> isMeteredConnection() async {
    return await isMobile();
  }

  /// Check if should download large files
  static Future<bool> shouldDownloadLargeFiles() async {
    // Only download large files on WiFi
    return await isWifi();
  }

  /// Check if should upload large files
  static Future<bool> shouldUploadLargeFiles() async {
    // Only upload large files on WiFi
    return await isWifi();
  }

  /// Check if should sync data
  static Future<bool> shouldSyncData({bool requireWifi = false}) async {
    if (requireWifi) {
      return await isWifi();
    }

    return await isConnected();
  }

  // ==================== Utility Methods ====================

  /// Get connectivity status as string
  static Future<String> getConnectivityStatus() async {
    final type = await getConnectivityType();

    switch (type) {
      case ConnectivityResult.wifi:
        return 'WiFi';
      case ConnectivityResult.mobile:
        return 'Mobile Data';
      case ConnectivityResult.ethernet:
        return 'Ethernet';
      case ConnectivityResult.none:
        return 'No Connection';
      default:
        return 'Unknown';
    }
  }

  /// Get connectivity icon name
  static Future<String> getConnectivityIcon() async {
    final type = await getConnectivityType();

    switch (type) {
      case ConnectivityResult.wifi:
        return 'wifi';
      case ConnectivityResult.mobile:
        return 'signal_cellular_alt';
      case ConnectivityResult.ethernet:
        return 'settings_ethernet';
      case ConnectivityResult.none:
        return 'wifi_off';
      default:
        return 'help_outline';
    }
  }

  // ==================== Network Info ====================

  /// Get network information
  static Future<NetworkInfo> getNetworkInfo() async {
    final type = await getConnectivityType();
    final connected = await isConnected();
    final quality = await getNetworkQuality();
    final status = await getConnectivityStatus();

    return NetworkInfo(
      type: type,
      isConnected: connected,
      quality: quality,
      status: status,
    );
  }

  /// Log network info
  static Future<void> logNetworkInfo() async {
    final info = await getNetworkInfo();
    AppLogger.info('Network Info: ${info.toString()}');
  }
}

/// Network quality enum
enum NetworkQuality {
  good,    // WiFi, Ethernet
  medium,  // Mobile data
  poor,    // No connection
  unknown, // Unknown
}

/// Network requirement enum
enum NetworkRequirement {
  basic,    // Any connection
  standard, // WiFi or Mobile
  high,     // WiFi only
}

/// Network info model
class NetworkInfo {
  final List<ConnectivityResult> type;
  final bool isConnected;
  final NetworkQuality quality;
  final String status;

  NetworkInfo({
    required this.type,
    required this.isConnected,
    required this.quality,
    required this.status,
  });

  @override
  String toString() {
    return 'NetworkInfo(status: $status, connected: $isConnected, quality: $quality)';
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.toString(),
      'isConnected': isConnected,
      'quality': quality.toString(),
      'status': status,
    };
  }
}

/// Network exception
class NetworkException implements Exception {
  final String message;

  NetworkException(this.message);

  @override
  String toString() => message;
}

/// Network callback
typedef NetworkCallback = void Function(bool isConnected);

/// Network listener
class NetworkListener {
  NetworkCallback? _onChanged;
  Stream<List<ConnectivityResult>>? _subscription;

  /// Start listening to network changes
  void start(NetworkCallback onChanged) {
    _onChanged = onChanged;
    _subscription = NetworkHelper.onConnectivityChanged;

    _subscription?.listen((result) async {
      final connected = !result.contains(ConnectivityResult.none);

      if (connected) {
        final hasInternet = await NetworkHelper.hasInternetConnection();
        _onChanged?.call(hasInternet);
      } else {
        _onChanged?.call(false);
      }
    });
  }

  /// Stop listening
  void stop() {
    _onChanged = null;
    _subscription = null;
  }
}
