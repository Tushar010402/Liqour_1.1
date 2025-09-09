import 'dart:async';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';

import 'logger.dart';
import 'cache_manager.dart';

/// Performance optimization utilities and monitoring
class PerformanceOptimizer {
  static PerformanceOptimizer? _instance;
  static PerformanceOptimizer get instance => _instance ??= PerformanceOptimizer._internal();
  
  PerformanceOptimizer._internal();

  final Map<String, PerformanceMetric> _metrics = {};
  final Map<String, Timer> _timers = {};
  final List<PerformanceEvent> _events = [];
  
  bool _isMonitoring = false;
  Timer? _memoryMonitorTimer;
  Timer? _fpsMonitorTimer;

  /// Initialize performance monitoring
  void initialize({bool enableMonitoring = true}) {
    if (_isMonitoring) return;

    AppLogger.info('⚡ Initializing PerformanceOptimizer...');

    if (enableMonitoring && !kDebugMode) {
      startMonitoring();
    }

    // Setup frame callback monitoring
    if (kDebugMode) {
      _setupFrameMonitoring();
    }

    AppLogger.info('✅ PerformanceOptimizer initialized');
  }

  /// Start performance monitoring
  void startMonitoring() {
    if (_isMonitoring) return;

    _isMonitoring = true;
    AppLogger.info('📊 Started performance monitoring');

    // Monitor memory usage every 30 seconds
    _memoryMonitorTimer = Timer.periodic(
      const Duration(seconds: 30),
      _monitorMemoryUsage,
    );

    // Monitor FPS every 5 seconds
    _fpsMonitorTimer = Timer.periodic(
      const Duration(seconds: 5),
      _monitorFrameRate,
    );
  }

  /// Stop performance monitoring
  void stopMonitoring() {
    if (!_isMonitoring) return;

    _isMonitoring = false;
    _memoryMonitorTimer?.cancel();
    _fpsMonitorTimer?.cancel();

    AppLogger.info('⏹️ Stopped performance monitoring');
  }

  /// Start measuring performance for a specific operation
  void startMeasurement(String operationName, {Map<String, dynamic>? metadata}) {
    final metric = PerformanceMetric(
      name: operationName,
      startTime: DateTime.now(),
      metadata: metadata ?? {},
    );

    _metrics[operationName] = metric;
    
    AppLogger.debug('⏱️ Started measuring: $operationName');
  }

  /// End measurement and log results
  PerformanceMetric? endMeasurement(String operationName, {
    bool logResult = true,
    Map<String, dynamic>? additionalData,
  }) {
    final metric = _metrics.remove(operationName);
    
    if (metric == null) {
      AppLogger.warning('No measurement found for: $operationName');
      return null;
    }

    metric.endTime = DateTime.now();
    metric.duration = metric.endTime!.difference(metric.startTime);
    
    if (additionalData != null) {
      metric.metadata.addAll(additionalData);
    }

    if (logResult) {
      AppLogger.performance(
        operationName, 
        metric.duration!, 
        metric.metadata,
      );
    }

    // Store event for analysis
    _events.add(PerformanceEvent(
      name: operationName,
      duration: metric.duration!,
      timestamp: metric.endTime!,
      metadata: Map.from(metric.metadata),
    ));

    // Keep only last 100 events
    if (_events.length > 100) {
      _events.removeAt(0);
    }

    return metric;
  }

  /// Measure async operation
  Future<T> measureAsync<T>(
    String operationName,
    Future<T> Function() operation, {
    Map<String, dynamic>? metadata,
  }) async {
    startMeasurement(operationName, metadata: metadata);
    
    try {
      final result = await operation();
      endMeasurement(operationName, additionalData: {'success': true});
      return result;
    } catch (error) {
      endMeasurement(operationName, additionalData: {
        'success': false,
        'error': error.toString(),
      });
      rethrow;
    }
  }

