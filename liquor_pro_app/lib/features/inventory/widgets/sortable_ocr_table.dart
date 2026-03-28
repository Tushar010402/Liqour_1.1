import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../../../core/constants/app_colors.dart';
import '../models/batch_ocr_models.dart';
import '../services/brand_intelligence_service.dart';

/// Sortable OCR Review Table with Column Sorting
///
/// Features:
/// - Click headers to sort by any column
/// - Ascending/descending toggle
/// - Visual sort indicators
/// - Multi-column sort support
/// - Smart sorting for different data types
/// - Maintains keyboard navigation features
class SortableOCRTable extends StatefulWidget {
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
  final VoidCallback? onSave;
  final VoidCallback? onSelectAll;

  const SortableOCRTable({
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
    this.onSave,
    this.onSelectAll,
  });

  @override
  State<SortableOCRTable> createState() => _SortableOCRTableState();
}

class _SortableOCRTableState extends State<SortableOCRTable> {
  // Focus management (from keyboard navigation)
  final FocusNode _tableFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  // Cell position
  int _focusedRow = 0;
  int _focusedColumn = 0;

  // Edit mode
  bool _isEditing = false;
  TextEditingController? _editController;
  FocusNode? _editFocusNode;

  // Sorting state
  SortColumn? _sortColumn;
  bool _sortAscending = true;

  // Secondary sort for multi-column sorting
  SortColumn? _secondarySortColumn;
  bool _secondarySortAscending = true;

  // Column definitions
  static const List<SortColumn> sortableColumns = [
    SortColumn.number,
    SortColumn.quality,
    SortColumn.brand,
    SortColumn.size,
    SortColumn.quantity,
    SortColumn.price,
    SortColumn.status,
  ];

  // Search and filter state
  String searchQuery = '';
  Timer? _searchDebouncer;
  bool showOnlyIssues = false;

  // Data quality scores cache
  final Map<String, DataQualityScore> _qualityScores = {};
  final Map<String, AutoFixResult> _autoFixes = {};

  // Sorted items cache
  List<DeduplicatedItem> _sortedItems = [];

  @override
  void initState() {
    super.initState();
    _calculateQualityScores();
    _updateSortedItems();
    _tableFocusNode.requestFocus();
  }

