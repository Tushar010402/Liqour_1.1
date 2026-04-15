import 'dart:io' show Platform;

/// Environment Configuration for LiquorPro
/// Supports development, staging, and production environments
enum Environment {
  development,
  staging,
  production,
}

class EnvironmentConfig {
  static Environment _currentEnvironment = Environment.production;

  /// Initialize environment from --dart-define flag
  /// Usage: flutter run --dart-define=ENVIRONMENT=production
  static void initialize() {
    const envString = String.fromEnvironment('ENVIRONMENT', defaultValue: 'production');

    switch (envString.toLowerCase()) {
      case 'production':
      case 'prod':
        _currentEnvironment = Environment.production;
        break;
      case 'staging':
      case 'stage':
        _currentEnvironment = Environment.staging;
        break;
      case 'development':
      case 'dev':
      default:
        _currentEnvironment = Environment.development;
        break;
    }
  }

  /// Get current environment
  static Environment get current => _currentEnvironment;

  /// Check if current environment is development
  static bool get isDevelopment => _currentEnvironment == Environment.development;

  /// Check if current environment is staging
  static bool get isStaging => _currentEnvironment == Environment.staging;

  /// Check if current environment is production
  static bool get isProduction => _currentEnvironment == Environment.production;

  /// Get API base URL based on environment
  static String get apiBaseUrl {
    switch (_currentEnvironment) {
      case Environment.development:
        // Local development - Platform-aware configuration
        // iOS Simulator: Can use localhost (runs on same Mac)
        // iOS Physical Device: Must use Mac's IP (change if needed)
        // Android Emulator: Use special alias 10.0.2.2 for host machine
        // Android Physical Device: Use Mac's IP (same as iOS device)

        if (Platform.isIOS) {
          // iOS Simulator: Use localhost (works since simulator runs on Mac)
          // iOS Physical Device: Change to your Mac's current IP if testing on device
          return 'http://localhost:8090';
        } else if (Platform.isAndroid) {
          // Android Emulator: Use 10.0.2.2 alias for host machine
          return 'http://10.0.2.2:8090';
          // Android Physical Device: Use 'http://YOUR_MAC_IP:8090'
        } else {
          // Desktop/Web - can use localhost
          return 'http://localhost:8090';
        }

      case Environment.staging:
        // Staging server
        return 'https://new.v2.floelife.in';

      case Environment.production:
        // Production server - FloeLife
        return 'https://new.v2.floelife.in';
    }
  }

  /// Get environment display name
  static String get displayName {
    switch (_currentEnvironment) {
      case Environment.development:
        return 'Development';
      case Environment.staging:
        return 'Staging';
      case Environment.production:
        return 'Production';
    }
  }

  /// Enable debug logging in development/staging
  static bool get enableDebugLogging => !isProduction;

  /// Enable analytics in staging/production
  static bool get enableAnalytics => isStaging || isProduction;

  /// Enable crash reporting in staging/production
  static bool get enableCrashReporting => isStaging || isProduction;

  /// Microsoft Clarity project ID for session replay & heatmaps
  /// Get from clarity.microsoft.com > Settings
  static String get clarityProjectId {
    switch (_currentEnvironment) {
      case Environment.development:
        return ''; // Disabled in dev
      case Environment.staging:
        return const String.fromEnvironment('CLARITY_PROJECT_ID', defaultValue: 'w4oicet2o0');
      case Environment.production:
        return const String.fromEnvironment('CLARITY_PROJECT_ID', defaultValue: 'w4oicet2o0');
    }
  }

  /// Get WebSocket URL based on environment
  static String get websocketUrl {
    switch (_currentEnvironment) {
      case Environment.development:
        // Local development - WebSocket server on Gateway
        if (Platform.isIOS) {
          return 'ws://localhost:8090/ws';
        } else if (Platform.isAndroid) {
          return 'ws://10.0.2.2:8090/ws';
        } else {
          return 'ws://localhost:8090/ws';
        }

      case Environment.staging:
        return 'wss://new.v2.floelife.in/ws';

      case Environment.production:
        // Production WebSocket - FloeLife
        return 'wss://new.v2.floelife.in/ws';
    }
  }

  /// API timeout based on environment
  /// Updated to 120 seconds for OCR image uploads (supports ~2MB images)
  static Duration get apiTimeout {
    switch (_currentEnvironment) {
      case Environment.development:
        return const Duration(seconds: 120); // Supports OCR batch processing
      case Environment.staging:
        return const Duration(seconds: 120); // Supports OCR batch processing
      case Environment.production:
        return const Duration(seconds: 120); // Supports OCR batch processing
    }
  }

  /// Print environment info (development only)
  static void printInfo() {
    if (!isDevelopment) return;

    // Using print here is acceptable for environment setup display
    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('╔════════════════════════════════════════╗');
    // ignore: avoid_print
    print('║   LiquorPro Environment Configuration  ║');
    // ignore: avoid_print
    print('╠════════════════════════════════════════╣');
    // ignore: avoid_print
    print('║ Environment: ${displayName.padRight(27)}║');
    // ignore: avoid_print
    print('║ API URL: ${apiBaseUrl.padRight(29)}║');
    // ignore: avoid_print
    print('║ Debug Logging: ${(enableDebugLogging ? 'Enabled' : 'Disabled').padRight(23)}║');
    // ignore: avoid_print
    print('║ Analytics: ${(enableAnalytics ? 'Enabled' : 'Disabled').padRight(27)}║');
    // ignore: avoid_print
    print('║ Crash Reporting: ${(enableCrashReporting ? 'Enabled' : 'Disabled').padRight(21)}║');
    // ignore: avoid_print
    print('╚════════════════════════════════════════╝');
    // ignore: avoid_print
    print('');
  }
}
