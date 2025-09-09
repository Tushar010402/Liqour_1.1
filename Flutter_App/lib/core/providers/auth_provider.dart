import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../services/auth_service.dart';
import '../models/user_model.dart';
import '../models/auth_models.dart';
import '../utils/logger.dart';

/// Authentication state provider
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService.instance;
});

/// Authentication state stream provider
final authStateProvider = StreamProvider<AuthState>((ref) {
  final authService = ref.watch(authServiceProvider);
  return authService.authStateStream;
});

/// Current user stream provider
final currentUserProvider = StreamProvider<UserModel?>((ref) {
  final authService = ref.watch(authServiceProvider);
  return authService.userStream;
});

/// Authentication controller provider
final authControllerProvider = StateNotifierProvider<AuthController, AuthControllerState>((ref) {
  final authService = ref.watch(authServiceProvider);
  return AuthController(authService);
});

/// Biometric availability provider
final biometricAvailabilityProvider = FutureProvider<BiometricAvailability>((ref) async {
  final authService = ref.watch(authServiceProvider);
  return await _checkBiometricAvailability(authService);
});

/// Network connectivity provider
final connectivityProvider = StreamProvider<ConnectivityResult>((ref) {
  return Connectivity().onConnectivityChanged;
});

/// Is authenticated provider
final isAuthenticatedProvider = Provider<bool>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.when(
    data: (state) => state == AuthState.authenticated,
    loading: () => false,
    error: (_, __) => false,
  );
});

/// Current user synchronous provider
final currentUserSyncProvider = Provider<UserModel?>((ref) {
  final userAsync = ref.watch(currentUserProvider);
  return userAsync.when(
    data: (user) => user,
    loading: () => null,
    error: (_, __) => null,
  );
});

/// User permissions provider
final userPermissionsProvider = Provider<List<String>>((ref) {
  final user = ref.watch(currentUserSyncProvider);
  return user?.permissions ?? [];
});

/// User has permission provider
final hasPermissionProvider = Provider.family<bool, String>((ref, permission) {
  final permissions = ref.watch(userPermissionsProvider);
  return permissions.contains(permission);
});

/// Authentication controller state
class AuthControllerState {
  final bool isLoading;
  final String? error;
  final String? successMessage;
  final AuthMethod? lastUsedMethod;
  final DateTime? lastAuthAttempt;
  final int failedAttempts;
  final bool isLocked;
  final DateTime? lockUntil;

  const AuthControllerState({
    this.isLoading = false,
    this.error,
    this.successMessage,
    this.lastUsedMethod,
    this.lastAuthAttempt,
    this.failedAttempts = 0,
    this.isLocked = false,
    this.lockUntil,
  });

  AuthControllerState copyWith({
    bool? isLoading,
    String? error,
    String? successMessage,
    AuthMethod? lastUsedMethod,
    DateTime? lastAuthAttempt,
    int? failedAttempts,
    bool? isLocked,
    DateTime? lockUntil,
  }) {
    return AuthControllerState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      successMessage: successMessage,
      lastUsedMethod: lastUsedMethod ?? this.lastUsedMethod,
      lastAuthAttempt: lastAuthAttempt ?? this.lastAuthAttempt,
      failedAttempts: failedAttempts ?? this.failedAttempts,
      isLocked: isLocked ?? this.isLocked,
      lockUntil: lockUntil ?? this.lockUntil,
    );
  }

  bool get canAttemptAuth {
    if (!isLocked) return true;
    if (lockUntil == null) return true;
    return DateTime.now().isAfter(lockUntil!);
  }

  Duration? get lockTimeRemaining {
    if (!isLocked || lockUntil == null) return null;
    final remaining = lockUntil!.difference(DateTime.now());
    return remaining.isNegative ? null : remaining;
  }
}

/// Authentication controller
class AuthController extends StateNotifier<AuthControllerState> {
  final AuthService _authService;
  Timer? _lockTimer;
  
  static const int maxFailedAttempts = 3;
  static const Duration lockDuration = Duration(minutes: 15);

  AuthController(this._authService) : super(const AuthControllerState()) {
    _initializeController();
  }

  /// Initialize the controller
  Future<void> _initializeController() async {
    try {
      await _authService.initialize();
    } catch (error) {
      AppLogger.error('Failed to initialize auth controller', error);
      state = state.copyWith(error: 'Failed to initialize authentication');
    }
  }

