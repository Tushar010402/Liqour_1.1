import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../routes/app_routes.dart';
import '../controllers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  bool _biometricAvailable = false;
  bool _biometricEnabled = false;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _checkBiometricAvailability();
    _loadStoredPhone();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
    ));

    _animationController.forward();
  }

  void _checkBiometricAvailability() async {
    final authProvider = context.read<AuthProvider>();
    final available = await authProvider.checkBiometricAvailability();
    final enabled = authProvider.biometricEnabled;

    setState(() {
      _biometricAvailable = available;
      _biometricEnabled = enabled;
    });
  }

  void _loadStoredPhone() async {
    final authProvider = context.read<AuthProvider>();
    final storedPhone = authProvider.phoneNumber;
    if (storedPhone != null) {
      _phoneController.text = storedPhone;
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGray,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: _buildContent(),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 60),

          // Logo and Header
          _buildHeader(),

          const SizedBox(height: 60),

          // Login Form
          _buildLoginForm(),

          const SizedBox(height: 40),

          // Biometric Option
          if (_biometricAvailable && _biometricEnabled) _buildBiometricOption(),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        // Logo
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(25),
            boxShadow: [AppColors.primaryShadow],
          ),
          child: const Icon(
            Icons.admin_panel_settings,
            size: 50,
            color: AppColors.white,
          ),
        ),

        const SizedBox(height: 24),

        // Welcome Text
        Text(
          AppStrings.welcome,
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.primaryBlack,
              ),
        ),

        const SizedBox(height: 8),

        Text(
          AppStrings.welcomeSubtitle,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: AppColors.mediumGray,
              ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildLoginForm() {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        return Card(
          elevation: 8,
          shadowColor: AppColors.primaryRed.withValues(alpha: 0.1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Phone Number Input
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.visiblePassword, // Prevent Hindi number conversion
                    autocorrect: false,
                    enableSuggestions: false,
                    enableInteractiveSelection: true,
                    autofillHints: const <String>[],
                    textCapitalization: TextCapitalization.none,
                    decoration: InputDecoration(
                      labelText: AppStrings.phoneNumber,
                      hintText: AppStrings.enterPhoneNumber,
                      prefixIcon: const Icon(Icons.phone_outlined),
                      prefixText: '+91 ',
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return AppStrings.requiredField;
                      }
                      if (value.length != 10) {
                        return AppStrings.invalidPhone;
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 24),

                  // Send OTP Button
                  ElevatedButton(
                    onPressed: authProvider.isLoading ? null : _handleSendOTP,
                    child: authProvider.isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppColors.white,
                              ),
                            ),
                          )
                        : const Text(AppStrings.sendOTP),
                  ),

                  // Error Message
                  if (authProvider.hasError) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.errorLight,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.error),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: AppColors.error,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              authProvider.errorMessage!,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: AppColors.error,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBiometricOption() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: _handleBiometricAuth,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.lightRed,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.fingerprint,
                  color: AppColors.primaryRed,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.biometricAuth,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    Text(
                      'Quick and secure access',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.mediumGray,
                          ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: AppColors.mediumGray,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleSendOTP() async {
    if (!_formKey.currentState!.validate()) return;

    final phoneNumber = '+91${_phoneController.text}';
    final authProvider = context.read<AuthProvider>();

    // First check if user is admin
    final isAdmin = await authProvider.checkIsAdmin(phoneNumber);
    if (!isAdmin) return;

    // Then send OTP
    final success = await authProvider.sendOTP(phoneNumber);
    if (success && mounted) {
      // URL encode the phone number to preserve the + character
      final encodedPhoneNumber = Uri.encodeComponent(phoneNumber);
      context.push('${AppRoutes.otp}?phone=$encodedPhoneNumber');
    }
  }

  void _handleBiometricAuth() async {
    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.authenticateWithBiometric();

    if (success && mounted) {
      context.go(AppRoutes.dashboard);
    }
  }
}
