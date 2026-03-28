import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_text_styles.dart';

/// UPI Details bottom sheet — same pattern as CashDetailsSheet.
/// Allows salesman to enter UPI collection amounts by app/source.
class UpiDetailsSheet extends StatefulWidget {
  final void Function(Map<String, double> upiEntries, double total)? onAdd;

  const UpiDetailsSheet({super.key, this.onAdd});

  static Future<void> show(BuildContext context, {void Function(Map<String, double>, double)? onAdd}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => UpiDetailsSheet(onAdd: onAdd),
    );
  }

  @override
  State<UpiDetailsSheet> createState() => _UpiDetailsSheetState();
}

class _UpiDetailsSheetState extends State<UpiDetailsSheet> {
  final _upiSources = ['Google Pay', 'PhonePe', 'Paytm', 'Other UPI'];
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    for (final s in _upiSources) {
      _controllers[s] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) { c.dispose(); }
    super.dispose();
  }

  double get _total {
    double sum = 0;
    for (final c in _controllers.values) {
      sum += double.tryParse(c.text.trim()) ?? 0;
    }
    return sum;
  }

  void _handleAdd() {
    final entries = <String, double>{};
    for (final entry in _controllers.entries) {
      final value = double.tryParse(entry.value.text.trim()) ?? 0;
      if (value > 0) entries[entry.key] = value;
    }
    double total = 0;
    for (final v in entries.values) { total += v; }
    widget.onAdd?.call(entries, total);
    Navigator.pop(context);
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
          // Title
          Text(
            'UPI Details',
            textAlign: TextAlign.center,
            style: AppTextStyles.h4.copyWith(
              fontWeight: FontWeight.w900, fontSize: 21, color: const Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 24),

          // UPI source inputs
          for (final source in _upiSources) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                source,
                style: AppTextStyles.bodyLarge.copyWith(
                  fontWeight: FontWeight.w800, fontSize: 16, color: const Color(0xFF1A1A2E),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controllers[source],
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Enter amount',
                hintStyle: AppTextStyles.bodySmall.copyWith(color: const Color(0xFFAAAAAA), fontWeight: FontWeight.w500, fontSize: 14),
                prefixText: '\u20B9 ',
                prefixStyle: const TextStyle(color: Color(0xFF888888), fontSize: 15, fontWeight: FontWeight.w600),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFD0D5DD), width: 1.8),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFD0D5DD), width: 1.8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF0D47A1), width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
              ),
            ),
            const SizedBox(height: 18),
          ],

          // Total
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFD0D9F0)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total UPI', style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w700, fontSize: 15, color: const Color(0xFF555555))),
                Text('\u20B9 ${_total.toStringAsFixed(0)}', style: AppTextStyles.h4.copyWith(
                  fontWeight: FontWeight.w900, fontSize: 18, color: const Color(0xFF0D47A1))),
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
}