  /// Sign in with email and password
  Future<AuthResult> signInWithEmail({
    required String email,
    required String password,
    bool rememberMe = false,
  }) async {
    if (!state.canAttemptAuth) {
      final remaining = state.lockTimeRemaining;
      final minutes = remaining?.inMinutes ?? 0;
      return AuthResult.failure('Too many failed attempts. Try again in $minutes minutes.');
    }

    state = state.copyWith(
      isLoading: true,
      error: null,
      successMessage: null,
    );

    try {
      final result = await _authService.signInWithEmail(
        email: email,
        password: password,
        rememberMe: rememberMe,
      );

      if (result.success) {
        state = state.copyWith(
          isLoading: false,
          successMessage: result.message,
          lastUsedMethod: AuthMethod.emailPassword,
          lastAuthAttempt: DateTime.now(),
          failedAttempts: 0,
          isLocked: false,
          lockUntil: null,
        );
        _lockTimer?.cancel();
      } else {
        final newFailedAttempts = state.failedAttempts + 1;
        final shouldLock = newFailedAttempts >= maxFailedAttempts;
        final lockUntil = shouldLock ? DateTime.now().add(lockDuration) : null;

        state = state.copyWith(
          isLoading: false,
          error: result.message,
          lastUsedMethod: AuthMethod.emailPassword,
          lastAuthAttempt: DateTime.now(),
          failedAttempts: newFailedAttempts,
          isLocked: shouldLock,
          lockUntil: lockUntil,
        );

        if (shouldLock) {
          _startLockTimer();
        }
      }

      return result;
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        error: 'An unexpected error occurred',
      );
      return AuthResult.failure('An unexpected error occurred');
    }
  }

  /// Sign in with biometric
  Future<AuthResult> signInWithBiometric() async {
    if (!state.canAttemptAuth) {
      final remaining = state.lockTimeRemaining;
      final minutes = remaining?.inMinutes ?? 0;
      return AuthResult.failure('Too many failed attempts. Try again in $minutes minutes.');
    }

    state = state.copyWith(
      isLoading: true,
      error: null,
      successMessage: null,
    );

    try {
      final result = await _authService.signInWithBiometric();

      if (result.success) {
        state = state.copyWith(
          isLoading: false,
          successMessage: result.message,
          lastUsedMethod: AuthMethod.biometric,
          lastAuthAttempt: DateTime.now(),
          failedAttempts: 0,
          isLocked: false,
          lockUntil: null,
        );
        _lockTimer?.cancel();
      } else {
        state = state.copyWith(
          isLoading: false,
          error: result.message,
          lastUsedMethod: AuthMethod.biometric,
          lastAuthAttempt: DateTime.now(),
        );
      }

      return result;
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        error: 'Biometric authentication failed',
      );
      return AuthResult.failure('Biometric authentication failed');
    }
  }

  /// Sign up new user
  Future<AuthResult> signUp({
    required String email,
    required String password,
    required String confirmPassword,
    required String firstName,
    required String lastName,
    String? phoneNumber,
    String? businessName,
  }) async {
    state = state.copyWith(
      isLoading: true,
      error: null,
      successMessage: null,
    );

    try {
      final result = await _authService.signUp(
        email: email,
        password: password,
        confirmPassword: confirmPassword,
        firstName: firstName,
        lastName: lastName,
        phoneNumber: phoneNumber,
        businessName: businessName,
      );

      state = state.copyWith(
        isLoading: false,
        error: result.success ? null : result.message,
        successMessage: result.success ? result.message : null,
      );

      return result;
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        error: 'Registration failed',
      );
      return AuthResult.failure('Registration failed');
    }
  }

  /// Enable biometric authentication
  Future<AuthResult> enableBiometric(String password) async {
    state = state.copyWith(
      isLoading: true,
      error: null,
      successMessage: null,
    );

    try {
      final result = await _authService.enableBiometricAuth(password);

      state = state.copyWith(
        isLoading: false,
        error: result.success ? null : result.message,
        successMessage: result.success ? result.message : null,
      );

      return result;
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to enable biometric authentication',
      );
      return AuthResult.failure('Failed to enable biometric authentication');
    }
  }

  /// Disable biometric authentication
  Future<AuthResult> disableBiometric() async {
    state = state.copyWith(
      isLoading: true,
      error: null,
      successMessage: null,
    );

    try {
      final result = await _authService.disableBiometricAuth();

      state = state.copyWith(
        isLoading: false,
        error: result.success ? null : result.message,
        successMessage: result.success ? result.message : null,
      );

      return result;
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to disable biometric authentication',
      );
      return AuthResult.failure('Failed to disable biometric authentication');
    }
  }

  /// Sign out user
  Future<void> signOut() async {
    state = state.copyWith(
      isLoading: true,
      error: null,
      successMessage: null,
    );

    try {
      await _authService.signOut();
      
      state = state.copyWith(
        isLoading: false,
        failedAttempts: 0,
        isLocked: false,
        lockUntil: null,
      );
      _lockTimer?.cancel();
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to sign out',
      );
    }
  }

  /// Clear error state
  void clearError() {
    state = state.copyWith(error: null);
  }

  /// Clear success message
  void clearSuccessMessage() {
    state = state.copyWith(successMessage: null);
  }

  /// Start lock timer
  void _startLockTimer() {
    _lockTimer?.cancel();
    _lockTimer = Timer(lockDuration, () {
      state = state.copyWith(
        isLocked: false,
        lockUntil: null,
        failedAttempts: 0,
      );
    });
  }

  @override
  void dispose() {
    _lockTimer?.cancel();
    super.dispose();
  }
}

