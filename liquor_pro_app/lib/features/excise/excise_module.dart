/// UP Excise Compliance Module
///
/// This file provides easy integration of the excise module into your main app.
///
/// Usage:
/// 1. Add ExciseProvider to your app's MultiProvider
/// 2. Navigate to ExciseHomeScreen from your main navigation
///
/// Example:
/// ```dart
/// // In your main.dart providers:
/// ChangeNotifierProvider(
///   create: (_) => ExciseModule.createProvider(
///     baseUrl: EnvironmentConfig.apiBaseUrl,
///     getToken: () => yourAuthService.getToken(),
///   ),
/// ),
///
/// // Navigate to excise:
/// Navigator.push(
///   context,
///   MaterialPageRoute(
///     builder: (context) => const ExciseHomeScreen(),
///   ),
/// );
/// ```
library;

import 'package:flutter/material.dart';
import 'providers/excise_provider.dart';
import 'services/excise_api_service.dart';
import 'screens/excise_home_screen.dart';

class ExciseModule {
  /// Create excise provider with API service
  static ExciseProvider createProvider({
    required String baseUrl,
    required Future<String?> Function() getToken,
  }) {
    final apiService = ExciseApiService(
      baseUrl: baseUrl,
      getToken: getToken,
    );

    return ExciseProvider(apiService);
  }

  /// Get excise home screen (main entry point)
  static Widget getHomeScreen() {
    return const ExciseHomeScreen();
  }

  /// Navigate to excise module from anywhere
  static void navigateToExcise(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ExciseHomeScreen(),
      ),
    );
  }
}
