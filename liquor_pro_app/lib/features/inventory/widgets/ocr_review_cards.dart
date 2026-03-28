import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../models/batch_ocr_models.dart';

/// Card-based review widget for OCR items
/// Mobile-friendly, no horizontal scrolling
class OCRReviewCards extends StatefulWidget {
  final List<DeduplicatedItem> items;
  final Set<String> selectedItemIds;
  final Map<String, int> editedQuantities;
  final Map<String, String> editedBrandNames;
  final Map<String, double> editedPrices;
  final Map<String, bool> acceptanceStates;
  final Map<String, bool> rejectionStates;
  final String? receiptType; // Add receipt type from parent
  final Function(String itemId) onItemSelected;
  final Function(String itemId, int quantity) onQuantityChanged;
  final Function(String itemId, String brandName) onBrandNameChanged;
  final Function(String itemId, double price) onPriceChanged;

  const OCRReviewCards({
    super.key,
    required this.items,
    required this.selectedItemIds,
    required this.editedQuantities,
    required this.editedBrandNames,
    required this.editedPrices,
    required this.acceptanceStates,
    required this.rejectionStates,
    this.receiptType,
    required this.onItemSelected,
    required this.onQuantityChanged,
    required this.onBrandNameChanged,
    required this.onPriceChanged,
  });

  @override
  State<OCRReviewCards> createState() => _OCRReviewCardsState();
}

class _OCRReviewCardsState extends State<OCRReviewCards> {
  String _searchQuery = '';
  bool _showOnlyIssues = false;

