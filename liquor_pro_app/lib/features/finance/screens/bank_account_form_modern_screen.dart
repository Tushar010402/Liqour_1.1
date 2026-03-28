import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../models/bank_models.dart';
import '../providers/bank_provider.dart';

/// Modern Bank Account Form Screen
/// Material Design form for creating and editing bank accounts
class BankAccountFormModernScreen extends ConsumerStatefulWidget {
  final TenantBankAccount? account; // null for create, non-null for edit

  const BankAccountFormModernScreen({
    super.key,
    this.account,
  });

  @override
  ConsumerState<BankAccountFormModernScreen> createState() =>
      _BankAccountFormModernScreenState();
}

class _BankAccountFormModernScreenState
    extends ConsumerState<BankAccountFormModernScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _bankNameController;
  late TextEditingController _accountNumberController;
  late TextEditingController _accountHolderController;
  late TextEditingController _ifscController;
  late TextEditingController _branchController;
  late TextEditingController _odLimitController;
  late TextEditingController _odInterestController;
  late TextEditingController _notesController;
  late TextEditingController _openingBalanceController;

  String _accountType = 'current';
  bool _isDefault = false;
  bool _isPrimary = false;
  bool _isActive = true;
  final bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final account = widget.account;

    _bankNameController = TextEditingController(text: account?.bankName ?? '');
    _accountNumberController =
        TextEditingController(text: account?.accountNumber ?? '');
    _accountHolderController =
        TextEditingController(text: account?.accountHolderName ?? '');
    _ifscController = TextEditingController(text: account?.ifscCode ?? '');
    _branchController = TextEditingController(text: account?.branchName ?? '');
    _odLimitController =
        TextEditingController(text: account?.odLimit.toString() ?? '0');
    _odInterestController = TextEditingController(
        text: account?.odInterestRate.toString() ?? '0');
    _notesController = TextEditingController(text: account?.notes ?? '');
    _openingBalanceController = TextEditingController(
        text: account?.currentBalance.toString() ?? '0');

    if (account != null) {
      _accountType = account.accountType;
      _isDefault = account.isDefault;
      _isPrimary = account.isDefault; // isPrimary mirrors isDefault for existing
      _isActive = account.isActive;
    }
  }

  @override
  void dispose() {
    _bankNameController.dispose();
    _accountNumberController.dispose();
    _accountHolderController.dispose();
    _ifscController.dispose();
    _branchController.dispose();
    _odLimitController.dispose();
    _odInterestController.dispose();
    _notesController.dispose();
    _openingBalanceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final formState = ref.watch(bankAccountFormProvider);

    return Scaffold(
      backgroundColor: cs.surfaceContainerHighest,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: cs.primary,
        title: Text(
          widget.account == null ? 'Add Bank Account' : 'Edit Bank Account',
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Bank Details Section
            _buildSectionHeader('Bank Details', Icons.account_balance),
            const SizedBox(height: 12),
            _buildModernCard([
              _buildTextField(
                label: 'Bank Name',
                controller: _bankNameController,
                hint: 'e.g., State Bank of India',
                icon: Icons.account_balance,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter bank name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _buildTextField(
                label: 'Account Holder Name',
                controller: _accountHolderController,
                hint: 'As per bank records',
                icon: Icons.person,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter account holder name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _buildTextField(
                label: 'Account Number',
                controller: _accountNumberController,
                hint: 'Account number',
                icon: Icons.numbers,
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter account number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _buildTextField(
                label: 'IFSC Code',
                controller: _ifscController,
                hint: 'e.g., SBIN0001234',
                icon: Icons.code,
                textCapitalization: TextCapitalization.characters,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter IFSC code';
                  }
                  if (value.length != 11) {
                    return 'IFSC code must be 11 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _buildTextField(
                label: 'Branch Name (Optional)',
                controller: _branchController,
                hint: 'Branch name',
                icon: Icons.location_on,
              ),
            ]),

            const SizedBox(height: 24),

            // Account Type Section
            _buildSectionHeader('Account Type', Icons.category),
            const SizedBox(height: 12),
            _buildModernCard([
              _buildDropdownField(
                label: 'Account Type',
                value: _accountType,
                icon: Icons.account_balance_wallet,
                items: const [
                  DropdownMenuItem(value: 'current', child: Text('Current Account')),
                  DropdownMenuItem(value: 'savings', child: Text('Savings Account')),
                  DropdownMenuItem(value: 'od', child: Text('Overdraft Account')),
                  DropdownMenuItem(
                      value: 'cash_credit', child: Text('Cash Credit Account')),
                ],
                onChanged: (value) {
                  setState(() => _accountType = value!);
                },
              ),
            ]),

            const SizedBox(height: 24),

            // Opening Balance Section (only for new accounts)
            if (widget.account == null) ...[
              _buildSectionHeader('Opening Balance', Icons.account_balance_wallet),
              const SizedBox(height: 12),
              _buildModernCard([
                _buildTextField(
                  label: 'Opening Balance',
                  controller: _openingBalanceController,
                  hint: '0',
                  icon: Icons.currency_rupee,
                  keyboardType: TextInputType.number,
                  prefix: const Text(
                    '₹',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                ),
              ]),
              const SizedBox(height: 24),
            ],

            // Overdraft Settings (if applicable)
            if (_accountType == 'current' || _accountType == 'od') ...[
              _buildSectionHeader('Overdraft Settings', Icons.credit_card),
              const SizedBox(height: 12),
              _buildModernCard([
                _buildTextField(
                  label: 'OD Limit',
                  controller: _odLimitController,
                  hint: '0',
                  icon: Icons.currency_rupee,
                  keyboardType: TextInputType.number,
                  prefix: const Text(
                    '₹',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  label: 'OD Interest Rate',
                  controller: _odInterestController,
                  hint: '0',
                  icon: Icons.percent,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  suffix: const Text(
                    '%',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                ),
              ]),
              const SizedBox(height: 24),
            ],

            // Account Settings
            _buildSectionHeader('Settings', Icons.settings),
            const SizedBox(height: 12),
            _buildModernCard([
              _buildSwitchTile(
                'Set as Default Account',
                _isDefault,
                Icons.star,
                (value) => setState(() => _isDefault = value),
              ),
              const Divider(height: 24),
              _buildSwitchTile(
                'Set as Primary Account',
                _isPrimary,
                Icons.push_pin,
                (value) => setState(() => _isPrimary = value),
              ),
              if (widget.account != null) ...[
                const Divider(height: 24),
                _buildSwitchTile(
                  'Account Active',
                  _isActive,
                  Icons.check_circle,
                  (value) => setState(() => _isActive = value),
                ),
              ],
            ]),

            const SizedBox(height: 24),

            // Notes Section
            _buildSectionHeader('Notes (Optional)', Icons.note),
            const SizedBox(height: 12),
            _buildModernCard([
              _buildTextField(
                label: 'Notes',
                controller: _notesController,
                hint: 'Additional notes',
                icon: Icons.notes,
                maxLines: 3,
              ),
            ]),

            const SizedBox(height: 24),

            // Error Message
            if (formState.errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: AppColors.error),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        formState.errorMessage!,
                        style: TextStyle(
                          color: AppColors.error,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Save Button
            Container(
              height: 54,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [cs.primary, const Color(0xFF8B5CF6)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: formState.isLoading ? null : _saveAccount,
                  borderRadius: BorderRadius.circular(12),
                  child: Center(
                    child: formState.isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text(
                            'Save Account',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: cs.primary, size: 20),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildModernCard(List<Widget> children) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    String? hint,
    IconData? icon,
    TextInputType? keyboardType,
    TextCapitalization? textCapitalization,
    Widget? prefix,
    Widget? suffix,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization ?? TextCapitalization.none,
          maxLines: maxLines,
          validator: validator,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: icon != null ? Icon(icon, color: cs.primary) : null,
            prefix: prefix,
            suffix: suffix,
            filled: true,
            fillColor: cs.surfaceContainerHighest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: cs.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: cs.outlineVariant),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: cs.primary, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.error),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.error, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String value,
    required IconData icon,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: value,
          items: items,
          onChanged: onChanged,
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: cs.primary),
            filled: true,
            fillColor: cs.surfaceContainerHighest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: cs.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: cs.outlineVariant),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: cs.primary, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildSwitchTile(
    String label,
    bool value,
    IconData icon,
    ValueChanged<bool> onChanged,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: value ? cs.primary.withValues(alpha: 0.1) : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: value ? cs.primary : cs.onSurfaceVariant,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: cs.primary,
        ),
      ],
    );
  }

  Future<void> _saveAccount() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final bankService = ref.read(bankServiceProvider);

    if (widget.account == null) {
      // Create new account
      final request = CreateBankAccountRequest(
        bankName: _bankNameController.text.trim(),
        accountNumber: _accountNumberController.text.trim(),
        accountHolderName: _accountHolderController.text.trim(),
        ifscCode: _ifscController.text.trim(),
        branchName: _branchController.text.trim().isEmpty
            ? null
            : _branchController.text.trim(),
        accountType: _accountType,
        openingBalance: double.tryParse(_openingBalanceController.text) ?? 0.0,
        odLimit: double.tryParse(_odLimitController.text) ?? 0.0,
        odInterestRate: double.tryParse(_odInterestController.text) ?? 0.0,
        isDefault: _isDefault,
        isPrimary: _isPrimary,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );

      await ref
          .read(bankAccountFormProvider.notifier)
          .createBankAccount(request);
    } else {
      // Update existing account
      final request = UpdateBankAccountRequest(
        bankName: _bankNameController.text.trim(),
        accountHolderName: _accountHolderController.text.trim(),
        branchName: _branchController.text.trim().isEmpty
            ? null
            : _branchController.text.trim(),
        odLimit: double.tryParse(_odLimitController.text),
        odInterestRate: double.tryParse(_odInterestController.text),
        isActive: _isActive,
        isDefault: _isDefault,
        isPrimary: _isPrimary,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );

      await ref
          .read(bankAccountFormProvider.notifier)
          .updateBankAccount(widget.account!.id, request);
    }

    final formState = ref.read(bankAccountFormProvider);
    if (formState.errorMessage == null && mounted) {
      // Success - show snackbar and go back
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.account == null
                ? 'Bank account created successfully'
                : 'Bank account updated successfully',
          ),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop();
      ref.invalidate(bankAccountsProvider);
    }
  }
}
