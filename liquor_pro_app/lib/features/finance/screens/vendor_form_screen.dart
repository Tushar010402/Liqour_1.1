import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../providers/vendor_provider.dart';
import '../models/vendor_model.dart';

/// Text formatter to convert input to uppercase
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

/// Vendor Form Screen - Add/Edit Vendors
///
/// Features:
/// - Multi-section form (Basic, Address, Business)
/// - Real-time validation
/// - Unsaved changes warning
/// - Loading states
/// - Success/error handling
class VendorFormScreen extends StatefulWidget {
  final Vendor? vendor;

  const VendorFormScreen({
    super.key,
    this.vendor,
  });

  @override
  State<VendorFormScreen> createState() => _VendorFormScreenState();
}

class _VendorFormScreenState extends State<VendorFormScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  late TextEditingController _nameController;
  late TextEditingController _contactPersonController;
  late TextEditingController _phoneController;
  late TextEditingController _emailController;
  late TextEditingController _addressController;
  late TextEditingController _taxIdController;
  late TextEditingController _creditLimitController;

  String? _paymentTerms;
  bool _isActive = true;
  bool _hasUnsavedChanges = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _initializeControllers();
  }

  void _initializeControllers() {
    final vendor = widget.vendor;

    _nameController = TextEditingController(text: vendor?.name ?? '');
    _contactPersonController = TextEditingController(text: vendor?.contactPerson ?? '');
    _phoneController = TextEditingController(text: vendor?.phone ?? '');
    _emailController = TextEditingController(text: vendor?.email ?? '');
    _addressController = TextEditingController(text: vendor?.address ?? '');
    _taxIdController = TextEditingController(text: vendor?.taxId ?? '');
    _creditLimitController = TextEditingController(
      text: vendor?.creditLimit != null && vendor!.creditLimit > 0
        ? vendor.creditLimit.toStringAsFixed(0)
        : '',
    );
    _paymentTerms = vendor?.paymentTerms;
    _isActive = vendor?.isActive ?? true;

    // Listen for changes
    _nameController.addListener(_onFieldChanged);
    _contactPersonController.addListener(_onFieldChanged);
    _phoneController.addListener(_onFieldChanged);
    _emailController.addListener(_onFieldChanged);
    _addressController.addListener(_onFieldChanged);
    _taxIdController.addListener(_onFieldChanged);
    _creditLimitController.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    if (!_hasUnsavedChanges) {
      setState(() {
        _hasUnsavedChanges = true;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contactPersonController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _taxIdController.dispose();
    _creditLimitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isEditing = widget.vendor != null;

    return WillPopScope(
      onWillPop: () async {
        if (_hasUnsavedChanges && !_isSaving) {
          return await _showUnsavedChangesDialog();
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: cs.surfaceContainerHighest,
        appBar: AppBar(
          title: Text(isEditing ? 'Edit Vendor' : 'Add Vendor'),
          elevation: 0,
          backgroundColor: cs.primary,
          foregroundColor: Colors.white,
        ),
        body: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Godam Information Card
                _buildSectionCard(
                  title: 'Godam Information',
                  icon: Icons.business,
                  children: [
                    CustomTextField(
                      label: 'Godam Name *',
                      controller: _nameController,
                      prefixIcon: const Icon(Icons.business),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Godam name is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    CustomTextField(
                      label: 'Contact Person',
                      controller: _contactPersonController,
                      prefixIcon: const Icon(Icons.person_outline),
                      hint: 'Name of contact person',
                    ),
                    const SizedBox(height: 16),
                    CustomTextField(
                      label: 'Phone Number *',
                      controller: _phoneController,
                      prefixIcon: const Icon(Icons.phone),
                      keyboardType: TextInputType.phone,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Phone number is required';
                        }
                        if (value.length < 10) {
                          return 'Please enter a valid phone number';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    CustomTextField(
                      label: 'Email',
                      controller: _emailController,
                      prefixIcon: const Icon(Icons.email_outlined),
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (value != null && value.isNotEmpty) {
                          final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                          if (!emailRegex.hasMatch(value)) {
                            return 'Please enter a valid email';
                          }
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    CustomTextField(
                      label: 'Address',
                      controller: _addressController,
                      prefixIcon: const Icon(Icons.location_on_outlined),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                    CustomTextField(
                      label: 'Tax ID / GST Number',
                      controller: _taxIdController,
                      prefixIcon: const Icon(Icons.numbers),
                      hint: 'Enter GST or Tax ID',
                      inputFormatters: [
                        UpperCaseTextFormatter(),
                      ],
                    ),
                    const SizedBox(height: 16),
                    CustomTextField(
                      label: 'Credit Limit (₹)',
                      controller: _creditLimitController,
                      prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
                      keyboardType: TextInputType.number,
                      hint: 'Enter credit limit amount',
                      validator: (value) {
                        if (value != null && value.isNotEmpty) {
                          final amount = double.tryParse(value);
                          if (amount == null) {
                            return 'Please enter a valid amount';
                          }
                          if (amount < 0) {
                            return 'Credit limit cannot be negative';
                          }
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _paymentTerms,
                      decoration: InputDecoration(
                        labelText: 'Payment Terms',
                        prefixIcon: const Icon(Icons.calendar_today),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: cs.outlineVariant),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: cs.primary, width: 2),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Net 7', child: Text('Net 7 Days')),
                        DropdownMenuItem(value: 'Net 15', child: Text('Net 15 Days')),
                        DropdownMenuItem(value: 'Net 30', child: Text('Net 30 Days')),
                        DropdownMenuItem(value: 'Net 45', child: Text('Net 45 Days')),
                        DropdownMenuItem(value: 'Net 60', child: Text('Net 60 Days')),
                        DropdownMenuItem(value: 'Net 90', child: Text('Net 90 Days')),
                        DropdownMenuItem(value: 'Cash on Delivery', child: Text('Cash on Delivery')),
                        DropdownMenuItem(value: 'Advance Payment', child: Text('Advance Payment')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _paymentTerms = value;
                          _hasUnsavedChanges = true;
                        });
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Save Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveVendor,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            isEditing ? 'Update Vendor' : 'Create Vendor',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: cs.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: AppTextStyles.bodyLarge.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }

  Future<void> _saveVendor() async {
    if (!_formKey.currentState!.validate()) {
      SnackbarHelper.showError(context, 'Please fix the errors in the form');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final provider = context.read<VendorProvider>();

    // Parse credit limit
    double? creditLimit;
    if (_creditLimitController.text.trim().isNotEmpty) {
      creditLimit = double.tryParse(_creditLimitController.text.trim());
    }

    final request = VendorRequest(
      name: _nameController.text.trim(),
      contactPerson: _contactPersonController.text.trim().isNotEmpty
          ? _contactPersonController.text.trim()
          : null,
      phone: _phoneController.text.trim().isNotEmpty
          ? _phoneController.text.trim()
          : null,
      email: _emailController.text.trim().isNotEmpty
          ? _emailController.text.trim()
          : null,
      address: _addressController.text.trim().isNotEmpty
          ? _addressController.text.trim()
          : null,
      city: null,
      state: null,
      postalCode: null,
      country: null,
      taxId: _taxIdController.text.trim().isNotEmpty
          ? _taxIdController.text.trim()
          : null,
      creditLimit: creditLimit,
      paymentTerms: _paymentTerms,
      isActive: _isActive,
    );

    bool success;
    if (widget.vendor != null) {
      success = await provider.updateVendor(widget.vendor!.id, request);
    } else {
      success = await provider.createVendor(request);
    }

    setState(() {
      _isSaving = false;
    });

    if (success && mounted) {
      SnackbarHelper.showSuccess(
        context,
        widget.vendor != null
            ? 'Godam updated successfully'
            : 'Godam created successfully',
      );
      setState(() {
        _hasUnsavedChanges = false;
      });
      Navigator.pop(context);
    } else if (mounted) {
      SnackbarHelper.showError(
        context,
        provider.errorMessage ?? 'Failed to save godam',
      );
    }
  }

  Future<bool> _showUnsavedChangesDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved Changes'),
        content: const Text(
          'You have unsaved changes. Are you sure you want to leave?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Discard'),
          ),
        ],
      ),
    );

    return result ?? false;
  }
}
