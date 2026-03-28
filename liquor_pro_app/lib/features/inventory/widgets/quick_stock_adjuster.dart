import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../models/product.dart';
import '../providers/product_provider.dart';

/// Quick Stock Adjuster Widget
/// Provides inline stock adjustment with +/- buttons and direct input
class QuickStockAdjuster extends StatefulWidget {
  final Product product;
  final Function(int newQuantity, String? reason) onAdjust;
  final bool showValue;

  const QuickStockAdjuster({
    super.key,
    required this.product,
    required this.onAdjust,
    this.showValue = true,
  });

  @override
  State<QuickStockAdjuster> createState() => _QuickStockAdjusterState();
}

class _QuickStockAdjusterState extends State<QuickStockAdjuster> {
  final TextEditingController _controller = TextEditingController();
  bool _isEditing = false;
  late int _currentStock;

  @override
  void initState() {
    super.initState();
    _currentStock = 0; // Will be updated in didChangeDependencies
    _controller.text = _currentStock.toString();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Get stock from ProductProvider
    final productProvider = context.read<ProductProvider>();
    final stock = productProvider.getStockForProduct(widget.product.id);
    _currentStock = stock?.quantity ?? 0;
    _controller.text = _currentStock.toString();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color get _stockColor {
    if (_currentStock <= 10) return AppColors.error;
    if (_currentStock <= 50) return AppColors.warning;
    return AppColors.success;
  }

  void _increment(int amount) {
    _adjustStock(_currentStock + amount);
  }

  void _decrement(int amount) {
    final newValue = _currentStock - amount;
    if (newValue >= 0) {
      _adjustStock(newValue);
    }
  }

  void _adjustStock(int newQuantity) {
    setState(() {
      _currentStock = newQuantity;
      _controller.text = newQuantity.toString();
    });

    // Call callback with new quantity
    widget.onAdjust(newQuantity, null);
  }

  void _showQuickAdjustDialog() {
    showDialog(
      context: context,
      builder: (context) => _QuickAdjustDialog(
        product: widget.product,
        currentStock: _currentStock,
        onAdjust: (newQuantity, reason) {
          _adjustStock(newQuantity);
          widget.onAdjust(newQuantity, reason);
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Quick decrement buttons
        _QuickButton(
          icon: Icons.remove,
          onPressed: () => _decrement(1),
          onLongPress: () => _decrement(10),
          color: AppColors.error,
          tooltip: 'Tap: -1, Hold: -10',
        ),

        const SizedBox(width: 4),

        // Current stock display/input
        if (_isEditing)
          SizedBox(
            width: 60,
            child: TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onSubmitted: (value) {
                final newQuantity = int.tryParse(value) ?? _currentStock;
                _adjustStock(newQuantity);
                setState(() => _isEditing = false);
              },
              onTapOutside: (_) {
                setState(() => _isEditing = false);
              },
              autofocus: true,
            ),
          )
        else
          InkWell(
            onTap: () => setState(() => _isEditing = true),
            onLongPress: _showQuickAdjustDialog,
            child: Container(
              width: 60,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: _stockColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _stockColor, width: 1.5),
              ),
              child: widget.showValue
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _currentStock.toString(),
                          style: TextStyle(
                            color: _stockColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        Text(
                          'units',
                          style: TextStyle(
                            color: _stockColor,
                            fontSize: 9,
                          ),
                        ),
                      ],
                    )
                  : Center(
                      child: Text(
                        _currentStock.toString(),
                        style: TextStyle(
                          color: _stockColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
            ),
          ),

        const SizedBox(width: 4),

        // Quick increment buttons
        _QuickButton(
          icon: Icons.add,
          onPressed: () => _increment(1),
          onLongPress: () => _increment(10),
          color: AppColors.success,
          tooltip: 'Tap: +1, Hold: +10',
        ),
      ],
    );
  }
}

/// Quick adjustment button
class _QuickButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final VoidCallback onLongPress;
  final Color color;
  final String tooltip;

  const _QuickButton({
    required this.icon,
    required this.onPressed,
    required this.onLongPress,
    required this.color,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color, width: 1.5),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
      ),
    );
  }
}

/// Quick Adjust Dialog - for larger adjustments
class _QuickAdjustDialog extends StatefulWidget {
  final Product product;
  final int currentStock;
  final Function(int newQuantity, String? reason) onAdjust;

  const _QuickAdjustDialog({
    required this.product,
    required this.currentStock,
    required this.onAdjust,
  });

  @override
  State<_QuickAdjustDialog> createState() => _QuickAdjustDialogState();
}

class _QuickAdjustDialogState extends State<_QuickAdjustDialog> {
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();
  String _adjustmentType = 'set'; // 'set', 'add', 'subtract'

  @override
  void initState() {
    super.initState();
    _quantityController.text = widget.currentStock.toString();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  int get _calculatedQuantity {
    final inputValue = int.tryParse(_quantityController.text) ?? 0;

    switch (_adjustmentType) {
      case 'add':
        return widget.currentStock + inputValue;
      case 'subtract':
        return (widget.currentStock - inputValue).clamp(0, double.infinity).toInt();
      case 'set':
      default:
        return inputValue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Quick Stock Adjustment'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.product.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('Current Stock: ${widget.currentStock} units'),
            const Divider(height: 24),

            // Adjustment type selector
            const Text('Adjustment Type:'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Set To'),
                  selected: _adjustmentType == 'set',
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _adjustmentType = 'set');
                    }
                  },
                ),
                ChoiceChip(
                  label: const Text('Add'),
                  selected: _adjustmentType == 'add',
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _adjustmentType = 'add';
                        _quantityController.text = '0';
                      });
                    }
                  },
                ),
                ChoiceChip(
                  label: const Text('Subtract'),
                  selected: _adjustmentType == 'subtract',
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _adjustmentType = 'subtract';
                        _quantityController.text = '0';
                      });
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Quantity input
            TextField(
              controller: _quantityController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: _adjustmentType == 'set'
                    ? 'New Quantity'
                    : 'Amount to ${_adjustmentType == 'add' ? 'Add' : 'Subtract'}',
                border: const OutlineInputBorder(),
                suffixText: 'units',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),

            // Calculated result
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('New Stock:'),
                  Text(
                    '$_calculatedQuantity units',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Reason (optional)
            TextField(
              controller: _reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                hintText: 'e.g., Stock received, Damaged',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),

            // Quick reason buttons
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ReasonChip(
                  label: 'Stock Received',
                  onTap: () => _reasonController.text = 'Stock Received',
                ),
                _ReasonChip(
                  label: 'Damaged',
                  onTap: () => _reasonController.text = 'Damaged',
                ),
                _ReasonChip(
                  label: 'Sold',
                  onTap: () => _reasonController.text = 'Sold',
                ),
                _ReasonChip(
                  label: 'Returned',
                  onTap: () => _reasonController.text = 'Returned',
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onAdjust(
              _calculatedQuantity,
              _reasonController.text.isEmpty ? null : _reasonController.text,
            );
          },
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}

/// Quick reason selection chip
class _ReasonChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ReasonChip({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Chip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        padding: EdgeInsets.zero,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
