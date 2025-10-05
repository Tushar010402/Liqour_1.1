import 'dart:async';

/// Debouncer - Best Practice Debouncing Utility
/// Delays function execution until after wait time has elapsed since last call

class Debouncer {
  final Duration delay;
  Timer? _timer;

  Debouncer({this.delay = const Duration(milliseconds: 500)});

  /// Run function after debounce delay
  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  /// Cancel pending execution
  void cancel() {
    _timer?.cancel();
  }

  /// Dispose debouncer
  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  /// Check if debouncer is active
  bool get isActive => _timer?.isActive ?? false;
}

/// Callback type
typedef VoidCallback = void Function();

/// Throttler - Best Practice Throttling Utility
/// Ensures function is called at most once per time period

class Throttler {
  final Duration delay;
  Timer? _timer;
  bool _isReady = true;

  Throttler({this.delay = const Duration(milliseconds: 500)});

  /// Run function with throttle (at most once per delay period)
  void run(VoidCallback action) {
    if (_isReady) {
      _isReady = false;
      action();

      _timer = Timer(delay, () {
        _isReady = true;
      });
    }
  }

  /// Cancel pending reset
  void cancel() {
    _timer?.cancel();
    _isReady = true;
  }

  /// Dispose throttler
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _isReady = true;
  }

  /// Check if throttler is ready
  bool get isReady => _isReady;
}

/// Utility class for common debounce/throttle patterns
class DebouncerHelper {
  // Private constructor
  DebouncerHelper._();

  /// Create debouncer for search input (300ms delay)
  static Debouncer searchDebouncer() {
    return Debouncer(delay: const Duration(milliseconds: 300));
  }

  /// Create debouncer for text input (500ms delay)
  static Debouncer textInputDebouncer() {
    return Debouncer(delay: const Duration(milliseconds: 500));
  }

  /// Create debouncer for API calls (800ms delay)
  static Debouncer apiDebouncer() {
    return Debouncer(delay: const Duration(milliseconds: 800));
  }

  /// Create throttler for scroll events (100ms delay)
  static Throttler scrollThrottler() {
    return Throttler(delay: const Duration(milliseconds: 100));
  }

  /// Create throttler for button clicks (1000ms delay)
  static Throttler buttonThrottler() {
    return Throttler(delay: const Duration(milliseconds: 1000));
  }

  /// Create throttler for API calls (2000ms delay)
  static Throttler apiThrottler() {
    return Throttler(delay: const Duration(milliseconds: 2000));
  }
}