  /// Measure sync operation
  T measureSync<T>(
    String operationName,
    T Function() operation, {
    Map<String, dynamic>? metadata,
  }) {
    startMeasurement(operationName, metadata: metadata);
    
    try {
      final result = operation();
      endMeasurement(operationName, additionalData: {'success': true});
      return result;
    } catch (error) {
      endMeasurement(operationName, additionalData: {
        'success': false,
        'error': error.toString(),
      });
      rethrow;
    }
  }

  /// Batch process items to avoid blocking UI
  Future<List<R>> processBatch<T, R>(
    List<T> items,
    Future<R> Function(T) processor, {
    int batchSize = 10,
    Duration batchDelay = const Duration(milliseconds: 16),
    String? operationName,
  }) async {
    final results = <R>[];
    final totalItems = items.length;
    final name = operationName ?? 'batch_process';

    startMeasurement(name, metadata: {
      'total_items': totalItems,
      'batch_size': batchSize,
    });

    for (int i = 0; i < totalItems; i += batchSize) {
      final endIndex = min(i + batchSize, totalItems);
      final batch = items.sublist(i, endIndex);

      // Process batch
      final batchResults = await Future.wait(
        batch.map(processor),
      );

      results.addAll(batchResults);

      // Yield to UI thread
      if (i + batchSize < totalItems) {
        await Future.delayed(batchDelay);
      }

      // Log progress for large batches
      if (totalItems > 100 && (i + batchSize) % (batchSize * 10) == 0) {
        AppLogger.debug('📊 Batch progress', {
          'operation': name,
          'processed': i + batchSize,
          'total': totalItems,
          'progress': '${((i + batchSize) / totalItems * 100).toStringAsFixed(1)}%',
        });
      }
    }

    endMeasurement(name, additionalData: {
      'processed_items': results.length,
      'success': true,
    });

    return results;
  }

  /// Optimize heavy computation by running in isolate
  Future<R> computeHeavy<T, R>(
    ComputeCallback<T, R> callback,
    T message, {
    String? debugLabel,
  }) async {
    final operationName = 'isolate_compute_${debugLabel ?? 'unknown'}';
    
    return await measureAsync(operationName, () async {
      return await compute(callback, message, debugLabel: debugLabel);
    }, metadata: {'isolate': true});
  }

  /// Debounce function calls
  void debounce(String key, VoidCallback callback, Duration delay) {
    _timers[key]?.cancel();
    _timers[key] = Timer(delay, callback);
  }

  /// Throttle function calls
  void throttle(String key, VoidCallback callback, Duration interval) {
    if (_timers[key]?.isActive == true) return;
    
    callback();
    _timers[key] = Timer(interval, () {
      _timers.remove(key);
    });
  }

  /// Preload critical resources
  Future<void> preloadResources({
    List<String>? imageUrls,
    List<String>? fontAssets,
    List<Future<void> Function()>? customPreloaders,
  }) async {
    final preloadTasks = <Future<void>>[];

    // Preload images
    if (imageUrls != null && imageUrls.isNotEmpty) {
      preloadTasks.add(
        measureAsync('preload_images', () async {
          await PremiumCacheManager.instance.preloadImages(imageUrls);
        }),
      );
    }

    // Preload fonts
    if (fontAssets != null) {
      for (final fontAsset in fontAssets) {
        preloadTasks.add(
          measureAsync('preload_font_$fontAsset', () async {
            await rootBundle.load(fontAsset);
          }),
        );
      }
    }

    // Custom preloaders
    if (customPreloaders != null) {
      preloadTasks.addAll(
        customPreloaders.map((preloader) => 
          measureAsync('custom_preloader', preloader),
        ),
      );
    }

    if (preloadTasks.isNotEmpty) {
      AppLogger.info('🚀 Starting resource preloading', {
        'tasks': preloadTasks.length,
      });

      await Future.wait(preloadTasks);

      AppLogger.info('✅ Resource preloading completed');
    }
  }

