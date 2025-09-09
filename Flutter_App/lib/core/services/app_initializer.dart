import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants/app_constants.dart';
import '../utils/logger.dart';
import 'storage_service.dart';
import 'network_service.dart';
import 'notification_service.dart';
import 'analytics_service.dart';

/// Central app initialization service
abstract class AppInitializer {
  static bool _initialized = false;
  
  /// Initialize all app services and configurations
  static Future<void> initialize() async {
    if (_initialized) return;
    
    try {
      AppLogger.info('🚀 Initializing LiquorPro Mobile App...');
      
      // Initialize Firebase (if available)
      await _initializeFirebase();
      
      // Initialize local storage
      await _initializeStorage();
      
      // Initialize network service
      await _initializeNetworking();
      
      // Initialize analytics and crash reporting
      await _initializeAnalytics();
      
      // Initialize notifications
      await _initializeNotifications();
      
      // Initialize device services
      await _initializeDeviceServices();
      
      // Perform initial app setup
      await _performInitialSetup();
      
      _initialized = true;
      AppLogger.info('✅ App initialization completed successfully');
      
    } catch (error, stackTrace) {
      AppLogger.error('❌ App initialization failed', error, stackTrace);
      rethrow;
    }
  }
  
  /// Check if app is initialized
  static bool get isInitialized => _initialized;
  
  /// Reset initialization state (for testing)
  static void reset() {
    _initialized = false;
  }
  
  /// Initialize Firebase services
  static Future<void> _initializeFirebase() async {
    try {
      if (kIsWeb || 
          defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) {
        
        await Firebase.initializeApp();
        AppLogger.info('Firebase initialized');
        
        // Initialize Crashlytics in production
        if (kReleaseMode && AppConstants.enableCrashReporting) {
          FlutterError.onError = (errorDetails) {
            FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
          };
          
          PlatformDispatcher.instance.onError = (error, stack) {
            FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
            return true;
          };
          
          AppLogger.info('Crashlytics initialized');
        }
      }
    } catch (error) {
      AppLogger.warning('Firebase initialization failed (optional service)', error);
      // Firebase is optional, continue initialization
    }
  }
  
  /// Initialize local storage systems
  static Future<void> _initializeStorage() async {
    try {
      // Initialize Hive for local database
      await Hive.initFlutter();
      AppLogger.info('Hive initialized');
      
      // Initialize SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await StorageService.initialize(prefs);
      AppLogger.info('SharedPreferences initialized');
      
      // Test secure storage availability
      const secureStorage = FlutterSecureStorage();
      try {
        await secureStorage.read(key: 'test_key');
        AppLogger.info('Secure storage available');
      } catch (error) {
        AppLogger.warning('Secure storage not available', error);
      }
      
    } catch (error, stackTrace) {
      AppLogger.error('Storage initialization failed', error, stackTrace);
      rethrow;
    }
  }
  
  /// Initialize network services
  static Future<void> _initializeNetworking() async {
    try {
      await NetworkService.initialize();
      AppLogger.info('Network service initialized');
      
      // Test network connectivity
      final isConnected = await NetworkService.isConnected();
      AppLogger.info('Network connectivity: ${isConnected ? 'Connected' : 'Disconnected'}');
      
    } catch (error, stackTrace) {
      AppLogger.error('Network service initialization failed', error, stackTrace);
      rethrow;
    }
  }
  
  /// Initialize analytics and performance monitoring
  static Future<void> _initializeAnalytics() async {
    try {
      if (AppConstants.enableAnalytics) {
        await AnalyticsService.initialize();
        AppLogger.info('Analytics service initialized');
        
        // Track app launch
        await AnalyticsService.trackEvent('app_launched', {
          'platform': defaultTargetPlatform.name,
          'version': AppConstants.appVersion,
          'debug_mode': kDebugMode,
        });
      }
    } catch (error) {
      AppLogger.warning('Analytics initialization failed (optional service)', error);
      // Analytics is optional, continue initialization
    }
  }
  
  /// Initialize notification services
  static Future<void> _initializeNotifications() async {
    try {
      if (AppConstants.enablePushNotifications) {
        await NotificationService.initialize();
        AppLogger.info('Notification service initialized');
      }
    } catch (error) {
      AppLogger.warning('Notification service initialization failed (optional service)', error);
      // Notifications are optional, continue initialization
    }
  }
  
  /// Initialize device-specific services
  static Future<void> _initializeDeviceServices() async {
    try {
      // Set device orientation preferences
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
      
      // Configure system UI
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: Color(0xFF000000),
          systemNavigationBarIconBrightness: Brightness.light,
        ),
      );
      
