/// Performance Constants for Tree-Shaking Optimization
/// Best Practices:
/// - Use const for compile-time constants
/// - Enable tree shaking by not importing unused constants
/// - Group related constants for better organization
/// - Use these values instead of magic numbers
library;

// ===============================================
// TIMING CONSTANTS (all in milliseconds)
// ===============================================
// Note: Animation durations are in animation_constants.dart (AnimationConstants)

/// Network timeout durations
class NetworkTimeouts {
  const NetworkTimeouts._();

  /// Connection timeout (30 seconds)
  static const int connection = 30000;

  /// Receive timeout (60 seconds)
  static const int receive = 60000;

  /// Send timeout (60 seconds)
  static const int send = 60000;

  /// Quick API calls timeout (10 seconds)
  static const int quick = 10000;

  /// File upload timeout (5 minutes)
  static const int fileUpload = 300000;

  /// Retry delay base (1 second)
  static const int retryBase = 1000;
}

/// Cache durations
class CacheDurations {
  const CacheDurations._();

  /// Token cache lifetime (30 seconds)
  static const int tokenCache = 30;

  /// API response cache (5 minutes)
  static const int apiResponse = 300;

  /// Image cache (7 days in seconds)
  static const int imageCache = 604800;

  /// Deduplication window (5 seconds)
  static const int dedupe = 5;

  /// Connectivity check throttle (5 seconds)
  static const int connectivityThrottle = 5;

  /// Dashboard refresh interval (30 seconds)
  static const int dashboardRefresh = 30;
}

// ===============================================
// UI CONSTANTS
// ===============================================

/// Spacing values (in logical pixels)
class Spacing {
  const Spacing._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 48;
}

/// Border radius values
class Radii {
  const Radii._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double round = 100;
}

/// Icon sizes
class IconSizes {
  const IconSizes._();

  static const double xs = 12;
  static const double sm = 16;
  static const double md = 20;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
  static const double huge = 64;
}

/// Font sizes
class FontSizes {
  const FontSizes._();

  static const double xs = 10;
  static const double sm = 12;
  static const double md = 14;
  static const double lg = 16;
  static const double xl = 18;
  static const double xxl = 20;
  static const double h3 = 24;
  static const double h2 = 28;
  static const double h1 = 32;
  static const double display = 40;
}

// ===============================================
// LIMITS & THRESHOLDS
// ===============================================

/// Pagination and list limits
class Limits {
  const Limits._();

  /// Default page size for API requests
  static const int defaultPageSize = 20;

  /// Maximum page size
  static const int maxPageSize = 100;

  /// Items to show before pagination
  static const int initialLoadCount = 20;

  /// Scroll threshold to trigger load more (pixels from bottom)
  static const double loadMoreThreshold = 200;

  /// Maximum retry attempts
  static const int maxRetries = 3;

  /// Maximum concurrent API requests
  static const int maxConcurrentRequests = 6;

  /// Maximum image cache entries
  static const int maxImageCacheEntries = 100;

  /// Maximum search history items
  static const int maxSearchHistory = 10;
}

/// Input validation limits
class ValidationLimits {
  const ValidationLimits._();

  /// Phone number length (without country code)
  static const int phoneLength = 10;

  /// OTP length
  static const int otpLength = 6;

  /// Minimum password length
  static const int minPasswordLength = 8;

  /// Maximum name length
  static const int maxNameLength = 100;

  /// Maximum description length
  static const int maxDescriptionLength = 500;

  /// Maximum quantity
  static const int maxQuantity = 99999;

  /// Maximum price
  static const double maxPrice = 999999.99;
}

// ===============================================
// FEATURE FLAGS (compile-time switches)
// ===============================================

/// Feature flags for tree-shaking unused features
class FeatureFlags {
  const FeatureFlags._();

  /// Enable debug logging (set to false for production)
  static const bool enableDebugLogs = true;

  /// Enable analytics tracking
  static const bool enableAnalytics = true;

  /// Enable offline mode
  static const bool enableOfflineMode = true;

  /// Enable biometric authentication
  static const bool enableBiometrics = true;

  /// Enable OCR features
  static const bool enableOCR = true;

  /// Enable push notifications
  static const bool enablePushNotifications = true;

  /// Enable device limit enforcement
  static const bool enableDeviceLimit = true;
}

// ===============================================
// BUILD CONFIGURATION
// ===============================================

/// Build-time configuration
class BuildConfig {
  const BuildConfig._();

  /// App version (updated during build)
  static const String appVersion = '1.0.0';

  /// Build number
  static const int buildNumber = 1;

  /// Minimum supported API version
  static const String minApiVersion = 'v1';

  /// Default environment (can be overridden with --dart-define)
  static const String environment = String.fromEnvironment(
    'ENVIRONMENT',
    defaultValue: 'production',
  );

  /// Check if running in debug mode
  static bool get isDebug => environment == 'development' || environment == 'debug';

  /// Check if running in production
  static bool get isProduction => environment == 'production';
}
