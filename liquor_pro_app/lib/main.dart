import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as riverpod;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'core/config/environment_config.dart';
import 'core/services/auth_service.dart';
import 'core/services/dio_api_service.dart';
import 'core/services/offline_queue_service.dart';
import 'core/services/preferences_service.dart';
import 'core/providers/shop_selection_provider.dart';
import 'core/providers/theme_provider.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/auth/screens/splash_screen.dart';
import 'features/auth/screens/salesman_login_screen.dart';
import 'features/auth/screens/otp_verification_screen.dart';
import 'features/auth/screens/pre_registration_screen.dart';
import 'features/auth/screens/registration_form_screen.dart';
import 'features/navigation/screens/main_navigation_screen.dart';
import 'features/excise/providers/excise_provider.dart';
import 'features/excise/services/excise_api_service.dart';
import 'features/admin/providers/shop_provider.dart';
import 'features/admin/services/shop_service.dart';
import 'features/dashboard/providers/dashboard_provider.dart';
import 'features/dashboard/services/dashboard_service.dart';
import 'features/dashboard/services/day_closing_service.dart';
import 'features/inventory/providers/product_provider.dart';
import 'features/inventory/providers/brand_onboarding_provider.dart';
import 'features/inventory/services/product_service.dart';
import 'features/inventory/services/brand_onboarding_service.dart';
import 'features/sales/providers/daily_sales_provider.dart';
import 'features/sales/services/daily_sales_service.dart';
import 'features/sales/services/daily_sales_draft_service.dart';
import 'features/sales/services/draft_api_service.dart';
import 'features/sales/services/smart_sale_draft_service.dart';
import 'features/inventory/providers/stock_purchase_provider.dart';
import 'features/inventory/services/stock_purchase_service.dart';
import 'features/sales/providers/expense_header_provider.dart';
import 'features/finance/providers/vendor_provider.dart';
import 'features/finance/services/vendor_service.dart';
import 'core/permissions/providers/permission_provider.dart';
import 'features/admin/providers/user_management_provider.dart';
import 'features/admin/services/user_management_service.dart';
import 'features/inventory/providers/brand_selection_provider.dart';
import 'core/providers/service_providers.dart';
import 'core/services/notification_navigation_service.dart';
// ATT removed - app does NOT track users for advertising
// import 'core/services/app_tracking_service.dart';

// Industrial-grade logging system
import 'core/logging/logging.dart';

/// Background message handler - must be top-level function
/// This handles push notifications when app is terminated or in background
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Ensure Firebase is initialized for background handler
  await Firebase.initializeApp();

  if (kDebugMode) {
    debugPrint('🔔 FCM Background: ${message.notification?.title}');
  }
}

void main() {
  // ═══════════════════════════════════════════════════════════════════════
  // INDUSTRIAL-GRADE LOGGING: Error Zone - catches ALL unhandled errors
  // IMPORTANT: runZonedGuarded must wrap EVERYTHING including Flutter binding
  // ═══════════════════════════════════════════════════════════════════════
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Initialize environment configuration (sync - fast)
      EnvironmentConfig.initialize();
      if (kDebugMode) EnvironmentConfig.printInfo();

      // ====== PARALLEL INITIALIZATION FOR SPEED ======
      // Run independent initializations in parallel
      final results = await Future.wait([
        // Firebase initialization
        _initFirebase(),
        // Hive initialization
        Hive.initFlutter(),
        // SharedPreferences initialization
        SharedPreferences.getInstance(),
        // ATT removed - app does NOT track users for advertising purposes
        // AppTrackingService().initialize(),
        Future.value(), // placeholder to maintain Future.wait array
      ]);

      final prefs = results[2] as SharedPreferences;
      setSharedPreferences(prefs);

      // Initialize Smart Sale draft service (uses Hive for persistence)
      await SmartSaleDraftService.instance.initialize();

      // PreferencesService depends on prefs, so run after
      final prefsService = await PreferencesService.getInstance();
      final userPrefs = UserPreferences(prefsService);

      // Initialize core services
      final authService = AuthService(
        secureStorage: const FlutterSecureStorage(),
        prefs: prefs,
      );
      final apiService = DioApiService(
        authService: authService,
        onSessionExpired: () {
          // Handle session expiration - navigate to login
          NotificationNavigationService.handleSessionExpiration();
        },
      );

      // ═══════════════════════════════════════════════════════════════════════
      // INDUSTRIAL-GRADE LOGGING: Initialize logging service
      // ═══════════════════════════════════════════════════════════════════════
      final loggingService = LoggingService();
      await loggingService.initialize();

      // Setup Flutter error handler
      FlutterError.onError = loggingService.logFlutterError;

      // Run app
      runApp(
        riverpod.ProviderScope(
          overrides: [
            apiServiceProvider.overrideWithValue(apiService),
          ],
          child: LiquorProApp(
            prefs: prefs,
            userPrefs: userPrefs,
            authService: authService,
            apiService: apiService,
          ),
        ),
      );
    },
    // Error handler for unhandled async errors
    (error, stackTrace) {
      // Log to console (LoggingService might not be initialized yet)
      if (kDebugMode) {
        debugPrint('❌ [UNHANDLED ERROR] $error');
        debugPrint('$stackTrace');
      }
      // Try to log via logging service if available
      try {
        LoggingService.instance.logUnhandledError(error, stackTrace);
      } catch (_) {
        // Service not ready yet, already logged to console
      }
    },
  );
}

