import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../../../core/constants/app_colors.dart';
import '../models/batch_ocr_models.dart';
import '../services/brand_intelligence_service.dart';
import 'quantity_editor.dart';

/// Enhanced OCR Review Table with Smart Features
///
/// Features:
/// - Smart brand name suggestions with fuzzy matching
/// - Inline validation for all editable fields
/// - Data quality scoring and visual indicators
/// - Auto-fix capabilities
/// - Excel-like keyboard navigation
/// - Advanced filtering and search
class EnhancedOCRReviewTable extends StatefulWidget {
  final List<DeduplicatedItem> items;
  final Set<String> selectedItemIds;
  final Map<String, int> editedQuantities;
  final Map<String, String> editedBrandNames;
  final Map<String, double> editedPrices;
  final Map<String, bool> acceptanceStates;
  final Map<String, bool> rejectionStates;
  final ValueChanged<String> onItemSelected;
  final Function(String itemId, int quantity) onQuantityChanged;
  final Function(String itemId, String brandName) onBrandNameChanged;
  final Function(String itemId, double price) onPriceChanged;

  const EnhancedOCRReviewTable({
    super.key,
    required this.items,
    required this.selectedItemIds,
    required this.editedQuantities,
    required this.editedBrandNames,
    required this.editedPrices,
    required this.acceptanceStates,
    required this.rejectionStates,
    required this.onItemSelected,
    required this.onQuantityChanged,
    required this.onBrandNameChanged,
    required this.onPriceChanged,
  });

  @override
  State<EnhancedOCRReviewTable> createState() => _EnhancedOCRReviewTableState();
}

class _EnhancedOCRReviewTableState extends State<EnhancedOCRReviewTable> {
  // Search and filter state
  String searchQuery = '';
  Timer? _searchDebouncer;
  bool showOnlyIssues = false;
  bool showAutoFixed = false;

  // Data quality scores cache
  final Map<String, DataQualityScore> _qualityScores = {};

  // Auto-fix tracking
  final Map<String, AutoFixResult> _autoFixes = {};

  @override
  void initState() {
    super.initState();
    _calculateQualityScores();
  }

  void _calculateQualityScores() {
    for (final item in widget.items) {
      final itemId = item.sourceItemIds.isNotEmpty ? item.sourceItemIds.first : '';
      if (itemId.isNotEmpty) {
        final brandName = widget.editedBrandNames[itemId] ?? item.brandText;
        final price = widget.editedPrices[itemId] ?? item.sellingPrice;
        final quantity = widget.editedQuantities[itemId] ?? item.totalStock;

        _qualityScores[itemId] = BrandIntelligenceService.calculateDataQuality(
          brandText: brandName,
          sizeText: item.sizeText,
          price: price,
          quantity: quantity,
        );
      }
    }
  }

