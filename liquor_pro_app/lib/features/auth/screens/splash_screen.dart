import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as riverpod;
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/responsive_utils.dart';
import '../../../core/services/fcm_service.dart';
import '../providers/auth_provider.dart';

/// Splash Screen - Shows logo for 2 seconds then navigates
/// Checks authentication status and restores session if user is logged in
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      if (!mounted) return;

      // ====== OPTIMIZED STARTUP ======
      // Run splash animation and auth check in parallel
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      // Start both tasks in parallel
      final results = await Future.wait([
        // Minimum splash display time (reduced from 2s to 800ms)
        Future.delayed(const Duration(milliseconds: 800)),
        // Load user credentials in parallel
        authProvider.loadCurrentUser().catchError((_) => null),
      ]);

      if (!mounted) return;

      // Navigate based on auth state
      if (authProvider.isAuthenticated) {
        if (kDebugMode) debugPrint('✅ [SplashScreen] Authenticated → Home');

        // Navigate FIRST, then initialize FCM in background (non-blocking)
        context.go('/home');

        // Initialize FCM in background AFTER navigation - doesn't block user
        _initFCMInBackground();
      } else {
        if (kDebugMode) debugPrint('ℹ️ [SplashScreen] Not authenticated → Login');
        context.go('/phone-login');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ [SplashScreen] Error: $e');
      if (mounted) context.go('/phone-login');
    }
  }

  /// Initialize FCM in background - doesn't block navigation
  void _initFCMInBackground() {
    // Use unawaited future to run in background
    Future.microtask(() async {
      try {
        final container = riverpod.ProviderScope.containerOf(context);
        final fcmService = container.read(fcmServiceProvider);
        await fcmService.initialize();
        // Force refresh token on app launch to ensure fresh token (fixes stale token issue)
        await fcmService.forceRefreshToken();
        await fcmService.registerDevice();
        if (kDebugMode) debugPrint('✅ [Background] FCM token refreshed and device registered');
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ [Background] FCM error (non-critical): $e');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = context.isTablet;
    final isLargeScreen = context.isLargeScreen;

    // Responsive sizes
    final logoSize = ResponsiveUtils.getValue(
      context: context,
      phone: 120.0,
      tablet: 160.0,
      desktop: 200.0,
    );

    final iconSize = ResponsiveUtils.getValue(
      context: context,
      phone: 60.0,
      tablet: 80.0,
      desktop: 100.0,
    );

    final titleFontSize = ResponsiveUtils.getValue(
      context: context,
      phone: 36.0,
      tablet: 48.0,
      desktop: 56.0,
    );

    final subtitleFontSize = ResponsiveUtils.getValue(
      context: context,
      phone: 16.0,
      tablet: 20.0,
      desktop: 24.0,
    );

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.primaryGradient,
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // App Icon/Logo
              Container(
                width: logoSize,
                height: logoSize,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(logoSize * 0.25),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha:0.2),
                      blurRadius: isTablet ? 30 : 20,
                      offset: Offset(0, isTablet ? 15 : 10),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.local_bar,
                  size: iconSize,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              SizedBox(height: context.responsiveSpacing * 2),

              // App Name
              Text(
                'LiquorPro',
                style: AppTextStyles.h1.copyWith(
                  color: Colors.white,
                  fontSize: titleFontSize,
                  fontWeight: FontWeight.bold,
                  letterSpacing: isTablet ? 2.0 : 1.0,
                ),
              ),
              SizedBox(height: context.responsiveSpacing * 0.5),

              // Tagline
              Text(
                'Manage Your Liquor Business',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: Colors.white.withValues(alpha:0.9),
                  fontSize: subtitleFontSize,
                  letterSpacing: isTablet ? 1.0 : 0.5,
                ),
              ),
              SizedBox(height: context.responsiveSpacing * 3),

              // Loading Indicator
              SizedBox(
                width: isTablet ? 50 : 40,
                height: isTablet ? 50 : 40,
                child: CircularProgressIndicator(
                  strokeWidth: isTablet ? 4 : 3,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
