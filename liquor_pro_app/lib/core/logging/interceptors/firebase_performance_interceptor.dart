import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_performance/firebase_performance.dart';
import '../../config/environment_config.dart';

/// Dio interceptor that creates Firebase Performance HTTP metrics for API tracing.
///
/// Tracks request duration, response codes, and payload sizes.
/// Disabled in debug mode and when analytics is off.
class FirebasePerformanceInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!kDebugMode && EnvironmentConfig.enableAnalytics) {
      try {
        final url = options.uri;
        final method = _mapMethod(options.method);
        final metric = FirebasePerformance.instance.newHttpMetric(
          url.toString(),
          method,
        );
        metric.start();
        // Store metric in extras for retrieval in onResponse/onError
        options.extra['_fb_perf_metric'] = metric;
      } catch (_) {
        // Non-blocking
      }
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _stopMetric(response.requestOptions, statusCode: response.statusCode);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _stopMetric(err.requestOptions, statusCode: err.response?.statusCode);
    handler.next(err);
  }

  void _stopMetric(RequestOptions options, {int? statusCode}) {
    try {
      final metric = options.extra['_fb_perf_metric'] as HttpMetric?;
      if (metric != null) {
        if (statusCode != null) {
          metric.httpResponseCode = statusCode;
        }
        metric.stop();
      }
    } catch (_) {
      // Non-blocking
    }
  }

  HttpMethod _mapMethod(String method) {
    switch (method.toUpperCase()) {
      case 'GET':
        return HttpMethod.Get;
      case 'POST':
        return HttpMethod.Post;
      case 'PUT':
        return HttpMethod.Put;
      case 'DELETE':
        return HttpMethod.Delete;
      case 'PATCH':
        return HttpMethod.Patch;
      default:
        return HttpMethod.Get;
    }
  }
}
