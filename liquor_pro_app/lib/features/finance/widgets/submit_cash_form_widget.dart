import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/document_scanner_service.dart';
import '../../../core/theme/ios_design_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../providers/cash_provider.dart';
import '../models/cash_models.dart';
import '../providers/bank_provider.dart';
import '../models/bank_models.dart';

/// Reusable Submit Cash Form Widget
/// Can be embedded in any screen (standalone or tabbed)
class SubmitCashFormWidget extends ConsumerStatefulWidget {
  final String shopId;
  final VoidCallback? onSubmitSuccess;
  final CashSubmission? resubmitFrom;

  const SubmitCashFormWidget({
    super.key,
    required this.shopId,
    this.onSubmitSuccess,
    this.resubmitFrom,
  });

  @override
  ConsumerState<SubmitCashFormWidget> createState() => _SubmitCashFormWidgetState();
}

class _SubmitCashFormWidgetState extends ConsumerState<SubmitCashFormWidget> {
  final _formKey = GlobalKey<FormState>();
  final _bankSlipController = TextEditingController();
  final _notesController = TextEditingController();
  late final DocumentScannerService _documentScanner;

  // Denomination controllers
  final Map<int, TextEditingController> _denominationControllers = {
    500: TextEditingController(text: '0'),
    200: TextEditingController(text: '0'),
    100: TextEditingController(text: '0'),
    50: TextEditingController(text: '0'),
    20: TextEditingController(text: '0'),
    10: TextEditingController(text: '0'),
  };

  File? _receiptImage;
  bool _isSubmitting = false;
  DateTime _depositDate = DateTime.now();
  TenantBankAccount? _selectedBankAccount;

  @override
  void initState() {
    super.initState();
    _documentScanner = DocumentScannerService();
    _prefillFromRejectedSubmission();
  }

  void _prefillFromRejectedSubmission() {
    final resubmit = widget.resubmitFrom;
    if (resubmit == null) return;

    _denominationControllers[500]!.text = resubmit.notes500.toString();
    _denominationControllers[200]!.text = resubmit.notes200.toString();
    _denominationControllers[100]!.text = resubmit.notes100.toString();
    _denominationControllers[50]!.text = resubmit.notes50.toString();
    _denominationControllers[20]!.text = resubmit.notes20.toString();
    _denominationControllers[10]!.text = resubmit.notes10.toString();

    if (resubmit.bankSlipNumber != null && resubmit.bankSlipNumber!.isNotEmpty) {
      _bankSlipController.text = resubmit.bankSlipNumber!;
    }
    if (resubmit.notes != null && resubmit.notes!.isNotEmpty) {
      _notesController.text = resubmit.notes!;
    }
    if (resubmit.depositDate != null) {
      _depositDate = resubmit.depositDate!;
    }
  }

  @override
  void dispose() {
    _bankSlipController.dispose();
    _notesController.dispose();
    for (var c in _denominationControllers.values) {
      c.dispose();
    }
    _documentScanner.dispose();
    super.dispose();
  }

  double get _calculatedTotal {
    double total = 0;
    _denominationControllers.forEach((denom, controller) {
      final count = int.tryParse(controller.text) ?? 0;
      total += denom * count;
    });
    return total;
  }

  Map<String, int> get _denominationValues {
    return {
      'notes_500': int.tryParse(_denominationControllers[500]!.text) ?? 0,
      'notes_200': int.tryParse(_denominationControllers[200]!.text) ?? 0,
      'notes_100': int.tryParse(_denominationControllers[100]!.text) ?? 0,
      'notes_50': int.tryParse(_denominationControllers[50]!.text) ?? 0,
      'notes_20': int.tryParse(_denominationControllers[20]!.text) ?? 0,
      'notes_10': int.tryParse(_denominationControllers[10]!.text) ?? 0,
    };
  }

  void _autoFill(double availableBalance) {
    HapticFeedback.lightImpact();
    double remaining = availableBalance;
    final Map<int, int> counts = {};

    for (final denom in [500, 200, 100, 50, 20, 10]) {
      final count = (remaining / denom).floor();
      counts[denom] = count;
      remaining -= count * denom;
    }

    setState(() {
      counts.forEach((denom, count) {
        _denominationControllers[denom]!.text = count.toString();
      });
    });
  }

