import 'dart:async';
import '../exceptions/app_exception.dart';
import 'exception_handler.dart';
import 'app_logger.dart';

/// Retry Strategy Utility
///
/// Provides configurable retry logic for operations that may fail
class RetryStrategy {
  /// Execute operation with exponential backoff retry
  static Future<T> executeWithRetry<T>({
    required Future<T> Function() operation,
    int maxAttempts = 3,
    Duration initialDelay = const Duration(seconds: 1),
    Duration maxDelay = const Duration(seconds: 30),
    double backoffMultiplier = 2.0,
    bool Function(dynamic error)? retryIf,
    void Function(int attempt, Duration delay, dynamic error)? onRetry,
  }) async {
    int attempt = 0;
    Duration currentDelay = initialDelay;

    while (true) {
      attempt++;

      try {
        AppLogger.debug('[RetryStrategy] Attempt $attempt/$maxAttempts');
        return await operation();
      } catch (e, stackTrace) {
        // Convert to AppException
        final appException = ExceptionHandler.handle(e, stackTrace);

        // Check if we should retry
        final shouldRetry = retryIf?.call(appException) ??
                           ExceptionHandler.isRecoverable(appException);

        if (!shouldRetry || attempt >= maxAttempts) {
          AppLogger.error('[RetryStrategy] Failed after $attempt attempts');
          rethrow;
        }

        // Calculate delay with exponential backoff
        if (attempt > 1) {
          currentDelay = Duration(
            milliseconds: (currentDelay.inMilliseconds * backoffMultiplier).toInt(),
          );
          if (currentDelay > maxDelay) {
            currentDelay = maxDelay;
          }
        }

        AppLogger.warning(
          '[RetryStrategy] Attempt $attempt failed, retrying in ${currentDelay.inSeconds}s',
        );

        // Notify retry callback
        onRetry?.call(attempt, currentDelay, appException);

        // Wait before retry
        await Future.delayed(currentDelay);
      }
    }
  }

  /// Execute operation with simple retry (no backoff)
  static Future<T> executeWithSimpleRetry<T>({
    required Future<T> Function() operation,
    int maxAttempts = 3,
    Duration retryDelay = const Duration(seconds: 2),
    bool Function(dynamic error)? retryIf,
  }) async {
    return executeWithRetry<T>(
      operation: operation,
      maxAttempts: maxAttempts,
      initialDelay: retryDelay,
      maxDelay: retryDelay,
      backoffMultiplier: 1.0, // No exponential backoff
      retryIf: retryIf,
    );
  }

  /// Execute operation with timeout
  static Future<T> executeWithTimeout<T>({
    required Future<T> Function() operation,
    Duration timeout = const Duration(seconds: 30),
    String? operationName,
  }) async {
    try {
      return await operation().timeout(
        timeout,
        onTimeout: () {
          throw TimeoutException(
            message: operationName != null
                ? '$operationName timed out after ${timeout.inSeconds}s'
                : 'Operation timed out after ${timeout.inSeconds}s',
          );
        },
      );
    } catch (e, stackTrace) {
      throw ExceptionHandler.handle(e, stackTrace);
    }
  }

  /// Execute operation with both retry and timeout
  static Future<T> executeWithRetryAndTimeout<T>({
    required Future<T> Function() operation,
    int maxAttempts = 3,
    Duration timeout = const Duration(seconds: 30),
    Duration initialRetryDelay = const Duration(seconds: 1),
    String? operationName,
  }) async {
    return executeWithRetry<T>(
      operation: () => executeWithTimeout<T>(
        operation: operation,
        timeout: timeout,
        operationName: operationName,
      ),
      maxAttempts: maxAttempts,
      initialDelay: initialRetryDelay,
    );
  }

  /// Execute multiple operations in parallel with retry
  static Future<List<T>> executeAllWithRetry<T>({
    required List<Future<T> Function()> operations,
    int maxAttempts = 3,
    Duration initialDelay = const Duration(seconds: 1),
  }) async {
    final futures = operations.map((operation) {
      return executeWithRetry<T>(
        operation: operation,
        maxAttempts: maxAttempts,
        initialDelay: initialDelay,
      );
    }).toList();

    return Future.wait(futures);
  }

  /// Execute operation with circuit breaker pattern
  static Future<T> executeWithCircuitBreaker<T>({
    required Future<T> Function() operation,
    required String operationId,
    int failureThreshold = 5,
    Duration resetTimeout = const Duration(minutes: 1),
  }) async {
    final state = _CircuitBreakerState.get(operationId);

    // Check if circuit is open
    if (state.isOpen) {
      if (DateTime.now().difference(state.lastFailureTime!) < resetTimeout) {
        throw BusinessException(
          message: 'Service temporarily unavailable. Please try again later.',
          code: 'CIRCUIT_BREAKER_OPEN',
        );
      } else {
        // Try to reset
        state.halfOpen();
      }
    }

    try {
      final result = await operation();
      state.recordSuccess();
      return result;
    } catch (e, stackTrace) {
      state.recordFailure();

      if (state.failureCount >= failureThreshold) {
        state.open();
        AppLogger.error(
          '[CircuitBreaker] Circuit opened for $operationId after $failureThreshold failures',
        );
      }

      throw ExceptionHandler.handle(e, stackTrace);
    }
  }
}

/// Circuit Breaker State
class _CircuitBreakerState {
  static final Map<String, _CircuitBreakerState> _states = {};

  int failureCount = 0;
  DateTime? lastFailureTime;
  bool isOpen = false;

  static _CircuitBreakerState get(String id) {
    return _states.putIfAbsent(id, () => _CircuitBreakerState());
  }

  void recordSuccess() {
    failureCount = 0;
    isOpen = false;
  }

  void recordFailure() {
    failureCount++;
    lastFailureTime = DateTime.now();
  }

  void open() {
    isOpen = true;
  }

  void halfOpen() {
    isOpen = false;
    failureCount = 0;
  }
}

/// Retry Policy Configuration
class RetryPolicy {
  final int maxAttempts;
  final Duration initialDelay;
  final Duration maxDelay;
  final double backoffMultiplier;

  const RetryPolicy({
    this.maxAttempts = 3,
    this.initialDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
    this.backoffMultiplier = 2.0,
  });

  /// Aggressive retry (quick retries, more attempts)
  static const RetryPolicy aggressive = RetryPolicy(
    maxAttempts: 5,
    initialDelay: Duration(milliseconds: 500),
    maxDelay: Duration(seconds: 10),
    backoffMultiplier: 1.5,
  );

  /// Conservative retry (slower retries, fewer attempts)
  static const RetryPolicy conservative = RetryPolicy(
    maxAttempts: 3,
    initialDelay: Duration(seconds: 2),
    maxDelay: Duration(seconds: 60),
    backoffMultiplier: 3.0,
  );

  /// Default retry policy
  static const RetryPolicy standard = RetryPolicy(
    maxAttempts: 3,
    initialDelay: Duration(seconds: 1),
    maxDelay: Duration(seconds: 30),
    backoffMultiplier: 2.0,
  );
}