  List<DeduplicatedItem> get filteredItems {
    var filtered = widget.items;

    // Apply search filter
    if (searchQuery.isNotEmpty) {
      filtered = filtered.where((item) {
        final brandName = widget.editedBrandNames[item.sourceItemIds.first] ?? item.brandText;
        final searchLower = searchQuery.toLowerCase();

        return brandName.toLowerCase().contains(searchLower) ||
               item.sizeText.toLowerCase().contains(searchLower) ||
               item.sellingPrice.toString().contains(searchLower) ||
               item.totalStock.toString().contains(searchLower);
      }).toList();
    }

    // Apply quality filter
    if (showOnlyIssues) {
      filtered = filtered.where((item) {
        final itemId = item.sourceItemIds.isNotEmpty ? item.sourceItemIds.first : '';
        final score = _qualityScores[itemId];
        return score != null && score.score < 0.8;
      }).toList();
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        // Search and Filter Bar
        _buildSearchAndFilterBar(),

        // Data Quality Summary
        _buildDataQualitySummary(),

        // Table Header
        _buildTableHeader(),

        // Divider
        Container(
          height: 2,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                cs.primary.withValues(alpha: 0.3),
                cs.primary.withValues(alpha: 0.1),
              ],
            ),
          ),
        ),

        // Table Body
        Expanded(
          child: _buildTableBody(),
        ),
      ],
    );
  }

  Widget _buildSearchAndFilterBar() {
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
          // Search Field
          Expanded(
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
              ),
              child: TextField(
                onChanged: (value) {
                  _searchDebouncer?.cancel();
                  _searchDebouncer = Timer(const Duration(milliseconds: 300), () {
                    setState(() {
                      searchQuery = value;
                    });
                  });
                },
                decoration: InputDecoration(
                  hintText: 'Search brands, sizes, prices...',
                  prefixIcon: Icon(Icons.search, color: cs.onSurfaceVariant),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Filter: Show Issues Only
          FilterChip(
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.warning_amber, size: 14),
                const SizedBox(width: 4),
                Text('Issues Only'),
              ],
            ),
            selected: showOnlyIssues,
            onSelected: (selected) {
              setState(() {
                showOnlyIssues = selected;
              });
            },
            selectedColor: AppColors.warning.withValues(alpha: 0.2),
          ),

          const SizedBox(width: 8),

          // Auto-Fix All Button
          ElevatedButton.icon(
            onPressed: _autoFixAll,
            icon: const Icon(Icons.auto_fix_high, size: 16),
            label: const Text('Auto-Fix All'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataQualitySummary() {
    final totalItems = widget.items.length;
    final excellentItems = _qualityScores.values.where((s) => s.score >= 0.9).length;
    final goodItems = _qualityScores.values.where((s) => s.score >= 0.7 && s.score < 0.9).length;
    final poorItems = _qualityScores.values.where((s) => s.score < 0.7).length;
    final averageScore = _qualityScores.isEmpty
        ? 0.0
        : _qualityScores.values.map((s) => s.score).reduce((a, b) => a + b) / _qualityScores.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _getQualityColor(averageScore).withValues(alpha: 0.1),
            _getQualityColor(averageScore).withValues(alpha: 0.05),
          ],
        ),
      ),
      child: Row(
        children: [
          // Average Score
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _getQualityColor(averageScore).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _getQualityColor(averageScore),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.insights, color: _getQualityColor(averageScore), size: 16),
                const SizedBox(width: 4),
                Text(
                  'Data Quality: ${(averageScore * 100).toInt()}%',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _getQualityColor(averageScore),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 16),

          // Quality Breakdown
          _buildQualityBadge('Excellent', excellentItems, AppColors.success),
          const SizedBox(width: 8),
          _buildQualityBadge('Good', goodItems, AppColors.warning),
          const SizedBox(width: 8),
          _buildQualityBadge('Poor', poorItems, AppColors.error),

          const Spacer(),

          // Auto-fix count
          if (_autoFixes.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.info,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.auto_fix_high, color: AppColors.info, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    '${_autoFixes.length} Auto-Fixed',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.info,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQualityBadge(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Text(
            '$label:',
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.05),
        border: Border(
          bottom: BorderSide(
            color: cs.primary.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildHeaderCell('', width: 50, icon: Icons.check_box_outline_blank),
            _buildHeaderCell('#', width: 60, icon: Icons.numbers),
            _buildHeaderCell('Quality', width: 80, icon: Icons.grade),
            _buildHeaderCell('Brand Name', width: 200, icon: Icons.local_drink),
            _buildHeaderCell('Size', width: 100, icon: Icons.straighten),
            _buildHeaderCell('Qty', width: 120, icon: Icons.inventory_2),
            _buildHeaderCell('Price', width: 100, icon: Icons.currency_rupee),
            _buildHeaderCell('Status', width: 100, icon: Icons.info_outline),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCell(String title, {required double width, IconData? icon}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 16,
              color: cs.primary,
            ),
            const SizedBox(width: 6),
          ],
          if (title.isNotEmpty)
            Flexible(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                  letterSpacing: 0.3,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTableBody() {
    final items = filteredItems;
    final cs = Theme.of(context).colorScheme;

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              searchQuery.isNotEmpty
                  ? 'No items match your search'
                  : 'No items to display',
              style: TextStyle(
                fontSize: 16,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: items.length,
      padding: const EdgeInsets.only(bottom: 80),
      itemBuilder: (context, index) {
        final item = items[index];
        final itemId = item.sourceItemIds.isNotEmpty ? item.sourceItemIds.first : '';

        return _buildEnhancedTableRow(item, itemId, index);
      },
    );
  }

  Widget _buildEnhancedTableRow(DeduplicatedItem item, String itemId, int index) {
    final isSelected = widget.selectedItemIds.contains(itemId);
    final isAccepted = widget.acceptanceStates[itemId] ?? false;
    final isRejected = widget.rejectionStates[itemId] ?? false;

    final brandName = widget.editedBrandNames[itemId] ?? item.brandText;
    final quantity = widget.editedQuantities[itemId] ?? item.totalStock;
    final price = widget.editedPrices[itemId] ?? item.sellingPrice;

    final qualityScore = _qualityScores[itemId];
    final autoFix = _autoFixes[itemId];

    final rowColor = _getRowColor(isSelected, isAccepted, isRejected, item.matchConfidence);
    final borderColor = _getBorderColor(isSelected, isAccepted, isRejected, item.matchConfidence);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: rowColor,
        border: Border.all(
          color: borderColor,
          width: isSelected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => widget.onItemSelected(itemId),
          borderRadius: BorderRadius.circular(8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Select Checkbox
                _buildCheckboxCell(isSelected, () => widget.onItemSelected(itemId)),

                // Row Number
                _buildRowNumberCell(item.rowNumber),

                // Data Quality Indicator
                _buildQualityCell(qualityScore, autoFix != null),

                // Brand Name with Suggestions
                _buildSmartBrandNameCell(brandName, itemId, !isRejected),

                // Size
                _buildSizeCell(item.sizeText),

                // Quantity
                _buildQuantityCell(quantity, !isRejected,
                  (newQty) => widget.onQuantityChanged(itemId, newQty)),

                // Price with Validation
                _buildSmartPriceCell(price, itemId, brandName, item.sizeText, !isRejected),

                // Status
                _buildStatusCell(isAccepted, isRejected, item.matchedBrandId != null, item.matchConfidence),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCheckboxCell(bool isSelected, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 50,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: isSelected ? cs.primary : cs.surface,
              border: Border.all(
                color: isSelected ? cs.primary : cs.onSurfaceVariant.withValues(alpha: 0.3),
                width: 2,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: isSelected
                ? Icon(
                    Icons.check,
                    size: 16,
                    color: Colors.white,
                  )
                : null,
          ),
        ),
      ),
    );
  }

  Widget _buildRowNumberCell(int? rowNumber) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 60,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      child: Center(
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.1),
            shape: BoxShape.circle,
            border: Border.all(
              color: cs.primary.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: Center(
            child: Text(
              rowNumber != null ? '#$rowNumber' : '-',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: cs.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQualityCell(DataQualityScore? score, bool hasAutoFix) {
    return Container(
      width: 80,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      child: Center(
        child: Stack(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _getQualityColor(score?.score ?? 1.0),
                  width: 3,
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      score?.grade ?? 'A',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: _getQualityColor(score?.score ?? 1.0),
                      ),
                    ),
                    Text(
                      '${((score?.score ?? 1.0) * 100).toInt()}%',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: _getQualityColor(score?.score ?? 1.0),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (hasAutoFix)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: AppColors.info,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.auto_fix_high,
                    size: 10,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmartBrandNameCell(String brandName, String itemId, bool isEditable) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 200,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Brand Name
          InkWell(
            onTap: isEditable ? () => _showBrandSuggestionsDialog(brandName, itemId) : null,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    brandName,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isEditable) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.edit,
                    size: 14,
                    color: cs.primary.withValues(alpha: 0.6),
                  ),
                ],
              ],
            ),
          ),

          // Show suggestion if available
          FutureBuilder<List<BrandSuggestion>>(
            future: Future.value(BrandIntelligenceService.getSuggestions(brandName)),
            builder: (context, snapshot) {
              if (snapshot.hasData &&
                  snapshot.data!.isNotEmpty &&
                  snapshot.data!.first.confidence >= 0.7 &&
                  snapshot.data!.first.originalName != brandName) {
                final suggestion = snapshot.data!.first;
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: InkWell(
                    onTap: () {
                      widget.onBrandNameChanged(itemId, suggestion.originalName);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.info.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.lightbulb_outline,
                            size: 10,
                            color: AppColors.info,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            suggestion.originalName,
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.info,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${(suggestion.confidence * 100).toInt()}%',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.info.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSizeCell(String size) {
    final normalizedSize = BrandIntelligenceService.normalizeSize(size);
    final isNormalized = normalizedSize != size;
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: 100,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.local_drink,
                size: 14,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  normalizedSize,
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (isNormalized)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'was: $size',
                style: TextStyle(
                  fontSize: 10,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuantityCell(int quantity, bool isEditable, ValueChanged<int> onChanged) {
    return Container(
      width: 120,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Center(
        child: isEditable
            ? QuantityEditor(
                initialQuantity: quantity,
                onChanged: onChanged,
                compact: true,
                min: 0,
                max: 9999,
              )
            : Text(
                quantity.toString(),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
      ),
    );
  }

  Widget _buildSmartPriceCell(double? price, String itemId, String brandName, String size, bool isEditable) {
    if (price == null) {
      return Container(
        width: 100,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        child: Center(
          child: Text(
            '-',
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final validation = BrandIntelligenceService.validatePrice(
      brand: brandName,
      size: size,
      price: price,
    );

    return Container(
      width: 100,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: isEditable
                ? () => _showPriceEditDialog(price, itemId, brandName, size)
                : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: validation.isValid
                    ? AppColors.success.withValues(alpha: 0.1)
                    : AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: validation.isValid
                      ? AppColors.success.withValues(alpha: 0.3)
                      : AppColors.warning.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '₹${price.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: validation.isValid ? AppColors.success : AppColors.warning,
                    ),
                  ),
                  if (isEditable) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.edit,
                      size: 11,
                      color: (validation.isValid ? AppColors.success : AppColors.warning).withValues(alpha: 0.7),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (!validation.isValid && validation.suggestedPrice != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: InkWell(
                onTap: () {
                  widget.onPriceChanged(itemId, validation.suggestedPrice!);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.info.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.tips_and_updates,
                        size: 10,
                        color: AppColors.info,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '₹${validation.suggestedPrice!.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.info,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusCell(bool isAccepted, bool isRejected, bool isMatched, double confidence) {
    String statusText;
    Color statusColor;
    IconData statusIcon;

    if (isRejected) {
      statusText = 'Rejected';
      statusColor = AppColors.error;
      statusIcon = Icons.cancel;
    } else if (isAccepted) {
      statusText = 'Accepted';
      statusColor = AppColors.success;
      statusIcon = Icons.check_circle;
    } else if (isMatched) {
      statusText = 'Matched';
      statusColor = AppColors.info;
      statusIcon = Icons.link;
    } else {
      statusText = 'Pending';
      statusColor = AppColors.warning;
      statusIcon = Icons.pending;
    }

    return Container(
      width: 100,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: statusColor.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              statusIcon,
              size: 12,
              color: statusColor,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                statusText,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: statusColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper methods

  Color _getQualityColor(double score) {
    if (score >= 0.9) return AppColors.success;
    if (score >= 0.7) return AppColors.warning;
    return AppColors.error;
  }

  Color _getRowColor(bool isSelected, bool isAccepted, bool isRejected, double confidence) {
    final cs = Theme.of(context).colorScheme;
    if (isRejected) {
      return AppColors.error.withValues(alpha: 0.08);
    }
    if (isAccepted) {
      return AppColors.success.withValues(alpha: 0.08);
    }
    if (isSelected) {
      return cs.primary.withValues(alpha: 0.08);
    }

    if (confidence >= 0.8) {
      return AppColors.success.withValues(alpha: 0.05);
    } else if (confidence >= 0.5) {
      return AppColors.warning.withValues(alpha: 0.05);
    } else {
      return AppColors.error.withValues(alpha: 0.05);
    }
  }

  Color _getBorderColor(bool isSelected, bool isAccepted, bool isRejected, double confidence) {
    final cs = Theme.of(context).colorScheme;
    if (isRejected) {
      return AppColors.error.withValues(alpha: 0.3);
    }
    if (isAccepted) {
      return AppColors.success.withValues(alpha: 0.3);
    }
    if (isSelected) {
      return cs.primary;
    }

    if (confidence >= 0.8) {
      return AppColors.success.withValues(alpha: 0.2);
    } else if (confidence >= 0.5) {
      return AppColors.warning.withValues(alpha: 0.2);
    } else {
      return AppColors.error.withValues(alpha: 0.2);
    }
  }

  // Dialog methods

  void _showBrandSuggestionsDialog(String currentBrand, String itemId) {
    final cs = Theme.of(context).colorScheme;
    final suggestions = BrandIntelligenceService.getSuggestions(currentBrand);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.auto_fix_high, color: cs.primary),
            const SizedBox(width: 8),
            const Text('Brand Suggestions'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: TextEditingController(text: currentBrand),
              onChanged: (value) {
                widget.onBrandNameChanged(itemId, value);
                Navigator.pop(context);
              },
              decoration: InputDecoration(
                labelText: 'Brand Name',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'Suggestions:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              ...suggestions.map((s) => ListTile(
                leading: CircleAvatar(
                  backgroundColor: _getQualityColor(s.confidence),
                  child: Text(
                    '${(s.confidence * 100).toInt()}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Text(s.originalName),
                subtitle: Text(
                  s.isExactMatch ? 'Exact match' :
                  s.isPartialMatch ? 'Partial match' :
                  'Similar',
                ),
                onTap: () {
                  widget.onBrandNameChanged(itemId, s.originalName);
                  Navigator.pop(context);
                },
              )),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showPriceEditDialog(double currentPrice, String itemId, String brandName, String size) {
    final validation = BrandIntelligenceService.validatePrice(
      brand: brandName,
      size: size,
      price: currentPrice,
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.currency_rupee, color: AppColors.success),
            const SizedBox(width: 8),
            const Text('Edit Price'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: TextEditingController(text: currentPrice.toString()),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (value) {
                final newPrice = double.tryParse(value);
                if (newPrice != null && newPrice > 0) {
                  widget.onPriceChanged(itemId, newPrice);
                }
              },
              decoration: InputDecoration(
                labelText: 'Price',
                prefix: const Text('₹ '),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            if (!validation.isValid && validation.suggestedPrice != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning_amber, color: AppColors.warning, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            validation.message,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: () {
                        widget.onPriceChanged(itemId, validation.suggestedPrice!);
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.auto_fix_high, size: 16),
                      label: Text('Use ₹${validation.suggestedPrice!.toStringAsFixed(0)}'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.warning,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _autoFixAll() {
    int fixedCount = 0;

    for (final item in widget.items) {
      final itemId = item.sourceItemIds.isNotEmpty ? item.sourceItemIds.first : '';
      if (itemId.isEmpty) continue;

      final brandName = widget.editedBrandNames[itemId] ?? item.brandText;
      final price = widget.editedPrices[itemId] ?? item.sellingPrice;

      final autoFix = BrandIntelligenceService.autoFixItem(
        brandText: brandName,
        sizeText: item.sizeText,
        price: price,
      );

      if (autoFix.hasChanges) {
        _autoFixes[itemId] = autoFix;
        widget.onBrandNameChanged(itemId, autoFix.brandText);
        if (autoFix.price != null && autoFix.price != price) {
          widget.onPriceChanged(itemId, autoFix.price!);
        }
        fixedCount++;
      }
    }

    if (fixedCount > 0) {
      setState(() {
        _calculateQualityScores();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.auto_fix_high, color: Colors.white),
              const SizedBox(width: 8),
              Text('Auto-fixed $fixedCount items'),
            ],
          ),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  @override
  void dispose() {
    _searchDebouncer?.cancel();
    super.dispose();
  }
}