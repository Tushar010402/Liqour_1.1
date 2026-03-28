import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_text_styles.dart';

/// Cash Details bottom sheet — enter note counts per denomination.
/// Updated: ₹2000 removed (demonetized in India 2023).
/// Shows: denomination label, count input, and live subtotal per row.
class CashDetailsSheet extends StatefulWidget {
  final void Function(Map<int, int> denominations, double total)? onAdd;

  const CashDetailsSheet({super.key, this.onAdd});

  static Future<void> show(BuildContext context, {void Function(Map<int, int>, double)? onAdd}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CashDetailsSheet(onAdd: onAdd),
    );
  }

  @override
  State<CashDetailsSheet> createState() => _CashDetailsSheetState();
}

class _CashDetailsSheetState extends State<CashDetailsSheet> {
  // Current Indian currency denominations (₹2000 demonetized Sep 2023)
  static const _denomValues = [500, 200, 100, 50, 20, 10];
  final Map<int, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    for (final d in _denomValues) {
      _controllers[d] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) { c.dispose(); }
    super.dispose();
  }

  double get _total {
    double sum = 0;
    for (final d in _denomValues) {
      final count = int.tryParse(_controllers[d]!.text.trim()) ?? 0;
      sum += d * count;
    }
    return sum;
  }

  void _handleAdd() {
    final denominations = <int, int>{};
    for (final d in _denomValues) {
      final count = int.tryParse(_controllers[d]!.text.trim()) ?? 0;
      if (count > 0) denominations[d] = count;
    }
    double total = 0;
    for (final e in denominations.entries) { total += e.key * e.value; }
    widget.onAdd?.call(denominations, total);
    Navigator.pop(context);
  }

  String _formatAmount(double amount) {
    if (amount <= 0) return '0';
    final s = amount.toInt().toString();
    if (s.length <= 3) return s;
    final l3 = s.substring(s.length - 3);
    var r = s.substring(0, s.length - 3);
    final p = <String>[];
    while (r.length > 2) { p.insert(0, r.substring(r.length - 2)); r = r.substring(0, r.length - 2); }
    if (r.isNotEmpty) p.insert(0, r);
    return '${p.join(",")},${l3}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 22, right: 22, top: 26,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Color(0x1A000000), blurRadius: 24, offset: Offset(0, -6))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(width: 36, height: 4,
            decoration: BoxDecoration(color: const Color(0xFFD0D5DD), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          // Title
          Text(
            'Cash Details',
            textAlign: TextAlign.center,
            style: AppTextStyles.h4.copyWith(
              fontWeight: FontWeight.w900, fontSize: 21, color: const Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Enter number of notes for each denomination',
            style: AppTextStyles.bodySmall.copyWith(color: const Color(0xFF888888), fontSize: 13),
          ),
          const SizedBox(height: 20),

          // Denomination rows
          for (final denom in _denomValues) ...[
            _buildDenomRow(denom),
            const SizedBox(height: 12),
          ],

          const SizedBox(height: 8),

          // Total
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFD0D9F0)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total Cash', style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w700, fontSize: 15, color: const Color(0xFF555555))),
                Text('\u20B9 ${_formatAmount(_total)}', style: AppTextStyles.h4.copyWith(
                  fontWeight: FontWeight.w900, fontSize: 20, color: const Color(0xFF0D47A1))),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Add button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _handleAdd,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2196F3),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: Text(
                'Add',
                style: AppTextStyles.h5.copyWith(
                  fontWeight: FontWeight.w800, fontSize: 18, color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDenomRow(int denom) {
    final controller = _controllers[denom]!;
    final count = int.tryParse(controller.text.trim()) ?? 0;
    final subtotal = denom * count;

    return Row(
      children: [
        // Denomination label
        Container(
          width: 60,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F6FA),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE0E3EA)),
          ),
          child: Center(
            child: Text(
              '\u20B9$denom',
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w800, fontSize: 14, color: const Color(0xFF1A1A2E),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // × symbol
        Text(' \u00D7 ', style: AppTextStyles.bodyMedium.copyWith(
          fontWeight: FontWeight.w600, fontSize: 16, color: const Color(0xFF888888))),
        const SizedBox(width: 4),
        // Count input
        SizedBox(
          width: 72,
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: '0',
              hintStyle: AppTextStyles.bodySmall.copyWith(color: const Color(0xFFCCCCCC), fontSize: 15),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFD0D5DD), width: 1.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFD0D5DD), width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF0D47A1), width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: 8),
        // = symbol
        Text(' = ', style: AppTextStyles.bodyMedium.copyWith(
          fontWeight: FontWeight.w600, fontSize: 16, color: const Color(0xFF888888))),
        // Subtotal
        Expanded(
          child: Text(
            '\u20B9${_formatAmount(subtotal.toDouble())}',
            textAlign: TextAlign.right,
            style: AppTextStyles.bodyMedium.copyWith(
              fontWeight: FontWeight.w700, fontSize: 15,
              color: subtotal > 0 ? const Color(0xFF1A1A2E) : const Color(0xFFCCCCCC),
            ),
          ),
        ),
      ],
    );
  }
}
