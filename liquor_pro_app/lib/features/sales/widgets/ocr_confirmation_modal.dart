/// OCR Confirmation Modal
///
/// Shows extracted OCR results for user verification before submission.
/// Allows editing, removing, and adding items.
///
/// Features:
/// - Display extracted date, shop, and items
/// - Individual item verification checkmarks
/// - Edit item quantity/details
/// - Remove misdetected items
/// - Add missing items
/// - Accept all or cancel
library;

import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../models/scan_quality_models.dart';

/// Modal for confirming OCR extraction results
class OCRConfirmationModal extends StatefulWidget {
  /// Extraction result to confirm
  final OCRExtractionResult extractionResult;

  /// Expected shop name
  final String expectedShopName;

  /// Callback when user accepts the results
  final Function(OCRExtractionResult) onAccept;

  /// Callback when user cancels
  final VoidCallback onCancel;

  /// Callback to add a missing item
  final VoidCallback? onAddItem;

  const OCRConfirmationModal({
    super.key,
    required this.extractionResult,
    required this.expectedShopName,
    required this.onAccept,
    required this.onCancel,
    this.onAddItem,
  });

  /// Show as a full screen modal
  static Future<void> show({
    required BuildContext context,
    required OCRExtractionResult extractionResult,
    required String expectedShopName,
    required Function(OCRExtractionResult) onAccept,
    required VoidCallback onCancel,
    VoidCallback? onAddItem,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => OCRConfirmationModal(
          extractionResult: extractionResult,
          expectedShopName: expectedShopName,
          onAccept: (result) {
            Navigator.pop(context);
            onAccept(result);
          },
          onCancel: () {
            Navigator.pop(context);
            onCancel();
          },
          onAddItem: onAddItem != null
              ? () {
                  Navigator.pop(context);
                  onAddItem();
                }
              : null,
        ),
      ),
    );
  }

  @override
  State<OCRConfirmationModal> createState() => _OCRConfirmationModalState();
}

