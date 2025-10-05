import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'logger.dart';

/// Network Retry Utility
/// Provides exponential backoff retry logic for network requests
class NetworkRetry {
  /// Default retry configuration
  static const int defaultMaxAttempts = 3;
  static const Duration defaultInitialDelay = Duration(milliseconds: 500);
  static const double defaultBackoffMultiplier = 2.0;
  static const Duration defaultMaxDelay = Duration(seconds: 10);

  /// Execute a network request with retry logic
  ///
  /// Parameters:
  /// - [request]: Function that performs the network request
  /// - [maxAttempts]: Maximum number of retry attempts (default: 3)
  /// - [initialDelay]: Initial delay before first retry (default: 500ms)
  /// - [backoffMultiplier]: Multiplier for exponential backoff (default: 2.0)
  /// - [maxDelay]: Maximum delay between retries (default: 10s)
  /// - [retryIf]: Predicate to determine if error should trigger retry
  /// - [onRetry]: Callback when retry is attempted
  ///
  /// Returns: Result of successful request
  /// Throws: Last exception if all retries fail
  static Future<T> execute<T>({
    required Future<T> Function() request,
    int maxAttempts = defaultMaxAttempts,
    Duration initialDelay = defaultInitialDelay,
    double backoffMultiplier = defaultBackoffMultiplier,
    Duration maxDelay = defaultMaxDelay,
    bool Function(dynamic error)? retryIf,
    void Function(int attempt, dynamic error)? onRetry,
  }) async {
    int attempt = 0;
    Duration currentDelay = initialDelay;

    while (true) {
      attempt++;

      try {
        return await request();
      } catch (error) {
        // Check if we should retry
        final shouldRetry = _shouldRetry(error, retryIf);
        final hasAttemptsLeft = attempt < maxAttempts;

        if (!shouldRetry || !hasAttemptsLeft) {
          Logger.error(
            'Network request failed after $attempt attempts',
            error,
            error is Error ? error.stackTrace : null,
          );
          rethrow;
        }

        // Log retry
        Logger.warning(
          'Network request failed (attempt $attempt/$maxAttempts), retrying in ${currentDelay.inMilliseconds}ms...',
          error,
        );

        // Call retry callback
        if (onRetry != null) {
          onRetry(attempt, error);
        }

        // Wait before retrying
        await Future.delayed(currentDelay);

        // Calculate next delay with exponential backoff
        currentDelay = Duration(
          milliseconds: (currentDelay.inMilliseconds * backoffMultiplier).toInt(),
        );

        // Cap at max delay
        if (currentDelay > maxDelay) {
          currentDelay = maxDelay;
        }
      }
    }
  }

  /// Execute HTTP request with retry logic
  static Future<http.Response> executeHttp({
    required Future<http.Response> Function() request,
    int maxAttempts = defaultMaxAttempts,
    Duration initialDelay = defaultInitialDelay,
    double backoffMultiplier = defaultBackoffMultiplier,
    Duration maxDelay = defaultMaxDelay,
    void Function(int attempt, dynamic error)? onRetry,
  }) async {
    return execute<http.Response>(
      request: request,
      maxAttempts: maxAttempts,
      initialDelay: initialDelay,
      backoffMultiplier: backoffMultiplier,
      maxDelay: maxDelay,
      retryIf: _isRetryableHttpError,
      onRetry: onRetry,
    );
  }

  /// Check if error should trigger retry
  static bool _shouldRetry(dynamic error, bool Function(dynamic)? retryIf) {
    if (retryIf != null) {
      return retryIf(error);
    }

    // Default retry conditions
    return _isRetryableHttpError(error);
  }

  /// Check if error is a retryable HTTP error
  static bool _isRetryableHttpError(dynamic error) {
    // Network errors (timeout, connection refused, etc.)
    if (error is SocketException) return true;
    if (error is TimeoutException) return true;
    if (error is HttpException) return true;

    // HTTP response errors
    if (error is http.Response) {
      final statusCode = error.statusCode;

      // Retry on server errors (5xx)
      if (statusCode >= 500 && statusCode < 600) return true;

      // Retry on specific client errors
      if (statusCode == 408) return true; // Request Timeout
      if (statusCode == 429) return true; // Too Many Requests

      return false;
    }

    return false;
  }