  /// Optimize list performance with viewport-based rendering
  Widget optimizeListView({
    required int itemCount,
    required Widget Function(BuildContext, int) itemBuilder,
    double? itemExtent,
    ScrollController? controller,
  }) {
    // This would return a custom ListView implementation
    // For now, returning a placeholder
    throw UnimplementedError('Custom ListView implementation needed');
  }

  /// Monitor frame rendering performance
  void _setupFrameMonitoring() {
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    if (!kDebugMode) return;

    for (final timing in timings) {
      final frameDuration = timing.totalSpan;
      final targetFrameDuration = Duration(
        microseconds: (1000000 / 60).round(), // 60 FPS target
      );

      if (frameDuration > targetFrameDuration) {
        AppLogger.warning('🐌 Slow frame detected', {
          'frame_duration_ms': frameDuration.inMilliseconds,
          'target_ms': targetFrameDuration.inMilliseconds,
          'rasterDuration': timing.rasterDuration.inMicroseconds,
          'buildDuration': timing.buildDuration.inMicroseconds,
        });
      }
    }
  }

  /// Monitor memory usage
  void _monitorMemoryUsage(Timer timer) {
    try {
      // This would use platform-specific memory monitoring
      // For now, just log a placeholder
      AppLogger.debug('📊 Memory usage monitoring tick');
    } catch (error) {
      AppLogger.error('Memory monitoring failed', error);
    }
  }

  /// Monitor frame rate
  void _monitorFrameRate(Timer timer) {
    try {
      // This would calculate actual FPS
      // For now, just log a placeholder
      AppLogger.debug('📊 Frame rate monitoring tick');
    } catch (error) {
      AppLogger.error('Frame rate monitoring failed', error);
    }
  }

  /// Get performance statistics
  Map<String, dynamic> getStatistics() {
    final recentEvents = _events
        .where((event) => event.timestamp
            .isAfter(DateTime.now().subtract(const Duration(minutes: 5))))
        .toList();

    return {
      'monitoring_active': _isMonitoring,
      'active_measurements': _metrics.length,
      'total_events': _events.length,
      'recent_events': recentEvents.length,
      'average_operation_time': _calculateAverageOperationTime(recentEvents),
      'slowest_operations': _getSlowestOperations(recentEvents, limit: 5),
    };
  }

  /// Calculate average operation time
  double _calculateAverageOperationTime(List<PerformanceEvent> events) {
    if (events.isEmpty) return 0.0;
    
    final totalMs = events
        .map((e) => e.duration.inMilliseconds)
        .reduce((a, b) => a + b);
    
    return totalMs / events.length;
  }

  /// Get slowest operations
  List<Map<String, dynamic>> _getSlowestOperations(
    List<PerformanceEvent> events, {
    int limit = 5,
  }) {
    final sortedEvents = List<PerformanceEvent>.from(events)
      ..sort((a, b) => b.duration.compareTo(a.duration));

    return sortedEvents
        .take(limit)
        .map((event) => {
          'name': event.name,
          'duration_ms': event.duration.inMilliseconds,
          'timestamp': event.timestamp.toIso8601String(),
        })
        .toList();
  }

  /// Dispose resources
  void dispose() {
    stopMonitoring();
    _timers.forEach((key, timer) => timer.cancel());
    _timers.clear();
    _metrics.clear();
    _events.clear();
    
    AppLogger.info('⚡ PerformanceOptimizer disposed');
  }
}

/// Performance metric data class
class PerformanceMetric {
  final String name;
  final DateTime startTime;
  DateTime? endTime;
  Duration? duration;
  final Map<String, dynamic> metadata;

  PerformanceMetric({
    required this.name,
    required this.startTime,
    this.endTime,
    this.duration,
    required this.metadata,
  });

  bool get isCompleted => endTime != null && duration != null;
  
  Duration get elapsed => endTime?.difference(startTime) ?? 
      DateTime.now().difference(startTime);
}

