import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../../admin/providers/shop_provider.dart';

/// Registration Form Screen - Collects business/shop info and completes registration
class RegistrationFormScreen extends StatefulWidget {
  final String phoneNumber;
  final String? email;
  final String? fullName;
  final String? registrationToken;
  final String companyName;
  final String tenantName;
  final String shopName;
  final String shopAddress;
  final String? shopPhone;
  final String? shopLicense;

  const RegistrationFormScreen({
    super.key,
    required this.phoneNumber,
    this.email,
    this.fullName,
    this.registrationToken,
    required this.companyName,
    required this.tenantName,
    required this.shopName,
    required this.shopAddress,
    this.shopPhone,
    this.shopLicense,
  });

  @override
  State<RegistrationFormScreen> createState() => _RegistrationFormScreenState();
}

class _RegistrationFormScreenState extends State<RegistrationFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _companyController;
  late final TextEditingController _shopNameController;
  late final TextEditingController _shopAddressController;
  bool _isLoading = false;
  String? _registrationError;

  @override
  void initState() {
    super.initState();
    _companyController = TextEditingController(text: widget.companyName);
    _shopNameController = TextEditingController(text: widget.shopName);
    _shopAddressController = TextEditingController(text: widget.shopAddress);
  }

  @override
  void dispose() {
    _companyController.dispose();
    _shopNameController.dispose();
    _shopAddressController.dispose();
    super.dispose();
  }

  /// Generate a tenant name slug from company name
  String _generateTenantName(String companyName) {
    return companyName
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .replaceAll(RegExp(r'\s+'), '-');
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _registrationError = null;
    });

    final authProvider = context.read<AuthProvider>();
    final companyName = _companyController.text.trim();
    final shopName = _shopNameController.text.trim();
    final shopAddress = _shopAddressController.text.trim();
    final tenantName = widget.tenantName.isNotEmpty
        ? widget.tenantName
        : _generateTenantName(companyName);

    // Split full name into first and last name
    final fullName = (widget.fullName ?? '').trim();
    final nameParts = fullName.split(' ');
    final firstName = nameParts.first;
    final lastName = nameParts.length > 1
        ? nameParts.sublist(1).join(' ')
        : nameParts.first;

    final email = (widget.email ?? '').trim();

    debugPrint('[Registration] Submitting:');
    debugPrint('  company=$companyName, tenant=$tenantName');
    debugPrint('  shop=$shopName, address=$shopAddress');
    debugPrint('  email=$email, name=$fullName');

    final success = await authProvider.register(
      email: email,
      password: '',
      firstName: firstName,
      lastName: lastName,
      phone: widget.phoneNumber,
      tenantName: tenantName,
      companyName: companyName,
      registrationToken: widget.registrationToken ?? '',
    );

    if (!mounted) return;

    if (success) {
      // Registration successful - create the shop
      await _createShop(shopName, shopAddress);
    } else {
      setState(() {
        _isLoading = false;
        _registrationError =
            authProvider.errorMessage ?? 'Registration failed. Please try again.';
      });
    }
  }

  Future<void> _createShop(String shopName, String shopAddress) async {
    if (!mounted) return;

    final shopProvider = context.read<ShopProvider>();

    final shopSuccess = await shopProvider.createShop(
      name: shopName,
      address: shopAddress,
      phone: widget.shopPhone ?? widget.phoneNumber,
      licenseNumber: widget.shopLicense ?? '',
      latitude: null,
      longitude: null,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (shopSuccess) {
      debugPrint('[Registration] Complete! Navigating to home...');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Registration successful! Welcome to LiquorPro.'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        context.goNamed('home');
      }
    } else {
      // Shop creation failed but registration succeeded - still go home
      debugPrint('[Registration] Shop creation failed, but user is registered. Going home.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Registration successful! You can set up your shop later.'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
        context.goNamed('home');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Progress dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildProgressDot(true),
                    _buildProgressLine(true),
                    _buildProgressDot(true),
                    _buildProgressLine(true),
                    _buildProgressDot(true),
                  ],
                ),

                const SizedBox(height: 32),

                Text(
                  'Set up your business',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),

                const SizedBox(height: 8),

                Text(
                  'Tell us about your business to get started',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),

                const SizedBox(height: 32),

                // User info summary
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: cs.primaryContainer,
                        child: Icon(Icons.person, color: cs.onPrimaryContainer),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (widget.fullName != null && widget.fullName!.isNotEmpty)
                              Text(
                                widget.fullName!,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            Text(
                              widget.phoneNumber,
                              style: TextStyle(
                                fontSize: 13,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.check_circle, color: Colors.green[600], size: 20),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Company Name
                TextFormField(
                  controller: _companyController,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Company / Business Name',
                    hintText: 'e.g. Sharma Wine Shop',
                    prefixIcon: const Icon(Icons.business_rounded),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: cs.surfaceContainerHighest,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Please enter your business name';
                    }
                    if (v.trim().length < 2) {
                      return 'Business name must be at least 2 characters';
                    }
                    return null;
                  },
                  enabled: !_isLoading,
                ),

                const SizedBox(height: 16),

                // Shop Name
                TextFormField(
                  controller: _shopNameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Shop Name',
                    hintText: 'e.g. Main Branch',
                    prefixIcon: const Icon(Icons.store_rounded),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: cs.surfaceContainerHighest,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Please enter your shop name';
                    }
                    return null;
                  },
                  enabled: !_isLoading,
                ),

                const SizedBox(height: 16),

                // Shop Address
                TextFormField(
                  controller: _shopAddressController,
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Shop Address',
                    hintText: 'e.g. 123 MG Road, Mumbai',
                    prefixIcon: const Padding(
                      padding: EdgeInsets.only(bottom: 24),
                      child: Icon(Icons.location_on_rounded),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: cs.surfaceContainerHighest,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Please enter your shop address';
                    }
                    return null;
                  },
                  enabled: !_isLoading,
                ),

                if (_registrationError != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _registrationError!,
                            style: const TextStyle(color: Colors.red, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 32),

                // Register button
                ElevatedButton(
                  onPressed: _isLoading ? null : _handleRegister,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'Complete Registration',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressDot(bool isActive) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isActive ? cs.primary : cs.outlineVariant,
      ),
    );
  }

  Widget _buildProgressLine(bool isActive) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 40,
      height: 2,
      color: isActive ? cs.primary : cs.outlineVariant,
      margin: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}
