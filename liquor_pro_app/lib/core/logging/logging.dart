/// Industrial-grade Logging System for LiquorPro
///
/// This module provides comprehensive logging capabilities:
/// - Persistent storage via SQLite
/// - Automatic API call logging
/// - Navigation tracking
/// - Privacy filtering
/// - Background sync to backend
/// - Session management
///
/// Usage:
/// ```dart
/// // Initialize in main.dart
/// await LoggingService.instance.initialize();
///
/// // Log messages
/// Log.info('MyTag', 'Something happened');
/// Log.error('MyTag', 'Something failed', exception: e);
///
/// // Log API calls (automatic via interceptor)
/// // Log navigation (automatic via observer)
/// ```
library;

export 'logging_service.dart';
export 'log_database.dart';
export 'log_sync_service.dart';
export 'session_manager.dart';
export 'privacy_filter.dart';
export 'interceptors/dio_logging_interceptor.dart';
export 'interceptors/firebase_performance_interceptor.dart';
export 'interceptors/navigation_observer.dart';