      AppLogger.info('Device services configured');
      
    } catch (error) {
      AppLogger.warning('Device services configuration failed', error);
      // Device services are optional, continue initialization
    }
  }
  
  /// Perform initial app setup and data migration
  static Future<void> _performInitialSetup() async {
    try {
      // Check if this is first launch
      final isFirstLaunch = await StorageService.getBool('is_first_launch') ?? true;
      
      if (isFirstLaunch) {
        AppLogger.info('First app launch detected');
        
        // Set default preferences
        await _setDefaultPreferences();
        
        // Mark first launch as completed
        await StorageService.setBool('is_first_launch', false);
        
        // Track first launch
        if (AppConstants.enableAnalytics) {
          await AnalyticsService.trackEvent('first_app_launch', {
            'platform': defaultTargetPlatform.name,
            'version': AppConstants.appVersion,
          });
        }
        
        AppLogger.info('First launch setup completed');
      }
      
      // Check for app updates
      await _checkForAppUpdates();
      
      // Perform data migrations if needed
      await _performDataMigrations();
      
      AppLogger.info('Initial setup completed');
      
    } catch (error, stackTrace) {
      AppLogger.error('Initial setup failed', error, stackTrace);
      // Don't rethrow, as this is not critical for app launch
    }
  }
  
  /// Set default app preferences
  static Future<void> _setDefaultPreferences() async {
    try {
      // Set default theme
      await StorageService.setString(AppConstants.themeKey, 'dark');
      
      // Set default language
      await StorageService.setString(AppConstants.languageKey, 'en');
      
      // Set default notification preferences
      await StorageService.setBool('notifications_enabled', true);
      await StorageService.setBool('marketing_notifications', false);
      
      // Set default biometric preference
      if (AppConstants.enableBiometricAuth) {
        await StorageService.setBool(AppConstants.biometricEnabledKey, false);
      }
      
      AppLogger.info('Default preferences set');
      
    } catch (error) {
      AppLogger.warning('Failed to set default preferences', error);
    }
  }
  
  /// Check for app updates
  static Future<void> _checkForAppUpdates() async {
    try {
      final lastVersion = await StorageService.getString('last_app_version');
      
      if (lastVersion != null && lastVersion != AppConstants.appVersion) {
        AppLogger.info('App updated from $lastVersion to ${AppConstants.appVersion}');
        
        // Track app update
        if (AppConstants.enableAnalytics) {
          await AnalyticsService.trackEvent('app_updated', {
            'from_version': lastVersion,
            'to_version': AppConstants.appVersion,
          });
        }
      }
      
      // Save current version
      await StorageService.setString('last_app_version', AppConstants.appVersion);
      
    } catch (error) {
      AppLogger.warning('Failed to check for app updates', error);
    }
  }
  
  /// Perform data migrations between app versions
  static Future<void> _performDataMigrations() async {
    try {
      final currentMigrationVersion = await StorageService.getInt('migration_version') ?? 0;
      const latestMigrationVersion = 1; // Increment when adding new migrations
      
      if (currentMigrationVersion < latestMigrationVersion) {
        AppLogger.info('Performing data migrations from version $currentMigrationVersion to $latestMigrationVersion');
        
        // Perform migrations sequentially
        for (int version = currentMigrationVersion + 1; version <= latestMigrationVersion; version++) {
          await _performMigration(version);
        }
        
        // Update migration version
        await StorageService.setInt('migration_version', latestMigrationVersion);
        
        AppLogger.info('Data migrations completed');
      }
      
    } catch (error) {
      AppLogger.warning('Data migration failed', error);
      // Don't rethrow, as this is not critical for app launch
    }
  }
  
  /// Perform specific migration based on version
  static Future<void> _performMigration(int version) async {
    try {
      switch (version) {
        case 1:
          // Migration 1: Example migration
          AppLogger.info('Performing migration v1');
          // Add specific migration logic here
          break;
          
        // Add more migrations as needed
        default:
          AppLogger.warning('Unknown migration version: $version');
      }
    } catch (error) {
      AppLogger.error('Migration v$version failed', error);
      rethrow;
    }
  }
  
  /// Get initialization status information
  static Map<String, dynamic> getInitializationStatus() {
    return {
      'initialized': _initialized,
      'app_name': AppConstants.appName,
      'app_version': AppConstants.appVersion,
      'debug_mode': kDebugMode,
      'platform': defaultTargetPlatform.name,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
}