/// Performance event data class
class PerformanceEvent {
  final String name;
  final Duration duration;
  final DateTime timestamp;
  final Map<String, dynamic> metadata;

  const PerformanceEvent({
    required this.name,
    required this.duration,
    required this.timestamp,
    required this.metadata,
  });
}

/// Performance optimization extensions
extension PerformanceWidgetExtensions on Widget {
  /// Wrap widget with performance monitoring
  Widget withPerformanceMonitoring(String name) {
    return PerformanceMonitoringWidget(
      name: name,
      child: this,
    );
  }
}

/// Widget wrapper for performance monitoring
class PerformanceMonitoringWidget extends StatefulWidget {
  final String name;
  final Widget child;

  const PerformanceMonitoringWidget({
    super.key,
    required this.name,
    required this.child,
  });

  @override
  State<PerformanceMonitoringWidget> createState() => _PerformanceMonitoringWidgetState();
}

class _PerformanceMonitoringWidgetState extends State<PerformanceMonitoringWidget> {
  @override
  void initState() {
    super.initState();
    PerformanceOptimizer.instance.startMeasurement(
      'widget_${widget.name}_build',
    );
  }

  @override
  void dispose() {
    PerformanceOptimizer.instance.endMeasurement(
      'widget_${widget.name}_build',
      logResult: false,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// Performance constants
class PerformanceConstants {
  // Target performance thresholds
  static const Duration targetFrameTime = Duration(milliseconds: 16); // 60 FPS
  static const Duration slowFrameThreshold = Duration(milliseconds: 32); // 30 FPS
  static const Duration verySlowFrameThreshold = Duration(milliseconds: 50); // 20 FPS
  
  // Memory thresholds (in MB)
  static const int lowMemoryThreshold = 50;
  static const int highMemoryThreshold = 200;
  static const int criticalMemoryThreshold = 500;
  
  // Network operation thresholds
  static const Duration fastNetworkThreshold = Duration(milliseconds: 500);
  static const Duration slowNetworkThreshold = Duration(seconds: 2);
  static const Duration verySlowNetworkThreshold = Duration(seconds: 5);
  
  // UI operation thresholds
  static const Duration fastUIThreshold = Duration(milliseconds: 16);
  static const Duration slowUIThreshold = Duration(milliseconds: 100);
  static const Duration verySlowUIThreshold = Duration(milliseconds: 500);
  
  // Batch processing defaults
  static const int defaultBatchSize = 20;
  static const Duration defaultBatchDelay = Duration(milliseconds: 16);
  
  // Cache performance settings
  static const int maxCachePreloadItems = 50;
  static const Duration cachePreloadTimeout = Duration(seconds: 10);
}

/// Performance utilities
class PerformanceUtils {
  /// Check if device is low-end based on performance metrics
  static bool isLowEndDevice() {
    // This would check device capabilities
    return false; // Placeholder
  }

  /// Get recommended settings for current device
  static Map<String, dynamic> getRecommendedSettings() {
    final isLowEnd = isLowEndDevice();
    
    return {
      'enable_animations': !isLowEnd,
      'image_quality': isLowEnd ? 'medium' : 'high',
      'cache_size': isLowEnd ? 'small' : 'large',
      'preload_images': !isLowEnd,
      'enable_blur_effects': !isLowEnd,
      'reduce_motion': isLowEnd,
    };
  }

  /// Format duration for display
  static String formatDuration(Duration duration) {
    if (duration.inMilliseconds < 1000) {
      return '${duration.inMilliseconds}ms';
    } else if (duration.inSeconds < 60) {
      return '${(duration.inMilliseconds / 1000).toStringAsFixed(2)}s';
    } else {
      return '${duration.inMinutes}m ${duration.inSeconds % 60}s';
    }
  }

  /// Get performance color based on duration
  static String getPerformanceColor(Duration duration, Duration threshold) {
    if (duration <= threshold) return 'green';
    if (duration <= threshold * 2) return 'yellow';
    return 'red';
  }
}