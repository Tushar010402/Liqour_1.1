/// Core Service Providers for Riverpod
/// Provides DioApiService and AuthService instances
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/dio_api_service.dart';
import '../services/auth_service.dart';

// =============================================================================
// SECURE STORAGE PROVIDER
// =============================================================================

/// Provider for FlutterSecureStorage - singleton instance
final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage();
});

// =============================================================================
// SHARED PREFERENCES PROVIDER
// =============================================================================

/// Holder for SharedPreferences - initialized at app startup
SharedPreferences? _sharedPrefsCache;

/// Initialize SharedPreferences - call this before runApp
Future<void> initializeSharedPreferences() async {
  _sharedPrefsCache = await SharedPreferences.getInstance();
}

/// Set SharedPreferences directly (used when already initialized in main.dart)
void setSharedPreferences(SharedPreferences prefs) {
  _sharedPrefsCache = prefs;
}

/// Provider for SharedPreferences - singleton instance
/// Falls back to synchronous getInstance if not pre-initialized
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  if (_sharedPrefsCache == null) {
    throw StateError(
      'SharedPreferences not initialized. Call initializeSharedPreferences() '
      'or setSharedPreferences() before accessing this provider.',
    );
  }
  return _sharedPrefsCache!;
});

// =============================================================================
// AUTH SERVICE PROVIDER
// =============================================================================

/// Provider for AuthService - depends on SecureStorage and SharedPreferences
final authServiceProvider = Provider<AuthService>((ref) {
  final secureStorage = ref.watch(secureStorageProvider);
  final prefs = ref.watch(sharedPreferencesProvider);
  return AuthService(
    secureStorage: secureStorage,
    prefs: prefs,
  );
});

// =============================================================================
// DIO API SERVICE PROVIDER
// =============================================================================

/// Provider for DioApiService - depends on AuthService
final dioApiServiceProvider = Provider<DioApiService>((ref) {
  final authService = ref.watch(authServiceProvider);
  return DioApiService(authService: authService);
});

// =============================================================================
// API SERVICE PROVIDER (Override-based)
// =============================================================================

/// Provider for DioApiService that must be overridden at app startup.
/// This is the primary provider used by most feature modules.
/// Override in main.dart ProviderScope to inject the configured instance.
final apiServiceProvider = Provider<DioApiService>((ref) {
  throw UnimplementedError(
    'DioApiService must be provided via ProviderScope override',
  );
});