  void _clearAll() {
    HapticFeedback.lightImpact();
    setState(() {
      _denominationControllers.forEach((_, controller) {
        controller.text = '0';
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final cashBalance = ref.watch(cashBalanceProvider);

    return cashBalance.when(
      data: (balance) {
        if (balance <= 0) {
          return _buildNoCashState();
        }
        return _buildForm(balance);
      },
      loading: () => const Center(
        child: CupertinoActivityIndicator(radius: 16),
      ),
      error: (error, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(CupertinoIcons.exclamationmark_triangle,
                size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text('Error: $error', style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
    );
  }

  Widget _buildNoCashState() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                CupertinoIcons.money_dollar_circle,
                size: 80,
                color: Colors.orange,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No Cash Available',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'You don\'t have any cash to submit to the bank.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: cs.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(double availableBalance) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildAvailableBalanceCard(availableBalance),
          const SizedBox(height: 20),
          _buildQuickActions(availableBalance),
          const SizedBox(height: 20),
          _buildDenominationSection(),
          const SizedBox(height: 20),
          _buildCalculatedTotalCard(availableBalance),
          const SizedBox(height: 20),
          _buildReceiptSection(),
          const SizedBox(height: 20),
          _buildBankAccountSelector(),
          const SizedBox(height: 20),
          _buildBankDetailsCard(),
          const SizedBox(height: 20),
          _buildDepositDateCard(),
          const SizedBox(height: 20),
          _buildNotesCard(),
          const SizedBox(height: 32),
          _buildSubmitButton(availableBalance),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildAvailableBalanceCard(double balance) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
        border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  cs.primary.withValues(alpha: 0.15),
                  cs.primary.withValues(alpha: 0.06),
                ],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              CupertinoIcons.money_dollar_circle_fill,
              color: cs.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cash in Hand',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  Formatters.currency(balance),
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(double availableBalance) {
    return Row(
      children: [
        Expanded(
          child: _buildActionButton(
            icon: CupertinoIcons.wand_stars,
            label: 'Auto Fill',
            onTap: () => _autoFill(availableBalance),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildActionButton(
            icon: CupertinoIcons.clear_circled,
            label: 'Clear All',
            onTap: _clearAll,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
          border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: cs.primary, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: cs.primary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDenominationSection() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
        border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        cs.primary.withValues(alpha: 0.15),
                        cs.primary.withValues(alpha: 0.06),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    CupertinoIcons.money_rubl_circle,
                    color: cs.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Denomination Breakdown',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [500, 200, 100, 50, 20, 10].map((denom) {
                return _buildDenominationRow(denom);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDenominationRow(int denomination) {
    final cs = Theme.of(context).colorScheme;
    final controller = _denominationControllers[denomination]!;
    final count = int.tryParse(controller.text) ?? 0;
    final subtotal = denomination * count;
    final color = _getDenominationColor(denomination);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: count > 0 ? color.withOpacity(0.3) : cs.outlineVariant,
          width: count > 0 ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          // Denomination Badge
          Container(
            width: 65,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withOpacity(0.4), width: 1.5),
            ),
            child: Text(
              '\u20B9$denomination',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Counter Controls
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    final current = int.tryParse(controller.text) ?? 0;
                    if (current > 0) {
                      setState(() {
                        controller.text = (current - 1).toString();
                      });
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withOpacity(0.3)),
                    ),
                    child: const Icon(
                      CupertinoIcons.minus,
                      color: Colors.red,
                      size: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: SizedBox(
                    width: 45,
                    child: CupertinoTextField(
                      controller: controller,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    final current = int.tryParse(controller.text) ?? 0;
                    setState(() {
                      controller.text = (current + 1).toString();
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                    ),
                    child: const Icon(
                      CupertinoIcons.plus,
                      color: Colors.green,
                      size: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),

          // Subtotal
          SizedBox(
            width: 90,
            child: Text(
              subtotal > 0 ? Formatters.currency(subtotal.toDouble()) : '\u20B90',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: subtotal > 0 ? cs.onSurface : cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalculatedTotalCard(double availableBalance) {
    final isValid = _calculatedTotal > 0 && _calculatedTotal <= availableBalance;
    final color = isValid ? Colors.green : Colors.red;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withOpacity(0.15),
            color.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
        border: Border.all(
          color: color.withOpacity(0.4),
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              isValid
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.exclamationmark_circle_fill,
              color: color,
              size: 32,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total Amount',
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  Formatters.currency(_calculatedTotal),
                  style: TextStyle(
                    color: color,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                if (!isValid && _calculatedTotal > 0)
                  Text(
                    'Exceeds available cash',
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptSection() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
        border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        cs.primary.withValues(alpha: 0.15),
                        cs.primary.withValues(alpha: 0.06),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    CupertinoIcons.camera_fill,
                    color: cs.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Bank Receipt Photo',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'REQUIRED',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (_receiptImage != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
                    Image.file(
                      _receiptImage!,
                      height: 220,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: () => setState(() => _receiptImage = null),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            CupertinoIcons.trash,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            SizedBox(
              width: double.infinity,
              child: _buildPhotoButton(
                icon: CupertinoIcons.viewfinder,
                label: 'Scan Bank Slip',
                onTap: _scanBankSlip,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              cs.primary.withValues(alpha: 0.8),
              cs.primary.withValues(alpha: 0.6),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBankAccountSelector() {
    final cs = Theme.of(context).colorScheme;
    final bankAccountsAsync = ref.watch(activeBankAccountsProvider);

    return bankAccountsAsync.when(
      data: (accounts) {
        if (_selectedBankAccount == null && accounts.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            setState(() {
              _selectedBankAccount = accounts.firstWhere(
                (account) => account.isDefault,
                orElse: () => accounts.first,
              );
            });
          });
        }

        if (accounts.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
              border: Border.all(
                color: Colors.orange.withOpacity(0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  CupertinoIcons.exclamationmark_triangle,
                  color: Colors.orange,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'No bank accounts found. Please add a bank account first.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.orange.shade800,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
            border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            cs.primary.withValues(alpha: 0.15),
                            cs.primary.withValues(alpha: 0.06),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        CupertinoIcons.building_2_fill,
                        color: cs.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Bank Account',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              GestureDetector(
                onTap: () => _showBankAccountPicker(accounts),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_selectedBankAccount != null) ...[
                              Row(
                                children: [
                                  Text(
                                    _selectedBankAccount!.bankName,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                  if (_selectedBankAccount!.isDefault) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: cs.primary.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'DEFAULT',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: cs.primary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '****${_selectedBankAccount!.accountNumber.substring(_selectedBankAccount!.accountNumber.length - 4)}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ] else ...[
                              Text(
                                'Select bank account',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Icon(
                        CupertinoIcons.chevron_right,
                        color: cs.onSurfaceVariant,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
          border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
        ),
        child: const Center(child: CupertinoActivityIndicator()),
      ),
      error: (error, stack) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.1),
          borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
          border: Border.all(
            color: Colors.red.withOpacity(0.3),
          ),
        ),
        child: Row(
          children: [
            const Icon(CupertinoIcons.exclamationmark_triangle, color: Colors.red),
            const SizedBox(width: 12),
            Expanded(child: Text('Error: $error', style: const TextStyle(color: Colors.red))),
          ],
        ),
      ),
    );
  }

  void _showBankAccountPicker(List<TenantBankAccount> accounts) {
    final cs = Theme.of(context).colorScheme;
    showCupertinoModalPopup(
      context: context,
      builder: (BuildContext context) => Container(
        height: 300,
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: cs.outlineVariant)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const Text(
                    'Select Bank Account',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: CupertinoPicker(
                itemExtent: 80,
                onSelectedItemChanged: (int index) {
                  setState(() => _selectedBankAccount = accounts[index]);
                },
                scrollController: FixedExtentScrollController(
                  initialItem: _selectedBankAccount != null
                      ? accounts.indexOf(_selectedBankAccount!)
                      : 0,
                ),
                children: accounts.map((account) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              account.bankName,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                            if (account.isDefault) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: cs.primary.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'DEFAULT',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: cs.primary),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '****${account.accountNumber.substring(account.accountNumber.length - 4)}',
                          style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBankDetailsCard() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
        border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      cs.primary.withValues(alpha: 0.15),
                      cs.primary.withValues(alpha: 0.06),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  CupertinoIcons.doc_text,
                  color: cs.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Bank Slip Number',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: cs.onSurface),
              ),
              const Spacer(),
              Text('Optional', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 16),
          CupertinoTextField(
            controller: _bankSlipController,
            placeholder: 'Bank slip number',
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outlineVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDepositDateCard() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
        border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: CupertinoListTile(
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                cs.primary.withValues(alpha: 0.15),
                cs.primary.withValues(alpha: 0.06),
              ],
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            CupertinoIcons.calendar,
            color: cs.primary,
            size: 20,
          ),
        ),
        title: const Text('Deposit Date', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        trailing: GestureDetector(
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: _depositDate,
              firstDate: DateTime.now().subtract(const Duration(days: 7)),
              lastDate: DateTime.now(),
            );
            if (date != null) {
              setState(() => _depositDate = date);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
            ),
            child: Text(
              '${_depositDate.day}/${_depositDate.month}/${_depositDate.year}',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: cs.primary),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNotesCard() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
        border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      cs.primary.withValues(alpha: 0.15),
                      cs.primary.withValues(alpha: 0.06),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  CupertinoIcons.text_alignleft,
                  color: cs.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text('Notes', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: cs.onSurface)),
              const Spacer(),
              Text('Optional', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 16),
          CupertinoTextField(
            controller: _notesController,
            placeholder: 'Add any additional notes...',
            maxLines: 3,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outlineVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton(double availableBalance) {
    final cs = Theme.of(context).colorScheme;
    final isValid = _calculatedTotal > 0 && _calculatedTotal <= availableBalance && _receiptImage != null;

    return GestureDetector(
      onTap: isValid && !_isSubmitting ? _handleSubmit : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          gradient: isValid
              ? LinearGradient(colors: [Colors.green.shade600, Colors.green.shade700])
              : LinearGradient(colors: [cs.outline, cs.outlineVariant]),
          borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
        ),
        child: _isSubmitting
            ? const Center(child: CupertinoActivityIndicator(radius: 12, color: CupertinoColors.white))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(CupertinoIcons.checkmark_circle_fill, color: Colors.white, size: 24),
                  const SizedBox(width: 12),
                  Text(
                    'Submit ${Formatters.currency(_calculatedTotal)} to Bank',
                    style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
      ),
    );
  }

  /// Scan bank slip using professional document scanner with edge detection
  Future<void> _scanBankSlip() async {
    final result = await _documentScanner.scanDocument(
      config: DocumentScannerService.bankSlipConfig,
      context: context,
    );

    if (result.success && result.processedImages.isNotEmpty) {
      setState(() {
        _receiptImage = result.processedImages.first;
      });
    } else if (result.error != null && mounted) {
      SnackbarHelper.showError(context, result.error!);
    }
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_receiptImage == null) {
      SnackbarHelper.showError(context, 'Please attach receipt photo');
      return;
    }

    setState(() => _isSubmitting = true);
    HapticFeedback.mediumImpact();

    try {
      final cashNotifier = ref.read(cashNotifierProvider.notifier);
      final receiptUrl = await cashNotifier.uploadReceiptPhoto(_receiptImage!.path);

      if (receiptUrl == null) {
        throw Exception('Failed to upload receipt photo');
      }

      final request = SubmitCashRequest(
        shopId: widget.shopId,
        totalAmount: _calculatedTotal,
        notes500: _denominationValues['notes_500']!,
        notes200: _denominationValues['notes_200']!,
        notes100: _denominationValues['notes_100']!,
        notes50: _denominationValues['notes_50']!,
        notes20: _denominationValues['notes_20']!,
        notes10: _denominationValues['notes_10']!,
        bankAccountId: _selectedBankAccount?.id,
        bankSlipNumber: _bankSlipController.text.trim().isEmpty ? null : _bankSlipController.text.trim(),
        depositDate: _depositDate,
        receiptPhotoUrl: receiptUrl,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      );

      final success = await cashNotifier.submitCash(request);

      if (success && mounted) {
        HapticFeedback.heavyImpact();
        SnackbarHelper.showSuccess(context, 'Cash submitted successfully! Awaiting approval.');

        // Clear form after successful submission
        _clearAll();
        setState(() => _receiptImage = null);
        _bankSlipController.clear();
        _notesController.clear();

        // Call the success callback
        widget.onSubmitSuccess?.call();
      } else {
        throw Exception('Failed to submit cash');
      }
    } catch (e) {
      if (mounted) {
        SnackbarHelper.showError(context, 'Error: ${e.toString().replaceAll('Exception: ', '')}');
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Color _getDenominationColor(int denomination) {
    switch (denomination) {
      case 500: return const Color(0xFF9C27B0);
      case 200: return const Color(0xFFFF9800);
      case 100: return const Color(0xFF2196F3);
      case 50: return const Color(0xFF4CAF50);
      case 20: return const Color(0xFFF44336);
      case 10: return const Color(0xFF795548);
      default: return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }
}
