import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../logging_service.dart';
import 'dio_logging_interceptor.dart';

/// Navigation Observer - Automatically logs all screen transitions
///
/// BEST PRACTICES IMPLEMENTED:
/// 1. Tracks current screen for API call context
/// 2. Logs push/pop/replace navigation events
/// 3. Tracks screen names from route settings
/// 4. Records screens visited in session
/// 5. Works with go_router and Navigator
class LoggingNavigatorObserver extends NavigatorObserver {
  // Current screen name - accessible for other components
  static String? currentScreenName;

  /// Get the current screen name
  static String get currentScreen => currentScreenName ?? 'unknown';

  /// Get route name from settings
  String _getRouteName(Route<dynamic>? route) {
    if (route == null) return 'unknown';

    // Try to get name from settings
    final settings = route.settings;
    if (settings.name != null && settings.name!.isNotEmpty) {
      return settings.name!;
    }

    // Fallback to route type
    return route.runtimeType.toString();
  }

  /// Update current screen and notify Dio interceptor
  void _updateCurrentScreen(String screenName) {
    currentScreenName = screenName;
    // Update Dio interceptor so API logs include screen context
    DioLoggingInterceptor.setCurrentScreen(screenName);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);

    final currentName = _getRouteName(route);
    final previousName = _getRouteName(previousRoute);

    // Update current screen for API logging context
    _updateCurrentScreen(currentName);

    _logNavigation(
      type: 'push',
      from: previousName,
      to: currentName,
      arguments: route.settings.arguments,
    );
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);

    final poppedName = _getRouteName(route);
    final returnToName = _getRouteName(previousRoute);

    // Update current screen for API logging context
    _updateCurrentScreen(returnToName);

    _logNavigation(
      type: 'pop',
      from: poppedName,
      to: returnToName,
    );
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);

    final newName = _getRouteName(newRoute);
    final oldName = _getRouteName(oldRoute);

    // Update current screen for API logging context
    _updateCurrentScreen(newName);

    _logNavigation(
      type: 'replace',
      from: oldName,
      to: newName,
      arguments: newRoute?.settings.arguments,
    );
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);

    final removedName = _getRouteName(route);
    final returnToName = _getRouteName(previousRoute);

    // Update current screen for API logging context
    _updateCurrentScreen(returnToName);

    _logNavigation(
      type: 'remove',
      from: removedName,
      to: returnToName,
    );
  }

  /// Log navigation event
  void _logNavigation({
    required String type,
    required String from,
    required String to,
    Object? arguments,
  }) {
    // Skip if navigating to same route (can happen with nested navigators)
    if (from == to && type == 'push') return;

    // Skip if route names are unknown
    if (from == 'unknown' && to == 'unknown') return;

    LoggingService.instance.logNavigation(
      from: from,
      to: to,
      arguments: arguments != null && arguments is Map<String, dynamic>
          ? arguments
          : null,
    );

    if (kDebugMode) {
      final emoji = type == 'push' ? '→' : type == 'pop' ? '←' : '⟳';
      print('🧭 [Nav] $from $emoji $to');
    }
  }
}

/// Route-aware mixin for widgets that want to log screen views
mixin ScreenLogging<T extends StatefulWidget> on State<T> {
  String get screenName => widget.runtimeType.toString();

  @override
  void initState() {
    super.initState();
    _logScreenView();
  }

  void _logScreenView() {
    // Update current screen for API logging context
    LoggingNavigatorObserver.currentScreenName = screenName;
    DioLoggingInterceptor.setCurrentScreen(screenName);

    LoggingService.instance.info(
      'Screen',
      'Viewed: $screenName',
      metadata: {
        'screen': screenName,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }
}
