import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../services/cash_service.dart';
import '../models/cash_models.dart';

/// iOS-style bottom sheet for bulk resetting team cash balances (Admin only)
class BulkResetSheet extends StatefulWidget {
  final List<TeamCashBalance> teamBalances;
  final Future<void> Function(
    List<String>? userIds,
    double newBalance,
    String reason,
    String? notes,
  ) onConfirm;

  const BulkResetSheet({
    super.key,
    required this.teamBalances,
    required this.onConfirm,
  });

  @override
  State<BulkResetSheet> createState() => _BulkResetSheetState();
}

class _BulkResetSheetState extends State<BulkResetSheet> {
  final TextEditingController _amountController = TextEditingController(text: '0');
  final TextEditingController _notesController = TextEditingController();
  String? _selectedReason;
  bool _isLoading = false;
  bool _resetAllUsers = true;
  final Set<String> _selectedUserIds = {};
  bool _showConfirmation = false;

  @override
  void initState() {
    super.initState();
    // Select all users by default
    for (final member in widget.teamBalances) {
      _selectedUserIds.add(member.userId);
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  double get _totalCurrentBalance {
    double total = 0;
    for (final member in widget.teamBalances) {
      if (_resetAllUsers || _selectedUserIds.contains(member.userId)) {
        total += member.currentBalance;
      }
    }
    return total;
  }

  int get _affectedUsersCount {
    if (_resetAllUsers) return widget.teamBalances.length;
    return _selectedUserIds.length;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _showConfirmation ? _buildConfirmationView() : _buildMainView(),
        ),
      ),
    );
  }

  Widget _buildMainView() {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Handle bar
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Title
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.restart_alt,
                color: Colors.red,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bulk Reset Balances',
                    style: AppTextStyles.h5.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${widget.teamBalances.length} team members',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Reset All Toggle
        Card(
          elevation: 0,
          color: cs.surfaceContainerHighest,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: SwitchListTile(
            title: const Text('Reset All Users'),
            subtitle: Text(
              _resetAllUsers
                  ? 'All ${widget.teamBalances.length} users will be reset'
                  : '${_selectedUserIds.length} user(s) selected',
            ),
            value: _resetAllUsers,
            activeThumbColor: cs.primary,
            onChanged: (value) {
              setState(() {
                _resetAllUsers = value;
                if (value) {
                  _selectedUserIds.clear();
                  for (final member in widget.teamBalances) {
                    _selectedUserIds.add(member.userId);
                  }
                }
              });
            },
          ),
        ),
        const SizedBox(height: 16),

        // User Selection (if not reset all)
        if (!_resetAllUsers) ...[
          Text(
            'Select Users to Reset',
            style: AppTextStyles.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: widget.teamBalances.length,
              itemBuilder: (context, index) {
                final member = widget.teamBalances[index];
                final isSelected = _selectedUserIds.contains(member.userId);
                return CheckboxListTile(
                  title: Text(member.displayName),
                  subtitle: Text(
                    '${member.role.toUpperCase()} • ${Formatters.currency(member.currentBalance)}',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                  value: isSelected,
                  activeColor: cs.primary,
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        _selectedUserIds.add(member.userId);
                      } else {
                        _selectedUserIds.remove(member.userId);
                      }
                    });
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Current Total
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.account_balance_wallet, color: cs.primary, size: 20),
              const SizedBox(width: 12),
              Text(
                'Current Total: ${Formatters.currency(_totalCurrentBalance)}',
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                  color: cs.primary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // New Balance Amount
        Text(
          'New Balance Amount (per user)',
          style: AppTextStyles.bodyMedium.copyWith(
            fontWeight: FontWeight.w600,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
          ],
          style: AppTextStyles.h3.copyWith(
            color: cs.primary,
            fontWeight: FontWeight.bold,
          ),
          decoration: InputDecoration(
            prefixText: '₹ ',
            prefixStyle: AppTextStyles.h3.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.bold,
            ),
            hintText: '0.00',
            filled: true,
            fillColor: cs.surfaceContainerHighest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: cs.primary, width: 2),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Quick Amount Chips
        Wrap(
          spacing: 8,
          children: [
            _buildQuickAmountChip('Reset to ₹0', 0),
            _buildQuickAmountChip('₹500', 500),
            _buildQuickAmountChip('₹1,000', 1000),
          ],
        ),
        const SizedBox(height: 24),

        // Reason Dropdown
        Text(
          'Reason for Reset',
          style: AppTextStyles.bodyMedium.copyWith(
            fontWeight: FontWeight.w600,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButtonFormField<String>(
            initialValue: _selectedReason,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            hint: const Text('Select a reason'),
            items: CashService.adjustmentReasons.entries.map((entry) {
              return DropdownMenuItem<String>(
                value: entry.key,
                child: Text(entry.value),
              );
            }).toList(),
            onChanged: (value) {
              setState(() {
                _selectedReason = value;
              });
            },
          ),
        ),
        const SizedBox(height: 16),

        // Notes (optional)
        Text(
          'Notes (Optional)',
          style: AppTextStyles.bodyMedium.copyWith(
            fontWeight: FontWeight.w600,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _notesController,
          maxLines: 2,
          decoration: InputDecoration(
            hintText: 'Add additional notes...',
            filled: true,
            fillColor: cs.surfaceContainerHighest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: cs.primary, width: 2),
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Warning message
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'This will reset $_affectedUsersCount user(s) balances. An audit trail will be created for each user.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: Colors.red[800],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Action Buttons
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: _selectedReason == null || _affectedUsersCount == 0
                    ? null
                    : () => setState(() => _showConfirmation = true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  disabledBackgroundColor: cs.outlineVariant,
                ),
                child: const Text(
                  'Review Reset',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildConfirmationView() {
    final cs = Theme.of(context).colorScheme;
    final newBalance = double.tryParse(_amountController.text.trim()) ?? 0.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Handle bar
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Warning Icon
        Center(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.warning_rounded,
              color: Colors.red,
              size: 48,
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Confirmation Title
        Text(
          'Confirm Bulk Reset',
          style: AppTextStyles.h3.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Please review the following changes',
          style: AppTextStyles.bodyMedium.copyWith(
            color: cs.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),

        // Summary Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _buildSummaryRow('Users Affected', '$_affectedUsersCount'),
              const Divider(height: 24),
              _buildSummaryRow('Current Total', Formatters.currency(_totalCurrentBalance)),
              const Divider(height: 24),
              _buildSummaryRow('New Balance (each)', Formatters.currency(newBalance)),
              const Divider(height: 24),
              _buildSummaryRow('Reason', CashService.adjustmentReasons[_selectedReason] ?? _selectedReason ?? 'N/A'),
              if (_notesController.text.trim().isNotEmpty) ...[
                const Divider(height: 24),
                _buildSummaryRow('Notes', _notesController.text.trim()),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Final Warning
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.lock, color: Colors.red, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'This action cannot be undone. All changes will be logged in the audit trail.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: Colors.red[800],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Action Buttons
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() => _showConfirmation = false),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Go Back'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleConfirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  disabledBackgroundColor: cs.outlineVariant,
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Confirm Reset',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTextStyles.bodyMedium.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        Flexible(
          child: Text(
            value,
            style: AppTextStyles.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickAmountChip(String label, double amount) {
    final cs = Theme.of(context).colorScheme;
    return ActionChip(
      label: Text(label),
      backgroundColor: cs.outlineVariant,
      labelStyle: const TextStyle(
        fontWeight: FontWeight.w500,
      ),
      onPressed: () {
        _amountController.text = amount.toStringAsFixed(0);
      },
    );
  }

  Future<void> _handleConfirm() async {
    if (_selectedReason == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a reason'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final amountText = _amountController.text.trim();
    final amount = double.tryParse(amountText) ?? 0.0;

    setState(() => _isLoading = true);

    try {
      await widget.onConfirm(
        _resetAllUsers ? null : _selectedUserIds.toList(),
        amount,
        _selectedReason!,
        _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