  @override
  void dispose() {
    _tableFocusNode.dispose();
    _scrollController.dispose();
    _editController?.dispose();
    _editFocusNode?.dispose();
    _searchDebouncer?.cancel();
    super.dispose();
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

  void _updateSortedItems() {
    _sortedItems = List.from(widget.items);

    if (_sortColumn != null) {
      _sortedItems.sort((a, b) {
        final comparison = _compareItems(a, b, _sortColumn!);

        // If primary sort values are equal and we have a secondary sort
        if (comparison == 0 && _secondarySortColumn != null) {
          final secondaryComparison = _compareItems(a, b, _secondarySortColumn!);
          return _secondarySortAscending ? secondaryComparison : -secondaryComparison;
        }

        return _sortAscending ? comparison : -comparison;
      });
    }

    // Apply search filter
    if (searchQuery.isNotEmpty) {
      _sortedItems = _sortedItems.where((item) {
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
      _sortedItems = _sortedItems.where((item) {
        final itemId = item.sourceItemIds.isNotEmpty ? item.sourceItemIds.first : '';
        final score = _qualityScores[itemId];
        return score != null && score.score < 0.8;
      }).toList();
    }
  }

  int _compareItems(DeduplicatedItem a, DeduplicatedItem b, SortColumn column) {
    final aId = a.sourceItemIds.isNotEmpty ? a.sourceItemIds.first : '';
    final bId = b.sourceItemIds.isNotEmpty ? b.sourceItemIds.first : '';

    switch (column) {
      case SortColumn.number:
        return (a.rowNumber ?? 0).compareTo(b.rowNumber ?? 0);

      case SortColumn.quality:
        final aScore = _qualityScores[aId]?.score ?? 1.0;
        final bScore = _qualityScores[bId]?.score ?? 1.0;
        return aScore.compareTo(bScore);

      case SortColumn.brand:
        final aBrand = widget.editedBrandNames[aId] ?? a.brandText;
        final bBrand = widget.editedBrandNames[bId] ?? b.brandText;
        return aBrand.toLowerCase().compareTo(bBrand.toLowerCase());

      case SortColumn.size:
        // Try to parse as numbers for intelligent sorting
        final aSize = _parseSizeAsNumber(a.sizeText);
        final bSize = _parseSizeAsNumber(b.sizeText);
        if (aSize != null && bSize != null) {
          return aSize.compareTo(bSize);
        }
        return a.sizeText.compareTo(b.sizeText);

      case SortColumn.quantity:
        final aQty = widget.editedQuantities[aId] ?? a.totalStock;
        final bQty = widget.editedQuantities[bId] ?? b.totalStock;
        return aQty.compareTo(bQty);

      case SortColumn.price:
        final aPrice = widget.editedPrices[aId] ?? a.sellingPrice ?? 0.0;
        final bPrice = widget.editedPrices[bId] ?? b.sellingPrice ?? 0.0;
        return aPrice.compareTo(bPrice);

      case SortColumn.status:
        final aAccepted = widget.acceptanceStates[aId] ?? false;
        final aRejected = widget.rejectionStates[aId] ?? false;
        final bAccepted = widget.acceptanceStates[bId] ?? false;
        final bRejected = widget.rejectionStates[bId] ?? false;

        // Order: Accepted, Pending, Rejected
        final aStatus = aAccepted ? 0 : (aRejected ? 2 : 1);
        final bStatus = bAccepted ? 0 : (bRejected ? 2 : 1);
        return aStatus.compareTo(bStatus);
    }
  }

  double? _parseSizeAsNumber(String size) {
    // Extract numeric value from size string (e.g., "750ml" -> 750)
    final match = RegExp(r'(\d+\.?\d*)').firstMatch(size);
    if (match != null) {
      return double.tryParse(match.group(1)!);
    }
    return null;
  }

  void _onHeaderClick(SortColumn column) {
    setState(() {
      if (_sortColumn == column) {
        // Toggle sort direction if clicking the same column
        _sortAscending = !_sortAscending;
      } else {
        // Set new primary sort column, move old to secondary
        _secondarySortColumn = _sortColumn;
        _secondarySortAscending = _sortAscending;
        _sortColumn = column;
        _sortAscending = true;
      }
      _updateSortedItems();
    });

    // Haptic feedback for column click
    HapticFeedback.lightImpact();
  }

  void _clearSort() {
    setState(() {
      _sortColumn = null;
      _secondarySortColumn = null;
      _sortAscending = true;
      _secondarySortAscending = true;
      _updateSortedItems();
    });
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;

    // Ctrl/Cmd combinations
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      if (event.logicalKey == LogicalKeyboardKey.keyA) {
        // Select All
        widget.onSelectAll?.call();
        return;
      } else if (event.logicalKey == LogicalKeyboardKey.keyS) {
        // Save
        widget.onSave?.call();
        return;
      }
    }

    if (_isEditing) {
      // Handle editing mode keys
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _cancelEdit();
      } else if (event.logicalKey == LogicalKeyboardKey.enter) {
        _commitEdit();
      } else if (event.logicalKey == LogicalKeyboardKey.tab) {
        _commitEdit();
        if (HardwareKeyboard.instance.isShiftPressed) {
          _moveToPreviousCell();
        } else {
          _moveToNextCell();
        }
      }
    } else {
      // Handle navigation mode keys
      switch (event.logicalKey) {
        case LogicalKeyboardKey.arrowUp:
          _moveUp();
          break;
        case LogicalKeyboardKey.arrowDown:
          _moveDown();
          break;
        case LogicalKeyboardKey.arrowLeft:
          _moveLeft();
          break;
        case LogicalKeyboardKey.arrowRight:
          _moveRight();
          break;
        case LogicalKeyboardKey.tab:
          if (HardwareKeyboard.instance.isShiftPressed) {
            _moveToPreviousCell();
          } else {
            _moveToNextCell();
          }
          break;
        case LogicalKeyboardKey.enter:
        case LogicalKeyboardKey.f2:
          _startEdit();
          break;
        case LogicalKeyboardKey.space:
          if (_focusedColumn == 0) {
            _toggleSelection();
          }
          break;
        case LogicalKeyboardKey.home:
          _moveToRowStart();
          break;
        case LogicalKeyboardKey.end:
          _moveToRowEnd();
          break;
        case LogicalKeyboardKey.pageUp:
          _pageUp();
          break;
        case LogicalKeyboardKey.pageDown:
          _pageDown();
          break;
      }
    }
  }

  // Navigation methods (same as KeyboardNavigableTable)
  void _moveUp() {
    setState(() {
      _focusedRow = (_focusedRow - 1).clamp(0, _sortedItems.length - 1);
      _ensureVisible();
    });
  }

  void _moveDown() {
    setState(() {
      _focusedRow = (_focusedRow + 1).clamp(0, _sortedItems.length - 1);
      _ensureVisible();
    });
  }

  void _moveLeft() {
    setState(() {
      _focusedColumn = (_focusedColumn - 1).clamp(0, sortableColumns.length);
    });
  }

  void _moveRight() {
    setState(() {
      _focusedColumn = (_focusedColumn + 1).clamp(0, sortableColumns.length);
    });
  }

  void _moveToNextCell() {
    setState(() {
      _focusedColumn++;
      if (_focusedColumn > sortableColumns.length) {
        _focusedColumn = 0;
        _focusedRow = (_focusedRow + 1).clamp(0, _sortedItems.length - 1);
      }
      _ensureVisible();
    });
  }

  void _moveToPreviousCell() {
    setState(() {
      _focusedColumn--;
      if (_focusedColumn < 0) {
        _focusedColumn = sortableColumns.length;
        _focusedRow = (_focusedRow - 1).clamp(0, _sortedItems.length - 1);
      }
      _ensureVisible();
    });
  }

  void _moveToRowStart() {
    setState(() {
      _focusedColumn = 0;
    });
  }

  void _moveToRowEnd() {
    setState(() {
      _focusedColumn = sortableColumns.length;
    });
  }

  void _pageUp() {
    setState(() {
      _focusedRow = (_focusedRow - 10).clamp(0, _sortedItems.length - 1);
      _ensureVisible();
    });
  }

  void _pageDown() {
    setState(() {
      _focusedRow = (_focusedRow + 10).clamp(0, _sortedItems.length - 1);
      _ensureVisible();
    });
  }

  void _toggleSelection() {
    if (_focusedRow < _sortedItems.length) {
      final item = _sortedItems[_focusedRow];
      final itemId = item.sourceItemIds.isNotEmpty ? item.sourceItemIds.first : '';
      widget.onItemSelected(itemId);
    }
  }

  void _startEdit() {
    // Edit logic for cells 3, 5, 6 (brand, quantity, price)
    if (![3, 5, 6].contains(_focusedColumn)) return;
    if (_focusedRow >= _sortedItems.length) return;

    final item = _sortedItems[_focusedRow];
    final itemId = item.sourceItemIds.isNotEmpty ? item.sourceItemIds.first : '';

    String initialValue = '';

    switch (_focusedColumn) {
      case 3: // Brand
        initialValue = widget.editedBrandNames[itemId] ?? item.brandText;
        break;
      case 5: // Quantity
        initialValue = (widget.editedQuantities[itemId] ?? item.totalStock).toString();
        break;
      case 6: // Price
        initialValue = (widget.editedPrices[itemId] ?? item.sellingPrice ?? 0).toString();
        break;
    }

    setState(() {
      _isEditing = true;
      _editController = TextEditingController(text: initialValue);
      _editFocusNode = FocusNode();

      _editController!.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _editController!.text.length,
      );
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _editFocusNode?.requestFocus();
    });
  }

