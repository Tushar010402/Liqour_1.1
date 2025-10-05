/// Logger Alias - Compatibility wrapper for AppLogger
/// Provides a simplified Logger interface that uses AppLogger internally
import 'app_logger.dart';

class Logger {
  Logger._();

  static void info(String message, [dynamic data]) {
    AppLogger.info(message);
    if (data != null) {
      AppLogger.debug('Data: $data');
    }
  }

  static void debug(String message, [dynamic data]) {
    AppLogger.debug(message);
    if (data != null) {
      AppLogger.debug('Data: $data');
    }
  }

  static void warning(String message, [dynamic error]) {
    AppLogger.warning(message);
    if (error != null) {
      AppLogger.warning('Error: $error');
    }
  }

  static void error(String message, [dynamic error, StackTrace? stackTrace]) {
    AppLogger.error(message, error, stackTrace);
  }
}
