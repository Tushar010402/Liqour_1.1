import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../utils/snackbar_helper.dart';
import '../utils/app_logger.dart';

/// Interceptor to handle backend limitations and error responses
/// Provides user-friendly messages for missing features
class ErrorHandlingInterceptor extends Interceptor {
  final BuildContext? context;

  // Track which warnings have been shown to avoid spam
  static final Map<String, DateTime> _lastWarningShown = {};
  static const Duration _warningCooldown = Duration(minutes: 5);

  ErrorHandlingInterceptor({this.context});

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    AppLogger.error('API Error: ${err.response?.statusCode} - ${err.message}');

    // Handle different error codes
    switch (err.response?.statusCode) {
      case 501:
        _handle501NotImplemented(err);
        break;
      case 404:
        _handle404NotFound(err);
        break;
      case 400:
        _handle400BadRequest(err);
        break;
      case 403:
        _handle403Forbidden(err);
        break;
      case 500:
        _handle500ServerError(err);
        break;
      case 502:
      case 503:
      case 504:
        _handleServiceUnavailable(err);
        break;
      default:
        _handleGenericError(err);
    }

    handler.next(err);
  }

  /// Handle 501 Not Implemented responses
  void _handle501NotImplemented(DioException err) {
    final endpoint = err.requestOptions.path;
    String message = 'This feature is not implemented in the backend.';
    String workaround = '';

    // Provide specific messages for known unimplemented features
    if (endpoint.contains('/ocr')) {
      message = 'OCR/Image scanning is not available';
      workaround = 'Please enter sale details manually.';
      _showOCRAlternative();
    } else if (endpoint.contains('/invoice')) {
      message = 'Invoice generation is not implemented';
      workaround = 'Invoices are generated locally in the app.';
    } else if (endpoint.contains('/tax')) {
      message = 'Tax calculation is not available on server';
      workaround = 'Tax is calculated locally using standard GST rates.';
    } else if (endpoint.contains('/stock/deduct')) {
      message = 'Stock deduction is not implemented';
      workaround = 'Please manually adjust inventory after sales.';
    } else if (endpoint.contains('/payment/validate')) {
      message = 'Payment validation is not available';
      workaround = 'Record payments manually and verify separately.';
    } else if (endpoint.contains('/notification')) {
      message = 'Notification service is not implemented';
      workaround = 'Notifications are not available at this time.';
    }

    _showWarningIfNeeded(
      '501_$endpoint',
      message,
      workaround,
      Icons.construction,
    );

    // Log for debugging
    AppLogger.warning('501 Not Implemented: $endpoint');
  }

  /// Handle 404 Not Found responses
  void _handle404NotFound(DioException err) {
    final endpoint = err.requestOptions.path;

    // Check if it's a known missing endpoint
    if (endpoint.contains('/saas-brands')) {
      _showWarningIfNeeded(
        '404_saas_brands',
        'Brand catalog endpoint not found',
        'Using local brand data instead.',
        Icons.error_outline,
      );
    } else if (endpoint.contains('/reports')) {
      _showWarningIfNeeded(
        '404_reports',
        'Report generation not available',
        'Reports are not implemented in the backend.',
        Icons.assessment,
      );
    } else {
      _showWarningIfNeeded(
        '404_generic',
        'Resource not found',
        'The requested data could not be found.',
        Icons.search_off,
      );
    }
  }

  /// Handle 400 Bad Request responses
  void _handle400BadRequest(DioException err) {
    final response = err.response?.data;
    String message = 'Invalid request';

    if (response is Map<String, dynamic>) {
      if (response.containsKey('error')) {
        message = response['error'].toString();
      } else if (response.containsKey('message')) {
        message = response['message'].toString();
      } else if (response.containsKey('errors')) {
        // Handle validation errors
        final errors = response['errors'];
        if (errors is List && errors.isNotEmpty) {
          message = errors.map((e) => e['message'] ?? e.toString()).join('\n');
        }
      }
    }

    if (context != null) {
      SnackbarHelper.showError(context!, message);
    }
  }

  /// Handle 403 Forbidden responses
  void _handle403Forbidden(DioException err) {
    _showWarningIfNeeded(
      '403_forbidden',
      'Access denied',
      'You do not have permission to perform this action.',
      Icons.lock,
    );
  }

  /// Handle 500 Server Error responses
  void _handle500ServerError(DioException err) {
    final endpoint = err.requestOptions.path;

    // Check for known problematic endpoints
    if (endpoint.contains('/stock')) {
      _showWarningIfNeeded(
        '500_stock',
        'Stock service error',
        'Stock management is experiencing issues. Manual adjustment required.',
        Icons.inventory,
      );
    } else {
      _showWarningIfNeeded(
        '500_generic',
        'Server error occurred',
        'Please try again later or contact support.',
        Icons.error,
      );
    }
  }

  /// Handle service unavailable errors
  void _handleServiceUnavailable(DioException err) {
    _showWarningIfNeeded(
      'service_unavailable',
      'Service temporarily unavailable',
      'The service is down for maintenance. Please try again later.',
      Icons.cloud_off,
    );
  }

  /// Handle generic errors
  void _handleGenericError(DioException err) {
    String message = 'An error occurred';

    if (err.type == DioExceptionType.connectionTimeout) {
      message = 'Connection timeout. Please check your internet connection.';
    } else if (err.type == DioExceptionType.receiveTimeout) {
      message = 'Response timeout. The server is taking too long to respond.';
    } else if (err.type == DioExceptionType.unknown) {
      message = 'Network error. Please check your connection.';
    }

    if (context != null) {
      SnackbarHelper.showError(context!, message);
    }
  }

  /// Show warning with cooldown to avoid spam
  void _showWarningIfNeeded(
    String key,
    String message,
    String workaround,
    IconData icon,
  ) {
    final now = DateTime.now();
    final lastShown = _lastWarningShown[key];

    // Check if we should show this warning
    if (lastShown == null || now.difference(lastShown) > _warningCooldown) {
      _lastWarningShown[key] = now;

      if (context != null) {
        _showLimitationDialog(message, workaround, icon);
      }
    }
  }

  /// Show limitation dialog with workaround
  void _showLimitationDialog(String message, String workaround, IconData icon) {
    if (context == null) return;

    showDialog(
      context: context!,
      builder: (BuildContext dialogContext) {
        final cs = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: Colors.orange, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Feature Limitation',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              if (workaround.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withOpacity(0.2)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.lightbulb, color: Colors.blue, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Workaround:',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.blue,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              workaround,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                'The backend is currently 35% complete. Critical features are being developed.',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, fontStyle: FontStyle.italic),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => _showSystemInfo(dialogContext),
              child: const Text('System Info'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Got it'),
            ),
          ],
        );
      },
    );
  }

  /// Show OCR alternative dialog
  void _showOCRAlternative() {
    if (context == null) return;

    showModalBottomSheet(
      context: context!,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext sheetContext) {
        final cs = Theme.of(sheetContext).colorScheme;
        return Container(
          padding: const EdgeInsets.all(24),
          color: cs.surface,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.camera_alt_outlined,
                size: 48,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              const Text(
                'OCR Not Available',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Receipt scanning is not implemented. Please enter sale details manually.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  // Navigate to manual entry
                  Navigator.pushNamed(context!, '/sales/new');
                },
                icon: const Icon(Icons.edit),
                label: const Text('Enter Manually'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.pop(sheetContext),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Cancel'),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Show system info dialog
  void _showSystemInfo(BuildContext dialogContext) {
    Navigator.pop(dialogContext);
    if (context != null) {
      Navigator.pushNamed(context!, '/sales/limitations-info');
    }
  }
}

/// Extension to easily add interceptor to Dio
extension DioExceptionHandling on Dio {
  void addErrorHandlingInterceptor(BuildContext? context) {
    interceptors.add(ErrorHandlingInterceptor(context: context));
  }
}