import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../sales/models/expense_header.dart';
import '../../sales/providers/expense_header_provider.dart';

/// Add Expense bottom sheet — uses real expense headers from provider.
/// Shows all active UP liquor shop expense categories with amount inputs.
class AddExpenseSheet extends StatefulWidget {
  final void Function(Map<String, double> expenses)? onAdd;
  final Map<String, double>? initialExpenses;

  const AddExpenseSheet({super.key, this.onAdd, this.initialExpenses});

  static Future<void> show(BuildContext context, {
    void Function(Map<String, double>)? onAdd,
    Map<String, double>? initialExpenses,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddExpenseSheet(onAdd: onAdd, initialExpenses: initialExpenses),
    );
  }

  @override
  State<AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<AddExpenseSheet> {
  final Map<String, TextEditingController> _controllers = {};
  List<ExpenseHeader> _activeHeaders = [];

  @override
  void initState() {
    super.initState();
    _loadHeaders();
  }

  void _loadHeaders() {
    final provider = context.read<ExpenseHeaderProvider>();
    _activeHeaders = provider.allActiveHeaders;
    for (final header in _activeHeaders) {
      // Backend stores expenses by header name, not ID
      final initial = widget.initialExpenses?[header.name];
      _controllers[header.id] = TextEditingController(
        text: initial != null && initial > 0 ? initial.toStringAsFixed(0) : '',
      );
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
    final expenses = <String, double>{};
    for (final header in _activeHeaders) {
      final value = double.tryParse(_controllers[header.id]?.text.trim() ?? '');
      if (value != null && value > 0) {
        expenses[header.name] = value;
      }
    }
    widget.onAdd?.call(expenses);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
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
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(color: const Color(0xFFD0D5DD), borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 16),
          // Title
          Text(
            'Add Expense',
            textAlign: TextAlign.center,
            style: AppTextStyles.h4.copyWith(
              fontWeight: FontWeight.w900, fontSize: 21, color: const Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Daily shop expenses',
            style: AppTextStyles.bodySmall.copyWith(
              color: const Color(0xFF888888), fontSize: 13,
            ),
          ),
          const SizedBox(height: 20),

          // Scrollable expense inputs
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final header in _activeHeaders) ...[
                    _buildExpenseField(header),
                    const SizedBox(height: 14),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Total row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F6FA),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total Expenses', style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w700, fontSize: 15, color: const Color(0xFF555555),
                )),
                StatefulBuilder(builder: (_, __) {
                  // Rebuild on any controller change
                  return Text(
                    '\u20B9 ${_total.toStringAsFixed(0)}',
                    style: AppTextStyles.h4.copyWith(
                      fontWeight: FontWeight.w900, fontSize: 18, color: const Color(0xFF1A1A2E),
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 16),

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
                'Add Expenses',
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

  Widget _buildExpenseField(ExpenseHeader header) {
    final controller = _controllers[header.id]!;
    final icon = _iconForHeader(header.id);

    return Row(
      children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFFF0F4FF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: const Color(0xFF0D47A1)),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: Text(
            header.name,
            style: AppTextStyles.bodyMedium.copyWith(
              fontWeight: FontWeight.w700, fontSize: 14, color: const Color(0xFF1A1A2E),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
            textAlign: TextAlign.right,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: '0',
              hintStyle: AppTextStyles.bodySmall.copyWith(color: const Color(0xFFCCCCCC), fontSize: 14),
              prefixText: '\u20B9 ',
              prefixStyle: const TextStyle(color: Color(0xFF888888), fontSize: 14, fontWeight: FontWeight.w600),
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
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }

  IconData _iconForHeader(String id) {
    switch (id) {
      case 'godam_charges': return Icons.warehouse_outlined;
      case 'transport': return Icons.local_shipping_outlined;
      case 'license_fee': return Icons.assignment_outlined;
      case 'staff_salary': return Icons.people_outline;
      case 'shop_rent': return Icons.storefront_outlined;
      case 'utilities': return Icons.power_outlined;
      case 'breakage': return Icons.broken_image_outlined;
      case 'cooler_rent': return Icons.ac_unit_outlined;
      case 'loading_unloading': return Icons.inventory_2_outlined;
      case 'muneem': return Icons.calculate_outlined;
      case 'electricity': return Icons.bolt_outlined;
      case 'cleaning': return Icons.cleaning_services_outlined;
      case 'police_local': return Icons.security_outlined;
      case 'misc': return Icons.more_horiz;
      default: return Icons.receipt_long_outlined;
    }
  }
}
