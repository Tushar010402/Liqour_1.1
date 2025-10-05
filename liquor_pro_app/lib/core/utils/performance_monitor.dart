import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import '../services/analytics_service.dart';
import 'logger.dart';

/// Performance Monitor - Track app performance metrics
/// Production-ready performance monitoring
class PerformanceMonitor {
  static final Map<String, DateTime> _operationStarts = {};
  static final Map<String, List<int>> _operationDurations = {};

  /// Start tracking an operation
  static void startOperation(String operationName) {
    _operationStarts[operationName] = DateTime.now();
  }

  /// End tracking an operation
  static void endOperation(String operationName, {String? category}) {
    final startTime = _operationStarts[operationName];
    if (startTime == null) {
      Logger.warning('Operation "$operationName" was not started');
      return;
    }

    final duration = DateTime.now().difference(startTime).inMilliseconds;
    _operationStarts.remove(operationName);

    // Track duration
    _operationDurations.putIfAbsent(operationName, () => []);
    _operationDurations[operationName]!.add(duration);

    // Log performance
    Logger.info('⏱️ $operationName: ${duration}ms');

    // Track in analytics
    AnalyticsService.trackPerformance(
      metricName: operationName,
      durationMs: duration,
      category: category,
    );

    // Warn if slow
    if (duration > 1000) {
      Logger.warning('Slow operation: $operationName took ${duration}ms');
    }
  }

  /// Measure operation performance
  static Future<T> measureAsync<T>({
    required String operationName,
    required Future<T> Function() operation,
    String? category,
  }) async {
    startOperation(operationName);
    try {
      return await operation();
    } finally {
      endOperation(operationName, category: category);
    }
  }

  /// Measure synchronous operation
  static T measureSync<T>({
    required String operationName,
    required T Function() operation,
    String? category,
  }) {
    startOperation(operationName);
    try {
      return operation();
    } finally {
      endOperation(operationName, category: category);
    }
  }

  /// Get average duration for an operation
  static double? getAverageDuration(String operationName) {
    final durations = _operationDurations[operationName];
    if (durations == null || durations.isEmpty) return null;

    return durations.reduce((a, b) => a + b) / durations.length;
  }

  /// Get statistics for an operation
  static OperationStats? getStats(String operationName) {
    final durations = _operationDurations[operationName];
    if (durations == null || durations.isEmpty) return null;

    final sorted = List<int>.from(durations)..sort();
    return OperationStats(
      operationName: operationName,
      count: durations.length,
      average: durations.reduce((a, b) => a + b) / durations.length,
      min: sorted.first,
      max: sorted.last,
      median: sorted[sorted.length ~/ 2],
      p95: sorted[(sorted.length * 0.95).toInt()],
      p99: sorted[(sorted.length * 0.99).toInt()],
    );
  }

  /// Clear all performance data
  static void clear() {
    _operationStarts.clear();
    _operationDurations.clear();
  }

  /// Print performance report
  static void printReport() {
    if (_operationDurations.isEmpty) {
      Logger.info('No performance data collected');
      return;
    }

    Logger.info('📊 Performance Report:');
    for (final operationName in _operationDurations.keys) {
      final stats = getStats(operationName);
      if (stats != null) {
        Logger.info('  $operationName:');
        Logger.info('    Calls: ${stats.count}');
        Logger.info('    Avg: ${stats.average.toStringAsFixed(2)}ms');
        Logger.info('    Min: ${stats.min}ms');
        Logger.info('    Max: ${stats.max}ms');
        Logger.info('    P95: ${stats.p95}ms');
      }
    }
  }
}

/// Operation statistics
class OperationStats {
  final String operationName;
  final int count;
  final double average;
  final int min;
  final int max;
  final int median;
  final int p95;
  final int p99;

  OperationStats({
    required this.operationName,
    required this.count,
    required this.average,
    required this.min,
    required this.max,
    required this.median,
    required this.p95,
    required this.p99,
  });

  @override
  String toString() {
    return 'OperationStats($operationName: count=$count, avg=${average.toStringAsFixed(2)}ms, '
        'min=${min}ms, max=${max}ms, p95=${p95}ms)';
  }
}

/// FPS Monitor - Track frame rendering performance
class FPSMonitor {
  static final List<Duration> _frameTimes = [];
  static bool _isMonitoring = false;
  static Timer? _reportTimer;

  /// Start FPS monitoring
  static void start({Duration reportInterval = const Duration(seconds: 5)}) {
    if (_isMonitoring) return;

    _isMonitoring = true;
    _frameTimes.clear();

    // Monitor frame callbacks
    SchedulerBinding.instance.addTimingsCallback(_onFrameTiming);

    // Periodic reporting
    _reportTimer = Timer.periodic(reportInterval, (_) {
      _reportFPS();
    });

    Logger.info('FPS monitoring started');
  }

  /// Stop FPS monitoring
  static void stop() {
    _isMonitoring = false;
    _reportTimer?.cancel();
    _reportTimer = null;
    Logger.info('FPS monitoring stopped');
  }

  /// Frame timing callback
  static void _onFrameTiming(List<FrameTiming> timings) {
    if (!_isMonitoring) return;

    for (final timing in timings) {
      _frameTimes.add(timing.totalSpan);
    }

    // Keep only last 120 frames (2 seconds at 60fps)
    if (_frameTimes.length > 120) {
      _frameTimes.removeRange(0, _frameTimes.length - 120);
    }
  }

