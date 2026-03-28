import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../models/bank_models.dart';
import '../providers/bank_provider.dart';

/// Modern iOS 16-style Record Transaction Form
/// Supports Deposit, Withdrawal, and OD Repayment
class RecordTransactionFormScreen extends ConsumerStatefulWidget {
  final String accountId;
  final String transactionType; // deposit, withdrawal, od_repayment
  final TenantBankAccount account;

  const RecordTransactionFormScreen({
    super.key,
    required this.accountId,
    required this.transactionType,
    required this.account,
  });

  @override
  ConsumerState<RecordTransactionFormScreen> createState() =>
      _RecordTransactionFormScreenState();
}

class _RecordTransactionFormScreenState
    extends ConsumerState<RecordTransactionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _bankReferenceController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _bankReferenceController.dispose();
    super.dispose();
  }

  String get _titleText {
    switch (widget.transactionType) {
      case 'deposit':
        return 'Record Deposit';
      case 'withdrawal':
        return 'Record Withdrawal';
      case 'od_repayment':
        return 'Record OD Repayment';
      default:
        return 'Record Transaction';
    }
  }

  IconData get _iconData {
    switch (widget.transactionType) {
      case 'deposit':
        return Icons.arrow_downward;
      case 'withdrawal':
        return Icons.arrow_upward;
      case 'od_repayment':
        return Icons.replay;
      default:
        return Icons.receipt;
    }
  }

  Color get _iconColor {
    switch (widget.transactionType) {
      case 'deposit':
        return AppColors.success;
      case 'withdrawal':
        return AppColors.error;
      case 'od_repayment':
        return AppColors.warning;
      default:
        return AppColors.info;
    }
  }

  Future<void> _selectDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      builder: (context, child) {
        final parentCs = Theme.of(context).colorScheme;
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: parentCs.copyWith(
              primary: AppColors.info,
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (date != null) {
      setState(() => _selectedDate = date);
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final request = RecordBankTransactionRequest(
        transactionType: widget.transactionType,
        amount: double.parse(_amountController.text),
        bankReferenceNo: _bankReferenceController.text.isEmpty
            ? null
            : _bankReferenceController.text,
        transactionDate: _selectedDate,
        // Backend requires description field - send empty string if not provided
        description: _descriptionController.text.isEmpty
            ? ''
            : _descriptionController.text,
      );

      await ref
          .read(bankTransactionFormProvider.notifier)
          .recordTransaction(widget.accountId, request);

      final formState = ref.read(bankTransactionFormProvider);

      if (formState.errorMessage != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(formState.errorMessage!),
              backgroundColor: AppColors.error,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Transaction recorded successfully'),
              backgroundColor: AppColors.success,
            ),
          );
          // Refresh all bank account data for real-time UI updates
          ref.invalidate(bankAccountProvider(widget.accountId)); // Account detail screen
          ref.invalidate(bankTransactionsProvider(widget.accountId)); // Transaction list
          ref.invalidate(bankAccountSummaryProvider(widget.accountId)); // Account summary
          ref.invalidate(bankAccountsProvider); // Main accounts list (updates balance)
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: cs.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _titleText,
          style: AppTextStyles.h5.copyWith(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Transaction Type Icon
              Center(
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: _iconColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_iconData, size: 40, color: _iconColor),
                ),
              ),
              const SizedBox(height: 12),

              // Account Info
              Center(
                child: Text(
                  widget.account.bankName,
                  style: AppTextStyles.h6.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  widget.account.accountNumber,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Amount Field
              Text(
                'Amount',
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.currency_rupee, size: 20),
                  hintText: '0.00',
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                style: AppTextStyles.h5.copyWith(fontWeight: FontWeight.bold),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter amount';
                  }
                  final amount = double.tryParse(value);
                  if (amount == null || amount <= 0) {
                    return 'Please enter a valid amount';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Transaction Date
              Text(
                'Transaction Date',
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: _selectDate,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today, size: 20, color: AppColors.info),
                      const SizedBox(width: 12),
                      Text(
                        DateFormat('dd MMM yyyy').format(_selectedDate),
                        style: AppTextStyles.bodyLarge,
                      ),
                      const Spacer(),
                      Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Bank Reference Number
              Text(
                'Bank Reference No. (Optional)',
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _bankReferenceController,
                decoration: InputDecoration(
                  hintText: 'e.g., TXN123456',
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Description
              Text(
                'Description (Optional)',
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descriptionController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Add notes or description...',
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Submit Button
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submitForm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _iconColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          'Record Transaction',
                          style: AppTextStyles.bodyLarge.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