  /// Retry with exponential backoff and jitter
  /// Adds randomness to prevent thundering herd problem
  static Future<T> executeWithJitter<T>({
    required Future<T> Function() request,
    int maxAttempts = defaultMaxAttempts,
    Duration initialDelay = defaultInitialDelay,
    double backoffMultiplier = defaultBackoffMultiplier,
    Duration maxDelay = defaultMaxDelay,
    bool Function(dynamic error)? retryIf,
    void Function(int attempt, dynamic error)? onRetry,
  }) async {
    int attempt = 0;
    Duration currentDelay = initialDelay;

    while (true) {
      attempt++;

      try {
        return await request();
      } catch (error) {
        final shouldRetry = _shouldRetry(error, retryIf);
        final hasAttemptsLeft = attempt < maxAttempts;

        if (!shouldRetry || !hasAttemptsLeft) {
          Logger.error(
            'Network request failed after $attempt attempts',
            error,
            error is Error ? error.stackTrace : null,
          );
          rethrow;
        }

        // Add jitter (random 0-50% of delay)
        final jitter = (currentDelay.inMilliseconds * 0.5 *
                       (DateTime.now().millisecondsSinceEpoch % 100) / 100).toInt();
        final delayWithJitter = Duration(
          milliseconds: currentDelay.inMilliseconds + jitter,
        );

        Logger.warning(
          'Network request failed (attempt $attempt/$maxAttempts), retrying in ${delayWithJitter.inMilliseconds}ms...',
          error,
        );

        if (onRetry != null) {
          onRetry(attempt, error);
        }

        await Future.delayed(delayWithJitter);

        currentDelay = Duration(
          milliseconds: (currentDelay.inMilliseconds * backoffMultiplier).toInt(),
        );

        if (currentDelay > maxDelay) {
          currentDelay = maxDelay;
        }
      }
    }
  }
}

/// Retry Policy Configuration
class RetryPolicy {
  final int maxAttempts;
  final Duration initialDelay;
  final double backoffMultiplier;
  final Duration maxDelay;
  final bool useJitter;

  const RetryPolicy({
    this.maxAttempts = NetworkRetry.defaultMaxAttempts,
    this.initialDelay = NetworkRetry.defaultInitialDelay,
    this.backoffMultiplier = NetworkRetry.defaultBackoffMultiplier,
    this.maxDelay = NetworkRetry.defaultMaxDelay,
    this.useJitter = false,
  });

  /// Aggressive retry policy (5 attempts, faster backoff)
  static const RetryPolicy aggressive = RetryPolicy(
    maxAttempts: 5,
    initialDelay: Duration(milliseconds: 200),
    backoffMultiplier: 1.5,
    maxDelay: Duration(seconds: 5),
    useJitter: true,
  );

  /// Conservative retry policy (2 attempts, slower backoff)
  static const RetryPolicy conservative = RetryPolicy(
    maxAttempts: 2,
    initialDelay: Duration(seconds: 1),
    backoffMultiplier: 3.0,
    maxDelay: Duration(seconds: 15),
    useJitter: false,
  );

  /// Default retry policy
  static const RetryPolicy standard = RetryPolicy();
}

/// Extension on Future for convenient retry syntax
extension RetryExtension<T> on Future<T> Function() {
  /// Retry this future with given policy
  Future<T> retry({RetryPolicy policy = RetryPolicy.standard}) {
    if (policy.useJitter) {
      return NetworkRetry.executeWithJitter(
        request: this,
        maxAttempts: policy.maxAttempts,
        initialDelay: policy.initialDelay,
        backoffMultiplier: policy.backoffMultiplier,
        maxDelay: policy.maxDelay,
      );
    } else {
      return NetworkRetry.execute(
        request: this,
        maxAttempts: policy.maxAttempts,
        initialDelay: policy.initialDelay,
        backoffMultiplier: policy.backoffMultiplier,
        maxDelay: policy.maxDelay,
      );
    }
  }
}
