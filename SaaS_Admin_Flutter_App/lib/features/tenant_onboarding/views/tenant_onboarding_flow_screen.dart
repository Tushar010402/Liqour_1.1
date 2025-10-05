import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/onboarding_service.dart';
import '../../tenant_marketplace/views/tenant_marketplace_screen.dart';

class TenantOnboardingFlowScreen extends StatefulWidget {
  final String? tenantId;

  const TenantOnboardingFlowScreen({
    super.key,
    this.tenantId,
  });

  @override
  State<TenantOnboardingFlowScreen> createState() => _TenantOnboardingFlowScreenState();
}

class _TenantOnboardingFlowScreenState extends State<TenantOnboardingFlowScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isLoading = false;

  // Onboarding data
  BusinessProfile? _businessProfile;
  String _selectedPackageType = 'starter';
  QuickSetupRecommendations? _recommendations;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGray,
      appBar: _currentPage == 0 ? null : AppBar(
        title: const Text('Setup Your Store'),
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.primaryBlack,
        elevation: 0,
        leading: _currentPage > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => _previousPage(),
              )
            : null,
      ),
      body: Column(
        children: [
          if (_currentPage > 0) _buildProgressIndicator(),
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: (page) {
                setState(() {
                  _currentPage = page;
                });
              },
              children: [
                _buildWelcomeScreen(),
                _buildBusinessProfileScreen(),
                _buildQuickSetupScreen(),
                _buildBrandSelectionScreen(),
                _buildCompletionScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      color: AppColors.white,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Step $_currentPage of 4',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.mediumGray,
                ),
              ),
              Text(
                '${((_currentPage / 4) * 100).round()}% Complete',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryRed,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _currentPage / 4,
            backgroundColor: AppColors.lightGray,
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primaryRed),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeScreen() {
    return Container(
      color: AppColors.primaryRed,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.store,
                size: 80,
                color: AppColors.white,
              ),
              const SizedBox(height: 24),
              const Text(
                'Welcome to LiquorPro!',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: AppColors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'Let\'s set up your liquor store in just a few steps. We\'ll help you choose the right brands and get your inventory ready.',
                style: TextStyle(
                  fontSize: 18,
                  color: AppColors.white,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _nextPage(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.white,
                        foregroundColor: AppColors.primaryRed,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Get Started',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => _skipOnboarding(),
                child: const Text(
                  'Skip Setup (Advanced Users)',
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBusinessProfileScreen() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tell us about your business',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'This helps us recommend the best setup for your store.',
            style: TextStyle(
              fontSize: 16,
              color: AppColors.mediumGray,
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildBusinessProfileForm(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _isLoading ? null : () => _saveBusinessProfile(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryRed,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: AppColors.white)
                      : const Text(
                          'Continue',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBusinessProfileForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFormField(
          'Business Name',
          'Enter your store name',
          onChanged: (value) {
            // Store business name
          },
        ),
        const SizedBox(height: 16),
        _buildDropdownField(
          'Business Type',
          'Select your business type',
          ['Wine Shop', 'Liquor Store', 'Supermarket', 'Restaurant', 'Bar', 'Other'],
          onChanged: (value) {
            // Store business type
          },
        ),
        const SizedBox(height: 16),
        _buildDropdownField(
          'Business Size',
          'Select your business size',
          ['Small (1-2 employees)', 'Medium (3-10 employees)', 'Large (10+ employees)'],
          onChanged: (value) {
            // Store business size
          },
        ),
        const SizedBox(height: 16),
        _buildFormField(
          'Location (Optional)',
          'City, State',
          onChanged: (value) {
            // Store location
          },
        ),
        const SizedBox(height: 16),
        _buildFormField(
          'Phone Number (Optional)',
          'Your business phone',
          onChanged: (value) {
            // Store phone
          },
        ),
      ],
    );
  }

  Widget _buildFormField(String label, String hint, {Function(String)? onChanged}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          decoration: InputDecoration(
            hintText: hint,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.lightGray),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.primaryRed),
            ),
          ),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildDropdownField(String label, String hint, List<String> options, {Function(String?)? onChanged}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          decoration: InputDecoration(
            hintText: hint,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.lightGray),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.primaryRed),
            ),
          ),
          items: options.map((option) =>
            DropdownMenuItem(
              value: option,
              child: Text(option),
            ),
          ).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildQuickSetupScreen() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quick Setup Options',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Choose a package to get started quickly, or customize your selection.',
            style: TextStyle(
              fontSize: 16,
              color: AppColors.mediumGray,
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Column(
              children: [
                _buildQuickSetupCard(
                  'Starter Package',
                  'Perfect for small stores',
                  '15 brands • 45 products • ₹4,999',
                  'starter',
                  Icons.store_outlined,
                ),
                const SizedBox(height: 16),
                _buildQuickSetupCard(
                  'Premium Package',
                  'Great for growing businesses',
                  '35 brands • 120 products • ₹9,999',
                  'premium',
                  Icons.trending_up,
                  isPopular: true,
                ),
                const SizedBox(height: 16),
                _buildQuickSetupCard(
                  'Complete Package',
                  'Everything for large stores',
                  '75 brands • 300 products • ₹19,999',
                  'full',
                  Icons.business,
                ),
                const SizedBox(height: 24),
                _buildCustomOption(),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _nextPage(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryRed,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Continue with Selection',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickSetupCard(String title, String subtitle, String details, String type, IconData icon, {bool isPopular = false}) {
    final isSelected = _selectedPackageType == type;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedPackageType = type;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primaryRed : AppColors.lightGray,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primaryRed : AppColors.lightGray,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: isSelected ? AppColors.white : AppColors.mediumGray,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (isPopular)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primaryRed,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'POPULAR',
                            style: TextStyle(
                              color: AppColors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.mediumGray,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    details,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle,
                color: AppColors.primaryRed,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomOption() {
    final isSelected = _selectedPackageType == 'custom';

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedPackageType = 'custom';
        });
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primaryRed : AppColors.lightGray,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primaryRed : AppColors.lightGray,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.tune,
                color: isSelected ? AppColors.white : AppColors.mediumGray,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Custom Selection',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Choose your own brands',
                    style: TextStyle(
                      color: AppColors.mediumGray,
                      fontSize: 14,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Browse marketplace and select individually',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle,
                color: AppColors.primaryRed,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrandSelectionScreen() {
    if (widget.tenantId == null) {
      return const Center(
        child: Text('Tenant ID not available'),
      );
    }

    return TenantMarketplaceScreen(tenantId: widget.tenantId);
  }

  Widget _buildCompletionScreen() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: AppColors.primaryRed,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check,
              size: 48,
              color: AppColors.white,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Setup Complete!',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          const Text(
            'Your store is ready to go! You can now start managing your inventory, tracking sales, and growing your business.',
            style: TextStyle(
              fontSize: 16,
              color: AppColors.mediumGray,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _finishOnboarding(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryRed,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Start Using LiquorPro',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => _takeTour(),
            child: const Text(
              'Take a Quick Tour',
              style: TextStyle(
                fontSize: 16,
                color: AppColors.primaryRed,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _nextPage() {
    if (_currentPage < 4) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _saveBusinessProfile() async {
    setState(() {
      _isLoading = true;
    });

    // Simulate API call
    await Future.delayed(const Duration(seconds: 1));

    setState(() {
      _isLoading = false;
    });

    _nextPage();
  }

  void _skipOnboarding() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Skip Setup?'),
        content: const Text(
          'You can always access the brand marketplace and setup features later from the dashboard.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop(); // Exit onboarding
            },
            child: const Text('Skip'),
          ),
        ],
      ),
    );
  }

  void _finishOnboarding() {
    Navigator.of(context).pop(); // Return to main app
  }

  void _takeTour() {
    // Implement tour functionality
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tour feature coming soon!')),
    );
  }
}