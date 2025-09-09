import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/constants/app_constants.dart';
import 'core/router/app_router.dart';
import 'core/services/connectivity_service.dart';
import 'core/services/notification_service.dart';
import 'presentation/themes/app_theme.dart';
import 'presentation/widgets/common/connectivity_wrapper.dart';
import 'presentation/widgets/common/global_loading_overlay.dart';

class LiquorProApp extends ConsumerStatefulWidget {
  const LiquorProApp({super.key});

  @override
  ConsumerState<LiquorProApp> createState() => _LiquorProAppState();
}

class _LiquorProAppState extends ConsumerState<LiquorProApp> 
    with WidgetsBindingObserver {
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeAppServices();
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.resumed:
        // App came to foreground
        ref.read(connectivityServiceProvider.notifier).checkConnectivity();
        break;
      case AppLifecycleState.paused:
        // App went to background
        break;
      case AppLifecycleState.detached:
        // App is about to be terminated
        break;
      case AppLifecycleState.inactive:
        // App is inactive (iOS only)
        break;
      case AppLifecycleState.hidden:
        // App is hidden
        break;
    }
  }
  
  Future<void> _initializeAppServices() async {
    // Initialize notification service
    await ref.read(notificationServiceProvider).initialize();
    
    // Start connectivity monitoring
    ref.read(connectivityServiceProvider.notifier).startMonitoring();
  }
  
  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);
    
    return MaterialApp.router(
      // App Configuration
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      
      // Routing
      routerConfig: router,
      
      // Theming
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      
      // Localization
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppConstants.supportedLocales,
      locale: const Locale('en', 'US'), // Default locale
      
      // Performance & Accessibility
      showPerformanceOverlay: false,
      checkerboardRasterCacheImages: false,
      checkerboardOffscreenLayers: false,
      showSemanticsDebugger: false,
      
      // Builder with global wrappers
      builder: (context, child) {
        return MediaQuery(
          // Ensure text scale factor doesn't exceed reasonable limits
          data: MediaQuery.of(context).copyWith(
            textScaler: MediaQuery.of(context).textScaler.clamp(
              minScaleFactor: 0.8,
              maxScaleFactor: 1.3,
            ),
          ),
          child: ConnectivityWrapper(
            child: GlobalLoadingOverlay(
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );
      },
    );
  }
}

/// Theme mode provider for app-wide theme management
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier();
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.dark); // Default to dark theme
  
  void toggleTheme() {
    state = state == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
  }
  
  void setThemeMode(ThemeMode mode) {
    state = mode;
  }
}