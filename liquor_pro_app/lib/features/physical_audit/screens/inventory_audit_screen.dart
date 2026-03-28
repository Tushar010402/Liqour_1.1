import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/physical_audit_models.dart';
import '../providers/physical_audit_provider.dart';

/// Inventory Audit Screen - Physical stock verification
class InventoryAuditScreen extends ConsumerStatefulWidget {
  const InventoryAuditScreen({super.key});

  @override
  ConsumerState<InventoryAuditScreen> createState() => _InventoryAuditScreenState();
}

class _InventoryAuditScreenState extends ConsumerState<InventoryAuditScreen> {
  final TextEditingController _searchController = TextEditingController();
  String? _selectedCategory;
  final Map<String, TextEditingController> _countControllers = {};

  @override
  void dispose() {
    _searchController.dispose();
    for (final controller in _countControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeAudit = ref.watch(activeAuditNotifierProvider);
    final shopId = ref.watch(auditShopIdProvider);

    // If no active audit or not an inventory audit, show empty state
    if (!activeAudit.hasSession || !activeAudit.isInventoryAudit) {
      return _buildNoAuditState();
    }

    final inventoryData = activeAudit.inventoryData;

    return Column(
      children: [
        // Summary Bar
        _buildSummaryBar(inventoryData),

        // Search and Filters
        _buildSearchBar(),

        // Items List
        Expanded(
          child: _buildItemsList(shopId, activeAudit),
        ),

        // Bottom Action Bar
        _buildBottomBar(activeAudit),
      ],
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
                color: const Color(0xFF3B82F6).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                CupertinoIcons.cube_box,
                size: 48,
                color: Color(0xFF3B82F6),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Inventory Audit Active',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Start an inventory audit from the Overview tab to begin verification',
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

  Widget _buildSummaryBar(InventoryAuditData? data) {
    final itemsChecked = data?.itemsChecked ?? 0;
    final itemsWithVariance = data?.itemsWithVariance ?? 0;
    final expectedValue = data?.totalExpectedValue ?? 0;
    final actualValue = data?.totalActualValue ?? 0;
    final variance = actualValue - expectedValue;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Expanded(
              child: _buildSummaryItem(
                'Checked',
                itemsChecked.toString(),
                CupertinoIcons.checkmark_circle,
              ),
            ),
            Container(
              width: 1,
              height: 40,
              color: Colors.white.withOpacity(0.3),
            ),
            Expanded(
              child: _buildSummaryItem(
                'Variance',
                itemsWithVariance.toString(),
                CupertinoIcons.exclamationmark_triangle,
                isWarning: itemsWithVariance > 0,
              ),
            ),
            Container(
              width: 1,
              height: 40,
              color: Colors.white.withOpacity(0.3),
            ),
            Expanded(
              child: _buildSummaryItem(
                'Value Diff',
                variance >= 0
                    ? '+₹${variance.toStringAsFixed(0)}'
                    : '-₹${variance.abs().toStringAsFixed(0)}',
                CupertinoIcons.money_dollar,
                isWarning: variance.abs() > 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(
    String label,
    String value,
    IconData icon, {
    bool isWarning = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 18,
          color: isWarning ? Colors.amber[200] : Colors.white.withOpacity(0.8),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: isWarning ? Colors.amber[200] : Colors.white,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withOpacity(0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: CupertinoColors.systemBackground,
      child: Row(
        children: [
          Expanded(
            child: CupertinoSearchTextField(
              controller: _searchController,
              placeholder: 'Search items...',
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 12),
          CupertinoButton(
            padding: EdgeInsets.zero,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: CupertinoColors.systemGrey6,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                CupertinoIcons.barcode_viewfinder,
                size: 22,
              ),
            ),
            onPressed: () => _scanBarcode(),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsList(String? shopId, ActiveAuditState activeAudit) {
    if (shopId == null) {
      return Center(
        child: Text(
          'Please select a shop',
          style: TextStyle(
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
        ),
      );
    }

    final query = InventoryItemsQuery(
      shopId: shopId,
      category: _selectedCategory,
      searchQuery:
          _searchController.text.isEmpty ? null : _searchController.text,
    );

    final itemsAsync = ref.watch(inventoryItemsForAuditProvider(query));
    final checkedItems = activeAudit.inventoryData?.items ?? [];

    return itemsAsync.when(
      data: (items) {
        if (items.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  CupertinoIcons.cube_box,
                  size: 48,
                  color: CupertinoColors.systemGrey,
                ),
                const SizedBox(height: 16),
                Text(
                  'No items found',
                  style: TextStyle(
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            final checkedItem = checkedItems.firstWhere(
              (i) => i.productId == item.productId,
              orElse: () => item,
            );
            return _buildInventoryItemCard(item, checkedItem);
          },
        );
      },
      loading: () => const Center(child: CupertinoActivityIndicator()),
      error: (e, _) => Center(
        child: Text(
          'Error: $e',
          style: const TextStyle(color: CupertinoColors.systemRed),
        ),
      ),
    );
  }

  Widget _buildInventoryItemCard(
    InventoryAuditItem originalItem,
    InventoryAuditItem checkedItem,
  ) {
    final hasVariance = checkedItem.variance != 0;
    final isChecked = checkedItem.actualQuantity != originalItem.expectedQuantity ||
        _countControllers.containsKey(originalItem.productId);

    // Get or create controller
    if (!_countControllers.containsKey(originalItem.productId)) {
      _countControllers[originalItem.productId] = TextEditingController();
    }
    final controller = _countControllers[originalItem.productId]!;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground,
        borderRadius: BorderRadius.circular(12),
        border: hasVariance
            ? Border.all(
                color: checkedItem.variance < 0
                    ? CupertinoColors.systemRed.withValues(alpha: 0.5)
                    : CupertinoColors.systemOrange.withValues(alpha: 0.5),
              )
            : isChecked
                ? Border.all(
                    color: const Color(0xFF10B981).withOpacity(0.5),
                  )
                : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Status indicator
            Container(
              width: 4,
              height: 50,
              decoration: BoxDecoration(
                color: hasVariance
                    ? checkedItem.variance < 0
                        ? CupertinoColors.systemRed
                        : CupertinoColors.systemOrange
                    : isChecked
                        ? const Color(0xFF10B981)
                        : CupertinoColors.systemGrey4,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            // Product Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    originalItem.productName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (originalItem.sku != null) ...[
                        Text(
                          originalItem.sku!,
                          style: TextStyle(
                            fontSize: 12,
                            color: CupertinoColors.secondaryLabel
                                .resolveFrom(context),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: CupertinoColors.systemGrey6,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Expected: ${originalItem.expectedQuantity}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Count Input
            SizedBox(
              width: 80,
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  hintText: '0',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: CupertinoColors.systemGrey4,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: CupertinoColors.systemGrey4,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: Color(0xFF3B82F6),
                      width: 2,
                    ),
                  ),
                ),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                onChanged: (value) {
                  final count = int.tryParse(value) ?? 0;
                  _updateItemCount(originalItem, count);
                },
              ),
            ),
            const SizedBox(width: 8),
            // Variance Badge
            if (hasVariance)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: checkedItem.variance < 0
                      ? CupertinoColors.systemRed.withValues(alpha: 0.1)
                      : CupertinoColors.systemOrange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  checkedItem.variance > 0
                      ? '+${checkedItem.variance}'
                      : '${checkedItem.variance}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: checkedItem.variance < 0
                        ? CupertinoColors.systemRed
                        : CupertinoColors.systemOrange,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(ActiveAuditState state) {
    final isSubmitting = state.isSubmitting;
    final itemsChecked = state.inventoryData?.itemsChecked ?? 0;

    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: 12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$itemsChecked items verified',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Continue counting or submit',
                  style: TextStyle(
                    fontSize: 12,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          ElevatedButton(
            onPressed: isSubmitting || itemsChecked == 0
                ? null
                : _submitInventoryAudit,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6),
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 14,
              ),
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
                    'Submit',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _updateItemCount(InventoryAuditItem item, int actualCount) {
    final updatedItem = InventoryAuditItem(
      productId: item.productId,
      productName: item.productName,
      sku: item.sku,
      expectedQuantity: item.expectedQuantity,
      actualQuantity: actualCount,
      variance: actualCount - item.expectedQuantity,
      unitPrice: item.unitPrice,
    );

    ref.read(activeAuditNotifierProvider.notifier).updateInventoryItem(updatedItem);
  }

  void _scanBarcode() async {
    // Implement barcode scanning
    // For now, show a placeholder
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Barcode scanner - Coming soon')),
    );
  }

  void _submitInventoryAudit() async {
    final success = await ref
        .read(activeAuditNotifierProvider.notifier)
        .submitInventoryAudit();

    if (success && mounted) {
      final activeAudit = ref.read(activeAuditNotifierProvider);

      // Check if this is a combined audit that still needs cash
      if (activeAudit.session?.type == AuditType.combined &&
          activeAudit.cashData == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Inventory audit submitted! Now complete cash audit.'),
            backgroundColor: Color(0xFF3B82F6),
          ),
        );
      } else {
        // Inventory-only or combined complete - prompt to finish
        _showCompleteAuditDialog();
      }
    } else if (mounted) {
      final error = ref.read(activeAuditNotifierProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error ?? 'Failed to submit inventory audit'),
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
            const Text('Inventory verification submitted successfully!'),
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
            child: const Text('Continue Counting'),
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
