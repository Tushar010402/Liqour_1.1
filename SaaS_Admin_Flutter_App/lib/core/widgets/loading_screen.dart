import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../constants/app_colors.dart';
import '../constants/app_strings.dart';
import '../../features/authentication/controllers/auth_provider.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  bool _timeoutReached = false;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _initializeAuth();
    _setupTimeout();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    ));

    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.2, 0.8, curve: Curves.elasticOut),
    ));

    _animationController.forward();
  }

  void _initializeAuth() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthProvider>().initialize();
    });
  }

  void _setupTimeout() {
    // Force navigation after 5 seconds if still loading
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && !_timeoutReached) {
        setState(() {
          _timeoutReached = true;
        });
        // Force navigation to login screen
        context.go('/login');
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: _buildContent(),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Logo/Icon
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryRed.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: const Icon(
              Icons.admin_panel_settings,
              size: 60,
              color: AppColors.white,
            ),
          ),

          const SizedBox(height: 40),

          // App Name
          Text(
            AppStrings.appName,
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryBlack,
                ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 12),

          // Tagline
          Text(
            AppStrings.appTagline,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.mediumGray,
                ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 60),

          // Loading Indicator
          _buildLoadingIndicator(),

          const SizedBox(height: 24),

          // Loading Text
          Text(
            AppStrings.loading,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.mediumGray,
                ),
          ),

          const SizedBox(height: 80),

          // Version
          Text(
            'Version ${AppStrings.appVersion}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.mediumGray,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25),
        border: Border.all(
          color: AppColors.lightRed,
          width: 3,
        ),
      ),
      child: const CircularProgressIndicator(
        strokeWidth: 3,
        valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryRed),
      ),
    );
  }
}
