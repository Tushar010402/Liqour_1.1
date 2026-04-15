/// Logger Alias - Compatibility wrapper for AppLogger
/// Provides a simplified Logger interface that uses AppLogger internally
/// OPTIMIZED: Eliminated double logging and added kDebugMode guards
library;
import 'package:flutter/foundation.dart';
import 'app_logger.dart';
import '../config/debug_performance_config.dart';

class Logger {
  Logger._();

  static void info(String message, [dynamic data]) {
    // OPTIMIZATION: Gated behind verbose flag to reduce console I/O
    if (!DebugPerformanceConfig.verboseDebugPrints && kDebugMode) return;
    if (!kDebugMode) return;

    // FIXED: Single log call instead of double logging
    if (data != null) {
      AppLogger.info('$message | Data: $data');
    } else {
      AppLogger.info(message);
    }
  }

  static void debug(String message, [dynamic data]) {
    // OPTIMIZATION: Gated behind verbose flag to reduce console I/O
    if (!DebugPerformanceConfig.verboseDebugPrints && kDebugMode) return;
    if (!kDebugMode) return;

    // FIXED: Single log call instead of double logging
    if (data != null) {
      AppLogger.debug('$message | Data: $data');
    } else {
      AppLogger.debug(message);
    }
  }

  static void warning(String message, [dynamic error]) {
    // OPTIMIZATION: Only log in debug mode for warnings
    // Errors should always be logged, but warnings can be silenced in production
    if (!kDebugMode) return;

    // FIXED: Single log call instead of double logging
    if (error != null) {
      AppLogger.warning('$message | Error: $error');
    } else {
      AppLogger.warning(message);
    }
  }

  static void error(String message, [dynamic error, StackTrace? stackTrace]) {
    // IMPORTANT: Errors are always logged even in production for crash reporting
    AppLogger.error(message, error, stackTrace);
  }
}