  /// Report FPS metrics
  static void _reportFPS() {
    if (_frameTimes.isEmpty) return;

    // Calculate FPS
    final averageFrameTime = _frameTimes
            .map((d) => d.inMicroseconds)
            .reduce((a, b) => a + b) /
        _frameTimes.length;

    final fps = 1000000 / averageFrameTime; // Convert microseconds to FPS

    // Count dropped frames (>16.67ms = below 60fps)
    final droppedFrames = _frameTimes
        .where((d) => d.inMicroseconds > 16670)
        .length;

    final dropRate = (droppedFrames / _frameTimes.length) * 100;

    Logger.info('📺 FPS: ${fps.toStringAsFixed(1)} | Dropped: ${dropRate.toStringAsFixed(1)}%');

    // Track in analytics
    AnalyticsService.trackPerformance(
      metricName: 'fps',
      durationMs: fps.toInt(),
      category: 'rendering',
    );

    if (fps < 50) {
      Logger.warning('Low FPS detected: ${fps.toStringAsFixed(1)}');
    }
  }

  /// Get current FPS
  static double? getCurrentFPS() {
    if (_frameTimes.isEmpty) return null;

    final averageFrameTime = _frameTimes
            .map((d) => d.inMicroseconds)
            .reduce((a, b) => a + b) /
        _frameTimes.length;

    return 1000000 / averageFrameTime;
  }
}

/// Memory Monitor - Track memory usage
class MemoryMonitor {
  static Timer? _monitorTimer;
  static bool _isMonitoring = false;

  /// Start memory monitoring
  static void start({Duration checkInterval = const Duration(seconds: 10)}) {
    if (_isMonitoring) return;

    _isMonitoring = true;

    _monitorTimer = Timer.periodic(checkInterval, (_) {
      _checkMemory();
    });

    Logger.info('Memory monitoring started');
  }

  /// Stop memory monitoring
  static void stop() {
    _isMonitoring = false;
    _monitorTimer?.cancel();
    _monitorTimer = null;
    Logger.info('Memory monitoring stopped');
  }

  /// Check memory usage
  static void _checkMemory() {
    // Note: Memory monitoring is platform-specific
    // This is a placeholder for platform-specific implementation

    if (kDebugMode) {
      // In debug mode, you can use DevTools for memory profiling
      debugPrint('💾 Memory check (use DevTools for detailed analysis)');
    }

    // In production, integrate with:
    // - Firebase Performance Monitoring
    // - Custom backend analytics
    // - Platform-specific memory APIs
  }
}

/// Network Performance Monitor
class NetworkMonitor {
  static final Map<String, List<int>> _requestDurations = {};
  static final Map<String, int> _requestCounts = {};
  static final Map<String, int> _failureCounts = {};

  /// Track network request
  static void trackRequest({
    required String endpoint,
    required int durationMs,
    required bool success,
  }) {
    // Track duration
    _requestDurations.putIfAbsent(endpoint, () => []);
    _requestDurations[endpoint]!.add(durationMs);

    // Track count
    _requestCounts[endpoint] = (_requestCounts[endpoint] ?? 0) + 1;

    // Track failures
    if (!success) {
      _failureCounts[endpoint] = (_failureCounts[endpoint] ?? 0) + 1;
    }

    // Log slow requests
    if (durationMs > 3000) {
      Logger.warning('Slow network request: $endpoint took ${durationMs}ms');
    }

    // Track in analytics
    AnalyticsService.trackApiCall(
      endpoint: endpoint,
      durationMs: durationMs,
      statusCode: success ? 200 : 500,
      success: success,
    );
  }

  /// Get endpoint statistics
  static EndpointStats? getEndpointStats(String endpoint) {
    final durations = _requestDurations[endpoint];
    if (durations == null || durations.isEmpty) return null;

    final count = _requestCounts[endpoint] ?? 0;
    final failures = _failureCounts[endpoint] ?? 0;
    final average = durations.reduce((a, b) => a + b) / durations.length;
    final sorted = List<int>.from(durations)..sort();

    return EndpointStats(
      endpoint: endpoint,
      requestCount: count,
      failureCount: failures,
      successRate: ((count - failures) / count) * 100,
      averageDuration: average,
      minDuration: sorted.first,
      maxDuration: sorted.last,
      p95Duration: sorted[(sorted.length * 0.95).toInt()],
    );
  }

  /// Print network report
  static void printReport() {
    if (_requestDurations.isEmpty) {
      Logger.info('No network data collected');
      return;
    }

    Logger.info('🌐 Network Performance Report:');
    for (final endpoint in _requestDurations.keys) {
      final stats = getEndpointStats(endpoint);
      if (stats != null) {
        Logger.info('  $endpoint:');
        Logger.info('    Requests: ${stats.requestCount}');
        Logger.info('    Success Rate: ${stats.successRate.toStringAsFixed(1)}%');
        Logger.info('    Avg Duration: ${stats.averageDuration.toStringAsFixed(2)}ms');
        Logger.info('    P95 Duration: ${stats.p95Duration}ms');
      }
    }
  }

  /// Clear network data
  static void clear() {
    _requestDurations.clear();
    _requestCounts.clear();
    _failureCounts.clear();
  }
}

/// Endpoint statistics
class EndpointStats {
  final String endpoint;
  final int requestCount;
  final int failureCount;
  final double successRate;
  final double averageDuration;
  final int minDuration;
  final int maxDuration;
  final int p95Duration;

  EndpointStats({
    required this.endpoint,
    required this.requestCount,
    required this.failureCount,
    required this.successRate,
    required this.averageDuration,
    required this.minDuration,
    required this.maxDuration,
    required this.p95Duration,
  });

  @override
  String toString() {
    return 'EndpointStats($endpoint: requests=$requestCount, success=${successRate.toStringAsFixed(1)}%, '
        'avg=${averageDuration.toStringAsFixed(2)}ms, p95=${p95Duration}ms)';
  }
}
