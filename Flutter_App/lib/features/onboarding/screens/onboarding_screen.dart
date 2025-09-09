import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/buttons/premium_button.dart';
import '../../../core/widgets/animations/page_transitions.dart';
import '../../auth/screens/login_screen.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  final List<OnboardingPage> _pages = [
    OnboardingPage(
      title: 'Premium Liquor Store',
      subtitle: 'Discover the finest selection of premium spirits and wines from around the world',
      animationPath: 'assets/lottie/wine_glass.json',
      backgroundColor: AppColors.primary.withOpacity(0.1),
    ),
    OnboardingPage(
      title: 'Smart Recommendations',
      subtitle: 'Get personalized recommendations based on your taste preferences and purchase history',
      animationPath: 'assets/lottie/recommendations.json',
      backgroundColor: AppColors.accent.withOpacity(0.1),
    ),
    OnboardingPage(
      title: 'Fast & Secure Delivery',
      subtitle: 'Enjoy fast, secure delivery with real-time tracking and premium packaging',
      animationPath: 'assets/lottie/delivery.json',
      backgroundColor: AppColors.success.withOpacity(0.1),
    ),
    OnboardingPage(
      title: 'Exclusive Rewards',
      subtitle: 'Earn points with every purchase and unlock exclusive rewards and VIP experiences',
      animationPath: 'assets/lottie/rewards.json',
      backgroundColor: AppColors.warning.withOpacity(0.1),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _startAutoAdvance();
  }

  void _setupAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    _fadeController.forward();
    _slideController.forward();
  }

  void _startAutoAdvance() {
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && _currentPage < _pages.length - 1) {
        _nextPage();
      }
    });
  }

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _skipToEnd() {
    _pageController.animateToPage(
      _pages.length - 1,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOutCubic,
    );
  }

  void _navigateToAuth() {
    HapticFeedback.lightImpact();
    Navigator.of(context).pushReplacement(
      CustomPageRoute(
        child: const LoginScreen(),
        transitionType: PageTransitionType.slideUp,
        duration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Header with Skip Button
            _buildHeader(),
            
            // Page View
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                  HapticFeedback.selectionClick();
                  
                  // Reset animations for new page
                  _fadeController.reset();
                  _slideController.reset();
                  _fadeController.forward();
                  _slideController.forward();
                  
                  // Auto advance except on last page
                  if (index < _pages.length - 1) {
                    _startAutoAdvance();
                  }
                },
                itemCount: _pages.length,
                itemBuilder: (context, index) {
                  return _buildPageContent(_pages[index]);
                },
              ),
            ),
            
            // Page Indicator
            _buildPageIndicator(),
            
            // Navigation Buttons
            _buildNavigationButtons(),
            
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Logo
          AnimatedBuilder(
            animation: _fadeAnimation,
            builder: (context, child) {
              return FadeTransition(
                opacity: _fadeAnimation,
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.wine_bar,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      AppConstants.appName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          
          // Skip Button
          if (_currentPage < _pages.length - 1)
            TextButton(
              onPressed: _skipToEnd,
              child: Text(
                'Skip',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPageContent(OnboardingPage page) {
    return AnimatedBuilder(
      animation: _fadeAnimation,
      builder: (context, child) {
        return SlideTransition(
          position: _slideAnimation,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Animation
                  Container(
                    width: 280,
                    height: 280,
                    decoration: BoxDecoration(
                      color: page.backgroundColor,
                      borderRadius: BorderRadius.circular(32),
                    ),
                    child: Center(
                      child: Lottie.asset(
                        page.animationPath,
                        width: 200,
                        height: 200,
                        fit: BoxFit.contain,
                        repeat: true,
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 48),
                  
                  // Title
                  Text(
                    page.title,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                      height: 1.2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Subtitle
                  Text(
                    page.subtitle,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPageIndicator() {
    return AnimatedBuilder(
      animation: _fadeAnimation,
      builder: (context, child) {
        return FadeTransition(
          opacity: _fadeAnimation,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: SmoothPageIndicator(
              controller: _pageController,
              count: _pages.length,
              effect: WormEffect(
                dotColor: AppColors.textSecondary.withOpacity(0.3),
                activeDotColor: AppColors.primary,
                dotWidth: 8,
                dotHeight: 8,
                spacing: 16,
                radius: 8,
                type: WormType.thinUnderground,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNavigationButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          // Main Action Button
          SizedBox(
            width: double.infinity,
            child: PremiumButton(
              text: _currentPage == _pages.length - 1 ? 'Get Started' : 'Continue',
              onPressed: _currentPage == _pages.length - 1 ? _navigateToAuth : _nextPage,
              variant: PremiumButtonVariant.primary,
              isLoading: false,
            ),
          ),
          
          // Secondary Actions
          if (_currentPage > 0 && _currentPage < _pages.length - 1)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: _previousPage,
                    icon: Icon(
                      Icons.arrow_back_ios,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                    label: Text(
                      'Previous',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _nextPage,
                    label: Text(
                      'Next',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    icon: Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class OnboardingPage {
  final String title;
  final String subtitle;
  final String animationPath;
  final Color backgroundColor;

  OnboardingPage({
    required this.title,
    required this.subtitle,
    required this.animationPath,
    required this.backgroundColor,
  });
}