  void _commitEdit() {
    if (!_isEditing || _editController == null) return;

    final item = _sortedItems[_focusedRow];
    final itemId = item.sourceItemIds.isNotEmpty ? item.sourceItemIds.first : '';
    final value = _editController!.text;

    switch (_focusedColumn) {
      case 3: // Brand
        widget.onBrandNameChanged(itemId, value);
        break;
      case 5: // Quantity
        final qty = int.tryParse(value) ?? 0;
        widget.onQuantityChanged(itemId, qty);
        break;
      case 6: // Price
        final price = double.tryParse(value) ?? 0.0;
        widget.onPriceChanged(itemId, price);
        break;
    }

    _cancelEdit();
    _calculateQualityScores();
  }

  void _cancelEdit() {
    setState(() {
      _isEditing = false;
      _editController?.dispose();
      _editController = null;
      _editFocusNode?.dispose();
      _editFocusNode = null;
    });
    _tableFocusNode.requestFocus();
  }

  void _ensureVisible() {
    const double rowHeight = 80.0;
    final double targetOffset = _focusedRow * rowHeight;
    final double viewportHeight = _scrollController.position.viewportDimension;
    final double currentOffset = _scrollController.offset;

    if (targetOffset < currentOffset) {
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
      );
    } else if (targetOffset + rowHeight > currentOffset + viewportHeight) {
      _scrollController.animateTo(
        targetOffset + rowHeight - viewportHeight,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return KeyboardListener(
      focusNode: _tableFocusNode,
      onKeyEvent: _handleKeyEvent,
      child: Column(
        children: [
          // Keyboard shortcuts help bar
          _buildKeyboardShortcutsBar(),

          // Search and Filter Bar
          _buildSearchAndFilterBar(),

          // Data Quality Summary
          _buildDataQualitySummary(),

          // Sort Info Bar
          if (_sortColumn != null) _buildSortInfoBar(),

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
      ),
    );
  }

  Widget _buildKeyboardShortcutsBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.1),
        border: Border(
          bottom: BorderSide(
            color: AppColors.info.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          _buildShortcut('↑↓←→', 'Navigate'),
          _buildShortcut('Click Header', 'Sort'),
          _buildShortcut('Enter/F2', 'Edit'),
          _buildShortcut('Tab', 'Next'),
          _buildShortcut('Ctrl+A', 'Select All'),
          _buildShortcut('Ctrl+S', 'Save'),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: _isEditing ? AppColors.warning : AppColors.success,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _isEditing ? 'EDIT MODE' : 'NAVIGATE MODE',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShortcut(String keys, String action) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: cs.onSurfaceVariant),
            ),
            child: Text(
              keys,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            action,
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSortInfoBar() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.05),
        border: Border(
          bottom: BorderSide(
            color: cs.primary.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.sort,
            size: 16,
            color: cs.primary,
          ),
          const SizedBox(width: 8),
          Text(
            'Sorted by: ${_sortColumn!.displayName}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: cs.primary,
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
            size: 14,
            color: cs.primary,
          ),
          if (_secondarySortColumn != null) ...[
            const SizedBox(width: 16),
            Text(
              'then by: ${_secondarySortColumn!.displayName}',
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              _secondarySortAscending ? Icons.arrow_upward : Icons.arrow_downward,
              size: 12,
              color: cs.onSurfaceVariant,
            ),
          ],
          const Spacer(),
          TextButton.icon(
            onPressed: _clearSort,
            icon: const Icon(Icons.clear, size: 14),
            label: const Text('Clear Sort'),
            style: TextButton.styleFrom(
              foregroundColor: cs.onSurfaceVariant,
              textStyle: const TextStyle(fontSize: 11),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
          ),
        ],
      ),
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
                      _updateSortedItems();
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
          FilterChip(
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber, size: 14),
                const SizedBox(width: 4),
                const Text('Issues Only'),
              ],
            ),
            selected: showOnlyIssues,
            onSelected: (selected) {
              setState(() {
                showOnlyIssues = selected;
                _updateSortedItems();
              });
            },
            selectedColor: AppColors.warning.withValues(alpha: 0.2),
          ),
          const SizedBox(width: 8),
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
          _buildQualityBadge('Excellent', excellentItems, AppColors.success),
          const SizedBox(width: 8),
          _buildQualityBadge('Good', goodItems, AppColors.warning),
          const SizedBox(width: 8),
          _buildQualityBadge('Poor', poorItems, AppColors.error),
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
            _buildSortableHeaderCell('#', width: 60, icon: Icons.numbers, column: SortColumn.number),
            _buildSortableHeaderCell('Quality', width: 80, icon: Icons.grade, column: SortColumn.quality),
            _buildSortableHeaderCell('Brand Name', width: 200, icon: Icons.local_drink, column: SortColumn.brand),
            _buildSortableHeaderCell('Size', width: 100, icon: Icons.straighten, column: SortColumn.size),
            _buildSortableHeaderCell('Qty', width: 120, icon: Icons.inventory_2, column: SortColumn.quantity),
            _buildSortableHeaderCell('Price', width: 100, icon: Icons.currency_rupee, column: SortColumn.price),
            _buildSortableHeaderCell('Status', width: 100, icon: Icons.info_outline, column: SortColumn.status),
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

  Widget _buildSortableHeaderCell(String title, {
    required double width,
    IconData? icon,
    required SortColumn column,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isSorted = _sortColumn == column;
    final isSecondarySorted = _secondarySortColumn == column;

    return InkWell(
      onTap: () => _onHeaderClick(column),
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: isSorted
              ? cs.primary.withValues(alpha: 0.1)
              : isSecondarySorted
                  ? cs.primary.withValues(alpha: 0.05)
                  : null,
          border: isSorted
              ? Border(
                  left: BorderSide(color: cs.primary, width: 2),
                  right: BorderSide(color: cs.primary, width: 2),
                )
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 16,
                color: isSorted || isSecondarySorted
                    ? cs.primary
                    : cs.primary.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isSorted || isSecondarySorted
                      ? cs.primary
                      : cs.primary.withValues(alpha: 0.9),
                  letterSpacing: 0.3,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isSorted) ...[
              const SizedBox(width: 4),
              Icon(
                _sortAscending ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                size: 20,
                color: cs.primary,
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  '1',
                  style: TextStyle(
                    fontSize: 9,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ] else if (isSecondarySorted) ...[
              const SizedBox(width: 4),
              Icon(
                _secondarySortAscending ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                size: 16,
                color: cs.primary.withValues(alpha: 0.6),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  '2',
                  style: TextStyle(
                    fontSize: 9,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTableBody() {
    final cs = Theme.of(context).colorScheme;
    if (_sortedItems.isEmpty) {
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
      controller: _scrollController,
      itemCount: _sortedItems.length,
      padding: const EdgeInsets.only(bottom: 80),
      itemBuilder: (context, index) {
        final item = _sortedItems[index];
        final itemId = item.sourceItemIds.isNotEmpty ? item.sourceItemIds.first : '';
        final isFocusedRow = !_isEditing && index == _focusedRow;

        return _buildTableRow(item, itemId, index, isFocusedRow);
      },
    );
  }

  Widget _buildTableRow(DeduplicatedItem item, String itemId, int rowIndex, bool isFocusedRow) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = widget.selectedItemIds.contains(itemId);
    final isAccepted = widget.acceptanceStates[itemId] ?? false;
    final isRejected = widget.rejectionStates[itemId] ?? false;

    final brandName = widget.editedBrandNames[itemId] ?? item.brandText;
    final quantity = widget.editedQuantities[itemId] ?? item.totalStock;
    final price = widget.editedPrices[itemId] ?? item.sellingPrice;

    final qualityScore = _qualityScores[itemId];
    final autoFix = _autoFixes[itemId];

    final rowColor = _getRowColor(isSelected, isAccepted, isRejected, item.matchConfidence, isFocusedRow);
    final borderColor = _getBorderColor(isSelected, isAccepted, isRejected, item.matchConfidence, isFocusedRow);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: rowColor,
        border: Border.all(
          color: borderColor,
          width: isFocusedRow ? 2 : (isSelected ? 2 : 1),
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: isFocusedRow
            ? [
                BoxShadow(
                  color: cs.primary.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              _focusedRow = rowIndex;
              _focusedColumn = 0;
            });
            widget.onItemSelected(itemId);
          },
          borderRadius: BorderRadius.circular(8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildCell(0, rowIndex, _buildCheckboxContent(isSelected)),
                _buildCell(1, rowIndex, _buildRowNumberContent(item.rowNumber)),
                _buildCell(2, rowIndex, _buildQualityContent(qualityScore, autoFix != null)),
                _buildCell(3, rowIndex, _buildBrandContent(brandName, itemId), isEditable: true),
                _buildCell(4, rowIndex, _buildSizeContent(item.sizeText)),
                _buildCell(5, rowIndex, _buildQuantityContent(quantity, itemId), isEditable: true),
                _buildCell(6, rowIndex, _buildPriceContent(price, itemId, brandName, item.sizeText), isEditable: true),
                _buildCell(7, rowIndex, _buildStatusContent(isAccepted, isRejected)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Cell content builders (same as KeyboardNavigableTable)
  Widget _buildCell(int column, int row, Widget content, {bool isEditable = false}) {
    final cs = Theme.of(context).colorScheme;
    final isFocused = !_isEditing && _focusedColumn == column && _focusedRow == row;
    final isEditingThisCell = _isEditing && _focusedColumn == column && _focusedRow == row;

    double width;
    switch (column) {
      case 0: width = 50; break;
      case 1: width = 60; break;
      case 2: width = 80; break;
      case 3: width = 200; break;
      case 4: width = 100; break;
      case 5: width = 120; break;
      case 6: width = 100; break;
      case 7: width = 100; break;
      default: width = 100;
    }

    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: isFocused
            ? cs.primary.withValues(alpha: 0.15)
            : isEditingThisCell
                ? AppColors.warning.withValues(alpha: 0.1)
                : null,
        border: isFocused || isEditingThisCell
            ? Border(
                left: BorderSide(
                  color: isEditingThisCell ? AppColors.warning : cs.primary,
                  width: 2,
                ),
                right: BorderSide(
                  color: isEditingThisCell ? AppColors.warning : cs.primary,
                  width: 2,
                ),
              )
            : null,
      ),
      child: isEditingThisCell && _editController != null
          ? TextField(
              controller: _editController,
              focusNode: _editFocusNode,
              onSubmitted: (_) => _commitEdit(),
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                border: OutlineInputBorder(),
              ),
            )
          : content,
    );
  }

  Widget _buildCheckboxContent(bool isSelected) {
    final cs = Theme.of(context).colorScheme;
    return Center(
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
            ? const Icon(Icons.check, size: 16, color: Colors.white)
            : null,
      ),
    );
  }

  Widget _buildRowNumberContent(int? rowNumber) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.1),
          shape: BoxShape.circle,
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
    );
  }

  Widget _buildQualityContent(DataQualityScore? score, bool hasAutoFix) {
    return Center(
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
                child: const Icon(
                  Icons.auto_fix_high,
                  size: 10,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBrandContent(String brandName, String itemId) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          brandName,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildSizeContent(String size) {
    final cs = Theme.of(context).colorScheme;
    final normalizedSize = BrandIntelligenceService.normalizeSize(size);
    return Center(
      child: Text(
        normalizedSize,
        style: TextStyle(
          fontSize: 13,
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildQuantityContent(int quantity, String itemId) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Text(
        quantity.toString(),
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildPriceContent(double? price, String itemId, String brandName, String size) {
    if (price == null) return const Center(child: Text('-'));

    final validation = BrandIntelligenceService.validatePrice(
      brand: brandName,
      size: size,
      price: price,
    );

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: validation.isValid
              ? AppColors.success.withValues(alpha: 0.1)
              : AppColors.warning.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: validation.isValid
                ? AppColors.success.withValues(alpha: 0.3)
                : AppColors.warning.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          '\u20B9${price.toStringAsFixed(0)}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: validation.isValid ? AppColors.success : AppColors.warning,
          ),
        ),
      ),
    );
  }

  Widget _buildStatusContent(bool isAccepted, bool isRejected) {
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
    } else {
      statusText = 'Pending';
      statusColor = AppColors.warning;
      statusIcon = Icons.pending;
    }

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(statusIcon, size: 12, color: statusColor),
            const SizedBox(width: 4),
            Text(
              statusText,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: statusColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getQualityColor(double score) {
    if (score >= 0.9) return AppColors.success;
    if (score >= 0.7) return AppColors.warning;
    return AppColors.error;
  }

  Color _getRowColor(bool isSelected, bool isAccepted, bool isRejected, double confidence, bool isFocused) {
    final cs = Theme.of(context).colorScheme;
    if (isFocused) {
      return cs.primary.withValues(alpha: 0.08);
    }
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

  Color _getBorderColor(bool isSelected, bool isAccepted, bool isRejected, double confidence, bool isFocused) {
    final cs = Theme.of(context).colorScheme;
    if (isFocused) {
      return cs.primary;
    }
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
        price: price ?? 0,
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
        _updateSortedItems();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.auto_fix_high, color: Colors.white),
              const SizedBox(width: 8),
              Text('Auto-fixed $fixedCount items'),
            ],
          ),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }
}

// Enum for sortable columns
enum SortColumn {
  number,
  quality,
  brand,
  size,
  quantity,
  price,
  status,
}

extension SortColumnExtension on SortColumn {
  String get displayName {
    switch (this) {
      case SortColumn.number:
        return 'Row Number';
      case SortColumn.quality:
        return 'Data Quality';
      case SortColumn.brand:
        return 'Brand Name';
      case SortColumn.size:
        return 'Size';
      case SortColumn.quantity:
        return 'Quantity';
      case SortColumn.price:
        return 'Price';
      case SortColumn.status:
        return 'Status';
    }
  }
}