/// Isolated Firebase initialization - won't block app if fails
Future<void> _initFirebase() async {
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    if (kDebugMode) debugPrint('✅ Firebase initialized');
  } catch (e) {
    if (kDebugMode) debugPrint('⚠️ Firebase init error (non-blocking): $e');
  }
}

class LiquorProApp extends StatelessWidget {
  final SharedPreferences prefs;
  final UserPreferences userPrefs;
  final AuthService authService;
  final DioApiService apiService;

  const LiquorProApp({
    super.key,
    required this.prefs,
    required this.userPrefs,
    required this.authService,
    required this.apiService,
  });

  @override
  Widget build(BuildContext context) {
    // Initialize OfflineQueueService (singleton)
    final offlineQueue = OfflineQueueService();
    offlineQueue.initialize(apiService);

    return MultiProvider(
      providers: [
        Provider<AuthService>.value(value: authService),
        Provider<DioApiService>.value(value: apiService),
        Provider<OfflineQueueService>.value(value: offlineQueue),
        Provider<UserPreferences>.value(value: userPrefs),
        ChangeNotifierProvider<ThemeProvider>(
          create: (_) => ThemeProvider(prefs: userPrefs),
        ),
        ChangeNotifierProxyProvider2<AuthService, DioApiService, AuthProvider>(
          create: (_) => AuthProvider(
            authService: authService,
            apiService: apiService,
          ),
          update: (_, authService, apiService, previous) =>
            previous ?? AuthProvider(
              authService: authService,
              apiService: apiService,
            ),
        ),
        // PermissionProvider - listens to AuthProvider for role-based permissions
        ChangeNotifierProxyProvider<AuthProvider, PermissionProvider>(
          create: (context) {
            final permProvider = PermissionProvider();
            final authProvider = context.read<AuthProvider>();
            // Initialize with current role if already logged in
            if (authProvider.isAuthenticated && authProvider.currentUser != null) {
              permProvider.setCurrentRole(
                authProvider.currentUser!.role,
                tenantId: authProvider.currentUser!.tenantId,
              );
            }
            return permProvider;
          },
          update: (_, authProvider, previous) {
            if (previous == null) return PermissionProvider();
            // Sync role when auth state changes
            if (authProvider.isAuthenticated && authProvider.currentUser != null) {
              previous.setCurrentRole(
                authProvider.currentUser!.role,
                tenantId: authProvider.currentUser!.tenantId,
              );
            } else {
              previous.clearRole();
            }
            return previous;
          },
        ),
        ChangeNotifierProxyProvider<AuthService, ExciseProvider>(
          create: (context) => ExciseProvider(
            ExciseApiService(
              baseUrl: EnvironmentConfig.apiBaseUrl,
              getToken: () => context.read<AuthService>().getToken(),
            ),
          ),
          update: (_, authService, previous) =>
            previous ?? ExciseProvider(
              ExciseApiService(
                baseUrl: EnvironmentConfig.apiBaseUrl,
                getToken: () => authService.getToken(),
              ),
            ),
        ),
        ChangeNotifierProxyProvider<DioApiService, ShopProvider>(
          create: (context) => ShopProvider(
            ShopService(context.read<DioApiService>()),
          ),
          update: (_, apiService, previous) =>
            previous ?? ShopProvider(ShopService(apiService)),
        ),
        // ShopSelectionProvider - depends on ShopService and UserPreferences
        ChangeNotifierProxyProvider<DioApiService, ShopSelectionProvider>(
          create: (context) => ShopSelectionProvider(
            shopService: ShopService(context.read<DioApiService>()),
            prefsService: userPrefs,
          ),
          update: (_, apiService, previous) =>
            previous ?? ShopSelectionProvider(
              shopService: ShopService(apiService),
              prefsService: userPrefs,
            ),
        ),
        ChangeNotifierProxyProvider<DioApiService, DashboardProvider>(
          create: (context) {
            final api = context.read<DioApiService>();
            final provider = DashboardProvider(DashboardService(api));
            provider.dayClosingService = DayClosingService(api);
            return provider;
          },
          update: (_, apiService, previous) {
            if (previous != null) {
              previous.dayClosingService = DayClosingService(apiService);
              return previous;
            }
            final provider = DashboardProvider(DashboardService(apiService));
            provider.dayClosingService = DayClosingService(apiService);
            return provider;
          },
        ),
        ChangeNotifierProxyProvider<DioApiService, ProductProvider>(
          create: (context) => ProductProvider(
            ProductService(context.read<DioApiService>()),
          ),
          update: (_, apiService, previous) =>
            previous ?? ProductProvider(ProductService(apiService)),
        ),
        ChangeNotifierProxyProvider<DioApiService, BrandOnboardingProvider>(
          create: (context) => BrandOnboardingProvider(
            BrandOnboardingService(context.read<DioApiService>()),
            ProductService(context.read<DioApiService>()),
          ),
          update: (_, apiService, previous) =>
            previous ?? BrandOnboardingProvider(
              BrandOnboardingService(apiService),
              ProductService(apiService),
            ),
        ),
        ChangeNotifierProxyProvider2<AuthService, DioApiService, DailySalesProvider>(
          create: (context) {
            final draftService = DailySalesDraftService();
            // Wire up backend sync
            final draftApiService = DraftApiService(context.read<DioApiService>());
            draftService.setApiService(draftApiService);
            // Start background sync (every 30 seconds)
            draftService.startBackgroundSync();
            return DailySalesProvider(
              DailySalesService(context.read<AuthService>()),
              draftService,
            );
          },
          update: (_, authService, apiService, previous) {
            if (previous != null) return previous;
            final draftService = DailySalesDraftService();
            final draftApiService = DraftApiService(apiService);
            draftService.setApiService(draftApiService);
            draftService.startBackgroundSync();
            return DailySalesProvider(
              DailySalesService(authService),
              draftService,
            );
          },
        ),
        ChangeNotifierProxyProvider<DioApiService, StockPurchaseProvider>(
          create: (context) => StockPurchaseProvider(
            StockPurchaseService(context.read<DioApiService>()),
          ),
          update: (_, apiService, previous) =>
            previous ?? StockPurchaseProvider(
              StockPurchaseService(apiService),
            ),
        ),
        // ExpenseHeaderProvider - no dependencies, loads from SharedPreferences
        ChangeNotifierProvider<ExpenseHeaderProvider>(
          create: (_) => ExpenseHeaderProvider(),
        ),
        // VendorProvider - depends on DioApiService
        ChangeNotifierProxyProvider<DioApiService, VendorProvider>(
          create: (context) => VendorProvider(
            VendorService(context.read<DioApiService>()),
          ),
          update: (_, apiService, previous) =>
            previous ?? VendorProvider(VendorService(apiService)),
        ),
        // UserManagementProvider - depends on DioApiService
        ChangeNotifierProxyProvider<DioApiService, UserManagementProvider>(
          create: (context) => UserManagementProvider(
            UserManagementService(context.read<DioApiService>()),
          ),
          update: (_, apiService, previous) =>
            previous ?? UserManagementProvider(UserManagementService(apiService)),
        ),
        // BrandSelectionProvider - no dependencies, manages brand selection state
        ChangeNotifierProvider<BrandSelectionProvider>(
          create: (_) => BrandSelectionProvider(),
        ),
      ],
      child: const _AppShell(),
    );
  }
}

