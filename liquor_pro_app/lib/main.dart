import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/config/environment_config.dart';
import 'core/constants/app_colors.dart';
import 'core/services/auth_service.dart';
import 'core/services/api_service.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/auth/screens/splash_screen.dart';
import 'features/auth/screens/phone_input_screen.dart';
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
import 'features/inventory/providers/product_provider.dart';
import 'features/inventory/providers/brand_onboarding_provider.dart';
import 'features/inventory/services/product_service.dart';
import 'features/inventory/services/brand_onboarding_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize environment configuration
  EnvironmentConfig.initialize();
  EnvironmentConfig.printInfo();

  final prefs = await SharedPreferences.getInstance();
  runApp(LiquorProApp(prefs: prefs));
}

class LiquorProApp extends StatelessWidget {
  final SharedPreferences prefs;

  const LiquorProApp({super.key, required this.prefs});

  @override
  Widget build(BuildContext context) {
    // Initialize services
    final authService = AuthService(
      secureStorage: const FlutterSecureStorage(),
      prefs: prefs,
    );
    final apiService = ApiService(authService: authService);

    return MultiProvider(
      providers: [
        Provider<AuthService>.value(value: authService),
        Provider<ApiService>.value(value: apiService),
        ChangeNotifierProxyProvider2<AuthService, ApiService, AuthProvider>(
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
        ChangeNotifierProxyProvider<AuthService, ExciseProvider>(
          create: (context) => ExciseProvider(
            ExciseApiService(
              baseUrl: 'http://localhost:8093',
              getToken: () => context.read<AuthService>().getToken(),
            ),
          ),
          update: (_, authService, previous) =>
            previous ?? ExciseProvider(
              ExciseApiService(
                baseUrl: 'http://localhost:8093',
                getToken: () => authService.getToken(),
              ),
            ),
        ),
        ChangeNotifierProxyProvider<ApiService, ShopProvider>(
          create: (context) => ShopProvider(
            ShopService(context.read<ApiService>()),
          ),
          update: (_, apiService, previous) =>
            previous ?? ShopProvider(ShopService(apiService)),
        ),
        ChangeNotifierProxyProvider<ApiService, DashboardProvider>(
          create: (context) => DashboardProvider(
            DashboardService(context.read<ApiService>()),
          ),
          update: (_, apiService, previous) =>
            previous ?? DashboardProvider(DashboardService(apiService)),
        ),
        ChangeNotifierProxyProvider<ApiService, ProductProvider>(
          create: (context) => ProductProvider(
            ProductService(context.read<ApiService>()),
          ),
          update: (_, apiService, previous) =>
            previous ?? ProductProvider(ProductService(apiService)),
        ),
        ChangeNotifierProxyProvider<ApiService, BrandOnboardingProvider>(
          create: (context) => BrandOnboardingProvider(
            BrandOnboardingService(context.read<ApiService>()),
          ),
          update: (_, apiService, previous) =>
            previous ?? BrandOnboardingProvider(
              BrandOnboardingService(apiService),
            ),
        ),
      ],
      child: Builder(
        builder: (context) {
          final authProvider = Provider.of<AuthProvider>(context, listen: false);
          return MaterialApp.router(
            title: 'LiquorPro',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: AppColors.primary,
                brightness: Brightness.light,
              ),
              useMaterial3: true,
              appBarTheme: const AppBarTheme(
                centerTitle: true,
                elevation: 0,
              ),
              cardTheme: CardThemeData(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              inputDecorationTheme: InputDecorationTheme(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
              ),
            ),
            routerConfig: _router(authProvider),
          );
        },
      ),
    );
  }

  GoRouter _router(AuthProvider authProvider) {
    return GoRouter(
      initialLocation: '/splash',
      refreshListenable: authProvider,
      redirect: (context, state) {
        final isLoggedIn = authProvider.isAuthenticated;
        final isOnSplash = state.matchedLocation == '/splash';
        final isOnAuthPage = state.matchedLocation == '/phone-login' ||
            state.matchedLocation == '/otp-verification' ||
            state.matchedLocation == '/pre-registration' ||
            state.matchedLocation == '/registration-form';

        if (isOnSplash) return null;
        if (!isLoggedIn && !isOnAuthPage) return '/phone-login';
        if (isLoggedIn && isOnAuthPage) return '/home';
        return null;
      },
      routes: [
        GoRoute(
          path: '/splash',
          builder: (context, state) => const SplashScreen(),
        ),
        GoRoute(
          path: '/phone-login',
          name: 'phone-login',
          builder: (context, state) => const PhoneInputScreen(),
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
            return OtpVerificationScreen(
              phoneNumber: phone,
              sessionId: sessionId,
              expiresAt: expiresAt,
              isRegistration: isRegistration,
            );
          },
        ),
        GoRoute(
          path: '/pre-registration',
          name: 'pre-registration',
          builder: (context, state) {
            final args = state.extra as Map<String, dynamic>?;
            final phone = args?['phone'] as String? ?? '';
            return PreRegistrationScreen(phoneNumber: phone);
          },
        ),
        GoRoute(
          path: '/registration-form',
          name: 'registration-form',
          builder: (context, state) {
            final args = state.extra as Map<String, dynamic>?;
            final phone = args?['phone'] as String? ?? '';
            return RegistrationFormScreen(phoneNumber: phone);
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
}