/// Biometric availability model
class BiometricAvailability {
  final bool isSupported;
  final bool isAvailable;
  final bool isEnrolled;
  final List<BiometricType> availableTypes;
  final String? error;

  const BiometricAvailability({
    required this.isSupported,
    required this.isAvailable,
    required this.isEnrolled,
    required this.availableTypes,
    this.error,
  });

  bool get canUseBiometric => isSupported && isAvailable && isEnrolled;
}

/// Check biometric availability
Future<BiometricAvailability> _checkBiometricAvailability(AuthService authService) async {
  try {
    // Implementation would use local_auth to check biometric availability
    // This is a simplified version
    return const BiometricAvailability(
      isSupported: true,
      isAvailable: true,
      isEnrolled: true,
      availableTypes: [BiometricType.fingerprint, BiometricType.faceId],
    );
  } catch (error) {
    return BiometricAvailability(
      isSupported: false,
      isAvailable: false,
      isEnrolled: false,
      availableTypes: const [],
      error: error.toString(),
    );
  }
}

/// User role provider
final userRoleProvider = Provider<UserRole?>((ref) {
  final user = ref.watch(currentUserSyncProvider);
  return user?.role;
});

/// User is admin provider
final isAdminProvider = Provider<bool>((ref) {
  final role = ref.watch(userRoleProvider);
  return role is UserRoleAdmin;
});

/// User is manager provider
final isManagerProvider = Provider<bool>((ref) {
  final role = ref.watch(userRoleProvider);
  return role is UserRoleManager || role is UserRoleAdmin;
});

/// User subscription provider
final userSubscriptionProvider = Provider<UserSubscription?>((ref) {
  final user = ref.watch(currentUserSyncProvider);
  return user?.subscription;
});

/// Has active subscription provider
final hasActiveSubscriptionProvider = Provider<bool>((ref) {
  final user = ref.watch(currentUserSyncProvider);
  return user?.hasActiveSubscription ?? false;
});

/// User preferences provider
final userPreferencesProvider = Provider<UserPreferences?>((ref) {
  final user = ref.watch(currentUserSyncProvider);
  return user?.preferences;
});

/// Theme mode provider
final themeModeProvider = Provider<String>((ref) {
  final preferences = ref.watch(userPreferencesProvider);
  return preferences?.theme ?? 'dark';
});

/// Language provider
final languageProvider = Provider<String>((ref) {
  final preferences = ref.watch(userPreferencesProvider);
  return preferences?.language ?? 'en';
});

/// Currency provider
final currencyProvider = Provider<String>((ref) {
  final preferences = ref.watch(userPreferencesProvider);
  return preferences?.currency ?? 'USD';
});

/// Notifications enabled provider
final notificationsEnabledProvider = Provider<bool>((ref) {
  final preferences = ref.watch(userPreferencesProvider);
  return preferences?.notificationsEnabled ?? true;
});

/// Biometric enabled provider
final biometricEnabledProvider = Provider<bool>((ref) {
  final preferences = ref.watch(userPreferencesProvider);
  return preferences?.biometricEnabled ?? false;
});