/// Stateful shell that caches the GoRouter so theme changes don't
/// recreate it (which would reset navigation to /splash).
class _AppShell extends StatefulWidget {
  const _AppShell();
  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  GoRouter? _router;

  GoRouter _getRouter(AuthProvider authProvider) {
    return _router ??= GoRouter(
      navigatorKey: NotificationNavigationService.navigatorKey,
      initialLocation: '/splash',
      refreshListenable: authProvider,
      observers: [LoggingNavigatorObserver()],
      errorBuilder: (context, state) {
        if (kDebugMode) {
          debugPrint('🚨 [Router] Unknown route: ${state.matchedLocation}');
          debugPrint('   Error: ${state.error}');
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            context.go('/splash');
          }
        });
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      },
      redirect: (context, state) {
        final isLoggedIn = authProvider.isAuthenticated;
        final isOnSplash = state.matchedLocation == '/splash';
        final isOnAuthPage = state.matchedLocation == '/phone-login' ||
            state.matchedLocation == '/otp-verification' ||
            state.matchedLocation == '/pre-registration' ||
            state.matchedLocation == '/registration-form';

        if (state.matchedLocation == '/') return '/splash';
        if (isOnSplash) return null;
        if (!isLoggedIn && !isOnAuthPage) return '/phone-login';
        if (isLoggedIn && isOnAuthPage) return '/home';
        return null;
      },
      routes: [
        GoRoute(
          path: '/',
          redirect: (context, state) => '/splash',
        ),
        GoRoute(
          path: '/splash',
          builder: (context, state) => const SplashScreen(),
        ),
        GoRoute(
          path: '/phone-login',
          name: 'phone-login',
          builder: (context, state) => const SalesmanLoginScreen(),
        ),
        GoRoute(
          path: '/otp-verification',
          name: 'otp-verification',
          builder: (context, state) {
            final args = state.extra as Map<String, dynamic>?;
            final phone = args?['phone'] as String? ?? '';
            final sessionId = args?['sessionId'] as String? ?? '';
            final expiresAt = args?['expiresAt'] as DateTime? ?? DateTime.now();
            final isRegistration = args?['isRegistration'] as bool? ?? false;
            final email = args?['email'] as String?;
            final fullName = args?['fullName'] as String?;
            return OtpVerificationScreen(
              phoneNumber: phone,
              sessionId: sessionId,
              expiresAt: expiresAt,
              isRegistration: isRegistration,
              email: email,
              fullName: fullName,
            );
          },
        ),
        GoRoute(
          path: '/pre-registration',
          name: 'pre-registration',
          builder: (context, state) {
            final args = state.extra as Map<String, dynamic>?;
            final phone = args?['phone'] as String? ?? '';
            final registrationToken = args?['registrationToken'] as String?;
            return PreRegistrationScreen(
              phoneNumber: phone,
              registrationToken: registrationToken,
            );
          },
        ),
        GoRoute(
          path: '/registration-form',
          name: 'registration-form',
          builder: (context, state) {
            final args = state.extra as Map<String, dynamic>?;
            final phone = args?['phone'] as String? ?? '';
            final email = args?['email'] as String?;
            final fullName = args?['fullName'] as String?;
            final registrationToken = args?['registrationToken'] as String?;
            final companyName = args?['companyName'] as String? ?? '';
            final tenantName = args?['tenantName'] as String? ?? '';
            final shopName = args?['shopName'] as String? ?? '';
            final shopAddress = args?['shopAddress'] as String? ?? '';
            return RegistrationFormScreen(
              phoneNumber: phone,
              email: email,
              fullName: fullName,
              registrationToken: registrationToken,
              companyName: companyName,
              tenantName: tenantName,
              shopName: shopName,
              shopAddress: shopAddress,
            );
          },
        ),
        GoRoute(
          path: '/dashboard',
          name: 'dashboard',
          builder: (context, state) => const MainNavigationScreen(),
        ),
        GoRoute(
          path: '/home',
          name: 'home',
          builder: (context, state) => const MainNavigationScreen(),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _router?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final themeProvider = Provider.of<ThemeProvider>(context);
    return MaterialApp.router(
      title: 'LiquorPro',
      debugShowCheckedModeBanner: false,
      theme: themeProvider.themeData,
      themeMode: themeProvider.themeMode,
      routerConfig: _getRouter(authProvider),
    );
  }
}
