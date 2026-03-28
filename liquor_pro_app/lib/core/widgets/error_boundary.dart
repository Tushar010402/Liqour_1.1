import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';
import '../exceptions/app_exception.dart';
import '../utils/exception_handler.dart';
import '../utils/app_logger.dart';

/// Error Boundary Widget - Catches and displays errors gracefully
/// Prevents white screen crashes by providing fallback UI
class ErrorBoundary extends StatefulWidget {
  final Widget child;
  final Widget? fallback;
  final void Function(Object error, StackTrace stackTrace)? onError;

  const ErrorBoundary({
    super.key,
    required this.child,
    this.fallback,
    this.onError,
  });

  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  AppException? _error;

  @override
  void initState() {
    super.initState();
    debugPrint('🛡️ [ErrorBoundary] initState - setting up error handler');
    // Set up error handler with proper async handling
    FlutterError.onError = (FlutterErrorDetails details) {
      debugPrint('🛡️ [ErrorBoundary] FlutterError.onError TRIGGERED!');
      debugPrint('🛡️ [ErrorBoundary] Error: ${details.exception}');
      debugPrint('🛡️ [ErrorBoundary] Stack: ${details.stack}');

      if (mounted) {
        // Ignore overflow errors - they're visual warnings, not crashes
        final errorMessage = details.exception.toString().toLowerCase();
        final isOverflowError = errorMessage.contains('overflowed') ||
                                errorMessage.contains('renderflex') ||
                                errorMessage.contains('renderbox');

        if (isOverflowError) {
          // Just log overflow errors, don't show error screen
          AppLogger.warning('Overflow warning: ${details.exception}');
          return;
        }

        final appException = ExceptionHandler.handle(details.exception, details.stack);

        // Use addPostFrameCallback to avoid setState during build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            debugPrint('🛡️ [ErrorBoundary] Setting _error state...');
            setState(() {
              _error = appException;
            });
          }
        });

        // Log the error
        ExceptionHandler.logException(appException, context: 'ErrorBoundary');

        // Call custom error handler if provided
        if (widget.onError != null && details.stack != null) {
          widget.onError!(details.exception, details.stack!);
        }
      }
    };
  }

  void _retry() {
    setState(() {
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('🛡️ [ErrorBoundary] build() called, _error: ${_error != null ? "HAS ERROR" : "null"}');
    if (_error != null) {
      debugPrint('🛡️ [ErrorBoundary] Showing error UI: ${_error!.userMessage}');
      return widget.fallback ?? _buildDefaultErrorUI();
    }

    debugPrint('🛡️ [ErrorBoundary] Returning child widget');
    return widget.child;
  }

  Widget _buildDefaultErrorUI() {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Error Icon
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha:0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.error_outline,
                    size: 64,
                    color: AppColors.error,
                  ),
                ),

                const SizedBox(height: 24),

                // Error Title
                Text(
                  'Oops! Something went wrong',
                  style: AppTextStyles.h5.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 12),

                // Error Message
                Text(
                  _error!.userMessage,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 8),

                // Error Details (in debug mode only)
                if (_error != null && const bool.fromEnvironment('dart.vm.product') == false) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Error Details:',
                          style: AppTextStyles.bodySmall.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _error!.technicalDetails,
                          style: AppTextStyles.bodySmall.copyWith(
                            fontFamily: 'monospace',
                            fontSize: 10,
                          ),
                          maxLines: 10,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 32),

                // Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Retry Button
                    ElevatedButton.icon(
                      onPressed: _retry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try Again'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cs.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Go Home Button
                    OutlinedButton.icon(
                      onPressed: () {
                        // Safely check if Navigator exists to prevent recursive errors
                        final navigator = Navigator.maybeOf(context);
                        if (navigator != null && navigator.canPop()) {
                          navigator.popUntil((route) => route.isFirst);
                        }
                        _retry();
                      },
                      icon: const Icon(Icons.home),
                      label: const Text('Go Home'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cs.primary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Error Boundary for specific widgets
/// Use this to wrap risky widgets that might throw errors
class WidgetErrorBoundary extends StatelessWidget {
  final Widget child;
  final String? errorMessage;

  const WidgetErrorBoundary({
    super.key,
    required this.child,
    this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    try {
      return child;
    } catch (error, stackTrace) {
      final appException = ExceptionHandler.handle(error, stackTrace);
      ExceptionHandler.logException(appException, context: 'WidgetErrorBoundary');

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha:0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.error.withValues(alpha:0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: AppColors.error,
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              errorMessage ?? appException.userMessage,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.error,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
  }
}