  @override
  Widget build(BuildContext context) {
    final filteredItems = _getFilteredItems();

    return Column(
      children: [
        // Search and Filter Bar
        _buildSearchBar(),
        // Items Count
        _buildItemsCount(filteredItems),
        // Cards List
        Expanded(
          child: _buildCardsList(filteredItems),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: cs.outline,
                  width: 1,
                ),
              ),
              child: TextField(
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value.toLowerCase();
                  });
                },
                decoration: InputDecoration(
                  hintText: 'Search brands...',
                  hintStyle: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 14,
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    color: cs.onSurfaceVariant,
                    size: 20,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Filter Toggle
          Container(
            decoration: BoxDecoration(
              color: _showOnlyIssues ? AppColors.warning : cs.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _showOnlyIssues ? AppColors.warning : cs.outline,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  setState(() {
                    _showOnlyIssues = !_showOnlyIssues;
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: _showOnlyIssues ? Colors.white : AppColors.warning,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Issues',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _showOnlyIssues ? Colors.white : cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsCount(List<DeduplicatedItem> items) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: cs.surfaceContainerHighest,
      child: Row(
        children: [
          Text(
            '${items.length} items',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          if (_showOnlyIssues)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Showing items with issues',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.warning,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCardsList(List<DeduplicatedItem> items) {
    final cs = Theme.of(context).colorScheme;
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 48,
              color: cs.onSurfaceVariant.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              _showOnlyIssues ? 'No items with issues' : 'No items found',
              style: TextStyle(
                fontSize: 16,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    // Group items by size within receipt
    final groupedItems = _groupItemsByReceipt(items);

    // Build a flat list with headers and items
    final List<Widget> listItems = [];

    // Add receipt type header if available
    if (groupedItems.isNotEmpty && groupedItems.first['receiptType'] != null) {
      listItems.add(_buildReceiptHeader(groupedItems.first['receiptType']));
    }

    // Add size groups with their items
    for (int i = 0; i < groupedItems.length; i++) {
      final group = groupedItems[i];
      final sizeGroup = group['sizeGroup'] as String;
      final sizeItems = group['items'] as List<DeduplicatedItem>;
      final itemCount = group['itemCount'] as int;

      // Add size header
      listItems.add(_buildSizeHeader(sizeGroup, itemCount));

      // Add items for this size group
      for (final item in sizeItems) {
        listItems.add(_buildItemCard(item));
      }

      // Add spacing between size groups
      if (i < groupedItems.length - 1) {
        listItems.add(const SizedBox(height: 8));
      }
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 80),
      children: listItems,
    );
  }

  Widget _buildGroupHeader(String? receiptType, int groupNumber) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      color: cs.primary.withValues(alpha: 0.05),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              Icons.receipt,
              size: 16,
              color: cs.primary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            receiptType ?? 'Receipt $groupNumber',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: cs.primary,
            ),
          ),
        ],
      ),
    );
  }

  // Build receipt type header (main header for all items)
  Widget _buildReceiptHeader(String receiptType) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cs.primary,
            cs.primary.withValues(alpha: 0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.receipt_long,
              size: 20,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              receiptType,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Build size group header
  Widget _buildSizeHeader(String sizeGroup, int itemCount) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 8, 0, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        border: Border(
          left: BorderSide(
            color: cs.primary.withValues(alpha: 0.7),
            width: 4,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: cs.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              sizeGroup.toUpperCase(),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: cs.primary,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$itemCount items',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemCard(DeduplicatedItem item) {
    final cs = Theme.of(context).colorScheme;
    final itemId = item.sourceItemIds.isNotEmpty ? item.sourceItemIds.first : '';
    final isSelected = widget.selectedItemIds.contains(itemId);
    final isAccepted = widget.acceptanceStates[itemId] ?? false;
    final isRejected = widget.rejectionStates[itemId] ?? false;

    // Show exact OCR text - no modifications
    final originalOCRText = item.brandText; // This is the exact text from OCR
    final editedBrandName = widget.editedBrandNames[itemId] ?? originalOCRText;
    final editedQuantity = widget.editedQuantities[itemId] ?? item.totalStock;
    final editedPrice = widget.editedPrices[itemId] ?? item.sellingPrice;

    final hasIssues = _itemHasIssues(item);
    final qualityGrade = _calculateQualityGrade(item);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? cs.primary
              : (hasIssues ? AppColors.warning.withValues(alpha: 0.4) : cs.outline.withValues(alpha: 0.5)),
          width: isSelected ? 2.5 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: isSelected
              ? cs.primary.withValues(alpha: 0.15)
              : Colors.black.withValues(alpha: 0.06),
            blurRadius: isSelected ? 12 : 8,
            offset: Offset(0, isSelected ? 6 : 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => widget.onItemSelected(itemId),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              // Top Row: Checkbox, Serial Number, Quality Grade
              Row(
                children: [
                  // Animated Checkbox
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected ? cs.primary : cs.outline.withValues(alpha: 0.5),
                        width: 2.5,
                      ),
                      gradient: isSelected
                        ? LinearGradient(
                            colors: [cs.primary, cs.primary.withValues(alpha: 0.8)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                      color: isSelected ? null : cs.surface,
                      boxShadow: isSelected ? [
                        BoxShadow(
                          color: cs.primary.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ] : null,
                    ),
                    child: isSelected
                        ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  // Serial Number Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          cs.primary.withValues(alpha: 0.12),
                          cs.primary.withValues(alpha: 0.08),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: cs.primary.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Text(
                      '#${item.rowNumber ?? '?'}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: cs.primary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Quality Grade
                  _buildQualityBadge(qualityGrade),
                  const SizedBox(width: 8),
                  // Status Badge
                  _buildStatusBadge(isAccepted, isRejected),
                ],
              ),
              const SizedBox(height: 12),

              // Brand Name Row
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.liquor_rounded,
                              size: 14,
                              color: cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Brand',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurfaceVariant,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => _editBrandName(item, itemId),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: cs.outline.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          editedBrandName,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: cs.onSurface,
                                            letterSpacing: 0.2,
                                          ),
                                        ),
                                        // Show original OCR text if edited
                                        if (editedBrandName != originalOCRText)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Text(
                                              'OCR: "$originalOCRText"',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontStyle: FontStyle.italic,
                                                color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.edit_rounded,
                                    size: 16,
                                    color: cs.primary.withValues(alpha: 0.7),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Size Badge
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.straighten_rounded,
                            size: 14,
                            color: cs.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Size',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurfaceVariant,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              cs.primary.withValues(alpha: 0.15),
                              cs.primary.withValues(alpha: 0.1),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: cs.primary.withValues(alpha: 0.3),
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          item.sizeText,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: cs.primary,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Category and Subcategory Row (if available from OCR)
              if (item.inferredCategoryName != null ||
                  item.inferredSubcategoryName != null) ...[
                Row(
                  children: [
                    // Category with confidence badge
                    if (item.inferredCategoryName != null)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.category_rounded,
                                  size: 14,
                                  color: cs.onSurfaceVariant,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Category',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: cs.onSurfaceVariant,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Text(
                                  item.inferredCategoryName!,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: cs.onSurface,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                                if (item.categoryConfidence != null) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _getConfidenceColor(
                                        item.categoryConfidence,
                                      ).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: _getConfidenceColor(
                                          item.categoryConfidence,
                                        ).withValues(alpha: 0.3),
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      '${item.categoryConfidence!.toInt()}%',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: _getConfidenceColor(
                                          item.categoryConfidence,
                                        ),
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    // Subcategory (if available)
                    if (item.inferredSubcategoryName != null) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.label_rounded,
                                  size: 14,
                                  color: cs.onSurfaceVariant,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Subcategory',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: cs.onSurfaceVariant,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              item.inferredSubcategoryName!,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
              ],

              // Quantity and Price Row
              Row(
                children: [
                  // Quantity
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.inventory_2_rounded,
                              size: 14,
                              color: cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Quantity',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurfaceVariant,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => _editQuantity(item, itemId),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: editedQuantity == 0
                                  ? AppColors.error.withValues(alpha: 0.08)
                                  : AppColors.success.withValues(alpha: 0.08),
                                border: Border.all(
                                  color: editedQuantity == 0
                                      ? AppColors.error.withValues(alpha: 0.3)
                                      : AppColors.success.withValues(alpha: 0.3),
                                  width: 1.5,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    editedQuantity.toString(),
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      color: editedQuantity == 0
                                          ? AppColors.error
                                          : AppColors.success,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const Spacer(),
                                  Icon(
                                    Icons.edit_rounded,
                                    size: 16,
                                    color: editedQuantity == 0
                                        ? AppColors.error
                                        : AppColors.success,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Price
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.currency_rupee_rounded,
                              size: 14,
                              color: cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Price',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurfaceVariant,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => _editPrice(item, itemId),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: editedPrice == null
                                    ? AppColors.warning.withValues(alpha: 0.08)
                                    : cs.primary.withValues(alpha: 0.08),
                                border: Border.all(
                                  color: editedPrice == null
                                      ? AppColors.warning.withValues(alpha: 0.3)
                                      : cs.primary.withValues(alpha: 0.3),
                                  width: 1.5,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    editedPrice != null
                                        ? '\u20B9${editedPrice.toStringAsFixed(0)}'
                                        : 'Set price',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      color: editedPrice == null
                                          ? AppColors.warning
                                          : cs.primary,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                  const Spacer(),
                                  Icon(
                                    Icons.edit_rounded,
                                    size: 16,
                                    color: editedPrice == null
                                        ? AppColors.warning
                                        : cs.primary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Match Confidence (if matched)
              if (item.matchedBrandId != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getConfidenceColor(item.matchConfidence).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.link,
                        size: 14,
                        color: _getConfidenceColor(item.matchConfidence),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Matched ${item.matchConfidence.toStringAsFixed(0) ?? 0}%',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _getConfidenceColor(item.matchConfidence),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildQualityBadge(String grade) {
    final cs = Theme.of(context).colorScheme;
    Color gradeColor;
    switch (grade) {
      case 'A':
        gradeColor = AppColors.success;
        break;
      case 'B':
        gradeColor = AppColors.success.withValues(alpha: 0.7);
        break;
      case 'C':
        gradeColor = AppColors.warning;
        break;
      case 'D':
        gradeColor = AppColors.warning.withValues(alpha: 0.8);
        break;
      case 'F':
        gradeColor = AppColors.error;
        break;
      default:
        gradeColor = cs.onSurfaceVariant;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: gradeColor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: gradeColor.withValues(alpha: 0.5),
        ),
      ),
      child: Text(
        grade,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: gradeColor,
        ),
      ),
    );
  }

  Widget _buildStatusBadge(bool isAccepted, bool isRejected) {
    if (isAccepted) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 12, color: AppColors.success),
            const SizedBox(width: 2),
            Text(
              'Accepted',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.success,
              ),
            ),
          ],
        ),
      );
    } else if (isRejected) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cancel, size: 12, color: AppColors.error),
            const SizedBox(width: 2),
            Text(
              'Rejected',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.error,
              ),
            ),
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.pending, size: 12, color: AppColors.warning),
            const SizedBox(width: 2),
            Text(
              'Pending',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.warning,
              ),
            ),
          ],
        ),
      );
    }
  }

  Color _getConfidenceColor(double? confidence, [Color? fallback]) {
    if (confidence == null) return fallback ?? Theme.of(context).colorScheme.onSurfaceVariant;
    if (confidence >= 90) return AppColors.success;
    if (confidence >= 70) return AppColors.warning;
    return AppColors.error;
  }

  List<DeduplicatedItem> _getFilteredItems() {
    var items = widget.items;

    // Search filter
    if (_searchQuery.isNotEmpty) {
      items = items.where((item) {
        final brandName = widget.editedBrandNames[
          item.sourceItemIds.isNotEmpty ? item.sourceItemIds.first : ''
        ] ?? item.brandText;
        return brandName.toLowerCase().contains(_searchQuery);
      }).toList();
    }

    // Issues filter
    if (_showOnlyIssues) {
      items = items.where((item) => _itemHasIssues(item)).toList();
    }

    return items;
  }

  bool _itemHasIssues(DeduplicatedItem item) {
    final itemId = item.sourceItemIds.isNotEmpty ? item.sourceItemIds.first : '';
    final editedPrice = widget.editedPrices[itemId] ?? item.sellingPrice;

    return editedPrice == null ||
           item.totalStock == 0 ||
           item.brandText.isEmpty ||
           item.brandText.length < 3;
  }

  String _calculateQualityGrade(DeduplicatedItem item) {
    final itemId = item.sourceItemIds.isNotEmpty ? item.sourceItemIds.first : '';
    final editedPrice = widget.editedPrices[itemId] ?? item.sellingPrice;

    int score = 100;

    // Deduct for missing price
    if (editedPrice == null) score -= 30;

    // Deduct for zero stock
    if (item.totalStock == 0) score -= 20;

    // Deduct for short brand name
    if (item.brandText.length < 3) score -= 20;

    // Deduct for no match
    if (item.matchedBrandId == null) score -= 10;

    // Grade calculation
    if (score >= 90) return 'A';
    if (score >= 80) return 'B';
    if (score >= 70) return 'C';
    if (score >= 60) return 'D';
    return 'F';
  }

  List<Map<String, dynamic>> _groupItemsByReceipt(List<DeduplicatedItem> items) {
    // Sort items by row number first
    final sortedItems = List<DeduplicatedItem>.from(items)
      ..sort((a, b) => (a.rowNumber ?? 0).compareTo(b.rowNumber ?? 0));

    // Group items by size within the receipt
    final Map<String, List<DeduplicatedItem>> sizeGroups = {};

    for (final item in sortedItems) {
      // Extract size and normalize it for grouping
      String sizeKey = _normalizeSizeForGrouping(item.sizeText);

      if (!sizeGroups.containsKey(sizeKey)) {
        sizeGroups[sizeKey] = [];
      }
      sizeGroups[sizeKey]!.add(item);
    }

    // Convert to list format with size groups
    final List<Map<String, dynamic>> result = [];

    // Use the receipt type from parent if available
    final receiptType = widget.receiptType ?? _inferReceiptType(items);

    // Sort size keys to show smaller sizes first
    final sortedSizeKeys = sizeGroups.keys.toList()
      ..sort((a, b) {
        // Extract numeric value from size for sorting
        final aNum = _extractNumericFromSize(a);
        final bNum = _extractNumericFromSize(b);
        return aNum.compareTo(bNum);
      });

    for (final sizeKey in sortedSizeKeys) {
      final sizeItems = sizeGroups[sizeKey]!;
      // Sort items within size group by row number
      sizeItems.sort((a, b) => (a.rowNumber ?? 0).compareTo(b.rowNumber ?? 0));

      result.add({
        'receiptType': receiptType,
        'sizeGroup': sizeKey,
        'items': sizeItems,
        'itemCount': sizeItems.length,
      });
    }

    return result;
  }

  // Helper method to normalize size text for grouping
  String _normalizeSizeForGrouping(String sizeText) {
    final lower = sizeText.toLowerCase().trim();
    // Remove 'ml' or 'm.l' or 'ml.' and standardize
    final normalized = lower
        .replaceAll(RegExp(r'm\.?l\.?'), '')
        .replaceAll(RegExp(r'\s+'), '')
        .trim();

    // Return with ML suffix for display
    if (normalized.isNotEmpty) {
      return '$normalized ML';
    }
    return 'Unknown Size';
  }

  // Helper method to extract numeric value from size
  int _extractNumericFromSize(String size) {
    final match = RegExp(r'(\d+)').firstMatch(size);
    if (match != null) {
      return int.tryParse(match.group(1)!) ?? 0;
    }
    return 0;
  }

  // Helper method to infer receipt type if not provided
  String _inferReceiptType(List<DeduplicatedItem> items) {
    if (items.isEmpty) return 'Receipt';

    final sizes = items.map((e) => e.sizeText.toLowerCase()).toSet();
    if (sizes.every((s) => s.contains('90'))) {
      return 'SALE RECEIPT - 90 ML';
    } else if (sizes.every((s) => s.contains('180'))) {
      return 'SALE RECEIPT - 180 ML';
    } else if (sizes.length > 1) {
      return 'SALE RECEIPT - MIXED';
    }
    return 'SALE RECEIPT';
  }

  void _editBrandName(DeduplicatedItem item, String itemId) {
    final cs = Theme.of(context).colorScheme;
    final currentName = widget.editedBrandNames[itemId] ?? item.brandText;
    final controller = TextEditingController(text: currentName);

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 0,
        backgroundColor: cs.surface,
        contentPadding: EdgeInsets.zero,
        content: Container(
          width: double.maxFinite,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              colors: [
                cs.surface,
                cs.primary.withValues(alpha: 0.02),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      cs.primary,
                      cs.primary.withValues(alpha: 0.85),
                    ],
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.edit_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Text(
                        'Edit Brand Name',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Content
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Original: ${item.brandText}',
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Brand Name',
                        hintText: 'Enter corrected brand name',
                        prefixIcon: Icon(Icons.liquor_rounded, color: cs.primary),
                        filled: true,
                        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: cs.outline),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.3)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: cs.primary, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Actions
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: cs.outline.withValues(alpha: 0.3)),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          widget.onBrandNameChanged(itemId, controller.text.trim());
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.check_rounded, size: 20),
                        label: const Text(
                          'Save Changes',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _editQuantity(DeduplicatedItem item, String itemId) {
    final cs = Theme.of(context).colorScheme;
    final currentQuantity = widget.editedQuantities[itemId] ?? item.totalStock;
    final controller = TextEditingController(text: currentQuantity.toString());

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 0,
        backgroundColor: cs.surface,
        contentPadding: EdgeInsets.zero,
        content: Container(
          width: double.maxFinite,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              colors: [
                cs.surface,
                AppColors.success.withValues(alpha: 0.02),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.success,
                      AppColors.success.withValues(alpha: 0.85),
                    ],
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.inventory_2_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Text(
                        'Edit Quantity',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Content
              Padding(
                padding: const EdgeInsets.all(24),
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    labelText: 'Quantity',
                    hintText: '0',
                    prefixIcon: Icon(Icons.inventory_2_rounded, color: AppColors.success),
                    filled: true,
                    fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: cs.outline),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.success, width: 2),
                    ),
                  ),
                ),
              ),
              // Actions
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: cs.outline.withValues(alpha: 0.3)),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          final quantity = int.tryParse(controller.text) ?? 0;
                          widget.onQuantityChanged(itemId, quantity);
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.check_rounded, size: 20),
                        label: const Text(
                          'Save Changes',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _editPrice(DeduplicatedItem item, String itemId) {
    final cs = Theme.of(context).colorScheme;
    final currentPrice = widget.editedPrices[itemId] ?? item.sellingPrice;
    final controller = TextEditingController(
      text: currentPrice?.toStringAsFixed(0) ?? '',
    );

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 0,
        backgroundColor: cs.surface,
        contentPadding: EdgeInsets.zero,
        content: Container(
          width: double.maxFinite,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              colors: [
                cs.surface,
                AppColors.success.withValues(alpha: 0.02),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.success,
                      AppColors.success.withValues(alpha: 0.85),
                    ],
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.currency_rupee_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Text(
                        'Edit Selling Price',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Content
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (item.sellingPrice != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Original: \u20B9${item.sellingPrice!.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Selling Price',
                        hintText: '0.00',
                        prefixIcon: Icon(Icons.currency_rupee_rounded, color: AppColors.success),
                        prefixText: '\u20B9 ',
                        prefixStyle: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppColors.success,
                        ),
                        filled: true,
                        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: cs.outline),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.3)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppColors.success, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Actions
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: cs.outline.withValues(alpha: 0.3)),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          final price = double.tryParse(controller.text);
                          if (price != null && price > 0) {
                            widget.onPriceChanged(itemId, price);
                            Navigator.pop(context);
                          } else {
                            // Show error
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('Please enter a valid price'),
                                backgroundColor: AppColors.error,
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.check_rounded, size: 20),
                        label: const Text(
                          'Save Changes',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
