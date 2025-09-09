import 'package:flutter/material.dart';

/// Global application constants
abstract class AppConstants {
  // App Information
  static const String appName = 'LiquorPro';
  static const String appDescription = 'Premium Liquor Store Management';
  static const String appVersion = '1.0.0';
  static const String companyName = 'LiquorPro Technologies';
  
  // API Configuration
  static const String baseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'http://localhost:8090',
  );
  static const String apiVersion = 'v1.0.0';
  static const Duration apiTimeout = Duration(seconds: 30);
  static const int apiRetryCount = 3;
  
  // Storage Keys
  static const String authTokenKey = 'auth_token';
  static const String refreshTokenKey = 'refresh_token';
  static const String userDataKey = 'user_data';
  static const String tenantDataKey = 'tenant_data';
  static const String themeKey = 'theme_mode';
  static const String languageKey = 'language_code';
  static const String biometricEnabledKey = 'biometric_enabled';
  static const String notificationTokenKey = 'notification_token';
  
  // Animation Durations
  static const Duration shortAnimation = Duration(milliseconds: 200);
  static const Duration mediumAnimation = Duration(milliseconds: 300);
  static const Duration longAnimation = Duration(milliseconds: 500);
  static const Duration extraLongAnimation = Duration(milliseconds: 800);
  
  // UI Constants
  static const double defaultPadding = 16.0;
  static const double smallPadding = 8.0;
  static const double largePadding = 24.0;
  static const double extraLargePadding = 32.0;
  
  static const double defaultBorderRadius = 12.0;
  static const double smallBorderRadius = 8.0;
  static const double largeBorderRadius = 16.0;
  static const double circularBorderRadius = 999.0;
  
  static const double defaultElevation = 2.0;
  static const double mediumElevation = 4.0;
  static const double highElevation = 8.0;
  
  // Screen Breakpoints
  static const double mobileBreakpoint = 600.0;
  static const double tabletBreakpoint = 1024.0;
  static const double desktopBreakpoint = 1440.0;
  
  // Pagination
  static const int defaultPageSize = 20;
  static const int maxPageSize = 100;
  
  // Validation
  static const int minPasswordLength = 8;
  static const int maxPasswordLength = 128;
  static const int maxUsernameLength = 50;
  static const int maxEmailLength = 254;
  
  // Image Configuration
  static const int maxImageSize = 5 * 1024 * 1024; // 5MB
  static const List<String> allowedImageFormats = [
    'jpg',
    'jpeg',
    'png',
    'webp',
  ];
  
  // Cache Configuration
  static const Duration shortCacheDuration = Duration(minutes: 5);
  static const Duration mediumCacheDuration = Duration(hours: 1);
  static const Duration longCacheDuration = Duration(days: 1);
  static const Duration extraLongCacheDuration = Duration(days: 7);
  
  // Notification Configuration
  static const String notificationChannelId = 'liquorpro_notifications';
  static const String notificationChannelName = 'LiquorPro Notifications';
  static const String notificationChannelDescription = 'LiquorPro app notifications';
  
  // Localization
  static const List<Locale> supportedLocales = [
    Locale('en', 'US'), // English
    Locale('es', 'ES'), // Spanish
    Locale('fr', 'FR'), // French
    Locale('de', 'DE'), // German
    Locale('hi', 'IN'), // Hindi
    Locale('ar', 'SA'), // Arabic
  ];
  
  // Business Logic Constants
  static const int lowStockThreshold = 10;
  static const int criticalStockThreshold = 3;
  static const double defaultTaxRate = 0.18; // 18% GST
  static const int maxCartItems = 50;
  static const double maxOrderAmount = 1000000.0; // ₹10 Lakh
  
  // Error Messages
  static const String genericErrorMessage = 'Something went wrong. Please try again.';
  static const String networkErrorMessage = 'Please check your internet connection and try again.';
  static const String timeoutErrorMessage = 'Request timed out. Please try again.';
  static const String unauthorizedErrorMessage = 'You are not authorized to perform this action.';
  static const String sessionExpiredMessage = 'Your session has expired. Please login again.';
  
  // Success Messages
  static const String loginSuccessMessage = 'Welcome back!';
  static const String logoutSuccessMessage = 'Logged out successfully';
  static const String profileUpdateSuccessMessage = 'Profile updated successfully';
  static const String passwordChangeSuccessMessage = 'Password changed successfully';
  
  // Feature Flags (can be controlled remotely)
  static const bool enableBiometricAuth = true;
  static const bool enablePushNotifications = true;
  static const bool enableAnalytics = true;
  static const bool enableCrashReporting = true;
  static const bool enablePerformanceMonitoring = true;
  
  // Debug Configuration
  static const bool enablePrettyLogger = true;
  static const bool enableNetworkLogging = true;
  static const bool enableStateLogging = false;
  
  // URLs
  static const String privacyPolicyUrl = 'https://liquorpro.com/privacy';
  static const String termsOfServiceUrl = 'https://liquorpro.com/terms';
  static const String supportUrl = 'https://liquorpro.com/support';
  static const String websiteUrl = 'https://liquorpro.com';
  
  // Contact Information
  static const String supportEmail = 'support@liquorpro.com';
  static const String supportPhone = '+1-800-LIQUOR';
  
  // Social Media
  static const String facebookUrl = 'https://facebook.com/liquorpro';
  static const String twitterUrl = 'https://twitter.com/liquorpro';
  static const String instagramUrl = 'https://instagram.com/liquorpro';
  static const String linkedinUrl = 'https://linkedin.com/company/liquorpro';
  
  // Regular Expressions
  static final RegExp emailRegex = RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  );
  
  static final RegExp phoneRegex = RegExp(
    r'^\+?[1-9]\d{1,14}$',
  );
  
  static final RegExp passwordRegex = RegExp(
    r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]',
  );
  
  static final RegExp usernameRegex = RegExp(
    r'^[a-zA-Z0-9._-]{3,50}$',
  );
  
  // Date Formats
  static const String dateFormat = 'dd/MM/yyyy';
  static const String timeFormat = 'HH:mm';
  static const String dateTimeFormat = 'dd/MM/yyyy HH:mm';
  static const String apiDateTimeFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'";
  
  // Currency
  static const String currencySymbol = '₹';
  static const String currencyCode = 'INR';
  static const int currencyDecimals = 2;
}