class _OCRConfirmationModalState extends State<OCRConfirmationModal> {
  late List<ExtractedItem> _items;
  late DateTime? _date;
  late String? _shopName;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.extractionResult.items);
    _date = widget.extractionResult.date;
    _shopName = widget.extractionResult.shopName;
  }

  void _toggleItemVerified(int index) {
    setState(() {
      _items[index] = _items[index].copyWith(
        isVerified: !_items[index].isVerified,
      );
    });
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
    });
  }

  void _editItem(int index) {
    _showEditItemDialog(index);
  }

  void _verifyAll() {
    setState(() {
      _items = _items.map((item) => item.copyWith(isVerified: true)).toList();
    });
  }

  void _acceptResults() {
    final updatedResult = OCRExtractionResult(
      date: _date,
      rawDateString: widget.extractionResult.rawDateString,
      shopName: _shopName,
      shopMatched: widget.extractionResult.shopMatched,
      items: _items,
      overallConfidence: widget.extractionResult.overallConfidence,
    );
    widget.onAccept(updatedResult);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final verifiedCount = _items.where((i) => i.isVerified).length;
    final totalItems = _items.length;
    final confidence = widget.extractionResult.overallConfidence * 100;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          _buildHeader(),

          // Date and Shop info
          _buildMetadataSection(),

          // Divider
          Divider(color: cs.outlineVariant, height: 1),

          // Items list header
          _buildItemsHeader(verifiedCount, totalItems),

          // Items list
          Expanded(
            child: _buildItemsList(),
          ),

          // Footer with stats and actions
          _buildFooter(verifiedCount, totalItems, confidence),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.document_scanner, color: cs.primary, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'OCR Results',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                ),
                Text(
                  'Verify before submitting',
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: cs.onSurfaceVariant),
            onPressed: widget.onCancel,
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataSection() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        children: [
          // Date row
          _buildMetadataRow(
            icon: Icons.calendar_today,
            label: 'Date',
            value: _date != null
                ? '${_date!.day.toString().padLeft(2, '0')}/${_date!.month.toString().padLeft(2, '0')}/${_date!.year}'
                : 'Not detected',
            isValid: _date != null,
            onEdit: _showDatePicker,
          ),
          const SizedBox(height: 8),
          // Shop row
          _buildMetadataRow(
            icon: Icons.store,
            label: 'Shop',
            value: _shopName ?? 'Not detected',
            isValid: widget.extractionResult.shopMatched,
            expectedValue: widget.expectedShopName,
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataRow({
    required IconData icon,
    required String label,
    required String value,
    required bool isValid,
    String? expectedValue,
    VoidCallback? onEdit,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(
          isValid ? Icons.check_circle : Icons.warning,
          color: isValid ? Colors.green : Colors.orange,
          size: 18,
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 50,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isValid ? cs.onSurface : Colors.orange[700],
            ),
          ),
        ),
        if (onEdit != null)
          GestureDetector(
            onTap: onEdit,
            child: Icon(Icons.edit, size: 18, color: cs.primary),
          ),
      ],
    );
  }

  Widget _buildItemsHeader(int verifiedCount, int totalItems) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                'Extracted Items',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$totalItems found',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          if (_items.isNotEmpty)
            TextButton(
              onPressed: _verifyAll,
              child: Text(
                'Verify All',
                style: TextStyle(
                  fontSize: 13,
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildItemsList() {
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              'No items extracted',
              style: TextStyle(
                fontSize: 15,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            if (widget.onAddItem != null)
              TextButton.icon(
                onPressed: widget.onAddItem,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Item Manually'),
              ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _items.length + 1, // +1 for add button
      itemBuilder: (context, index) {
        if (index == _items.length) {
          // Add item button
          return widget.onAddItem != null
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: OutlinedButton.icon(
                    onPressed: widget.onAddItem,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant, style: BorderStyle.solid),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Missing Item'),
                  ),
                )
              : const SizedBox.shrink();
        }

        return _buildItemCard(index);
      },
    );
  }

  Widget _buildItemCard(int index) {
    final cs = Theme.of(context).colorScheme;
    final item = _items[index];
    final confidenceColor = item.confidence >= 0.8
        ? Colors.green
        : (item.confidence >= 0.6 ? Colors.orange : Colors.red);

    return Dismissible(
      key: Key(item.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => _removeItem(index),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red[400],
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: item.isVerified ? AppColors.success.withOpacity(0.3) : cs.outlineVariant,
            width: item.isVerified ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: () => _toggleItemVerified(index),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Verification checkbox
                GestureDetector(
                  onTap: () => _toggleItemVerified(index),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: item.isVerified ? Colors.green : Colors.transparent,
                      border: Border.all(
                        color: item.isVerified ? Colors.green : cs.onSurfaceVariant,
                        width: 2,
                      ),
                    ),
                    child: item.isVerified
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : null,
                  ),
                ),
                const SizedBox(width: 12),

                // Item details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.brandName,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              item.size,
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurface,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: confidenceColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${(item.confidence * 100).round()}%',
                              style: TextStyle(
                                fontSize: 10,
                                color: confidenceColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Quantity
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Qty: ${item.quantity}',
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Edit button
                IconButton(
                  icon: Icon(Icons.edit, size: 18, color: cs.onSurfaceVariant),
                  onPressed: () => _editItem(index),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(int verifiedCount, int totalItems, double confidence) {
    final cs = Theme.of(context).colorScheme;
    final allVerified = _items.isNotEmpty && verifiedCount == totalItems;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Stats row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  label: 'Confidence',
                  value: '${confidence.round()}%',
                  color: confidence >= 80 ? Colors.green : Colors.orange,
                ),
                _buildStatItem(
                  label: 'Verified',
                  value: '$verifiedCount/$totalItems',
                  color: allVerified ? Colors.green : cs.primary,
                ),
                _buildStatItem(
                  label: 'Total Qty',
                  value: '${_items.fold(0, (sum, item) => sum + item.quantity)}',
                  color: Colors.purple,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onCancel,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: cs.onSurfaceVariant),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _items.isNotEmpty ? _acceptResults : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: allVerified ? Colors.green : cs.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      allVerified ? 'Accept All' : 'Accept (${_items.length} items)',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  void _showDatePicker() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        _date = picked;
      });
    }
  }

  void _showEditItemDialog(int index) {
    final item = _items[index];
    final quantityController = TextEditingController(text: item.quantity.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.brandName,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              item.size,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: quantityController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Quantity',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final newQty = int.tryParse(quantityController.text) ?? item.quantity;
              setState(() {
                _items[index] = item.copyWith(
                  quantity: newQty,
                  isEdited: true,
                  isVerified: true,
                );
              });
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
