import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/physical_audit_models.dart';
import '../providers/physical_audit_provider.dart';

/// Cash Audit Screen - Denomination-wise cash counting
class CashAuditScreen extends ConsumerStatefulWidget {
  const CashAuditScreen({super.key});

  @override
  ConsumerState<CashAuditScreen> createState() => _CashAuditScreenState();
}

class _CashAuditScreenState extends ConsumerState<CashAuditScreen> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, int> _denominations = {};
  String? _notes;

  @override
  void initState() {
    super.initState();
    // Initialize controllers for all denominations
    for (final note in CurrencyDenominations.notes) {
      _controllers[note] = TextEditingController();
      _denominations[note] = 0;
    }
    for (final coin in CurrencyDenominations.coins) {
      _controllers[coin] = TextEditingController();
      _denominations[coin] = 0;
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  double get _totalCounted => CashAuditData.calculateTotal(_denominations);

  @override
  Widget build(BuildContext context) {
    final activeAudit = ref.watch(activeAuditNotifierProvider);
    final shopId = ref.watch(auditShopIdProvider);

    // If no active audit or not a cash audit, show empty state
    if (!activeAudit.hasSession || !activeAudit.isCashAudit) {
      return _buildNoAuditState();
    }

    final expectedCash = ref.watch(expectedCashProvider(shopId ?? ''));
    final cashData = activeAudit.cashData;
    final variance = _totalCounted - (cashData?.expectedAmount ?? 0);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Summary Card
          _buildSummaryCard(
            expectedCash: expectedCash,
            actualCash: _totalCounted,
            variance: variance,
          ),

          const SizedBox(height: 24),

          // Notes Section
          _buildSectionHeader('Notes (Denominations)'),
          const SizedBox(height: 12),
          _buildDenominationGrid(CurrencyDenominations.notes),

          const SizedBox(height: 24),

          // Coins Section
          _buildSectionHeader('Coins'),
          const SizedBox(height: 12),
          _buildDenominationGrid(CurrencyDenominations.coins),

          const SizedBox(height: 24),

          // Notes Field
          _buildNotesField(),

          const SizedBox(height: 24),

          // Action Buttons
          _buildActionButtons(activeAudit),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildNoAuditState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                CupertinoIcons.money_dollar,
                size: 48,
                color: Color(0xFF10B981),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Cash Audit Active',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Start a cash audit from the Overview tab to begin counting',
              style: TextStyle(
                fontSize: 14,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard({
    required AsyncValue<double> expectedCash,
    required double actualCash,
    required double variance,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF10B981),
            const Color(0xFF059669),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildSummaryItem(
                  label: 'Expected',
                  value: expectedCash.when(
                    data: (v) => '₹${v.toStringAsFixed(0)}',
                    loading: () => '...',
                    error: (_, __) => '₹0',
                  ),
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: Colors.white.withOpacity(0.3),
              ),
              Expanded(
                child: _buildSummaryItem(
                  label: 'Counted',
                  value: '₹${actualCash.toStringAsFixed(0)}',
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: Colors.white.withOpacity(0.3),
              ),
              Expanded(
                child: _buildSummaryItem(
                  label: 'Variance',
                  value: variance >= 0
                      ? '+₹${variance.toStringAsFixed(0)}'
                      : '-₹${variance.abs().toStringAsFixed(0)}',
                  valueColor: variance < 0
                      ? Colors.red[200]
                      : variance > 0
                          ? Colors.amber[200]
                          : Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem({
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withOpacity(0.8),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: valueColor ?? Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        CupertinoButton(
          padding: EdgeInsets.zero,
          child: const Text('Clear All', style: TextStyle(fontSize: 13)),
          onPressed: () {
            for (final entry in _controllers.entries) {
              entry.value.clear();
              _denominations[entry.key] = 0;
            }
            setState(() {});
            _updateProvider();
          },
        ),
      ],
    );
  }

  Widget _buildDenominationGrid(List<String> denominations) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 2.2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: denominations.length,
      itemBuilder: (context, index) {
        final denom = denominations[index];
        return _buildDenominationTile(denom);
      },
    );
  }

  Widget _buildDenominationTile(String denomination) {
    final count = _denominations[denomination] ?? 0;
    final value = int.parse(denomination);
    final total = count * value;
    final isNote = CurrencyDenominations.notes.contains(denomination);

    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: count > 0
              ? const Color(0xFF10B981).withOpacity(0.5)
              : CupertinoColors.systemGrey5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // Denomination Label
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isNote
                      ? const Color(0xFF10B981).withOpacity(0.1)
                      : CupertinoColors.systemGrey6,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '₹$denomination',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isNote
                        ? const Color(0xFF10B981)
                        : CupertinoColors.label,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Count Input
              Expanded(
                child: TextField(
                  controller: _controllers[denomination],
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    hintText: '0',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: CupertinoColors.systemGrey6,
                  ),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  onChanged: (value) {
                    final count = int.tryParse(value) ?? 0;
                    setState(() {
                      _denominations[denomination] = count;
                    });
                    _updateProvider();
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Total for this denomination
              SizedBox(
                width: 50,
                child: Text(
                  total > 0 ? '₹$total' : '',
                  style: TextStyle(
                    fontSize: 12,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotesField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Additional Notes',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: CupertinoColors.systemBackground,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextField(
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Any discrepancies or notes...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: CupertinoColors.systemBackground,
            ),
            onChanged: (value) => _notes = value,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(ActiveAuditState state) {
    final isSubmitting = state.isSubmitting;

    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: isSubmitting ? null : _resetCounting,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              side: const BorderSide(color: CupertinoColors.systemGrey),
            ),
            child: const Text('Reset'),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: ElevatedButton(
            onPressed: isSubmitting ? null : _submitCashAudit,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: isSubmitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Submit Cash Count',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  void _updateProvider() {
    ref.read(activeAuditNotifierProvider.notifier).updateDenominations(
          Map.from(_denominations),
        );
  }

  void _resetCounting() {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Reset Count?'),
        content: const Text('This will clear all denomination entries.'),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(context);
              for (final entry in _controllers.entries) {
                entry.value.clear();
                _denominations[entry.key] = 0;
              }
              setState(() {});
              _updateProvider();
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  void _submitCashAudit() async {
    final activeAudit = ref.read(activeAuditNotifierProvider);
    if (_totalCounted == 0 && activeAudit.cashData?.expectedAmount != 0) {
      showCupertinoDialog(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('No Cash Counted'),
          content: const Text(
            'You haven\'t entered any denomination counts. Are you sure you want to submit with ₹0?',
          ),
          actions: [
            CupertinoDialogAction(
              child: const Text('Go Back'),
              onPressed: () => Navigator.pop(context),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.pop(context);
                _doSubmit();
              },
              child: const Text('Submit Anyway'),
            ),
          ],
        ),
      );
      return;
    }

    _doSubmit();
  }

  void _doSubmit() async {
    final success =
        await ref.read(activeAuditNotifierProvider.notifier).submitCashAudit();

    if (success && mounted) {
      final activeAudit = ref.read(activeAuditNotifierProvider);

      // Check if this is a combined audit that still needs inventory
      if (activeAudit.session?.type == AuditType.combined) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cash audit submitted! Now complete inventory audit.'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      } else {
        // Cash-only audit - prompt to complete
        _showCompleteAuditDialog();
      }
    } else if (mounted) {
      final error = ref.read(activeAuditNotifierProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error ?? 'Failed to submit cash audit'),
          backgroundColor: CupertinoColors.systemRed,
        ),
      );
    }
  }

  void _showCompleteAuditDialog() {
    final notesController = TextEditingController();
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Complete Audit'),
        content: Column(
          children: [
            const Text('Cash count submitted successfully!'),
            const SizedBox(height: 16),
            CupertinoTextField(
              controller: notesController,
              placeholder: 'Final notes (optional)',
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Add More Counts'),
            onPressed: () => Navigator.pop(context),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () async {
              Navigator.pop(context);
              final success = await ref
                  .read(activeAuditNotifierProvider.notifier)
                  .completeAudit(notes: notesController.text);
              if (success && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Audit completed successfully!'),
                    backgroundColor: Color(0xFF10B981),
                  ),
                );
              }
            },
            child: const Text('Complete Audit'),
          ),
        ],
      ),
    );
  }
}
