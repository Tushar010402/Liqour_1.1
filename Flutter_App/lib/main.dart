import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';
import 'core/services/app_initializer.dart';
import 'core/services/error_handler.dart';
import 'core/utils/logger.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize error handling
  FlutterError.onError = ErrorHandler.onFlutterError;
  PlatformDispatcher.instance.onError = ErrorHandler.onPlatformError;
  
  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xFF000000),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  
  try {
    // Initialize Hive for local storage
    await Hive.initFlutter();
    
    // Initialize all app services
    await AppInitializer.initialize();
    
    AppLogger.info('🚀 LiquorPro Mobile App Starting...');
    
    runApp(
      ProviderScope(
        observers: [
          if (kDebugMode) _ProviderLogger(),
        ],
        child: const LiquorProApp(),
      ),
    );
  } catch (error, stackTrace) {
    AppLogger.error('Failed to initialize app', error, stackTrace);
    
    runApp(
      MaterialApp(
        title: 'LiquorPro - Error',
        theme: ThemeData.dark(),
        home: AppInitializationErrorScreen(
          error: error.toString(),
          onRetry: () async {
            await AppInitializer.initialize();
            runApp(
              ProviderScope(
                child: const LiquorProApp(),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Provider observer for debugging in development mode
class _ProviderLogger extends ProviderObserver {
  @override
  void didUpdateProvider(
    ProviderBase<Object?> provider,
    Object? previousValue,
    Object? newValue,
    ProviderContainer container,
  ) {
    AppLogger.debug('Provider Updated: ${provider.name ?? provider.runtimeType}');
  }
  
  @override
  void didAddProvider(
    ProviderBase<Object?> provider,
    Object? value,
    ProviderContainer container,
  ) {
    AppLogger.debug('Provider Added: ${provider.name ?? provider.runtimeType}');
  }
  
  @override
  void didDisposeProvider(
    ProviderBase<Object?> provider,
    ProviderContainer container,
  ) {
    AppLogger.debug('Provider Disposed: ${provider.name ?? provider.runtimeType}');
  }
}

/// Error screen shown when app initialization fails
class AppInitializationErrorScreen extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  
  const AppInitializationErrorScreen({
    super.key,
    required this.error,
    required this.onRetry,
  });
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Error Icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF5252).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(40),
                ),
                child: const Icon(
                  Icons.error_outline,
                  color: Color(0xFFFF5252),
                  size: 40,
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Error Title
              const Text(
                'Initialization Failed',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 12),
              
              // Error Message
              Text(
                'Failed to initialize LiquorPro Mobile.\nPlease check your connection and try again.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 16,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              
              if (kDebugMode) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    error,
                    style: const TextStyle(
                      color: Color(0xFFFF5252),
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
              
              const SizedBox(height: 32),
              
              // Retry Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: onRetry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4AF37),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Retry',
                    style: TextStyle(
                      color: Color(0xFF0A0A0A),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}